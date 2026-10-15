# Layout and build allocations — design

Item P2 of the gpui-gap priority list (user request 2026-10-02; not a plan task), from the 2026-10-13 release profile
(`/private/tmp/claude-501/profiling/REPORT.md`), carried by P1 (record §111 §8) until C14b-2 merged (record §110).
Rulings: [`../2026-10-14-layout-allocations-decisions.md`](../2026-10-14-layout-allocations-decisions.md) (`PA-`).
Record: `../../record/119-layout-allocations.md` (Record phase). Branch `perf/layout-allocations` from `6273e3a4`.
Divergence labels reserved 495–504: **none taken**. No public declaration, no inventory row, no human check.

**Status: DESIGNED, not built. Two lanes.**

## 1 Re-measure at 6273e3a4 (2026-10-14, release, headless, load average 10–25 on the shared Mac)

Harness: `Prof` copied to `/private/tmp/claude-501/profiling/la/`, `MetalUI` symlinked to this worktree,
`PROF_ALLOC=16` (malloc_logger, main thread). Allocations per frame, base: **bracket-value 7,659; bracket-orbit 5,934;
bracket-pan 19,468; demo 2,150; list-fixed 1,248** (the 2026-10-13 profile read 12,065 / 11,412 / 20,431 / 2,676: P1 and
C14b-2 already removed 20–48 %). The reported "39 % array growth" now reads 44 % (bracket) and 42 % (demo).

Attribution by the innermost MetalUI frame (allocs/frame, bracket-value | demo), stacks in
`docs/probes/layout-allocations/` (`stacks-of.py`, `isolation-sites.py`):

| Site | bracket | demo | What allocates |
|---|---|---|---|
| `roundLayout` ← `roundNativeStoredRects` | 812 | 126 | `roundLayout([layout(node)])[0]`: one one-element array **per node** |
| `solveLinearStack` | 614 | 452 | `stackGaps`, `priorities`, `Set`, `sorted`, `members`/`reserved` filters, `order`, a `Dictionary` of flexibilities, per stack per call |
| `Frame.retainedAmbientKey` | 392 | - | eight `[Double]` per key, `v +=` regrowth per scope |
| `LayoutTree.nodeSignature` | 384 | 36 | `AnyHashable.base` and `.hash(into:)` open a boxed existential **per leaf per run** |
| `LayoutTree.graft` | 340 | - | `reserveCapacity(base + n)` on every call: exact growth, a new buffer per graft |
| `StateTable.mark` | 151 | 194 + ~290 coroutine frames | `storage[id]?.isLive = true` allocates a `swift_coroFrameAlloc` frame |
| `ForEach.produceElements` | 223 | - | `Set<ID>`, `nodes` grown without capacity, `String(describing:)` |
| `planLegacyItems` / `registerLegacyItems` | 117 | 146 + 79 | `plans` and `reports` grown without capacity |
| `LayoutTree.preorder` | 120 | - | `order` grown without capacity |

Scratch experiment (`docs/probes/layout-allocations/scratch-E1-round-graft-mark.patch`: `roundedRect`, geometric graft
reserve, `mark` through `index(forKey:)`; reverted, not in this branch): allocations per frame **value 7,659 -> 6,598,
orbit 5,934 -> 4,847, pan 19,468 -> 18,158, demo 2,150 -> 1,733, list-fixed 1,248 -> 1,049** (-14 %, -18 %, -7 %, -19 %,
-16 %). Median ms did not move measurably under load 25 and `PROF_ALLOC` overhead; **time is a claim for the lanes' A/B,
not for this document** (`PA-A`).

`measureNative` (lines ~831-855): `LayoutMemo.lookup` 3.8 %/3.1 %, `run.cache` find 1.7 %/2.2 %, the two `setValue`s
3.4 %/2.6 % (demo/orbit): about 8 % of a frame in hashing a `NativeMeasurementKey`/`MeasureKey`.

Isolation checks (`isCurrentExecutor`/`pthread_main_np`), demo | orbit: **1.2 % | 1.3 % in all**, at
`LegacyLowering` 116 (`children.map { consume }`), 323 (same), 951-952 (`planLegacyItems` weights `filter`/`map`),
`RetainedSubtree` 601/606 (`finishRetainedPaint`: `allSatisfy`, `filter`), 500 (`replayPaint`) and 542
(`allSatisfy`). **`Frame.swift` 2373/3224 no longer appear** (below 0.1 %): P1 fixed them.

## 2 Public API

None. Every change is `internal`/`package` or inside a body; `roundLayout` keeps its public signature and its results
byte for byte (`PA-B`). `zsh docs/probes/closeout-inventory-check.sh` and `closeout-undocumented.sh` print nothing; the
census is unmoved.

## 3 Lane 1 — kernel: `Sources/MetalUILayout/*`, `Tests/MetalUILayoutTests/*`, `Tests/MetalUITestSupport/AllocationCounter.swift`

Files: `Rounding.swift`, `LayoutTree.swift`, `LayoutMemo.swift`, `LayoutLeafKeys.swift` (if the key type moves).

- **L1 `roundedRect(_:)`** (internal scalar; `roundLayout` becomes `rects.map(roundedRect)`); `roundNativeStoredRects`
  calls it. Removes one array per node.
- **L2 geometric graft reserve** (`PA-C`): `if array.capacity < need { array.reserveCapacity(max(need, 2 * capacity)) }`
  for `childLists`, `layouts`, `measuredWidths`, and the same guard (`Dictionary.capacity`) for the Int-keyed
  dictionaries `graft` fills when the segment is non-empty; `preorder` reserves `childLists.count`.
- **L3 leaf-key signature at registration** (`PA-D`): `leafKeys: [Int: AnyHashable]` becomes `[Int: LeafKey]`,
  `LeafKey { let key: AnyHashable; let typeID: UInt64; let h1: UInt64; let h2: UInt64 }` built where `leafKeys[id.index]`
  is set (line ~217); `LayoutSegment.leafKeys` carries it, so a grafted leaf is hashed zero times. `nodeSignature` mixes
  `1, typeID, h1, h2` **in the order it mixes today**, so every signature value is unchanged.
- **L4 `solveLinearStack`** (`PA-F`): one `gaps` sum without the array when `spacing != nil` (`gap * (n-1)`: **the same
  sum, in the same order only if computed as the reduce does** - use the loop, not the product, so floating results are
  bit-equal); `priorities` kept; **a single-priority fast path** (`priorities` all equal: `members` is every index, `reserved`
  is 0 with no `measureNative` call, no `Set`/`sorted`); the flexibilities dictionary becomes an array indexed by member
  position; `members`/`order` reserve. The measure calls keep their **order and arguments** (`reserved`, then the
  flexibility pair per member, then the offers), so `measureCalls`/`cacheHits`/`cacheMisses`/`memoHits` are equal.
- **L5 measure-key hashing** (`PA-K`), **gated**: custom `hash(into:)` on `LayoutMemo.MeasureKey` (signature words are
  already mixed: combine `a ^ rotate(b)` and one folded proposal word; `==` unchanged and complete) and a reserve of
  `run.cache` from the previous run's count. Kept only if the A/B median improves >= 1 % on demo or list-fixed with every
  work counter equal; otherwise reverted and recorded.

Tests (lane 1; each names what is red before and what must redden):

1. `aRoundedRectEqualsTheArrayRoundingOfItself` (`RoundedRectTests`): `roundedRect(r) == roundLayout([r])[0]` over a
   corpus of fractional, negative, half, large and zero-size rects. Red before: new symbol (compile red). Mutation:
   `.rounded()` -> `.rounded(.down)` on `x0` in `roundedRect` reddens it, `nativeLayoutRoundsStoredRectanglesAfterFractionalPlacement`
   and `theDemoFrameMatchesTheValuesRecordedOnMacOS`.
2. `roundingStoredRectsAllocatesNothingPerNode` (`LayoutAllocationTests`): thread-filtered allocation count (`PA-J`) of a
   rounding pass over a 50-node and a 500-node tree through a `package` hook (`roundStoredRectsForTesting`): the **difference
   is 0**. Red before: difference ~450 (the array per node), confirmed in the test's configuration before the fix, or the pin
   is dropped and the figure recorded as a measurement. Mutation: restore `roundLayout([layout(node)])[0]`.
3. `graftingManySegmentsReallocatesLogarithmically` (`LayoutAllocationTests`): 200 grafts of 5 nodes; the number of distinct
   `childLists.capacity` values seen through a `package` accessor is <= 12 (log2 1000 + slack). Red before: ~200. Mutation:
   restore the exact `reserveCapacity(base + n)`.
4. `aLeafKeyIsHashedOncePerRegistrationNotOncePerRun` (`LayoutMemoTests`): a `Hashable` key counting `hash(into:)` calls
   in a global; register once, compute signatures for 5 runs and for a graft of the segment: count == 1. Red before: 6.
   Mutation: hash `key` again in `nodeSignature`.
5. `aCachedLeafKeySignatureEqualsTheDirectOne` (`LayoutMemoTests`): `LeafKey` mixed into a `SignatureBuilder` equals
   `mix(1); mix(typeID of type(of: key.base)); mixHashable(key)` for Int, String, a struct and a tuple key. Mutation:
   swap `h1` and `h2` in `nodeSignature` reddens it and `everyRegistrarParameterIsInItsSignature`.
6. `aStackWithEqualPrioritiesSolvesLikeTheReference` (`StackSolveTests`): a corpus (equal priorities; two levels; three
   with one reserved; infinite and finite proposals; spacing nil and given; 1, 2, 7 children) against a test-local copy of the
   **old** algorithm, rects and the four counters equal. Red before: passes (differential; the pin is for the rewrite).
   Mutations: (a) in the fast path drop the tie-break `lhs < rhs`; (b) compute the gap sum as `spacing * Double(n-1)` on a
   corpus holding `0.1`; (c) skip the flexibility sort when `members.count > 1`. Name the reddened tests at lane time.
7. Existing, must read unchanged: `LayoutMemoTests` (hits, verify mode `METALUI_VERIFY_LAYOUT_MEMO=1` on the demo),
   `GraftKernelTests` (digest equality), `IncrementalInvalidationBaselineTests`, every `FrameWork`/work-counter pin.

## 4 Lane 2 — build: `Sources/MetalUI/*`, `Tests/MetalUITests*/*`

Files: `StateTable.swift` (`mark` only), `ForEach.swift`, `LegacyLowering.swift`, `RetainedSubtree.swift`
(the `retainedAmbientKey` scope loop and the `finishRetainedPaint`/`replayPaint` closures **only**: C14-c's workflow edits
`EquatableComponent.swift`, `ContentMemo.swift` and the environment code, and owns the `environment:` field of the key).

- **M1 `StateTable.mark`** (`PA-E`): `if let index = storage.index(forKey: id) { storage.values[index].isLive = true }`.
  Behaviour identical (an absent id does nothing, as `?.`). **Keep only if the allocation count falls** (it did in the
  scratch: ~290 coroutine frames per demo frame).
- **M2 `ForEach.produceElements`** (`PA-G`): `seenIDs.reserveCapacity(data.count)`, `nodes.reserveCapacity(data.count)` (a
  child usually yields >= 1 node; a bound, not a promise), `seenNames` reserved only when `dedupesNames`. The name stays
  `String(describing:)` and the `IdentityKey` stays as `FI-B` mints it (**byte for byte**).
- **M3 `planLegacyItems`/`registerLegacyItems`**: `plans.reserveCapacity(received.count)`; the weights `Set(compactMap.filter.map)`
  becomes one `for` loop (also an isolation site); `registerLegacyItems`' `nodes` reserved.
- **M4 isolation sites measured >= 0.3 %** (`PA-H`): `children.map { frame.lowering.consume($0) }` (two sites),
  `finishRetainedPaint`'s `allSatisfy`/`filter`, `replayPaint`'s, `retainedPaintDecision`'s `allSatisfy` become plain
  `for` loops with a reserved destination. No other site is touched; re-run `isolation-sites.py` after: the total must be
  below the 1.2 % above.
- **M5 `retainedAmbientKey`**: `v.reserveCapacity(64)` before the `+=` chain only (`PA-I`).

Tests (lane 2):

1. `aMarkedEntryIsLiveAndAnAbsentOneIsUntouched` (`StateTableTests`): mark present -> `isLive`; mark absent -> no entry
   created, `marked` holds it (as before). Mutation: drop the `isLive = true` line reddens it and the sweep tests
   (`aMarkedEntrySurvivesASweep` family; name at lane time); mutation: `storage[id] = Entry(...)` on absent reddens it.
2. `markAllocatesNothingOnASteadyFrame` (`LayoutAllocationTests`-style helper, `PA-J`): 1,000 `mark` calls of present ids
   after one warm pass: 0 allocations. Red before: ~1,000 **if** the debug build allocates the coroutine frame as release
   does; if not, the pin is dropped and the release figure is recorded as a measurement (`PA-J`).
3. `aForEachProducesTheSameNamesAndKeysAfterPresizing` (`ForEachIdentityTests` existing family `FI-`): the `FI-B`/`FI-K`
   byte-for-byte pins must read unchanged; add `aNaNIdStillDedupesByName` only if the existing set lacks the arm (check
   first). Mutation: drop `seenIDs.insert` guard reddens `FI-` tests (name at lane time).
4. `planLegacyItemsFlexWeightsMatchTheFilterMapSet` (`LegacyLoweringTests`): weights corpus (none, one factor, two, a
   zero, a negative) -> the same reported fields as before the loop. Mutation: `> 0` -> `>= 0` in the loop.
5. `everyIsolationSiteOfTheProfileIsALoop` is **not** written as a source scan (a grep over source is not a guard); the
   evidence is the dated `isolation-sites.py` reading in the record.
6. Existing, must read unchanged: `RetainedGraftTests`/`RetainedSubtreeTests` (replay equality), `DemoFrameDeterminismTests`
   Expected unedited, `PhaseSeparationTests`, the fourteen images 0 px (`docs/probes/demo-pixels/compare.sh <scratch>
   6273e3a4 HEAD`), the typecheck guards at their count (no new guard: no new public or phase surface).

## 5 Shared test support

`Tests/MetalUITestSupport/AllocationCounter.swift` (lane 1 owns it; lane 2 consumes it after lane 1 lands, so lane 2's
tests 2 land last): `countAllocations(_ body:) -> Int` installs `malloc_logger` (Darwin only,
`#if canImport(Darwin)`), counts only allocations whose `pthread_self()` equals the caller's, ignores its own, removes the
logger on exit. **Positive control** (`theCounterSeesAKnownAllocation`: `Array(repeating: 0, count: n)` -> exactly 1;
`let _ = 5 + 5` -> 0) and a **separating arm** (an allocation on another thread is not counted).

## 6 Measurements the lanes owe (dated, in the record)

Release `ms/frame` and allocations per frame at `6273e3a4` and HEAD for bracket-value, -orbit, -pan, demo, list-fixed,
**A/B alternated at least five times each** with `uptime` before and after, medians reported with the spread. Without
`PROF_ALLOC` for time, with it for counts. `swift build --build-system native --build-tests`, unfiltered suite
(**3918 tests in 3 suites** at 6273e3a4 plus the new ones), `FR-J no-argument frame: succeeded=true`, 0 `error:`,
`swift build --build-tests` 0 warnings; Linux image (`swift:6.4-noble`, `metalui-portable`) build and the portable suites
(allocation-counter tests are Darwin-only by `#if`); `Backends/SDL` untouched (not run).

## 7 Deferred, named

| Item | Why | Owner |
|---|---|---|
| `AmbientKey` as a fixed-layout struct (kills `retainedAmbientKey`'s 392/frame, 5 % of bracket allocations) | its `environment:` field is C14-c's (environment epoch); a reshape now conflicts | C14-c's merge, then a follow-up |
| Int-name cache for `ForEach` (`String(describing:)`) | `FI-B` byte-for-byte names; gain unmeasured (<1 % of frames) | none until a profile shows it |
| Array-indexed per-run measure cache replacing the `Dictionary` | redesign of `SA-H`'s cache; counters must stay equal | P3 if L5 shows hashing still >= 5 % |
| Text placement cache, `GlyphAtlas.packed`, `borderWidths`, animation early returns, rich-text caching | other items of the 2026-10-13 REPORT, not layout/build allocation; E1/E2 patch in `docs/probes/hot-paths/` | the item that owns text paint (P1 successors) |
| CoverageRasterizer allocations on pan (822/frame, 10.8 % of bracket-value) | `MetalUIPath` imports nothing and its rasteriser is bit-identical on every platform (`GX-B`); a buffer pool is a separate ruling | the pan item (path raster cache cut by clip) |
| `Frame.swift` 2373/3224 | no longer measurable (below 0.1 %) | closed by P1 |

## 8 Demo and human checks

Demo expectation: pixel-identical (fourteen images 0 px), same layout and replay counters; only allocation counts fall.
Human checks: none added (no look, no input, no platform behaviour moves).
