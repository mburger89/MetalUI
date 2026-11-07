# Record 228: editing in the code view (Alloy gap G1, PR 3) - DRAFT, run 1 of 2

PR 3 of Alloy gap G1 on branch `feat/code-edit` (master `640237c6`, which has `MetalUICodeBuffer`, record 225, and the read-only `CodeView`, record 227). **Run 1** built the window's session seam, the keys, the clipboard, the undo keys, Tab and indentation, the caret and the mouse through the session. **Run 2 (TODO(run 2))** owes IME and marked text, the caret blink wake, drag-select autoscroll, the gutter-bar click and context callbacks (addendum item 4), find painting, and this record's final form (numbers re-taken on the final tree, the divergence note, `docs/api-overview.md`, the guide, `CLAUDE.md`). Class `M`: no divergence added or retired. Rulings `CV-W`..`CV-Z` in `docs/superpowers/2026-11-07-code-view-decisions.md` (next `CV-AA`).

## 1. What was built

- **The seam (`CV-W`).** `TextInputTarget`'s `submitBox` and `sinkBox` became one class box, `TextTargetHooks { submit, sink, code }`; `TextInputTarget(code:caretRect:)` is a target with no string whose `codeSession` is the `CodeEditSession` that `CodeView.prepaint` builds over the frame's `CodeViewPlan`. `Window` branches early on `codeSession` in `dispatchTextInput` (`.mouseDown`, `.mouseDragged`, `.textInput`, `.textComposition`), `dispatchTextKey`, `dispatchTypedKeyPress`, `dispatchFocusTraversal`, `focusedElement.didSet` and `testingComposition`. No `dispatchScrollChain` arm (the view's wheel is the pointer attachment's, `target.lines` is nil). Edits go to the live buffer in input under `StateDispatch.dispatching(to:)`.
- **Keys (`CV-X`).** `CodeEditing.command(for:platform:)`, a pure table to `CodeCommand`; `CodeEditSession` runs them. Motions by grapheme, word, smart line start, line end, document ends, page, with `goalX`; deletes by grapheme, break, word, to line start; Return with the buffer's line ending and indent; Tab, Shift-Tab with spaces or tabs; copy, cut (whole line when nothing is selected), paste (line-ending-normalized), select all, undo, redo. `codeViewEditable(_:)` (default on) and `indentUsingSpaces(_:)`, `CodeTheme.caret`.
- **Caret and reveal.** A one-point bar at the head while focused with an empty selection; every key that moves or edits sets `CodeViewState.revealsCaret` from input, and `makePlan` scrolls the least that shows the caret (three advances of horizontal margin), as a compared write that clears the flag.
- **Mouse (`CV-Y`).** Press, shift-press, double (word), triple and gutter (line), drag by the press's unit, all through the session; the `DragGesture` of record 227 is gone.
- **Control-Tab (`CV-W`).** `dispatchFocusTraversal` lets Control through when the focused element is a code view.

## 2. Deviations from the plan

- **The plan's Control-Tab claim was wrong against the source.** The plan said a Tab with Control or Command "is not consumed, so focus can still leave" through the traversal stage; that stage returns for any Control, Command or Option, so an editable view would have been a focus trap. The stage now exempts Control for a focused code view (`CV-W`).
- **`Handlers` shrank to 480.** The plan wanted 488 kept; merging two boxes frees a pointer. `handlersGainsOneReferenceMember` is `== 480` and says why.
- **The hit test took the wrong coordinates for a view not at the window's origin** (a record 227 bug): `CodeViewPlan.offset(at:)` added the view's origin to a window point. Fixed (`CV-Y`); found by the new stage test, whose view sits below a box.
- **Page keys move the caret** on every platform (the plan: "move the caret and the scroll"); a Mac text view only scrolls, so `TextEditing`'s table is not reused for them.
- **Home/End are the smart line keys on every platform**, not document scrolls on a Mac.
- **`codeViewEditable` is on by default** (the plan's `false` opts out). The demo (`METALUI_CODE_DEMO=1`) and existing views are therefore editable now; a read-only use says `codeViewEditable(false)`.
- **The state-site classification scan is recursive** (`everyStateWriteSiteIsClassified`): `Sources/MetalUI/Code/` was never in it. Rows added for `Code/CodeView.swift`, `Code/CodeEditSession.swift`, `Code/CodeViewPlan.swift`.
- **Whole-line paste at the line start is not done** (VS Code pastes a copied whole line above the caret's line); a paste is a paste.
- Not in run 1: IME (the target ignores marked text and commits through `.textInput`), the blink (the caret is solid), autoscroll.

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

The idle frame's count is the visible rows' lookups (twice the depth at 100k); the pin subtracts it, bounds the difference at 40 and the extra at 200. `Handlers`: 480 bytes (was 488).

## 4. Pins that moved

| Pin | Before | After | Cause |
| --- | --- | --- | --- |
| `handlersGainsOneReferenceMember` | `== 488` | `== 480` | two boxes merged into one (`CV-W`) |
| `aWarmScrollFrameAllocatesTheSameAt1kAnd100kLinesAndAtAnyPosition` ceiling | 830 | 910 | the focused view now draws a caret: one more primitive, 81 allocations in `Scene.finalize`'s debug sort (764 to 845); the 1k-against-100k bound is unchanged |
| `everyStateWriteSiteIsClassified` | top-level files only | recursive, three `Code/` rows | the `Code/` sources were never scanned |

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
| the typed-key-press composition arm removed | **green, and equivalent until run 2**: a code view never composes yet (`isComposing` is `false`, the spelling it is replaced by reads a default `TextEditState`, also empty) |
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

## 6. TODO(run 2)

IME and marked text in `CodeViewState.composition` (`CodeEditSession.compose`/`dropComposition`/`isComposing`, `testingComposition`, the typed-key-press arm), the caret blink wake, drag-select autoscroll, gutter-bar click and context callbacks, find painting, the demo's read-only flag, final numbers and the verification run lines, `docs/api-overview.md`, the guide and `CLAUDE.md`.
