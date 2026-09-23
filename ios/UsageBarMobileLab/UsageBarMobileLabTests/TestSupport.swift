import Foundation
import XCTest
import UsageBarSync
@testable import UsageBarMobileLab

/// Stubs the network at the `URLProtocol` layer.
///
/// Chosen over a fake `SnapshotFetching` on purpose: the rules worth testing —
/// redirect refusal, the size ceiling, status and Content-Type policy — all
/// live inside the real client and its session delegate. A fake client would
/// test the fake.
final class StubURLProtocol: URLProtocol {
    struct Stub {
        var statusCode: Int = 200
        var headers: [String: String] = ["Content-Type": "application/json"]
        var body: Data = Data()
        /// When set, the stub answers with a redirect to this location first.
        var redirectTo: URL?
        var redirectStatusCode: Int = 302
        var error: Error?
    }

    nonisolated(unsafe) static var stub = Stub()
    /// Every request the loading system actually issued, so a test can assert
    /// that a refused redirect produced no second request.
    nonisolated(unsafe) static var recordedRequests: [URLRequest] = []

    static func reset() {
        stub = Stub()
        recordedRequests = []
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.recordedRequests.append(request)

        if let error = Self.stub.error {
            client?.urlProtocol(self, didFailWithError: error)
            return
        }

        if let location = Self.stub.redirectTo {
            let redirectResponse = HTTPURLResponse(
                url: request.url!,
                statusCode: Self.stub.redirectStatusCode,
                httpVersion: "HTTP/1.1",
                headerFields: ["Location": location.absoluteString]
            )!
            var followUp = URLRequest(url: location)
            followUp.httpMethod = request.httpMethod
            // Mirror what URLSession would do if it followed: carry the headers.
            followUp.allHTTPHeaderFields = request.allHTTPHeaderFields
            client?.urlProtocol(self, wasRedirectedTo: followUp, redirectResponse: redirectResponse)
            return
        }

        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: Self.stub.statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: Self.stub.headers
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        if !Self.stub.body.isEmpty {
            client?.urlProtocol(self, didLoad: Self.stub.body)
        }
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

enum TestFixtures {
    static let host = try! UsageSyncHost(validating: "usagebar-test.example-tail.ts.net")
    static let accessKey = String(repeating: "k", count: 64)
    static var connection: UsageSyncConnection {
        UsageSyncConnection(host: host, accessKey: accessKey)
    }

    static func stubbedClient() -> UsageSyncAPIClient {
        let configuration = UsageSyncAPIClient.privateConfiguration()
        configuration.protocolClasses = [StubURLProtocol.self]
        return UsageSyncAPIClient(configuration: configuration)
    }

    /// Mirrors `shared/sync-schema/parity/basic.json`, the cross-platform
    /// oracle, so the app is exercised against the same corpus both desktop
    /// builders are tested against.
    static let basicSnapshotJSON = """
    {
      "schemaVersion": 1,
      "generatedAt": "2026-03-04T09:00:00Z",
      "providers": [
        {
          "providerId": "codex",
          "connected": true,
          "collecting": true,
          "measurement": {
            "measuredAt": "2026-03-04T09:00:00Z",
            "headlineRemainingPercent": 64,
            "headlineWindowId": "five-hour",
            "windows": [
              { "windowId": "five-hour", "kind": "fiveHour", "durationMinutes": 300, "remainingPercent": 64, "resetsAt": "2026-03-04T13:00:00Z" },
              { "windowId": "weekly", "kind": "weekly", "durationMinutes": 10080, "remainingPercent": 81, "resetsAt": "2026-03-08T00:00:00Z" }
            ]
          }
        },
        {
          "providerId": "claude-code",
          "connected": true,
          "collecting": true,
          "measurement": {
            "measuredAt": "2026-03-04T08:55:00Z",
            "headlineRemainingPercent": 52,
            "headlineWindowId": "five-hour",
            "windows": [
              { "windowId": "five-hour", "kind": "fiveHour", "durationMinutes": 300, "remainingPercent": 52, "resetsAt": "2026-03-04T12:30:00Z" },
              { "windowId": "weekly", "kind": "weekly", "durationMinutes": 10080, "remainingPercent": 76, "resetsAt": "2026-03-09T19:00:00Z" }
            ]
          }
        }
      ]
    }
    """

    static var basicSnapshotData: Data { Data(basicSnapshotJSON.utf8) }

    static func decodedBasicSnapshot() throws -> UsageSyncSnapshot {
        try UsageSyncSerialization.decode(basicSnapshotData)
    }
}

/// A fetcher whose outcome each test dictates, for store-level behaviour where
/// the network itself is not what is under test.
final class ScriptedFetcher: SnapshotFetching, @unchecked Sendable {
    enum Outcome {
        case success(UsageSyncSnapshot)
        case failure(Error)
    }

    var outcome: Outcome
    private(set) var callCount = 0

    init(outcome: Outcome) {
        self.outcome = outcome
    }

    func fetchSnapshot(using connection: UsageSyncConnection) async throws -> UsageSyncSnapshot {
        callCount += 1
        switch outcome {
        case .success(let snapshot): return snapshot
        case .failure(let error): throw error
        }
    }
}

extension TestFixtures {
    /// The repository root, reached from this file rather than from a bundle
    /// resource: the parity corpus is deliberately *not* copied into the test
    /// bundle, because a copy is a second source of truth and the whole point
    /// of `shared/sync-schema/parity/` is that every platform reads the same
    /// bytes.
    static var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // UsageBarMobileLabTests
            .deletingLastPathComponent()   // UsageBarMobileLab (project dir)
            .deletingLastPathComponent()   // ios
            .deletingLastPathComponent()   // repository root
    }

    static func parityFixtureData(_ name: String) throws -> Data {
        try Data(contentsOf: repositoryRoot
            .appendingPathComponent("shared/sync-schema/parity/\(name).json"))
    }

    /// Decoded through the shipping validator, so a fixture that stopped being
    /// schema-valid fails here rather than quietly changing what a test proves.
    static func paritySnapshot(_ name: String) throws -> UsageSyncSnapshot {
        try UsageSyncSerialization.decode(try parityFixtureData(name))
    }
}

/// A connection store that counts reads, for proving that a code path did not
/// touch the keychain at all — and that can pretend to be a locked device.
final class CountingConnectionStore: ConnectionStore {
    private(set) var loadCount = 0
    private(set) var clearCount = 0
    private var connection: UsageSyncConnection?
    /// Simulates `errSecInteractionNotAllowed`: the item is there, the device
    /// is locked, and the read cannot be served right now.
    var isTemporarilyUnavailable = false

    init(connection: UsageSyncConnection? = nil, isTemporarilyUnavailable: Bool = false) {
        self.connection = connection
        self.isTemporarilyUnavailable = isTemporarilyUnavailable
    }

    func availability() -> ConnectionAvailability {
        loadCount += 1
        if isTemporarilyUnavailable { return .temporarilyUnavailable }
        guard let connection else { return .missing }
        return .available(connection)
    }

    func save(_ connection: UsageSyncConnection) throws { self.connection = connection }

    func clear() {
        clearCount += 1
        connection = nil
    }
}

/// A snapshot cache that counts every operation.
final class CountingSnapshotCache: SnapshotCaching {
    private(set) var loadCount = 0
    private(set) var storeCount = 0
    private(set) var clearCount = 0
    private var snapshot: UsageSyncSnapshot?

    init(snapshot: UsageSyncSnapshot? = nil) {
        self.snapshot = snapshot
    }

    func load() -> UsageSyncSnapshot? {
        loadCount += 1
        return snapshot
    }

    func store(_ snapshot: UsageSyncSnapshot) throws {
        storeCount += 1
        self.snapshot = snapshot
    }

    func clear() {
        clearCount += 1
        snapshot = nil
    }

    var storedSnapshot: UsageSyncSnapshot? { snapshot }
}
