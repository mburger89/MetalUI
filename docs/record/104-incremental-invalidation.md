# 104 — Incremental invalidation (C14)

Branch `perf/incremental-invalidation` from `f6f865c1`. Not a plan task: item C14
of the gpui-gap priority list (user request 2026-10-02), requested by MetalCreator
(gap PERF-b). Spec `docs/superpowers/specs/2026-10-13-incremental-invalidation-design.md`;
rulings `IV-A`…`IV-Q` (`IV-L`, `IV-M` are the critic's; `IV-N`, `IV-O` are lane 1's; `IV-P`, `IV-Q` lane 2's) in `docs/superpowers/2026-10-13-incremental-invalidation-decisions.md`
(next unused `IV-R`); probes `docs/probes/swiftui-incremental-invalidation.swift`,
`docs/probes/swift-observation-nested-scopes.swift`, `docs/probes/incremental-invalidation/`.
Divergence labels reserved: 345–354 (346 planned; 345 refuted and unused, `IV-L`).

**Status: SLICE 1 BUILT (both lanes verified `ok`, record phase written).** Lane 1 the layout memo (§4), lane 2 the
`.equatable()` content memo (§5), sequential; §6 is the merge and the close-out counts, §7 what is carried.
Merged with master `d279f34d` (records 101, 103, 105, 106, 107 are parallel branches; 104 was free and is kept).

## §1 The measurement (design phase, `f6f865c1`)

`Tests/MetalUITestingTests/IncrementalInvalidationBaselineTests.swift`,
`oneObservedLeafChangeRebuildsTheWholeWindow(levels:)` (2, 3, 4): a 3-ary tree of
`Component`s, one observed leaf written per frame, 2 warm frames then 4 counted.
Per frame, at 81 leaves: 1 build, **81 leaf and 40 branch bodies**, 81 leaf measures,
832 layout-cache hits, 337 misses, 162 text-system measures, 81 `placeGlyphs`, atlas
upload only for the new digit's glyph. At 27: 27/13 bodies; at 9: 9/4.

Re-taking it: `swift test --build-system native --no-parallel --filter
oneObservedLeafChangeRebuildsTheWholeWindow` prints `IV baseline L=…` lines; after
lane 2 the same tree with `.equatable()` is test 2.1. The phase-timing instrument is
`docs/probes/incremental-invalidation/phase-timing.patch` (README there has the
table and the sample's reading): at 81 leaves build 51%, layout kernel 19%, prepaint
10%, paint 14%, sweeps 6%; content getters 21% of build; no hot spot.

Counts at the design commit: `swift test --build-system native --no-parallel` unfiltered
reads **3567 tests in 3 suites** (3566 + the baseline test), all passed, `FR-J no-argument
frame: succeeded=true`, 0 `error:`, the only `warning:` SwiftPM's deprecation notice.

## §2 The probes

`swiftui-incremental-invalidation.swift` (hosted `NSHostingView`, macOS 27, three
runs identical except one arm noted unexplained in its header): bodies re-run exactly
for readers (R, T, O, ES); equal plain-value or same-instance inputs skip (S, U, V);
`.equatable()` with a custom `==` skipped the plain-value view and not a closure or
fresh-class-instance view on the first bump only (S2/S3 refute a divergence, `IV-L`); a custom `Layout` re-measures every
sibling on a colour change (L-colour). `swift-observation-nested-scopes.swift`
(Swift 6.4): access lists merge upward; the per-scope token gives one live session.

## §3 Design (summary; the spec is the document)

Slice 1 = layout memo by structural signature (automatic) + `.equatable()` content
memo (opt-in) with a per-memo getter session; both leave every phase and channel
running on an equal value, so no existing behaviour moves. Retained subtrees (the
build recursion, prepaint, paint) are carried as C14-b with the design ruled
(`IV-H`). GT-F: `drawText` stays deferred (`IV-I`), re-taken at C14-b.

## §4 Lane 1: the layout memo (built on `f6f865c1`)

**What landed.** `LayoutMemo` (`Sources/MetalUILayout/LayoutMemo.swift`, `package`), a window-owned
table in `AnimationStore` next to `rasters`, keyed by a 128-bit structural signature
(`LayoutTree.nodeSignature`: one pre-order walk with an explicit stack and a reverse-order hash,
at the start of every `computeNativeLayout`/`measureNativeLayout`; no node id enters). (M) in
`measureNative` after the run cache; (P) in `runNativeLayout` before placement, keyed
`(signature, proposal, bounds)`. Keyed leaves: plain `Text` and `ProposalText`
(`TextLeafKey`), `Divider`, the four built-in shapes, `Rectangle`, the gradient leaf and
`GPUSurface` (`LayoutLeafKeys.swift`); every other leaf is unkeyed and taints exactly its
ancestors. `LayoutMemo.verifies` (`METALUI_VERIFY_LAYOUT_MEMO=1`, read once) recomputes
every hit fresh and traps `(IV-J)`. New counters: `NativeLayoutWork.memoHits/memoMisses/
memoRootHits/signatureNodesHashed`; `FrameWork.layoutMemoHits/layoutMemoMisses/
layoutMemoRootHits/layoutSignatureNodes` (census 3462 -> 3466; no map row, `FrameWork.swift` is
covered by the harness regex). Five amendments to `IV-E` are `IV-N`; GT-F is `IV-O`.

**Counted results** (`FrameWork`, `HarnessWorkTests`, hand-predicted before each run; the
memo-off arm in each test is the separating control):

| tree, change | before (`f6f865c1`) | after lane 1 |
|---|---|---|
| N moving `.offset` labels over a `GPUSurface`, per frame | N+1 measure calls, N+2 misses, 2N seam measures | **0 / 0**, root hit 1, N seam measures (paint's), N `placeGlyphs` |
| 81 leaves, one text changes, per frame | 81 measure calls, 337 misses, 162 seam measures | **1** measure call, misses within 2(L+3), seam measures 82 (paint measures all 81) |
| warm drag (`aWarmDragLoopCountsLayoutWorkPerFrame`) | 1 / 6 / 78 / 67 | 1 / 0 / 0 / 0; press frame 1 / 0 / 44 / 25 |
| main demo, warm frame, shaping-cache lookups | 110 | 58 (cold frame 1020 / 1544 unmoved) |

**Signature-pass share** (release, macOS arm64, other workflows running, so the readings are
noisy): at 202 nodes the pass cost 0.08-0.16 ms per frame against a layout phase of 0.46-0.70 ms
with the memo on (0.61-1.04 ms off) and a render of 3.5-5.4 ms: 2-4 % of render, about 15-25 %
of the memo-on layout phase. In 3 of 4 pairs the pass was below half the layout time the memo
saved; one pair was inside noise. **The time win is not claimed; the counted win is exact.** After
those readings the pass hashes small enums as integer tags instead of through `Hasher`
(`d249d471`); that was not re-timed (a release build costs 15 minutes on the loaded machine).
Instrument: `docs/probes/incremental-invalidation/phase-timing.patch` plus a timer in
`prepareMemo`; `signatureNodesHashed` is pinned at the reachable node count by the work pins
(120 and 71 in the two list pins).

**Moved pins** (each re-derived; see `IV-N`): `aWarmDragLoopCountsLayoutWorkPerFrame` (literals above),
`theOverlayCostIsLinearAndCounted` (GT-F, `IV-O`), `aListsWorkIsTheSameFor160RowsAsFor40` and
`aVariableListsWorkIsTheSameFor160RowsAsFor40` (`NativeLayoutWork ==` gained fields: 112 / 120 and
0 / 71 measured, the three old counts unmoved because each frame there is cold),
`theDemoDoesTheSameTextWorkAsBefore` (warm lookups 110 -> 58). Lane 0's baseline test and
test 1.2 now call `setNeedsRedraw()` after an `@Observable` write: off macOS the observation hop is
asynchronous (`HT-I`), which the Linux image showed (`w.count == frames`); fixed in both.

**Red lines first.** The window tests' memo-off arms read the old numbers (N+1 / N+2 / 2N;
81 / 337 / 162) and the work pins read them at `f6f865c1`; the kernel tests have no red-before
(`IV-M` 3 says the test that does not compile is red by its stub; here the tests were written
after the code, so each is verified by mutation below instead).

**Mutation table** (every mutation committed first, applied to the file named, restored from a
copy, the **full unfiltered** suite run, `git status --short` empty after; names are the
reddened tests; an AppKit sheet issue is the locked-screen `CI-AF` five, present in every run):

| # | declaration and spelling | reddened |
|---|---|---|
| M1 | `placeFromMemo` returns `false` first line (LayoutTree.swift) | `aSteadyOffsetFrameMeasuresNothing` (both N), `aRootPlacementHitEqualsAFreshRun`, `aRootPlacementHitRestoresMeasuredWidths`, `aWindowResizeMissesByProposalAndAScaleChangeDoesNot` (its scale arm), `theOverlayCostIsLinearAndCounted` (both N). **Not reddened: `aWarmDragLoopCountsLayoutWorkPerFrame`** (it separates memo-on from memo-off, not (P) from (M)) |
| M2 | `TextLeafKey.init` stores `""` for `string` (LayoutLeafKeys.swift) | suite truncated by the `verifies` trap in `aMemoHitEqualsAFreshLayoutBitForBit`; a filtered re-run reddens `oneChangedTextRemeasuresOnlyItsPath` (6 issues, all three levels) |
| M3 | `leafKeys[index] ?? AnyHashable(0)` for a missing key; a `[LayoutNodeID: Int]` member on `LayoutMemo`; `newNativeLeaf(key:)` made `public` | `anUnkeyedLeafTaintsOnlyItsAncestors` (3 issues), `theMemoHoldsNoNodeID`, `thePlainImportCannotReachTheMemo`, plus 240 stale-answer issues in grid, list, overlay and stack tests (a constant key matches everything) |
| M4 | `frame.maxHeight` dropped from the `.frame` hash; spacer mark replaced by `0`; grid cell hashed by node index instead of position | `everyRegistrarParameterIsInItsSignature` (named arm `frame.maxHeight` only), `aSpacersSignatureCarriesItsStacksAxis` (2), `aGridRowMarkIsNormalisedNotHashedAsAToken` (1); **`aMemoHitEqualsAFreshLayoutBitForBit` stays green under the `frame.maxHeight` omission** (its script has no `maxHeight`: the table is the instrument) |
| M5 | `MeasureKey` built with `ProposedSize()` in `lookup` and `store`; `scale` added to `TextLeafKey` | run truncated by a non-finite-rect trap in `theDemoFrameMatchesTheValuesRecordedOnMacOS`; filtered re-runs: proposal ignored traps `aWindowResizeMissesByProposalAndAScaleChangeDoesNot`, scale in the key reddens its scale arm (2 issues) |
| M6 | `roundNativeStoredRects(root)` skipped after a placement hit | `aMemoHitEqualsAFreshLayoutBitForBit` (36), `aRootPlacementHitEqualsAFreshRun` (9), `aRootPlacementHitRestoresMeasuredWidths`, `aSteadyOffsetFrameMeasuresNothing`, `aWindowResizeMissesByProposalAndAScaleChangeDoesNot`, `aProposalPathPopoverPresentsPlacesAndDismisses`, `theOverlayCostIsLinearAndCounted` |
| M7 | `LayoutTree.memo` initialised to `LayoutMemo()` | `aGridsWorkAtFiniteProposalsIsOneLeafCallPerDistinctProposal` (2), `aGridsWorkAtNilIsOneLeafCallPerDistinctProposal`, `aLargeColumnCountCostsTheKernelOnePassPerColumn` (the bare-tree work pins; `aColdMemoCountsAsTheOldRunDid` does not separate this, it pins the window's cold frame) |
| M8 | placement restore order reversed; `run.work` not restored in `verifyMemoHit` plus its first `precondition` made vacuous | `aRootPlacementHitEqualsAFreshRun` (8), `verifyModeDoesNotChangeTheCounters`, and twenty-odd window tests that read placements; **`aVerifiedHitThatDiffersFromAFreshMeasurementTraps` stayed green** because the placement check traps too; a filtered run with both preconditions vacuous reddens it (2 issues) |

**Verify-mode suite run (test 1.12).** `METALUI_VERIFY_LAYOUT_MEMO=1` over the whole suite: **0
verification traps**, the suite completed. The first run's only extra issues were the four pins that
count seam measures (recomputation measures again); they now stand aside under the variable, and the
re-run at the final commit reads the five AppKit issues only.

**Fourteen images.** `docs/probes/demo-pixels/compare.sh <scratch> f6f865c1 HEAD` (HEAD `ac80c917`,
controls as recorded): 14 of 14 `differing=0`, scene identical.

**Linux image (`swift:6.4-noble`).** `MetalUILayoutTests` 208 and `MetalUICoreTests` 22 pass;
`MetalUITestingTests` 130 and `MetalUICrossPlatformTests` 79 pass (after the observation-hop fix
above; before it, 6 issues in the two observed-leaf trees). `Backends/SDL` untouched; its
Linux-image run (`metalui-portable`) reads 30 + 121 passing.

**Counts** (final commit, `swift build --build-system native --build-tests`, then
`swift test --build-system native --no-parallel` unfiltered): **3583 tests in 3 suites** (3567 at the
design commit + 16: kernel file 11 incl. the exit test, window file 6 incl. 1.1 and 1.2 as two
parameterised tests counted by cases, guard 1.13), exactly the five locked-screen
`AppKitPresentationTests` sheet issues and nothing else, `FR-J no-argument frame: succeeded=true`,
0 `error:`, the only `warning:` SwiftPM's deprecation notice; `swift build --build-tests` (default
build system) 0 warnings; one new typecheck guard (1.13). The verify-mode run at the same commit:
3583 tests, the same five issues, 0 verification traps.

**Carried.** C14-b retained subtrees (`IV-H`); lane 2 landed, §5. Keys for rich text, images,
`Canvas` and controls (each one line plus a covering test). A subtree placement memo (a moved
subtree's rects need the same arithmetic as a fresh placement; spec §4.1). The list-row leaves are
unkeyed, so a `List` window gets no memo. The release timing of the integer-tag signature stream.

## §5 Lane 2: the equatable content memo (built on `415c7fbd`)

**What landed.** `Component.equatable()` (`where Self: Equatable`) returning
`EquatableComponent<Self>` (`Sources/MetalUI/EquatableComponent.swift`, no initialiser, no identity
level, no cursor index); `ContentMemoStore` (`ContentMemo.swift`, `package`, hosted as
`StateTable.contentMemos`, swept by the last line of `StateTable.sweep()`); `Component`'s
`requestGroupLayout` split into `enterComponent`/`finishComponent` with the bare path unchanged in
order; `StateTable.entryVersion` (a monotonic counter bumped by `write` and `withState`);
`StateBinder.memoShape` (the `@State` ordinals; `@Environment`/`@FocusState` refuse, via the
`BindableFocusState` marker); one observation session per memo over the getter only, with a
serial-checked `onChange` that reports through `markDirtyFromObservation`; `FrameWork`
`contentEvaluations`/`contentSkips`/`contentRefusals` (census 3466 -> 3476); the demo
(`METALUI_INVALIDATION_DEMO=1`, `InvalidationDemo.swift`, its own function, in
`DemoStackBudgetTests`); divergence 346 (`@Environment`; probe arms `E0`/`E-env`/`E-env2`, separating
`EnvQuiet`); inventory family `equatable-component` (class A) and one `M` row. Six amendments are
`IV-P`; the mutation findings are `IV-Q`. `Backends/SDL` untouched.

**Counted result** (test 2.1, one leaf written per frame, every component `.equatable()`):

| tree | bodies evaluated per frame, before | after |
|---|---|---|
| 3 levels: 27 leaves + 13 branches | 27 + 13 | **1** leaf, 0 branches; 39 skips |
| 4 levels: 81 leaves + 40 branches | 81 + 40 | **1** leaf, 0 branches; 120 skips |
| demo, one bump (`theInvalidationDemoEvaluatesOneGetterToTheOtherTreesHundredAndTwentyOne`) | 121 | **1** |

Build recursion, prepaint and paint stay whole (spec §2); only the getters are saved. Not timed.

**Red first** (commit `24246005`, against an evaluate-always stub; first lines, the filtered run):
2.1 `IVStats.leaves == frames`, `branches == 0`, `contentEvaluations == frames`,
`contentSkips == frames * (components - 1)` at L = 2, 3, 4; 2.2 `leaves == 0`, `== 1`, `== 1`; 2.3
`leaves == 0`, `== 1`, `== 2`; 2.4 `branches == 0 && leaves == 0`, `branches == 1`, `leaves == 0`,
`contentEvaluations == 1 && contentSkips == 3`; 2.6 `branches == 0`, `== 1`; 2.7 `entryCount == 1 &&
armedSessions == 1`, `leaves == 0`, `armedSessions <= entryCount && entryCount == 1`; 2.8 `leaves == 0`,
`entryCount == 1`; 2.9 `skipped > 0` (the differential itself stayed equal: the stub is correct, just
unskipped); 2.10 `contentSkips > 0`. Green against the stub, as controls: 2.5 (the refusal is
counted), 2.11b, 2.13. 2.11a's first fixture was wrong (a `public func` over an internal type) and is
fixed in that commit. 2.7b and the quiet-frame count of 2.10 were added after `IV-Q`.

**Mutation table** (each committed first, applied to the file named, restored by `git checkout`, the
full suite run with the seven hanging AppKit sheet tests skipped (see counts), `git status --short`
empty after each; names are the reddened tests):

| # | declaration and spelling | reddened |
|---|---|---|
| A | `ContentMemo.swift` hit condition gains `&& false` (never hits) | 2.1 (12), 2.2 (3), 2.3 (3), 2.4 (4), 2.6 (2), 2.7, 2.8, 2.9, 2.10, demo test |
| B | `onChange` body replaced by `_ = 0` (no session effect) | 2.2 (2), 2.9 (12), 2.1 (9), 2.13, demo test |
| C | recorded `@State` versions not compared (`true`) | 2.3 (2), 2.9 (8), 2.10 (2) |
| D | `previous == component` replaced by `true \|\| ...` | 2.4 (3), 2.6 (3), 2.1 (12: its `==`-false arm now hits), 2.9, demo test |
| E | `!shape.refused` replaced by `true` | 2.5 (3) |
| G | `guard entry.serial == serial` replaced by `_ = serial` | **2.7b only** (`runUntilIdle`: still drawing after 64 rounds); the spec's 2.7 loop stayed green (`IV-Q` 2) |
| H | every entry's token written at `endFrame` (a per-frame flush) | 2.8, 2.7 (not idle), 2.1 (12), 2.2, 2.3, 2.4, 2.6, 2.9, 2.10 |
| I | pristine copy re-taken after `finishComponent` (`repristine`) | **2.10 only** (5 issues); 2.9 stayed green (`IV-Q` 3) |
| J | entry keyed by `(constant id, type)` | 2.1 (12), 2.4 (3), **2.10** (the quiet-frame count), demo test |
| K | `entry.touched = true` removed from the hit path | 2.8, 2.7, 2.1 (12), 2.2, 2.3, 2.4, 2.6, demo test |
| L | `EquatableComponent.init(component:)` made `public` | 2.11a |
| M | an unconstrained `public func equatable() -> Self` overload | 2.11b |

The first G and J runs (before 2.7b and the quiet-frame count existed) were the findings of `IV-Q`:
G reddened nothing and J reddened no 2.10 pin. The existing `ComponentTests` mutations (the two
recorded in `Component.swift`) are not re-run here: `requestGroupLayout` is the same two halves in
the same order, and the bare path's tests all passed unfiltered (`IV-M` 2.12 is not a test).

**Fourteen images.** `docs/probes/demo-pixels/compare.sh <scratch> f6f865c1 HEAD` (HEAD `b8506dfe`,
controls as recorded): 14 of 14 `differing=0`, scene identical.

**Linux image (`swift:6.4-noble`).** `swift build --build-tests` then `swift test --skip-build`, parallel
and `--no-parallel`: `MetalUITestingTests` 142, `MetalUICoreTests` 22, `MetalUILayoutTests` 208,
`MetalUICrossPlatformTests` 79, the three small ones 9, 40, 25: all pass. Two findings, both from
the first run: (1) a main-actor test does not run on the main thread there (`Thread.isMainThread` is
false), so every `onChange` takes the hop, `armedSessions` lags a frame and **even a plain window does not
idle after a tracked frame** (measured with a window of one `Text`: `observationDirtyings` 6 after 6
drawn frames, `runUntilIdle` throws); the two tests that count sessions or idle frames (2.7, 2.7b) are
`.enabled(if:)` Darwin; (2) the `async` tests interleaved at their `await`s under the default parallel
run and corrupted `IVStats`; they now count in their own `MemoStats` behind a main-actor FIFO gate.
Windows CI runs the same two paths and is not run here.

**Counts** (`swift package clean`, `swift build --build-system native --build-tests`, then
`swift test --build-system native --no-parallel --skip-build`): **3591 tests in 3 suites passed**,
`FR-J no-argument frame: succeeded=true`, 0 `error:`, the only `warning:` SwiftPM's deprecation notice;
`swift build --build-tests` (default build system) 0 warnings. **Not an unfiltered run**: the machine's
screen was locked and the display asleep, and `NSOpenPanel.init()` in the seven `AppKitPresentationTests`
tests that present a sheet hangs there (sampled twice: `AppKitWindow.presentFileDialog` -> `NSOpenPanel
__allocating_init`, 0 % CPU), so those seven were `--skip`ped by name (the earlier locked-screen runs
read them as the five `CI-AF` issues; a `caffeinate -d` woke the display and did not cure it). 3591 run + 7 skipped = 3598 in a screen-unlocked run (lane 1's 3583 + the window file's 12 functions, 2.1 counted by its three cases, +2 guards, +1 demo test, within 2 of that sum; the difference was not chased). Typecheck guards: two new (2.11a, 2.11b), each
mutated red once (L, M).

**GT-F.** Unchanged by this lane (`IV-O`): `theOverlayCostIsLinearAndCounted` passes in the full run;
`drawText` stays deferred and is re-taken at C14-b's close-out.

**Carried.** C14-b (retained subtrees, `IV-H`); C14-c (an environment epoch, divergence 346);
`@Environment`/`@FocusState` components stay refused; per-row `List`/`ForEach` scopes (C14-d); the
memo's cost (the `==` comparison and the pristine copy) is not timed; the demo's real window and
human checks IV1-IV4 (spec §10) are not run (screen locked; an agent cannot).

## §6 The merge and the close-out (record phase)

**Merge.** `origin/master` had moved to `d279f34d` (52 commits: §101 material follow-ups, §103 guides, §105
performance baselines, §106 `runUntilIdle()` on Linux, §107 guides follow-up). The merge was clean (no
conflict); records 101, 103 and 105-107 are parallel branches and **104 was free, so it keeps its number**.
Divergence 346 stands (master took 315, 325, 326). The census file was re-recorded after the merge for master's
line shifts and growth: **3492** declarations (master's 3476 at the merge base's line plus the branch's 16:
the four layout-memo and three content-memo `FrameWork` fields are covered by the harness regex and moved no
row; the rest is master's), `closeout-inventory-check.sh` and `closeout-undocumented.sh` print nothing.

**Counts** (`swift package clean`, `swift build --build-system native --build-tests`, then
`swift test --build-system native --no-parallel --skip-build --skip AppKitPresentationTests`): **3654 tests in 3
suites passed** (211 s), `FR-J no-argument frame: succeeded=true`, 0 `error:`, the only `warning:` SwiftPM's
deprecation notice; 0 recorded issues. **Not an unfiltered run, and why:** the screen was locked
(`CGSSessionScreenIsLocked = 1`), and the unfiltered run hung with the process at 0 % CPU after
`aMenuBarThePlatformDeclinesIsDrawnAndDrivenThroughTheTree`; `sample` read `AppKitWindow.presentFileDialog` ->
`NSOpenPanel.init()`, the same hang lane 2 found (§5), so that run was killed by its PID and the suite re-run with
`AppKitPresentationTests` (9 `@Test`s) skipped. The expected unfiltered count is **3663** (3654 + the suite's 9 `@Test`s; cross-check: master's 3631 is
+65 over the 3566 base and the branch alone was 3598, +32); re-take it on an unlocked screen. Typecheck guards **232** by derivation (master's 229 + lane 1's 1.13 + lane 2's 2.11a and
2.11b; the log carries no guard total), each new one mutated red once (§5 L, M; lane 1's by the lane verdict).
`swift build --build-tests` (default build system) at this commit: `Build complete`, 0 `warning:`.

**Not re-taken at the merge:** the fourteen images (the branch's last 0 px reading is §5, against `f6f865c1`,
before master's material work, which legitimately moves the material images' own history and is §101's to
compare); `Backends/SDL` and the Linux image (both lanes ran them; the merge touched no `Backends/SDL` or
portable target); the verify-mode run over the merged suite (§4's reading was at the lane commit).

**Verdict findings carried from the lane checks (minor, all documented, none changes behaviour):**
(1) `PlacementKey.bounds.height` is redundant under `computeNativeLayout(centredIn:)` (the only caller that
attaches a memo), so forcing it to 0 reddens nothing; the public `in:` variant would need it; owner: a kernel arm
with equal proposals and different bounds, if a second caller ever attaches a memo. (2) `TextLeafKey.alignment`
reddens nothing when dropped: the measured size is probably independent of alignment, so the field is
over-conservative, not missing; owner: a test measuring with two alignments, then drop the field. (3) lane 1's own
weak spots stand (`aWarmDragLoopCountsLayoutWorkPerFrame` does not separate (P) from (M); the release timing of the
integer-tag signature is not re-taken).

## §7 Carried, with owners

| item | why | owner |
|---|---|---|
| retained subtrees: skip the build recursion, prepaint and paint of an unchanged subtree | the numbers: build 51 %, prepaint 10 %, paint 14 % of a frame stay whole (§1); needs a per-scope observation token and the sweep rules of `IV-H` | C14-b |
| an environment epoch, so `@Environment` readers can skip (divergence 346) | `EnvironmentValues` cannot compare old and new | C14-c |
| per-row scopes for `List`/`ForEach`; the list-row leaves carry no key | `List` windowing and TB-AH stay untouched | C14-d |
| keys for rich text, images, `Canvas`-like and controls' leaves | one line plus a covering test each | follow-up of C14 |
| a subtree placement memo (a moved subtree's rects) | spec §4.1 | C14-b |
| `MetalDrawContext.drawText` and its SDL twin | GT-F re-taken: the overlay cost is still 1 measure + 2 seam + 1 `placeGlyphs` a label (`IV-O`); re-take at C14-b | C14-b close-out |
| release timing of the signature pass and of the content memo's `==` and pristine copy | a release build costs 15 minutes on the shared machine; the win is claimed as counted only | C14-b |
| the real-window demo and human checks IV1-IV4 | the screen was locked for the branch; an agent cannot | a human, `docs/verification/human-checks.md` group IV |
| the unfiltered suite count and the fourteen images on the merged tree | locked screen (NSOpenPanel hang); material work merged beneath | the merge checker |

