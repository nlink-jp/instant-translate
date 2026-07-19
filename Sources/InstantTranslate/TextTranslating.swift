import Foundation

/// Abstraction over "translate this text into a target language".
///
/// The production path is backed by the OS `Translation` framework
/// (`TranslationSession`), which is only reachable from a SwiftUI view — see
/// `PanelView`. This protocol exists so `TranslationModel`'s flow can be driven by
/// a deterministic stub in tests and SwiftUI previews, with no framework and no
/// on-device model download.
protocol TextTranslating {
    /// Translate `text` into `target` (base subtag). `source` nil = auto-detect.
    func translate(_ text: String, source: String?, target: String) async throws -> String
}

/// A deterministic stub for tests and previews. Produces a visible, checkable
/// marker rather than a real translation.
struct EchoTranslator: TextTranslating {
    /// Optional custom transform; defaults to `"[<target>] <text>"`.
    var transform: ((String, String?, String) -> String)?

    func translate(_ text: String, source: String?, target: String) async throws -> String {
        if let transform { return transform(text, source, target) }
        return "[\(target)] \(text)"
    }
}
