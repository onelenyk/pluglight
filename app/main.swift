// PlugLight: програма в рядку меню. Поки вона працює й увімкнена, помічник (root LaunchDaemon
// `pluglight daemon --require-app`) показує стан агентів світлодіодом MagSafe. Програма раз на
// секунду оновлює файл-пульс; без нього помічник віддає світлодіод macOS.
import AppKit
import ServiceManagement

let helperLabel = "com.onelenyk.pluglight"
let helperPlist = "/Library/LaunchDaemons/\(helperLabel).plist"
let installedBin = "/usr/local/bin/pluglight"
let stateDir = "/tmp/pluglight"
let heartbeatPath = stateDir + "/.app"
let ledStatePath = "/var/run/pluglight.state"
let claudeSettings = NSHomeDirectory() + "/.claude/settings.json"

/// Рядок інтерфейсу мовою системи. Ключ — англійський текст; переклади в uk.lproj.
func L(_ key: String, _ args: CVarArg...) -> String {
    String(format: NSLocalizedString(key, comment: ""), arguments: args)
}

// Ті самі стани, пріоритет і час життя, що й у pluglight.c.
enum AgentState: Int, Comparable {
    case done = 1, busy, waiting, error
    init?(word: String) {
        switch word {
        case "done": self = .done
        case "busy": self = .busy
        case "waiting", "notification": self = .waiting
        case "error": self = .error
        default: return nil
        }
    }
    var ttl: TimeInterval { [.done: 600, .busy: 1200, .waiting: 3600, .error: 600][self]! }
    var title: String {
        switch self {
        case .done: return L("done")
        case .busy: return L("working")
        case .waiting: return L("waiting for you")
        case .error: return L("error")
        }
    }
    static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }
}

struct Session { let id: String; let state: AgentState }

/// Читає сесії прямо з файлів, без запуску pluglight щосекунди. Прострочені пропускає
/// (прибирає їх помічник), посилання й не-файли ігнорує, як і він.
func readSessions() -> [Session] {
    let fm = FileManager.default
    guard let names = try? fm.contentsOfDirectory(atPath: stateDir) else { return [] }
    let now = Date()
    var out: [Session] = []
    for name in names where !name.hasPrefix(".") {
        let path = stateDir + "/" + name
        guard let attrs = try? fm.attributesOfItem(atPath: path), attrs[.type] as? FileAttributeType == .typeRegular,
              let mtime = attrs[.modificationDate] as? Date,
              let data = fm.contents(atPath: path), data.count < 64,
              let state = AgentState(word: String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)),
              now.timeIntervalSince(mtime) <= state.ttl else { continue }
        out.append(Session(id: name, state: state))
    }
    return out.sorted { $0.state > $1.state }
}

@discardableResult
func run(_ path: String, _ args: [String]) -> (code: Int32, out: String) {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: path)
    p.arguments = args
    let pipe = Pipe()
    p.standardOutput = pipe
    p.standardError = pipe
    do { try p.run() } catch { return (-1, error.localizedDescription) }
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    p.waitUntilExit()
    return (p.terminationStatus, String(decoding: data, as: UTF8.self))
}

func shellQuote(_ s: String) -> String { "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'" }

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    let resources = Bundle.main.resourcePath!
    var bundledBin: String { resources + "/pluglight" }
    var timer: Timer?
    var sessions: [Session] = []
    var helperOK = false
    var hasLED = true
    let updater = Updater()

    var enabled: Bool {
        get { UserDefaults.standard.object(forKey: "enabled") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "enabled") }
    }

    func applicationDidFinishLaunching(_ note: Notification) {
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
        hasLED = run(bundledBin, ["probe"]).code == 0
        helperOK = helperReady()
        tick()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.tick() }
        DispatchQueue.main.async {
            if !self.hasLED { self.explainNoLED(); return }
            if !self.helperOK { self.offerHelperInstall() }
            if self.helperOK { self.migrateLegacyHooks(); self.offerHooksInstall() }
        }
        updater.onChange = { [weak self] in self?.updateIcon() }
        if CommandLine.arguments.contains("--update") {
            // `open -a PlugLight --args --update`: оновитись одразу, без питань.
            Task { @MainActor in
                do { if let rel = try await updater.check(force: true) { try await updater.install(rel) } }
                catch { alert(L("Update failed"), error.localizedDescription) }
            }
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 10) { self.autoCheck() }
            Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { [weak self] _ in self?.autoCheck() }
        }
    }

    func applicationWillTerminate(_ note: Notification) {
        try? FileManager.default.removeItem(atPath: heartbeatPath)
    }

    // MARK: стан

    func tick() {
        if enabled && hasLED { beat() }
        sessions = readSessions()
        updateIcon()
    }

    func beat() {
        let fm = FileManager.default
        if !fm.fileExists(atPath: stateDir) {
            try? fm.createDirectory(atPath: stateDir, withIntermediateDirectories: true)
            chmod(stateDir, 0o1777)
        }
        try? Data("1\n".utf8).write(to: URL(fileURLWithPath: heartbeatPath))
    }

    /// Що зараз показує світлодіод, за словами помічника.
    var ledTitle: String {
        let id = (try? String(contentsOfFile: ledStatePath, encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines)
        switch id {
        case "green": return L("green")
        case "orange": return L("orange")
        case "orange-slow": return L("orange, slow blink")
        case "orange-fast": return L("orange, fast blink")
        default: return L("controlled by macOS")
        }
    }

    func updateIcon() {
        let symbol: String
        var tint: NSColor?
        if !hasLED || !helperOK {
            symbol = "exclamationmark.circle"
        } else if !enabled {
            symbol = "bolt.slash.circle"
        } else {
            switch sessions.first?.state {
            case .error: symbol = "exclamationmark.triangle.fill"; tint = .systemOrange
            case .waiting: symbol = "hand.raised.circle.fill"; tint = .systemOrange
            case .busy: symbol = "bolt.circle.fill"; tint = .systemOrange
            case .done: symbol = "checkmark.circle.fill"; tint = .systemGreen
            case nil: symbol = "bolt.circle"
            }
        }
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: "PlugLight")
        image?.isTemplate = true
        statusItem.button?.image = image
        statusItem.button?.contentTintColor = tint
    }

    func helperReady() -> Bool {
        let fm = FileManager.default
        guard let plist = try? String(contentsOfFile: helperPlist, encoding: .utf8), plist.contains("--require-app"),
              fm.contentsEqual(atPath: bundledBin, andPath: installedBin) else { return false }
        return run("/bin/launchctl", ["print", "system/\(helperLabel)"]).code == 0
    }

    var hooksInstalled: Bool {
        (try? String(contentsOfFile: claudeSettings, encoding: .utf8))?.contains("pluglight hook") ?? false
    }

    // MARK: меню

    func menuNeedsUpdate(_ menu: NSMenu) {
        helperOK = helperReady()
        sessions = readSessions()
        updateIcon()
        menu.removeAllItems()

        if !hasLED {
            menu.addItem(info(L("This Mac has no MagSafe 3 LED")))
        } else if !helperOK {
            menu.addItem(info(L("Helper not installed")))
        } else if !enabled {
            menu.addItem(info(L("Off: macOS controls the LED")))
        } else {
            menu.addItem(info(L("LED: %@", ledTitle)))
            if sessions.isEmpty {
                menu.addItem(info(L("No active sessions")))
            } else {
                for s in sessions.prefix(8) {
                    menu.addItem(info("    \(s.id.prefix(8)) — \(s.state.title)"))
                }
            }
        }
        if updater.busy {
            menu.addItem(info(L("Downloading update…")))
        } else if let rel = updater.available {
            menu.addItem(item(L("Update to %@…", rel.version), #selector(installUpdate)))
        }
        menu.addItem(.separator())

        let toggle = item(L("Enabled"), #selector(toggleEnabled))
        toggle.state = enabled ? .on : .off
        toggle.isEnabled = hasLED
        menu.addItem(toggle)
        let test = item(L("Test LED"), #selector(runTest))
        test.isEnabled = hasLED && helperOK && enabled
        menu.addItem(test)
        menu.addItem(.separator())

        let hooks = item(L("Claude Code hooks"), #selector(toggleHooks))
        hooks.state = hooksInstalled ? .on : .off
        menu.addItem(hooks)

        let helper = NSMenuItem(title: L("Helper"), action: nil, keyEquivalent: "")
        let sub = NSMenu()
        sub.addItem(info(helperOK ? L("Running") : L("Not installed or out of date")))
        let install = item(helperOK ? L("Reinstall…") : L("Install…"), #selector(installHelper))
        install.isEnabled = hasLED
        sub.addItem(install)
        let remove = item(L("Remove…"), #selector(removeHelper))
        remove.isEnabled = FileManager.default.fileExists(atPath: helperPlist)
        sub.addItem(remove)
        helper.submenu = sub
        menu.addItem(helper)

        let updates = NSMenuItem(title: L("Updates"), action: nil, keyEquivalent: "")
        let usub = NSMenu()
        usub.addItem(info(L("Version %@", Updater.current)))
        let check = item(L("Check now"), #selector(checkUpdatesNow))
        check.isEnabled = !updater.busy
        usub.addItem(check)
        let auto = item(L("Check automatically"), #selector(toggleAutoUpdates))
        auto.state = updater.automatic ? .on : .off
        usub.addItem(auto)
        updates.submenu = usub
        menu.addItem(updates)

        let login = item(L("Launch at login"), #selector(toggleLogin))
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)
        menu.addItem(.separator())

        menu.addItem(item(L("About PlugLight"), #selector(showAbout)))
        menu.addItem(item(L("Quit"), #selector(quit), key: "q"))
    }

    func info(_ title: String) -> NSMenuItem {
        let i = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        i.isEnabled = false
        return i
    }

    func item(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let i = NSMenuItem(title: title, action: action, keyEquivalent: key)
        i.target = self
        return i
    }

    // MARK: дії

    @objc func toggleEnabled() {
        enabled.toggle()
        if !enabled { try? FileManager.default.removeItem(atPath: heartbeatPath) }
        tick()
    }

    @objc func runTest() {
        let steps = ["busy", "waiting", "error", "done", "idle"]
        for (i, s) in steps.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 3) {
                run(self.bundledBin, ["set", s, "test"])
                self.tick()
            }
        }
    }

    @objc func toggleHooks() {
        let removing = hooksInstalled
        let r = run("/bin/sh", [resources + "/install-hooks.sh", "claude"] + (removing ? ["remove"] : []))
        if r.code != 0 {
            alert(L("Something went wrong"), r.out.trimmingCharacters(in: .whitespacesAndNewlines))
        } else if removing {
            alert(L("Hooks removed"), L("PlugLight hooks were removed from ~/.claude/settings.json. Restart Claude Code to apply."))
        } else {
            alert(L("Claude Code connected"), L("PlugLight hooks were added to ~/.claude/settings.json. Restart Claude Code to apply."))
        }
    }

    // Один раз пояснює, чому нічого не світиться, і не пропонує ставити помічника.
    func explainNoLED() {
        guard !UserDefaults.standard.bool(forKey: "explainedNoLED") else { return }
        UserDefaults.standard.set(true, forKey: "explainedNoLED")
        alert(L("This Mac has no MagSafe 3 LED"),
              L("PlugLight needs a Mac with a MagSafe 3 port: MacBook Air M2 or later, or MacBook Pro 14″/16″ from 2021 onward. You can remove the app: drag it from Applications to the Trash."))
    }

    func offerHelperInstall() {
        let a = NSAlert()
        if FileManager.default.fileExists(atPath: helperPlist) {
            // Помічник є, але від іншої версії: найчастіше це після оновлення програми.
            a.messageText = L("Update the helper?")
            a.informativeText = L("This version of PlugLight comes with a newer helper. Your password is needed to replace it.")
            a.addButton(withTitle: L("Update"))
        } else {
            a.messageText = L("Install the helper?")
            a.informativeText = L("Only root can write to the SMC to control the MagSafe LED. The helper is a small system service that does this while PlugLight is running. You need your password once.")
            a.addButton(withTitle: L("Install"))
        }
        a.addButton(withTitle: L("Later"))
        NSApp.activate(ignoringOtherApps: true)
        if a.runModal() == .alertFirstButtonReturn { installHelper() }
    }

    // До 0.3.0 проєкт називався MagSafe Light і хуки викликали magsafe-light. Хто їх тоді
    // підключив, уже погодився: тихо замінюємо їх на нові.
    func migrateLegacyHooks() {
        guard let s = try? String(contentsOfFile: claudeSettings, encoding: .utf8),
              s.contains("magsafe-light hook") else { return }
        run("/bin/sh", [resources + "/install-hooks.sh", "claude"])
        UserDefaults.standard.set(true, forKey: "offeredHooks")
    }

    // Один раз пропонує підключити Claude Code, якщо він є на цьому маку.
    func offerHooksInstall() {
        let claudeDir = NSHomeDirectory() + "/.claude"
        guard !hooksInstalled, FileManager.default.fileExists(atPath: claudeDir),
              !UserDefaults.standard.bool(forKey: "offeredHooks") else { return }
        UserDefaults.standard.set(true, forKey: "offeredHooks")
        let a = NSAlert()
        a.messageText = L("Connect Claude Code?")
        a.informativeText = L("PlugLight will add its hooks to ~/.claude/settings.json without touching your other hooks. You can remove them from the menu: “Claude Code hooks”.")
        a.addButton(withTitle: L("Connect"))
        a.addButton(withTitle: L("Not now"))
        NSApp.activate(ignoringOtherApps: true)
        if a.runModal() == .alertFirstButtonReturn { toggleHooks() }
    }

    @objc func installHelper() {
        let cmd = "PLUGLIGHT_SRC=\(shellQuote(bundledBin)) /bin/sh \(shellQuote(resources + "/install.sh")) --require-app"
        if admin(cmd, prompt: L("PlugLight wants to install its helper to control the MagSafe LED.")) {
            helperOK = helperReady()
            tick()
        }
    }

    @objc func removeHelper() {
        if admin("/bin/sh \(shellQuote(resources + "/install.sh")) uninstall", prompt: L("PlugLight wants to remove its helper.")) {
            helperOK = helperReady()
            tick()
        }
    }

    func admin(_ cmd: String, prompt: String) -> Bool {
        let esc = { (s: String) in s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") }
        let source = "do shell script \"\(esc(cmd))\" with administrator privileges with prompt \"\(esc(prompt))\""
        var err: NSDictionary?
        NSAppleScript(source: source)?.executeAndReturnError(&err)
        if let err, (err[NSAppleScript.errorNumber] as? Int) != -128 {
            alert(L("Something went wrong"), err[NSAppleScript.errorMessage] as? String ?? "\(err)")
        }
        return err == nil
    }

    // MARK: оновлення

    func autoCheck() {
        Task { @MainActor in
            guard let rel = try? await updater.check() else { return }
            // Одне вікно на версію; далі тільки пункт у меню.
            guard UserDefaults.standard.string(forKey: "offeredVersion") != rel.version else { return }
            UserDefaults.standard.set(rel.version, forKey: "offeredVersion")
            offerUpdate(rel)
        }
    }

    @objc func checkUpdatesNow() {
        Task { @MainActor in
            do {
                if let rel = try await updater.check(force: true) { offerUpdate(rel) }
                else { alert(L("You’re up to date"), L("PlugLight %@ is the latest version.", Updater.current)) }
            } catch {
                alert(L("Couldn’t check for updates"), error.localizedDescription)
            }
        }
    }

    @objc func toggleAutoUpdates() { updater.automatic.toggle() }

    @objc func installUpdate() { if let rel = updater.available { offerUpdate(rel) } }

    func offerUpdate(_ rel: Release) {
        let a = NSAlert()
        a.messageText = L("PlugLight %@ is available", rel.version)
        let notes = whatsNew(rel.notes)
        a.informativeText = L("You have %@. PlugLight will download the update from GitHub, verify its checksum and restart.", Updater.current)
            + (notes.isEmpty ? "" : "\n\n" + String(notes.prefix(700)) + (notes.count > 700 ? "…" : ""))
        a.addButton(withTitle: L("Update"))
        a.addButton(withTitle: L("Later"))
        NSApp.activate(ignoringOtherApps: true)
        guard a.runModal() == .alertFirstButtonReturn else { return }
        Task { @MainActor in
            do { try await updater.install(rel) }
            catch { alert(L("Update failed"), error.localizedDescription) }
        }
    }

    // Нотатки релізу двомовні; у вікно йде розділ «Що нового» мовою інтерфейсу.
    func whatsNew(_ body: String) -> String {
        let heading = Bundle.main.preferredLocalizations.first == "uk" ? "## Що нового" : "## What's new"
        guard let start = body.range(of: heading) else { return "" }
        var rest = body[start.upperBound...]
        if let end = rest.range(of: "\n## ") { rest = rest[..<end.lowerBound] }
        if let end = rest.range(of: "\n---") { rest = rest[..<end.lowerBound] }
        return rest.replacingOccurrences(of: "**", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    @objc func toggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() }
            else { try SMAppService.mainApp.register() }
        } catch {
            alert(L("Something went wrong"), error.localizedDescription)
        }
    }

    @objc func showAbout() {
        let credits = NSAttributedString(
            string: L("The LED on your MagSafe cable shows what your AI agent is doing.\n\nOrange: working. Slow blink: waiting for you. Fast blink: error. Green: done."),
            attributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.secondaryLabelColor])
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(options: [.credits: credits])
    }

    @objc func quit() { NSApp.terminate(nil) }

    func alert(_ title: String, _ text: String) {
        let a = NSAlert()
        a.messageText = title
        a.informativeText = text
        NSApp.activate(ignoringOtherApps: true)
        a.runModal()
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
