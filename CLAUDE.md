# CLAUDE.md — instant-translate

**Organization rules (mandatory): https://github.com/nlink-jp/.github/blob/main/CONVENTIONS.md**

## Project overview

A lightweight macOS menu-bar app (SwiftUI, `MenuBarExtra`, `LSUIElement`) that
translates text with the OS **Translation framework** (`TranslationSession`,
on-device). Open a panel from the menu bar to type/paste text, translate, and copy
the result. The lightweight sibling of [`quick-translate`](https://github.com/nlink-jp/quick-translate)
(local LLM) — same UX, different backend, they coexist. macOS 26+, Apple silicon.

## Non-negotiable rules

- **Tests are mandatory** — write them with the implementation. The routing logic
  (`LanguagePolicy`) and settings (`SettingsStore`) are pure/injected and unit-tested.
- **Never build ad-hoc** — use `make build` / `make build-app`.
- **Docs in sync** — update `README.md` and `README.ja.md` together.
- **Small, typed commits** — `feat:`, `fix:`, `test:`, `chore:`, `docs:`, etc.
- **No secrets / PII** — the app reads only what the user types/pastes; nothing leaves the machine.

## Build & test

```sh
make run          # swift run (debug)
make build-app    # signed .app
make package      # notarized + stapled + zipped .app
make test         # swift test
```

Requires the **macOS 26 SDK** (recent Xcode / Command Line Tools) — the
programmatic Translation API and this app's deployment target are macOS 26.

## Key decisions (see docs/ja/instant-translate-rfp.ja.md)

- **Apple Translation, not an LLM**: on-device, lightweight, OS-managed models —
  fixes `quick-translate`'s tens-of-GB load. No network / credentials in the app.
- **GUI-only, no CLI**: `TranslationSession` needs a SwiftUI view host, and "light"
  is the point — so there is no pipe/CLI surface.
- **SwiftPM `.app`, not `.xcodeproj`**: matches `claude-usage-lens-gui` /
  `quick-translate` — `Package.swift` + `Makefile` assemble/sign/notarize the bundle.

## Architecture

- `App.swift` — `@main`; `@NSApplicationDelegateAdaptor(AppController.self)` + a placeholder `Settings { EmptyView() }` scene (no window).
- `AppController.swift` — `NSApplicationDelegate`/`ObservableObject`; owns the `NSStatusItem`, the resizable translation `NSPanel` (hosts `PanelView`), and the separate settings `NSWindow`. Show/hide/focus + `openSettings`.
- `LanguagePolicy.swift` — **pure** target-language routing (local / secondary / auto-swap). Unit-tested.
- `LanguageDetector.swift` — `NLLanguageRecognizer` dominant-language detection (→ base subtag). Feeds the policy. Unit-tested.
- `HotKey.swift` — `HotKeyCombo` (persist/display/Carbon masks, unit-tested) + `GlobalHotKey` (Carbon `RegisterEventHotKey`).
- `HotKeyRecorder.swift` — click-to-record shortcut control (local `keyDown` monitor).
- `SettingsStore.swift` — `UserDefaults` keys/defaults + snapshot; builds a `LanguagePolicy`.
- `TranslationModel.swift` — `ObservableObject`; UI state + the volatile most-recent entry + `targetOverride` (manual target, nil = Auto). DI seam via `TextTranslating`.
- `LoginItem.swift` — `SMAppService.mainApp` wrapper for the "launch at login" toggle.
- `Languages.swift` — curated fallback language list + localized names for the pickers.
- `LanguageCatalog.swift` — async load of OS-supported languages (`LanguageAvailability`) → `[LanguageOption]` (region-qualified when a base has >1 variant); pickers bind to it.
- `TextTranslating.swift` — protocol + `EchoTranslator` stub (tests/previews).
- `PanelView.swift` — the translation panel; owns the real `TranslationSession` via `.translationTask`; fills the panel; focus-on-open; debounced auto-translate. Gear → `openSettings`.
- `SettingsView.swift` — the settings window content (secondary language, auto-swap, auto-translate, clipboard, copy); shown in a fixed-size window (scrollable/width-capped as a safety net).

## Gotchas / conventions

- **`TranslationSession` is view-bound**: it can't be instantiated directly — it's
  delivered into `.translationTask`, tied to the view's lifetime. Re-translating
  with the same target uses `configuration.invalidate()`; a new target assigns a
  new `Configuration`. For closed-panel paths (hotkey / selected text, Phase 2) a
  hidden host view must stay resident.
- **History is volatile** — only the most-recent entry, in memory, never persisted.
- **Settings persist, history doesn't**: `SettingsStore` reads `UserDefaults`;
  `SettingsView` binds the same keys via `@AppStorage`.
- **Signing**: pure SwiftUI/AppKit → no entitlements, Hardened Runtime alone.
  Notarize + staple the `.app`.
- **Menu-bar shell is AppKit** (`NSStatusItem` + resizable `NSPanel`), not
  `MenuBarExtra` — a MenuBarExtra popover can't be user-resized and can't reliably
  focus a text field. The panel autosaves its size (`setFrameAutosaveName`) and is
  re-anchored under the status item on each open; focus-on-open is driven by
  `AppController.focusToken` → `PanelView`'s `@FocusState`. `AppController` is also
  the Phase 2 hotkey entry point (`showPanel()`).
- **Input language is detected before routing**: `PanelView.translate()` runs
  `LanguageDetector` first, then `LanguagePolicy` picks the target. If the detected
  source equals the target (e.g. native input with auto-swap off), it echoes instead
  of translating — the framework errors on identical-language pairs (this was the
  "Japanese input errors" bug: with no detection the target stayed the local
  language → ja→ja).
- **Settings is a separate AppKit `NSWindow`** (`AppController.openSettings` →
  `ensureSettingsWindow`), not the SwiftUI `Settings` scene / `showSettingsWindow:`
  (unreliable for a menu-only `LSUIElement` app). An in-panel 3D "card flip"
  (`PanelContainer`, load-spinner ADR 0003 style) was tried and **reverted**: the
  container's 180° `rotation3DEffect` inverts hit-test z-order so the flipped Back
  button couldn't be clicked (only Esc worked). `allowsHitTesting` gating didn't fully
  fix it — a separate window is reliable and conventional. The `Settings { EmptyView() }`
  scene is just the required placeholder.
- **No special permissions / no Accessibility** — selected-text translation was
  descoped, so the app needs no TCC grant (only the OS's language-model download
  consent). The global hotkey uses Carbon `RegisterEventHotKey` (no TCC). Don't add
  Accessibility back without a deliberate scope decision.
- **Only OS-supported languages in pickers** — `LanguageCatalog` loads them async from
  `LanguageAvailability`; `PanelView.run` pre-checks `status(from:to:)` for a clear
  unsupported-pair message.
- **Cask min-macOS** (`scripts/cask.rb.tmpl`) is the shared template's `:big_sur`
  floor; the app itself enforces macOS 26 via `LSMinimumSystemVersion`. Bump the
  cask floor at release if precision matters.

## Design reference

- RFP: `docs/ja/instant-translate-rfp.ja.md` (`docs/en/instant-translate-rfp.md`)
- Sibling: https://github.com/nlink-jp/quick-translate
