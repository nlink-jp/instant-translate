import XCTest
@testable import InstantTranslate

final class SingleInstanceTests: XCTestCase {
    func testBareDevBinaryAlwaysProceeds() {
        // No bundle identifier → instances cannot be enumerated; never exit.
        XCTAssertEqual(
            singleInstanceDecision(bundleID: nil, ownPID: 1, instancePIDs: [2, 3]),
            .proceed
        )
    }

    func testNoRunningInstancesProceeds() {
        XCTAssertEqual(
            singleInstanceDecision(
                bundleID: "jp.nlink.instant-translate", ownPID: 42, instancePIDs: []
            ),
            .proceed
        )
    }

    func testOwnPIDAloneProceeds() {
        // The enumeration may include the launching process itself.
        XCTAssertEqual(
            singleInstanceDecision(
                bundleID: "jp.nlink.instant-translate", ownPID: 42, instancePIDs: [42]
            ),
            .proceed
        )
    }

    func testAnotherInstanceExits() {
        guard case .exitDuplicate(let message) = singleInstanceDecision(
            bundleID: "jp.nlink.instant-translate", ownPID: 42, instancePIDs: [97316]
        ) else {
            return XCTFail("expected exitDuplicate")
        }
        XCTAssertTrue(message.contains("97316"))
        XCTAssertTrue(message.contains("already running"))
    }

    func testAllOtherPIDsAreListed() {
        guard case .exitDuplicate(let message) = singleInstanceDecision(
            bundleID: "jp.nlink.instant-translate", ownPID: 1, instancePIDs: [1, 2, 3]
        ) else {
            return XCTFail("expected exitDuplicate")
        }
        XCTAssertTrue(message.contains("2, 3"))
        XCTAssertFalse(message.contains("1,"))
    }
}
