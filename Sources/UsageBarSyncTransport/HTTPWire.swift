import Foundation

/// A parsed request, reduced to the three things this service is allowed to
/// care about: method, path, and a lowercased header map.
///
/// There is deliberately no body property. The only route serves a GET, so a
/// body is drained and discarded rather than retained — nothing downstream can
/// accidentally act on caller-supplied content.
public struct UsageSyncTransportRequest: Equatable, Sendable {
    public let method: String
    public let path: String
    private let headers: [String: String]

    public init(method: String, path: String, headers: [String: String]) {
        self.method = method
        self.path = path
        self.headers = headers.reduce(into: [:]) { result, entry in
            result[entry.key.lowercased()] = entry.value
        }
    }

    /// Header lookup is case-insensitive, as HTTP requires.
    public func header(_ name: String) -> String? {
        headers[name.lowercased()]
    }
}

/// A response this service is willing to emit.
///
/// The set of bodies is closed: either the snapshot JSON, or one of a handful
/// of fixed generic strings. No error path can interpolate caller input, a file
/// path, an exception message or a provider string into a response.
public struct UsageSyncTransportResponse: Equatable, Sendable {
    public let status: Int
    public let reason: String
    public let contentType: String
    public let body: Data

    public init(status: Int, reason: String, contentType: String, body: Data) {
        self.status = status
        self.reason = reason
        self.contentType = contentType
        self.body = body
    }

    public static func snapshot(_ json: Data) -> UsageSyncTransportResponse {
        UsageSyncTransportResponse(
            status: 200,
            reason: "OK",
            contentType: "application/json; charset=utf-8",
            body: json
        )
    }

    /// One generic refusal shape for every failure. The status code is the only
    /// signal a caller gets; the body never narrows down *why*, so a probe
    /// cannot distinguish "no such route" from "route exists, bad credential"
    /// by reading it.
    public static func generic(status: Int, reason: String) -> UsageSyncTransportResponse {
        UsageSyncTransportResponse(
            status: status,
            reason: reason,
            contentType: "text/plain; charset=utf-8",
            body: Data("\(status)\n".utf8)
        )
    }

    public static func forRejection(_ rejection: UsageSyncTransportRejection) -> UsageSyncTransportResponse {
        switch rejection {
        case .malformedRequest:
            return .generic(status: 400, reason: "Bad Request")
        case .requestTooLarge:
            return .generic(status: 413, reason: "Payload Too Large")
        case .tooManyHeaders:
            return .generic(status: 431, reason: "Request Header Fields Too Large")
        case .unauthenticated:
            return .generic(status: 401, reason: "Unauthorized")
        case .methodNotAllowed:
            return .generic(status: 405, reason: "Method Not Allowed")
        case .notFound:
            return .generic(status: 404, reason: "Not Found")
        case .snapshotUnavailable:
            return .generic(status: 503, reason: "Service Unavailable")
        }
    }

    /// Renders the wire bytes.
    ///
    /// `Connection: close` is unconditional: the prototype serves one request
    /// per connection, which removes request-smuggling and pipelining as a
    /// class of concern rather than defending against them.
    public func serialized() -> Data {
        var head = "HTTP/1.1 \(status) \(reason)\r\n"
        head += "Content-Type: \(contentType)\r\n"
        head += "Content-Length: \(body.count)\r\n"
        head += "Cache-Control: no-store\r\n"
        head += "X-Content-Type-Options: nosniff\r\n"
        head += "Connection: close\r\n"
        if status == 401 {
            head += "WWW-Authenticate: Bearer\r\n"
        }
        head += "\r\n"
        var data = Data(head.utf8)
        data.append(body)
        return data
    }
}

/// Parses a request head under the configured limits.
///
/// The parser is intentionally narrow. It understands the request line and
/// `name: value` headers and nothing else — no continuation lines, no
/// pipelining, no chunked decoding. Anything it does not understand is a
/// `malformedRequest`, never a best-effort interpretation.
public enum UsageSyncTransportRequestParser {
    public static func parse(
        head: Data,
        limits: UsageSyncTransportLimits
    ) throws -> UsageSyncTransportRequest {
        guard let text = String(data: head, encoding: .utf8) else {
            throw UsageSyncTransportRejection.malformedRequest
        }

        var lines = text.components(separatedBy: "\r\n")
        // A well-formed head ends with the blank line that terminated it.
        if lines.last == "" { lines.removeLast() }
        guard let requestLine = lines.first, !requestLine.isEmpty else {
            throw UsageSyncTransportRejection.malformedRequest
        }
        guard requestLine.utf8.count <= limits.maxRequestLineBytes else {
            throw UsageSyncTransportRejection.requestTooLarge
        }

        let parts = requestLine.split(separator: " ", omittingEmptySubsequences: false)
        guard parts.count == 3 else {
            throw UsageSyncTransportRejection.malformedRequest
        }
        let method = String(parts[0])
        let target = String(parts[1])
        let version = String(parts[2])
        guard version == "HTTP/1.1" || version == "HTTP/1.0" else {
            throw UsageSyncTransportRejection.malformedRequest
        }
        guard !method.isEmpty, method.allSatisfy({ $0.isUppercase && $0.isLetter }) else {
            throw UsageSyncTransportRejection.malformedRequest
        }
        guard target.hasPrefix("/") else {
            throw UsageSyncTransportRejection.malformedRequest
        }

        let headerLines = lines.dropFirst()
        guard headerLines.count <= limits.maxHeaderCount else {
            throw UsageSyncTransportRejection.tooManyHeaders
        }

        var headers: [String: String] = [:]
        for line in headerLines {
            guard line.utf8.count <= limits.maxHeaderLineBytes else {
                throw UsageSyncTransportRejection.requestTooLarge
            }
            guard let separator = line.firstIndex(of: ":") else {
                throw UsageSyncTransportRejection.malformedRequest
            }
            let name = String(line[line.startIndex..<separator])
            guard !name.isEmpty, !name.contains(" ") else {
                throw UsageSyncTransportRejection.malformedRequest
            }
            let value = String(line[line.index(after: separator)...])
                .trimmingCharacters(in: .whitespaces)
            // A duplicated header is ambiguous, and ambiguity at an auth
            // boundary is a vulnerability: reject rather than pick one.
            if headers[name.lowercased()] != nil {
                throw UsageSyncTransportRejection.malformedRequest
            }
            headers[name.lowercased()] = value
        }

        // Strip any query string; the only route takes no parameters.
        let path = target.split(separator: "?", maxSplits: 1).first.map(String.init) ?? target
        return UsageSyncTransportRequest(method: method, path: path, headers: headers)
    }
}
