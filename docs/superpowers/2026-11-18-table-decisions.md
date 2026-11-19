# `Table` with rows and columns virtualised (prefix `TBL-`): decisions

Requester: Sift, a database explorer (millions of rows by hundreds of columns). Branch `feat/table-a` (PR A), then PRs B to E; records 388 to 392 at planning time; class `A` (SwiftUI's `Table`) except the MetalUI-only modifiers (class `M`); divergence labels 1105–1114 reserved (see `docs/rules/divergence-labels.md`). Spec `specs/2026-11-18-table-design.md`, plan `plans/2026-11-18-table.md`. Probe `docs/probes/swiftui-table.swift` (arms `G1`..`F1`, written in PR B task B0).

Next unused id: `TBL-X`.

Every ruling below is marked "(ruled, not built)" until the PR that builds it flips it. `TBL-H`, `TBL-I` and `TBL-M` are built in PR A.

## TBL-A: recommendation and scope (ruled, not built)

Build SwiftUI's `Table`, not a separate `LazyTable`. Sift's needs fit `Table` plus three MetalUI-only modifiers: `tableRowHeight`, `tableFrozenColumns` and `tableRowIndex`. The two-axis engine (`ColumnExtentIndex`, `UniformWindow`, `TableWindowPlanner`) is internal and reusable, so a later lazy grid can adopt it with no public API. `Table` owns its scroller: a `ProposalScrollView([.horizontal, .vertical])` around an internal `TableBody`.

## TBL-B: types, builder, column keys, `TableColumnForEach` (ruled, not built)

`Table<Value, Rows, Columns>`, `TableColumn`, `TableColumnBuilder`, `TableColumnGroup` and `TableColumnForEach` follow SwiftUI, with divergence 1110 for the type shape (`Columns` is the builder's erased `TableColumnGroup`, and `alignment(_:)` returns `TableColumn`). A static column is keyed by its structural slot path (`.slot([UInt16])`, with `buildEither` and `buildOptional` adding a branch component as `ID-B` does); a `TableColumnForEach` element is keyed `.element(slotPath, AnyHashable(id))`. Display position is never identity.

## TBL-C: Foundation portability (ruled, not built)

Sorting types are Foundation's: `SortComparator`, `KeyPathComparator`, `SortOrder`, `String.StandardComparator` and `Never: SortComparator`. Their availability on Linux and Windows is guarded in CI by task B0.

## TBL-D: the row-source contract, `tableRowIndex` (ruled, not built)

`Data` is any `RandomAccessCollection` whose `count` and `subscript(position)` are O(1). The table reads only realised positions: one `data.count` per build and one `data[i]` per realised row per build. `tableRowIndex { id -> Int? }` replaces O(n) id scans; without it the table scans, as `List` documents.

## TBL-E: the internal scroller, pins from the clamped offset, indicator margin (ruled, not built)

The scroller's layout offset is raw (wheel events bank past the ends until prepaint clamps them, `XS-E`), so the table clamps it itself into its exact content extents before placing anything. The header goes at content `y = offset.y` and a frozen cell at content `x = offset.x + Σwf(before it)`, so a wheel past either end never moves the pins. The header's height is a `.contentMargins(.top, header, for: .scrollIndicators)`.

## TBL-F: uniform rows (divergence 1105) (ruled, not built)

Rows are one uniform height from `tableRowHeight(_:)` (default `TableMetrics.rowHeight`). A cell taller than the row is clipped, where SwiftUI sizes the row to its content (arm T2). Content-sized rows stay `List`'s.

## TBL-G: widths and fill (divergence 1106) (ruled, not built)

`TableWidthSolver.resolve` takes a fixed width as is, else the user override, else `ideal`, else the default width, clamped to `[min, max]`. A surplus is split uniformly among flexible columns (not fixed, not overridden, below their max), repeating as columns cap. There is no shrinking when the sum exceeds the viewport (arm W3); divergence 1106 is used only if SwiftUI shrinks.

## TBL-H: the column index and window (built, PR A)

`ColumnExtentIndex` holds prefix offsets: `offset(of:)` and `width(at:)` are O(1), `index(containing:)` and `firstIndex(startingAtOrAfter:)` binary searches. A rebuild is O(C), once per build; widths are declared, never measured, so there is no anchor correction. The window is `max(0, index(containing: top) − 1) ..< min(C, firstIndex(startingAtOrAfter: top + viewport) + 1)`, which for uniform widths equals `UniformWindow.lines` with overscan 1. Frozen columns are the first `f` declared columns, always realised; the scrolling columns window over the band after them.

## TBL-I: the row window, the planner, staleness (built, PR A)

`List.window`'s arithmetic is extracted, behaviour unchanged, into `UniformWindow.lines(count:extent:offset:viewport:origin:overscan:)`. `TableWindowPlanner.plan` runs at layout from `pass.scrollContext` and `.along(.horizontal)`; `fresh` recomputes from the resolved offsets and this frame's viewport at prepaint; `contains` compares rows, columns, the widths digest and the pin offsets, and a cold plan never contains a bounded one. The cold frame realises rows `0..<min(32, N)` and columns `0..<min(16, C)`, never everything. A settled table asks for no further frame.

## TBL-J: identity and windowed parents (ruled, not built)

Cell identity is (row id × column key), never the window position or display order. `TableBody` and each `TableRowElement` call `noteWindowedParent` (`ID-R`). A scrolled-out cell keeps its `@State` for two generations (`TB-AH`).

## TBL-K: cells, truncation, alignment (ruled, not built)

`TableCellBox` is an internal `Element`, not a `Box`, so it mints no `$anim` slot. Content is proposed `(width − 2 × cellInset, rowHeight)`, aligned by the column's `TableColumnAlignment` and clipped in paint. `TableBody` pushes `lineLimit = 1` and tail truncation once around all rows. Frozen cells paint the row's background under their content.

## TBL-L: state, `RW-I`, replay (ruled, not built)

`Table`'s `@State columnState` holds the user's widths and order and the drag states, written only by the divider and header handlers. `TableViewState` (lead, anchor, position cache, last plan) sits at the body id and is written through `withState(…, unchanged: TableViewState.sameEntry)`, never `write`, so a settled table taints nothing. `Table` inserts no `.equatable()` boundary of its own in v1.

## TBL-M: counters and cost (built, PR A)

`Frame.tableWork` counts `rowsRealized`, `cellsRealized`, `columnsResolved`, `dataReads` and `coldFrames` per build, never time, and `FrameWork` exposes them as `tableRowsRealized`, `tableCellsRealized`, `tableColumnsResolved`, `tableDataReads` and `tableColdFrames` (class M). All are 0 in a window with no table, and a window with no table keeps its `elementRequests` (6 for `PointerDragFrameCostTests` R5's steady frame, and the `List` literal in `TableFrameCostTests`). The table's own cost literals land with PR B.

## TBL-N: selection (ruled, not built)

Clicks follow `ListSelectionController`: a click selects and focuses, `Modifiers.primary`-click toggles in a multi-selection table, ⇧-click selects the range from the anchor. Positions come from a `TableRowPositionCache` (an LRU of 8) verified with one read, then `tableRowIndex`, then a scan. `ListRowSpace` gains an optional `firstSelected` hook, nil by default, so `List` is unchanged.

## TBL-O: keys (divergence 1109) (ruled, not built)

↑ ↓ (with ⇧) use `ControlKeys.listMove`. Page Up, Page Down, Home and End scroll only (arm K3 decides). ← → are declined (arm K4), Return runs `primaryAction(selection)`, ⌘A is not handled (arm K7), and there is no type-select (divergence 1109 if arm K6 shows SwiftUI type-selects). A keyboard reveal keeps the horizontal band and clears the header, resolved by position.

## TBL-P: context menu and double-click (ruled, not built)

The existing `contextMenu(forSelectionType:menu:primaryAction:)` (`OG-G`, `OG-N`) supplies the menu when `I == Value.ID`. A row's menu gets `row ∈ selection ? selection : [row]`, empty space gets `[]`, a click count of exactly 2 runs `primaryAction([row])` after the selection click, and a row child's `.onTapGesture(count: 2)` must not swallow the selection click.

## TBL-Q: sorting (ruled, not built)

A header cell carries one `DragGesture(minimumDistance: 0)`; a drag shorter than `reorderThreshold` is a sort click. The click flips `sortOrder.first` if it is the column's prototype comparator, otherwise moves it to the front (arms S1–S4). The binding is written once; the table never sorts the data.

## TBL-R: resize (divergence 1111) (ruled, not built)

A `TableColumnDivider` is a 6-point hit area on the column's trailing edge, modelled on `SplitDividerHitArea`, with the `.columnResize` pointer. A drag writes `columnState.widths[key]` clamped, only when the value changes; a fixed-width column has none. A neighbour does not give way (divergence 1111 if arm R2 shows SwiftUI compensating).

## TBL-S: reorder (ruled, not built)

The dragged header cell paints at the pointer offset (a `@State` write per step) and the order is written when the pointer crosses a neighbour's midpoint. Frozen columns cannot be dragged and nothing drops among them. Reorder is on by default only if arm R1 shows SwiftUI allows it.

## TBL-T: accessibility (divergence 1107, amends 32) (ruled, not built)

The platform tree gains `AccessibilityRole.columnHeader`, `columnCount`, `columnIndex`, `headerRowCount` and `sortDirection`; a node with a non-nil `columnCount` on a `.table` is a data table. AppKit publishes no `AXColumn` elements (divergence 1107) and cells carry index ranges; AccessKit's `row_count` and `row_index` count the header row where AppKit's do not. Divergence 32 gains `Table`'s realised rows and cells.

## TBL-U: not offered (ruled, not built)

The rows form (`Table(of:columns:rows:)`, `TableRow`, `DisclosureTableRow`), column customisation, `.tableStyle`, `TableColumnAlignment.numeric(_:)`, `SortDescriptor` and `LocalizedStringResource` forms, row drag, `onDelete`/`onMove`, `scrollPosition(id:)`, a header context menu and double-click auto-size are not in v1.

## TBL-V: look, demo, human checks (ruled, not built)

Metrics live in `TableMetrics` and come from arms G1 and G2 (provisional in PR A: row 24, header 28, default width 100, minimum 20, cell inset 6, divider hit 6, reorder threshold 3). The demo is `METALUI_TABLE_DEMO=1` over 1 000 000 × 200 rows, and the TBL group is added to `docs/verification/human-checks.md`.

## TBL-W: RTL (divergence 1108) (ruled, not built)

In a right-to-left environment columns are laid out left to right and the frozen column stays on the left, only if arm L1 shows SwiftUI mirroring.

## Carried

- Per-row retention for `Value: Equatable` (a `.equatable()` boundary per row).
- `TableColumnCustomization` and the `columnCustomization:` inits.
- The rows form (`TableRow`, `DisclosureTableRow`).
- RTL, if divergence 1108 is used.
- Double-click on a divider to size the column to fit.
