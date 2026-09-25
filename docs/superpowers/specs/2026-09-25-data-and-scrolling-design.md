# Data and scrolling — plan task 10, part 1 (design)

Branch `feat/data-and-scrolling` from `e7bc2e7`. Rulings `DD-A`…`DD-J` in
[`../2026-09-25-data-and-scrolling-decisions.md`](../2026-09-25-data-and-scrolling-decisions.md);
probe [`docs/probes/swiftui-data-and-scrolling.swift`](../../probes/swiftui-data-and-scrolling.swift)
(arms cited as F*, B*, L*, W*, T*, P*, I*, K2); record `docs/record/57-data-and-scrolling.md`
(written by the Record phase).

**Status: DESIGNED.** Part 1 of plan task 10 — `ForEach`, `Binding`, the
`List`/`ScrollView` limitations, programmatic scrolling and indicators. Part 2
(common controls, selection, and everything `DD-J` names) is the next run; the
plan's task 10 box stays unticked.

## 1. Baseline

Measured in this worktree at `e7bc2e7` by the design session: `swift build
--build-system native --build-tests` (0 `error:`, the one `warning:` is
SwiftPM's deprecation notice), then `swift test --build-system native
--no-parallel` → **`Test run with 1506 tests in 3 suites passed`**, the guards
ran (`FR-J no-argument frame: succeeded=true`). No goldens remain (stage 7a).
`grep -c canTypecheck` over `Tests/MetalUITests/*.swift` reads **88** hits in
19 files (the record's "90 guards" figure counts by record §56's method; a lane
reports its guard delta **by file**, below, not a new total).

## 2. The audit table

Every item addressed to plan task 10 (collected by grep, `DD-A`) and every
part-1 concept, with the probe arm that answers SwiftUI's side, MetalUI's
answer at `e7bc2e7`, the verdict and where it is done.

| concept | SwiftUI (probe arm) | MetalUI at `e7bc2e7` | verdict | run |
|---|---|---|---|---|
| `ForEach` over Identifiable / `id:` / a range | exists (SDK; K `Shapes`) | absent; `for` loops only | **add**, `DD-B` | part 1, lane 1 |
| state follows the id through a reorder | kept (F1) | — (a `for` item keeps state only with `.id`) | match, `DD-B` | lane 1 |
| an element dropped at the tail, returning | **new** (F2, F3, F8; V10) | `for` loop: **retained** (C2.4b reads 2), divergence 74 | **fix**, 74 retires, `DD-C` | lane 1 |
| a middle element removed | others kept (F6) | — | match, `DD-B`/`DD-C` | lane 1 |
| ids that are indices keep state with the position | pos0 kept (F5) | — | match (the key is the id) | lane 1 |
| a `ForEach` is one slot | trailing sibling kept (F9) | `for` loop: one slot (`ID-B`) | match | lane 1 |
| an id moved to another `ForEach` | new (F10) | — | match (scoped to the loop slot) | lane 1 |
| duplicate ids | only the first element's content evaluated (F7) | — | match, `DD-B` item 5 | lane 1 |
| `for` in a builder | **rejected by the compiler** (K2) | accepted (`ID-B`) | kept as MetalUI's extension; resets like `ForEach(0..<n)`, `DD-C` | lane 1 |
| a `List` row removed from the data and re-added | **kept** (F12) | kept (`TB-AH`; rows exempt, `ID-R` item 4) | match, unchanged | — |
| `Binding` via `$state`, through `@Binding` hops | writes the owner (B1) | no value `Binding`; `Binding` is `KeyBinding`'s deprecated alias | **add**, `DD-D` | lane 2 |
| `.constant` | ignores writes (B2) | — | match | lane 2 |
| key-path derived binding | one field written (B3) | — | match | lane 2 |
| `init(get:set:)` | setter once per write (B4) | — | match (getter count unspecified) | lane 2 |
| optional initialisers | nil over nil; lifted ignores a nil write (B5) | — | match | lane 2 |
| a kept binding | live reads and writes (B6) | — | match | lane 2 |
| `Binding`'s isolation | nonisolated, `Sendable` (SDK) | — | **divergence 78, added**: `@MainActor`, `DD-D` item 4 | lane 2 |
| the `KeyBinding` alias | — | deprecated alias + guard | **deleted** (`EV-N`), `DD-D` item 6 | lane 2 |
| `TextField(_:text:)`, `TextEditor(text:)` | take `Binding<String>` (K `Shapes`) | controlled only (`TI-`) | **add**, `DD-E` | lane 2 |
| a `List` below a header in a `ScrollView` | SwiftUI's `List` there is **0 tall, blank** (L1); the ordinary shape, `LazyVStack`, realises the rows on screen, 0…3 (L2) | builds rows **8…16**, all off screen (DD14) — divergence 14 | **fix** to L2's answer, 14 retires, `DD-F` | lane 3 |
| a grown viewport with no input | — (internal) | stale window **persists**, no frame drawn (DD13) — divergence 13's effect | **fix**: one more frame when stale; 13 amended, kept, `DD-F` | lane 3 |
| `List` scrolling itself, greedy (K6) | L0 (rows 0…4 in 112), L1 | needs an enclosing `ScrollView`, answers `count × rowHeight` | kept; **part 2** (`DD-J`) | part 2 |
| `ProposalScrollView` publishing a `ScrollContext` | — | none (`LR-BF`) | joins the prepaint scroller stack; layout context still unread → lazy stacks, `DD-I` | lane 3 |
| `ProposalScrollView`'s animation | — | nothing to animate | closed as vacuous; animated offset → task 13, `DD-I` | — |
| wheel under `.disabled` | **unmeasured** (W0 control failed; W1 hit chain = W0) | still scrolls (pinned) | kept; human look owed, `DD-I` | lane 3 (doc only) |
| `scrollTo(_:anchor:)` with an anchor | `minY − a.y × (vp − h)`: 300/265/230/282.5 (T1–T3, T9), horizontal 300 (T11) | absent | **add**, `DD-G` | lane 3 |
| `scrollTo` with no anchor | least distance: 230 / 0 / 60 (T4–T6) | — | match | lane 3 |
| clamped; unknown id | 500 (T7); no-op (T8) | — | match | lane 3 |
| unrealised rows | LazyVStack 4500 (T10), `List` (T15) | — | match (`List` by index) | lane 3 |
| a two-member `ForEach` element | first member (T12/T12b: 330) | — | match | lane 3 |
| any `.id` view | target (T13) | — | match | lane 3 |
| nested scrollers | nearest only (T14) | — | match | lane 3 |
| `scrollPosition(id:)` | set → least distance (P1); no report on a platform scroll (P2) | absent | **part 2** (`DD-J`) | part 2 |
| scroll position | — | `ScrollState.offset` in `StateTable` | specified, `DD-G` item 6 | lane 3 (doc) |
| indicators `.automatic`/`.visible` | identical `NSScrollView` state (I1, I2) | `.automatic` only | **add `.visible`**, `DD-H` | lane 3 |
| indicators `.hidden`/`.never`/`showsIndicators: false` | scroller removed (I3–I5) | `.hidden` only | **add `.never`**, `DD-H` | lane 3 |
| two-axis scrolling, divergence 54 | — | one axis; cross axis from parent | **part 2** (`DD-J`) | part 2 |
| selection, common controls, divergences 32, 76 | — | — | **part 2** (`DD-J`) | part 2 |

## 3. Public API (permanent — each spelling ruled against SwiftUI's SDK interface)

```swift
// Lane 1 — Sources/MetalUI/ForEach.swift (DD-B)
public struct ForEach<Data: RandomAccessCollection, ID: Hashable, Content: ElementGroup>: ElementGroup {
    public var data: Data
    public var content: (Data.Element) -> Content
    public init(_ data: Data, id: KeyPath<Data.Element, ID>,
                @ElementBuilder content: @escaping (Data.Element) -> Content)
}
extension ForEach where ID == Data.Element.ID, Data.Element: Identifiable {
    public init(_ data: Data, @ElementBuilder content: @escaping (Data.Element) -> Content)
}
extension ForEach where Data == Range<Int>, ID == Int {
    public init(_ data: Range<Int>, @ElementBuilder content: @escaping (Int) -> Content)
}
extension ForEach: ProposalElementGroup where Content: ProposalElementGroup {}

// Lane 2 — Sources/MetalUI/Binding.swift, State.swift, TextField.swift, TextEditor.swift (DD-D, DD-E)
@MainActor @propertyWrapper @dynamicMemberLookup
public struct Binding<Value> {
    public init(get: @escaping @MainActor () -> Value, set: @escaping @MainActor (Value) -> Void)
    public static func constant(_ value: Value) -> Binding<Value>
    public var wrappedValue: Value { get nonmutating set }
    public var projectedValue: Binding<Value> { get }
    public init(projectedValue: Binding<Value>)
    public subscript<Subject>(dynamicMember keyPath: WritableKeyPath<Value, Subject>) -> Binding<Subject> { get }
    public init<V>(_ base: Binding<V>) where Value == V?
    public init?(_ base: Binding<Value?>)
}
extension State { public var projectedValue: Binding<Value> { get } }
extension TextField { public init(_ placeholder: String, text: Binding<String>) }
extension TextEditor { public init(_ placeholder: String = "", text: Binding<String>) }
// deleted: `public typealias Binding = KeyBinding` (Keymap.swift)

// Lane 3 — ScrollViewReader.swift, UnitPoint.swift, ScrollView.swift (DD-G, DD-H)
public struct ScrollViewReader<Content: ElementGroup>: ElementGroup {
    public init(@ElementBuilder content: @escaping (ScrollViewProxy) -> Content)
}
extension ScrollViewReader: ProposalElementGroup where Content: ProposalElementGroup {}
@MainActor public struct ScrollViewProxy {          // no public init
    public func scrollTo<ID: Hashable>(_ id: ID, anchor: UnitPoint? = nil)
}
public struct UnitPoint: Hashable, Sendable {
    public var x: Double
    public var y: Double
    public init(x: Double, y: Double)
    public static let zero, center, leading, trailing, top, bottom,
                      topLeading, topTrailing, bottomLeading, bottomTrailing: UnitPoint
}
public enum ScrollIndicatorVisibility { case automatic, visible, hidden, never }  // + visible, never
```

**`swift package clean` is required** before re-taking counts after lane 3
(new cases on a public enum crossing a module boundary) and is harmless after
lanes 1–2 (new public types, no stored property added to an existing public
type).

## 4. Lanes

Run in the order 1, 2, 3 (lane 3's 3.12 needs lane 1's `ForEach`). Each lane:
tests written first and run red (or, for a test of new API, the named mutation
run against the finished implementation — a test that cannot compile before the
API exists has no red-before run, and the mutation is its proof); commit before
mutating; mutations restored from a copy, the full unfiltered suite after each,
`git status --short` after each, **every reddened test named**. Each NEW
typecheck guard is mutated red once.

### Lane 1 — `ForEach` and loop identity (`DD-B`, `DD-C`)

**Files.** `Sources/MetalUI/ForEach.swift` (new; the untyped entry and the
typed `ProposalElementGroup` copy), `Sources/MetalUI/ElementGroup.swift`
(`ArrayGroup.requestGroupLayout` notes its loop), `Sources/MetalUI/ProposalElementGroup.swift`
(the typed `ArrayGroup` copy notes its loop), `Sources/MetalUI/StateTable.swift`
(`noteLoop(_:extent:)`, the sweep's loop rule, a work counter). Tests:
`Tests/MetalUITests/ForEachTests.swift` (new),
`Tests/MetalUITests/ForEachCompileGuards.swift` (new),
`Tests/MetalUITests/ConditionalIdentityTests.swift` (C2.4b's arm inverted; its
doc and `ArrayGroup`'s doc updated).

**Tests** (state read with the existing `CountingElement`/`ConditionalCounter`
shapes: a count that steps by 1 per frame, so a retained entry reads more than
1 on a returning element's first frame back):

| # | test | asserts (arm) | red-before / mutation that must redden it |
|---|---|---|---|
| 1.1 | `aForEachKeepsEachElementsStateThroughAReorder` | [a,b] → [b,a]: a and b keep their counts (F1) | **M1a**: the element scope minted `.positional(offset)` instead of the key's name |
| 1.2 | `aForEachElementRemovedAndReAddedStartsFresh` | [a,b], [a], [a,b]: b reads 1, a reads 3 (F2) | **M1b**: `ForEach`'s `noteLoop` call removed (untyped entry) |
| 1.3 | `aForEachOverARangeResetsItsDroppedTail` | `0..<2, 0..<1, 0..<2`: element 1 reads 1 (F3) | M1b |
| 1.4 | `theKeyDecidesWhetherStateFollowsTheValueOrThePosition` | `id: \.self` [b] → [a,b]: b keeps its count (F4); indices as ids: position 0 keeps its count (F5) | M1a (first arm) |
| 1.5 | `aForEachRemovingAMiddleElementKeepsTheOthersState` | [a,b,c] → [a,c]: a, c keep; b re-added reads 1 (F6) | **M1c**: the element scope not noted (`noteNamed` call removed); reddens 1.2 and 1.5 |
| 1.6 | `aForEachIsOneSlotSoTheTrailingSiblingKeepsItsState` | shrink in a `Row` and an `HStack`: the trailing element's id and count unchanged (F9) | **M1d**: `ForEach` consumes no slot of its own (elements threaded through the parent's cursor) |
| 1.7 | `anElementMovedToAnotherForEachStartsFresh` | a moves from the first `ForEach` to the second: reads 1 (F10) | M1c |
| 1.8 | `aForEachDuplicateIDProducesOnlyTheFirstElement` | [x, x]: one node registered, the first element's content only (F7) | **M1e**: the per-frame dedupe removed |
| 1.9 | `aForEachElementOfTwoMembersResetsBothOnReturn` | two members per element, tail shrink and back: both read 1 (F8) | M1b |
| 1.10 | `aForEachInsideAProposalStackPlacesEveryElementAndResetsItsDroppedTail` | typed copy: `HStack { ForEach(…) { Color… } }` places each element; tail shrink and back resets | **M1f**: the typed copy's `noteLoop` removed — reddens this test alone |
| 1.11 | `aShrinkingForLoopLeavesTheTrailingSiblingsStateAlone` (existing; C2.4b arm **inverted**) | `for` n 2 → 1 → 2: `root/0/1` reads **1** (was 2) | **red-before: 2** (the existing pin, measured, DD scratch); **M1g**: `ArrayGroup`'s untyped `noteLoop` removed |
| 1.12 | `aForLoopsNamedIterationDroppedAtTheTailStartsFreshOnReturn` | `for x in xs { C().id(x) }` [a,b], [a], [a,b]: b reads 1 | red-before: 2 (today's retention); **M1h**: the sweep's named-children half removed (positional half kept) |
| 1.13 | `aForLoopInsideAProposalContainerResetsItsDroppedTail` | typed `ArrayGroup` copy, n 2 → 1 → 2 in an `HStack` | red-before: 2; **M1i**: the typed `ArrayGroup` copy's `noteLoop` removed — reddens this test alone |
| 1.14 | `aSurvivingForEachElementsListKeepsItsWindowedRowsState` | a `List` inside a surviving element of a shrinking `ForEach`: a row scrolled out and back keeps its state (`TB-AH`) | **M1j**: the loop rule resets every unmarked entry under the slot, not only departed direct children |
| 1.15 | `aSteadyLoopQueuesNoReset` | a 1000-element `ForEach` and a 1000-iteration `for`, frame 3 unchanged: `subtreeResetScans`, `departedNameResets` and `lastResetScanWork` read 0 (work counters, literals derived before the run) | **M1k**: the positional rule's `previous > extent` written `previous >= extent` |

**Guards** (`ForEachCompileGuards.swift`, `typecheckFile`, plain import — an
external module's view):

| # | guard | mutation that must redden it |
|---|---|---|
| G1.1 | `anExternalModuleCanWriteForEachOverIdentifiableKeyPathAndRangeData` — all three initialisers, in a `Column` and in an `HStack` | the `Range` initialiser made `internal` |
| G1.2 | `aForEachOfLegacyContentDoesNotCompileInsideAProposalStack` — `HStack { ForEach(0..<2) { _ in Box() } }` fails | the `ProposalElementGroup` conformance made unconditional (with a trapping body) |

**Retirement rows**: none (1.11 is an existing test whose assertion changes by
ruling — record it as a changed answer, divergence 74's retirement).
**Guard delta**: +2 (`ForEachCompileGuards` 2).

### Lane 2 — `Binding` (`DD-D`, `DD-E`)

**Files.** `Sources/MetalUI/Binding.swift` (new), `Sources/MetalUI/State.swift`
(`projectedValue`), `Sources/MetalUI/Keymap.swift` (alias and its doc deleted;
`KeyBinding`'s doc no longer promises the deletion), `Sources/MetalUI/TextField.swift`,
`Sources/MetalUI/TextEditor.swift`. Tests: `Tests/MetalUITests/BindingTests.swift`
(new), `Tests/MetalUITests/BindingCompileGuards.swift` (new),
`Tests/MetalUITests/EnvironmentCompileGuards.swift` (the alias guard deleted).

| # | test | asserts (arm) | red-before / mutation |
|---|---|---|---|
| 2.1 | `aStateProjectionWritesTheOwnersStateThroughTwoLevels` | a grandchild's click writes 5 through `@Binding` → `@Binding` → `$n`; the owner reads 5 next frame (B1) | **M2a**: `State.projectedValue`'s setter a no-op |
| 2.2 | `aConstantBindingIgnoresWrites` | `.constant(3)`: write 5, read 3 (B2) | **M2b**: `.constant` stores into a box and reads it back |
| 2.3 | `aKeyPathBindingWritesOneFieldAndLeavesTheOthers` | `$model.name = "b"`: name "b", count 1 (B3) | **M2c**: the dynamic-member setter drops the write |
| 2.4 | `aGetSetBindingCallsTheSetterOncePerWrite` | read 1, write 4, read 4; setter calls 1 (B4) | **M2d**: `wrappedValue`'s setter calls `set` twice |
| 2.5 | `theOptionalBindingInitialisersMatchSwiftUI` | `init?` nil over nil, writes through over 3 → 9; lifted: nil write ignored (2), 6 written (B5) | **M2e**: `init?` returns a binding over nil (falls back to a default) |
| 2.6 | `aKeptBindingReadsAndWritesTheCurrentState` | a `$n` kept from frame 1 reads the state after another handler set 7, and a write of 11 lands (B6) | **M2f**: `projectedValue` captures the value at creation (snapshot getter) |
| 2.7 | `aBindingWrittenFromADispatchedHandlerReachesItsOwnOccurrence` | one element value placed twice, each passing `$n` down; a click in occurrence 0's child moves only occurrence 0's slot (`ID-F`) | **M2g**: the projection writes `box.slotID` instead of `resolvedSlot` |
| 2.8 | `aTextFieldBoundToStateUpdatesItOnEveryEdit` | a focused `TextField("p", text: $s)` in a `Window`: two `.textInput` edits between frames compose; `s == "ab"` and the field shows it; bound to `.constant("x")` it keeps "x" | **M2h**: the binding initialiser's `onChange` ignores the edit |
| 2.9 | `aTextEditorBoundToStateUpdatesItOnEveryEdit` | the same for `TextEditor(text: $s)` | M2h's twin in `TextEditor` (**M2i**) |
| 2.10 | `aBoundTextFieldDrawsTheSameSceneAsAControlledOne` | `Frame` scenes of `TextField("p", text: $s)` and `TextField("p", text: s) { … }` are equal, and of the two `TextEditor` spellings | **M2j**: the binding initialiser passes `""` as the placeholder |

**Guards** (`BindingCompileGuards.swift`):

| # | guard | mutation |
|---|---|---|
| G2.1 | `theKeyBindingAliasIsGoneSoBindingNamesTheValueBinding` — `Keymap([Binding("cmd-k", A())])` fails to typecheck; the same with `KeyBinding` succeeds (control, same fixture) | a public `init(_: String, _: some Action)` added to `Binding` |
| G2.2 | `anExternalModuleCanDeclareABindingAndPassAStateProjection` — Swift 6 whole-file: `@Binding var value: Int` in an `Element`, `Child(value: $n)` from `@State`, `.constant`, `$model.name`, `Binding(get:set:)`, `TextField("p", text: $s)`, `TextEditor(text: $s)` | `State.projectedValue` made `internal` |
| G2.3 | `aBindingIsMainActorIsolated` — a `nonisolated func` reading `b.wrappedValue` fails under Swift 6 (divergence 78's pin) | `@MainActor` removed from `Binding` (closures made `@Sendable`) |

**Retirement row**: `theDeprecatedBindingSpellingStillCompilesAndPointsAtKeyBinding`
(`EnvironmentCompileGuards`, `EV-N`'s guard) — deleted because the alias is
(`DD-D` item 6); its fact is inverted by G2.1. **Guard delta**: −1
(`EnvironmentCompileGuards` 8 → 7) + 3 (`BindingCompileGuards`).

### Lane 3 — `List`/`ScrollView` and the scroll APIs (`DD-F`…`DD-I`)

**Files.** `Sources/MetalUI/List.swift` (stored origin, fresh-window check,
pending-request scan), `Sources/MetalUI/ScrollView.swift` and
`Sources/MetalUI/ProposalScrollView.swift` (push a `ScrollerFrame`; enum cases),
`Sources/MetalUI/ScrollChrome.swift` (`.never`/`.visible` in `paintIndicator`),
`Sources/MetalUI/Passes.swift` (`deferred` resets the scroller stack),
`Sources/MetalUI/Frame.swift` (the scroller stack, `recordElementBounds`'
request match, the post-prepaint resolution), `Sources/MetalUI/Window.swift`
(the request queue, handed to each `Frame`; dirtied on enqueue),
`Sources/MetalUI/ScrollViewReader.swift` and `Sources/MetalUI/UnitPoint.swift`
(new). Tests: `Tests/MetalUITests/ListTests.swift` (the divergence-14 pin
retired and replaced), `Tests/MetalUITests/ScrollToTests.swift` (new),
`Tests/MetalUITests/ScrollIndicatorTests.swift` (new arms),
`Tests/MetalUITests/ScrollCompileGuards.swift` (new),
`Tests/MetalUITests/DisabledTests.swift` (the EV-Q pin's message cites `DD-I`;
assertion unchanged).

| # | test | asserts (arm) | red-before / mutation |
|---|---|---|---|
| 3.1 | `aListBelowAHeaderWindowsTheRowsOnScreen` (replaces the retired `aListNotAtTheScrollersContentOriginWindowsAgainstTheWrongRows`) | real `Window`: header 300, `List` of 40 at 28, viewport 112, wheel to 300 → rows built ⊇ 0…3 and ⊆ 0…5 (L2) | **red-before: 8…16** (DD14); **M3a**: `visibleRange` ignores the stored origin |
| 3.2 | `aListWhoseOriginChangesIsReWindowedOnTheNextFrame` | a header toggled from 0 to 300 by a click while scrolled: the frame after the click leaves `needsRedraw` true, and the next frame's rows cover the rows on screen | red-before: the stale window, `needsRedraw` false; **M3b**: `requestAnotherFrame()` removed from `List.prepaint` |
| 3.3 | `aGrownViewportIsFilledOnTheNextFrameWithoutInput` | 100 rows, viewport 112 → 560 by resize: frame 1 after builds 0…5 and asks for a frame; the next `drawFrameIfNeeded()` builds 0…21 (divergence 13's effect) | **red-before: 0 rows, `needsRedraw` false** (DD13); M3b; **M3c**: the containment test inverted |
| 3.4 | `anUnboundedListFrameAsksForNoExtraFrame` | a `ScrollView { List }`'s first frame (every row built) leaves `needsRedraw` false | **M3d**: request whenever the fresh window differs (containment dropped) |
| 3.5 | `aListInADeferredInsideAScrollViewMeasuresNoScrollerOrigin` | real `Window`: a `Deferred { List }` inside a scrolled `ScrollView` builds every row, and asks for no frame | **M3e**: `PrepaintPass.deferred` does not reset the scroller stack |
| 3.6 | `scrollToAnAnchorLandsTheTargetAtTheAnchor` | rows 30 in a 100 viewport, 20 rows: `.top` 300, `.center` 265, `.bottom` 230, `UnitPoint(x: 0, y: 0.25)` 282.5 (T1–T3, T9) | **M3f**: the formula uses the target's `maxY` |
| 3.7 | `scrollToWithNoAnchorScrollsTheLeastDistance` | 230 (below), 0 (visible), 60 (above, after `.top` to 10) (T4–T6) | **M3g**: a nil anchor treated as `.top` |
| 3.8 | `scrollToClampsToTheContentAndIgnoresAnUnknownID` | row 19 `.top` → 500 (T7); an unknown id → 0, and an element that appears with that id a frame later is **not** scrolled to (T8) | **M3h**: unresolved requests kept pending (second arm). The clamp itself is re-applied by `ScrollChrome.resolvedOffset`'s write-back, so removing it is expected to redden nothing — **measure it**, and record it as redundant rather than as a pin if so |
| 3.9 | `scrollToReachesAnUnrealisedListRow` | `List` of 200 at 30 in a 100 viewport: row 150 `.top` → 4500 (T15) | **M3i**: `List`'s pending-request scan removed |
| 3.10 | `scrollToTargetsTheFirstMemberOfAForEachElement` | 30 + 10 members per element: `.top` 400, `.bottom` 330 (T12, T12b) | **M3j**: the target is the union of every element under the name (reads 340) |
| 3.11 | `scrollToMovesOnlyTheNearestScroller` | T14's shape: outer 0, inner 300 | **M3k**: resolved against the outermost scroller frame |
| 3.12 | `scrollToWorksHorizontallyAndInAProposalScrollView` | horizontal `.leading` 300 (T11); a `ProposalScrollView` `.top` 300 | **M3l**: `ProposalScrollView` pushes no scroller frame (second arm) |
| 3.13 | `scrollToIsScopedToItsReader` | two readers, each over a scroller with an element `.id("x")`: reader A's proxy moves only A's scroller | **M3m**: the scope check dropped from the match |
| 3.14 | `aScrollViewReaderIsOneSlotWithItsOwnIdentityLevel` | a reader's content state is kept across frames, and a sibling after the reader keeps its index | **M3n**: the reader consumes no slot |
| 3.15 | `visibleIndicatorsPaintAsAutomaticAndNeverAsHidden` | `.visible` paints and asks for frames exactly as `.automatic`; `.never` paints nothing and asks for nothing, as `.hidden` (I1–I4) | **M3o**: `.never` falls through to the automatic path |

Unchanged and required green: `aListInsideADeferredIgnoresTheEscapedScrollersOffset`,
every `TB-AH` retention test, `AB-X`'s `activatingBeforeTheFirstFramePublishesNoRowsUntilTheWindowIsBounded`,
`scrollViewPublishesTheCurrentOffsetAndLastFramesViewportDuringRequestLayout`,
`aDisabledScrollViewStillScrollsOnTheWheel`, the 100 000-row test
(`METALUI_RUN_100K_LIST_TEST=1`, run once by the lane), and the frame-loop
pause tests.

**Guards** (`ScrollCompileGuards.swift`):

| # | guard | mutation |
|---|---|---|
| G3.1 | `anExternalModuleCanWriteScrollViewReaderAndScrollTo` — `ScrollViewReader { proxy in ScrollView { … } }`, a handler calling `proxy.scrollTo(3, anchor: .top)` and `proxy.scrollTo("x")`, `UnitPoint(x: 0, y: 0.25)`, `.scrollIndicators(.never)` | `scrollTo` made `internal` |
| G3.2 | `aScrollViewProxyCannotBeConstructedOutsideTheFramework` — `ScrollViewProxy()` fails | a public no-argument initialiser added |

**Retirement row**: `aListNotAtTheScrollersContentOriginWindowsAgainstTheWrongRows`
— its synthetic `ScrollContext` harness has no scroller, so it cannot see a
measured origin at all (it would stay green, asserting the retired wrong
answer); divergence 14 retires and 3.1 asserts the fix through a real
`ScrollView`. **Guard delta**: +2 (`ScrollCompileGuards` 2).

## 5. Demo expectation and the must-not-move checks

**No demo source changes.** The demo's `List` sits at its scroller's content
origin, and every one-frame harness renders the unbounded first frame, so:

- **0 px against `e7bc2e7` in all fourteen offscreen images**
  (`docs/probes/demo-pixels/compare.sh`), taken by lane 3 and by the Record
  phase;
- `Tests/MetalUICrossPlatformTests/Expected.swift` **unedited**
  (`DemoFrameDeterminismTests`);
- `everyProductionTreeBuildsOnAOneMegabyteThread`,
  `theLegacyEngineSymbolsAreAbsentFromTheTestProcess`,
  `theSevenRetentionSlotsAreMutuallyDistinct` green; `MetalUILayout` imports
  only `MetalUICore` (anchored grep); 0 `warning:` on both build systems;
  `Backends/SDL` builds and tests (21 + 22 on macOS) and a `swift:6.4-noble`
  container builds if Docker is available;
- **Real-window capture** per the lock probe: `xcrun swiftc -O
  docs/probes/appkit-screen-lock-state.swift -o /tmp/lockstate && /tmp/lockstate`
  — no `CGSSessionScreenIsLocked` line and `displayAsleep main: 0` → run
  `docs/probes/window-capture/capture.sh <scratch> e7bc2e7 <HEAD>`. **At design
  time the screen was locked** (`CGSSessionScreenIsLocked = 1`,
  `displayAsleep main: 1`).

**Must not move** (the workflow's list): the `StateTable`'s reset rules other
than `DD-C`'s ruled addition, `MC-A`/`MC-C`/`MC-P` numbering, `.id()`
outermost, hit testing, accessibility, animation, focus, the scrim, `List`
windowing (except `DD-F`'s origin and follow-up frame) and `TB-AH`, `Deferred`,
`TextField`/`TextEditor` behaviour (`DD-E` only adds initialisers).

## 6. Counts, expected

By construction: lane 1 adds **14 tests** (1.1–1.10, 1.12–1.15; 1.11 is an
existing test whose answer changes) and **2 guards**; lane 2 adds **10 tests**
and **3 guards** and deletes **1 guard**; lane 3 adds **15 tests** and **2
guards** and retires **1 test**. A guard is a `@Test`, so the summary line
moves by **+16, +12 and +16**: **1506 → 1522 → 1534 → 1550**. Guards by file:
+2 `ForEachCompileGuards`, +3 `BindingCompileGuards`, −1
`EnvironmentCompileGuards`, +2 `ScrollCompileGuards` (net +6). Goldens: 0.
Each lane reports the printed summary line, never the exit status; a lane that
adds or splits a test beyond this table says so and gives its own figure.

## 7. Record, plan and CLAUDE.md (the Record phase)

- Record `docs/record/57-data-and-scrolling.md`: the scratch measurements
  (DD13, DD14, C2.4b), each lane's red-before and mutation table, the counts,
  the pixel comparison, the retirement rows with their reasons.
- Record §04: a dated section — **14 and 74 retire, 13 amended, 78 added**
  (`Binding` is main-actor isolated).
- Record §03: the wheel-under-`.disabled` look (`DD-I` 3) and the real-window
  capture if the screen stays locked.
- Record §05: `ScrollIndicatorVisibility`'s `EP-5` note superseded (`DD-H`);
  `KeyBinding`'s deprecated alias gone.
- The plan: task 10 **unticked**, a dated progress note naming part 1's
  delivery and `DD-J`'s part-2 list.
- `CLAUDE.md`/`AGENTS.md`: the `DD-` prefix (next `DD-K`) in the prefix list;
  the `List` paragraph (divergence 14 gone, the follow-up frame); `@State`'s
  `$` projection and `Binding`; `Binding` no longer `KeyBinding`'s alias
  (Environment and Text-input paragraphs); `ForEach` and the loop reset rule
  under "Identity is structural"; `ScrollViewReader`; counts.
