import AppKit
import SwiftUI
import Translation

/// The translation panel: source input → translation → copy.
///
/// This view is where the OS `Translation` framework is reached. `TranslationSession`
/// cannot be created directly; it is delivered into the `.translationTask` closure,
/// bound to this view's lifetime. Assigning `configuration` (re)runs the task; to
/// re-translate with the same target we `invalidate()` the existing configuration.
///
/// The layout is flexible (min + `.infinity` maxes) so it fills the resizable
/// `NSPanel` the `AppController` hosts it in. Input focus on open is driven by
/// `AppController.focusToken`.
struct PanelView: View {
    @EnvironmentObject private var model: TranslationModel
    @EnvironmentObject private var controller: AppController
    @EnvironmentObject private var catalog: LanguageCatalog
    @AppStorage(SettingsKey.autoTranslate) private var autoTranslate = true
    @State private var configuration: TranslationSession.Configuration?
    @State private var debounceTask: Task<Void, Never>?

    /// Idle time after the last keystroke before an automatic translation fires.
    private let autoTranslateDelay: Duration = .milliseconds(600)

    /// Binding to the model's manual target override (nil = Auto). `@EnvironmentObject`
    /// doesn't provide `$model.property`, so build it explicitly.
    private var targetOverrideBinding: Binding<String?> {
        Binding(get: { model.targetOverride }, set: { model.targetOverride = $0 })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("instant-translate")
                    .font(.headline)
                // The app has no menu bar and no About item, so this is the only place
                // you can find out which build you're running.
                Text(AppInfo.version)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .textSelection(.enabled)
                Spacer()
                Button { controller.openSettings() } label: {
                    Image(systemName: "gearshape")
                }
                .buttonStyle(.borderless)
                .help("Settings")
            }

            SourceTextView(text: $model.sourceText,
                           isComposing: $model.isComposing,
                           focusToken: controller.focusToken)
                .frame(minHeight: 80, maxHeight: .infinity)
                .overlay(alignment: .topLeading) {
                    // A caret alone in an empty field is easy to miss; the prompt makes
                    // it unmistakable that the panel is ready for input.
                    if isSourceEmpty {
                        Text("Type or paste text to translate")
                            .font(.body)
                            .foregroundStyle(.tertiary)
                            .padding(.leading, 8)
                            .padding(.top, 6)
                            .allowsHitTesting(false)
                    }
                }
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(.quaternary))

            HStack(spacing: 6) {
                Text("→").foregroundStyle(.secondary)
                Picker("", selection: targetOverrideBinding) {
                    Text("Auto").tag(String?.none)
                    Divider()
                    ForEach(catalog.options) { opt in
                        Text(opt.name).tag(Optional(opt.id))
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .fixedSize()
                if model.targetOverride == nil {
                    // Hint what "Auto" currently resolves to.
                    Text("(\(catalog.name(for: model.targetLanguage)))")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                Spacer()
                Button("Translate") { translate() }
                    .keyboardShortcut(.return, modifiers: [.command])
                    .disabled(isSourceEmpty)
            }

            Divider()

            ScrollView {
                Text(model.translatedText.isEmpty ? "—" : model.translatedText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .foregroundStyle(model.translatedText.isEmpty ? .secondary : .primary)
            }
            .frame(minHeight: 80, maxHeight: .infinity)

            if let err = model.errorMessage {
                Text(err)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Button("Copy", action: copy)
                    .disabled(model.translatedText.isEmpty)
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
            }
            .font(.callout)
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onChange(of: model.sourceText) { _, newValue in scheduleAutoTranslate(newValue) }
        .onChange(of: model.isComposing) { _, composing in
            // A committed composition often leaves the text unchanged (the marked run
            // and the confirmed run are the same string), so the source-text observer
            // above never fires — arm the timer from the composition edge instead.
            if composing { debounceTask?.cancel() } else { scheduleAutoTranslate(model.sourceText) }
        }
        .onChange(of: model.targetOverride) { _, _ in
            // Switching the target re-runs the translation (or just updates the label
            // when there's nothing to translate yet).
            if isSourceEmpty { model.resolveTarget() } else { translate() }
        }
        .translationTask(configuration) { session in
            await run(session)
        }
    }

    /// Debounced auto-translate: fire once the input has been idle for
    /// `autoTranslateDelay`. Each change cancels the pending run, so it only
    /// translates when typing pauses. Clearing the input clears the output; an open
    /// IME composition holds everything back (see `AutoTranslatePolicy`).
    private func scheduleAutoTranslate(_ newValue: String) {
        debounceTask?.cancel()
        switch AutoTranslatePolicy.action(forSourceText: newValue,
                                          autoTranslateEnabled: autoTranslate,
                                          isComposing: model.isComposing) {
        case .clearOutput:
            model.translatedText = ""
            model.errorMessage = nil
        case .ignore:
            break
        case .schedule:
            debounceTask = Task { @MainActor in
                try? await Task.sleep(for: autoTranslateDelay)
                guard !Task.isCancelled, model.sourceText == newValue else { return }
                translate(automatic: true)
            }
        }
    }

    private var isSourceEmpty: Bool {
        model.sourceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Detect the input language, resolve the target from the policy, then build (or
    /// re-arm) the translation configuration. The session's source is left `nil` so
    /// the framework auto-detects; the *detected* language is used only to route the
    /// target (e.g. native input → the secondary language when auto-swap is on).
    ///
    /// `automatic` runs are additionally gated by `AutoTranslatePolicy.mayRun` — they
    /// stand down rather than provoke the OS's source-language picker mid-typing.
    private func translate(automatic: Bool = false) {
        guard !isSourceEmpty else { return }
        debounceTask?.cancel()          // a manual translate supersedes any pending auto-run
        model.errorMessage = nil
        model.detectedSource = LanguageDetector.detect(model.sourceText)
        model.resolveTarget()           // before the guard, so the "Auto (…)" hint stays honest
        if automatic, !AutoTranslatePolicy.mayRun(detectedSource: model.detectedSource,
                                                  isComposing: model.isComposing) {
            return
        }

        // Identical source/target languages error out in the framework — short-circuit
        // and echo the input instead (e.g. native input with auto-swap turned off).
        if let src = model.detectedSource, src == model.targetLanguage {
            model.apply(result: model.sourceText)
            return
        }

        model.isTranslating = true
        let target = Locale.Language(identifier: model.targetLanguage)
        if configuration?.target == target {
            configuration?.invalidate()    // same target → just re-run the task
        } else {
            configuration = TranslationSession.Configuration(source: nil, target: target)
        }
    }

    /// Run one translation against the session delivered by `.translationTask`.
    private func run(_ session: TranslationSession) async {
        // Pre-flight: if the OS can't translate this pair at all, say so clearly
        // instead of surfacing a cryptic framework error.
        if let src = model.detectedSource {
            let status = await LanguageAvailability().status(
                from: Locale.Language(identifier: src),
                to: Locale.Language(identifier: model.targetLanguage))
            if case .unsupported = status {
                model.fail("\(Languages.name(src)) → \(Languages.name(model.targetLanguage)) isn't supported for translation on this Mac.")
                return
            }
        }
        do {
            let response = try await session.translate(model.sourceText)
            model.apply(result: response.targetText)
            if SettingsStore.current().copyOnTranslate { copy() }
        } catch {
            model.fail("Couldn't translate — the language model may still be downloading. \(error.localizedDescription)")
        }
    }

    private func copy() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(model.translatedText, forType: .string)
    }
}
