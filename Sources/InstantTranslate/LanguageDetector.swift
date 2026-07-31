import Foundation
import NaturalLanguage

/// On-device dominant-language detection for the input text, used to route the
/// translation target (see `LanguagePolicy`) and — since the source is now passed
/// explicitly to the Translation framework — to keep the OS from raising its own
/// source-language picker. Kept separate from the pure policy so the routing rule
/// stays testable without a model, and so the detector can be swapped/expanded
/// independently.
enum LanguageDetector {
    /// Candidates whose probability is at least this fraction of the winner's are
    /// "in contention": close enough that a preferred language beats the raw winner.
    static let ambiguityRatio = 0.5

    /// The dominant language of `text` as a base subtag ("ja", "en", "zh"), or `nil`
    /// when the text is empty or undetectable.
    ///
    /// `preferred` (typically the user's local + secondary languages) breaks ties:
    /// when the recognizer's candidates are close — kanji-only text is a classic
    /// ja/zh coin toss — the highest-probability preferred language in contention
    /// wins over the raw winner.
    static func detect(_ text: String, preferred: [String] = []) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(trimmed)
        guard let dominant = recognizer.dominantLanguage else { return nil }
        let hypotheses = recognizer.languageHypotheses(withMaximum: 8)
            .reduce(into: [String: Double]()) { $0[$1.key.rawValue] = $1.value }
        return resolve(hypotheses: hypotheses, preferred: preferred)
            ?? LanguagePolicy.base(dominant.rawValue)
    }

    /// The pure tie-break rule, split out for unit testing.
    ///
    /// Probabilities are merged by base subtag (zh-Hans + zh-Hant → zh). Among the
    /// candidates within `ambiguityRatio` of the winner, the highest-probability
    /// preferred language wins (ties go to the earlier entry in `preferred`);
    /// otherwise the raw winner stands. Returns `nil` only for empty input.
    static func resolve(hypotheses: [String: Double], preferred: [String]) -> String? {
        var merged: [String: Double] = [:]
        for (lang, p) in hypotheses { merged[LanguagePolicy.base(lang), default: 0] += p }
        guard let top = merged.values.max(), top > 0 else { return nil }
        let floor = top * ambiguityRatio
        var best: (lang: String, p: Double)?
        for lang in preferred.map(LanguagePolicy.base) {
            guard let p = merged[lang], p >= floor else { continue }
            if best == nil || p > best!.p { best = (lang, p) }
        }
        if let best { return best.lang }
        return merged.max { $0.value < $1.value }?.key
    }
}
