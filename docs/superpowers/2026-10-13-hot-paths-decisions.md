# Hot paths - decisions

Rulings for item P1 (user request 2026-10-02; **not a plan task**). Prefix `HP-`. **Next unused: `HP-I`.**
Spec: [`specs/2026-10-13-hot-paths-design.md`](specs/2026-10-13-hot-paths-design.md). Record:
`../record/111-hot-paths.md` (Record phase). Branch `perf/hot-paths` from `fb9a7e42`. Divergence labels
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
