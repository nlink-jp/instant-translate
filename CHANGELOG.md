# Changelog

All notable changes to instant-translate are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/), and the project adheres to
Semantic Versioning.

## [Unreleased]

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
