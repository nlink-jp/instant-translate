import Foundation

/// The pure language-routing rule for instant-translate.
///
/// Output defaults to the user's local (primary) language. When "auto-swap" is
/// enabled and the *input* is detected to already be the local language, the
/// output is instead routed to a configured secondary language — giving the
/// intuitive "foreign → native / native → configured-foreign" behaviour the RFP
/// describes.
///
/// This type is deliberately free of any UI or `Translation`-framework dependency
/// so the routing decision can be unit-tested in isolation; the framework call is
/// a thin shell around it (see `PanelView`).
struct LanguagePolicy: Equatable {
    /// The user's primary language (identifier or base subtag, e.g. "ja"). Usually the
    /// system language. Compared by base subtag; also returned as the target for the
    /// local direction.
    let local: String
    /// The secondary language identifier (may carry a region, e.g. "en-GB"). Returned
    /// **as-is** so the specific regional variant reaches the translator.
    let secondary: String
    /// When true, route local-language input to `secondary` instead of back to `local`.
    let autoSwap: Bool

    init(local: String, secondary: String, autoSwap: Bool) {
        // Kept verbatim (not normalized) so regional variants survive to the target;
        // comparisons below use `base(...)`.
        self.local = local
        self.secondary = secondary
        self.autoSwap = autoSwap
    }

    /// Decide the target language identifier for a given detected source language.
    ///
    /// - Parameter detectedSource: the language subtag of the input (any form —
    ///   "en", "en-US", "zh_Hans_CN"), or `nil` when detection hasn't run.
    /// - Returns: the target language identifier (regional variant preserved).
    func target(forDetectedSource detectedSource: String?) -> String {
        guard autoSwap,
              let src = detectedSource.map(LanguagePolicy.base),
              src == LanguagePolicy.base(local)
        else {
            return local
        }
        return secondary
    }

    /// True when translating `detectedSource` to the resolved target would be a
    /// no-op (same base language). The UI can short-circuit and echo the input rather
    /// than round-tripping identical text through a model.
    func isNoop(detectedSource: String?) -> Bool {
        guard let src = detectedSource.map(LanguagePolicy.base) else { return false }
        return src == LanguagePolicy.base(target(forDetectedSource: detectedSource))
    }

    /// Normalise a BCP-47 / locale identifier to its lowercase base language
    /// subtag ("en-US" → "en", "zh_Hans_CN" → "zh").
    static func base(_ code: String) -> String {
        let lower = code.lowercased()
        if let i = lower.firstIndex(where: { $0 == "-" || $0 == "_" }) {
            return String(lower[..<i])
        }
        return lower
    }
}
