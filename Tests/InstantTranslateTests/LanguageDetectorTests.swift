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

    func testPreferredLanguagesDoNotDisturbAClearWinner() {
        // Unambiguous English must stay English even with ja first in the preferences.
        XCTAssertEqual(
            LanguageDetector.detect("The quick brown fox jumps over the lazy dog.",
                                    preferred: ["ja", "en"]),
            "en")
    }

    // MARK: - resolve(hypotheses:preferred:) — the pure tie-break rule

    func testAmbiguousCandidatesFallToThePreferredLanguage() {
        // The kanji-only coin toss: ja and zh in contention → the preferred ja wins
        // even though zh scored (slightly) higher.
        XCTAssertEqual(
            LanguageDetector.resolve(hypotheses: ["zh-Hans": 0.45, "ja": 0.40],
                                     preferred: ["ja", "en"]),
            "ja")
    }

    func testHigherProbabilityPreferredLanguageBeatsListOrder() {
        // Both preferred languages are in contention — probability decides, not the
        // order of the preference list (ja is listed first but en clearly leads).
        XCTAssertEqual(
            LanguageDetector.resolve(hypotheses: ["en": 0.60, "ja": 0.35],
                                     preferred: ["ja", "en"]),
            "en")
    }

    func testDistantPreferredLanguageCannotSteal() {
        // A preferred language far below the winner is not "in contention".
        XCTAssertEqual(
            LanguageDetector.resolve(hypotheses: ["fr": 0.90, "en": 0.08],
                                     preferred: ["en"]),
            "fr")
    }

    func testNoPreferredMatchKeepsTheRawWinner() {
        XCTAssertEqual(
            LanguageDetector.resolve(hypotheses: ["ko": 0.55, "zh-Hant": 0.30],
                                     preferred: ["ja", "en"]),
            "ko")
    }

    func testScriptVariantsMergeToTheBaseLanguage() {
        // zh-Hans + zh-Hant together outweigh ko once merged by base subtag.
        XCTAssertEqual(
            LanguageDetector.resolve(hypotheses: ["zh-Hans": 0.30, "zh-Hant": 0.25, "ko": 0.40],
                                     preferred: []),
            "zh")
    }

    func testEmptyHypothesesResolveToNil() {
        XCTAssertNil(LanguageDetector.resolve(hypotheses: [:], preferred: ["ja"]))
    }
}
