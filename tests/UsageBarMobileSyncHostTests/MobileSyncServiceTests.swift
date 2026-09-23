import XCTest
import UsageBarPairing
import UsageBarSync
import UsageBarSyncTransport
@testable import UsageBarMobileSyncHost

/// The two routes, and everything they refuse.
final class MobileSyncServiceTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_772_000_000)

    private func makeService(
        authStore: InMemoryMobileSyncAuthStore = InMemoryMobileSyncAuthStore(),
        pairing: MobileSyncPairingSessionStore = MobileSyncPairingSessionStore(),
        snapshot: UsageSyncSnapshot? = nil
    ) throws -> (MobileSyncService, InMemoryMobileSyncAuthStore, MobileSyncPairingSessionStore) {
        let store = UsageSyncLiveSnapshotStore(initial: try snapshot ?? HostFixtures.snapshot())
        let service = MobileSyncService(
            authStore: authStore,
            pairing: pairing,
            source: store,
            now: { self.now }
        )
        return (service, authStore, pairing)
    }

    private func pairedStore(bearer: String) throws -> InMemoryMobileSyncAuthStore {
        InMemoryMobileSyncAuthStore(
            record: MobileSyncAuthRecord(
                bearerDigest: MobileSyncDigest.of(bearer),
                identityDigest: try XCTUnwrap(MobileSyncTailscaleIdentity.digest(of: HostFixtures.identity)),
                createdAt: now
            )
        )
    }

    // MARK: - Identity is required everywhere

    /// Without a Serve-injected identity, every route answers the same 401 —
    /// including pairing, and including routes that do not exist. An
    /// unauthenticated prober learns nothing about the surface behind it.
    func testMissingIdentityIsAlways401() throws {
        let (service, _, pairing) = try makeService()
        pairing.start(now: now)
        for request in [
            HostRequests.snapshot(bearer: "anything", identity: nil),
            HostRequests.pair(code: UsageBarPairingCode.generate().encoded, identity: nil),
            HostRequests.snapshot(identity: nil, path: "/v1/nope"),
            HostRequests.snapshot(identity: nil, method: "DELETE")
        ] {
            XCTAssertEqual(service.respond(to: request).status, 401)
        }
    }

    func testBlankIdentityRejected() throws {
        let (service, _, _) = try makeService()
        XCTAssertEqual(service.respond(to: HostRequests.snapshot(identity: "   ")).status, 401)
    }

    // MARK: - Snapshot route

    func testUnpairedHostServesNoSnapshot() throws {
        let (service, _, _) = try makeService()
        XCTAssertEqual(service.respond(to: HostRequests.snapshot(bearer: "anything")).status, 401)
    }

    func testCorrectBearerAndIdentityGetsTheSnapshot() throws {
        let bearer = MobileSyncBearer.generate()
        let (service, _, _) = try makeService(authStore: try pairedStore(bearer: bearer))
        let response = service.respond(to: HostRequests.snapshot(bearer: bearer))
        XCTAssertEqual(response.status, 200)
        XCTAssertTrue(response.contentType.hasPrefix("application/json"))
        XCTAssertNoThrow(try UsageSyncSerialization.decode(response.body))
    }

    func testCorrectBearerFromWrongIdentityRejected() throws {
        let bearer = MobileSyncBearer.generate()
        let (service, _, _) = try makeService(authStore: try pairedStore(bearer: bearer))
        let response = service.respond(
            to: HostRequests.snapshot(bearer: bearer, identity: HostFixtures.otherIdentity)
        )
        XCTAssertEqual(response.status, 401)
    }

    func testWrongBearerFromCorrectIdentityRejected() throws {
        let (service, _, _) = try makeService(authStore: try pairedStore(bearer: MobileSyncBearer.generate()))
        XCTAssertEqual(
            service.respond(to: HostRequests.snapshot(bearer: MobileSyncBearer.generate())).status,
            401
        )
    }

    func testMissingOrMalformedAuthorizationRejected() throws {
        let bearer = MobileSyncBearer.generate()
        let (service, _, _) = try makeService(authStore: try pairedStore(bearer: bearer))
        XCTAssertEqual(service.respond(to: HostRequests.snapshot()).status, 401)
        let wrongScheme = UsageSyncTransportRequest(
            method: "GET",
            path: MobileSyncService.snapshotPath,
            headers: [
                MobileSyncService.identityHeader: HostFixtures.identity,
                "Authorization": "UsageBar-Pair \(bearer)"
            ]
        )
        XCTAssertEqual(service.respond(to: wrongScheme).status, 401)
    }

    /// Revoking on the Mac makes every previously issued bearer fail.
    func testRevokedPairingYields401() throws {
        let bearer = MobileSyncBearer.generate()
        let store = try pairedStore(bearer: bearer)
        let (service, _, _) = try makeService(authStore: store)
        XCTAssertEqual(service.respond(to: HostRequests.snapshot(bearer: bearer)).status, 200)
        store.clear()
        XCTAssertEqual(service.respond(to: HostRequests.snapshot(bearer: bearer)).status, 401)
    }

    func testPostToSnapshotPathRejected() throws {
        let bearer = MobileSyncBearer.generate()
        let (service, _, _) = try makeService(authStore: try pairedStore(bearer: bearer))
        let response = service.respond(
            to: HostRequests.snapshot(bearer: bearer, method: "POST")
        )
        XCTAssertNotEqual(response.status, 200)
        XCTAssertEqual(response.status, 404)
    }

    func testSnapshotUnavailableWhenNothingPublished() throws {
        let bearer = MobileSyncBearer.generate()
        let service = MobileSyncService(
            authStore: try pairedStore(bearer: bearer),
            pairing: MobileSyncPairingSessionStore(),
            source: UsageSyncLiveSnapshotStore(),
            now: { self.now }
        )
        XCTAssertEqual(service.respond(to: HostRequests.snapshot(bearer: bearer)).status, 503)
    }

    // MARK: - Pairing route

    func testNoActivePairingSessionIssuesNoCredential() throws {
        let (service, authStore, _) = try makeService()
        let response = service.respond(
            to: HostRequests.pair(code: UsageBarPairingCode.generate().encoded)
        )
        XCTAssertEqual(response.status, 401)
        XCTAssertNil(authStore.load())
    }

    func testMissingPairingCodeRejected() throws {
        let (service, authStore, pairing) = try makeService()
        pairing.start(now: now)
        XCTAssertEqual(service.respond(to: HostRequests.pair(code: nil)).status, 401)
        XCTAssertNil(authStore.load())
    }

    func testWrongPairingCodeRejected() throws {
        let (service, authStore, pairing) = try makeService()
        pairing.start(now: now)
        let response = service.respond(
            to: HostRequests.pair(code: UsageBarPairingCode.generate().encoded)
        )
        XCTAssertEqual(response.status, 401)
        XCTAssertNil(authStore.load())
    }

    func testMalformedPairingCodeRejected() throws {
        let (service, authStore, pairing) = try makeService()
        pairing.start(now: now)
        for bad in ["", "short", "!!!!", String(repeating: "A", count: 300)] {
            XCTAssertEqual(service.respond(to: HostRequests.pair(code: bad)).status, 401, bad)
        }
        XCTAssertNil(authStore.load())
    }

    func testValidPairIssuesACredential() throws {
        let (service, authStore, pairing) = try makeService()
        let session = pairing.start(now: now)
        let response = service.respond(to: HostRequests.pair(code: session.code.encoded))

        XCTAssertEqual(response.status, 200)
        XCTAssertTrue(response.contentType.hasPrefix("application/json"))
        let json = try XCTUnwrap(response.jsonObject)
        XCTAssertEqual(json["schemaVersion"] as? Int, 1)
        let bearer = try XCTUnwrap(json["accessKey"] as? String)
        XCTAssertEqual(bearer.count, 43)

        // The issued bearer works, bound to the identity that paired.
        XCTAssertEqual(service.respond(to: HostRequests.snapshot(bearer: bearer)).status, 200)
        XCTAssertEqual(
            service.respond(to: HostRequests.snapshot(bearer: bearer, identity: HostFixtures.otherIdentity)).status,
            401
        )
        XCTAssertNotNil(authStore.load())
    }

    /// Two fields. No identity, no hostname, no usage, no echo of the code.
    func testPairingResponseCarriesNothingElse() throws {
        let (service, _, pairing) = try makeService()
        let session = pairing.start(now: now)
        let response = service.respond(to: HostRequests.pair(code: session.code.encoded))

        let json = try XCTUnwrap(response.jsonObject)
        XCTAssertEqual(Set(json.keys), ["schemaVersion", "accessKey"])
        let text = response.bodyText
        XCTAssertFalse(text.contains(HostFixtures.identity))
        XCTAssertFalse(text.contains(HostFixtures.host))
        XCTAssertFalse(text.contains(session.code.encoded))
        XCTAssertFalse(text.contains("ts.net"))
        XCTAssertLessThan(response.body.count, 512)
    }

    /// Every response carries `Cache-Control: no-store`, so the one moment a
    /// raw bearer is on the wire is not written into any cache on the way back.
    func testEveryResponseIsNoStore() throws {
        let (service, _, pairing) = try makeService()
        let session = pairing.start(now: now)
        let paired = service.respond(to: HostRequests.pair(code: session.code.encoded))
        let refused = service.respond(to: HostRequests.snapshot())
        for response in [paired, refused] {
            let head = String(decoding: response.serialized(), as: UTF8.self)
            XCTAssertTrue(head.contains("Cache-Control: no-store"))
        }
    }

    func testPairingReplayIsRejected() throws {
        let (service, _, pairing) = try makeService()
        let session = pairing.start(now: now)
        XCTAssertEqual(service.respond(to: HostRequests.pair(code: session.code.encoded)).status, 200)
        XCTAssertEqual(service.respond(to: HostRequests.pair(code: session.code.encoded)).status, 401)
    }

    /// Pairing again rotates the credential: the previously issued bearer stops
    /// working the moment a new one is issued.
    func testRePairingInvalidatesThePreviousBearer() throws {
        let (service, _, pairing) = try makeService()
        let first = pairing.start(now: now)
        let firstBearer = try XCTUnwrap(
            service.respond(to: HostRequests.pair(code: first.code.encoded)).jsonObject?["accessKey"] as? String
        )
        XCTAssertEqual(service.respond(to: HostRequests.snapshot(bearer: firstBearer)).status, 200)

        let second = pairing.start(now: now)
        let secondBearer = try XCTUnwrap(
            service.respond(to: HostRequests.pair(code: second.code.encoded)).jsonObject?["accessKey"] as? String
        )
        XCTAssertNotEqual(firstBearer, secondBearer)
        XCTAssertEqual(service.respond(to: HostRequests.snapshot(bearer: firstBearer)).status, 401)
        XCTAssertEqual(service.respond(to: HostRequests.snapshot(bearer: secondBearer)).status, 200)
    }

    func testExpiredSessionIssuesNoCredential() throws {
        let pairing = MobileSyncPairingSessionStore(lifetime: 60)
        let store = UsageSyncLiveSnapshotStore(initial: try HostFixtures.snapshot())
        let authStore = InMemoryMobileSyncAuthStore()
        var clock = now
        let service = MobileSyncService(
            authStore: authStore, pairing: pairing, source: store, now: { clock }
        )
        let session = pairing.start(now: clock)
        clock = now.addingTimeInterval(61)
        XCTAssertEqual(service.respond(to: HostRequests.pair(code: session.code.encoded)).status, 401)
        XCTAssertNil(authStore.load())
    }

    func testGetOnPairingPathRejected() throws {
        let (service, authStore, pairing) = try makeService()
        let session = pairing.start(now: now)
        let response = service.respond(
            to: HostRequests.pair(code: session.code.encoded, method: "GET")
        )
        XCTAssertNotEqual(response.status, 200)
        XCTAssertNil(authStore.load())
        // And the session survives an attempt on the wrong method.
        XCTAssertNotNil(pairing.current(now: now))
    }

    func testWrongAuthorizationSchemeOnPairingRejected() throws {
        let (service, authStore, pairing) = try makeService()
        let session = pairing.start(now: now)
        let response = service.respond(
            to: HostRequests.pair(code: session.code.encoded, scheme: "Bearer")
        )
        XCTAssertEqual(response.status, 401)
        XCTAssertNil(authStore.load())
    }

    // MARK: - Failure bodies

    /// A refusal is a status code and nothing more. No body explains which
    /// factor failed, which route exists, or whether a pairing is live.
    func testRefusalBodiesCarryNoAuthDetail() throws {
        let (service, _, _) = try makeService()
        let responses = [
            service.respond(to: HostRequests.snapshot()),
            service.respond(to: HostRequests.snapshot(identity: nil)),
            service.respond(to: HostRequests.pair(code: UsageBarPairingCode.generate().encoded)),
            service.respond(to: HostRequests.snapshot(path: "/v1/unknown"))
        ]
        for response in responses {
            let text = response.bodyText.lowercased()
            for forbidden in [
                "bearer", "identity", "tailscale", "pair", "token", "revoked",
                "expired", "keychain", "snapshot", "@"
            ] {
                XCTAssertFalse(text.contains(forbidden), "\(response.status) leaked \"\(forbidden)\"")
            }
        }
    }

    /// An authenticated caller may be told a route does not exist; an
    /// unauthenticated one gets 401 for the same request.
    func testUnknownRouteIs404OnlyOnceAuthenticated() throws {
        let bearer = MobileSyncBearer.generate()
        let (service, _, _) = try makeService(authStore: try pairedStore(bearer: bearer))
        XCTAssertEqual(
            service.respond(to: HostRequests.snapshot(bearer: bearer, path: "/v1/unknown")).status,
            404
        )
        XCTAssertEqual(service.respond(to: HostRequests.snapshot(path: "/v1/unknown")).status, 401)
    }
}
