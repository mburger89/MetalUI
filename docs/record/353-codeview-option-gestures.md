# 353: the ⌥-click caret toggle and ⌥-drag column selection (`CV-BK`)

Branch `feat/codeview-option-gestures` from master e349cd74. Class M, no divergence. Alloy gap G4, design PR 6 of the editor-essentials plan; Alloy's answers 7 (keep ⌥/Alt on Linux and Windows, no substitute) and 10 (⌥-drag replaces every selection) are binding.

## What changed
- `CodeEditing.caretToggleModifier = .option`.
- `CodeEditSession.press`: after the `onTextClick` and gutter-bar checks, a press holding ⌥ off the line-number gutter records a pending toggle in `CodeViewState` (`optionMode`, `optionOffset`, `optionRow`, `optionX`) and changes nothing. `drag` turns it into a column selection once the pointer's nearest boundary or buffer row differs from the press's; `endDrag` toggles (pending) or commits the live column (autoscroll). A plain press resets the mode.
- `CodeViewPlan`: `rowIndex(at:)` (factored out of `hit`), `textX(of:)`, `columnRow(at:towards:)`, `columnSelections(...)`, `liveColumnSelections`, and a frame branch that computes the live column while a ⌥ drag autoscrolls.
- `CodeSelectionState.isFoldHidden(line:)` (package) over the registered fold states.

## Decisions worth knowing
- The column is built over buffer rows, so virtual rows are skipped by construction; a row not among the frame's rows (a long autoscrolled column) is placed by monospace columns, since it has no layout to measure.
- At `selectionLimit` the rows nearest the press are dropped, not the pointer's.
- The fold layout (`CV-BM`, another branch) is not in this branch: a pointer that lands on a row a fold hides writes a selection there and so opens that fold, as every explicit selection write does.
- A ⌥ press in the line-number gutter is the ordinary line press.
- An existing test (`aPlainClickStillPlacesTheCaretWithAHandlerSet`) clicked with ⌥ and expected a plain caret; it now expects the added caret.

## Cost
The ⌥ press frame, the release and the following steady frame (two carets) equal a plain click's: 1 request, 0 hits, 1 miss, 0 ineligible, 1 frame, one retained card (off Darwin compared per frame).

## Tests and mutations
`Tests/MetalUITestingTests/CodeViewOptionGestureTests.swift`, 13 tests. Mutations shown red: removing the last-selection guard; `primary: 0` on the added caret; dropping the crossing guard; `primary: 0` on the column; dropping the limit trim; dropping the frame's live column; not clearing the mode on a plain press; ignoring hidden rows; `contains` instead of `==` for the handler's modifiers (also reddens `aShiftPrimaryClickIsNotAPrimaryClick`); dropping the buffer-row to frame-row map (clamping then reads the wrong lines). The cost test is a pin: it goes red when the literals move.
