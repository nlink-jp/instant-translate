# AGENTS.md — instant-translate

## What this is

A lightweight macOS menu-bar app (SwiftUI, `MenuBarExtra`, `LSUIElement`) that
translates text via the OS **Translation framework** (`TranslationSession`,
on-device). The lightweight sibling of `quick-translate` (local LLM) — same UX,
different backend. GUI-only, macOS 26+, Apple silicon. Signed + notarized SwiftPM
`.app` (no `.xcodeproj`).

## Build & test

```sh
make run        # swift run (debug)
make build      # swift build -c release
make build-app  # signed .app → dist/
make package    # build-app + notarize + staple + zip
make verify-release  # gate: .notarized marker + stapler validate (run before upload)
make test       # swift test
```

Needs the macOS 26 SDK (recent Xcode / CLT).

## Structure

```
Sources/InstantTranslate/
  Entry.swift            @main; single-instance guard, then InstantTranslateApp.main()
  SingleInstance.swift   singleInstanceDecision() — startup duplicate-
                         instance guard (pure; pids in, decision out)
  App.swift              NSApplicationDelegateAdaptor(AppController) + placeholder Settings scene
  AppController.swift    NSStatusItem + translation NSPanel (hosts PanelView) + settings NSWindow; show/hide/focus; openSettings
  LanguagePolicy.swift   PURE routing: local / secondary / auto-swap → target lang
  LanguageDetector.swift NLLanguageRecognizer detection → base subtag; PURE preferred-language tie-break (resolve)
  LoginItem.swift        SMAppService.mainApp wrapper ("launch at login" toggle)
  Languages.swift        curated fallback language list + localized name
  LanguageCatalog.swift  async OS-supported languages → LanguageOption list (region-qualified when needed)
  HotKey.swift           HotKeyCombo (persist/display/Carbon) + GlobalHotKey (RegisterEventHotKey)
  HotKeyRecorder.swift   click-to-record shortcut control (local keyDown monitor)
  SettingsStore.swift    UserDefaults keys/defaults + snapshot; builds LanguagePolicy
  TranslationModel.swift ObservableObject; UI state + phase + failure + volatile last entry; DI seam
  TranslationFailure.swift  classify(Error) → named failure; PURE message(sourceName:targetName:)
  TranslationStatus.swift   TranslationPhase + PURE display() → status-row symbol/text/spinner/tone
  TextTranslating.swift  protocol + EchoTranslator stub (tests/previews)
  PanelView.swift        the panel; owns the real TranslationSession via .translationTask
  SettingsView.swift     settings Form (@AppStorage)
Tests/InstantTranslateTests/
  LanguagePolicyTests, SettingsStoreTests, TranslationModelTests,
  TranslationFailureTests, TranslationStatusTests, SingleInstanceTests
Info.plist               LSUIElement=true, LSMinimumSystemVersion=26.0
scripts/                 codesign / notarize / make-icns / gen-brew / release-brew.mk / cask.rb.tmpl
assets/                  AppIcon-1024.png (→ AppIcon.icns at build; absent for now)
docs/{en,ja}/            RFP + adr/
```

## Gotchas / conventions

- **`TranslationSession` is view-bound** — never instantiated directly; delivered
  into `.translationTask` and bound to the view's lifetime. Same-target re-run =
  `configuration.invalidate()`; new target = new `Configuration`. Closed-panel
  paths (Phase 2 hotkey / selected text) require a resident hidden host view.
- **Keep the routing pure** — all target-language logic lives in `LanguagePolicy`
  (no UI / framework imports) so it stays unit-testable. `TranslationModel` is
  `@MainActor` and takes an injected `TextTranslating` for tests/previews; the real
  session path is in `PanelView`.
- **Never show a raw `TranslationError`** — `localizedDescription` is
  `"Unable to Translate"` for seven of its eight cases and every case bridges to
  `NSError` domain `Translation.TranslationError` **code 1**, so the thrown error
  is neither showable nor distinguishable by shape. `TranslationError` is a struct
  with a custom `~=`, and that operator *does* discriminate cleanly (verified as an
  exact 8×8 diagonal), so `TranslationFailure.classify` matches on it and is the
  only place in the app that touches the framework's error type. `message(...)` is
  pure. Unplaced errors become `.unknown` carrying `failureReason ??
  localizedDescription` plus domain/code — never drop that, it is all an
  unanticipated error leaves behind. ADR-0001.
- **Every state the panel is in must be nameable** — `TranslationPhase` covers the
  states that *withhold* a translation on purpose (IME composition, undetectable
  input, debounce armed, echo) as well as the ones doing work. Before it existed
  they were all indistinguishable from a hang. A new "quietly do nothing" branch
  needs a phase and a line in `TranslationStatus.display`, not a bare `return`.
  ADR-0001.
- **`isTranslating` is derived, not stored** — it is `phase == .preparing ||
  .translating`. Setting a phase is the only way to move the UI; there is no second
  source of truth to drift.
- **History is volatile** — most-recent entry only, in memory, never persisted.
- **Settings persist via UserDefaults** — `SettingsStore` reads; `SettingsView`
  binds the same keys via `@AppStorage`. `SettingsKey.registerDefaults()` runs at
  launch in `App.init`.
- **AppKit shell, not `MenuBarExtra`** — the menu bar is an `NSStatusItem` and the
  panel is a resizable `NSPanel` hosting `PanelView` (`NSHostingView`). Reason: a
  MenuBarExtra popover can't be user-resized and can't reliably focus a text field.
  The panel autosaves its size and re-anchors under the status item each open;
  focus-on-open = `AppController.focusToken` → `PanelView` `@FocusState`.
  `AppController.showPanel()` is also the Phase 2 hotkey entry point.
- **Global hotkey** — `GlobalHotKey` wraps Carbon `RegisterEventHotKey` (no external
  dep, no Accessibility). `AppController` registers `HotKeyCombo.current()` at launch
  and re-registers on `UserDefaults.didChangeNotification` when the combo changes.
  Hotkey-open (`hotKeyPressed` → `showPanel(seedClipboard: true)`) seeds the source
  from the clipboard when the setting is on; the status-item click doesn't seed. The
  recorder swallows keys via a local `keyDown` monitor while capturing.
- **Panel is `.nonactivatingPanel`** (don't remove) — an ordinary NSPanel only renders
  while the app is active, and macOS 14+ focus-stealing prevention can deny activation
  for ~30 s after launch, so the panel was `isVisible` but never shown ("won't open
  after launch", fixed 0.1.1). Non-activating renders + takes input without activation.
- **Panel toggle: never `hidesOnDeactivate` on a toggled `NSPanel`** — it auto-hides
  on deactivation but leaves `isVisible == true`, so a `isVisible ? orderOut : show`
  toggle then no-ops instead of opening (the "clicking the icon doesn't open it" bug).
  Dismiss on deactivation yourself via `applicationDidResignActive` → `orderOut`, which
  keeps `isVisible` truthful. `position()` also clamps the panel size to the current
  screen (an autosaved size from a bigger display would otherwise push it off-screen).
- **Auto-translate is debounced** — `PanelView.scheduleAutoTranslate` fires ~600 ms
  after the input stops changing; each change cancels the pending `Task`. Gated by the
  `autoTranslate` setting; a manual `translate()` cancels any pending auto-run.
- **Auto-translate must never run mid-IME-composition** — the source field is a custom
  `SourceTextView` (`NSTextView`), not `TextEditor`, precisely because `TextEditor`
  can't tell you about *marked* (uncommitted) IME text. Translating a half-done
  kana-kanji conversion produced garbage and made the OS raise its source-language
  picker over the panel, blocking typing (the 0.1.2 bug). `ComposingTextView` reports
  composition edges from `setMarkedText`/`unmarkText`/`insertText` — `textDidChange`
  alone is not enough, because committing a composition can leave the string
  byte-identical and emit no change at all. State lands in
  `TranslationModel.isComposing`; the rules live in the pure, unit-tested
  `AutoTranslatePolicy` (`action(forSourceText:…)` to arm, `mayRun(…)` at fire time).
  `mayRun` also stands down when the *resolved* source (pin, else detection) is `nil` —
  undetectable input is exactly what triggers that OS picker; a pinned source always
  passes. Manual translate is never gated.
- **The caret must be visible in the empty input** — focus is applied by
  `SourceTextView.updateNSView` calling `makeFirstResponder` when `focusToken` changes
  (a monotonic counter, since a `Bool` can't re-trigger focus when already `true`);
  `@FocusState` on `TextEditor` did not reliably land. An empty field also shows a
  placeholder overlay so focus is unmistakable.
- **First responder is not enough — an `NSTextView` draws its caret only in a *key*
  window.** Opening the panel by hotkey from another app does *not* activate the app
  (macOS denies it; verified — the other app stays frontmost), so key status is the only
  thing that makes the caret appear. Three parts, all needed: `TranslationPanel`
  overrides `canBecomeKey` (a `.nonactivatingPanel` is exactly the case where a window
  holds key status while the app is inactive); `showPanel` calls `makeKey()` and
  re-asserts key + focus one runloop turn later, since `NSApp.activate()` is async and
  may be refused; and the `SourceTextView` coordinator observes
  `NSWindow.didBecomeKeyNotification` to reclaim first responder and call
  `updateInsertionPointStateAndRestartTimer`, which covers any remaining ordering.
- **The version must stay visible in the UI** — `AppInfo.version` reads
  `CFBundleShortVersionString` (injected by `make build-app` from `git describe`) and is
  shown in the panel header and at the foot of Settings. This app has no menu bar and no
  About item, so removing those labels leaves users with no way to identify their build.
  Under `make run` there's no bundle, so it reads `dev` — that's expected, not a bug.
- **Pickers show only OS-supported languages, regional variants distinguished** —
  `LanguageCatalog.load()` fetches `LanguageAvailability().supportedLanguages` (async)
  and builds `[LanguageOption]` (id = `minimalIdentifier` e.g. "en-GB"; name
  region-qualified only when a base language has >1 variant — `options(from:)` is
  unit-tested). Pickers bind to `options` (curated fallback until loaded). The chosen
  variant is preserved: `LanguagePolicy` compares by `base(...)` but returns the full
  identifier as the target; `TranslationModel.resolveTarget` keeps `targetOverride`
  verbatim. `PanelView.run` pre-checks `status(from:to:)` for a clear unsupported message.
- **The model download is prepared explicitly, not stumbled into** — `PanelView.run`
  checks `session.isReady` and, when false, enters `.preparing` and calls
  `session.prepareTranslation()` before translating. The OS raises its download
  consent for that pair either way; doing it here moves it to a moment the panel has
  already labelled, instead of an unexplained multi-second freeze inside
  `session.translate`. Gate on `isReady` (the session's own answer for the exact
  configuration about to run), not on `LanguageAvailability.status == .supported`;
  `status` keeps its separate job of rejecting unsupported pairs up front. This is
  narrower than the blanket "never let the OS raise a dialog" stance below — that one
  is about the *source-language* picker, which is avoidable and interrupts typing.
  ADR-0001.
- **Launch at login** — `LoginItem` wraps `SMAppService.mainApp`; `SMAppService` is the
  source of truth (the Settings toggle mirrors `status`, refreshes `.onAppear`, no
  persisted flag). Registration only works from the signed `.app`, not `swift run`.
- **No special permissions** — selected-text translation (which would have needed
  Accessibility) was descoped. The app needs no TCC grant; only the OS's own
  language-model download consent. Don't reintroduce Accessibility casually.
- **Manual target override** — `TranslationModel.targetOverride` (base subtag, nil =
  Auto) wins in `resolveTarget()` over the policy. It's in-memory only (resets to Auto
  on restart). The panel's "Auto + languages" picker binds it; changing it re-translates.
- **Source pin** — `TranslationModel.sourceOverride` (base subtag, nil = Auto) mirrors
  the target override: in-memory only, bound to the panel's left picker (which lists
  `LanguageCatalog.sourceOptions` — base languages only, variants collapsed), changing
  it re-translates. `model.resolvedSource` (`sourceOverride ?? detectedSource`) is what
  everything downstream uses — routing, the no-op echo check, `mayRun`, the pre-flight
  status check, and the session configuration. A pin satisfies `mayRun` even when the
  text is undetectable.
- **Detect before routing, and hand the source to the framework** —
  `PanelView.translate()` runs `LanguageDetector` (biased toward the local + secondary
  languages via the pure `resolve(hypotheses:preferred:)` tie-break) to set
  `model.detectedSource`, *then* `LanguagePolicy` resolves the target. Without
  detection the target defaulted to the local language and native input became a
  same-language pair, which the framework rejects (the "Japanese errors" bug). Same
  base source==target → echo, don't call the session. The resolved source is passed
  **explicitly** in `TranslationSession.Configuration(source:…)` — leaving it `nil`
  made the framework re-detect on its own and raise the OS source-language picker
  whenever *it* was unsure, even when we weren't. `nil` reaches the framework only
  for a manual ⌘↩ on genuinely undetectable input (deliberate: the OS dialog is the
  last resort there). Note the config rebuild check compares source *and* target.
- **Settings is a separate AppKit `NSWindow`** (`AppController.openSettings`), not the
  SwiftUI `Settings` scene / `showSettingsWindow:` (unreliable for a menu-only
  `LSUIElement` app). An in-panel 3D card flip was tried and reverted — the 180°
  `rotation3DEffect` inverts hit-test z-order so the flipped Back button wasn't
  clickable (only Esc worked). `Settings { EmptyView() }` is a placeholder only.
  If a flip is ever revisited: don't put interactive controls inside a statically
  180°-rotated layer.
- **Notification clicks launch by bundle ID — enforce a single instance.**
  Clicking a banner makes notificationd open the app via LaunchServices,
  which resolves `jp.nlink.instant-translate` among *all* registered
  copies (`dist/` dev builds, release-verification extractions,
  `/Applications`) and may start a different copy than the running one →
  two menu bar items, duplicated work. Guarded at two layers:
  `LSMultipleInstancesProhibited` (Info.plist, stops LaunchServices
  launches) and a startup check in `Entry.main`
  (`singleInstanceDecision`, pure + tested) that exits with a stderr note
  (covers direct exec / `open -n`). Side effect: to run a `dist/` build,
  quit the installed instance first — a second copy now refuses to start.
- **Signing**: pure SwiftUI/AppKit → no entitlements (Hardened Runtime alone);
  notarize + staple.
- **macOS 26 platform pin** — `Package.swift` uses `.macOS("26.0")` (string form;
  the `.v26` enum may be absent in older toolchains).

## Status

Phase 1 (core translate) + Phase 2 done: global hotkey (⌥⌘T, rebindable) + clipboard
seed, manual target picker, `LanguageAvailability` (supported-language pickers +
unsupported-pair messaging). **Selected-text translation was descoped** (would have
needed Accessibility) — the app needs no TCC grant. See the RFP (with its scope note).

Post-0.2.0: the panel reports its state (`TranslationPhase` + status row) and
classifies framework failures into actionable messages (`TranslationFailure`) —
ADR-0001.

## Design reference

- RFP: `docs/ja/instant-translate-rfp.ja.md`
- ADR-0001 — panel feedback and failure messages:
  `docs/en/adr/0001-panel-feedback-and-failure-messages.md`
  (`docs/ja/adr/0001-panel-feedback-and-failure-messages.ja.md`)
- Sibling: https://github.com/nlink-jp/quick-translate
