import XCTest
@testable import InstantTranslate

final class LanguagePolicyTests: XCTestCase {
    func testForeignSourceRoutesToLocal() {
        let p = LanguagePolicy(local: "ja", secondary: "en", autoSwap: true)
        XCTAssertEqual(p.target(forDetectedSource: "en"), "ja")
        XCTAssertEqual(p.target(forDetectedSource: "fr"), "ja")
    }

    func testLocalSourceSwapsToSecondaryWhenEnabled() {
        let p = LanguagePolicy(local: "ja", secondary: "en", autoSwap: true)
        XCTAssertEqual(p.target(forDetectedSource: "ja"), "en")
    }

    func testLocalSourceStaysLocalWhenSwapDisabled() {
        let p = LanguagePolicy(local: "ja", secondary: "en", autoSwap: false)
        XCTAssertEqual(p.target(forDetectedSource: "ja"), "ja")
    }

    func testUnknownSourceDefaultsToLocal() {
        let p = LanguagePolicy(local: "ja", secondary: "en", autoSwap: true)
        XCTAssertEqual(p.target(forDetectedSource: nil), "ja")
    }

    func testTargetPreservesRegionalIdentifier() {
        // The secondary's regional variant must survive to the target (not collapse to "en").
        let p = LanguagePolicy(local: "ja", secondary: "en-GB", autoSwap: true)
        XCTAssertEqual(p.target(forDetectedSource: "ja"), "en-GB")     // native input → secondary variant
        XCTAssertEqual(p.target(forDetectedSource: "en-US"), "ja")     // foreign input → local
        XCTAssertFalse(p.isNoop(detectedSource: "en-US"))             // en → ja
        // Comparison still uses base subtags:
        XCTAssertEqual(p.target(forDetectedSource: "ja_JP"), "en-GB")
    }

    func testIsNoop() {
        let swapOff = LanguagePolicy(local: "ja", secondary: "en", autoSwap: false)
        XCTAssertTrue(swapOff.isNoop(detectedSource: "ja"))          // ja → ja
        let swapOn = LanguagePolicy(local: "ja", secondary: "en", autoSwap: true)
        XCTAssertFalse(swapOn.isNoop(detectedSource: "ja"))          // ja → en
        XCTAssertFalse(swapOn.isNoop(detectedSource: "en"))          // en → ja
        XCTAssertFalse(swapOn.isNoop(detectedSource: nil))           // unknown
    }

    func testBaseNormalisation() {
        XCTAssertEqual(LanguagePolicy.base("EN-US"), "en")
        XCTAssertEqual(LanguagePolicy.base("zh_Hans_CN"), "zh")
        XCTAssertEqual(LanguagePolicy.base("ja"), "ja")
    }
}
