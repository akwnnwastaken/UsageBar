import Foundation
import Darwin

/// A minimal HTTP/1.1 listener bound to the loopback interface and nothing else.
///
/// Loopback-only is a security requirement, not a convenience. Tailscale Serve
/// authenticates the caller and injects the identity header, but those headers
/// are only trustworthy because Serve is the sole path to the backend: a
/// service listening on a routable interface could be called directly by
/// anyone on the LAN or tailnet, who would then supply whatever identity header
/// they liked. Binding to 127.0.0.1 is what makes the header meaningful, so the
/// bind address is fixed in code and cannot be configured outward.
public final class UsageSyncLoopbackHTTPServer: @unchecked Sendable {
    public enum StartFailure: Error, CustomStringConvertible {
        case socketCreationFailed(errno: Int32)
        case bindFailed(errno: Int32)
        case listenFailed(errno: Int32)
        case portLookupFailed(errno: Int32)

        public var description: String {
            switch self {
            case .socketCreationFailed(let code): return "socket() failed (errno \(code))"
            case .bindFailed(let code): return "bind() to loopback failed (errno \(code))"
            case .listenFailed(let code): return "listen() failed (errno \(code))"
            case .portLookupFailed(let code): return "getsockname() failed (errno \(code))"
            }
        }
    }

    /// The only address this server will ever bind: 127.0.0.1.
    public static let loopbackAddress = "127.0.0.1"

    private let limits: UsageSyncTransportLimits
    private let handler: @Sendable (UsageSyncTransportRequest) -> UsageSyncTransportResponse
    private let rejectionHandler: @Sendable (UsageSyncTransportRejection) -> UsageSyncTransportResponse

    private var listenerFD: Int32 = -1
    private let stateLock = NSLock()
    private var running = false
    private var acceptQueue: DispatchQueue?
    private let connectionQueue = DispatchQueue(
        label: "local.codex.usagebar.sync-transport.connections",
        attributes: .concurrent
    )

    public private(set) var boundPort: UInt16 = 0

    public init(
        limits: UsageSyncTransportLimits = .default,
        handler: @escaping @Sendable (UsageSyncTransportRequest) -> UsageSyncTransportResponse,
        rejectionHandler: @escaping @Sendable (UsageSyncTransportRejection) -> UsageSyncTransportResponse = {
            UsageSyncTransportResponse.forRejection($0)
        }
    ) {
        self.limits = limits
        self.handler = handler
        self.rejectionHandler = rejectionHandler
    }

    /// Binds and begins accepting. Passing port 0 asks the kernel for an
    /// ephemeral port, which is what the tests and the probe use so a run can
    /// never collide with an unrelated service.
    public func start(port: UInt16 = 0) throws {
        stateLock.lock()
        defer { stateLock.unlock() }
        guard !running else { return }

        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { throw StartFailure.socketCreationFailed(errno: errno) }

        var reuse: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))

        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = port.bigEndian
        // INADDR_LOOPBACK, and only INADDR_LOOPBACK.
        address.sin_addr.s_addr = UInt32(0x7f00_0001).bigEndian

        let bound = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { raw in
                Darwin.bind(fd, raw, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bound == 0 else {
            let code = errno
            close(fd)
            throw StartFailure.bindFailed(errno: code)
        }

        guard Darwin.listen(fd, 8) == 0 else {
            let code = errno
            close(fd)
            throw StartFailure.listenFailed(errno: code)
        }

        var actual = sockaddr_in()
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let looked = withUnsafeMutablePointer(to: &actual) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { raw in
                getsockname(fd, raw, &length)
            }
        }
        guard looked == 0 else {
            let code = errno
            close(fd)
            throw StartFailure.portLookupFailed(errno: code)
        }

        listenerFD = fd
        boundPort = UInt16(bigEndian: actual.sin_port)
        running = true

        let queue = DispatchQueue(label: "local.codex.usagebar.sync-transport.accept")
        acceptQueue = queue
        queue.async { [weak self] in self?.acceptLoop(fd: fd) }
    }

    public func stop() {
        stateLock.lock()
        let fd = listenerFD
        running = false
        listenerFD = -1
        stateLock.unlock()
        if fd >= 0 { close(fd) }
    }

    /// The address the socket is actually bound to, read back from the kernel.
    ///
    /// Tests assert on this rather than on the constant above: the point is to
    /// prove what the kernel did, not to re-read our own intent.
    public func boundAddressDescription() -> String? {
        stateLock.lock()
        let fd = listenerFD
        stateLock.unlock()
        guard fd >= 0 else { return nil }

        var actual = sockaddr_in()
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let looked = withUnsafeMutablePointer(to: &actual) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { raw in
                getsockname(fd, raw, &length)
            }
        }
        guard looked == 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
        var inAddr = actual.sin_addr
        guard inet_ntop(AF_INET, &inAddr, &buffer, socklen_t(INET_ADDRSTRLEN)) != nil else {
            return nil
        }
        return String(cString: buffer)
    }

    private func acceptLoop(fd: Int32) {
        while true {
            stateLock.lock()
            let stillRunning = running
            stateLock.unlock()
            guard stillRunning else { return }

            var peer = sockaddr_in()
            var length = socklen_t(MemoryLayout<sockaddr_in>.size)
            let client = withUnsafeMutablePointer(to: &peer) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { raw in
                    Darwin.accept(fd, raw, &length)
                }
            }
            guard client >= 0 else {
                if errno == EINTR { continue }
                return
            }
            connectionQueue.async { [weak self] in
                self?.serve(client: client)
            }
        }
    }

    private func serve(client: Int32) {
        defer { close(client) }

        var timeout = timeval(tv_sec: limits.readTimeoutSeconds, tv_usec: 0)
        setsockopt(client, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(client, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))

        let response: UsageSyncTransportResponse
        do {
            let received = try readHead(client: client)
            let request = try UsageSyncTransportRequestParser.parse(
                head: received.head,
                limits: limits
            )
            try drainBody(client: client, request: request, alreadyRead: received.bodyPrefixCount)
            response = handler(request)
        } catch let rejection as UsageSyncTransportRejection {
            response = rejectionHandler(rejection)
        } catch {
            response = rejectionHandler(.malformedRequest)
        }

        write(client: client, data: response.serialized())
        // Half-close so the peer reliably sees the response even when it sent a
        // body we chose not to consume.
        shutdown(client, SHUT_WR)
    }

    private struct ReceivedHead {
        let head: Data
        /// Body bytes that arrived in the same read as the head. They are
        /// counted, not kept: forgetting them would make `drainBody` wait for
        /// bytes the socket has already delivered, and stall until the receive
        /// timeout.
        let bodyPrefixCount: Int
    }

    /// Reads until the blank line that ends the head, never past the byte
    /// budget. A peer that never sends the terminator hits either the budget or
    /// the receive timeout.
    private func readHead(client: Int32) throws -> ReceivedHead {
        var accumulated = Data()
        var chunk = [UInt8](repeating: 0, count: 1_024)

        while true {
            if let range = accumulated.range(of: Data("\r\n\r\n".utf8)) {
                return ReceivedHead(
                    head: accumulated.subdata(in: accumulated.startIndex..<range.lowerBound),
                    bodyPrefixCount: accumulated.distance(
                        from: range.upperBound,
                        to: accumulated.endIndex
                    )
                )
            }
            guard accumulated.count <= limits.maxRequestBytes else {
                throw UsageSyncTransportRejection.requestTooLarge
            }
            let read = Darwin.read(client, &chunk, chunk.count)
            if read > 0 {
                accumulated.append(contentsOf: chunk[0..<read])
                continue
            }
            if read == 0 { throw UsageSyncTransportRejection.malformedRequest }
            if errno == EINTR { continue }
            throw UsageSyncTransportRejection.malformedRequest
        }
    }

    /// Consumes and discards a declared body.
    ///
    /// The body is never handed to the service — no route accepts one — but a
    /// bounded drain lets the peer finish writing so it can read the response
    /// instead of seeing a reset.
    private func drainBody(
        client: Int32,
        request: UsageSyncTransportRequest,
        alreadyRead: Int
    ) throws {
        guard let declared = request.header("Content-Length") else { return }
        guard let length = Int(declared), length >= 0 else {
            throw UsageSyncTransportRejection.malformedRequest
        }
        guard length <= limits.maxRequestBytes else {
            throw UsageSyncTransportRejection.requestTooLarge
        }
        var remaining = max(length - alreadyRead, 0)
        var chunk = [UInt8](repeating: 0, count: 1_024)
        while remaining > 0 {
            let read = Darwin.read(client, &chunk, min(chunk.count, remaining))
            if read > 0 { remaining -= read; continue }
            if read == 0 { return }
            if errno == EINTR { continue }
            return
        }
    }

    private func write(client: Int32, data: Data) {
        data.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return }
            var offset = 0
            while offset < raw.count {
                let written = Darwin.write(client, base.advanced(by: offset), raw.count - offset)
                if written > 0 { offset += written; continue }
                if written < 0 && errno == EINTR { continue }
                return
            }
        }
    }
}
