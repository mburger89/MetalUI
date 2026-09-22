# 21 — FreeType rasterizer (`MetalUIFreeType`), 2026-09-22

Spec and rulings: `docs/superpowers/specs/2026-09-22-freetype-rasterizer-design.md`
(`FT-A`…`FT-K`). Branch `feat/freetype-raster` from `3d184d8`.

## Why

Every glyph rasterizer in the tree is CoreText, so `MetalUIScene`'s portable
types (`GlyphImage`, `FontKey`, moved out to `MetalUIScene` in record §20)
have exactly one producer and no non-Apple backend can fill an atlas. This
step vendors FreeType and builds a second rasterizer, `MetalUIFreeType`, that
must honour `GlyphRaster`'s contract (same box, same bearings, matching
coverage) closely enough that the atlas and every backend can take either
rasterizer's output unchanged. Not in this step: shaping (HarfBuzz), font
discovery, variable fonts, colour glyphs, hinting.

## What was measured before

- FreeType's scaled (`26.6` fixed-point) outline quantizes the ink box to
  `1/64` px. The first oracle run, with the box taken from that scaled
  outline, found `width`/`height`/`left`/`top` disagreeing with CoreText in
  18 of 416 cases for Noto Sans and 8 of 416 for Source Sans 3, always by one
  pixel. Example: Noto Sans "o" at 11 pt has an exact outline top of 6.006 px
  (what CoreText's bounding rect reports); FreeType's 26.6 outline puts it at
  6.000 px, one row short.
- `CTFontGetBoundingRectsForGlyphs` returns the exact bounding box of the
  outline for every glyph checked, and for these glyphs that box also equals
  the box of the raw control points — so an unscaled, unhinted outline
  (`FT_LOAD_NO_SCALE`, measured with `FT_Outline_Get_BBox`) scaled in Double
  with `GlyphRaster`'s own arithmetic reproduces CoreText's box exactly.
- A clean build surfaced one warning: `FreeTypeFont.init` copied font bytes
  through a pointer no longer valid after the call that produced it returned.

## What changed

- `Sources/CFreeType/`: FreeType 2.14.3 vendored (`FT-A`), `include/` and the
  `src/` of seven modules (`base`, `sfnt`, `truetype`, `cff`, `psaux`,
  `psnames`, `smooth`; ~4.7 MB), compiling only the per-module amalgamation
  files. `VENDORED.md` records the tarball's SHA-256, what was kept/removed/
  edited/added. New target `MetalUIFreeType` → `MetalUIScene`, `CFreeType`
  only (`FT-B`, `FT-K`); also a library product.
- `Sources/MetalUIFreeType/FreeTypeFont.swift`: loads a font from bytes with
  `FT_Open_Face` off an `FT_Open_Args` pointing at a copy of the data made
  inside `data.withUnsafeBytes` (fixing the dangling-pointer warning);
  `key: FontKey` reads the PostScript name, size, empty `variations`, the
  identity matrix (`FT-F`); `glyph(for:)` is the cmap lookup FreeType tests
  check against CoreText's.
- `Sources/MetalUIFreeType/FreeTypeRaster.swift`: `rasterize(glyph:font:
  subpixelVariant:scaleFactor:)`. The ink box comes from the outline loaded
  unscaled (`FT_LOAD_NO_SCALE | FT_LOAD_NO_BITMAP`), its exact bounding box
  (`FT_Outline_Get_BBox`) scaled to device pixels and shifted by the subpixel
  offset in Double, then floored/ceiled and grown by `GlyphImage.inkPadding`
  — the same arithmetic `GlyphRaster` uses (`FT-D`). The outline is then
  reloaded at the target size, unhinted (`FT_LOAD_NO_HINTING |
  FT_LOAD_NO_BITMAP`, `FT-E`), translated by one `FT_Outline_Translate` (the
  subpixel shift and the box's origin, in 26.6 units) and rendered with
  `FT_Outline_Get_Bitmap` into a buffer of exactly the computed size —
  FreeType's own bitmap rectangle from `FT_Render_Glyph` is never used, so
  the two rasterizers agree on size and bearings by construction rather than
  by coincidence.
- `Tests/Fonts/`: `NotoSans-Regular.ttf` (TrueType `glyf`, Noto Sans v2.015
  unhinted build) and `SourceSans3-Regular.otf` (CFF `CFF `, Source Sans 3
  3.052R), neither with an `fvar` table; both SIL OFL 1.1 with their licence
  files; `SOURCES.md` records each release URL, zip and file SHA-256, and the
  sfnt table list read back from each file (`FT-G`).
- `Tests/MetalUIFreeTypeTests/FreeTypeOracleTests.swift` (Swift Testing,
  `@testable import MetalUIText` for `ResolvedFont(ctFont:)`): glyph set o O
  b g p y . x W M j f and a space (j/f for negative left bearing, since
  neither font has an italic); sizes 11/13/17/26, all 4 subpixel variants,
  scales 1 and 2 — 416 cases per font. Asserts CoreText's glyph id equals
  `FreeTypeFont.glyph(for:)`; `FontKey` equality three ways; `width`/`height`/
  `left`/`top` exactly equal with no tolerance and the space empty in both;
  coverage within tolerance of CoreGraphics filling the outline path, and of
  `GlyphRaster`, at every size except four pinned ones; a pin that
  `GlyphRaster` departs from the outline at exactly those four sizes; a
  measurement test gated on `METALUI_FREETYPE_MEASURE=1` that prints every
  number the tolerance constants were set from (FT-H).
- `Tests/PortableTests/`: a separate package (tools version 6.0,
  `.macOS(.v14)`, `.package(name: "MetalUI", path: "../..")`) so FreeType's
  output can be exercised where the root package's own tests (which include
  the Metal suite) cannot run. `Tests/FreeTypeDeterminismTests/
  FreeTypeDeterminismTests.swift` loads the two fonts by `#filePath` through
  `Data(contentsOf:)`, no CoreText: 2 fonts × {o, g, W, j, period, space} ×
  {13, 26} pt × variants {0, 3} × scales {1, 2} = 96 cases, each pinning glyph
  id, width, height, left, top and an FNV-1a 64 checksum of the coverage
  bytes (checked against its own published test vectors) against
  `Expected.swift`'s 96 rows, recorded on macOS arm64 (`FT-J`). A separate
  test checks the space is empty and every other glyph has ink; a record test
  gated on `METALUI_PORTABLE_RECORD=1` prints the table.
- `.github/workflows/swift.yml`: `scene-linux` gained a second step, `swift
  build --target MetalUIFreeType`. Two new jobs: `freetype-portable-linux`
  (`swift test` in `Tests/PortableTests`, `ubuntu-24.04` and
  `ubuntu-24.04-arm`, `swift:6.4-noble` container) and
  `freetype-portable-windows` (`windows-latest`,
  `compnerd/gha-setup-swift@v0.5.0`, `swift-6.4.0-release`).
- The default (swiftbuild) build system on macOS turns on
  `-Wshorten-64-to-32`, which the vendored LP64 C code trips 116 times; native
  SwiftPM (this project's baseline) and Linux do not. The portable lane first
  silenced it with `.unsafeFlags(["-Wno-shorten-64-to-32"])` in `CFreeType`'s
  `cSettings`. **Replaced at review:** SwiftPM refuses `unsafeFlags` in any
  package consumed by URL, so that would have made MetalUI undependable as a
  library. It is now `#pragma clang diagnostic ignored "-Wshorten-64-to-32"`
  in the vendored `ftoption.h`, under `FT2_BUILD_LIBRARY` (set only for
  FreeType's own compilation). Measured from `rm -rf .build` on the default
  build system: 116 warnings with the pragma removed, 0 with it.

## Measurements

Geometry agreement (416 cases per font; 32 are the space, empty in both):

| Font | Before the box fix | After |
|---|---|---|
| NotoSans-Regular.ttf (glyf) | 398/416 | 416/416 |
| SourceSans3-Regular.otf (CFF) | 408/416 | 416/416 |

Coverage per (font, size, scale) — largest single-pixel diff / largest
per-glyph mean diff, 0–255 scale (re-measured in this session with
`METALUI_FREETYPE_MEASURE=1 swift test --filter FreeTypeOracleTests/measure`,
values identical to first record):

| Font | pt × scale | vs `GlyphRaster` | vs CG outline fill | CoreText ink centroid Δ (px) | CoreText/FreeType ink |
|---|---|---|---|---|---|
| Noto | 11×1 | 44 / 6.200 | 11 / 1.200 | −0.05..+0.08 | 0.98..1.01 |
| Noto | 11×2 | 54 / 4.600 | 16 / 1.009 | −0.08..+0.02 | 0.92..1.01 |
| Noto | 13×1 | 60 / 7.024 | 15 / 1.303 | −0.05..+0.04 | 0.97..1.04 |
| Noto | 13×2 | 62 / 4.119 | 21 / 1.089 | −0.09..+0.02 | 0.92..1.02 |
| Noto | **17×1 (pinned)** | **220 / 18.576** | 15 / 1.102 | +0.02..+0.44 | 0.94..1.08 |
| Noto | 17×2 | 55 / 5.286 | 17 / 0.339 | −0.12..+0.02 | 0.92..1.00 |
| Noto | 26×1 | 62 / 4.119 | 21 / 1.089 | −0.09..+0.02 | 0.92..1.02 |
| Noto | 26×2 | 67 / 2.800 | 24 / 0.533 | −0.07..+0.05 | 0.97..1.01 |
| Source | **11×1 (pinned)** | **200 / 16.838** | 25 / 3.375 | +0.01..+0.39 | 1.01..1.13 |
| Source | 11×2 | 40 / 2.615 | 33 / 3.881 | −0.01..+0.04 | 0.99..1.03 |
| Source | **13×1 (pinned)** | **135 / 15.708** | 24 / 3.031 | +0.02..+0.32 | 1.01..1.11 |
| Source | 13×2 | 38 / 2.263 | 38 / 4.278 | −0.02..+0.02 | 0.97..1.01 |
| Source | **17×1 (pinned)** | **216 / 17.767** | 23 / 3.767 | +0.01..+0.43 | 1.01..1.09 |
| Source | 17×2 | 59 / 5.388 | 36 / 2.488 | −0.14..+0.03 | 0.92..1.01 |
| Source | 26×1 | 38 / 2.263 | 38 / 4.278 | −0.02..+0.02 | 0.97..1.01 |
| Source | 26×2 | 54 / 1.632 | 34 / 2.086 | −0.04..+0.07 | 0.99..1.02 |

13 pt×2 and 26 pt×1 are the same device size and give identical numbers in
every column, on both fonts.

Tolerance constants (`Tests/MetalUIFreeTypeTests/FreeTypeOracleTests.swift`):

| Constant | Value | Measured max (unpinned sizes) | Margin |
|---|---|---|---|
| `outlineMaxTolerance` | 50 | 38 | +12 (~5% of full coverage) |
| `outlineMeanTolerance` | 6.0 | 4.278 | +1.7 |
| `glyphRasterMaxTolerance` | 80 | 67 | +13 |
| `glyphRasterMeanTolerance` | 9.0 | 7.024 | +2 (also separates the four pinned sizes, whose smallest worst-mean is 15.708) |

**Pinned, not hidden by a tolerance:** at Noto Sans 17 pt×1 and Source Sans 3
11/13/17 pt×1, `CTFontDrawGlyphs` does not draw the outline CoreText itself
reports — its ink sits up to 0.44 px higher, its total changes −6%..+13%, one
pixel differs by up to 220/255 — while CoreGraphics filling the same path
stays within 38/255 of FreeType at those sizes. The difference is CoreText's
glyph drawing, not FreeType's; `glyphRasterAdjustsTheseSizesAwayFromTheOutline`
reddens if CoreText stops doing this or starts at another size.

Portable package (`Tests/PortableTests`, exact integer/checksum comparison,
no tolerance, FT-J): 96/96 cases match the macOS-recorded table on macOS
arm64 (host), Linux aarch64 and Linux x86_64 (both via `docker --context
orbstack`, `swift:6.4-noble`); Windows was not run locally, only in CI.
Re-run in this session: macOS 4/4 tests pass (`swift test` in
`Tests/PortableTests`, 0 `warning:`, 0 `error:` from a clean `.build`); Linux
aarch64 via Docker, 4/4 tests pass, same values.

## Mutations

Oracle suite (`swift test --build-system native --no-parallel --filter
MetalUIFreeTypeTests`) and portable suite (`swift test` in
`Tests/PortableTests`), both green beforehand (8 tests/1 skipped; 4 tests/1
skipped):

| Mutant | Oracle reddened | Portable reddened |
|---|---|---|
| Box from the 26.6 **scaled** outline (pre-fix code) | geometry, both coverage tests, the pin | — |
| Subpixel shift sign flipped in the render translate only | both coverage tests, the pin (geometry stays green: box unchanged) | — |
| Subpixel shift sign flipped at its source (box + translate) | geometry, both coverage tests, the pin | `everyCaseMatchesTheValuesRecordedOnMacOS` (40/96 cases) |
| `inkPadding` / `pad` set to 0 | geometry, both coverage tests, the pin | `everyCaseMatchesTheValuesRecordedOnMacOS` (80/96 cases) |
| Hinting turned on (`FT_LOAD_NO_HINTING` dropped from the scaled load) | both coverage tests, the pin (geometry stays green: box comes from the `NO_SCALE` outline) | `everyCaseMatchesTheValuesRecordedOnMacOS` (40/96 cases) |
| Render into FreeType's own bitmap rectangle (`FT_Render_Glyph`, `bitmap_left`/`bitmap_top` as bearings) | geometry, both coverage tests, the pin | (not re-run; same shape as the box mutants) |
| `FontKey` size doubled (the "size×scale at scale 2" case) | `fontKeys` only | none — 4/4 tests pass; `FreeTypeFont` carries no scale parameter, so nothing in the portable package reads a doubled key |
| Portable `Expected.swift`'s first checksum changed by one hex digit | not applicable | `everyCaseMatchesTheValuesRecordedOnMacOS` |

The FontKey mutant is the one green result the verifier flagged as a finding
worth naming, not a broken instrument: the portable package pins geometry and
a coverage checksum, never a `FontKey`, so it has no way to see that mutant —
consistent with `FT-J`'s scope.

## Counts

After `swift package clean`, `--build-system native` (re-taken in this
session): **1419 tests** (1411 + 8, one of the 8 skipped), **97 goldens**
(`find Tests -name "*.json" | wc -l` read 115 once `Tests/PortableTests`'s
own gitignored `.build/` had run; CLAUDE.md's command is now scoped to
`Tests/MetalUILayoutTests`), **73 typecheck guards** (no new guard
file — `MetalUIFreeType` adds no plain-import boundary that needed one beyond
`FT-K`'s Linux build check), 0 `error:`, 1 `warning:` (SwiftPM's
`--build-system native` deprecation notice), the `FR-J` line present once.
`swift build --build-system native --build-tests` from a clean state: 0
`error:`, the same one `warning:`. `swift test --build-system native
--no-parallel --filter MetalUIFreeTypeTests`: 8 tests, 1 suite, 1 skipped
(the measurement test), ~0.2s. Portable package on macOS: 4 tests, 1 suite, 1
skipped (the record test), 0 `warning:` from a clean `.build`. Linux build of
`MetalUIFreeType` alone (`swift build --scratch-path /tmp/b --target
MetalUIFreeType` in `swift:6.4-noble`): 0 `error:`, 0 `warning:`. Portable
package on Linux aarch64: 4/4 pass.

## Open

- Shaping is still CoreText-only; a HarfBuzz shaper is a separate step (spec,
  "Not in this step").
- No font discovery (fontconfig, DirectWrite) — fonts are loaded by path in
  tests only.
- No variable-font support; `FT-F`'s `FontKey` always writes empty
  `variations`, and both bundled fonts are static (`SOURCES.md`, the
  `outlineFormat` test's `!tables.contains("fvar")` assertion).
- Nothing in production calls `FreeTypeRaster`; `GlyphRaster` remains the only
  rasterizer any renderer or atlas uses (`FT-I`). Wiring a non-Apple backend
  to `MetalUIFreeType` is future work.
- Windows could not be run locally; CI carries the only Windows coverage for
  `Tests/PortableTests`.

## Review fixes (after the workflow)

- `unsafeFlags` replaced by the scoped pragma (above).
- The verifier's one surviving mutant: FontKey's size built from `size * 2`
  reddened nothing in `Tests/PortableTests`, which never read the key. Added
  `theFontKeyIsReadOffTheFaceAtTheRequestedSize` (PostScript name, size in
  points, no variations, identity matrix, per font at 13 and 26 pt); the same
  mutant now reddens it alone. The portable package runs 5 tests.
- The verifier counted 71 guards because it used a pre-`PS-` file list; the
  list in CLAUDE.md includes `SceneBoundaryCompileGuards` (2), so 73.
