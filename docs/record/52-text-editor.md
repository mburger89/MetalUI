# 52 — `TextEditor`: multi-line editing, 2026-09-23

Branch `feat/text-editor`, from `master` `6e01d9e`. Written as §48 and
renumbered 48→52 when it met `master` at `8095fd9`: stages 7a, 7b, 8 and 9
had published §48–§51 (record §51's header). Ruling `TI-H`, added to
`docs/superpowers/specs/2026-09-23-text-input-design.md` (next `TI-I`). A
follow-up to roadmap item 14 (record §45) and to undo (record §47).

## What changed

- `TextSystem.lineRanges(_:font:wrappingAt:)`: CoreText's `CTLine` string
  ranges from the shaping cache, and the portable `PortableText.lines` ranges.
- `TextLineModel` (`TextEditing.swift`) holds the display lines in graphemes,
  with the caret offsets of each line.
- `TextEditing.key` gains `lines:`, with up and down on a remembered column
  (`goalX`), the display-line keys, return inserting `\n`, and ⌘delete to the
  line's start. `insert` gains `multiline:`, and line breaks are normalized.
- `TextEditState` gains `goalX`, `scrollY` and `revealsCaret`.
- `TextInputTarget` gains `lines`, `originY`, `lineHeight`, `maxScrollY` and a
  point-based `boundary(atWindowX:y:)`.
- `Window.applyScroll` routes the wheel over an editor to its `scrollY`.
- `TextEditor` itself, a new lowering site (`textEditor`), and the
  `.textArea` role (AppKit `.textArea`, AccessKit `MULTILINE_TEXT_INPUT`).
- The text-input demo (`METALUI_TEXT_INPUT_DEMO=1`) gains a 160-point editor.

## Measured

- **Both systems give the same line ranges through the seam.** Six strings ×
  four widths all agree, hard breaks and an empty string included
  (`bothSystemsBreakLinesAtTheSameRanges`). This rests on the line-breaking
  oracle's 13,464 cases.
- **A zero-width wrap trapped on the first run.** The placeholder was wrapped
  at the editor's width, which is 0 in the diagnostics harness, and hit
  `Shaper.shape`'s positive-width precondition. It is now clamped to
  `smallestWrapWidth`, as every other wrap in the editor is.
- **Up past the first line** first kept the column, so the next down landed
  at the old column rather than at 0. It now forgets the column, as AppKit
  does (`upAndDownKeepTheirColumnAcrossAShortLine`).
- **Written against both engines, merged against one.** On `6e01d9e` the
  editor also had a CSS-engine layout path, and a test ran both. Stage 9
  deleted that engine before this branch met `master`, so the merge drops the
  path. The two-engine test became
  `anEditorTakesTheOfferedSizeAndItsContentHeightWhenOfferedNone`: greedy
  200 × 200 in a 200-point window, lines from the top, and three lines' height
  as a vertical `ScrollView`'s content.
- **Linux aarch64:** the root's portable suites read 6 + 486 + 3 + 22 and
  `Backends/SDL` reads 21 + 18.

## Counts

Taken after the merge with `master` `8095fd9` (stage 9 and PR #30): 1423
tests, 0 goldens, 79 guards; 0 `error:` and 0 new `warning:` on both build
systems after `swift package clean` (`Test run with 1423 tests in 3 suites
passed`; the guards ran). **1423 = 1411 + 12**:
- `TextEditingTests` +4;
- `TextEditorTests` +7;
- `TextSystemSeamTests` +1.

Before the merge the branch read 1770 = 1758 + 12. Its 1758 was the
pre-stage-9 master's count, and stage 9 retired tests on the way to 1411.
`Backends/SDL` is unchanged at 21 + 19, with two role expectations added to
an existing test.

## Mutations (`--filter TextEditorTests|TextEditingTests|TextFieldTests|bothSystemsBreakLines`)

| # | Mutant | Reddens |
|---|---|---|
| H1 | a wrap boundary stays on its own line | `aLineModelPutsAWrapBoundaryOnTheNextLineAndAHardBreakOnItsOwn` |
| H2 | no remembered column | `upAndDownKeepTheirColumnAcrossAShortLine` |
| H3 | a wrapped line's visible end is its full range | `aLineModelPuts…` |
| H4 | return does not insert a break | `lineKeysWorkOnTheDisplayLine`, `returnStartsANewLineAndTheCaretMovesDownALine` |
| H5 | a paste flattens its breaks in an editor | `aMultiLineFieldKeepsLineBreaksAndASingleLineOneFlattensThem` |
| H6 | the wheel is ignored by editors | `theWheelScrollsAndTypingScrollsTheCaretBackIntoView` |
| H7 | the caret is never revealed | `theWheelScrolls…` |
| H8 | a wheel scroll is snapped back to the caret | **green at first**: the frame after an edit had already cleared the reveal. A wheel with no frame after the edit now reddens `theWheelScrolls…` |
| H9 | a final break opens no empty line | **green at first**: text was typed on the new line before anything was checked. Checking the caret on the empty line first now reddens `returnStartsANewLine…` |
| H10 | a press ignores y | `aPressOnALaterLinePlacesTheCaretThere`, `anEditorPaintsEachLineAndTheCaretOnItsLine` |
| H11 | CoreText's `lineRanges` ignores the width | `bothSystemsBreakLinesAtTheSameRanges`, `longTextWrapsAtTheEditorsWidth` |

## Open

- **A human look:** the demo's editor with typing, return, up and down across
  wrapped lines, the wheel, a drag selection across lines, and an input
  method on a later line.
- **Not built:**
  - page up and page down;
  - option-up/down by paragraph;
  - auto-scroll while dragging a selection past the edge;
  - a scroll indicator;
  - Tab inserting a tab (it moves on, as it does in `TextField`);
  - bidirectional carets, secure entry.
