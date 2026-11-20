# `Table` with rows and columns virtualised (prefix `TBL-`): decisions

Requester: Sift, a database explorer (millions of rows by hundreds of columns). Branch `feat/table-a` (PR A), then PRs B to E; records 388 to 392 at planning time; class `A` (SwiftUI's `Table`) except the MetalUI-only modifiers (class `M`); divergence labels 1105–1114 reserved (see `docs/rules/divergence-labels.md`). Spec `specs/2026-11-18-table-design.md`, plan `plans/2026-11-18-table.md`. Probe `docs/probes/swiftui-table.swift` (arms `G1`..`F1`, written in PR B task B0).

Next unused id: `TBL-Y`.

Every ruling below is marked "(ruled, not built)" until the PR that builds it flips it. `TBL-H`, `TBL-I` and `TBL-M` are built in PR A (record 388); `TBL-A`..`TBL-G`, `TBL-J`, `TBL-K` and `TBL-L` in PR B (record 389), where the probe `docs/probes/swiftui-table.swift` was run (macOS 27.2.1, 2026-11-19) and decided the arms the spec left open: its read is in the probe's header and `swiftui-table.recorded.txt`.

## TBL-A: recommendation and scope (built, PR B)

Build SwiftUI's `Table`, not a separate `LazyTable`. Sift's needs fit `Table` plus three MetalUI-only modifiers: `tableRowHeight`, `tableFrozenColumns` and `tableRowIndex`. The two-axis engine (`ColumnExtentIndex`, `UniformWindow`, `TableWindowPlanner`) is internal and reusable, so a later lazy grid can adopt it with no public API. `Table` owns its scroller: a `ProposalScrollView([.horizontal, .vertical])` around an internal `TableBody`.

## TBL-B: types, builder, column keys, `TableColumnForEach` (built, PR B)

`Table<Value, Rows, Columns>`, `TableColumn`, `TableColumnBuilder`, `TableColumnGroup` and `TableColumnForEach` follow SwiftUI, with divergence 1110 for the type shape (`Columns` is the builder's erased `TableColumnGroup`, and `alignment(_:)` returns `TableColumn`). A static column is keyed by its structural slot path (`.slot([UInt16])`, with `buildEither` and `buildOptional` adding a branch component as `ID-B` does); a `TableColumnForEach` element is keyed `.element(slotPath, AnyHashable(id))`. Display position is never identity. The column's cell content is any `ElementGroup` (`@ElementBuilder`; a `Component` and an `.equatable()` cell are accepted, as a `ViewBuilder` accepts any view), wrapped as `LegacyContent` in the cell, so the cell's one request and one paint are its own and the content's; divergence 1110 says so. Probe `F1`: appending a column to a `TableColumnForEach` keeps the survivors' `@State` in SwiftUI; **removing** one aborts SwiftUI itself in the rig (`SIGABRT`, "accessing attribute in a different namespace"), so only the append was measurable. MetalUI keeps the surviving columns' state across a removal, by key (`aDynamicColumnSetKeepsSurvivingCellsState`).

## TBL-C: Foundation portability (built, PR B)

Sorting types are Foundation's: `SortComparator`, `KeyPathComparator`, `SortOrder`, `String.StandardComparator` and `Never: SortComparator`. Their availability on Linux and Windows is guarded in CI by task B0. Guard: `foundationSortTypesAreAvailableOnEveryPlatform`; the macOS run is green, Linux and Windows run in the PR's CI.

## TBL-D: the row-source contract, `tableRowIndex` (built, PR B)

`Data` is any `RandomAccessCollection` whose `count` and `subscript(position)` are O(1). The table reads only realised positions: one `data.count` per build and one `data[i]` per realised row per build. `tableRowIndex { id -> Int? }` replaces O(n) id scans; without it the table scans, as `List` documents. `TableSource` reads by position: the count once per build and `data[i]` once per realised row, through index arithmetic when `Data.Index` is `Int` (the stdlib's Strideable `index(_:offsetBy:)` range-checks against `endIndex`, which a counting collection would count per row), through `index(_:offsetBy:)` otherwise. Pinned by `aTableReadsEachRealisedRowOnceAndTheCountOncePerBuild` (28 reads and one count).

## TBL-E: the internal scroller, pins from the clamped offset, indicator margin (built, PR B)

The scroller's layout offset is raw (wheel events bank past the ends until prepaint clamps them, `XS-E`), so the table clamps it itself into its exact content extents before placing anything. The header goes at content `y = offset.y` and a frozen cell at content `x = offset.x + Σwf(before it)`, so a wheel past either end never moves the pins. The header's height is a `.contentMargins(.top, header, for: .scrollIndicators)`.

## TBL-F: uniform rows (divergence 1105) (built, PR B)

Rows are one uniform height from `tableRowHeight(_:)` (default `TableMetrics.rowHeight`). A cell taller than the row is clipped, where SwiftUI sizes the row to its content (arm T2). Content-sized rows stay `List`'s. Probe `T2` confirmed it: a three-`Text` cell makes SwiftUI's row 56 high against 24, `usesAutomaticRowHeights` true. **Amended by `TBL-K`:** a cell is clipped only when its content overflows it.

## TBL-G: widths and fill (divergence 1106) (built, PR B)

`TableWidthSolver.resolve` takes a fixed width as is, else the user override, else `ideal`, else the default width, clamped to `[min, max]`. A surplus is split uniformly among flexible columns (not fixed, not overridden, below their max), repeating as columns cap. There is no shrinking when the sum exceeds the viewport (arm W3); divergence 1106 is used only if SwiftUI shrinks. Probe `W1`: a column with no width is 100 wide; `W4`: the default minimum is 10 (NSTableColumn), so `TableMetrics.defaultMinWidth` fell from the provisional 20 to 10; `W2`: a surplus is split uniformly among the flexible columns, a column stops at its maximum and the rest goes to the others (fixed 100, (min 50 ideal 100 max 150), (ideal 100) in 800 give 100, 150, 484: the fill pass stays, A3 test 2 stays); `W3`: ten columns of 100 in 400 stay 1000 wide, so **divergence 1106 stays unused**. The AppKit chrome (10-point side margins, 17-point intercell spacing) takes about 66 of the 800 and is not modelled.

## TBL-H: the column index and window (built, PR A)

`ColumnExtentIndex` holds prefix offsets: `offset(of:)` and `width(at:)` are O(1), `index(containing:)` and `firstIndex(startingAtOrAfter:)` binary searches. A rebuild is O(C), once per build; widths are declared, never measured, so there is no anchor correction. The window is `max(0, index(containing: top) − 1) ..< min(C, firstIndex(startingAtOrAfter: top + viewport) + 1)`, which for uniform widths equals `UniformWindow.lines` with overscan 1. Frozen columns are the first `f` declared columns, always realised; the scrolling columns window over the band after them.

## TBL-I: the row window, the planner, staleness (built, PR A)

`List.window`'s arithmetic is extracted, behaviour unchanged, into `UniformWindow.lines(count:extent:offset:viewport:origin:overscan:)`. `TableWindowPlanner.plan` runs at layout from `pass.scrollContext` and `.along(.horizontal)`; `fresh` recomputes from the resolved offsets and this frame's viewport at prepaint; `contains` compares rows, columns, the widths digest and the pin offsets, and a cold plan never contains a bounded one. The cold frame realises rows `0..<min(32, N)` and columns `0..<min(16, C)`, never everything. A settled table asks for no further frame.

## TBL-J: identity and windowed parents (built, PR B)

Cell identity is (row id × column key), never the window position or display order. `TableBody` and each `TableRowElement` call `noteWindowedParent` (`ID-R`). A scrolled-out cell keeps its `@State` for two generations (`TB-AH`).

## TBL-K: cells, truncation, alignment (built, PR B)

`TableCellBox` is an internal `Element`, not a `Box`, so it mints no `$anim` slot. Content is proposed `(width − 2 × cellInset, rowHeight)`, aligned by the column's `TableColumnAlignment` and clipped in paint. `TableBody` pushes `lineLimit = 1` and tail truncation once around all rows. Frozen cells paint the row's background under their content. **Amendment (PR B): a cell is clipped to its box only when its content is laid out larger than the box.** The plan clips every cell in prepaint and paint. A clip on the pass's stack is part of the replay key's ambient (`AmbientKey.clip`, translated into window space), so a clipped cell's `.equatable()` content never replays translated on a scroll step (measured: 0 translated, 280 misses; unclipped: 270 translated and 10 misses, the plan's figure). Content that fits cannot reach a neighbour, so the clip would only cost the replay; content that overflows (divergence 1105) is clipped as the plan says. A paint outside a node's own bounds (a shadow, an overlay) is therefore not clipped in a cell that fits. Pinned by `aCellTallerThanItsRowIsClippedToIt` and `equatableCellsReplayTranslatedOnAScrollStep`. A frozen cell and a frozen header cell paint the row's (or the window's) background under themselves, so they are opaque over the scrolled cells.

## TBL-L: state, `RW-I`, replay (built, PR B)

`Table`'s `@State columnState` holds the user's widths and order and the drag states, written only by the divider and header handlers. `TableViewState` (lead, anchor, position cache, last plan) sits at the body id and is written through `withState(…, unchanged: TableViewState.sameEntry)`, never `write`, so a settled table taints nothing. `Table` inserts no `.equatable()` boundary of its own in v1.

## TBL-M: counters and cost (built, PR A)

`Frame.tableWork` counts `rowsRealized`, `cellsRealized`, `columnsResolved`, `dataReads` and `coldFrames` per build, never time, and `FrameWork` exposes them as `tableRowsRealized`, `tableCellsRealized`, `tableColumnsResolved`, `tableDataReads` and `tableColdFrames` (class M). All are 0 in a window with no table, and a window with no table keeps its `elementRequests` (6 for `PointerDragFrameCostTests` R5's steady frame, and the `List` literal in `TableFrameCostTests`). The table's own cost literals land with PR B.

## TBL-N: selection (ruled, not built)

Clicks follow `ListSelectionController`: a click selects and focuses, `Modifiers.primary`-click toggles in a multi-selection table, ⇧-click selects the range from the anchor. Positions come from a `TableRowPositionCache` (an LRU of 8) verified with one read, then `tableRowIndex`, then a scan. `ListRowSpace` gains an optional `firstSelected` hook, nil by default, so `List` is unchanged. Probe: a row click and ⌘-/⇧-selection are AppKit's; not measured here (record 390).

## TBL-O: keys (divergence 1109) (ruled, not built)

↑ ↓ (with ⇧) use `ControlKeys.listMove`. Page Up, Page Down, Home and End scroll only (arm K3 decides). ← → are declined (arm K4), Return runs `primaryAction(selection)`, ⌘A is not handled (arm K7), and there is no type-select (divergence 1109 if arm K6 shows SwiftUI type-selects). A keyboard reveal keeps the horizontal band and clears the header, resolved by position. **Probe (macOS 27.2.1):** `K1` ↓ moves one row with one write and ⇧↑ extends; `K3` Home and End scroll to the ends and write nothing (Page Up and Page Down wrote nothing and did not scroll under a synthetic event: unmeasured, the default "scroll only, selection unchanged" stands); `K4` ← → write nothing; `K5` Return runs the `primaryAction` with the whole selection; `K7` ⌘A writes nothing; **`K6`: typing "name" selects row 0, SwiftUI type-selects, so divergence 1109 is used** (record 390).

## TBL-P: context menu and double-click (ruled, not built)

The existing `contextMenu(forSelectionType:menu:primaryAction:)` (`OG-G`, `OG-N`) supplies the menu when `I == Value.ID`. A row's menu gets `row ∈ selection ? selection : [row]`, empty space gets `[]`, a click count of exactly 2 runs `primaryAction([row])` after the selection click, and a row child's `.onTapGesture(count: 2)` must not swallow the selection click.

## TBL-Q: sorting (ruled, not built)

A header cell carries one `DragGesture(minimumDistance: 0)`; a drag shorter than `reorderThreshold` is a sort click. The click flips `sortOrder.first` if it is the column's prototype comparator, otherwise moves it to the front (arms S1–S4). The binding is written once; the table never sorts the data. **Probe `S1`..`S4`** (a header click, one write each): nothing sorted, click Name gives `[name+]`; click again `[name-]`; click Size with `[name-]` gives `[size+, name-]` (the new column first, the old entry stays); click Name with `[size+, name-]` gives `[name-, size+]` — an existing entry moves to the front **keeping its order**, it is not reset or flipped. A column with no comparator writes nothing. The spec's "remove every entry equal to p ignoring order and insert p at the front" is wrong for the last case; record 390 takes this read.

## TBL-R: resize (divergence 1111) (ruled, not built)

A `TableColumnDivider` is a 6-point hit area on the column's trailing edge, modelled on `SplitDividerHitArea`, with the `.columnResize` pointer. A drag writes `columnState.widths[key]` clamped, only when the value changes; a fixed-width column has none. A neighbour does not give way (divergence 1111 if arm R2 shows SwiftUI compensating). **Probe `R2`:** dragging a divider +40 changes widths 206, 206, 100, 205 to 206, 246, 100, 165: the last column gives the 40 back, so **divergence 1111 is used** (record 391). `R3`: a fixed-width column has `resizingMask` 0 and `min == max`.

## TBL-S: reorder (ruled, not built)

The dragged header cell paints at the pointer offset (a `@State` write per step) and the order is written when the pointer crosses a neighbour's midpoint. Frozen columns cannot be dragged and nothing drops among them. Reorder is on by default only if arm R1 shows SwiftUI allows it. **Probe `R1`: `allowsColumnReordering` is false** without a column customisation, so headers do not reorder by default: record 391 attaches no reorder gesture and replaces the reorder tests with `headersDoNotReorderByDefault` (no MetalUI switch in v1).

## TBL-T: accessibility (divergence 1107, amends 32) (ruled, not built)

The platform tree gains `AccessibilityRole.columnHeader`, `columnCount`, `columnIndex`, `headerRowCount` and `sortDirection`; a node with a non-nil `columnCount` on a `.table` is a data table. AppKit publishes no `AXColumn` elements (divergence 1107) and cells carry index ranges; AccessKit's `row_count` and `row_index` count the header row where AppKit's do not. Divergence 32 gains `Table`'s realised rows and cells. **Probe `A1`/`A2`:** SwiftUI's table is an `AXOutline` (not `AXTable`) whose `AXRows` are every row (300 of 300 after a scroll, `AXVisibleRows` 25), each `AXRow`/`AXOutlineRow` with `AXCell` children carrying `AXRowIndexRange` and `AXColumnIndexRange`; `AXColumns` are present; the header's children are `AXButton`/`AXSortButton` with `AXSortDirection`. Record 392 reads this before it chooses the AppKit roles.

## TBL-U: not offered (ruled, not built)

The rows form (`Table(of:columns:rows:)`, `TableRow`, `DisclosureTableRow`), column customisation, `.tableStyle`, `TableColumnAlignment.numeric(_:)`, `SortDescriptor` and `LocalizedStringResource` forms, row drag, `onDelete`/`onMove`, `scrollPosition(id:)`, a header context menu and double-click auto-size are not in v1.

## TBL-V: look, demo, human checks (ruled, not built)

Metrics live in `TableMetrics` and come from arms G1 and G2 (provisional in PR A: row 24, header 28, default width 100, minimum 20, cell inset 6, divider hit 6, reorder threshold 3). The demo is `METALUI_TABLE_DEMO=1` over 1 000 000 × 200 rows, and the TBL group is added to `docs/verification/human-checks.md`. **Metrics (probe `G1`, `G2`):** row 24, header 28, a cell label 6 points in from its column, alternating row backgrounds (`usesAlternatingRowBackgroundColors` true; MetalUI tints odd rows `.surfaceSecondary`); not modelled: the inset style's 10-point side margins, 5-point top margin and 17-point intercell spacing. `G3`: a table in a vertical `ScrollView` is the proposed width by 0. The divider hit area (6) and the reorder threshold (3) are MetalUI's own. **Unmeasured:** Page Up/Down scrolling, the removal half of `F1`, the VoiceOver reading and the selection highlight colour. The demo is `METALUI_TABLE_DEMO=1`; its human-check group TBL is added by record 392.

## TBL-W: RTL (divergence 1108, unused) (built, PR B: nothing to build)

In a right-to-left environment columns are laid out left to right and the frozen column stays on the left, only if arm L1 shows SwiftUI mirroring. **Probe `L1`:** a right-to-left environment mirrors SwiftUI's columns (the first is the rightmost, x 476 against 361). **MetalUI mirrors too, so divergence 1108 stays unused and the ruling "columns laid out left to right" is withdrawn:** the layout engine mirrors a custom layout's placements and the scroller's offsets are logical, so the table's columns, its scroller's origin and its window agree with no code of the table's (pinned by `aRightToLeftTableMirrorsItsColumnsAndWindowsThemOnTheScroll`: columns 0...5 at open and no blank band after scrolling to the end). A frozen column is the leading one, so it sits on the right.

## TBL-X: the default string comparator off Darwin (divergence 1106) (built, PR B)

A string column (`TableColumn(_, value: \.name)`) sorts by `String.StandardComparator.localizedStandard` where Foundation has it, as SwiftUI does. swift-corelibs Foundation on Linux and Windows has neither `localized` nor `localizedStandard` (measured in `swift:6.4-noble`: both "no member"), so off Darwin the default is `lexical`; a caller can name any comparator that exists (`comparator:`). No MetalUI-owned comparator is added (`TBL-C`). The first CI run failed to build on Linux for exactly this: `TableFoundationGuards.swift` is not built by the portable-tests job, so its `localizedStandard` was never compiled there; the guard now splits at `#if canImport(Darwin)`.

## Carried

- Per-row retention for `Value: Equatable` (a `.equatable()` boundary per row).
- `TableColumnCustomization` and the `columnCustomization:` inits.
- The rows form (`TableRow`, `DisclosureTableRow`).
- RTL, if divergence 1108 is used.
- Double-click on a divider to size the column to fit.
