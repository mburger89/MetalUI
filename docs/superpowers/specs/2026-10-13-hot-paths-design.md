# Hot paths (item P1) - design

Item P1 of the gpui-gap priority list (user request 2026-10-02; **not a plan task**). Prefix `HP-`.
Rulings: [`../2026-10-13-hot-paths-decisions.md`](../2026-10-13-hot-paths-decisions.md). Branch
`perf/hot-paths` from `fb9a7e42`. Divergence labels reserved 415-424: **none taken** (no public API,
nothing SwiftUI-visible). Record `docs/record/111-hot-paths.md` (Record phase). Profile:
`/private/tmp/claude-501/profiling/REPORT.md`; scratch patch `docs/probes/hot-paths/experiments-E1-E2-E3.patch`
(a starting point; it passed scene checksums only).

## 0. Contract

Every change is **value-identical**: the fourteen offscreen images 0 px against `fb9a7e42`
(`docs/probes/demo-pixels/compare.sh <scratch> fb9a7e42 HEAD`), every `FrameWork` and work-counter pin
unchanged, `DemoFrameDeterminismTests` `Expected.swift` unedited, the CoreText oracle green. No public
declaration (so no inventory row, no doc-comment debt; re-run both closeout scripts, they print
nothing). No shader, no `Backends/SDL` change. Wins are **counted, never timed** (pins count work);
ms/frame and allocations/frame are dated measurements in the record.

No SwiftUI-facing claim is made, so no SwiftUI probe is owed. gpui precedent (recalled, not read here):
it caches shaped lines and reuses per-frame layout by value; MetalUI's `ShapingCache` already does for
shaping, this item extends it to placement. No platform requirement changes (no migration note).

## 1. File boundary

Not touched: `RetainedSubtree.swift`, `EquatableComponent.swift`, `ContentMemo.swift`, `StateTable.swift`,
`ForEach.swift`, `Sources/MetalUILayout/*`, `ProposalNodeID.swift`, Frame.swift's build/prepaint/paint
recursion. **Frame.swift:2373 (`hoveredElement`) and :3224 (`insertThroughScopes`) are deferred to P2**
(live workflow C14b-2 edits that file). Out of scope, owner P2: allocation pre-sizing in layout,
`measureNative` hashing, `ForEach` cost. Carried to P3 (changes pixels/shaders): the pan path-raster
clip-key change (paint 43 % of a pan frame; path rasters miss every pan, `CoverageRasterizer.rasterize`
7.6 % about 2,400 allocs/frame, `RasterCache.tint` 5.8 %) and an R8 coverage format.

## 2. Lanes (two, disjoint files)

**Lane 1 - text** (`MetalUIText`, `MetalUIScene/Atlas.swift`, rich-text parse cache). Items 2, 3, 5 and
the CoreText sites of item 1.
Files: `Sources/MetalUIText/{CoreTextTextSystem,PlacedGlyph,ShapedText,StyledShaper,ShapingCache}.swift`,
`Sources/MetalUIScene/Atlas.swift`, `Sources/MetalUI/LocalizedStringKey.swift` (+ `MarkdownInline.swift`
call site only), `Sources/MetalUI/Text.swift` only if `paintGlyphs` needs a loop rewrite; tests
`Tests/MetalUITextTests/*`, `Tests/MetalUITests/HotPathText*.swift`.

**Lane 2 - isolation, animation, shadows** (items 1 (non-text), 4, 6).
Files: `Sources/MetalUI/{LegacyLowering,MenuSession,Shadow,ProposalAnimation,AnimatedStyle,Affine2D,RasterCache,AnimationStore}.swift`;
tests `Tests/MetalUITests/HotPathAnimation*.swift`, `HotPathShadow*.swift`, the typecheck guard file.

Neither lane edits a file of the other. Lane 1 owns `CoreTextTextSystem.swift`'s :66, :78, :86, :89.

## 3. Design per item

### 3.1 Isolation checks (item 1)
Replace closures passed to stdlib generics from `@MainActor` code by plain loops: `placeGlyphs`
(:66, one check per glyph), `measure`/`layOut` `text.runs.map` (:78, :86, :89) - Lane 1;
`hasPercentEdge` (four `if case`, LegacyLowering:787), `MenuSession.contextualTarget` (:271,
`lastIndex(where:)` becomes a reverse index loop; same first-from-the-end match), Shadow:118,
`ProposalAnimation` :163 and :187 - Lane 2. Then re-run `--rt` on `list-fixed`, `demo`, `shadows` and
fix any further site outside the boundary that names `swift_task_isCurrentExecutor`. Evidence: the
profile's 3-8 % per frame.

### 3.2 Placement cache (item 2, `HP-A`)
`ShapedText` gains a `final class PlacementBox` (internal, `let`, so the struct stays a value):
(a) per line, `[Run]` where `Run` = resolved font, size, glyph ids, positions, read once from the CTLine
(`CTLineGetGlyphRuns` bridge, `CTRunGetGlyphs/Positions`, `resolvedRunFont`); (b) a one-entry memo of the
finished `[PlacedGlyph]` keyed by `(origin.x.bitPattern, origin.y.bitPattern, scaleFactor.bitPattern)`.
`GlyphRaster.subpixelPlacement(forDeviceX:)` stays the only place the rule lives (PT-C): it is called per
glyph on a memo miss, never inlined or cached as its own result. A box lives as long as its `ShapedText`
(the `ShapingCache` entry's two-frame lifetime). RT-M: the plain path returns the same `[TextGlyph]`
byte for byte. The portable system is **not** changed (it already caches an origin-free line per
`MeasureKey`, GT-E; no profile shows placement hot there; Linux image not needed unless that changes).

### 3.3 Atlas probe (item 3, `HP-B`)
`GlyphKey` stores a precomputed `Int` hash built in `init` (mixing its five fields, `FontKey`'s own
stored hash included), `hash(into:)` feeds that one `Int`, and `==` rejects on it first, the `FontKey`
pattern. `PlacedGlyph`/`TextGlyph` carry the key built once per placement, so with 3.2 a warm paint
builds zero keys and `packed(for:)` hashes one `Int`. `MetalUIScene` still imports only
`MetalUIShaderTypes`.

### 3.4 Animation early-outs (item 4, `HP-C`)
`AnimatedStyle.borderWidths`: guard first (`declared == nil || previous == nil`, drop in-flight keys
only if the dictionary is non-empty), then `inFlight.isEmpty && d == p` returns `declared`, building no
string. `LayoutModifier.animate`/`animatedNumbers` and `AnimationStore.value(at:)`: when the stored
track has an empty `inFlight` and every `declared[i]` equals its baseline, return `declared` before
copying the dictionary or building `String(i)` keys; the baseline update and the `note...` calls run
exactly as before. Clamping of in-flight values, never of declared, and every `AN-` pin stay.

### 3.5 Rich text (item 5, `HP-D`)
`CoreTextTextSystem.layOut`/`measure` memoise by the `StyledText` value in the shaping cache entry
(placement by `(origin, scale)` as 3.2, `StyledShaper.placed` over the same run box); fonts `map`
becomes a loop. `LocalizedStringKey.textContent` is memoised per key by value in a window-independent
bounded table (keys are values; contents are immutable runs); `markdownParserCounter` pins that a
steady frame parses 0 times. RT- rules hold: a `String` value, `Text(verbatim:)` and control titles are
never parsed.

### 3.6 Shadow hits (item 6, `HP-E`)
`RasterKey` gets a stored hash built incrementally in `add(_:)` (`words`, `paths`, `objects` fold in),
`hash(into:)` feeds it, `==` rejects on it first; **no field may be added without folding into it**
(key completeness, PF-). `Affine2D.boundingBox(x:y:w:h:)` computes the four corners into scalar
mins/maxes, no array. The cache-hit path stops rebuilding the key `[UInt64]` where the canonical key is
already equal (`touchedCoverage.insert` + `coverage[key]` hash twice today: use one `index(forKey:)`).

## 4. Tests (name, red before, mutation that must redden)

All new tests count work, never time; each is red on arrival (written against a counter that reads the
old value first, recorded in the record). New counters are `package`/internal read-backs.

Lane 1 (`Tests/MetalUITextTests/PlacementCacheTests.swift`, `Tests/MetalUITests/HotPathTextTests.swift`):
1. `aSecondPaintOfTheSameTextReadsNoRunsFromCoreText`: `CoreTextTextSystem.placementWork.runReads` is 0 on
   the second `placeGlyphs` of one string. Red before: counter is N per call. Mutation: drop the box's
   `lines` memo (re-read every call) reddens it.
2. `aSecondPaintAtTheSameOriginComputesNoPlacements`: `placementsComputed` 0 on repeat at an equal
   origin/scale. Mutation: drop the finished-array memo.
3. `aChangedFractionalOriginOrScaleRecomputesPlacement`: origins 10.0 vs 10.3, scale 1 vs 2 each
   recompute, and the glyphs equal an uncached system's. Mutation: key the memo on `origin.x` rounded
   (reddens: wrong variant) or omit the scale.
4. `thePlacedGlyphsEqualTheUncachedWalkForEveryOracleString`: over the CoreText oracle strings incl.
   fallback fonts, an `.equatable` comparison with a cache-bypassing reference copy (test-only) is
   equal. Mutation: cache `pixelX` of a different origin.
5. `aWarmPlainParagraphBuildsNoGlyphKeys`: `GlyphKey` constructions per warm paint 0 (counter in test
   hook). Mutation: build the key in `placeGlyphs` again.
6. `aGlyphKeyHashesFromItsStoredHashAndComparesEqualByFields`: equal fields give equal hash and `==`;
   each of five fields differing gives `!=`. Mutation: leave one field out of the mix (red: collision
   test builds keys differing only in that field and asserts `!=`), and flip `==` to hash-only.
7. `aWarmAtlasFrameProbesOncePerDistinctGlyphKey`: `GlyphAtlas.lastFrameProbes` equals the distinct
   keys, 0 rasterizes. Mutation: remove the early return.
8. `aSteadyRichTextFrameLaysOutAndMeasuresZeroTimes`: styled `layOut`/`measure` compute counters 0 on
   frame 2; a changed run recomputes. Mutation: key by identity of the array.
9. `aSteadyMarkdownLiteralParsesZeroTimes`: `markdownParserCounter` unchanged on frame 2, a different
   key parses once. Mutation: remove the table.
10. A typecheck guard `HP.1 - GlyphKey's stored hash is not spellable outside the module` (plain
    import, `typecheckFile`), mutated red once by making the member `public`.

Lane 2 (`Tests/MetalUITests/HotPathAnimationTests.swift`, `HotPathShadowTests.swift`):
11. `aSettledBorderlessTreeBuildsNoBorderWidthKeys`: `AnimatedStyle.borderKeyBuilds` 0 with nothing in
    flight, and `borderWidths` output equals the old function (kept as a test-only reference) for
    declared/previous pairs with and without a transaction. Mutation: remove the `isEmpty && d == p`
    guard (counter reddens); mutation 2: return `declared` while in flight (value test reddens).
12. `aSettledProposalTreeAllocatesNoTracks`: `AnimationStore.lastFrameTrackCopies` 0 for a settled tree;
    existing `aSettledProposalTreeInterpolatesNothing` unmoved. Mutation: early return that ignores a
    changed baseline (test 13 reddens).
13. `aChangedValueStillAnimatesAndClampsAfterTheEarlyOut`: spring overshoot clamped, declared not,
    interpolation count equals the pre-change literals. Mutation: clamp declared.
14. `contextualTargetPicksTheSameHitboxAsTheClosureForm`: nested ids, layers, region/non-region
    permutations versus a reference closure implementation. Mutation: forward instead of reverse loop.
15. `hasPercentEdgeAgreesWithItsClosureForm` (four edges x percent/point). Mutation: omit `.left`.
16. `aRasterKeyHashesFromItsStoredHash`: keys differing in only `words`, only `paths`, only `objects`
    are unequal and (probabilistically) hash apart; adding a word after construction updates it.
    Mutation: skip `objects` in the fold (red), skip updating in `add(Int)`.
17. `aShadowHitDoesNotRehashItsKey`: `RasterCache.lastKeyHashes` per hit 1, 0 coverage makes. Mutation:
    insert into `touchedCoverage` via a second lookup.
18. `boundingBoxEqualsTheFourCornerArrayForm` over random affines (rotation, negative scale) bit for
    bit. Mutation: swap min/max for y.

Whole-branch: the unfiltered native suite (3717 + new, one summary line), `FR-J` line, both build
systems 0 `warning:`, 14 images 0 px, closeout scripts silent, Linux image run only if a portable
target changes (not planned).

## 5. Measurements (record, dated, not pins)

Prof harness copied and pointed at this worktree; A/B alternated against `fb9a7e42`, load average
recorded: ms/frame for demo, list-fixed, list-var, rich, shadows, materials, bracket-value,
bracket-orbit; allocations per frame (`PROF_ALLOC=16`) for bracket-value and demo. Baseline numbers
from the profile: fixed list -19 %, variable -25 %, demo -11 %, materials -15 %, orbit -5 % were the
scratch patch's, not claims.

## 6. Demo and human checks

No demo section (no visible change). Human-checks addition: group HP, one item: real-window text and
shadows look the same as `fb9a7e42` at 1x and 2x, scrolling a list, subpixel text positions (an agent
cannot see a real display; the 14 images cover the offscreen path). Real-window capture only when the
lock probe allows.

## 7. Deferred (named)

`hoveredElement`, `insertThroughScopes` (P2, after C14b-2); `RetainedSubtree.swift:519/:524` (C14b-2);
layout allocation pre-sizing, `measureNative` hashing, `ForEach` cost (P2); path-raster clip key and R8
coverage (P3, pixels/shaders); portable text placement cache (only if a Linux profile asks).
