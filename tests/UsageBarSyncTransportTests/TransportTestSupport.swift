import Foundation
import XCTest
@testable import UsageBarSyncTransport

/// A raw-socket HTTP client.
///
/// Deliberately not URLSession: these tests must send malformed request lines,
/// oversized heads, duplicated headers and bodies that contradict their own
/// Content-Length. A well-behaved client library would normalize or refuse to
/// send exactly the inputs worth testing.
struct RawHTTPClient {
    struct Response {
        let status: Int
        let headers: [String: String]
        let body: Data
    }

    enum ClientError: Error {
        case connectFailed(errno: Int32)
        case connectTimedOut
        case noResponse
        case malformedResponse
    }

    let port: UInt16
    var host: String = "127.0.0.1"
    /// Bounded so a dropped (rather than refused) SYN fails the test in
    /// seconds instead of waiting out the kernel's full TCP retry schedule.
    var connectTimeoutSeconds: Int32 = 3

    func send(raw: String) throws -> Response {
        try send(raw: Data(raw.utf8))
    }

    func send(raw: Data) throws -> Response {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { throw ClientError.connectFailed(errno: errno) }
        defer { close(fd) }

        var timeout = timeval(tv_sec: 5, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))

        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = port.bigEndian
        guard inet_pton(AF_INET, host, &address.sin_addr) == 1 else {
            throw ClientError.connectFailed(errno: errno)
        }

        try Self.connectWithTimeout(
            fd: fd,
            address: &address,
            timeoutSeconds: connectTimeoutSeconds
        )

        try raw.withUnsafeBytes { buffer in
            guard let base = buffer.baseAddress else { return }
            var offset = 0
            while offset < buffer.count {
                let written = Darwin.write(fd, base.advanced(by: offset), buffer.count - offset)
                if written > 0 { offset += written; continue }
                if written < 0 && errno == EINTR { continue }
                throw ClientError.noResponse
            }
        }

        var accumulated = Data()
        var chunk = [UInt8](repeating: 0, count: 4_096)
        while true {
            let read = Darwin.read(fd, &chunk, chunk.count)
            if read > 0 { accumulated.append(contentsOf: chunk[0..<read]); continue }
            if read < 0 && errno == EINTR { continue }
            break
        }
        guard !accumulated.isEmpty else { throw ClientError.noResponse }
        return try Self.parse(accumulated)
    }

    /// Convenience for well-formed requests.
    func request(
        method: String = "GET",
        path: String = UsageSyncTransportService.snapshotPath,
        headers: [(String, String)] = [],
        body: String? = nil
    ) throws -> Response {
        var text = "\(method) \(path) HTTP/1.1\r\nHost: 127.0.0.1\r\n"
        for (name, value) in headers {
            text += "\(name): \(value)\r\n"
        }
        if let body {
            text += "Content-Length: \(body.utf8.count)\r\n"
        }
        text += "\r\n"
        if let body { text += body }
        return try send(raw: text)
    }

    /// Non-blocking connect plus `poll`, so an unreachable address fails fast.
    private static func connectWithTimeout(
        fd: Int32,
        address: inout sockaddr_in,
        timeoutSeconds: Int32
    ) throws {
        let flags = fcntl(fd, F_GETFL, 0)
        _ = fcntl(fd, F_SETFL, flags | O_NONBLOCK)
        defer { _ = fcntl(fd, F_SETFL, flags) }

        let started = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { rawAddr in
                Darwin.connect(fd, rawAddr, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        if started == 0 { return }
        guard errno == EINPROGRESS else {
            throw ClientError.connectFailed(errno: errno)
        }

        var descriptor = pollfd(fd: fd, events: Int16(POLLOUT), revents: 0)
        let ready = poll(&descriptor, 1, timeoutSeconds * 1_000)
        guard ready > 0 else {
            throw ready == 0 ? ClientError.connectTimedOut : ClientError.connectFailed(errno: errno)
        }

        var socketError: Int32 = 0
        var length = socklen_t(MemoryLayout<Int32>.size)
        guard getsockopt(fd, SOL_SOCKET, SO_ERROR, &socketError, &length) == 0,
              socketError == 0 else {
            throw ClientError.connectFailed(errno: socketError)
        }
    }

    private static func parse(_ data: Data) throws -> Response {
        guard let separator = data.range(of: Data("\r\n\r\n".utf8)) else {
            throw ClientError.malformedResponse
        }
        let headData = data.subdata(in: data.startIndex..<separator.lowerBound)
        let body = data.subdata(in: separator.upperBound..<data.endIndex)
        guard let headText = String(data: headData, encoding: .utf8) else {
            throw ClientError.malformedResponse
        }
        var lines = headText.components(separatedBy: "\r\n")
        guard !lines.isEmpty else { throw ClientError.malformedResponse }
        let statusLine = lines.removeFirst()
        let parts = statusLine.split(separator: " ", omittingEmptySubsequences: false)
        guard parts.count >= 2, let status = Int(parts[1]) else {
            throw ClientError.malformedResponse
        }
        var headers: [String: String] = [:]
        for line in lines where !line.isEmpty {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let name = String(line[line.startIndex..<colon]).lowercased()
            headers[name] = String(line[line.index(after: colon)...])
                .trimmingCharacters(in: .whitespaces)
        }
        return Response(status: status, headers: headers, body: body)
    }
}

/// A 32-byte secret with a known value, so tests can present a correct bearer.
let testSecretValue = String(repeating: "a", count: 64)

func makeTestSecret() throws -> UsageSyncTransportSecret {
    try UsageSyncTransportSecret.fromString(testSecretValue)
}

func validHeaders(bearer: String = testSecretValue) -> [(String, String)] {
    [
        (UsageSyncTransportService.identityHeader, "tester@example.invalid"),
        ("Authorization", "Bearer \(bearer)")
    ]
}

/// Starts a server for the duration of one test and guarantees it is stopped.
func withRunningServer(
    limits: UsageSyncTransportLimits = .default,
    source: any UsageSyncSnapshotSource = UsageSyncSyntheticSnapshotSource(),
    _ body: (UsageSyncLoopbackHTTPServer, RawHTTPClient) throws -> Void
) throws {
    let service = UsageSyncTransportService(
        secret: try makeTestSecret(),
        source: source,
        limits: limits
    )
    let server = UsageSyncLoopbackHTTPServer(limits: limits) { request in
        service.respond(to: request)
    }
    try server.start()
    defer { server.stop() }
    try body(server, RawHTTPClient(port: server.boundPort))
}
