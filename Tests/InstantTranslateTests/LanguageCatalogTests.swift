import XCTest
@testable import InstantTranslate

final class LanguageCatalogTests: XCTestCase {
    private let en = Locale(identifier: "en")

    func testQualifiesOnlyMultiVariantLanguages() {
        let infos = [
            LanguageCatalog.LangInfo(id: "en", base: "en", region: "US", script: "Latn"),
            LanguageCatalog.LangInfo(id: "en-GB", base: "en", region: "GB", script: "Latn"),
            LanguageCatalog.LangInfo(id: "ja", base: "ja", region: "JP", script: "Jpan"),
        ]
        let byId = Dictionary(uniqueKeysWithValues:
            LanguageCatalog.options(from: infos, locale: en).map { ($0.id, $0.name) })
        XCTAssertEqual(byId["en"], "English (United States)")
        XCTAssertEqual(byId["en-GB"], "English (United Kingdom)")
        XCTAssertEqual(byId["ja"], "Japanese")   // single variant → no region qualifier
    }

    func testDedupesById() {
        let infos = [
            LanguageCatalog.LangInfo(id: "en", base: "en", region: "US", script: "Latn"),
            LanguageCatalog.LangInfo(id: "en", base: "en", region: "US", script: "Latn"),
        ]
        XCTAssertEqual(LanguageCatalog.options(from: infos, locale: en).count, 1)
    }

    func testEmptyInput() {
        XCTAssertTrue(LanguageCatalog.options(from: [], locale: en).isEmpty)
    }

    func testSortedByName() {
        let infos = [
            LanguageCatalog.LangInfo(id: "ja", base: "ja", region: "JP", script: "Jpan"),
            LanguageCatalog.LangInfo(id: "en", base: "en", region: "US", script: "Latn"),
            LanguageCatalog.LangInfo(id: "fr", base: "fr", region: "FR", script: "Latn"),
        ]
        let names = LanguageCatalog.options(from: infos, locale: en).map(\.name)
        XCTAssertEqual(names, names.sorted { $0.localizedCompare($1) == .orderedAscending })
    }

    // MARK: - sourceOptions — the base-language list for the source pin picker

    func testSourceOptionsCollapseRegionalVariants() {
        let options = [
            LanguageOption(id: "en", name: "English (United States)"),
            LanguageOption(id: "en-GB", name: "English (United Kingdom)"),
            LanguageOption(id: "ja", name: "Japanese"),
        ]
        let sources = LanguageCatalog.sourceOptions(from: options, locale: en)
        XCTAssertEqual(sources.map(\.id), ["en", "ja"])
        XCTAssertEqual(sources.map(\.name), ["English", "Japanese"])   // no qualifier
    }

    func testSourceOptionsStaySortedByName() {
        let options = [
            LanguageOption(id: "ja", name: "Japanese"),
            LanguageOption(id: "fr", name: "French"),
        ]
        XCTAssertEqual(LanguageCatalog.sourceOptions(from: options, locale: en).map(\.id),
                       ["fr", "ja"])
    }
}
