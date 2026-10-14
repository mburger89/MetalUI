# 111 - Hot paths (item P1)

Branch `perf/hot-paths` from `fb9a7e42`. Not a plan task: item P1 of the gpui-gap priority list (user request 2026-10-02),
from a release profile of MetalUI at `fb9a7e42` (`/private/tmp/claude-501/profiling/REPORT.md`, scratch, shared Mac). Spec
`docs/superpowers/specs/2026-10-13-hot-paths-design.md`; rulings `HP-A`...`HP-I` in
`docs/superpowers/2026-10-13-hot-paths-decisions.md` (`HP-A`...`HP-G` the design phase's, `HP-H` lane 1's, `HP-I` lane 2's; next
unused `HP-J`); probes `docs/probes/hot-paths/` (the unvalidated scratch patch `experiments-E1-E2-E3.patch`, a starting point
only). Divergence labels reserved 415-424: **none taken** (no public declaration, nothing SwiftUI-visible; census unmoved).

**Status: BUILT, two lanes, both verified `ok`.** Every change is value-identical: the fourteen offscreen images are 0 px
against `fb9a7e42`, no `FrameWork` or work-counter pin moved, the CoreText oracle is green. Release ms/frame, dated and
measured on a loaded shared Mac (load 65-130): demo -17 %, list-fixed -27 %, list-var -36 %, rich -61 %, shadows -36 %, materials
-21 %, orbit -5 % (section 5). The verifier's one major finding (the rich-text placement memo key's `y` unpinned) is closed in
section 7. Carried: `Frame.swift` :2373 and :3224 and the `RetainedSubtree` sites (C14b-2), layout pre-sizing, `measureNative` hashing and
`ForEach` (P2), the path-raster clip key and an R8 coverage format (P3, section 8).

## 1. The profile and what was taken

The release profile named four costs in the hot loops: **dynamic actor-isolation checks** (a closure handed from `@MainActor`
code to a stdlib generic checks its isolation on every call, once per glyph in `placeGlyphs`), **CoreText placement redone every
paint** (6.7-8.7 % inclusive in lists, `paintGlyphs` + `placeGlyphs` 21-29 %), **a SipHash of a `GlyphKey` per glyph per frame**
in `GlyphAtlas.packed(for:)`, and **settled animation and shadow-hit paths that still allocate** (border key strings, track
arrays, a `[UInt32]` tint key, a four-element corner array). The scratch patch's A/B hinted at -19 % (fixed list), -25 %
(variable), -11 % (demo); the figures in section 5 replace those.

Taken: spec items 1-6 outside the file boundary (a live workflow, C14b-2, edits the retained-subtree and layout code). Not taken:
section 8.

## 2. Lane 1 - text (`HP-A`, `HP-B`, `HP-D`, `HP-H`)

Commits `562a511a` (red), `40057d43`, `57c78e87`. Files: `Sources/MetalUIText/PlacedGlyph.swift`, `ShapedText.swift`,
`CoreTextTextSystem.swift`, `StyledShaping.swift`, `Sources/MetalUIScene/Atlas.swift`, `Sources/MetalUI/LocalizedStringKey.swift`.

- **`PlacementBox`** (a `final class` held `let` in `ShapedText` and `StyledShapedText`, freed with the shaping cache's two-frame
  lifetime) reads the CoreText runs once, and memoises the finished `[PlacedGlyph]` by `(origin x bits, origin y bits, scale bits,
  requested FontKey)`. The rule is still `GlyphRaster.subpixelPlacement` (PT-C), run on a miss. One entry: two origins
  alternating thrash it, pinned as the measured miss behaviour (`HP-G` item 5).
- **The rich path** memoises two things in `StyledShapedText`'s box: placed glyphs and segments by `(x, y, scale)` bits, and the
  finished `StyledTextLayout` with a **weak owner** (the system whose `placedFonts` its fonts were registered in).
- **`GlyphKey`** stores its hash (`precomputedHash`, `package`): a chain of bijections (xor, odd multiply, xorshift), `size` and
  `scaleFactor` as `bitPattern` of `x + 0.0` so `-0.0` and `0.0` hash alike; `==` early-rejects on it and still compares every
  field. `MetalUIScene` stays Foundation-free (PS-A). A stored property on a public type crossing a module: `swift package clean`.
- **`MarkdownContentTable`** (lock-guarded, not main-actor: `textContent` is nonisolated and runs on a 1 MB thread) parses a
  `LocalizedStringKey` literal once per process, keyed on `[.format(String)/.value(String)]`, never a key holding interpolated
  runs, cleared whole at 256 entries.
- Plain loops for the closures at `CoreTextTextSystem.swift`'s `placeGlyphs`, :78, :86, :89.

Pins (`Tests/MetalUITextTests/PlacementCacheTests.swift`, `Tests/MetalUICrossPlatformTests/HotPathMarkdownTests.swift`,
`Tests/MetalUITests/HotPathTextGuards.swift`), all counting work through `PlacementBox` (`runReads`, `placementsComputed`,
`keysBuilt`, `layoutsBuilt`):
`aSecondPaintOfTheSameTextReadsNoRunsFromCoreText`, `aSecondPaintAtTheSameOriginComputesNoPlacements`,
`aChangedFractionalOriginOrScaleRecomputesPlacement`, `thePlacedGlyphsEqualTheUncachedWalkForEveryOracleString`,
`aWarmPlainParagraphBuildsNoGlyphKeys`, `aGlyphKeyHashesFromItsStoredHashAndComparesEqualByFields` (stored-hash read-back per
component, a forced-collision initialiser proving `==` is not hash-only), `aWarmAtlasFrameProbesOncePerDistinctGlyphKey`
(re-spelled, `HP-H` 4), `aSteadyRichTextFrameLaysOutAndMeasuresZeroTimes`, `aRichTextPlacementMemoKeyHoldsXAndYAndScale`
(added at the record phase, section 7), `aSteadyMarkdownLiteralParsesZeroTimes`; the guard **HP.1** (plain import, the stored hash
is not spellable outside the package; mutated red once by making the member `public`). `LocalizedStringKeyTests` test 3.16 now
uses a key unique to it (`Text("**b-3.16-unique**")`: a literal already parsed in the process is a table hit by design).

## 3. Lane 2 - isolation, animation, shadows (`HP-C`, `HP-E`, `HP-I`)

Commits `8084f798` (red), `ffb7ebd0`, `3c767723`, `59868536`. Spec s3.1, s3.4, s3.6, tests 11-18.

### 3.1 What changed

- Plain loops or `guard let` for closures passed to stdlib generics in `@MainActor` code: `hasPercentEdge`
  (now file-level `edgesHavePercent`), `Shadow.shadowImage`'s canonical-leaf `map`, `ProposalAnimation`'s
  `px`/`raw`/`ordered`/`dimension`/`length` `Optional.map` sites. `MenuSession.contextualTarget` moved into a
  static list form (`Window.contextualTarget(in:at:where:)`), bodies unchanged.
- `AnimatedStyle.borderWidths` returns before building any key string when nothing is in flight and the
  border is unchanged (and on the `nil` branch when nothing is in flight). `animatedNumbers` returns
  `declared` when `inFlight` is empty and every position is bit-equal to its baseline (NaN excluded).
- `RasterKey` carries a stored hash folded by every `add...`; the fields are `private(set)`. `RasterCache`
  touches a coverage or tint entry in place with one `index(forKey:)` (epoch stamp), and the tint key no longer
  allocates a `[UInt32]` per lookup. `Affine2D.boundingBox` is four scalar corners.

### 3.2 Pins

Red lines at commit `8084f798` (before the implementation):
`aSettledBorderlessTreeBuildsNoBorderWidthKeys` (`borderKeyBuilds == before`),
`aSettledProposalTreeAllocatesNoTracks` and `aChangedValueStillAnimatesAndClampsAfterTheEarlyOut`
(`numberTrackRebuilds == before`), `aRasterKeyHashesFromItsStoredHash` (two issues: six keys stored one hash;
a later word did not move it), `aShadowHitDoesNotRehashItsKey` (`perFrame == 2`, was 4 per shadow). Green first
(pure refactors, mutation-verified instead): `edgesHavePercentAgreesWithItsClosureFormForEverySubset`,
`contextualTargetPicksTheSameHitboxAsTheClosureForm`, `boundingBoxEqualsTheFourCornerArrayForm`,
`aChangedBorderWidthStillAnimatesAfterTheEarlyOut`. Test 14's first version did not see the search direction
(M6 passed): the random lists now count ambiguous matches (`ambiguous > 15`) and M6 reddens it.
`everyStateTableAndAnimationStoreChannelIsClassified` (`SB-E`) owed the two new `AnimationStore` counters a
row (`.frameLocal`); a one-line addition to `RetainedSubtreeInternalTests` that C14b-2's merge must keep.

### 3.3 Mutations (lane 2's, filtered to the HotPath files plus the animation, shadow and gradient suites for M1-M4, M10)

Applied to the committed implementation, restored with `git checkout`, `git status --short` clean after each.
Not the full unfiltered suite per mutation (the Mac ran at load 90-130; a full run is 8-10 minutes): a
deviation from the practice, named here.

| Mutation | Reddened |
|---|---|
| M1 `borderWidths` early return removed | `aSettledBorderlessTreeBuildsNoBorderWidthKeys` |
| M2 `borderWidths` returns declared while in flight (`\|\|`) | `aChangedBorderWidthStillAnimatesAfterTheEarlyOut`, `aSettledBorderlessTreeBuildsNoBorderWidthKeys`, `aFocusRingAnimatesItsWidth`, `aHoverBorderAnimatesItsWidth` |
| M3 `animatedNumbers` early return deleted | `aSettledProposalTreeAllocatesNoTracks`, `aChangedValueStillAnimatesAndClampsAfterTheEarlyOut` |
| M4 early return ignores a changed baseline | 39 issues in 17 tests, among them `aChangedValueStillAnimatesAndClampsAfterTheEarlyOut`, `aProposalFrameAnimatesItsWidthUnderATransaction`, `aSettledProposalTreeAllocatesNoTracks`, `everyAnimatableProposalModifierAnimates` |
| M5 in-flight clamp removed | the run aborts inside `aChangedValueStillAnimatesAndClampsAfterTheEarlyOut` (opacity above 1 reaches its precondition: the clamp's own reason) |
| M6 `contextualTarget` searches forward | `contextualTargetPicksTheSameHitboxAsTheClosureForm` (28 issues) |
| M7 `edgesHavePercent` omits `.left` | `edgesHavePercentAgreesWithItsClosureFormForEverySubset` |
| M8a hash skips `objects` | `aRasterKeyHashesFromItsStoredHash` |
| M8b `add(Int)` skips the fold | `aRasterKeyHashesFromItsStoredHash` (2 issues) |
| M8c `==` is hash-only | `aRasterKeyHashesFromItsStoredHash` |
| M9 a coverage hit probes twice | `aShadowHitDoesNotRehashItsKey` |
| M10 `boundingBox` y min/max swapped | `boundingBoxEqualsTheFourCornerArrayForm` (438 issues) and five scene tests (`aGradientUnderARotationFollowsTheTransform`, `aShadowInsideARotationOrScaleHasItsOffsetTransformed`, ...) |

## 4. Whole-branch verification

- Fourteen offscreen images against `fb9a7e42` (`docs/probes/demo-pixels/compare.sh`), lane 2 verifier at `bd7102cd` (lane 1 and 2
  together): every row `differing=0`, scene identical.
- Record-phase run on ``df71b14e`` after `swift package clean`: `swift build --build-system native --build-tests` 0 `error:`, the only
  `warning:` SwiftPM's deprecation notice; `swift test --build-system native --no-parallel` unfiltered: **3737 tests in 3 suites passed** (3717 + lane 1's 10 + lane 2's 9 + the record phase's 1), after 428 s; `FR-J
  no-argument frame: succeeded=true`; guards **235** (234 + HP.1; the typecheck call sites read 429 -> 431, HP.1 holds two).
- Lane verifiers: lane 1 at its head, 3727 tests in 3 suites (3717 + 10); lane 2 at `bd7102cd`, 3736 (3717 + 19, lane 2's 9), default
  `swift build --build-tests` 0 warnings.
- `zsh docs/probes/closeout-inventory-check.sh` and `closeout-undocumented.sh` print nothing (no public declaration).
- Linux image (`metalui-portable`, `Atlas.swift` is portable, `HP-G`): `Backends/SDL` 30 + 122 tests passed in `swift:6.4-noble` (volume `metalui-sdl-build-hot-paths`); the root package's portable tests built and passed there (226 + 9 + 40 + 25 + 217 + 80 + 22 across its seven runs, volume `metalui-root-build-hot-paths`); `MetalUIText` is Darwin-only and not built there.

## 5. Measurements (dated 2026-10-13/14, not pins; lanes 1 and 2 together)

Release, headless, Prof harness (`/private/tmp/claude-501/profiling/Prof`) built twice: A = `fb9a7e42`
(`git archive`), B = this branch HEAD (**lane 1 and lane 2 together**). Alternated A,B three times per
scenario, 8 s each, median ms/frame (the middle of three medians). **The Mac was shared and loaded: load
average 65-130 throughout**, so the figures are an upper-noise bound, not a claim; a second machine state
will differ.

| Scenario | A ms | B ms | change |
|---|---|---|---|
| demo | 1.280 | 1.063 | -17 % |
| list-fixed | 0.942 | 0.689 | -27 % |
| list-var | 1.340 | 0.864 | -36 % |
| rich | 3.398 | 1.341 | -61 % |
| shadows | 2.033 | 1.297 | -36 % |
| materials | 0.650 | 0.517 | -21 % |
| bracket-orbit | 4.736 | 4.496 | -5 % |
| bracket-value | median 0.000 (the scenario's median frame is a no-op) | mean 7.1 / 9.9 / 12.6 (A), 6.1 / 11.2 / 20.4 (B) | too noisy to read |

Allocations per frame (`PROF_ALLOC=16`, one run each): bracket-value A 3,186,717 / 243 = 13,112, B
2,959,752 / 243 = 12,180 (-7 %); demo A 2,593,068 / 969 = 2,676, B 2,511,225 / 1,168 = 2,150 (-20 %).
Lane 2's share is not separable from this table (the harness builds lane 1 and 2 together).

## 6. Lane 1 mutations

Lane 1's own mutations (M1-M7, M4b, guard HP.1) were run by its implementer against the 23-test filtered set, each reddening the
tests named in `HP-H` and the spec's section 4 mapping (box memo dropped, finished-array memo dropped, x/scale left out of the key,
a key built in `placeGlyphs` again, a field left out of the `GlyphKey` mix, `==` made hash-only, the table removed). **Deviation
from the practice: those were not re-run on the unfiltered suite** (each full run is 8-9 minutes at load 27-130). The verifier
re-ran, on the full unfiltered suite, one mutation that applied `y` to 0 in `PlacementBox.MemoKey` and `StyledKey` together,
restored, `git status --short` clean:

| Mutation | Reddened |
|---|---|
| `MemoKey` y component replaced by 0 (`PlacedGlyph.swift`), with `StyledKey` y also 0 | `aSecondPaintAtTheSameOriginComputesNoPlacements`, `aChangedFractionalOriginOrScaleRecomputesPlacement` (3 issues); **no rich-text test** |

## 7. Findings and their closure

1. **Major (verifier, lane 1): the rich-text placement memo key's `y` was unpinned** - no test reddened when `StyledKey.y` became 0,
   so a rich `Text` moved only vertically (a scroll) would have drawn stale positions with every pin green. The shipped key was
   correct. Closed at the record phase by `aRichTextPlacementMemoKeyHoldsXAndYAndScale` (places one `StyledShapedText` at origins
   differing in only `y`, only `x`, only scale and asserts a recompute each time and moved glyphs). Mutation: `StyledKey.y` replaced by 0 (`StyledShaping.swift`), restored with `git checkout`, filtered to the placement and rich-text tests (10 tests): reddens `aRichTextPlacementMemoKeyHoldsXAndYAndScale` alone (4 issues: the y, x and scale recompute counts and the moved baselines). A filtered, not unfiltered, run (deviation named).
2. **Minor: `thePlacedGlyphsEqualTheUncachedWalkForEveryOracleString` compares a memo hit with a fresh shape's first computation**
   (the new code), not with the pre-change walk. Equivalence to `fb9a7e42` rests on the fourteen images and the CoreText oracle
   tests. A verbatim copy of the old walk as a reference is an option, not done.
3. **Minor: `edgesHavePercent` still uses `.contains` with a closure**; the isolation check is gone because the function moved out
   of `@MainActor` context (a file-level nonisolated function), not because it is a `for` loop. No counter can see the check, so the
   benefit is the measurement of section 5, not a pin. Lane 2's section 3.1 says "plain loops or `guard let`" for the other sites,
   which is exact for them.
4. Lane 2's mutations were filtered (section 3.3); the verifier added one of its own at the filtered level (`RasterCache.texture`'s hit
   path no longer stamping the epoch: `aShadowHitDoesNotRehashItsKey`, `aReplayTouchesItsRastersSoTheyAreNotDropped`,
   `aShadowedContainerDraggedByWholePixelsHitsTheCache`, `aShadowedContainerPannedByWholePixelsHitsTheCache`,
   `aPathDraggedByWholePixelsHitsTheCache`) and re-ran M1 (`aSettledBorderlessTreeBuildsNoBorderWidthKeys`).

## 8. Deferred, with owners

- `Frame.swift` :2373 and :3224 (the `hoveredElement` getter and `insertThroughScopes`) and the `RetainedSubtree.swift` sites:
  **C14b-2** (`perf/retained-build-skip` edits them), then P2.
- Layout allocation pre-sizing, `measureNative` hashing, `ForEach` cost: **P2**, after C14b-2.
- The pan path-raster clip-key change and an R8 coverage format: **P3** (they change pixels and shaders). The profile's numbers: pan
  paint 43 %, `CoverageRasterizer.rasterize` 7.6 %, about 2,400 allocations a frame, `tint` 5.8 %, 20,431 allocations a frame.
- `RasterCache.image` (gradient images) still uses the touched-set pair, two probes (`HP-I`).
- A portable text placement cache: only if a Linux profile asks (`PortableTextSystem` already caches an origin-free line, `GT-E`).
- Human checks: `docs/verification/human-checks.md` group HP (3 items), none performed (an agent cannot).

## 9. Hazards

- A placement memo key missing a component draws stale glyphs while the counters stay plausible: pin every component, plain and rich.
- A stored hash folded from fewer fields than `==` compares only slows a probe; one folded from *more* fields than `==` (a field not
  compared) breaks equal keys. Both `GlyphKey` and `RasterKey` fold exactly what `==` compares.
- A cumulative counter read-back (differenced by the test) beats a per-frame reset that a concurrent test can race.
- `SB-E`'s classification test (`everyStateTableAndAnimationStoreChannelIsClassified`) owes every new `AnimationStore` counter a
  row; C14b-2's merge must keep the two lines this branch added to `RetainedSubtreeInternalTests`.
- A main-actor-only global (a markdown table) is unreachable from `textContent` on a 1 MB thread: lock-guarded instead.
