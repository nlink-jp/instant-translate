# Changelog

All notable changes to instant-translate are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/), and the project adheres to
Semantic Versioning.

## [Unreleased]

## [0.3.0] - 2026-08-08

### Added
- **The panel now says what it is doing.** A status line under the language pickers
  reports every state: ready, waiting for you to pause typing, waiting for your
  input method to commit, "can't tell the language yet — type more, or pin it on
  the left", preparing the language model, translating (with a spinner), and
  translated. The states where the app is *deliberately* not translating — an open
  IME composition, input too short to identify — now say so instead of looking
  identical to a hang.
- **The first use of a language pair is announced.** macOS downloads the on-device
  model for a pair the first time you use it; the panel now prepares it explicitly
  and shows "Preparing the Japanese → English language model — the first use
  downloads it…", instead of freezing for several seconds with no explanation.
- **Passing the input through unchanged is explained.** When the input is already
  in the target language, the status line says "Input is already Japanese — shown
  unchanged" rather than silently showing output identical to the input.

### Changed
- **Translation failures are legible.** Every failure now names its cause, what to
  do about it, and the exact technical error — the last one selectable, so it can
  be pasted into a bug report (this app has no log file). Previously every failure
  read:

  > Couldn't translate — the language model may still be downloading. Unable to Translate

  `TranslationError.localizedDescription` collapses seven of its eight cases to
  that same "Unable to Translate", and all of them bridge to `NSError` code 1, so
  an unsupported language pair, an internal service fault and a genuinely missing
  model were indistinguishable — and the "may still be downloading" prefix was a
  guess that was wrong in most of them. The cases are now told apart properly and
  phrased for a person, e.g.:

  > macOS can't translate Japanese → Korean.
  > Choose a different target language on the right, or pin a different input language on the left.
  > `TranslationError.unsupportedLanguagePairing`

  A missing model additionally points at System Settings › General › Language &
  Region › Translation Languages as an alternative to waiting.
- The panel's minimum height is now 320 pt (was 280 pt), to fit the status line
  above the two text areas. Panels already sized larger are unaffected.

See [ADR-0001](docs/en/adr/0001-panel-feedback-and-failure-messages.md)
([ja](docs/ja/adr/0001-panel-feedback-and-failure-messages.ja.md)).

## [0.2.0] - 2026-07-31

### Added
- **Pin the input language**: a new source picker in the panel ("Auto" + languages,
  mirroring the target picker) skips detection entirely and always translates the
  input as the pinned language. Like the target override it is in-memory only and
  resets to Auto on restart. While pinned, auto-translate no longer needs the text
  to be detectable, so even very short input translates automatically.

### Changed
- **Ambiguous input no longer triggers the macOS source-language picker.** Two
  changes together: (1) language detection now weighs your own languages — the
  system language and the configured secondary language — so a close call
  (e.g. kanji-only text that reads as Japanese *or* Chinese) resolves to the
  language you actually use; (2) the resolved source is passed explicitly to the
  Translation framework instead of letting it re-detect, so the OS has nothing to
  ask about. The dialog can still appear for a *manual* ⌘↩ translate when the
  input is genuinely undetectable (deliberate — the OS asking beats guessing).
- The "Auto" source now shows what it detected next to the picker, mirroring the
  target side.

## [0.1.3] - 2026-07-20

### Added
- **The version is now visible in the app** — next to the title in the panel header, and
  again at the foot of Settings. The app has no menu bar and no About item, so there was
  previously no way to tell which build you were running. Both labels are selectable, so
  the exact string can be copied into a bug report.

## [0.1.2] - 2026-07-20

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
