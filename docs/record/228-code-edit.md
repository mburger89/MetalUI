# Record 228: editing in the code view (Alloy gap G1, PR 3)

PR 3 of Alloy gap G1 on branch `feat/code-edit` (master `640237c6`, which has `MetalUICodeBuffer`, record 225, and the read-only `CodeView`, record 227). **Run 1** built the window's session seam, the keys, the clipboard, the undo keys, Tab and indentation, the caret and the mouse through the session. **Run 2** added the input method's marked text, the caret blink, drag-select autoscroll and the gutter-bar click and context menu (Alloy's addendum item 4, as Alloy shaped it), and finalized this record. Find painting is PR 4. Class `M`: no divergence added or retired. Rulings `CV-W`..`CV-AD` in `docs/superpowers/2026-11-07-code-view-decisions.md` (next `CV-AE`).

## 1. What was built

- **The seam (`CV-W`).** `TextInputTarget`'s `submitBox` and `sinkBox` became one class box, `TextTargetHooks { submit, sink, code }`; `TextInputTarget(code:caretRect:)` is a target with no string whose `codeSession` is the `CodeEditSession` that `CodeView.prepaint` builds over the frame's `CodeViewPlan`. `Window` branches early on `codeSession` in `dispatchTextInput` (`.mouseDown`, `.mouseDragged`, `.textInput`, `.textComposition`), `dispatchTextKey`, `dispatchTypedKeyPress`, `dispatchFocusTraversal`, `focusedElement.didSet` and `testingComposition`. No `dispatchScrollChain` arm (the view's wheel is the pointer attachment's, `target.lines` is nil). Edits go to the live buffer in input under `StateDispatch.dispatching(to:)`.
- **Keys (`CV-X`).** `CodeEditing.command(for:platform:)`, a pure table to `CodeCommand`; `CodeEditSession` runs them. Motions by grapheme, word, smart line start, line end, document ends, page, with `goalX`; deletes by grapheme, break, word, to line start; Return with the buffer's line ending and indent; Tab, Shift-Tab with spaces or tabs; copy, cut (whole line when nothing is selected), paste (line-ending-normalized), select all, undo, redo. `codeViewEditable(_:)` (default on) and `indentUsingSpaces(_:)`, `CodeTheme.caret`.
- **Caret and reveal.** A one-point bar at the head while focused with an empty selection; every key that moves or edits sets `CodeViewState.revealsCaret` from input, and `makePlan` scrolls the least that shows the caret (three advances of horizontal margin), as a compared write that clears the flag.
- **Mouse (`CV-Y`).** Press, shift-press, double (word), triple and gutter (line), drag by the press's unit, all through the session; the `DragGesture` of record 227 is gone.
- **Control-Tab (`CV-W`).** `dispatchFocusTraversal` lets Control through when the focused element is a code view.
- **Marked text (`CV-AA`, run 2).** `CodeViewState.composition` (+ `compositionOffset`, `compositionVersion`); `CodeEditSession.compose`/`dropComposition`/`isComposing`/`composition`; the typed-key-press stage asks the session; `focusedElement.didSet` drops it; `testingComposition` reads it. Marked text never enters the buffer or its edit stream until `insert` commits it. Only the composing row is laid out with the marked text inserted (`Row.marked`, `layoutByte`), underlined, the selected clause doubly; the caret rect (the input method's area) follows the clause.
- **Gutter bars (`CV-AB`, run 2, Alloy's shape).** `tag: UInt64?` on `CodeLineDecoration` and `CodeVirtualRow`; `CodeGutterHit { lines, tag, source, displayRow }`; `onGutterBarClick(_:)` and `gutterBarContextMenu(_:)` (a `@MenuContentBuilder` closure of the hit, through `Handlers.contextual`). Virtual rows' bars hit. `onGutterBarHover` is not built.
- **Blink (`CV-AC`, run 2).** `codeCaretBlink(_:)` (`CodeCaretBlink`); visible is a function of `frame.timestamp` and a stored epoch, read in paint; the frames are `TimelineStore.noteDeadline(atTimestamp:owner:stateTable:)`, a package extension feeding the store's one wake.
- **Autoscroll (`CV-AD`, run 2).** Input stores `CodeViewState.autoscroll`; `makePlan` evaluates the scroll and the head under the pointer from the frame time; `.mouseUp` folds the selection into the buffer.

## 2. Deviations from the plan

- **The plan's Control-Tab claim was wrong against the source.** The plan said a Tab with Control or Command "is not consumed, so focus can still leave" through the traversal stage; that stage returns for any Control, Command or Option, so an editable view would have been a focus trap. The stage now exempts Control for a focused code view (`CV-W`).
- **`Handlers` shrank to 480.** The plan wanted 488 kept; merging two boxes frees a pointer. `handlersGainsOneReferenceMember` is `== 480` and says why.
- **The hit test took the wrong coordinates for a view not at the window's origin** (a record 227 bug): `CodeViewPlan.offset(at:)` added the view's origin to a window point. Fixed (`CV-Y`); found by the new stage test, whose view sits below a box.
- **Page keys move the caret** on every platform (the plan: "move the caret and the scroll"); a Mac text view only scrolls, so `TextEditing`'s table is not reused for them.
- **Home/End are the smart line keys on every platform**, not document scrolls on a Mac.
- **`codeViewEditable` is on by default** (the plan's `false` opts out). The demo (`METALUI_CODE_DEMO=1`) and existing views are therefore editable now; a read-only use says `codeViewEditable(false)`.
- **The state-site classification scan is recursive** (`everyStateWriteSiteIsClassified`): `Sources/MetalUI/Code/` was never in it. Rows added for `Code/CodeView.swift`, `Code/CodeEditSession.swift`, `Code/CodeViewPlan.swift`.
- **Whole-line paste at the line start is not done** (VS Code pastes a copied whole line above the caret's line); a paste is a paste.
- **Run 2 deviations from the plan.** (a) *Autoscroll's selection*: the plan has every phase compute the head from the timestamp and the next move or release fold it; the head is computed in `makePlan` and drawn (`plan.selection`), and the buffer's selection is folded by the next drag event and the `.mouseUp` arm (which claims nothing). A mutation that writes the autoscroll base in prepaint is **equivalent** (the derived state already goes through the one compared write); the pin is the `everyStateWriteSiteIsClassified` row (no new `withState`) plus the rest-at-the-limit test (no frame, no write). (b) *Blink epoch*: the plan reads "last caret move" from input; it is stored by `makePlan`'s compared write when the selection, head, `version`, marked text or focus differs from what it last saw, so every source of a caret move restarts it with no input hook. (c) *`noteDeadline` takes the `StateTable`*: a wake writes through it, and a timeline's build hands it in; without it the first version of the test saw no wake at all. (d) *Marked text reveals the caret* (`revealsCaret`), so a test that scrolled the view away from the caret and then composed saw it jump back; the stage test now puts the caret in view first. (e) *The hit region of a bar* is its column widened four points towards the numbers (the plan did not say). (f) *The press that ends a composition* is the view's (a `TextField`'s precedent). (g) *Not built*: `onGutterBarHover` (optional in Alloy's reply; it needs a pointer-move hook in the text stage), the demo's read-only flag (the demo stays editable, the default), marked text on a line over 4 KB (it still commits), and a wheel during an autoscroll is ignored.

## 3. Numbers

Harness window 400 x 200 at 1x, Noto Sans 12 (pitch 17), macOS arm64 debug, `RopeStats.nodesVisited`.

| Measure | 1k lines | 100k lines |
| --- | --- | --- |
| Lines shaped by one keystroke | 1 | 1 |
| Layout measure calls / layout-memo misses by it | 0 / 0 | 0 / 0 |
| Rope nodes visited in the whole keystroke frame | 152 | 304 |
| Rope nodes visited in an idle frame | 132 | 264 |
| **Rope nodes the keystroke added** | **20** | **40** |
| Allocations, one warm 1 px scroll frame, top (focused, caret drawn) | 845 | 845 |

Run 2, same harness (`CodeViewImeBlinkTests`; the clock is the harness's simulated one):

| Measure | Value |
| --- | --- |
| Lines shaped on the frame that shows a composition / the next, still frame | 1 / 0 |
| `version` while a composition is set, grown and re-selected | unchanged; +1 at the commit (a second commit of the marked text: +1) |
| Frames drawn by a focused, idle view with the blink on, in 2 s (8 ticks of 0.25 s) | 4 (2 a second) |
| `hasActiveAnimations` after each of them (`noteActiveAnimation` calls) | false (0) |
| Frames drawn by `.codeCaretBlink(.off)` in the same 2 s | 0 |
| Caret bars drawn at 0.25 s steps from a restart | 1, 0, 0, 1, 1, 0, 0, 1 |
| Autoscroll, a drag held 20 points below a 200-point view: scroll after 1 s at 60 and at 4 frames a second | equal to within one row (`60 + 20 d` = 460 points a second, about 27 rows) |
| Autoscroll at the end of a 30-line file: frames drawn in 1 s of held pointer / writes | 0 / none (`hasActiveAnimations` false) |
| Gutter hits | a decoration bar: its whole `10..<20` (`10..<21` after a line is inserted inside), tag 7; a virtual row: `5..<6`, tag 9, display rows 5 and 6 |

The idle frame's count is the visible rows' lookups (twice the depth at 100k); the pin subtracts it, bounds the difference at 40 and the extra at 200. `Handlers`: 480 bytes (was 488).

## 4. Pins that moved

| Pin | Before | After | Cause |
| --- | --- | --- | --- |
| `handlersGainsOneReferenceMember` | `== 488` | `== 480` | two boxes merged into one (`CV-W`) |
| `aWarmScrollFrameAllocatesTheSameAt1kAnd100kLinesAndAtAnyPosition` ceiling | 830 | 910 | the focused view now draws a caret: one more primitive, 81 allocations in `Scene.finalize`'s debug sort (764 to 845); the 1k-against-100k bound is unchanged |
| `everyStateWriteSiteIsClassified` | top-level files only | recursive, three `Code/` rows | the `Code/` sources were never scanned |
| `everyStateWriteSiteIsClassified`, `Code/CodeViewPlan.swift` reads | 1 | 2 | the blink's epoch is read in paint (`CV-AC`); no `withState` was added (run 2) |
| `aCodeTargetReachesEveryTextStage` | marked text asserted absent from `testingComposition`; caret at the top while scrolled | asserted present; caret placed in view | marked text is drawn and reveals a caret that is out of view (`CV-AA`) |
| `handlersGainsOneReferenceMember` | `== 480` | `== 480` | unchanged: the session grew, the hooks box did not |

## 5. Mutations

Each applied alone to the committed tree in place and restored with `git checkout` (script and log in the session scratchpad); the editing tests, `CodeViewTests`, `CodeViewVirtualRowsTests` and the key table per mutation.

| Mutation | Reddened |
| --- | --- |
| `.textInput` early branch removed | `aCodeTargetReachesEveryTextStage`, `typingEditsTheBufferAndTheCaretFollows`, `undoAndRedoKeysRestoreTheSelections`, `aKeystrokeShapesOneLineAndVisitsLogarithmicNodes` |
| `.mouseDown` early branch removed | `aCodeTargetReachesEveryTextStage`, `doubleClickSelectsAWordAndAGutterPressALine`, `linesInsertedAboveKeepTheTopRowInPlace` and 8 more of the PR 2 tests that press the view |
| `.mouseDragged` early branch removed | `aCodeTargetReachesEveryTextStage`, `draggingSelectsAndCopyWritesTheSelection` |
| `.textComposition` early branch removed | first spelling green (the `TextEditState` write was invisible); after the scroll-picture arms, `aCodeTargetReachesEveryTextStage` |
| `dispatchTextKey` early branch removed | 18 tests (every key test) |
| `dispatchFocusTraversal` selecting all for a code target | first green; after the picture arm, `aCodeTargetReachesEveryTextStage` |
| `focusedElement.didSet` branch removed | first green (the scroll state heals through `CodeScrollState`); after the picture arm, `aCodeTargetReachesEveryTextStage` |
| Control exemption of the traversal removed | `tabbingIntoACodeViewDoesNotSelectAllAndControlTabLeaves` |
| the typed-key-press composition arm removed | **green in run 1 (equivalent until a view composes); red in run 2**: `aCommittedCharacterOfAnInputMethodIsNotOfferedToOnKeyPress` (table below) |
| keystroke reads `snapshot().text` | `aKeystrokeShapesOneLineAndVisitsLogarithmicNodes` |
| select-all reveals the caret | first green (the test read the first selection rect, which starts at 0 wherever the view is); `selectAllStaysPutAndUndoAndTypingRevealTheCaret` after |
| `goalX` dropped | `verticalMotionRemembersItsColumn` |
| Home always to column 0 | `smartHomeAndTheLineAndDocumentEnds` |
| Return inserts a fixed LF | `returnKeepsTheLineEndingAndTheIndentation` |
| paste not normalized | `pasteNormalizesLineEndingsToTheBuffers` |
| empty selection copies nothing | `copyAndCutTakeTheWholeLineWhenNothingIsSelected` |
| right arrow steps one byte | `arrowsMoveByGraphemeAndAcrossBreaks` |
| hit test adds the origin twice | `aCodeTargetReachesEveryTextStage` |
| view flag ignored / buffer read-only ignored | `aReadOnlyViewSelectsAndCopiesButDoesNotEdit` |
| caret reveal never scrolls | `pageKeysMoveTheCaretAndTheView` |
| outdent removes two tab widths | first green (the fixture had two spaces); after a six-space line, `tabIndentsAndShiftTabOutdents` |
| tab-with-spaces inserts a fixed width | `tabWithSpacesPadsToTheNextStop` |
| word and shortcut modifiers swapped | `theMacKeyTable` and 5 more |
| backspace removes one scalar | `deleteKeysRemoveGraphemesBreaksWordsAndSelections` |
| backspace not coalesced | `deleteKeysRemoveGraphemesBreaksWordsAndSelections` |
| undo does not reveal; typing does not reveal | `selectAllStaysPutAndUndoAndTypingRevealTheCaret` |
| a member beside the hooks box | `handlersGainsOneReferenceMember` |

Run 2 mutations (same method; script `mutate.py` and `log.txt` in the session scratchpad; the filter is the editing, blink and view tests plus the two pins):

| Mutation | Reddened |
| --- | --- |
| commit inserts the composition and then the committed text | `markedTextIsDrawnAtTheCaretAndNeverReachesTheBufferUntilItIsCommitted`, `cancellingACompositionChangesNothingAndACommitReplacesTheSelection`, `aCommittedCharacterOfAnInputMethodIsNotOfferedToOnKeyPress`, `aCompositionEndsWithFocusAndAPressAndFollowsAnEditAbove`, `aCodeTargetReachesEveryTextStage` |
| the composition written into the buffer by `compose` | the same five |
| the typed-key-press arm answers `true` for a code target (the run 1 green mutant) | `aCommittedCharacterOfAnInputMethodIsNotOfferedToOnKeyPress` |
| `focusedElement.didSet` not dropping the composition | first green (the later click was a press, which also ends it); after the test re-enters by Shift-Tab, `aCompositionEndsWithFocusAndAPressAndFollowsAnEditAbove` |
| the composition not mapped through an edit above | `aCompositionEndsWithFocusAndAPressAndFollowsAnEditAbove` |
| the hit test not removing the marked bytes | first green (no test pressed on marked text); after `aPressAfterMarkedTextResolvesToTheBufferOffset`, that test |
| cancel (an empty composition) commits the marked text | `cancellingACompositionChangesNothingAndACommitReplacesTheSelection` |
| the blink calling `noteActiveAnimation()` | `theCaretBlinksTwiceASecondFromTheOneWakeAndNeverKeepsTheLinkRunning` |
| the timeline store ignoring a deadline | that test and `typingRestartsTheBlinkAndOffIsSolidAndFree` |
| the epoch never restarting | `typingRestartsTheBlinkAndOffIsSolidAndFree` |
| autoscroll as a step per frame, not a function of the timestamp | `aDragHeldBelowTheViewScrollsByTheFrameTimeAndSelectsAlong` |
| autoscroll noting an animation at the limit | `anAutoscrollAtTheLimitRestsAndTheViewStopsWhenThePointerReturns` |
| `.mouseUp` not folding the autoscroll's selection | `aDragHeldBelowTheViewScrollsByTheFrameTimeAndSelectsAlong` |
| the gutter hit test skipping virtual rows | `aPressOnAGutterBarReportsItsHitAndABarlessGutterRowKeepsLineSelect`, `aContextMenuOnAGutterBarPresentsTheItemsOfItsHit` |
| a bar press also selecting the line | `aPressOnAGutterBarReportsItsHitAndABarlessGutterRowKeepsLineSelect` |
| the menu built from the first row's hit, not the pressed one | `aContextMenuOnAGutterBarPresentsTheItemsOfItsHit` |

Equivalent, not applied as a mutation: writing the autoscroll base from prepaint (see section 2, run 2 deviation (a)).

## 6. Verification (macOS 27.2 arm64, `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`, head after the commit that carries this record)

- `swift package clean`, `swift build --build-system native --build-tests`, `swift test --build-system native --no-parallel`, unfiltered: `✔ Test run with 5525 tests in 18 suites passed after 336.349 seconds.` and `FR-J no-argument frame: succeeded=true deprecations=2`. This branch adds 11 tests (`CodeViewImeBlinkTests`) and no guard.
- The same unfiltered run under `METALUI_VERIFY_RETAINED=1 METALUI_VERIFY_CODE_CACHE=1`: `✔ Test run with 5525 tests in 18 suites passed after 311.785 seconds.` (a focused, blinking code view taints retention and so is never replayed; the unfocused one replays and passes).
- Portable Docker, `metalui-portable:latest` fed by `git archive` of the head with the code (`swift build --build-tests` 42.2 s, then `swift test --skip-build --no-parallel`): `✔ Test run with 902 tests in 10 suites passed after 99.406 seconds.` (`MetalUITestingTests`; 9, 16, 73, 68, 53, 286, 154, 24 and 45 in the others). The container ran with `--rm`; no volume, archive or image was left.
- `zsh docs/probes/closeout-inventory-check.sh` and `zsh docs/probes/closeout-undocumented.sh` print nothing.
- **Not run:** the human checks `CV1`..`CV16` (an agent cannot: IME candidate placement, blink feel, autoscroll feel, bar click targets), Linux SDL and Windows (the portable harness stands in for them), a release build, and the benchmark recipe of plan section 11 (typing latency with a real CGEvent stream).
