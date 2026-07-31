import Combine
import Foundation
import Translation

/// A selectable language: a stable identifier (regional variant preserved) plus a
/// localized display name.
struct LanguageOption: Identifiable, Equatable {
    /// e.g. "en" (US), "en-GB", "zh-TW" — a `Locale.Language.minimalIdentifier`.
    let id: String
    /// Localized name, region-qualified only when the base language has >1 variant.
    let name: String
}

/// The languages the OS Translation framework supports, loaded asynchronously from
/// `LanguageAvailability`. The pickers bind to `options` so they only ever offer
/// translatable languages — and distinguish regional variants (English (US) vs
/// English (United Kingdom), Chinese (China) vs Chinese (Taiwan), …). Starts with a
/// curated fallback and is replaced once the real set loads.
final class LanguageCatalog: ObservableObject {
    @Published var options: [LanguageOption] = LanguageCatalog.fallback

    static let fallback: [LanguageOption] =
        Languages.codes.map { LanguageOption(id: $0, name: Languages.name($0)) }

    func load() {
        Task { [weak self] in
            let langs = await LanguageAvailability().supportedLanguages
            let infos = langs.map {
                LangInfo(id: $0.minimalIdentifier,
                         base: $0.languageCode?.identifier ?? $0.minimalIdentifier,
                         region: $0.region?.identifier,
                         script: $0.script?.identifier)
            }
            let opts = LanguageCatalog.options(from: infos)
            guard !opts.isEmpty else { return }
            await self?.setOptions(opts)
        }
    }

    @MainActor private func setOptions(_ newOptions: [LanguageOption]) { options = newOptions }

    /// Display name for a language id, from the loaded options (falls back to the base
    /// subtag's name for ids not in the list).
    func name(for id: String) -> String {
        options.first { $0.id == id }?.name ?? Languages.name(LanguagePolicy.base(id))
    }

    /// Options for the *source* pin picker: regional variants collapse to one base
    /// entry ("English", not one row per region) — the input side of a translation
    /// has no meaningful region, and detection yields base subtags anyway.
    var sourceOptions: [LanguageOption] { LanguageCatalog.sourceOptions(from: options) }

    /// Pure — unit-tested.
    static func sourceOptions(from options: [LanguageOption],
                              locale: Locale = .current) -> [LanguageOption] {
        var seen = Set<String>()
        var out: [LanguageOption] = []
        for opt in options {
            let base = LanguagePolicy.base(opt.id)
            guard seen.insert(base).inserted else { continue }
            out.append(LanguageOption(id: base,
                                      name: locale.localizedString(forLanguageCode: base) ?? base))
        }
        return out.sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
    }

    struct LangInfo: Equatable {
        let id: String
        let base: String
        let region: String?
        let script: String?
    }

    /// Build display options: dedupe by id; add a region (or script) qualifier only
    /// when a base language has more than one variant, so single-variant languages
    /// stay clean ("Japanese", not "Japanese (Japan)"); sort by localized name. Pure —
    /// unit-tested.
    static func options(from infos: [LangInfo], locale: Locale = .current) -> [LanguageOption] {
        var seen = Set<String>()
        let unique = infos.filter { seen.insert($0.id).inserted }
        let counts = Dictionary(grouping: unique, by: { LanguagePolicy.base($0.base) })
            .mapValues(\.count)
        let opts = unique.map { info -> LanguageOption in
            let base = LanguagePolicy.base(info.base)
            var name = locale.localizedString(forLanguageCode: base) ?? base
            if (counts[base] ?? 0) > 1 {
                if let region = info.region, let rn = locale.localizedString(forRegionCode: region) {
                    name += " (\(rn))"
                } else if let script = info.script, let sn = locale.localizedString(forScriptCode: script) {
                    name += " (\(sn))"
                }
            }
            return LanguageOption(id: info.id, name: name)
        }
        return opts.sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
    }
}
