import Combine
import Foundation

/// A single volatile translation record. Held in memory only — never persisted;
/// cleared when the app quits (the RFP's "most-recent-one, volatile" history).
struct HistoryEntry: Equatable {
    var source: String
    var translation: String
    var target: String
}

/// UI-facing state + orchestration for a translation.
///
/// The routing decision lives in the pure `LanguagePolicy`; the actual translation
/// is performed either by the real `TranslationSession` (driven by `PanelView` via
/// `.translationTask`, which calls `apply(result:)`), or — in tests/previews — by
/// an injected `TextTranslating` through `translateUsingInjected()`.
///
/// All mutations happen on the main thread (from SwiftUI views or tests), matching
/// the sibling apps' `ObservableObject` isolation model.
final class TranslationModel: ObservableObject {
    // Inputs
    @Published var sourceText: String = ""
    @Published var detectedSource: String?
    /// True while an input method is composing uncommitted text in the source field
    /// (kana-kanji conversion and friends). Mirrored from the text view by
    /// `SourceTextView`; gates auto-translate via `AutoTranslatePolicy`.
    @Published var isComposing: Bool = false
    /// A manual target-language override (base subtag). `nil` = automatic routing
    /// (`LanguagePolicy`). In-memory only — resets to automatic on app restart.
    @Published var targetOverride: String?
    /// A manual *source*-language pin (base subtag). `nil` = automatic detection.
    /// When set, detection is bypassed entirely — the pinned language is what the
    /// routing policy and the Translation framework see. In-memory only, like
    /// `targetOverride` — resets to automatic on app restart.
    @Published var sourceOverride: String?

    /// The source language everything downstream acts on: the pin when set,
    /// otherwise whatever detection produced (which may be `nil`).
    var resolvedSource: String? { sourceOverride ?? detectedSource }

    // Outputs
    @Published var translatedText: String = ""
    @Published var targetLanguage: String
    /// The current failure, if any — headline / recovery / technical detail. Set by
    /// `fail(_:)`, cleared by every path that starts or clears a translation.
    @Published var failure: FailureMessage?
    /// What the panel is doing (or deliberately not doing). Drives the status row;
    /// see `TranslationStatus`.
    @Published var phase: TranslationPhase = .idle

    /// True while work is actually in flight (as opposed to waiting or held back).
    var isTranslating: Bool { phase == .preparing || phase == .translating }
    /// The failure headline, for call sites that only need one line.
    var errorMessage: String? { failure?.headline }

    /// The single volatile "most recent" entry (not persisted).
    @Published private(set) var lastEntry: HistoryEntry?

    private let settings: () -> SettingsStore
    private let localLanguage: String
    private let injected: TextTranslating?

    init(settings: @escaping () -> SettingsStore = { SettingsStore.current() },
         localLanguage: String = SettingsStore.localLanguage(),
         injected: TextTranslating? = nil) {
        self.settings = settings
        self.localLanguage = localLanguage
        self.injected = injected
        self.targetLanguage = settings().policy(local: localLanguage).target(forDetectedSource: nil)
    }

    /// Recompute the target: a manual override wins; otherwise the policy routes from
    /// the resolved source language (pin or detection).
    func resolveTarget() {
        if let targetOverride {
            targetLanguage = targetOverride     // keep the full identifier (e.g. "en-GB")
        } else {
            targetLanguage = settings()
                .policy(local: localLanguage)
                .target(forDetectedSource: resolvedSource)
        }
    }

    /// Record a completed translation as the (volatile) most-recent entry.
    ///
    /// `echoed` marks the source == target pass-through, which produces output
    /// identical to the input and needs the status row to say why.
    func apply(result: String, echoed: Bool = false) {
        translatedText = result
        failure = nil
        phase = echoed ? .echoed : .done
        let trimmed = sourceText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            lastEntry = HistoryEntry(source: sourceText, translation: result, target: targetLanguage)
        }
    }

    /// Record a failure.
    func fail(_ message: FailureMessage) {
        failure = message
        phase = .failed
    }

    /// Record a failure from a thrown error, phrased with the languages in play.
    func fail(_ error: any Error, sourceName: String?, targetName: String) {
        fail(TranslationFailure.classify(error).message(sourceName: sourceName,
                                                        targetName: targetName))
    }

    /// Tests / previews: run the injected translator end-to-end. In production this
    /// path is unused — `PanelView` owns the `TranslationSession` and calls
    /// `apply(result:)` / `fail(_:)` directly.
    func translateUsingInjected() async {
        guard let injected else { return }
        phase = .translating
        failure = nil
        resolveTarget()
        do {
            let out = try await injected.translate(sourceText, source: resolvedSource, target: targetLanguage)
            apply(result: out)
        } catch {
            fail(error, sourceName: resolvedSource, targetName: targetLanguage)
        }
    }
}
