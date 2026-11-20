# 390: Table PR C, selection, keys, context menu and sorting (`TBL-N`..`TBL-Q`, `TBL-Y`, `TBL-Z`)

Class `A` (SwiftUI's `Table` input), divergence 1109 used (no type-select). Branch `feat/table-c`, base master `1f36cadc` (PR B, record 389, merged). Spec `docs/superpowers/specs/2026-11-18-table-design.md`, plan `docs/superpowers/plans/2026-11-18-table.md` (tasks C1 to C6), decisions `docs/superpowers/2026-11-18-table-decisions.md`, probe `docs/probes/swiftui-table.swift` (arms `K1`..`K7`, `S1`..`S4`, read in record 389; no new probe run).

## Change

- **Selection** (`TableSelection.swift`, `TableBody.swift`, `ListSelectionController.swift`): the table drives `ListSelectionController` over positions. `TableSelectionContext` (one per build, shared by every realised row's closures) builds the `ListRowSpace` at input time: `id(position)` is one `data[i]` read, `index(id)` is the cached position verified with one read, then `tableRowIndex` verified with one read, then a scan. `ListRowSpace` gains an optional `firstSelected` hook (nil by default: `List` unchanged) that the table answers with nil for an empty selection and the minimum of `tableRowIndex(selected)` with a lookup. `TableRowPositionCache` is an LRU of 8, seeded by a click and a key move. The lead and anchor live in `TableViewState` at the body id (written through `withState`, which fires no `onWrite`). The selected row paints the tint (else the accent) and carries `selectionHint` and `isSelectableRow` (G39: a `Text.onTapGesture(count: 2)` in a cell no longer swallows the click). The accessibility selection is registered on the body and maps only the realised rows.
- **Keys and reveal** (`ControlKeys.tableScroll`, `TableSelectionContext.keyHandler`, `TableBody.resolveScrollRequests`): Return, then ↑ ↓ (⇧ extends), then Page Up, Page Down, Home and End (scroll only). A move enqueues a `ScrollRequest` keyed by `TableLeadReveal(body, position)`; the body resolves it in prepaint, before its rows, as the row plus the header above it over the current horizontal band, so the row lands below the pinned header and the columns never jump sideways. Page keys read the last plan's offset and viewport at input time. ← → and typed characters do nothing.
- **Context menu and double click**: the existing `contextMenu(forSelectionType:menu:primaryAction:)` reaches the table through the environment. A row's menu gets the selection when the row is in it, else the row; the table's own region (registered before its scroller) gets `[]`; a click count of 2 runs `primaryAction([row])`.
- **Sorting** (`TableSort.swift`): `TableSortClick.clicked` follows `S1`..`S4`; `TableSortControl` erases the `sortOrder` binding. A sortable column's header cell is a click target that writes the binding once. The leading column shows a chevron (`chevron.down`, turned for ascending) at the trailing inset, costing its elements on that column only. The demo's selection, sort and menu now act.
- **A caller's `scrollTo(rowID)`** resolves in the body by position: `tableRowIndex` when given, else a scan counted in `tableDataReads`.
- **Rulings** `TBL-N`..`TBL-Q` built and amended, `TBL-Y` (only a table that selects or has a menu is focusable) and `TBL-Z` (a caller's scroll request) new. Divergence 1109. Docs: `docs/divergences.md` (233 live), `docs/rules/input-focus.md`, `docs/rules/divergence-labels.md`, `docs/rules/decision-prefixes.md`, `docs/api-overview.md`, the inventory map (families `table-selection` and `table-sort`, claiming the selection and sort initialisers).

## Measured (macOS, debug build, the harness text system)

- A click at the steady offsets of a 1 000 000 x 200 table is builds x (28 rows, 280 cells) with at most 4 reads beyond the window's 28 per build; the steady frame afterwards (a selected row) costs the unselected window's requests (621). A ↓ key is the same.
- A ⇧-click from row 999 000 to 999 010 reads **13** rows during the input (the 11 of the range plus one verification each of the clicked row and the anchor; the plan counted 12) and selects 11. Without the position cache it scans about 1 000 000.
- ↓ with nothing selected reads 2 rows (the `firstSelected` hook); without the hook the controller scans every row.
- End on a 1 000 000-row table reads the new window only; `scrollTo(900_000)` with `tableRowIndex` reads the window only and without one `scrollTo(9_999)` over 10 000 rows reads at least 10 000.
- A sort click is one write and builds the window (28 rows, 280 cells, 28 reads per build); an idle selected table draws no frame.
- Counts: root 7141 tests in 79 suites (+29), see CLAUDE.md.

## Tests

`TableSelectionTests` (7), `TableKeyboardTests` (13), `TableSortTests` (5), `TableFrameCostTests` (+4). Every new test names its mutation in its doc comment; the round below (each restored after its run, `git status` clean of source changes):

| test | mutation | red |
|---|---|---|
| `aClickSelectsTheRowAndFocusesTheTable` | the controller's `ClickDispatch.focusRequest` line removed | itself |
| `aPrimaryClickTogglesAndAShiftClickSelectsTheRange` | the anchor kept from the first click (`stored.anchor ?? anchor`) | itself |
| `aShiftClickAcrossAMillionRowsReadsOnlyTheRange` | the position cache's lookup dropped from `index` | itself (a scan) |
| `aKeyMoveWithNothingSelectedReadsOneRow` | the `firstSelected` hook ignored by `leadIndex` | itself (a scan) |
| `aRowChildsDoubleTapDoesNotSwallowTheSelectionClick` | `isSelectableRow` not set on the row | itself |
| `anAccessibilitySelectionNamesOnlyRealisedRows` | `byRow` built over every row of the data | itself |
| `theSelectionFollowsItsIDAcrossASort` | the cached position trusted without verifying | itself |
| `arrowKeysMoveTheLeadAndRevealItBelowTheHeader` | the reveal rect's x from 0 (no horizontal band) | itself |
| `anUpwardRevealClearsTheHeader` | the header left out of the reveal rect | itself |
| `pageDownScrollsByAPageWithoutChangingTheSelection` | Page Down also moves the lead | itself |
| `homeAndEndScrollToTheEnds` | End targets row 0 | itself |
| `leftAndRightArrowsAreDeclined` | ← mapped to Home | itself |
| `returnRunsThePrimaryActionOnTheSelection` | Return given an empty selection | itself |
| `aDoubleClickRunsThePrimaryActionWithItsRow` | the primary-action click wrapper dropped | itself |
| `aKeyRevealOfADistantRowResolvesWithoutAScan` | the reveal scans the data | itself |
| `aRowsContextMenuGetsTheSelectionOrItsRow` | the row's menu always gets `[row]` | itself |
| `emptySpaceGetsTheEmptySet` | no table-level attachment | itself |
| `aFirstClickSortsByTheColumn` | the insert returns `[]` | itself |
| `aSecondClickReversesIt` | entries compared including `order` | itself |
| `anotherColumnGoesFirstAndAnExistingEntryKeepsItsOrder` | the new entry appended, not inserted | itself |
| `aHeaderClickWritesTheSortOrderOnce` | a second write per click | itself |
| `aColumnWithoutAComparatorIgnoresHeaderClicks` | every column given a click | itself |
| `scrollToARowIDUsesTheRowIndexLookup` | the lookup ignored | itself (a scan) |
| `aSelectionChangeRealisesOnlyTheVisibleWindow` | 5 000 rows read in layout when the table selects | itself |
| `aKeyMoveRealisesOnlyTheVisibleWindow` | the same | itself |
| `aSortRealisesOnlyTheVisibleWindow` | the same, for a table with a sort | itself |
| `anIdleSelectedTableAsksNoFrames` | `requestAnotherFrame()` when the body is focusable | itself (`notIdle`) |

Not mutated: `scrollToWithoutALookupScans` (it pins the documented cost, the opposite of the lookup test's mutation) and `typingDoesNotSelectARow` (divergence 1109: there is no type-select to remove). Guards: the whole of `ListSelectionTests` and the other `List` selection suites stay green (`firstSelected` is nil for a list), and `aWindowWithoutATableKeepsItsSteadyRequests` keeps R5's 6 and the `List` literal 28.

## Deviations from the plan

- **The position cache is seeded by a click and a key move, not at build.** The plan noted every realised row at build (`cache.note(row, position)`), but a window is 28 rows and the cache holds 8.
- **A ⇧-click reads 13 rows, not 12**: the cache verifies both the clicked row and the anchor.
- **A header cell is a click target, not a `DragGesture(minimumDistance: 0)`** (`TBL-Q`): headers do not reorder by default (`TBL-S`, arm `R1`), so there is no drag to tell a click from.
- **`firstSelected` scans only for a non-empty selection with neither a lookup nor a stored lead**; with a lookup it is the minimum of the lookups.
- **The sort rule is the probe's** (`S4`: an existing entry moves to the front keeping its order), not the spec's "remove every equal entry and insert the prototype".
- **`TBL-Y`: a table with no selection and no menu is not focusable** (the plan did not say), so no existing table's focus order moves.
- **The selection-change cost test is "builds x the window"**, not a single build: a click in the harness draws the write's frame and may draw a follow-up.
- **The "chevron present" test counts header-band glyphs and images** (the symbol is an image on macOS and a path glyph off it) rather than naming a glyph.
- The divergences count in `docs/divergences.md` and `CLAUDE.md` was 232 after the SecureField merge (1115 to 1117), 233 with 1109.
