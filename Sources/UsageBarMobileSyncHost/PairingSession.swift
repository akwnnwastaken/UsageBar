import Foundation
import UsageBarPairing

/// One short-lived opportunity to issue a mobile credential.
///
/// Everything about it is deliberately fragile. It exists only in memory, only
/// after the owner explicitly asks for it, only for a couple of minutes, only
/// for one success, and only for a handful of failures. A pairing QR is visible
/// to anyone in the room and photographable from across it, so the defence is
/// not secrecy of the code but the narrowness of the window in which it means
/// anything.
public struct MobileSyncPairingSession: Sendable {
    /// Short enough that a photographed QR is stale before it is useful,
    /// long enough to walk to the phone and open the scanner.
    public static let defaultLifetime: TimeInterval = 120

    /// A wrong code is either a typo-free forgery or a scan of something else;
    /// neither needs many tries. The ceiling turns an online guessing attempt
    /// into a single-shot one.
    public static let maximumFailedAttempts = 8

    public let code: UsageBarPairingCode
    public let createdAt: Date
    public let expiresAt: Date

    init(code: UsageBarPairingCode, createdAt: Date, lifetime: TimeInterval) {
        self.code = code
        self.createdAt = createdAt
        self.expiresAt = createdAt.addingTimeInterval(lifetime)
    }

    public func isExpired(at now: Date) -> Bool { now >= expiresAt }

    public func remaining(at now: Date) -> TimeInterval {
        max(0, expiresAt.timeIntervalSince(now))
    }
}

/// Owns the current pairing session, if there is one.
///
/// Thread-safe because the listener consumes a session from a connection queue
/// while the menu creates and cancels one from the main queue.
public final class MobileSyncPairingSessionStore: @unchecked Sendable {
    public enum ConsumeResult: Equatable {
        case paired
        /// Every failure looks the same to a caller. The distinction exists so
        /// the host can count attempts and expire sessions, never so a response
        /// can explain which part was wrong.
        case rejected
    }

    private let lock = NSLock()
    private var session: MobileSyncPairingSession?
    private var failedAttempts = 0
    private let lifetime: TimeInterval
    private let attemptCeiling: Int

    public init(
        lifetime: TimeInterval = MobileSyncPairingSession.defaultLifetime,
        attemptCeiling: Int = MobileSyncPairingSession.maximumFailedAttempts
    ) {
        self.lifetime = lifetime
        self.attemptCeiling = attemptCeiling
    }

    /// Starts a session, replacing any existing one.
    ///
    /// Replacing rather than refusing is the safer default: the owner pressing
    /// "Pair iPhone" again means the previous attempt is being abandoned, and
    /// leaving the old code live would keep a window open that the owner
    /// believes they have closed.
    @discardableResult
    public func start(now: Date = Date()) -> MobileSyncPairingSession {
        let session = MobileSyncPairingSession(
            code: UsageBarPairingCode.generate(),
            createdAt: now,
            lifetime: lifetime
        )
        lock.lock()
        self.session = session
        failedAttempts = 0
        lock.unlock()
        return session
    }

    public func cancel() {
        lock.lock()
        session = nil
        failedAttempts = 0
        lock.unlock()
    }

    public func current(now: Date = Date()) -> MobileSyncPairingSession? {
        lock.lock()
        defer { lock.unlock() }
        guard let session, !session.isExpired(at: now) else { return nil }
        return session
    }

    public var isPairing: Bool { current() != nil }

    /// Atomically checks and consumes.
    ///
    /// Success clears the session inside the same lock acquisition that
    /// verified it, so two simultaneous requests carrying the same valid code
    /// cannot both be issued a credential. That is the whole point of
    /// "one-time", and it is a property of this critical section rather than of
    /// how quickly the caller follows up.
    public func consume(presented: UsageBarPairingCode, now: Date = Date()) -> ConsumeResult {
        lock.lock()
        defer { lock.unlock() }

        guard let session else { return .rejected }
        guard !session.isExpired(at: now) else {
            self.session = nil
            failedAttempts = 0
            return .rejected
        }
        guard session.code.matches(presented) else {
            failedAttempts += 1
            if failedAttempts >= attemptCeiling {
                self.session = nil
                failedAttempts = 0
            }
            return .rejected
        }
        self.session = nil
        failedAttempts = 0
        return .paired
    }
}
