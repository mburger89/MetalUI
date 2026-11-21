# Design: `Table` cell mode (prefix `TCM-`, Table PR F)

2026-11-20, master `1f36cadc` (Table PR B merged; PR C, selection, keys and sorting, in flight). Requesters:

- **Alloy (developer-af):** a CSV table editor. It checks the values an agent produced and fixes wrong ones in place. Alloy keeps the data, the parsing and the undo. A commit becomes a minimal text replacement on the open document.
- **Sift:** edit mode (phase 7) and keyboard browsing of a result grid.

This document is both the spec and the decisions document for `TCM-`. **Built in PR F (record 394, 2026-11-20): `TCM-A`..`TCM-K` stand as written except where "As built" at the end of the spec half records a deviation. Next unused id `TCM-L`.**

## 0. Scope (`TCM-A`)

SwiftUI's `Table` has no cell cursor, no cell keyboard navigation and no inline editor (its editable cells are `TextField`s the caller puts in a column). Cell mode is therefore **MetalUI-only API, class M**. It needs no divergence label, and SwiftUI behaviour is unchanged whenever cell mode is off.

Cell mode is switched on by attaching a cell binding. A table without one behaves exactly as PRs B–E define it, and its frame work and `elementRequests` are pinned unchanged.

Not in PR F:

- a rectangular range: a follow-up if asked for;
- range copy and paste;
- variable row height;
- cell accessibility: PR E adds the cell nodes, and it consumes `TCM-` state.

## 1. Public API (`TCM-B`)

```swift
/// A cell of a table: a row id and a column's declared index.
public struct TableCell<RowID: Hashable>: Hashable {
  public var row: RowID
  public var column: Int
  public init(row: RowID, column: Int)
}

extension Table {
  /// Cell mode: the active cell, as a binding.
  public func tableActiveCell(_ cell: Binding<TableCell<Value.ID>?>) -> Self

  /// Makes cells editable.
  /// - `text` supplies the editor's initial text: the raw value, never the displayed content.
  /// - `isEditable` defaults to every cell.
  /// - `editing` is the cell being edited. Setting it to `nil` from outside cancels the edit; setting it to a cell starts one.
  /// - `onCommit` receives the edited text. The caller writes it.
  public func tableCellEditing(
      _ editing: Binding<TableCell<Value.ID>?>,
      text: @escaping @MainActor (TableCell<Value.ID>) -> String,
      isEditable: @escaping @MainActor (TableCell<Value.ID>) -> Bool = { _ in true },
      onCommit: @escaping @MainActor (TableCell<Value.ID>, String) -> Void) -> Self

  /// A fill for the whole cell box, not the content inset. `nil` means no fill.
  public func tableCellBackground(_ fill: @escaping @MainActor (TableCell<Value.ID>) -> Color?) -> Self
}
```

All three are written directly on the `Table`, as the other `table…` modifiers are (`HS-G`). Each new public declaration owes a doc comment and an inventory row (class M).

**The column coordinate is the column's declared index** (`TCM-C`): its position in the flattened declaration, counting static columns and `TableColumnForEach` elements alike. It is not the display position, so it is stable when the user reorders columns (PR D).

- A `TableColumnForEach(0..<n)` table's column index equals the element's id. That is Alloy's and Sift's case.
- A caller that inserts or removes columns owns remapping its stored cells; an index past the last column is clamped.
- (Considered and rejected: the internal `TableColumnKey`, which is a slot path and not meaningful to a caller; and an `AnyHashable` column id, which makes static columns awkward.)

**Edit lifecycle is visible to the caller through `editing`** (Alloy's ask, `TCM-H`):

- MetalUI writes `editing` to the cell when an edit begins and to `nil` when it ends (commit or cancel).
- The caller can snapshot its document revision on the begin write, and rebase or reject in `onCommit`.
- A write of `nil` by the caller **cancels** the edit: there is no `onCommit`, and the typed text is discarded. This is the programmatic cancel, for example when the row is deleted.
- A write of a cell by the caller begins an edit there, reveals the cell and makes it the active cell.

## 2. The active cell (`TCM-D`)

**Selecting cells**
- A click on a cell sets the active cell to it, focuses the table, and selects its row through PR C's `rowClick`, so a row selection binding still works.
- ⇧-click and `Modifiers.primary`-click act on the row selection exactly as TBL-N says, and the active cell moves to the clicked cell.
- A click in empty space below the last row leaves the active cell unchanged.

**Drawing the active cell**
- A focused table draws a ring **inside** the cell box: 2 pt, accent colour, above the content.
- An unfocused table draws it 1 pt in the secondary label colour, as a dimmed selection.
- Frozen cells draw their ring above the scrolled cells.

**The row highlight in cell mode**
- In cell mode, a selected row uses the unemphasised selection fill: the secondary selection colour, as an unfocused `List` row.
- It is never the accent fill, so `tableCellBackground` tints stay readable on selected rows.

**Paint order inside a cell box**
1. the row background (stripe or selection);
2. `tableCellBackground`;
3. the cell content;
4. the active ring.

**Write behaviour**
- The binding is written once per move.
- A move to the same cell writes nothing (`withState(…, unchanged:)` discipline, as TBL-L).
- The active cell is never pruned when the data changes. A cell whose row id no longer resolves draws no ring, and the next key move starts from the first row (TBL-N's empty-lead rule).

## 3. Keys (`TCM-E`)

Cell mode composes **before** PR C's row keys. Keys it does not handle fall through to C's `composeTableKeys`.

Not editing:

| key | effect |
|---|---|
| ← → | move one column, stopping at the edges (consumed at the edge, no wrap) |
| ↑ ↓ | move one row; ⇧ extends the **row selection** as TBL-O, and the active cell follows the lead |
| Tab / ⇧Tab | move one column right or left, wrapping to the next or previous row's first or last column; consumed at the very ends |
| Return | begin editing if the cell is editable; otherwise PR C's Return (`primaryAction(selection)`) |
| ⇧Return | move one row up |
| F2 | begin editing (the Windows and Linux convention) |
| Home / End | first or last column of the row |
| `Modifiers.primary` + ← → | first or last column |
| `Modifiers.primary` + ↑ ↓ | first or last row |
| Page Up / Page Down | move the active cell by `rowsPerPage` (amends TBL-O's scroll-only rule, in cell mode only) |
| a printable character with no `primary` or control modifier | begin editing, with the editor text **replaced** by that character |
| Escape | nothing (falls through) |

Editing (the editor has focus):

| key | effect |
|---|---|
| Return | commit, then move down one row |
| ⇧Return | commit, then move up |
| Tab / ⇧Tab | commit, then move right or left (with the same wrapping) |
| Escape | cancel and keep the active cell |
| ⌥Return | inserts a line break into the text (the spreadsheet convention) |
| every other key | the editor's own (`TextField` editing) |

**Revealing the active cell:** every move reveals the new cell on both axes. It clears the header and the frozen columns, uses no scan, and resolves by position. TBL-O's reveal is extended with a horizontal band from the column's offset.

There is no type-select in cell mode: a printable key begins an edit. Divergence 1109 still covers row mode.

## 4. The editor (`TCM-F`, `TCM-G`)

**What the editor is**
- It is an internal `TextField(axis: .vertical)` with `.lineLimit(1...6)`.
- **It is owned by `TableBody`, not by the cell.** It has its own stable identity under the body id, so cell recycling never touches it.
- It is laid out over the cell's box, positioned by position:
  - y = position × rowHeight;
  - x = the column's offset;
  - width = max(column width, 120 pt);
  - it grows downward over the following rows as lines are added.
- It draws above the cells and below the header. A frozen column's editor also draws above the scrolled cells.

**Starting an edit**
- The initial text comes from `text(cell)`, and the caret goes at the end.
- When a printable key starts the edit, the text is that character.
- `editing` is written with the cell (`TCM-H`).

**Commit**
- `onCommit(cell, text)` is called exactly once per edit, then `editing` is written `nil`.
- It runs on Return, Tab, a click on another cell or in empty space, focus leaving the table, the table leaving the hierarchy, or its window closing. The window resigning key does **not** commit; the edit waits.
- It is called even when the text is unchanged. The caller decides whether that is a no-op.

**Cancel**
- Escape, or the caller writing `editing = nil`.
- No callback, and the typed text is discarded.

**Scrolling out (Alloy's "no text lost") (`TCM-G`)**
- The editor **survives** the cell scrolling out of the window. It is the body's, so the window planner's recycling does not reach it.
- It keeps keyboard focus.
- The next keystroke into it reveals the cell again, as a focused `TextField` in a `ScrollView` does.
- While the cell is off-screen, the editor is clipped by the viewport like any content.

**Data changing under the edit**
- If the edited row id no longer resolves, the editor stays open: the caller owns that case and can cancel with `editing = nil`.
- Resolving means the position cache verified by one read, then `tableRowIndex`, then one scan. This is TBL-N's ladder; with no `tableRowIndex`, the scan is the documented cost.
- While unresolved, the editor holds its last frame.

**Line breaks**
- A value with line breaks shows them in the editor, up to six lines, then scrolls.
- The cell itself still draws one line (TBL-K, divergence 1105).

**What the editor is not**
- It is not `SecureField`.
- It has no autocomplete and no formatter: the text in is the text out.

## 5. Cell background (`TCM-I`)

- **When `fill` runs:** while a cell's box is built, so only for realised cells, and in the same invalidation as the cell content.
  - The caller's own data change reaches it the way it reaches cell content: Observation, or the table being rebuilt.
  - An idle table calls it zero times.
  - A scroll step calls it only for the newly realised cells.
- **What it fills:** the whole cell box, including the inset and under frozen-cell opacity.
- **When it is `nil`:** no fill and no paint op.

## 6. Scroll to a cell (`TCM-J`)

**`ScrollViewReader.scrollTo(TableCell(row:column:), anchor:)`** on a cell-mode table reveals that cell on both axes. The row is found with `tableRowIndex`; with no lookup, by one documented scan, as PR C's C5. This is Alloy's "jump to the cell an agent changed".

- **The active cell:** it does not change. The caller sets it if it wants to.
- **A plain row id:** it keeps PR C's behaviour.

## 7. Cost (`TCM-K`)

Pinned, each with a failing mutation:

1. **No cell mode:** a `Table` without `tableActiveCell` has its `elementRequests`, `tableCellsRealized` and frame work identical to PR C's. A window with no table is unchanged.
2. **Moving the active cell:** the move rebuilds no rows. Two cells repaint (the old ring and the new one) with zero `tableCellsRealized`, unless the move scrolls.
3. **Idle:**
   - a focused cell-mode table asks no frames;
   - an idle editor costs what an idle `TextField` costs (only the caret blink);
   - `fill` is called zero times.
4. **Moving across a million rows:** `primary`+↓ on 1 M rows reads ≤ 30 rows (the new window).
5. **Typing in the editor:** keystrokes rebuild only the editor. `tableCellsRealized` is 0 per keystroke.

## 8. Accessibility (handed to PR E)

PR E builds the cell nodes:

- the active cell is reported as the focused cell;
- the editor is a text field child of that cell;
- with no cell mode, the row model is used, as TBL-T says.

PR F publishes nothing new to the tree, except that the editor is a normal `TextField` node.

## 9. Divergences and inventory

None. All three modifiers and `TableCell` are class M. The only SwiftUI-visible behaviour change is in cell mode, which SwiftUI does not have.

Inventory rows go in the `table-cell-mode` family.

## As built (record 394)

Where the source made a ruling impossible or the spec was silent, the build did this; each is also in the record's deviations.

- **`TCM-K` pins 2, 3 and 5 are "builds x the steady window", not "zero cells realised".** Every frame the table draws rebuilds its window (`TBL-M`), so a move or a keystroke realises the same 28 rows as an idle redraw, never more, and never anything that grows with the data. The pins count `tableRowsRealized` and `tableCellsRealized` per build.
- **`TCM-I`: `fill` runs once per realised cell per build**, not "only for the newly realised cells": the window is rebuilt whole. Idle it runs zero times; in a scroll step it runs exactly `tableCellsRealized` times.
- **`TCM-F`: the window resigning key cannot commit because `Window` has no such event.** The test pins that a pointer leaving and a modifier change commit nothing.
- **A click in the empty space commits through a viewport-sized region registered only while an edit is open**; the body is only as tall as its rows.
- **A cell registers its own click in cell mode** (the row's hitbox is untouched): the cell runs the row click (the selection, the menu's double click) after making itself active.
- **`tableCellEditing` and `tableCellBackground` do nothing without `tableActiveCell`** (cell mode is on exactly then).
- **A caller writing `editing` to another cell while an edit is open cancels the open edit** (no callback) and begins the new one.
- **Page Up and Page Down move the active cell and leave the row selection alone**; ↑ ↓ (and ⇧) use the table's row move, so the row selection follows as TBL-O says.
- **The unemphasised selection fill is `Color.secondary` at 0.25**: `List` has no unfocused fill to copy. The unfocused ring is `Color.secondary`, 1 point.
- **A table with an open edit reads one more data row per build** (the edit's row position, verified with one read).

---

# Plan (PR F, record: next free number at merge)

Build after PR C merges, on `feat/table-f`. Merge master first. Consume PR C's `TableViewState`, `composeTableKeys`, `TableLeadReveal` and the position cache, whatever their names are as built. Follow the source wherever this plan disagrees with it, and note each deviation.

**Global constraints**
- Steady-frame cost tests, as section 7.
- Every new test is shown to fail under a named mutation.
- Off-Darwin pitfalls:
  - use `runUntilIdle()`;
  - sum `frameWork`;
  - use `Modifiers.primary`.
- Never O(rows) work outside the documented scan.

### F1: `TableCell`, the modifiers, and the active-cell state

- Add `TableCell` and the three modifiers to `Sources/MetalUI/TableCellMode.swift` (new). The state lives in `TableViewState`.
- Click handling: see section 2.
- Tests (`Tests/MetalUITestingTests/TableCellModeTests.swift`):

| test | assertion | mutation |
|---|---|---|
| `aClickSetsTheActiveCellAndSelectsItsRow` | the binding is `(id 3, 2)`; the row selection is `[3]` | — |
| `aMoveWritesTheBindingOnceAndToTheSameCellNotAtAll` | one write, then zero | write unconditionally |
| `aMoveRepaintsTwoCellsAndRealisesNone` | `tableCellsRealized == 0`; the rows rebuilt == 0 | rebuild the row on a move |
| `aTableWithoutCellModeIsUnchanged` | its counters equal PR C's pinned numbers | ring paint always on |
| `anUnresolvableActiveCellDrawsNoRing` | remove the row: no ring op; ↓ goes to row 0 | — |
| `theRingIsAccentWhenFocusedAndSecondaryWhenNot` | colour and width | — |

### F2: keys and reveal

Tests (`TableCellKeyboardTests.swift`): one per row of section 3's first table. Also:

| test | assertion | mutation |
|---|---|---|
| `tabWrapsToTheNextRowsFirstColumn` | — | — |
| `arrowsStopAtTheEdgesAndAreConsumed` | — | — |
| `aCellRevealClearsHeaderAndFrozenColumns` | frame y ≥ header height; x ≥ the frozen width | reveal x from 0 |
| `primaryDownOnAMillionRowsReadsTheWindowOnly` | reads ≤ 30 | a scan |
| `keysFallThroughToRowModeWithoutCellMode` | PR C's keyboard tests pass | — |

### F3: the editor

`Tests/MetalUITestingTests/TableCellEditorTests.swift`:

| test | assertion | mutation |
|---|---|---|
| `returnBeginsEditingWithTheCallersText` | the editor text is `text(cell)`, not the displayed text; `editing` is written | use the displayed content |
| `typingACharacterReplacesTheText` | — | — |
| `returnCommitsOnceAndMovesDown` | one `onCommit`, then `editing == nil` and active is `(row+1, col)` | commit twice |
| `tabCommitsAndMovesRight` | — | — |
| `escapeCancelsWithNoCallback` | — | — |
| `aCallerNilCancels` | no callback; the editor is gone | — |
| `aCallerCellBeginsAnEditAndRevealsIt` | — | — |
| `aClickElsewhereCommits` | — | — |
| `focusLeavingTheTableCommitsButResigningKeyDoesNot` | — | — |
| `theEditorSurvivesScrollingItsCellOut` | scroll 5 000 rows away and back: the text is intact, focus is kept, and one commit with the typed text | key the editor by the window slot |
| `aKeystrokeIntoAnOffscreenEditorRevealsIt` | — | — |
| `optionReturnInsertsALineBreak` | — | — |
| `typingRebuildsOnlyTheEditor` | `tableCellsRealized == 0` per keystroke | — |
| `anIdleEditorCostsAnIdleTextField` | — | — |

### F4: cell background and scroll-to-cell

| test | assertion | mutation |
|---|---|---|
| `aCellBackgroundFillsTheWholeBox` | the fill rect equals the cell box, not the inset | the inset rect |
| `theFillIsCalledOnlyForRealisedCellsAndNeverWhenIdle` | the call counts: idle 0, one scroll step equals the newly realised count | call it in paint |
| `aTintStaysVisibleOnASelectedRow` | — | — |
| `scrollToACellRevealsBothAxes` | 1 M rows × 200 columns, `scrollTo(TableCell(row: 900_000, column: 150))`: reads ≤ 30, cell visible | ignore the column |
| `scrollToACellLeavesTheActiveCell` | — | — |

### F5: demo and docs

- **Demo:** `METALUI_TABLE_DEMO`, or the existing table demo, gains a cell-mode editable CSV-like sheet.
- **Record and docs:**
  - the record;
  - a `docs/rules/` sentence (input-focus);
  - api-overview bullets;
  - inventory rows (M);
  - this document's rulings marked built;
  - the `TCM-` row in `docs/rules/decision-prefixes.md` (next `TCM-L`).
- **Human check:** the ring, the editor and the tint look.
- **PR:** "Table PR F: cell mode (TCM, record N)".

## Review focus

1. **Text loss:** an edit must end in exactly one `onCommit` or one cancel. It must never end silently, whether by scroll, sort, data reload, the table leaving the hierarchy (that **commits**, as focus leaving does) or a window close (that **commits**).
2. **Row-mode regressions:** with cell mode off, every PR C test must still pass unchanged.
3. **Hidden O(rows) work:** in `Modifiers.primary`+↓, the unresolvable-row check, or `scrollTo`.
4. **Recycling:** the editor and the ring must key to (row id, column) and never to a window slot.
5. **The `fill` closure is called in paint:** it must not run each frame.
