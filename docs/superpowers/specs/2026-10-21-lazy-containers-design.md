# Lazy containers - design (item L1)

`LazyVStack`, `LazyHStack`, `LazyVGrid`, `LazyHGrid` and `GridItem`: SwiftUI's spellings, windowed against the enclosing
scroller, on the proposal path. Branch `feat/lazy-containers` from `1bdead8d`. Rulings: `../2026-10-21-lazy-containers-decisions.md`
(prefix `LZ-`). Record: `../../record/134-lazy-containers.md` (written at the Record phase). Probe:
`../../probes/swiftui-lazy-containers.swift` (recorded output in its header; extends `swiftui-lazy-grid-scope.swift` LZ0-LZ7,
`swiftui-lifecycle.swift` S2, `swiftui-data-and-scrolling.swift` L2 and T10). Reserved divergence labels 635-644: this design takes
**635, 636, 637** (rows added by the lanes, the header's next label left for the merge).

## 1. What the probe settled (the figures are in the probe header)

| claim in the item | reading |
|---|---|
| cross size is "the widest *realised* child" | **Refuted.** With a cross proposal the lazy stack answers the proposal (A1, A5); at nil it answers the **first** child's (A3, A3b, A3d), not the widest and not the smallest. Main axis is content, not greedy (A1 height 40 at a 200 proposal). |
| outside a ScrollView | A lazy stack outside any scroller realises everything (A1-A9 lay out every child) and sizes as above. |
| spacing default | 8 between views, as `VStack` (A2 = A2c); beside text SwiftUI is font-derived and MetalUI's 8 is the existing divergence 51 (A10). |
| realisation | On screen only, no margin (R1: 10 of 1000, 100...109 after a scroll, 20 built in all); the other axis of a scroller is **not** windowed (R5). |
| extent of unrealised children | the measured ones' mean (R4: 20000, not 20100; G2: 15000). |
| state of a scrolled-out child | **retained** (S1: one serial across a 4000pt round trip). |
| `GridItem` | fixed exact; flexible = min-first then equal share clamped to the maximum with no giveback (C4, C6, C15); adaptive `n = floor((rest + s)/(min + s))` (C1-C3, C16, C17); item `spacing` is the gap after its column (C7); tracks aligned in the proposal by `alignment:` (C8); `max(proposal, tracks)` wide (C5); row height = tallest cell (C10); nil width: first row's cells (LZ4), adaptive one column (C12); a ForEach element of two views is **two cells** (C14). |
| `pinnedViews` | pinned header held at the viewport top (H1) but the control arm is broken (H0): unproven. **Not built** (LZ-N). |

## 2. Public API (class A rows in `closeout-inventory-map.tsv`, a doc comment on each)

```swift
public struct LazyVStack<Content: ProposalElementGroup>: Element {
    public init(alignment: HorizontalAlignment = .center, spacing: Pixels? = nil,
                @ProposalContentBuilder content: () -> Content)
}
public struct LazyHStack<Content: ProposalElementGroup>: Element {
    public init(alignment: VerticalAlignment = .center, spacing: Pixels? = nil,
                @ProposalContentBuilder content: () -> Content)
}
public struct GridItem: Sendable, Hashable {
    public enum Size: Sendable, Hashable {
        case fixed(Pixels)
        case flexible(minimum: Pixels = Pixels(10), maximum: Pixels = Pixels(Float.infinity))
        case adaptive(minimum: Pixels, maximum: Pixels = Pixels(Float.infinity))
    }
    public var size: Size
    public var spacing: Pixels?            // the gap after this item's column/row; nil = 8
    public var alignment: ProposalAlignment // the cell inside its track; default .center
    public init(_ size: Size = .flexible(), spacing: Pixels? = nil, alignment: ProposalAlignment = .center)
}
public struct LazyVGrid<Content: ProposalElementGroup>: Element {
    public init(columns: [GridItem], alignment: HorizontalAlignment = .center, spacing: Pixels? = nil,
                @ProposalContentBuilder content: () -> Content)
}
public struct LazyHGrid<Content: ProposalElementGroup>: Element {
    public init(rows: [GridItem], alignment: VerticalAlignment = .center, spacing: Pixels? = nil,
                @ProposalContentBuilder content: () -> Content)
}
```

All four are `ProposalElement`s like `VStack` (`requestProposalLayout`, one `ProposalNodeID`), take the proposal `.padding`/`.frame`/
`.background` chain unchanged and add **no** public member beyond the above. **No `pinnedViews:` parameter and no `Section`** (LZ-N; a
typecheck guard pins the absence). A `GridItem` is a MetalUI type (lengths are `Pixels`, alignment is the nine-case
`ProposalAlignment` as `ZStack`'s); name clash with SwiftUI's own only where a file imports both.
One public `MetalUITesting` read-back: `FrameWork.lazyUnitsRealized`, `lazyLinesRealized`, `lazyUnbounded` (class M, LZ-I).

## 3. Mechanism

### 3.1 Units (LZ-B)

A lazy container's content is a **unit source**: an ordered list of *units*, each realised on demand.

- `ForEach` over proposal content: one unit per element (`unitID` = the element's `Hashable` id, as `FI-`).
- A `ProposalElement` leaf (`Text`, `HStack`, a proposal `Component`, ...): one **static** unit.
- `Pair` concatenates its halves; `EmptyGroup` has none.
- **Anything else** (`if` / `switch` / `for` members, `LegacyContent`, a `ForEach` of legacy rows) makes the container **eager**:
  it realises every unit every frame, exactly as a `VStack` would, and counts `lazyUnbounded` (divergence 636).
- A unit's nodes are the nodes its content registers: 1 usually; **0** (adds no extent and no spacing, A9); **>1** in a stack
  (laid out in sequence with the container's spacing, A8) and in a grid (**one cell**, a vertical stack, divergence 635).

Internal protocol (`package`-level, `@MainActor`, new file `LazyUnits.swift`; **`ForEach.swift` and `ElementGroup.swift` are not
edited**: the conformances are extensions in the new file reading `ForEach.data/content/idKeyPath` and `Pair.first/second`, all
internal):

```swift
@MainActor protocol LazyUnitSource {
    var lazyUnitCount: Int { get }                 // O(1): data.count; Pair sums its halves
    var lazyCursorSpan: Int { get }                // cursor slots the member consumes (ForEach 1, leaf 1, Pair sum)
    func lazyUnitID(_ unit: Int) -> AnyHashable    // ForEach id; StaticUnitKey(ordinal) for a leaf
    mutating func realizeLazyUnit(_ unit: Int, under parent: GlobalElementID?, cursorBase: Int,
                                  pass: inout LayoutPass) -> LazyUnitBox
}
/// What a realised unit hands to prepaint and paint: its nodes, and its two later phases closed over the unit's own
/// mutable content and layout (`ForEach.Member`'s shape, type-erased because the realised set is a window).
final class LazyUnitBox { let unit: Int; let id: AnyHashable; var nodes: [ProposalNodeID]
                          var prepaint: (inout PrepaintPass) -> Void; var paint: (inout PaintPass) -> Void }
```

`ForEach`'s realisation derives the element scope exactly as `produceElements` does (`GlobalElementID.child(of: slot, at: ordinal, name:
ElementID(name:key:))`, `IdentityKey` for a non-injective id): **identity is the ForEach's** (`FI-A`, `FI-B`), so `@State`,
focus and accessibility ids of a lazy child are what the same element would have in a `VStack`'s `ForEach` below the container's id
level. It does **not** call `noteLoop` (that is the reset a window must not trigger) and calls `noteWindowedParent(slot)`
(LZ-H).

### 3.2 Window planning (LZ-C, LZ-E, LZ-G): one core, both shapes

New file `LazyCore.swift` holds everything the stacks and the grids share: **lines**. A stack's line is one unit; a grid's line is a
row (`unitsPerLine` cells). The planner mirrors `List.variableWindow` / `rebuildKeepingAnchor` / `prepaintVariableRows` step for step
(VL-E to VL-H, VL-O, VL-P) over the **same `RowExtentIndex`** (class unchanged, `RowExtentIndex<AnyHashable>`; the id of a line is
its first unit's id), and **does not edit `List.swift`** (cost named in LZ-C).

- **Bounded** = a scroll context whose axis equals the container's axis and whose viewport extent is > 0. Window = `anchor - 2 ..<
  index(containing: bottom) + 1 + 2` lines, anchor = the line holding the clamped `top` (the scroller's offset minus the
  container's stored origin, `DD-F`). Same overscan as `List` (2, divergence 637).
- **Cold** (a scroller whose viewport is not yet known, `ScrollContext.viewportExtent == 0`): realise the first
  `LazyWindow.coldLines = 32` lines, never all of them (`List` realises all, `MP-I`); prepaint asks for one more frame when the
  real viewport needs more (`requestAnotherFrame`, `DD-F` item 3).
- **Unbounded** (no scroller, the other axis, a `Deferred`, an eager fallback): every line, each measured, `lazyUnbounded += 1`.
- **State**: `LazyOrigin` (offset, `extents: AnyObject?`, anchor), stored at the container's own id through the compared
  `withState(_:initial:unchanged:)` (`RW-I`), created in prepaint only inside a bounded scroller, never through `write`, so it
  raises no `isDirty`. It is `ListOrigin`'s twin (a separate type, so `ListOrigin` does not move).
- **Prepaint** (in this order, as `VL-`): store origin; forget heights on a cross-width change; record each realised line's
  measured extent under its id (`extent + spacing`, 0 for a line with no node); anchor correction through
  `Frame.noteScrollAnchorAdjustment(scroller:delta:)`; staleness (`requestAnotherFrame` when the window the updated index gives is not
  contained in the built one); `scrollTo` resolution (LZ-O).
- **Data change** rebuilds the index by id (`rebuild(ids:)`, `O(n)` on a count change or a realised id that differs from the recorded
  one) and keeps the anchor by id (`VL-G` item 3).
- **Duplicate ids** dedupe **within the realised window only** (first wins; the rest are not produced): a whole-data dedupe is `O(n)`
  per frame (LZ-G, cost named).

### 3.3 `LazyStack` (lane 1)

`LazyStackLayout: ProposalLayout` (not `Hashable`: it taints exactly its ancestors for the layout memo, `IV-`, as
`VariableRowsLayout`; no registrar changes) over the realised nodes, parameters `axis`, `alignment`, `spacing: Double`
(`nil` -> `ProposalSpacing.platformDefault`), `unitNodeCounts: [Int]`, `anchorSlot`, `anchorOffset`, `trailingExtent`.

- **Size** (probe A): cross = the proposal when there is one, else the first realised unit's first node's answer at `(nil, nil)`;
  main = `anchorOffset + sum of realised units from the anchor (extent + spacing) + trailingExtent - spacing`, floored at 0
  (a unit with no node adds nothing, no spacing).
- **Placement**: the anchor unit at `bounds.main + anchorOffset`, later units below/after it, earlier ones above/before it (so a
  re-measured unit above the anchor moves only units above it, `VL-G` item 1); within a unit its nodes in sequence with `spacing`;
  each node proposed `(cross, nil)` (vertical) and aligned across by `alignment`; a node wider than the cross overflows centred (A5).
- Outside a scroller it is `VStack`'s answer on the main axis and the proposal / first-child answer on the cross axis (A1-A3).

### 3.4 `LazyGrid` (lane 2)

`GridTrackSolver` (pure, Foundation-free, in **`MetalUILayout`**, `package`, so Linux runs it in `MetalUILayoutTests`) resolves
`[GridItem]` and the available cross extent to `[Track(size, gapAfter)]` and the grid's origin, per the probe's reading (LZ-K). The
container builds a `columnCount` at **build time** from the stored cross extent (`LazyOrigin.crossExtent`, last frame's, as the
viewport is) - for fixed/flexible items it is static and always right, for an adaptive item it is `floor`-derived from last
frame's width - and `LazyGridLayout` resolves the real tracks from its bounds at layout; when the resolved count differs from
the built one prepaint asks for one more frame (LZ-L). Rows are lines: `unitsPerLine = columnCount`; a row's extent is its tallest
realised cell. `LazyHGrid` is the same with the axes swapped (rows are the tracks, columns the lines).

## 4. Files and lanes

**Lane 1 (first; the core and the stacks).** New: `Sources/MetalUI/LazyUnits.swift`, `LazyCore.swift`, `LazyStack.swift`;
tests `Tests/MetalUITests/LazyStackLayoutTests.swift`, `Tests/MetalUITestingTests/LazyStackWindowTests.swift`,
`LazyStackGuards.swift`; probe (done). **Lane 2 (after lane 1's core is committed; the grids).** New:
`Sources/MetalUILayout/GridTrackSolver.swift`, `Sources/MetalUI/GridItem.swift`, `LazyGrid.swift`; tests
`Tests/MetalUILayoutTests/GridTrackSolverTests.swift`, `Tests/MetalUITests/LazyGridLayoutTests.swift`,
`Tests/MetalUITestingTests/LazyGridWindowTests.swift`, `LazyGridGuards.swift`. Lane 2 reads lane 1's `LazyCore` API
(`LazyLinePlanner`, `LazyUnitSource`, `LazyOrigin`, `LazyWork`) and edits none of lane 1's files except to add a `unitsPerLine`
use the planner already has. The demo (`Sources/MetalUIDemoContent/LazyContainersDemo.swift`, `METALUI_LAZY_DEMO=1`, one function
per section for the 1 MB stack), the guide (`docs/guides/layout.md` + `Tests/MetalUITestingTests/GuideMirrorsLazy.swift`) and the
human-checks group `LZ` are lane 2's last step.

**Shared lines touched (the only ones; each a few lines):** `Sources/MetalUI/Frame.swift` (one stored property `lazyWork`, beside
`forEachIdentityWork` at line 151, and its reset); `Sources/MetalUI/TestingHooks.swift` (its read-back);
`Sources/MetalUITesting/FrameWork.swift` (three fields); `Tests/MetalUITests/RetainedSubtreeInternalTests.swift` (the
`"lazyWork": .buildOnly` classification at line 47); the state-write-site classification test (`everyStateWriteSiteIsClassified`, a
row per new file) and `everyNamingSiteStartsAReturningNameFresh` (an arm for the lazy unit scope); `docs/probes/
closeout-inventory-map.tsv` and `closeout-public-api.tsv` (rows); `docs/divergences.md` (635-637). **Not touched:** `ForEach.swift`,
`ElementGroup.swift`, `List*.swift`, `StateTable.swift`, `Retained*.swift`, `LayoutTree.swift`, `Window.swift`, any shader, any platform
file, `Backends/SDL`. No new registrar parameter, no new `LayoutTree` node kind, no `Handlers` member, no `PlatformWindow`
requirement.

## 5. Tests (name, red before, the mutation that must redden it)

Every test is red on arrival because the types do not compile; the **mutation** column is the real instrument (each on the
declaration the test is named for, restored from a copy, full unfiltered suite, the reddened tests named in the record).

Lane 1, layout facts (native arms with hand-derived literals, `LayoutDifferential`; children 30x10, 100x20, 50x10 at 200x200):

| # | test | asserts | mutation |
|---|---|---|---|
| 1.1 | `aLazyVStackOutsideAScrollerPlacesEveryChildAndAnswersTheProposalAcross` | size 200x40, a (85,0), b (50,10), c (75,30); `spacing: nil` gives 8 (size 200x56) | spacing default 8 -> 0; cross answer = widest child |
| 1.2 | `aLazyVStackAnswersTheFirstChildAtANilCrossProposal` | nil: 30x40 (a first), 100x40 for 100/30/50, 50x40 for 50/100/30; width 80 proposal: 80x48 with b at -10 | first -> widest; first -> last |
| 1.3 | `aLazyHStackIsTheSameOnTheOtherAxis` | nil 180x10 with b at y -5; 200x200: 180x200 | axis swap in the cross answer |
| 1.4 | `leadingAndTrailingAlignmentPlaceTheChildrenAcross` | A4 (0,0)(0,10)(0,30); A4t (170,0)(100,10)(150,30) | alignment ignored |
| 1.5 | `aForEachElementOfSeveralViewsIsSeveralViewsInSequenceAndOneOfNoneAddsNoSpacing` | A8 b at y 10; A9 c at 16 (spacing 6) | unit extent counts a trailing spacing for an empty unit |

Lane 1, work and behaviour (harness, `FrameWork`; a work pin counts, never times; the ratio is against an eager `VStack` stand-in of
the same 10 000 rows):

| # | test | asserts | mutation |
|---|---|---|---|
| 2.1 | `aTenThousandChildLazyVStackRealizesOnlyTheWindow` | warm frame: `lazyUnitsRealized == 13` (20pt rows, 200pt viewport: `index(containing: 200) = 10`, `+1 +2`); the eager stand-in realises 10 000; ratio asserted >= 500 | window upper bound `+1 +overscan` removed or widened to `count` |
| 2.2 | `theColdFrameRealizesABoundedSliceThenTheViewportWindow` | frame 1 `lazyUnitsRealized == 32`, then settled 13 | cold slice `32 -> count` |
| 2.3 | `aWarmFrameRealizesTheSameWindowAndRebuildsNothing` | `lazyUnitsRealized` equal frame to frame, `RowExtentIndex` rebuilds 0 | rebuild every frame |
| 2.4 | `scrollingRealizesTheNewWindowAndTheAccessibilityTreeFollows` | wheel to 2000: realised rows 98...112-ish by the literal derived in the test; a11y tree holds exactly the realised rows | window not recomputed on scroll |
| 2.5 | `variableChildExtentsAreMeasuredAndUnrealisedOnesCountAsTheMean` | 1000 rows of 20 with one 120 tall unrealised: content extent 20 000 (R4); realised becomes 20 100 after it is | estimate -> fallback 24 |
| 2.6 | `theTopChildStaysPutWhenAChildAboveItIsMeasured` | `scrollAnchorAdjustments` equals the delta; the on-screen top row's y unchanged | anchor correction removed |
| 2.7 | `aScrolledOutChildKeepsItsStateAndTheTableBoundsIt` | state serial equal after a round trip (S1); lost once > 256 entries (`TB-AH`) | `noteWindowedParent` removed; `noteLoop` added |
| 2.8 | `aDataChangeKeepsTheAnchorByID` | insert 3 rows above the anchor: the anchor row keeps its screen y | rebuild by position |
| 2.9 | `duplicateIDsInTheWindowAreProducedOnce` | one node for two equal ids in the window | no dedupe (CN-L trap or doubled node) |
| 2.10 | `aLazyStackInAScrollerOfTheOtherAxisRealizesEverythingAndCountsIt` | R5: all realised, `lazyUnbounded == 1` | axis test dropped |
| 2.11 | `anIfOrForMemberMakesTheContainerEagerAndCounted` | all units realised, `lazyUnbounded >= 1`, layout equals a `VStack`'s (divergence 636) | fallback removed (windowed over a conditional) |
| 2.12 | `aRealizedChildsHitTestingFocusAndButtonsAreOrdinary` | click a `Button` in a realised row fires; Tab reaches it; an unrealised row has no hitbox | hit registration skipped for units |
| 2.13 | `anEquatableChildInsideALazyStackIsSkippedAndRetained` | `contentSkips` rises on a warm frame; under `METALUI_VERIFY_RETAINED=1` no trap | unit box rebuilt each frame defeating the memo key |
| 2.14 | `scrollToAnUnrealisedElementReachesItInAtMostTwoResolutions` | T10-shaped: target lands in the viewport, `scrollResolutions <= 2` | refinement carry removed |
| 2.15 | `theOverscanAppearsBeforeTheRowsAreOnScreen` | `onAppear` fires for the 2 rows each side (divergence 637 pin, `13` appeared vs 10 on screen) | overscan 2 -> 0 |
| G.1 | `lazyInitHasNoPinnedViewsParameter` (plain-import `typecheckFile`) | `LazyVStack(pinnedViews: ...)` does not compile | add the parameter |
| G.2 | `theLazyCoreIsUnreachableOutsideTheModule` (plain-import guard) | `LazyUnitSource`, `LazyOrigin`, `LazyUnitBox` do not typecheck outside | make one `public` |

Lane 2:

| # | test | asserts | mutation |
|---|---|---|---|
| 3.1 | `gridTracksFollowTheProbe` (`MetalUILayoutTests`, Linux) | C1 7 columns of 21.71 at x origin 0; C2 3 of 61.33; C3 3 of 53.33; C4 67/67->40 total 173 origin 13.5; C5 248 origin 0; C6 96, 30; C15 150 and 42; C16 70 centred in 100; C17 n=4 of 32; C7 gaps 20, 0 | min-first pass removed; max clamp gives back; adaptive `floor` -> `ceil` |
| 3.2 | `aLazyVGridPlacesCellsInTheirTracksByAlignment` | C8 leading (0, 38), centre (76, 114); C9 topLeading / bottomTrailing at 66 / 124; C10 row 1 is 30 tall and c3 at y 28; width `max(proposal, tracks)` (C5 248) | cell alignment ignored; origin always 0 |
| 3.3 | `aLazyHGridIsTheSameOnTheOtherAxis` | C11 48x100, c0 (0,18), c3 (28,72) | axis swap |
| 3.4 | `aNilWidthTakesTheFirstRowAndAnAdaptiveItemMakesOneColumn` | LZ4 58; C12 10x64; C13 0x0 | first row -> all realised cells |
| 3.5 | `aForEachElementOfSeveralViewsIsOneGridCell` | C14 as MetalUI's own answer: one cell holding a vertical stack (divergence 635) | cell = node |
| 3.6 | `aTenThousandCellLazyVGridRealizesOnlyTheWindow` | `lazyLinesRealized` = viewport rows + 2 + 2, `lazyUnitsRealized = lines * columns`; the eager `Grid` stand-in realises 10 000; ratio asserted | window in cells not lines |
| 3.7 | `rowsAreAsTallAsTheirTallestRealizedCellAndUnrealizedRowsCountAsTheMean` | G2: 15 000 | mean -> 0 |
| 3.8 | `aStaleAdaptiveWidthIsCorrectedOnTheNextFrame` | first frame builds 1 column (no stored width), then the real count within one more frame | mismatch detection removed |
| 3.9 | `scrollingAGridRealizesTheNewRowsAndAScrolledOutCellKeepsItsState` | rows around the scroll offset; state serial equal on return | as 2.7 |
| 3.10 | `aLazyGridCellIsAnOrdinaryOccurrence` | click, focus, `.equatable()` skip in a cell | as 2.12/2.13 |
| G.3 | `gridItemAndTheLazyGridsHaveSwiftUIsSpellings` (typecheck) | `GridItem(.adaptive(minimum: 40))`, `GridItem(.flexible(minimum:maximum:), spacing:, alignment:)`, `LazyVGrid(columns:alignment:spacing:)`, `LazyHGrid(rows:...)` compile | rename an argument |

Both lanes: `everyStateWriteSiteIsClassified` gains the new files; `everyNamingSiteStartsAReturningNameFresh` gains the unit scope arm
(mutation: drop `noteNamed` there reddens it); the fourteen demo images stay 0 px against `1bdead8d` (the demo section is
behind `METALUI_LAZY_DEMO`); `DemoFrameDeterminismTests` `Expected.swift` is not edited; the inventory and undocumented scripts print
nothing; the census is re-recorded.

## 6. Demo, guide, human checks

- **Demo** `METALUI_LAZY_DEMO=1` (`Sources/MetalUIDemoContent/LazyContainersDemo.swift`; each section its own function, composed
  by a generic composer, for the 1 MB Windows stack - `everyProductionTreeBuildsOnAOneMegabyteThread` gains the entry): a header
  label showing `FrameWork`-style counters is not available outside tests, so each section shows its own `onAppear`-fed live count:
  (1) 10 000 variable-height rows in a `LazyVStack` (a counter of rows currently realised stays near 13-20 while the scroller moves);
  (2) a 10 000-cell `LazyVGrid` with `GridItem(.adaptive(minimum: 60))` that re-flows on a window resize; (3) a `LazyHStack` carousel;
  (4) a `LazyHGrid` of fixed rows. Expectation: the counters never exceed viewport + overscan, scrolling is smooth, variable rows
  do not jump when measured.
- **Guide** `docs/guides/layout.md`: "How do I show ten thousand rows?" - one `swift` block (`ScrollView { LazyVStack { ForEach } }`)
  and one for a `LazyVGrid`, each copied by hand into `GuideMirrorsLazy.swift` (`DG-C`, `DG-D`), with a `(pin: ...)` per behaviour
  word.
- **Human checks, new group `LZ`** (`docs/verification/human-checks.md`; not run - an agent cannot): LZ1 fast-scroll of variable rows
  does not jump or flash; LZ2 an adaptive grid's first frame in a real window (the stale-width frame, LZ-L) is not visibly a
  single column; LZ3 VoiceOver reads realised rows and reaches an off-screen row only after scrolling (LZ-J); LZ4 resizing the window
  re-flows the grid with no blank band; LZ5 the same on SDL (Linux, Windows) and a wheel over a lazy stack inside a `ScrollView`.

## 7. Scope: deferred, with owner

| not built | why | owner |
|---|---|---|
| `pinnedViews:` and `Section` | no `Section` exists; pinning needs a paint-time offset of one realised unit, hitboxes and accessibility frames following it; the probe's pinned arm has a broken control (H0) | follow-up L2 (a `Section` item) |
| windowed `if` / `switch` / `for` members | each owes its structural notes (`noteAbsent`, `noteProduced`, animation notes) every frame whether or not realised: eager fallback, counted, value-identical to `VStack` (divergence 636) | follow-up L1b |
| extracting `List`'s planner so both share it | `List` windowing must not move in this item; the glue is mirrored (LZ-C) | follow-up, after both are green |
| whole-data duplicate dedupe | `O(n)` per frame (LZ-G) | none (a ruling) |
| transitions on lazy children, `.id` scroll keys beyond ForEach ids, `logicalIndex` for accessibility, a `Spacer` zero-spacing edge inside a lazy stack | none probed; each is a `List` limitation too | named in the record |
| mixed adaptive + flexible / two adaptive items | unprobed; MetalUI's own equal-share ruling, no divergence claimed (LZ-K) | a later probe |
| `drawText` over a lazy surface, GPU surfaces inside a lazy cell | `GT-F`, unchanged | C14 close-out |
