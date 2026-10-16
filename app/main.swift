// MagSafe Light: програма в рядку меню. Поки вона працює й увімкнена, помічник (root LaunchDaemon
// `magsafe-light daemon --require-app`) показує стан агентів світлодіодом MagSafe. Програма раз на
// секунду оновлює файл-пульс; без нього помічник віддає світлодіод macOS.
import AppKit
import ServiceManagement

let helperLabel = "com.onelenyk.magsafe-light"
let helperPlist = "/Library/LaunchDaemons/\(helperLabel).plist"
let installedBin = "/usr/local/bin/magsafe-light"
let stateDir = "/tmp/magsafe-light"
let heartbeatPath = stateDir + "/.app"
let claudeSettings = NSHomeDirectory() + "/.claude/settings.json"

struct Session { let id: String; let state: String }

let stateTitles = ["busy": "працює", "waiting": "чекає на тебе", "error": "помилка", "done": "готово"]

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
    var bundledBin: String { resources + "/magsafe-light" }
    var timer: Timer?
    var led = "керує macOS"
    var sessions: [Session] = []
    var helperOK = false

    var enabled: Bool {
        get { UserDefaults.standard.object(forKey: "enabled") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "enabled") }
    }

    func applicationDidFinishLaunching(_ note: Notification) {
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
        helperOK = helperReady()
        tick()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.tick() }
        DispatchQueue.main.async {
            if !self.helperOK { self.offerHelperInstall() }
            if self.helperOK { self.offerHooksInstall() }
        }
    }

    func applicationWillTerminate(_ note: Notification) {
        try? FileManager.default.removeItem(atPath: heartbeatPath)
    }

    // MARK: стан

    func tick() {
        if enabled { beat() }
        readStatus()
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

    func readStatus() {
        let out = run(bundledBin, ["status"]).out
        var found: [Session] = []
        for line in out.split(separator: "\n") {
            if line.hasPrefix("Світлодіод: ") {
                led = String(line.dropFirst("Світлодіод: ".count))
            } else if line.hasPrefix("  "), !line.contains("прострочено") {
                let parts = line.split(separator: " ", omittingEmptySubsequences: true)
                if parts.count >= 2 { found.append(Session(id: String(parts[0]), state: String(parts[1]))) }
            }
        }
        sessions = found
    }

    func updateIcon() {
        let symbol: String
        var tint: NSColor?
        if !helperOK {
            symbol = "exclamationmark.circle"
        } else if !enabled {
            symbol = "bolt.slash.circle"
        } else {
            let states = Set(sessions.map(\.state))
            if states.contains("error") { symbol = "exclamationmark.triangle.fill"; tint = .systemOrange }
            else if states.contains("waiting") { symbol = "hand.raised.circle.fill"; tint = .systemOrange }
            else if states.contains("busy") { symbol = "bolt.circle.fill"; tint = .systemOrange }
            else if states.contains("done") { symbol = "checkmark.circle.fill"; tint = .systemGreen }
            else { symbol = "bolt.circle" }
        }
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: "MagSafe Light")
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
        (try? String(contentsOfFile: claudeSettings, encoding: .utf8))?.contains("magsafe-light hook") ?? false
    }

    // MARK: меню

    func menuNeedsUpdate(_ menu: NSMenu) {
        helperOK = helperReady()
        readStatus()
        updateIcon()
        menu.removeAllItems()

        if !helperOK {
            menu.addItem(info("Помічник не встановлено"))
        } else if !enabled {
            menu.addItem(info("Вимкнено: світлодіодом керує macOS"))
        } else {
            menu.addItem(info("Світлодіод: \(led)"))
            if sessions.isEmpty {
                menu.addItem(info("Немає активних сесій"))
            } else {
                for s in sessions.prefix(8) {
                    menu.addItem(info("    \(s.id.prefix(8)) — \(stateTitles[s.state] ?? s.state)"))
                }
            }
        }
        menu.addItem(.separator())

        let toggle = item("Увімкнено", #selector(toggleEnabled))
        toggle.state = enabled ? .on : .off
        menu.addItem(toggle)
        let test = item("Тест світлодіода", #selector(runTest))
        test.isEnabled = helperOK && enabled
        menu.addItem(test)
        menu.addItem(.separator())

        let hooks = item("Хуки Claude Code", #selector(toggleHooks))
        hooks.state = hooksInstalled ? .on : .off
        menu.addItem(hooks)

        let helper = NSMenuItem(title: "Помічник", action: nil, keyEquivalent: "")
        let sub = NSMenu()
        sub.addItem(info(helperOK ? "Працює" : "Не встановлено або застарів"))
        sub.addItem(item(helperOK ? "Перевстановити…" : "Встановити…", #selector(installHelper)))
        let remove = item("Видалити…", #selector(removeHelper))
        remove.isEnabled = FileManager.default.fileExists(atPath: helperPlist)
        sub.addItem(remove)
        helper.submenu = sub
        menu.addItem(helper)

        let login = item("Запускати при вході", #selector(toggleLogin))
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)
        menu.addItem(.separator())

        menu.addItem(item("Про MagSafe Light", #selector(showAbout)))
        menu.addItem(item("Вийти", #selector(quit), key: "q"))
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
        let args = [resources + "/install-hooks.sh", "claude"] + (hooksInstalled ? ["remove"] : [])
        let r = run("/bin/sh", args)
        alert(r.code == 0 ? "Готово" : "Не вдалося",
              r.out.trimmingCharacters(in: .whitespacesAndNewlines) + (r.code == 0 ? "\n\nПерезапусти Claude Code, щоб зміни підхопились." : ""))
    }

    func offerHelperInstall() {
        let a = NSAlert()
        a.messageText = "Встановити помічника?"
        a.informativeText = "Писати в SMC, щоб керувати світлодіодом MagSafe, може лише root. Помічник — маленька системна служба, яка робить це, поки працює MagSafe Light. Пароль потрібен один раз."
        a.addButton(withTitle: "Встановити")
        a.addButton(withTitle: "Пізніше")
        NSApp.activate(ignoringOtherApps: true)
        if a.runModal() == .alertFirstButtonReturn { installHelper() }
    }

    // Один раз пропонує підключити Claude Code, якщо він є на цьому маку.
    func offerHooksInstall() {
        let claudeDir = NSHomeDirectory() + "/.claude"
        guard !hooksInstalled, FileManager.default.fileExists(atPath: claudeDir),
              !UserDefaults.standard.bool(forKey: "offeredHooks") else { return }
        UserDefaults.standard.set(true, forKey: "offeredHooks")
        let a = NSAlert()
        a.messageText = "Підключити Claude Code?"
        a.informativeText = "MagSafe Light додасть свої хуки в ~/.claude/settings.json, не чіпаючи інших. Прибрати їх можна в меню: «Хуки Claude Code»."
        a.addButton(withTitle: "Підключити")
        a.addButton(withTitle: "Не зараз")
        NSApp.activate(ignoringOtherApps: true)
        if a.runModal() == .alertFirstButtonReturn { toggleHooks() }
    }

    @objc func installHelper() {
        let cmd = "MAGSAFE_LIGHT_SRC=\(shellQuote(bundledBin)) /bin/sh \(shellQuote(resources + "/install.sh")) --require-app"
        if admin(cmd, prompt: "MagSafe Light хоче встановити помічника для керування світлодіодом MagSafe.") {
            helperOK = helperReady()
            tick()
        }
    }

    @objc func removeHelper() {
        if admin("/bin/sh \(shellQuote(resources + "/install.sh")) uninstall", prompt: "MagSafe Light хоче видалити свого помічника.") {
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
            alert("Не вдалося", err[NSAppleScript.errorMessage] as? String ?? "\(err)")
        }
        return err == nil
    }

    @objc func toggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() }
            else { try SMAppService.mainApp.register() }
        } catch {
            alert("Не вдалося", error.localizedDescription)
        }
    }

    @objc func showAbout() {
        let credits = NSAttributedString(
            string: "Світлодіод на кабелі MagSafe показує, що робить AI-агент.\n\nПомаранчевий — працює, блимає — чекає на тебе, швидко блимає — помилка, зелений — готово.",
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
