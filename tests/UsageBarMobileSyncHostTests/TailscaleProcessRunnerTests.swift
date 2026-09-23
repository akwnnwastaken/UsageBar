import Darwin
import XCTest
@testable import UsageBarMobileSyncHost

/// Process-level proof for the runner itself, as opposed to the parsing above
/// it: what it does with a real child that exits, floods, or refuses to die.
///
/// Every child here is a throwaway script in the test's own temporary
/// directory, and every byte it emits is synthetic filler. No Tailscale
/// account, tailnet, hostname, address or key appears in this file, and none is
/// needed: the runner's contract is about bytes and lifetimes, not about what
/// the real CLI happens to say.
///
/// The fixtures being shell scripts is not the runner using a shell — the
/// runner still executes one absolute path with a fixed argument vector, which
/// `testTheChildIsGivenExactlyStatusAndJSONOnAClosedStdin` pins.
final class TailscaleProcessRunnerTests: XCTestCase {
    private var directory: URL!

    /// Small enough that a child can pass it in milliseconds, so the stdout
    /// ceiling can be exercised without allocating anything absurd.
    private let injectedCeiling = 4 * 1_024

    override func setUpWithError() throws {
        try super.setUpWithError()
        directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("usagebar-tailscale-runner-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let directory { try? FileManager.default.removeItem(at: directory) }
        directory = nil
        try super.tearDownWithError()
    }

    // MARK: - Fixtures

    private func makeChild(_ body: String, named name: String = "child") throws -> URL {
        let url = directory.appendingPathComponent(name)
        try "#!/bin/sh\n\(body)\n".write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: url.path
        )
        return url
    }

    /// Filler bytes on disk, so a child can emit a precise amount quickly.
    @discardableResult
    private func makeFiller(_ count: Int, named name: String) throws -> URL {
        let url = directory.appendingPathComponent(name)
        try Data(repeating: UInt8(ascii: "x"), count: count).write(to: url)
        return url
    }

    private func path(_ name: String) -> String {
        directory.appendingPathComponent(name).path
    }

    private func run(
        _ child: URL,
        timeout: TimeInterval = 5,
        maximumBytes: Int? = nil
    ) -> (data: Data?, elapsed: TimeInterval) {
        let started = Date()
        let data = MobileSyncTailscaleStatusReader.runStatus(
            executableURL: child,
            timeout: timeout,
            maximumBytes: maximumBytes ?? MobileSyncTailscaleStatusReader.maximumOutputBytes
        )
        return (data, Date().timeIntervalSince(started))
    }

    private func recordedIdentifier(_ name: String) throws -> pid_t {
        let text = try String(contentsOf: directory.appendingPathComponent(name), encoding: .utf8)
        return try XCTUnwrap(pid_t(text.trimmingCharacters(in: .whitespacesAndNewlines)))
    }

    /// A *reaped* child is gone from the process table; a merely-terminated one
    /// is still there as a zombie and still answers signal 0. So this is the
    /// assertion that the runner waited for what it killed.
    private func isPresent(_ identifier: pid_t) -> Bool {
        Darwin.kill(identifier, 0) == 0 || errno != ESRCH
    }

    private static let validJSON = #"{"BackendState":"Running"}"#

    // MARK: - The bounds are the documented ones

    func testCeilingsAndTimeoutAreTheDocumentedValues() {
        XCTAssertEqual(MobileSyncTailscaleStatusReader.maximumOutputBytes, 512 * 1_024)
        XCTAssertEqual(MobileSyncTailscaleStatusReader.maximumErrorBytes, 64 * 1_024)
        XCTAssertEqual(MobileSyncTailscaleStatusReader.timeout, 5)
    }

    // MARK: - The happy path

    func testValidJSONOnStdoutIsReturned() throws {
        let child = try makeChild(#"printf '%s' '\#(Self.validJSON)'"#)
        let outcome = run(child)
        XCTAssertEqual(outcome.data.map { String(decoding: $0, as: UTF8.self) }, Self.validJSON)
    }

    /// The argument vector is fixed and stdin is the null device, so nothing a
    /// caller or an environment could supply is ever interpreted as a command,
    /// and the child can never sit waiting on input this host will not send.
    func testTheChildIsGivenExactlyStatusAndJSONOnAClosedStdin() throws {
        let child = try makeChild(#"""
        printf '%s\n' "$@" > "\#(path("argv"))"
        cat > "\#(path("stdin"))"
        printf '%s' '\#(Self.validJSON)'
        """#)
        XCTAssertNotNil(run(child).data)

        let argv = try String(contentsOf: directory.appendingPathComponent("argv"), encoding: .utf8)
        XCTAssertEqual(argv.split(separator: "\n").map(String.init), ["status", "--json"])
        let stdin = try Data(contentsOf: directory.appendingPathComponent("stdin"))
        XCTAssertTrue(stdin.isEmpty)
    }

    // MARK: - What is not an answer

    /// The known macOS failure shape: the CLI cannot reach its GUI helper, says
    /// so in a human sentence on *stdout*, and exits 0 anyway.
    func testProseOnStdoutWithExitZeroIsRefused() throws {
        let child = try makeChild("echo 'The Tailscale GUI failed to start.'\nexit 0")
        XCTAssertNil(run(child).data)
    }

    func testNonZeroExitIsRefusedEvenWithValidJSON() throws {
        let child = try makeChild(#"printf '%s' '\#(Self.validJSON)'; exit 3"#)
        XCTAssertNil(run(child).data)
    }

    // MARK: - Ceilings

    func testStdoutBeyondTheCeilingIsRefusedAndNotTruncatedIntoAnAnswer() throws {
        try makeFiller(16 * 1_024, named: "flood")
        // Valid JSON first, then filler past the ceiling: a runner that kept
        // the prefix it liked would return a plausible-looking answer here.
        let child = try makeChild(#"printf '%s' '\#(Self.validJSON)'; cat "\#(path("flood"))""#)
        let outcome = run(child, maximumBytes: injectedCeiling)
        XCTAssertNil(outcome.data)
        XCTAssertLessThan(outcome.elapsed, 4)
    }

    /// The deadlock this whole change exists to make impossible.
    ///
    /// Half a megabyte of stderr is far past any pipe buffer macOS will grant.
    /// A runner that read stderr only after the child exited would leave the
    /// child blocked in `write(2)` forever, and this would end at the timeout
    /// rather than in milliseconds.
    func testStderrFloodNeitherDeadlocksNorIsAccepted() throws {
        try makeFiller(512 * 1_024, named: "noise")
        let child = try makeChild(#"""
        cat "\#(path("noise"))" >&2
        printf '%s' '\#(Self.validJSON)'
        """#)
        let outcome = run(child, timeout: 5)
        XCTAssertNil(outcome.data, "stderr past its ceiling is fail-closed")
        XCTAssertLessThan(outcome.elapsed, 4, "ended on the ceiling, not on the timeout")
    }

    /// The positive interleaved case: stderr arrives before, between and after
    /// the JSON, and a bounded amount of it must not spoil a good answer.
    ///
    /// This one cannot also prove concurrency. A macOS pipe buffers 64 KiB —
    /// measured, not assumed, and the same whether the child writes it in one
    /// call or in one-kilobyte pieces — which is exactly the stderr ceiling, so
    /// no child that stays inside the ceiling can ever be made to block. The
    /// deadlock proofs are the two tests around this one, which cross it.
    func testInterleavedBoundedStderrStillYieldsTheAnswer() throws {
        try makeFiller(30 * 1_024, named: "noise-a")
        try makeFiller(30 * 1_024, named: "noise-b")
        let child = try makeChild(#"""
        cat "\#(path("noise-a"))" >&2
        printf '%s' '{"BackendState":'
        cat "\#(path("noise-b"))" >&2
        printf '%s' '"Running"}'
        """#)
        let outcome = run(child, timeout: 5)
        XCTAssertEqual(
            outcome.data.map { String(decoding: $0, as: UTF8.self) },
            Self.validJSON,
            "60 KiB of stderr is inside the ceiling and must not spoil a good answer"
        )
        XCTAssertLessThan(outcome.elapsed, 4)
    }

    /// The same interleaving, past the ceiling: 80 KiB of stderr arriving in
    /// two bursts either side of the JSON.
    ///
    /// Both drains have to be live together for this to end quickly. The child
    /// blocks partway through the second burst, so a runner that only started
    /// reading stderr once the child exited would wait for a child that is
    /// waiting for it, and would end at the timeout.
    func testInterleavedStderrPastTheCeilingIsRefusedWithoutDeadlock() throws {
        try makeFiller(40 * 1_024, named: "noise-a")
        try makeFiller(40 * 1_024, named: "noise-b")
        let child = try makeChild(#"""
        cat "\#(path("noise-a"))" >&2
        printf '%s' '{"BackendState":'
        cat "\#(path("noise-b"))" >&2
        printf '%s' '"Running"}'
        """#)
        let outcome = run(child, timeout: 5)
        XCTAssertNil(outcome.data, "stderr past its ceiling is fail-closed")
        XCTAssertLessThan(outcome.elapsed, 4, "ended on the ceiling, not on the timeout")
    }

    // MARK: - Lifetimes

    func testTimeoutEndsTheReadAndTheChildIsReaped() throws {
        let child = try makeChild(#"echo $$ > "\#(path("pid"))"; exec sleep 30"#)
        let outcome = run(child, timeout: 0.5)
        XCTAssertNil(outcome.data)
        XCTAssertLessThan(outcome.elapsed, 4, "bounded by the read's own deadline, not by the child")
        XCTAssertFalse(isPresent(try recordedIdentifier("pid")))
    }

    /// SIGTERM is a request. A child that declines it must still be gone by the
    /// time the read returns, and gone means reaped, not zombied.
    func testChildIgnoringSIGTERMIsForceStoppedAndReaped() throws {
        let child = try makeChild(#"""
        trap '' TERM
        echo $$ > "\#(path("pid"))"
        while :; do sleep 0.2; done
        """#)
        let outcome = run(child, timeout: 0.5)
        XCTAssertNil(outcome.data)
        XCTAssertLessThan(
            outcome.elapsed,
            0.5 + MobileSyncProcessStopper.terminationGrace + 3,
            "the escalation to SIGKILL is on a finite grace"
        )
        XCTAssertFalse(isPresent(try recordedIdentifier("pid")))
    }

    // MARK: - The bounded buffer itself

    func testBoundedCaptureKeepsItsLimitAndRemembersOverflow() {
        let capture = MobileSyncBoundedCapture(limit: 4)
        XCTAssertTrue(capture.append(Data([1, 2, 3])))
        XCTAssertFalse(capture.append(Data([4, 5])))
        XCTAssertEqual(capture.snapshot().bytes, Data([1, 2, 3, 4]))
        XCTAssertTrue(capture.snapshot().overflowed)
        // Once exceeded it stays exceeded, even for an empty append.
        XCTAssertFalse(capture.append(Data()))
        XCTAssertTrue(capture.hasOverflowed)
    }

    func testBoundedCaptureAcceptsExactlyItsLimit() {
        let capture = MobileSyncBoundedCapture(limit: 3)
        XCTAssertTrue(capture.append(Data([1, 2, 3])))
        XCTAssertFalse(capture.hasOverflowed)
        XCTAssertEqual(capture.snapshot().bytes.count, 3)
    }
}
