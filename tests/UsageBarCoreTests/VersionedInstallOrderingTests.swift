import XCTest
@testable import UsageBarCore

final class VersionedInstallOrderingTests: XCTestCase {
    func testOrdersNumericallyNewestFirst() {
        XCTAssertEqual(
            VersionedInstallOrdering.newestFirst(["2.1.9", "2.1.281", "2.1.10", "1.9.999"]),
            ["2.1.281", "2.1.10", "2.1.9", "1.9.999"]
        )
    }

    func testRejectsNamesThatAreNotPlainVersions() {
        XCTAssertEqual(
            VersionedInstallOrdering.newestFirst([
                "2.1.0.tmp", ".DS_Store", "latest", "", "2..1", "2.1.", "-1.0", "2.1.3"
            ]),
            ["2.1.3"]
        )
    }

    func testMissingTrailingComponentsCountAsZero() {
        XCTAssertEqual(VersionedInstallOrdering.newestFirst(["2.1", "2.1.1"]), ["2.1.1", "2.1"])
    }
}
