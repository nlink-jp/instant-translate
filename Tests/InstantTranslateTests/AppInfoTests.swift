import XCTest
@testable import InstantTranslate

final class AppInfoTests: XCTestCase {
    func testBundleVersionIsShownVerbatim() {
        // The org's Info.plist carries a `git describe` string with a leading "v"
        // (and possibly a `-dirty` suffix) — show it as-is, so a user reporting a
        // problem quotes the exact build.
        XCTAssertEqual(AppInfo.version(fromBundleValue: "v0.1.3"), "v0.1.3")
        XCTAssertEqual(AppInfo.version(fromBundleValue: "v0.1.2-3-gabc1234-dirty"),
                       "v0.1.2-3-gabc1234-dirty")
    }

    func testFallsBackToDevWithoutABundleValue() {
        // `swift run` / `make run` has no bundle Info.plist.
        XCTAssertEqual(AppInfo.version(fromBundleValue: nil), "dev")
    }

    func testFallsBackToDevOnABlankValue() {
        // An empty label would read as a UI glitch rather than a version.
        XCTAssertEqual(AppInfo.version(fromBundleValue: ""), "dev")
        XCTAssertEqual(AppInfo.version(fromBundleValue: "   "), "dev")
    }
}
