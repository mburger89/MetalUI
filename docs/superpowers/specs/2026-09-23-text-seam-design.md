# Text seam — design

**Status: implemented** on `feat/text-seam` (record §35); roadmap item 6 of
`plans/2026-09-23-cross-platform-roadmap.md`. **Ruling prefix:** `TS-`
(`TS-A`…`TS-D`, next `TS-E`; rulings here).

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
