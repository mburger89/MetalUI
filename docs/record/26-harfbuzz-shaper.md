# 26 — HarfBuzz shaper (`MetalUIHarfBuzz`), 2026-09-22

Spec and rulings: `docs/superpowers/specs/2026-09-22-harfbuzz-shaper-design.md`
(`SH-A`…`SH-K`). Branch `feat/harfbuzz-shaper` from `b10594c` (`master` at the
FreeType merge, record §24). Commit at record time: `ce1088e`.

**This number may be renumbered at merge.** `master` took its own §26 for an
unrelated line while this branch was in flight (as §19/§20/§21 were
renumbered at the stage-2/grids integration, record §23 §7); if so, resolve
the collision the same way that record documents, by moving this file's
number up and fixing this line and the README row.

## Why

`MetalUIFreeType` (record §24) gave the rasterizer a non-Apple backend, but
every *shaper* in the tree is still CoreText: a rasterizer with no shaper in
front of it is invisible to a Linux or Windows renderer. This step vendors
HarfBuzz and builds `MetalUIHarfBuzz`, which must turn a string into glyph
ids and positions the way CoreText does closely enough that the same font
bytes, shaped by either engine, place the same glyphs at the same pen — and
whose glyph ids rasterize through `FreeTypeRaster` (SH-H), completing the
string → glyph ids → coverage bitmaps chain with no Apple framework
anywhere in it. Not in this step: line breaking, bidi reordering across
runs, script itemization of mixed text, font fallback, OpenType feature
control, variable-font instances, and any change to `Shaper`/`ShapedText`
(the production text pipeline is untouched, SH-J).

## What changed

- `Sources/CHarfBuzz/`: HarfBuzz 14.5.0 vendored whole (`SH-A`;
  `VENDORED.md`) — the amalgamation `#include`s the rest of `src/`, so
  nothing was pruned beyond generator scripts, docs, build files, tests and
  fuzzers. `COPYING` (Old MIT) kept. Only `src/harfbuzz.cc` compiles, C++17,
  with no optional backend (no FreeType, ICU, GLib, CoreText, DirectWrite,
  Uniscribe) — HarfBuzz reads the font's own tables through `hb-ot`. **No
  pragma needed**: unlike `CFreeType` (`FT-A`), the vendored HarfBuzz source
  builds warning-free on both macOS build systems and on Linux with no edit
  and no `unsafeFlags`, measured.
- `Sources/MetalUIHarfBuzz/HarfBuzzFont.swift`: `HarfBuzzFont(data:faceIndex:
  size:)` loads a face through `hb_blob_create` (`HB_MEMORY_MODE_DUPLICATE`,
  so the caller's bytes need not outlive the call), sets the `hb_font`'s
  scale to the face's own `unitsPerEm` on both axes (`SH-D`) so HarfBuzz
  answers in design units, and exposes `points(_:)` as `units × size ÷
  unitsPerEm` in `Double` — no 26.6 fixed point anywhere, which `FT-D`
  already measured changes answers by quantizing to 1/64 px.
- `Sources/MetalUIHarfBuzz/HarfBuzzShaper.swift`: `HarfBuzzShaper.shape(_:
  font:direction:)` feeds the buffer UTF-16 (`hb_buffer_add_utf16`) so
  `ShapedGlyph.cluster` lands in the same unit CoreText's string indices use
  (`SH-C`); `.auto` calls `hb_buffer_guess_segment_properties` for direction,
  script and language together, while an explicit direction sets it first and
  guesses only script/language; no feature list is passed to `hb_shape`
  (`SH-E`) — HarfBuzz applies each script's own required/default features,
  which is what CoreText does for an OpenType font by default. `ShapedRun`
  reports glyphs in visual order (HarfBuzz already returns RTL runs that
  way), the total advance, and `isRightToLeft` read off
  `hb_buffer_get_direction` (`HB_DIRECTION_RTL`/`HB_DIRECTION_BTT`, spelled
  out since `HB_DIRECTION_IS_BACKWARD` is a C macro).
- `Tests/Fonts/NotoSansArabic-Regular.ttf` (`SH-F`): Noto Sans Arabic v2.013,
  unhinted static TrueType, SIL OFL 1.1 (`NotoSansArabic-OFL.txt`).
  `Tests/Fonts/SOURCES.md` gained its row: release URL, archive SHA-256, both
  member SHA-256s, and everything read back off the file — sfnt `00 01 00
  00`, no `fvar`, tables `GDEF GPOS GSUB OS/2 cmap glyf head hhea hmtx loca
  maxp name post`, `cmap` (3,10) format 12 with 1250 mappings (256 in
  U+0600..U+06FF), `GSUB` scripts `DFLT arab` with features `aalt ccmp dlig
  fina init liga locl medi pnum rlig rtlm tnum`, `GPOS` `kern mark mkmk`. It
  has **no Latin letters** (U+0041/U+0061 unmapped), asserted so the Latin
  corpus can never accidentally exercise it.
- `Tests/MetalUIHarfBuzzTests/HarfBuzzOracleTests.swift` (`SH-G`, `SH-H`)
  replaces `SmokeTests.swift`: 678 lines, 15 tests (14 running + one
  `METALUI_HARFBUZZ_MEASURE=1` measurement test), 31 corpus cases across
  three fonts. CoreText side:
  `CTFontManagerCreateFontDescriptorsFromData` → `CTFontCreateWithFontDescriptor`
  at 13 pt → `CTLineCreateWithAttributedString` → per run
  `CTRunGetGlyphs`/`CTRunGetPositions`/`CTRunGetAdvances`/
  `CTRunGetStringIndices`/`CTRunGetStatus`'s `rightToLeft` bit, total from
  `CTLineGetTypographicBounds`; every case is one `CTRun`. Asserted: same
  glyph-id sequence, same cluster sequence, same visual order, positions and
  totals within measured tolerances. `everyShapedLatinGlyphRasterizes`
  (`SH-H`): every shaped Latin glyph rasterizes through `FreeTypeRaster` to a
  non-empty, inked `GlyphImage` unless it is the space glyph (empty in both);
  `plainASCIIIdsEqualFreeTypesCmapLookup` pins the shaper's ids against
  `FreeTypeFont.glyph(for:)` one for one on the 14 unligated, unmarked-ASCII
  cases.
- `Tests/PortableTests/`: a second test target, `HarfBuzzDeterminismTests`
  (depends on the root package's `MetalUIHarfBuzz`, `MetalUIFreeType`,
  `MetalUIScene`), re-declaring the SH-G corpus (13 Latin strings × 2 Latin
  faces + 5 Arabic strings = 31 cases) and pinning, per case, the exact
  glyph-id sequence, the exact cluster sequence, `isRightToLeft`, the total
  advance and an FNV-1a 64 checksum of the per-glyph positions, plus one
  end-to-end case: shape a Latin pangram-adjacent string in Noto Sans,
  rasterize every glyph through `FreeTypeRaster`, and checksum the
  concatenated coverage. `Expected.swift` holds the 32 rows, recorded on
  macOS arm64 by a `METALUI_PORTABLE_RECORD=1` gate (`FreeTypeDeterminismTests`'
  own style). Faces are opened at `size == unitsPerEm` (`SH-D`'s conversion is
  the identity there), so every pinned number is a whole design-unit integer
  and the `Int32(exactly:)` conversion traps rather than rounds; a separate
  test re-shapes the corpus at 13 pt and checks the same ids/clusters and
  values equal to the design-unit ones scaled by `13/unitsPerEm` within
  `1e-12`, which is the only test the 1/64-quantization mutant reddens (`SH-D`
  is a no-op at `size == unitsPerEm`, so nothing else can see that mutant).
- `.github/workflows/swift.yml`: `scene-linux` gained a third step, `swift
  build --target MetalUIHarfBuzz` (`SH-K`). The two portable jobs already ran
  `swift test` over the whole `Tests/PortableTests` package, so they needed
  no new steps, only honest names for the job ids and display names
  (`freetype-portable-*` → `portable-*`, "FreeType" → "Portable tests") since
  they now cover both `FT-J` and `SH-I`.

## Measurements

### Agreement, per case (31 cases, 13 pt, `METALUI_HARFBUZZ_MEASURE=1`)

Ids and clusters agree on **29 of 31** cases; the two that do not are pinned
by name below, never by loosening a tolerance.

| Font | Case | glyphs | CTRuns | ids | clusters |
|---|---|---|---|---|---|
| NotoSans-Regular.ttf | plain | 43 | 1 | = | = |
| NotoSans | kern AV / To / Ty / LT | 2 each | 1 | = | = |
| NotoSans | liga fi / fl / ffi | 1 / 1 / 1 | 1 | = | = |
| NotoSans | mark e+U+0301 / a+U+0308 / n+U+0303 | 1 / 1 / 1 | 1 | = | = |
| NotoSans | digits / punctuation | 10 / 11 | 1 | = | = |
| SourceSans3-Regular.otf | plain | 43 | 1 | = | = |
| SourceSans3 | kern AV / To / Ty / LT | 2 each | 1 | = | = |
| SourceSans3 | liga fi / fl / ffi | 2 / 2 / 2 | 1 | = | = |
| SourceSans3 | mark e+U+0301 / a+U+0308 / n+U+0303 | 1 / 1 / 1 | 1 | = | = |
| SourceSans3 | digits / punctuation | 10 / 11 | 1 | = | = |
| NotoSansArabic | arabic word (مرحبا) | 6 | 1 | = | = |
| NotoSansArabic | arabic sentence | 15 | 1 | = | = |
| NotoSansArabic | lam-alef (لا) | 2 | 1 | = | = |
| NotoSansArabic | harakat (مَرْحَبًا) | 10 | 1 | = | **DIFFER** |
| NotoSansArabic | arabic-indic digits (٠…٩) | 10 | 1 | **DIFFER** | **DIFFER** |

Noto Sans forms `fi`/`fl`/`ffi`; Source Sans 3 leaves two glyphs in each —
both shapers agree case by case, which is what is asserted, not a particular
outcome.

### The representation trap

CoreText has no per-glyph offset: every offset derived from `positions −
walk(advances)` is zero to `7.11e-15` pt over all 404 glyph values
(`coreTextFoldsGlyphOffsetsIntoItsAdvances`). HarfBuzz reports advance +
offset separately. In the Arabic mark cases the same placement therefore
differs by up to **2.366 pt of raw advance and 2.262 pt of raw offset** while
the glyph lands in exactly the same spot (worked example, harakat glyph 1:
HarfBuzz advance `0.0` + next glyph's offset `1.222` − own offset `−0.091` =
`1.313`, CoreText's advance exactly; the identity holds to `1.8e-15` across
the corpus). A raw-advance tolerance would have had to be 2.4 pt — wide
enough to hide a real shaping difference. Instead the corpus-wide bounds are
on what the two conventions share by definition (pen advance, drawn
position, run total), and raw per-glyph advances are asserted only on the 27
cases where HarfBuzz reports no offset at all.

### Tolerances set (points, 13 pt, maxima over the whole corpus)

| Quantity | Measured max | Tolerance set | Margin |
|---|---|---|---|
| pen advance, x or y (`xAdvance + nextOffset − offset` vs `CTRunGetAdvances`) | 1.7763568394002505e-15 | `advanceTolerance = 1e-12` | ~560× |
| raw per-glyph advance, on the 27 offset-free cases | 1.7763568394002505e-15 | same `advanceTolerance` | ~560× |
| CoreText's derived per-glyph offset (404 values; it has none) | 7.105427357601002e-15 | `offsetTolerance = 1e-12` | ~140× |
| drawn glyph position (pen + offset) vs `CTRunGetPositions` | 5.684341886080802e-14 | `positionTolerance = 1e-12` | ~18× |
| total run advance vs `CTLineGetTypographicBounds` | 5.684341886080802e-14 | `totalAdvanceTolerance = 1e-12` | ~18× |

`1e-12` pt is four orders of magnitude below one design unit at this size
(13/1000 pt = 0.013 pt for Noto Sans), so the bounds cannot absorb a real
shaping difference. The raw advance/offset deltas above (the representation
gap) were **not** used to set any tolerance — every other case's raw delta
is ≤ 8.9e-16 pt, so the Arabic-mark rows are the only ones that ever near
this constant.

### The two pinned disagreements with CoreText

**`harfBuzzMergesMarkClustersIntoTheirBase`** — مَرْحَبًا, ids and drawn
positions identical (`[9,374,316,16,370,27,378,31,370,79]`, 0.0 pt diff,
total identical):

| | clusters |
|---|---|
| HarfBuzz | `[8, 6, 6, 6, 4, 4, 2, 2, 0, 0]` |
| CoreText | `[8, 7, 6, 6, 5, 4, 3, 2, 1, 0]` |

Every difference is a mark reported at its base's offset instead of its
own — HarfBuzz's default cluster level `HB_BUFFER_CLUSTER_LEVEL_
MONOTONE_GRAPHEMES`, which is exactly what `ShapedGlyph.cluster`'s own
contract states ("several glyphs can share a cluster \[a decomposed
mark]"). **Measured, not assumed:** adding
`hb_buffer_set_cluster_level(buffer, HB_BUFFER_CLUSTER_LEVEL_
MONOTONE_CHARACTERS)` to `HarfBuzzShaper.shape` makes this case's clusters
equal CoreText's exactly and changes **no other case** in the corpus — no
id, no cluster, no position moves. **Reverted, not shipped** — see Open.

**`harfBuzzGuessesDirectionFromScriptWhereCoreTextRunsBidi`** —
٠١٢٣٤٥٦٧٨٩:

| | rtl | ids | clusters |
|---|---|---|---|
| HarfBuzz `.auto` | true | `[137…128]` | `[9…0]` |
| HarfBuzz `.rightToLeft` | true | `[137…128]` | `[9…0]` |
| HarfBuzz `.leftToRight` | false | `[128…137]` | `[0…9]` |
| CoreText | false | `[128…137]` | `[0…9]` |

`hb_buffer_guess_segment_properties` takes direction from the script
(`SH-C`) and Arabic's is RTL; CoreText runs the bidi algorithm, and
U+0660..U+0669 are class AN (Arabic number), not strong, so the paragraph
level is 0 (LTR). **Separating arm, measured:** the same digits after one
strong Arabic letter (`م٠١٢…`) give a CoreText line that is right-to-left
overall (2 runs, the letter last in visual order at cluster 0) with the
digits still ascending `[1…10]` — so the LTR answer is the *paragraph
level*, not a property of the digit glyphs, ruling out "CoreText treats
digits as inherently LTR" as the explanation. With `direction:
.leftToRight` the shaper reproduces CoreText's ids, clusters and positions
exactly, which the pin asserts. Totals agree either way (one advance,
7.436 pt, for these glyphs).

## Mutations

Eight in a detached `git worktree` (created from the commit, mutated, run,
removed afterward — `git status` in the real worktree stayed clean
throughout):

| Mutant | Tests reddened |
|---|---|
| `hb_font_set_scale` in 26.6 (`size*64`) instead of design units | drawnPositions, penAdvances, rawAdvances, totalAdvance, coreTextFoldsGlyphOffsets, both pins |
| clusters as UTF-8 offsets (`hb_buffer_add_utf8`) | clusterSequences, both pins (Latin unaffected — ASCII UTF-8 == UTF-16 offsets) |
| `hb_buffer_reverse` after shaping (all runs) | glyphIds, clusterSequences, visualOrder, drawnPositions, penAdvances, rawAdvances, plainASCIIIds, both pins |
| reverse RTL runs only (logical instead of visual order) | glyphIds, clusterSequences, visualOrder, drawnPositions, penAdvances, rawAdvances, both pins |
| `-kern` feature list | drawnPositions, penAdvances, rawAdvances, totalAdvance, cluster pin |
| `-liga` feature list | glyphIds, clusterSequences, drawnPositions, penAdvances, rawAdvances, totalAdvance |
| force `HB_DIRECTION_LTR` under `.auto` | directionAgrees, glyphIds, clusterSequences, drawnPositions, penAdvances, rawAdvances, totalAdvance, coreTextFoldsGlyphOffsets, both pins |
| `FreeTypeFont.glyph(for:)` returns `1 &+ id` | everyShapedLatinGlyphRasterizes, plainASCIIIdsEqualFreeTypesCmapLookup |
| `layoutTableTags` reads FeatureList from the ScriptList slot | theArabicFontHasAnArabicCmapAndJoiningFeatures |

Every one of the 14 running tests is reddened by at least one mutant.

Ten more against the portable package (also in a detached worktree, applied
one at a time and reverted; baseline 6/6 HarfBuzz + 5/5 FreeType green
beforehand):

| Mutant | Tests reddened |
|---|---|
| 26.6 scale (`upem * 64`) | `everyCaseMatchesTheValuesRecordedOnMacOS` |
| clusters as UTF-8 offsets | `everyCaseMatchesTheValuesRecordedOnMacOS` |
| RTL run in logical instead of visual order | `everyCaseMatchesTheValuesRecordedOnMacOS` |
| `kern` disabled | `everyCaseMatchesTheValuesRecordedOnMacOS`, `theCorpusIsNotDegenerate` |
| `liga` disabled | `everyCaseMatchesTheValuesRecordedOnMacOS`, `theCorpusIsNotDegenerate`, `theRasterizedRunMatchesTheValueRecordedOnMacOS` |
| direction forced LTR under `.auto` | `everyCaseMatchesTheValuesRecordedOnMacOS`, `theCorpusIsNotDegenerate` |
| one pinned position checksum changed by one hex digit | `everyCaseMatchesTheValuesRecordedOnMacOS` |
| the end-to-end raster checksum changed by one hex digit | `theRasterizedRunMatchesTheValueRecordedOnMacOS` |
| FNV-1a offset basis changed | `theChecksumIsFNV1a64`, `everyCaseMatchesTheValuesRecordedOnMacOS`, `theRasterizedRunMatchesTheValueRecordedOnMacOS` |
| `points()` quantized to 1/64 (26.6 in the conversion only) | `shapingIsInWholeDesignUnitsAndScalesWithTheSize` **alone** |

The last row is the separating mutant the scaling test exists for: every
design-unit pin is blind to it (at `size == unitsPerEm` the quantization is
a no-op), so it reddens nothing else. The `liga`-off row needed the
end-to-end string changed from the original pangram (which has no ff/fi/fl
pair) to `"Affix the fluffy waffle: AV To Ty LT jig!"` before it could see a
shaping change in the coverage-only checksum; with the pangram it reddened
only the corpus test.

## Cross-platform determinism (`SH-I`)

32 pinned values (31 corpus rows + 1 end-to-end row), compared as exact
integers and exact 64-bit checksums, no tolerance:

| Comparison | Rows equal | Rows differing |
|---|---|---|
| macOS arm64 (recorded) vs Linux aarch64 | 32 / 32 | 0 |
| macOS arm64 (recorded) vs Linux x86_64 | 32 / 32 | 0 |

No macOS/Linux difference — nothing was re-pinned from a non-macOS platform.
Windows was not run locally (no Windows host or container available); CI is
the only Windows coverage, and the first time the vendored HarfBuzz C++
amalgamation is compiled by the Windows toolchain.

## Counts

Measured in this worktree at `ce1088e`, clean tree, this session:

- `swift package clean` + `swift build --build-system native --build-tests`:
  0 `error:`, 1 `warning:` (SwiftPM's own `--build-system native`
  deprecation notice — 0 real warnings).
- Unfiltered `swift test --build-system native --no-parallel`: one summary
  line, `Test run with 1573 tests in 3 suites passed after 67.273 seconds`
  (1558 + 15). `FR-J no-argument frame: succeeded=` appears once
  (`succeeded=true deprecations=2`) — the guards ran.
- `swift test --build-system native --no-parallel --filter
  MetalUIHarfBuzzTests`: `Test run with 15 tests in 1 suite passed after
  0.237 seconds` (14 running + `measure()` skipped).
- `rm -rf .build` then default build system `swift build --build-tests`: 0
  `error:`, **0** `warning:`, `Build complete! (72.14 sec)`.
- Goldens: `find Tests/MetalUILayoutTests -name "*.json" | wc -l` = **97**;
  `find Tests -name "*.json" -not -path "*/.build/*" | wc -l` = **97** —
  unmoved.
- Guards: `grep -c canTypecheck` over the 15 files CLAUDE.md names plus
  `Typecheck.swift` totals 79; minus `Typecheck.swift`'s one declaration and
  `UnitSafetyTests`' one comment hit = **77** — unchanged, no new guard file
  (`MetalUIHarfBuzz` gains a Linux build check, `SH-K`, but no plain-import
  boundary of its own beyond that).
- Portable package, default build system, clean `.build`
  (`Tests/PortableTests`, `swift test --no-parallel`): two summary lines,
  `Test run with 6 tests in 1 suite passed` (HarfBuzz) and `Test run with 5
  tests in 1 suite passed` (FreeType) — **11 tests**, 0 `error:`, 0
  `warning:`.

## Open

- Line breaking, bidi reordering across runs, script itemization of mixed
  text and font fallback are all still CoreText-only in production; this
  step is one run (one font, one direction, one script, one line), as the
  spec's "Not in this step" says.
- No OpenType feature control (no way to force `kern`/`liga` off through the
  API) and no variable-font support — `HarfBuzzFont` takes no variation
  axes, and all three bundled fonts are static.
- `HB_BUFFER_CLUSTER_LEVEL_MONOTONE_CHARACTERS` was measured to fix the one
  cluster disagreement with **no other change anywhere in the corpus**, and
  was reverted rather than shipped, so `HarfBuzzShaper.shape` still uses
  HarfBuzz's default cluster level. Switching it is a one-line,
  fully-measured follow-up whenever a caller needs CoreText-identical mark
  clusters.
- `hb_buffer_guess_segment_properties`'s script-based direction guess will
  disagree with CoreText's bidi algorithm on any text whose paragraph
  direction is not implied by its dominant script (not just Arabic digits);
  nothing in this step runs a bidi pass, so a caller mixing scripts must
  choose `direction:` itself.
- Windows could not be run locally; CI carries the only Windows coverage for
  `Tests/PortableTests`, and the only Windows build of `Sources/CHarfBuzz`.
- Nothing in production calls `HarfBuzzShaper`; `Shaper` remains the only
  shaper any renderer uses (`SH-J`). Wiring a non-Apple shaping backend into
  the render pipeline is future work, the same open item `FT-I` left for the
  rasterizer.

Renumbered from §25 to §26 at merge (2026-09-22): `master` had meanwhile
taken §25 for engine stage 3.

Re-taken on the merged tree with `master` (clean native build): 1595 tests
(1580 + 15), 97 goldens unmoved against `b10594c`, 77 guards, 0 errors,
0 warnings.
