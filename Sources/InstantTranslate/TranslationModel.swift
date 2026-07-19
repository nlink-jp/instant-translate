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
    /// A manual target-language override (base subtag). `nil` = automatic routing
    /// (`LanguagePolicy`). In-memory only — resets to automatic on app restart.
    @Published var targetOverride: String?

    // Outputs
    @Published var translatedText: String = ""
    @Published var targetLanguage: String
    @Published var errorMessage: String?
    @Published var isTranslating: Bool = false

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
    /// the (possibly newly) detected source language.
    func resolveTarget() {
        if let targetOverride {
            targetLanguage = targetOverride     // keep the full identifier (e.g. "en-GB")
        } else {
            targetLanguage = settings()
                .policy(local: localLanguage)
                .target(forDetectedSource: detectedSource)
        }
    }

    /// Record a completed translation as the (volatile) most-recent entry.
    func apply(result: String) {
        translatedText = result
        errorMessage = nil
        isTranslating = false
        let trimmed = sourceText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            lastEntry = HistoryEntry(source: sourceText, translation: result, target: targetLanguage)
        }
    }

    /// Record a failure.
    func fail(_ message: String) {
        errorMessage = message
        isTranslating = false
    }

    /// Tests / previews: run the injected translator end-to-end. In production this
    /// path is unused — `PanelView` owns the `TranslationSession` and calls
    /// `apply(result:)` / `fail(_:)` directly.
    func translateUsingInjected() async {
        guard let injected else { return }
        isTranslating = true
        errorMessage = nil
        resolveTarget()
        do {
            let out = try await injected.translate(sourceText, source: detectedSource, target: targetLanguage)
            apply(result: out)
        } catch {
            fail(error.localizedDescription)
        }
    }
}
