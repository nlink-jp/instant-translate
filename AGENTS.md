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
make test       # swift test
```

Needs the macOS 26 SDK (recent Xcode / CLT).

## Structure

```
Sources/InstantTranslate/
  App.swift              @main; NSApplicationDelegateAdaptor(AppController) + placeholder Settings scene
  AppController.swift    NSStatusItem + translation NSPanel (hosts PanelView) + settings NSWindow; show/hide/focus; openSettings
  LanguagePolicy.swift   PURE routing: local / secondary / auto-swap → target lang
  LanguageDetector.swift NLLanguageRecognizer dominant-language detection → base subtag
  LoginItem.swift        SMAppService.mainApp wrapper ("launch at login" toggle)
  Languages.swift        curated fallback language list + localized name
  LanguageCatalog.swift  async OS-supported languages → LanguageOption list (region-qualified when needed)
  HotKey.swift           HotKeyCombo (persist/display/Carbon) + GlobalHotKey (RegisterEventHotKey)
  HotKeyRecorder.swift   click-to-record shortcut control (local keyDown monitor)
  SettingsStore.swift    UserDefaults keys/defaults + snapshot; builds LanguagePolicy
  TranslationModel.swift ObservableObject; UI state + volatile last entry; DI seam
  TextTranslating.swift  protocol + EchoTranslator stub (tests/previews)
  PanelView.swift        the panel; owns the real TranslationSession via .translationTask
  SettingsView.swift     settings Form (@AppStorage)
Tests/InstantTranslateTests/
  LanguagePolicyTests, SettingsStoreTests, TranslationModelTests
Info.plist               LSUIElement=true, LSMinimumSystemVersion=26.0
scripts/                 codesign / notarize / make-icns / gen-brew / release-brew.mk / cask.rb.tmpl
assets/                  AppIcon-1024.png (→ AppIcon.icns at build; absent for now)
docs/{en,ja}/            RFP
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
- **Pickers show only OS-supported languages, regional variants distinguished** —
  `LanguageCatalog.load()` fetches `LanguageAvailability().supportedLanguages` (async)
  and builds `[LanguageOption]` (id = `minimalIdentifier` e.g. "en-GB"; name
  region-qualified only when a base language has >1 variant — `options(from:)` is
  unit-tested). Pickers bind to `options` (curated fallback until loaded). The chosen
  variant is preserved: `LanguagePolicy` compares by `base(...)` but returns the full
  identifier as the target; `TranslationModel.resolveTarget` keeps `targetOverride`
  verbatim. `PanelView.run` pre-checks `status(from:to:)` for a clear unsupported message.
- **Launch at login** — `LoginItem` wraps `SMAppService.mainApp`; `SMAppService` is the
  source of truth (the Settings toggle mirrors `status`, refreshes `.onAppear`, no
  persisted flag). Registration only works from the signed `.app`, not `swift run`.
- **No special permissions** — selected-text translation (which would have needed
  Accessibility) was descoped. The app needs no TCC grant; only the OS's own
  language-model download consent. Don't reintroduce Accessibility casually.
- **Manual target override** — `TranslationModel.targetOverride` (base subtag, nil =
  Auto) wins in `resolveTarget()` over the policy. It's in-memory only (resets to Auto
  on restart). The panel's "Auto + languages" picker binds it; changing it re-translates.
- **Detect before routing** — `PanelView.translate()` runs `LanguageDetector` to set
  `model.detectedSource`, *then* `LanguagePolicy` resolves the target. Without this
  the target defaulted to the local language and native input became a same-language
  pair, which the framework rejects (the "Japanese errors" bug). Same source==target
  → echo, don't call the session.
- **Settings is a separate AppKit `NSWindow`** (`AppController.openSettings`), not the
  SwiftUI `Settings` scene / `showSettingsWindow:` (unreliable for a menu-only
  `LSUIElement` app). An in-panel 3D card flip was tried and reverted — the 180°
  `rotation3DEffect` inverts hit-test z-order so the flipped Back button wasn't
  clickable (only Esc worked). `Settings { EmptyView() }` is a placeholder only.
  If a flip is ever revisited: don't put interactive controls inside a statically
  180°-rotated layer.
- **Signing**: pure SwiftUI/AppKit → no entitlements (Hardened Runtime alone);
  notarize + staple.
- **macOS 26 platform pin** — `Package.swift` uses `.macOS("26.0")` (string form;
  the `.v26` enum may be absent in older toolchains).

## Status

Phase 1 (core translate) + Phase 2 done: global hotkey (⌥⌘T, rebindable) + clipboard
seed, manual target picker, `LanguageAvailability` (supported-language pickers +
unsupported-pair messaging). **Selected-text translation was descoped** (would have
needed Accessibility) — the app needs no TCC grant. See the RFP (with its scope note).

## Design reference

- RFP: `docs/ja/instant-translate-rfp.ja.md`
- Sibling: https://github.com/nlink-jp/quick-translate
