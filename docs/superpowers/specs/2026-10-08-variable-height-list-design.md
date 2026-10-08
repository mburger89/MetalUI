# Variable-height `List` — design

User request 2026-10-02 (item 7 of the gpui-gap priority list; **not a plan
task**). Rulings: [`../2026-10-08-variable-height-list-decisions.md`](../2026-10-08-variable-height-list-decisions.md)
(`VL-A`…`VL-S`; `VL-N`…`VL-S` are the critic's corrections, folded in below). Record: `../../record/82-variable-height-list.md`. Branch
`feat/variable-height-list` from `70ed000`. Divergence labels: this branch's
reserved range **145–149** (145, 146, 147 used; 148, 149 spare).

Parallel branches running now: `feat/input-apis` (record §81: input events,
gestures, bridges) and `feat/rich-text` (record §83: `Text`, the text
systems). This branch stays off their files; the one shared file it touches is
`Frame.swift` (two small additions, §3.2) — the merge's to reconcile.

**Status: designed (2026-10-08), critic pass applied (`VL-N`…`VL-S`).** Lanes not started.

---

## §0 Baseline

Measured by the design session at `70ed000` (`swift build --build-system
native --build-tests`, then `swift test --build-system native --no-parallel`
unfiltered).

### §0.1 Reading

- Build: `Build complete!`, exit 0; the only `warning:` SwiftPM's
  `--build-system native` deprecation notice.
- Suite: **`Test run with 2672 tests in 3 suites passed after 214.227
  seconds.`**, exit 0, 0 `error:`; `FR-J no-argument frame: succeeded=true
  deprecations=2` present (guards ran). Matches record §80 §5.
- Not re-taken by the design session: `swift build --build-tests` (default
  build system) warnings, `Backends/SDL`, the Linux image, demo pixels —
  lane 1 takes the first, lane 3 the rest.

---

## §1 What exists (inventory)

- `Sources/MetalUI/List.swift` (912 lines): `List<Data, Row>` — stored
  `rowHeight: Pixels`, `style.size.height = rowHeight × count` set in `init`;
  `visibleRange`/`window(count:rowExtent:offset:viewport:origin:)` divide by the
  row height; `requestLayout` builds each realised row as `Box(style:
  rowStyle) { row(datum) }.id(String(describing: datum.id))` with selection
  background, `logicalIndex`, `rowClick`; `prepaint` runs
  `noteOriginAndStaleness` (`DD-F` items 1 and 3: `ListOrigin.offset` stored
  through `withState`, `requestAnotherFrame()` on a stale window),
  `resolveScrollRequests` (`DD-G`/`DD-K`: a row's rect from `index ×
  rowHeight`, a scan of `data` while a request is pending), `composeSelectionKeys`
  (`DD-Z`, `ListLeadReveal` enqueued from input), and the AB-X suppression.
  `ListOrigin` (`offset`, `lead`, `anchor`) is the one entry at the list's id.
- `Sources/MetalUI/ListRows.swift`: `ListRows<Row>` (the group, no id level,
  `noteWindowedParent` for `ID-R`, `planLegacyItems`/`registerLegacyItems`
  against the list's declared style, `LR-CD`'s width correction) and
  `WindowedRowsLayout` (height `rowHeight × logicalCount`; width the proposal's
  or the widest realised row at `(nil, rowHeight)`; row *i* at `(firstIndex +
  i) × rowHeight`).
- `Sources/MetalUI/Frame.swift`: `activeScrollerFrame` (`ScrollerFrame`:
  `scrollerID`, `contentOrigin`, `viewport`, `offset`, `contentExtent`),
  `resolveScrollRequest`, `scrollOffset(bringing:into:anchor:)`,
  `applyScrollResolutions()` (after paint: `withState` writes of the resolved
  offsets, one `requestAnotherFrame()`).
- `Sources/MetalUI/ScrollChrome.swift`: `resolvedOffset` (prepaint: clamps the
  stored offset against this frame's content and writes it back) — runs in the
  scroller's `prepaint` **before** the content prepaints, which is why `VL-G`
  corrects the offset after paint and anchors placement in the same frame.
- `Sources/MetalUI/ScrollViewReader.swift`: `ScrollRequestQueue` (`enqueue`
  fires `onEnqueue`, which dirties the window; `take()` at frame start).
- Tests touching `List` (35 files; the pins this branch must keep green):
  `ListTests`, `ListLoweringTests`, `ListSelectionTests`, `ScrollToTests`,
  `TombstoneTests`, `FocusTests`, `AXNodeTests`, `AccessibilityTreeTests`,
  `MeasurePerformanceTests` (`demoLikeRowsWarmWork` = 17 / 103 / 120,
  `aListsWorkIsTheSameFor160RowsAsFor40`, env-gated
  `aListsWorkIsTheSameFor100kRowsAsFor500`), `LifecycleTests`
  (`aListsFirstFrameAppears…`, divergence 124).
- Public-API inventory: `List.swift` is mapped wholesale (`M MetalUI List.swift
  .* → list`), so new initialisers there need doc comments and a refreshed
  `F list` row text, not new rows.

## §2 SwiftUI's answers (probe `swiftui-variable-height-list.swift`, recorded)

| Arm | Reading | Used by |
|---|---|---|
| V0/V1 | row = content + 8 (30→38; 20,60,40,100 → 28,68,48,108) | `VL-B`, div 145 |
| V2/V2c | measured at the list's width (72 at 200, 40 at 400; `.lineLimit(1)` 24/24) | `VL-B` |
| V3/V3b | floor `defaultMinListRowHeight` 24 (4 → 24; floor 4 → 12) | `VL-B`, div 145 |
| R1 | lazy: 13 of 1000 realised | (div 124 unchanged) |
| R2 | unrealised rows estimated at 24 (document 25721 vs 60000) | `VL-C`, div 147 |
| T-top/T-bottom | `scrollTo` an unrealised row lands exactly (.top 0.2; .bottom 272.2 + 28) | `VL-H` |
| A1/A2/A4 | an off-screen row's content change moves nothing (height stays 24/28); **A2's row was not realised** (98:24, content 80 — `VL-N`) | `VL-E` item 4 |
| A3 | an insertion above the top moves the top row 24 | `VL-G` item 3, div 146 |
| A6s | a non-lazy `ScrollView` keeps its clip while content above grows (reads the clip only; `A3` is the arm that reads a row move, `VL-N`) | `VL-G` |
| — | **unprobed**: a *realised* row above the viewport changing height — no divergence claimed for `VL-G` items 1–2 (`VL-N`) | — |
| S1 | `List(_:rowContent:)`, both `List(_:selection:rowContent:)` compile | `VL-A` |

gpui's approach (cited from source, `VL-G`'s evidence): `ListOffset { item_ix,
offset_in_item }`, `SumTree<ListItem>` of `Unmeasured`/`Measured`,
`splice`/`reset`.

## §3 Design

### §3.1 Public API (`VL-A`)

```swift
extension List {
    public init(_ data: Data, estimatedRowHeight: Pixels? = nil,
                @ElementBuilder rowContent: @escaping (Data.Element) -> Row)
    public init(_ data: Data, selection: Binding<Data.Element.ID?>, estimatedRowHeight: Pixels? = nil,
                @ElementBuilder rowContent: @escaping (Data.Element) -> Row)
    public init(_ data: Data, selection: Binding<Set<Data.Element.ID>>, estimatedRowHeight: Pixels? = nil,
                @ElementBuilder rowContent: @escaping (Data.Element) -> Row)
}
```

Each with a doc comment. The uniform `init(_:rowHeight:row:)` and its selection
twins are unchanged. A non-positive or non-finite `estimatedRowHeight` is
**clamped** to "not declared" (the mean/24 rule applies) — not a trap (`SA-J`:
SwiftUI has no such parameter to reject it; trap → clamp is additive, the
reverse is not).

### §3.2 Internal pieces

1. **`RowExtentIndex<ID>`** (`VL-D`; new file `Sources/MetalUI/ListRowExtents.swift`):
   `init(count:declaredEstimate:)`, `count`, `width: Double?`,
   `estimate`, `offset(of:)`, `extent(at:)`, `totalExtent`,
   `index(containing:)`, `record(_:at:id:)`, `isMeasured(_:)`, `id(at:)`,
   `forgetMeasurements(width:)`, `rebuild(ids:)` (keeps heights by id; returns
   the old-index → new-index lookup the anchor needs, or the new index of a
   given id), `nodeVisits` (work counter), `rebuilds` (count, for the
   performance pins). Two Fenwick arrays (`[Double]` sums, `[Int32]` counts),
   `heights: [Double]` (NaN = unmeasured), `ids: [ID?]`, `byID: [ID: Double]`.
2. **`Frame.noteScrollAnchorAdjustment(scroller:delta:)`** and its application
   in `applyScrollResolutions()` (`VL-G` item 2): adjustments are summed per
   scroller and **added after** that scroller's absolute resolution (or to the
   stored offset when there is none), through `withState`; a nonzero
   adjustment asks for one more frame; a zero one is never recorded.
3. **`ScrollRequestQueue.carry(_:)`** (`VL-H`): appends without `onEnqueue`.
   **`Frame.unresolvedScrollRequestsWithScope(enclosing:)`** (new, beside the
   unchanged two-member `unresolvedScrollRequests(enclosing:)`, which is it
   narrowed — `VL-T` item 1) returns `(index, key, scope, anchor)` so a list
   can carry a refinement with its request's scope and anchor (`VL-P`; lane 1).
4. **`ListOrigin`** gains one field, `extents: AnyObject?` (the index). The
   anchor is **not** stored: it is recomputed each frame from the index (`VL-G`
   item 1) and, across a rebuild, from `ids[oldAnchorIndex]` read before the
   rebuild (item 3).
5. **`ListLeadReveal`** gains only `refined: Bool` (default false; `VL-P` —
   the anchor stays on the `ScrollRequest`; equality unchanged in meaning: a
   reveal is only ever matched by its own list).
6. **`ListRows`** stores which layout it registers (an internal enum,
   uniform or variable) and **`VariableRowsLayout`** lives beside
   `WindowedRowsLayout` — both lane 1's (`VL-Q`).

### §3.3 `List` (variable branch; `VL-E`…`VL-H`)

Stored `rowSizing: RowSizing` (`.uniform(Pixels)` / `.variable(estimate:
Pixels?)`) replaces `rowHeight` (**`swift package clean`**). Also threaded
`builtIDs: [Data.Element.ID]` and `anchor: (index: Int, y: Double)?` from
`requestLayout` to `prepaint`, as `builtWindow` is.

`requestLayout` (variable):

1. Row style: `rowStyle` without `size.height`. `style.size.height` stays
   `.auto`.
2. `peek` `ListOrigin`; downcast `extents` to `RowExtentIndex<Data.Element.ID>`.
   If present and `count != data.count` → remember `ids[anchorIndex]` (from the
   pre-change top), `rebuild(ids:)` — `O(n)`.
3. Bounded (vertical context, viewport > 0, index present): `top`, anchor =
   `index(containing: top)`, `anchorY = offset(of: anchor)` (after a rebuild:
   the anchor id's new index, placed at its **old** `anchorY`), window per
   `VL-F`. While building rows, a realised row whose recorded id differs from
   `datum.id` triggers one rebuild and one recomputation of the window.
   **Across a rebuild, an anchor whose id is gone** falls to the first
   still-present recorded id after it, else the last before it, else
   `min(oldAnchorIndex, count − 1)`, placed at the old `anchorY` (`VL-O`).
   Bounded without an index (first bounded frame after a wipe or a list newly
   inside a measured scroller): estimate-only window from a fresh `count`
   index (not stored until `prepaint`), anchor row 0 at 0 unless `top > 0`.
4. Unbounded: every row, no anchor.
5. `ListRows` registers `VariableRowsLayout(anchorSlot:anchorY:trailingExtent:)`
   instead of `WindowedRowsLayout`, `trailingExtent = totalExtent −
   offset(of: window.upperBound)`.
6. Everything else — ids, scroll keys, selection, `logicalIndex`, handlers,
   AX — is the uniform code, shared.

`VariableRowsLayout` (`ListRows.swift`): width = proposal's, else the widest
realised row at `(nil, nil)`; each realised row measured at `(width, nil)`;
height = `anchorY + Σ h[anchorSlot...] + trailingExtent`; placement: anchor at
`bounds.y + anchorY`, later rows downward, earlier rows upward. `SA-J`: rejects
nothing.

`prepaint` (variable, in this order):

1. Inside a vertical scroller: `withState(ListOrigin)` creates the index if
   absent (with `count` and the declared estimate); `forgetMeasurements` if
   `bounds.width` differs from `index.width`; `record` each realised row's
   placed height (`PrepaintPass.bounds(of:)` of the row's node) and id.
2. `D = offset(of: anchor.index) − anchor.y`; nonzero →
   `noteScrollAnchorAdjustment(scroller: activeScrollerFrame.scrollerID, delta: D)`.
3. `DD-F` origin store and staleness, with `VL-F`'s window from the updated
   index and `scroller.offset + D`.
4. `resolveScrollRequests` (`VL-H`): target `bounds.origin.y + offset(of: i) −
   D`, height `extent(at: i)` (this frame's coordinates; `applyScrollResolutions`
   adds `D`); unmeasured target and not `refined` → `carry`
   `ScrollRequest(scope: request.scope, key: ListLeadReveal(list:row:refined: true),
   anchor: request.anchor)` (`VL-P`; the clamp binds before `D` near the
   content's end — named cost (d)).
5. Selection keys and AB-X exactly as today.

Outside every scroller a variable list has no index, no entry and no anchor —
it is a column of measured rows (`aVariableListOutsideAScrollerMintsNoStateEntry`).

### §3.4 Platforms

Portable code only: `MetalUI`, no renderer, shader, `PlatformWindow`,
`Platform` or `WindowRenderer` change. `Backends/SDL` changes only by the demo
flag in `MetalUISDLDemo/main.swift` (lane 3), which obliges the
`Backends/SDL` build/test and the Linux image run. `MetalUILayout` and
`MetalUIScene` imports untouched.

### §3.5 How tests drive it headless

`Window` over `Fakes.swift`'s platform, `renderFrame`/`simulateTick` only, no
sleeps; scroll by writing `ScrollState.offset` (`TombstoneTests`' idiom) or by
wheel events (`ListTests.wheel`). Row geometry from `Frame.bounds(of:)` /
`ListTests`' recorded-row log; "on screen" = row content y − scroller offset.
A deterministic width-dependent leaf (`AreaLeaf`: a `requestNativeLeaf`
answering `height = area / width`) stands in for wrapping text — **no `Text`
fixture** (TX-B). Literals are derived in the test's comment before the run.

## §4 Divergences (labels from 145–149)

- **145** — a variable-height `List` row: SwiftUI content + 8 (4pt insets),
  floored at `defaultMinListRowHeight` 24 (V0–V3b); MetalUI exactly the
  content's height, no inset, no floor. Pin
  `aVariableListSizesEachRowToItsContent`. `VL-B`.
- **146** — an insertion or removal above the viewport: SwiftUI moves the top
  row (24 in A3); MetalUI keeps it where it was. Pin
  `anInsertionAboveTheViewportKeepsTheRowOnTop`. `VL-G` item 3.
- **147** — an unrealised row's estimate: SwiftUI the constant 24 (R2);
  MetalUI the declared estimate, else the running mean, else 24. Pins
  `theRunningMeanEstimatesUnmeasuredRows` (the index) and
  `aVariableListAnswersMeasuredPlusEstimatedExtent` (the list; `VL-R` item 6). `VL-C`.
- **84** amended in the Record phase: "one row height" becomes "uniform
  `rowHeight:` or content-sized rows"; the enclosing-`ScrollView` and
  `rowHeight × count` clauses stay for the uniform spelling.

## §5 Tests — by lane, each with its red-before and the mutation that must redden it

"Red-before" is how the test is seen to fail before the code it pins exists
(`docs/practices/verifying-tests-can-fail.md`); "mutation" is applied after
the lane lands, on a commit, full unfiltered suite, every reddened test
named. A new typecheck guard is mutated red once.

### Lane 1 — the index and the `Frame` hook

`Tests/MetalUITests/RowExtentIndexTests.swift` (pure, `@testable`; red-before:
against a stub `RowExtentIndex` whose queries return 0 and whose `record` does
nothing, each test fails on its first `#expect`):

| # | Test | Asserts | Mutation that must redden it |
|---|---|---|---|
| 1.1 | `anIndexWithNothingMeasuredEstimatesEveryRowAtTwentyFour` | count 5: `offset(of: 5)` 120, `extent(at: 2)` 24 | fallback 24 → 28 |
| 1.2 | `aDeclaredEstimateWinsOverTheRunningMean` | estimate 40 declared, rows measured 10/30: unmeasured rows 40 | precedence swapped |
| 1.3 | `theRunningMeanEstimatesUnmeasuredRows` | count 4, record 10@0, 30@1: offsets 0,10,40,60, total 80 | mean → last recorded height |
| 1.4 | `prefixOffsetsMatchANaiveSumAfterRecordsInAnyOrder` | 1000 rows, a fixed pseudo-random record order, every `offset(of:)` equals the naive sum | Fenwick update stride `i += i & -i` → `i += 1` |
| 1.5 | `indexContainingAnOffsetFindsTheRowWhoseSpanHoldsIt` | boundary belongs to the row below; past the end → last; negative → 0; empty → 0 | descent `<=` → `<` |
| 1.6 | `reRecordingARowReplacesItsHeight` | record 10 then 30 at row 2: offset after it +30, not +40 | drop the subtract-old step |
| 1.7 | `forgettingMeasurementsReturnsEveryRowToTheEstimate` | after `forgetMeasurements(width:)`, mean back to 24, width stored, and `id(at:)` still answers (`VL-O`) | (a) clear sums but not counts; (b) clear `ids` too |
| 1.8 | `aRebuildKeepsHeightsByIDAcrossAReorderAndAnInsertion` | [a,b,c] measured 10/20/30 → [x,c,a,b]: offsets 0,24,54,64 | rebuild keyed by index |
| 1.9 | `aRebuildDropsHeightsOfIDsNoLongerPresent` | removed id's height leaves the mean | keep `byID` entries for absent ids |
| 1.10 | `aLookupAtAHundredThousandRowsVisitsLogarithmicallyManyNodes` | `index(containing:)` visits exactly `⌊log₂ 100 000⌋ + 1` = 17 nodes (`VL-T` item 2), `offset(of:)` ≤ 17; at 500: 9 / ≤ 9 | linear prefix scan |

`Tests/MetalUITests/ScrollAnchorAdjustmentTests.swift` (a `Window` over the
fakes; a probe element inside a `ScrollView` calls the hook in `prepaint`;
red-before: the hook does not exist — the lane first lands it as a no-op and
sees 1.11/1.12 fail):

| # | Test | Asserts | Mutation |
|---|---|---|---|
| 1.11 | `anAnchorAdjustmentMovesTheStoredOffsetAfterPaintAndAsksForAFrame` | offset 100, delta 30: this frame paints at 100, stored 130 after, `wantsAnotherFrame` | (a) not applied; (b) no `requestAnotherFrame` — each reddens it |
| 1.12 | `anAnchorAdjustmentAddsToAScrollToResolutionInTheSameFrame` | `scrollTo` resolving to 200 plus delta 30 → 230 | absolute overrides the delta |
| 1.13 | `aZeroAdjustmentWritesNothingAndAsksForNoFrame` | delta 0: no write, no frame | record and request unconditionally |
| 1.14 | `aCarriedScrollRequestDirtiesNothingAndResolvesNextFrame` | `carry` from prepaint: `isDirty` false after the frame; resolved on the next | `carry` calls `onEnqueue` |
| 1.15 | `anUnresolvedRequestCarriesItsScopeAndAnchorToTheList` | `scrollTo(k, anchor: .bottom)` under a reader: the probe element reads the reader's scope and `.bottom` (`VL-P`) | return `anchor: nil` |

`Tests/MetalUITests/VariableRowsLayoutTests.swift` (new; `VL-Q`; under a
`ProposalLayoutContainer`, the fixture `Tests/MetalUITests/AreaLeaf.swift`;
red-before: `VariableRowsLayout` first lands placing every row at y 0 with
height 0):

| # | Test | Asserts | Mutation |
|---|---|---|---|
| 1.16 | `variableRowsPlaceTheAnchorAtItsOffsetAndTheRestAroundIt` | rows 10/20/30/40, `anchorSlot` 2, `anchorY` 100, `trailingExtent` 50: y 70/80/100/130, height 220 | place every row downward from slot 0 |
| 1.17 | `variableRowsAreMeasuredAtTheProposedWidth` | `AreaLeaf(4000)` rows: 20 each at width 200, 10 at 400 | propose rows `(nil, nil)` |
| 1.18 | `variableRowsAtANilWidthTakeTheWidestRow` | nil width: width = widest `(nil, nil)` answer, heights at it | measure heights at `(nil, nil)` |

### Lane 2 — `List` and `ListRows`

`Tests/MetalUITests/VariableHeightListTests.swift` (red-before: the variable
initialisers first land routed to the uniform path at `rowHeight` 24 — each
test below fails against that stub, which is how it is seen to fail):

| # | Test | Asserts | Mutation |
|---|---|---|---|
| 2.1 | `aVariableListSizesEachRowToItsContent` | outside a scroller, rows 20/60/40: y 0/20/80, list height 120 (div 145) | pin rows to the estimate |
| 2.2 | `aVariableRowIsMeasuredAtTheListsWidth` | `AreaLeaf(4000)` rows: 20 tall at width 200, 10 at 400 | propose rows `(nil, nil)` |
| 2.3 | `aVariableListAnswersMeasuredPlusEstimatedExtent` | in a scroller, bounded: content extent = derived literal (measured window + mean × rest) | omit `trailingExtent` |
| 2.4 | `aVariableListWindowsByPrefixOffsets` | patterned heights 20…100, offset 3000: built rows exactly the derived range | window by division at the estimate |
| 2.5a | `aRowAboveTheTopMeasuredAnewDoesNotMoveTheRowOnTopInThatFrame` | row 48 (overscan) grows 200 via the model: row 50's on-screen y identical in the frame of the change | place from `offset(of: first)` (no anchor placement) |
| 2.5b | `aRowAboveTheTopMeasuredAnewDoesNotMoveTheRowOnTopOnTheNextFrame` | same, on the frame after: y identical, stored offset +200 | skip `noteScrollAnchorAdjustment` |
| 2.6 | `aWidthChangeKeepsTheRowOnTopAndForgetsEveryMeasurement` | window narrowed: top row id and on-screen y unchanged; extent = derived literal at the new width | (a) skip `forgetMeasurements` (extent reddens); (b) skip the anchor (y reddens) |
| 2.7 | `anInsertionAboveTheViewportKeepsTheRowOnTop` | insert a 150-tall row at 0 while row 50 is on top: row 50 stays (div 146) | anchor by index across the rebuild |
| 2.7b | `removingTheRowOnTopPutsTheNextRowInItsPlace` | arm 1: row 50 on top removed → row 51's id on top at row 50's old y; arm 2: remove row 50 and insert at 0 in one change → old row 51 on top (`VL-O`) | (a) prefer the id before (arm 1 reddens); (b) fall back to `oldAnchorIndex` (arm 2 reddens) |
| 2.7c | `anInsertionAboveTheViewportUnderWithAnimationKeepsTheRowOnTopEveryTick` | 2.7 inside `withAnimation`, `simulateTick`-driven: the row on top's on-screen y unchanged at every tick until no frame is asked for (`VL-R` item 8) | skip `noteScrollAnchorAdjustment` |
| 2.8 | `aSameCountDataChangeIsDetectedFromARealizedRow` | ids in the window replaced, count equal: positions follow the new rows' heights | skip the realised-id check |
| 2.9 | `scrollToAnUnmeasuredRowLandsExactlyOnceMeasured` | `scrollTo(row 150, anchor: .bottom)`, real height ≠ estimate: after the settle frames, bottom = viewport bottom exactly (cf. T-bottom) | no refinement carried |
| 2.10 | `aRefinedRevealNeverRefinesAgain` | a target that stays unmeasured: at most two resolutions, then no frame requested | drop the `refined` guard |
| 2.11 | `aVariableListSettlesWithoutInput` | after a jump of 5000: frames asking for another frame ≤ 3, then none | request a frame whenever `D` is computed |
| 2.12 | `selectionAndShiftRangesAreUnchangedInAVariableList` | click, ⌘-click, ⇧-click, ⇧↓ give the uniform list's sets | variable branch skips `rowClick` |
| 2.13 | `aVariableListRowsStateSurvivesABoundedExcursionButNotALongerOne` | TB-AH, both halves | drop the row's `.id(datum.id)` in the variable branch (`VL-R` item 1) |
| 2.14 | `aFocusedVariableRowKeepsFocusOutOfWindow` | `IX-I` | variable branch drops `isFocusable` composition |
| 2.15 | `aVariableListPublishesItsLogicalCountAndRealizedRowIndices` | AB-L/AB-X | drop `logicalIndex` in the variable branch |
| 2.16 | `aVariableListOutsideAScrollerMintsNoStateEntry` | `peek` nil after frames | `withState` in `requestLayout` |
| 2.17 | `aVariableListInAHorizontalScrollerMeasuresEveryRowAtItsWidestWidth` | nil-width path: width = widest at `(nil,nil)`, heights at it | measure heights at `(nil, nil)` |
| 2.18 | `aNonPositiveEstimateIsTreatedAsUndeclared` | `estimatedRowHeight: 0` and `-5` behave as nil | drop the clamp (a declared 0 makes every unmeasured row 0; `VL-R` item 2) |

`Tests/MetalUITests/VariableHeightListCompileGuards.swift`:

| # | Guard | Asserts | Mutated red once by |
|---|---|---|---|
| 2.19 | `theVariableListSpellingsCompileFromAPlainImport` | `typecheckFile` with `import MetalUI`: `List(items) { … }`, `List(items, selection: $one) { … }`, `List(items, selection: $many) { … }`, `List(items, estimatedRowHeight: 40) { … }`, `List(items, rowContent: { … })` | renaming `rowContent:` → `content:` |

`Tests/MetalUITests/MeasurePerformanceTests.swift` (additions; red-before:
written against the stub, the literal fails):

| # | Test | Asserts | Mutation |
|---|---|---|---|
| 2.20 | `aVariableListsWorkIsTheSameFor160RowsAsFor40` | warm `lastNativeLayoutWork` equal at 40 and 160 and equal to a literal derived in the comment before the run; index `rebuilds` 0 on warm frames; `nodeVisits` per warm frame equal to its derived literal at each count (`VL-R` item 7) | (a) rebuild every frame; (b) linear `offset(of:)` |
| 2.21 | `aVariableListsWorkIsTheSameFor100kRowsAsFor500` (gated `METALUI_RUN_100K_LIST_TEST=1`) | as 2.20 at 500 / 100 000, plus `nodeVisits` per warm frame equal to the derived `O(window · log n)` literal at each count | linear `offset(of:)` |

Existing pins that must stay green **unedited** (the uniform fast path,
`VL-I`): every test in §1's list; a mutation routing the uniform spelling
through the variable path must redden at least `aListSizesItselfToCountTimesRowHeight`,
`aListsWorkIsTheSameFor160RowsAsFor40` and `aRowTallerThanRowHeightIsFlooredAtRowHeightNotContent`
(recorded by name).

### Lane 3 — demo and documents

| # | Test | Asserts | Mutation |
|---|---|---|---|
| 3.1 | arm in `everyProductionTreeBuildsOnAOneMegabyteThread` (`Tests/MetalUICrossPlatformTests/DemoStackBudgetTests.swift`) | `variableListDemoContent()` builds on a 1 MB thread | the arm run once at a 64 KiB thread must fail, recorded; the separating control is `aThreadTooSmallForTheDemoFailsTheSameHarness` (`VL-R` item 3) |
| 3.2 | `theVariableListDemoSettlesHeadless` (`Tests/MetalUITests/VariableHeightListTests.swift`'s neighbour, a new `VariableListDemoTests.swift`) | the demo tree renders in a fake window, scrolls by 4000, settles in exactly the derived number of frames, and builds fewer rows than `data.count` (`VL-R` items 4–5) | remove the demo's `ScrollView` (the built-row assertion reddens) |

Plus, not tests: the fourteen offscreen images at **0 px** against `70ed000`
(`docs/probes/demo-pixels/compare.sh <scratch> 70ed000 HEAD`);
`DemoFrameDeterminismTests`' Expected.swift unedited; `Backends/SDL` build and
test (`swift test $(python3 scripts/fetch-accesskit.py --print-flags)`) and the
Linux image run (§7).

## §6 Lanes and files (disjoint; run in order)

| Lane | Files (only these) |
|---|---|
| 1 | `Sources/MetalUI/ListRowExtents.swift` (new), `Sources/MetalUI/Frame.swift` (anchor hook, request accessor), `Sources/MetalUI/ScrollViewReader.swift` (`carry`), `Sources/MetalUI/ListRows.swift` (`VariableRowsLayout`, the layout choice; `VL-Q`), `Tests/MetalUITests/RowExtentIndexTests.swift` (new), `Tests/MetalUITests/ScrollAnchorAdjustmentTests.swift` (new), `Tests/MetalUITests/VariableRowsLayoutTests.swift` (new), `Tests/MetalUITests/AreaLeaf.swift` (new) |
| 2 | `Sources/MetalUI/List.swift`, `Tests/MetalUITests/VariableHeightListTests.swift` (new), `Tests/MetalUITests/VariableHeightListCompileGuards.swift` (new), `Tests/MetalUITests/MeasurePerformanceTests.swift` (additions only) |
| 3 | `Sources/MetalUIDemoContent/VariableListDemo.swift` (new), `Sources/MetalUIDemo/main.swift`, `Backends/SDL/Sources/MetalUISDLDemo/main.swift`, `Tests/MetalUICrossPlatformTests/DemoStackBudgetTests.swift`, `Tests/MetalUITests/VariableListDemoTests.swift` (new), `docs/divergences.md` (rows 145–147, 84 amended), `docs/migration.md`, `docs/api-overview.md`, `docs/verification/human-checks.md`, `docs/probes/closeout-inventory-map.tsv` (the `F list` row text), `docs/probes/closeout-public-api.tsv` (re-recorded census) |

Each lane appends its amendments as `VL-` rulings (next unused `VL-U`), and its
record section to `docs/record/82-variable-height-list.md`. The Record phase
(after lane 3) edits `CLAUDE.md`/`AGENTS.md` (the `VL-` prefix, one rule
sentence under `List`, counts), `docs/record/README.md`, record §03/§04 rows.

## §7 Gates (every lane)

`swift build --build-system native --build-tests`; `swift test --build-system
native --no-parallel` unfiltered — the one summary line, the `FR-J
no-argument frame: succeeded=` line, 0 `error:`, the only `warning:` SwiftPM's
deprecation notice; `swift build --build-tests` 0 warnings;
`zsh docs/probes/closeout-inventory-check.sh` and `closeout-undocumented.sh`
print nothing. `swift package clean` before lane 2's first build (the stored
property change, `VL-I`). **Lane 2 additionally** (`VL-R` item 9): the
fourteen offscreen images at 0 px against `70ed000`
(`docs/probes/demo-pixels/compare.sh <scratch> 70ed000 HEAD`) and both
env-gated 100k tests under `METALUI_RUN_100K_LIST_TEST=1`, readings recorded.
Lane 3 additionally: `Backends/SDL` and the Linux
image:

```
docker build -t metalui-portable -f Backends/SDL/linux/Dockerfile Backends/SDL
docker run --rm -v "$PWD":/work -v metalui-sdl-build-variable-height-list:/tmp/build \
  -w /work/Backends/SDL metalui-portable \
  bash -c 'swift build --build-tests --scratch-path /tmp/build && swift test --skip-build --scratch-path /tmp/build'
```

## §8 Human checks (new group, letter settled at merge — provisionally "VL")

On AppKit and on `MetalUISDLDemo`, `METALUI_LIST_DEMO=1`:

- VL1 Scroll the variable list top to bottom and back with the wheel and the
  thumb: rows of three heights, no gaps at the window's edges, no row drawn
  over another.
- VL2 Scroll up quickly from the bottom after resizing the window narrower:
  the row at the top of the viewport stays put while rows above it re-measure
  (no jump), the thumb may move.
- VL3 "Jump to row 250": row 250 lands at the top and stays there over the
  next frames.
- VL4 Click, ⌘-click, ⇧-click and ⇧↓ select as in the controls demo's list;
  ↓ past the viewport's bottom reveals the lead row fully.
- VL5 Resize the window width continuously: text rows re-wrap, the top row
  keeps its place.

## §9 Deferred (`VL-L`)

A splice API (owner none); a probe arm for a *realised* row above the viewport changing height (`VL-N`; owner none — needed before any divergence is claimed for `VL-G` items 1–2); `defaultMinListRowHeight`/insets (div 145, owner
none); re-measuring off-screen rows whose datum changed (owner none; SwiftUI
does not, A1/A2/A4); a lazy cold frame (`MP-I`, div 124, owner none);
horizontal variable lists and lazy stacks/grids (stage G2, owner none);
separators, sections, swipe actions, `.listStyle` (owner none).

## §10 MUST-NOT-MOVE accounting

`List` windowing moves **only** through `VL-F`/`VL-G`/`VL-H` and only for the
new spelling (`VL-I` keeps the uniform path byte-identical in behaviour).
TB-AH, identity, the seven slots, hit testing, accessibility, animation,
focus, `Deferred`, text input: unmoved (`VL-J`); the lanes' full unfiltered
runs are the evidence. Migration note: `VL-I`'s (a variable list's
`style.size.height` is `.auto`), in `docs/migration.md` by lane 3.
