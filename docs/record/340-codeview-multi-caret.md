# 340 - Drawing every caret (`CV-BG`)

Branch `feat/codeview-multi-caret` from master `66cfba26`. Class M, no divergence (labels untouched). PR 3 of the editor-essentials plan for Alloy (G1, multi-caret drawing); builds on the primary selection and batched edits of record 333.

**What landed.**
- `CodeViewPlan` keeps the state's sorted `selections` (no copy) and, after the shown rows are laid out, the index range of those touching their byte span by two binary searches (`selections(_:touching:visited:)`). One selection runs the scalar path unchanged.
- Paint: the highlight of every visible selection (a cursor over the rows), a caret for every visible empty selection, none at the head of a range (Alloy's answer 1, Xcode). One `caretIsShown` call a frame: one blink deadline, one epoch.
- `CodeSelectionState.mutationSerial` (`package`, `@ObservationIgnored`) rises on every stored change; the blink restart compares it, so a non-primary selection moving restarts the blink at O(1).
- The primary still drives `revealsCaret`, the input method's rectangle, `CodeTextAnchor.caret` and marked text; a composition is drawn at the primary only and commits to every selection.
- `FrameWork.codeSelectionsVisited` (public, `MetalUITesting`) counts the probes and the selections of the range.

**Probe** `docs/probes/appkit-multi-range-selection.swift` (compiled, run on macOS 27.2; the process could not become the active application, so the window's key state was faked as in the inactive-selection probe): `NSTextView.setSelectedRanges` kept one of three zero-length ranges; with a caret, a range and a caret it kept the first caret and the range; with a range, a caret and a range it dropped the caret; non-empty ranges all survived and drew. No multi-caret drawing in AppKit, so this is MetalUI-only.

**Cost** (literals measured on master `66cfba26` with the same test file, identical on this branch for 1, 3 and 50 carets): steady frame, one retained view 2 requests and 0 hits / 1 miss / 0 ineligible, two views 3 and 1/1/0; keystroke frame 2 and 0/1/0 (blinking: 2 and 0/0/1); an idle view with three solid carets 0 requests, 0 frames.

**Offscreen.** With 10,000 selections one per line, a frame visits at most visible + 2 x 14 selections; with every selection below the view, at most 28.

**Tests.** `CodeViewMultiCaretTests.swift`, `CodeViewMultiCaretCostTests.swift`, `SelectionStateTests.theMutationSerialRisesOnEachStoredChangeAndOnlyThen`. Mutations run and reverted are listed in the PR description.

**Human check.** `CV25` (several carets, blink, the inactive colour, a composition).
