# Design: `Table` with rows and columns virtualised (prefix `TBL-`)

2026-11-18, master `91a9904e`. Requester: Sift, a database explorer that shows millions of rows by hundreds of columns (`Sift/docs/superpowers/specs/2026-11-18-sift-design.md`, section 2 and the Grid row).

## 0. Recommendation (`TBL-A`)

**Build SwiftUI's `Table`, not a separate `LazyTable`.**

- SwiftUI is the design authority and has `Table`.
- Sift's needs fit `Table` plus three MetalUI-only modifiers: `tableRowHeight`, `tableFrozenColumns` and `tableRowIndex`.
- A public `LazyTable` would add a second surface with its own divergences.

**The two-axis engine is internal and reusable.** It is `ColumnExtentIndex`, `UniformWindow` and `TableWindowPlanner`. A later lazy grid can adopt it without any public API.

**`Table` owns its scroller.** Internally it is a `ProposalScrollView([.horizontal, .vertical])` around an internal `TableBody`. This is SwiftUI's shape: a table is greedy and self-scrolling. It also lets the body know its own origin, which is the scroller's content origin. So `Table` needs no `ListOrigin`-style origin measurement and none of `DD-F`'s staleness. Only the viewport is one frame stale.

## 1. Public API

All public declarations are on `@MainActor` types in `Sources/MetalUI`. Each one owes a doc comment and an inventory row.

### 1.1 `Table` (class A, except where marked)

```swift
public struct Table<Value: Identifiable, Rows: TableRowContent, Columns: TableColumnContent>: Element, ProposalElement
    where Rows.TableRowValue == Value, Columns.TableRowValue == Value

extension Table {
  public init<Data: RandomAccessCollection>(_ data: Data,
      @TableColumnBuilder<Value, Never> columns: () -> Columns)
      where Rows == TableForEachContent<Data>, Data.Element == Value, Columns == TableColumnGroup<Value, Never>
  public init<Data>(_ data: Data, selection: Binding<Value.ID?>, @TableColumnBuilder<Value, Never> columns: () -> Columns) // same where
  public init<Data>(_ data: Data, selection: Binding<Set<Value.ID>>, @TableColumnBuilder<Value, Never> columns: () -> Columns)
  public init<Data, Sort: SortComparator>(_ data: Data, sortOrder: Binding<[Sort]>,
      @TableColumnBuilder<Value, Sort> columns: () -> Columns)
      where Rows == TableForEachContent<Data>, Data.Element == Value, Sort.Compared == Value, Columns == TableColumnGroup<Value, Sort>
  public init<Data, Sort>(_ data: Data, selection: Binding<Value.ID?>, sortOrder: Binding<[Sort]>, @TableColumnBuilder<Value, Sort> columns: () -> Columns)
  public init<Data, Sort>(_ data: Data, selection: Binding<Set<Value.ID>>, sortOrder: Binding<[Sort]>, @TableColumnBuilder<Value, Sort> columns: () -> Columns)

  // MetalUI-only (class M, TBL-F / TBL-H / TBL-D). Write them directly on the Table, before other modifiers (HS-G's rule).
  public func tableRowHeight(_ height: Pixels) -> Self             // uniform row height; default TableMetrics.rowHeight
  public func tableFrozenColumns(_ count: Int) -> Self             // the first `count` DECLARED columns stay at the leading edge; clamped to 0...columns
  public func tableRowIndex(_ lookup: @escaping @MainActor (Value.ID) -> Int?) -> Self   // id -> position; replaces O(n) scans
}
```

**What the builder runs, and when.** The `columns` builder runs in `init`, as SwiftUI's does. The data is retained and read only for realised rows (section 4.6).

**Selection.** The binding is `Binding<Value.ID?>` or `Binding<Set<Value.ID>>`. These are the same models as `List`, and the selection is never pruned.

### 1.2 Columns (class A, except the type shape in divergence 1110)

```swift
@MainActor public protocol TableColumnContent<TableRowValue, TableColumnSortComparator> {
  associatedtype TableRowValue: Identifiable
  associatedtype TableColumnSortComparator: SortComparator
}
@MainActor public protocol TableRowContent<TableRowValue> { associatedtype TableRowValue: Identifiable }

public struct TableColumn<RowValue: Identifiable, Sort: SortComparator, Content: Element, Label: Element>: TableColumnContent
// Every title spelling comes three ways: LocalizedStringKey, <S: StringProtocol> (@_disfavoredOverload) and Text. Label == Text.
//   where Sort == Never:
//     init(_ title, @ElementBuilder content: @escaping (RowValue) -> Content)
//     init(_ title, value: KeyPath<RowValue, String>) where Content == Text
//   where Sort == KeyPathComparator<RowValue>:
//     init<V: Comparable>(_ title, value: KeyPath<RowValue, V>, @ElementBuilder content:)
//     init<V, C: SortComparator>(_ title, value: KeyPath<RowValue, V>, comparator: C, @ElementBuilder content:) where C.Compared == V
//     init(_ title, value: KeyPath<RowValue, String>, comparator: String.StandardComparator = .localizedStandard) where Content == Text
//   where Sort.Compared == RowValue:
//     init(_ title, sortUsing comparator: Sort, @ElementBuilder content:)
  public func width(_ width: Pixels? = nil) -> Self                                  // fixed, not resizable
  public func width(min: Pixels? = nil, ideal: Pixels? = nil, max: Pixels? = nil) -> Self
  public func width() -> Self
  public func alignment(_ alignment: TableColumnAlignment) -> Self                   // SwiftUI returns some TableColumnContent (1110)

public struct TableColumnAlignment: Hashable, Sendable { .automatic, .leading, .center, .trailing, .numeric }   // .numeric(_:) not offered

@resultBuilder public struct TableColumnBuilder<RowValue: Identifiable, Sort: SortComparator>
  // buildExpression(TableColumnContent with the same Sort), and @_disfavoredOverload buildExpression(... Sort == Never),
  // which lifts the column; buildBlock(variadic), buildOptional, buildEither(first:)/(second:), buildLimitedAvailability;
  // buildFinalResult -> TableColumnGroup<RowValue, Sort>.
public struct TableColumnGroup<RowValue: Identifiable, Sort: SortComparator>: TableColumnContent   // erased, flattened columns (1110)

public struct TableColumnForEach<Data: RandomAccessCollection, ID: Hashable, RowValue: Identifiable, Sort: SortComparator, Content: TableColumnContent>: TableColumnContent
  // init(_ data:, @TableColumnBuilder<RowValue, Sort> content: @escaping (Data.Element) -> Content) where ID == Data.Element.ID, Data.Element: Identifiable
  // init(_ data:, id: KeyPath<Data.Element, ID>, @TableColumnBuilder<RowValue, Sort> content:)
  // init(_ data: Range<Int>, @TableColumnBuilder<RowValue, Sort> content: @escaping (Int) -> Content) where ID == Int

public struct TableForEachContent<Data: RandomAccessCollection>: TableRowContent where Data.Element: Identifiable
// an empty placeholder: never built by an app, like ListContentRows

extension ElementGroup { public func tableColumnHeaders(_ visibility: Visibility) -> EnvironmentScope<Self> }   // class A
```

**Dynamic columns (`TBL-B`).**

- SwiftUI's `TableColumnForEach` (macOS 14) is the shaped answer, and it is adopted.
- Sift writes `TableColumnForEach(result.columns) { c in TableColumn(c.name) { row in Text(row[c.ordinal]) } }`.
- The column descriptors are re-resolved every build in O(columns). That is cheap: no element is built. Cells are built only for windowed columns.

**Column identity, `TableColumnKey` (internal).**

- A static column is keyed by its structural slot path in the builder, `.slot([UInt16])`. `buildEither` and `buildOptional` add a branch component, as `ID-B` does. A sibling's key therefore survives an `if`.
- A `TableColumnForEach` element is keyed `.element(slotPath, AnyHashable(id))`.
- Display position is never identity.

**Sorting types are Foundation's.** `SortComparator`, `KeyPathComparator`, `SortOrder`, `String.StandardComparator` and `Never: SortComparator`. Their availability on Linux and Windows is guarded in task B0 (`TBL-C`).

### 1.3 Context menu, double-click, Return

These are the existing `contextMenu(forSelectionType:menu:primaryAction:)` (`OG-G`, `OG-N`). Table takes the menu from its own `handlers.contextual?.selection` or from the environment, and only when `I == Value.ID`.

- A row's menu gets `row ∈ selection ? selection : [row]`.
- Empty space gets `[]`.
- A click count of exactly 2 runs `primaryAction([row])` after the selection click.
- Return runs `primaryAction(selection)`.

### 1.4 Not offered in v1 (the "Not offered" table, ruling `TBL-U`)

- **The rows form:** `Table(of:columns:rows:)`, `TableRow`, `TableRowBuilder`, `DisclosureTableRow` and `Table(_:children:)`. `Rows` stays a generic parameter, so this can be added later without breaking anything.
- **Customisation:** `TableColumnCustomization`, `.customizationID`, `.defaultVisibility`, `.disabledCustomizationBehavior` and the `columnCustomization:` inits.
- `.tableStyle`, including a custom `TableStyle`.
- `TableColumnAlignment.numeric(_:)`.
- `SortDescriptor`/`NSObject` columns and the `LocalizedStringResource` title forms.
- Row drag (`itemProvider`), `onDelete`/`onMove`, and `scrollPosition(id:)` on a table.
- A header context menu for showing and hiding columns.
- Double-click on a divider to size the column to fit.

## 2. Divergences: labels 1105–1114 reserved by TBL

| label | what | ruling | condition |
|---|---|---|---|
| 1105 | Rows are one uniform height. A cell taller than the row is clipped, where SwiftUI sizes the row to its content (arm T2). | `TBL-F` | always |
| 1106 | Columns never shrink below their resolved width to fit the viewport; the table scrolls across instead. | `TBL-G` | only if arm W3 shows SwiftUI shrinking; otherwise the label stays unused |
| 1107 | AppKit publishes no `AXColumn` elements and no `AXColumns`/`AXVisibleColumns`; cells carry column index ranges. | `TBL-T` | always |
| 1108 | In a right-to-left environment columns are laid out left to right and the frozen column stays on the left. | `TBL-W` | only if arm L1 shows SwiftUI mirroring |
| 1109 | No type-select. | `TBL-O` | only if arm K6 shows SwiftUI type-selects |
| 1110 | Type shape: `Columns` is `TableColumnGroup<Value, Sort>`, the builder's erased result, and `alignment(_:)` returns `TableColumn`, not `some TableColumnContent`. | `TBL-B` | always |
| 1111 | A user resize does not make the neighbouring columns give way. | `TBL-R` | only if arm R2 shows SwiftUI compensating |
| 1112–1114 | unused | | |

**Amended divergence:** 32 (a virtualised container publishes realised rows only) gains `Table`'s rows and cells.

## 3. Layout and virtualisation

### 3.1 Structure and identity (`TBL-E`, `TBL-J`)

```
Table (Element; @State columnState: TableColumnState)
└ ProposalScrollView([.horizontal, .vertical])   (positional 0; `.contentMargins(.top, header, for: .scrollIndicators)`)
  └ TableBody<Value>   (internal Element; TableBodyLayout)
    ├ TableRowElement   named ElementID.forRow(row.id, keyed:)          (LH-A/LH-B: as a List row)
    │   └ TableCellBox  named ElementID.forColumn(columnKey, keyed:)    (new helper beside forRow)
    │       └ cell content (the column's closure)
    └ TableHeaderRow    (positional; built last so it prepaints and paints over the rows)
        └ TableHeaderCell named forColumn(key) ─ label Text, TableColumnDivider (6 pt hit area, as SplitDividerHitArea)
```

- **Cell identity** is (row id × column key). It never depends on the window position or the display order.
- **Windowed parents.** `TableBody` calls `stateTable.noteWindowedParent(bodyID)` for its rows, and each `TableRowElement` calls it for its cells. This is `ID-R`. Without it, a row or cell scrolled out of the window would be read as vanished.
- **Bounded state retention.** A scrolled-out cell keeps its `@State` for two generations, as `TB-AH` gives a `List` row.

### 3.2 Rows: uniform height, windowed by division (`TBL-F`, `TBL-I`)

**Height.** It is uniform, from `tableRowHeight(_:)` (default `TableMetrics.rowHeight`, 24 until arm G1 records otherwise). Variable heights are never part of `Table`; content-sized rows stay `List`'s.

**What is reused from `List`, exactly:**

- `List.window(count:rowExtent:offset:viewport:origin:)` is extracted, behaviour unchanged, into `UniformWindow.lines(count:extent:offset:viewport:origin:overscan:)`. `List.window` forwards to it.
- `LazyWindow.overscan` (2 rows) and `LazyWindow.coldLines` (32).
- `ElementID.forRow`, `DescriptionInjectiveID`, `StateTable.noteWindowedParent` and `Frame.insideListRows`. The last means no row content is seated by the first-draw focus rule (`FC-F`).
- `ListSelection`, `ListSelectionController`, `ListRowSpace` (one new optional hook) and `ListLeadStore`.
- `SelectionContextMenu`, `ControlKeys.listMove`, `AccessibilityRowSelection`, `withAccessibilitySuppressed(except:)` and `requestAccessibilityRetry`.

**Not reused:**

- `RowExtentIndex`: there is nothing to measure.
- `ListRows` and `WindowedRowsLayout`: a nil-width proposal measures every row twice there (`LR-CA`), and they have no pinned header.
- `ListOrigin`: the table's state is `TableViewState`.

**Vertical geometry.** The content height is `header + count × rowHeight`. With offset `y`, the rows window is `UniformWindow.lines(count, rowHeight, y, viewportHeight − header, 0, 2)`.

### 3.3 Columns: a prefix-sum index plus a horizontal planner (`TBL-G`, `TBL-H`)

**Resolving widths.** `TableWidthSolver.resolve(specs, overrides, viewport) -> [Double]` takes columns in display order and returns their widths:

1. A `width(x)` column is fixed at `x`. It ignores any override and is not resizable.
2. Otherwise the width is the user override (`TableColumnState.widths[key]`) if there is one, else `ideal`, else `TableMetrics.defaultWidth` (100, arm W1). It is clamped to `[min ?? TableMetrics.defaultMinWidth, max ?? ∞]`.
3. **Fill rule.** If `Σ < viewport`, the surplus is split uniformly among flexible columns: not fixed, not overridden, and below their max. Each is capped at its max, and the split repeats until the surplus or the flexible columns run out (arm W2).
4. There is no shrinking when `Σ > viewport`; the table scrolls across (arm W3; divergence 1106 if SwiftUI shrinks).

**The index.** `ColumnExtentIndex` is a value type holding the prefix offsets (`[Double]`, count + 1).

- `offset(of:)` and `width(at:)` are O(1).
- `index(containing:)` and `firstIndex(startingAtOrAfter:)` are binary searches, O(log C).
- A rebuild is O(C) and happens once per build. It does not use `RowExtentIndex`, because widths are declared, never measured or estimated, and there is no anchor correction.

**The window.**

- Columns use `ColumnExtentIndex.window(offset:viewport:overscan: 1)`. The top is clamped into `[0, max(0, total − viewport)]` as `UniformWindow` clamps it.
- The window is `max(0, index(containing: top) − 1) ..< min(C, firstIndex(startingAtOrAfter: top + viewport) + 1)`. For uniform widths this equals `UniformWindow.lines` with overscan 1.
- **Frozen columns** are the first `f` declared columns, each with width `wf`. They are always realised. The scrolling columns are windowed over the band `[x + Σwf, x + viewport)`, intersected with `f..<C`.

**The cold frame.** When the viewport is 0 (the table's first frame), the plan realises rows `0..<min(32, N)` and columns `0..<min(16, C)`. It never realises everything, unlike `List`'s `MP-I`. The next frame realises exactly the window (`LZ-T`'s rule).

### 3.4 The planner (`TBL-I`)

`TableWindowPlanner.plan(...)` runs in `TableBody.requestLayout` and reads two contexts:

- `pass.scrollContext`: the primary axis is vertical (`XS-A`);
- `pass.scrollContext?.along(.horizontal)`: the cross slot (`XS-H`).

It returns a `TableWindowPlan`:

```swift
struct TableWindowPlan: Equatable {
  var mode: LazyPlanMode                    // .bounded or .cold (never .unbounded: the table owns its scroller)
  var rows: Range<Int>
  var columns: Range<Int>                   // display positions, excluding frozen ones
  var frozen: Range<Int>                    // 0..<f
  var offset: (x: Double, y: Double)        // the raw context offsets clamped into the content
  var viewport: (width: Double, height: Double)
  var widthsDigest: TableWidthsDigest       // count + totalWidth + frozenWidth, so a width change counts as stale
}
```

**The clamped offset feeds both the window and the pins (`TBL-E`, the main correctness rule).**

- The scroller's layout offset is raw: wheel events bank past the ends until prepaint clamps them (`XS-E`).
- The table knows its content extents exactly, so it clamps the raw offset itself before it places anything.
- The header goes at content `y = offset.y`. A frozen cell goes at content `x = offset.x + Σwf(before it)`.
- So a wheel past either end never moves the header or the frozen column for a frame.

**Staleness (the `DD-F` item 3 analogue).**

- In prepaint, `TableWindowPlanner.fresh(...)` recomputes the plan from `pass.frame.activeScrollerFrame` and `.along(.horizontal)`, which hold the resolved offsets and this frame's viewport.
- If the fresh rows, columns or `widthsDigest` are not contained in the built plan, or the build was cold and the viewport is now known, prepaint calls `requestAnotherFrame()` once.
- If the pinned positions differ, that also counts as not contained.
- A settled table asks for nothing.

### 3.5 Layouts (internal `ProposalLayout`s; not `Hashable`, so they taint exactly their ancestors as `LZ-F` does)

**`TableBodyLayout`.**

- At any proposal it answers `(max(Σw, viewportWidth), header + N × rowHeight)`.
- It places row `i` at `(0, header + (rows.lower + i) × rowHeight)`, proposed `(rowWidth, rowHeight)`.
- It places the header at `(0, offset.y)`, proposed `(rowWidth, header)`.

**`TableRowLayout`** places cell `j` of a row:

- a scrolling column at `x = index.offset(of: col)`;
- a frozen column at `x = offset.x + Σwf(before)`.

Each cell is proposed `(width(col), rowHeight)`. The header row uses the same layout at the header's height.

**`Table` at a nil proposal** answers the arm G3 value. If that arm is unmeasured, it answers `K6`'s rule for `List`: the proposal, else 0. A table inside a vertical `ScrollView` therefore needs a frame, and never realises every row.

### 3.6 Cells (`TBL-K`)

`TableCellBox<Content>` is an internal `Element`, not a `Box`. It therefore mints no `$anim` slot, and a scrolled frame creates no state entries.

- Its content is proposed `(width − 2 × TableMetrics.cellInset, rowHeight)`, with `cellInset` = 6 (arm G1).
- It is aligned by the column's `TableColumnAlignment`: `.automatic` and `.leading` go leading, `.numeric` goes trailing.
- It clips to its bounds in paint (`PaintPass.clipped(to:)`).
- **Truncation.** `TableBody` pushes `lineLimit = 1` and `truncationMode = .tail` once, around all rows. That is one environment push, not an `EnvironmentScope` per cell. A long `Text` truncates with an ellipsis (arm T1).
- **Frozen cells** paint the row's current background (alternating or selected) under their content, so they are opaque over the scrolled cells.
- **Erasure.** Columns erase into `AnyTableColumn<RowValue>`, whose `makeCell(RowValue) -> AnyTableCell` works like `AnyElement`'s forwarding. It holds the cell's phase states, so no extra element sits between the row and its cell.

### 3.7 Order: paint, prepaint, hit testing and accessibility

**Within a row:** scrolling cells first, then frozen cells.

**Within the body:** rows, then the header, then the frozen header cells and the dividers. Prepaint uses the same order, so the hitboxes of the pinned parts rank on top. The header row registers an opaque background hitbox so clicks never fall through to rows under it.

**Accessibility order is logical, not paint order.** `AccessibilityTreeBuilder` orders a data table's children header row first, then rows by row index. It orders a row's cells by column index, a stable sort of a window-sized list.

### 3.8 The look (`TBL-V`; the constants live in `TableMetrics` and come from arm G1)

- **Header:** 28 points high, with a 1-point `.separator` between header cells and under the header. Its background is the window background.
- **Sort indicator:** a chevron (`chevron.up` or `chevron.down`, bundled art off Apple, `SYM-I`) on the column of `sortOrder.first`.
- **Rows:** alternating backgrounds if G2 shows them. The selected row is filled with `tint ?? .accent`, painted directly with no `$anim`, as SwiftUI's highlight is not animated.

## 4. Identity, state, retained subtrees, cost

### 4.1 State (`TBL-L`)

**`Table.@State var columnState: TableColumnState`** holds:

- `widths: [TableColumnKey: Double]`, the user overrides;
- `order: [TableColumnKey]`, the user's order of the non-frozen columns;
- `resize: TableResizeDrag?` and `reorder: TableReorderDrag?`.

It is written only by the divider and header drag handlers.

**`TableViewState`** sits at the body id, is written through `withState(…, unchanged: TableViewState.sameEntry)` (`RW-I`) and never through `write`. It holds:

- `lead` and `anchor` (`AnyHashable`);
- `positions: TableRowPositionCache`, a class compared by identity;
- `lastPlan`.

Because the `unchanged:` comparator is exact, a settled table taints nothing. It stays eligible inside an ancestor's retained subtree, as "a `List` whose window did not move" already is.

### 4.2 Replay

- A scroll frame makes the scroller ineligible (existing rule). Rows and cells are rebuilt.
- A caller's `.equatable()` cell content replays translated on a scroll step (`RetainedTranslation`, K2), and so do pinned header and frozen-cell contents.
- `Table` inserts no `.equatable()` boundary of its own in v1. Per-row retention for `Value: Equatable` is carried to v2.
- Shaping-cache hits make revisited text cheap.

### 4.3 Work counters (`TBL-M`)

They are counted, never timed. `Frame.tableWork` exposes these public `FrameWork` fields (class M):

- `tableRowsRealized`
- `tableCellsRealized` (frozen ones included, header cells excluded)
- `tableColumnsResolved` (specs resolved per build)
- `tableDataReads` (calls the table made to `data[i]`)
- `tableColdFrames`

### 4.4 Cost targets

**Fixture `F`:**

- an 800 × 600 harness window; `.tableRowHeight(24)`; every column `.width(100)`; `Text` cells; `TableMetrics.headerHeight` = 28;
- scrolled to `(x 600, y 12000)`;
- the row viewport is 600 − 28 = 572, giving rows 498..<526 (R = 28);
- columns 5..<15 (Cw = 10).

**The formulas.**

- `B`, `P` = the requests and paints of an empty table (0 rows, 0 columns), measured once and pinned.
- `h`, `ph` = per header cell: cell, label `Text` and divider, so 3 requests.
- `c`, `pc` = per body cell: cell box and `Text`, so 2 requests.

| frame | builds | elementRequests | elementPaints | rows / cells / dataReads |
|---|---|---|---|---|
| steady (`setNeedsRedraw(); tick()`) | 1 | `B + 1 + 3·Cw + R·(1 + 2·Cw)` = **B + 619** (header row 1, header cells 30, rows 28 × 21) | `P + (same shape)`, pinned as a literal | 28 / 280 / 28 |
| vertical scroll step (+24) | 1 | = steady | = steady | 28 / 280 / 28 |
| horizontal scroll step (+100) | 1 | = steady | = steady | 28 / 280 / 28 |
| resize drag step (+5 on column 6) | 1 | = steady | = steady | 28 / 280 / 28; `tableColumnsResolved` = C |
| idle | 0 (no frame) | 0 | 0 | 0 |
| first frame (cold), then one follow-up | 1 + 1 | | | cold: 32 / 32·16 / 32 |
| frozen 1, same offsets | 1 | `B + 1 + 3·11 + 28·(1 + 2·11)` = B + 678 | | 28 / 308 / 28 |
| `.equatable()` cell content, vertical step | 1 | = steady | steady − 270·(paints per cell content) | `retainedTranslated` = 270 (27 surviving rows × 10) |
| window with no table | unchanged literals (section 6) | | | 0 |

**Identical at every size:** 1k × 20, 10k × 50 and 1M × 200 give the same numbers at the same offsets.

**Data access:** one `data.count` per build, and one `data[i]` per realised row per build. Input paths read O(1) rows, except a ⇧ range, which reads O(range).

## 5. Input

### 5.1 Selection (`TBL-N`)

**Clicks.** These follow `ListSelectionController` (`DD-Z`):

- a click selects the row and focuses the table;
- `Modifiers.primary`-click (⌘, Ctrl off Apple) toggles in a multi-selection table;
- ⇧-click selects the range from the anchor;
- a single-selection table ignores the modifiers.

**Positions without scans.** The position-free calls are fed by a `TableRowPositionCache`, an LRU of 8 entries mapping `AnyHashable` to `Int`:

- A row click seeds its own position.
- `space.index(id)` checks the cached position by verifying `data[p].id == id` (one read). Then it tries `tableRowIndex`. Only after both fail does it scan, which is `List`'s documented O(n).
- A new hook, `ListRowSpace.firstSelected: (@MainActor () -> Int?)?`, defaults to nil, so `List` is unchanged. The table answers nil for an empty selection without reading, and with a lookup it answers the minimum of `lookup(selected)`.
- Positions go stale after a sort or a data change and are re-verified before use. The selection is by id, so it follows its rows.

**Accessibility selection.** `AccessibilityRowSelection` maps only the realised rows, O(window).

### 5.2 Keys (`TBL-O`)

| key | effect |
|---|---|
| ↑ ↓, with ⇧ | `ControlKeys.listMove`, as `List` (KY6, KY8) |
| Page Up, Page Down, Home, End | scroll only, selection unchanged (`ControlKeys.tableScroll`; AppKit `NSTableView`, arm K3; if K3 shows they move the selection, they move the lead instead and ⇧ extends) |
| ← → | declined (arm K4) |
| Return | `primaryAction(selection)` (`OG-N`) |
| ⌘A | not handled (`KY8c`'s `List` rule; arm K7) |
| type-select | none (arm K6; divergence 1109 if SwiftUI type-selects) |

**Reveal.** After a key move, a `ScrollRequest(scope: scrollerID, key: TableLeadReveal(body:, position:), anchor: nil)` is resolved by the body by position, with no scan. The target rect is:

- **x:** the current visible band, `[offset.x, offset.x + viewportW)`, so the horizontal position never jumps;
- **y:** `rowTop − header` with height `rowHeight + header`, so the row lands below the pinned header.

Page Up and Page Down target row `top ± rowsPerPage` with anchor `.top`. Home and End target rows 0 and N−1.

A caller's `ScrollViewReader.scrollTo(rowID)` is resolved through `tableRowIndex`; without it, the table scans (documented).

### 5.3 Pointer (`TBL-P`, `TBL-Q`, `TBL-R`, `TBL-S`)

**Double-click** runs the primary action (`OG-N`). A row child's `.onTapGesture(count: 2)` must not swallow the selection click, which is the G39 fix inherited from the row-click path.

**A header cell carries one `DragGesture(minimumDistance: 0)`.**

- If the drag ends with `|translation| < TableMetrics.reorderThreshold` (3 points), it is a sort click.
- **Sort click.** Let `p` be the column's prototype comparator. If `sortOrder.first`, compared ignoring `order`, is `p`, its `order` flips. Otherwise every entry equal to `p` (ignoring `order`) is removed and `p` is inserted at index 0 (arms S1–S4).
- The binding is written once. A table without a `sortOrder` binding, or a `Never` column, does not sort. The table never sorts the data; the app does, as in SwiftUI.
- **Reorder.** The dragged header cell paints at the pointer offset; that offset is a `@State` write, so 1 build per step (`FP-U`: a write redraws). When the pointer crosses a neighbour's midpoint, the order is written.
- Frozen columns cannot be dragged, and nothing can be dropped among them. Reorder is on by default if arm R1 shows SwiftUI allows it; otherwise it is off, with no MetalUI switch in v1.

**Divider (`TableColumnDivider`).** It is a 6-point hit area centred on the column's trailing edge, modelled on `SplitDividerHitArea` (`HS-K`). It shows the `.columnResize` pointer.

- A drag writes `columnState.widths[key] = clamp(start + dx, min, max)`, and only when the value changes. A drag that does not move writes nothing and draws nothing (`FP-U`).
- A fixed-width column has no divider (arm R3).
- Drag-end prunes overrides whose key is gone.

## 6. A window with no table (the steady-frame rule)

Two literals are measured on master before PR A and stay unchanged afterwards:

- `PointerDragFrameCostTests` R5's steady `elementRequests` (6);
- a `List` of 40 rows at `rowHeight` 28 in a 300-point `ScrollView`.

Every new `FrameWork` field is 0 in a window with no table.

## 7. Accessibility (`TBL-T`)

### 7.1 Platform tree (`MetalUIPlatform`, public, class M)

- `AccessibilityRole.columnHeader`
- `AccessibilityNode.columnCount: Int?`. When it is non-nil on a `.table` node, that node is a data table, not a `List`.
- `columnIndex: Int?`
- `headerRowCount: Int?`
- `sortDirection: AccessibilitySortDirection?`, where `public enum AccessibilitySortDirection { case ascending, descending }`.
- Cells reuse `.cell`, with `rowIndex` and `columnIndex`.

### 7.2 `MetalUI` (internal)

- `AXRoleHint` gains `.dataTable`, `.tableRow`, `.tableCell` and `.columnHeader`.
- `AXNode` gains internal `columnCount`, `columnIndex` and `sortDirection`. They are stripped before the `isEmpty` gate, as `logicalIndex` is (`AB-L`).

### 7.3 Publishing

- The table node carries `rowCount = N`, `columnCount = C` and `headerRowCount` (1 if headers are visible).
- Each realised row carries `rowIndex = position`. Each realised cell carries `rowIndex` and its logical `columnIndex`. Header cells carry `columnIndex` and the sort direction of `sortOrder.first`.
- A cold frame publishes the table and no rows, and calls `requestAccessibilityRetry()` (`AB-X` rule 1).

### 7.4 AppKit (`MetalUIAppKit`)

**Roles.** A data table is `.table` (a `List` stays `.outline`). Its rows are `.row` with subrole `.tableRow`, its cells `.cell`, and its header cells `.button` with subrole `AXSortButton` when sortable (arm A1).

**Attributes:**

- `accessibilityRowCount`, `accessibilityColumnCount`;
- `accessibilityRows` and `accessibilityVisibleRows` (the realised rows), `accessibilitySelectedRows`;
- `accessibilityHeader`, the header group;
- `accessibilityColumnHeaderUIElements`;
- `accessibilityIndex` on rows;
- `accessibilityRowIndexRange` and `accessibilityColumnIndexRange` on cells;
- `accessibilitySortDirection` on header cells.

There are no `AXColumn` elements (divergence 1107).

### 7.5 AccessKit (SDL)

- The table is `TABLE`, with `row_count = N + headerRowCount` and `column_count = C`.
- The header row is `ROW` with `row_index 0`. Its cells are `COLUMN_HEADER` with `column_index` and `sort_direction`.
- A data row is `ROW` with `row_index = position + headerRowCount`. Its cells are `CELL` with `row_index` and `column_index`.

### 7.6 Human checks

The new group TBL is added to `docs/verification/human-checks.md`:

- **VoiceOver:** it announces "table, N rows, M columns", reads a cell with its column header, sorts by pressing a header, and announces selection.
- **Orca and Narrator:** the same checks.
- **Scrolling and pointer feel:** sticky header, frozen column, resize and reorder.

## 8. Platforms

Nothing in the core is Darwin-only. Text uses the portable text system in tests (harness Noto Sans). The pointer styles already map on SDL (`PH-A`). The Foundation sorting types are guarded in CI on Linux and Windows (task B0). The AppKit mapping lives in `MetalUIAppKit`, the AccessKit mapping in `Backends/SDL`.

## 9. Bookkeeping

**Prefix `TBL-`.** The decisions doc is `docs/superpowers/2026-11-18-table-decisions.md`, and the next unused id is `TBL-X`. Add a row to `docs/rules/decision-prefixes.md`; the prefix is distinct from `TB-` (tombstones) and `TBS-`.

**Rulings `TBL-A`..`TBL-W`:**

| id | ruling |
|---|---|
| A | recommendation and scope |
| B | types, builder, column keys, `TableColumnForEach` |
| C | Foundation portability |
| D | the row-source contract, `tableRowIndex` |
| E | the internal scroller, pins from the clamped offset, indicator margin |
| F | uniform rows (1105) |
| G | widths and fill (1106) |
| H | the column index and window |
| I | the row window, the planner, staleness |
| J | identity and windowed parents |
| K | cells, truncation, alignment |
| L | state, `RW-I`, replay |
| M | counters and cost |
| N | selection |
| O | keys (1109) |
| P | context menu and double-click |
| Q | sorting |
| R | resize (1111) |
| S | reorder |
| T | accessibility (1107, amends 32) |
| U | not offered |
| V | look, demo, human checks |
| W | RTL (1108) |

**Divergence labels.** In `docs/rules/divergence-labels.md`, record "1105–1114 reserved by TBL". The live count rises with each label used; `CLAUDE.md`'s next label stays 243.

**Records.** The latest is 387. Each PR appends one record, taking the next free number at its merge (388–392 at planning time) and adding one row to `docs/record/README.md`.

**Probe.** `docs/probes/swiftui-table.swift`, plus a recorded `.txt`. Its arms are:

| arms | covers |
|---|---|
| G1 G2 G3 | metrics, alternating rows, nil proposal |
| W1 W2 W3 W4 | default width, fill, shrink, default min |
| T1 T2 | truncation, tall content |
| S1–S4 | sort clicks |
| K1–K7 | keys |
| R1 R2 R3 | reorder default, resize compensation, fixed width |
| A1 A2 | AX roles and attributes, AX under scrolling |
| L1 | RTL |
| F1 | `TableColumnForEach` count change |

**Demo.** `METALUI_TABLE_DEMO=1 swift run MetalUIDemo` shows 1 000 000 × 200 synthetic rows with a frozen "#" column, sortable columns, a `Set` selection, a context menu and `tableRowIndex { $0 }`.

**Opt-in test.**

```
METALUI_RUN_1M_TABLE_TEST=1 swift test --filter aTablesWorkIsTheSameFor1MBy200AsFor1kBy20
```

**Paged sources: the contract for Sift.** `Data` is any `RandomAccessCollection` whose `count` and `subscript(position)` are O(1). The table reads only realised positions. Sift's element should be a cheap handle, `RowRef { ordinal, source }`, with `id = ordinal` and the cell values fetched from the page cache. Then `tableRowIndex { $0 }` makes every id lookup O(1).

---

