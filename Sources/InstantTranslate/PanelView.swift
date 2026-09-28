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
    /// ⌘+ / ⌘− preference; nil = system body size (ADR-0002).
    @AppStorage(SettingsKey.textSize) private var textSizePreference: Double?
    @State private var configuration: TranslationSession.Configuration?
    @State private var debounceTask: Task<Void, Never>?
    @State private var speechSynthesizer = LocalSpeechSynthesizer()
    /// Laid-out sizes the panel's minimum is derived from (`PanelMinimumSize`).
    @State private var metrics = PanelMinimumSize.Metrics()

    /// Idle time after the last keystroke before an automatic translation fires.
    private let autoTranslateDelay: Duration = .milliseconds(600)

    /// Bindings to the model's manual overrides (nil = Auto). `@EnvironmentObject`
    /// doesn't provide `$model.property`, so build them explicitly.
    private var targetOverrideBinding: Binding<String?> {
        Binding(get: { model.targetOverride }, set: { model.targetOverride = $0 })
    }
    private var sourceOverrideBinding: Binding<String?> {
        Binding(get: { model.sourceOverride }, set: { model.sourceOverride = $0 })
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
                           focusToken: controller.focusToken,
                           fontSize: textSize)
                .frame(minHeight: PanelMinimumSize.fieldMinimum, maxHeight: .infinity)
                .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { metrics.inputHeight = $0 }
                .overlay(alignment: .topLeading) {
                    // A caret alone in an empty field is easy to miss; the prompt makes
                    // it unmistakable that the panel is ready for input.
                    if isSourceEmpty {
                        Text("Type or paste text to translate")
                            .font(.system(size: textSize))
                            .foregroundStyle(.tertiary)
                            .padding(.leading, 8)
                            .padding(.top, 6)
                            .allowsHitTesting(false)
                    }
                }
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(.quaternary))

            pickerRow

            statusRow

            Divider()

            ScrollView {
                Text(model.translatedText.isEmpty ? "—" : model.translatedText)
                    .font(.system(size: textSize))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .foregroundStyle(model.translatedText.isEmpty ? .secondary : .primary)
            }
            .frame(minHeight: PanelMinimumSize.fieldMinimum, maxHeight: .infinity)
            .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { metrics.outputHeight = $0 }

            if let failure = model.failure {
                failureBlock(failure)
            }

            HStack {
                Button {
                    speechSynthesizer.speak(model.translatedText, language: model.targetLanguage)
                } label: {
                    Image(systemName: "speaker.wave.2.fill")
                }
                .buttonStyle(.borderless)
                .help("Speak")
                .accessibilityLabel("Speak translation")
                .disabled(model.translatedText.isEmpty)
                Button("Copy", action: copy)
                    .disabled(model.translatedText.isEmpty)
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
            }
            .font(.callout)
        }
        .padding(12)
        // Measured before the frame below, so an overflowing stack reports the
        // height it needs rather than the height it was given.
        .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { metrics.contentHeight = $0 }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onGeometryChange(for: CGFloat.self, of: { $0.safeAreaInsets.top }) { metrics.safeAreaTop = $0 }
        .onChange(of: metrics, initial: true) { _, m in
            if let minimum = PanelMinimumSize.compute(m) { controller.setPanelMinimum(minimum) }
        }
        .background { textSizeShortcuts }
        .onChange(of: model.sourceText) { _, newValue in scheduleAutoTranslate(newValue) }
        .onChange(of: model.isComposing) { _, composing in
            // A committed composition often leaves the text unchanged (the marked run
            // and the confirmed run are the same string), so the source-text observer
            // above never fires — arm the timer from the composition edge instead.
            if composing {
                debounceTask?.cancel()
                model.phase = .composing     // say why nothing is happening
            } else {
                scheduleAutoTranslate(model.sourceText)
            }
        }
        .onChange(of: model.targetOverride) { _, _ in
            // Switching the target re-runs the translation (or just updates the label
            // when there's nothing to translate yet).
            if isSourceEmpty { model.resolveTarget() } else { translate() }
        }
        .onChange(of: model.sourceOverride) { _, _ in
            // Same for pinning/unpinning the source — it can change the routed target
            // (auto-swap) and the translation itself.
            if isSourceEmpty { model.resolveTarget() } else { translate() }
        }
        .translationTask(configuration) { session in
            await run(session)
        }
    }

    // MARK: - Picker row

    /// Source picker · arrow · target picker, each with its "(language)" hint on the
    /// line under it, and the Translate button.
    ///
    /// The pickers, the arrow and the button never compress: they are the panel's
    /// minimum width. Each hint is overlaid on a blank line under its picker, so it
    /// adds no width at all. Beside the pickers the hints either wrapped one character
    /// per line when squeezed or, given room, pushed the panel wider as a longer name
    /// appeared; switching between beside and under by width was tried and dropped —
    /// the controls shifted as the layout changed.
    private var pickerRow: some View {
        let sourceHint = model.sourceOverride == nil ? model.detectedSource.map(catalog.name(for:)) : nil
        let targetHint = model.targetOverride == nil ? catalog.name(for: model.targetLanguage) : nil
        return HStack(alignment: .firstTextBaseline, spacing: PanelMinimumSize.rowSpacing) {
            HStack(alignment: .firstTextBaseline, spacing: PanelMinimumSize.itemSpacing) {
                VStack(alignment: .leading, spacing: PanelMinimumSize.hintSpacing) {
                    sourcePicker
                    hintLine
                }
                .overlay(alignment: .bottomLeading) { hint(sourceHint) }
                arrow
                VStack(alignment: .leading, spacing: PanelMinimumSize.hintSpacing) {
                    targetPicker
                    hintLine
                }
                .overlay(alignment: .bottomLeading) { hint(targetHint) }
            }
            // What pushes the button right. Not a `Spacer`: wrapped in a measuring
            // modifier a `Spacer` stops being a stack spacer and stretches vertically.
            .frame(maxWidth: .infinity, alignment: .leading)
            Button("Translate") { translate() }
                .keyboardShortcut(.return, modifiers: [.command])
                .disabled(isSourceEmpty)
                .fixedSize()
                .onGeometryChange(for: CGFloat.self, of: { $0.size.width }) { metrics.buttonWidth = $0 }
        }
        // A fixed gap, not a `Spacer` (see above): part of the minimum height.
        .padding(.bottom, PanelMinimumSize.hintGap)
    }

    /// Source pin: Auto = detect, a language = translate as that language (also keeps
    /// the OS from ever asking which language the input is).
    private var sourcePicker: some View {
        Picker("", selection: sourceOverrideBinding) {
            Text("Auto").tag(String?.none)
            Divider()
            ForEach(catalog.sourceOptions) { opt in
                Text(opt.name).tag(Optional(opt.id))
            }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .fixedSize()
        .onGeometryChange(for: CGFloat.self, of: { $0.size.width }) { metrics.sourcePickerWidth = $0 }
    }

    /// Target: Auto = the routing policy, a language = translate into it.
    private var targetPicker: some View {
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
        .onGeometryChange(for: CGFloat.self, of: { $0.size.width }) { metrics.targetPickerWidth = $0 }
    }

    private var arrow: some View {
        Text("→").foregroundStyle(.secondary).fixedSize()
            .onGeometryChange(for: CGFloat.self, of: { $0.size.width }) { metrics.arrowWidth = $0 }
    }

    /// A blank caption-height line under each picker: it holds the hint's space
    /// whether or not there is a hint, so the row never changes height.
    private var hintLine: some View {
        Text(" ").font(.caption).hidden()
    }

    /// A picker's "(language)" hint — what "Auto" detected or resolves to. It is
    /// overlaid on a `hintLine`, so it is offered the picker's width and cannot widen
    /// the column: a longer name truncates in the middle, keeping both parentheses
    /// that mark it as a hint rather than a selection.
    private func hint(_ name: String?) -> some View {
        Text(name.map { "(\($0))" } ?? "")
            .font(.caption)
            .foregroundStyle(.tertiary)
            .lineLimit(1)
            .truncationMode(.middle)
            .padding(.leading, PanelMinimumSize.hintIndent)
    }

    // MARK: - Text size (ADR-0002)

    /// The content text size: the ⌘+ / ⌘− preference, else the system body size.
    private var textSize: Double {
        TextSize.effective(preference: textSizePreference,
                           body: NSFont.preferredFont(forTextStyle: .body).pointSize)
    }

    /// ⌘+ / ⌘− / ⌘0. Invisible buttons carry the shortcuts — the same
    /// `.keyboardShortcut` mechanism as ⌘↩ — since this app has no menu bar to hold
    /// them. Only the content text scales; controls keep their sizes.
    private var textSizeShortcuts: some View {
        ZStack {
            // A shortcut matches its modifiers exactly, so "+" is bound twice: the
            // main-row "+" is shifted on both US ("=" key) and JIS (";" key) and
            // arrives as ⌘⇧+, while the keypad "+" arrives as ⌘+ with no Shift.
            // ⌘= is the unshifted alias browsers also accept on a US layout.
            // `.focusable(false)`: invisible, so Tab (with Full Keyboard Access) must
            // not land on them either — only the shortcuts reach them.
            Button("Bigger") { stepTextSize(.larger) }
                .keyboardShortcut("+", modifiers: [.command, .shift])
                .focusable(false)
            Button("Bigger") { stepTextSize(.larger) }
                .keyboardShortcut("+", modifiers: .command)
                .focusable(false)
            Button("Bigger") { stepTextSize(.larger) }
                .keyboardShortcut("=", modifiers: .command)
                .focusable(false)
            Button("Smaller") { stepTextSize(.smaller) }
                .keyboardShortcut("-", modifiers: .command)
                .focusable(false)
            Button("Actual Size") { textSizePreference = nil }
                .keyboardShortcut("0", modifiers: .command)
                .focusable(false)
        }
        .opacity(0)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func stepTextSize(_ step: TextSize.Step) {
        if let next = TextSize.next(from: textSize, step) { textSizePreference = next }
    }

    // MARK: - Status & failure

    /// Always present, so the panel never goes silent and the layout never jumps.
    /// The interesting states are the ones where *nothing* is running on purpose
    /// (IME composition, undetectable input, debounce armed) — those are the ones
    /// that used to look like a hang.
    private var statusRow: some View {
        let status = TranslationStatus.display(
            phase: model.phase,
            hasInput: !isSourceEmpty,
            autoTranslateEnabled: autoTranslate,
            sourceName: model.resolvedSource.map { catalog.name(for: $0) },
            targetName: catalog.name(for: model.targetLanguage))
        return HStack(spacing: 5) {
            // Spinner and symbol share the slot, so the text doesn't shift sideways
            // when work starts or stops.
            Group {
                if status.showsSpinner {
                    ProgressView().controlSize(.small)
                } else if let symbol = status.symbol {
                    Image(systemName: symbol)
                }
            }
            .frame(width: 16, height: 16)
            Text(status.text)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 0)
        }
        .font(.caption)
        .foregroundStyle(tint(for: status.tone))
        .frame(height: 18)
        .help(status.text)          // the full text, when the row truncates
        .accessibilityElement(children: .combine)
        .accessibilityLabel(status.text)
    }

    private func tint(for tone: StatusDisplay.Tone) -> Color {
        switch tone {
        case .neutral: return .secondary
        case .active:  return .accentColor
        case .success: return .green
        case .failure: return .red
        }
    }

    /// A failure, in three registers: what happened, what to do, and the exact cause.
    /// The last one is selectable because this app has no log file — a bug report can
    /// only carry what the panel lets you copy (same reasoning as the version string).
    private func failureBlock(_ failure: FailureMessage) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(failure.headline)
                .font(.callout)
                .foregroundStyle(.red)
            if let recovery = failure.recovery {
                Text(recovery)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(failure.detail)
                .font(.caption2)
                .monospaced()
                .foregroundStyle(.tertiary)
                .textSelection(.enabled)
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.red.opacity(0.08)))
    }

    // MARK: - Translation

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
            model.clearForEmptyInput()
        case .ignore:
            // Two different reasons to do nothing, and they read very differently to
            // the user: an IME is mid-conversion (transient, will resume), or
            // auto-translate is simply off (waiting for ⌘↩).
            model.phase = model.isComposing ? .composing : .idle
        case .schedule:
            model.phase = .pending
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

    /// Resolve the source language (pin, or detection biased toward the user's local +
    /// secondary languages), resolve the target from the policy, then build (or
    /// re-arm) the translation configuration. The resolved source is passed
    /// *explicitly* to the session: with a source of its own the framework never
    /// raises its "which language is this?" picker. Only when nothing is pinned and
    /// nothing is detectable does the source stay `nil` — a manual run then leaves
    /// the last word to the OS dialog (deliberate; automatic runs stand down).
    ///
    /// `automatic` runs are additionally gated by `AutoTranslatePolicy.mayRun`.
    private func translate(automatic: Bool = false) {
        guard !isSourceEmpty else { return }
        debounceTask?.cancel()          // a manual translate supersedes any pending auto-run
        model.failure = nil
        let settings = SettingsStore.current()
        model.detectedSource = LanguageDetector.detect(
            model.sourceText,
            preferred: [SettingsStore.localLanguage(), settings.secondaryLanguage])
        model.resolveTarget()           // before the guard, so the "Auto (…)" hint stays honest
        if automatic, !AutoTranslatePolicy.mayRun(resolvedSource: model.resolvedSource,
                                                  isComposing: model.isComposing) {
            // Standing down is correct here, but silence makes it look like a hang —
            // name the two ways out (more text, or pin the language).
            model.phase = model.isComposing ? .composing : .awaitingLanguage
            return
        }

        // Identical source/target languages error out in the framework — short-circuit
        // and echo the input instead (e.g. native input with auto-swap turned off).
        if let src = model.resolvedSource,
           LanguagePolicy.base(src) == LanguagePolicy.base(model.targetLanguage) {
            model.apply(result: model.sourceText, echoed: true)
            return
        }

        model.phase = .translating
        let source = model.resolvedSource.map { Locale.Language(identifier: $0) }
        let target = Locale.Language(identifier: model.targetLanguage)
        if let current = configuration, current.source == source, current.target == target {
            configuration?.invalidate()    // same pair → just re-run the task
        } else {
            configuration = TranslationSession.Configuration(source: source, target: target)
        }
    }

    /// Run one translation against the session delivered by `.translationTask`.
    ///
    /// Three steps, each of which can be reported: reject an unsupported pair before
    /// the session is used at all; prepare the on-device model if the session isn't
    /// ready (the first use of a pair downloads it, which is where the unexplained
    /// multi-second wait used to come from); then translate.
    private func run(_ session: TranslationSession) async {
        let sourceName = model.resolvedSource.map { catalog.name(for: $0) }
        let targetName = catalog.name(for: model.targetLanguage)

        // Pre-flight: if the OS can't translate this pair at all, say so clearly
        // instead of surfacing a cryptic framework error.
        if let src = model.resolvedSource {
            let status = await LanguageAvailability().status(
                from: Locale.Language(identifier: src),
                to: Locale.Language(identifier: model.targetLanguage))
            if case .unsupported = status {
                model.fail(TranslationFailure.unsupportedPair
                    .message(sourceName: sourceName, targetName: targetName))
                return
            }
        }
        do {
            // Asking the session itself beats inferring from `LanguageAvailability`:
            // it is the session that has to be ready, and it answers for the exact
            // configuration about to run.
            let isReady = await session.isReady
            if !isReady {
                model.phase = .preparing
                try await session.prepareTranslation()
            }
            model.phase = .translating
            let response = try await session.translate(model.sourceText)
            model.apply(result: response.targetText)
            if SettingsStore.current().copyOnTranslate { copy() }
        } catch {
            model.fail(error, sourceName: sourceName, targetName: targetName)
        }
    }

    private func copy() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(model.translatedText, forType: .string)
    }
}
