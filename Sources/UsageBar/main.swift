import AppKit
import Foundation

struct UsageWindow {
    let usedPercent: Int
    let resetsAt: Date?
    let durationMinutes: Int?
}

struct ProviderUsage {
    let name: String
    let session: UsageWindow?
    let weekly: UsageWindow?
    let error: String?

    static func unavailable(_ name: String, _ message: String) -> ProviderUsage {
        ProviderUsage(name: name, session: nil, weekly: nil, error: message)
    }
}

enum UsageParser {
    static func codexResponse(from data: Data) -> ProviderUsage? {
        guard
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let id = object["id"] as? NSNumber,
            id.intValue == 2
        else { return nil }

        if let error = object["error"] as? [String: Any] {
            let message = error["message"] as? String ?? "Kullanım bilgisi alınamadı"
            return .unavailable("Codex", message)
        }

        guard
            let result = object["result"] as? [String: Any],
            let limits = result["rateLimits"] as? [String: Any]
        else {
            return .unavailable("Codex", "Codex kullanım sınırı bulunamadı")
        }

        return ProviderUsage(
            name: "Codex",
            session: rateWindow(limits["primary"]),
            weekly: rateWindow(limits["secondary"]),
            error: nil
        )
    }

    static func claudeScreen(_ raw: String) -> ProviderUsage {
        let cleaned = stripTerminalCodes(raw)
        let session = percentage(afterAny: ["Current session", "Current Session"], in: cleaned)
        let weekly = percentage(afterAny: [
            "Current week (all models)",
            "Current week",
            "Current Week"
        ], in: cleaned)

        if session == nil && weekly == nil {
            let message: String
            if cleaned.localizedCaseInsensitiveContains("login") ||
                cleaned.localizedCaseInsensitiveContains("sign in") {
                message = "Claude Code'a giriş yapılmamış"
            } else {
                message = "Claude /usage yüzdesi okunamadı"
            }
            return .unavailable("Claude Code", message)
        }

        return ProviderUsage(
            name: "Claude Code",
            session: session.map { UsageWindow(usedPercent: $0, resetsAt: nil, durationMinutes: 300) },
            weekly: weekly.map { UsageWindow(usedPercent: $0, resetsAt: nil, durationMinutes: 10_080) },
            error: nil
        )
    }

    private static func rateWindow(_ value: Any?) -> UsageWindow? {
        guard let dictionary = value as? [String: Any] else { return nil }
        guard let used = number(dictionary["usedPercent"]) else { return nil }
        let resetSeconds = number(dictionary["resetsAt"])
        let duration = number(dictionary["windowDurationMins"])
        return UsageWindow(
            usedPercent: min(100, max(0, Int(used.rounded()))),
            resetsAt: resetSeconds.map { Date(timeIntervalSince1970: $0) },
            durationMinutes: duration.map { Int($0) }
        )
    }

    private static func number(_ value: Any?) -> Double? {
        if let number = value as? NSNumber { return number.doubleValue }
        if let string = value as? String { return Double(string) }
        return nil
    }

    private static func percentage(afterAny labels: [String], in text: String) -> Int? {
        var values: [Int] = []
        for label in labels {
            let escaped = NSRegularExpression.escapedPattern(for: label)
            let pattern = "(?is)\(escaped).{0,500}?(\\d{1,3}(?:[.,]\\d+)?)\\s*%"
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            for match in regex.matches(in: text, range: range) {
                guard
                    match.numberOfRanges > 1,
                    let valueRange = Range(match.range(at: 1), in: text)
                else { continue }
                let normalized = text[valueRange].replacingOccurrences(of: ",", with: ".")
                if let value = Double(normalized) {
                    values.append(min(100, max(0, Int(value.rounded()))))
                }
            }
        }
        return values.last
    }

    private static func stripTerminalCodes(_ text: String) -> String {
        let ansi = "\\u{001B}(?:\\[[0-?]*[ -/]*[@-~]|\\][^\\u{0007}]*(?:\\u{0007}|\\u{001B}\\\\))"
        let withoutANSI = text.replacingOccurrences(
            of: ansi,
            with: "",
            options: .regularExpression
        )
        return withoutANSI
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "\u{0008}", with: "")
    }
}

enum ExecutableLocator {
    static func codex() -> String? {
        firstExecutable([
            "/Applications/ChatGPT.app/Contents/Resources/codex",
            "/opt/homebrew/bin/codex",
            "/usr/local/bin/codex",
            NSString(string: "~/.local/bin/codex").expandingTildeInPath
        ])
    }

    static func claude() -> String? {
        firstExecutable([
            "/opt/homebrew/bin/claude",
            "/usr/local/bin/claude",
            NSString(string: "~/.claude/bin/claude").expandingTildeInPath,
            NSString(string: "~/.claude/local/claude").expandingTildeInPath,
            NSString(string: "~/.local/bin/claude").expandingTildeInPath
        ])
    }

    private static func firstExecutable(_ candidates: [String]) -> String? {
        candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }
}

final class CodexUsageFetcher {
    func fetch(completion: @escaping (ProviderUsage) -> Void) {
        DispatchQueue.global(qos: .utility).async {
            guard let executable = ExecutableLocator.codex() else {
                completion(.unavailable("Codex", "Codex bulunamadı"))
                return
            }

            let process = Process()
            let input = Pipe()
            let output = Pipe()
            let errors = Pipe()
            process.executableURL = URL(fileURLWithPath: executable)
            // UsageBar only needs the account quota RPC. Disabling unrelated
            // app/plugin features avoids background catalog scans and their
            // associated file/network access.
            process.arguments = [
                "app-server", "--stdio",
                "--disable", "apps",
                "--disable", "plugins",
                "--disable", "remote_plugin",
                "--disable", "plugin_sharing"
            ]
            process.standardInput = input
            process.standardOutput = output
            process.standardError = errors
            process.environment = Self.environment()

            let semaphore = DispatchSemaphore(value: 0)
            let lock = NSLock()
            var pending = Data()
            var result: ProviderUsage?

            output.fileHandleForReading.readabilityHandler = { handle in
                let chunk = handle.availableData
                guard !chunk.isEmpty else { return }
                lock.lock()
                pending.append(chunk)
                while let newline = pending.firstIndex(of: 0x0A) {
                    let line = pending.prefix(upTo: newline)
                    pending.removeSubrange(...newline)
                    if let parsed = UsageParser.codexResponse(from: Data(line)) {
                        result = parsed
                        semaphore.signal()
                    }
                }
                lock.unlock()
            }

            do {
                try process.run()
                let messages = [
                    "{\"method\":\"initialize\",\"id\":1,\"params\":{\"clientInfo\":{\"name\":\"usage_bar\",\"title\":\"UsageBar\",\"version\":\"1.0.0\"}}}",
                    "{\"method\":\"initialized\"}",
                    "{\"method\":\"account/rateLimits/read\",\"id\":2}"
                ].joined(separator: "\n") + "\n"
                input.fileHandleForWriting.write(Data(messages.utf8))

                let waitResult = semaphore.wait(timeout: .now() + 15)
                output.fileHandleForReading.readabilityHandler = nil
                if process.isRunning { process.terminate() }

                lock.lock()
                let final = result
                lock.unlock()

                if let final {
                    completion(final)
                } else if waitResult == .timedOut {
                    completion(.unavailable("Codex", "Codex yanıtı zaman aşımına uğradı"))
                } else {
                    completion(.unavailable("Codex", "Codex kullanım yanıtı boş"))
                }
            } catch {
                output.fileHandleForReading.readabilityHandler = nil
                completion(.unavailable("Codex", "Codex başlatılamadı: \(error.localizedDescription)"))
            }
        }
    }

    private static func environment() -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = [
            "/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin", "/usr/sbin", "/sbin"
        ].joined(separator: ":")
        environment["TERM"] = "xterm-256color"
        return environment
    }
}

final class ClaudeUsageFetcher {
    func fetch(completion: @escaping (ProviderUsage) -> Void) {
        DispatchQueue.global(qos: .utility).async {
            guard let executable = ExecutableLocator.claude() else {
                completion(.unavailable("Claude Code", "Claude Code bulunamadı"))
                return
            }

            guard Self.isLoggedIn(executable) else {
                completion(.unavailable("Claude Code", "Claude Code'a giriş yapılmamış"))
                return
            }

            let process = Process()
            let input = Pipe()
            let output = Pipe()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/script")
            process.arguments = ["-q", "/dev/null", executable, "--allowed-tools", ""]
            process.standardInput = input
            process.standardOutput = output
            process.standardError = output
            process.environment = CodexUsageFetcherEnvironment.value

            let lock = NSLock()
            var captured = Data()
            output.fileHandleForReading.readabilityHandler = { handle in
                let chunk = handle.availableData
                guard !chunk.isEmpty else { return }
                lock.lock()
                captured.append(chunk)
                lock.unlock()
            }

            do {
                try process.run()
                Thread.sleep(forTimeInterval: 1.5)
                input.fileHandleForWriting.write(Data("/usage\r".utf8))
                Thread.sleep(forTimeInterval: 5.0)
                input.fileHandleForWriting.write(Data("/exit\r".utf8))
                Thread.sleep(forTimeInterval: 1.0)
                output.fileHandleForReading.readabilityHandler = nil
                if process.isRunning { process.terminate() }

                lock.lock()
                let data = captured
                lock.unlock()
                let screen = String(decoding: data, as: UTF8.self)
                completion(UsageParser.claudeScreen(screen))
            } catch {
                output.fileHandleForReading.readabilityHandler = nil
                completion(.unavailable("Claude Code", "Claude Code başlatılamadı: \(error.localizedDescription)"))
            }
        }
    }

    private static func isLoggedIn(_ executable: String) -> Bool {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = ["auth", "status"]
        process.standardOutput = output
        process.standardError = Pipe()
        process.environment = CodexUsageFetcherEnvironment.value
        do {
            try process.run()
            process.waitUntilExit()
            let data = output.fileHandleForReading.readDataToEndOfFile()
            guard
                let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                let loggedIn = object["loggedIn"] as? Bool
            else { return false }
            return loggedIn
        } catch {
            return false
        }
    }
}

private enum CodexUsageFetcherEnvironment {
    static let value: [String: String] = {
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = [
            "/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin", "/usr/sbin", "/sbin"
        ].joined(separator: ":")
        environment["TERM"] = "xterm-256color"
        return environment
    }()
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private enum PreferenceKey {
        static let codexEnabled = "provider.codex.enabled"
        static let claudeEnabled = "provider.claude.enabled"
    }

    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let menu = NSMenu()
    private let codexFetcher = CodexUsageFetcher()
    private let claudeFetcher = ClaudeUsageFetcher()
    private var usages: [String: ProviderUsage] = [:]
    private var lastUpdated: Date?
    private var isRefreshing = false
    private var refreshTimer: Timer?

    private var codexEnabled: Bool {
        get {
            if UserDefaults.standard.object(forKey: PreferenceKey.codexEnabled) == nil { return true }
            return UserDefaults.standard.bool(forKey: PreferenceKey.codexEnabled)
        }
        set { UserDefaults.standard.set(newValue, forKey: PreferenceKey.codexEnabled) }
    }

    private var claudeEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: PreferenceKey.claudeEnabled) }
        set { UserDefaults.standard.set(newValue, forKey: PreferenceKey.claudeEnabled) }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        menu.delegate = self
        statusItem.menu = menu
        statusItem.button?.title = "%—"
        statusItem.button?.toolTip = "Codex ve Claude Code kullanımı"
        rebuildMenu()
        refresh()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }

    func menuWillOpen(_ menu: NSMenu) {
        if let lastUpdated, Date().timeIntervalSince(lastUpdated) > 60 {
            refresh()
        }
    }

    @objc private func refresh() {
        guard !isRefreshing else { return }
        isRefreshing = true
        rebuildMenu()

        let group = DispatchGroup()
        if codexEnabled {
            group.enter()
            codexFetcher.fetch { [weak self] usage in
                DispatchQueue.main.async {
                    self?.usages[usage.name] = usage
                    group.leave()
                }
            }
        } else {
            usages.removeValue(forKey: "Codex")
        }

        if claudeEnabled {
            group.enter()
            claudeFetcher.fetch { [weak self] usage in
                DispatchQueue.main.async {
                    self?.usages[usage.name] = usage
                    group.leave()
                }
            }
        } else {
            usages.removeValue(forKey: "Claude Code")
        }

        group.notify(queue: .main) { [weak self] in
            guard let self else { return }
            self.isRefreshing = false
            self.lastUpdated = Date()
            self.updateStatusTitle()
            self.rebuildMenu()
        }
    }

    private func updateStatusTitle() {
        let percentages = usages.values.compactMap { $0.session?.usedPercent }
        if let highest = percentages.max() {
            statusItem.button?.title = "%\(highest)"
            statusItem.button?.toolTip = "En yüksek 5 saatlik kullanım: %\(highest)"
        } else {
            statusItem.button?.title = "%—"
            statusItem.button?.toolTip = "Kullanım bilgisi bekleniyor"
        }
    }

    private func rebuildMenu() {
        menu.removeAllItems()
        let codexFallback = codexEnabled
            ? (isRefreshing ? "Yenileniyor…" : "Henüz veri yok")
            : "Takip kapalı"
        addProvider(usages["Codex"] ?? .unavailable("Codex", codexFallback))
        menu.addItem(.separator())
        let claudeFallback = claudeEnabled
            ? (isRefreshing ? "Yenileniyor…" : "Henüz veri yok")
            : "Takip kapalı · etkinleştirince anahtar zinciri kullanılabilir"
        addProvider(usages["Claude Code"] ?? .unavailable("Claude Code", claudeFallback))
        menu.addItem(.separator())

        let codexToggle = NSMenuItem(title: "Codex takibi", action: #selector(toggleCodex), keyEquivalent: "")
        codexToggle.target = self
        codexToggle.state = codexEnabled ? .on : .off
        menu.addItem(codexToggle)

        let claudeToggle = NSMenuItem(title: "Claude Code takibi", action: #selector(toggleClaude), keyEquivalent: "")
        claudeToggle.target = self
        claudeToggle.state = claudeEnabled ? .on : .off
        menu.addItem(claudeToggle)
        menu.addItem(.separator())

        if let lastUpdated {
            let item = NSMenuItem(title: "Son güncelleme: \(Self.timeFormatter.string(from: lastUpdated))", action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
        }

        let refreshItem = NSMenuItem(title: isRefreshing ? "Yenileniyor…" : "Şimdi yenile", action: #selector(refresh), keyEquivalent: "r")
        refreshItem.target = self
        refreshItem.isEnabled = !isRefreshing
        menu.addItem(refreshItem)

        menu.addItem(.separator())
        let quitItem = NSMenuItem(title: "UsageBar'dan çık", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
    }

    private func addProvider(_ usage: ProviderUsage) {
        let header = NSMenuItem(title: usage.name, action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)

        if let session = usage.session {
            menu.addItem(disabledItem(windowTitle("5 saat", session)))
        }
        if let weekly = usage.weekly {
            menu.addItem(disabledItem(windowTitle("Haftalık", weekly)))
        }
        if let error = usage.error {
            menu.addItem(disabledItem("  \(error)"))
        }
    }

    private func windowTitle(_ label: String, _ window: UsageWindow) -> String {
        var text = "  \(label): %\(window.usedPercent) kullanıldı"
        if let resetsAt = window.resetsAt {
            text += " · \(Self.relativeReset(resetsAt))"
        }
        return text
    }

    private func disabledItem(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    @objc private func toggleCodex() {
        codexEnabled.toggle()
        if !codexEnabled { usages.removeValue(forKey: "Codex") }
        updateStatusTitle()
        rebuildMenu()
        if codexEnabled { refresh() }
    }

    @objc private func toggleClaude() {
        if claudeEnabled {
            claudeEnabled = false
            usages.removeValue(forKey: "Claude Code")
            updateStatusTitle()
            rebuildMenu()
            return
        }

        let alert = NSAlert()
        alert.messageText = "Claude Code takibi etkinleştirilsin mi?"
        alert.informativeText = "UsageBar yalnızca Claude Code'un mevcut giriş durumunu ve /usage ekranını okuyacak. macOS, Claude Code kimliği için Anahtar Zinciri izni sorabilir. Disk, ekran, erişilebilirlik veya otomasyon izni gerekmez."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Etkinleştir")
        alert.addButton(withTitle: "Vazgeç")
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        claudeEnabled = true
        rebuildMenu()
        refresh()
    }

    private static func relativeReset(_ date: Date) -> String {
        let interval = max(0, Int(date.timeIntervalSinceNow))
        let days = interval / 86_400
        let hours = (interval % 86_400) / 3_600
        let minutes = (interval % 3_600) / 60
        if days > 0 { return "\(days)g \(hours)sa sonra sıfırlanır" }
        if hours > 0 { return "\(hours)sa \(minutes)dk sonra sıfırlanır" }
        return "\(minutes)dk sonra sıfırlanır"
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "tr_TR")
        formatter.dateFormat = "HH:mm"
        return formatter
    }()
}

private func runSelfTest() -> Int32 {
    let codex = """
    {"id":2,"result":{"rateLimits":{"primary":{"usedPercent":35,"windowDurationMins":300,"resetsAt":1784740000},"secondary":{"usedPercent":12.4,"windowDurationMins":10080,"resetsAt":1785000000}}}}
    """
    guard
        let parsedCodex = UsageParser.codexResponse(from: Data(codex.utf8)),
        parsedCodex.session?.usedPercent == 35,
        parsedCodex.weekly?.usedPercent == 12
    else {
        fputs("Codex parser testi başarısız\n", stderr)
        return 1
    }

    let claude = "Current session     41% used\nCurrent week (all models)     18% used"
    let parsedClaude = UsageParser.claudeScreen(claude)
    guard parsedClaude.session?.usedPercent == 41, parsedClaude.weekly?.usedPercent == 18 else {
        fputs("Claude parser testi başarısız\n", stderr)
        return 1
    }

    print("UsageBar öz testi başarılı")
    return 0
}

private func runProbe() -> Int32 {
    let group = DispatchGroup()
    let lock = NSLock()
    var results: [ProviderUsage] = []

    group.enter()
    CodexUsageFetcher().fetch { usage in
        lock.lock()
        results.append(usage)
        lock.unlock()
        group.leave()
    }

    group.enter()
    ClaudeUsageFetcher().fetch { usage in
        lock.lock()
        results.append(usage)
        lock.unlock()
        group.leave()
    }

    guard group.wait(timeout: .now() + 20) == .success else {
        fputs("Probe zaman aşımına uğradı\n", stderr)
        return 1
    }

    for usage in results.sorted(by: { $0.name < $1.name }) {
        let session = usage.session.map { "%\($0.usedPercent)" } ?? "—"
        let weekly = usage.weekly.map { "%\($0.usedPercent)" } ?? "—"
        if let error = usage.error {
            print("\(usage.name): \(error)")
        } else {
            print("\(usage.name): 5 saat \(session), haftalık \(weekly)")
        }
    }
    return results.contains(where: { $0.session != nil }) ? 0 : 1
}

if CommandLine.arguments.contains("--self-test") {
    exit(runSelfTest())
}

if CommandLine.arguments.contains("--probe") {
    exit(runProbe())
}

let application = NSApplication.shared
let delegate = AppDelegate()
application.delegate = delegate
application.run()
