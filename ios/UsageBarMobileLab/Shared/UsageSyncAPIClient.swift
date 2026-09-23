import Foundation
import UsageBarSync

/// The one network operation this app performs.
public protocol SnapshotFetching: Sendable {
    func fetchSnapshot(using connection: UsageSyncConnection) async throws -> UsageSyncSnapshot
}

/// Why a refresh failed.
///
/// Every case maps to the same short, generic user-facing sentence. The
/// distinction exists so the app can reason about failures, not so it can
/// describe a server's internals on screen: a response body from a host the
/// user typed is untrusted text and is never displayed.
public enum SnapshotFetchError: Error, Equatable, CustomStringConvertible {
    case notConnected
    /// The desktop refused the credential outright.
    ///
    /// Distinct from every other failure because it is the only one that is
    /// *definitive*: a timeout, a 503 or an unreachable host all mean "ask
    /// again later" and must leave the stored connection alone, while this one
    /// means the credential no longer authorizes anything — the Mac has been
    /// re-paired or the phone revoked — and the phone must forget it.
    case authenticationRejected
    case rejectedByServer
    case redirectRefused
    case responseTooLarge
    case unexpectedContentType
    case malformedSnapshot
    case transportFailure

    public var description: String {
        switch self {
        case .authenticationRejected:
            return "The access key was refused."
        default:
            return "Could not reach UsageBar."
        }
    }

    /// Whether this failure revokes the stored credential.
    ///
    /// Exactly one case does. Everything else is a transient condition that
    /// must never cost the user their connection — the Mac being asleep is the
    /// accepted tradeoff of a direct overlay, not a reason to log them out.
    public var revokesStoredCredential: Bool {
        self == .authenticationRejected
    }
}

/// Fetches a schema-v1 snapshot over HTTPS from a Tailscale Serve endpoint.
///
/// The app speaks ordinary HTTPS. It embeds no Tailscale SDK, starts no VPN and
/// reads nothing from the Tailscale app — the installed Tailscale client
/// supplies reachability, and from `URLSession`'s point of view this is a
/// normal request to a normal hostname.
public final class UsageSyncAPIClient: NSObject, SnapshotFetching, @unchecked Sendable {
    /// Hard ceiling on a response body.
    ///
    /// A schema-v1 snapshot for a realistic number of providers is a couple of
    /// kilobytes; 64 KiB is generous. The bound exists because the endpoint is
    /// a hostname the user typed, and a hostile or wrong host must not be able
    /// to make the app buffer without limit.
    public static let maximumResponseBytes = 64 * 1024

    private let configuration: URLSessionConfiguration
    private let requestTimeout: TimeInterval

    public init(
        configuration: URLSessionConfiguration = UsageSyncAPIClient.privateConfiguration(),
        requestTimeout: TimeInterval = 15
    ) {
        self.configuration = configuration
        self.requestTimeout = requestTimeout
        super.init()
    }

    /// A session configuration that remembers nothing.
    ///
    /// No URL cache (a snapshot must never be served from disk after the
    /// credential is forgotten), no cookie storage and no credential storage —
    /// the bearer is attached to exactly one request and never persisted by the
    /// loading system.
    public static func privateConfiguration() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.httpCookieAcceptPolicy = .never
        configuration.urlCredentialStorage = nil
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 30
        configuration.waitsForConnectivity = false
        return configuration
    }

    public func fetchSnapshot(using connection: UsageSyncConnection) async throws -> UsageSyncSnapshot {
        var request = URLRequest(url: connection.host.snapshotURL)
        request.httpMethod = "GET"
        request.timeoutInterval = requestTimeout
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(connection.accessKey)", forHTTPHeaderField: "Authorization")
        // No Tailscale identity header is set here, or anywhere else in this
        // app. `Tailscale-User-Login` is injected by Serve, which is the only
        // party in a position to prove it; a client that set it would merely be
        // asserting it, and the desktop would be trusting a value the caller
        // chose.

        let delegate = SnapshotTaskDelegate(maximumBytes: Self.maximumResponseBytes)
        let session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }

        let (data, response) = try await delegate.perform(request: request, on: session)

        guard let http = response as? HTTPURLResponse else {
            throw SnapshotFetchError.transportFailure
        }
        guard http.statusCode != 401, http.statusCode != 403 else {
            throw SnapshotFetchError.authenticationRejected
        }
        // Only a 200 may replace what is already cached. Anything else is a
        // failed refresh, which leaves the previous snapshot in place.
        guard http.statusCode == 200 else {
            throw SnapshotFetchError.rejectedByServer
        }
        let contentType = (http.value(forHTTPHeaderField: "Content-Type") ?? "").lowercased()
        guard contentType.hasPrefix("application/json") else {
            throw SnapshotFetchError.unexpectedContentType
        }
        guard data.count <= Self.maximumResponseBytes else {
            throw SnapshotFetchError.responseTooLarge
        }

        // Everything arriving over the network is untrusted structured input:
        // decode *and* validate, and reject the whole document on any failure
        // rather than repairing it.
        do {
            return try UsageSyncSerialization.decode(data)
        } catch {
            throw SnapshotFetchError.malformedSnapshot
        }
    }
}

/// Session delegate enforcing the two rules `URLSession` will not enforce for us.
final class SnapshotTaskDelegate: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let maximumBytes: Int
    private var buffer = Data()
    private var continuation: CheckedContinuation<(Data, URLResponse), Error>?
    private var response: URLResponse?
    private var failure: Error?
    private let lock = NSLock()

    init(maximumBytes: Int) {
        self.maximumBytes = maximumBytes
    }

    func perform(request: URLRequest, on session: URLSession) async throws -> (Data, URLResponse) {
        try await withCheckedThrowingContinuation { continuation in
            lock.lock()
            self.continuation = continuation
            lock.unlock()
            session.dataTask(with: request).resume()
        }
    }

    /// Refuse every redirect.
    ///
    /// Following one would re-issue the request — with the `Authorization`
    /// header — at whatever host the response named. A single 302 from a
    /// mistyped host would be enough to hand the bearer token to a stranger.
    /// The UsageBar endpoint never redirects, so refusing costs nothing.
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        lock.lock()
        failure = SnapshotFetchError.redirectRefused
        lock.unlock()
        completionHandler(nil)
        task.cancel()
    }

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        // Reject on the declared length before a single byte of body is taken.
        if response.expectedContentLength > Int64(maximumBytes) {
            lock.lock()
            failure = SnapshotFetchError.responseTooLarge
            lock.unlock()
            completionHandler(.cancel)
            return
        }
        lock.lock()
        self.response = response
        lock.unlock()
        completionHandler(.allow)
    }

    /// Enforce the ceiling during receipt, not after.
    ///
    /// A server that lies about (or omits) `Content-Length` would otherwise
    /// stream unbounded data into memory before anyone checked.
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        lock.lock()
        buffer.append(data)
        let exceeded = buffer.count > maximumBytes
        if exceeded {
            failure = SnapshotFetchError.responseTooLarge
            buffer = Data()
        }
        lock.unlock()
        if exceeded { dataTask.cancel() }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        lock.lock()
        let pending = continuation
        continuation = nil
        let recordedFailure = failure
        let collected = buffer
        let received = response ?? task.response
        lock.unlock()

        guard let pending else { return }
        if let recordedFailure {
            pending.resume(throwing: recordedFailure)
            return
        }
        if error != nil {
            pending.resume(throwing: SnapshotFetchError.transportFailure)
            return
        }
        guard let received else {
            pending.resume(throwing: SnapshotFetchError.transportFailure)
            return
        }
        pending.resume(returning: (collected, received))
    }
}
