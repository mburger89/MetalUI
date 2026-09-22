# §21 — the integration of task 7's stage 2 and stage G

`integrate/stage-2-grids`, branched from `cb2e708` (the last commit before
either track). Two tracks ran in parallel in separate worktrees and are merged
here: `feat/engine-stage-2` (record §19, rulings `LR-AB`…`LR-BA`) and
`feat/grids` (record §20, rulings `GR-A`…`GR-AT`).

This file records **the merge itself**: what conflicted, what the merged suite
found that neither track's suite could, and the demo comparison. Each track's
own reasoning stays in its own record.

## 1. The two merges

Both tracks branched from `cb2e708` and the integration branch started there,
so each merge is a real three-way merge against the other's work.

| # | merge | result |
|---|---|---|
| 1 | `git merge --no-ff feat/engine-stage-2` (`c41a633`) → `356bb2b` | **no conflicts.** 22 files, +8 998 / −372 |
| 2 | `git merge --no-ff feat/grids` (`ac1ad1d`) → `a948f8a` | **no conflicts.** 34 files, +17 426 / −11 |

**One source file is touched by both tracks**, `Sources/MetalUILayout/LayoutTree.swift`,
and git resolved it without a conflict because both tracks obeyed the brief's
"append rather than reorder": the engine track's edits are in the lowering and
rounding regions, the grids track's are a `case` appended last to `NativeNode`,
arms appended last to each `switch`, mark tables after `nativeParents`, and one
extension at the end. `Tests/MetalUITests/ModifierCompositionProofTests.swift`
and `Tests/MetalUILayoutTests/NativeValidationAcceptanceTests.swift` are each
touched by one track only.

**No interaction breakage.** After merge 2, `swift package clean` →
`swift build --build-system native --build-tests` → unfiltered
`swift test --build-system native --no-parallel` read
`Test run with 1544 tests in 1 suite passed` on the first attempt: 1460 (the
engine track's figure, reproduced here after merge 1) + 84 (the grids track's
1493 − 1409). Nothing needed fixing red-first, so there is no fix commit in this
record. The `swift package clean` was not optional: **both** tracks add stored
properties to public types that cross a module boundary (the engine track's
`Frame.lowering`, the grids track's six `LayoutTree` mark tables).

### On `feat/grids`' `allOk: false`

The grids track's track-outcome JSON reports `allOk: false`, because lane 2's
verifier returned `ok: false` with one major (a whole-file `GF14`/`GF15` →
`GF19`/`GF20` rename that also renamed test 2.1's pre-existing arms) and one
minor (a mutation tally counting `M5` as green). **Both were applied on the
track before this merge**, in `ac1ad1d` (ruling `GR-AT`), and both were verified
here against the merged source before merging rather than taken on the note's
word:

- `Tests/MetalUILayoutTests/NativeGridTests.swift` carries `// GF14` and
  `// GF15` in test 2.1 again (lines 1122 and 1128, with the probe's own
  200×58 and 78×58 figures) and its own `GF19`/`GF20` in test 2.2, so the
  namespace collision is gone and the "GF14–GF18 belong to 2.1, next free is
  GF21" rule is true of the source;
- `docs/record/20-grids.md:1089` and the decisions doc both now read "of the
  eighteen, seventeen reddened and one — A — is green", and the "None was
  green." sentence is gone.

Neither finding was executable — labels and prose only — and the verdict field
predates the fix commit. The track was merged, with this paragraph as the
record of why.

## 2. Cross-track tests

`Tests/MetalUITests/GridLoweringInteractionTests.swift`, four tests, suite
1544 → **1548**. The two tracks meet at exactly one seam: a kernel node under
the **proposal layout authority**, where a lowered legacy element and a grid are
both simply native nodes (ruling `LR-T`). Neither track could write these —
each holds only one half.

Every literal was hand-derived in the test's doc comment before the first run,
and every arm but one matched on the first run (see X3 below).

| id | test | claim |
|---|---|---|
| X1 | `aGridsColumnWidthReachesAGrowingChildInsideALoweredCell` | a grid cell that is a lowered legacy container with a growing child: the grower fills the width the **grid** chose, not the width the cell answered alone |
| X2 | `aGridInsideALoweredContainerIsNeverStretchedWhereItsRecordedSiblingIs` | a `Grid` inside a lowered legacy container registers no `LoweredItem`, so `planLegacyItems` gives it an empty plan — never stretched — while a recorded sibling in the same container is |
| X3 | `aLoweredTextAndAProposalTextSizeOneGridColumnIdentically` | a lowered `Text` and a `ProposalText` share one measurement (`LR-F`), so two cells of one grid column spelling the same string both ways size it identically |
| X4 | `anItemFieldOnAGridCellIsReportedUnconsumed` | a grid consumes no item record, so an item field on a top-level cell reports `<site>.<field>.unconsumed` (`LR-AQ`) rather than silently doing nothing |

**X1's derivation.** A 120×40 harness root, so the grid's own proposal is
120×40. One column: the `Row` cell is flexible (its grower answers its
proposal) and the finite solve serves it the whole 120, so it answers 120×10;
the `fixed(50, 12)` cell is rigid. Column 0 = max(120, 50) = 120; row heights
10 and 12; `vgap[1]` = 10, so the grid is 120×32 and row 1 starts at y = 20.
The `Row` cell's slot equals its answer and is placed at (0, 0, 120, 10); the
rigid cell's slot (120×12) does **not**, so it is re-measured at the slot, still
answers 50×12, and `.topLeading` puts it at (0, 20, 50, 12) — the control that a
rigid cell does not grow into its slot. Inside the `Row`, the lowered stack is
offered 120: `fixed` takes 20 and the grower's W takes the surplus, (20, 0, 100,
10), its element rect being W's by the grow alias (`LR-AB` item 3).

**X2's derivation.** `Row { fixed(20,10); Box().width(15); Grid{…} }.alignItems(.stretch).height(40)`
under the proposal authority (under `.legacy` this tree traps, `SA-G` — which is
the point: the grids track's elements only became reachable from a legacy
container when the engine track's authority landed). `fixed` declares its cross
size and is not stretched; `Box().width(15)` leaves its height `auto` and fills
the 40-deep line — the control proving stretch is live in this very tree; the
`Grid` keeps its own 80×10 answer at (35, 0).

**X3, and the clause neither track pinned.** X3's first clamp arm was written at
an offer of 40 and then 12, and the mutation that should have reddened it —
**XM4**, the shared `min(proposal, widest line)` dropped from the lowered `Text`
alone — left **all 1548 tests green**. The reason: lane 3 pinned that clamp
through `ProposalText` only, and at an offer of 12, 16 or 40 the typesetter's
broken line already fits, so the clamp is not what bounds the answer (measured:
12 → 12, 16 → **15**, 40 → **39**). Only a very narrow offer discriminates, where
the typesetter breaks inside a word and the line it produces is wider than the
proposal (stage 1's T3/T4 read 11.18 against 5). The arm was moved to an offer of
5 and XM4 then reddens X3 and **nothing else** — so X3 is the sole pin for the
lowered half of lane 3's clamp, and this is the integration's one real finding.

This is the merge-shaped version of a practice already in `CLAUDE.md`: a clause
both tracks share can be pinned by neither.

### Mutations

Protocol: committed first, each mutation applied to a copy, the **full
unfiltered** suite run, the file restored from the copy, `git status --short`
empty after each (it was, every time).

| id | mutation | reddened |
|---|---|---|
| **XM1** | `planLegacyItems`: grow sets the **cross** axis (`if isRow { grownV } else { grownH }`) | **X1 (5)**, plus 15 stage-2 tests — `aGrowingChildTakesTheRemainingMainSpace` (36), `aZeroBasisGrowerTakesItsShareDownToItsContent` (9), `reversingKeepsIdentityPaintOrderHitOrderAndAccessibilityOrder` (10), `growingSiblingsShareTheSurplusEquallyWhereCSSAddsItToTheirBases` (8) and eleven more; 99 issues |
| **XM2** | `NativeGridSolver.serve`: `width = Swift.max(shareW, widths[cell.column])` → `width = widths[cell.column]` | **X1 (3)** and **X3 (1)**, plus 19 grid tests — `theGridProbeCorpusAgreesCaseByCase` (144), `aFiniteProposalServesGroupsWithSharesAndCommits` (63), `theModelsDisagreementsWithSwiftUIArePinned` (23) and sixteen more; 359 issues |
| **XM3** | `planLegacyItems`: the `guard let item else` arm made to give an **unrecorded** child a greedy vertical W under a row parent | **X2 (1)** and `theWholeDemoReportsExactlyTheFieldsAndSitesLaterStagesOwn` (2); 3 issues |
| **XM4** | `Text.swift`'s lowered leaf de-unified from `ProposalText` — the shared `min(proposal, widest line)` clamp dropped there only | **first run: NOTHING** (1548 passed). After X3's arm moved to an offer of 5 (**XM4b**): **X3 (3)** and nothing else |
| **XM5** | `Grid.requestProposalLayout` made to consume its children's `LoweredItem` records | **X4 (5)** and nothing else |

XM1 and XM2 are the two sides of X1 — one from each track — and each reddens it,
so X1 reads the seam rather than one track's half. XM3, XM4b and XM5 each redden
their own test alone.

## 3. Demo comparison

`CN-R`'s harness (`gen-lib.py`, which imports `MetalUIDemoContent` rather than
copying `main.swift`), generated into fresh `git archive`s of `cb2e708`, the
merged HEAD and — for attribution — `feat/grids`; `DEMO_PIXELS_SMALL=1`.

**Controls first, on the head images** (an instrument that reads 0 everywhere is
not an instrument). Every one reproduces the figure both tracks recorded:

| control | px |
|---|---|
| light vs dark, `default-*-f0` | 1 048 576 |
| `default-light-f0` vs `modal-light` | 1 030 498 |
| `default-light-f0` vs `animation-light` | 210 027 |
| `default-light-f0` vs `default-light-f3` | 0 (settled, as recorded) |
| `preview-light` vs `preview-dark` | 1 048 576 |
| `small560-default-light` vs `small560-preview-light` | 171 670 |
| `chrome-legacy` vs `small560-default-light` | 308 354 |
| distinct pixel values in `default-light-f0` / `chrome-legacy` | 544 / 216 |

**`cb2e708` → merged HEAD**, twelve images:

| image | px | bbox | scene |
|---|---|---|---|
| `default-light-f0`, `default-light-f3`, `default-dark-f0`, `default-dark-f3` | **0** | — | identical |
| `modal-light`, `modal-dark` | **0** | — | identical |
| `animation-light`, `animation-dark` | **0** | — | identical |
| `small560-default-light` | **0** | — | identical |
| `preview-light` | 7 680 | (624, 865)–(795, 920) | DIFFER |
| `preview-dark` | 7 680 | (624, 865)–(795, 920) | DIFFER |
| `small560-preview-light` | 52 033 | (0, 63)–(559, 497) | DIFFER |

**The three differences are explained, not tolerated.** The grids track
deliberately added a grid to `nativeLayoutPreviewContent()`:

- the bounding box is 172 × 56, which is two 80-wide columns with a 12 gap and
  two 24-tall rows with an 8 gap — the grid's own box;
- 7 680 differing pixels is exactly 4 × 80 × 24, the four cells, the gaps between
  them being background that did not change;
- `small560-preview-light` differs more widely because the narrower preview
  reflows around the new grid.

**The merge itself renders nothing.** Merged HEAD vs `feat/grids`' own head is
**0 differing pixels in all twelve, every scene identical** — so the whole
`cb2e708` → HEAD delta is the grids track's preview grid and none of it is a
merge artefact. `cb2e708` → `feat/grids` reproduces exactly the same three
numbers, which is the same statement from the other side.

The **two-authority chrome pair** on the merged head (`chrome-legacy` vs
`chrome-proposal`, the same corpus tree rendered under each layout authority
through a real `Window`) reads **0 differing pixels**, scene identical, and is
not blank (216 distinct values, 308 354 against `small560-default-light`).

**No real-window capture.** `docs/probes/appkit-screen-lock-state.swift`
printed `session CGSSessionScreenIsLocked = 1`, `displayAsleep main: 1`,
`displayActive main: 0`, so the brief's gate fails and
`docs/probes/window-capture/capture.sh` was not run. `IOConsoleLocked` was not
read (`FR-V`). The row in `CLAUDE.md`'s human-verification table is open for the
real-window half and closed for the offscreen half.

## 4. Counts

Measured on `integrate/stage-2-grids` after `swift package clean` and
`swift build --build-system native --build-tests`
(`Build complete!`, 0 `error:`, the only `warning:` SwiftPM's own
`--build-system native` deprecation notice), unfiltered
`swift test --build-system native --no-parallel`, one summary line:

**1548 tests · 97 goldens · 75 guards · 0 `error:` · 0 `warning:`**

- 1409 → 1548 = **+139**: stage 2 +51, stage G +84, this integration +4.
- Goldens: 97, and `git diff --name-only cb2e708 -- '*.json'` is empty.
- Guards: 77 `canTypecheck` hits less `Typecheck.swift`'s declaration and
  `UnitSafetyTests`' comment. **+4** over 71, all `GridCompileGuards`; stage 2
  added none. Per file: `PhaseSeparationTests` 19, `ErasureCompileGuards` 10,
  `EnvironmentCompileGuards` 8, `ProposalNodeIDCompileGuards` 6,
  `ProposalLayoutCompileGuards` 6, `ElementGroupTrapTests` 5,
  `ContainerCompileGuards` 4, `GridCompileGuards` 4, `AXNodeTests` 3,
  `DecorationCompileGuards` 3, `UnitSafetyTests` 2 (3 hits, one a comment),
  `ModifiedElementCompileGuards` 2, `FrameSizingCompileGuards` 2,
  `LayoutAuthorityCompileGuards` 1.
- `@available(*, deprecated` hits: **34**, unchanged.
- Kernel surface: `NativeNode` is **twelve** built-in cases plus `custom`;
  `LayoutPass` and `LayoutTree` have **13** registrars each plus **two** mark
  functions each.

Re-measure rather than trust these: a count is stale the moment a test lands.

## 5. What this integration did NOT do

- **Production is unchanged.** `LayoutAuthority.proposal` is still set by no
  production code; every production frame runs the CSS engine. Stage 6b is when
  that changes, and stage 2's and stage G's answers reach a user then.
- **No real-window capture** (screen locked; §3).
- **No human look at a grid on screen** — open, owner task 15's closeout
  (`GR-N`), now a row in `CLAUDE.md`'s human-verification table.
- **Divergence 60 is unpinned** (SwiftUI's integer text width), owner task 11,
  and must be settled before stage 6b.
- **Task 7 is not ticked.** Stages 2 and G of fourteen are landed; the plan's
  entry carries a dated progress note instead.
