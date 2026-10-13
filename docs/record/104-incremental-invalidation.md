# 104 — Incremental invalidation (C14)

Branch `perf/incremental-invalidation` from `f6f865c1`. Not a plan task: item C14
of the gpui-gap priority list (user request 2026-10-02), requested by MetalCreator
(gap PERF-b). Spec `docs/superpowers/specs/2026-10-13-incremental-invalidation-design.md`;
rulings `IV-A`…`IV-O` (`IV-L`, `IV-M` are the critic's; `IV-N`, `IV-O` are lane 1's) in `docs/superpowers/2026-10-13-incremental-invalidation-decisions.md`
(next unused `IV-P`); probes `docs/probes/swiftui-incremental-invalidation.swift`,
`docs/probes/swift-observation-nested-scopes.swift`, `docs/probes/incremental-invalidation/`.
Divergence labels reserved: 345–354 (346 planned; 345 refuted and unused, `IV-L`).

**Status: LANE 1 (layout memo) BUILT; lane 2 (`.equatable()`) not yet.** Two lanes follow, sequential: lane 1 the layout memo, lane 2 the
`.equatable()` content memo (spec §6). The Record phase appends §3 onward.

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

**Carried.** Lane 2 (`.equatable()`), C14-b retained subtrees (`IV-H`). Keys for rich text, images,
`Canvas` and controls (each one line plus a covering test). A subtree placement memo (a moved
subtree's rects need the same arithmetic as a fresh placement; spec §4.1). The list-row leaves are
unkeyed, so a `List` window gets no memo. The release timing of the integer-tag signature stream.
