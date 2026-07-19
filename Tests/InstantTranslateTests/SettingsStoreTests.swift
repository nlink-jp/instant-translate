import XCTest
@testable import InstantTranslate

final class SettingsStoreTests: XCTestCase {
    private func ephemeral() -> UserDefaults {
        let suite = "instant-translate-test-\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suite)!
        d.removePersistentDomain(forName: suite)
        return d
    }

    func testDefaultSecondaryIsEnglishForJapaneseLocale() {
        XCTAssertEqual(SettingsStore.systemDefaultSecondary(Locale(identifier: "ja_JP")), "en")
    }

    func testDefaultSecondaryIsJapaneseForEnglishLocale() {
        XCTAssertEqual(SettingsStore.systemDefaultSecondary(Locale(identifier: "en_US")), "ja")
    }

    func testLocalLanguageIsBaseSubtag() {
        XCTAssertEqual(SettingsStore.localLanguage(Locale(identifier: "zh_Hans_CN")), "zh")
        XCTAssertEqual(SettingsStore.localLanguage(Locale(identifier: "ja_JP")), "ja")
    }

    func testCurrentReadsRegisteredDefaults() {
        let d = ephemeral()
        SettingsKey.registerDefaults(d)
        let s = SettingsStore.current(d)
        XCTAssertTrue(s.autoSwapEnabled)
        XCTAssertTrue(s.autoTranslate)
        XCTAssertTrue(s.clipboardAutoTranslate)
        XCTAssertFalse(s.copyOnTranslate)
        XCTAssertFalse(s.secondaryLanguage.isEmpty)
    }

    func testPolicyBuiltFromSettings() {
        let s = SettingsStore(secondaryLanguage: "en", autoSwapEnabled: true,
                              clipboardAutoTranslate: true, copyOnTranslate: false)
        let p = s.policy(local: "ja")
        XCTAssertEqual(p.target(forDetectedSource: "ja"), "en")     // my language → secondary
        XCTAssertEqual(p.target(forDetectedSource: "en"), "ja")     // foreign → my language
    }
}
