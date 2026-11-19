# 388: Table PR A, the two-axis window engine (`TBL-H`, `TBL-I`, `TBL-M`)

Class `M` (internal engine and counters); no public `Table` yet, no divergence used. Branch `feat/table-a`, base master `91a9904e`. Spec `docs/superpowers/specs/2026-11-18-table-design.md`, plan `docs/superpowers/plans/2026-11-18-table.md`, decisions `docs/superpowers/2026-11-18-table-decisions.md`.

## Change

- `UniformWindow.lines(count:extent:offset:viewport:origin:overscan:)` is `List.window`'s arithmetic extracted unchanged; `List.window` forwards with its own overscan.
- `ColumnExtentIndex` (`TableColumnIndex.swift`): prefix offsets, O(1) `offset(of:)`/`width(at:)`, O(log C) `index(containing:)`/`firstIndex(startingAtOrAfter:)`, and a clamped `window(offset:viewport:overscan:)` that equals `UniformWindow.lines` for equal widths.
- `TableWidthSolver` and `TableMetrics` (`TableWidths.swift`, `TableMetrics.swift`): fixed, override, ideal, default, clamp, then a repeating uniform fill of the surplus; no shrink. Metrics are provisional (24, 28, 100, 20, 6, 6, 3) until PR B's probe.
- `TableWindowPlanner` (`TableWindow.swift`): `plan` (layout, from `ScrollContext` and `.along(.horizontal)`), `fresh` (prepaint, from `ScrollerFrame`) and `contains`. Offsets are clamped into the exact content so the pins never follow an overscroll; a cold plan (viewport 0 or no context) is 32 rows by 16 columns and never contains a bounded one.
- `Frame.tableWork` and five public `FrameWork` fields (`tableRowsRealized`, `tableCellsRealized`, `tableColumnsResolved`, `tableDataReads`, `tableColdFrames`), 0 in a window with no table.

## Measured on master `91a9904e`, before the change

- R5's `WriterChip` steady `elementRequests`: 6.
- A `List` of 40 rows at `rowHeight` 28 in a 300-point `ScrollView` in a 300 x 300 window: 28 steady element requests. Both unchanged after.

## Tests

`TableWindowTests` (13 tests) and `TableFrameCostTests` (2). Each names its mutation in its doc comment. The round (all restored, `git status` clean of source changes after):

| test | mutation | red tests |
|---|---|---|
| `uniformWindowPinsTheListArithmetic` | drop `max(0, total - viewport)` | itself |
| `aColumnIndexAnswersPrefixOffsetsAndContainment` | `<=` to `<` in `index(containing:)` | itself, plus the column window, uniform agreement and three planner tests |
| `aColumnWindowIsViewportPlusOneEachSide` | overscan on the leading side only | itself, uniform agreement and three planner tests |
| `aUniformColumnIndexAgreesWithTheUniformWindow` | `firstIndex` as `index(containing) + 1` | itself and six others |
| `widthsResolveFixedIdealDefaultAndOverride` | drop the clamp | itself |
| `surplusGrowsFlexibleColumnsUniformlyUpToTheirMax` | one distribution pass | itself |
| `noSurplusMeansNoShrink` | scale down to the viewport (our own, not the plan's) | itself |
| `anOverriddenColumnTakesNoSurplus` | overridden columns count as flexible (our own) | itself |
| `aBoundedPlanWindowsBothAxesFromTheContext` | rows use the full viewport height | itself and `aPlanClampsARawOffsetPastEitherEnd` |
| `aPlanClampsARawOffsetPastEitherEnd` | raw offsets | itself |
| `aColdPlanTakesThirtyTwoRowsAndSixteenColumns` | cold rows `0..<count` | itself |
| `frozenColumnsAreOutsideTheWindowAndAlwaysPlanned` | ignore the frozen width in the band | itself |
| `containmentIgnoresAnInnerShiftAndCatchesEveryOther` | omit the digest from `contains` | itself |
| `aWindowWithoutATableReportsNoTableWork` | `coldFrames` starts at 1 | itself |
| `aWindowWithoutATableKeepsItsSteadyRequests` | `List.overscan = 3` (the plan named `LazyWindow.overscan`, which `List` does not read) | itself (the `List` literal 28 moves) | Nothing in PR A uses a Darwin-only API.

## Deviations from the plan

- `TableFixtures.swift` holds `RowRef`, `CountingRows` and the steady constants only; `tableFixture` and `scrollTable` need `Table` and arrive in PR B.
- The `ScrollContext` test init is `init(offset:viewportExtent:axis:cross:)` in `TableWindow.swift`.

`RetainedSubtreeInternalTests.everyFrameChannelIsClassified` needed `"tableWork": .buildOnly` for the new `Frame` property. Full root run (`--build-system native`, `--no-parallel`): 7057 tests in 79 suites; the single red was that guard, green after the row.
