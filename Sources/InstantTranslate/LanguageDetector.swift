import Foundation
import NaturalLanguage

/// On-device dominant-language detection for the input text, used to route the
/// translation target (see `LanguagePolicy`). Kept separate from the pure policy so
/// the routing rule stays testable without a model, and so the detector can be
/// swapped/expanded independently.
enum LanguageDetector {
    /// The dominant language of `text` as a base subtag ("ja", "en", "zh"), or `nil`
    /// when the text is empty or undetectable.
    static func detect(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(trimmed)
        guard let lang = recognizer.dominantLanguage else { return nil }
        return LanguagePolicy.base(lang.rawValue)
    }
}
