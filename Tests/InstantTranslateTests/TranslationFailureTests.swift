import Translation
import XCTest
@testable import InstantTranslate

/// The bug this file guards: `TranslationError.localizedDescription` reads
/// "Unable to Translate" for seven of its eight cases and every case bridges to
/// `NSError` domain `Translation.TranslationError` code 1, so the thrown error is
/// neither showable nor distinguishable by shape. `classify` must recover the
/// distinction, and `message` must turn it into something a user can act on.
final class TranslationFailureTests: XCTestCase {
    // MARK: - classify

    func testEveryFrameworkErrorIsPlaced() {
        let expected: [(TranslationError, TranslationFailure)] = [
            (.unsupportedSourceLanguage,  .unsupportedSourceLanguage),
            (.unsupportedTargetLanguage,  .unsupportedTargetLanguage),
            (.unsupportedLanguagePairing, .unsupportedLanguagePairing),
            (.unableToIdentifyLanguage,   .unableToIdentifyLanguage),
            (.nothingToTranslate,         .nothingToTranslate),
            (.alreadyCancelled,           .cancelled),
            (.notInstalled,               .notInstalled),
            (.internalError,              .frameworkInternal),
        ]
        for (error, failure) in expected {
            XCTAssertEqual(TranslationFailure.classify(error), failure,
                           "\(error.failureReason ?? "?") was misclassified")
        }
    }

    func testDistinctErrorsClassifyDistinctly() {
        // The whole point: eight inputs, eight different outcomes. A `~=` that matched
        // loosely would collapse them and silently reintroduce the original bug.
        let all: [TranslationError] = [
            .unsupportedSourceLanguage, .unsupportedTargetLanguage,
            .unsupportedLanguagePairing, .unableToIdentifyLanguage,
            .nothingToTranslate, .alreadyCancelled, .notInstalled, .internalError,
        ]
        let classified = all.map { TranslationFailure.classify($0) }
        XCTAssertEqual(Set(classified.map(\.tag)).count, all.count)
    }

    func testSwiftCancellationIsTreatedAsCancelled() {
        XCTAssertEqual(TranslationFailure.classify(CancellationError()), .cancelled)
    }

    func testUnknownErrorKeepsWhateverTextItHas() {
        struct Odd: LocalizedError {
            var errorDescription: String? { "generic headline" }
            var failureReason: String? { "the specific reason" }
        }
        let failure = TranslationFailure.classify(Odd())
        // `failureReason` is where the substance lives, so it must survive — the
        // original bug was discarding exactly this.
        guard case .unknown(let text) = failure else { return XCTFail("expected .unknown") }
        XCTAssertTrue(text.contains("the specific reason"), text)
    }

    func testUnknownErrorCarriesDomainAndCodeForABugReport() {
        let error = NSError(domain: "SomeDomain", code: 42,
                            userInfo: [NSLocalizedDescriptionKey: "boom"])
        guard case .unknown(let text) = TranslationFailure.classify(error) else {
            return XCTFail("expected .unknown")
        }
        XCTAssertTrue(text.contains("SomeDomain"), text)
        XCTAssertTrue(text.contains("42"), text)
    }

    // MARK: - message

    func testMessagesNameTheLanguagesInvolved() {
        let m = TranslationFailure.unsupportedPair.message(sourceName: "Japanese",
                                                           targetName: "Korean")
        XCTAssertTrue(m.headline.contains("Japanese → Korean"), m.headline)
    }

    func testMessagesDropTheArrowWhenTheSourceIsUnresolved() {
        // Detection can come up empty; a half-formed "→ English" pair would be worse
        // than no pair at all.
        let m = TranslationFailure.unsupportedPair.message(sourceName: nil,
                                                           targetName: "English")
        XCTAssertFalse(m.headline.contains("→"), m.headline)
        XCTAssertTrue(m.headline.contains("English"), m.headline)
    }

    func testEveryMessageHasANonEmptyHeadlineAndDetail() {
        for failure in allFailures {
            let m = failure.message(sourceName: "Japanese", targetName: "English")
            XCTAssertFalse(m.headline.isEmpty, "\(failure) has no headline")
            XCTAssertFalse(m.detail.isEmpty, "\(failure) has no detail")
            // "Unable to Translate" is the framework string this whole type exists to
            // replace — it must never reach the panel.
            XCTAssertFalse(m.headline.contains("Unable to Translate"),
                           "\(failure) leaked the framework's undifferentiated string")
        }
    }

    func testActionableFailuresSayWhatToDo() {
        // The failures a user can actually resolve must name the way out; only
        // `nothingToTranslate` (already fixed by typing) may omit it.
        for failure in allFailures where failure != .nothingToTranslate {
            XCTAssertNotNil(failure.message(sourceName: "Japanese", targetName: "English").recovery,
                            "\(failure) offers no recovery")
        }
    }

    func testUnsupportedTargetPointsAtTheTargetPicker() {
        let m = TranslationFailure.unsupportedTargetLanguage
            .message(sourceName: "Japanese", targetName: "Korean")
        XCTAssertTrue(m.headline.contains("Korean"), m.headline)
        XCTAssertTrue(m.recovery?.contains("right") == true, m.recovery ?? "nil")
    }

    func testUnsupportedSourcePointsAtTheSourcePicker() {
        let m = TranslationFailure.unsupportedSourceLanguage
            .message(sourceName: "Japanese", targetName: "Korean")
        XCTAssertTrue(m.headline.contains("Japanese"), m.headline)
        XCTAssertTrue(m.recovery?.contains("left") == true, m.recovery ?? "nil")
    }

    func testMissingModelOffersTheSystemSettingsRouteAsWellAsWaiting() {
        // The one case the old wording described correctly — it must not lose ground.
        let m = TranslationFailure.notInstalled.message(sourceName: "Japanese",
                                                        targetName: "English")
        XCTAssertTrue(m.headline.contains("Japanese → English"), m.headline)
        XCTAssertTrue(m.recovery?.contains("System Settings") == true, m.recovery ?? "nil")
    }

    func testUnknownFailureShowsItsCarriedTextAsTheDetail() {
        let m = TranslationFailure.unknown("SomeDomain 42: boom")
            .message(sourceName: nil, targetName: "English")
        XCTAssertEqual(m.detail, "SomeDomain 42: boom")
    }

    func testTagsAreSourceLevelIdentifiers() {
        XCTAssertEqual(TranslationFailure.notInstalled.tag, "TranslationError.notInstalled")
        XCTAssertEqual(TranslationFailure.unsupportedPair.tag,
                       "LanguageAvailability.Status.unsupported")
    }

    private let allFailures: [TranslationFailure] = [
        .unsupportedPair, .unsupportedSourceLanguage, .unsupportedTargetLanguage,
        .unsupportedLanguagePairing, .unableToIdentifyLanguage, .nothingToTranslate,
        .cancelled, .notInstalled, .frameworkInternal, .unknown("Domain 1: detail"),
    ]
}
