# RFP: instant-translate

> Generated: 2026-07-19
> Status: Draft

> **Scope update (2026-07-19):** Trigger #3, *selected-text translation* (which would
> have required Accessibility), was **cancelled** during Phase 2. Consequently the app
> needs **no special permissions** (only the OS's language-model download consent), and
> "Accessibility permission" in §5 no longer applies. The global hotkey + clipboard
> seeding covers the "translate what I'm looking at" flow. The rest of the document is
> as originally planned and implemented.

## 1. Problem Statement

**instant-translate** is a lightweight, menu-bar-resident translation app for macOS
built on the Translation framework (on-device translation). Users open a panel from
the menu bar to type or paste source text, trigger translation via a global hotkey,
or translate selected text from another app — then review the result and copy it for
reuse. Unlike the existing `quick-translate` (local-LLM version), which loads
tens-of-gigabyte LLM models, instant-translate uses the OS-standard on-device models
(downloaded once with user consent, lightweight), so it launches fast and keeps memory
pressure low. The target users are macOS users — including the developer — who want to
knock out short translations quickly. It coexists with `quick-translate` as a sibling
(same UX, different backend), each used where it fits.

## 2. Functional Specification

### Commands / API Surface

GUI-only app (no CLI subcommand). Menu-bar resident (NSStatusItem / MenuBarExtra),
with the translation panel launched from three triggers:

1. **Direct input from the menu bar** — click the icon to expand the panel, type/paste
   source text → see the translation → copy. Minimal path requiring no extra permission.
2. **Global hotkey** — bring up the panel instantly from anywhere via a shortcut.
   Optionally auto-fill the source field from clipboard contents.
3. **Selected-text translation** — grab text selected in another app via a hotkey and
   translate it (synthesize `Cmd+C` → read the pasteboard). Requires Accessibility
   permission.

The panel consists of a source-input field, a translation-output field, and copy /
language-switch controls.

### Input / Output

- Input: typed text, clipboard, text selected in another app
- Output: translation shown in the panel + copy to clipboard
- No pipe/stdin-stdout or file I/O (GUI I/O only)

### Language Handling

- **Source language is auto-detected** (Translation framework language detection)
- The default output target is the system's local locale (e.g. `ja`)
- **When the input is detected as the same language as the local locale, the output is
  automatically swapped to a configured secondary locale** (e.g. `en`). This automatic
  behavior can be toggled on/off in settings
- In practice this yields smart bidirectional behavior:
  "foreign → native / native → configured foreign"

### History

- Keeps only the most recent single entry in memory
- **Not persisted** (volatile; cleared when the app quits)

### Configuration

- Settings are persisted in `UserDefaults` and edited via a SwiftUI Settings screen
- Setting items: secondary locale, auto-swap on/off, hotkey bindings,
  clipboard-auto-translate on/off, etc.

### External Dependencies

- External services / APIs / credentials: **None**
- Depends only on the OS Translation framework (on-device)
- No network required by the app (the OS communicates only during language-model
  download; the app is not involved)
- Global hotkey implemented primarily via Carbon `RegisterEventHotKey`
  (adoption of an additional library to be decided at implementation time)

## 3. Design Decisions

- **Why Swift/SwiftUI**: The Translation framework is Swift/SwiftUI-native, and
  `TranslationSession` is obtained by attaching to a SwiftUI view. A menu-bar GUI is
  also best served by SwiftUI. It aligns the tech stack with existing Swift menu-bar
  apps (`quick-translate`, `claude-usage-lens-gui`, `active-lens-gui`).
- **Why Apple Translation**: To eliminate the weight of `quick-translate`'s
  tens-of-GB LLM load (launch latency, memory pressure). Adopts on-device, lightweight,
  OS-managed models.
- **Complementary nlink-jp tools**: A lightweight sibling of `quick-translate`
  (same UX, different backend, coexisting). Belongs to the util-series macOS GUI apps.
- **Explicitly out of scope**:
  - CLI / pipe integration (GUI-only)
  - Persisting translation history
  - OCR-based on-screen translation (SwiftyCrow-style; future consideration)
  - macOS 25 and earlier; iOS
  - A custom/proprietary translation engine (translation quality is left to the OS)

## 4. Development Plan

### Phase 1: Core

- Menu-bar residency + translation panel UI
- `TranslationSession` hosting (including a resident hidden SwiftUI host view for the
  closed-panel path)
- Translation from direct input
- Automatic language handling (auto-detect + local-locale detection + secondary-locale
  auto-swap)
- Copy translation, hold the most recent single entry (volatile)
- Tests: extract the language-decision logic as pure functions and unit-test it;
  design `TranslationSession` to be testable via dependency injection / mocking

### Phase 2: Features

- Global hotkey
- Clipboard auto-translate
- Selected-text translation (Accessibility)
- SwiftUI Settings screen
- Handling of not-yet-downloaded models / consent prompt / unsupported pairs
  (`LanguageAvailability`)

### Phase 3: Release

- README.md / README.ja.md, CHANGELOG.md, AGENTS.md
- Developer ID signing + notarization
- Homebrew tap (arm64-only prebuilt binary)
- Update umbrella submodule pointer
- Update org profile / web-site catalog (EN + JA)
- `check-org.sh` all green

### Independently Reviewable Boundaries

- Phase 1 (core translation path) and Phase 2 (trigger expansion / permissions) can be
  reviewed independently

## 5. Required API Scopes / Permissions

- **Accessibility permission (TCC)**: Required for selected-text translation to
  synthesize `Cmd+C` and read the selected text from the pasteboard.
- **First-time Translation model download consent**: When using a not-yet-downloaded
  language pair, the OS shows a user-consent prompt. The app pre-checks download state
  via `LanguageAvailability` and handles it (the app cannot suppress the consent).
- **Global hotkey**: Using Carbon `RegisterEventHotKey` requires no additional TCC
  permission.
- **OAuth / IAM scopes**: None (does not connect to any external service).

## 6. Series Placement

Series: **util-series**
Reason: A general-purpose local-utility macOS GUI app, positioned the same as existing
util-series GUI apps such as `quick-translate`, `claude-usage-lens-gui`,
`active-lens-gui`, and `image-forge-gui`. With neither external-service integration nor
a security purpose, no other series applies.

## 7. External Platform Constraints

Constraints stemming from the macOS **Translation framework**:

- `TranslationSession` cannot be instantiated directly; it is obtained by attaching
  `.translationTask()` to a SwiftUI view. → For the closed-panel paths
  (hotkey / selected text), keep a hidden view that hosts the session resident.
- The session is bound to the host view's lifetime and is invalidated when the view
  disappears; the session must not be retained beyond the view's lifetime.
- Supported languages are limited to what the OS provides; arbitrary language pairs are
  not available. Unsupported / not-yet-downloaded pairs are pre-checked and handled via
  `LanguageAvailability`.
- The first-time model download requires user consent and is managed by the OS
  (the app cannot suppress or automate it).
- Due to the programmatic translation API, the app targets macOS 26 only.
- No rate limits or network constraints (local, on-device processing).

---

## Discussion Log

- **Genesis**: Learning about macOS's built-in translation API (Translation framework)
  sparked the idea of a lightweight app to fix the poor usability of the existing
  `quick-translate`, which loads tens of GB of LLM.
- **Technical premise check**: Web research confirmed that `TranslationSession` can only
  be obtained via SwiftUI's `.translationTask()` (cannot be created directly; bound to
  the view lifetime). However, the menu-bar popover itself is a SwiftUI view, and the
  closed-panel case is achievable by keeping a hidden host view resident — existing
  examples (e.g. SwiftyCrow) share this structure.
- **Positioning decision**: Coexist as a new sibling app separate from `quick-translate`
  (local LLM); the replace/integrate options were rejected. Same UX, different backend,
  used per fit.
- **Trigger decision**: Adopt all three — direct panel input, global hotkey, and
  selected-text translation. Confirmed the implications: selected-text needs
  Accessibility permission, and closed-panel translation needs a resident hidden host
  view.
- **Language-handling decision**: Auto-detect input. Default output to the local locale;
  when input equals the local locale, auto-swap the output to a configured secondary
  locale — made toggleable in settings.
- **History decision**: Keep only the most recent single entry, volatile
  (no persistence), prioritizing lightness.
- **CLI co-residency decision**: Given the Translation framework's view-host requirement
  and the "lightweight" intent, keep it GUI-only (no CLI subcommand).
- **Minimum OS decision**: macOS 26 only (use the stable programmatic API; keep
  implementation and verification simple).
- **Naming**: Compared `native-translate` / `menu-translate` / `instant-translate` /
  `lingo-bar`, and chose **instant-translate** to convey the immediacy of hotkey-driven
  translation.
