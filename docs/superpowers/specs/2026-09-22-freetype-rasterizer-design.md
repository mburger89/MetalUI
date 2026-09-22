# FreeType rasterizer — design

**Status:** draft for approval, 2026-09-22. Decided with the user: vendor the
FreeType source; this step is the rasterizer only.
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
  so an upgrade is a re-run rather than an archaeology.
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
  rasterizers agree on size and bearings by construction.
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
  For a fixed glyph set (letters with overshoot, descenders, a dot, a
  negative-bearing italic-like case if the font has one, a space) at several
  sizes, all four variants and scales 1 and 2:
  - `width`, `height`, `left`, `top` **equal** (FT-D makes this a real claim:
    both derive the box from the unhinted outline bounds);
  - coverage within tolerances **measured before they are set**: first run
    records per-glyph max and mean absolute difference, the ruling then fixes
    bounds above the measurement with the margin stated in the record;
  - the two `FontKey`s equal (FT-F).
  If the bounds cannot be made equal (CoreText's bounding rect is not the
  outline bbox for some glyph), the discrepancy is measured and reported, not
  papered over with a tolerance.
- **FT-I — no behaviour change on Apple.** `GlyphRaster` stays the production
  rasterizer; nothing calls `FreeTypeRaster` outside tests. Counts: 1411 + the
  new tests, 97 goldens, guards unchanged or grown, 0 errors, 0 warnings.
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

- Clean native build and full suite, counts read from the summary.
- Mutations: flip the subpixel shift's sign; drop `inkPadding`; render into
  FreeType's own bitmap rectangle instead of the computed one; turn hinting
  on; build the key's size from the scaled size. Each must redden a named
  test, on macOS (oracle) or in the portable package (determinism).
- Linux and Windows CI green with the portable package's pinned values, and a
  pinned checksum mutated to show the portable tests can fail.

## Order of work

1. Vendor FreeType (FT-A); `CFreeType` builds on macOS and in the Linux
   container.
2. `MetalUIFreeType`: font loading, key, rasterize (FT-B…FT-F); shared
   variant count.
3. Fonts (FT-G) and the CoreText oracle tests; measure, then set tolerances
   (FT-H).
4. Portable package and CI (FT-J); CLAUDE.md, record, spec status.
