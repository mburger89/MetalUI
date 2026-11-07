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

## 4. Counts

See section 5 (filled by the verification runs).

## 5. Verification

(Appended by the final runs below.)
