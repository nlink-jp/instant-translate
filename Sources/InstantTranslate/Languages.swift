import Foundation

/// The curated language set shown in pickers (secondary language, manual target
/// override). Phase 2 `LanguageAvailability` will replace this with the OS-supported
/// set at runtime.
enum Languages {
    static let codes = ["en", "ja", "zh", "ko", "fr", "de", "es", "it", "pt", "ru"]

    /// Localized display name for a base subtag, falling back to the code.
    static func name(_ code: String) -> String {
        Locale.current.localizedString(forLanguageCode: code) ?? code
    }
}
