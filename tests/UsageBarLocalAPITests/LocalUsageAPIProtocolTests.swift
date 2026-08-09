import Foundation
import XCTest
@testable import UsageBarLocalAPI

final class LocalUsageAPIResponseBuilderTests: XCTestCase {
    private let date = Date(timeIntervalSince1970: 1_893_499_200)

    func testSuccessHeadersDateAndByteAccurateContentLength() throws {
        let body = Data("{\"value\":\"synthetic-✓\"}".utf8)
        let response = LocalUsageAPIHTTPResponseBuilder().build(status: .ok, body: body, date: date)
        let parsed = try ParsedResponse(response)

        XCTAssertEqual(parsed.status, 200)
        XCTAssertEqual(parsed.headers["Date"], "Tue, 01 Jan 2030 12:00:00 GMT")
        XCTAssertEqual(parsed.headers["Content-Type"], "application/json; charset=utf-8")
        XCTAssertEqual(parsed.headers["Content-Length"], String(body.count))
        XCTAssertEqual(parsed.headers["Connection"], "close")
        XCTAssertEqual(parsed.headers["Cache-Control"], "no-store")
        XCTAssertEqual(parsed.headers["X-Content-Type-Options"], "nosniff")
        XCTAssertEqual(parsed.body, body)
        XCTAssertNil(parsed.headers["Server"])
        XCTAssertFalse(parsed.headers.keys.contains { $0.hasPrefix("Access-Control-") })
        XCTAssertNil(parsed.headers["Location"])
        XCTAssertNil(parsed.headers["Transfer-Encoding"])
    }

    func testAllTransportErrorsHaveEmptyBodiesAndAllowlistedHeaders() throws {
        for status in [
            LocalUsageAPIHTTPStatus.badRequest, .notFound, .methodNotAllowed, .contentTooLarge,
            .uriTooLong, .tooManyRequests, .requestHeaderFieldsTooLarge,
            .serviceUnavailable, .httpVersionNotSupported
        ] {
            let response = LocalUsageAPIHTTPResponseBuilder().build(
                status: status,
                body: Data("must-not-leak".utf8),
                date: date
            )
            let parsed = try ParsedResponse(response)
            XCTAssertEqual(parsed.status, status.rawValue)
            XCTAssertEqual(parsed.headers["Content-Length"], "0")
            XCTAssertTrue(parsed.body.isEmpty)
            XCTAssertNil(parsed.headers["Content-Type"])
        }

        let method = try ParsedResponse(LocalUsageAPIHTTPResponseBuilder().build(status: .methodNotAllowed, date: date))
        XCTAssertEqual(method.headers["Allow"], "GET")
        let limited = try ParsedResponse(LocalUsageAPIHTTPResponseBuilder().build(status: .tooManyRequests, date: date))
        XCTAssertEqual(limited.headers["Retry-After"], "1")
    }
}

final class LocalUsageAPITokenBucketTests: XCTestCase {
    func testBurstNinthAdmissionPartialAndFullRefill() {
        let bucket = LocalUsageAPITokenBucket(initialMonotonicTime: 10)
        for _ in 0..<8 { XCTAssertTrue(bucket.admit(at: 10)) }
        XCTAssertFalse(bucket.admit(at: 10))
        XCTAssertFalse(bucket.admit(at: 10.24))
        XCTAssertTrue(bucket.admit(at: 10.25))
        XCTAssertFalse(bucket.admit(at: 10.25))

        for _ in 0..<8 { XCTAssertTrue(bucket.admit(at: 20)) }
        XCTAssertFalse(bucket.admit(at: 20))
    }

    func testMonotonicRegressionDoesNotRefill() {
        let bucket = LocalUsageAPITokenBucket(initialMonotonicTime: 100)
        for _ in 0..<8 { XCTAssertTrue(bucket.admit(at: 100)) }
        XCTAssertFalse(bucket.admit(at: 99))
        XCTAssertFalse(bucket.admit(at: 100.24))
        XCTAssertTrue(bucket.admit(at: 100.25))
    }

    func testBucketIsSharedAcrossCallers() {
        let bucket = LocalUsageAPITokenBucket(initialMonotonicTime: 0)
        let callers = (0..<8).map { _ in bucket.admit(at: 0) }
        XCTAssertTrue(callers.allSatisfy { $0 })
        XCTAssertFalse(bucket.admit(at: 0))
    }
}

final class LocalUsageAPIActiveConnectionGateTests: XCTestCase {
    func testFourActiveConnectionsAndSlotRelease() {
        let gate = LocalUsageAPIActiveConnectionGate()
        for expected in 1...4 {
            XCTAssertTrue(gate.acquire())
            XCTAssertEqual(gate.activeCount, expected)
        }
        XCTAssertFalse(gate.acquire())
        gate.release()
        XCTAssertEqual(gate.activeCount, 3)
        XCTAssertTrue(gate.acquire())
        XCTAssertEqual(gate.activeCount, 4)
        for _ in 0..<4 { gate.release() }
        XCTAssertEqual(gate.activeCount, 0)
    }
}

final class LocalUsageAPIRequestProcessorTests: XCTestCase {
    private let fixedDate = Date(timeIntervalSince1970: 1_893_499_200)
    private let validRequest = Data("GET /v1/usage HTTP/1.1\r\nHost: 127.0.0.1:54132\r\n\r\n".utf8)

    func testFreshStaleUnavailableAndDisabledSnapshotsRemainHTTP200() throws {
        for fixture in ["fresh-multiple-windows.json", "stale-and-disabled.json", "unavailable.json"] {
            let body = try Data(contentsOf: fixtureURL(fixture))
            let response = process(body: .success(body))
            let parsed = try ParsedResponse(response)
            XCTAssertEqual(parsed.status, 200, fixture)
            XCTAssertEqual(parsed.body, body, fixture)
        }
    }

    func testSnapshotFailureAndOversizeProduceEmpty503WithoutPartialJSON() throws {
        let failed = try ParsedResponse(process(body: .failure(TestError.synthetic)))
        XCTAssertEqual(failed.status, 503)
        XCTAssertTrue(failed.body.isEmpty)

        let oversized = Data(repeating: 0x61, count: LocalUsageAPIRequestProcessor.maximumResponseBodyBytes + 1)
        let tooLarge = try ParsedResponse(process(body: .success(oversized)))
        XCTAssertEqual(tooLarge.status, 503)
        XCTAssertTrue(tooLarge.body.isEmpty)
        XCTAssertFalse(String(decoding: process(body: .failure(TestError.synthetic)), as: UTF8.self).contains("synthetic"))
    }

    func testObservedAtIsInjectedAndRepeatedReadsDoNotRefreshOrMutate() throws {
        var observedTimes: [Date] = []
        var snapshotReads = 0
        var providerRefreshes = 0
        let body = Data("{\"schemaVersion\":1}".utf8)
        let processor = LocalUsageAPIRequestProcessor(
            expectedHost: "127.0.0.1:54132",
            wallNow: { self.fixedDate },
            snapshotProvider: { observedAt, completion in
                observedTimes.append(observedAt)
                snapshotReads += 1
                completion(.success(body))
            }
        )

        for _ in 0..<3 {
            let expectation = expectation(description: "response")
            XCTAssertTrue(processor.process(validRequest) { response in
                XCTAssertEqual(try? ParsedResponse(response).status, 200)
                expectation.fulfill()
            })
            wait(for: [expectation], timeout: 1)
        }

        XCTAssertEqual(snapshotReads, 3)
        XCTAssertEqual(observedTimes, [fixedDate, fixedDate, fixedDate])
        XCTAssertEqual(providerRefreshes, 0)
        providerRefreshes = 0
    }

    func testRejectedRequestNeverCallsSnapshotProvider() throws {
        var snapshotReads = 0
        let processor = LocalUsageAPIRequestProcessor(
            expectedHost: "127.0.0.1:54132",
            wallNow: { self.fixedDate },
            snapshotProvider: { _, _ in snapshotReads += 1 }
        )
        let expectation = expectation(description: "response")
        XCTAssertTrue(processor.process(Data("POST /v1/usage HTTP/1.1\r\nHost: 127.0.0.1:54132\r\n\r\n".utf8)) { response in
            XCTAssertEqual(try? ParsedResponse(response).status, 405)
            expectation.fulfill()
        })
        wait(for: [expectation], timeout: 1)
        XCTAssertEqual(snapshotReads, 0)
    }

    private func process(body: Result<Data, Error>) -> Data {
        let processor = LocalUsageAPIRequestProcessor(
            expectedHost: "127.0.0.1:54132",
            wallNow: { self.fixedDate },
            snapshotProvider: { _, completion in completion(body) }
        )
        var result = Data()
        let expectation = expectation(description: "processed")
        XCTAssertTrue(processor.process(validRequest) { response in
            result = response
            expectation.fulfill()
        })
        wait(for: [expectation], timeout: 1)
        return result
    }

    private func fixtureURL(_ name: String) -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("shared/fixtures/contract/v1")
            .appendingPathComponent(name)
    }

    private enum TestError: Error {
        case synthetic
    }
}

private struct ParsedResponse {
    let status: Int
    let headers: [String: String]
    let body: Data

    init(_ data: Data) throws {
        let delimiter = Data([0x0d, 0x0a, 0x0d, 0x0a])
        guard let split = data.range(of: delimiter),
              let head = String(data: data[..<split.lowerBound], encoding: .ascii)
        else {
            throw ParseError.invalidResponse
        }
        let lines = head.components(separatedBy: "\r\n")
        guard let status = lines.first?.split(separator: " ").dropFirst().first.flatMap({ Int($0) }) else {
            throw ParseError.invalidResponse
        }
        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of: ":") else { throw ParseError.invalidResponse }
            headers[String(line[..<colon])] = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
        }
        self.status = status
        self.headers = headers
        body = Data(data[split.upperBound...])
    }

    private enum ParseError: Error {
        case invalidResponse
    }
}
