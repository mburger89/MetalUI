# Portable text pipeline — design

**Status:** draft for approval, 2026-09-23. Decided with the user: wire the
shaper and rasterizer together, and render the result through SDL.
**Ruling prefix:** `PT-` (lettered; next `PT-J`).
**Builds on:** `MetalUIHarfBuzz` (`SH-`), `MetalUIFreeType` (`FT-`),
`MetalUIScene` (`PS-`), and `Experiments/SDLGPU` for the render.

## Goal

Close the loop off Apple platforms: a string becomes `MUIGlyph`s in a `Scene`
with the coverage they sample sitting in a `GlyphAtlas`, and those pixels
reach a window through SDL on Vulkan and Direct3D 12. Today each half exists
and is checked against CoreText separately; nothing joins them, and no
non-Apple pixel of text has ever been drawn.

**Not in this step:** line breaking and wrapping (no portable Unicode
line-break implementation yet — one call is one line), bidi across runs,
script itemization, font fallback, `Text`/`Shaper` changes, atlas eviction
policy, colour glyphs.

## Rulings

- **PT-A — one new target, `MetalUIPortableText`**, depending on
  `MetalUIScene`, `MetalUIHarfBuzz` and `MetalUIFreeType` only. No Foundation,
  CoreText, CoreGraphics or Metal; built by `scene-linux`; library product;
  joins CLAUDE.md's silent-failure constraints beside `SH-K` and `FT-K`.
- **PT-B — `PortableFont` opens one font file once for both engines.** It
  holds a `HarfBuzzFont` and a `FreeTypeFont` over the same bytes at the same
  size, and exposes the `FontKey` (FreeType's, `FT-F`) that the atlas keys on.
  It **checks the two engines agree** on `unitsPerEm` and on the glyph id for
  a probe character at construction, so a mismatched pair fails at once rather
  than drawing wrong glyphs.
- **PT-C — one shared placement rule.** `GlyphRaster.subpixelPlacement(forDeviceX:)`
  moves to `MetalUIScene` (`GlyphImage.subpixelPlacement(forDeviceX:)`), with
  `GlyphRaster` forwarding, exactly as `FT-C` did for the variant count. Both
  pipelines then round a pen position the same way by construction, not by a
  copied formula.
- **PT-D — the emitter mirrors `Frame.draw`.** For each shaped glyph, in visual
  order: device x = `(originX + penX + xOffset) × scale`, split by PT-C into
  `pixelX` and a subpixel variant; device baseline y =
  `round((originY − yOffset) × scale)`; key = `GlyphKey(font:glyph:size:subpixelVariant:scaleFactor:)`;
  the atlas packs it, rasterizing through `FreeTypeRaster` on a miss; the
  `MUIGlyph`'s origin is `(pixelX + packed.left, baselineY − packed.top)` and
  its size is the slot's. A zero-area slot (a space) is packed but not
  emitted. Same arithmetic as `Frame.draw`, which is the point.
- **PT-E — the API.**
  `PortableText.emit(_ text: String, font: PortableFont, origin: (x: Double, y: Double), scaleFactor: Float, color: MUIHsla, contentMask: MUIBounds, into scene: inout Scene, atlas: GlyphAtlas) throws -> Double`
  (returns the run's advance in points). Origin is the **left end of the
  baseline**, in points, as `placedGlyphs(at:)` takes it. One call is one run
  on one line.
- **PT-F — the oracle is MetalUI's own Apple path.** For a corpus of Latin
  strings, sizes and scales, the same string is emitted twice: once through
  `PortableText`, once through CoreText shaping + `GlyphRaster` + an atlas,
  and the two `Scene`s are compared.
  - Glyph **count and order** must be equal, and each glyph's rect must match
    within tolerances **measured before they are set** (the expectation is
    exact equality of `origin`/`size`, since `SH-G` measured shaping agreement
    at ~1e-14 pt and `FT-H` measured identical bitmap boxes; any deviation is
    investigated, and pinned with its measurement if real).
  - Atlas **coverage** for each glyph is compared with the same
    region-scoped rule `FT-H` established (glyph pixels differ by at most the
    FreeType/CoreText sampling bound; nothing else differs).
  - A disagreement is never absorbed by widening a tolerance.
- **PT-G — the SDL frame.** `Experiments/SDLGPU`'s `Replay` gains a fifth
  fixture frame whose glyphs come from `PortableText` (its rects and atlas
  built with no CoreText), rendered by **both** the production Metal renderer
  and SDL. The Metal renderer draws whatever `Scene` it is handed, so this
  frame has a Metal reference like every other and the existing parity rule
  (`≤1` step outside glyph quads, `≤8` inside) applies unchanged. The frame is
  recorded into the fixture set, so Linux (llvmpipe) and Windows (D3D12) CI
  replay it: the first non-Apple text pixels this project has drawn.
- **PT-H — cross-platform pins.** `Tests/PortableTests` gains a case that
  emits a string through `PortableText` and pins the emitted glyph rects, the
  atlas dirty rect and an FNV-1a checksum of the atlas coverage, recorded on
  macOS and asserted on Linux and Windows. Recording validates every row
  before writing (record §26's hazard).
- **PT-I — no behaviour change on Apple.** `Text`, `Shaper` and `GlyphRaster`
  keep their production roles; the only production edit is PT-C's move.
  Counts: 1595 + the new tests, 97 goldens, 77 guards, 0 errors, 0 warnings on
  both macOS build systems.

## Verification

- Clean native build and full suite; counts read from the summary lines.
- Mutations, each must redden a named test: drop `xOffset` from the pen walk;
  use `floor` instead of `round` for the baseline; ignore the subpixel variant
  when keying the atlas; emit `packed.top` as `+` instead of `−`; skip the
  zero-area check so spaces are emitted; feed the emitter a `PortableFont`
  whose two engines are different files (PT-B's check); change one pinned
  portable checksum; drop the SDL text frame from the fixture set.
- Linux and Windows CI green, including the new text frame's replay.

## Order of work

1. PT-C's move, then `MetalUIPortableText` (PT-A, PT-B, PT-D, PT-E).
2. The Apple-path oracle (PT-F): measure, then set tolerances.
3. The SDL frame (PT-G) and cross-platform pins (PT-H), with CI.
4. Mutations, counts, CLAUDE.md, record, spec status.
