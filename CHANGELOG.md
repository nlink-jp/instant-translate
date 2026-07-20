# Changelog

All notable changes to instant-translate are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/), and the project adheres to
Semantic Versioning.

## [Unreleased]

### Fixed
- **Auto-translate no longer fires in the middle of an IME composition.** While a
  kana-kanji conversion (or any input method) was still composing, the debounce timer
  could elapse and translate the half-converted text. That text isn't recognisable as
  any language, so macOS put up its source-language picker on top of the panel and
  blocked further typing. The source field is now an IME-aware `NSTextView`
  (`SourceTextView`) that reports uncommitted *marked* text; auto-translate holds until
  the composition is committed, and an automatic run additionally stands down when the
  input language can't be detected (the condition that raises that picker). Manual
  Translate (⌘↩) is unchanged — it always runs.
- **The text cursor is now visible in an empty input field**, so it's clear the panel
  has focus. Focus is applied directly to the text view on each panel open instead of
  through SwiftUI's `@FocusState`, and an empty field shows a "Type or paste text to
  translate" placeholder.
- **The cursor also appears when the panel is opened by the global hotkey while another
  app is frontmost.** A text view only draws its insertion point in a *key* window, and
  the panel wasn't reliably taking key status in that case: macOS refuses to activate
  the app, and activation is asynchronous besides. The panel now states that it accepts
  key status, key status and focus are re-asserted after activation settles, and the
  text view claims focus again whenever the panel becomes key.

## [0.1.1] - 2026-07-19

### Fixed
- The panel sometimes wouldn't open for up to ~30 s after launch (it opened only once
  the app happened to become active). The menu-bar `NSPanel` depended on the app being
  active to render, but macOS 14+ focus-stealing prevention can deny
  `NSApp.activate(ignoringOtherApps:)` right after launch — so the panel was
  `isVisible` yet never shown on screen. The panel is now a `.nonactivatingPanel`, so it
  renders and accepts keyboard input without requiring app activation (the reason
  NSPopover-based menu-bar apps don't hit this). Also: `orderFrontRegardless()` on show,
  a short grace period so a post-launch focus bounce can't hide the just-opened panel,
  and the panel is pre-warmed at launch.

## [0.1.0] - 2026-07-19

First release.

### Added
- Lightweight macOS menu-bar translator built on the OS **Translation framework**
  (on-device `TranslationSession`) — no LLM, no network, no credentials. macOS 26+,
  Apple silicon; Developer ID signed + notarized.
- Menu-bar panel (resizable `NSPanel`): type or paste source text and translate; the
  input is focused on open, and the panel size is remembered.
- **Debounced auto-translate** (~600 ms after you stop typing; toggle in Settings),
  plus manual Translate (⌘↩).
- **Smart language routing**: the input language is auto-detected
  (`NLLanguageRecognizer`); output goes to your system language, auto-swapping to a
  configured secondary language when you type in your own language (toggle in Settings).
- **Manual target picker** ("Auto" + languages) to temporarily override the target;
  resets to Auto on restart.
- **OS-supported languages only**, with regional variants distinguished (e.g. English
  (United States) vs English (United Kingdom), Chinese (China) vs Chinese (Taiwan));
  unsupported pairs are reported clearly.
- **Global hotkey** (default ⌥⌘T, rebindable via a built-in recorder) to open the panel
  from anywhere; on hotkey-open the source can be seeded from the clipboard and
  translated.
- **Copy** the result (with optional auto-copy). The most-recent entry is kept in
  memory only (volatile — cleared on quit).
- **Launch at login** (Settings → General) via `SMAppService`.
- Needs **no special permissions** — only the OS's own language-model download consent.

### Notes
- Selected-text translation (which would have required Accessibility) was descoped; the
  global hotkey + clipboard seeding covers the "translate what I'm looking at" flow.
