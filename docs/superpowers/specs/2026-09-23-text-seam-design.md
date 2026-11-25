# Text seam — design

**Status: implemented** on `feat/text-seam` (record §35); roadmap item 6 of
`plans/2026-09-23-cross-platform-roadmap.md`. **Ruling prefix:** `TS-`
(`TS-A`…`TS-E`, next `TS-F`; rulings here).

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
- **The bound.** `ShapingCache` holds at most `entryCap` = 4096 entries and `costCap` = 512 KiB of source text in each of
  `storage`, `styledStorage` and `caretStorage` after a frame, twice that inside one. `endFrame` first runs the existing
  stale sweep, then `Table.bound`: oldest generation first, within a generation arbitrary. Arbitrary, because a live set over
  the cap is one generation, and dropping its overage re-shapes at most `live - cap` strings a frame where a strict LRU loop
  re-shapes all of them (`aWorkingSetOverTheCapReShapesTheOverageAndNoMore`). A miss that takes a table to twice a cap evicts
  at once (`trimInFrame`), amortised to once per `entryCap` inserts. Recency is the existing generation stamp: no per-lookup
  allocation, no list. `fonts` and `resolvedFonts` stay unswept and bounded by the app's distinct font requests (one entry
  each in a 1500-frame streaming run; `theFontMemosGrowWithDistinctFontsAndNotWithText`).
- **Why 4096 and 512 KiB.** Measured (record 411): a 200-message transcript and a composer look up about 400 entries a
  frame, a 1M-row, ten-column table's visible cells about 850 (470 distinct), so the cap is eight times the larger live set.
  A shaped paragraph and its caret line weigh about 50 bytes of heap per source byte (26 KiB per 512 bytes), a 20-byte label
  about 3 KiB: the worst case after a frame is 4096 labels (about 13 MiB) or 512 KiB of paragraphs (about 25 MiB) per
  dictionary, twice inside a frame. The portable system's dictionaries keep their two-frame lifetime and have no cap: their size
  is the last two frames' lookups.
