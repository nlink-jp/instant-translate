import SwiftUI

/// The settings window's content. Binds the same `UserDefaults` keys as
/// `SettingsStore` reads, via `@AppStorage`. Shown in a separate AppKit window
/// (`AppController.openSettings`), which provides the title bar and close button.
///
/// Robust to any window size: the content scrolls (never clips when short) and its
/// width is capped (never stretches absurdly when wide).
struct SettingsView: View {
    @EnvironmentObject private var catalog: LanguageCatalog
    @AppStorage(SettingsKey.secondaryLanguage) private var secondaryLanguage = SettingsStore.systemDefaultSecondary()
    @AppStorage(SettingsKey.autoSwapEnabled) private var autoSwapEnabled = true
    @AppStorage(SettingsKey.autoTranslate) private var autoTranslate = true
    @AppStorage(SettingsKey.clipboardAutoTranslate) private var clipboardAutoTranslate = true
    @AppStorage(SettingsKey.copyOnTranslate) private var copyOnTranslate = false
    @AppStorage(SettingsKey.hotKeyKeyCode) private var hotKeyKeyCode = Int(HotKeyCombo.default.keyCode)
    @AppStorage(SettingsKey.hotKeyModifiers) private var hotKeyModifiers = Int(bitPattern: HotKeyCombo.default.modifiers)

    @State private var launchAtLogin = LoginItem.isEnabled

    private var hotKeyBinding: Binding<HotKeyCombo> {
        Binding(
            get: { HotKeyCombo(keyCode: UInt16(truncatingIfNeeded: hotKeyKeyCode),
                               modifiers: UInt(bitPattern: hotKeyModifiers)) },
            set: { hotKeyKeyCode = Int($0.keyCode); hotKeyModifiers = Int(bitPattern: $0.modifiers) }
        )
    }

    /// `SMAppService` is the source of truth; the toggle mirrors it and applies changes.
    private var launchAtLoginBinding: Binding<Bool> {
        Binding(get: { launchAtLogin },
                set: { launchAtLogin = $0; LoginItem.setEnabled($0) })
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                GroupBox("General") {
                    Toggle("Launch at login", isOn: launchAtLoginBinding)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                GroupBox("Language") {
                    VStack(alignment: .leading, spacing: 10) {
                        Picker("Secondary language", selection: $secondaryLanguage) {
                            ForEach(catalog.options) { opt in Text(opt.name).tag(opt.id) }
                        }
                        Toggle("Auto-swap when input is my language", isOn: $autoSwapEnabled)
                        Text("Output goes to your system language. When the input is already your language, it goes to the secondary language instead.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                GroupBox("Shortcut") {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("Open panel")
                            Spacer()
                            HotKeyRecorder(combo: hotKeyBinding)
                        }
                        Text("Press this shortcut anywhere to open instant-translate.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                GroupBox("Behaviour") {
                    VStack(alignment: .leading, spacing: 10) {
                        Toggle("Translate automatically as you type", isOn: $autoTranslate)
                        Toggle("Seed from clipboard when opened by hotkey", isOn: $clipboardAutoTranslate)
                        Toggle("Copy result automatically", isOn: $copyOnTranslate)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(16)
            .frame(maxWidth: 480, alignment: .leading)   // don't stretch on a wide window
            .frame(maxWidth: .infinity)                   // …and center the capped content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { launchAtLogin = LoginItem.isEnabled }   // reflect external changes
    }
}
