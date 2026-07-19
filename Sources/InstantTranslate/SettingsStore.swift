import Foundation

/// UserDefaults keys + registered defaults for instant-translate's persisted
/// settings. Only *settings* are persisted — translation history is deliberately
/// volatile (see `TranslationModel`).
enum SettingsKey {
    /// Secondary language base subtag used when the input is the local language (e.g. "en").
    static let secondaryLanguage = "secondaryLanguage"
    /// Route local-language input to the secondary language instead of back to local.
    static let autoSwapEnabled = "autoSwapEnabled"
    /// Translate automatically a short time after the input stops changing (debounced).
    static let autoTranslate = "autoTranslate"
    /// When the panel is opened by a global hotkey, seed the source field from the clipboard.
    static let clipboardAutoTranslate = "clipboardAutoTranslate"
    /// Automatically copy the translation to the clipboard when it completes.
    static let copyOnTranslate = "copyOnTranslate"
    /// Global hotkey that opens the panel — virtual key code + modifier flags.
    static let hotKeyKeyCode = "hotKeyKeyCode"
    static let hotKeyModifiers = "hotKeyModifiers"

    static func registerDefaults(_ d: UserDefaults = .standard) {
        d.register(defaults: [
            secondaryLanguage: SettingsStore.systemDefaultSecondary(),
            autoSwapEnabled: true,
            autoTranslate: true,
            clipboardAutoTranslate: true,
            copyOnTranslate: false,
            hotKeyKeyCode: Int(HotKeyCombo.default.keyCode),
            hotKeyModifiers: Int(bitPattern: HotKeyCombo.default.modifiers),
        ])
    }
}

/// A snapshot of the persisted settings. Non-View types (`TranslationModel`) read
/// through this; `SettingsView` binds the same keys via `@AppStorage`.
struct SettingsStore: Equatable {
    var secondaryLanguage: String
    var autoSwapEnabled: Bool
    /// Defaulted so existing call sites (and tests) that don't set it still compile.
    var autoTranslate: Bool = true
    var clipboardAutoTranslate: Bool
    var copyOnTranslate: Bool

    static func current(_ d: UserDefaults = .standard) -> SettingsStore {
        SettingsStore(
            secondaryLanguage: d.string(forKey: SettingsKey.secondaryLanguage) ?? systemDefaultSecondary(),
            autoSwapEnabled: d.bool(forKey: SettingsKey.autoSwapEnabled),
            autoTranslate: d.bool(forKey: SettingsKey.autoTranslate),
            clipboardAutoTranslate: d.bool(forKey: SettingsKey.clipboardAutoTranslate),
            copyOnTranslate: d.bool(forKey: SettingsKey.copyOnTranslate)
        )
    }

    /// The local (primary) language base subtag — the system's preferred language.
    static func localLanguage(_ locale: Locale = .current) -> String {
        LanguagePolicy.base(locale.language.languageCode?.identifier ?? locale.identifier)
    }

    /// A sensible default secondary language: English, unless the user's local
    /// language *is* English, in which case Japanese (this org's other working
    /// language). The user overrides it in Settings.
    static func systemDefaultSecondary(_ locale: Locale = .current) -> String {
        localLanguage(locale) == "en" ? "ja" : "en"
    }

    /// Build the pure routing policy from these settings + the local language.
    func policy(local: String = SettingsStore.localLanguage()) -> LanguagePolicy {
        LanguagePolicy(local: local, secondary: secondaryLanguage, autoSwap: autoSwapEnabled)
    }
}
