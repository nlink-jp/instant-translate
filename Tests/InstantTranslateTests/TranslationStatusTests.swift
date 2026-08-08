import XCTest
@testable import InstantTranslate

/// The panel used to render nothing at all for any of these phases, so a translation
/// that was correctly waiting looked exactly like one that had hung. Each test below
/// pins one of those states to a visible, distinct line.
final class TranslationStatusTests: XCTestCase {
    private func display(_ phase: TranslationPhase,
                         hasInput: Bool = true,
                         autoTranslate: Bool = true,
                         source: String? = "Japanese",
                         target: String = "English") -> StatusDisplay {
        TranslationStatus.display(phase: phase, hasInput: hasInput,
                                  autoTranslateEnabled: autoTranslate,
                                  sourceName: source, targetName: target)
    }

    func testWorkInFlightShowsASpinner() {
        for phase in [TranslationPhase.preparing, .translating] {
            XCTAssertTrue(display(phase).showsSpinner, "\(phase) should spin")
            XCTAssertEqual(display(phase).tone, .active)
        }
    }

    func testWaitingStatesDoNotSpin() {
        // These are holds, not work — a spinner would claim progress that isn't there.
        for phase in [TranslationPhase.idle, .composing, .awaitingLanguage, .pending,
                      .echoed, .done, .failed] {
            XCTAssertFalse(display(phase).showsSpinner, "\(phase) should not spin")
        }
    }

    func testInFlightStatesNameThePair() {
        XCTAssertTrue(display(.translating).text.contains("Japanese → English"))
        XCTAssertTrue(display(.preparing).text.contains("Japanese → English"))
        XCTAssertTrue(display(.done).text.contains("Japanese → English"))
    }

    func testPreparingExplainsTheFirstUseDownload() {
        // This is the multi-second wait that used to happen with no explanation.
        XCTAssertTrue(display(.preparing).text.lowercased().contains("download"),
                      display(.preparing).text)
    }

    func testComposingSaysAnInputMethodIsHoldingThings() {
        XCTAssertTrue(display(.composing).text.lowercased().contains("input method"),
                      display(.composing).text)
    }

    func testUndetectableInputNamesBothWaysOut() {
        // Type more, or pin the language — otherwise this state is indistinguishable
        // from a hang.
        let text = display(.awaitingLanguage).text.lowercased()
        XCTAssertTrue(text.contains("type more"), text)
        XCTAssertTrue(text.contains("pin"), text)
    }

    func testEchoExplainsWhyOutputMatchesInput() {
        let text = display(.echoed, source: "English", target: "English").text
        XCTAssertTrue(text.contains("English"), text)
        XCTAssertTrue(text.lowercased().contains("unchanged"), text)
    }

    func testIdleWithTextAndAutoTranslateOffNamesTheShortcut() {
        // Nothing is scheduled and nothing will be — say what starts it.
        let text = display(.idle, hasInput: true, autoTranslate: false).text
        XCTAssertTrue(text.contains("⌘↩"), text)
    }

    func testIdleWithNoInputIsJustReady() {
        let text = display(.idle, hasInput: false, autoTranslate: false).text
        XCTAssertFalse(text.contains("⌘↩"), text)
    }

    func testIdleWithAutoTranslateOnDoesNotPromptForTheShortcut() {
        let text = display(.idle, hasInput: true, autoTranslate: true).text
        XCTAssertFalse(text.contains("⌘↩"), text)
    }

    func testFailureAndSuccessAreTonedApart() {
        XCTAssertEqual(display(.failed).tone, .failure)
        XCTAssertEqual(display(.done).tone, .success)
    }

    func testEveryPhaseSaysSomething() {
        // The row is always rendered; an empty string would be a silent panel again.
        for phase in [TranslationPhase.idle, .composing, .awaitingLanguage, .pending,
                      .preparing, .translating, .echoed, .done, .failed] {
            XCTAssertFalse(display(phase).text.isEmpty, "\(phase) renders nothing")
        }
    }

    func testEverySpinnerlessPhaseHasASymbol() {
        for phase in [TranslationPhase.idle, .composing, .awaitingLanguage, .pending,
                      .echoed, .done, .failed] {
            XCTAssertNotNil(display(phase).symbol, "\(phase) has neither spinner nor symbol")
        }
    }

    func testUnresolvedSourceFallsBackToTheTargetAlone() {
        XCTAssertEqual(TranslationStatus.pair(sourceName: nil, targetName: "English"), "English")
        XCTAssertEqual(TranslationStatus.pair(sourceName: "Japanese", targetName: "English"),
                       "Japanese → English")
        XCTAssertFalse(display(.translating, source: nil).text.contains("→"))
    }
}
