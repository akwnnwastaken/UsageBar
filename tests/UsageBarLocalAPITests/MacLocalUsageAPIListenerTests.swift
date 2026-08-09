import Foundation
import Network
import XCTest
@testable import UsageBarLocalAPI

final class MacLocalUsageAPIListenerTests: XCTestCase {
    private let fixedDate = Date(timeIntervalSince1970: 1_893_499_200)

    func testProductionConfigurationIsFixedNumericIPv4LoopbackWithoutFallback() {
        XCTAssertEqual(MacLocalUsageAPIConfiguration.production.address, "127.0.0.1")
        XCTAssertEqual(MacLocalUsageAPIConfiguration.production.port, 54_132)
    }

    func testListenerParametersRequireIPv4LoopbackLocalOnlyAndDisableReuse() {
        let inspected = expectation(description: "parameters inspected")
        let failed = expectation(description: "listener failed after inspection")
        let listener = MacLocalUsageAPIListener(
            configuration: .production,
            wallNow: { self.fixedDate },
            monotonicNow: { 0 },
            snapshotProvider: { _, completion in completion(.success(Data("{}".utf8))) },
            diagnosticHandler: { _ in },
            listenerFactory: { parameters, port in
                XCTAssertEqual(port.rawValue, 54_132)
                XCTAssertEqual(
                    parameters.requiredLocalEndpoint,
                    .hostPort(host: .ipv4(.loopback), port: port)
                )
                XCTAssertTrue(parameters.acceptLocalOnly)
                XCTAssertFalse(parameters.allowLocalEndpointReuse)
                inspected.fulfill()
                throw TestError.syntheticPrivateDetail
            }
        )
        listener.onStateChange { state in
            if state == .failed { failed.fulfill() }
        }
        listener.start()
        wait(for: [inspected, failed], timeout: 1)
    }

    func testRealLoopbackValidGETReturnsSnapshotAndClosesConnection() throws {
        let body = try fixture("fresh-multiple-windows.json")
        var snapshotReads = 0
        var providerRefreshes = 0
        let listener = makeListener { observedAt, completion in
            XCTAssertEqual(observedAt, self.fixedDate)
            snapshotReads += 1
            completion(.success(body))
        }
        let port = try start(listener)
        defer { stop(listener) }

        let response = try exchange(
            port: port,
            request: "GET /v1/usage HTTP/1.1\r\nHost: 127.0.0.1:\(port)\r\n\r\n"
        )
        XCTAssertEqual(statusCode(response), 200)
        XCTAssertEqual(responseBody(response), body)
        XCTAssertEqual(snapshotReads, 1)
        XCTAssertEqual(providerRefreshes, 0)
        providerRefreshes = 0
    }

    func testRealLoopbackRejectsWrongHostOriginAndUnknownEndpointWithoutSnapshotRead() throws {
        var snapshotReads = 0
        let listener = makeListener { _, completion in
            snapshotReads += 1
            completion(.success(Data("{}".utf8)))
        }
        let port = try start(listener)
        defer { stop(listener) }

        let cases = [
            ("GET /v1/usage HTTP/1.1\r\nHost: localhost:\(port)\r\n\r\n", 400),
            ("GET /v1/usage HTTP/1.1\r\nHost: 127.0.0.1:\(port)\r\nOrigin: https://example.invalid\r\n\r\n", 400),
            ("GET /v1/health HTTP/1.1\r\nHost: 127.0.0.1:\(port)\r\n\r\n", 404)
        ]
        for (request, expectedStatus) in cases {
            XCTAssertEqual(statusCode(try exchange(port: port, request: request)), expectedStatus)
        }
        XCTAssertEqual(snapshotReads, 0)
    }

    func testRealLoopbackProcessWideBurstReturns429OnNinthAdmission() throws {
        let listener = MacLocalUsageAPIListener(
            configuration: MacLocalUsageAPIConfiguration(port: 0),
            wallNow: { self.fixedDate },
            monotonicNow: { 0 },
            snapshotProvider: { _, completion in completion(.success(Data("{}".utf8))) }
        )
        let port = try start(listener)
        defer { stop(listener) }
        let request = "GET /v1/usage HTTP/1.1\r\nHost: 127.0.0.1:\(port)\r\n\r\n"

        for _ in 0..<8 {
            XCTAssertEqual(statusCode(try exchange(port: port, request: request)), 200)
        }
        let limited = try exchange(port: port, request: request)
        XCTAssertEqual(statusCode(limited), 429)
        XCTAssertTrue(String(decoding: limited, as: UTF8.self).contains("Retry-After: 1\r\n"))
        XCTAssertTrue(responseBody(limited).isEmpty)
    }

    func testStopReleasesEndpointAndRepeatedStartStopIsIdempotent() throws {
        let listener = makeListener { _, completion in completion(.success(Data("{}".utf8))) }
        let firstPort = try start(listener, label: "initial")
        listener.start()
        XCTAssertEqual(listener.state, .listening)
        stop(listener)
        stop(listener)
        XCTAssertEqual(listener.state, .stopped)

        let rebound = makeListener(port: firstPort) { _, completion in completion(.success(Data("{}".utf8))) }
        _ = try start(rebound, label: "rebound")
        stop(rebound)

        let secondPort = try start(listener, label: "restart")
        XCTAssertNotEqual(secondPort, 0)
        stop(listener)
    }

    func testPortCollisionFailsSecondListenerWithoutAffectingFirst() throws {
        let first = makeListener { _, completion in completion(.success(Data("{}".utf8))) }
        let port = try start(first)
        defer { stop(first) }

        let second = makeListener(port: port) { _, completion in completion(.success(Data("{}".utf8))) }
        let failed = expectation(description: "second listener failed")
        second.onStateChange { state in
            if state == .failed { failed.fulfill() }
        }
        second.start()
        wait(for: [failed], timeout: 3)
        XCTAssertEqual(second.state, .failed)
        XCTAssertNil(second.boundPort)
        second.start()
        XCTAssertEqual(second.state, .failed)
        stop(second)
        XCTAssertEqual(second.state, .failed)

        let response = try exchange(
            port: port,
            request: "GET /v1/usage HTTP/1.1\r\nHost: 127.0.0.1:\(port)\r\n\r\n"
        )
        XCTAssertEqual(statusCode(response), 200)
    }

    func testFactoryFailureIsTerminalAndPrivacySafe() {
        var diagnostics: [MacLocalUsageAPIDiagnostic] = []
        let listener = MacLocalUsageAPIListener(
            configuration: MacLocalUsageAPIConfiguration(port: 0),
            wallNow: { self.fixedDate },
            monotonicNow: { 0 },
            snapshotProvider: { _, completion in completion(.success(Data("{}".utf8))) },
            diagnosticHandler: { diagnostics.append($0) },
            listenerFactory: { _, _ in throw TestError.syntheticPrivateDetail }
        )
        let failed = expectation(description: "failed")
        listener.onStateChange { state in
            if state == .failed { failed.fulfill() }
        }
        listener.start()
        wait(for: [failed], timeout: 1)
        XCTAssertEqual(listener.state, .failed)
        XCTAssertEqual(diagnostics, [.listenerBindFailed])
    }

    private func makeListener(
        port: UInt16 = 0,
        snapshotProvider: @escaping MacLocalUsageAPIListener.SnapshotProvider
    ) -> MacLocalUsageAPIListener {
        MacLocalUsageAPIListener(
            configuration: MacLocalUsageAPIConfiguration(port: port),
            wallNow: { self.fixedDate },
            monotonicNow: {
                TimeInterval(DispatchTime.now().uptimeNanoseconds) / 1_000_000_000
            },
            snapshotProvider: snapshotProvider
        )
    }

    private func start(_ listener: MacLocalUsageAPIListener, label: String = "listener") throws -> UInt16 {
        let ready = expectation(description: "\(label) ready")
        listener.onStateChange { state in
            if state == .listening { ready.fulfill() }
        }
        listener.start()
        wait(for: [ready], timeout: 3)
        return try XCTUnwrap(listener.boundPort)
    }

    private func stop(_ listener: MacLocalUsageAPIListener) {
        let stopped = expectation(description: "listener stopped")
        listener.stop { stopped.fulfill() }
        wait(for: [stopped], timeout: 3)
    }

    private func exchange(port: UInt16, request: String) throws -> Data {
        let finished = expectation(description: "connection closed")
        let connection = NWConnection(
            host: .ipv4(.loopback),
            port: try XCTUnwrap(NWEndpoint.Port(rawValue: port)),
            using: .tcp
        )
        let queue = DispatchQueue(label: "UsageBar.LocalUsageAPI.Tests.Client")
        let lock = NSLock()
        var received = Data()
        var terminalError: NWError?

        func receiveNext() {
            connection.receive(minimumIncompleteLength: 1, maximumLength: 32 * 1_024) { data, _, complete, error in
                lock.lock()
                if let data { received.append(data) }
                if let error { terminalError = error }
                lock.unlock()
                if complete || error != nil {
                    finished.fulfill()
                } else {
                    receiveNext()
                }
            }
        }

        connection.stateUpdateHandler = { state in
            switch state {
            case .ready:
                connection.send(content: Data(request.utf8), completion: .contentProcessed { error in
                    if let error {
                        lock.lock()
                        terminalError = error
                        lock.unlock()
                        finished.fulfill()
                    } else {
                        receiveNext()
                    }
                })
            case let .failed(error):
                lock.lock()
                terminalError = error
                lock.unlock()
                finished.fulfill()
            default:
                break
            }
        }
        connection.start(queue: queue)
        wait(for: [finished], timeout: 4)
        connection.cancel()
        lock.lock()
        defer { lock.unlock() }
        if received.isEmpty, let terminalError { throw terminalError }
        return received
    }

    private func statusCode(_ response: Data) -> Int? {
        guard let lineEnd = response.range(of: Data([0x0d, 0x0a]))?.lowerBound,
              let line = String(data: response[..<lineEnd], encoding: .ascii)
        else { return nil }
        return line.split(separator: " ").dropFirst().first.flatMap { Int($0) }
    }

    private func responseBody(_ response: Data) -> Data {
        let delimiter = Data([0x0d, 0x0a, 0x0d, 0x0a])
        guard let split = response.range(of: delimiter) else { return Data() }
        return Data(response[split.upperBound...])
    }

    private func fixture(_ name: String) throws -> Data {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("shared/fixtures/contract/v1")
            .appendingPathComponent(name)
        return try Data(contentsOf: url)
    }

    private enum TestError: Error {
        case syntheticPrivateDetail
    }
}
