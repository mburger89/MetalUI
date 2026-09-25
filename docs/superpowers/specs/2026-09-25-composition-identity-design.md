# Composition and identity (design)

Plan task 8 of
[`../plans/2026-09-12-swiftui-alignment.md`](../plans/2026-09-12-swiftui-alignment.md):
*"Verify `Group`, conditional content, explicit identity, `Component`, and
modifier placement against SwiftUI custom-view behaviour. Preserve MetalUI's
structural identity model where it matches, and close or document the currently
known state-retention and reused-value aliasing differences."* Branch
`feat/composition-identity` from `e3cb3e9` (task 7 closed: one engine, one
modifier type). Rulings `ID-A`…`ID-N` in
[`../2026-09-25-composition-identity-decisions.md`](../2026-09-25-composition-identity-decisions.md);
measurements and **the audit table** in `docs/record/55-composition-identity.md`
(record §55 §3); SwiftUI evidence in `docs/probes/swiftui-composition-identity.swift`
(new, arms A, V, X, S, G, L; revision 2 from the critic round, `ID-M`; output in
its header).

**Status, 2026-09-25: DESIGNED, critic round applied (`ID-M`).** No lane has run. In the design phase no
`Sources/` or `Tests/` file changed in a commit; one throwaway test file and
one scratch implementation were applied, run and reverted (record §55 §2), and
`git status --short` showed only this design's documents and the probe
afterwards.

## Contents

1. Baseline
2. What task 8 owns
3. The fixes
4. What is kept, and its pins
5. Lanes
6. Accounting, pixels, gates
7. For the Record phase
8. Risks

## 1. Baseline (`e3cb3e9`, measured 2026-09-25)

`swift build --build-system native --build-tests`; `swift test --build-system
native --no-parallel` → **`Test run with 1444 tests in 3 suites passed`**,
guards **84** (the log carries `FR-J no-argument frame: succeeded=true`), no
goldens (stage 7a), 0 `error:`, the only `warning:` SwiftPM's deprecation
notice. Divergences: **55 live**.

## 2. What task 8 owns

Record §55 §1 lists every item addressed to plan task 8 with its source;
`ID-L` disposes of each. Record §55 §3 is the audit: every concept the task
names, with SwiftUI's answer (probe arm), MetalUI's answer (test at
`e3cb3e9`), the verdict and the owner. In one line each:

- **Fixed** (EP-5): an `if` without `else` and a `for` loop take one
  structural slot (`ID-B`); content an evaluated conditional removes is reset
  (`ID-C`); `if`/`else` compiles inside proposal containers (`ID-D`);
  `@State`/`@Environment` bind inside `AnyElement` (`ID-E`); a dispatched
  handler reaches its own occurrence of a value placed twice (`ID-F`); `.id(_:)`
  on every element group (`ID-G`); a legacy `.background(alignment:content:)`
  (`ID-J`).
- **Kept, numbered**: duplicate sibling names (72, `ID-H`); modifiers on
  multi-member content stay one layer — 56 amended, 66, per-member attachments
  (73), the builder wrappers, `Component` decorations (`ID-I`); divergence 20
  (`ID-K`); a `for` loop's dropped element keeps its state (74, plan task 10,
  `ID-C`); a write outside dispatch (71, `ID-F`).
- **Matches, pinned**: record §55 §3's M rows; one gains a pin here (a changed
  `.id` resets, E3.8); divergence 48 retires (`ID-K`).

## 3. The fixes

### 3.1 One structural slot per `if` and per `for` (`ID-B`)

`OptionalGroup.requestGroupLayout` and `.requestProposalGroupLayout`, and
`ArrayGroup`'s two, become:

```swift
let slot = GlobalElementID(component: .positional(cursor), parent: parent)
cursor += 1                                   // whether or not content exists
guard var inner = wrapped else { /* ID-C, §3.2 */ return ([], nil) }
var innerCursor = 0
let (nodes, layout) = inner.requestGroupLayout(under: slot, at: &innerCursor, pass: &pass)
```

— `ArrayGroup` threads **one** `innerCursor` across all its members under the
slot (a named member still replaces its position within the loop). The
prepaint/paint halves are unchanged (they thread no ids). Paths: an `if`'s
content moves from `parent/k` to `parent/k/0`; a loop's i-th unnamed member
from `parent/(k+i)` to `parent/k/i`; everything after an `if` or a loop keeps
one index whatever the content. `SI-G` is reversed; `EitherGroup` is unchanged.

### 3.2 Reset on an evaluated removal (`ID-C`)

`StateTable` gains, internal:

```swift
private var producedSlots: Set<GlobalElementID> = []        // this frame
private var previouslyProducedSlots: Set<GlobalElementID> = [] // last frame
private(set) var subtreeResetScans = 0                       // work counter (C2.9)
func noteProduced(_ slot: GlobalElementID)
func noteAbsent(_ slot: GlobalElementID)   // resets iff previouslyProducedSlots.contains(slot)
```

`noteAbsent` deletes every entry whose id has `slot` as a proper ancestor,
**except** an entry whose own component is `.named(ElementID("$focus"))` or
`.named(ElementID("$ax"))`, and bumps `subtreeResetScans`. `sweep()` swaps the
two sets (`removeAll(keepingCapacity: true)`, no per-frame allocation once warm).
Callers: `OptionalGroup` (both copies) notes its slot produced or absent;
`EitherGroup` (both copies, §3.3) notes the taken branch id produced and the
untaken one absent. Nothing else calls `noteAbsent`, so an unevaluated subtree
(a `List` row out of the window) keeps `TB-AH`'s retention, and `sweep()` itself
never resets (M2h). `ArrayGroup` does not reset (divergence 74).

### 3.3 `if`/`else` inside proposal containers (`ID-D`)

```swift
extension EitherGroup: ProposalElementGroup
    where First: ProposalElementGroup, Second: ProposalElementGroup {
    public mutating func requestProposalGroupLayout(under parent: GlobalElementID?,
                                                    at cursor: inout Int,
                                                    pass: inout LayoutPass) -> ([ProposalNodeID], Layout)
}
```

Numbering identical to the untyped entry (`branchIndex = cursor; cursor += 2`;
the taken branch under `.positional(branchIndex)` or `+ 1`, members from 0),
plus §3.2's notes. `switch` is nested `EitherGroup`s and needs nothing more.

### 3.4 `AnyElement` binds (`ID-E`)

`AnyElementBox.requestLayout`, `.prepaint` and `.paint` each call
`StateBinder.bind(element, in: pass.frame, id: id)` before forwarding. The
`extension AnyElement: ElementGroup` block and `EnvironmentProperty.swift`'s
"inside `AnyElement` it is always unbound" paragraphs become false; lane 2 (the
owner of `ElementGroup.swift`) rewrites the first, lane 1 the second.

### 3.5 Dispatch resolves the occurrence (`ID-F`)

New `Sources/MetalUI/StateDispatch.swift`:

```swift
@MainActor enum StateDispatch {
    static private(set) var owner: GlobalElementID?
    static func dispatching<R>(to id: GlobalElementID, _ body: () throws -> R) rethrows -> R
}
```

`State.Box` gains `var occurrences: [GlobalElementID]?` (every slot bound this
generation, set only once a second, different slot is bound in the same
generation — the moment `noteAliasedStateBox()` already fires — and cleared on
the first bind of a later generation). `wrappedValue`'s get and set use
`box.resolvedSlot`: when `occurrences != nil` and `StateDispatch.owner != nil`,
the occurrence whose `parent` (the element id) is the owner or an ancestor of
it; otherwise `slotID` as today. `Environment.Box` does the same with its
`values` (one snapshot per occurrence, keyed by the element id —
`BindableEnvironment.bind` gains the id, `StateReflection.swift`). The dispatch sites wrap the handler
call: `Window`'s click (`hit.id`), `dispatchKey` (each chain `id` whose handler
runs), `dispatchAction` (its target id), `WindowAccessibility`'s press and
adjust (`id`), and the text-input path's calls into a field's edit and submit
callbacks (the field's id; submit added by `ID-N` item 1). No other behaviour of any site moves.

### 3.6 `.id(_:)` on every element group (`ID-G`)

New `Sources/MetalUI/ExplicitIdentity.swift`:

```swift
public struct IdentifiedGroup<Content: ElementGroup>: ElementGroup {
    public var content: Content
    public var name: ElementID
}
extension IdentifiedGroup: ProposalElementGroup where Content: ProposalElementGroup {}
extension ElementGroup {
    /// Names this group among its siblings: one index, named; its content numbers from 0 under it.
    public func id(_ name: String) -> IdentifiedGroup<Self>
}
```

`requestGroupLayout`: `let id = GlobalElementID.child(of: parent, at: cursor,
name: name); cursor += 1; var inner = 0` — content under `id`, nodes returned
unchanged. `StyledElement.id(_:) -> Self` (`Box.swift`) is untouched and wins
for every `StyledElement` (guard G3.1).

### 3.7 A legacy `.background(alignment:content:)` (`ID-J`)

`BackgroundModifier<Content: ElementGroup, Background: ElementGroup>` —
`OverlayModifier`'s `LR-FX` shape: two entries (untyped `requestLayout` through
`requestGroupLayout`, typed `requestProposalLayout` when both sides are proposal
content), a shared background-side id (`.child(of: id, at: -1)`, `MC-P`) and a
shared `attach` through `lowerAttachmentChildren`; prepaint and paint background
first. One `.background(alignment:content:)` on `ElementGroup` replaces the
`ProposalElementGroup` one. A primary of 0 or 2+ nodes traps naming its count.

## 4. What is kept, and its pins

| kept | pin | ruling |
|---|---|---|
| duplicate sibling names share one identity (72) | `twoSiblingsWithTheSameIDShareOneStateEntry`; E3.7 | `ID-H` |
| `.frame` on a multi-member `Component` is one layer over a row (56, amended) | `aFrameOverAMultiMemberComponentFramesEachMember`; N3.1 (the row's alignment) | `ID-I` 1–2 |
| `.overlay` / `.background { }` on a multi-member primary trap (73) | `aLegacyOverlayOnATwoMemberComponentTrapsNamingItsPrimaryCount`; B3.3 | `ID-I` 3 |
| a modifier on a multi-cell `GridRow` traps (66) | `aModifierOnAMultiCellGridRowTraps` | `ID-I` 4 |
| builder wrappers over 0/2+ nodes trap | their existing exit tests (`CN-Q`) | `ID-I` 5 |
| `Component` `background`/`onClick`/`focusable` not offered | `decorationBackedModifiersAreNotOfferedOnAComponent` | `ID-I` 6 |
| a layer added at run time is adopted by the new outermost layer (20) | `aLayerAddedAtRunTimeIsAdoptedByTheNewOutermostLayer` | `ID-K` |
| a write outside input dispatch reaches the last-bound occurrence (71; SwiftUI: its own, probe S5) | `aClosureRunOutsideInputDispatchWritesTheLastBoundOccurrence` (renamed, lane 2) | `ID-F` |
| a `for` loop's dropped element keeps its state (74) | C2.4b | `ID-C` |

## 5. Lanes

**Three lanes, run in order 1 → 2 → 3, disjoint files.** Each lane: `swift
package clean` first (lane 1 adds a stored property to `State.Box`/`Environment.Box`;
lane 3 changes `BackgroundModifier`'s public generic constraints); commit the
red tests first; build under both build systems (0 `error:`, the only
`warning:` SwiftPM's notice); run the **whole** suite unfiltered and read the
summary line; mutations from a committed tree, restored from a copy, whole
suite, `git status --short` after each, every reddened test named; each new
typecheck guard mutated red once. Opus for each lane and its verifier.

"Red before" is the answer at `e3cb3e9`; a test that pins behaviour that
already holds says **green (pin)** and is proven by its mutation instead.

### Lane 1 — occurrences and erasure (`ID-E`, `ID-F`)

**Files.** New `Sources/MetalUI/StateDispatch.swift`; `State.swift`;
`EnvironmentProperty.swift`; `StateReflection.swift` (the id passed to an
environment bind); `AnyElement.swift`; `Window.swift` (the click and
text-input dispatch sites only); `WindowAccessibility.swift`; `Focus.swift`
(`dispatchKey`); `Action.swift` (`dispatchAction`). Tests: new
`Tests/MetalUITests/OccurrenceIdentityTests.swift`; `EnvironmentTests.swift`
(one rename). **Not** `IdentityTests.swift` (lane 2's): its
`aHandlerWritesTheStateOfTheOccurrenceThatRegisteredIt` invokes the closure
directly, outside dispatch, and must stay **green and unedited** through this
lane — that is divergence 71's pin, and lane 1 confirms it in its record.

| test | red before | mutation that must redden it |
|---|---|---|
| **O1.1** `aClickWritesTheStateOfTheOccurrenceThatWasClicked` — through a real `Window` (`makeFakeWindow`), `let p = ClickCounter(); Row { p; p }` (`@State count`, `onClick { count += 1 }`), click occurrence 0: counts `[1, 0]`; then occurrence 1: `[1, 1]`; `table.aliasedStateBoxes > 0` still | `[0, 1]` after the first click | **M1a** `resolvedSlot` returns `slotID` always; **M1b** the click site does not set the owner |
| **O1.2** `aKeyHandlerWritesTheStateOfTheOccurrenceThatHandledIt` — the value focusable with an `onKey` writing its `@State`, placed twice, occurrence 0 focused, a key: only occurrence 0 moves | occurrence 1 moves | **M1c** `dispatchKey` sets no owner |
| **O1.3** `anActionAndAnAccessibilityPressAndAdjustEachWriteTheirOwnOccurrence` — three arms, each its own `@State`: a `Keymap` action to focused occurrence 0; an AX press on occurrence 0 (was 1: the last-bound occurrence cannot redden, `ID-N` item 2); an AX increment on occurrence 0 | the last-bound occurrence moves in each arm | **M1d** `dispatchAction`, **M1e** the press, **M1f** the adjust — each without its owner; each reddens its own arm only |
| **O1.4** `aComponentPlacedTwiceWritesTheOccurrenceWhoseInnerHandlerRan` — a `Component` value with `@State`, its body a `Box().onClick { n += 1 }`, placed twice; click occurrence 0's inner box, then occurrence 1's: `[1, 0]`, `[1, 1]` (`ID-N` item 2) | `[0, 1]`, `[0, 2]` | **M1g** match `owner == slot.parent` exactly (no ancestor walk) — reddens O1.4 and O1.6 (`ID-N` item 4) |
| **O1.5** `aDispatchedHandlerReadsItsOwnOccurrencesEnvironment` — one value under two `.environment` scopes (7 and 9), each click records the handler's read: `[7, 9]` | `[9, 9]` | **M1h** `Environment.Box` resolution ignores the owner |
| **O1.6** `aTextFieldEditWritesTheOccurrenceThatWasEdited` — a `Component` value holding `@State text` with `TextField(text:onChange:)` writing it and `@State submits` written by `.onSubmit`, placed twice; type into occurrence 0, then return | occurrence 1's text and submit count change | **M1i** the edit site sets no owner (edit arm); **M1l** the submit site sets no owner (submit arm, `ID-N` item 1) |
| **O1.7** `stateInsideAnAnyElementPersistsAcrossFrames` — `Row { AnyElement(leaf) }`, `@State n += 1` in layout, three frames: slot reads 3 | slot `nil` (record §55 §2.2) | **M1j** drop the bind in `AnyElementBox.requestLayout` |
| **O1.8** `stateInsideAnAnyElementIsReboundForPrepaintAndPaint` — one `AnyElement` value placed twice, each occurrence stamping a distinct number in layout and reading it in prepaint and paint: `[1, 2]`, `[1, 2]` | initial values | **M1k** drop the prepaint and paint re-binds (layout-only: `[2, 2]`) |

**R** (renamed, retirement row owed): `anEnvironmentPropertyInsideAnyElementIsInertAndReadsTheDefault`
→ **`anEnvironmentPropertyInsideAnyElementReadsItsScope`**, asserting the
scope's value (M1j reddens it too). **Lane 1 adds 8 tests** (1444 → 1452), no
guard.

### Lane 2 — structural slots, reset, proposal if/else (`ID-B`, `ID-C`, `ID-D`)

**Files.** `ElementGroup.swift` (`OptionalGroup`, `EitherGroup`, `ArrayGroup`;
the `AnyElement` extension's doc paragraph, §3.4); `ProposalElementGroup.swift`
(the typed copies; the new `EitherGroup` conformance); `StateTable.swift`
(§3.2); doc lines in `ElementID.swift` (identity depth now counts every `if` and
`for`), `Grid.swift` (the "universal trailing-sibling rule" wording) and
`Sources/MetalUIDemoContent/DemoContent.swift` (the modal `if`'s comment — a
comment only; no statement of the demo moves). Tests: new
`Tests/MetalUITests/ConditionalIdentityTests.swift` and
`ConditionalIdentityCompileGuards.swift`; T/R rows in `IdentityTests.swift`,
`GridElementTests.swift`, `AccessibilityEndToEndTests.swift`,
`ContainerIntegrationTests.swift`, `FocusTests.swift`, `InputDispatchTests.swift`,
`LegacyOverlayTests.swift`, `LoweringCorpusTests.swift`,
`ModifierCompositionProofTests.swift`, `ProposalGroupEntryTests.swift` (and
`StateTableTests.swift` only if a count literal moves). **Two copies of each
group**: every mutation below names the copy it is applied to, and each copy is
mutated on its own ("a copy of a pinned implementation is unpinned").

| test | red before | mutation that must redden it |
|---|---|---|
| **C2.1** `anElementAfterAVanishingIfKeepsItsOwnState` (**R** from `anElementAfterAVanishingIfAdoptsTheVanishedElementsState`) — `Row { if flag { C }; C }` true → false: trailing at `root/1` reads 2; the `if` content's entry (`root/0/0`) is gone (§3.2); a second arm (`ID-M` item 5, probe G7) makes the trailing sibling a two-member `Component` with `.padding(Pixels(4))` and reads both members' own counts | trailing at `root/0` reads 2 (adoption) | **M2a** untyped `OptionalGroup` advances the cursor only when `wrapped != nil` |
| **C2.2** `anElementAfterAnAppearingIfKeepsItsOwnState` — false → true: trailing `root/1` reads 2, the new content `root/0/0` reads 1 | the content reads 2, the trailing 1 | **M2a** |
| **C2.3** `aTwoMemberIfTakesOneSlotAndNumbersItsMembersInside` — `Row { if flag { C; C }; C }` across flips: members at `root/0/0`, `root/0/1`; trailing `root/1` reads the frame count | trailing adopts | **M2b** untyped: reserve the slot but number the members with the outer cursor (no nesting) |
| **C2.4** `aShrinkingForLoopLeavesTheTrailingSiblingsStateAlone` — `Row { for _ in 0..<n { C }; C }`, n 2 → 1: trailing `root/1` reads 2; **C2.4b** (same test, divergence 74's pin) n 2 → 1 → 2: iteration `root/0/1` reads 2 (retained) | trailing adopts (record §55 §2.2 V6) | **M2c** untyped `ArrayGroup` reserves no slot |
| **C2.5a** `removingACellFromARowLeavesTheNextCellsStateAlone` (**R** from `removingACellFromARowHandsItsStateToTheNextCell`), **C2.5b** `removingAWholeGridRowLeavesTheNextRowsStateAlone` (**R** from `removingAWholeGridRowHandsItsStateToTheNextRow`) — the next cell/row keeps its own reads | hands on (divergence 69) | **M2a′** the **typed** `OptionalGroup` copy with M2a's edit — reddens these two and no untyped test |
| **C2.6** `contentAnIfRemovesIsResetWhenItReturns` — `Row { if flag { C("c") }; C("t") }` true/false/true: `c` reads 1, `t` 3 | `c` reads 2 | **M2d** `noteAbsent` never resets |
| **C2.7** `anIfElseBranchFlippedAwayAndBackStartsFresh` — if/else true/false/true: the first branch's member reads 1 | reads 2 | **M2e** `EitherGroup` notes no absent branch (only `OptionalGroup` resets) |
| **C2.8** `aResetKeepsTheFocusAndAccessibilityRetentionSlots` — a focused, AX-published element inside an `if` goes false for one frame: `window.focusedElement` unchanged, its `$ax` entry present, its `$state0` entry gone | green on the first two, red on the third (retained) | **M2f** reset without the exemption — reddens this and `focusOnAnElementThatStopsBeingProducedIsRetainedWithinTheWindow` |
| **C2.9** `aResetScansTheTableOnlyOnATransition` — an `if` true for 3 frames, false for 3, true for 3: `subtreeResetScans` reads exactly 1 | does not compile (no counter) | **M2g** `noteAbsent` scans whenever absent (counter 3) |
| **C2.10** `aConditionalInAWindowedListRowIsNotResetByAnExcursion` — a `List` row whose content holds `if true { stateful }`, scrolled out for 2 generations and back (above the 256 threshold, as `aListRowsStateSurvivesABoundedExcursionButNotALongerOne` does): its state survives | green (pin) | **M2h** `sweep()` resets every previously produced slot not produced this frame |
| **C2.11** `anIfElseInsideAProposalStackTakesItsBranchIdentity` — `HStack { if flag { probe } else { probe }; probe }`: branches at `root/0/0` / `root/1/0`, trailing `root/2`; a flip resets the branch and keeps the trailing probe | does not compile | **M2i** the typed `EitherGroup` copy numbers both branches at `branchIndex` |
| **C2.12** `aFocusedTextFieldInsideAToggledIfKeepsFocusAndStartsItsEditStateFresh` (`ID-M` item 4) — through a real `Window` (`makeFakeWindow`), a `TextField` inside `if flag`, focused, with a selection and marked text; `flag` false for one frame then true: while absent `setTextInputArea(nil)` is recorded (the `e3cb3e9` behaviour); `window.focusedElement` is the field's id throughout; on return its `TextEditState` equals `TextEditState()` and the recorded input area is the fresh caret's | red on the state half (the old selection and marked text come back) | **M2d** reddens the state half; **M2f** the focus half |
| **G2.1** `anIfElseAndASwitchCompileInEveryProposalContainer` (`typecheckFile`) — if/else and a three-case `switch` inside `HStack`, `VStack`, `ZStack`, `Grid`, `GridRow`, and a proposal `.overlay` content, compile; control: `HStack { if f { Box() } else { Box() } }` does not (`#require`d to disagree) | the positive does not compile | delete the conformance |

**T** (body change, same subject, new literal — reason in the lane's record
section): `reorderingANamedListCarriesEachItemsState`,
`aForLoopInsideAProposalContainerPlacesEveryIterationInItsOwnSlot`,
`anOverlaysIdentityDoesNotDependOnTheIndicesItsPrimaryConsumed`,
`aBackgroundsContentKeepsItsStateWhenThePrimaryChangesShape`,
`aLegacyOverlayKeepsItsOverlaysStateThroughAFlipOfItsPrimarysShape` (the lane
reads why its `kept(true)` arms moved before editing; the overlay's state must
still be kept), `focusOnAnElementThatStopsBeingProducedIsRetainedWithinTheWindow`
(the id literal gains the slot), `theWholeDemoReportsExactlyTheFieldsAndSitesLaterStagesOwn`
(the modal's ids), and the `table.count` literals of
`flippingAnEitherBranchResetsTheBranchesState`,
`aBranchWithTwoMembersDoesNotLeakStateIntoAOneMemberBranch` and
`aBranchReservesBothIndicesSoASiblingCannotLandOnTheUntakenOne` (the reset
removes the tombstones they count). **R** (renamed, retirement row owed):

- `namingTheLaterSiblingIsWhatSurvivesAVanishingIf` →
  **`namingEitherSideOfAVanishingIfLeavesTheTrailingSiblingsStateAlone`** (both
  arms now read 2);
- `aHeldElementWhoseIDIsAdoptedPressesTheAdopter` →
  **`aHeldElementWhoseNameMovesPressesItsNewOwner`**: `AB-H`'s hazard re-spelled
  through the path that still has it (a named item in a `for` loop whose name
  moves to another item), plus an arm showing a vanishing `if` no longer
  transfers the held element;
- `aVanishingIfBetweenPressAndReleaseClicksTheTrailingSibling` →
  **`aPressHeldAcrossARebuildClicksItsOwnTargetAndAVanishedTargetClicksNothing`**:
  arm 1, press A, A vanishes, release — nothing fires; arm 2, press B, A (before
  it) vanishes, release — B fires. **The `hit.id === pressed` mutation must
  still redden arm 2** (it is the only test that straddles a frame with a
  press);
- `aHandlerWritesTheStateOfTheOccurrenceThatRegisteredIt` →
  **`aClosureRunOutsideInputDispatchWritesTheLastBoundOccurrence`** — divergence
  71's pin, assertions unchanged, doc rewritten (lane 1's `ID-F` landed).

Tests that exercise the reset drive frames through `Frame.render` (whose
`stateTable.sweep()` swaps the produced sets) or a `Window`; a layout-only
frame never swaps them and so never resets.

**Lane 2 adds 11 tests** (10 + guard G2.1; 1452 → 1463), guards 84 → 85.

### Lane 3 — explicit identity and the legacy background (`ID-G`, `ID-J`, pins)

**Files.** New `Sources/MetalUI/ExplicitIdentity.swift`;
`NativeBackgroundModifier.swift`. Tests: new
`Tests/MetalUITests/ExplicitIdentityTests.swift`,
`ExplicitIdentityCompileGuards.swift`, `LegacyBackgroundTests.swift`; one new
test in `LoweringComponentTests.swift`; the one re-spelled guard in
`ErasureCompileGuards.swift` (`ID-M` item 1).

| test | red before | mutation that must redden it |
|---|---|---|
| **E3.1** `anIDOnAProposalStackResetsItsContentWhenItChanges` — `HStack { probe }.id("g\(n)")`: n constant → the probe counts frames; n changes → it restarts at 1 | does not compile | **M3a** `IdentifiedGroup` numbers under `.positional(cursor)` (the name ignored) |
| **E3.2** `anIDOnAGridAndOnAGridRowResetsTheirCells` — the same on a `Grid` and on one `GridRow` inside it | does not compile | **M3a** |
| **E3.3** `anIDOnAComponentResetsItsStateAndItsMembers` | does not compile | **M3a** |
| **E3.4** `anIDOnAGroupTakesOneSlotAndNumbersItsContentInside` — paths: `parent/named(x)/0`, `/1`; a trailing sibling at the next index | does not compile | **M3b** content numbered with the outer cursor under `parent` |
| **E3.5** `anIDOnAGroupIsLayoutTransparent` — `VStack { HStack { a; b }.id("x") }`: every rect and `tree.nodeCount` equal to the same tree without the id | does not compile | **M3c** register the content under an extra native node (a one-child `ZStack`) |
| **E3.6** `aNamedProposalItemKeepsItsStateThroughALoopReorder` — `HStack { for item in items { probe.id(item) } }`, items reordered: each keeps its count | does not compile | **M3a** |
| **E3.7** `twoSiblingGroupsWithTheSameIDShareOneIdentity` — divergence 72 on the new API | does not compile | **M3a** (shares nothing — the pin's shared count reads 1, 1) |
| **E3.8** `changingAnElementsIDResetsItsState` — `Box`-based probe `.id("a\(n)")` (the existing `StyledElement.id`): constant keeps, changed resets | green (pin; record §55 §3) | **M3d** `GlobalElementID.child(of:at:name:)` ignores `name` for the component (reddens many; name this one among them) |
| **E3.9** `anIDWrittenInsideAModifierStillResetsWhenItChanges` (`ID-M` item 5, probe X7) — `Box`-based probe `.id("a\(n)").padding(Pixels(4))`: constant keeps, changed resets | green (pin) | **M3d** (name this one among those it reddens) |
| **G3.1** `anIDOnAStyledElementStillReturnsItsOwnType` (`typecheckFile`) — `let b: Box<EmptyGroup> = Box().id("x")` and a legacy chain `.padding(Pixels(4)).id("x")` keeping `ModifiedContent<…, ModifierLayer>` compile; control `let g: IdentifiedGroup<Box<EmptyGroup>> = Box().id("x")` does not (`#require`d disagreement) | the control's type does not exist, so the disagreement is not measurable — the guard fails its `#require` | **M3e** a second `id(_:) -> IdentifiedGroup<Self>` on `StyledElement` (ambiguity) |
| **G3.2** `anIDOnAProposalGroupEntersAProposalContainer` (`typecheckFile`) — `HStack { Rectangle(…).id("x") }`, `Grid { GridRow { … }.id("r") }`, `VStack { SomeProposalComponent().id("c") }` compile; control `HStack { Box().padding(Pixels(4)).id("x") }` does not | does not compile | **M3f** delete `IdentifiedGroup`'s conditional `ProposalElementGroup` conformance |
| **B3.1** `aLegacyBackgroundSitsBehindItsPrimaryAtThePrimarysSize` — `Box().cssWidth(px(40)).cssHeight(px(20)).background(alignment: .topLeading) { Box().cssWidth(px(10)).cssHeight(px(10)) }`: background rect (0, 0, 10, 10) inside the primary's (0, 0, 40, 20); the scene paints the background first; a click at (5, 5) with both clickable reaches the primary | does not compile | **M3g** paint the background after the primary |
| **B3.2** `aLegacyBackgroundsContentKeepsItsStateWhenThePrimaryChangesShape` — `MC-P`'s `-1` side over a legacy primary whose `if` flips | does not compile | **M3h** number the background side under `id` at the cursor after the primary |
| **B3.3** `aLegacyBackgroundOnATwoMemberComponentTrapsNamingItsPrimaryCount` (exit test; divergence 73) | does not compile | **M3i** drop the count precondition (attach to the first member) |
| **G3.3** `theLegacyBackgroundKeepsTheTokenOverloadAndTheProposalSpelling` (`typecheckFile`) — `Box().background(.accent)` still infers the `Box`/chain type; `HStack { Rectangle(…).background { Rectangle(…) } }` compiles and infers `BackgroundModifier<Rectangle, Rectangle>`; control `HStack { Box().background { Box() } }` does not | does not compile (the legacy spelling) | **M3j** restore the `ProposalElementGroup`-only constraint on the `Content` parameter |
| **N3.1** `aMultiMemberFrameRowAlignsItsMembersByTheFramesOwnAlignment` (`LoweringComponentTests`) — a pair 30×10 and 50×30 under `.frame(width: 70, alignment: .top)` in a 300×60 `Box`: the short member at y 0, not 10 (divergence 56's `LR-BP` sub-row) | green (pin) | **M3k** `alignment: .center` on the row in `lowerShownLegacyFrameLayer` (stage 3's `M5g`, green until now) |

**T** (`ID-M` item 1, measured): `backgroundCannotBeCalledOnAComponent`
(`ErasureCompileGuards.swift`) — with `ID-J`'s overload on `ElementGroup` its
fixture `Leafless().background(.accent)` is still rejected but with
`missing argument label 'alignment:'`/`missing argument for parameter
'content'`, so `messages.contains("background")` fails. Re-spelled: fixture
`Leafless().background(ColorToken.accent)`, reason `contains("ColorToken")`
(the measured diagnostic: `cannot convert value of type 'ColorToken' to
expected argument type 'ProposalAlignment'`); mutated red once by declaring
`background(_: ColorToken)` on `Component`. Its doc says the content
`.background { }` is offered, as `.overlay { }` is. `ErasureCompileGuards.swift`
joins lane 3's files for this one edit.

**Lane 3 adds 16 tests** (13 + guards G3.1–G3.3; 1463 → **1479**), guards 85 →
**88**.

## 6. Accounting, pixels, gates

- **Suite: 1444 → 1452 → 1463 → 1479** (`ID-M`). Guards 84 → 84 → 85 → 88.
  No goldens. Every removed or renamed `@Test` has a retirement row in its
  lane's record section (`goldensUnchanged`): the R rows above, seven in lane
  2 (C2.1, C2.5a, C2.5b and the four listed after its table), one in lane 1;
  no test is deleted outright.
- **Pixels.** 0 px against `e3cb3e9` in all fourteen offscreen images after
  every lane (`docs/probes/demo-pixels/compare.sh <workdir> e3cb3e9 <HEAD>`).
  **Lane 2 moves the demo's ids** — the modal sits behind an `if`, and the
  `List` after it keeps one index across the toggle instead of sliding — and
  must move no pixel: the images are static frames, the `List` holds no
  cross-frame state (the demo's own comment), and the modal's elements are
  fresh on each opening either way. Lanes 1 and 3 touch nothing the demo
  builds (it holds no `AnyElement`, no value placed twice and no `.id` on a
  group; `aliasedStateBoxes` reads 0 outside the two identity tests).
  `DemoFrameDeterminismTests`' `Expected.swift` stays unedited (it pins the
  scene, not ids).
- **Must not move** (each lane re-reads, whole suite): `theSevenRetentionSlotsAreMutuallyDistinct`;
  `MC-A`/`MC-C`/`MC-P` numbering (only an `if`'s and a loop's content gain a
  level; a modifier's layers do not); `.id()` outermost; hit testing,
  accessibility, animation, focus (C2.8's exemption), the scrim, `List`
  windowing and `TB-AH` (C2.10), `Deferred`, `TextField`/`TextEditor`;
  `everyProductionTreeBuildsOnAOneMegabyteThread`;
  `everyProductionRootsDeepestNativeLevelIsMeasured` (identity depth is not
  native depth); `theLegacyEngineSymbolsAreAbsentFromTheTestProcess`.
- **Elsewhere** (lane 3's close, or the Record phase): `MetalUILayout` imports
  only `MetalUICore` (anchored grep); `Backends/SDL` builds and tests
  (`PKG_CONFIG_PATH=$PWD/.accesskit`); a `swift:6.4-noble` container builds and
  runs `MetalUICoreTests`, `MetalUILayoutTests`, `MetalUICrossPlatformTests` if
  Docker is available; 0 `warning:` on both build systems.
- **Real window.** `xcrun swiftc -O docs/probes/appkit-screen-lock-state.swift
  -o /tmp/lockstate && /tmp/lockstate`: with no `CGSSessionScreenIsLocked` line
  and `displayAsleep main: 0`, run `docs/probes/window-capture/capture.sh
  <scratch> e3cb3e9 <HEAD>` after lane 2 (the lane that moves ids) and at the
  Record phase; otherwise record the probe's output and that the capture is owed.

## 7. For the Record phase

- Record §04: retire 18, 19, 48, 69; add 71–74; amend 56 (record §55 §4);
  live count stays 55. **Name the live pins** (`ID-M`): 48's listed pin
  `aComponentsWidthStillOverwritesItsMembersDeclaredWidth` and 56's
  `aFrameWrapsAComponentsBodyWithoutOverwritingItsChildren` do not exist at
  `e3cb3e9`; the live ones are `aComponentsWidthFramesEachMember` and
  `aFrameOverAMultiMemberComponentFramesEachMember` (plus N3.1 for 56's
  alignment sub-row).
- Record §05: delete the "`@State` inside an `AnyElement`" row (and the
  `@Environment` sentence with it).
- `CLAUDE.md`/`AGENTS.md`: the "Identity is structural" bullets (a vanishing
  `if` no longer shifts; the remedy sentence goes), "`@State`" ("Inert inside
  `AnyElement`" and divergence 19's sentence), "`Component`" ("No
  `.background`/`.id()`" → `.id()` exists via `IdentifiedGroup`), the grid
  bullet ("A vanishing `if` inside a grid moves the cells after it" and "no
  built-in proposal element has `.id()`"), the vocabulary list (`.id(_:)`,
  `IdentifiedGroup`, the legacy `.background { }`), the `ID-` prefix line (next
  unused as the decisions doc's last heading says), counts and guards, and a
  plan-8 entry in "Where things are".
- The plan's task 8 checkbox: ticked by the Record phase if every row of record
  §55 §3 reads as the lanes left it.

## 8. Risks

1. **An unexpected id consumer.** A test or production path that builds a
   `GlobalElementID` through an `if` or a `for` by hand. The scratch run found
   thirteen tests and no production path (the demo captures `counterID` at run
   time); lane 2 re-runs the whole suite red-first.
2. **The reset's exemptions.** If an animation, scroll or text-selection test
   depends on state retained through an `if`, it reddens under C2.6's
   implementation; the lane stops and records it rather than widening the
   exemption silently (a widened exemption is a ruling).
3. **Overload resolution.** `ElementGroup.id` against `StyledElement.id`, and the
   generalized `.background(alignment:content:)` against the token overload
   (G3.1, G3.3); the solver-budget guard (`FR-S`) runs in every lane.
4. **Dispatch sites.** A handler path lane 1 did not enumerate stays on
   divergence 71's answer; O1.1–O1.6 are one arm per enumerated site, and the
   lane greps for every other call of a `Handlers` closure before closing.
