# Text seam — design

**Status: implemented** on `feat/text-seam` (record §35); roadmap item 6 of
`plans/2026-09-23-cross-platform-roadmap.md`. **Ruling prefix:** `TS-`
(`TS-A`…`TS-G`, next `TS-H`; rulings here).

## Goal

`Text` and `ProposalText` called CoreText types directly — `ShapingCache`,
`ResolvedFont`, `ShapedText.placedGlyphs`, `GlyphRaster` — so `MetalUI`
could only ever draw text through CoreText. Roadmap items 1–4 built a
portable pipeline measured equal to that path; this item puts both behind
one protocol so the choice is an app's, and so item 9 can drop CoreText from
the non-Apple build.

## Rulings

### TS-A — One protocol, chosen once per app

`MetalUITextSystem` (a new portable target importing only `MetalUIScene`)
holds `@MainActor protocol TextSystem: AnyObject, Sendable`:
`resolveFont(family:size:) -> FontKey`, `measure(_:font:wrappingAt:) ->
TextMeasurement` (widest line, total height), `minContentWidth(_:font:)`,
`placeGlyphs(_:font:wrappingAt:origin:scaleFactor:) -> [TextGlyph]`
(`GlyphKey`, device pixel x, device baseline), `rasterize(_: GlyphKey) ->
GlyphImage`, and `beginFrame()`/`endFrame()`. Fonts cross the seam as their
resolved `FontKey`, never as a request.

`Text` and `ProposalText` measure and paint through `Frame.textSystem` only;
`Frame.draw(_: TextGlyph, color:)` rasterizes through it on an atlas miss.
The sprite arithmetic is one private `drawSprite`, shared with the CoreText
`draw(_: PlacedGlyph, color:)` tests still call. `App(device:textSystem:)`
takes a factory run once per window (each window keeps its own caches);
`nil` is CoreText. `MetalUI` re-exports `MetalUITextSystem`.

`Sendable`: a `@MainActor` class is implicitly `Sendable`, an existential of
a `@MainActor` protocol is not — the measure closures capture the system, so
the protocol refines `Sendable`.

### TS-B — `CoreTextTextSystem` is today's path, over the frame's cache

In `MetalUIText`, over a `ShapingCache` — by default the one the `Frame` or
`Window` was given, so every test that inspects a frame's cache sees the
entries it did before (all 1681 tests pass unchanged through the seam). It
records each placed glyph's run font (CoreText's fallback fonts included) so
`rasterize` can draw a key it placed. `textMeasure(_:font:cache:…)` and
`proposalTextMeasurement(_:font:cache:proposal:)` remain as thin wrappers
for the tests that ask the Apple path directly.

### TS-C — `PortableTextSystem` is items 1–4, memoized per frame

In `MetalUIPortableText`, over a `PortableFontResolver`: `lines` for
measurement, `minContentWidth`, `placements` (the arithmetic `emitLines`
uses, without the atlas) and FreeType for rasterization. Measurements are
memoized with `ShapingCache`'s two-frame lifetime. A thrown error — a font
that opened and then failed to shape — traps with its reason.

### TS-D — The oracle: the same tree, the same sprites

`TextSystemSeamTests`: a legacy column of three `Text`s (a four-line wrap,
kerning pairs, a hard break) at scale 1 and 2, and a native `VStack` of
wrapping `ProposalText`s, rendered through `CoreTextTextSystem` and
`PortableTextSystem` with Noto Sans in both, put **identical glyph sprites**
in the scene. Two companions keep that equality honest: the portable system
with a different default face draws different sprites (so equality is not
both frames using one engine), and a frame with the portable system leaves
its CoreText cache empty under both authorities and for `ProposalText` (so
no element measures through one engine and draws through the other).

### TS-E — The shaping trace: `METALUI_TRACE_SHAPING=1` (record 406)

An opt-in instrument for the question "which strings missed the shaping cache this frame?", answered per text system. It decides
nothing: no cache reads a trace value.

- **The switch.** `ShapingTrace.active` (package, `MetalUITextSystem`, which imports no Foundation). `MetalUI` reads
  `METALUI_TRACE_SHAPING` once, value exactly `"1"`, when the first `Window` or `Frame` is made and sets it
  (`shapingTraceFromEnvironment`); a test sets `active` and `sink` directly. The sink defaults to standard output, as
  `RetainedTrace` does.
- **The line.** One per frame that looked a shape up: `shaping frame <n>: hits <h> misses <m> [<system>] missed: "<str>"(<font>
  <size> [var=<n>] [w=<width>] [lines=<n>] [trunc=…] [align=…]), …, +K more`, then ` uncached: …` when a shape bypassed the
  cache. `<n>` is the cache's frame generation, `<system>` is `coretext` or `portable`. A string is cut at 40 characters with
  `…` and escaped (`\n`, `\t`, `\"`, `\\`); at most 20 are listed. The key is the cache's own: the font's PostScript name and
  size (plus variation count and a non-identity matrix), the wrapping width and the non-default options, so "same string,
  different key" and "new string" read apart. A styled text lists its run count and the first three runs' fonts.
- **Coverage.** `CoreTextTextSystem` through `ShapingCache` (plain and styled lookups: `hits`/`misses` as the cache counts
  them); `PortableTextSystem` through its three dictionaries (a hit is a measurement, a laid-out line list or a styled
  measurement answering; a miss is `PortableText.layOut` or `styledLines` running). **Paths that shape without any cache:**
  `caretOffsets` in both systems (a text field's caret and selection geometry, every call; cached since `TS-F`) and the portable system's styled
  `layOut`. They are listed under `uncached:` and counted in neither number.
- **Cost.** Off, one `Bool` read per shape call and no allocation: every description is built inside `if ShapingTrace.active`
  (`ShapingTrace.described` counts the strings built, pinned 0 while off). On, a miss builds one string and appends it to
  an array capped at 20 per frame.

### TS-F — `caretOffsets` is a cached lookup, and the shaping cache has a hard bound (G48, record 411)

Alloy's traces (`TS-E`, #419) showed two things: a text field typed into asked for the same string's caret offsets twice a
key, both through the one path no cache answered, and an empty field that was not focused did the same every frame; and
`ShapingCache` had no ceiling, only a sweep that frees what nobody touched for three frames and only above 256 entries.

- **Why it ran twice.** `TextField.prepaint` and `TextField.paintText` each call `TextField.geometry`, which calls
  `system.caretOffsets(shown)` (`TextField.swift`, the `textOffsets` line; a second call only while composing). A vertical
  field's `MultilineText.geometry` calls it once per wrapped line in each phase (`TextEditor.swift`, `lineModel`), the code view
  once per line it draws, and a selectable `Text` once per run. The empty field asked because `traceBypass` ran before
  `Shaper.caretOffsets`' own `isEmpty` early return: the work was nil, the trace line was not.
- **The answer is cached by `(string, font)`.** `ShapingCache.caretOffsets(_:font:)` (CoreText) and
  `PortableTextSystem.caretOffsets` hold the offsets, stamped with the generation like a shape, under the same lifetime and
  bound as the shape dictionaries. The computation is unchanged (`Shaper.caretOffsets`, `PortableText.caretOffsets`): exact by
  construction, not derived from the shaped `CTLine`, whose offsets differ by an ulp at the last boundary (the reason
  `caretOffsetsAreOnePerGraphemeBoundaryFromZeroToTheMeasuredWidth` exists) and which a hard break ends. A key stroke changes
  the string once, so it is one typeset line per key whatever the phase count; a vertical field retypesets only the line that
  changed. The empty string is `[0]` before any lookup or trace line. A caret lookup is a miss in the trace, listed as
  `"…"(caretOffsets <font>)`; `uncached:` is now only the portable styled `layOut`. `caretHits`/`caretMisses` count apart from
  `hits`/`misses`, so no pin on shaped lookups moves.
- **No lazy path for unfocused fields.** An unfocused, non-empty field still reads its offsets in prepaint (scroll, the
  input target) and paint (selection); with the cache that is a hash and no typesetting after the text arrives, and the
  scroll it keeps (`SL-P`) stays what it was.
- **The bound is one shared budget** (`TextCacheBudget`, `BoundedTable.swift` in `MetalUITextSystem`): after a frame a text
  system's cache tables together hold at most 1024 entries and 192 KiB of weight, a string's weight being its UTF-8 bytes
  plus 32 per entry (a shaped entry costs about 1.6 KiB of heap whatever its length). `ShapingCache` shares it across
  `storage`, `styledStorage` and `caretStorage`; `PortableTextSystem` across its four tables (measurements, line layouts,
  styled measurements, caret offsets), on top of the two-frame lifetime, which alone lets a frame that looked up a great
  deal of text keep all of it for the next. `endFrame` runs the stale sweep, then evicts oldest generation first until the
  budget holds; the overage of the last generation dropped is taken from each table in proportion, never all from the
  first. Inside a frame an eviction runs once the tables are a quarter over, and it takes stale entries first, then those
  this frame has already used, and the previous frame's not yet reached last: those are the hits still to come, and taking
  them re-shapes more than the overage (61 a frame of 100 under a budget of 64 when it took the oldest first; 36 with this
  order, `aWorkingSetOverTheBudgetReShapesTheOverageAndNoMore`). Recency is the existing generation stamp: no per-lookup
  allocation, no list. `fonts` and `resolvedFonts` stay unswept and bounded by the app's distinct font requests (one
  entry each in a 1500-frame streaming run; `theFontMemosGrowWithDistinctFontsAndNotWithText`).
- **Why 1024 and 192 KiB.** Measured as live sets per frame (record 411): a 1M-row, ten-column table 430 entries and 2.5 KB of
  source; a 200-message transcript, its composer and a streaming paragraph 205 entries and 59 KB at the largest (p50 37
  KB); a 5k-line code view scrolled 8 entries and 216 bytes. The entry budget is 2.4 times the largest, the weight budget
  3 times the largest (65 KB weighed). Worst case after a frame, measured by filling past the budget: 1.8 MiB of heap for
  20-byte labels, 4.1 MiB for 120-byte lines, 4.9 MiB for 1000-byte paragraphs (`phys_footprint` +3.2 to +5.2 MiB);
  inside a frame a quarter more.

### TS-G — the budget bounds stale entries, never the working set (G48-B, record 421)

`TS-F`'s budget (1024 entries, 192 KiB, after a frame) was sized from the live set of each view measured alone and applied to
everything the cache held, including what the current frame was using. A window with a 1M-row table, a transcript with a
streaming reply, a code view and a composer in one text system has a live set none of them has by itself (1294 entries at
twice the single-view window, 1654 at three times), and a bound under the live set evicts entries the next frame asks for:
273 and 633 misses a frame there against 1.9 and 1.0 before `TS-F`, and the caret table starved to nothing, so a composer's
every key re-typeset. Alloy measured 3.4 to 18 misses a frame typing.

- **The rule.** An entry the current frame or the previous one touched is the working set and is never evicted, whatever its
  number. The budget (`TextCacheBudget.entries`, `.cost`: 1024 and 192 KiB, a quarter more inside a frame) bounds the **stale**
  entries, those neither frame touched, oldest generation first, shared across the tables as in `TS-F`. Memory is what is on
  screen plus at most the stale budget (about 9 MiB, 11 inside a frame). The app owns its live set; a window that shows ten
  thousand distinct strings holds ten thousand, as it did before `TS-F`.
- **Exact.** Shaping is a pure function of the key, so what an eviction takes never changes an answer, only whether it is
  recomputed.
- **Cost.** An in-frame trim scans for stale entries; one that found nothing to take arms the next scan a quarter-budget of
  inserts later, so a large first draw costs a scan per quarter-budget of misses and not one per miss.
- **The portable system** drops what neither of the last two frames asked for at `endFrame` (the two-frame lifetime), which
  is the same working set with no stale entries; it keeps no budget (`PortableTextSystem` has no `entryLimit`).
- Pinned by `SharedTextBudgetTests` (a window over the budget stops missing once warm), `ShapingCacheBoundTests` (a working
  set over the budget is never evicted, the frame before is kept, stale entries are bounded by count and by weight).

Next unused id: `TS-H`.
