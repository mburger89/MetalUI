# 28 — Portable text pipeline (`MetalUIPortableText`), 2026-09-23

Branch `feat/portable-text`, from `master` at `f5e5651` (the HarfBuzz merge,
record §26). Spec: `docs/superpowers/specs/2026-09-23-portable-text-design.md`,
rulings `PT-A`…`PT-I` in that spec (no separate decisions doc; next `PT-J`).

**Renumbered 27→28 at the merge with `master` (`e5caefb`).** Task 7 stage 4
reached `master` first and took §27, as record §23 §7 and §25's header
record for the earlier cases. §28 §Counts is re-taken on the merged tree.

## Why

The FreeType rasterizer (§24) and the HarfBuzz shaper (§26) were each checked
against CoreText in isolation, and nothing joined them: no string had become
`MUIGlyph`s and atlas coverage without CoreText, and no text pixel had been
drawn off an Apple platform.

## What changed

- **`PT-C`** — `subpixelPlacement(forDeviceX:)` moved from `GlyphRaster` to
  `MetalUIScene`'s `GlyphImage`; `GlyphRaster` forwards. Both pipelines split a
  pen position by calling one function. The only production edit (`PT-I`).
- **`PT-A`, `PT-B`, `PT-D`, `PT-E`** — `MetalUIPortableText` (library product,
  built by `scene-linux`): `PortableFont` opens one file in both engines and
  checks `unitsPerEm` and three probe glyphs agree; `PortableText.emit` shapes,
  places, packs (rasterizing on a miss) and emits one run on one line, with
  `Frame.draw`'s arithmetic. `FreeTypeFont.unitsPerEm` and
  `HarfBuzzFont.glyph(for:)` were added for the check. Commit `51e1dcf`.
- **`PT-F`** — the Apple-path oracle, `ApplePathOracleTests.swift` (8 tests,
  384 cases). Commit `bb47d15`, whose message carries the measurement: every
  `MUIGlyph`'s origin and size **exactly** equal over all 384 cases (no
  tolerance), coverage within 67 per pixel / 7.024 mean outside the four
  CoreText-adjusted sizes of §24, which are pinned.
- **`PT-G`** — `Experiments/SDLGPU`'s `Replay` gains **frame 4**: frames 0–3's
  layout with every glyph from `PortableText` (Noto Sans from `Tests/Fonts/`)
  into a fresh atlas no CoreText call touched, drawn by the production Metal
  renderer and by SDL, and recorded as `frame-4.muireplay`, so Linux
  (llvmpipe) and Windows (D3D12/WARP) CI replay it. All its primitives are
  `order: 0`, as production emits them. `PortableReplay` gains `--expect <n>`
  and CI passes 5. The SDL workflow now also triggers on the text targets'
  sources and `Tests/Fonts/`.
- **`PT-H`** — `Tests/PortableTests` gains a third target,
  `PortableTextDeterminismTests` (4 tests: the FNV vector, the pin table, a
  non-degeneracy check, the gated recorder). Five cases — both Latin outline
  formats, both scales, whole and fractional origins, and one Arabic run with
  harakat — each pin glyph count, an FNV-1a 64 of every quad and atlas slot,
  the returned advance's bit pattern, the atlas dirty rect and an FNV-1a 64 of
  the whole 512×512 atlas. The recorder refuses a row with no glyphs, no dirty
  rect or an all-zero atlas before printing it.
- **The `unitsPerEm` check was unreachable.** All three bundled fonts are 1000
  units per em, so deleting PT-B's first comparison reddened nothing (M6a
  below). `aPortableFontWhoseHalvesAreDifferentFilesThrows` gained a case whose
  raster half is Noto Sans with its `head.unitsPerEm` patched to 2048 in
  memory — every glyph id agrees, so only that comparison can throw — plus a
  control that the patched face opens and reads 2048 in both engines.

## Measurements

### Frame 4 (2026-09-23, Apple M1 Max, SDL 3.4.16, MoltenVK)

| Path | Frames 0–3 | Frame 4 (portable text, 128 glyphs) | Order mutation |
|---|---|---|---|
| `Replay --portable` (live, SDL Metal) | 0 px each | 0 px, Δ0 | frame 3: 283 px, Δ152 |
| `PortableReplay` SDL Metal | 0 / 0 px in and out of glyphs | 0 / 0 | frame 4: 302 px >16, Δ154 |
| `PortableReplay` SDL Vulkan (MoltenVK) | 0 / 0 | 0 / 0 | frame 4: 302 px >16, Δ154 |

Linux and Windows: not yet run — the first CI run of this branch is where the
first non-Apple text pixels are drawn. The expectation, from frames 0–3's
history (SDLGPU README), is ≤1 outside glyphs and a few steps inside.

`--expect 5` over a directory holding only frames 0–3 fails with `expected 5
fixtures, found 4` (measured), which is mutation M8 below.

### Pins (`PT-H`)

Recorded on macOS arm64; the table is `Expected.swift`. The Arabic case emits
**18 glyphs from 16 visible scalars** — HarfBuzz shapes some harakat to more
than one glyph, as `SH-I`'s harakat row does — so the non-degeneracy check's
"no more glyphs than visible scalars" clause is Latin-only (it was written for
all five and was wrong; measured).

## Mutations

Each applied to one line, both suites run (`--filter MetalUIPortableTextTests`
in the root, the whole of `Tests/PortableTests`), reverted by
the runner in a `finally` (a Python script in the session scratchpad; its
first run crashed decoding M5's non-UTF-8 test output, after restoring the
file, and M5–M7 were re-run with lossy decoding).

| # | Mutant | Root (PT-F) reddens | Portable (PT-H) reddens |
|---|---|---|---|
| M1 | drop `xOffset` from the pen walk | **nothing** | `everyCaseMatchesTheValuesRecordedOnMacOS` (Arabic row only) |
| M2 | `floor` for the baseline | `everyCorpusCasePlacesTheSameGlyphs…` | `everyCaseMatches…` |
| M3 | atlas key ignores the subpixel variant | places, inks, `coreTextDrawsAwayFromItsOutline…` | `everyCaseMatches…` |
| M4 | `packed.top` as `+` | places | `everyCaseMatches…` |
| M5 | skip the zero-area check (spaces emitted) | places | `everyCaseMatches…`, `theCorpusIsNotDegenerate` |
| M6a | delete the `unitsPerEm` comparison | nothing → **`aPortableFontWhoseHalves…`** after the 2048 case | nothing |
| M6b | delete the probe-glyph comparison | `aPortableFontWhoseHalves…` | nothing |
| M7 | change one pinned coverage checksum | nothing | `everyCaseMatches…` |
| M8 | drop frame 4 from the fixture set | — | CI's `PortableReplay … --expect 5` fails |

**M1 is the finding.** `bb47d15` recorded it green on the oracle and argued it
equivalent there: its Latin corpus has no shaping offsets
(`noCorpusGlyphCarriesAShapingOffset`). That is true of the corpus and not of
`emit`; PT-H's Arabic run is the only test in the repository that sees the
`xOffset` term, and it runs in the portable package, not the root suite.

## Counts

Taken after `swift package clean`, `swift build --build-system native
--build-tests`, unfiltered `swift test --build-system native --no-parallel`:
**`Test run with 1603 tests in 3 suites passed`** (1595 + the oracle's 8; the
2048 case is new expectations in an existing test), 97 goldens (none moved
against `f5e5651`), 77 guards (no guard file touched; they **ran** — the log
carries `FR-J no-argument frame: succeeded=`, so `CLAUDE.md`'s "guards skip in
a worktree" did not hold for this worktree's layout). 0 `error:`; the one
`warning:` is SwiftPM's `--build-system native` deprecation notice. The default
build system: 0 `error:`, 0 `warning:` (`swift build --build-tests`).

**After the merge with `master` at `e5caefb` (stage 4), re-taken the same
way from a clean tree: `Test run with 1625 tests in 3 suites passed`** —
master's 1617 plus this line's 8 — 97 goldens unmoved against `e5caefb`, the
guards ran, 0 `error:`, 0 `warning:` on the default build system.

The portable package: 4 + 6 + 5 tests in three suites (`PortableTextDeterminism`
4 with the recorder skipped, `HarfBuzzDeterminism` 6, `FreeTypeDeterminism` 5),
all passing on macOS.

## Open

- **Linux and Windows pixels** for frame 4 and the PT-H pins: owed to the
  first CI run of this branch.
- **Rounded content masks.** `emit` takes a `contentMask` but no corner radii,
  so frame 4's clipped line is clipped square where frames 0–3 round it. A
  caller clipping text to a rounded box needs a `maskCornerRadii` parameter.
- **Paint order.** `emit` stamps `order: 0` on every glyph, like production;
  a caller that orders primitives by `order` rather than emission sequence
  cannot interleave portable text with its rects.
- **One line, one run.** No line breaking, bidi across runs, itemization or
  fallback — the spec's non-goals, unchanged.
