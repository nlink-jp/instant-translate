import XCTest
@testable import InstantTranslate

@MainActor
final class TranslationModelTests: XCTestCase {
    private func model(local: String, secondary: String, autoSwap: Bool,
                       injected: TextTranslating = EchoTranslator()) -> TranslationModel {
        TranslationModel(
            settings: { SettingsStore(secondaryLanguage: secondary, autoSwapEnabled: autoSwap,
                                      clipboardAutoTranslate: true, copyOnTranslate: false) },
            localLanguage: local,
            injected: injected)
    }

    func testForeignInputTranslatesToLocalAndRecordsVolatileEntry() async {
        let m = model(local: "ja", secondary: "en", autoSwap: true)
        m.sourceText = "Hello"
        m.detectedSource = "en"
        await m.translateUsingInjected()

        XCTAssertEqual(m.targetLanguage, "ja")                 // foreign → local
        XCTAssertEqual(m.translatedText, "[ja] Hello")
        XCTAssertEqual(m.lastEntry, HistoryEntry(source: "Hello", translation: "[ja] Hello", target: "ja"))
        XCTAssertNil(m.errorMessage)
        XCTAssertFalse(m.isTranslating)
    }

    func testLocalInputSwapsToSecondary() async {
        let m = model(local: "ja", secondary: "en", autoSwap: true)
        m.sourceText = "こんにちは"
        m.detectedSource = "ja"
        await m.translateUsingInjected()

        XCTAssertEqual(m.targetLanguage, "en")                 // my language → secondary
        XCTAssertEqual(m.translatedText, "[en] こんにちは")
    }

    func testTargetOverrideWinsOverAutoRouting() async {
        let m = model(local: "ja", secondary: "en", autoSwap: true)
        m.targetOverride = "fr"
        m.sourceText = "Hello"
        m.detectedSource = "en"          // auto would route en → ja
        await m.translateUsingInjected()
        XCTAssertEqual(m.targetLanguage, "fr")
        XCTAssertEqual(m.translatedText, "[fr] Hello")
    }

    func testClearingOverrideReturnsToAutoRouting() {
        let m = model(local: "ja", secondary: "en", autoSwap: true)
        m.detectedSource = "en"
        m.targetOverride = "fr"; m.resolveTarget()
        XCTAssertEqual(m.targetLanguage, "fr")
        m.targetOverride = nil; m.resolveTarget()
        XCTAssertEqual(m.targetLanguage, "ja")   // en → ja (auto)
    }

    func testPinnedSourceWinsOverDetection() async {
        let m = model(local: "ja", secondary: "en", autoSwap: true)
        m.sourceOverride = "ja"          // user pinned the input language
        m.sourceText = "Hello"
        m.detectedSource = "en"          // auto would route en → ja
        await m.translateUsingInjected()

        XCTAssertEqual(m.targetLanguage, "en")   // pinned ja → secondary (auto-swap)
        XCTAssertEqual(m.translatedText, "[en] Hello")
    }

    func testPinnedSourceResolvesEvenWhenDetectionFails() {
        let m = model(local: "ja", secondary: "en", autoSwap: true)
        m.sourceOverride = "en"
        m.detectedSource = nil           // short/undetectable input
        XCTAssertEqual(m.resolvedSource, "en")
        m.resolveTarget()
        XCTAssertEqual(m.targetLanguage, "ja")   // pinned en → local
    }

    func testUnpinningReturnsToDetection() {
        let m = model(local: "ja", secondary: "en", autoSwap: true)
        m.detectedSource = "en"
        m.sourceOverride = "ja"; m.resolveTarget()
        XCTAssertEqual(m.targetLanguage, "en")   // pinned ja → secondary
        m.sourceOverride = nil; m.resolveTarget()
        XCTAssertEqual(m.targetLanguage, "ja")   // detected en → local
    }

    func testBlankSourceDoesNotRecordEntry() async {
        let m = model(local: "ja", secondary: "en", autoSwap: true)
        m.sourceText = "   "
        m.detectedSource = "en"
        await m.translateUsingInjected()

        XCTAssertNil(m.lastEntry)
    }

    func testFailureIsSurfaced() async {
        let m = model(local: "ja", secondary: "en", autoSwap: true, injected: ThrowingTranslator())
        m.sourceText = "Hello"
        m.detectedSource = "en"
        await m.translateUsingInjected()

        XCTAssertNotNil(m.errorMessage)
        XCTAssertFalse(m.isTranslating)
    }
}

/// A stub that always throws, to exercise the model's failure path.
private struct ThrowingTranslator: TextTranslating {
    struct Failure: Error {}
    func translate(_ text: String, source: String?, target: String) async throws -> String {
        throw Failure()
    }
}
