# FreeType rasterizer — design

**Status:** implemented, 2026-09-22, on `feat/freetype-raster`. Record:
`docs/record/21-freetype-rasterizer.md`.
**Ruling prefix:** `FT-` (lettered; next `FT-L`).
**Builds on:** `MetalUIScene` (`PS-`), whose `GlyphImage` and `FontKey` have
`package` initialisers meant for a second producer inside this package.

## Goal

A glyph rasterizer that builds without Apple frameworks and honours
`GlyphRaster`'s contract exactly, so the atlas, `Scene` and every backend take
its output unchanged. Given a font file, a glyph id, a point size, a subpixel
variant and a scale factor, it returns a `GlyphImage`; given a face, it
returns the `FontKey` the atlas keys on.

**Not in this step:** shaping (a HarfBuzz shaper supplies glyph ids later;
until then ids come from CoreText's shaper or from tests), font discovery
(fontconfig, DirectWrite), variable-font instances, colour glyphs, hinting.

## Rulings

- **FT-A — FreeType 2.14.3, vendored as the C target `CFreeType`.**
  `Sources/CFreeType/` holds FreeType's `include/` and the `src/` directories
  of seven modules: `base`, `sfnt`, `truetype`, `cff`, `psaux`, `psnames`,
  `smooth` (~4.7 MB). The target compiles only the amalgamation files
  (`ftbase.c`, `ftinit.c`, `ftsystem.c`, `ftdebug.c`, `ftbbox.c`,
  `ftbitmap.c`, `ftmm.c`, and `sfnt.c`, `truetype.c`, `cff.c`, `psaux.c`,
  `psnames.c`, `smooth.c`) through `sources:`. A custom `ftmodule.h`
  registers exactly those drivers; `FT_CONFIG_OPTION_*` defaults otherwise.
  `LICENSE.TXT` and `FTL.TXT` are kept beside the source; used under the FTL.
  `VENDORED.md` records the version, the tarball's SHA-256 and the file list,
  so an upgrade is a re-run rather than an archaeology. **Measured, not
  drafted:** the default (swiftbuild) build system on macOS turns on
  `-Wshorten-64-to-32`, which the vendored LP64 code trips 116 times, in both
  the root package and when the portable package pulls `MetalUIFreeType` in
  as a dependency; native SwiftPM (this project's counted baseline) and Linux
  do not turn it on. Fixed with `.unsafeFlags(["-Wno-shorten-64-to-32"])` in
  `CFreeType`'s `cSettings` rather than editing vendored sources; SwiftPM
  accepts an `unsafeFlags` C setting in a path dependency.
- **FT-B — one new target, `MetalUIFreeType`, depending on `MetalUIScene` and
  `CFreeType` only.** No Foundation, CoreText, CoreGraphics or Metal; it joins
  `MetalUIScene` under the Linux build rule (`PS-G`). It is in the root package
  because only there can it construct `GlyphImage` and `FontKey`. It is a
  library product, so a package outside the root can run its tests on Linux
  and Windows (FT-J).
- **FT-C — the API.**
  `FreeTypeFont(data: [UInt8], faceIndex: Int = 0, size: Double)` (throws on a
  font FreeType rejects); `font.key: FontKey`;
  `FreeTypeRaster.rasterize(glyph: UInt16, font:, subpixelVariant:, scaleFactor:) -> GlyphImage`.
  Same argument meanings and preconditions as `GlyphRaster.rasterize`
  (variant in `0..<GlyphRaster.subpixelVariants`, scale positive). The
  variant count is a shared constant, not a copy: it moves to `MetalUIScene`
  (`GlyphImage.subpixelVariants`), and `GlyphRaster.subpixelVariants` forwards
  to it.
- **FT-D — identical geometry rules to `GlyphRaster`.** Ink box = the
  outline's exact bounding box (`FT_Outline_Get_BBox`, unhinted) scaled to
  device pixels and shifted by `variant / subpixelVariants` px; bitmap =
  `floor`/`ceil` of that box grown by `inkPadding` (1) on every side; row 0 is
  the top row; `left` = device px from pen to bitmap left, `top` = device px
  from baseline up to bitmap top; an empty ink box returns the empty image.
  The outline is translated and rendered into a buffer of exactly that size
  (`FT_Outline_Get_Bitmap`), never FreeType's own bitmap rectangle, so the two
  rasterizers agree on size and bearings by construction. **Measured, not
  drafted:** the outline must be loaded unscaled (`FT_LOAD_NO_SCALE`) and its
  bbox scaled to device pixels in `Double`, not taken from FreeType's own
  26.6-scaled outline. The 26.6 outline quantizes to 1/64 px, and that
  quantization crossed a pixel boundary in 26 of 832 first-run oracle cases
  (dims/bearings off by exactly one pixel each — e.g. Noto Sans "o" at 11 pt:
  exact top 6.006 px, 26.6-scaled top 6.000 px, one row short). After scaling
  the unhinted design-unit bbox instead, dims and bearings agree in 832/832
  cases (record §21).
- **FT-E — unhinted, grayscale.** `FT_LOAD_NO_HINTING | FT_LOAD_NO_BITMAP`,
  smooth renderer, 256-level coverage: CoreText on macOS is unhinted and
  grayscale-only (spec §6.1). No LCD filtering.
- **FT-F — `FontKey` read off the face.** PostScript name
  (`FT_Get_Postscript_Name`), the requested size, empty `variations` (static
  fonts only this step), identity matrix. For the same font file at the same
  size this must **equal** CoreText's `FontKey(resolved:)` — one atlas can
  then serve both rasterizers. Pinned on macOS (FT-H). A face without a
  PostScript name is rejected: the key's first component would be empty.
- **FT-G — two bundled test fonts, open-licensed:** one TrueType-outline
  (`glyf`) and one CFF-outline (`CFF `) face, so both drivers are exercised.
  Stored under `Tests/Fonts/` with their license files and a `SOURCES.md`
  (URL, version, SHA-256). Not a layout fixture: `TX-B` bans text from the
  WebKit goldens only.
- **FT-H — CoreText is the oracle on macOS.** The same file is loaded into
  both rasterizers (CoreText via `CTFontManagerCreateFontDescriptorsFromData`).
  Glyph set: `o O b g p y . x W M j f` and a space (13 characters — overshoot,
  ascenders/descenders, a dot, an x-height letter, wide glyphs, and `j`/`f`
  for negative left bearing since neither bundled font has an italic). Sizes
  11/13/17/26 pt, all four subpixel variants, scales 1 and 2 — 416 cases per
  font, 832 total. For every case:
  - `width`, `height`, `left`, `top` **equal**, no tolerance (FT-D makes this
    a real claim: both derive the box from the unhinted outline bounds).
    Measured: 832/832 agree after the FT-D fix (416/416 per font; the space
    is empty in both rasterizers in all 64 of its cases);
  - coverage within tolerances **measured before they were set** — a run
    gated on `METALUI_FREETYPE_MEASURE=1` prints every per-(font, size,
    scale) max and mean absolute difference; the constants below carry the
    measured maximum plus a stated margin, as named constants in
    `FreeTypeOracleTests.swift` with the measurement in each one's comment:

    | Constant | Value | Measured max | Margin |
    |---|---|---|---|
    | `outlineMaxTolerance` (vs. CoreGraphics filling the outline path) | 50 | 38 | +12 (~5% of full coverage) |
    | `outlineMeanTolerance` | 6.0 | 4.278 | +1.7 |
    | `glyphRasterMaxTolerance` (vs. `GlyphRaster`, unpinned sizes) | 80 | 67 | +13 |
    | `glyphRasterMeanTolerance` | 9.0 | 7.024 | +2 (also separates the four pinned sizes below, whose smallest worst-mean is 15.708) |

  - the two `FontKey`s equal (FT-F) — measured equal for both fonts at all
    four sizes.

  **The bounds could not be made equal for coverage against `GlyphRaster`,
  and the discrepancy is measured and pinned rather than hidden in a
  tolerance:** at Noto Sans 17 pt×1 and Source Sans 3 11/13/17 pt×1 (four of
  the sixteen (font, size, scale) cells), `CTFontDrawGlyphs` does not draw
  the outline CoreText itself reports for the bounding rect — its ink sits up
  to 0.44 px higher than FreeType's, its total ink changes between −6% and
  +13%, and one pixel differs by as much as 220/255 — while CoreGraphics
  filling that same path stays within 38/255 of FreeType at those sizes. The
  cause is CoreText's glyph *drawing*, not its reported outline. A pin test,
  `glyphRasterAdjustsTheseSizesAwayFromTheOutline`, checks that exactly those
  four (font, size) pairs cross `glyphRasterMeanTolerance` and no others;
  it reddens if CoreText changes this behaviour. Full per-cell figures and
  the mutation table are in record §21.
- **FT-I — no behaviour change on Apple.** `GlyphRaster` stays the production
  rasterizer; nothing calls `FreeTypeRaster` outside tests. Measured counts
  (`swift package clean`, `--build-system native`): **1419 tests** (1411 + 8,
  one gated on `METALUI_FREETYPE_MEASURE=1` and skipped), **97 goldens**, **73
  typecheck guards** (unchanged — no new guard file), 0 `error:`, 1
  `warning:` (SwiftPM's `--build-system native` deprecation notice, the
  project's standing baseline; record §21).
- **FT-J — cross-platform determinism.** FreeType's rasterizer is integer
  arithmetic, so its output should be byte-identical on every platform. A
  small package at `Tests/PortableTests/` depends on the root's
  `MetalUIFreeType` product and asserts, for the fixed glyph set, the exact
  image dimensions, bearings and a coverage checksum recorded on macOS. CI
  runs it on Linux (x86_64, aarch64) and Windows. (The root package's own
  tests cannot run there: its test bundle includes the Metal tests.)
- **FT-K — `MetalUIFreeType` imports only `MetalUIScene` and `CFreeType`**,
  added to CLAUDE.md's silent-failure constraints next to `PS-A`, and built
  by the `scene-linux` job.

## Verification

Done; full tables in record §21.

- Clean native build and full suite, counts read from the summary: done (FT-I).
- Mutations, each run and reverted, each reddening the named tests on macOS
  (oracle) and/or in the portable package (determinism): flip the subpixel
  shift's sign (at its source, and in the render translate only); drop
  `inkPadding`; render into FreeType's own bitmap rectangle instead of the
  computed one; turn hinting on; build the key's size from the scaled size
  (green in the portable package — it has no scale parameter to read, and
  that gap is itself a verified finding, not a broken mutant); a one-digit
  change to a pinned portable checksum.
- Linux (x86_64, aarch64, via `docker --context orbstack`, `swift:6.4-noble`)
  and Windows CI green with the portable package's pinned values (Windows in
  CI only, not run locally); the checksum mutant above shows the portable
  tests can fail.

## Order of work

Done, in this order:

1. Vendor FreeType (FT-A); `CFreeType` builds on macOS and in the Linux
   container.
2. `MetalUIFreeType`: font loading, key, rasterize (FT-B…FT-F); shared
   variant count.
3. Fonts (FT-G) and the CoreText oracle tests; measure, then set tolerances
   (FT-H).
4. Portable package and CI (FT-J); CLAUDE.md, record, spec status.
