# Lifecycle modifiers — onAppear, onDisappear, onChange — design

**Status: LANDED (2026-10-03) — lanes 1 and 2 and the fix pass implemented (`LC-Q`, `LC-S`, `LC-T`), the Record phase done (record §76); the looks are owed to a human (human-checks group T); `.task` is deferred with an owner (§9).** User request
2026-10-02, an item of the gpui-gap priority list; **not a plan task**.
Rulings `LC-A`…`LC-V` (`LC-U`: the branch check; `LC-V`: a `nil` action is a present scope with no action, fixed, and the depth redundant again; `LC-T`: lane 2's findings — the demo's placement and the 1 MB stack, a demo census pin, the SDL test target, the count; `LC-P`: the critic pass, which amends `LC-C`, `LC-H` and this spec's tests and counts; `LC-Q`: lane 1's findings — divergence 124, cancellation of every key under a ghost, the drain loop) in
[`../2026-10-03-lifecycle-decisions.md`](../2026-10-03-lifecycle-decisions.md).
Record: `docs/record/76-lifecycle.md` (Record phase). Probes (new, outputs in
their headers): `docs/probes/swiftui-lifecycle.swift` (SwiftUI, run three
times; byte-identical outside the lazy-container arms, whose row sets agree
and whose order does not) and `docs/probes/swift-main-actor-task-loop.swift`
(macOS and `swift:6.4-noble`). Branch `feat/lifecycle` from `047f0ab`.

**Motivation.** The user is porting the SMK keyboard configurator
(SwiftCrossUI) to MetalUI. Its device monitor starts and stops with the DEV
pane (`onAppear`/`onDisappear`), and a load error becomes an alert through
`onChange(of:)`. MetalUI has none of the three.

## 0. Baseline (re-taken by the design session at `047f0ab`)

`swift build --build-system native --build-tests`: **0 `error:`**, the one
`warning:` SwiftPM's deprecation notice. `swift test --build-system native
--no-parallel`: **`Test run with 2376 tests in 3 suites passed after 124.971
seconds`**, the `FR-J no-argument frame: succeeded=true` line present. 146
`canTypecheck`-gated test declarations (`grep -rh "enabled(if: canTypecheck"
Tests | wc -l`), 0 goldens, **86 live divergences, next label 120**
(`docs/divergences.md` lines 4 and 12). Screen **locked** throughout (lock
probe: `CGSSessionScreenIsLocked = 1`, `displayAsleep main: 1`): no
real-window capture in the design session. OrbStack was already running and
was left running.

## 1. What MetalUI has, and what SwiftUI does

### 1.1 Inventory

| Area | Today | File |
|---|---|---|
| Lifecycle API | **None**: no `onAppear`, `onDisappear`, `onChange`, `task` anywhere in `Sources/` or `Backends/SDL/Sources` (grep). | — |
| Transparent scope precedent | `TransactionScope<Content>` (`.animation(_:value:)`, `.transaction`): `ElementGroup`, typed copy `ProposalElementGroup where Content: ProposalElementGroup`, `parent`/`cursor` forwarded; previous value in `AnimationStore` at `.child(of: .child(of: parent, at: cursor, name: nil), at: 0, name: "$anim-value<depth>")` (`AN-Y`). | `Sources/MetalUI/AnimationScope.swift` |
| Window-owned per-frame stores | `AnimationStore` (entries dropped when untouched one frame, `AN-AB`; holds `transitions`, `rasters`), `SurfaceRegistry` (key = id + occurrence, `MV-M`). Fresh per headless `renderFrame` / test `Frame`. | `AnimationStore.swift`, `SurfaceRegistry.swift` |
| State resets | `StateTable.sweep()` at the end of `Frame.render`: `ID-C` absent slots, `ID-R` departed names, `DD-C` dropped loop elements, one `removeEntries` pass, `$ax` exempt; `List` rows exempt (`noteWindowedParent`, `TB-AH`); reap above 256 entries after 2 generations. | `StateTable.swift:170–470, 856` |
| `@State` read/write | `State.wrappedValue` → `StateTable.peek(slotID)` ?? `initialValue`; set → `StateTable.write` (fires `onWrite` → `setNeedsRedraw`). | `State.swift:102`, `StateTable.swift:735, 771` |
| Dispatch | `StateDispatch.dispatching(to:)` around every input handler; `Frame.render` builds `outsideDispatch`. | `StateDispatch.swift` |
| Frame loop | `drawFrameIfNeeded`: guard → flush → `beginFrame()` → `buildAndAdoptFrame` (inside it `withObservationTracking { renderRoot }`, read-backs, `@FocusState` reconcile, `wantsAnotherFrame`) → `CR-Q` first-frame second build → accessibility → `finishFrame`. | `Window.swift:1100–1290, 1300–1456` |
| Frame.render order | layout → `transitions.afterLayout` → prepaint → paint → `paintGhosts` (drops finished ghosts) → `transitions.endFrame`, `animationStore.endFrame`, `rasters.endFrame`, `surfaceRegistry.endFrame` → `stateTable.sweep()` → focus clear. | `Frame.swift:2889–3040` |
| Removal ghosts | `TransitionStore.ghosts: [(key, Ghost)]`, key `.child(of: P, at: 0, name: "$transition")` with `P` the group's position; created in `afterLayout` for an animated removal; removed when the group is re-inserted (`afterLayout`) or finished (`paintGhosts`). Replayed captures — the removed content is **not built**. | `TransitionStore.swift:120–300` |
| Window close | `App` sets `platformWindow.onClose` (terminate on AppKit); `AppKitWindow` calls it at `AppKitPlatform.swift:792`, `SDLWindow` at `SDLPlatform.swift:528`. `Window` itself has no close hook. | `App.swift:123` |
| Headless | `renderFrame` builds one fresh `Frame` and returns its scene; draw requests dropped (`MV-H`). | `RenderFrame.swift` |
| SDL loop | `SDLPlatform.run()`: `while running { pumpEvents / mui_wait_event; tick }` — never enters `RunLoop` or `dispatchMain`. | `Backends/SDL/Sources/MetalUISDL/SDLPlatform.swift:84` |
| Modifier order after a scope | `Text("a").animation(.default, value: x).onClick {}` → "value of type 'TransactionScope<Text>' has no member 'onClick'"; `.padding(4)` fails likewise; `.frame(width:)` compiles (measured by `swiftc -typecheck` against the `047f0ab` build). | — |
| Looks demo | `looksDemoContent()`, six section functions to `looksRoot`; not in the fourteen offscreen images nor `DemoFrameDeterminismTests`; built on a 1 MB thread by `everyProductionTreeBuildsOnAOneMegabyteThread`. | `Sources/MetalUIDemoContent/LooksDemo.swift` |

### 1.2 SwiftUI's answers (probe `swiftui-lifecycle.swift`, macOS 27.0.1)

- **Presence is per modified group, while it has content** (`LC-P`): a
  modifier on a `ForEach` or `Group` fires **once for the group**, not per
  child, and only while the group produces at least one view — an empty
  `ForEach` does not appear; it appears when it first has rows, disappears when
  it has none (`A6`, `A6b`). A lifecycle modifier written **outside** `.id`
  keys on the position: an `.id` change fires no appear/disappear there and
  its `onChange` compares across the two identities (`E2b`: only
  `change old=0 new=1`).
- **Presence is hierarchy membership**: `.hidden()`, opacity 0, zero size and
  clipped-out content appear (`E3`–`E5`); a lazy `List`/`LazyVStack` row
  disappears when scrolled out and appears when scrolled in (`S1`, `S2`); a
  plain `VStack` in a `ScrollView` fires nothing on scroll (`S3`).
- **Order**: reverse pre-order — children before parents, later siblings
  first, inner modifier first — on insertion (`A1`–`A3`) and removal (`A1`,
  `A3`), except three separately removed siblings, which go forward (`A2`).
  New content appears before old disappears (`A4`, `A5`, `E2`, `C10`).
  Existing views' changes run before inserted views' appears (`C12`).
- **Timing**: onAppear runs after the first body, before the first draw, and
  its write reaches the first draw (`F1`, `F2b`); chains settle in one turn
  (`F3`, `C9`); onChange runs after the body, before the draw (`C8`).
- **onChange**: (old, new) and zero-parameter forms (`C1`, `C2`);
  `initial: true` fires (v, v) with onAppear in modifier order (`C3`, `C3b`);
  coalesced per update (`C5`–`C7`); fresh per identity (`C10`); not for the
  inserted or removed view (`C12`, `C13`).
- **Transitions**: an animated removal's onDisappear runs when the transition
  ends (`T1`, `T3`, `T5`); re-insertion mid-removal runs neither callback and
  keeps the view (`T4`); insertion appears at once (`T2`).
- **State in onDisappear**: reads its own `@State` as it was; a write is lost
  (`D1`).
- **Window**: order-out and `close()` with the host retained fire nothing
  (`W1`, `W2`); removing the hosting view fires onDisappear (`W3`).
- **`.task`**: starts after onAppear, cancelled after onDisappear; `task(id:)`
  restarts new-then-cancel (`K1`, `K2`) — recorded for `LC-L`'s owner.

## 2. Public API (lane 1, new file `Sources/MetalUI/Lifecycle.swift`)

Every declaration has a doc comment citing its ruling and an inventory row.

```swift
extension ElementGroup {
    public func onAppear(perform action: (() -> Void)? = nil) -> LifecycleScope<Self>          // A, LC-B
    public func onDisappear(perform action: (() -> Void)? = nil) -> LifecycleScope<Self>       // A, LC-B
    public func onChange<V: Equatable>(of value: V, initial: Bool = false,
                                       _ action: @escaping (_ oldValue: V, _ newValue: V) -> Void)
        -> LifecycleScope<Self>                                                                 // A, LC-G
    public func onChange<V: Equatable>(of value: V, initial: Bool = false,
                                       _ action: @escaping () -> Void) -> LifecycleScope<Self>  // A, LC-G
}

/// `content` with an appearance, disappearance or value-change action —
/// layout- and identity-transparent (LC-B).
public struct LifecycleScope<Content: ElementGroup>: ElementGroup { … }                        // A
extension LifecycleScope: ProposalElementGroup where Content: ProposalElementGroup { … }        // A
public struct LifecycleScopeLayout<ContentLayout> { … }                                         // M (the scope's GroupLayout)
```

Inventory: one family row `F lifecycle A swiftui-lifecycle.swift C1
onChangePassesTheOldAndNewValues 120 121 122 123 LC-B LC-C LC-E LC-F LC-G LC-H
LC-I LC-J <behaviour>` and `M MetalUI Lifecycle.swift .* .* .* lifecycle`;
re-record `closeout-public-api.tsv`; both closeout scripts print nothing.

## 3. Implementation (lane 1)

### 3.1 `Lifecycle.swift` (new)

- `enum LifecycleWrite { case appear(() -> Void); case disappear(() -> Void);
  case change(value: Any, isEqual: (Any) -> Bool, action: (Any, Any) -> Void,
  initial: Bool) }` — the two `onChange` forms both build `.change` (the
  zero-parameter form wraps `{ _, _ in action() }`); `nil` actions build a
  scope that notes nothing.
- `LifecycleScope.requestGroupLayout(under:at:pass:)`: reserves its
  registration order **before** recursing (pre-order, `LC-F`) — `let order =
  pass.frame.reserveLifecycleOrder()` — then `let (nodes, layout) =
  pass.frame.withLifecycleScope { content.requestGroupLayout(under: parent,
  at: &cursor, pass: &pass) }` (depth + 1 around the content, `LC-C` item 2),
  then **only when `nodes` is non-empty** `pass.frame.noteLifecycle(write,
  order: order, under: parent, at: cursorBefore)` (`LC-P` item 1: a group
  with no content is absent — no entry, no `onChange` comparison).
  `prepaintGroup`/`paintGroup` forward with no work. **The typed
  `requestProposalGroupLayout` is a line-for-line copy, pinned on its own**
  (test 1.10).
- `Frame.noteLifecycle` (in this file, `extension Frame`): key = `.child(of:
  .child(of: parent, at: cursor, name: nil), at: 0, name:
  "$lifecycle\(lifecycleDepth)")`, owner = the inner position; forwards to
  `animationStore.lifecycle.note(write, key:, owner:)`.
- `final class LifecycleStore` (`@MainActor`): `struct Key { scope:
  GlobalElementID; occurrence: Int }`; `struct Entry { order: Int; owner:
  GlobalElementID; onAppear, onDisappear: (() -> Void)?; change:
  (value: Any, isEqual:, action:, initial:)? }`. `current`/`previous:
  [Key: Entry]`, `occurrences: [GlobalElementID: Int]`, `nextOrder`, `parked:
  [GlobalElementID /* ghost key */: [LifecycleEvent]]`, `pending:
  [LifecycleEvent]`, `lastFrameWork`, `hasDisappearActions` (any entry in
  `previous` with `onDisappear`). One scope with several writes is
  impossible (one write per scope), so `note` merges into the entry for
  `Key` (a stacked pair has two depths, two keys).
  - `note(_:key:owner:)` (layout): occurrence, order, merge; for `.change`,
    `lastFrameWork += 1`. (`LC-Q` item 4: the `onChange` comparison and the
    `initial` first firing moved to `endFrame`.)
  - `endFrame(ghosts: [(key: GlobalElementID, position: GlobalElementID)],
    departed: DepartedState?)` — called by `Frame.render` **after
    `stateTable.sweep()`**: appearances = keys in `current` not in
    `previous` (bucket 2, `onAppear` events; minus keys whose parked
    disappearance is cancelled, `LC-H`); disappearances = keys in `previous`
    not in `current` with `onDisappear`: parked when the entry's owner equals
    or descends from a live ghost's position, else bucket 3 with `departed`
    attached; parked events whose ghost is no longer live run (key absent) or
    are cancelled (key present again). **`LC-Q` item 2:** a live ghost holds
    every key that left under it (`ParkedGhost.keys`), with or without an
    `onDisappear`, and a held key present again cancels its appearance. Sort each bucket by descending order
    (bucket 3 by the previous build's order), append to `pending`; swap
    `current`→`previous`; clear `current`, `occurrences`. Early return when
    `current`, `previous` and `parked` are all empty. `lastFrameWork` adds
    `current.count + previous.count`, stored, then reset.
  - `takeEvents() -> [LifecycleEvent]`, `closeAll() -> [LifecycleEvent]`
    (every `previous` entry's `onDisappear` in reverse order, then every
    parked one; clears everything), `count`, `parkedCount`,
    `hasDisappearActions`.
- `struct LifecycleEvent { owner: GlobalElementID; action: () -> Void;
  departed: DepartedState? }`.

### 3.2 `AnimationStore.swift`

`let lifecycle = LifecycleStore()` beside `transitions` and `rasters`, doc
citing `LC-D`. `AnimationStore.endFrame()` does **not** call it (the
lifecycle's end is after the sweep).

### 3.3 `Frame.swift`

- `private(set) var lifecycleDepth = 0`, `func withLifecycleScope<R>(_ body:
  () -> R) -> R` (the `withTransactionScope` shape).
- In `renderOutsideDispatch`, before `stateTable.sweep()`:
  `stateTable.retainsDepartedValues = animationStore.lifecycle
  .hasDisappearActions`; after the sweep (and after the focus clear):
  `animationStore.lifecycle.endFrame(ghosts: animationStore.transitions
  .liveGhosts, departed: stateTable.takeDepartedState())`.
- `isRendering` becomes `private(set)` (read by test 4.3).

### 3.4 `TransitionStore.swift`

`var liveGhosts: [(key: GlobalElementID, position: GlobalElementID)]` —
each live ghost's key and `key.parent!` (the group's position). Read after
`paintGhosts`, so a finished ghost is already gone. No other change.

### 3.5 `StateTable.swift` (`LC-I`; no retention rule moves)

- `var retainsDepartedValues = false`; in `removeEntries`, when set, each
  doomed key's value goes into `departedValues` before removal; the reset
  roots (`departedRoots ∪ absentSlots`, collected in `resetQueuedEntries`
  before they are cleared) into `departedRootsKept`. `noteProduced`'s
  mid-frame reset keeps nothing.
- `struct DepartedState { var values: [GlobalElementID: Any]; let roots:
  Set<GlobalElementID> }` (class-free, copy-on-write);
  `takeDepartedState() -> DepartedState?` (nil when nothing was kept);
  `private(set) var lastDepartedValueCount`.
- `func withDepartedOverlay(_ state: DepartedState?, _ body: () -> Void)`:
  while set, `peek` answers `overlay.values[id]` first; `write` to an id
  equal to or descending from an overlay root stores into the overlay only
  (no `storage`, no `onWrite`, no `writeCount`). Outside a disappearance the
  overlay is nil and both paths are unchanged.

### 3.6 `Window.swift`

- `private var isDrainingLifecycle = false`; `private(set) var
  lastDrawBuildCount = 0` (incremented per `buildAndAdoptFrame`, reset at
  the top of `drawFrameIfNeeded`).
- `@discardableResult private func drainLifecycle() -> Bool`: guard
  `!isDrainingLifecycle`; take events, and take again until none are left
  (`LC-Q` item 3); `let wasDirty = needsRedraw;
  needsRedraw = false`; for each event:
  `stateTable.withDepartedOverlay(event.departed) {
  StateDispatch.dispatching(to: event.owner) { event.action() } }`; `let
  dirtied = needsRedraw; needsRedraw = wasDirty || dirtied; return dirtied`.
- `drawFrameIfNeeded`, after the `CR-Q` block and before accessibility:

  ```swift
  if drainLifecycle() {                       // LC-E item 2
      needsRedraw = false
      (frame, scene) = buildAndAdoptFrame(scaleFactor: drawScaleFactor)
      _ = applyTreeColorSchemePreference(of: frame)
      drainLifecycle()                        // second level: writes schedule the next frame
  }
  ```
- `func runDisappearancesForClose()` (internal): runs
  `animationStore.lifecycle.closeAll()` the same way, once (a second call
  finds nothing).

### 3.7 `App.swift`

The `onClose` closure captures the window weakly and calls
`runDisappearancesForClose()` before AppKit's terminate (`LC-J`).

### 3.8 Platforms

**No new `Platform`/`PlatformWindow`/`WindowRenderer` requirement**: every
piece is in `MetalUI`, which both platforms drive through
`drawFrameIfNeeded` and `onClose`. No shader change, no new primitive
(`TE-AD` not triggered). `MetalUILayout`/`MetalUIScene` imports untouched.

## 4. Divergences (lane 1, `docs/divergences.md`; record §04 sections in the Record phase)

| Label | Surface | SwiftUI | MetalUI | Ruling | Pin |
|---|---|---|---|---|---|
| 120 | a legacy decoration after a lifecycle modifier | any order compiles | `Self`-returning `StyledElement` decorations (`onClick`, `background(_:)`, `padding(_:)`) after `.onAppear`/`.onDisappear`/`.onChange` do not compile; write them first | `LC-B` item 4 | `aLegacyDecorationAfterALifecycleModifierDoesNotCompile` |
| 121 | an action chain | settles to a fixed point before the first draw (`F3`, `C9`) | two levels of actions per drawn frame; the first level's writes are presented, each later level's one frame later | `LC-E` item 3 | `aChainOfAppearancesSettlesOneLevelOfWritesPerPresentedFrame` |
| 122 | callback order | reverse pre-order except separately removed siblings (forward, `A2`); a lazy container's scroll order varies by run (`S1`, `S2`) | changes → appears → disappears, each reverse pre-order, always | `LC-F` | `removalRunsInReversePreOrderEvenForSeparatelyRemovedSiblings` |
| 123 | content re-inserted during its removal transition | keeps the view and its state (`T4`) | runs neither callback (as SwiftUI) but its `@State` is fresh (`ID-C` reset it at removal) and its `onChange` compares against nothing on return (`LC-D` dropped the entry at removal; `LC-P` item 8) | `LC-H` | `reinsertingDuringTheGhostRunsNeitherCallbackAndStartsWithFreshState` |

| 124 | a `List`'s first frame | only rows in view appear (`S1`) | every row appears on the cold frame; the rows outside the measured window disappear on the next build | `LC-Q` item 1 | `aListsFirstFrameAppearsEveryRowAndTheNextBuildDisappearsTheRowsOutsideItsWindow` |

Header count moves 86 → 91 live, next label 125 (`LC-Q` added 124).

## 5. Tests

**Red before, for every test below: the file does not compile at `047f0ab`**
(no `onAppear`/`onDisappear`/`onChange`/`LifecycleStore`). Each test's
**mutation** is applied on `feat/lifecycle` after lane 1's implementation
commit, restored from a copy, the full suite run unfiltered; the
implementer records the spelling mutated and every test it reddens.

### 5.1 `Tests/MetalUITests/LifecycleTests.swift` (lane 1)

Presence and identity:

| # | Test | Asserts (probe arm) | Mutation that must redden it |
|---|---|---|---|
| 1.1 | `anIfThatInsertsContentRunsItsOnAppearOnce` | toggled in, 3 frames: 1 appearance (`A1`) | `endFrame` treats every `current` key as appearing |
| 1.2 | `anIfThatRemovesContentRunsItsOnDisappearOnce` | 1 disappearance, none after (`E1`) | delete the disappearance loop |
| 1.3 | `aChangedIdRunsTheNewAppearBeforeTheOldDisappear` | log `[appear 1, disappear 0]` (`E2`) | swap buckets 2 and 3 |
| 1.4 | `hiddenTransparentZeroSizedAndClippedElementsAppear` | 4 appearances (`E3`–`E5`); opacity toggle fires nothing (`E4`) | note from `paintGroup` instead of layout (hidden nodes skip paint) |
| 1.5 | `aListRowScrolledOutDisappearsReturnsAsAnAppearanceAndKeepsItsState` | out: disappear; back within 2 generations: appear and its `@State` value kept (`S1`, `TB-AH`) | exempt children of `noteWindowedParent` parents from disappearance |
| 1.5b | `aListsFirstFrameAppearsEveryRowAndTheNextBuildDisappearsTheRowsOutsideItsWindow` | 12 appearances, 9 disappearances (rows 3…11) in the first `drawFrameIfNeeded`, nothing after (divergence 124, `LC-Q` item 1) | none of its own (the `List` cold-frame rule is outside the lane) |
| 1.6 | `twoSiblingsSharingOneIdAppearTwice` | 2 appearances (divergence 72's shape) | drop `occurrence` from `Key` |
| 1.7 | `stackedLifecycleModifiersKeepSeparateEntriesInnerFirst` | `[a, b]` on insertion and removal (`A3`) | drop `depth` from the key — **green**. `LC-R` finding 1 read this as redundant; `LC-U` item 1 refutes that, because the depth is needed when an inner action toggles to or from `nil`, and no committed test pins it. Measured with M1.7b, depth and occurrence dropped |
| 1.8 | `addingALifecycleModifierMovesNoIdentity` | recorded element ids and a nested `@State` equal with and without the scope | `cursor += 1` in `requestGroupLayout` |
| 1.9 | `lifecycleModifiersFireInsideAComponentAnEnvironmentScopeAndADeferred` | each fires once | (composition; pinned by 1.1's mutation — no own) |
| 1.10 | `theTypedProposalScopeNotesLikeTheUntypedOne` | a `ProposalText().onAppear` inside `HStack` fires; ids equal | delete `noteLifecycle` from `requestProposalGroupLayout` only |
| 1.11 | `aLifecycleModifierWrittenOutsideIdKeysOnThePosition` | `Text("x").id(k).onAppear{}.onDisappear{}.onChange(of: v){}`, `k` and `v` changed in one write: no appear, no disappear, one change `(0, 1)`; recorded ids equal those without the scope (`E2b`, `LC-P` item 2) | key the entry on the content's first node's element id instead of the scope's position |
| 1.12 | `aGroupModifierFiresOncePerGroupAndOnlyWhileItHasContent` | `ForEach(0..<n).onAppear/.onDisappear`, n 0 → 3 → 1 → 0 → 2: `[appear]` at 3, nothing at 1, `[disappear]` at 0, `[appear]` at 2, nothing at 0 initially; a two-child group under an `if`: one appear, one disappear (`A6`, `A6b`, `LC-P` item 1) | note the entry whether or not `nodes` is empty |

Order:

| # | Test | Asserts | Mutation |
|---|---|---|---|
| 2.1 | `insertionRunsChildrenBeforeParentsAndLaterSiblingsFirst` | `[child2, child1, parent, grandparent]`, `[s3, s2, s1]` (`A1`, `A2`) | sort ascending |
| 2.2 | `removalRunsInReversePreOrderEvenForSeparatelyRemovedSiblings` | `A1` removal order; `A2` removal `[s3, s2, s1]` (divergence 122) | sort bucket 3 by this build's order (or ascending) |
| 2.3 | `changesRunBeforeAppearsAndAppearsBeforeDisappears` | `[change a, appear new, disappear old]` (`C12`, `A5`) | concatenate buckets 2, 1, 3 |
| 2.4 | `initialTrueFiresWithAppearInModifierOrder` | `[appear, change 5 5]`; swapped modifiers `[change 5 5, appear]` (`C3`, `C3b`) | put initial firings in bucket 1 |

`onChange`:

| # | Test | Asserts | Mutation |
|---|---|---|---|
| 3.1 | `onChangePassesTheOldAndNewValues` | `(0, 1)` (`C1`) | pass `(new, old)` |
| 3.2 | `theZeroParameterFormFires` | called once (`C2`) | zero-param overload builds a no-op |
| 3.3 | `aFirstSightingFiresOnlyWithInitialTrue` | default: 0 calls; `initial: true`: `(5, 5)` (`C3`, `C4`) | fire on first sighting regardless |
| 3.4 | `writesBetweenFramesCoalesceAndAnUndoneChangeFiresNothing` | `1; 2` → `(0, 2)`; `1; 0` → none; `0` → none (`C5`–`C7`) | compare `previous` by `writeCount` instead of `isEqual` |
| 3.5 | `contentThatReturnsComparesAgainstNothing` | removed, value changed, returned: 0 calls; `.id` change with value change: 0 calls (`C10`) | `endFrame` keeps untouched `previous` entries one more build |
| 3.6 | `insertedAndRemovedElementsDoNotSeeTheChangeThatMovedThem` | `C12`, `C13` | compare a key absent from `previous` against the last value under its owner |

Timing, dispatch, settle:

| # | Test | Asserts | Mutation |
|---|---|---|---|
| 4.1 | `anOnAppearWriteIsPresentedInTheFirstFrame` | after one `drawFrameIfNeeded`: `lastScene` shows the written value; `lastDrawBuildCount == 2` (`F1`) | delete the settle build |
| 4.2 | `anActionThatWritesNothingCostsNoSecondBuild` | `lastDrawBuildCount == 1` | settle unconditionally |
| 4.3 | `actionsRunOutsideEveryPhaseUnderTheirElementsDispatch` | inside the action: `StateDispatch.owner` = the scope's position, the frame's `isRendering == false`, `Frame` not in `withObservationTracking` (an `@Observable` write dirties the window) | run the drain inside `renderRoot` (end of `Frame.render`) |
| 4.4 | `anObservableWriteInOnAppearIsPresentedAndNotLost` | an `@Observable` model's write reaches the first presented frame; after it the window goes clean only once nothing changes | run the drain inside the `withObservationTracking` apply closure |
| 4.5 | `aSettledWindowGoesIdle` | after the events, two `drawFrameIfNeeded`: `needsRedraw == false`, `pausesEntered` increments | `drainLifecycle` returns/sets dirty unconditionally |
| 4.6 | `anActionThatDrawsAFrameDoesNotDrainReentrantly` | an action writing then calling `window.drawFrameIfNeeded()` runs once; the inserted content's appear runs exactly once | delete the `isDrainingLifecycle` guard |
| 4.7 | `aChainOfAppearancesSettlesOneLevelOfWritesPerPresentedFrame` | `F3`'s shape: frame 1 presents `second`; `third` presented in frame 2 (divergence 121) | loop the settle until clean (SwiftUI's fixed point) — reddens by design; the test pins MetalUI's bound |

Departed state:

| # | Test | Asserts | Mutation |
|---|---|---|---|
| 5.1 | `onDisappearReadsItsOwnStateAsItWasLastFrame` | reads 7 (`D1`) | `withDepartedOverlay` ignores the overlay |
| 5.2 | `aWriteInOnDisappearIsLostAndReturningContentStartsFresh` | written 99, never-written slot written too; returned content reads 0 for both (`D1`) | overlay writes fall through to `storage` |
| 5.3 | `noDepartedValuesAreKeptWithoutAnOnDisappear` | `lastDepartedValueCount == 0` for an `if` removal with no lifecycle modifier | `retainsDepartedValues = true` always |
| 5.4 | `aListRowsOnDisappearReadsItsRetainedLiveState` | the row's live `@State` value, not the initial | `peek` under `withDepartedOverlay` answers only from the overlay (nil outside it) — `LC-P` item 5 |
| 5.5 | `aNeverWrittenStateDefaultIsReseededSoOnAppearAndOnDisappearSeeDifferentInstances` | pins divergence 125 (`D2`, `LC-S` item 1): start 1, stop a later instance | green by design; separating arm 5.6 |
| 5.6 | `aMonitorAssignedInOnAppearIsTheOneOnDisappearStops` | the documented spelling starts and stops one instance | `departedOverlay = nil` (M5.1) |
| 5.7 | `eachRemovalCountsOnlyTheDepartedValuesItsOwnSweepKept` | `takeDepartedState()` empties its buffers (`LC-S` item 3) | delete its clearing `defer` (V3) |

Transitions (`startsDisplayLink: true`, `simulateTick(timestamp:)`):

| # | Test | Asserts | Mutation |
|---|---|---|---|
| 6.1 | `anAnimatedRemovalDisappearsWhenItsGhostEnds` | `.linear(duration: 0.6)`: none at t + 0.3, one at t + 0.7 (`T1`) | never park |
| 6.2 | `anOnDisappearOutsideTheTransitionAlsoWaits` | same with `.transition(.opacity).onDisappear` (`T3`) | park only on strict descent (not equal position) |
| 6.3 | `aParentAndItsChildUnderOneGhostDisappearTogetherChildFirst` | `[child, parent]` after the fade (`T5`) | release parked events in stored order reversed |
| 6.4 | `reinsertingDuringTheGhostRunsNeitherCallbackAndStartsWithFreshState` | re-inserted at t + 0.15: no disappear, no second appear, ever; nested `@State` reads initial (`T4`; divergence 123) | do not cancel a parked event whose key returned |
| 6.5 | `anUnanimatedRemovalDisappearsAtOnceAndAnAnimatedInsertionAppearsAtOnce` | `T0`, `T2` | park every disappearance for one build |
| 6.6 | `aGhostParkedOnDisappearReadsTheStateItsElementHad` | a ghost-parked `onDisappear` reads `a = 7` (`LC-I` item 1, `LC-S` item 2) | the parked event built with `departed: nil` (V1) |

Window and headless:

| # | Test | Asserts | Mutation |
|---|---|---|---|
| 7.1 | `closingTheWindowRunsEveryPresentOnDisappearOnce` | `App` over `FakePlatform`; the fake's `onClose`: each present element once, reverse pre-order; a second close nothing (`W3`) | remove the call from `App`'s `onClose` |
| 7.2 | `closingTheWindowAlsoRunsParkedDisappearances` | a mid-ghost close runs the parked one | `closeAll` skips `parked` |
| 7.3 | `aHeadlessRenderFrameRunsNoAction` | `renderFrame` with `.onAppear`: 0 calls | drain in `renderFrame` |

Performance (branching tree, literals derived before the run):

| # | Test | Asserts | Mutation |
|---|---|---|---|
| 8.1 | `aTreeWithNoLifecycleModifierDoesNoLifecycleWork` | `demoContent()` in a window, 3 frames: `lifecycle.count == 0`, `lastFrameWork == 0`, `lastDepartedValueCount == 0` | note an entry from `Element`'s default `requestGroupLayout` |
| 8.2 | `aSteadyFrameDoesThreeUnitsOfLifecycleWorkPerScope` | a ternary tree three levels deep with a scope on every node (1 + 3 + 9 + 27 = 40 scopes): steady `lastFrameWork == 120`; removing one leaf subtree changes it by the literal derived | a nested-loop diff (`previous` scanned per `current` key) |

### 5.2 `Tests/MetalUITests/LifecycleCompileGuards.swift` (lane 1; each mutated red once)

| # | Guard | Asserts | Mutation (fixture or source) |
|---|---|---|---|
| 9.1 | `theLifecycleSpellingsTypecheckFromAnExternalModule` | `typecheckFile`, plain `import MetalUI`: `.onAppear { model.start() }` (`@MainActor` model), `.onAppear()`, `.onDisappear(perform: f)`, `.onChange(of: x) { old, new in }`, `{ }`, `{ _, _ in }`, `initial: true`, on `Text` and `ProposalText`, then `.frame`/`.id` after | delete the zero-parameter overload |
| 9.2 | `aNonEquatableOnChangeValueDoesNotCompile` | negative | drop the `Equatable` constraint |
| 9.3 | `aLegacyDecorationAfterALifecycleModifierDoesNotCompile` | negative: `Text("a").onAppear {}.onClick {}` (divergence 120) | move `.onClick` before `.onAppear` in the fixture |
| 9.4 | `aLifecycleModifierOnAWindowRootNeedsAContainer` | negative: `openWindow(…) { Text("a").onAppear {} }`; positive: the root inside `Column { }` (divergence 120, `LC-S` item 7) | wrap the negative's root in `Column { }` (MG9.4) |

### 5.3 Lane 2 tests

| # | Test | File | Asserts | Mutation |
|---|---|---|---|---|
| 10.1 | `theLooksLifecycleSectionCountsAppearancesDisappearancesAndChanges` | `Tests/MetalUITests/LooksLifecycleDemoTests.swift` | click the section's toggle (hitbox) twice: the appear and disappear bars are 8 and 8 wide; the stepper's increment: the change bar 8 | the section's `onDisappear` increments the appear counter |
| 10.2 | `anOnAppearRunsInAnSDLWindowsFirstFrame` | `Backends/SDL/Tests/MetalUISDLTests/SDLLifecycleTests.swift` (helper arms `armMainRunLoopExitCheck()`) | an `SDLPlatform` window's first tick runs the action and presents its write | delete the drain call in `drawFrameIfNeeded` (on the lane-2 branch spelling) |
| 10.3 | `closingAnSDLWindowRunsItsOnDisappear` | same file | `MUI_EVENT_CLOSE` path (`onClose`) runs it once | remove the call from `App`'s `onClose` |

Expected count after both lanes (corrected by `LC-P` item 4: tests 10.2 and
10.3 live in `Backends/SDL`, a separate package the 2376 does not count):
2376 + 47 (lane 1: 44 tests with `LC-Q`'s 1.5b + 3 guards) + 1 (lane 2's 10.1) = **2424 tests**
in the main package, `canTypecheck`-gated declarations 146 → 149;
`Backends/SDL` + 2. Re-measure; a count is stale when a test lands.
**Measured (`LC-T` item 5):** `LC-S` added five (2428), so with 10.1 the main
package reads **2429 tests in 3 suites**; `Backends/SDL` **24 + 65**.

## 6. Demo (lane 2)

**As built (`LC-T` items 2–3):** the section is `LooksLifecycle()` alone
(its title inside the component's body), composed beside H1 by its own
`looksBesideH1(text:lifecycle:)` and passed to `looksRoot` as its `text:`
argument — under the transitions the looks content grew past its 880-point
window, and composed inline or with an outer `Column` the tree overflowed a
1 MB thread; the counters sit two by two; the title line gains "T1–T2". As
designed: `looksLifecycleSection()` in `LooksDemo.swift`, its own function passed to
`looksRoot` as a seventh argument (title line gains "T1"): a
`LooksLifecycle: Component` with `@State var appeared = 0, disappeared = 0,
faded = 0, changes = 0, shown = false, fadingShown = false, value = 0`;
a `Button("Toggle tile")` inserting a 120 × 28 tile with
`.onAppear { appeared += 1 }.onDisappear { disappeared += 1 }`; a
`Button("Toggle fading tile")` doing the same under `withAnimation(.easeInOut
(duration: 0.8))` with `.transition(.opacity)` and `onDisappear { faded += 1
}`; a `Stepper` on `value` with `.onChange(of: value) { changes += 1 }`; each
counter as `Text` and as a bar `8 × count` pt wide. **Expectation**: the
fourteen offscreen images 0 px against `047f0ab`
(`docs/probes/demo-pixels/compare.sh <scratch> 047f0ab HEAD`),
`Expected.swift` unedited, `everyProductionTreeBuildsOnAOneMegabyteThread`
green.

## 7. Human checks (lane 2, `docs/verification/human-checks.md` group T)

**T1** — `METALUI_LOOKS_DEMO=1 swift run MetalUIDemo`: toggle the fading tile
off; the "faded" counter increments when the fade ends (~0.8 s), not on the
click. **T2** — toggle the plain tile on and off quickly five times: appear and
disappear counters stay equal at rest. Not run — an agent cannot.

## 8. Lanes

**Lane 1** (Opus; files in `LC-O`): §2, §3, §4, tests 1.1–9.3 (1.11 and 1.12 included), inventory and
census. Gate: unfiltered native suite, both closeout scripts silent,
`swift build --build-tests` 0 warnings, `theSevenRetentionSlotsAreMutuallyDistinct`
and every `ID-`/`TB-AH`/transition test unchanged and green. **Lane 2** (after
lane 1; Opus for the SDL tests, Sonnet for docs): §6, §7, tests 10.1–10.3,
`docs/api-overview.md` (a "Lifecycle" section), `docs/migration.md`
(SwiftUI → MetalUI: `.task` absent, decoration order, settle bound),
Backends/SDL build/test with `PKG_CONFIG_PATH=$PWD/.accesskit`, the
`swift:6.4-noble` container build, the pixel compare.

## 9. Deferred (reason, owner)

| Item | Reason | Owner |
|---|---|---|
| `.task(perform:)`, `.task(id:priority:_:)` | a main-actor task never runs inside `SDLPlatform.run()` (`LC-L`, probe `B1` on macOS and Linux) | the plan's gap 10 (SDL run-loop main-queue drain); probe `B2` is its measured candidate, `K1`/`K2` its SwiftUI answers |
| `onChange(of:perform:)` (one parameter) | deprecated by SwiftUI in macOS 14 | none |
| `onReceive`, `scenePhase`, app lifecycle | no request; needs a scene model MetalUI does not have (`PB-A`'s host family) | none |
| lifecycle modifiers on menu content | `MenuContent` is data, not an `ElementGroup` | none |
| a decoration after a lifecycle modifier | the transparent-scope constraint shared with `.animation(_:value:)`/`.environment` (divergence 120) | none |
| re-inserted content keeping its state mid-transition | `ID-C` resets at removal; changing it moves identity rules (divergence 123) | none |

## 10. Must not move — the checklist each lane re-measures

`theSevenRetentionSlotsAreMutuallyDistinct`; `MC-A`/`MC-C`/`MC-P` numbering;
`.id()` outermost; hit testing; accessibility; animation; focus; `List`
windowing and `TB-AH`; `Deferred`; text input — every existing test green
and unedited. Pixels 0 px in all fourteen images; `Expected.swift`
unedited; 0 `warning:` on both build systems; `MetalUILayout` imports only
`MetalUICore`; `MetalUIScene` only `MetalUIShaderTypes`; Backends/SDL and
`swift:6.4-noble` build; `theLegacyEngineSymbolsAreAbsentFromTheTestProcess`
green. `StateTable` is touched only by `LC-I`'s overlay: the sweep deletes
the same entries at the same point.
