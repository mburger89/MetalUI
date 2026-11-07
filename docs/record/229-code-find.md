# Record 229: find matches in the code view (Alloy gap G1, PR 4)

PR 4 of Alloy gap G1 on branch `feat/code-find` (master `33aad057`, which has `MetalUICodeBuffer` with `snapshot.ranges(of:options:limit:)`, record 225, the read-only `CodeView`, record 227, and editing, record 228). Class `M`: no divergence added or retired. Ruling `CV-AE` in `docs/superpowers/2026-11-07-code-view-decisions.md` (next `CV-AF`). The find **bar** stays the app's; this PR is the painting and the navigation.

## 1. What was built

- **Matches as decorations (`CV-AE`).** `CodeDecorations.findMatches: [Range<Int>]` and `currentMatch: Int?`, UTF-8 offsets into the text now (assignment drains the edit cursor first). Observable, sorted and thinned to disjoint ranges on the way in. They follow the buffer's edits inside `apply(edit)`: a match ending at or before the edit stays, one starting at or after its end shifts by the delta, any the edit touches is dropped, and `currentMatch` follows or becomes `nil`. A `.resync` clears them. Never painted from stale coordinates.
- **Painting.** A background layer under the selection, in paint order after the run backgrounds: `CodeTheme.findMatch` (yellow at 0.35) and `CodeTheme.currentFindMatch` (orange at 0.65), both new with defaults. Only the shown rows' matches are visited: `findSpan(in:)` binary-searches the sorted matches per painted row. `FrameWork.codeFindMatchesVisited` (public, `TestApp`, `BuildWork`, `Frame.codeWork`) counts them.
- **Navigation.** `CodeCommand.findNext`/`.findPrevious`: ⌘G / ⇧⌘G on a Mac and ⌃G / ⌃⇧G elsewhere (`CodeEditing.command(for:platform:)`). Wraps; steps from the current match when the selection is exactly it, otherwise from the selection. Selects the match with `buffer.select(_, reveal: true)`, which centres its row in every view of the buffer in the next frame (`CV-V`). Claimed only while matches exist; works on a read-only view.
- **Current line.** `CodeTheme.currentLine: Color?` (default `nil`, off): a tint across the caret's row while nothing is selected, painted after the line tints and before the matches.

## 2. Deviations from the plan

- **The plan's `findMatches` is a stored array; here it is a computed property over ignored storage** so a read can first `sync()` the edits. A read in a phase is therefore not a pure read of the observed stamp; it observes `revision` like the other getters.
- **Overlapping matches are thinned, not rejected**: an assignment keeps the first of two overlapping ranges (the engine never produces them, but a hand-built list could, and the sorted-ends lookup needs them disjoint). `currentMatch` is remapped by identity.
- **The key is not claimed with no matches** (the plan: "when find matches exist"), so an app's `onKey` binding for the same chord still fires; with matches the view claims it before `onKey` (the order is Keymap, `onKeyPress`, field keys, `onKey`).
- **The step from a caret inside a match skips that match** (Xcode's behaviour); from a caret at a match's start it takes that match.
- **No `setFindMatches(asOf:)`**: the matches are as of the version at assignment. An app that searches on a background snapshot reassigns on the main actor after checking `snapshot.version == buffer.version`.
- **No F3 binding**: the chord table stays ⌘G / ⌃G only.

## 3. Numbers

Harness window 400 x 200 at 1x, Noto Sans 12 (pitch 17, 13 rows shown), macOS arm64 debug, `RopeStats.nodesVisited` and `FrameWork.codeFindMatchesVisited`.

| Measure | 1k matches | 10k matches |
| --- | --- | --- |
| Matches looked at by the first frame (13 rows, 12 painted) | 132 | 174 |
| Bound the pin states (rows x (ceil(log2 m) + 3)) | 169 | 221 |
| Matches looked at by a wheel and a redraw (two frames) | 286 | 372 |
| Painting every match (the mutation) | at least 1 000 | at least 10 000 |
| Rope nodes of one `ranges(of: "foo")` over the text | 4 | 35 |
| Rope nodes of two warm frames with the matches / without them | 260 / 260 | 390 / 390 |

The find query is linear in the text (35 against 4 for 10 times the text) and a frame adds nothing to the buffer's work for any number of matches.

## 4. Pins that moved

None moved. `handlersGainsOneReferenceMember` stays 480 (the session gained a `decorations` reference; the hooks box did not grow). `everyStateWriteSiteIsClassified` gained no row: no `withState` was added. `FrameWork` gained one defaulted field.

## 5. Mutations

Each applied alone to the committed tree in place and restored with `git checkout` (script `mut.py` in the session scratchpad); the filter is `CodeViewFindTests` and the key table.

| Mutation | Reddened |
| --- | --- |
| no wrap (`min`/`max` clamp instead of the modulo) | `nextAndPreviousStepWithWrap` |
| stale coordinates (`mapFindMatches` not called by `apply`) | `matchesShiftWithAnEditAboveAndDropWhenTouched` |
| painting all matches (`findSpan` returns every index) | `manyMatchesPaintOnlyTheVisibleOnes` (both sizes) |
| ⇧⌘G direction flipped (the shift cases swapped) | `nextAndPreviousStepWithWrap`, `steppingCentresAMatchBeyondTheViewportInOneFrame`, `theFindKeysFollowThePlatformConvention` |
| the reveal left out (`reveal: false`) | `steppingCentresAMatchBeyondTheViewportInOneFrame` |
| the key claimed with no matches | `theKeyIsClaimedOnlyWhileMatchesExist` |
| the current index ignored in paint | `matchesPaintInTheirColoursAndTheCurrentOneApart` (first spelling trapped on an index after a failed count; the test now `#require`s it) |
| an edit that touches a match not dropping it (the span starts at the edit's start) | `matchesShiftWithAnEditAboveAndDropWhenTouched` |

## 6. Verification

VERIFICATION_PLACEHOLDER
