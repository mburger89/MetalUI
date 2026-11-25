# 413 - Split limits and stack probes: a frame answers one axis alone (G48, `HS-M`)

Date: 2026-11-24. Branch `perf/g48-split-limit-probes`. Owner prefix `HS-` (`docs/superpowers/2026-10-30-split-view-decisions.md`,
`HS-M`). No divergence: behaviour is the layout's, number for number.

## The finding

Alloy streams a reply into a chat transcript; `METALUI_TRACE_SHAPING=1` showed the growing paragraph shaped at five widths a frame
(395.36, 0.5, 284, 530, about 512). `SplitLayout.limits` was the suspect: it measured every pane at 0, nil and infinity, every layout.
`SplitLimitProbeTests` rebuilds the shape MetalUI-only (an `HSplitView` of three framed panes, the middle one `frame(minWidth: 320,
maxWidth: .infinity)` over a `VStack`, an `HStack` of a 4-point stripe and a `ZStack(.bottom)` frame, a `ScrollView` over a
`LazyVStack` with two short rows and a paragraph that gains eight words a frame, window 1100 wide) and reads the widths out of the trace.

| width | what asked for it | where |
|---|---|---|
| **284** (`320 - 4 - 2 * 16`) | the split's **minimum probe** of the chat pane: the frame's `minWidth: 320`, less the stripe and the padding, is the width the lazy stack and then the paragraph are offered | `SplitLayout.limits` (`SplitView.swift`, proposal `main: 0`) through `measureNative` `.frame`, `LayoutTree.swift` `framedProposal` |
| **50.43** (Alloy: 395.36) | the lazy stack at an unspecified or infinite width: its cross size is the **first row's ideal**, then every row, the paragraph included, is measured at it. Asked by the split's **ideal probe** (nil) and by the stripe row's flexibility probe at infinity | `LazyStackLayout.sizeThatFits` (`LazyStack.swift`, `cross = across(subviews[0].sizeThatFits(.unspecified))`), reached from `SplitLayout.limits` (nil) and `solveLinearStack` `offer(.infinity)` (`LayoutTree.swift`) |
| **0.5** (a text at 0) | the stripe row's flexibility probe at **0** of the flexible `ZStack` frame (a `frame(maxWidth: .infinity)` has no minimum, so it reads its child there) | `solveLinearStack`, `offer(0)` |
| **572** (Alloy: 530; `1100 - 2 - 250 - 240` less 4 and 32) | the pane's **own** proposal at placement: the one measure width that is not a probe | `placeNative`, the stack's offer |
| **549.26** (Alloy: about 512) | the **paint**: `ProposalText` shapes at the width it measured, its widest line at the proposal | `ProposalText.paint` (`pass.measuredWidth`), a different key from 572 |

**530 was not a mystery**: it is the pane's proposal (pane width less stripe and padding), the same role as the fixture's 572; about 512 is
the widest line of the text wrapped at 530, the paint width. Both are legitimate: the measure and the paint of a wrapped text are two
shapes by the text system's design (`ProposalText` paints at the width it measured). 395.36 is the fixture's 50.43 with Alloy's longer
first row. 284 is the split's.

## What changed

- `LayoutTree.determinedExtent(_:proposal:horizontal:)` (`package`): the one axis of a **frame** node's answer when no child can change it,
  else `nil`. The cases are `framedDetermined`, now the first thing `framedSize` does, so the answer a frame gives and the one
  `determinedExtent` gives are one expression: a fixed size; a maximum and a minimum with a proposal; a maximum alone with a proposal
  at or above it; no proposal and an ideal.
- `solveLinearStack`'s flexibility probes (main 0 and infinity) and its reserve probes read only the main axis: they take
  `determinedExtent` first. A stack of fixed frames, of `frame(maxWidth: .infinity)` children, of `frame(minWidth:maxWidth:)` ones no
  longer measures them for ordering.
- `SplitLayout.limits` reads each pane through `MeasurementSubview.extent(horizontal:_:)` / `PlacementSubview.extent(horizontal:_:)`
  (`package`), the same shortcut. A pane that is a frame with min and max (the common spelling) is never measured for its minimum or
  maximum; with `idealWidth` also, never for its ideal.
- The ideal is read **only when the solve can read it** (`solveReadsIdeals`): `SplitSolver.solve` replaces every ideal with the user's size
  when `preferred` has one entry per pane (an autosaved or dragged split view), and the nil-or-infinite proposal sums the ideals (`HS-J`).
- Not done, with the reason: the ideal probe of a pane with no `idealWidth` stays (probe: `min320 max inf` at nil answers 320, 500 or 1500
  as the child does), and the stripe row's 0 probe of a `frame(maxWidth: .infinity)` stays (no minimum: the child shows through at 0).
  Neither can be skipped without changing an answer.

## The SwiftUI rule

`docs/probes/swiftui-flex-frame-determined.swift` (macOS 27.2.1) measures a frame over a child that answers 10, 500 or 1500 points whatever it
is proposed, for ten frame spellings and proposals 0, nil, 100, 500, 900 and infinity. The answer is the same over all three exactly for: a
fixed size; `minWidth` and `maxWidth` with any proposal (`clamp(proposal, min, max)`); `maxWidth` alone at a proposal at or above it;
an ideal at a nil proposal (`clamp(ideal, min, max)`). The child shows through everywhere else, including a nil proposal with min and
max but no ideal (the split's ideal probe of Alloy's chat pane). `FR-A`/`FR-B`/`FR-L`/`FR-M` had these answers; the probe adds that
the child cannot move them. (The probe also shows, unrelated to this work and not investigated, that a frame with a minimum and no
maximum answers the child's width clipped to the proposal, where `framedSize` answers the child's.)

## Pins (record 413's tests)

- `DeterminedExtentTests` (Layout target, 6): the grid of 29 bound sets, four child widths and twelve proposals (`determinedExtent`
  equals the measured width when it answers and answers exactly when no child width moves the measurement); the height axis; only a frame
  answers; a greedy frame's infinite probe never reaches its leaf (the leaf sees 0 and 96, not infinity); 3 072 stack layouts equal the same stack with each frame
  behind zero padding (both axes, eight main proposals); the probe's recorded SwiftUI rows as literals.
- `SplitLimitProbeTests` (Testing target, 5): the control (a pane behind zero padding is still probed at 284 and shapes at **five** widths a
  frame); the fix, no saved sizes: **four** widths (50.43, 0.5, 572, 549.26), 284 gone; saved sizes: **three** (0.5, 572, 549.26), the least a
  stack and a text allow; every sixth ordered triple of nine pane specs, three window widths, three kinds of saved sizes, laid out bare
  against behind zero padding, same rects; bare panes keep probing and keep their sizes, `VSplitView` included.
- Moved by the skipped probes (each fell, each re-derived): `aLoweredBranchingTreeRegistersAndMeasuresAHandDerivedAmountOfNativeWork`
  118 misses / 94 hits to 94 / 52 (the hand derivation re-done in its doc comment and equal to the run), the bracket window's drag frame
  (cache misses 223 to 207, cache hits 365 to 323, memo hits 1259 to 1097 retention off; 330 / 288 and 363 / 327 retained), the harness warm-drag
  press frame (25 misses / 44 hits to 17 / 24), and the demo's cold-frame shaping (`theDemoDoesTheSameTextWorkAsBefore`: 1020 misses / 1544
  lookups to 1018 / 1538). Steady and warm frames, element requests, allocation pins: unmoved.

## Mutations

Each applied alone to the committed code, `--filter` the two new files; "red" names the tests that reddened.

| # | mutation | red |
|---|---|---|
| M1 | `framedDetermined` never answers | the grid, the greedy-frame leaf test, the height-axis test, the fixture's 284 and 3-width pins |
| M2 | min+max arm answers the proposal unclamped | the fixture's 284 pin, the bare-pane literals, the height-axis test (and the recorded rows, test 6, added after) |
| M3 | maximum-alone arm without its proposal test (a minimum alone is "determined") | the grid, the greedy-frame leaf test, the control, both fixture pins |
| M4 | ideal arm unclamped | **none: an equivalent mutant**; `validateFrameAxis` already orders min <= ideal <= max |
| M5 | `mainExtent` in the stack measures | the greedy-frame leaf test, the saved-sizes fixture pin |
| M6 | `solveReadsIdeals` always true | the saved-sizes fixture pin |
| M7 | `solveReadsIdeals` always false | the control, the bare-pane literals, the no-saved fixture pin (not the parity test: both arms share it) |
| M8 | the minimum and maximum probes swapped | the control, the bare-pane literals, both fixture pins |
| M9 | the proxies' `extent` measures instead | both fixture pins |
| M10 | `determinedExtent` answers for padding | the stack parity test, the only-a-frame test, the bare-pane literals, the split parity test |

## Measurement

Release, `SplitBench` (the fixture in a scratch package against `master` and the branch, interleaved base/branch, nine repeats, 60
streamed frames after 20 of warm-up; the machine loaded by other sessions' builds, load average 12): CPU ms a streamed frame, median of the nine medians
(paired delta of the nine, median / min / max), `phys_footprint` at exit, live malloc blocks at exit.

| mode | ms (base, branch) | paired delta ms | footprint MB | live blocks | shaping misses a frame |
|---|---|---|---|---|---|
| saved sizes | 45.8, 37.6 | -10.5 (-4.4 to -67.4; every pair down) | 27.2 to 22.5 | 25514 to 21744 | 5 to 3 |
| no saved sizes | 46.3, 44.0 | -1.7 (-10.1 to +25.5, noise) | 27.3 to 25.7 | 25560 to 24966 | 5 to 4 |

Without saved sizes the saving is one of five shapes of a paragraph (the minimum probe's); with them it is two of five and the paragraph's
unbounded cache growth is smaller by what it no longer shapes (14129 blocks grown against 16616 over the timed frames). No new cache and no
new allocation: a determined answer is arithmetic on the node's own fields. The sizes are small because the fixture streams 300 words;
the saving grows with the paragraph (a shape costs by its length). Kept: it helps.

## Counts

See `CLAUDE.md`'s counts line for this record.
