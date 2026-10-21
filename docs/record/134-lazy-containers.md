# 134 - Lazy containers (L1: `LazyVStack`, `LazyHStack`, `LazyVGrid`, `LazyHGrid`, `GridItem`)

Branch `feat/lazy-containers` from `1bdead8d`. Not a plan task: item L1 of the gpui-gap list (user request 2026-10-02, round 2 2026-10-21). Spec
`docs/superpowers/specs/2026-10-21-lazy-containers-design.md`; rulings `LZ-A`...`LZ-Z` in `docs/superpowers/2026-10-21-lazy-containers-decisions.md`
(next unused `LZ-AA`). Probe `docs/probes/swiftui-lazy-containers.swift` (output in its header; lane 2 added arms `C14b`/`C14c` and re-ran, the other 62
lines byte-identical). Divergence labels 635-644 reserved: **635, 636, 637, 638 taken** (636 and 637 by lane 1, 635 and 638 by lane 2), 639-644 unused.
Two lanes. Demo `METALUI_LAZY_DEMO=1`; guide section "How do I show ten thousand rows?" in `docs/guides/layout.md`; human checks group `LZ`.

## 1 What landed

**Lane 1 (core and stacks).** `LazyUnits.swift` (a container's content read as units: a `ForEach` element, a static leaf or component, legacy rows through
`LegacyContent`, `LZ-B`/`LZ-S`; anything else makes the container eager, divergence 636), `LazyCore.swift` (`LazyLinePlanner`: `List.variableWindow`,
`rebuildKeepingAnchor` and `prepaintVariableRows` rewritten over lines, the SAME unchanged `RowExtentIndex`, `LZ-C`; `LazyOrigin`; `LazyWork`),
`LazyStack.swift` (`LazyVStack`/`LazyHStack` over the non-`Hashable` `LazyStackLayout`, which taints exactly its ancestors, `LZ-F`). Shared lines: `Frame.lazyWork`,
`TestingHooks`/`BuildWork`, `FrameWork`'s three counters, the frame-channel and state-write classification tests, inventory and census, divergences 636/637.
Cross size is the proposal else the FIRST child's (the premise "widest realised child" was refuted by the probe), spacing 8, realisation = viewport plus two lines
(637), a cold slice of 32 lines, unrealised children count as the measured mean, a scrolled-out child keeps its `@State` the `List` way (`TB-AH`).

**Lane 2 (grids, demo, guide).** `Sources/MetalUILayout/GridTrackSolver.swift` (`package`, pure, Foundation-free: `GridTrackSpec`, `GridTrack`, `GridTrackResolution`,
`resolve`, `availableForUnspecified`; Linux and Windows run it in `MetalUILayoutTests`), `Sources/MetalUI/GridItem.swift` (public `GridItem` and `GridItem.Size`),
`Sources/MetalUI/LazyGrid.swift` (`LazyVGrid`/`LazyHGrid` over the non-`Hashable` `LazyGridLayout` and one `LazyGridEngine`; lines are rows over lane 1's planner and
index, a line's key is its first cell's). Shared lines touched by lane 2: `RetainedWithStatePanelTests.swift`'s `everyStateWriteSiteIsClassified` table (one row,
`LazyGrid.swift` (0, 1, 0)), `DemoStackBudgetTests.swift` (the demo's builder), `Sources/MetalUIDemo/main.swift` (one switch), `closeout-inventory-map.tsv`/
`closeout-public-api.tsv` (rows), `divergences.md` (635, 638), `human-checks.md` (group LZ), `docs/guides/layout.md`. No registrar parameter, no `LayoutTree` kind, no
`Handlers` member, no `PlatformWindow` requirement; `Backends/SDL`, `List.swift`, `ForEach.swift`, `StateTable.swift`, `Retained*.swift`, shaders untouched.

## 2 What the probe corrected (lane 2)

- **C8 against C8c** (ruling `LZ-W`): the spec's test literals (c0 at 0, c1 at 38) were the probe's, but its rule ("tracks aligned by `alignment:`") would give 10 and
  48. The grid's `alignment:` places the tracks AND is the default alignment of a cell in its track; `GridItem.alignment` is therefore `ProposalAlignment?` (SwiftUI's
  `Alignment?`), `nil` taking the grid's. Test 3.2a separates the two jobs.
- **C14 could not separate "two cells" from "one stacked cell"** (single column: a 0, b 18, c 36 either way). Arm `C14b` (two `.fixed(40)` columns) does: SwiftUI
  lays an element of two views a, b then c as a (71, 0), b (119, 0), c (71, 18), identical to three plain cells (`C14c`). Divergence 635 is MetalUI's one-cell rule, pinned
  by 3.5 (c lands in cell 1 of row 0 at (119, 9)).
- **The kernel snaps placed edges to whole points** (cumulative, round half away from zero): LZ4's SwiftUI figures -2.5 / 35.5 / -37.5 read (-3, 31 wide), (36, 20),
  (-38, 101) here; 3.4 asserts the rounded values and 3.1d the unrounded track sizes.
- **Divergence 638** (new): an adaptive item's column count is decided at build time from the previous frame's width (`LZ-L`, `LZ-Y`); SwiftUI has no stale frame.

## 3 Red on arrival and the green run

Lane 2's tests were committed before the code (`60227aa3`). Red: `swift build --build-system native --build-tests` failed in `MetalUILayoutTests` first with
`error: cannot find 'GridTrackSolver' in scope` (x14) and `cannot find type 'GridTrackResolution' in scope`, `cannot find type 'GridTrackSpec' in scope`,
`type 'Any' has no member 'adaptive'/'fixed'/'flexible'`; the later targets were not reached in that build (the missing `LazyVGrid`/`GridItem` are the same absences by
construction). First green run of the new set after the code: 22 tests, 2 failed for the instrument, not the code - the guard's expected message (the compiler reports
`extra arguments at positions #2, #3 in call`) and 3.4's literals (the kernel's rounding, above) - both corrected in the tests, then 56 of the lazy set passed.

New lane-2 tests (23): `GridTrackSolverTests` 5 (3.1a-3.1e), `LazyGridLayoutTests` 5 (3.2a, 3.2b, 3.3, 3.4, 3.5) + 3.13, `LazyGridFrameTests` 4 (3.6, 3.7a, 3.7b, 3.8),
`LazyGridWindowTests` 5 (3.9a, 3.9b, 3.10, 3.11, 3.12), `LazyGridGuards` 1 (G.3), `LazyContainersDemoTests` 1 (L.1), `GuideMirrorsLazy` 2 (guide pins). Lane 1's 26 stand.

## 4 Mutations (committed tree, restored from a copy, `git status --short` empty after each)

Run on the **filtered set of every lazy test** (the 56 tests of both lanes plus `everyStateWriteSiteIsClassified`, `theGuideSetIsComplete`,
`everyProductionTreeBuildsOnAOneMegabyteThread`), not the unfiltered suite: the mutated declarations are new files used by no other test. The unfiltered runs are in section 5.

| mutation (file, spelling) | reddened |
|---|---|
| S1 `GridTrackSolver`: adaptive `floor` -> `ceil` | `adaptiveItemsPackAsTheProbeSays`, `anAdaptiveItemBesideAFlexibleOneSharesTheRestEqually`, `aStaleAdaptiveWidthIsCorrectedOnTheNextFrame`, `anAdaptiveGridOutsideAScrollerPacksFromItsStoredWidth`, `aLazyGridTaintsItsAncestorsAndAMemoHitIsNeverStale`, `theLayoutGuideLazyGridPacksFourColumnsAndRealizesTenRows` |
| S2 min-first pass removed (`minimum < 0` for the overflow test) | `flexibleItemsFollowTheProbe` (C15 only: C5 gives the same 120 either way) |
| S3 a clamped maximum gives the excess back (water-fill) | `flexibleItemsFollowTheProbe` (C4, C6) |
| S4 `availableForUnspecified` reads the widest first-line cell | `anUnspecifiedExtentIsTheFirstLinesCells`, `aNilWidthTakesTheFirstRowAndAnAdaptiveItemMakesOneColumn` |
| S5 the whole rest to the adaptive item | `anAdaptiveItemBesideAFlexibleOneSharesTheRestEqually` |
| S6 origin always 0 | `adaptiveItemsPackAsTheProbeSays`, `flexibleItemsFollowTheProbe`, `gapsAndAlignmentPlaceTheTracks`, `aLazyVGridPlacesTracksAndCellsByTheGridAlignment`, `aLazyVGridPlacesCellsInTheirTracksAndSizesRowsByTheirTallestCell`, `aForEachElementOfSeveralViewsIsOneGridCell` |
| L6 overflow centred instead of origin 0 | `flexibleItemsFollowTheProbe` only (equivalent at layout level: placement is handed bounds = the answer, so the overflow branch is reached only by `sizeThatFits`) |
| L1 `trackFactor` 0 (the grid alignment does not place the tracks) | `aLazyVGridPlacesTracksAndCellsByTheGridAlignment`, `...PlacesCellsInTheirTracksAndSizesRowsByTheirTallestCell`, `aForEachElementOfSeveralViewsIsOneGridCell` |
| L2 cell alignment always `.center` | `aLazyVGridPlacesTracksAndCellsByTheGridAlignment`, `...AndSizesRowsByTheirTallestCell` |
| L3 a row sized by its first cell | `aLazyVGridPlacesCellsInTheirTracksAndSizesRowsByTheirTallestCell`, `aRowIsAsTallAsItsTallestRealizedCell` |
| L4 a cell's nodes not stacked | `aForEachElementOfSeveralViewsIsOneGridCell` |
| L5 `LazyHGrid` on the vertical axis | `aLazyHGridIsTheSameOnTheOtherAxis`, `theLazyContainersDemoIsWindowedAndSettles` |
| E1 the window in cells, not lines | 16 tests: `aTenThousandCellLazyVGridRealizesOnlyTheWindow`, `scrollingAGridRealizesTheNewRowsAndTheAccessibilityTreeFollows`, `aStaleAdaptiveWidthIsCorrectedOnTheNextFrame`, `unrealizedRowsCountAsTheMeanOfTheMeasuredOnes`, `scrollToAnUnrealizedGridCellReachesIt`, `theLayoutGuideLazyGridPacksFourColumnsAndRealizesTenRows`, `theLazyContainersDemoIsWindowedAndSettles` and the layout arms |
| E2 mismatch detection removed | `aStaleAdaptiveWidthIsCorrectedOnTheNextFrame`, `anAdaptiveGridOutsideAScrollerPacksFromItsStoredWidth` |
| E3 `trailing: 0` (unrealised rows count as nothing) | `unrealizedRowsCountAsTheMeanOfTheMeasuredOnes`, `scrollToAnUnrealizedGridCellReachesIt` |
| E4 the width not stored outside a scroller | `anAdaptiveGridOutsideAScrollerPacksFromItsStoredWidth` |
| E6 cells not prepainted (no hitbox, no accessibility) | `aLazyGridCellIsAnOrdinaryOccurrence`, `scrollingAGridRealizesTheNewRowsAndTheAccessibilityTreeFollows` and 11 more |
| W1 `LazyGridLayout` `Hashable` over its visible fields | `aLazyGridTaintsItsAncestorsAndAMemoHitIsNeverStale` |
| MG3a `LazyHGrid.init`'s `alignment:` renamed `align:` | `gridItemAndTheLazyGridsHaveSwiftUIsSpellings` |
| MG3b a `pinnedViews:` parameter added to `LazyHGrid.init` | `gridItemAndTheLazyGridsHaveSwiftUIsSpellings` |
| M-carry (lane 1's code): the `scrollTo` refinement carry removed | `scrollToAnUnrealizedElementReachesItInAtMostTwoResolutions`, `scrollToAnUnrealizedGridCellReachesIt` |
| M14b (lane 1's code): `noteWindowedParent` replaced by `noteLoop(extent: 0)` in both `ForEach` sources | `aScrolledOutChildKeepsItsStateAndTheTableBoundsIt`, `aScrolledOutGridCellKeepsItsState` |

Not separately mutated: 3.10's `.equatable()` arm (its code path is lane 1's, mutation 2.13) and `MG3a` as the spec spelled it (renaming `columns:` breaks every caller, so
the build fails first: the `LazyHGrid` argument was renamed instead). A rename of `LazyVGrid.columns:` is therefore guarded by the compile of every call site.

## 5 Verification

(Filled in by the final runs, section 5 of this file is updated in the verification commit.)

## 6 Deferred and owed

- `pinnedViews:` and `Section` (`LZ-N`, follow-up L2); windowed `if`/`switch`/`for` members (follow-up L1b); extracting `List`'s planner (`LZ-C`).
- Two adaptive items, or an adaptive beside a flexible one, are unprobed: the equal share is MetalUI's own ruling (`LZ-K`, pinned by 3.1e, no SwiftUI claim).
- The SDL demo (`MetalUISDLDemo`) does not carry the lazy demo (`Backends/SDL` untouched; human check `LZ5`).
- Accessibility exposes realised children only and no list position (`LZ-J`); VoiceOver is a human check (`LZ3`). Real-window looks: group `LZ`.
- Windows: the solver is pure and the grids add no Apple import, compiled by CI only; the unlocked-screen re-take of `AppKitPresentationTests` is owed (the screen was locked).
