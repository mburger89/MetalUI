# Text input and `TextField` — design

**Status: in progress** on `feat/text-input` (record §45); roadmap item 14 of
`plans/2026-09-23-cross-platform-roadmap.md`. **Ruling prefix:** `TI-`
(`TI-A`…`TI-F`, next `TI-G`; rulings here). The user chose a full
`TextField`: caret, selection, editing keys, IME composition and the
clipboard, on AppKit and on SDL3.

## Problem

MetalUI has no text entry. Keys arrive as `KeyEvent`s whose `characters`
come from the key alone, so dead keys, input methods (Japanese, Chinese,
Korean) and anything a keyboard layout composes are unreachable; there is no
clipboard; there is no element that holds an editable string.

## Rulings

### TI-A — Text arrives as text, not as keys

`InputEvent` gains three cases:

- `.textInput(String)` — committed text: a typed character after the
  platform's keyboard layout and dead keys, or an input method's commit.
- `.textComposition(TextComposition)` — an input method's uncommitted
  ("marked") text and the selection inside it; an empty composition ends it.
- `.mouseDragged(MouseEvent)` — pointer motion with the primary button held
  (AppKit's `mouseDragged`, SDL motion with the left button down). Hover
  still follows it: `Window` treats it as a move for hover.

`PlatformWindow` gains three requirements, **with no default
implementations** (the `AB-R` precedent — a platform that forgets them must
not compile):

- `setTextInputArea(_ caret: Bounds<Pixels>?)` — non-nil starts (or keeps)
  text input with the caret's rectangle in window points, where the input
  method puts its candidate window; nil stops it.
- `readClipboard() -> String?` and `writeClipboard(_:)` — plain text.

**While text input is active, a printable key is text, not a key.** AppKit
sends a non-command key through the input context
(`NSTextInputClient`): `insertText` becomes `.textInput`, `setMarkedText`
`.textComposition`, and `doCommand(by:)` re-delivers the original event as
`.keyDown`, so arrows, delete, return, tab and escape still reach `Keymap`
and the focused field. SDL sends `SDL_EVENT_TEXT_INPUT` and
`SDL_EVENT_TEXT_EDITING` itself and also a key event for the same press, so
`SDLWindow` drops a key-down that would produce text (no control or command,
a printable keycode) while text input is active. On both, a plain-letter
`Keymap` binding does not fire while a text field is focused, and a command
shortcut still does.

### TI-B — One text-input target, reached through focus

`Handlers` gains an internal `textInput: TextInputTarget?`, set only by
`TextField`. It makes the element a pointer target and a key target, rides
the ordinary `registerHandlers` path (so `.disabled` removes it with the
hitbox and focus entry) and the focus registry records it.

`Window` routes:

- **mouse down** on a text target focuses it (unlike every other element:
  clicking a field is how one types into it) and places the caret at the
  pointer; **drag** while it is pressed extends the selection.
- **`.textInput` / `.textComposition`** go to the focused element's target
  only — no bubbling, and nothing when the focused element is not a field.
- **key down**: `Keymap` first, then the focused field's editing keys, then
  the raw `onKey` bubble, then `onInput` — so a binding the app declares wins
  over editing, as a menu shortcut does.
- after each frame, `setTextInputArea` with the focused field's caret
  rectangle, or nil when no field is focused.

Editing state (selection, composition, horizontal scroll) lives in the
window's `StateTable` under the field's id, written from input only.

### TI-C — `TextField` is a controlled element

```swift
TextField("Name", text: name) { name = $0 }
    .font(size: 15)
```

`TextField(_ placeholder:text:onChange:)` shows `text` and calls `onChange`
with every edit; the caller stores it (`@State`, an `@Observable` model) and
passes it back. MetalUI has no two-way value binding (`Binding` is still the
deprecated alias of `KeyBinding`), and a controlled field needs none.
`onSubmit(_:)` runs on return. `StyledElement` like `Text`: `.padding`,
`.background`, `.border`, `.frame` and the sizing modifiers apply.

- **One line.** Its height is the font's line height; its width is greedy
  under the proposal authority (SwiftUI's `TextField` takes the offered
  width). Under the legacy authority it sizes as a `Text` does — the wider of
  its text and placeholder plus the caret, stretched across by `Box`
  (EP-8) — so `.flexGrow(1)` or a width widens it there. The line is centred
  in whatever height it gets.
- Text longer than the field **scrolls horizontally** to keep the caret
  visible; glyphs are clipped to the field.
- **Paint:** selection behind the glyphs (`accent` at 30 % opacity), the
  text — or the placeholder in `textPrimary` at 45 % opacity when the text
  and composition are empty (the theme has no secondary text token) — the composition inline at the caret, underlined, and a 1-point
  caret in the text colour when focused and nothing is selected. **The caret
  does not blink** — a blink keeps the display link awake forever.
- **Accessibility:** a new `AccessibilityRole.textField` — AppKit's
  `.textField`, AccessKit's `textInput` — labelled with the placeholder, its
  value the text.

### TI-D — Editing is a pure function over graphemes

`TextEditing` applies one event to `(text, TextEditState)` and returns the new
state and, if the text changed, the new text. Offsets are **grapheme
(Character) offsets**. Keys, in AppKit's characters (`SP-C`):

| Keys | Effect |
|---|---|
| ← / → | collapse a selection to its start/end, else move one grapheme |
| ⌥← / ⌥→ | to the previous/next word boundary |
| ⌘← / ⌘→, Home / End | to the start/end |
| any of the above + ⇧ | extend the selection instead |
| delete (`\u{7f}`) / forward delete | the selection, else one grapheme before/after |
| ⌥delete / ⌘delete | to the previous word boundary / to the start |
| ⌘A | select all |
| ⌘C / ⌘X / ⌘V | copy / cut / paste through the platform clipboard |
| return | `onSubmit`, not claimed if there is none |

The table is macOS's. **Off Apple platforms it is the Windows/Linux
convention**, chosen at compile time (`TextEditing.platform`): ⌘A/C/X/V are
ctrl-A/C/X/V, word motion and word delete are ctrl-←/→ and ctrl-delete, and
start/end are Home/End only (⌘←/→ and ⌘delete have no counterpart). `SDLKeys`
still reports control as `.control`, so a `Keymap`'s bindings are untouched;
an SDL window on macOS uses the macOS table. Pointer: one click places the caret at the
nearest grapheme boundary, two select the word, three select all, ⇧-click
extends; a drag extends from the press. A word is a run of letters, digits
and `_`.

### TI-E — Caret offsets come from the text system

`TextSystem` gains `caretOffsets(_:font:) -> [Double]`: the x of every
grapheme boundary of one unwrapped line, `count + 1` values from 0, in the
string's logical order. `CoreTextTextSystem` asks the `CTLine`
(`CTLineGetOffsetForStringIndex`); `PortableTextSystem` sums the shaped
advances of the clusters before each boundary. **The portable answer is
measured against CoreText's** over the portable-text corpora (Latin, and the
fallback corpus), as every earlier portable-text item was. Bidirectional
carets are out of scope: a right-to-left field edits in logical order and
its caret positions are the logical ones.

### TI-F — What is tested, and what is a human look

Tested: every row of TI-D against the pure engine; the Window routing with a
fake platform window (focus on click, caret on click, drag, text to the
focused field only, `Keymap` precedence, `setTextInputArea` after a frame,
clipboard round trip, disabled fields ignore everything); the AppKit host
view's `NSTextInputClient` answers with real `NSEvent`s and a scripted input
context where one can be driven; SDL's text and editing events through its
own queue; the caret-offset oracle. **A real input method's candidate
window, dead keys on a real layout and the system clipboard across apps are
human looks.**

## Not in scope

Multi-line editing (`TextEditor`), undo, secure entry, formatters, spelling,
drag and drop of text, bidirectional caret movement, and a blinking caret.
