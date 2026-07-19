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
}
