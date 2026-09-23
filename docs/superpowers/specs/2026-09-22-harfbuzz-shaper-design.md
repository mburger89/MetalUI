# HarfBuzz shaper — design

**Status:** implemented, 2026-09-22 (record `docs/record/26-harfbuzz-shaper.md`,
commit `ce1088e` on `feat/harfbuzz-shaper`). Decided with the user: vendor the
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
  `FT-A`). **Implemented: no pragma needed either.** Unlike `CFreeType`
  (`FT-A`'s `-Wshorten-64-to-32`, silenced with a scoped pragma under
  `FT2_BUILD_LIBRARY`), the vendored HarfBuzz amalgamation compiles with 0
  warnings on both macOS build systems and in the Linux container with no
  edit to any vendored file — measured from `rm -rf .build` on the default
  build system.
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

  **Implemented: 29 of 31 corpus cases agree on ids and clusters; two are
  pinned (below).** CoreText has no per-glyph offset — every offset derived
  from `positions − walk(advances)` is zero to `7.11e-15` pt over 404 glyph
  values — while HarfBuzz reports advance and offset separately; in the
  Arabic mark cases the two conventions differ by up to 2.366 pt of raw
  advance and 2.262 pt of raw offset for the *same* drawn position. A raw
  tolerance would have needed to be ~2.4 pt, wide enough to hide a real
  shaping difference, so the tolerances below bound only what the two
  conventions share by construction (pen advance, drawn position, run
  total), and raw per-glyph advances are asserted only on the 27 cases where
  HarfBuzz reports no offset at all:

  | Constant | Value | Measured max | Margin |
  |---|---|---|---|
  | `advanceTolerance` (pen advance, and raw advance on offset-free cases) | 1e-12 pt | 1.7763568394002505e-15 | ~560× |
  | `offsetTolerance` (CoreText's derived per-glyph offset; it has none) | 1e-12 pt | 7.105427357601002e-15 | ~140× |
  | `positionTolerance` (drawn glyph position, pen + offset) | 1e-12 pt | 5.684341886080802e-14 | ~18× |
  | `totalAdvanceTolerance` (run total vs `CTLineGetTypographicBounds`) | 1e-12 pt | 5.684341886080802e-14 | ~18× |

  `1e-12` pt is four orders of magnitude below one design unit at 13 pt
  (0.013 pt for Noto Sans), so none of these bounds can absorb a real
  shaping difference.

  **The two pinned disagreements**, each named and never loosened into a
  tolerance:
  - `harfBuzzMergesMarkClustersIntoTheirBase` (مَرْحَبًا): ids and drawn
    positions identical; HarfBuzz's clusters `[8,6,6,6,4,4,2,2,0,0]` merge
    each mark into its base's cluster where CoreText's
    `[8,7,6,6,5,4,3,2,1,0]` keep every character distinct — HarfBuzz's
    default cluster level, `MONOTONE_GRAPHEMES`, which is exactly what
    `ShapedGlyph.cluster`'s own contract states. Measured but not shipped:
    `HB_BUFFER_CLUSTER_LEVEL_MONOTONE_CHARACTERS` makes this case match
    CoreText exactly and changes no other case in the corpus; left as an
    Open item rather than the default, since nothing yet needs it.
  - `harfBuzzGuessesDirectionFromScriptWhereCoreTextRunsBidi` (٠١٢٣٤٥٦٧٨٩):
    `.auto` guesses RTL from Arabic's script (`SH-C`); CoreText runs bidi and
    finds these Arabic-indic digits (bidi class AN, not strong) give a
    paragraph level of 0, so it is LTR. Measured separating arm: the same
    digits after one strong Arabic letter give an overall-RTL CoreText line
    with the digits still ascending — the LTR answer is the *paragraph
    level*, not a property of the digit glyphs. `direction: .leftToRight`
    reproduces CoreText's ids, clusters and positions exactly.
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
  default one shows). **Implemented: 1573 tests (1558 + 15), 97 goldens
  unmoved, 77 guards (no new guard file), 0 errors, 0 warnings on both build
  systems** (1 `warning:` under `--build-system native` is SwiftPM's own
  deprecation notice for that flag, not a real warning).
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

**Implemented:** eighteen mutations run in detached `git worktree`s and
reverted (eight against the oracle suite, ten against the portable package);
every one of the 14 running oracle tests and all 6 HarfBuzz portable tests
were reddened by at least one mutant (full tables: `docs/record/
25-harfbuzz-shaper.md`). Windows CI carries the only Windows run of the
portable pins and the first Windows compile of the vendored C++ amalgamation;
not run locally (no Windows host or container available).

## Order of work

1. Vendor HarfBuzz (SH-A); `CHarfBuzz` builds with 0 warnings on both macOS
   build systems and in the Linux container.
2. `MetalUIHarfBuzz` (SH-B…SH-E).
3. Arabic font (SH-F) and the CoreText oracle (SH-G, SH-H); measure, then set
   tolerances.
4. Portable tests and CI (SH-I, SH-K); mutations; CLAUDE.md, record, spec.

All four steps done as of this Status line; record `docs/record/
25-harfbuzz-shaper.md` has the full detail, tables and open items.
