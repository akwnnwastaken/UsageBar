import Foundation

/// The minimum this host needs to know about Tailscale, read-only.
public struct MobileSyncTailscaleStatus: Equatable, Sendable {
    public let isRunning: Bool
    /// The machine's own MagicDNS name, without the trailing dot. Held in
    /// memory for as long as a QR is on screen and never written anywhere.
    public let host: String?

    public init(isRunning: Bool, host: String?) {
        self.isRunning = isRunning
        self.host = host
    }

    public var isPairable: Bool { isRunning && host != nil }
}

/// Reads `tailscale status` and nothing else.
///
/// Deliberately not a Tailscale SDK, not `tsnet`, and not a write path. This
/// host may *observe* Tailscale; configuring Serve, Funnel, grants, ACLs, tags
/// or auth keys remains an owner action performed outside the app, because an
/// application that can reshape a tailnet is a much larger thing to trust than
/// one that can read its own hostname.
public struct MobileSyncTailscaleStatusReader {
    /// Absolute paths only, from a fixed list.
    ///
    /// Never resolved through `PATH` and never run through a shell: both would
    /// let whatever a user happens to have installed decide what this process
    /// executes.
    public static let candidateExecutables = [
        "/Applications/Tailscale.app/Contents/MacOS/Tailscale",
        "/usr/local/bin/tailscale",
        "/opt/homebrew/bin/tailscale"
    ]

    /// A stuck CLI must not hold the pairing sheet — or the main queue — open.
    public static let timeout: TimeInterval = 5

    /// `tailscale status --json` is a few kilobytes. Anything far beyond that
    /// is not an answer worth parsing.
    public static let maximumOutputBytes = 512 * 1024

    /// stderr is drained so the pipe cannot fill, held under a ceiling so it
    /// cannot fill memory instead, and then discarded unread: `tailscale`
    /// diagnostics can name the account, the tailnet and its peers, none of
    /// which this host has any business holding or logging.
    ///
    /// The ceiling is small because nothing consumes what it bounds. A child
    /// that floods stderr is not producing an answer worth having, so passing
    /// it is treated as failure rather than as output to keep reading.
    public static let maximumErrorBytes = 64 * 1024

    private let executableURL: URL?
    private let runner: (URL, TimeInterval, Int) -> Data?

    public init(
        executableURL: URL? = MobileSyncTailscaleStatusReader.locateExecutable(),
        runner: @escaping (URL, TimeInterval, Int) -> Data? = MobileSyncTailscaleStatusReader.runStatus
    ) {
        self.executableURL = executableURL
        self.runner = runner
    }

    public static func locateExecutable() -> URL? {
        let manager = FileManager.default
        for path in candidateExecutables where manager.isExecutableFile(atPath: path) {
            return URL(fileURLWithPath: path)
        }
        return nil
    }

    /// Returns only what pairing needs. The raw JSON is parsed and dropped: it
    /// contains peers, keys and addresses, none of which this host has any
    /// business holding, and none of which is ever logged.
    public func read() -> MobileSyncTailscaleStatus {
        guard let executableURL,
              let data = runner(executableURL, Self.timeout, Self.maximumOutputBytes),
              let object = try? JSONSerialization.jsonObject(with: data),
              let dictionary = object as? [String: Any]
        else { return MobileSyncTailscaleStatus(isRunning: false, host: nil) }

        let isRunning = (dictionary["BackendState"] as? String) == "Running"
        let selfNode = dictionary["Self"] as? [String: Any]
        let host = (selfNode?["DNSName"] as? String).flatMap(Self.tailnetHost)
        return MobileSyncTailscaleStatus(isRunning: isRunning, host: host)
    }

    /// Normalizes a MagicDNS name and refuses anything that is not one.
    ///
    /// Requiring `.ts.net` here is the host's own sanity gate on its own CLI
    /// output. The phone re-validates what it scans before building a URL from
    /// it; that client-side check is the authoritative one, and this does not
    /// replace it.
    static func tailnetHost(_ raw: String) -> String? {
        var host = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        while host.hasSuffix(".") { host.removeLast() }
        guard !host.isEmpty, host.utf8.count <= 253, host.hasSuffix(".ts.net") else { return nil }
        guard host.rangeOfCharacter(from: .whitespacesAndNewlines) == nil,
              !host.contains("/"), !host.contains(":"), !host.contains("@")
        else { return nil }
        let labels = host.split(separator: ".", omittingEmptySubsequences: false)
        guard labels.count >= 4 else { return nil }
        for label in labels {
            guard !label.isEmpty, label.utf8.count <= 63,
                  label.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") })
            else { return nil }
        }
        return host
    }

    /// Runs the CLI with an explicit argument vector — no shell, so no string
    /// is ever interpreted — bounded, concurrently drained pipes and a hard
    /// timeout, after which the child is stopped and reaped.
    public static func runStatus(
        executableURL: URL,
        timeout: TimeInterval,
        maximumBytes: Int
    ) -> Data? {
        let process = Process()
        process.executableURL = executableURL
        process.arguments = ["status", "--json"]
        // The environment is inherited rather than stripped.
        //
        // A minimal environment was the first instinct and it does not work:
        // the macOS Tailscale CLI talks to its GUI helper, and under `env -i`
        // it fails to reach it, prints "The Tailscale GUI failed to start" to
        // *stdout* and still exits 0 — which reads as "Tailscale unavailable"
        // no matter which variables are added back.
        //
        // Inheriting costs nothing here. The reason to control a child's
        // environment is to stop PATH deciding what gets executed, and that is
        // already handled by resolving an absolute path from a fixed list. No
        // secret of this app lives in its environment, and the argument vector
        // below is explicit, so nothing a variable could contain is
        // interpreted as a command.

        let output = Pipe()
        let errors = Pipe()
        process.standardOutput = output
        process.standardError = errors
        process.standardInput = FileHandle.nullDevice

        do { try process.run() } catch { return nil }

        // Both pipes are drained from here on, concurrently and in bounded
        // chunks, each into its own ceiling. Neither drain waits for the
        // process and the process waits for neither drain, so the only thing
        // that can end this read is one of the limits below.
        let captured = MobileSyncBoundedCapture(limit: maximumBytes)
        let discardedErrors = MobileSyncBoundedCapture(limit: maximumErrorBytes)
        let progress = DispatchSemaphore(value: 0)
        let outputDrain = MobileSyncPipeDrainer.start(output, into: captured, progress: progress)
        let errorDrain = MobileSyncPipeDrainer.start(errors, into: discardedErrors, progress: progress)

        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning, Date() < deadline {
            // Past either ceiling there is no answer left to wait for.
            if captured.hasOverflowed || discardedErrors.hasOverflowed { break }
            _ = progress.wait(timeout: .now() + .milliseconds(100))
        }
        // Decided before the child is stopped. Afterwards nothing is running,
        // and a timeout would be indistinguishable from a clean finish.
        let ranOutOfTime = process.isRunning
            && !captured.hasOverflowed
            && !discardedErrors.hasOverflowed

        // Every path out — finished, oversized, or out of time — ends the child
        // and reaps it, so the status read below is safe and nothing is left
        // behind. The drains are then joined under their own finite deadline.
        MobileSyncProcessStopper.stopAndReap(process)
        _ = outputDrain.wait(timeout: .now() + .seconds(1))
        _ = errorDrain.wait(timeout: .now() + .seconds(1))

        let collected = captured.snapshot()
        guard !ranOutOfTime, !collected.overflowed, !discardedErrors.hasOverflowed else { return nil }
        guard process.terminationStatus == 0 else { return nil }
        // The CLI can fail while still exiting 0, writing a human sentence to
        // stdout instead of JSON. Anything that does not begin an object is
        // not an answer.
        guard collected.bytes.first == UInt8(ascii: "{") else { return nil }
        return collected.bytes
    }
}
