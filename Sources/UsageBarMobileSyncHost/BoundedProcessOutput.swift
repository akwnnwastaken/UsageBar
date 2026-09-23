import Darwin
import Foundation

// Reading a child process safely is three separate obligations, and this file
// holds one small, auditable implementation of each:
//
//   1. never accumulate output without a ceiling,
//   2. drain every pipe from the moment the child starts, and
//   3. end the child and reap it before reading its status.
//
// The UsageBar executable solves the same three problems for the Codex and
// Claude CLIs, but those helpers are private to that target and their stopper
// signals a *process group*, because provider processes are launched through a
// group launcher. This host runs the Tailscale CLI directly, so the child
// shares this process's group and a group-wide signal would be aimed at
// UsageBar itself. Copying the shape rather than exporting the code keeps the
// production launcher out of this module's reach, and keeps this module's
// reader small enough to read in one sitting.

/// A byte buffer that cannot grow past its limit.
///
/// The ceiling is enforced on every append rather than checked afterwards. A
/// hostile or simply broken child that writes without end must not be able to
/// make this host allocate without end, and "collect it all, then measure it"
/// is precisely the shape that lets it.
final class MobileSyncBoundedCapture {
    private let limit: Int
    private let lock = NSLock()
    private var bytes = Data()
    private var overflowed = false

    init(limit: Int) {
        self.limit = max(0, limit)
    }

    /// Appends up to the remaining allowance and reports whether the buffer is
    /// still within bounds. Once exceeded it stays exceeded: a truncated answer
    /// is not a smaller answer, it is a different one.
    @discardableResult
    func append(_ chunk: Data) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !chunk.isEmpty else { return !overflowed }

        let remaining = max(0, limit - bytes.count)
        if chunk.count > remaining {
            bytes.append(chunk.prefix(remaining))
            overflowed = true
        } else {
            bytes.append(chunk)
        }
        return !overflowed
    }

    func snapshot() -> (bytes: Data, overflowed: Bool) {
        lock.lock()
        defer { lock.unlock() }
        return (bytes, overflowed)
    }

    var hasOverflowed: Bool {
        lock.lock()
        defer { lock.unlock() }
        return overflowed
    }
}

/// Drains a pipe into a bounded buffer, in finite chunks, off the caller's
/// thread.
///
/// Both of a child's pipes must be drained from the moment it starts. A child
/// that fills the stderr pipe while the parent reads only stdout blocks inside
/// `write(2)` and never reaches exit — so the parent waits for a process that
/// is waiting for the parent, and only a timeout ends it. Draining both
/// concurrently is what makes that deadlock impossible rather than merely
/// unlikely.
enum MobileSyncPipeDrainer {
    /// Finite, so a single read can never be asked for an unbounded amount.
    static let chunkSize = 16 * 1_024

    static func start(
        _ pipe: Pipe,
        into capture: MobileSyncBoundedCapture,
        progress: DispatchSemaphore? = nil
    ) -> DispatchGroup {
        let group = DispatchGroup()
        let handle = pipe.fileHandleForReading
        group.enter()
        DispatchQueue.global(qos: .utility).async {
            defer {
                // Wake the waiter one last time so it observes the end of the
                // stream on its next pass instead of sleeping out its poll.
                progress?.signal()
                group.leave()
            }
            while true {
                do {
                    // EOF reads as nil or as empty; either ends the drain, so
                    // the loop cannot spin once the child's end is closed.
                    guard let chunk = try handle.read(upToCount: chunkSize),
                          !chunk.isEmpty
                    else { return }
                    let withinBounds = capture.append(chunk)
                    progress?.signal()
                    // Past the ceiling there is nothing further to learn, and
                    // reading on would only keep a runaway child comfortable.
                    guard withinBounds else { return }
                } catch {
                    return
                }
            }
        }
        return group
    }
}

/// Ends a child and reaps it.
///
/// Every exit from a read goes through here, and here always ends in
/// `waitUntilExit`. `terminationStatus` may only be read once Foundation has
/// observed the exit; reading it while the process still runs traps, which is
/// the historical Foundation failure this exists to make unreachable.
enum MobileSyncProcessStopper {
    /// Long enough for a well-behaved child to finish on SIGTERM, short enough
    /// that a badly-behaved one cannot hold the caller.
    static let terminationGrace: TimeInterval = 1
    private static let pollInterval: TimeInterval = 0.02

    static func stopAndReap(_ process: Process) {
        let identifier = process.processIdentifier
        if process.isRunning, identifier > 0 {
            // The pid, never `-pid`: this child shares UsageBar's own process
            // group, so a group signal would be aimed at UsageBar.
            Darwin.kill(identifier, SIGTERM)
            let deadline = Date().addingTimeInterval(terminationGrace)
            while process.isRunning, Date() < deadline {
                Thread.sleep(forTimeInterval: pollInterval)
            }
            // A child that ignores SIGTERM does not get to outlive the read.
            if process.isRunning {
                Darwin.kill(identifier, SIGKILL)
            }
        }
        // Already signalled, so this returns promptly — and it is what makes
        // the child a reaped exit rather than a zombie.
        process.waitUntilExit()
    }
}
