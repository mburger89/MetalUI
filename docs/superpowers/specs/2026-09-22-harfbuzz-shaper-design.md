# HarfBuzz shaper — design

**Status:** draft for approval, 2026-09-22. Decided with the user: vendor the
HarfBuzz source; this step shapes one run, checked on Latin and on Arabic.
**Ruling prefix:** `SH-` (lettered; next `SH-L`). (`HB-` was free but matches
FreeType's license text case-insensitively, `ft-hb-ft.c`.)
**Builds on:** `MetalUIFreeType` (`FT-`), which rasterizes the glyph ids this
shaper produces, from the same font bytes.

## Goal

Turn a string into positioned glyphs without Apple frameworks, so non-Apple
text can go string → glyph ids (HarfBuzz) → coverage bitmaps (FreeType) →
atlas → `Scene`. This step is **one run**: one font, one direction, one
script, one line.

**Not in this step:** line breaking (`CTTypesetter`'s job today), bidi
reordering across runs, script itemization of mixed text, font fallback,
min-content word boundaries (`CFStringTokenizer`), OpenType feature control,
variable-font instances, and any change to `Shaper`/`ShapedText`.

## Rulings

- **SH-A — HarfBuzz 14.5.0, vendored as the C++ target `CHarfBuzz`.**
  `Sources/CHarfBuzz/` holds HarfBuzz's `src/*.cc`, `*.hh`, `*.h` (~6.5 MB;
  generator scripts, tests and build files dropped) plus `COPYING` (Old MIT).
  Only the amalgamation `src/harfbuzz.cc` compiles (`sources:`), with no
  optional backend: no FreeType (`hb-ft`), ICU, GLib, CoreText, DirectWrite or
  Uniscribe — HarfBuzz reads the font's own tables (`hb-ot`). `include/` holds
  a module map and an umbrella header over `hb.h`/`hb-ot.h`. `VENDORED.md`
  records version, tarball SHA-256, the file list and every edit. **No
  `unsafeFlags`** (SwiftPM refuses them in a URL dependency; lesson from
  `FT-A`): any warning is silenced by a scoped pragma in a vendored header,
  measured with and without.
- **SH-B — one new target, `MetalUIHarfBuzz`, depending on `CHarfBuzz` only**
  (it needs nothing from `MetalUIScene`). No Foundation, CoreText, CoreGraphics
  or Metal. Library product. Joins `scene-linux` and CLAUDE.md's
  silent-failure constraints beside `PS-A` and `FT-K`.
- **SH-C — the API.**
  `HarfBuzzFont(data: [UInt8], faceIndex: Int = 0, size: Double)`;
  `HarfBuzzShaper.shape(_ text: String, font:, direction: .auto | .leftToRight | .rightToLeft) -> ShapedRun`.
  `ShapedRun`: `glyphs: [ShapedGlyph]` in **visual order** (left to right, as
  a renderer places them), `advance: Double` (total, points),
  `isRightToLeft: Bool`. `ShapedGlyph`: `id: UInt16`, `cluster: Int` (a
  **UTF-16 offset** into `text`, the unit CoreText's string indices use),
  `xAdvance`, `yAdvance`, `xOffset`, `yOffset` in **points**. With `.auto`,
  direction, script and language come from
  `hb_buffer_guess_segment_properties`.
- **SH-D — exact unit conversion.** The `hb_font` scale is the face's
  `unitsPerEm`, so HarfBuzz returns design units; conversion to points is
  `units × size / unitsPerEm` in `Double`. No 26.6 anywhere: `FT-D` measured
  that 1/64 quantization changes answers.
- **SH-E — HarfBuzz's default features.** No feature list is passed; HarfBuzz
  applies each script's required and default features (`kern`, `liga`,
  `calt`, `mark`, `mkmk`, Arabic joining forms, …), which is what CoreText
  applies to an OpenType font by default. Any difference is measured (SH-G),
  not assumed away.
- **SH-F — a third bundled font:** Noto Sans Arabic Regular (static, OFL), in
  `Tests/Fonts/` with its license and a `SOURCES.md` row, as `FT-G`.
- **SH-G — CoreText is the oracle on macOS.** The same bytes are loaded into
  both (`CTFontManagerCreateFontDescriptorsFromData`); CoreText's answer is a
  `CTLine` of the same string, read run by run (glyphs, positions → advances,
  string indices, the right-to-left status). Corpus, each string in each
  applicable font at 13 pt:
  - Latin: plain text; kerning pairs (`AV`, `To`, `Ty`, `LT`); ligatures
    (`fi`, `fl`, `ffi` — per font, whichever it has); combining marks
    (`e` + U+0301, `a` + U+0308, `n` + U+0303); digits and punctuation.
  - Arabic: a plain word; a sentence with spaces; lam-alef (`لا`); a word with
    harakat (marks); Arabic digits.
  Assertions: same glyph-id sequence, same cluster sequence, same visual
  order; advances and offsets within tolerances **measured before they are
  set**, as named constants whose comments give the measurement; total
  advance likewise. Where the two shapers disagree on ids or clusters, the
  case is investigated and either fixed (SH-C…SH-E) or pinned as a measured,
  explained difference — never loosened into a tolerance.
- **SH-H — glyph ids agree with FreeType.** For every Latin corpus string,
  each shaped glyph id rasterizes through `FreeTypeRaster` to a non-empty
  image unless it is a space, and ids from `FreeTypeFont.glyph(for:)` equal
  the shaper's for the unligated, unmarked characters.
- **SH-I — cross-platform determinism.** `Tests/PortableTests` gains a
  HarfBuzz test: for the corpus, the exact glyph ids, clusters and an FNV-1a
  checksum of the design-unit positions, recorded on macOS, asserted on Linux
  (x86_64, aarch64) and Windows in CI. Plus one end-to-end case: shape a
  Latin string, rasterize every glyph with FreeType, and pin the checksum of
  the concatenated coverage.
- **SH-J — no behaviour change on Apple.** `Shaper` stays the production
  shaper; nothing calls `HarfBuzzShaper` outside tests. Counts: 1558 + the new
  tests, 97 goldens, 77 guards (or more), 0 errors, 0 warnings — on the
  native build system **and** the default one (`FT-A` found warnings only the
  default one shows).
- **SH-K — the Linux boundary.** `MetalUIHarfBuzz` imports only `CHarfBuzz`;
  the `scene-linux` job builds it.

## Verification

- Clean native build and full suite, counts read from the summary lines; a
  default-build-system build counted separately for warnings.
- Mutations, each must redden a named test: pass `hb_font_set_scale` in 26.6
  instead of design units; report clusters as UTF-8 offsets; return glyphs in
  logical instead of visual order for RTL; disable `kern` via a feature list;
  disable `liga`; force direction LTR for Arabic; one pinned portable
  checksum changed.
- Linux and Windows CI green with the portable pins.

## Order of work

1. Vendor HarfBuzz (SH-A); `CHarfBuzz` builds with 0 warnings on both macOS
   build systems and in the Linux container.
2. `MetalUIHarfBuzz` (SH-B…SH-E).
3. Arabic font (SH-F) and the CoreText oracle (SH-G, SH-H); measure, then set
   tolerances.
4. Portable tests and CI (SH-I, SH-K); mutations; CLAUDE.md, record, spec.
