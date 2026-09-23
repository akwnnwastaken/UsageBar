import Foundation
import UsageBarSync
import UsageBarSyncTransport
import UsageBarPairing

/// The Mobile Lab host's request policy.
///
/// Pure: a request in, a response out, no sockets — which is what lets every
/// authentication, routing and pairing rule below be tested directly.
///
/// It replaces the Phase-4 prototype's single ephemeral shared secret with a
/// paired credential: the Mac stores only digests, and a request must satisfy
/// both the Serve-injected identity and the bearer that identity was issued.
public struct MobileSyncService: Sendable {
    public static let snapshotPath = "/v1/snapshot"
    public static let pairingPath = "/v1/pair"

    /// Injected by Tailscale Serve. Trustworthy only because Serve is the sole
    /// ingress to a loopback-bound listener — a service on a routable interface
    /// could be called directly by anyone who would then supply their own.
    public static let identityHeader = "Tailscale-User-Login"

    /// A dedicated scheme, so a pairing code can never be mistaken for a
    /// bearer by either side, and so a stray `Bearer` header from a confused
    /// client cannot reach the pairing path.
    public static let pairingAuthorizationScheme = "UsageBar-Pair"

    private let authStore: any MobileSyncAuthStoring
    private let pairing: MobileSyncPairingSessionStore
    private let source: any UsageSyncSnapshotSource
    private let now: @Sendable () -> Date

    public init(
        authStore: any MobileSyncAuthStoring,
        pairing: MobileSyncPairingSessionStore,
        source: any UsageSyncSnapshotSource,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.authStore = authStore
        self.pairing = pairing
        self.source = source
        self.now = now
    }

    public func respond(to request: UsageSyncTransportRequest) -> UsageSyncTransportResponse {
        // Identity first, for every route including pairing. Without it there
        // is no evidence a tailnet user is calling at all, and the endpoint
        // must look identical to an unauthenticated prober whatever they ask
        // for — answering 404 or 405 first would disclose which routes exist.
        guard let identity = provenIdentity(in: request) else {
            return .forRejection(.unauthenticated)
        }

        switch (request.method, request.path) {
        case ("POST", Self.pairingPath):
            return pair(request, identity: identity)
        case ("GET", Self.snapshotPath):
            return snapshot(request, identity: identity)
        default:
            // An authenticated caller may be told the truth about routing; an
            // unauthenticated one never reaches here.
            return .forRejection(authorizes(request, identity: identity) ? .notFound : .unauthenticated)
        }
    }

    private func provenIdentity(in request: UsageSyncTransportRequest) -> String? {
        guard let raw = request.header(Self.identityHeader) else { return nil }
        return MobileSyncTailscaleIdentity.normalized(raw)
    }

    // MARK: - Snapshot

    private func snapshot(
        _ request: UsageSyncTransportRequest,
        identity: String
    ) -> UsageSyncTransportResponse {
        guard authorizes(request, identity: identity) else {
            return .forRejection(.unauthenticated)
        }
        do {
            let snapshot = try source.currentSnapshot()
            return .snapshot(try UsageSyncSerialization.encode(snapshot))
        } catch {
            return .forRejection(.snapshotUnavailable)
        }
    }

    /// Both factors, or nothing.
    ///
    /// A caller is told 401 whether the bearer was wrong, the identity was
    /// wrong, or the pairing has been revoked. Distinguishing them would tell
    /// someone holding a leaked token that the token itself is still good and
    /// only the identity is not — which is precisely the fact the binding
    /// exists to keep from them.
    private func authorizes(_ request: UsageSyncTransportRequest, identity: String) -> Bool {
        guard let record = authStore.load() else { return false }
        guard let authorization = request.header("Authorization"),
              authorization.hasPrefix("Bearer ") else { return false }
        let presented = String(authorization.dropFirst("Bearer ".count))
        return record.authorizes(bearer: presented, identity: identity)
    }

    // MARK: - Pairing

    private func pair(
        _ request: UsageSyncTransportRequest,
        identity: String
    ) -> UsageSyncTransportResponse {
        let prefix = Self.pairingAuthorizationScheme + " "
        guard let authorization = request.header("Authorization"),
              authorization.hasPrefix(prefix) else {
            return .forRejection(.unauthenticated)
        }
        let presented = String(authorization.dropFirst(prefix.count))
        guard let code = try? UsageBarPairingCode(decoding: presented) else {
            return .forRejection(.unauthenticated)
        }
        guard pairing.consume(presented: code, now: now()) == .paired else {
            return .forRejection(.unauthenticated)
        }

        // The session is already consumed at this point, so a failure below
        // costs the owner a new QR rather than leaving a live code behind.
        let bearer = MobileSyncBearer.generate()
        guard let identityDigest = MobileSyncTailscaleIdentity.digest(of: identity) else {
            return .forRejection(.unauthenticated)
        }
        let record = MobileSyncAuthRecord(
            bearerDigest: MobileSyncDigest.of(bearer),
            identityDigest: identityDigest,
            createdAt: now()
        )
        // Saving replaces any previous record, which is what rotates — and
        // therefore revokes — the credential a previously paired phone holds.
        guard (try? authStore.save(record)) != nil else {
            return .forRejection(.snapshotUnavailable)
        }

        return .pairingIssued(bearer: bearer)
    }
}

public extension UsageSyncTransportResponse {
    /// The one moment a raw bearer is on the wire.
    ///
    /// Two fields and nothing else: no identity, no hostname, no usage, no
    /// echo of what was presented. Every response already carries
    /// `Cache-Control: no-store`, so this body is not written to any
    /// intermediary's cache on the way back.
    static func pairingIssued(bearer: String) -> UsageSyncTransportResponse {
        let object: [String: Any] = ["schemaVersion": 1, "accessKey": bearer]
        guard let body = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]) else {
            return .forRejection(.snapshotUnavailable)
        }
        return UsageSyncTransportResponse(
            status: 200,
            reason: "OK",
            contentType: "application/json; charset=utf-8",
            body: body
        )
    }
}
