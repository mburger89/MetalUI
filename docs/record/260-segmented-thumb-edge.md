# 260. The segmented thumb's hairline edge (Alloy G23, G28; `SD-C`)

Branch `fix/segmented-thumb-edge` (master `b255947b`). Ruling `SD-C` in `docs/superpowers/2026-11-01-segmented-dark-decisions.md` (next `SD-D`). Class A, no divergence label. Records 258 and 259 belong to open PRs; a later merge renumbers.

- **Problem.** Alloy measured the selected pill against the track at 1.24:1 (light) and 1.68:1 (dark); with a page equal to `.surface` (Solarized Light) the pill vanishes into the page.
- **Probe** `docs/probes/swiftui-segmented-thumb.swift`. Pixel readback of the native control is still not possible on macOS 27: `cacheDisplay(in:to:)` returns an alpha mask only (SwiftUI's selected segment blank; an `NSSegmentedControl` pill a flat layer, text colour at alpha 0.20 over a 0.08 track, no stroke or halo in the row and column samples), `CGWindowListCreateImage` is unavailable. So a native stroke or shadow was neither seen nor excluded. Semantic colours (resolved light / dark): `separatorColor` black 0.10 / white 0.12; `controlColor` #FFFFFF 1.0 / white 0.247; `selectedControlColor` #B3D7FF / #3F638B; `controlBackgroundColor` and `windowBackgroundColor` #FFFFFF / #1E1E1E; `quaternaryLabelColor` 0.098 / 0.098; `gridColor` #E6E6E6 / #1A1A1A.
- **Change.** `PickerScope.selectedSegmentEdge`: `.textPrimary` x 0.10 (light) / 0.12 (dark), a 1-pixel `Decoration.border` on the selected segment only (`Picker.swift`). No shadow, no new capability (`shaders.metal`/`replay.hlsl` untouched), no `Theme` token, thumb fill unchanged. `TabStrip` does not use this paint.
- **Contrast** (edge on thumb vs page): default light 1.13 (vs thumb 1.23), default dark 3.24 (vs thumb 1.33), Solarized Light 1.12. A hairline at AppKit's alpha does **not** reach 3:1 in light; reported, not faked (`SD-C`).
- **Tests** (`Tests/MetalUITests/SegmentedPickerFillTests.swift`): `theSelectedSegmentDrawsAHairlineEdgeAtItsRect`, `anUnselectedSegmentHasNoEdge`, `theEdgeSeparatesTheThumbFromAPageEqualToSurface`.
- **Mutations** (each alone, restored): drop `border:` reddens all three; alpha 0.5 reddens `theSelectedSegmentDrawsAHairlineEdgeAtItsRect`; `border:` on every segment reddens `anUnselectedSegmentHasNoEdge` and `theSelectedSegmentDrawsAHairlineEdgeAtItsRect`.
- **Re-pinned.** The retained demo's selected segment adds one border rect: `f.rects` 180 -> 181 in `RetainedGraftTests`, `RetainedPrepaintTests` (two) and `RetainedSubtreesBaselineTests` (12 failures read before the re-pin, all `f.rects`).
- **Human check** `SD2` (the look, and AppKit's shadow, are unsampled).

Counts (2026-11-09): root 5797 tests in 26 suites passed, native build system, unfiltered, `--no-parallel`; `FR-J no-argument frame: succeeded=true`.
