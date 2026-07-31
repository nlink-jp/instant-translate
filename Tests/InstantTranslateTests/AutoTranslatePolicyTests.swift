import XCTest
@testable import InstantTranslate

final class AutoTranslatePolicyTests: XCTestCase {
    // MARK: - action(forSourceText:…)

    func testTypedTextArmsTheTimer() {
        XCTAssertEqual(
            AutoTranslatePolicy.action(forSourceText: "hello",
                                       autoTranslateEnabled: true, isComposing: false),
            .schedule)
    }

    func testEmptyInputClearsTheOutput() {
        for text in ["", "   ", "\n\t "] {
            XCTAssertEqual(
                AutoTranslatePolicy.action(forSourceText: text,
                                           autoTranslateEnabled: true, isComposing: false),
                .clearOutput, "whitespace-only input should clear, not translate: \(text.debugDescription)")
        }
    }

    func testEmptyInputStillClearsWhileComposing() {
        // A composition that has been backspaced away leaves an empty field — the stale
        // translation must not linger.
        XCTAssertEqual(
            AutoTranslatePolicy.action(forSourceText: "",
                                       autoTranslateEnabled: true, isComposing: true),
            .clearOutput)
    }

    func testCompositionSuppressesScheduling() {
        // The kana-kanji bug: mid-conversion text must never arm a translation.
        XCTAssertEqual(
            AutoTranslatePolicy.action(forSourceText: "にほんご",
                                       autoTranslateEnabled: true, isComposing: true),
            .ignore)
    }

    func testDisabledAutoTranslateIgnoresChanges() {
        XCTAssertEqual(
            AutoTranslatePolicy.action(forSourceText: "hello",
                                       autoTranslateEnabled: false, isComposing: false),
            .ignore)
    }

    // MARK: - mayRun(resolvedSource:isComposing:)

    func testMayRunWithAResolvedLanguage() {
        // Detected — or pinned: a pin resolves the source even when the text itself
        // is undetectable, so the gate must let the run through either way.
        XCTAssertTrue(AutoTranslatePolicy.mayRun(resolvedSource: "ja", isComposing: false))
    }

    func testStandsDownWhenTheLanguageIsUnresolvable() {
        // No pin and undetectable input makes macOS raise its source-language picker
        // over the panel; an automatic run must never trigger that.
        XCTAssertFalse(AutoTranslatePolicy.mayRun(resolvedSource: nil, isComposing: false))
    }

    func testStandsDownIfACompositionOpenedWhileTheTimerRan() {
        XCTAssertFalse(AutoTranslatePolicy.mayRun(resolvedSource: "ja", isComposing: true))
    }
}
