# §23 — the integration of task 7's stage 2 and stage G

`integrate/stage-2-grids`, branched from `cb2e708` (the last commit before
either track). Two tracks ran in parallel in separate worktrees and are merged
here: `feat/engine-stage-2` (record §21, rulings `LR-AB`…`LR-BA`) and
`feat/grids` (record §22, rulings `GR-A`…`GR-AT`).

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
- `docs/record/22-grids.md:1089` and the decisions doc both now read "of the
  eighteen, seventeen reddened and one — A — is green", and the "None was
  green." sentence no longer states anything: its one surviving occurrence,
  `docs/record/22-grids.md:1091`, is the **quoted erratum** that replaced it
  ("This paragraph read 'None was green.' until the lane-4 docs round"). *Said
  "the sentence is gone" until 2026-09-22; a `grep "None was green"` returns
  one hit, not zero, and an adversarial reader checking the grep would have
  read that as the fix not having landed.*

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

## 6. The verification round — every §2 and §3 number re-taken independently

A second pass over this integration, on the committed tree, taking the
measurements again rather than reading them. It changed no source and no test;
its two commits are documentation. The session that wrote §1–§5 was interrupted
after committing, so nothing here is a fix of unfinished work — it is the
check that the committed claims are true of the committed tree.

### The suite, the counts and the tree

`swift package clean` → `swift build --build-system native --build-tests`
(`Build complete!`, 0 `error:`, the only `warning:` SwiftPM's own deprecation
notice) → unfiltered `swift test --build-system native --no-parallel`:
**`Test run with 1548 tests in 1 suite passed after 52.663 seconds`** — §4's
figure. Goldens 97, `git diff --name-only cb2e708 -- '*.json'` empty. Guards 77
`canTypecheck` hits across 15 files, less `Typecheck.swift`'s declaration and
`UnitSafetyTests`' comment = **75**, the per-file table of §4 reproduced hit for
hit. `@available(*, deprecated` 34.

**The kernel-surface counts were the one claim that needed looking at twice.**
`grep -c "func requestNative" Sources/MetalUI/Passes.swift` reads **12**, not 13
— the thirteenth, `requestNativeGrid`, is in `Sources/MetalUI/Grid.swift`, an
extension on `LayoutPass` the grids track added in its own file. So §4 and
`CLAUDE.md` are right about the **type** (`LayoutPass` has 13) and a reader
greping one file will get 12. `LayoutTree.newNative*` is 13 in one file.
`NativeNode` is twelve built-in cases (`leaf`, `overlay`, `overlayAttachment`,
`frame`, `padding`, `fixedSize`, `aspectRatio`, `layoutPriority`, `spacer`,
`scrollViewport`, `linearStack`, `grid`) plus `custom`. Every test name
`CLAUDE.md`'s new rows and record §04's new index rows cite exists, checked by
`grep -rl "func <name>" Tests`: 18 of 18, one file each.

### The four cross-track tests: four of the five mutations re-applied

Protocol as in §2: committed first, the file copied aside, the mutation applied,
the **full unfiltered** suite run, the file restored from the copy,
`git status --short` empty after each (it was, every time). `XM2` was not
re-run: `XM1` and `XM2` are the two halves of `X1`'s seam and `XM1` was.

| id | re-applied as | reddened | vs §2 |
|---|---|---|---|
| **XM1** | `planLegacyItems`: `if isRow { grownH = true } else { grownV = true }` → the two swapped | `aGridsColumnWidthReachesAGrowingChildInsideALoweredCell` (**X1**, 5) plus 15 stage-2 tests, **99 issues** — `aGrowingChildTakesTheRemainingMainSpace` 36, `reversingKeepsIdentityPaintOrderHitOrderAndAccessibilityOrder` 10, `aZeroBasisGrowerTakesItsShareDownToItsContent` 9, `growingSiblingsShareTheSurplusEquallyWhereCSSAddsItToTheirBases` 8 … | **exact** |
| **XM3** | `planLegacyItems`' `guard let item else` arm given `plan.itemFrameHeight = (0, .infinity)` under a row parent | **X2** (1) and `theWholeDemoReportsExactlyTheFieldsAndSitesLaterStagesOwn` (2), 3 issues | **exact** |
| **XM4b** | `Text.swift`'s lowered leaf de-unified: `proposalTextMeasurement` replaced inline by `cache.shaped(…).widestLine` with no `min(proposal, …)` | **X3 and nothing else**, 3 issues | **exact** |
| **XM5** | `Grid.requestProposalLayout`: `for c in children { _ = pass.frame.lowering.consume(c.layoutNodeID) }` before the registrar | **X4 and nothing else**, 5 issues | **exact** |

`XM4b` is the one worth re-taking by hand, because it is this integration's only
finding: it confirms that **X3 is the sole pin for the lowered half of lane 3's
clamp**, and that the clause was reachable by neither track alone.

### The pixels, re-generated from scratch on three trees

The `CN-R` harness was **rebuilt from the recipe** (it is a scratch artefact, not
a committed one): a generator importing `MetalUIDemoContent`, rendering through a
real `Window` over `FakePlatformWindow`, writing each image's raw BGRA bytes and
a scene dump. Three trees, each a fresh `git archive` built on its own:
`cb2e708`, `ac1ad1d` (`feat/grids`' head) and this branch's HEAD.

**Controls first, on both sides.** Every one reproduces §3's figure: light vs
dark f0 **1 048 576**; f0 vs f3 **0**; f0 vs modal **1 030 498**; f0 vs animation
**210 027**; preview light vs dark **1 048 576**; `small560-default-light` vs
`small560-preview-light` **171 670** at the head (178 634 at the base — it moves
because the grid is in the preview, which is the point).
`default-light-f0` holds 544 distinct pixel values.

**`cb2e708` → HEAD, twelve images:** nine at **0** with identical scene dumps
(every default, modal and animation image, light and dark, and
`small560-default-light`); `preview-light` and `preview-dark` **7 680** in bbox
**(624, 865)–(795, 920)**; `small560-preview-light` **52 033** in bbox
(0, 63)–(559, 497). §3's numbers to the pixel and to the bounding box.

The attribution checks out arithmetically: the bbox is 172 × 56 =
(80 + 12 + 80) × (24 + 8 + 24), the preview grid's own box, and 7 680 = 4 × 80 ×
24, its four cells — the gaps between them are background that did not change.

**HEAD vs `feat/grids`: 0 differing pixels in all twelve, every scene identical.**
So the whole `cb2e708` → HEAD delta is the grids track's preview grid and none of
it is a merge artefact — §3's claim, re-measured from both trees' own archives.

**The two-authority chrome pair** (`StageOneCorpus.counterChrome()` in a 560²
`DifferentialRoot` through a 560² `Window` under each authority, via
`WindowPair`): `chrome-legacy` vs `chrome-proposal` **0 differing pixels, scene
dumps byte-identical**, 216 distinct values, **308 354** against
`small560-default-light` — so it is not two blank images agreeing. **Its
instrument control `M5d`** (`spacing: arrangement.spacing + 50` in
`LegacyLowering.swift`, which moves the lowered side alone) takes the pair to
**8 214** differing pixels with the scenes differing: §3's figure, and the proof
that this pair can see a lowering change when the twelve images cannot.

### The screen, again

`docs/probes/appkit-screen-lock-state.swift`, compiled and run twice in this
round: `session CGSSessionScreenIsLocked = 1`, `displayAsleep main: 1`,
`displayActive main: 0`. The brief's gate fails in both readings, so
`docs/probes/window-capture/capture.sh` was **not** run and the real-window half
of the human-verification row stays open. `IOConsoleLocked` was not read
(`FR-V`).

### Two staleness findings, fixed

Neither is about this merge's code; both are documents this integration's own
claims point at.

1. **`SA-N` item 4 was still open in the `SA-` decisions doc.** `CLAUDE.md` and
   the plan both say `SA-N`'s "probed, and the kernel disagrees" list is empty,
   closed by `LR-AU`. The doc they cite still read "assigned to plan task 7 by
   `CN-Q`", with no closure — so following the citation gave the opposite answer.
   Item 4 now records the closure (both kernel entries, the pin
   `aNativePaddingPlacesItsChildAtTheChildsOwnSize`, the mutation `M3a` that
   reddens it, and the caller-bounds arm to re-check at stage 6b), and the
   section's closing paragraphs state that the list is empty and why.
2. **`README.md`'s pointer at record §04** named index tables "20–34, 35–50 and
   51–58" — already missing 59 before this stage and now 60–70 as well — and its
   retirement sentence did not carry 59. Both corrected against §04's own
   section headings.

**Nothing else in §1–§5 was refuted.** Every number this round re-took came back
identical.

## 7. Adversarial round (2026-09-22) — §1–§6 re-taken by a reader who did not merge

A second, independent pass over the merged branch at `80a9f9a`. It repeats §6's
work rather than reading it, on the principle that a round cannot verify itself:
§6 was written by the integrator.

### Suite, counts, goldens, guards

`swift package clean`, then `swift build --build-system native --build-tests`
(`Build complete! (34.89s)`, 0 `error:`, the only `warning:` SwiftPM's own
`--build-system native` deprecation notice), then unfiltered
`swift test --build-system native --no-parallel`:

```
􁁛  Test run with 1548 tests in 1 suite passed after 58.286 seconds.
```

One summary line. Exactly two tests skipped — `regenerateAllGoldens` and
`aListsWorkIsTheSameFor100kRowsAsFor500`, the two known gated ones — and **no
guard skipped**: `.build/arm64-apple-macosx/debug/Modules` is present and the
four `GridCompileGuards` each took ~0.46 s of real `swiftc -typecheck`, which is
the only way to tell a guard that ran from a guard that returned true for free
(`08-when-ci-lands.md` item 3).

`find Tests -name "*.json" | wc -l` → **97**, and `git diff --name-only cb2e708
HEAD -- '*.json'` is empty. Guards: **77** `canTypecheck` hits across 15 files,
less `Typecheck.swift`'s declaration and `UnitSafetyTests`' comment (3 hits, one
at `:13` inside a comment) → **75**, per file exactly as `CLAUDE.md`'s table
reads. `cmp CLAUDE.md AGENTS.md` clean.

### Citation sweep

Every backticked identifier of 15 characters or more in the fourteen documents
changed since `cb2e708` (514 distinct) was checked against the set of all
identifiers in `Sources/` and `Tests/`. **Thirteen are absent, and all thirteen
are legitimate**: seven name work a later stage owes
(`noProductionFrameReachesTheLegacyEngine` at 6b,
`theLegacyEngineSymbolsAreAbsentFromTheTestProcess` at 10,
`aProposalTextBelowItsNarrowestWord…` in the retired-divergence-59 entry), three
name symbols an earlier round deleted or renamed and say so at the citation
(`aspectRatioSize`, `stackMainAllocations`,
`aLegacyNodeRegisteredUnderANativeGridTraps`), and three are spec prose for
types that were never built. No changed document cites a test that does not
exist.

Ruling ids: 294 distinct cited, all defined in a decisions doc except the
deliberate "a bare `GR-3` is a typo" examples, the "next unused" pointers, and
the six older numbered ids whose docs define them in tables rather than
headings. **One real defect** (below). `CLAUDE.md`'s divergence table holds 58
numbered rows and its prose says fifty-eight; 59 is absent and listed as
retired. Every `file.swift:NNN` citation in `CLAUDE.md` resolves to a file that
exists and a line within it.

### Mutations — one central one per track, plus the integration's own

Applied to the merged tree, full unfiltered native suite each time,
`git status --short` empty after each revert.

| id | track | mutant | read | recorded |
|---|---|---|---|---|
| `XM1` | stage 2 | `LegacyLowering.swift`'s `planLegacyItems`: `if isRow { grownH = true } else { grownV = true }` → the two swapped | **16 tests, 99 issues** — `aGridsColumnWidthReachesAGrowingChildInsideALoweredCell` (**X1**) 5, `aGrowingChildTakesTheRemainingMainSpace` 36, `reversingKeepsIdentityPaintOrderHitOrderAndAccessibilityOrder` 10, `aZeroBasisGrowerTakesItsShareDownToItsContent` 9, `growingSiblingsShareTheSurplusEquallyWhereCSSAddsItToTheirBases` 8, eleven more | **exact**, every named figure |
| `XM2` | stage G | `NativeGrid.swift`'s `NativeGridSolver.serve`: `width = Swift.max(shareW, widths[cell.column])` → `width = widths[cell.column]` | **21 tests, 359 issues** — **X1** 3 and **X3** 1 plus 19 grid tests: `theGridProbeCorpusAgreesCaseByCase` 144, `aFiniteProposalServesGroupsWithSharesAndCommits` 63, `theModelsDisagreementsWithSwiftUIArePinned` 23 | **exact** |
| `XM4b` | integration | `Text.swift`'s lowered leaf de-unified: `proposalTextMeasurement` replaced inline by `cache.shaped(…).widestLine` with no `min(proposal, …)` | **`aLoweredTextAndAProposalTextSizeOneGridColumnIdentically` alone, 3 issues** | **exact** |

`XM2` is the one §6 skipped ("`XM1` and `XM2` are the two halves of `X1`'s seam
and `XM1` was"). It is also the grids track's single most central line, so it
was taken here rather than inherited: both halves of the seam are now measured
in the same round, and each reddens `X1` on its own.

### Pixels, from a harness built a third time

`CN-R`'s harness is a scratch artefact, so it was written again from the recipe
— not copied from §6 — as a `DEMO_PIXELS_OUT`-gated test in `MetalUITests`
(which already depends on `MetalUIDemoContent`, `LR-S`), rendering through a
real `Window` over `FakePlatformWindow` and writing raw BGRA plus a scene dump.
Twelve images on three separately built `git archive`s: `cb2e708`, `ac1ad1d`
(`feat/grids`' head) and `80a9f9a`.

**Controls first, on both the base and the head.** Every one reproduces §3's
figure: light vs dark f0 **1 048 576**; f0 vs f3 **0**; f0 vs modal
**1 030 498**; f0 vs animation **210 027**; preview light vs dark **1 048 576**;
`small560-default-light` vs `small560-preview-light` **171 670** at the head and
**178 634** at the base; **544** distinct pixel values in `default-light-f0`.
That the same six figures fall out of a harness written independently is what
says it is the same instrument.

| pair | reading |
|---|---|
| `cb2e708` → HEAD, the nine legacy images | **0** each, scene dumps byte-identical |
| `cb2e708` → HEAD, `preview-light` and `preview-dark` | **7 680** each, bbox **(624, 865)–(795, 920)** |
| `cb2e708` → HEAD, `small560-preview-light` | **52 033**, bbox **(0, 63)–(559, 497)** |
| HEAD vs `feat/grids`, all twelve | **0**, every scene identical |

§3 and §6 to the pixel and to the bounding box, third instrument. The bbox is
172 × 56 and 7 680 = 4 × 80 × 24, the preview grid's four cells.

No real-window capture: the gate is unchanged and the offscreen half is what
this round could take.

### The one defect, and one wording fix

1. **`docs/superpowers/2026-09-17-grids-decisions.md`'s header was stale.** It
   read "Ids are lettered, `GR-A`…`GR-AS`; next unused is `GR-AT`" while the
   file's own last section is `## GR-AT`, appended by the closing docs round in
   `ac1ad1d`. `CLAUDE.md`'s ruling table and the spec both already read
   `GR-A`…`GR-AT` / next `GR-AU`, so the decisions doc — the authority for its
   own namespace — was the only document with the wrong answer, and the next
   round to append would have reused `GR-AT`. Corrected, with the rule that a
   round appending a ruling moves that line in the same commit.
2. **§1's "the 'None was green.' sentence is gone" is not what the grep says.**
   One occurrence survives, at `docs/record/22-grids.md:1091`, as the quoted
   erratum that replaced it. The claim's substance holds — the tally is
   corrected in both documents — but a reader checking it by grep reads one hit
   and concludes the fix did not land. Reworded to say which hit survives and
   why.

**Nothing else was refuted.** Every number §1–§6 states and this round could
re-take came back identical, including the two that a reader would most expect
to have drifted: the guard census and the twelve-image bounding boxes. One claim
this round set out to refute and could not — `CLAUDE.md`'s new human-verification
row saying "the offscreen and real-window captures both read the delta as exactly
those four cells" — is supported: the track's **lane 4** capture at `12d4b28`
reads the preview window at **30 720** device pixels, bbox (1248, 900)–(1591,
1011) = 4 × 160 × 48 at scale 2 = the same four cells (record §22). The lane-1
capture at `a2c1216`, which reads 0, predates the preview grid (`f0e72b1`) and is
not the one the row cites.

## 8. The third merge (2026-09-22) — `feat/review-fixes`' portable-`Scene` line

A separate line of work had landed on `master` while stages 2 and G ran:
`3d184d8`, carrying the portable `MetalUIScene` module (record §20, rulings
`PS-`), the SDL GPU replay experiment under `Experiments/SDLGPU/`, CI changes, a
Swift 6.4 requirement, and a root `CLAUDE.md` cut to rules only with its
long-form content moved to `docs/record/19-claude-md-full-2026-09-21.md`. Both
lines descend from `cb2e708`.

**Conflicts: three, all documentation** — `CLAUDE.md`, `AGENTS.md`,
`docs/record/README.md`. No source file conflicted: the two lines touch
different modules (`MetalUIScene`/`MetalUIText`/`MetalUIRender` against
`MetalUILayout`/`MetalUI`).

**Resolution.** `CLAUDE.md` keeps the other side's rules-only structure and its
`MetalUIScene` rules (the ten-target list, the `PS-A` import constraint, the
workflow token budget) and re-acquires this side's stage 2 and grids rules: the
`LR-`/`GR-` prefix rows, the stage-2 item-lowering paragraph, the `Grid`/
`GridRow` bullet and vocabulary, the twelve-case kernel enum, the 13 + 13
registrars counted by type, the depth-guard amendments, the empty `SA-N` list,
the animated-structure snap and four practice bullets. Every number in it was
**re-measured on the merged tree**, not copied from either side.

**Record renumbering.** Both lines added `19-*.md` and `20-*.md`. The other
side's two were already published, so they keep their numbers and this side's
three moved: `19-engine-replacement-stage-2.md` → `21-`, `20-grids.md` → `22-`,
`21-integration-stage-2-grids.md` → `23-` (this file). Every `§19`/`§20`/`§21`
citation written by this side was repointed across `Sources/`, `Tests/`,
`docs/` and the two root READMEs; the other side's `§19`/`§20` citations were
all filename references in `docs/record/README.md` and stayed.

**Where the long-form tables went.** `19-claude-md-full-2026-09-21.md` is frozen
at `cb2e708`, so it does not carry this integration's rows. The divergence rows
were already in record §04; the inert rows and the two human-verification rows
were only in the old root `CLAUDE.md`, so they were appended as dated sections to
records §05 and §03. `CLAUDE.md` now says which copy is current.

**Counts on the merged tree** (`swift package clean`, `swift build
--build-system native --build-tests`, unfiltered `swift test --build-system
native --no-parallel`): **`Test run with 1550 tests in 1 suite passed`**, 97
goldens (`git diff --name-only cb2e708 HEAD -- '*.json'` empty), **77** guards.
1550 = 1409 (stage 1) + 139 (stages 2 and G) + 2 (`SceneBoundaryCompileGuards`);
77 = 71 + 4 (`GridCompileGuards`) + 2 (`SceneBoundaryCompileGuards`). 0
`error:`, and the only `warning:` is SwiftPM's `--build-system native`
deprecation notice.
