import Foundation
import Network

public struct MacLocalUsageAPIConfiguration: Equatable {
    public static let productionPort: UInt16 = 54_132
    public static let production = MacLocalUsageAPIConfiguration(port: productionPort)

    public let address: String
    public let port: UInt16

    init(port: UInt16) {
        address = "127.0.0.1"
        self.port = port
    }

    var networkPort: NWEndpoint.Port {
        NWEndpoint.Port(rawValue: port) ?? .any
    }

    func expectedHost(boundPort: UInt16) -> String {
        "\(address):\(boundPort)"
    }
}

public enum MacLocalUsageAPIListenerState: Equatable {
    case stopped
    case starting
    case listening
    case failed
    case stopping
}

public enum MacLocalUsageAPIDiagnostic: String, Equatable {
    case listenerStarted = "listener_started"
    case listenerBindFailed = "listener_bind_failed"
    case listenerFailed = "listener_failed"
    case listenerStopped = "listener_stopped"
    case requestRejected = "request_rejected"
    case requestRateLimited = "request_rate_limited"
    case snapshotUnavailable = "snapshot_unavailable"
}

public final class MacLocalUsageAPIListener {
    public typealias SnapshotProvider = (Date, @escaping (Result<Data, Error>) -> Void) -> Void
    public typealias StateHandler = (MacLocalUsageAPIListenerState) -> Void
    public typealias DiagnosticHandler = (MacLocalUsageAPIDiagnostic) -> Void

    private let configuration: MacLocalUsageAPIConfiguration
    private let queue: DispatchQueue
    private let wallNow: () -> Date
    private let monotonicNow: () -> TimeInterval
    private let snapshotProvider: SnapshotProvider
    private let diagnosticHandler: DiagnosticHandler
    private let listenerFactory: (NWParameters, NWEndpoint.Port) throws -> NWListener
    private let stateLock = NSLock()
    private var storedState: MacLocalUsageAPIListenerState = .stopped
    private var storedBoundPort: UInt16?
    private var listener: NWListener?
    private var sessions: [ObjectIdentifier: LocalUsageAPIConnectionSession] = [:]
    private var stopCompletions: [() -> Void] = []
    private let connectionGate = LocalUsageAPIActiveConnectionGate(maximum: 4)
    private let tokenBucket: LocalUsageAPITokenBucket
    private var stateHandler: StateHandler?

    public convenience init(
        configuration: MacLocalUsageAPIConfiguration = .production,
        wallNow: @escaping () -> Date = Date.init,
        monotonicNow: @escaping () -> TimeInterval = {
            TimeInterval(DispatchTime.now().uptimeNanoseconds) / 1_000_000_000
        },
        snapshotProvider: @escaping SnapshotProvider,
        diagnosticHandler: @escaping DiagnosticHandler = { _ in }
    ) {
        self.init(
            configuration: configuration,
            wallNow: wallNow,
            monotonicNow: monotonicNow,
            snapshotProvider: snapshotProvider,
            diagnosticHandler: diagnosticHandler,
            listenerFactory: { parameters, _ in
                try NWListener(using: parameters)
            }
        )
    }

    init(
        configuration: MacLocalUsageAPIConfiguration,
        wallNow: @escaping () -> Date,
        monotonicNow: @escaping () -> TimeInterval,
        snapshotProvider: @escaping SnapshotProvider,
        diagnosticHandler: @escaping DiagnosticHandler,
        listenerFactory: @escaping (NWParameters, NWEndpoint.Port) throws -> NWListener
    ) {
        self.configuration = configuration
        queue = DispatchQueue(label: "UsageBar.LocalUsageAPI")
        self.wallNow = wallNow
        self.monotonicNow = monotonicNow
        self.snapshotProvider = snapshotProvider
        self.diagnosticHandler = diagnosticHandler
        self.listenerFactory = listenerFactory
        tokenBucket = LocalUsageAPITokenBucket(initialMonotonicTime: monotonicNow())
    }

    public var state: MacLocalUsageAPIListenerState {
        stateLock.lock()
        defer { stateLock.unlock() }
        return storedState
    }

    public var boundPort: UInt16? {
        stateLock.lock()
        defer { stateLock.unlock() }
        return storedBoundPort
    }

    public func onStateChange(_ handler: StateHandler?) {
        queue.async {
            self.stateHandler = handler
            if let handler {
                handler(self.state)
            }
        }
    }

    public func start() {
        queue.async {
            guard self.state == .stopped else { return }
            self.transition(to: .starting)

            let parameters = NWParameters.tcp
            parameters.requiredLocalEndpoint = .hostPort(
                host: .ipv4(.loopback),
                port: self.configuration.networkPort
            )
            parameters.allowLocalEndpointReuse = false
            parameters.acceptLocalOnly = true

            do {
                let listener = try self.listenerFactory(parameters, self.configuration.networkPort)
                listener.stateUpdateHandler = { [weak self, weak listener] state in
                    guard let self, let listener else { return }
                    self.queue.async {
                        self.handleListenerState(state, listener: listener)
                    }
                }
                listener.newConnectionHandler = { [weak self] connection in
                    self?.queue.async {
                        self?.accept(connection)
                    }
                }
                self.listener = listener
                listener.start(queue: self.queue)
            } catch {
                self.listener = nil
                self.transition(to: .failed)
                self.diagnosticHandler(.listenerBindFailed)
            }
        }
    }

    public func stop(completion: (() -> Void)? = nil) {
        queue.async {
            switch self.state {
            case .stopped:
                completion?()
            case .failed:
                self.cancelAllSessions()
                self.listener?.cancel()
                self.listener = nil
                self.setBoundPort(nil)
                completion?()
            case .stopping:
                if let completion { self.stopCompletions.append(completion) }
            case .starting, .listening:
                if let completion { self.stopCompletions.append(completion) }
                self.transition(to: .stopping)
                self.cancelAllSessions()
                guard let listener = self.listener else {
                    self.finishStopping()
                    return
                }
                listener.cancel()
                self.queue.asyncAfter(deadline: .now() + 2) { [weak self, weak listener] in
                    guard let self, let listener,
                          self.state == .stopping,
                          self.listener === listener
                    else { return }
                    self.finishStopping()
                }
            }
        }
    }

    public func stopAndWait(timeout: TimeInterval = 2) {
        let stopped = DispatchSemaphore(value: 0)
        stop { stopped.signal() }
        _ = stopped.wait(timeout: .now() + timeout)
    }

    private func handleListenerState(_ newState: NWListener.State, listener: NWListener) {
        guard self.listener === listener else { return }
        switch newState {
        case .ready:
            guard state == .starting, let port = listener.port else {
                failListener(.listenerFailed)
                return
            }
            setBoundPort(port.rawValue)
            transition(to: .listening)
            diagnosticHandler(.listenerStarted)
        case .failed:
            if state == .stopping {
                finishStopping()
            } else {
                failListener(.listenerBindFailed)
            }
        case .cancelled:
            if state == .stopping {
                finishStopping()
            } else if state != .stopped && state != .failed {
                failListener(.listenerFailed)
            }
        case .setup, .waiting:
            break
        @unknown default:
            failListener(.listenerFailed)
        }
    }

    private func failListener(_ diagnostic: MacLocalUsageAPIDiagnostic) {
        cancelAllSessions()
        let failedListener = listener
        listener = nil
        failedListener?.cancel()
        setBoundPort(nil)
        transition(to: .failed)
        diagnosticHandler(diagnostic)
    }

    private func finishStopping() {
        listener = nil
        setBoundPort(nil)
        transition(to: .stopped)
        diagnosticHandler(.listenerStopped)
        let completions = stopCompletions
        stopCompletions.removeAll()
        completions.forEach { $0() }
    }

    private func accept(_ connection: NWConnection) {
        guard state == .listening, let boundPort else {
            connection.forceCancel()
            return
        }
        // Concurrency admission happens before allocating a session. Because an
        // over-limit peer has not supplied a validated HTTP request yet, it is
        // closed rather than receiving a response. The process-wide rate limit
        // is applied only after strict parsing, when a safe 429 can be emitted.
        guard connectionGate.acquire() else {
            connection.forceCancel()
            return
        }

        let key = ObjectIdentifier(connection)
        let processor = LocalUsageAPIRequestProcessor(
            expectedHost: configuration.expectedHost(boundPort: boundPort),
            wallNow: wallNow,
            snapshotProvider: snapshotProvider
        )
        let session = LocalUsageAPIConnectionSession(
            connection: connection,
            expectedLocalPort: boundPort,
            queue: queue,
            parser: StrictHTTPRequestParser(expectedHost: configuration.expectedHost(boundPort: boundPort)),
            processor: processor,
            tokenBucket: tokenBucket,
            monotonicNow: monotonicNow,
            scheduler: DispatchLocalUsageAPIDeadlineScheduler(queue: queue),
            diagnosticHandler: diagnosticHandler
        ) { [weak self] in
            guard let self else { return }
            self.sessions.removeValue(forKey: key)
            self.connectionGate.release()
        }
        sessions[key] = session
        session.start()
    }

    private func cancelAllSessions() {
        let current = Array(sessions.values)
        current.forEach { $0.cancel() }
        sessions.removeAll()
    }

    private func transition(to state: MacLocalUsageAPIListenerState) {
        stateLock.lock()
        storedState = state
        stateLock.unlock()
        stateHandler?(state)
    }

    private func setBoundPort(_ port: UInt16?) {
        stateLock.lock()
        storedBoundPort = port
        stateLock.unlock()
    }
}

private final class LocalUsageAPIConnectionSession {
    private let connection: NWConnection
    private let expectedLocalPort: UInt16
    private let queue: DispatchQueue
    private let parser: StrictHTTPRequestParser
    private let processor: LocalUsageAPIRequestProcessor
    private let tokenBucket: LocalUsageAPITokenBucket
    private let monotonicNow: () -> TimeInterval
    private let scheduler: LocalUsageAPIDeadlineScheduling
    private let diagnosticHandler: MacLocalUsageAPIListener.DiagnosticHandler
    private let onFinish: () -> Void
    private var buffer = Data()
    private lazy var readDeadline = LocalUsageAPIAbsoluteDeadline(delay: 2, scheduler: scheduler)
    private lazy var writeDeadline = LocalUsageAPIAbsoluteDeadline(delay: 2, scheduler: scheduler)
    private var finished = false

    init(
        connection: NWConnection,
        expectedLocalPort: UInt16,
        queue: DispatchQueue,
        parser: StrictHTTPRequestParser,
        processor: LocalUsageAPIRequestProcessor,
        tokenBucket: LocalUsageAPITokenBucket,
        monotonicNow: @escaping () -> TimeInterval,
        scheduler: LocalUsageAPIDeadlineScheduling,
        diagnosticHandler: @escaping MacLocalUsageAPIListener.DiagnosticHandler,
        onFinish: @escaping () -> Void
    ) {
        self.connection = connection
        self.expectedLocalPort = expectedLocalPort
        self.queue = queue
        self.parser = parser
        self.processor = processor
        self.tokenBucket = tokenBucket
        self.monotonicNow = monotonicNow
        self.scheduler = scheduler
        self.diagnosticHandler = diagnosticHandler
        self.onFinish = onFinish
    }

    func start() {
        connection.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            self.queue.async {
                self.handleConnectionState(state)
            }
        }
        connection.start(queue: queue)
    }

    func cancel() {
        guard !finished else { return }
        connection.cancel()
        finish()
    }

    private func handleConnectionState(_ state: NWConnection.State) {
        guard !finished else { return }
        switch state {
        case .ready:
            guard isApprovedPath(connection.currentPath) else {
                connection.forceCancel()
                finish()
                return
            }
            readDeadline.start { [weak self] in
                self?.cancel()
            }
            receiveMore()
        case .failed, .cancelled:
            finish()
        case .setup, .preparing, .waiting:
            break
        @unknown default:
            cancel()
        }
    }

    private func receiveMore() {
        guard !finished else { return }
        let remaining = StrictHTTPRequestParser.maximumBufferedRequestBytes - buffer.count
        guard remaining > 0 else {
            send(processor.response(status: .requestHeaderFieldsTooLarge))
            return
        }
        connection.receive(minimumIncompleteLength: 1, maximumLength: remaining) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            self.queue.async {
                guard !self.finished else { return }
                if let data { self.buffer.append(data) }
                if error != nil {
                    self.finish()
                    return
                }
                switch self.parser.parse(self.buffer) {
                case .incomplete:
                    if isComplete {
                        self.readDeadline.cancel()
                        self.send(self.processor.response(status: .badRequest))
                    } else {
                        self.receiveMore()
                    }
                case let .rejected(status):
                    self.readDeadline.cancel()
                    self.diagnosticHandler(.requestRejected)
                    self.send(self.processor.response(status: status))
                case .accepted:
                    self.readDeadline.cancel()
                    guard self.tokenBucket.admit(at: self.monotonicNow()) else {
                        self.diagnosticHandler(.requestRateLimited)
                        self.send(self.processor.response(status: .tooManyRequests))
                        return
                    }
                    _ = self.processor.process(self.buffer) { [weak self] response in
                        guard let self else { return }
                        self.queue.async {
                            if Self.statusCode(in: response) == LocalUsageAPIHTTPStatus.serviceUnavailable.rawValue {
                                self.diagnosticHandler(.snapshotUnavailable)
                            }
                            self.send(response)
                        }
                    }
                }
            }
        }
    }

    private func send(_ response: Data) {
        guard !finished else { return }
        writeDeadline.cancel()
        writeDeadline.start { [weak self] in
            self?.cancel()
        }
        connection.send(content: response, contentContext: .finalMessage, isComplete: true, completion: .contentProcessed { [weak self] _ in
            guard let self else { return }
            self.queue.async {
                self.writeDeadline.cancel()
                self.connection.cancel()
                self.finish()
            }
        })
    }

    private func finish() {
        guard !finished else { return }
        finished = true
        readDeadline.cancel()
        writeDeadline.cancel()
        connection.stateUpdateHandler = nil
        onFinish()
    }

    private func isApprovedPath(_ path: NWPath?) -> Bool {
        guard let path,
              case let .hostPort(localHost, localPort)? = path.localEndpoint,
              case let .hostPort(remoteHost, _)? = path.remoteEndpoint,
              localPort.rawValue == expectedLocalPort,
              isExactIPv4Loopback(localHost),
              isExactIPv4Loopback(remoteHost)
        else {
            return false
        }
        return true
    }

    private func isExactIPv4Loopback(_ host: NWEndpoint.Host) -> Bool {
        guard case let .ipv4(address) = host else { return false }
        return address == .loopback
    }

    private static func statusCode(in response: Data) -> Int? {
        guard let firstLineEnd = response.range(of: Data([0x0d, 0x0a]))?.lowerBound,
              let firstLine = String(data: response[..<firstLineEnd], encoding: .ascii)
        else {
            return nil
        }
        return firstLine.split(separator: " ").dropFirst().first.flatMap { Int($0) }
    }
}
