// Оновлення з GitHub Releases. Раз на добу питає api.github.com про останній реліз; якщо він новіший,
// меню пропонує оновитись. Оновлення завантажує той самий PlugLight.zip, що й get.sh, перевіряє sha256,
// і окремий процес після виходу програми замінює бандл та запускає нову версію.
import AppKit
import CryptoKit

let repo = "onelenyk/pluglight"

struct Release { let version: String; let tag: String; let notes: String }

// "0.10.0" > "0.9.1": порівнюємо числа, а не рядки.
func isNewer(_ a: String, than b: String) -> Bool {
    let pa = a.split(separator: ".").map { Int($0) ?? 0 }, pb = b.split(separator: ".").map { Int($0) ?? 0 }
    for i in 0..<max(pa.count, pb.count) {
        let x = i < pa.count ? pa[i] : 0, y = i < pb.count ? pb[i] : 0
        if x != y { return x > y }
    }
    return false
}

enum UpdateError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let m) = self { return m }; return nil }
}

final class Updater {
    static let current = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    var available: Release?
    var busy = false
    var onChange: () -> Void = {}

    var automatic: Bool {
        get { UserDefaults.standard.object(forKey: "checkUpdates") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "checkUpdates") }
    }
    var lastCheck: Date? {
        get { UserDefaults.standard.object(forKey: "lastUpdateCheck") as? Date }
        set { UserDefaults.standard.set(newValue, forKey: "lastUpdateCheck") }
    }

    func request(_ url: String) -> URLRequest {
        var r = URLRequest(url: URL(string: url)!, timeoutInterval: 30)
        r.setValue("PlugLight/\(Updater.current)", forHTTPHeaderField: "User-Agent")
        return r
    }

    func latest() async throws -> Release {
        var r = request("https://api.github.com/repos/\(repo)/releases/latest")
        r.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        let (data, resp) = try await URLSession.shared.data(for: r)
        guard (resp as? HTTPURLResponse)?.statusCode == 200,
              let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = json["tag_name"] as? String else {
            throw UpdateError.message("GitHub не відповів як очікувалось.")
        }
        let version = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
        return Release(version: version, tag: tag, notes: json["body"] as? String ?? "")
    }

    /// Перевіряє оновлення. `force` ігнорує добовий інтервал і вимкнену автоперевірку.
    func check(force: Bool = false) async throws -> Release? {
        if !force {
            guard automatic else { return nil }
            if let last = lastCheck, Date().timeIntervalSince(last) < 23 * 3600 { return available }
        }
        let rel = try await latest()
        lastCheck = Date()
        available = isNewer(rel.version, than: Updater.current) ? rel : nil
        await MainActor.run { onChange() }
        return available
    }

    /// Завантажує й перевіряє реліз, потім виходить; заміну робить окремий процес.
    func install(_ rel: Release) async throws {
        let appPath = Bundle.main.bundlePath
        let parent = (appPath as NSString).deletingLastPathComponent
        guard FileManager.default.isWritableFile(atPath: parent) else {
            throw UpdateError.message("Немає прав на запис у \(parent). Онови командою встановлення з сайту.")
        }
        busy = true
        await MainActor.run { onChange() }
        defer { busy = false; Task { @MainActor in self.onChange() } }

        let base = "https://github.com/\(repo)/releases/download/\(rel.tag)/PlugLight.zip"
        let (zipURL, r1) = try await URLSession.shared.download(for: request(base))
        let (sumData, r2) = try await URLSession.shared.data(for: request(base + ".sha256"))
        guard (r1 as? HTTPURLResponse)?.statusCode == 200, (r2 as? HTTPURLResponse)?.statusCode == 200 else {
            throw UpdateError.message("Не вдалося завантажити реліз \(rel.tag).")
        }
        let want = String(decoding: sumData, as: UTF8.self).split(separator: " ").first.map(String.init) ?? ""
        let got = SHA256.hash(data: try Data(contentsOf: zipURL)).map { String(format: "%02x", $0) }.joined()
        guard !want.isEmpty, want == got else {
            throw UpdateError.message("Контрольна сума не збігається, оновлення скасовано.")
        }

        let work = FileManager.default.temporaryDirectory.appendingPathComponent("pluglight-update-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        let zip = work.appendingPathComponent("PlugLight.zip")
        try FileManager.default.moveItem(at: zipURL, to: zip)
        guard run("/usr/bin/ditto", ["-x", "-k", zip.path, work.path]).code == 0 else {
            throw UpdateError.message("Не вдалося розпакувати реліз.")
        }
        let newApp = work.appendingPathComponent("PlugLight.app")
        guard let info = NSDictionary(contentsOf: newApp.appendingPathComponent("Contents/Info.plist")),
              info["CFBundleIdentifier"] as? String == Bundle.main.bundleIdentifier else {
            throw UpdateError.message("У релізі не та програма, оновлення скасовано.")
        }

        // Чекає, поки ця програма вийде, міняє бандл і запускає нову версію.
        let script = """
        while kill -0 \(getpid()) 2>/dev/null; do sleep 0.2; done
        rm -rf \(shellQuote(appPath))
        ditto \(shellQuote(newApp.path)) \(shellQuote(appPath))
        xattr -dr com.apple.quarantine \(shellQuote(appPath)) 2>/dev/null
        open \(shellQuote(appPath))
        rm -rf \(shellQuote(work.path))
        """
        try spawnDetached(["/bin/sh", "-c", script])
        await MainActor.run { NSApp.terminate(nil) }
    }
}

// Окрема сесія, щоб launchd не прибив процес разом із програмою.
func spawnDetached(_ argv: [String]) throws {
    var attr: posix_spawnattr_t?
    posix_spawnattr_init(&attr)
    defer { posix_spawnattr_destroy(&attr) }
    posix_spawnattr_setflags(&attr, Int16(POSIX_SPAWN_SETSID))
    var actions: posix_spawn_file_actions_t?
    posix_spawn_file_actions_init(&actions)
    defer { posix_spawn_file_actions_destroy(&actions) }
    for fd: Int32 in [0, 1, 2] { posix_spawn_file_actions_addopen(&actions, fd, "/dev/null", O_RDWR, 0) }
    var cargs = argv.map { strdup($0) } + [nil]
    defer { cargs.forEach { free($0) } }
    var pid: pid_t = 0
    let rc = posix_spawn(&pid, argv[0], &actions, &attr, &cargs, environ)
    if rc != 0 { throw UpdateError.message("Не вдалося запустити оновлення (\(rc)).") }
}
