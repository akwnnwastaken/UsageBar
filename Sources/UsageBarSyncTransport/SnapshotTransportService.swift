import Foundation
import UsageBarSync

/// The request policy for the mobile sync endpoint.
///
/// This type is pure: a request in, a response out, no sockets. Keeping the
/// policy separable from the listener is what lets every authentication and
/// routing rule below be tested directly, without a network.
public struct UsageSyncTransportService: Sendable {
    /// The only route. Versioned in the path so a future schema-v2 endpoint can
    /// be served alongside this one rather than silently replacing it.
    public static let snapshotPath = "/v1/snapshot"

    /// The identity header Tailscale Serve injects for a tailnet user.
    ///
    /// Its *presence* is what is required. The prototype does not
    /// allowlist a particular login, because binding the endpoint to one
    /// account is a grants-policy decision — see
    /// `docs/mobile-transport-grants-plan.md` — and encoding it here would
    /// quietly answer a question that belongs in reviewed tailnet policy.
    public static let identityHeader = "Tailscale-User-Login"

    private let secret: UsageSyncTransportSecret
    private let source: any UsageSyncSnapshotSource
    private let limits: UsageSyncTransportLimits

    public init(
        secret: UsageSyncTransportSecret,
        source: any UsageSyncSnapshotSource,
        limits: UsageSyncTransportLimits = .default
    ) {
        self.secret = secret
        self.source = source
        self.limits = limits
    }

    public func respond(to request: UsageSyncTransportRequest) -> UsageSyncTransportResponse {
        do {
            try authenticate(request)
            guard request.method == "GET" else {
                throw UsageSyncTransportRejection.methodNotAllowed
            }
            guard request.path == Self.snapshotPath else {
                throw UsageSyncTransportRejection.notFound
            }
            return try snapshotResponse()
        } catch let rejection as UsageSyncTransportRejection {
            return .forRejection(rejection)
        } catch {
            return .forRejection(.snapshotUnavailable)
        }
    }

    /// Authentication runs *before* routing and method checks on purpose.
    ///
    /// The alternative ordering would answer 404 or 405 to an unauthenticated
    /// caller, which discloses which paths and methods exist. Refusing
    /// everything with an identical 401 until both factors are satisfied means
    /// an unauthorized prober learns nothing about the surface behind it.
    private func authenticate(_ request: UsageSyncTransportRequest) throws {
        // Factor one: Serve proved a tailnet user is calling.
        guard let login = request.header(Self.identityHeader),
              !login.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw UsageSyncTransportRejection.unauthenticated
        }

        // Factor two: the caller holds this run's secret.
        guard let authorization = request.header("Authorization") else {
            throw UsageSyncTransportRejection.unauthenticated
        }
        let expectedPrefix = "Bearer "
        guard authorization.hasPrefix(expectedPrefix) else {
            throw UsageSyncTransportRejection.unauthenticated
        }
        let presented = String(authorization.dropFirst(expectedPrefix.count))
        guard secret.matches(presented) else {
            throw UsageSyncTransportRejection.unauthenticated
        }
    }

    /// Builds the body.
    ///
    /// `UsageSyncSerialization.encode` validates before encoding, so an invalid
    /// snapshot becomes a 503 rather than bytes on the wire. Serving a payload
    /// the validator would reject is the one outcome worth failing loudly for:
    /// the phone treats what arrives as authoritative.
    private func snapshotResponse() throws -> UsageSyncTransportResponse {
        let snapshot = try source.currentSnapshot()
        let json = try UsageSyncSerialization.encode(snapshot)
        return .snapshot(json)
    }

    public var configuredLimits: UsageSyncTransportLimits { limits }
}
