import Foundation
import Translation

/// A failure message as the panel presents it: what happened, what to do, and the
/// exact technical cause for a bug report.
///
/// The app has no menu bar, no About item and no log file, so whatever the panel
/// shows *is* the diagnostic surface — hence `detail`, which is rendered small and
/// selectable next to the (equally selectable) version string.
struct FailureMessage: Equatable {
    /// What went wrong, in plain words, naming the actual languages.
    let headline: String
    /// What the user can do about it, naming the control that does it.
    let recovery: String?
    /// The technical cause, verbatim — for a bug report.
    let detail: String
}

/// Every way a translation can fail, named.
///
/// `TranslationError.localizedDescription` collapses seven of its eight cases to the
/// single string "Unable to Translate", and the `NSError` bridge reports domain
/// `Translation.TranslationError` code 1 for all of them — so the error as thrown
/// cannot be shown to a user and cannot be told apart by shape. The discriminating
/// text lives in `failureReason`, and the cases themselves are distinguishable only
/// through `TranslationError`'s custom `~=`. This enum does that matching once, in
/// `classify`, so everything downstream works with a value it can reason about.
///
/// See `docs/en/adr/0001-panel-feedback-and-failure-messages.md`.
enum TranslationFailure: Equatable {
    /// Our own pre-flight verdict (`LanguageAvailability.status` == `.unsupported`),
    /// reached before a session is ever used.
    case unsupportedPair
    case unsupportedSourceLanguage
    case unsupportedTargetLanguage
    case unsupportedLanguagePairing
    case unableToIdentifyLanguage
    case nothingToTranslate
    case cancelled
    case notInstalled
    case frameworkInternal
    /// Something outside the known set. Carries whatever text the error could supply
    /// — without this, an unanticipated error would reproduce the original bug.
    case unknown(String)

    /// Place a thrown error. The only function in the app that matches against
    /// `TranslationError`; everything else consumes the result.
    static func classify(_ error: any Error) -> TranslationFailure {
        switch error {
        case TranslationError.unsupportedSourceLanguage:  return .unsupportedSourceLanguage
        case TranslationError.unsupportedTargetLanguage:  return .unsupportedTargetLanguage
        case TranslationError.unsupportedLanguagePairing: return .unsupportedLanguagePairing
        case TranslationError.unableToIdentifyLanguage:   return .unableToIdentifyLanguage
        case TranslationError.nothingToTranslate:         return .nothingToTranslate
        case TranslationError.alreadyCancelled:           return .cancelled
        case TranslationError.notInstalled:               return .notInstalled
        case TranslationError.internalError:              return .frameworkInternal
        case is CancellationError:                        return .cancelled
        default:                                          return .unknown(describe(error))
        }
    }

    /// The most informative text an unplaced error can give us. `failureReason` is
    /// preferred because that is where the Translation framework puts the substance;
    /// the domain/code tail is what makes an unknown error reportable.
    private static func describe(_ error: any Error) -> String {
        let ns = error as NSError
        let reason = (error as? any LocalizedError)?.failureReason
        let text = reason ?? error.localizedDescription
        return "\(text) [\(ns.domain) \(ns.code)]"
    }

    /// The user-facing message. Pure — unit-tested.
    ///
    /// `sourceName` is nil when nothing is pinned and detection came up empty; the
    /// wording drops the arrow rather than printing a half-formed pair.
    func message(sourceName: String?, targetName: String) -> FailureMessage {
        let pair = sourceName.map { "\($0) → \(targetName)" }
        switch self {
        case .unsupportedPair, .unsupportedLanguagePairing:
            return FailureMessage(
                headline: pair.map { "macOS can't translate \($0)." }
                    ?? "macOS can't translate this input into \(targetName).",
                recovery: "Choose a different target language on the right, or pin a different input language on the left.",
                detail: tag)
        case .unsupportedSourceLanguage:
            return FailureMessage(
                headline: sourceName.map { "macOS can't translate from \($0)." }
                    ?? "macOS can't translate from this input's language.",
                recovery: "Pin a different input language with the left picker.",
                detail: tag)
        case .unsupportedTargetLanguage:
            return FailureMessage(
                headline: "macOS can't translate into \(targetName).",
                recovery: "Choose a different target language with the right picker.",
                detail: tag)
        case .unableToIdentifyLanguage:
            return FailureMessage(
                headline: "macOS couldn't tell which language the input is.",
                recovery: "Type a little more, or pin the input language with the left picker.",
                detail: tag)
        case .nothingToTranslate:
            return FailureMessage(
                headline: "There was nothing to translate.",
                recovery: nil,
                detail: tag)
        case .cancelled:
            return FailureMessage(
                headline: "The translation was cancelled before it finished.",
                recovery: "Press ⌘↩ to translate again.",
                detail: tag)
        case .notInstalled:
            return FailureMessage(
                headline: pair.map { "The \($0) language model isn't on this Mac yet." }
                    ?? "The language model for \(targetName) isn't on this Mac yet.",
                recovery: "macOS downloads it on first use — allow the download when it asks. You can also install it ahead of time in System Settings › General › Language & Region › Translation Languages.",
                detail: tag)
        case .frameworkInternal:
            return FailureMessage(
                headline: "The macOS translation service failed.",
                recovery: "Try again. If it keeps failing, quitting and reopening instant-translate usually clears it.",
                detail: tag)
        case .unknown(let text):
            return FailureMessage(
                headline: "The translation failed for an unrecognised reason.",
                recovery: "Try again; if it repeats, please include the line below in a bug report.",
                detail: text)
        }
    }

    /// The technical cause, as it would be written in source — the string a bug
    /// report should carry.
    var tag: String {
        switch self {
        case .unsupportedPair:            return "LanguageAvailability.Status.unsupported"
        case .unsupportedSourceLanguage:  return "TranslationError.unsupportedSourceLanguage"
        case .unsupportedTargetLanguage:  return "TranslationError.unsupportedTargetLanguage"
        case .unsupportedLanguagePairing: return "TranslationError.unsupportedLanguagePairing"
        case .unableToIdentifyLanguage:   return "TranslationError.unableToIdentifyLanguage"
        case .nothingToTranslate:         return "TranslationError.nothingToTranslate"
        case .cancelled:                  return "TranslationError.alreadyCancelled"
        case .notInstalled:               return "TranslationError.notInstalled"
        case .frameworkInternal:          return "TranslationError.internalError"
        case .unknown(let text):          return text
        }
    }
}
