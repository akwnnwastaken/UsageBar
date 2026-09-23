import XCTest
import UsageBarPairing
import UsageBarSyncTransport
@testable import UsageBarMobileSyncHost

/// The long-lived credential: what the Mac keeps, what it refuses to keep, and
/// what it demands before serving a snapshot.
final class MobileSyncAuthTests: XCTestCase {
    private let createdAt = Date(timeIntervalSince1970: 1_772_000_000)

    private func record(
        bearer: String,
        identity: String = HostFixtures.identity
    ) throws -> MobileSyncAuthRecord {
        MobileSyncAuthRecord(
            bearerDigest: MobileSyncDigest.of(bearer),
            identityDigest: try XCTUnwrap(MobileSyncTailscaleIdentity.digest(of: identity)),
            createdAt: createdAt
        )
    }

    // MARK: - Entropy

    func testGeneratedBearerIs256Bits() {
        XCTAssertEqual(MobileSyncBearer.byteCount, 32)
        let bearer = MobileSyncBearer.generate()
        // base64url of 32 bytes, unpadded.
        XCTAssertEqual(bearer.count, 43)
        XCTAssertFalse(bearer.contains("="))
    }

    func testGeneratedBearersDiffer() {
        let bearers = (0..<32).map { _ in MobileSyncBearer.generate() }
        XCTAssertEqual(Set(bearers).count, bearers.count)
    }

    // MARK: - What is persisted

    /// The central privacy property of the desktop side: a Keychain dump, a
    /// backup or a stolen laptop yields nothing replayable.
    func testPersistedRecordContainsNoRawBearer() throws {
        let bearer = MobileSyncBearer.generate()
        let encoded = String(decoding: try record(bearer: bearer).encoded(), as: UTF8.self)
        XCTAssertFalse(encoded.contains(bearer))
    }

    /// A Tailscale login is an email address. The Mac has no reason to keep one.
    func testPersistedRecordContainsNoRawIdentity() throws {
        let encoded = String(decoding: try record(bearer: "b").encoded(), as: UTF8.self)
        XCTAssertFalse(encoded.contains(HostFixtures.identity))
        XCTAssertFalse(encoded.contains("@"))
    }

    func testRecordRoundTrips() throws {
        let original = try record(bearer: "bearer-value")
        let decoded = try XCTUnwrap(MobileSyncAuthRecord.decode(original.encoded()))
        XCTAssertEqual(decoded, original)
    }

    func testRecordRejectsForeignOrCorruptData() {
        XCTAssertNil(MobileSyncAuthRecord.decode(Data("not json".utf8)))
        XCTAssertNil(MobileSyncAuthRecord.decode(Data(#"{"schemaVersion":2}"#.utf8)))
        XCTAssertNil(MobileSyncAuthRecord.decode(Data(
            #"{"schemaVersion":1,"bearerDigest":"short","identityDigest":"x","createdAt":0}"#.utf8
        )))
    }

    // MARK: - Both factors

    func testCorrectBearerAndIdentityAccepted() throws {
        let bearer = MobileSyncBearer.generate()
        XCTAssertTrue(
            try record(bearer: bearer).authorizes(bearer: bearer, identity: HostFixtures.identity)
        )
    }

    /// A leaked bearer is not enough. This is what the identity binding buys.
    func testCorrectBearerWithWrongIdentityRejected() throws {
        let bearer = MobileSyncBearer.generate()
        XCTAssertFalse(
            try record(bearer: bearer).authorizes(bearer: bearer, identity: HostFixtures.otherIdentity)
        )
    }

    func testWrongBearerWithCorrectIdentityRejected() throws {
        let stored = try record(bearer: MobileSyncBearer.generate())
        XCTAssertFalse(
            stored.authorizes(bearer: MobileSyncBearer.generate(), identity: HostFixtures.identity)
        )
    }

    func testWrongBothRejected() throws {
        let stored = try record(bearer: MobileSyncBearer.generate())
        XCTAssertFalse(
            stored.authorizes(bearer: MobileSyncBearer.generate(), identity: HostFixtures.otherIdentity)
        )
    }

    /// Same length, one bit different — the case a short-circuiting comparison
    /// would leak through timing.
    func testSameLengthWrongBearerRejected() throws {
        let bearer = MobileSyncBearer.generate()
        var wrong = Array(bearer)
        wrong[0] = wrong[0] == "A" ? "B" : "A"
        XCTAssertEqual(String(wrong).count, bearer.count)
        XCTAssertFalse(
            try record(bearer: bearer).authorizes(bearer: String(wrong), identity: HostFixtures.identity)
        )
    }

    func testBearerPrefixRejected() throws {
        let bearer = MobileSyncBearer.generate()
        XCTAssertFalse(
            try record(bearer: bearer)
                .authorizes(bearer: String(bearer.dropLast()), identity: HostFixtures.identity)
        )
        XCTAssertFalse(
            try record(bearer: bearer).authorizes(bearer: "", identity: HostFixtures.identity)
        )
    }

    // MARK: - Identity normalization

    /// Normalization has to be identical at pairing time and afterwards, or the
    /// binding would break whenever Serve changed a header's casing.
    func testIdentityNormalizationIsStable() throws {
        let bearer = MobileSyncBearer.generate()
        let stored = try record(bearer: bearer, identity: "Owner@Example.Invalid")
        for variant in ["owner@example.invalid", " OWNER@EXAMPLE.INVALID ", "Owner@Example.Invalid\n"] {
            XCTAssertTrue(stored.authorizes(bearer: bearer, identity: variant), variant)
        }
    }

    func testEmptyOrControlCharacterIdentityRejected() {
        XCTAssertNil(MobileSyncTailscaleIdentity.normalized(""))
        XCTAssertNil(MobileSyncTailscaleIdentity.normalized("   "))
        XCTAssertNil(MobileSyncTailscaleIdentity.normalized("owner\u{0}@example.invalid"))
        XCTAssertNil(MobileSyncTailscaleIdentity.normalized(String(repeating: "a", count: 400)))
    }

    // MARK: - Digest

    func testDigestIsConstantTimeAndHexRoundTrips() {
        let digest = MobileSyncDigest.of("value")
        XCTAssertEqual(digest.bytes.count, 32)
        XCTAssertEqual(MobileSyncDigest(hexEncoded: digest.hexEncoded), digest)
        XCTAssertNil(MobileSyncDigest(hexEncoded: "abcd"))
        XCTAssertNil(MobileSyncDigest(hexEncoded: String(repeating: "z", count: 64)))
        XCTAssertFalse(digest.matches(MobileSyncDigest.of("other")))
    }

    // MARK: - Lifecycle

    func testRePairReplacesTheStoredRecord() throws {
        let store = InMemoryMobileSyncAuthStore()
        let first = MobileSyncBearer.generate()
        try store.save(try record(bearer: first))
        let second = MobileSyncBearer.generate()
        try store.save(try record(bearer: second))

        let current = try XCTUnwrap(store.load())
        XCTAssertFalse(current.authorizes(bearer: first, identity: HostFixtures.identity))
        XCTAssertTrue(current.authorizes(bearer: second, identity: HostFixtures.identity))
    }

    /// The digests are what survive a relaunch; the raw bearer does not exist
    /// on this machine to survive.
    func testStoredDigestsSurviveAFreshCoordinator() throws {
        let store = InMemoryMobileSyncAuthStore()
        let bearer = MobileSyncBearer.generate()
        try store.save(try record(bearer: bearer))

        let afterRestart = MobileSyncCoordinator(
            authStore: store,
            preferences: InMemoryMobileSyncPreferences(isMobileSyncEnabled: true),
            isPermittedInThisProcess: true,
            makeServer: { _ in UsageSyncLoopbackHTTPServer { _ in .forRejection(.notFound) } }
        )
        XCTAssertTrue(afterRestart.isPaired)
        let reloaded = try XCTUnwrap(store.load())
        XCTAssertTrue(reloaded.authorizes(bearer: bearer, identity: HostFixtures.identity))
    }

    func testRevokeDeletesTheAuthRecord() throws {
        let store = InMemoryMobileSyncAuthStore(record: try record(bearer: "b"))
        let coordinator = MobileSyncCoordinator(
            authStore: store,
            preferences: InMemoryMobileSyncPreferences(isMobileSyncEnabled: true),
            isPermittedInThisProcess: true,
            makeServer: { _ in UsageSyncLoopbackHTTPServer { _ in .forRejection(.notFound) } }
        )
        XCTAssertTrue(coordinator.isPaired)
        coordinator.revokePairedDevice()
        XCTAssertFalse(coordinator.isPaired)
        XCTAssertNil(store.load())
    }

    /// Switching the feature off is a revocation, not a pause.
    func testDisableRemovesTheAuthRecord() throws {
        let store = InMemoryMobileSyncAuthStore(record: try record(bearer: "b"))
        let preferences = InMemoryMobileSyncPreferences(isMobileSyncEnabled: true)
        let coordinator = MobileSyncCoordinator(
            authStore: store,
            preferences: preferences,
            isPermittedInThisProcess: true,
            makeServer: { _ in UsageSyncLoopbackHTTPServer { _ in .forRejection(.notFound) } }
        )
        coordinator.disable()
        XCTAssertNil(store.load())
        XCTAssertFalse(preferences.isMobileSyncEnabled)
    }
}
