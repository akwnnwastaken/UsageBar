import Foundation

/// Hard ceilings applied to every request before any of it is interpreted.
///
/// The prototype answers exactly one small, unauthenticated-by-default GET, so
/// every limit here is deliberately far below what a general-purpose server
/// would allow. A request that exceeds any of them is refused without being
/// parsed further: the cheapest way to not mishandle hostile input is to stop
/// reading it.
public struct UsageSyncTransportLimits: Sendable, Equatable {
    /// Total bytes accepted from one connection, headers and body together.
    public let maxRequestBytes: Int

    /// Bytes accepted for the request line (`GET /v1/snapshot HTTP/1.1`).
    public let maxRequestLineBytes: Int

    /// Bytes accepted for any single header line.
    public let maxHeaderLineBytes: Int

    /// Number of header lines accepted.
    public let maxHeaderCount: Int

    /// Seconds a connection may stay idle mid-request before it is dropped.
    /// Without this a peer that opens a socket and says nothing would hold a
    /// handler thread indefinitely.
    public let readTimeoutSeconds: Int

    public init(
        maxRequestBytes: Int = 8_192,
        maxRequestLineBytes: Int = 1_024,
        maxHeaderLineBytes: Int = 1_024,
        maxHeaderCount: Int = 48,
        readTimeoutSeconds: Int = 5
    ) {
        self.maxRequestBytes = maxRequestBytes
        self.maxRequestLineBytes = maxRequestLineBytes
        self.maxHeaderLineBytes = maxHeaderLineBytes
        self.maxHeaderCount = maxHeaderCount
        self.readTimeoutSeconds = readTimeoutSeconds
    }

    public static let `default` = UsageSyncTransportLimits()
}

/// Why a request was refused.
///
/// These cases exist so the *server* can reason about failures; they are never
/// rendered into a response body. Every rejection leaves as a generic status
/// line and a fixed short reason, because a precise error is a free oracle for
/// anyone probing the endpoint.
public enum UsageSyncTransportRejection: Error, Equatable, Sendable {
    case malformedRequest
    case requestTooLarge
    case tooManyHeaders
    case unauthenticated
    case methodNotAllowed
    case notFound
    case snapshotUnavailable
}
