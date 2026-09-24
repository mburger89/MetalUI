# 47 — `TextField` undo and redo, 2026-09-23

Branch `feat/text-undo`, from `master` `78862c9`. Ruling `TI-G`, added to
`docs/superpowers/specs/2026-09-23-text-input-design.md` (next `TI-H`). A
follow-up to roadmap item 14 (record §45), which left undo out of scope.

## What changed

- `TextEditHistory` in `TextEditState`: undo and redo stacks of
  `(text, anchor, head)` snapshots, 100 deep, plus the open group's kind and
  the text the last edit produced.
- `TextEditing`: every text-changing path records (`recording(_:from:_:to:_:)`).
  Undo and redo are keys: ⌘Z / ⌘⇧Z on a Mac, ctrl-Z / ctrl-Y / ctrl-shift-Z
  elsewhere. Caret moves, presses, drags and select-all close the open group.
  An event whose text is not what the history last produced drops the history
  (`synced(_:with:)`).
- No `Window` change: undo's text reaches the caller through `onChange`, like
  any edit, and `editedText` composes it with the edits around it.

## Counts

1758 tests, 97 goldens, 78 guards; 0 `error:` and 0 `warning:` on both build
systems after `swift package clean` (`Test run with 1758 tests in 3 suites
passed`; the guards ran). 1758 = 1752 + 6 (`TextEditingTests` +5,
`TextFieldTests` +1). The first clean build carried one warning (an unused
ternary in a test helper), fixed before this count stood.

## Mutations (`--filter TextEditingTests|TextFieldTests`)

| # | Mutant | Reddens |
|---|---|---|
| U1 | never coalesce | `typingIsOneUndoGroupAndRedoRestoresIt`, `caretMotionAndEditKindsSplitGroups`, `undoAndRedoReachTheCallerThroughOnChange` |
| U2 | a caret move keeps the group open | `caretMotionAndEditKindsSplitGroups`, `undoIsBoundedAndKeyedPerPlatform` |
| U3 | an edit does not clear redo | `typingIsOneUndoGroupAndRedoRestoresIt` |
| U4 | an external change keeps the history | `anExternalChangeDropsTheHistory` |
| U5 | no depth cap | `undoIsBoundedAndKeyedPerPlatform` |
| U6 | ⌘Y redoes on a Mac too | **green at first** — the test pressed ctrl-Y on a Mac, which never reaches the shortcut branch; with ⌘Y it reddens `undoIsBoundedAndKeyedPerPlatform` |
| U7 | undo restores the text but not the selection | three tests, `cutPasteAndReplacingASelectionUndoOneAtATime` among them |
| U8 | typing over a selection continues the open group | **green at first** — no typing group was open; a case that types, selects and types reddens `cutPasteAndReplacingASelectionUndoOneAtATime` |

## Open

- A human look: undo and redo in `METALUI_TEXT_INPUT_DEMO=1`, including after
  an input method's commit.
- Not built: the Edit menu's Undo item on macOS (MetalUI has no menus), and
  coalescing by time or by word, as AppKit does. Groups here end only on a
  kind change or a caret move.
