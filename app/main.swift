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

/// Агент, якому вміємо ставити хуки. id — той самий аргумент, що й у install-hooks.sh.
struct AgentRef {
    let id: String
    let title: String
    let file: String
    let dir: String
    let marker: String?   // nil — достатньо існування файлу (плагін OpenCode)
}

let supportedAgents: [AgentRef] = [
    AgentRef(id: "claude", title: "Claude Code", file: claudeSettings,
             dir: NSHomeDirectory() + "/.claude", marker: "pluglight hook"),
    AgentRef(id: "codex", title: "Codex CLI", file: NSHomeDirectory() + "/.codex/hooks.json",
             dir: NSHomeDirectory() + "/.codex", marker: "pluglight hook"),
    AgentRef(id: "qwen", title: "Qwen Code", file: NSHomeDirectory() + "/.qwen/settings.json",
             dir: NSHomeDirectory() + "/.qwen", marker: "pluglight hook"),
    AgentRef(id: "gemini", title: "Gemini CLI", file: NSHomeDirectory() + "/.gemini/settings.json",
             dir: NSHomeDirectory() + "/.gemini", marker: "pluglight hook"),
    AgentRef(id: "cursor", title: "Cursor", file: NSHomeDirectory() + "/.cursor/hooks.json",
             dir: NSHomeDirectory() + "/.cursor", marker: "pluglight hook"),
    AgentRef(id: "antigravity", title: "Antigravity", file: NSHomeDirectory() + "/.gemini/config/hooks.json",
             dir: NSHomeDirectory() + "/.gemini/config", marker: "pluglight hook"),
    AgentRef(id: "copilot", title: "Copilot CLI", file: NSHomeDirectory() + "/.copilot/hooks/pluglight.json",
             dir: NSHomeDirectory() + "/.copilot", marker: "pluglight hook"),
    AgentRef(id: "opencode", title: "OpenCode", file: NSHomeDirectory() + "/.config/opencode/plugins/pluglight.js",
             dir: NSHomeDirectory() + "/.config/opencode", marker: nil),
]

func agentPresent(_ a: AgentRef) -> Bool { FileManager.default.fileExists(atPath: a.dir) }

func agentConnected(_ a: AgentRef) -> Bool {
    guard let marker = a.marker else { return FileManager.default.fileExists(atPath: a.file) }
    return (try? String(contentsOfFile: a.file, encoding: .utf8))?.contains(marker) ?? false
}

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
/// (прибирає їх помічник), посилання й не-файли ігнорує, як і він. Через lstat і read:
/// FileManager.attributesOfItem щоразу тягне ще й розширені атрибути.
func readSessions() -> [Session] {
    guard let names = try? FileManager.default.contentsOfDirectory(atPath: stateDir) else { return [] }
    let now = time(nil)
    var out: [Session] = []
    for name in names where !name.hasPrefix(".") {
        let path = stateDir + "/" + name
        var st = stat()
        guard lstat(path, &st) == 0, st.st_mode & S_IFMT == S_IFREG, st.st_size < 64 else { continue }
        let fd = open(path, O_RDONLY | O_NOFOLLOW)
        guard fd >= 0 else { continue }
        var buf = [UInt8](repeating: 0, count: 64)
        let n = read(fd, &buf, buf.count)
        close(fd)
        guard n > 0, let state = AgentState(word: String(decoding: buf[..<n], as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)),
              TimeInterval(now - st.st_mtimespec.tv_sec) <= state.ttl else { continue }
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
    var shownIcon = ""
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
        // Тік щосекунди; перемальовуємо рядок меню, лише коли іконка справді змінилась.
        let key = symbol + (tint?.description ?? "")
        guard key != shownIcon else { return }
        shownIcon = key
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

        menu.addItem(agentHooksMenu())

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

    /// Підменю «Хуки агентів»: спершу ті агенти, що є на цьому макі (їх можна перемкнути одним кліком),
    /// далі сірим — решта підтримуваних, щоб було видно, з чим іще працює PlugLight.
    func agentHooksMenu() -> NSMenuItem {
        let title = NSMenuItem(title: L("Agent hooks"), action: nil, keyEquivalent: "")
        let sub = NSMenu()
        let present = supportedAgents.filter { agentPresent($0) || agentConnected($0) }
        for agent in present {
            let entry = item(agent.title, #selector(toggleAgent(_:)))
            entry.representedObject = agent.id
            entry.state = agentConnected(agent) ? .on : .off
            sub.addItem(entry)
        }
        if present.isEmpty { sub.addItem(info(L("No agents found on this Mac"))) }
        let missing = supportedAgents.filter { agent in !present.contains { $0.id == agent.id } }
        if !missing.isEmpty {
            if !present.isEmpty { sub.addItem(.separator()) }
            for agent in missing { sub.addItem(info(L("%@ — not installed", agent.title))) }
        }
        title.submenu = sub
        return title
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

    /// Ставить або прибирає хуки одного агента через install-hooks.sh. Повертає текст помилки, якщо не вдалось.
    @discardableResult
    func setHooks(for agent: AgentRef, install: Bool) -> String? {
        let r = run("/bin/sh", [resources + "/install-hooks.sh", agent.id] + (install ? [] : ["remove"]))
        guard r.code == 0 else { return r.out.trimmingCharacters(in: .whitespacesAndNewlines) }
        return nil
    }

    @objc func toggleAgent(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String,
              let agent = supportedAgents.first(where: { $0.id == id }) else { return }
        let removing = agentConnected(agent)
        if let err = setHooks(for: agent, install: !removing) {
            alert(L("Something went wrong"), err)
        } else if removing {
            alert(L("Hooks removed"), L("PlugLight hooks were removed from %@. Restart %@ to apply.", agent.file, agent.title))
        } else {
            alert(L("%@ connected", agent.title), L("PlugLight hooks were added to %@. Restart %@ to apply.", agent.file, agent.title))
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

    // Один раз пропонує підключити агентів, яких знайдено на цьому макі.
    func offerHooksInstall() {
        let pending = supportedAgents.filter { agentPresent($0) && !agentConnected($0) }
        guard !pending.isEmpty, !UserDefaults.standard.bool(forKey: "offeredHooks") else { return }
        UserDefaults.standard.set(true, forKey: "offeredHooks")
        let names = pending.map(\.title).joined(separator: ", ")
        let a = NSAlert()
        a.messageText = pending.count == 1 ? L("Connect %@?", pending[0].title) : L("Connect your agents?")
        a.informativeText = L("PlugLight will add its hooks to %@ without touching your other hooks. You can change this later in the menu: “Agent hooks”.", names)
        a.addButton(withTitle: L("Connect"))
        a.addButton(withTitle: L("Not now"))
        NSApp.activate(ignoringOtherApps: true)
        guard a.runModal() == .alertFirstButtonReturn else { return }
        for agent in pending { setHooks(for: agent, install: true) }
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
