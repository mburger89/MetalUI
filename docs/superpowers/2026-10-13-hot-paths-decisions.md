# Hot paths - decisions

Rulings for item P1 (user request 2026-10-02; **not a plan task**). Prefix `HP-`. **Next unused: `HP-Q`.**
Spec: [`specs/2026-10-13-hot-paths-design.md`](specs/2026-10-13-hot-paths-design.md). Record:
`../record/111-hot-paths.md`. Branch `perf/hot-paths` from `fb9a7e42`. Divergence labels
reserved 415-424: none taken (none yet).

Sources of truth. SwiftUI: none claimed (no public API, no visible behaviour). gpui (recalled, not read
on this machine): caches shaped text and reuses frames by value - precedent only. Evidence is the
release profile `/private/tmp/claude-501/profiling/REPORT.md` at `fb9a7e42` (shared Mac, load 5-40);
the scratch patch's A/B (fixed list -19 %, variable -25 %, demo -11 %) is an upper hint, to be re-taken.

## HP-A - Cache CoreText placement in a class box on `ShapedText`, plus a one-entry finished memo

**Question.** Where does the cache live and what keys it? **Ruling.** In a `final class` box stored
`let` in `ShapedText` (the shaping cache's two-frame lifetime frees it): runs once; the finished
`[PlacedGlyph]` by `(origin x/y bits, scale bits)`. `GlyphRaster.subpixelPlacement` stays the one rule
(PT-C) and runs on a memo miss. **Evidence.** Placement 6.7-8.7 % inclusive in lists, `paintGlyphs` +
`placeGlyphs` 21-29 % in profile. **Why not a global (text, x, scale) dictionary:** an extra hash per
paint, the cost being removed. **Cost if wrong.** A stale key draws misplaced glyphs; tests 3-4 compare
with the uncached walk. Portable system untouched (GT-E).

## HP-B - `GlyphKey` stores its hash; `==` early-rejects on it

**Ruling.** Follow `FontKey`: compute once in `init`, feed one `Int` to `hash(into:)`. Interning through
the atlas was rejected: `MetalUIScene` cannot see the text system's per-placement lifetime and an
intern table is a second lifetime to sweep. **Evidence.** `packed(for:)` 4 % fixed list, 9 % variable,
5.5 % rich. **Cost if wrong.** A mix omitting a field collides and still compares by fields (`==` is
total), so the worst case is a slower probe, never a wrong glyph; test 6 pins both halves.

## HP-C - Animation early-outs return when settled and equal, never when in doubt

**Ruling.** Return before allocating only if nothing is in flight **and** the declared value equals the
stored baseline bit for bit; otherwise the old path runs unchanged. In-flight clamped, declared never;
counters and `note...` calls identical (AN-M). **Evidence.** `borderWidths` 2-5 % and about 355
allocs/frame; `animate` + `value(at:)` 1.8-3.5 %, about 750 allocs/frame. **Cost if wrong.** A skipped
baseline update would freeze an animation start; test 13.

## HP-D - Rich text: memoise by value; parse a literal once

**Ruling.** Styled layout/measure memoised in the shaping cache entry; `LocalizedStringKey.textContent`
in a bounded value-keyed table. **Evidence.** `layOut` 15 %, `measure` 7.7 %, `ShapingCache.styled`
hashing 7.6 %, markdown 3.4 % (about 144 allocs). **Cost if wrong.** A table that grows without bound
leaks: bounded at 256 entries, cleared whole when full (no LRU bookkeeping on the hot path).

## HP-E - Shadow hits: stored `RasterKey` hash, one lookup, scalar bounding box

**Ruling.** Fold the hash in `add(_:)`; `touched...insert` and the dictionary read share one hash; the
`boundingBox` corners are scalars. Keys stay complete (PF-): every field is folded, test 16 mutates it.
**Evidence.** 22 % of the shadows frame is hashing. **Cost if wrong.** A field missing from the fold only
hurts speed (`==` still compares fields); a field missing from `add` is the existing stale-raster hazard
and is untouched.

## HP-F - Scope: what is deferred and why

**Ruling.** `Frame.swift` :2373 and :3224 and `RetainedSubtree.swift` sites wait for C14b-2's merge (a
live workflow edits them); layout allocation pre-sizing, `measureNative` hashing and `ForEach` are P2;
the pan path-raster clip-key and an R8 coverage format are P3 because they change pixels or shaders
(pan: paint 43 %, `CoverageRasterizer.rasterize` 7.6 %, about 2,400 allocs/frame, `tint` 5.8 %;
20,431 allocs/frame). **Cost if wrong.** Lost wins only; none is a correctness risk.

## HP-G - Critic amendments: tests that could not be red, the portable Atlas, the parse table, bit-equal

**Defects found and fixed in the spec.** (1) Tests 6 and 16 asserted `!=` on keys differing in one field,
but `==` compares fields, so omitting a field from the hash mix cannot redden them: both now read the
stored hash back (`package` read-back) and assert that keys differing in only that field have different
stored hashes (deterministic, not probabilistic), and a test-only forced-collision initialiser proves `==`
is not hash-only. (2) `GlyphAtlas.swift` is in `MetalUIScene`, a portable target `PortableTextSystem`
uses: the Linux image run is **required**, not conditional, and the mix uses no Foundation or `Hasher`
(PS-A). A stored property on `GlyphKey`/`TextGlyph` crossing a module owes `swift package clean`. (3) The
`LocalizedStringKey` table is global mutable state: it is `@MainActor`-isolated (or lock-guarded if the
type is nonisolated), keyed by the resolved source string and markdown flag, never by interpolated
values' identity; a test calls it from the main actor only. (4) Animation "equal" means `bitPattern`
equality, so NaN and -0.0 take the old path. (5) The one-entry placement memo thrashes if one `ShapedText`
is painted at two origins in a frame (shadow leaves); test 2 adds that case and the record states the
measured miss rate. **Rejected, with reason:** a global (text, x, scale) dictionary (HP-A); an atlas intern
table (HP-B). No public API, no divergence taken.

## HP-H - Lane 1 as built: where the spec's spelling moved

**Rulings.** (1) The work counters live on the per-shape `PlacementBox` (`runReads`,
`placementsComputed`, `keysBuilt`, `layoutsBuilt`), read by tests through `cache.shaped(...).placement` /
`cache.styled(...).placement`, not on `CoreTextTextSystem.placementWork`: a counter on the (main-actor)
system would need an isolation hop from the nonisolated `ShapedText.placedGlyphs`, the cost this item
removes. (2) The memo key carries the requested font's `FontKey` beside origin and scale bit patterns,
because the font decides the baseline arithmetic and which run fonts fall back to it. (3) The rich path
memoises two things inside the `StyledShapedText`'s box: the placed glyphs and segments by `(origin, scale)`
bits, and the finished `StyledTextLayout` with a **weak owner** (the system whose `placedFonts` its glyph
fonts were registered in); a second system sharing the cache rebuilds the layout from the memoised
placement. (4) Spec test 7 (`lastFrameProbes`) is re-spelled: `GlyphAtlas` has no counter that is not
tautological, so `aWarmAtlasFrameProbesOncePerDistinctGlyphKey` pins that a warm frame rasterizes nothing
and builds no key; the probe saving itself is the stored hash, pinned by test 6's read-back. (5) The
`GlyphKey` mix is a chain of bijections (xor, odd multiply, xorshift), so keys differing in one component
store different hashes deterministically; `size`/`scaleFactor` enter as `bitPattern` of `x + 0.0` so `-0.0`
and `0.0`, equal by `==`, hash alike. (6) `MarkdownContentTable` is lock-guarded (not main-actor):
`textContent` is nonisolated and runs on a 1 MB thread in `everyProductionTreeBuildsOnAOneMegabyteThread`.
It keys on `[.format(String)/.value(String)]`, never tables a key holding interpolated runs, and clears
whole at 256 entries. (7) Test `aLiteralWithNoMarkupRunsNoParser` (3.16) now uses a key unique to it:
`Text("**b**")` is used elsewhere in the process and is a table hit by design. **Evidence.** Mutations
M1-M7 each reddened the named tests (record 111). **Cost if wrong.** A stale memo draws misplaced glyphs;
tests 3 and 4 compare with a fresh shape for every origin and scale variant.

## HP-I - Lane 2 as built: where the spec's spelling moved

**Rulings.** (1) `hasPercentEdge` left its nested position for a file-level `edgesHavePercent(_:)`
(`LegacyLowering.swift`) and `contextualTarget(at:where:)` forwards to a `static
Window.contextualTarget(in:at:where:)` over an explicit hitbox list, so tests reach both without a
`LayoutPass` or a `Window`; the bodies are unchanged (the nested `isRegion` closure and the `lastIndex(where:)`
remain: the profile named the cost as the isolation check of closures passed from `@MainActor` code,
and the static function is nonisolated, so neither runs one). Shadow.swift's canonical-leaf `map` and
`ProposalAnimation`'s `Optional.map` sites (`px`, `raw`, `ordered`, the component-op `dimension`/`length`)
became `guard let` and a reserve-then-append loop. (2) Counters, not time: `AnimationStore.borderKeyBuilds`
and `numberTrackRebuilds` (cumulative, internal) and `RasterCache.keyProbes` (cumulative). Spec test 12's
`lastFrameTrackCopies` is that last-named counter's neighbour, re-spelled for the same reason as `HP-H` (1):
cumulative read-backs a test differences, no per-frame reset to race. (3) `borderWidths` also returns before
building keys on the `nil` branch when nothing is in flight (the keys it would clear cannot exist). (4)
`animatedNumbers` returns early only when the stored `inFlight` is empty **and** `baseline.count ==
declared.count` **and** every position is `nil` on both sides or non-NaN with an equal bit pattern; the
old slow path wrote nothing in that case either (state `==` existing), so no `set`, no
`noteActiveAnimation`, no `noteInterpolation` is skipped. (5) `RasterKey` is a manual `Hashable`:
`words`/`paths`/`objects` are `private(set)` and grow only through `add…`/`addPath`/`addObject`/`addWords`,
each folding into `storedHash` (xor, odd multiply, xorshift: bijections, so one differing component stores
a different hash); `==` checks the hash first then all three fields. A path folds its own `hashValue` at
add time (once, where the synthesized hash re-walked it on every lookup). (6) The cache keeps its touched
state in the entries (an epoch stamp, `endFrame` filtering only when a count says some entry went
untouched), so a hit is one `index(forKey:)` and a stamp in place; the tint key holds four `UInt32`s
instead of a freshly allocated `[UInt32]` per lookup. A miss costs two probes (find, insert), counted.
(7) `Affine2D.boundingBox` keeps `Array.min()`/`max()`'s comparison order in four scalar corners, bit-equal
(test 18, 500 random affines). **Evidence.** Mutations in record 111 §3. **Cost if wrong.** A stamp that
fails to move leaves a stale entry for one extra frame (memory only); a hash fold that omits a component
only slows a probe, never a wrong raster (`==` compares fields).

## HP-J - Record phase: every component of every memo key is pinned, plain and rich

**Question.** The verifier zeroed `StyledKey.y` and nothing reddened: is "the shipped key is correct" enough? **Ruling.** No: a
cache key is pinned per component where it is built. `aRichTextPlacementMemoKeyHoldsXAndYAndScale` places one
`StyledShapedText` at origins differing in only `y`, only `x`, only scale and asserts a recompute and moved glyphs each time. The
plain key's components were pinned already (`aChangedFractionalOriginOrScaleRecomputesPlacement`); the requested `FontKey` in the
plain key is covered by the oracle comparison only (named, not mutation-pinned). **Cost if wrong.** A rich `Text` scrolled
vertically draws at its previous position. Record 111 s7.

## HP-K - Per-frame maps reserve the previous frame's count (G33 (b), record 266)

**Question.** An Alloy profile (200 keystrokes) put 310 samples in `_NativeDictionary._copyOrMoveAndResize`: a `Frame` and its
`LayoutTree` are made new every frame, so every map regrows from empty. **Ruling.** The window captures a `FrameCapacityHints`
(counts only) when it adopts a frame and passes it to the next `Frame.init`, which **reserves** that much and nothing else:
`LayoutTree` (`childLists`, `layouts`, `measuredWidths`, `nativeNodes`, `leafKeys`, `spacingMarks`, `nativeParents`),
`FocusRegistry` (`focusable`, `keyHandlers`, `tabOrder`), `hitboxes`, `lowering.items`/`order`, and `elementBounds`/`axNodes` when
recorded. Storage is never reused, so no state crosses frames; maps that stay small (presentation anchors and spaces, context menus, scroll keys,
named spaces, AX press-only) are left alone. A window that shrinks reserves the large count for one frame only. **Evidence.**
`theSecondFrameReservesWhatTheFirstFrameHeld`. **Cost if wrong.** A wasted allocation, never a wrong frame.

## HP-L - The scene's rect and glyph arrays reserve the previous frame's count (G47, record 412)

**Question.** A frame's `Scene` starts empty, so its glyph array (about 200 B a glyph) doubled its way up each frame: twelve growth copies a frame in Alloy's probe, 2 MB. **Ruling.** `FrameCapacityHints` (`HP-K`) carries `sceneRects` and `sceneGlyphs`, the counts the adopted frame's scene held; `Frame.init` reserves them plus an eighth through `Scene.reserveCapacity(rects:glyphs:)` (`package`; the rect, glyph, sequence and layer arrays), reserve only. A window that shrinks reserves the large count for one frame. The test target's `countAllocatedBytes` (`MetalUITestSupport`) reads the bytes a pin on a copy's size needs. **Evidence.** Record 412. **Cost if wrong.** A wasted allocation, never a wrong frame.

## HP-M - A paint scope's capture arrays, a group's scene and a layout call's dictionaries start at the last count; a captured primitive carries no rare kind inline (G51, record 420)

**Question.** A streamed frame of a long transcript inside a paint scope grew, by doubling from empty, the text draw's leaf group, every composite and mask scope's `captures`, every offscreen group's scene, the layout run's measurement cache and the memo's generations, and a `CapturedPrimitive` was 424 bytes for an 88-byte glyph. **Ruling.** `Frame.beginLeafGroup(reserving:)` takes the draw's glyph count; `FrameCapacityHints.scopeCaptures` (`HP-K`'s struct, 64 entries at most) is the count each composite or mask scope collected, by opening order, and the next frame reserves it (`reserveCaptures(of:)`); `collectingIntoFreshScene(reserving:)` reserves the group's own rects and glyphs (counted with a `while`); a closed scope's captures are taken, not copied; `NativeLayoutRun` reserves the last call's count per entry point and `LayoutMemo.endFrame` makes each generation at the count of the one before; `CapturedPrimitive.Kind`'s path, shadow, gradient, blur and backdrop cases are `indirect` (424 to 272 bytes). Every size is a count carried one frame, never a buffer, and follows the count down. **A new array that a paint scope or a text draw fills per primitive owes a reserve from a known count; a new `CapturedPrimitive.Kind` case with a payload over 130 bytes is `indirect`.** **Evidence.** `G51ChurnTests`, `LayoutCacheHintTests`, `theSecondFrameReservesWhatTheFirstFramesScopeCollected`; record 420. **Cost if wrong.** A reserve of last frame's size that this frame does not fill, once; never a wrong frame.

## HP-N - The scene's arrays and a retained record's op arrays reserve a size class, not the exact count (G52, record 422)

**Question.** After `HP-M` a streamed frame still left `Malloc Large (empty)` regions behind (Alloy: 160 MB in 61 regions that stayed through 45 s of idle). **Ruling.** Every array a frame builds that is as long as the scene (`Scene.reserveCapacity`, the permuted arrays and the merge array `finalize()` builds, a retained record's `scene` and `finalScene`, `BuildJournal.rebased`) reserves `steadyCapacity(count)`: exact under 1024, else rounded up to a step of an eighth of the count's power of two (at most 12.5 percent over). A scene a few glyphs longer is then the same malloc request as the block the frame before freed, so malloc's large-block cache serves it. `finalize()` also skips its sort (and the sort's half-scene scratch block) when the merged order is already sorted, checked in one pass. **Bound.** The slack is untouched capacity, at most an eighth, in arrays that live one frame (a retained record's, as long as the record). No cache, no timer. **Tests.** `SceneSteadyCapacityTests` (5), `G52StreamingCapacityTests`.

## HP-O - A frame live under a recursion holds only what crosses the call; its tail is an `@inline(never)` helper (record 427)

**Question.** The controls demo's first frame needed 1.54 MB of stack in a debug build and a 1 MiB Windows thread overflowed (`c00000fd`, record 419). Where does a frame's size come from, and may it be cut without boxing? **Ruling.** A debug build gives every local of a function a slot at entry, none reused, and a value of an unknown generic type is an `alloca` of its size, so a frame on the layout recursion (live under the whole subtree) is 1 to 4 copies of the value it handles. Code after the recursive call moves to an `@inline(never)` function taking the one value that crosses the call (`Component.sealedComponentLayout`, `Element.singleGroupLayout`, `Box.finishLayout`, `ModifiedContent.finishLayout`, `Frame.renderAfterRootLayout`), and **a type's public initialisers do not delegate to one another** (an initialiser's frame is about four times its value; `Stepper`: `self = Self.make(…)`, a static function, then a leaf memberwise `init`). **No value moves to the heap**; release builds are unchanged in time and allocation. A section of a demo or an app whose `content` getter chain is deep becomes a `Component` (`PE-K`). **Evidence.** `aNestingLevelOfLayoutCostsAtMostItsCeilingOfDebugStack` (per level: 114,176 to 79,904 bytes, ceiling 88,000; thin 12,912 to 8,624, ceiling 10,000), `theCensusDemosLayOutBelowOneMebibyte` with the controls and looks demos (1.54 to 0.85 MB, 1.18 to 0.79 MB); record 427. **Cost if wrong.** A debug frame a helper-call larger; never a wrong frame. A new function on the layout recursion that does work after the recursive call owes the helper, and the per-level ceiling says when it does not.

## HP-P - In release the first frame's stack is dominated by the constructed tree value; a large static tree is split at `Component` boundaries (record 435)

**Question.** The default demo's first frame took 1,107,040 bytes of stack in a release build, over a Windows main thread's 1 MiB, with layout and paint at 0.45 MB. **Ruling.** In release the specialised composing functions and the container initialisers keep every intermediate copy of a nested generic tree alive, about six times the root value in the composing frames, so the first frame's stack is the tree value's size times six, not what layout needs. A large static tree is split at `Component` boundaries: a component is an empty or small value whose `content` is built when layout reaches it, and it holds its own modifiers. The default demo's root went from 51,680 to 4,720 bytes and its first frame from 1,107,040 to 302,656 (`theDefaultDemosRootValueIsAFewKilobytes`, a ceiling of 5,120 that only goes down). `@inline(never)` on the builders saved nothing and a non-delegating `Box` init 49 KB on the pre-fix demo; neither landed. **Cost.** A component is one layout record's heap box: 16 allocations of 19,952 in an idle frame, no element request. **Carried.** The 49 KB `Box` init change, if a tree cannot be split further.
