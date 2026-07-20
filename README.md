# instant-translate

A **lightweight** macOS menu-bar translator built on the OS **Translation
framework** (on-device). Open a panel from the menu bar, translate, copy — no
tens-of-gigabyte model to load.

The lightweight sibling of [`quick-translate`](https://github.com/nlink-jp/quick-translate)
(local LLM): same menu-bar UX, a different backend. Use `quick-translate` when you
want an LLM's quality/customization; use instant-translate when you want it fast
and light. macOS 26+ (Apple silicon). Signed with Developer ID and notarized.

> **Status: pre-release (Phase 1 scaffold).**

## What it does

- **Menu bar**: click to open the translation panel.
- **Type or paste** source text → it **auto-translates** shortly after you stop
  typing (toggle in Settings), or translate immediately with ⌘↩ → **copy** the result.
  Auto-translate waits for your input method: while an IME is composing (kana-kanji
  conversion, pinyin, hangul…) nothing is translated until you commit the text.
- **Smart language routing**: the input language is auto-detected; output goes to
  your system language. When you type in *your own* language, the output is
  auto-swapped to a configured **secondary language** (e.g. English) — toggle in
  Settings. In short: *foreign → native, native → your chosen foreign*.
- **Manual target**: a picker in the panel lets you temporarily send the translation
  to a specific language instead of Auto (resets to Auto on restart).
- **Global hotkey**: press **⌥⌘T** (rebindable in Settings) to open the panel from
  anywhere. On open it can seed the source from your clipboard and translate it.
- **Only OS-supported languages**: the pickers list exactly the languages your Mac's
  Translation framework supports; unsupported pairs are reported clearly.
- **Launch at login**: optional (Settings → General).
- **Volatile history**: the most recent translation is kept in memory only (never
  written to disk); it clears when you quit.

**No special permissions:** instant-translate needs no Accessibility or other TCC
grant — only the OS's own one-time language-model download consent.

## How it works

Translation is performed entirely **on-device** by macOS's Translation framework.
The first time you use a language pair, macOS downloads its (small, OS-managed)
model with your consent. The app itself needs **no network, no API key, no
credentials**.

## Build

```sh
make run          # build + run (debug)
make build        # release binary → .build/release/
make build-app    # signed .app → dist/
make package      # build-app + notarize + staple + zip (release)
make test
```

Requires the macOS 26 SDK (recent Xcode / Command Line Tools).

## Why Apple Translation (not an LLM)

`quick-translate` loads a local LLM (tens of GB) for high-quality/customizable
translation, at the cost of slow start and heavy memory. instant-translate trades
that for the OS's on-device models: near-instant, light, and good enough for quick
day-to-day translations. The two coexist.

## License

MIT — see [LICENSE](LICENSE).
