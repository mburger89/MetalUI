# 119 — Layout and build allocations (P2)

Branch `perf/layout-allocations` from `6273e3a4`. Not a plan task: item P2 of the gpui-gap list (user request 2026-10-02), from the
2026-10-13 release profile (`/private/tmp/claude-501/profiling/REPORT.md`) and record §111 §8 "carried" until C14b-2 (§110) merged.
Spec `docs/superpowers/specs/2026-10-14-layout-allocations-design.md`; rulings `PA-A`…`PA-R` in
`docs/superpowers/2026-10-14-layout-allocations-decisions.md` (next unused `PA-S`). Divergence labels reserved 495–504: **none
taken**. No public declaration (inventory and undocumented scripts print nothing, census unmoved), no human check.

**Status: LANDED (both lanes verified `ok`; Record phase merged master `298c23d4` (§118 pan rasters, `PN-`); master's last record
was 118, so 119 held.)**

## §1 What changed

Every change is value-identical: the fourteen offscreen images read 0 px against `6273e3a4`, scenes identical, every layout work
counter (`measureCalls`, `cacheHits`, `cacheMisses`, `memoHits`) and `FrameWork` pin unmoved, `DemoFrameDeterminismTests`' Expected
unedited.

Lane 1, `Sources/MetalUILayout` (`PA-B`…`PA-D`, `PA-F`, `PA-K`):

- `roundedRect(_:)`, an internal scalar; `roundLayout` forwards to it and `roundNativeStoredRects` calls it, so a node no longer
  allocates a one-element array (812 allocations per bracket frame).
- `LayoutTree.graft` reserves geometrically (`capacity < need` then `max(need, 2 * capacity)`) for `childLists`, `layouts`,
  `measuredWidths` and the Int-keyed dictionaries; `preorder` reserves (`PA-C`).
- `leafKeys` stores a `LeafKey` (key, type id, two hasher words) computed at registration; `nodeSignature` mixes the same words
  in the same order, so every signature is unchanged and a grafted leaf is hashed zero times (`PA-D`).
- `solveLinearStack`: a single-priority fast path (no `Set`, no sort, no `reserved` pass), flexibilities in an array by member
  position, reserved `members`/`order`; the `measureNative` calls keep their order and arguments (`PA-F`).
- `NativeMeasurementKey` and `LayoutMemo.MeasureKey` hash one folded word (`ProposedSize.foldedHashWord`), `==` unchanged and
  complete (`PA-K`, kept by the A/B of `PA-N`).

Lane 2, `Sources/MetalUI` (`PA-E`, `PA-G`, `PA-H`, `PA-I`, `PA-R`):

- `StateTable.mark` writes through `index(forKey:)` and `storage.values[index]`, avoiding the `Dictionary.subscript.modify`
  coroutine frame.
- `ForEach.produceElements` reserves `seenIDs`, `nodes` and (floating-point ids) `seenNames`; names and keys byte for byte (`FI-B`,
  `FI-K`).
- `planLegacyItems`/`registerLegacyItems` reserve and the weights chain is one loop; the two `children.map { consume }` sites,
  `retainedVersionsUnchanged` (two `allSatisfy`) and `finishRetainedPaint`'s `filter`/`allSatisfy` are plain loops (the profile's
  remaining isolation sites).
- `retainedAmbientKey` reserves 64 before its `+=` chain (the struct reshape is C14-c's, `PA-I`).

`Package.swift`: only `MetalUILayoutTests` gains a `MetalUITestSupport` dependency (`PA-L`); `Tests/MetalUITestSupport/AllocationCounter.swift`
(`countAllocations`, Darwin only) is new. `MetalUILayout` still imports only `MetalUICore`.

## §2 Measurements (dated 2026-10-14, release, headless, shared Mac)

Re-measure at `6273e3a4` before the work (spec §1), allocations per frame with `PROF_ALLOC=16` (malloc_logger, main thread):
bracket-value 7,659, orbit 5,934, pan 19,468, demo 2,150, list-fixed 1,248 (the 2026-10-13 profile read 12,065 / 11,412 / 20,431 /
2,676; P1 and C14b-2 had already removed 20–48 %). Base against lane 2's head (lane 2 includes lane 1), allocations per frame:

| Scenario | base | head | change |
|---|---|---|---|
| bracket-value | 7,722 | 5,941 | -23 % |
| bracket-orbit | 5,934 | 4,122 | -31 % |
| bracket-pan | 19,434 | 17,582 | -10 % |
| demo | 2,150 | 1,525 | -29 % |
| list-fixed | 1,248 | 977 | -22 % |

Median ms/frame, A/B alternated five times each, no `PROF_ALLOC`, load average 20–50 (`uptime` per run in
`docs/probes/layout-allocations/ab-lane2-2026-10-14.txt`): bracket-orbit 2.40 -> 2.10 (-12 %), bracket-pan 7.09 -> 6.89 (-3 %),
demo 1.046 -> 0.940 (-10 %), list-fixed 0.670 -> 0.601 (-10 %); bracket-value reads 0 ms in the harness (unusable). Lane 1 alone
(`PA-K`, lane head against lane head + `PA-K`): demo -5.6 %, list-fixed -3.7 %, orbit -4.2 % (`ab-pak-keep-2026-10-14.txt`).
**These are dated measurements on a loaded shared Mac, not pins.** The final head-with-everything against base was not taken as one
alternating run; the two tables above are the lanes' own.

Not re-taken: `isolation-sites.py` after the loops (the sample harness needs a quiet, unlocked machine). The 1.2 % (demo) / 1.3 %
(orbit) isolation-check share of the base is **unmeasured after the change** and no claim is made on it. Owner: the next profile.

## §3 Tests and guards

No new typecheck guard (no public or phase surface). New tests, all counting work, none timing:

Lane 1 (`Tests/MetalUILayoutTests`): `theCounterSeesAKnownAllocationAndOnlyTheCallersThread` (counter's positive control and
separating arm), `roundingStoredRectsAllocatesNothingPerNode` (floor-corrected difference 0, `PA-O`), `graftingManySegmentsReallocatesLogarithmically`,
`aLeafKeyIsHashedOncePerRegistrationNotOncePerRun`, `aCachedLeafKeySignatureEqualsTheDirectOne`,
`equalMeasureKeysHashEqualAndNilIsNotZero`, `aRoundedRectEqualsTheArrayRoundingOfItself`, `aStackWithEqualPrioritiesSolvesLikeTheReference`
(a differential against a test-local copy of the old algorithm, 360 cases, `PA-P`).
Lane 2 (`Tests/MetalUITests`): `markAllocatesNothingOnASteadyFrame` (bounds one debug event a call, `PA-Q`),
`planLegacyItemsFlexWeightsMatchTheFilterMapSet`, and a `StateTableTests` liveness pin.
Allocation pins are Darwin only (`#if canImport(Darwin)`); Linux/Windows run the behavioural ones.

## §4 Red first and mutation tables

Red before the fix (commit `f4da0530`): `roundingStoredRectsAllocatesNothingPerNode` 304 vs 3004 events (50 vs 500 nodes),
`graftingManySegmentsReallocatesLogarithmically` 26 capacities, `aLeafKeyIsHashedOncePerRegistrationNotOncePerRun` 20 and 24 against
the one required. Lane 2 (`64de1650`): the mark pin read 700 at 100 calls and 7,001 at 1,000 (floor-corrected). The stack
differential passes against the old algorithm by design.

Lane 1, verifier's runs, one full unfiltered run with M3, M4 and M7 applied together (3926 tests, 89 issues: the three pins plus five
`AppKitPresentationTests` sheet issues of `CI-AF` on a locked screen, all passing unmutated):

| Mutation | Reddened |
|---|---|
| M3 exact graft reserve `childLists.reserveCapacity(need)` restored | `graftingManySegmentsReallocatesLogarithmically` |
| M4 leaf key hashed again in `nodeSignature` (direct `mixHashable` route) | `aLeafKeyIsHashedOncePerRegistrationNotOncePerRun` |
| M7 `axis == 0 ? 0 :` removed from `ProposedSize.foldedHashWord` | `equalMeasureKeysHashEqualAndNilIsNotZero` |
| M1, M2, M5, M6b, M6c, M6d (implementer's runs, not re-run by the verifier) | each reddened its named test(s) in the implementer's run |
| M6a drop the `lhs < rhs` tie-break in the flexibility sort | **nothing: survived**; an equivalent mutant while the stdlib sort is stable in practice, tie-break kept as deliberate (`PA-F`) |

Lane 2, verifier's runs (full unfiltered):

| Mutation | Reddened |
|---|---|
| `StateTable.mark`: `storage[id]?.isLive = true` restored (~7 events a call) | `markAllocatesNothingOnASteadyFrame` |
| `planLegacyItems` weights `flexGrow > 0` -> `>= 0` | the run **trapped** (`box.flexGrow.weights refused by name`) and printed no summary line; counts as reddened because the unmutated suite finishes; the implementer's filtered run named `planLegacyItemsFlexWeightsMatchTheFilterMapSet` and 20 flex-lowering tests |
| `retainedVersionsUnchanged`: in-loop `return false` -> `return true` | `aDescendantStateChangeFromAShortcutInvalidatesTheRecordByVersion`, `aStateWriteToAPlainChildRebuildsAGraftedOccurrence` |
| `finishRetainedPaint` final-scene loop `op.boundary == 0` -> `!= 0` | 681 issues in 44 tests, among them `aRetainedFrameEqualsAFreshFrameOverAScript`, `aPanOfTheWholeGraphReplaysEveryNodeAndEqualsAFreshFrame`, `aTranslatedReplayEqualsAFreshFrameAtEveryScale`, `aVerifiedGraftThatDiffersTraps`, `theBracketNodeDragReplaysEveryUnchangedSubtree` |

## §5 Suite

Record phase, merged tree (branch + master `298c23d4`), 2026-10-14: `swift package clean`, `swift build --build-system native
--build-tests` 0 `error:`, the only `warning:` SwiftPM's deprecation notice; `swift test --build-system native --no-parallel`
unfiltered **3937 tests in 3 suites passed** (338 s), `FR-J no-argument frame: succeeded=true`, 0 issues (the screen was unlocked
for this run, so the five `AppKitPresentationTests` sheet tests passed). 3937 = master's 3926 + the branch's 11 (lane 1's 8, lane
2's 3; the lanes read 3926 and 3929 on `6273e3a4`'s 3918 before the merge). Typecheck guards **246**, unmoved (no guard added; not
re-counted guard by guard on the merged tree). `swift build --build-tests` (default build system) 0 warnings is the lanes' reading
on the unmerged tree, not re-taken here. `zsh docs/probes/closeout-inventory-check.sh` and `closeout-undocumented.sh` print
nothing; census unmoved. The fourteen-image comparison, the Linux image and `Backends/SDL` were not re-taken after the merge
(master's change is a raster-cache path this branch does not touch; the branch touches no `Backends/SDL`).

## §6 Hazards

- A debug build logs **more than one event per `malloc`** and allocates twice per `for-in` turn over an array (`PA-O`): an allocation
  pin counts a **floor loop** and requires the floor-corrected difference, never an absolute number. A toolchain that changes the
  floor moves pass and floor together.
- `markAllocatesNothingOnASteadyFrame` bounds a **regression, not zero**: `Dictionary.Values`' `modify` coroutine still logs one
  event a call in debug, so a change from 1 to 1 is invisible (`PA-Q`).
- The `ForEach` and `retainedAmbientKey` reserves are capacity hints with no behavioural effect: no pin, no mutation reddens them.
  They are measured only in the allocation table above.
- `reserveCapacity` is exact in Swift, not geometric: reserve per append batch or reserve geometrically, never `base + n` per call
  (`PA-C`).
- The five `AppKitPresentationTests` sheet tests fail on a locked screen and are timing-sensitive (`CI-AF`); the mutation runs
  (load average above 100, 688 s against 374 s) hit them.
- Timings were taken at load 20–100 on a Mac shared with other workflows: indicative only.

## §7 Deferred, with owners

| Item | Owner |
|---|---|
| `AmbientKey` as a fixed-layout struct (`retainedAmbientKey` 392 allocations per bracket frame before the reserve) | C14-c's merge, then a follow-up |
| Array-indexed per-run measure cache replacing the `Dictionary` | P3, only if hashing still reads >= 5 % |
| Int-name cache for `ForEach` (`String(describing:)`) | none until a profile shows it |
| `CoverageRasterizer` allocations on pan (822 per frame) | the pan item (§118 carried P3b/P3c) |
| Text placement caches, `GlyphAtlas.packed`, `borderWidths`, animation early returns, rich-text caching (REPORT E1/E2) | the item that owns text paint |
| A re-run of `isolation-sites.py` and one A/B of base against the final head on a quiet machine | the merge |
| Pixel comparison, Linux image and `Backends/SDL` after the master merge (untouched by this branch) | the merge |
