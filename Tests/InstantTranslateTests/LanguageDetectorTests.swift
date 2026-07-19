import XCTest
@testable import InstantTranslate

final class LanguageDetectorTests: XCTestCase {
    func testDetectsEnglish() {
        XCTAssertEqual(LanguageDetector.detect("The quick brown fox jumps over the lazy dog."), "en")
    }

    func testDetectsJapanese() {
        XCTAssertEqual(LanguageDetector.detect("これは日本語の文章です。翻訳のテストをしています。"), "ja")
    }

    func testEmptyOrBlankReturnsNil() {
        XCTAssertNil(LanguageDetector.detect(""))
        XCTAssertNil(LanguageDetector.detect("   \n "))
    }

    func testResultIsBaseSubtag() {
        // Chinese may be reported as "zh-Hans"; the detector normalises to "zh".
        if let zh = LanguageDetector.detect("这是一段用来测试语言检测功能的中文文本。") {
            XCTAssertEqual(zh, "zh")
        }
    }
}
