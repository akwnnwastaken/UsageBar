import AppKit
import Darwin
import Foundation
import ServiceManagement
import UsageBarCore
import UsageBarProcessLauncher

enum AppMetadata {
    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "development"
    }

    static var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "development"
    }
}

struct Localizer {
    let language: AppLanguage

    private func pick(_ turkish: String, _ english: String) -> String {
        language == .turkish ? turkish : english
    }

    var usageTooltip: String { pick("Codex ve Claude Code kullanımı", "Codex and Claude Code usage") }
    var connectFirst: String { pick("Önce bir sağlayıcı bağlayın", "Connect a provider first") }
    var refreshing: String { pick("Yenileniyor…", "Refreshing…") }
    var noData: String { pick("Henüz veri yok", "No data yet") }
    var connectCodex: String { pick("Codex'e bağlan", "Connect Codex") }
    var connectClaude: String { pick("Claude Code'a bağlan", "Connect Claude Code") }
    var disconnectCodex: String { pick("Codex bağlantısını kaldır", "Disconnect Codex") }
    var disconnectClaude: String { pick("Claude Code bağlantısını kaldır", "Disconnect Claude Code") }
    var refreshNow: String { pick("Şimdi yenile", "Refresh now") }
    var quit: String { pick("UsageBar'dan çık", "Quit UsageBar") }
    var showInMenuBar: String { pick("Üst çubukta göster", "Show in menu bar") }
    var languageTitle: String { pick("Dil", "Language") }
    var usageColorsTitle: String { pick("Kullanım renkleri", "Usage colors") }
    var usageColorsEnabled: String { pick("Renkleri kullan", "Use colors") }
    var menuBarAppearance: String { pick("Üst çubuk görünümü", "Menu bar appearance") }
    var showResetInMenuBar: String { pick("Sıfırlanma süresini göster", "Show reset countdown") }
    var automatic: String { pick("Otomatik", "Auto") }
    var usageHistoryTitle: String { pick("Kullanım geçmişi", "Usage history") }
    var showUsageHistory: String { pick("24 saatlik mini grafiği göster", "Show 24-hour mini chart") }
    var clearUsageHistory: String { pick("Geçmişi temizle", "Clear history") }
    var copyDiagnostics: String { pick("Tanılama özetini kopyala", "Copy diagnostics") }
    var launchAtLogin: String { pick("Mac açılışında başlat", "Launch at login") }
    var loginItemFailed: String { pick("Başlangıç ayarı değiştirilemedi", "Could not change login item") }
    var loginItemNeedsApproval: String { pick("onay gerekli", "approval required") }
    var fiveHours: String { pick("5 saat", "5 hours") }
    var weekly: String { pick("Haftalık", "Weekly") }

    func usageWindowLabel(_ window: UsageWindow, position: Int) -> String {
        switch window.kind {
        case .fiveHour:
            return fiveHours
        case .weekly:
            return weekly
        case .duration(let minutes):
            let days = minutes / (24 * 60)
            let hours = (minutes % (24 * 60)) / 60
            let remainingMinutes = minutes % 60
            var parts: [String] = []
            if days > 0 { parts.append(pick("\(days) gün", "\(days) days")) }
            if hours > 0 { parts.append(pick("\(hours) saat", "\(hours) hours")) }
            if remainingMinutes > 0 { parts.append(pick("\(remainingMinutes) dk", "\(remainingMinutes) min")) }
            return parts.isEmpty ? pick("Kullanım penceresi", "Usage window") : parts.joined(separator: " ")
        case .unknown:
            return pick("Kullanım penceresi \(position + 1)", "Usage window \(position + 1)")
        }
    }

    func usageHistoryRange(_ duration: TimeInterval) -> String {
        if duration < 60 {
            return pick("İlk kayıt", "First sample")
        }

        let totalMinutes = Int(duration) / 60
        if totalMinutes < 60 {
            return pick("Son \(totalMinutes) dk", "Last \(totalMinutes)m")
        }

        let totalHours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if totalHours < 24 {
            let suffix = minutes > 0 ? pick(" \(minutes) dk", " \(minutes)m") : ""
            return pick("Son \(totalHours) sa", "Last \(totalHours)h") + suffix
        }

        let days = totalHours / 24
        let hours = totalHours % 24
        let suffix = hours > 0 ? pick(" \(hours) sa", " \(hours)h") : ""
        return pick("Son \(days) gün", "Last \(days)d") + suffix
    }

    func usageHistorySummary(_ model: UsageHistoryChartModel) -> String {
        guard let first = model.samples.first, let last = model.samples.last else { return noData }
        let firstPercent = language == .turkish
            ? "%\(first.remainingPercent)"
            : "\(first.remainingPercent)%"
        guard let delta = model.delta else {
            return pick("Başlangıç: \(firstPercent)", "Start: \(firstPercent)")
        }

        let lastPercent = language == .turkish
            ? "%\(last.remainingPercent)"
            : "\(last.remainingPercent)%"
        let signedDelta = delta > 0 ? "+\(delta)" : "\(delta)"
        var result = pick(
            "\(firstPercent) → \(lastPercent) · değişim \(signedDelta)",
            "\(firstPercent) → \(lastPercent) · change \(signedDelta)"
        )
        if !model.resetIndices.isEmpty {
            result += pick(
                " · \(model.resetIndices.count) sıfırlama",
                " · \(model.resetIndices.count) reset"
            )
        }
        return result
    }
    var codexNotFoundTitle: String { pick("Codex bulunamadı", "Codex not found") }
    var codexNotFoundMessage: String {
        pick(
            "Önce ChatGPT veya Codex komut satırı uygulamasını kurup hesabınıza giriş yapın.",
            "Install ChatGPT or the Codex CLI and sign in first."
        )
    }
    var codexUntrustedTitle: String { pick("Codex güvenli değil", "Codex is not trusted") }
    var codexUntrustedMessage: String {
        pick(
            "Codex çalıştırılabilir dosyasının sahibi, izinleri veya gerçek yolu güvenli bulunmadı. Codex'i resmi kaynaktan yeniden kurun.",
            "The Codex executable has an unsafe owner, permissions, or resolved path. Reinstall Codex from an official source."
        )
    }
    var claudeNotFoundTitle: String { pick("Claude Code bulunamadı", "Claude Code not found") }
    var claudeNotFoundMessage: String {
        pick("Önce Claude Code'u kurup hesabınıza giriş yapın.", "Install Claude Code and sign in first.")
    }
    var claudeUntrustedTitle: String { pick("Claude Code güvenli değil", "Claude Code is not trusted") }
    var claudeUntrustedMessage: String {
        pick(
            "Claude Code çalıştırılabilir dosyasının sahibi, izinleri veya gerçek yolu güvenli bulunmadı. Claude Code'u resmi kaynaktan yeniden kurun.",
            "The Claude Code executable has an unsafe owner, permissions, or resolved path. Reinstall Claude Code from an official source."
        )
    }
    var connectClaudeTitle: String { pick("Claude Code'a bağlanılsın mı?", "Connect Claude Code?") }
    var connectClaudeMessage: String {
        pick(
            "UsageBar yalnızca Claude Code'un mevcut giriş durumunu ve yapılandırılmış kullanım sınırlarını izole bir oturumda okuyacak. macOS, Claude Code kimliği için Anahtar Zinciri izni sorabilir. Bu pencerede bir kez 'Her Zaman İzin Ver' seçilebilir. Disk, ağ diski, ekran, erişilebilirlik veya otomasyon izni gerekmez.",
            "UsageBar will read only Claude Code's current sign-in status and structured usage limits in an isolated session. macOS may request Keychain access for the Claude Code credential; you can choose 'Always Allow' once. Disk, network volume, screen recording, accessibility, and automation access are not required."
        )
    }
    var connect: String { pick("Bağlan", "Connect") }
    var cancel: String { pick("Vazgeç", "Cancel") }
    var ok: String { pick("Tamam", "OK") }
    var now: String { pick("şimdi", "now") }

    func remaining(_ percent: Int) -> String {
        pick("%\(percent) kaldı", "\(percent)% remaining")
    }

    func remainingTooltip(provider: String, percent: Int) -> String {
        pick("\(provider): %\(percent) kaldı", "\(provider): \(percent)% remaining")
    }

    func waitingForUsage(provider: String) -> String {
        pick("\(provider) kullanım bilgisi bekleniyor", "Waiting for \(provider) usage")
    }

    func alertPresetTitle(_ preset: UsageAlertPreset) -> String {
        let name: String
        switch preset {
        case .late: name = pick("Geç", "Late")
        case .balanced: name = pick("Dengeli", "Balanced")
        case .early: name = pick("Erken", "Early")
        }
        return pick(
            "\(name) — turuncu %\(preset.warningThreshold), kırmızı %\(preset.criticalThreshold)",
            "\(name) — orange \(preset.warningThreshold)%, red \(preset.criticalThreshold)%"
        )
    }

    var refreshIntervalTitle: String {
        pick("Yenileme aralığı", "Refresh interval")
    }

    func refreshIntervalOption(_ interval: UsageRefreshInterval) -> String {
        let minutes = interval.minutes
        return pick(
            "\(minutes) dakika",
            minutes == 1 ? "1 minute" : "\(minutes) minutes"
        )
    }

    func resetIn(_ duration: String) -> String {
        pick("Sıfırlama: \(duration)", "Resets in \(duration)")
    }

    func lastUpdated(_ time: String) -> String {
        pick("Son güncelleme: \(time)", "Last updated: \(time)")
    }

    func staleData(lastSuccessfulTime: String, issue: ProviderIssue) -> String {
        pick(
            "Son iyi veri: \(lastSuccessfulTime)\n\(self.issue(issue))",
            "Last good data: \(lastSuccessfulTime)\n\(self.issue(issue))"
        )
    }

    func staleTooltip(provider: String, percent: Int) -> String {
        pick(
            "\(provider): %\(percent) kaldı (eski veri)",
            "\(provider): \(percent)% remaining (stale)"
        )
    }

    func relativeReset(_ date: Date, now: Date = Date()) -> String {
        let interval = max(0, Int(date.timeIntervalSince(now)))
        let days = interval / 86_400
        let hours = (interval % 86_400) / 3_600
        let minutes = (interval % 3_600) / 60
        if language == .turkish {
            if days > 0 { return "\(days)g \(hours)sa" }
            if hours > 0 { return "\(hours)sa \(minutes)dk" }
            if minutes > 0 { return "\(minutes)dk" }
            return self.now
        }

        if days > 0 { return "\(days)d \(hours)h" }
        if hours > 0 { return "\(hours)h \(minutes)m" }
        if minutes > 0 { return "\(minutes)m" }
        return self.now
    }

    func issue(_ issue: ProviderIssue) -> String {
        switch issue {
        case .refreshing: return refreshing
        case .noData: return noData
        case .codexUsageUnavailable:
            return pick("Codex kullanım bilgisi alınamadı", "Could not retrieve Codex usage")
        case .codexLimitMissing:
            return pick("Codex kullanım sınırı bulunamadı", "Codex usage limit not found")
        case .codexNotFound:
            return codexNotFoundTitle
        case .codexUntrustedExecutable:
            return codexUntrustedTitle
        case .codexTimedOut:
            return pick("Codex yanıtı zaman aşımına uğradı", "Codex response timed out")
        case .codexEmptyResponse:
            return pick("Codex kullanım yanıtı boş", "Codex returned an empty usage response")
        case .codexIncompatible:
            return pick("Codex sürümü güvenli kullanım sorgusuyla uyumlu değil", "This Codex version is incompatible with the safe usage query")
        case .codexCommandFailed:
            return pick("Codex kullanım komutu başarısız oldu", "The Codex usage command failed")
        case .codexLaunchFailed(let reason):
            return pick("Codex başlatılamadı: \(reason)", "Could not start Codex: \(reason)")
        case .claudeNotFound:
            return claudeNotFoundTitle
        case .claudeUntrustedExecutable:
            return claudeUntrustedTitle
        case .claudeNotLoggedIn:
            return pick("Claude Code'a giriş yapılmamış", "Claude Code is not signed in")
        case .claudeUsageUnreadable:
            return pick("Claude kullanım yüzdesi okunamadı", "Could not read Claude usage")
        case .claudeUsageTimedOut:
            return pick("Claude kullanım sorgusu zaman aşımına uğradı", "Claude usage query timed out")
        case .claudeLaunchFailed(let reason):
            return pick("Claude Code başlatılamadı: \(reason)", "Could not start Claude Code: \(reason)")
        case .outputTooLarge(let provider):
            return pick("\(provider) çok fazla çıktı üretti", "\(provider) produced too much output")
        }
    }
}

enum ExecutableLookup {
    case found(String)
    case untrusted
    case missing

    var path: String? {
        guard case .found(let path) = self else { return nil }
        return path
    }
}

enum ExecutableLocator {
    private struct Candidate {
        let path: String
        let allowedRoot: String
    }

    static func codex() -> ExecutableLookup {
        firstTrusted([
            Candidate(
                path: "/Applications/ChatGPT.app/Contents/Resources/codex",
                allowedRoot: "/Applications/ChatGPT.app"
            ),
            Candidate(path: "/opt/homebrew/bin/codex", allowedRoot: "/opt/homebrew"),
            Candidate(path: "/usr/local/bin/codex", allowedRoot: "/usr/local"),
            Candidate(
                path: NSString(string: "~/.local/bin/codex").expandingTildeInPath,
                allowedRoot: NSString(string: "~/.local").expandingTildeInPath
            )
        ])
    }

    static func claude() -> ExecutableLookup {
        firstTrusted([
            Candidate(path: "/opt/homebrew/bin/claude", allowedRoot: "/opt/homebrew"),
            Candidate(path: "/usr/local/bin/claude", allowedRoot: "/usr/local"),
            Candidate(
                path: NSString(string: "~/.claude/bin/claude").expandingTildeInPath,
                allowedRoot: NSString(string: "~/.claude").expandingTildeInPath
            ),
            Candidate(
                path: NSString(string: "~/.claude/local/claude").expandingTildeInPath,
                allowedRoot: NSString(string: "~/.claude").expandingTildeInPath
            ),
            Candidate(
                path: NSString(string: "~/.local/bin/claude").expandingTildeInPath,
                allowedRoot: NSString(string: "~/.local").expandingTildeInPath
            )
        ])
    }

    private static func firstTrusted(_ candidates: [Candidate]) -> ExecutableLookup {
        var rejectedCandidate = false
        for candidate in candidates where FileManager.default.fileExists(atPath: candidate.path) {
            if let trustedPath = trustedExecutable(
                at: candidate.path,
                allowedRoot: candidate.allowedRoot
            ) {
                return .found(trustedPath)
            }
            rejectedCandidate = true
        }
        return rejectedCandidate ? .untrusted : .missing
    }

    static func trustedExecutable(at path: String, allowedRoot: String) -> String? {
        let fileManager = FileManager.default
        let resolvedPath = URL(fileURLWithPath: path)
            .standardizedFileURL
            .resolvingSymlinksInPath()
            .path
        let resolvedRoot = URL(fileURLWithPath: allowedRoot)
            .standardizedFileURL
            .resolvingSymlinksInPath()
            .path
        guard resolvedPath == resolvedRoot || resolvedPath.hasPrefix(resolvedRoot + "/") else {
            return nil
        }
        guard fileManager.isExecutableFile(atPath: resolvedPath) else { return nil }
        guard
            let attributes = try? fileManager.attributesOfItem(atPath: resolvedPath),
            attributes[.type] as? FileAttributeType == .typeRegular,
            let owner = attributes[.ownerAccountID] as? NSNumber,
            owner.int32Value == 0 || owner.int32Value == getuid(),
            let permissions = attributes[.posixPermissions] as? NSNumber,
            permissions.intValue & 0o022 == 0
        else { return nil }

        var directory = URL(fileURLWithPath: resolvedPath).deletingLastPathComponent()
        let rootURL = URL(fileURLWithPath: resolvedRoot)
        while directory.path.hasPrefix(resolvedRoot) {
            guard
                let directoryAttributes = try? fileManager.attributesOfItem(atPath: directory.path),
                let directoryPermissions = directoryAttributes[.posixPermissions] as? NSNumber,
                directoryPermissions.intValue & 0o002 == 0
            else { return nil }
            if directory.path == rootURL.path { break }
            let parent = directory.deletingLastPathComponent()
            guard parent.path != directory.path else { return nil }
            directory = parent
        }
        return resolvedPath
    }
}

/// Keeps provider CLIs away from the folder that UsageBar was launched from.
/// In particular, Claude Code normally discovers project files, hooks, MCP
/// servers and integrations from its current directory. That discovery can
/// make macOS attribute unrelated Desktop/Documents/network-volume access to
/// UsageBar. Quota checks only need the user's local login, so they run from a
/// private temporary directory with a deliberately small environment.
private enum ProviderProcessContext {
    static let workingDirectory: URL = {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("local.codex.usagebar", isDirectory: true)
        do {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
            return directory
        } catch {
            return FileManager.default.temporaryDirectory
        }
    }()

    static let environment: [String: String] = {
        let inherited = ProcessInfo.processInfo.environment
        var value: [String: String] = [
            "HOME": NSHomeDirectory(),
            "PATH": [
                "/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin",
                "/usr/sbin", "/sbin"
            ].joined(separator: ":"),
            "TERM": "xterm-256color",
            "TMPDIR": FileManager.default.temporaryDirectory.path
        ]
        for key in ["USER", "LOGNAME", "LANG", "LC_ALL", "LC_CTYPE"] {
            if let inheritedValue = inherited[key] {
                value[key] = inheritedValue
            }
        }
        return value
    }()

    static func apply(to process: Process) {
        process.currentDirectoryURL = workingDirectory
        process.environment = environment
    }
}

private enum ProviderProcessLauncher {
    static func configure(
        _ process: Process,
        executable: String,
        arguments: [String]
    ) {
        let launcher = Bundle.main.executableURL?.path
            ?? ProcessInfo.processInfo.arguments[0]
        process.executableURL = URL(fileURLWithPath: launcher)
        process.arguments = ["--process-group-launcher", executable] + arguments
    }
}

private enum ProviderProcessLimits {
    static let maxOutputBytes = 2 * 1_024 * 1_024
    private static let terminationGrace: TimeInterval = 1

    static func stop(_ process: Process) {
        let processIdentifier = process.processIdentifier
        guard processIdentifier > 0 else { return }
        stop(processIdentifier: processIdentifier)
        if process.isRunning {
            Darwin.kill(processIdentifier, SIGKILL)
        }
        // Reap the child so a later `terminationStatus` read is safe. Without
        // this, reading `terminationStatus` before Foundation observes the exit
        // traps (SIGABRT, exit 134). The process group was already signalled, so
        // this returns promptly. Runs on a background queue, never the UI thread.
        process.waitUntilExit()
    }

    static func stop(processIdentifier: pid_t) {
        guard processIdentifier > 0 else { return }
        Darwin.kill(-processIdentifier, SIGTERM)
        let deadline = Date().addingTimeInterval(terminationGrace)
        while processGroupExists(processIdentifier), Date() < deadline {
            Thread.sleep(forTimeInterval: 0.02)
        }
        if processGroupExists(processIdentifier) {
            Darwin.kill(-processIdentifier, SIGKILL)
        }
    }

    private static func processGroupExists(_ processIdentifier: pid_t) -> Bool {
        if Darwin.kill(-processIdentifier, 0) == 0 { return true }
        return errno != ESRCH
    }
}

private final class BoundedDataCapture {
    private let limit: Int
    private let lock = NSLock()
    private var data = Data()
    private var exceeded = false

    init(limit: Int) {
        self.limit = max(0, limit)
    }

    @discardableResult
    func append(_ chunk: Data) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !chunk.isEmpty else { return !exceeded }

        let remaining = max(0, limit - data.count)
        if chunk.count > remaining {
            data.append(chunk.prefix(remaining))
            exceeded = true
        } else {
            data.append(chunk)
        }
        return !exceeded
    }

    func snapshot() -> (data: Data, exceeded: Bool) {
        lock.lock()
        defer { lock.unlock() }
        return (data, exceeded)
    }
}

private enum PipeDrainer {
    static func start(
        _ pipe: Pipe,
        capture: BoundedDataCapture,
        dataAvailable: DispatchSemaphore? = nil
    ) -> DispatchGroup {
        start(
            pipe.fileHandleForReading,
            capture: capture,
            dataAvailable: dataAvailable
        )
    }

    static func start(
        _ fileHandle: FileHandle,
        capture: BoundedDataCapture,
        dataAvailable: DispatchSemaphore? = nil
    ) -> DispatchGroup {
        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global(qos: .utility).async {
            defer { group.leave() }
            while true {
                do {
                    guard
                        let chunk = try fileHandle.read(upToCount: 16 * 1_024),
                        !chunk.isEmpty
                    else { return }
                    capture.append(chunk)
                    dataAvailable?.signal()
                } catch {
                    return
                }
            }
        }
        return group
    }
}

final class CodexUsageFetcher {
    private static let responseTimeout: TimeInterval = 15

    func fetch(completion: @escaping (ProviderUsage) -> Void) {
        DispatchQueue.global(qos: .utility).async {
            let executable: String
            switch ExecutableLocator.codex() {
            case .found(let path):
                executable = path
            case .untrusted:
                completion(.unavailable("Codex", .codexUntrustedExecutable))
                return
            case .missing:
                completion(.unavailable("Codex", .codexNotFound))
                return
            }

            let process = Process()
            let input = Pipe()
            let output = Pipe()
            let errors = Pipe()
            // UsageBar only needs the account quota RPC. Disabling unrelated
            // app/plugin features avoids background catalog scans and their
            // associated file/network access.
            ProviderProcessLauncher.configure(process, executable: executable, arguments: [
                "app-server", "--stdio",
                "--disable", "apps",
                "--disable", "plugins",
                "--disable", "remote_plugin",
                "--disable", "plugin_sharing"
            ])
            process.standardInput = input
            process.standardOutput = output
            process.standardError = errors
            ProviderProcessContext.apply(to: process)

            do {
                try process.run()
                let captured = BoundedDataCapture(limit: ProviderProcessLimits.maxOutputBytes)
                let errorCapture = BoundedDataCapture(limit: 64 * 1_024)
                let dataAvailable = DispatchSemaphore(value: 0)
                let outputDrainer = PipeDrainer.start(
                    output,
                    capture: captured,
                    dataAvailable: dataAvailable
                )
                let errorDrainer = PipeDrainer.start(errors, capture: errorCapture)
                let messages = [
                    "{\"method\":\"initialize\",\"id\":1,\"params\":{\"clientInfo\":{\"name\":\"usage_bar\",\"title\":\"UsageBar\",\"version\":\"\(AppMetadata.version)\"}}}",
                    "{\"method\":\"initialized\"}",
                    "{\"method\":\"account/rateLimits/read\",\"id\":2}"
                ].joined(separator: "\n") + "\n"
                try? input.fileHandleForWriting.write(contentsOf: Data(messages.utf8))

                let deadline = Date().addingTimeInterval(Self.responseTimeout)
                var parsedUsage: ProviderUsage?
                var didTimeout = false
                while true {
                    if Date() >= deadline { didTimeout = true; break }
                    let snapshot = captured.snapshot()
                    if snapshot.exceeded { break }
                    parsedUsage = Self.response(from: snapshot.data)
                    if parsedUsage != nil || !process.isRunning { break }
                    _ = dataAvailable.wait(timeout: .now() + .milliseconds(100))
                }

                input.fileHandleForWriting.closeFile()
                // stop() reaps the process, so `terminationStatus` below is safe.
                ProviderProcessLimits.stop(process)
                _ = outputDrainer.wait(timeout: .now() + .seconds(1))
                _ = errorDrainer.wait(timeout: .now() + .seconds(1))

                let finalSnapshot = captured.snapshot()
                let final = parsedUsage ?? Self.response(from: finalSnapshot.data)
                let outcome = CodexFetchOutcome.classify(
                    hasUsage: final != nil,
                    outputExceeded: finalSnapshot.exceeded || errorCapture.snapshot().exceeded,
                    incompatible: Self.isIncompatible(errorCapture.snapshot().data),
                    didTimeout: didTimeout,
                    terminationStatus: process.terminationStatus
                )
                switch outcome {
                case .usage:
                    completion(final ?? .unavailable("Codex", .codexEmptyResponse))
                case .outputTooLarge:
                    completion(.unavailable("Codex", .outputTooLarge("Codex")))
                case .incompatible:
                    completion(.unavailable("Codex", .codexIncompatible))
                case .timedOut:
                    completion(.unavailable("Codex", .codexTimedOut))
                case .commandFailed:
                    completion(.unavailable("Codex", .codexCommandFailed))
                case .emptyResponse:
                    completion(.unavailable("Codex", .codexEmptyResponse))
                }
            } catch {
                ProviderProcessLimits.stop(process)
                completion(.unavailable("Codex", .codexLaunchFailed(error.localizedDescription)))
            }
        }
    }

    private static func response(from data: Data) -> ProviderUsage? {
        for line in data.split(separator: 0x0A) {
            if let usage = UsageParser.codexResponse(from: Data(line)) { return usage }
        }
        return nil
    }

    private static func isIncompatible(_ errorData: Data) -> Bool {
        let message = String(decoding: errorData, as: UTF8.self).lowercased()
        let mentionsDisabledFlag = message.contains("--disable")
        let signalsUnknownOption = message.contains("unexpected argument")
            || message.contains("unknown option")
            || message.contains("unrecognized option")
        return mentionsDisabledFlag && signalsUnknownOption
    }

}

final class ClaudeUsageFetcher {
    private static let usageTimeout: TimeInterval = 15

    func fetch(completion: @escaping (ProviderUsage) -> Void) {
        DispatchQueue.global(qos: .utility).async {
            let executable: String
            switch ExecutableLocator.claude() {
            case .found(let path):
                executable = path
            case .untrusted:
                completion(.unavailable("Claude Code", .claudeUntrustedExecutable))
                return
            case .missing:
                completion(.unavailable("Claude Code", .claudeNotFound))
                return
            }

            let process = Process()
            let output = Pipe()
            let errors = Pipe()
            // Read usage non-interactively with `-p /usage`. Print mode prints
            // the usage summary as plain text and exits; with
            // --no-session-persistence it registers no session (so it leaves no
            // Claude "Recents" entry) and writes no transcript. `/usage` is a
            // local slash command, so it does not consume model quota. The
            // isolation flags keep project settings, hooks, Chrome, MCP and
            // tools out of the quota check while leaving local auth available.
            ProviderProcessLauncher.configure(process, executable: executable, arguments: [
                "-p", "/usage",
                "--no-session-persistence",
                "--setting-sources", "",
                "--no-chrome",
                "--strict-mcp-config",
                "--tools", ""
            ])
            process.standardInput = FileHandle.nullDevice
            process.standardOutput = output
            process.standardError = errors
            ProviderProcessContext.apply(to: process)

            do {
                try process.run()
                let captured = BoundedDataCapture(limit: ProviderProcessLimits.maxOutputBytes)
                let errorCapture = BoundedDataCapture(limit: 64 * 1_024)
                let dataAvailable = DispatchSemaphore(value: 0)
                let outputDrainer = PipeDrainer.start(
                    output,
                    capture: captured,
                    dataAvailable: dataAvailable
                )
                let errorDrainer = PipeDrainer.start(errors, capture: errorCapture)

                // Print mode emits its whole output then exits, so wait for the
                // process to finish (bounded by the deadline) and parse the
                // complete text once. This avoids accepting a partially-written
                // line that would drop the weekly window.
                let deadline = Date().addingTimeInterval(Self.usageTimeout)
                while process.isRunning && Date() < deadline {
                    if captured.snapshot().exceeded { break }
                    _ = dataAvailable.wait(timeout: .now() + .milliseconds(100))
                }

                ProviderProcessLimits.stop(process)
                _ = outputDrainer.wait(timeout: .now() + .seconds(1))
                _ = errorDrainer.wait(timeout: .now() + .seconds(1))

                let snapshot = captured.snapshot()
                guard !snapshot.exceeded else {
                    completion(.unavailable("Claude Code", .outputTooLarge("Claude Code")))
                    return
                }
                let finalText = String(decoding: snapshot.data, as: UTF8.self)
                let final = UsageParser.claudePrintUsage(finalText)
                if final.error == nil {
                    completion(final)
                } else if case .claudeNotLoggedIn? = final.error {
                    completion(.unavailable("Claude Code", .claudeNotLoggedIn))
                } else if Date() >= deadline {
                    completion(.unavailable("Claude Code", .claudeUsageTimedOut))
                } else {
                    completion(.unavailable("Claude Code", .claudeUsageUnreadable))
                }
            } catch {
                ProviderProcessLimits.stop(process)
                completion(.unavailable("Claude Code", .claudeLaunchFailed(error.localizedDescription)))
            }
        }
    }

}

final class UsageSparklineView: NSView {
    private let model: UsageHistoryChartModel
    private let lineColor: NSColor

    init(frame frameRect: NSRect, samples: [UsageHistorySample], lineColor: NSColor) {
        model = UsageHistoryChartModel(samples: samples)
        self.lineColor = lineColor
        super.init(frame: frameRect)
        setAccessibilityElement(true)
        setAccessibilityRole(.image)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let chartRect = bounds.insetBy(dx: 1, dy: 2)
        NSColor.secondaryLabelColor.withAlphaComponent(0.08).setFill()
        NSBezierPath(roundedRect: chartRect, xRadius: 4, yRadius: 4).fill()
        guard let first = model.displaySamples.first, let last = model.displaySamples.last else { return }

        let duration = max(1, last.recordedAt.timeIntervalSince(first.recordedAt))
        let point: (Int, UsageHistorySample) -> NSPoint = { index, sample in
            let elapsed = sample.recordedAt.timeIntervalSince(first.recordedAt)
            let x = self.model.displaySamples.count == 1
                ? chartRect.midX
                : chartRect.minX + CGFloat(elapsed / duration) * chartRect.width
            let y = chartRect.minY + self.model.normalizedY(for: sample.remainingPercent) * chartRect.height
            return NSPoint(x: x, y: y)
        }

        NSColor.secondaryLabelColor.withAlphaComponent(0.12).setStroke()
        let guide = NSBezierPath()
        guide.move(to: NSPoint(x: chartRect.minX, y: chartRect.midY))
        guide.line(to: NSPoint(x: chartRect.maxX, y: chartRect.midY))
        guide.lineWidth = 0.5
        guide.stroke()

        for index in model.resetIndices {
            let resetPoint = point(index, model.samples[index])
            let marker = NSBezierPath()
            marker.move(to: NSPoint(x: resetPoint.x, y: chartRect.minY))
            marker.line(to: NSPoint(x: resetPoint.x, y: chartRect.maxY))
            lineColor.withAlphaComponent(0.35).setStroke()
            marker.lineWidth = 1
            marker.stroke()
            lineColor.setStroke()
            let ring = NSRect(x: resetPoint.x - 2.5, y: resetPoint.y - 2.5, width: 5, height: 5)
            NSBezierPath(ovalIn: ring).stroke()
        }

        let path = NSBezierPath()
        for (index, sample) in model.displaySamples.enumerated() {
            let samplePoint = point(index, sample)
            if index == 0 { path.move(to: samplePoint) } else { path.line(to: samplePoint) }
        }
        lineColor.setStroke()
        path.lineWidth = 1.75
        path.lineJoinStyle = .round
        path.lineCapStyle = .round
        path.stroke()

        let latestPoint = point(model.displaySamples.count - 1, last)
        let dotRect = NSRect(x: latestPoint.x - 2, y: latestPoint.y - 2, width: 4, height: 4)
        lineColor.setFill()
        NSBezierPath(ovalIn: dotRect).fill()
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private enum PreferenceKey {
        static let codexConnected = "provider.codex.connected"
        static let claudeConnected = "provider.claude.connected"
        static let selectedProvider = "status.selected.provider"
        static let language = "app.language"
        static let usageColorsEnabled = "status.usage.colors.enabled"
        static let usageAlertPreset = "status.usage.alert.preset"
        static let showResetInMenuBar = "status.reset.countdown.visible"
        static let autoRotateProviders = "status.providers.auto.rotate"
        static let refreshInterval = "status.refresh.interval"
        static let usageHistoryEnabled = "usage.history.enabled"
        static let usageHistoryData = "usage.history.samples.v2"
        static let legacyUsageHistoryData = "usage.history.samples.v1"
        static let legacyCodexEnabled = "provider.codex.enabled"
        static let legacyClaudeEnabled = "provider.claude.enabled"
    }

    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let menu: NSMenu = {
        let menu = NSMenu()
        menu.autoenablesItems = false
        return menu
    }()
    private let codexFetcher = CodexUsageFetcher()
    private let claudeFetcher = ClaudeUsageFetcher()
    private var usages: [String: ProviderUsage] = [:]
    private var lastUpdated: Date?
    private var isRefreshing = false
    private var refreshTimer: Timer?
    private var statusPresentationTimer: Timer?
    private var rotatingProviderIndex = 0
    private var usageHistory: [String: [UsageHistorySample]] = [:]
    private var displayedRemaining: [String: Int] = [:]
    private var pendingRemainingRise: [String: Int] = [:]
    private var pendingRemainingRiseCount: [String: Int] = [:]

    private var language: AppLanguage {
        get {
            guard let raw = UserDefaults.standard.string(forKey: PreferenceKey.language) else {
                return AppLanguage.preferred(from: Locale.preferredLanguages)
            }
            return AppLanguage(rawValue: raw)
                ?? AppLanguage.preferred(from: Locale.preferredLanguages)
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: PreferenceKey.language) }
    }

    private var text: Localizer { Localizer(language: language) }

    private var usageColorsEnabled: Bool {
        get {
            if UserDefaults.standard.object(forKey: PreferenceKey.usageColorsEnabled) == nil {
                return true
            }
            return UserDefaults.standard.bool(forKey: PreferenceKey.usageColorsEnabled)
        }
        set { UserDefaults.standard.set(newValue, forKey: PreferenceKey.usageColorsEnabled) }
    }

    private var usageAlertPreset: UsageAlertPreset {
        get {
            guard let raw = UserDefaults.standard.string(forKey: PreferenceKey.usageAlertPreset) else {
                return .balanced
            }
            return UsageAlertPreset(rawValue: raw) ?? .balanced
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: PreferenceKey.usageAlertPreset) }
    }

    private var refreshInterval: UsageRefreshInterval {
        get {
            UsageRefreshInterval.resolved(
                from: UserDefaults.standard.string(forKey: PreferenceKey.refreshInterval)
            )
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: PreferenceKey.refreshInterval) }
    }

    private var usageAlertPolicy: UsageAlertPolicy {
        UsageAlertPolicy(isEnabled: usageColorsEnabled, preset: usageAlertPreset)
    }

    private var showResetInMenuBar: Bool {
        get { UserDefaults.standard.bool(forKey: PreferenceKey.showResetInMenuBar) }
        set { UserDefaults.standard.set(newValue, forKey: PreferenceKey.showResetInMenuBar) }
    }

    private var autoRotateProviders: Bool {
        get { UserDefaults.standard.bool(forKey: PreferenceKey.autoRotateProviders) }
        set { UserDefaults.standard.set(newValue, forKey: PreferenceKey.autoRotateProviders) }
    }

    private var usageHistoryEnabled: Bool {
        get {
            if UserDefaults.standard.object(forKey: PreferenceKey.usageHistoryEnabled) == nil {
                return true
            }
            return UserDefaults.standard.bool(forKey: PreferenceKey.usageHistoryEnabled)
        }
        set { UserDefaults.standard.set(newValue, forKey: PreferenceKey.usageHistoryEnabled) }
    }

    private var codexConnected: Bool {
        get { UserDefaults.standard.bool(forKey: PreferenceKey.codexConnected) }
        set { UserDefaults.standard.set(newValue, forKey: PreferenceKey.codexConnected) }
    }

    private var claudeConnected: Bool {
        get { UserDefaults.standard.bool(forKey: PreferenceKey.claudeConnected) }
        set { UserDefaults.standard.set(newValue, forKey: PreferenceKey.claudeConnected) }
    }

    private var connectedProviderNames: [String] {
        var names: [String] = []
        if codexConnected { names.append("Codex") }
        if claudeConnected { names.append("Claude Code") }
        return names
    }

    private var selectedProviderName: String? {
        get {
            let saved = UserDefaults.standard.string(forKey: PreferenceKey.selectedProvider)
            if let saved, connectedProviderNames.contains(saved) { return saved }
            return connectedProviderNames.first
        }
        set {
            if let newValue {
                UserDefaults.standard.set(newValue, forKey: PreferenceKey.selectedProvider)
            } else {
                UserDefaults.standard.removeObject(forKey: PreferenceKey.selectedProvider)
            }
        }
    }

    private var statusProviderName: String? {
        let providers = connectedProviderNames
        guard !providers.isEmpty else { return nil }
        if autoRotateProviders && providers.count > 1 {
            return providers[rotatingProviderIndex % providers.count]
        }
        return selectedProviderName
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        migrateLegacyPreferences()
        let defaults = UserDefaults.standard
        let storedHistory = defaults.data(forKey: PreferenceKey.usageHistoryData)
            ?? defaults.data(forKey: PreferenceKey.legacyUsageHistoryData)
        usageHistory = UsageHistoryModel.sanitized(
            UsageHistoryModel.decode(storedHistory),
            now: Date()
        )
        persistUsageHistory()
        NSApp.setActivationPolicy(.accessory)
        menu.delegate = self
        statusItem.menu = menu
        statusItem.button?.title = "%—"
        statusItem.button?.toolTip = text.usageTooltip
        rebuildMenu()
        refresh()
        configureRefreshTimer()
        configureStatusPresentationTimer()
    }

    private func configureRefreshTimer() {
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(
            withTimeInterval: refreshInterval.seconds,
            repeats: true
        ) { [weak self] _ in
            self?.refresh()
        }
    }

    func menuWillOpen(_ menu: NSMenu) {
        if UsageRefreshPolicy.shouldRefreshOnMenuOpen(lastUpdated: lastUpdated, now: Date()) {
            refresh()
        }
    }

    @objc private func refresh() {
        guard !isRefreshing else { return }
        isRefreshing = true
        rebuildMenu()

        let group = DispatchGroup()
        if codexConnected {
            group.enter()
            codexFetcher.fetch { [weak self] usage in
                DispatchQueue.main.async {
                    self?.acceptFetchedUsage(usage)
                    group.leave()
                }
            }
        } else {
            usages.removeValue(forKey: "Codex")
        }

        if claudeConnected {
            group.enter()
            claudeFetcher.fetch { [weak self] usage in
                DispatchQueue.main.async {
                    self?.acceptFetchedUsage(usage)
                    group.leave()
                }
            }
        } else {
            usages.removeValue(forKey: "Claude Code")
        }

        group.notify(queue: .main) { [weak self] in
            guard let self else { return }
            self.isRefreshing = false
            let updateDate = Date()
            self.lastUpdated = updateDate
            self.recordUsageHistory(at: updateDate)
            self.updateDisplayedRemaining()
            self.updateStatusTitle()
            self.rebuildMenu()
        }
    }

    private func acceptFetchedUsage(_ fetched: ProviderUsage, at date: Date = Date()) {
        if fetched.error == nil, !fetched.windows.isEmpty {
            usages[fetched.name] = fetched.markedSuccessful(at: date)
            return
        }
        if let issue = fetched.error,
           let previous = usages[fetched.name],
           !previous.windows.isEmpty,
           previous.lastSuccessfulAt != nil {
            usages[fetched.name] = .stale(from: previous, issue: issue)
            return
        }
        usages[fetched.name] = fetched
    }

    private func updateStatusTitle() {
        if let statusProviderName,
           let summary = UsageSummaryCalculator.summary(for: statusProviderName, in: displayUsages) {
            var title = "%\(summary.remainingPercent)"
            if showResetInMenuBar, let resetsAt = summary.resetsAt {
                title += " · \(text.relativeReset(resetsAt))"
            }
            let level = usageAlertPolicy.level(for: summary.remainingPercent)
            statusItem.button?.title = ""
            statusItem.button?.attributedTitle = NSAttributedString(
                string: title,
                attributes: [
                    .font: NSFont.systemFont(ofSize: NSFont.systemFontSize, weight: .semibold),
                    .foregroundColor: statusColor(for: level)
                ]
            )
            statusItem.button?.image = providerIcon(for: summary.providerName, size: 16)
            statusItem.button?.imagePosition = .imageLeading
            statusItem.button?.imageScaling = .scaleProportionallyDown
            if usages[summary.providerName]?.isStale == true {
                statusItem.button?.toolTip = text.staleTooltip(
                    provider: summary.providerName,
                    percent: summary.remainingPercent
                )
            } else {
                statusItem.button?.toolTip = text.remainingTooltip(
                    provider: summary.providerName,
                    percent: summary.remainingPercent
                )
            }
        } else {
            statusItem.button?.attributedTitle = NSAttributedString(string: "")
            statusItem.button?.title = "%—"
            statusItem.button?.image = statusProviderName.flatMap { providerIcon(for: $0, size: 16) }
            statusItem.button?.toolTip = statusProviderName.map { text.waitingForUsage(provider: $0) }
                ?? text.connectFirst
        }
    }

    private func configureStatusPresentationTimer() {
        statusPresentationTimer?.invalidate()
        statusPresentationTimer = nil

        let shouldRotate = autoRotateProviders && connectedProviderNames.count > 1
        guard shouldRotate || showResetInMenuBar else { return }
        let interval: TimeInterval = shouldRotate ? ProviderRotation.interval : 60
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            guard let self else { return }
            if self.autoRotateProviders && self.connectedProviderNames.count > 1 {
                self.rotatingProviderIndex = ProviderRotation.nextIndex(
                    after: self.rotatingProviderIndex,
                    providerCount: self.connectedProviderNames.count
                )
            }
            self.updateStatusTitle()
        }
        RunLoop.main.add(timer, forMode: .common)
        statusPresentationTimer = timer
    }

    private func recordUsageHistory(at date: Date) {
        guard usageHistoryEnabled else { return }
        for providerName in connectedProviderNames {
            guard let usage = usages[providerName], usage.error == nil else { continue }

            if let legacySamples = usageHistory.removeValue(forKey: providerName),
               let summary = UsageSummaryCalculator.summary(for: providerName, in: usages) {
                let migratedKey = historyKey(providerName: providerName, windowKind: summary.windowKind)
                if usageHistory[migratedKey] == nil {
                    usageHistory[migratedKey] = legacySamples
                }
            }

            for window in usage.windows {
                let key = historyKey(providerName: providerName, windowKind: window.kind)
                usageHistory[key] = UsageHistoryModel.adding(
                    remainingPercent: min(100, max(0, 100 - window.usedPercent)),
                    at: date,
                    to: usageHistory[key] ?? []
                )
            }
        }
        usageHistory = UsageHistoryModel.sanitized(usageHistory, now: date)
        persistUsageHistory()
    }

    private func historyKey(providerName: String, windowKind: UsageWindowKind) -> String {
        "\(providerName)|\(windowKind.historyKey)"
    }

    /// Gösterilecek kalan yüzdeleri günceller. Yalnızca yenileme tamamlandığında
    /// çağrılmalıdır; menü her yeniden çizildiğinde çağrılırsa bekletme mantığı
    /// tek bir ölçümü birden çok kez saymış olur.
    private func updateDisplayedRemaining() {
        for (providerName, usage) in usages where usage.error == nil {
            for window in usage.windows {
                let key = historyKey(providerName: providerName, windowKind: window.kind)
                let decision = UsageDisplayNoiseFilter.decide(
                    raw: remainingPercent(of: window),
                    previouslyDisplayed: displayedRemaining[key],
                    pendingRise: pendingRemainingRise[key],
                    pendingCount: pendingRemainingRiseCount[key] ?? 0
                )
                displayedRemaining[key] = decision.displayed
                pendingRemainingRise[key] = decision.pendingRise
                pendingRemainingRiseCount[key] = decision.pendingCount
            }
        }
    }

    private func remainingPercent(of window: UsageWindow) -> Int {
        min(100, max(0, 100 - window.usedPercent))
    }

    /// Menü ve üst çubuk için yumuşatılmış kopya. Geçmiş kaydı ham `usages`
    /// üzerinden yapılır, bu dönüşüm yalnızca gösterimi etkiler.
    private var displayUsages: [String: ProviderUsage] {
        usages.mapValues { usage in
            guard usage.error == nil else { return usage }
            return usage.replacingWindows(usage.windows.map { window in
                let key = historyKey(providerName: usage.name, windowKind: window.kind)
                guard let displayed = displayedRemaining[key],
                      displayed != remainingPercent(of: window)
                else { return window }
                return UsageWindow(
                    kind: window.kind,
                    usedPercent: 100 - displayed,
                    resetsAt: window.resetsAt,
                    durationMinutes: window.durationMinutes
                )
            })
        }
    }

    private func persistUsageHistory() {
        guard let data = UsageHistoryModel.encode(usageHistory) else { return }
        UserDefaults.standard.set(data, forKey: PreferenceKey.usageHistoryData)
        UserDefaults.standard.removeObject(forKey: PreferenceKey.legacyUsageHistoryData)
    }

    private func migrateLegacyPreferences() {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: PreferenceKey.codexConnected) == nil {
            let legacy = defaults.object(forKey: PreferenceKey.legacyCodexEnabled) != nil
                && defaults.bool(forKey: PreferenceKey.legacyCodexEnabled)
            defaults.set(legacy, forKey: PreferenceKey.codexConnected)
        }
        if defaults.object(forKey: PreferenceKey.claudeConnected) == nil {
            let legacy = defaults.object(forKey: PreferenceKey.legacyClaudeEnabled) != nil
                && defaults.bool(forKey: PreferenceKey.legacyClaudeEnabled)
            defaults.set(legacy, forKey: PreferenceKey.claudeConnected)
        }
        if defaults.string(forKey: PreferenceKey.selectedProvider) == nil {
            selectedProviderName = connectedProviderNames.first
        }
    }

    private func rebuildMenu() {
        menu.removeAllItems()
        let connectedNames = connectedProviderNames
        for (index, providerName) in connectedNames.enumerated() {
            if index > 0 { menu.addItem(.separator()) }
            let fallback: ProviderIssue = isRefreshing ? .refreshing : .noData
            addProvider(displayUsages[providerName] ?? .unavailable(providerName, fallback))
        }

        if !connectedNames.isEmpty {
            menu.addItem(.separator())
            addProviderSelector()
            addMenuBarAppearanceSettings()
            addUsageColorSettings()
            addUsageHistorySettings()
            addRefreshIntervalSettings()
            addDisconnectItems(connectedNames)
        }

        if !codexConnected || !claudeConnected {
            if !menu.items.isEmpty { menu.addItem(.separator()) }
            if !codexConnected {
                addConnectionItem(
                    title: text.connectCodex,
                    providerName: "Codex",
                    action: #selector(connectCodex)
                )
            }
            if !claudeConnected {
                addConnectionItem(
                    title: text.connectClaude,
                    providerName: "Claude Code",
                    action: #selector(connectClaude)
                )
            }
        }

        menu.addItem(.separator())
        addLanguageSelector()
        addLaunchAtLoginItem()
        menu.addItem(.separator())

        if let lastUpdated {
            let item = NSMenuItem(
                title: text.lastUpdated(formattedTime(lastUpdated)),
                action: nil,
                keyEquivalent: ""
            )
            item.isEnabled = false
            menu.addItem(item)
        }

        let refreshItem = NSMenuItem(
            title: isRefreshing ? text.refreshing : text.refreshNow,
            action: #selector(refresh),
            keyEquivalent: ""
        )
        refreshItem.target = self
        refreshItem.isEnabled = !isRefreshing && !connectedNames.isEmpty
        menu.addItem(refreshItem)

        let diagnosticsItem = NSMenuItem(
            title: text.copyDiagnostics,
            action: #selector(copyDiagnostics),
            keyEquivalent: ""
        )
        diagnosticsItem.target = self
        menu.addItem(diagnosticsItem)

        menu.addItem(.separator())
        let quitItem = NSMenuItem(title: text.quit, action: #selector(quit), keyEquivalent: "")
        quitItem.target = self
        menu.addItem(quitItem)
    }

    private func addProviderSelector() {
        let providerNames = connectedProviderNames
        let supportsAutomatic = providerNames.count > 1
        let providerLabels = providerNames.map { $0 == "Claude Code" ? "Claude" : $0 }
        let labels = supportsAutomatic ? [text.automatic] + providerLabels : providerLabels
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 276, height: 58))

        let label = NSTextField(labelWithString: text.showInMenuBar)
        label.font = .systemFont(ofSize: 11, weight: .medium)
        label.textColor = .secondaryLabelColor
        label.frame = NSRect(x: 12, y: 37, width: 252, height: 16)
        container.addSubview(label)

        let selector = NSSegmentedControl(
            labels: labels,
            trackingMode: .selectOne,
            target: self,
            action: #selector(selectStatusProvider(_:))
        )
        selector.segmentStyle = .rounded
        selector.frame = NSRect(x: 12, y: 7, width: 252, height: 28)
        if supportsAutomatic && autoRotateProviders {
            selector.selectedSegment = 0
        } else {
            let providerIndex = providerNames.firstIndex(of: selectedProviderName ?? "") ?? 0
            selector.selectedSegment = providerIndex + (supportsAutomatic ? 1 : 0)
        }
        container.addSubview(selector)

        let item = NSMenuItem()
        item.view = container
        menu.addItem(item)
    }

    private func addMenuBarAppearanceSettings() {
        let rootItem = NSMenuItem(title: text.menuBarAppearance, action: nil, keyEquivalent: "")
        let submenu = manuallyEnabledMenu()
        let resetItem = NSMenuItem(
            title: text.showResetInMenuBar,
            action: #selector(toggleResetInMenuBar),
            keyEquivalent: ""
        )
        resetItem.target = self
        resetItem.state = showResetInMenuBar ? .on : .off
        submenu.addItem(resetItem)
        rootItem.submenu = submenu
        menu.addItem(rootItem)
    }

    private func addLanguageSelector() {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 276, height: 58))

        let label = NSTextField(labelWithString: text.languageTitle)
        label.font = .systemFont(ofSize: 11, weight: .medium)
        label.textColor = .secondaryLabelColor
        label.frame = NSRect(x: 12, y: 37, width: 252, height: 16)
        container.addSubview(label)

        let selector = NSSegmentedControl(
            labels: ["Türkçe", "English"],
            trackingMode: .selectOne,
            target: self,
            action: #selector(selectLanguage(_:))
        )
        selector.segmentStyle = .rounded
        selector.frame = NSRect(x: 12, y: 7, width: 252, height: 28)
        selector.selectedSegment = language == .turkish ? 0 : 1
        container.addSubview(selector)

        let item = NSMenuItem()
        item.view = container
        menu.addItem(item)
    }

    private func addUsageColorSettings() {
        let rootItem = NSMenuItem(title: text.usageColorsTitle, action: nil, keyEquivalent: "")
        let submenu = manuallyEnabledMenu()

        let enabledItem = NSMenuItem(
            title: text.usageColorsEnabled,
            action: #selector(toggleUsageColors),
            keyEquivalent: ""
        )
        enabledItem.target = self
        enabledItem.state = usageColorsEnabled ? .on : .off
        submenu.addItem(enabledItem)
        submenu.addItem(.separator())

        for preset in UsageAlertPreset.allCases {
            let item = NSMenuItem(
                title: text.alertPresetTitle(preset),
                action: #selector(selectUsageAlertPreset(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = preset.rawValue
            item.state = usageAlertPreset == preset ? .on : .off
            item.isEnabled = usageColorsEnabled
            submenu.addItem(item)
        }

        rootItem.submenu = submenu
        menu.addItem(rootItem)
    }

    private func addRefreshIntervalSettings() {
        let rootItem = NSMenuItem(title: text.refreshIntervalTitle, action: nil, keyEquivalent: "")
        let submenu = manuallyEnabledMenu()

        for interval in UsageRefreshInterval.allCases {
            let item = NSMenuItem(
                title: text.refreshIntervalOption(interval),
                action: #selector(selectRefreshInterval(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = interval.rawValue
            item.state = refreshInterval == interval ? .on : .off
            submenu.addItem(item)
        }

        rootItem.submenu = submenu
        menu.addItem(rootItem)
    }

    private func addUsageHistorySettings() {
        let rootItem = NSMenuItem(title: text.usageHistoryTitle, action: nil, keyEquivalent: "")
        let submenu = manuallyEnabledMenu()

        let enabledItem = NSMenuItem(
            title: text.showUsageHistory,
            action: #selector(toggleUsageHistory),
            keyEquivalent: ""
        )
        enabledItem.target = self
        enabledItem.state = usageHistoryEnabled ? .on : .off
        submenu.addItem(enabledItem)

        let clearItem = NSMenuItem(
            title: text.clearUsageHistory,
            action: #selector(clearUsageHistory),
            keyEquivalent: ""
        )
        clearItem.target = self
        clearItem.isEnabled = usageHistory.values.contains { !$0.isEmpty }
        submenu.addItem(clearItem)

        rootItem.submenu = submenu
        menu.addItem(rootItem)
    }

    private func manuallyEnabledMenu() -> NSMenu {
        let submenu = NSMenu()
        submenu.autoenablesItems = false
        return submenu
    }

    private func addLaunchAtLoginItem() {
        let status = SMAppService.mainApp.status
        let suffix = status == .requiresApproval ? " (\(text.loginItemNeedsApproval))" : ""
        let item = NSMenuItem(
            title: text.launchAtLogin + suffix,
            action: #selector(toggleLaunchAtLogin),
            keyEquivalent: ""
        )
        item.target = self
        item.state = status == .enabled ? .on : (status == .requiresApproval ? .mixed : .off)
        menu.addItem(item)
    }

    private func addConnectionItem(title: String, providerName: String, action: Selector) {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        item.image = providerIcon(for: providerName, size: 16)
        menu.addItem(item)
    }

    private func addDisconnectItems(_ connectedNames: [String]) {
        for providerName in connectedNames {
            let title = providerName == "Codex" ? text.disconnectCodex : text.disconnectClaude
            let action = providerName == "Codex"
                ? #selector(disconnectCodex)
                : #selector(disconnectClaude)
            let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
            item.target = self
            item.image = providerIcon(for: providerName, size: 16)
            menu.addItem(item)
        }
    }

    private func addProvider(_ usage: ProviderUsage) {
        var rows: [(title: NSAttributedString, history: [UsageHistorySample])] = []
        for (position, window) in usage.windows.enumerated() {
            let samples = usageHistoryEnabled
                ? usageHistory[historyKey(providerName: usage.name, windowKind: window.kind)] ?? []
                : []
            rows.append((windowTitle(text.usageWindowLabel(window, position: position), window), samples))
        }
        if let error = usage.error {
            if let lastSuccessfulAt = usage.lastSuccessfulAt, usage.isStale {
                rows.append((staleTitle(error, lastSuccessfulAt: lastSuccessfulAt), []))
            } else {
                rows.append((errorTitle(error), []))
            }
        }

        let width: CGFloat = 276
        let rowHeights = rows.map { row in
            row.title.string.contains("\n") ? CGFloat(40) : CGFloat(25)
        }
        let historyHeights = rows.map { $0.history.isEmpty ? CGFloat(0) : CGFloat(58) }
        let height = 46 + rowHeights.reduce(0, +) + historyHeights.reduce(0, +)
        let container = NSView(frame: NSRect(x: 0, y: 0, width: width, height: height))

        if let icon = providerIcon(for: usage.name, size: 18) {
            let imageView = NSImageView(frame: NSRect(x: 12, y: height - 31, width: 18, height: 18))
            imageView.image = icon
            imageView.imageScaling = .scaleProportionallyDown
            container.addSubview(imageView)
        }

        let title = NSTextField(labelWithString: usage.name)
        title.font = .systemFont(ofSize: 15, weight: .semibold)
        title.textColor = .labelColor
        title.frame = NSRect(x: 38, y: height - 34, width: width - 50, height: 23)
        container.addSubview(title)

        var rowTop = height - 42
        for (index, rowData) in rows.enumerated() {
            let rowHeight = rowHeights[index]
            rowTop -= rowHeight
            let row = NSTextField(labelWithAttributedString: rowData.title)
            row.maximumNumberOfLines = 2
            row.lineBreakMode = .byWordWrapping
            row.frame = NSRect(
                x: 14,
                y: rowTop,
                width: width - 28,
                height: rowHeight
            )
            container.addSubview(row)

            guard let latestSample = rowData.history.last else { continue }
            rowTop -= historyHeights[index]
            let historyModel = UsageHistoryChartModel(samples: rowData.history)
            let historyRange = text.usageHistoryRange(historyModel.recordedDuration)
            let historySummary = text.usageHistorySummary(historyModel)
            let historyLabel = NSTextField(labelWithString: historyRange)
            historyLabel.font = .systemFont(ofSize: 10, weight: .medium)
            historyLabel.textColor = .secondaryLabelColor
            historyLabel.frame = NSRect(x: 14, y: rowTop + 43, width: width - 28, height: 13)
            container.addSubview(historyLabel)

            let summaryLabel = NSTextField(labelWithString: historySummary)
            summaryLabel.font = .systemFont(ofSize: 9.5, weight: .regular)
            summaryLabel.textColor = .secondaryLabelColor
            summaryLabel.lineBreakMode = .byTruncatingTail
            summaryLabel.frame = NSRect(x: 14, y: rowTop + 30, width: width - 28, height: 12)
            container.addSubview(summaryLabel)

            let graph = UsageSparklineView(
                frame: NSRect(x: 14, y: rowTop + 6, width: width - 28, height: 22),
                samples: rowData.history,
                lineColor: remainingColor(latestSample.remainingPercent)
            )
            graph.setAccessibilityLabel(historyRange)
            graph.setAccessibilityValue(historySummary)
            container.addSubview(graph)
        }

        let item = NSMenuItem()
        item.view = container
        menu.addItem(item)
    }

    private func windowTitle(_ label: String, _ window: UsageWindow) -> NSAttributedString {
        let remainingPercent = min(100, max(0, 100 - window.usedPercent))
        let prefix = "\(label): "
        let remaining = text.remaining(remainingPercent)
        var displayText = prefix + remaining
        if let resetsAt = window.resetsAt {
            displayText += "\n\(text.resetIn(text.relativeReset(resetsAt)))"
        }
        let attributed = NSMutableAttributedString(
            string: displayText,
            attributes: [
                .font: NSFont.systemFont(ofSize: 13),
                .foregroundColor: NSColor.labelColor
            ]
        )
        attributed.addAttributes(
            [
                .font: NSFont.systemFont(ofSize: 13, weight: .semibold),
                .foregroundColor: remainingColor(remainingPercent)
            ],
            range: NSRange(location: prefix.utf16.count, length: remaining.utf16.count)
        )
        if let lineBreak = displayText.firstIndex(of: "\n") {
            let resetStart = displayText.index(after: lineBreak)
            attributed.addAttributes(
                [
                    .font: NSFont.systemFont(ofSize: 12),
                    .foregroundColor: NSColor.secondaryLabelColor
                ],
                range: NSRange(resetStart..<displayText.endIndex, in: displayText)
            )
        }
        return attributed
    }

    private func errorTitle(_ issue: ProviderIssue) -> NSAttributedString {
        let informational: Bool
        switch issue {
        case .refreshing, .noData: informational = true
        default: informational = false
        }
        return NSAttributedString(
            string: text.issue(issue),
            attributes: [
                .font: NSFont.systemFont(ofSize: 13),
                .foregroundColor: informational ? NSColor.secondaryLabelColor : NSColor.systemRed
            ]
        )
    }

    private func staleTitle(_ issue: ProviderIssue, lastSuccessfulAt: Date) -> NSAttributedString {
        NSAttributedString(
            string: text.staleData(
                lastSuccessfulTime: formattedTime(lastSuccessfulAt),
                issue: issue
            ),
            attributes: [
                .font: NSFont.systemFont(ofSize: 11),
                .foregroundColor: NSColor.systemOrange
            ]
        )
    }

    private func remainingColor(_ percent: Int) -> NSColor {
        guard usageColorsEnabled else { return .labelColor }
        switch usageAlertPolicy.level(for: percent) {
        case .critical: return .systemRed
        case .warning: return .systemOrange
        case .normal: return .systemGreen
        }
    }

    private func statusColor(for level: UsageAlertLevel) -> NSColor {
        switch level {
        case .critical: return .systemRed
        case .warning: return .systemOrange
        case .normal: return .labelColor
        }
    }

    private func providerIcon(for providerName: String, size: CGFloat) -> NSImage? {
        let appPaths: [String]
        let fallbackSymbol: String
        switch providerName {
        case "Codex":
            appPaths = ["/Applications/Codex.app", "/Applications/ChatGPT.app"]
            fallbackSymbol = "ellipsis.curlybraces"
        case "Claude Code":
            appPaths = ["/Applications/Claude.app"]
            fallbackSymbol = "sparkles"
        default:
            appPaths = []
            fallbackSymbol = "gauge.with.dots.needle.33percent"
        }

        if let appPath = appPaths.first(where: { FileManager.default.fileExists(atPath: $0) }),
           let icon = NSWorkspace.shared.icon(forFile: appPath).copy() as? NSImage {
            icon.size = NSSize(width: size, height: size)
            return icon
        }

        let symbol = NSImage(systemSymbolName: fallbackSymbol, accessibilityDescription: providerName)
        symbol?.size = NSSize(width: size, height: size)
        symbol?.isTemplate = true
        return symbol
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    @objc private func connectCodex() {
        switch ExecutableLocator.codex() {
        case .found:
            break
        case .untrusted:
            showConnectionError(
                title: text.codexUntrustedTitle,
                message: text.codexUntrustedMessage
            )
            return
        case .missing:
            showConnectionError(
                title: text.codexNotFoundTitle,
                message: text.codexNotFoundMessage
            )
            return
        }
        let wasEmpty = connectedProviderNames.isEmpty
        codexConnected = true
        if wasEmpty { selectedProviderName = "Codex" }
        configureStatusPresentationTimer()
        updateStatusTitle()
        rebuildMenu()
        refresh()
    }

    @objc private func connectClaude() {
        switch ExecutableLocator.claude() {
        case .found:
            break
        case .untrusted:
            showConnectionError(
                title: text.claudeUntrustedTitle,
                message: text.claudeUntrustedMessage
            )
            return
        case .missing:
            showConnectionError(
                title: text.claudeNotFoundTitle,
                message: text.claudeNotFoundMessage
            )
            return
        }

        let alert = NSAlert()
        alert.messageText = text.connectClaudeTitle
        alert.informativeText = text.connectClaudeMessage
        alert.alertStyle = .informational
        alert.addButton(withTitle: text.connect)
        alert.addButton(withTitle: text.cancel)
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        let wasEmpty = connectedProviderNames.isEmpty
        claudeConnected = true
        if wasEmpty { selectedProviderName = "Claude Code" }
        configureStatusPresentationTimer()
        updateStatusTitle()
        rebuildMenu()
        refresh()
    }

    @objc private func disconnectCodex() { disconnectProvider("Codex") { self.codexConnected = false } }
    @objc private func disconnectClaude() { disconnectProvider("Claude Code") { self.claudeConnected = false } }

    private func disconnectProvider(_ providerName: String, clearPreference: () -> Void) {
        let previousSelection = selectedProviderName
        clearPreference()
        // Drop the live usage and menu-display state for the provider. Usage
        // history is intentionally kept (the "Clear history" item removes it).
        usages.removeValue(forKey: providerName)
        let prefix = "\(providerName)|"
        displayedRemaining = displayedRemaining.filter { !$0.key.hasPrefix(prefix) }
        pendingRemainingRise = pendingRemainingRise.filter { !$0.key.hasPrefix(prefix) }
        pendingRemainingRiseCount = pendingRemainingRiseCount.filter { !$0.key.hasPrefix(prefix) }

        let remaining = connectedProviderNames
        selectedProviderName = ProviderConnectionTransition.selection(
            afterDisconnecting: providerName,
            remaining: remaining,
            previousSelection: previousSelection
        )
        if !ProviderConnectionTransition.autoRotateStaysEnabled(
            remainingCount: remaining.count,
            wasEnabled: autoRotateProviders
        ) {
            autoRotateProviders = false
        }
        configureStatusPresentationTimer()
        updateStatusTitle()
        rebuildMenu()
    }

    @objc private func selectStatusProvider(_ sender: NSSegmentedControl) {
        let providerNames = connectedProviderNames
        let supportsAutomatic = providerNames.count > 1
        if supportsAutomatic && sender.selectedSegment == 0 {
            autoRotateProviders = true
            rotatingProviderIndex = providerNames.firstIndex(of: selectedProviderName ?? "") ?? 0
        } else {
            let providerIndex = sender.selectedSegment - (supportsAutomatic ? 1 : 0)
            guard providerNames.indices.contains(providerIndex) else { return }
            autoRotateProviders = false
            rotatingProviderIndex = providerIndex
            selectedProviderName = providerNames[providerIndex]
        }
        configureStatusPresentationTimer()
        updateStatusTitle()
    }

    @objc private func toggleResetInMenuBar() {
        showResetInMenuBar.toggle()
        configureStatusPresentationTimer()
        updateStatusTitle()
        rebuildMenu()
    }

    @objc private func toggleUsageColors() {
        usageColorsEnabled.toggle()
        updateStatusTitle()
        rebuildMenu()
    }

    @objc private func selectUsageAlertPreset(_ sender: NSMenuItem) {
        guard
            let raw = sender.representedObject as? String,
            let preset = UsageAlertPreset(rawValue: raw)
        else { return }
        usageAlertPreset = preset
        updateStatusTitle()
        rebuildMenu()
    }

    @objc private func selectRefreshInterval(_ sender: NSMenuItem) {
        guard
            let raw = sender.representedObject as? String,
            let interval = UsageRefreshInterval(rawValue: raw),
            interval != refreshInterval
        else { return }
        refreshInterval = interval
        configureRefreshTimer()
        rebuildMenu()
    }

    @objc private func toggleUsageHistory() {
        usageHistoryEnabled.toggle()
        if usageHistoryEnabled { recordUsageHistory(at: Date()) }
        rebuildMenu()
    }

    @objc private func clearUsageHistory() {
        usageHistory.removeAll()
        UserDefaults.standard.removeObject(forKey: PreferenceKey.usageHistoryData)
        UserDefaults.standard.removeObject(forKey: PreferenceKey.legacyUsageHistoryData)
        rebuildMenu()
    }

    @objc private func copyDiagnostics() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(diagnosticsSummary(), forType: .string)
    }

    private func diagnosticsSummary() -> String {
        let system = ProcessInfo.processInfo.operatingSystemVersion
        let lastRefresh = lastUpdated.map { ISO8601DateFormatter().string(from: $0) } ?? "never"
        var lines = [
            "UsageBar \(AppMetadata.version) (\(AppMetadata.build))",
            "macOS \(system.majorVersion).\(system.minorVersion).\(system.patchVersion)",
            "language=\(language.rawValue)",
            "last_refresh=\(lastRefresh)",
            "history_enabled=\(usageHistoryEnabled)",
            "history_series=\(usageHistory.count)",
            "history_samples=\(usageHistory.values.reduce(0) { $0 + $1.count })"
        ]

        for providerName in ["Codex", "Claude Code"] {
            let connected = providerName == "Codex" ? codexConnected : claudeConnected
            let executableState: String
            let lookup = providerName == "Codex"
                ? ExecutableLocator.codex()
                : ExecutableLocator.claude()
            switch lookup {
            case .found: executableState = "trusted"
            case .untrusted: executableState = "untrusted"
            case .missing: executableState = "missing"
            }
            let usage = usages[providerName]
            let state: String
            if usage?.isStale == true {
                state = "stale"
            } else if usage?.error != nil {
                state = "error"
            } else if usage?.windows.isEmpty == false {
                state = "fresh"
            } else {
                state = "no_data"
            }
            let windowKinds = usage?.windows.map { $0.kind.historyKey }.joined(separator: ",") ?? "none"
            let issue = usage?.error?.diagnosticCode ?? "none"
            let key = providerName == "Codex" ? "codex" : "claude"
            lines.append("\(key)=connected:\(connected),executable:\(executableState),state:\(state),windows:\(windowKinds),issue:\(issue)")
        }
        return lines.joined(separator: "\n")
    }

    @objc private func toggleLaunchAtLogin() {
        let service = SMAppService.mainApp
        if service.status == .requiresApproval {
            SMAppService.openSystemSettingsLoginItems()
            return
        }
        do {
            if service.status == .enabled {
                try service.unregister()
            } else {
                try service.register()
            }
            rebuildMenu()
        } catch {
            showConnectionError(
                title: text.loginItemFailed,
                message: error.localizedDescription
            )
        }
    }

    @objc private func selectLanguage(_ sender: NSSegmentedControl) {
        let selectedLanguage: AppLanguage = sender.selectedSegment == 1 ? .english : .turkish
        guard selectedLanguage != language else { return }
        language = selectedLanguage
        updateStatusTitle()
        menu.cancelTracking()
        rebuildMenu()
    }

    private func showConnectionError(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: text.ok)
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    private func formattedTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: language == .turkish ? "tr_TR" : "en_US")
        formatter.dateFormat = language == .turkish ? "HH:mm" : "h:mm a"
        return formatter.string(from: date)
    }
}

private func runSelfTest() -> Int32 {
    let turkish = Localizer(language: .turkish)
    let english = Localizer(language: .english)
    let durationOrigin = Date(timeIntervalSince1970: 1_000_000)
    guard
        turkish.remaining(59) == "%59 kaldı",
        english.remaining(59) == "59% remaining",
        english.remainingTooltip(provider: "Codex", percent: 59) == "Codex: 59% remaining",
        AppLanguage.preferred(from: ["tr-TR", "en-US"]) == .turkish,
        AppLanguage.preferred(from: ["en-US", "tr-TR"]) == .english,
        AppLanguage.preferred(from: []) == .english,
        turkish.issue(.claudeNotLoggedIn) == "Claude Code'a giriş yapılmamış",
        english.issue(.claudeNotLoggedIn) == "Claude Code is not signed in",
        english.relativeReset(
            durationOrigin.addingTimeInterval(3_600 + 15 * 60),
            now: durationOrigin
        ) == "1h 15m",
        english.relativeReset(
            durationOrigin.addingTimeInterval(6 * 86_400 + 21 * 3_600),
            now: durationOrigin
        ) == "6d 21h"
    else {
        fputs("Dil testi başarısız\n", stderr)
        return 1
    }

    let balancedAlerts = UsageAlertPolicy(isEnabled: true, preset: .balanced)
    let disabledAlerts = UsageAlertPolicy(isEnabled: false, preset: .early)
    guard
        balancedAlerts.level(for: 21) == .normal,
        balancedAlerts.level(for: 20) == .warning,
        balancedAlerts.level(for: 11) == .warning,
        balancedAlerts.level(for: 10) == .critical,
        balancedAlerts.level(for: -1) == .critical,
        disabledAlerts.level(for: 0) == .normal
    else {
        fputs("Kullanım renk eşiği testi başarısız\n", stderr)
        return 1
    }

    let historyOrigin = Date(timeIntervalSince1970: 2_000_000)
    let historyWithExpiredSample = [
        UsageHistorySample(
            recordedAt: historyOrigin.addingTimeInterval(-UsageHistoryModel.retentionInterval - 1),
            remainingPercent: 95
        ),
        UsageHistorySample(recordedAt: historyOrigin.addingTimeInterval(-120), remainingPercent: 80)
    ]
    let prunedHistory = UsageHistoryModel.adding(
        remainingPercent: 70,
        at: historyOrigin,
        to: historyWithExpiredSample
    )
    let replacedHistory = UsageHistoryModel.adding(
        remainingPercent: 65,
        at: historyOrigin.addingTimeInterval(30),
        to: prunedHistory
    )
    let encodedHistory = UsageHistoryModel.encode(["Codex": replacedHistory])
    let decodedHistory = UsageHistoryModel.decode(encodedHistory)
    let sanitizedHistory = UsageHistoryModel.sanitized([
        "Codex|weekly": [
            UsageHistorySample(recordedAt: historyOrigin.addingTimeInterval(-120), remainingPercent: 140),
            UsageHistorySample(recordedAt: historyOrigin.addingTimeInterval(-90), remainingPercent: -20),
            UsageHistorySample(recordedAt: historyOrigin.addingTimeInterval(120), remainingPercent: 50)
        ]
    ], now: historyOrigin)
    let flatChart = UsageHistoryChartModel(samples: [
        UsageHistorySample(recordedAt: historyOrigin, remainingPercent: 33)
    ])
    let changingChart = UsageHistoryChartModel(samples: [
        UsageHistorySample(recordedAt: historyOrigin, remainingPercent: 33),
        UsageHistorySample(recordedAt: historyOrigin.addingTimeInterval(35 * 60), remainingPercent: 31)
    ])
    let resetChart = UsageHistoryChartModel(samples: [
        UsageHistorySample(recordedAt: historyOrigin, remainingPercent: 20),
        UsageHistorySample(recordedAt: historyOrigin.addingTimeInterval(60), remainingPercent: 19),
        UsageHistorySample(recordedAt: historyOrigin.addingTimeInterval(120), remainingPercent: 90)
    ])
    let noisyChart = UsageHistoryChartModel(samples: [33, 34, 33, 32, 31].enumerated().map {
        UsageHistorySample(
            recordedAt: historyOrigin.addingTimeInterval(Double($0.offset * 60)),
            remainingPercent: $0.element
        )
    })
    guard
        prunedHistory.count == 2,
        replacedHistory.count == 2,
        replacedHistory.last?.remainingPercent == 65,
        decodedHistory["Codex"] == replacedHistory,
        sanitizedHistory["Codex|weekly"]?.count == 1,
        sanitizedHistory["Codex|weekly"]?.first?.remainingPercent == 0,
        flatChart.lowerBound == 28,
        flatChart.upperBound == 38,
        changingChart.delta == -2,
        resetChart.resetIndices == [2],
        noisyChart.samples.map(\.remainingPercent) == [33, 34, 33, 32, 31],
        noisyChart.displaySamples.map(\.remainingPercent) == [33, 33, 33, 32, 31],
        turkish.usageHistoryRange(changingChart.recordedDuration) == "Son 35 dk",
        english.usageHistoryRange(changingChart.recordedDuration) == "Last 35m",
        english.usageHistorySummary(changingChart) == "33% → 31% · change -2"
    else {
        fputs("Yerel kullanım geçmişi testi başarısız\n", stderr)
        return 1
    }

    // Eski snapshot geri sıçraması (33 → 38) gösterimde bekletilmeli; kalıcı
    // artış ise doğrulanınca kabul edilmeli.
    func renderedRemaining(_ raw: [Int]) -> [Int] {
        var displayed: Int?
        var pendingRise: Int?
        var pendingCount = 0
        return raw.map { value in
            let decision = UsageDisplayNoiseFilter.decide(
                raw: value,
                previouslyDisplayed: displayed,
                pendingRise: pendingRise,
                pendingCount: pendingCount
            )
            displayed = decision.displayed
            pendingRise = decision.pendingRise
            pendingCount = decision.pendingCount
            return decision.displayed
        }
    }
    guard
        renderedRemaining([33, 38, 33]) == [33, 33, 33],
        renderedRemaining([33, 38, 38, 38]) == [33, 33, 33, 38],
        renderedRemaining([4, 100, 98]) == [4, 100, 98]
    else {
        fputs("Kullanım gösterim filtresi testi başarısız\n", stderr)
        return 1
    }

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

    let claude = """
    Current session     41% used
    Resets in 2 hours 15 minutes
    Current week (all models)     18% used
    Resets Jul 29, 11:59pm (Europe/Istanbul)
    """
    let parsedClaude = UsageParser.claudeScreen(claude)
    guard
        parsedClaude.session?.usedPercent == 41,
        parsedClaude.weekly?.usedPercent == 18,
        parsedClaude.session?.resetsAt != nil,
        parsedClaude.weekly?.resetsAt != nil
    else {
        fputs("Claude parser testi başarısız\n", stderr)
        return 1
    }

    // Print-mode `claude -p "/usage"` output: plain text, one line per window.
    let printClaude = UsageParser.claudePrintUsage("""
    You are currently using your subscription to power your Claude Code usage

    Current session: 100% used · resets Jul 23 at 10:20pm (Europe/Istanbul)
    Current week (all models): 53% used · resets Jul 26 at 10pm (Europe/Istanbul)

    Last 24h · 623 requests · 8 sessions
    """)
    guard
        printClaude.session?.usedPercent == 100,
        printClaude.weekly?.usedPercent == 53,
        printClaude.session?.kind == .fiveHour,
        printClaude.weekly?.kind == .weekly,
        printClaude.session?.resetsAt != nil,
        printClaude.weekly?.resetsAt != nil, // minute-less "10pm" still parses
        printClaude.error == nil
    else {
        fputs("Claude print-mode kullanım testi başarısız\n", stderr)
        return 1
    }

    // Fractional percentage rounds; the "Last 24h · N requests" line must not be
    // misread as a usage window.
    let printFractional = UsageParser.claudePrintUsage("""
    Current session: 8.6% used · resets Jul 23 at 5pm (Europe/Istanbul)
    Current week (all models): 47% used
    Last 24h · 640 requests · 8 sessions
    """)
    guard
        printFractional.session?.usedPercent == 9,
        printFractional.weekly?.usedPercent == 47,
        printFractional.weekly?.resetsAt == nil,
        printFractional.error == nil
    else {
        fputs("Claude print-mode kesirli/kısmi testi başarısız\n", stderr)
        return 1
    }

    // Logged out and unreadable verdicts.
    guard
        case .claudeNotLoggedIn? =
            UsageParser.claudePrintUsage("Please run /login to authenticate").error,
        case .claudeUsageUnreadable? =
            UsageParser.claudePrintUsage("some unrelated output").error
    else {
        fputs("Claude print-mode oturum durumu testi başarısız\n", stderr)
        return 1
    }

    // Reset time-zone / DST handling. All date math must happen in the reset's
    // own time zone, independent of the Mac's, so these expectations hold on any
    // runner. `instant` builds the expected absolute time in a given zone.
    func resetInstant(_ resetText: String, now: Date) -> Date? {
        UsageParser.claudePrintUsage(
            "Current session: 10% used · resets \(resetText)",
            now: now
        ).session?.resetsAt
    }
    func instant(_ y: Int, _ mo: Int, _ d: Int, _ h: Int, _ mi: Int, _ zone: String) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: zone)!
        var components = DateComponents()
        components.year = y; components.month = mo; components.day = d
        components.hour = h; components.minute = mi
        return calendar.date(from: components)!
    }
    let ist = "Europe/Istanbul"
    let ny = "America/New_York"
    guard
        // Reset zone differs from the Mac's zone: resolves in Istanbul time.
        resetInstant("Jul 26 at 10pm (Europe/Istanbul)", now: instant(2026, 7, 20, 12, 0, ist))
            == instant(2026, 7, 26, 22, 0, ist),
        // Minute-less "5pm" pins to :00 and rolls to the next occurrence in-zone.
        resetInstant("5pm (America/New_York)", now: instant(2026, 3, 10, 18, 0, ny))
            == instant(2026, 3, 11, 17, 0, ny),
        // "4:59pm" keeps its minutes (not misread as "4" by the ha format).
        resetInstant("4:59pm (America/New_York)", now: instant(2026, 3, 10, 12, 0, ny))
            == instant(2026, 3, 10, 16, 59, ny),
        // Year-end roll: from a December now, "Jan 1 at 1am" advances a year in-zone.
        resetInstant("Jan 1 at 1am (America/New_York)", now: instant(2026, 12, 15, 12, 0, ny))
            == instant(2027, 1, 1, 1, 0, ny),
        // DST spring-forward: rolling "1am" a day across the US change (Mar 8, 2026)
        // preserves the 1am wall clock in New York. A Mac-zone roll would add a
        // fixed 24h and land an hour off.
        resetInstant("1am (America/New_York)", now: instant(2026, 3, 8, 3, 0, ny))
            == instant(2026, 3, 9, 1, 0, ny)
    else {
        fputs("Claude reset zaman dilimi/DST testi başarısız\n", stderr)
        return 1
    }

    let summary = UsageSummaryCalculator.summary(for: "Claude Code", in: [
        "Codex": parsedCodex,
        "Claude Code": parsedClaude
    ])
    guard summary?.providerName == "Claude Code", summary?.remainingPercent == 59 else {
        fputs("Kalan kullanım özeti testi başarısız\n", stderr)
        return 1
    }

    let claudeSessionFirst = ProviderUsage(
        name: "Claude Code",
        windows: [
            UsageWindow(
                kind: .fiveHour,
                usedPercent: 20,
                resetsAt: Date(timeIntervalSince1970: 1_800_000_000),
                durationMinutes: 300
            ),
            UsageWindow(kind: .weekly, usedPercent: 95, resetsAt: nil, durationMinutes: 10_080)
        ],
        error: nil
    )
    let sessionFirstSummary = UsageSummaryCalculator.summary(for: "Claude Code", in: [
        "Claude Code": claudeSessionFirst
    ])
    guard
        sessionFirstSummary?.remainingPercent == 80,
        sessionFirstSummary?.resetsAt?.timeIntervalSince1970 == 1_800_000_000
    else {
        fputs("Claude 5 saatlik pencere önceliği testi başarısız\n", stderr)
        return 1
    }

    guard
        ProviderRotation.nextIndex(after: 0, providerCount: 2) == 1,
        ProviderRotation.nextIndex(after: 1, providerCount: 2) == 0,
        ProviderRotation.nextIndex(after: 8, providerCount: 0) == 0,
        ProviderRotation.interval == 30
    else {
        fputs("Sağlayıcı dönüşüm testi başarısız\n", stderr)
        return 1
    }

    let diagnosticReset = Date(timeIntervalSince1970: 1_800_000_000)
    guard
        claudeDiagnosticWindowSummary([]) == "none",
        claudeDiagnosticWindowSummary([
            UsageWindow(kind: .fiveHour, usedPercent: 58, resetsAt: diagnosticReset, durationMinutes: 300),
            UsageWindow(kind: .weekly, usedPercent: 48, resetsAt: diagnosticReset, durationMinutes: 10_080)
        ]) == "five-hour+reset,weekly+reset",
        claudeDiagnosticWindowSummary([
            UsageWindow(kind: .fiveHour, usedPercent: 58, resetsAt: diagnosticReset, durationMinutes: 300),
            UsageWindow(kind: .weekly, usedPercent: 48, resetsAt: nil, durationMinutes: 10_080)
        ]) == "five-hour+reset,weekly"
    else {
        fputs("Claude teşhis pencere özeti testi başarısız\n", stderr)
        return 1
    }

    let refreshOrigin = Date(timeIntervalSince1970: 1_800_000_000)
    guard
        UsageRefreshInterval.allCases.map(\.minutes) == [1, 2, 5],
        UsageRefreshInterval.resolved(from: nil) == .fiveMinutes,
        UsageRefreshInterval.resolved(from: "bilinmeyen") == .fiveMinutes,
        UsageRefreshInterval.resolved(from: "oneMinute") == .oneMinute,
        UsageRefreshInterval.oneMinute.seconds == 60,
        UsageRefreshInterval.fiveMinutes.seconds == 300,
        UsageRefreshPolicy.menuOpenStalenessThreshold == 30,
        UsageRefreshPolicy.shouldRefreshOnMenuOpen(lastUpdated: nil, now: refreshOrigin) == false,
        UsageRefreshPolicy.shouldRefreshOnMenuOpen(
            lastUpdated: refreshOrigin.addingTimeInterval(-20),
            now: refreshOrigin
        ) == false,
        UsageRefreshPolicy.shouldRefreshOnMenuOpen(
            lastUpdated: refreshOrigin.addingTimeInterval(-45),
            now: refreshOrigin
        ),
        turkish.refreshIntervalTitle == "Yenileme aralığı",
        english.refreshIntervalTitle == "Refresh interval",
        turkish.refreshIntervalOption(.oneMinute) == "1 dakika",
        turkish.refreshIntervalOption(.fiveMinutes) == "5 dakika",
        english.refreshIntervalOption(.oneMinute) == "1 minute",
        english.refreshIntervalOption(.twoMinutes) == "2 minutes"
    else {
        fputs("Yenileme aralığı testi başarısız\n", stderr)
        return 1
    }

    let claudeWeeklyFallback = ProviderUsage(
        name: "Claude Code",
        windows: [
            UsageWindow(kind: .weekly, usedPercent: 26, resetsAt: nil, durationMinutes: 10_080)
        ],
        error: nil
    )
    let weeklyFallbackSummary = UsageSummaryCalculator.summary(for: "Claude Code", in: [
        "Claude Code": claudeWeeklyFallback
    ])
    guard weeklyFallbackSummary?.remainingPercent == 74 else {
        fputs("Claude haftalık yedek pencere testi başarısız\n", stderr)
        return 1
    }

    let successfulUsage = claudeSessionFirst.markedSuccessful(at: historyOrigin)
    let staleUsage = ProviderUsage.stale(from: successfulUsage, issue: .claudeUsageUnreadable)
    guard
        staleUsage.isStale,
        staleUsage.lastSuccessfulAt == historyOrigin,
        staleUsage.error?.diagnosticCode == "claude_usage_unreadable",
        UsageSummaryCalculator.summary(
            for: "Claude Code",
            in: ["Claude Code": staleUsage]
        )?.remainingPercent == 80
    else {
        fputs("Eski veri durumu testi başarısız\n", stderr)
        return 1
    }

    let weeklyOnlyCodex = """
    {"id":2,"result":{"rateLimits":{"primary":{"usedPercent":13,"windowDurationMins":10080,"resetsAt":1785340800},"secondary":null}}}
    """
    guard
        let parsedWeeklyOnly = UsageParser.codexResponse(from: Data(weeklyOnlyCodex.utf8)),
        parsedWeeklyOnly.session == nil,
        parsedWeeklyOnly.weekly?.usedPercent == 13
    else {
        fputs("Codex haftalık-only parser testi başarısız\n", stderr)
        return 1
    }

    let customWindowCodex = """
    {"id":2,"result":{"rateLimits":{"primary":{"usedPercent":13,"windowDurationMins":10080},"secondary":{"usedPercent":55,"windowDurationMins":4320}}}}
    """
    guard
        let parsedCustomWindow = UsageParser.codexResponse(from: Data(customWindowCodex.utf8)),
        parsedCustomWindow.windows.count == 2,
        parsedCustomWindow.windows.contains(where: { $0.kind == .duration(minutes: 4_320) }),
        UsageSummaryCalculator.summary(
            for: "Codex",
            in: ["Codex": parsedCustomWindow]
        )?.remainingPercent == 45,
        english.usageWindowLabel(
            UsageWindow(usedPercent: 55, resetsAt: nil, durationMinutes: 4_320),
            position: 1
        ) == "3 days"
    else {
        fputs("Codex özel pencere testi başarısız\n", stderr)
        return 1
    }

    let boundedCapture = BoundedDataCapture(limit: 4)
    guard
        boundedCapture.append(Data([1, 2, 3])),
        !boundedCapture.append(Data([4, 5])),
        boundedCapture.snapshot().data == Data([1, 2, 3, 4]),
        boundedCapture.snapshot().exceeded,
        ExecutableLocator.trustedExecutable(at: "/bin/echo", allowedRoot: "/bin") != nil,
        ExecutableLocator.trustedExecutable(at: "/bin/echo", allowedRoot: "/opt/homebrew") == nil
    else {
        fputs("Süreç güvenliği testi başarısız\n", stderr)
        return 1
    }

    // Regression for the SIGTERM/terminationStatus crash: stopping a child that
    // ignores SIGTERM must escalate to SIGKILL and reap it, so reading
    // terminationStatus afterward is safe. Before the fix this trapped
    // (SIGABRT, exit 134), which would abort this very self-test. Also exercise a
    // clean zero exit and a non-zero exit so terminationStatus is read across
    // outcomes.
    func runProcessStub(_ script: String) -> (exited: Bool, status: Int32)? {
        let process = Process()
        ProviderProcessLauncher.configure(
            process,
            executable: "/bin/sh",
            arguments: ["-c", script]
        )
        ProviderProcessContext.apply(to: process)
        guard (try? process.run()) != nil else { return nil }
        // Mirror the fetcher: let a self-exiting process finish on its own before
        // stopping, so a clean exit keeps its real status instead of the signal
        // stop() would otherwise deliver. A stubborn process outlives this wait
        // and is force-stopped below.
        let deadline = Date().addingTimeInterval(2)
        while process.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.02)
        }
        ProviderProcessLimits.stop(process)
        return (!process.isRunning, process.terminationStatus)
    }
    guard
        let stubborn = runProcessStub("trap '' TERM; sleep 30"),
        stubborn.exited, stubborn.status != 0,
        let cleanExit = runProcessStub("exit 0"),
        cleanExit.exited, cleanExit.status == 0,
        let failedExit = runProcessStub("exit 3"),
        failedExit.exited, failedExit.status == 3
    else {
        fputs("Süreç sonlandırma regresyon testi başarısız\n", stderr)
        return 1
    }

    print("UsageBar öz testi başarılı")
    return 0
}

/// Teşhis çıktısı için pencere özeti. Sıfırlama zamanının **okunabildiğini**
/// bildirir, zamanın kendisini asla yazmaz; böylece çıktı gizlilik açısından
/// güvenli kalırken sıfırlama ayrıştırmasındaki bir gerileme de görünür olur.
private func claudeDiagnosticWindowSummary(_ windows: [UsageWindow]) -> String {
    guard !windows.isEmpty else { return "none" }
    return windows
        .map { $0.resetsAt == nil ? $0.kind.historyKey : "\($0.kind.historyKey)+reset" }
        .joined(separator: ",")
}

private func runClaudeLiveDiagnostics() -> Int32 {
    let completed = DispatchSemaphore(value: 0)
    let lock = NSLock()
    var result: ProviderUsage?
    ClaudeUsageFetcher().fetch { usage in
        lock.lock()
        result = usage
        lock.unlock()
        completed.signal()
    }

    guard completed.wait(timeout: .now() + .seconds(25)) == .success else {
        print("claude_live=issue:diagnostic_wait_timed_out,windows:none")
        return 2
    }
    lock.lock()
    let usage = result
    lock.unlock()
    guard let usage else {
        print("claude_live=issue:no_result,windows:none")
        return 2
    }
    let windows = claudeDiagnosticWindowSummary(usage.windows)
    print("claude_live=issue:\(usage.error?.diagnosticCode ?? "none"),windows:\(windows)")
    return usage.error == nil ? 0 : 2
}

private func runProcessGroupLauncher() -> Int32 {
    let argumentOffset: Int32 = 2
    guard CommandLine.argc > argumentOffset else { return Int32(EINVAL) }
    return Int32(usagebar_exec_in_new_process_group(
        CommandLine.argc - argumentOffset,
        CommandLine.unsafeArgv.advanced(by: Int(argumentOffset))
    ))
}

if CommandLine.arguments.contains("--self-test") {
    exit(runSelfTest())
}

if CommandLine.arguments.contains("--diagnose-claude-live") {
    exit(runClaudeLiveDiagnostics())
}

if CommandLine.arguments.count > 2,
   CommandLine.arguments[1] == "--process-group-launcher" {
    exit(runProcessGroupLauncher())
}

let application = NSApplication.shared
let delegate = AppDelegate()
application.delegate = delegate
application.run()
