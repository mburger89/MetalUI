# `TextField(axis: .vertical)` and `lineLimit` ranges - decisions (prefix `VT-`)

Alloy gap G18. Branch `feat/vertical-text-field` (master `12ca12d4`), record 255. Probe `docs/probes/swiftui-vertical-text-field.swift` (arms S, E, F, R, W, K, P; recorded 2026-11-09, macOS 27.2, Swift 6.4.2, run twice byte-identical). Class `A` (SwiftUI-aligned); divergences 232-238 (see `VT-G`). **Next unused id: `VT-I`.** Out of scope, and carried to later PRs: the placeholder colour, `prompt:`, the `TabStrip` ink.

An Alloy chat composer is a text field that is one line tall when empty, grows with what is typed up to eight lines, and then scrolls inside itself while Return sends the message. SwiftUI spells it `TextField("Message", text: $draft, axis: .vertical).lineLimit(1...8)`.

## VT-A: API, and one geometry for the editor and the field

`TextField` gains an `axis: Axis` (default `.horizontal`, internal) and four initialisers: the controlled `init(_:text:axis:onChange:)`, `init(_:text:axis:)` over a `Binding<String>`, and `axis:` on the `selection:` (macOS 15) and `selectedOffsets:` spellings. The existing initialisers are untouched (no defaulted parameter was added, so no public signature moved). `prompt:` does not exist on `TextField` yet and is not added here. A vertical field is the same `TextField` type, the same element, the same environment and the same role (`.textField`).

`TextEditor`'s geometry and its line-by-line paint loop moved, unchanged, into `MultilineText.geometry(...)` and `MultilineText.paintLines(...)` (`Sources/MetalUI/MultilineText.swift`), so the two draw, scroll and aim a press identically. **`TextEditor`'s scene is byte-identical**: three texts (empty, short, 30 lines) each unfocused, focused, selected, scrolled to the end and composing, 11 scenes, were dumped before and after (md5 `a18b8c05e0402643028881fa3d4db995`, identical), and `aTextEditorDrawsItsLinesAndCaretWhereItAlwaysDid` pins the line and selection geometry.

## VT-B: the height is one pure function

`VerticalFieldMetrics.height(displayLines:lineHeight:verticalInset:limit:proposal:)` (probe S):

- `n` is the display lines of the text wrapped at `width - 2h` (unwrapped when the width proposal is nil or infinite), one more after a trailing line break, and the **placeholder's** lines while the text is empty; counted with the same `lineRanges` call `TextEditor` wraps with.
- `shown = min(max(n, lower ?? 1), upper ?? infinity)`; a bound under 1 reads as 1 (`lineLimit(0)` is 1).
- `content = shown * lh + 2v` (`v` is 4 bordered, 0 plain; 16 per line at 13 pt, so 24/56/136 for 1/3/8).
- A nil or infinite height proposal is answered with `content` (it hugs). Any other is answered `max(floor, min(p, content))`, **exactly, not snapped to whole lines** (100, 80 and 70 are answered 100, 80 and 70), where `floor` is the **lower bound's** height and **0 without a lower bound** (`1...8` at proposal 10 is 24, `2...8` is 40, `3...` is 56, no limit or `lineLimit(8)` or `...8` is 10 and 0 at 0).
- `lineLimit(3, reservesSpace: true)` is `3...3` and so is always 56; `lineLimit(8)` alone caps like `1...8` with no floor.
- The width follows the existing `TextField` rule (`PE-D`): greedy, infinity answered with infinity, nil asks the text or placeholder plus the chrome.
- A horizontal field is always 24 and ignores `lineLimit` (probe S, last row).

The measure closure reads `ownLineLimit ?? environment.textLineLimit`; the leaf stays unkeyed (a `TextField` always was), so it makes its ancestors unmatchable for the layout memo as before. `TextEditor` ignores `lineLimit` entirely in SwiftUI (probe E), and MetalUI's does too: do not make it honour one.

## VT-C: `lineLimit` on the field

The five `lineLimit` spellings are also written on `TextField` itself and return a `TextField` (as `textFieldStyle(_:)` does, `MD-B` item 2), so `.lineLimit(1...8).onSubmit {}` and `.onSubmit {}.lineLimit(1...8)` both compile. The field's own value wins over a container's (`ownLineLimit ?? environment`), and a container's `.lineLimit` reaches the field (probe S, `container lineLimit(1...2) @5` is 40). The environment key `textLineLimit` is unchanged.

## VT-D: geometry, paint, scroll

- The text is laid out in `FieldChrome.contentRect(bounds, insets)`: line 0's top is at `y + v`, the viewport is `bounds - 2v` (128 at 8 lines bordered), `maxScrollY = lines * lh - viewport`. The target carries `lines`, `originY`, `lineHeight` and `maxScrollY` exactly as `TextEditor`'s, which gives the line keys, the page keys (`TI-I`) and a press for free; its `TextLineModel.visibleHeight` is the viewport.
- Clipped across to the content width and down to the bounds inset by 2 points (`min(2, v)`, so a plain field clips to its bounds), the clip AppKit's field editor sits in (probe R: 128 tall, 132 when overflowing). **No scroll indicator** (probe R, `scrollers=0`).
- The caret reveal and the clamp are written back in prepaint with the **compared** `withState(_:initial:unchanged:)` (`RW-J`), only while focused, so an unfocused field writes nothing and replays (`RW-` eligible); shrinking text re-clamps in the same write. The state is `TextEditState.scrollY` / `revealsCaret`, reused.
- **Unfocused, the field draws from the top** (`MultilineText.geometry(focused: false)` reads the scroll as 0, reveals nothing, and nothing is stored): probe R `unfocused` has no clip view, the label draws from line 0. The stored scroll is kept for the next focus (human check VT2). The press target is aimed at what is drawn, so a click on an unfocused field lands on the line it shows.
- `followExternalText` (`SL-P`) is unchanged: a text replaced from code moves the caret to the end of a focused field with no selection binding and **reveals it** (SwiftUI moves the caret without scrolling, probe R). A divergence (235).
- The `Handlers` pin (480 bytes) is kept by putting the vertical marker in `TextTargetHooks` (`vertical`), not in `TextLineModel` or `TextInputTarget` (a `Bool` there moved it).
- `everyStateWriteSiteIsClassified`: `TextField.swift` gains one compared write and one `readState` (1, 2, 3, 0); `Window.swift` gains the wheel arm's plain write (6). No new leaf key, no journal event beyond the compared write's.

## VT-E: the wheel

`Window.dispatchScrollChain` keeps its `TI-H` arm for `TextEditor` (it swallows the vertical wheel at its cover, with room or not, focused or not). For a **vertical field only**, the arm takes the wheel when the event is vertical, the field is the focused element and has room in the wheel's direction (`scrollY < maxScrollY` growing, `scrollY > 0` otherwise); otherwise the wheel **continues up the chain** (`XS-F`'s one-axis rule), where an outer `ScrollView` takes it. Probe W showed a focused field scrolling under a direct AppKit call; the window routing and the focus gate are not measured (assumptions, human check VT1; divergence 236).

## VT-F: the keys

`TextEditing.key` takes a `KeyMode` (`.singleLine`, `.editor`, `.verticalField`) instead of inferring multi-line from `lines != nil`; `nil` keeps the old inference, so no existing caller moved. `Window.dispatchTextKey` passes `.singleLine` without `lines`, `.verticalField` for a target whose hooks say so, `.editor` otherwise.

On a Mac, in a vertical field (probe K):

| Key | Behaviour |
|---|---|
| Return, ⇧Return, Enter (`\u{3}`) | `onSubmit` once, nothing inserted. **Unclaimed and bubbling without an `onSubmit`.** |
| ⌥Return | inserts `\n` as a `.typing` edit with reveal |
| ⌃Return | inserts `\n` (SwiftUI inserts U+2028: divergence 232) |
| ⌘Return | unclaimed (`KF-Z`) |

Off a Mac (class `M`, MetalUI's own): Alt+Enter inserts a line break, Ctrl+Enter is the shortcut modifier and passes on, Shift+Enter submits. A paste and an input method's commit keep their newlines in a vertical field (`lineBreaksNormalized` for every mode but `.singleLine`). `TextEditor` keeps inserting on Return, ⇧Return, Enter and ⌥Return and passing ⌘Return on.

**Not built:** SwiftUI also selects all text after a submit (divergence 233). **Found, not fixed:** the one-line `TextField` submits on ⌥Return and ⌘Return; SwiftUI's inserts a line break on ⌥Return and ignores ⌘Return (divergence 234); changing it moves every existing horizontal field and is its own follow-up.

## VT-G: divergences and the carried finding

232 ⌃Return inserts a line break, not U+2028. 233 No select-all after submit. 234 The one-line `TextField` submits on ⌥Return and ⌘Return. 235 A text replaced from code reveals the caret in a vertical field. 236 Assumptions with no measurement: window wheel routing and its focus gate, the stored scroll of an unfocused field, the 2-point overflow clip (human checks VT1-VT3). 237 `.controlSize(.small)` at 3 lines: see the record for MetalUI's measured number against SwiftUI's 50. 238 **Finding K, measured by probe F and not fixed here:** a flexible `.frame(minHeight:maxHeight:)` under `.fixedSize(vertical:)`; recorded as `SA-N` item 10.

## VT-H: carried

The placeholder colour (`NSColor.placeholderTextColor` is `secondaryLabelColor`: black at 0.498 / white at 0.549, and a `prompt:` `Text`'s colour is honoured while the field's `foregroundStyle` is not, probe P), `prompt:`, the `TabStrip` ink, kernel finding K, the horizontal field's ⌥Return / ⌘Return, a select-all after submit and the autoscroll of a selection drag past a vertical field's edge are for later PRs. Human checks `VT1`-`VT6`.
