import Foundation

/// The pure rule for *when* a debounced automatic translation may be armed and run.
///
/// Split out of `PanelView` (as `LanguagePolicy` is for routing) so the conditions can
/// be unit-tested without a view, a `TranslationSession`, or a live input method.
///
/// The rule exists mostly to stay out of the way of an input method: translating text
/// that an IME is still composing yields nonsense, and undetectable input makes the OS
/// raise its source-language picker over the panel — both interrupt typing.
enum AutoTranslatePolicy {
    /// What a change to the source text should do.
    enum Action: Equatable {
        /// The input is empty — clear the previous output.
        case clearOutput
        /// Arm the debounce timer.
        case schedule
        /// Do nothing (auto-translate is off, or an IME composition is in flight).
        case ignore
    }

    static func action(forSourceText text: String,
                       autoTranslateEnabled: Bool,
                       isComposing: Bool) -> Action {
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return .clearOutput }
        guard autoTranslateEnabled, !isComposing else { return .ignore }
        return .schedule
    }

    /// Whether an armed auto-translation may actually fire once the timer elapses.
    ///
    /// - A composition may have opened while the timer was running — wait it out.
    /// - `resolvedSource` is the pinned source language, or the detected one when
    ///   nothing is pinned. `nil` means the text isn't recognisable as any language
    ///   yet (a couple of characters, or a half-typed romaji run). Handing that to
    ///   the translator makes macOS ask the user which language it is, in a picker
    ///   that steals focus mid-sentence — so an *automatic* run stands down and waits
    ///   for more text. A pin makes the source known, so the gate never holds it
    ///   back. A manual Translate is never gated by this: the user asked for it.
    static func mayRun(resolvedSource: String?, isComposing: Bool) -> Bool {
        resolvedSource != nil && !isComposing
    }
}
