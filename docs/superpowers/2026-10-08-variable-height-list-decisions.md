# Variable-height `List` — decisions

Rulings for rows of differing heights in `List` (user request 2026-10-02,
item 7 of the gpui-gap priority list; **not a plan task**). Spec:
[`specs/2026-10-08-variable-height-list-design.md`](specs/2026-10-08-variable-height-list-design.md).
Record: `../record/82-variable-height-list.md`. Branch
`feat/variable-height-list` from `70ed000`. Divergence labels come from this
branch's reserved range **145–149** (parallel branches hold the others; the
header's next-label line is the merge's to settle).

**Next unused id: `VL-N`.** (Moves in the commit that appends a ruling; to
find it, read this file's last `## VL-` heading.)

Evidence (each header carries its recorded output and how to run it):

- [`../probes/swiftui-variable-height-list.swift`](../probes/swiftui-variable-height-list.swift)
  (**new**; arms `V0`…`V3b`, `R1`/`R2`, `T-top`/`T-bottom`, `A1`…`A4`,
  `A6s`, `S1`; script and compiled forms byte-identical, 23 lines) —
  SwiftUI's `List` row sizing, its estimate for unrealised rows, `scrollTo`
  onto an unrealised row, and what moves when a row above the viewport
  changes.
- [`../probes/swiftui-data-and-scrolling.swift`](../probes/swiftui-data-and-scrolling.swift)
  (`T1`…`T15`, `L0`…`L3`; unchanged) — `scrollTo` arithmetic and a lazy
  stack's realisation, which `DD-G`/`DD-F` already rest on.
- [`../probes/swiftui-stack-algorithms.swift`](../probes/swiftui-stack-algorithms.swift)
  (`K6`; unchanged) — SwiftUI's `List` is greedy and self-scrolling, the root
  of divergence 84.
- **gpui** (`crates/gpui/src/elements/list.rs`, zed `main`, fetched
  2026-10-08 from `raw.githubusercontent.com` — read, not run; no local
  checkout on this machine): `ListState(Rc<RefCell<StateInner>>)`;
  `StateInner.items: SumTree<ListItem>` with `enum ListItem { Unmeasured {
  size_hint: Option<Size<Pixels>>, … }, Measured { size: Size<Pixels>, … } }`;
  the scroll position is `logical_scroll_top: Option<ListOffset>` with
  `pub struct ListOffset { pub item_ix: usize, pub offset_in_item: Pixels }` —
  an item and a distance into it, not a pixel offset — so remeasuring items
  above the top preserves what is on screen (through `pending_scroll`);
  `overdraw: Pixels` renders extra space above and below the viewport; data
  changes are announced with `splice(old_range, count)` ("the items in
  `old_range` have been replaced by `count` new items that must be
  recalculated") and `reset(count)`. SwiftUI has no anchoring answer (probe
  `A3`, `A6s`), so `VL-G` takes gpui's idea and adapts it to MetalUI's
  scroller-owned offset.

---

## VL-A — Scope and spelling

**Ruling.** A `List` whose rows size from their content, spelled as SwiftUI
spells `List` (probe `S1`):

```swift
public init(_ data: Data, estimatedRowHeight: Pixels? = nil,
            @ElementBuilder rowContent: @escaping (Data.Element) -> Row)
public init(_ data: Data, selection: Binding<Data.Element.ID?>, estimatedRowHeight: Pixels? = nil,
            @ElementBuilder rowContent: @escaping (Data.Element) -> Row)
public init(_ data: Data, selection: Binding<Set<Data.Element.ID>>, estimatedRowHeight: Pixels? = nil,
            @ElementBuilder rowContent: @escaping (Data.Element) -> Row)
```

`List(items) { row in … }` is the variable-height list; `List(items,
rowHeight: 28) { … }` (and its two selection twins) keeps its exact behaviour,
costs and `row:` label — the **uniform fast path** (`VL-I`). The row closure's
label is `rowContent:` on the new initialisers because it is SwiftUI's; the
uniform initialisers' `row:` is not renamed (renaming would churn every caller
for a label a trailing closure never shows). `estimatedRowHeight:` is
MetalUI-only (SwiftUI has none; `VL-C`).

**Why.** Item 7 asks for SwiftUI's row sizing; SwiftUI's spelling has no row
height at all, so the parameter's absence is the switch. A separate type
(`VariableList`) would leave `List(items) { }` unspellable — the one shape a
SwiftUI port writes first.

**Cost if wrong.** If `rowContent:` beside `row:` reads as noise, a later
ruling can add `row:` spellings of the new initialisers additively; nothing
removes.

## VL-B — A row's height is its content's, measured at the list's width

**Ruling.** A variable row is the realised row `Box` with **no** height pin
(today's `rowStyle` minus `size.height`; the inert `minSize.height: 0` and
`flexShrink: 0` stay, `LR-BS`), proposed `(list width, nil)` by the list's
layout and placed at its answer. **No inset and no floor**: a row 20 tall is
20, a row of zero height is 0. **Divergence 145.**

**Evidence.** Probe `V0`/`V1`: SwiftUI's row is its content plus 8 (30 → 38;
20, 60, 40, 100 → 28, 68, 48, 108). `V2`/`V2c`: measured at the list's width
(a wrapping `Text` is 72 at 200 wide, 40 at 400; at `.lineLimit(1)`, 24 at
both). `V3`/`V3b`: floored at `defaultMinListRowHeight`, 24 by default (a
4-tall content reads 24; with the floor at 4, 12).

**Why diverge.** MetalUI's `List` draws no row chrome (no separators, no
insets: the uniform path has always pinned rows to exactly `rowHeight`), and a
floor without `defaultMinListRowHeight` to lower it would be a constant no
caller can change. A caller who wants SwiftUI's look writes `.padding(.vertical,
4)` and `.frame(minHeight: 24)` on the row content.

**Cost if wrong.** Adding insets or a floor later moves every variable row —
a visible change the divergence row names; `defaultMinListRowHeight` as an
environment value is deferred (`VL-L`).

## VL-C — The estimate for an unmeasured row

**Ruling.** An unmeasured row counts, for windowing, offsets and the list's
extent, as: the **declared** `estimatedRowHeight` when the caller passed one;
else the **running mean** of every row measured at the current width; else
**24** (no row measured yet). **Divergence 147** (SwiftUI's estimate is the
constant 24, probe `R2`).

**Evidence.** `R2`: rows 995..<1000 of a lazy SwiftUI list read 24 each and
the document is 25721 where the content sums to 60000 — SwiftUI's estimate is
the floor. The 24 fallback is that number, so the first bounded frame of a
list with nothing measured windows as SwiftUI would.

**Why the mean.** The estimate decides the scroll extent the thumb and the
offset clamp see (`List` is its scroller's content, divergence 84). A mean
converges on the real extent as rows are measured; a constant never does. A
caller who knows better (a chat log of 80-point bubbles) declares it, and a
declared estimate is deterministic for tests.

**Note — a measured first window.** The third rule the brief offered is
covered by MetalUI's cold-frame rule rather than added: a list's first frame
inside its scroller is unbounded (`MP-I`) and builds and measures **every**
row, so the running mean starts exact. A bounded frame with nothing measured
happens only after a width change wipes the cache (`VL-E`), and that frame's
realised rows are measured before the mean is next read.

**Cost if wrong.** Switching to SwiftUI's constant is one line in
`RowExtentIndex.estimate`; the extent a scroller reports moves, nothing on
screen does (`VL-G` anchors it).

## VL-D — The height index: prefix offsets in `O(log n)`

**Ruling.** An internal `final class RowExtentIndex<ID: Hashable>`
(`Sources/MetalUI/ListRowExtents.swift`) holds, per data index, a measured
height or nothing, and answers:

- `offset(of: i)` — the sum of rows `0..<i` (measured, else the estimate);
- `extent(at: i)`, `totalExtent`;
- `index(containing y)` — the row whose span holds `y` (clamped into
  `0..<count`; a `y` exactly on a boundary belongs to the row below it);
- `record(_ height:, at:, id:)`, `isMeasured(_:)`, `id(at:)`.

Two Fenwick trees over the indices — measured heights, and a measured count —
so `offset(of: i) = measuredSum(i) + (i − measuredCount(i)) × estimate`; a
changed estimate costs nothing, and `index(containing:)` descends both trees in
lockstep (`⌈log₂ count⌉` steps). Every query and record is `O(log n)`; a
`nodeVisits` work counter (internal) is what the performance tests read.

**Where it lives.** A reference held in `ListOrigin` (new field
`extents: AnyObject?`, downcast by the generic list) at the list's own
`StateTable` entry — **no new reserved name, `theSevenRetentionSlotsAreMutuallyDistinct`
unmoved**, reaped with the list exactly as `ListOrigin` is. It is **created in
`prepaint` only inside a vertical scroller** (the `DD-F` item 1 rule: a list
outside every scroller mints no entry, read with `peek` in `requestLayout`);
**mutated in `requestLayout` (a rebuild, `VL-E`) and `prepaint` (records), never
in paint**; never through `write`, so it raises no `isDirty` and fires no
`onWrite` — it cannot keep the display link awake.

**Why a Fenwick pair and not a `SumTree`.** gpui's `SumTree` also supports
splices in `O(log n)`; MetalUI has no splice API to feed it (`VL-E`), and two
flat arrays are what an index-ordered prefix query over a re-read
`RandomAccessCollection` needs. **Cost if wrong**: a splice API later replaces
the storage behind the same queries.

## VL-E — Invalidation

**Ruling.**

1. **A realised row is re-measured every frame it is realised** (it is laid
   out every frame), and its record replaces the old height.
2. **A width change forgets every measurement** (`O(n)` once): `prepaint`
   compares the list's bounds width with the width the index was measured at,
   clears, then records this frame's realised rows (already measured at the new
   width).
3. **A data change is detected two ways, and either rebuilds the index by id**
   (`O(n)` once, in `requestLayout`, before the window is chosen): `data.count`
   differs from the index's count, or a row about to be realised carries an id
   other than the one recorded at its index. A rebuild keeps every height whose
   id is still present (at its new index) and drops the rest.
4. **An unrealised row's height is trusted until it is realised again** — a
   datum whose content changed off screen keeps its old height. There is no
   `O(1)` way to learn it changed, and SwiftUI does the same (probe `A1`, `A2`,
   `A4`: the table height of an off-screen row whose content grew stays 24 or
   28, the offset and the rows on screen unmoved).

**Cost.** Frames that change `data.count` cost `O(n)` id hashing; steady frames
cost `O(window · log n)`. An append-heavy 100k list pays `O(n)` per appending
frame — named, and the reason `VL-L` lists a splice API.

## VL-F — Windowing

**Ruling.** Inside a vertical scroller with a measured viewport, the window is
`index(containing: top) − 2 ..< index(containing: top + viewport) + 1 + 2`,
clamped into `0..<count`, where `top = min(max(0, offset − origin), max(0,
totalExtent − viewport))` — `DD-F`'s clamp and origin, `overscan` 2 rows, with
prefix offsets in place of division. **The escape hatches are unchanged**: no
context, a horizontal context, or a zero viewport (the scroller's first frame,
`MP-I`) builds **every** row — and a variable list measures each one exactly,
so its cold frame fills the index. `DD-F` item 3 is unchanged in shape: after
recording, `prepaint` computes the fresh window from the updated index and the
resolved offset and calls `requestAnotherFrame()` only when it is not contained
in the built one. AB-X rules 1 and 3 read `windowIsBounded` /
`windowAwaitsViewport` as today.

## VL-G — Anchoring: the row on top does not move

**Ruling.** Two halves, each with its own pin (`OM-AI`):

1. **This frame — placement.** `requestLayout` names the **anchor**: the row
   containing `top` (from the index as it stood before this frame's
   measurements) and its offset `anchorY = offset(of: anchor)`. The list's
   layout places the anchor row at `anchorY`, the realised rows after it
   downward and the realised rows before it **upward** from it, each at its
   measured height; the list answers `anchorY + Σ measured(anchor…last) +
   trailing estimate`. Rows above the anchor are above the viewport top, so the
   region they rearrange is never on screen.
2. **Next frame — the offset.** After recording, `prepaint` computes `D =
   offset(of: anchor) − anchorY` with the **updated** index and, when `D ≠ 0`,
   calls the new internal `Frame.noteScrollAnchorAdjustment(scroller:delta:)`.
   `applyScrollResolutions` (after paint) adds every adjustment to that
   scroller's stored offset through `withState` — **additively, after any
   `scrollTo` resolution for the same scroller** — and asks for one more
   frame. The next frame's offset and index agree, so the anchor row is drawn
   where it was. Every list row's position in this frame's coordinates is its
   next-frame position minus `D` (both for rows after the anchor and, by
   construction, for rows before it), which is why the additive composition is
   exact for a `scrollTo` onto one of the list's rows.
3. **Across a rebuild** the anchor is found **by id**: the id recorded at the
   anchor's old index (the row on top was realised last frame, so it is
   measured and its id recorded); the rebuilt index gives its new index; it is
   placed at its old `anchorY`. An insertion or removal above the viewport
   leaves the row on top where it was. **Divergence 146** (SwiftUI moves it,
   probe `A3`: 24 on screen).

Unbounded windows have no anchor (row 0 at 0, every row measured, exact).

**Evidence.** gpui's `logical_scroll_top` (an item and an offset into it) is
the approach; SwiftUI has none — `A6s` (a non-lazy `ScrollView` keeps its
offset while 200 points grow above it) and `A3` (an insertion above the top
moves the top row 24).

**Known costs, named.** (a) At the end of the content, the scroller's clamp can
still move what is on screen when the measured extent is smaller than the
estimated one (the offset cannot pass the end). (b) A `scrollTo` target that
is **not** a list row and sits above the list's anchor in the same frame is
shifted by `D` (the additive composition assumes the target moved with the
list). (c) Every frame with `D ≠ 0` costs one more frame; `D` is zero once the
rows around the viewport are measured.

## VL-H — `scrollTo` and keyboard reveal onto an unmeasured row

**Ruling.** `resolveScrollRequests` targets a row at `offset(of: i)` with
height `extent(at: i)` from the updated index (estimate if unmeasured). When
the target row was **unmeasured**, the list carries a refinement into the next
frame: a `ListLeadReveal` (gaining `anchor: UnitPoint?` and `refined: Bool`)
for the same row and anchor, appended to the window's queue with a new
`ScrollRequestQueue.carry(_:)` that does **not** fire `onEnqueue` (a phase
must not dirty the window; `applyScrollResolutions` already asks for the next
frame). A refined reveal never refines again, so a target resolves in at most
two steps. A keyboard reveal (`DD-AC` item 2) goes through the same path.

**Evidence.** Probe `T-top`/`T-bottom`: SwiftUI lands an unrealised row exactly
— `.top` at 0.2 on screen, `.bottom` with its bottom at the viewport's (272.2 +
28 = 300). A one-step estimate would miss `.bottom`/`.center`/nil-anchor
targets by `height − estimate`.

## VL-I — The uniform fast path

**Ruling.** `List(_:rowHeight:row:)` and its two selection twins keep
`WindowedRowsLayout`, division windowing, `style.size.height = rowHeight ×
count`, and **no** `RowExtentIndex`, no anchor adjustment, no new `ListOrigin`
field written. The variable path is a separate `VariableRowsLayout` and a
branch on a stored `rowSizing` enum (`.uniform(Pixels)` /
`.variable(estimate: Pixels?)`) replacing the stored `rowHeight` — **a stored
property change on a public generic type: `swift package clean` after it**.
Pinned by the existing literals (`aListsWorkIsTheSameFor160RowsAsFor40`,
`MeasurePerformanceTests.demoLikeRowsWarmWork`, `aListSizesItselfToCountTimesRowHeight`),
which must not change.

**Migration note.** None for callers of the uniform spelling. A variable list's
`style.size.height` is `.auto` (its extent is the layout's answer), so code
reading `List.style.size.height` to learn a list's height must read layout.

## VL-J — What does not move

**Ruling.** Row identity (`child(of: list, at: 0, name: datum.id)`), TB-AH
retention, `ID-R`'s windowed-parent exemption, selection (`DD-Z`), ⇧ ranges and
the keyboard table, focus (`IX-I`, a row out of window keeps it), accessibility
(the table's `logicalCount`, realised rows' `logicalIndex`, AB-X), hit testing
and animation all run through the **same** row construction the uniform path
uses; the variable branch differs only in the row style, the layout it
registers, the window arithmetic and `prepaint`'s recording. `Deferred`, text
input and the seven slots are untouched.

## VL-K — Demo

**Ruling.** A variable-height list (a few hundred rows of wrapping text of
three lengths, a selectable column, a "jump to row 250" button through
`ScrollViewReader`) in its own file
`Sources/MetalUIDemoContent/VariableListDemo.swift`, its own function (1 MB
stacks), reached only with `METALUI_LIST_DEMO=1` in `MetalUIDemo` and
`MetalUISDLDemo`. No captured image sees it: the fourteen offscreen images
stay at **0 px** against `70ed000`, `DemoFrameDeterminismTests`' Expected.swift
unedited.

## VL-L — Deferred, each with a reason and an owner

- **A splice API** (`List` told "rows 3..<5 replaced by 4", gpui's
  `ListState::splice`) so inserts and appends cost `O(log n)` rather than an
  `O(n)` rebuild. Owner: none — no caller yet; `VL-E` names the cost.
- **`defaultMinListRowHeight` and row insets** (divergence 145). Owner: none.
- **Re-measuring an off-screen row whose datum changed** (`VL-E` item 4).
  Owner: none; SwiftUI does not either.
- **A lazy cold frame** (`MP-I`, divergence 124): the first frame inside a
  scroller still builds every row — now also measuring each. Owner: the `List`
  cold-frame rule (none scheduled), as today.
- **Horizontal variable lists, `LazyVStack`/lazy grids** — not built (stage
  G2). Owner: none.
- **Separators, sections, row swipe actions, `.listStyle`.** Owner: none.

## VL-M — Lanes

**Ruling.** Three lanes on disjoint files, run in order (one agent at a time
in this worktree): lane 1 the index and the `Frame` hook; lane 2 `List` and
`ListRows`; lane 3 the demo and the public documents. Spec §6 lists every file
and every test.
