# ADR-0001: Panel Feedback and Failure Messages

| Field | Value |
|-------|-------|
| Status | **Accepted** |
| Date | 2026-08-08 |
| Binds | instant-translate |
| Decision makers | nlink-jp maintainers |
| Triggered by | User report after v0.2.0: the panel never says whether a translation is running, and every framework failure surfaces as the same unhelpful sentence |

## Context

Two complaints about v0.2.0, both about the panel telling the user nothing.

**1. Failures are illegible.** `PanelView.run` renders one line on any thrown
error:

```swift
model.fail("Couldn't translate — the language model may still be downloading. \(error.localizedDescription)")
```

Measured against the macOS 26.5 SDK, `TranslationError.localizedDescription`
collapses **seven of its eight cases to the single string `"Unable to
Translate"`** (only `nothingToTranslate` differs). The discriminating text
lives in `failureReason`, which this code never reads:

| Case | `localizedDescription` | `failureReason` |
|------|------------------------|-----------------|
| `unsupportedSourceLanguage` | Unable to Translate | Translation from this language is not supported. … |
| `unsupportedTargetLanguage` | Unable to Translate | Translation into this language is not supported. … |
| `unsupportedLanguagePairing` | Unable to Translate | This language pairing is not supported. |
| `unableToIdentifyLanguage` | Unable to Translate | The language could not be automatically detected. |
| `nothingToTranslate` | Translation Request Empty | Please provide text to translate and try again. |
| `alreadyCancelled` | Unable to Translate | Translation was already cancelled. |
| `notInstalled` | Unable to Translate | Languages must be downloaded on-device. |
| `internalError` | Unable to Translate | Something went wrong. Please try again later. |

The `NSError` bridge does not help either: every case is domain
`Translation.TranslationError`, **code 1**. So the user sees

> Couldn't translate — the language model may still be downloading. Unable to Translate

for an unsupported language pair, for an internal service fault, and for a
genuinely missing model alike. The prefix is a guess, and it is wrong in most
of those cases — it actively misleads.

`TranslationError` is a struct with a custom `~=`, not an enum, so it cannot
be `switch`ed on shape. A probe of the full 8×8 match matrix confirms `~=`
discriminates cleanly (an exact diagonal; unrelated errors and
`CancellationError` match nothing), so precise classification *is* available —
it simply was not being done.

**2. There is no activity indication.** `TranslationModel.isTranslating`
exists and is maintained, but no view reads it. Worse, several states that
deliberately *withhold* a translation are equally invisible:

- the 600 ms debounce is armed (typing paused, nothing has started yet);
- an IME composition is open, so `AutoTranslatePolicy` is holding everything
  back (v0.1.2);
- the input is not yet identifiable as any language, so an automatic run
  stands down rather than raising the OS source-language picker (v0.2.0);
- source and target resolve to the same language, so the input is echoed
  unchanged — output identical to input, with no stated reason;
- the OS language model for the pair is not downloaded, so the first
  translation of that pair blocks for a long time with no explanation.

Each of these was a correct behavioural decision, and each is silent. The
compound effect is a panel that looks broken while it is working as designed.

Both complaints are the same defect at different points in the pipeline: the
panel knows its state and does not say it.

## Decision

### Decision 1: Classify framework failures and phrase them for a human

A new `TranslationFailure` enum names every failure the app can hit —
the eight `TranslationError` cases, our own pre-flight
`LanguageAvailability` rejection, and an `unknown` catch-all carrying whatever
text the error could supply.

`TranslationFailure.classify(_:)` is the only place that touches the
framework; it matches with `~=` and falls back to `unknown(failureReason ??
localizedDescription)`. `TranslationFailure.message(sourceName:targetName:)`
is **pure** and unit-tested, and returns three fields:

- **headline** — what happened, naming the actual languages
  ("macOS can't translate Japanese → Korean.");
- **recovery** — what the user can do about it, naming the control that does
  it ("Choose a different target language with the right picker.");
- **detail** — the technical tag (`TranslationError.unsupportedLanguagePairing`),
  rendered small, monospaced and selectable.

The detail line exists for the same reason the version string was put in the
panel header in v0.1.3: this app has no menu bar, no About item, and no log
file, so a bug report can only contain what the panel shows. Copyable exact
cause plus copyable exact build is the whole diagnostic surface.

### Decision 2: A phase model, surfaced as one status row

`TranslationModel.isTranslating: Bool` is replaced by
`TranslationModel.phase: TranslationPhase` covering every state above:

```
idle · composing · awaitingLanguage · pending · preparing · translating · echoed · done · failed
```

`isTranslating` survives as a computed property (`preparing` or
`translating`) so existing call sites and tests keep working.

A single always-present status row sits between the language pickers and the
output. `TranslationStatus.display(...)` maps a phase to symbol / text /
spinner / tone and is **pure and unit-tested** — the same split already used
for `LanguagePolicy` and `AutoTranslatePolicy`. The row is always rendered so
the layout never jumps, and `idle` with text in the field and auto-translate
off shows the manual shortcut instead of nothing.

### Decision 3: Prepare the language model explicitly, and say so

Rather than let the first translation of an uninstalled pair block silently
inside `session.translate`, `PanelView.run` checks `session.isReady` and, when
false, enters `preparing` and calls `session.prepareTranslation()` before
translating.

This does not add a dialog the app was otherwise avoiding — the OS raises its
download consent for that pair either way. It moves it to a moment the panel
has already labelled ("Preparing the Japanese → English language model — the
first use downloads it…"), instead of an unexplained multi-second freeze.

This is deliberately narrower than the v0.2.0 stance on the OS
*source-language* picker, which the app works hard to never trigger: that
dialog is avoidable and interrupts typing mid-sentence, whereas the model
download is mandatory, one-off per pair, and something the user needs to
consent to knowingly.

## Consequences

- Failures name their cause, their affected languages, and a next action.
  `notInstalled` — the only case the old wording ever described correctly —
  now also points at System Settings › General › Language & Region ›
  Translation Languages as an alternative to waiting.
- Five previously invisible states become visible, including the two
  "correctly doing nothing" ones (IME composition, undetectable input) that
  most look like a hang.
- The echo path (source == target) states its reason instead of silently
  returning the input unchanged.
- `TranslationFailure` and `TranslationStatus` are unit-testable without a
  view, a session, or a live input method. `classify` is testable too, because
  `TranslationError`'s cases are public constructible values.
- The status row costs one line of vertical space in a panel with a 280 pt
  minimum height. Acceptable; the panel is user-resizable.
- Strictly additive to behaviour except for the explicit `prepareTranslation()`
  call, which changes *when* the OS download consent appears, not whether.
- No new settings. Every state either reports itself or does not exist.

## Alternatives considered

**A1. Keep one error line, but append `failureReason`.** Cheapest fix, and it
would have removed the worst symptom (all failures reading alike). Rejected
because Apple's `failureReason` strings are written for a system dialog with
no knowledge of this app: "Please try another language" cannot say *which of
the two pickers* to touch, and none of them mention that a pinned source or a
target override is what produced the pair. Owning the phrasing is what makes
the message actionable, and it costs one pure function.

**A2. Drop `failureReason` entirely and show only our own text.** Rejected in
the other direction: when `classify` cannot place an error, Apple's string is
the only information left, and discarding it would recreate the original bug
for exactly the cases we did not anticipate. `unknown` carries it.

**A3. A spinner only, no phase model.** A spinner answers "is it running"
but not "why is nothing running", which is the harder half of the complaint —
debounce, IME hold, and undetectable input all look identical to idle. A
boolean cannot distinguish them.

**A4. Toast/alert for errors instead of an inline block.** Rejected: the panel
dismisses on deactivation, so a transient toast can be lost before it is read,
and an alert steals focus from a text field the user is mid-sentence in. The
inline block persists exactly as long as the failure is the current state.

**A5. A Cancel button for an in-flight translation.** `TranslationSession.cancel()`
exists on macOS 26. Rejected for this round: it requires `PanelView` to hold
the session outside the `.translationTask` closure, which is the lifetime
model the framework specifically does not offer, and the status row already
resolves the reported problem ("is it running or stuck"). Revisit if a real
long-running case appears.

**A6. Detect the missing model with `LanguageAvailability.status(from:to:) == .supported`
instead of `session.isReady`.** Both are reachable, and the pre-flight already
calls `status(from:to:)` for the unsupported check. Rejected as the *gate*
because `isReady` is a property of the session that will actually run, while
`status` describes the pair in the abstract; using the session's own answer
removes a class of disagreement between the two. `status` keeps its existing
job of rejecting unsupported pairs before a session is used at all.

## References

- `Translation.framework` interface, macOS 26.5 SDK — `TranslationError`,
  `TranslationSession.isReady`, `prepareTranslation()`, `LanguageAvailability.Status`
- v0.1.2 — IME composition gating (`AutoTranslatePolicy`)
- v0.1.3 — version string in the panel header, for bug reports
- v0.2.0 — explicit source language, to keep the OS source-language picker away
