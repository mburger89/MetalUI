# Record 230: symbol images (Alloy gap G3, PRs 0 and 1)

Branch `feat/symbol-images` (master `33aad057`). PR 0 is the probe `docs/probes/swiftui-symbol-images.swift` (arms S0-S11, S5b and S8b added during PR 1; macOS 27.2, run twice, `cmp` clean, output verbatim in its header). PR 1 is `Image(systemName:)` on macOS. **Linux and Windows treat every name as missing in this PR**: `Image(systemName:)` compiles and is an empty 0 x 0 leaf there (`SymbolBackend` has no catalogue off AppKit); the bundled Lucide icons, `MetalUIIconData`, `Icon` and the portable box are PR 2 and not started. Rulings `SYM-A`..`SYM-M` (`docs/superpowers/2026-11-07-symbol-images-decisions.md`).

## 1. What was built

- **API (`SYM-B`).** `Image(systemName:)`, `Image.Scale` + `imageScale`, `SymbolRenderingMode` (no `.palette`) + `symbolRenderingMode` (modifier and `Image` method), `SymbolVariants` + `symbolVariant`; `EnvironmentValues.imageScale`/`symbolVariants` public, `symbolRenderingMode` internal; all three in `EnvironmentFingerprint` (`SYM-K`). `Image` stores `Content` (`bitmap`, `symbol`): `swift package clean`.
- **Resolution (`SYM-F`).** The pure `resolveSymbolName(_:variants:exists:)`.
- **Layout (`SYM-D`).** A native leaf: width the alignment rect's, height the image's, baseline `height - alignmentRect.minY`; a missing name 0 x 0.
- **Raster (`SYM-C`, `SYM-E`).** `SymbolRasterCache` (process-wide, LRU 512, counters), AppKit `NSImage` symbol configuration, monochrome coverage then tint, hierarchical and multicolor coloured by AppKit.
- **Accessibility (`SYM-H`), cursor and toolbar (`SYM-L`), diagnostics (`SYM-G`).**

## 2. Probe readings that changed the plan

- **S1: H1 refuted for two symbols.** `doc.badge.plus` (9 pt) and `square.and.pencil` (1 pt) differ from `NSImage.size`; H1' (width = alignment rect width) matches 38 names x 6 sizes x 3 scales x 2 weights exactly.
- **S2: H2 holds** (14 rows), the cap-centre model (H3) is off by up to 2.8 pt.
- **S9: the AppKit raster is not SwiftUI's.** The plan's stop condition (over 2% off at an integer origin) was reached; one bounded attempt (header of the probe) found no routing or offset that closes it; the plain draw ships with divergence 227.
- **S8: the accessibility label is SwiftUI's own table**, not `NSImage.accessibilityDescription` (`star` is "Favorite" against "favorite"); the 38 names S8b read are the table, other names fall back (divergence 228).
- **S6: a missing name is silent in SwiftUI**, so MetalUI logs nothing (the plan's once-per-name stderr line is dropped; `SymbolDiagnostics.misses` remains for tests).
- **S5b (added):** the fallback drops words slash > shape > fill.
- **S10:** no outline route exists (an AppKit symbol in a PDF is a Form plus an Image XObject), so a soft symbol under `scaleEffect` stays (divergence 229).

## 3. Tests and mutations

`SymbolImageTests` (macOS, 12 tests: 4, 5, 11, 12, 13, 14, 16, 17, 18 and the pins of 227, 228 and 229), `RetainedSymbolImageTests` (test 15 and a fingerprint-name test, `MetalUITestingTests`), the two guards in `ImageCompileGuards.swift` (test 1 renamed `anImageHasASystemNameButNoAssetInitialiser`, test 2 `everySymbolSpellingCompilesFromAPlainImport`). Pins moved: `everyEnvironmentFingerprintFieldIsNamedWhenItDiffersAlone` 31 to 34 fields, `environmentFields` in `RetainedSubtreeInternalTests` gained three rows. Mutation results are in section 5.

## 4. Counts (2026-11-07, branch `feat/symbol-images`, after `swift package clean`)

Root **5541 tests in 19 suites passed** (`--build-system native`, unfiltered, `--no-parallel`; 0 failures), `FR-J no-argument frame: succeeded=true`; the same run under `METALUI_VERIFY_RETAINED=1` also **5541 passed**. Portable Docker (`metalui-portable`, from `git archive`): `MetalUITestingTests` 903, `MetalUILayoutTests` 286, `MetalUICoreTests` 154, `MetalUICrossPlatformTests` 24, all passed. The first full run found three failures this PR owed and fixed: the fingerprint field count (31 to 34) in `everyEnvironmentFingerprintFieldIsNamedWhenItDiffersAlone`, the `environmentFields` table in `RetainedSubtreeInternalTests`, and G3.2's asset message (now `missing argument label 'systemName:'`). `Backends/SDL` not re-run.

## 5. Mutations (applied in place after committing, restored with `git checkout`)

Reddened, by test: M4a (shape before slash) and M4b (fallback removed) `symbolVariantsResolveByTheMeasuredSuffixOrderAndFallBack`; M5a (placeholder fill) and M5b (miss counted every call) `aMissingSymbolIsAnEmptyLeafCountedOncePerName`; M11a (tint skipped) and M11b (scale 1) `aSymbolIsTintedByTheForegroundAndRasterisedAtTheFramesScale`; M12a (small/large swapped), M12b (weight dropped), M12c (`size.width`) `aSymbolsSizeIsTheFontsAtTheImageScale`; M13 (`alignment.minY` as the baseline) `aSymbolsBaselineIsItsHeightMinusTheAlignmentRectsBottom`; M14b (colour out of the tint key) and M14c (cache cleared per lookup) `aSymbolIsRasterisedOnceAndRetintedWithoutRasterising`; **M14a (point size out of the key) survived the first test** (a font change also changes the pixel size, which is in the key) and reddened after the test gained the 13 pt / 13.2 pt arm; M15a (`imageScale` out of the fingerprint) `anImageScaleChangeAboveAnEquatablePanelRemeasuresIt` and `theSymbolFieldsAreNamedInTheFingerprint`; M16 (no accessibility record) `aSymbolIsAnImageLabelledLikeSwiftUIAndHiddenWhenAsked` (its first spelling, deleting the guard, did not compile and was redone as `_ = label; return`); M17 (a hitbox) `aSymbolRegistersNoHitbox`; M18 (cache reset per cursor) `aSymbolCursorIsTheBodyFontStarAtScaleTwoWithOneIdentity`; M227 (image drawn 0.5 pt higher) `anAppKitSymbolRasterSitsOneDeviceRowLowerThanSwiftUIs`; M228 (description capitalised) `aSymbolOutsideTheLabelTableReadsAppKitsLowerCaseDescription`. Guards (native build): MG3b (`init(systemName:)` made internal) reddened `anImageHasASystemNameButNoAssetInitialiser` and `everySymbolSpellingCompilesFromAPlainImport`; MG3c (`init(_ name: String)` added) the first; MS2 (`imageScale` internal) the second. Not mutated: M229 (no spelling of the soft symbol exists to mutate; a fix would redden its pin).

## 6. Carried

PR 2 (`MetalUIIconData`, Lucide, `Icon`, the portable box, tests 3 and 6-10, 19), PR 3 (`Label`), the toolbar template flag, a symbol spacing edge, `symbolVariant` nesting, `Text(Image)`, `.palette`, `variableValue`, `symbolEffect`. Suggested "agent" icon for Alloy: `cpu` (`robot` does not exist on macOS 27.2).
