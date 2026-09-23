# 45 — Text input and `TextField`, 2026-09-23

Branch `feat/text-input`, from `feat/accessibility` (PR #25, record §44).
Spec: `docs/superpowers/specs/2026-09-23-text-input-design.md`, rulings
`TI-A`…`TI-F` (next `TI-G`). Roadmap item 14. The user chose the full field:
caret, selection, editing keys, input-method composition and the clipboard,
on AppKit and on SDL3.

## What changed

- **Platform seam (`TI-A`).** `InputEvent` gains `.textInput`,
  `.textComposition(TextComposition)` and `.mouseDragged`. `PlatformWindow`
  gains `setTextInputArea(_:)`, `readClipboard()` and `writeClipboard(_:)`, with
  no default implementations.
  - **AppKit:** the host view is an `NSTextInputClient`. While a caret is set,
    a non-command key goes through `inputContext.handleEvent`. `doCommand(by:)`
    re-delivers the key in flight as a `keyDown`. It gains `mouseDragged`. The
    clipboard is `NSPasteboard.general`.
  - **SDL:** `SDL_EVENT_TEXT_INPUT`/`TEXT_EDITING` and left-button motion are
    flattened. `SDL_StartTextInput` and `SDL_SetTextInputArea` run with the
    caret, and `SDL_StopTextInput` stops it. The clipboard is SDL's. A key-down
    that would produce text is dropped while text input is on.
- **Routing (`TI-B`).** `Handlers.textInput` is internal and set only by
  `TextField`. It makes the element a pointer and key target and is recorded
  in the focus registry. `Window` dispatches in this order:
  1. A press on a field focuses it and places the caret; a drag selects.
  2. Text and composition go to the focused field only.
  3. Keys go `Keymap` → field → raw `onKey` → `onInput`.

  After each frame, `setTextInputArea` gets the focused field's caret, or nil.
  Editing state lives in `StateTable` under the field's id.
- **`TextField` (`TI-C`).** A controlled, single-line field:
  `TextField(_:text:onChange:)` plus `.onSubmit`, `.font` and
  `.foregroundColor`, and it is a `StyledElement`.
  - **Layout:** it is a new lowering site, `textField`. It is greedy under the
    proposal authority. Under the legacy one it takes its natural width and a
    `Box` stretches it.
  - **Paint:** selection, text or a dimmed placeholder, the composition
    underlined, and a caret that does not blink. Text wider than the field
    scrolls horizontally.
  - **Accessibility:** a new role, `.textField`, in `AXRole` and
    `AccessibilityRole`. It maps to AppKit's `.textField` and AccessKit's
    `TEXT_INPUT`.
- **Editing (`TI-D`).** `TextEditing` is a set of pure functions over
  Character offsets: the key table on both platforms' conventions, plus
  insertion, composition, press, drag, nearest boundary and scroll.
- **Caret offsets (`TI-E`)**, a parallel lane, commit `0e127b1`:
  `TextSystem.caretOffsets(_:font:)`.
  - **CoreText:** `CTLineGetOffsetForStringIndex`, with the line's width as the
    last value.
  - **Portable:** `shapeCascading` plus three measured rules.
  - **HarfBuzz:** gains `nominalAdvance(of:)` and `ligatureCarets(of:)`.
- **Demo.** A separate root, `textInputDemoContent()`: two fields and an
  echo line, opened by `METALUI_TEXT_INPUT_DEMO=1 swift run MetalUIDemo`, and
  by `MetalUISDLDemo` with the same variable.
  - **It is not a panel of `demoContent()`.** A first version put one field
    under the paragraph. That re-recorded the cross-platform frame pin
    (518 → 519 rects, 15 710 → 15 756 glyphs) and read the same on Linux
    aarch64.
  - But it moved `theWholeDemoReportsExactlyTheFieldsAndSitesLaterStagesOwn`,
    whose 2 035 ids and 29 attributed disagreements are derived from named
    causes, and the scroller below the field shrank with it. Re-deriving that
    corpus for a demo affordance was the wrong trade, so the field moved out
    and both pins are `master`'s.

## Measured

- **The caret oracle** (from the lane's report): 280 cases and 6 216 grapheme
  boundaries, 0 differences at 1e-9 pt. A plain sum of advances differed in
  185 of the first 272 cases. Three rules, each read at 1000 pt, brought that
  to 0:
  - CoreText uses the font's **GDEF ligature carets** when the font has them
    (Noto Sans `ff`: 301 of 688, not 344), and splits evenly only when it has
    none (Source Sans 3).
  - The caret between two clusters sits **halfway through the kern** (Noto Sans
    `AV`: 619 between 599 and 639).
  - A default-ignorable character's zeroed advance (a soft hyphen) is not a
    kern.
- **A bug found by the first `Window` test run:** two edits between frames —
  a cut, then a paste — both started from the text the last frame saw, and
  read `"pastedhello"`. `Window.editedText` now carries the latest edit until
  the next frame rebuilds the target (T2 pins it).
- **A crash found by the first SDL run:** converting an input method's range
  to Characters trapped when the range fell inside a grapheme ("String index
  is out of bounds"), because the index was not Character-aligned. Both
  converters (AppKit's UTF-16 and SDL's code points) now count whole
  Characters and round down.
- **The real `NSTextInputContext`** turns a plain `a` into `insertText("a")`
  and an arrow into `doCommand`, synchronously, in the test process
  (`keysGoThroughTheInputContextOnlyWhileTextInputIsOn`).
- **Under the legacy authority** the field sizes as a `Text` does: 36 × 200 in
  a `Box` in a 200-point window, against 200 × 16 under the proposal authority.
  The spec's first wording ("the offered definite width") was wrong for a flex
  item and was corrected.
- **Demo parity on macOS, with the first version's field in the frame:**
  frame 5 had 519 rects, 15 756 glyphs and 1 010 runs; the scene was
  byte-for-byte macOS's, with 0 differing pixels through SDL Metal
  (`Replay --portable`, `PortableReplay`, `DemoCapture`). Since the move the
  frame is `master`'s again.

## Counts

1746 tests, 97 goldens, 78 guards; 0 `error:` and 0 `warning:` on both build
systems after `swift package clean` (`Test run with 1746 tests in 3 suites
passed`, the guards ran). 1746 = 1712 + 4 (the caret lane) + 30 (10 + 13 + 7).
`Backends/SDL`: 21 + 19 on macOS, 21 + 18 on Linux aarch64 in the CI image.
Linux aarch64 (`swift:6.4-noble`): the root's portable suites 486 + 3 + 22,
the demo-frame pin included.

## Mutations

Root package (filter: `TextFieldTests|TextEditingTests|TextInputPlatformTests|everyLegacySiteIsReportedByName`):

| # | Mutant | Reddens |
|---|---|---|
| T1 | a press on a field does not focus it | 10 of the 12 `TextFieldTests` |
| T2 | edits between frames start from the frame's text | `copyCutAndPasteGoThroughThePlatformClipboard` |
| T3 | field keys before the keymap | **green at first** — the binding was `cmd-k`, which no field claims; rebound to the field's own select-all, it reddens `anAppsKeymapBindingWinsOverEditingAndUnclaimedKeysBubble` |
| T4 | no `setTextInputArea` after a frame | `aCompositionIsShownThenCommitted`, `aLongTextScrolls…`, `clickingAField…`, `textGoesOnlyToAFocusedField` |
| T5 | a field is not a pointer target | the same 10 as T1 |
| T6 | command keys also go through the input context | **green**, and kept: the context declines a command key and it comes back as the same `keyDown` either way — measured with the ABC layout; an input method that claimed shortcuts would differ |
| T7 | `doCommand` drops the key | `keysGoThroughTheInputContextOnlyWhileTextInputIsOn` |
| T8 | `onSubmit` not carried to the target | `returnRunsOnSubmitAndIsNotClaimedWithoutOne` |
| T9 | caret painted while unfocused | `aFieldPaintsItsPlaceholderCaretSelectionAndComposition` |
| T10 | placeholder not dimmed | `aFieldPaints…` |
| T11 | the scroll not written back | **green at first** — recomputing from 0 pins the caret to the right edge, which reads the same at the end; the test now walks the caret ten left and it reddens `aLongTextScrollsToKeepTheCaretVisible` |
| T12 | composition caret at its start | `aCompositionIsShownThenCommitted` |
| T13 | the greedy width dropped | 6 tests, `aFieldLaysOutAndEditsUnderBothAuthorities` among them |
| T14 | `unmarkText` commits nothing | `theInputContextsCallbacksBecomeTextEvents` |
| T15 | cut copies nothing | `shortcutsSelectCopyCutAndPaste` |

`Backends/SDL` (filter: the five `SDLTextInputTests`):

| # | Mutant | Reddens |
|---|---|---|
| S1 | a typed key-down not dropped | `textAndCompositionArriveOnlyWhileTextInputIsOn` |
| S2 | the editing range counted in Characters, not code points | `anEditingSelectionInCodePointsBecomesCharacterOffsets` |
| S3 | held-button motion reported as a move | `motionWithTheButtonHeldIsADrag` |
| S4 | text events delivered with text input off | `textAndCompositionArriveOnlyWhileTextInputIsOn` |

The caret lane's nine mutations (M1–M9) are in its commit message and the
oracle's doc comment; all redden, M8 only through the per-string invariant
test.

## Open

- **Human looks:**
  - a real input method (Japanese, Pinyin) in the demo field on macOS and on
    SDL, and its candidate window at the caret;
  - dead keys on a real layout;
  - copy and paste to and from another app;
  - that plain-letter demo bindings (Space, A, M) stay quiet while the field
    is focused, and Esc unfocuses it.
- **Out of scope:** multi-line editing, undo, secure entry, bidirectional
  carets and a blinking caret.
