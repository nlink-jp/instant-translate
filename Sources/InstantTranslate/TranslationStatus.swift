import Foundation

/// What the panel is doing — or deliberately not doing — right now.
///
/// The app has several states in which withholding a translation is the *correct*
/// behaviour (an open IME composition, input too short to identify, auto-translate
/// switched off). Before this existed they were all indistinguishable from a hang,
/// because a `Bool` can only say "running / not running".
///
/// See `docs/en/adr/0001-panel-feedback-and-failure-messages.md`.
enum TranslationPhase: Equatable {
    /// Nothing pending.
    case idle
    /// An input method is composing uncommitted text; `AutoTranslatePolicy` holds
    /// everything back until it commits.
    case composing
    /// The text isn't identifiable as any language yet, so an automatic run stood
    /// down rather than raising the OS source-language picker mid-sentence.
    case awaitingLanguage
    /// The debounce timer is armed — translating once typing pauses.
    case pending
    /// The OS language model for this pair is being prepared (downloaded on first use).
    case preparing
    /// A translation is in flight.
    case translating
    /// Source and target resolved to the same language, so the input was passed
    /// through unchanged. Without this the output looks identical to the input for
    /// no stated reason.
    case echoed
    /// A translation completed.
    case done
    /// A translation failed; `TranslationModel.failure` carries the detail.
    case failed
}

/// One rendering of the status row.
struct StatusDisplay: Equatable {
    enum Tone: Equatable {
        case neutral    // waiting, or nothing to do
        case active     // work in flight
        case success
        case failure
    }

    /// SF Symbol name. `nil` when a spinner occupies the same slot.
    let symbol: String?
    let text: String
    let showsSpinner: Bool
    let tone: Tone
}

/// Maps a phase to what the status row shows. Pure — unit-tested, in the same spirit
/// as `LanguagePolicy` and `AutoTranslatePolicy`.
enum TranslationStatus {
    /// - Parameters:
    ///   - phase: the current phase.
    ///   - hasInput: whether the source field holds anything but whitespace.
    ///   - autoTranslateEnabled: the `autoTranslate` setting.
    ///   - sourceName: the resolved input language's display name, nil when unresolved.
    ///   - targetName: the target language's display name.
    static func display(phase: TranslationPhase,
                        hasInput: Bool,
                        autoTranslateEnabled: Bool,
                        sourceName: String?,
                        targetName: String) -> StatusDisplay {
        let pair = pair(sourceName: sourceName, targetName: targetName)
        switch phase {
        case .idle:
            // With text sitting in the field and auto-translate off, silence reads as
            // a hang — name the shortcut that actually starts it.
            if hasInput && !autoTranslateEnabled {
                return StatusDisplay(symbol: "return",
                                     text: "Press ⌘↩ to translate",
                                     showsSpinner: false, tone: .neutral)
            }
            return StatusDisplay(symbol: "circle.dotted",
                                 text: "Ready",
                                 showsSpinner: false, tone: .neutral)
        case .composing:
            return StatusDisplay(symbol: "keyboard",
                                 text: "Waiting for the input method to finish…",
                                 showsSpinner: false, tone: .neutral)
        case .awaitingLanguage:
            return StatusDisplay(symbol: "questionmark.circle",
                                 text: "Can't tell the language yet — type more, or pin it on the left",
                                 showsSpinner: false, tone: .neutral)
        case .pending:
            return StatusDisplay(symbol: "clock",
                                 text: "Translating when you pause typing…",
                                 showsSpinner: false, tone: .neutral)
        case .preparing:
            return StatusDisplay(symbol: nil,
                                 text: "Preparing the \(pair) language model — the first use downloads it…",
                                 showsSpinner: true, tone: .active)
        case .translating:
            return StatusDisplay(symbol: nil,
                                 text: "Translating \(pair)…",
                                 showsSpinner: true, tone: .active)
        case .echoed:
            return StatusDisplay(symbol: "equal.circle",
                                 text: "Input is already \(targetName) — shown unchanged",
                                 showsSpinner: false, tone: .neutral)
        case .done:
            return StatusDisplay(symbol: "checkmark.circle",
                                 text: "Translated \(pair)",
                                 showsSpinner: false, tone: .success)
        case .failed:
            return StatusDisplay(symbol: "exclamationmark.triangle",
                                 text: "Couldn't translate",
                                 showsSpinner: false, tone: .failure)
        }
    }

    /// "Japanese → English", or just the target when the source is unresolved.
    static func pair(sourceName: String?, targetName: String) -> String {
        sourceName.map { "\($0) → \(targetName)" } ?? targetName
    }
}
