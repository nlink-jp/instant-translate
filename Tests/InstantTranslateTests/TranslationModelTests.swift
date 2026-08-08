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

    // MARK: - Phase

    func testASuccessfulTranslationEndsInDone() async {
        let m = model(local: "ja", secondary: "en", autoSwap: true)
        m.sourceText = "Hello"
        m.detectedSource = "en"
        await m.translateUsingInjected()
        XCTAssertEqual(m.phase, .done)
    }

    func testAnEchoIsDistinguishableFromARealTranslation() {
        // Output identical to input needs its own phase — otherwise the status row
        // claims a translation that never happened.
        let m = model(local: "ja", secondary: "en", autoSwap: true)
        m.sourceText = "Hello"
        m.apply(result: "Hello", echoed: true)
        XCTAssertEqual(m.phase, .echoed)
    }

    func testFailureCarriesAHeadlineRecoveryAndDetail() async {
        let m = model(local: "ja", secondary: "en", autoSwap: true, injected: ThrowingTranslator())
        m.sourceText = "Hello"
        m.detectedSource = "en"
        await m.translateUsingInjected()

        XCTAssertEqual(m.phase, .failed)
        let failure = try? XCTUnwrap(m.failure)
        XCTAssertNotNil(failure)
        XCTAssertFalse(failure?.detail.isEmpty ?? true)          // reportable
        XCTAssertEqual(m.errorMessage, failure?.headline)
    }

    func testIsTranslatingCoversPreparingAsWellAsTranslating() {
        // The model download is work in flight too — the spinner must not stop for it.
        let m = model(local: "ja", secondary: "en", autoSwap: true)
        m.phase = .preparing
        XCTAssertTrue(m.isTranslating)
        m.phase = .translating
        XCTAssertTrue(m.isTranslating)
        for phase in [TranslationPhase.idle, .composing, .awaitingLanguage, .pending,
                      .echoed, .done, .failed] {
            m.phase = phase
            XCTAssertFalse(m.isTranslating, "\(phase) is not work in flight")
        }
    }
}

/// A stub that always throws, to exercise the model's failure path.
private struct ThrowingTranslator: TextTranslating {
    struct Failure: Error {}
    func translate(_ text: String, source: String?, target: String) async throws -> String {
        throw Failure()
    }
}
