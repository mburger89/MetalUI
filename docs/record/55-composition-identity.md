# 55 — Composition and identity (plan task 8)

Branch `feat/composition-identity` from `e3cb3e9`. Spec
`docs/superpowers/specs/2026-09-25-composition-identity-design.md`; rulings
`ID-A`…`ID-M` in `docs/superpowers/2026-09-25-composition-identity-decisions.md`;
probe `docs/probes/swiftui-composition-identity.swift` (new). This section is
the design phase's; each lane appends its own.

## 1. What was addressed to plan task 8

Collected by `grep -rn -i "plan task 8\|task 8\b"` over `docs/record/` and
`docs/superpowers/*.md` (hits about *other* milestones' "Task 8" — sizing,
tombstones, text m2, absolute positioning, build — discarded), then read at
each hit:

| source | item |
|---|---|
| record §54 §8.5, §10.3; `LR-FX` item 6 | a legacy `.background { content }` |
| record §54 §10.3; `LR-GA` item 3; `LR-FY` item 2; record §04 (2026-09-25) | `.frame` on a multi-member `Component` distributing per member; divergence 56's remainder (`TB-M`) |
| record §54 §10.3; N1.7 | a `Group`-style overlay on a multi-member primary |
| record §54 §11; `LR-GG` item 5; `LR-BP` | the per-member row's cross-axis alignment (`M5g` green) |
| record §54 §10.3 | `OnTapModifier` and `BackgroundModifier` as separate types |
| record §22 (grids) §2327, §2371; `GR-J`; `GR-N` | `.id()` on `Grid`/`GridRow`; "no built-in proposal element has `.id()`" |
| record §22; `GR-O` 9; record §04 row 69 | divergence 69, a vanishing cell/row hands its state on |
| `GR-J` ("Cost if wrong") | whether grid rows should be identity-transparent |
| record §10 §1159; modifier-composition carried table | divergence 19; `@State` inside `AnyElement` |
| record §11 §554, §1809; `EV-M` | `@Environment` inside `AnyElement` |
| record §17 §1558; containers carried table; `CN-Q` | builder wrappers with zero or several nodes |
| record §18 §1498; `LR-V` | `Component` `background`/`onClick`/`focusable` |
| modifier-composition carried table | `EitherGroup: ProposalElementGroup` ("tasks 6/8") |
| grids decisions `GR-J` | a modifier distributing over a multi-cell `GridRow` (divergence 66) |
| the task text | `Group`, conditional content, explicit identity, `Component`, modifier placement; divergences 18, 19, 48, 56; trailing-sibling adoption |

`docs/record/09-swiftui-alignment.md:1065` ("first `Component` in a demo (task
8)") and `docs/record/07-layout-cost.md:247`, `06-build.md` are other
milestones' Task 8 and carry nothing here.

## 2. Measurements (design phase)

### 2.1 Baseline

`swift build --build-system native --build-tests`, then `swift test
--build-system native --no-parallel` at `e3cb3e9` in this worktree: **`Test run
with 1444 tests in 3 suites passed after 81.223 seconds`**; the guards ran (`FR-J
no-argument frame: succeeded=true deprecations=2`).

### 2.2 SwiftUI, and MetalUI's current answers

The probe (`docs/probes/swiftui-composition-identity.swift`) was run in both
forms (`/usr/bin/swift` and `xcrun swiftc`, Apple Swift 6.4,
swiftlang-6.4.0.33.1, macOS 27.0 26A428): byte-identical stdout, exit 0, 0
stderr lines each. Its output and an arm-by-arm reading are in its header. Two
revisions in this session: the first had G1/G2 only at the root (one instance —
the root has no parent stack to distribute into), so G3–G7 were added hosted in
a stack; then V9/V10 (the three-generation if/else and `ForEach` arms).

MetalUI's current answers that no existing test states were read from one
throwaway test file (`Tests/MetalUITests/ZZScratchTask8.swift`, filtered run,
then deleted; never committed):

| arm | fixture | MetalUI at `e3cb3e9` | SwiftUI |
|---|---|---|---|
| V2 | `Row { if flag { C }; C }`, false → true | the new `if` content reads **2** (the trailing element's count), the trailing element **1** (reset) | trailing kept |
| V5 | `Row { if flag { C("c") }; C("t") }`, true/false/true | `c` reads **2** (retained) | new |
| V4/V9 | `Row { if flag { C } else { C } }`, true/false/true | first branch reads **2** (retained) | new |
| V6 | `Row { for _ in 0..<n { C }; C }`, n 2 → 1 | trailing element (now slot 1) reads **2** — adopted | trailing kept |
| S2 | `Row { AnyElement(leaf with @State n += 1) }`, 3 frames | slot **nil** (the plain leaf: 3) | works |
| L1 | `Column { Pair().frame(width: 70) }` (30×10, 50×10) | column **140×10**, members at (20, 0) and (80, 0) — a row | 70×20, stacked |
| L5 | `Column { 30×10; EmptyComponent().frame(width: 70) }` | the frame layer is **70×0** at (0, 10), the column 70 wide | 30×10 |
| D | `HStack { if flag { Rectangle } else { Rectangle } }` | **does not compile**: `EitherGroup<Rectangle, Rectangle>` is not a `ProposalElementGroup` | compiles |

### 2.3 A scratch implementation of `ID-B`, whole suite

Both copies of `OptionalGroup` and `ArrayGroup` changed to reserve one index and
number their content under a slot id (the spec's lane 2 shape, no reset), the
scratch test file present: `Test run with 1451 tests in 3 suites failed … with
36 issues` (1451 = 1444 + 7 scratch). **Thirteen tests reddened**, each read at
its assertion:

| test | why |
|---|---|
| `anElementAfterAVanishingIfAdoptsTheVanishedElementsState` | the adoption it pins is gone |
| `namingTheLaterSiblingIsWhatSurvivesAVanishingIf` | the unnamed arm now survives too; counts |
| `reorderingANamedListCarriesEachItemsState` | path literals: items under the loop's slot |
| `aForLoopInsideAProposalContainerPlacesEveryIterationInItsOwnSlot` | path literals |
| `removingACellFromARowHandsItsStateToTheNextCell` | divergence 69's pin: the next cell keeps its own |
| `removingAWholeGridRowHandsItsStateToTheNextRow` | the same, a whole row |
| `aHeldElementWhoseIDIsAdoptedPressesTheAdopter` | `AB-H`'s hazard no longer arises through an `if` |
| `aVanishingIfBetweenPressAndReleaseClicksTheTrailingSibling` | the trailing sibling no longer adopts the press |
| `focusOnAnElementThatStopsBeingProducedIsRetainedWithinTheWindow` | the focused id's literal gains the slot level |
| `anOverlaysIdentityDoesNotDependOnTheIndicesItsPrimaryConsumed` | the primary's component literals |
| `aBackgroundsContentKeepsItsStateWhenThePrimaryChangesShape` | the same, the background |
| `aLegacyOverlayKeepsItsOverlaysStateThroughAFlipOfItsPrimarysShape` | its five `kept(true)` arms (lane 2 reads why) |
| `theWholeDemoReportsExactlyTheFieldsAndSitesLaterStagesOwn` | the demo's modal ids (the modal is behind an `if`) |

No allocation pin, no performance pin, no demo-frame pin
(`theDemoFrameMatchesTheValuesRecordedOnMacOS`) and no pixel-adjacent test
reddened. Reverted by copying the two files back; `git status --short` then
showed only the probe.

### 2.4 `.frame` on a `Component`, census

`grep` over `Tests/` and `Sources/` for a `.frame(` directly on a `Component`
value: six test files (`FrameDecorationInteractionTests`,
`PresentationLoweringTests`, `PresentationContainingBlockTests`,
`LoweringStackAndLayerTests`, `LoweringComponentTests`, `ModifiedElementTests`),
several chaining `.opacity`, `.background(.accent)` or `.hidden()` after the
frame, and a presentation (`Deferred`) lowering through the frame layer; the
demo calls none. This is `ID-I`'s evidence that distributing `.frame` would
change the layer every one of those chains configures.

### 2.5 The critic round (`ID-M`)

Run on `4a660e7` by the critic-and-reviser agent, same day, same machine and
toolchain.

- **Probes re-run.** `swiftui-composition-identity.swift` in both forms:
  byte-identical to each other and to its recorded header, exit 0, stderr 0
  lines. Then revision 2 (arms S5/S6, L8–L10 added; nothing else changed): both
  forms byte-identical, exit 0, stderr empty, every earlier line unchanged
  (a `diff` against the first run shows only the five added lines). The new
  lines:

  ```
  S5 one Stash VALUE placed twice, closures called outside dispatch: closures 2, call 0: x 1, call 1: x 1
  S6 two DIFFERENT Stash values (control for S5): closures 2, call 0: x none y 1, call 1: x 1 y none
  L8 HStack{ TallPair().frame(width: 70, alignment: .top) }: 140x30, short minY 10, tall minY 0
  L9 HStack{ TallPair() } (control): 80x30, short minY 10, tall minY 0
  L10 HStack(alignment: .top){ TallPair() } (control: top is visible): 80x30, short minY 0, tall minY 0
  ```

  `swiftui-component-distribution.swift` and `swiftui-modifier-identity.swift`
  (cited, previously "not re-run") re-run in both forms: byte-identical, exit
  0, stderr empty, every output line found in its recorded header.
- **`ID-J` against an existing guard**, measured by declaring the planned
  `ElementGroup.background(alignment:content:)` inside a fixture and
  type-checking it against this worktree's `e3cb3e9` modules (the
  `Typecheck.swift` helper's flags): `Leafless().background(.accent)` goes from
  `value of type 'Leafless' has no member 'background'` to `missing argument
  label 'alignment:' in call` + `missing argument for parameter 'content' in
  call` — `backgroundCannotBeCalledOnAComponent`'s reason check would fail.
  `Leafless().background(ColorToken.accent)` gives `cannot convert value of
  type 'ColorToken' to expected argument type 'ProposalAlignment'` (the
  re-spelling). `let b: Box<EmptyGroup> = Box().background(.accent)` still
  type-checks. Scratch files only, under the session scratchpad; no `Sources/`
  or `Tests/` file was touched.
- **Citations checked.** Every test the spec and rulings name exists exactly
  once under `Tests/`, except record §04's listed pins for 48 and 56
  (`aComponentsWidthStillOverwritesItsMembersDeclaredWidth`,
  `aFrameWrapsAComponentsBodyWithoutOverwritingItsChildren`), which exist
  nowhere; the live pins are named in `ID-M`. Divergence labels 71–74 are
  unused (record §04's highest is 70). `StateTable.sweep()` runs once per
  `Frame.render` (`Frame.swift`), so §3.2's swap is per frame.
- **Amendments**: `ID-M` items 1–5 (the guard, 71's arm, 56's alignment arm,
  `TextField`'s reset, the `.id`-inside-a-modifier pin). Accounting now
  1444 → 1452 → 1463 → 1479, guards 84 → 84 → 85 → 88.

## 3. The audit

Verdicts: **M** matches SwiftUI and is pinned; **F** fixed to SwiftUI's answer
by this task (lane); **K** kept, a numbered divergence with a reason.

| concept | SwiftUI (probe arm) | MetalUI (test, at `e3cb3e9`) | verdict | owner |
|---|---|---|---|---|
| a vanishing `if`'s trailing sibling | keeps its own state (V1, V3) | adopts the vanished element's (`anElementAfterAVanishingIfAdoptsTheVanishedElementsState`) | **F** `ID-B` | lane 2 |
| an appearing `if`'s trailing sibling | keeps (V2) | resets; the new content adopts (scratch V2) | **F** `ID-B` | lane 2 |
| a shrinking `for` loop's trailing sibling | keeps (V6, `ForEach`) | adopts (scratch V6) | **F** `ID-B` | lane 2 |
| a vanishing cell / row in a `Grid` | keeps (V7, V8) | hands on (divergence 69's two pins) | **F** `ID-B`, 69 retires | lane 2 |
| content an `if` removes, on return | new state (V5) | retained (scratch V5; divergence 18) | **F** `ID-C`, 18 retires | lane 2 |
| an if/else flipped away and back | new state (V9) | retained (scratch V4) | **F** `ID-C` | lane 2 |
| an element a `for` loop drops, on regrowth | new state (V10) | retained | **K** divergence 74 | plan task 10 |
| a conditional not evaluated (a `List` row out of window) | — (no SwiftUI analogue probed) | retained for two generations (`TB-AH`) | unchanged | — |
| an if/else flip | new branch state (V4) | resets (`flippingAnEitherBranchResetsTheBranchesState`) | **M** | — |
| if/else inside a proposal container | compiles | does not compile (scratch D) | **F** `ID-D` | lane 2 |
| a constant `.id` | keeps (X1) | keeps (`reorderingANamedListCarriesEachItemsState`, `anAnonymousElementHoldsStateAcrossFrames`) | **M** | — |
| a changed `.id` | resets (A1, X8) | resets — **unpinned** | **M**, pin E3.8 | lane 3 |
| `.id` on a stack / grid / group | resets its content (X4–X6) | not spellable | **F** `ID-G` | lane 3 |
| `.id` written inside a modifier | still resets (X7) | legacy `.id` names the element under the layer; `.id()` must be outermost for index stability — reset **unpinned** | **M** (reset), pin E3.9; outermost rule kept for `for` loops | lane 3 |
| a name that changes and then **returns** (`.id` a → b → a) | new state (X9, X11; X10 control keeps) — probe revision 3, branch check | its **old** state back within `TB-AH`'s bound (§9.3; unpinned) | **open** — owes a ruling and, if kept, divergence 75 and a pin | unassigned (§9) |
| two siblings with the same `.id` | distinct (X2) | shared (`twoSiblingsWithTheSameIDShareOneStateEntry`) | **K** divergence 72, `ID-H` | — |
| one element value placed twice: reads per phase | separate (S1, S4) | separate (`oneElementValuePlacedTwiceDoesNotShareItsState`) | **M** | — |
| one value placed twice: a handler's write | its own occurrence (S1) | the last-bound occurrence (`aHandlerWritesTheStateOfTheOccurrenceThatRegisteredIt`; divergence 19) | **F** `ID-F`, 19 retires | lane 1 |
| one value placed twice: a write outside input dispatch | its own occurrence (S5; S6 control) | the last-bound occurrence | **K** divergence 71 | — |
| `@State` through erasure | works, kept (S2, S3) | inert (scratch S2; record §05 row) | **F** `ID-E` | lane 1 |
| `@Environment` through erasure | works | inert (`anEnvironmentPropertyInsideAnyElementIsInertAndReadsTheDefault`) | **F** `ID-E` | lane 1 |
| a custom view / `Component` is layout-transparent | G0 = G1 (component-distribution) | `aComponentsContentFlattensIntoItsParent` | **M** | — |
| a `Component` owns its state under its own identity | a custom view's `@State` | `twoSiblingComponentsHoldIndependentState`, `aNamedComponentsContentKeepsItsStateWhenASiblingIsInsertedBeforeIt` | **M** | — |
| `.padding` on a multi-member `Component` | per member (G2, G3, L7) | per member (`aComponentsPaddingLowersAsAnOrdinaryOneChildContainer`, `OM-D`) | **M** | — |
| `.width`/`.height` on a `Component` | per member, framed (G7, G8) | per member (`aComponentsWidthFramesEachMember`) | **M**, divergence 48 retires | — |
| `.frame` on a multi-member `Component` | per member; the parent stacks them (L1–L4) | one layer over a row (`aFrameOverAMultiMemberComponentFramesEachMember`, scratch L1) | **K** divergence 56, amended | none (`ID-I`) |
| the row's cross-axis alignment | the parent's: minY 10 under `.top` (L8; L9 no frame 10, L10 top-aligned stack 0) | the frame's own — **unpinned** (`M5g` green) | **K** (56), pin N3.1 | lane 3 |
| `.frame` over zero members | adds nothing (L5; `EmptyView` control L6) | a 0-content frame occupying its parent (scratch L5) | **K** (56) | none |
| `.overlay`/`.background { }` on a multi-member primary | one instance per member (G3, G4) | traps naming the count (N1.7) | **K** divergence 73 | none (`ID-I`) |
| an overlay's / background's content identity | its own state (modifier-identity E/F) | its own (`theOverlaysPrimaryAndOverlayElementsHaveDistinctIdentities`) | **M** | — |
| a legacy `.background { content }` | exists (F) | absent (`LR-FX` item 6) | **F** `ID-J` | lane 3 |
| a modifier on a multi-cell `GridRow` | per cell | traps (divergence 66) | **K** | none |
| builder wrappers over 0/2+ nodes | no such API | trap | **K** (`CN-Q`) | none |
| `Component` `background`/`onClick`/`focusable` | per member (G9) | not offered (`decorationBackedModifiersAreNotOfferedOnAComponent`) | **K** | none |
| a modifier's value change / count change | keeps / resets (modifier-identity C, D1, D2) | keeps / resets the content (`addingAModifierDoesNotResetAComponentsState`, `aLayerAddedAtRunTimeIsAdoptedByTheNewOutermostLayer`) | **M**; the layer's own state is divergence 20, **K** | — |
| `.onTapGesture` on a `Group` past a vanishing `if` | members keep (G7) | covered by `ID-B`; C2.1's second arm (a padded two-member `Component`) | **F** | lane 2 |
| a focused `TextField` inside a toggled `if` | (the field is new; SwiftUI drops focus) | edit state and focus retained | **F** for the edit state (`ID-C`), focus kept (`TB-J`); pin C2.12 (`ID-M` item 4) | lane 2 |

## 4. The divergence table after this task (planned)

Retire **18**, **19**, **48**, **69** (never reused); add **71** (a write
outside input dispatch reaches the last-bound occurrence), **72** (duplicate
sibling names share one identity), **73** (per-member attachments trap), **74**
(a `for` loop's dropped element keeps its state); amend **56** (the vertical
parent, the zero-member frame, the row's alignment; owner none). Live count
55 → 55. The Record phase writes record §04's section and CLAUDE.md's bullet.

## 5. Lane 1 — occurrences and erasure (`ID-E`, `ID-F`)

Commits `11a5433` (red tests), `8f325ed` (implementation), then this section
with `ID-N`. `swift package clean` first (new stored properties on
`State.Box`/`Environment.Box`).

### 5.1 What landed

- New `Sources/MetalUI/StateDispatch.swift`: `StateDispatch.owner`,
  `dispatching(to:_:)` (saves and restores the previous owner) and
  `resolve(among:)` (walk from the owner up, nearest match first).
- `State.Box.occurrences` (every slot bound in one generation, set when a
  second different slot binds — the moment `noteAliasedStateBox()` fires,
  which still counts — cleared on a later generation's first bind) and
  `resolvedSlot`, read by `wrappedValue`'s get and set.
- `Environment.Box`: `boundID`, `boundGeneration`, one snapshot per element id
  when aliased, `resolvedValues`; `BindableEnvironment.bind` takes the element
  id and the table's generation (`StateReflection.swift`, both paths).
- `AnyElementBox` binds its element in `requestLayout`, `prepaint`, `paint`.
- Dispatch sites: `Window.dispatchClick`, `dispatchKey`, `dispatchAction`,
  the accessibility press and adjust, `Window.applyEdit` (edit) and
  `dispatchTextKey` (submit, `ID-N` item 1). The risk-4 grep of every handler
  call in `Sources/MetalUI` found no other element-owned call
  (`Box.onAction`'s and `accessibilityAdjustableAction`'s wrappers run inside
  an enumerated site; `Window.onAction`/`onInput` have no element).

### 5.2 Red before (`11a5433` against `e3cb3e9`'s sources)

`Test run with 1452 tests in 3 suites failed … with 15 issues`, all in the
nine lane-1 tests:

| test | line | read |
|---|---|---|
| O1.1 | `counts == [1, 0]`, then `[1, 1]` | `[0, 1]`, then `[0, 2]` |
| O1.2 | `[1, 0]` | `[0, 1]` |
| O1.3 action / press / adjust | `[1, 0]` each | `[0, 1]` each |
| O1.4 | `[1, 0]`, then `[1, 1]` | `[0, 1]`, then `[0, 2]` |
| O1.5 | `reads == [7, 9]` | `[9, 9]` |
| O1.6 edit / submit | `["a", ""]` / `[1, 0]` | `["", "a"]` / `[0, 1]` |
| O1.7 | slot `== 3` | `nil` |
| O1.8 | prepaint and paint `[1, 2]` | `[0, 0]`, `[0, 0]` |
| E8 renamed | `[[5], [5], [5]]` | `[[0], [0], [0]]` |

### 5.3 After

`swift build --build-system native --build-tests` and `swift build
--build-tests`: 0 `error:`, the only `warning:` SwiftPM's deprecation notice.
`swift test --build-system native --no-parallel` → **`Test run with 1452 tests
in 3 suites passed after 81.063 seconds`**, guards ran (`FR-J no-argument
frame: succeeded=true`). **1452 = 1444 + 8** (O1.1–O1.8); E8 renamed, not
added. `IdentityTests.swift` unedited, and
`aHandlerWritesTheStateOfTheOccurrenceThatRegisteredIt` green at 1 / 102 —
divergence 71's pin holds (a direct call has no owner); SwiftUI's half is probe
S5.

**Retirement row.** `anEnvironmentPropertyInsideAnyElementIsInertAndReadsTheDefault`
(`EnvironmentTests.swift`, E8, pinned inert `[[0], [0], [0]]`) →
**`anEnvironmentPropertyInsideAnyElementReadsItsScope`**, asserting the scope's
`[[5], [5], [5]]`; its answer changed by ruling (`ID-E`), reddened by M1j. No
other retained test changed its answer; no test deleted.

**Pixels.** `docs/probes/demo-pixels/compare.sh <scratch> e3cb3e9 8f325ed`:
controls as recorded (light/dark 1048576, prod default vs modal 491221, f0 vs
f3 0, chrome pair 0, distinct 544/216/529, indicator rects 0), and **all
fourteen images differing=0, scene identical**. `Expected.swift` unedited.
The real-window capture is lane 2's and the Record phase's (spec §6), not
taken here.

### 5.4 Mutations

Each from the committed `8f325ed`, the file copied and restored, whole suite
unfiltered, `git status --short` empty after each.

| id | mutation | reddened (issues) |
|---|---|---|
| M1a | `resolvedSlot` returns `slotID` first | O1.1, O1.2, O1.3 (all three arms), O1.4, O1.6 (both arms) — 10 |
| M1b | click site without owner | O1.1, O1.4, O1.5 — 5 |
| M1c | `dispatchKey` without owner | O1.2 — 1 |
| M1d | `dispatchAction` without owner | O1.3 action arm — 1 |
| M1e | AX press without owner | O1.3 press arm — 1 |
| M1f | AX adjust without owner (`do { }`) | O1.3 adjust arm — 1 |
| M1g | `resolve` stops at the owner (no ancestor walk) | O1.4, O1.6 (both arms) — 4 |
| M1h | `Environment.Box` ignores the owner (`owner == nil` guard) | O1.5 — 1 |
| M1i | edit callback without owner | O1.6 edit arm — 1 |
| M1l | submit callback without owner (`ID-N`) | O1.6 submit arm — 1 |
| M1j | no bind in `AnyElementBox.requestLayout` | E8 renamed, O1.7 (`nil`), O1.8 (`[0, 0]`) — 4 |
| M1k | no bind in `AnyElementBox.prepaint`/`paint` (both lines) | O1.8 (`[2, 2]`) — 2 |

Three predictions in the spec were wrong and are corrected by `ID-N` item 4
(M1a not O1.5; M1g also O1.6; M1j also O1.8), and two test spellings by item 2
(O1.3's press arm, O1.4's clicks).

### 5.6 Review round (`ID-O`)

The lane's reviewer returned one major and two minors; all three fixed.
Commits: red tests, then the fix (`3ffcc91`), then this subsection with
`ID-O`.

- **Major — V10 was unpinned.** Mutation V10 in
  `Sources/MetalUI/EnvironmentProperty.swift`, `box.occurrences =
  [(previous, last)]` → `_ = last; box.occurrences = []`, left the whole suite
  green at 1452. New O1.9 (`aComponentsEnvironmentKeepsTheFirstOccurrencesSnapshot`,
  a `Component` value holding `@Environment` placed twice under 7 and 9) is
  green at the test commit and **V10, re-run from that committed tree, whole
  suite unfiltered, reddens O1.9 alone** (`[9, 9]`; the run's only other red
  was O1.10, red at that commit without any mutation). `git status --short`
  empty after the restore.
- **Minor — an owner leaking into a frame build.** O1.10
  (`aFrameBuiltInsideADispatchedHandlerReadsEachOccurrencesBinding`) renders
  one `Element` value placed twice under 7 and 9 inside
  `StateDispatch.dispatching(to: occurrence 0)`: **red at the test commit**
  (`[7, 7]`, `Test run with 1454 tests in 3 suites failed … with 1 issue`),
  green once `Frame.render` wraps its build in
  `StateDispatch.outsideDispatch`. Reverting that wrap is the test commit's
  sources, so the red run is its mutation.
- **Minor — two stale comments** (`Component.swift`'s `requestGroupLayout`
  note and `ComponentTests.swift`'s `stateInsideAComponentsContentIsAlsoSeeded`
  doc) called `AnyElement`'s unbound `@State` "the live defect"; reworded to
  say forwarding to `requestLayout` would skip `StateBinder.bind`, the shape
  `AnyElement` had before `ID-E`.

**After.** `swift build --build-system native --build-tests` and `swift build
--build-tests`: 0 `error:`, the only `warning:` SwiftPM's deprecation notice.
`swift test --build-system native --no-parallel` → **`Test run with 1454 tests
in 3 suites passed after 81.073 seconds`**, guards ran. **1454 = 1452 + 2**
(O1.9, O1.10). No test deleted or changed its answer. `compare.sh <scratch>
e3cb3e9 3ffcc91`: controls as in §5.3, **all fourteen images differing=0,
scene identical**. `Expected.swift` unedited.

| id | mutation | reddened (issues) |
|---|---|---|
| V10 | `Environment` bind drops the previous occurrence's snapshot | O1.9 (`[9, 9]`) — 1 |
| V11 | `Frame.render` without `outsideDispatch` (the test commit's sources) | O1.10 (`[7, 7]`) — 1 |

### 5.5 Deferred

- `ElementGroup.swift`'s `extension AnyElement: ElementGroup` comment still
  says `@State` inside an `AnyElement` is inert — lane 2's file (spec §3.4).
- The Record phase: record §05's `AnyElement` inert row, divergence 19's
  retirement and 71's addition, CLAUDE.md's "Inert inside `AnyElement`" and
  divergence 19 sentences.

## 6. Lane 2 — structural slots, reset, proposal if/else (`ID-B`, `ID-C`, `ID-D`)

Commits `4fe5881` (red tests), `9f2528c` (implementation), then this section
with `ID-P`. Baseline `a2cd063`, **1454** tests (lane 1's review round added
two, `ID-O`), not the spec's 1452 (`ID-P` item 4). No stored property on a
public type changed (`StateTable` is internal), so no `swift package clean`.

### 6.1 What landed

- `OptionalGroup` and `ArrayGroup`, **both copies** (`ElementGroup.swift`,
  `ProposalElementGroup.swift`): one cursor index always, content numbered from
  0 under `.positional(index)`; an `ArrayGroup` threads one inner cursor across
  its members.
- `StateTable`: `producedSlots`/`previouslyProducedSlots`, swapped in `sweep()`
  (`removeAll(keepingCapacity:)`); `noteProduced`; `noteAbsent` resets only
  when the slot was produced by the last completed frame (it `remove`s the slot
  from the previous set, so a second note in one frame scans nothing), deleting
  every entry with the slot as a proper ancestor except a `.named("$focus")` or
  `.named("$ax")` component; `subtreeResetScans` counts the scans. `sweep()`
  never resets.
- `EitherGroup`: both copies note the taken branch produced and the untaken
  absent; the typed conformance (`ID-D`) is new. An `if`/`else` now builds two
  branch ids per frame (was one); every allocation pin stayed green.
- Doc comments rewritten: the groups, the `AnyElement` extension (§3.4),
  `ElementID.swift` (identity depth), `Grid.swift`, the demo's modal comment
  (a comment only), and — outside the listed files, `ID-P` item 6 —
  `ScrollView.swift`, `Window.dispatchClick`, `State.swift`, `Frame.swift`.

### 6.2 Red before (`4fe5881` against `a2cd063`'s sources)

The test target does not build: `ConditionalIdentityTests.swift:324: value of
type 'StateTable' has no member 'subtreeResetScans'` (C2.9) and `:399: generic
struct 'HStack' requires that 'EitherGroup<ProposalConditionalCounter,
ProposalConditionalCounter>' conform to 'ProposalElementGroup'` (C2.11). With
those two compiled out (uncommitted), `Test run with 1463 tests in 3 suites
failed … with 61 issues`, every one in a lane-2 test; G2.1 printed `positive:
succeeded=false`, `control: succeeded=false`. (This read "60 issues", as did
`4fe5881`'s message; lane 2's review re-ran it at 61 — 25 tests, each count
as the table below — and 61 is also the sum of the table's lines.)

| test | failing line(s) |
|---|---|
| C2.1 `anElementAfterAVanishingIfKeepsItsOwnState` | `root/1 == 2`, slot `== nil`, `count == 2`, `m0 == 2`, `m1 == 2` |
| C2.2 | `root/1 == 2`; `root/0/0 == 1` |
| C2.3 | `root/0/0 == 1`, `root/0/1 == 1`, `root/1 == 3` |
| C2.4 | `root/0/1 == 2`, `root/0/0 == 3`; the first spelling's `root/1 == 2` was **green** — re-spelled with steps of 10, then `t == 2` read **11** (`ID-P` item 2) |
| C2.5a / C2.5b | `b == 1`, `c == 0` / `q == 1`, `r == 0` |
| C2.6 | `c == 1`, `t == 3` |
| C2.7 | `a == 1` |
| C2.8 | `$state0 == nil` only (focus and `$ax` green, as predicted) |
| C2.10 | green (pin) |
| C2.12 | `after == TextEditState()`; the input area at boundary 0 (focus half green, as predicted) |
| G2.1 | `positive.succeeded != control.succeeded` |
| T `reorderingANamedListCarriesEachItemsState` | both loop-slot peeks |
| T `flippingAnEitherBranchResetsTheBranchesState` | `peek(ifContent) == nil`, `count == 2` |
| T `aBranchWithTwoMembers…` / `aBranchReservesBothIndices…` | `count == 2` / `count == 4` |
| R `namingEitherSideOfAVanishingIf…` | `named.count == 2`, misplaced `root/1 == 2`, `misplaced.count == 2` |
| R `aHeldElementWhoseNameMovesPressesItsNewOwner` | arm 2's four (arm 1 green: a moving name already carried the held element) |
| R `aPressHeldAcrossARebuild…` | arm 1 `== []`, arm 2 `== ["B"]` |
| R `aReturningAnimatingElementSnaps…` (`ID-P` item 1) | arm 1 `fresh == 200` (arm 2's 175 green) |
| T `aBackgroundsContentKeepsItsState…`, `anOverlaysIdentity…` | the re-spelled control `1, 1, 1` |
| T `aLegacyOverlayKeepsItsOverlaysState…` | L1–L5 `kept(true)`, P5 `[3, nil, 0]`, Q `[3, 0, 0]` |
| T `focusOnAnElementThatStopsBeingProduced…` | four (the id gains the slot) |
| T `theWholeDemoReports…` | the `Deferred`/stack and four modal rows (the ids gain the slot) |
| T `aForLoopInsideAProposalContainer…` | three ids |

### 6.3 After

`swift build --build-system native --build-tests` and `swift build
--build-tests`: 0 `error:`, the only `warning:` SwiftPM's deprecation notice.
`swift test --build-system native --no-parallel` → **`Test run with 1465 tests
in 3 suites passed after 81.741 seconds`**, guards ran (`FR-J no-argument
frame: succeeded=true`; `CONDITIONAL GUARD G2.1 positive: succeeded=true`,
`control: succeeded=false`). **1465 = 1454 + 11** (C2.2, C2.3, C2.4, C2.6–C2.12,
G2.1); guards **85** (`canTypecheck(module` grep 82 → 83 at `a2cd063` → `HEAD`).
`everyProductionTreeBuildsOnAOneMegabyteThread`,
`theSevenRetentionSlotsAreMutuallyDistinct` and
`theLegacyEngineSymbolsAreAbsentFromTheTestProcess` green in that run.
`StateTableTests.swift` unedited (no count literal moved).

**After lane 2's review round (`ID-P` item 7).** C2.13
`contentAnIfInsideAProposalContainerRemovesIsResetWhenItReturns` added (the
typed `OptionalGroup` copy's reset, which no test pinned — N1 below), and stale
test names in comments renamed or marked as predating `ID-B`
(`ElementLayoutTests`, `StateTableTests` — comment only, no literal —
`ComponentTests`, `IdentityTests`). Both build systems: 0 `error:`, the only
`warning:` SwiftPM's deprecation notice. **`Test run with 1466 tests in 3
suites passed after 81.683 seconds`**, guards ran (`FR-J no-argument frame:
succeeded=true`, `CONDITIONAL GUARD G2.1 positive: succeeded=true`). **1466 =
1454 + 12**; guards 85. No `Sources/` line moved, so the pixel run above stands.

**Retirement rows (eight, `goldensUnchanged`).** Each renamed test's answer
changed by ruling; none deleted:

| was | now | ruling |
|---|---|---|
| `anElementAfterAVanishingIfAdoptsTheVanishedElementsState` (2 at `root/0`) | `anElementAfterAVanishingIfKeepsItsOwnState` (2 at `root/1`, content gone; G7 arm) | `ID-B`, `ID-C` |
| `removingACellFromARowHandsItsStateToTheNextCell` (b 0, c 1) | `removingACellFromARowLeavesTheNextCellsStateAlone` (b 1, c 0) | `ID-B`; 69 retires |
| `removingAWholeGridRowHandsItsStateToTheNextRow` (q 0, r 1) | `removingAWholeGridRowLeavesTheNextRowsStateAlone` (q 1, r 0) | `ID-B`; 69 retires |
| `namingTheLaterSiblingIsWhatSurvivesAVanishingIf` (2 / 1) | `namingEitherSideOfAVanishingIfLeavesTheTrailingSiblingsStateAlone` (2 / 2) | `ID-B` |
| `aHeldElementWhoseIDIsAdoptedPressesTheAdopter` | `aHeldElementWhoseNameMovesPressesItsNewOwner` (`AB-H` through a moving name; a vanishing `if` detaches) | `ID-B` |
| `aVanishingIfBetweenPressAndReleaseClicksTheTrailingSibling` (`["B"]` / `[]`) | `aPressHeldAcrossARebuildClicksItsOwnTargetAndAVanishedTargetClicksNothing` (`[]` / `["B"]`) | `ID-B` |
| `aHandlerWritesTheStateOfTheOccurrenceThatRegisteredIt` | `aClosureRunOutsideInputDispatchWritesTheLastBoundOccurrence` — assertions unchanged (1 / 102), doc rewritten | `ID-F` (71) |
| `anAnimatingElementThatVanishesAndReturnsResumesRatherThanRestarting` (175) | `aReturningAnimatingElementSnapsInsideAnIfAndResumesInsideALoop` (200 in an `if`, 175 in a loop) | `ID-C`, `ID-P` item 1 |

The T rows keep their names; their literals moved as §6.2 lists. Every other
retained test kept its answer.

**Pixels.** `docs/probes/demo-pixels/compare.sh <scratch> e3cb3e9 9f2528c`:
controls as lane 1 read them (light/dark 1048576, default vs modal 1031003,
default vs animation 454895, f0 vs f3 0, chrome pair 0, distinct 544/216/529,
prod default vs modal 491221, indicator rects 0), and **all fourteen images
differing=0, scene identical** — the demo's ids moved (the modal's `if` slot)
and no pixel did. `Expected.swift` unedited.

**Real window.** Lock probe (`appkit-screen-lock-state.swift`):
`CGSSessionScreenIsLocked = 1`, `displayAsleep main: 1` — the screen was
locked, so `capture.sh` was not run; the capture after lane 2 is **owed**
(spec §6), with the Record phase's.

### 6.4 Mutations

Each from the committed `9f2528c`, the file copied and restored, whole suite
unfiltered, `git status --short` empty after each. Copy named per row.

| id | copy | mutation | reddened (issues) |
|---|---|---|---|
| M2a | untyped `OptionalGroup` | cursor advanced only when `wrapped != nil` | C2.1 (5), C2.2, C2.3, C2.6, `namingEitherSide…` (2), `aPressHeldAcrossARebuild…`, `aLegacyOverlayKeeps…` (4) — 15 |
| M2a′ | typed `OptionalGroup` | the same edit | C2.5a (2), C2.5b (2), `aBackgroundsContentKeeps…`, `aLegacyOverlayKeeps…` (L4), `anOverlaysIdentity…` — 7; no untyped test (`ID-P` item 5) |
| M2b | untyped `OptionalGroup` | slot reserved, members numbered with the outer cursor under `parent` | C2.3 (2) among 13 tests, 37 issues (C2.1, C2.2, C2.6, C2.8, C2.12, the held-element, press, overlay, focus, demo and animation rows — content outside the slot escapes the reset too) |
| M2c | untyped `ArrayGroup` | no slot; members through the outer cursor | C2.4 (3), `reorderingANamedListCarriesEachItemsState` (2) — 5 |
| M2c′ | typed `ArrayGroup` | the same edit (`ID-P` item 5) | `aForLoopInsideAProposalContainerPlacesEveryIterationInItsOwnSlot` (3) |
| M2d | `StateTable.noteAbsent` | never deletes | 13 tests, 19 issues: C2.3, C2.6, C2.7, C2.8, C2.11, C2.12 (state half, 2), C2.1, the animation row (arm 1), `namingEitherSide…`, the three `IdentityTests` count T rows, `aLegacyOverlayKeeps…` (P5, Q) |
| M2e | both `EitherGroup`s' untyped copy | no absent note | C2.7, `flippingAnEither…` (2), `aBranchWithTwoMembers…`, `aBranchReservesBoth…`, `aLegacyOverlayKeeps…` (Q) — 6 |
| M2f | `StateTable.noteAbsent` | no `$focus`/`$ax` exemption | C2.8 (2), C2.12 (focus half, 3), `focusOnAnElementThatStopsBeingProduced…`, `aFocusRequestWhileDisabledLeavesNoRetentionSlot` — 7 |
| M2g | `StateTable.noteAbsent` | scans on every absent note | C2.9 alone |
| M2h | `StateTable.sweep` | resets every previously produced slot not produced this frame | C2.10 alone |
| M2i | typed `EitherGroup` | both branches at `branchIndex` | C2.11 alone |
| G2.1 | typed `EitherGroup` | conformance deleted (C2.11 compiled out, uncommitted) | G2.1 alone (`positive: succeeded=false`; 1464 tests) |
| Mp | `Window.dispatchClick` | `hit.id === pressed` | `aPressHeldAcrossARebuild…` (arm 2), `aClickNeedsTheTargetEnabledAtPressAndAtRelease` — 2 |
| N1 | typed `OptionalGroup` | `noteAbsent(slot)` replaced with `_ = slot` (review round, from the C2.13 commit) | before C2.13: **none** (`1465 tests … passed`); after: C2.13 alone (1 issue, `c == 1` read 2) |
| Mo | `OverlayModifier`, both entries | overlay side threaded through the primary's cursor (`MC-E`) | `aLegacyOverlayKeeps…` (6), `anOverlaysIdentity…` (3) among 8 tests, 17 issues (`ID-P` item 3) |

M2a′'s three extra tests and M2f's `aFocusRequestWhileDisabled…` were not in
the spec's predictions; `ID-P` item 5 records the first. The second
(`DisabledTests.swift:755`, `hazard`) is that test's instrument arm, pinned wrong
on purpose: a non-focusable element inside `if model.present` leaves a `$focus`
slot that makes a second focus request stick — it needs `$focus` to survive the
`if`'s reset, so it pins the exemption too. Mp's old doc said the
press test was the only one to redden it; `aClickNeedsTheTargetEnabledAtPressAndAtRelease`
now reddens too.

### 6.5 Deferred

- The real-window capture (locked screen), to the Record phase.
- Record phase: record §04 retires 18 and 69 (and 19, 48 with lanes 1/3), adds
  74; CLAUDE.md's "Identity is structural" bullets, the grid bullet and the
  demo/`ScrollView` notes; record §05's `AnyElement` row (its source comment is
  rewritten here).

## 7. Lane 3 — explicit identity and the legacy background (`ID-G`, `ID-J`, pins)

Commits `77f6ae1` (red tests), `1f65b62` (implementation), `52fd4b6` (B3.2's
typed arm, `ID-Q` item 2), then this section with `ID-Q`. Baseline `e7c8162`,
**1466** tests, guards 85. `swift package clean` before the implementation build
(`BackgroundModifier`'s public generic constraints changed).

### 7.1 What landed

- `Sources/MetalUI/ExplicitIdentity.swift` (new): `IdentifiedGroup<Content:
  ElementGroup>` and `ElementGroup.id(_:)`. One cursor index, component
  `.named(name)` (`slot(under:at:)`, shared by both entries), content numbered
  from 0 under it with a fresh cursor, nodes returned unchanged; `prepaint`/
  `paint` forward. `IdentifiedGroup: ProposalElementGroup where Content:
  ProposalElementGroup`, its typed entry a copy of the content line.
  `StyledElement.id(_:) -> Self` untouched and still chosen for every
  `StyledElement`.
- `NativeBackgroundModifier.swift`: `BackgroundModifier<Content: ElementGroup,
  Background: ElementGroup>` on `OverlayModifier`'s `LR-FX` shape — untyped
  `requestLayout`, typed `requestProposalLayout` in a conformance conditional on
  both sides, shared `backgroundSide(of:)` (`MC-P`'s `-1`) and `attach`
  (`lowerAttachmentChildren` on both sides, then
  `requestSecondaryContentAttachment` naming `"background"`); background
  prepainted and painted first. One `.background(alignment:content:)` on
  `ElementGroup` replaces the `ProposalElementGroup` one; the token overloads
  are untouched. `ProposalElementGroup.swift`: the unconditional
  `extension BackgroundModifier: ProposalElement {}` replaced by a comment
  (`ID-Q` item 5).
- Tests: `ExplicitIdentityTests.swift` (E3.1–E3.9),
  `ExplicitIdentityCompileGuards.swift` (G3.1–G3.3), `LegacyBackgroundTests.swift`
  (B3.1–B3.3), N3.1 in `LoweringComponentTests.swift`; the T row
  `backgroundCannotBeCalledOnAComponent` re-spelled (fixture
  `Leafless().background(ColorToken.accent)`, reason `contains("ColorToken")`).

### 7.2 Red before (`77f6ae1` against `e7c8162`'s sources)

The test target does not build: E3.1–E3.7 (`value of type 'HStack<…>' / 'Grid<…>'
/ 'GridRow<…>' / 'StatefulPair' / 'some ElementGroup' has no member 'id'`,
`cannot find type 'IdentifiedGroup' in scope`) and B3.1–B3.3 (`type
'Box<EmptyGroup>' does not conform to protocol 'ProposalElementGroup'`, `type
'ColorToken' has no member 'topLeading'`, `value of type 'TwoMembers' has no
member 'background'`). With those compiled out (uncommitted), **`Test run with
1472 tests in 3 suites failed … with 4 issues`**:

| test | failing line |
|---|---|
| G3.1 | `positive.succeeded != control.succeeded` (both rejected: `'Rectangle' has no member 'id'`, `cannot find type 'IdentifiedGroup'`) |
| G3.2 | the same (`'Rectangle' has no member 'id'`) |
| G3.3 | the same (`'ColorToken' has no member 'topLeading'`, `'Pair' has no member 'background'`) |
| T `backgroundCannotBeCalledOnAComponent` | `messages.contains("ColorToken")` (`'Leafless' has no member 'background'`) |
| E3.8, E3.9, N3.1 | green (pins) |

### 7.3 After

Both build systems: 0 `error:`, the only `warning:` SwiftPM's deprecation
notice. `swift test --build-system native --no-parallel` → **`Test run with 1482
tests in 3 suites passed after 83.478 seconds`**, guards ran (`FR-J no-argument
frame: succeeded=true`; `EXPLICIT IDENTITY GUARD G3.1/G3.2/G3.3 positive:
succeeded=true`, each control `succeeded=false`). **1482 = 1466 + 16** (E3.1–E3.9,
B3.1–B3.3, N3.1, G3.1–G3.3); guards **88** (`canTypecheck` hits 90 less the
declaration and `UnitSafetyTests`' comment; `canTypecheck(module` 83 → 86).
`theSevenRetentionSlotsAreMutuallyDistinct`,
`everyProductionTreeBuildsOnAOneMegabyteThread`,
`theLegacyEngineSymbolsAreAbsentFromTheTestProcess` and
`theDemoFrameMatchesTheValuesRecordedOnMacOS` green in that run. No test was
removed or renamed (no retirement row); the T row keeps its name and subject.
**The fix round adds B3.4** (`ID-Q` item 6, §7.4's V5/V6): **1483 = 1482 + 1**,
`Test run with 1483 tests in 3 suites passed after 83.430 seconds` at
`3af2ad2`; guards unmoved (88).

**Pixels.** `docs/probes/demo-pixels/compare.sh <scratch> e3cb3e9 1f65b62`:
controls as lanes 1–2 read them (light/dark 1048576, default vs modal 1031003,
default vs animation 454895, f0 vs f3 0, chrome pair 0, distinct 544/216/529,
prod default vs modal 491221, indicator rects 0), **all fourteen images
differing=0, scene identical**. Later commits change tests and comments only.
`Expected.swift` unedited.

**Elsewhere.** `MetalUILayout` imports only `MetalUICore` (anchored grep, no
other hit). `Backends/SDL` (`PKG_CONFIG_PATH=$PWD/.accesskit`): `Build
complete!`, 0 `error:` (only the pre-existing SDL dylib deployment-target linker
notes), 21 + 19 passed. `swift:6.4-noble` (Docker, aarch64) over `git archive
52fd4b6`: `swift build --build-tests` → `Build complete!`, 0 `error:`/`warning:`;
`swift test --skip-build --filter
'MetalUICoreTests|MetalUILayoutTests|MetalUICrossPlatformTests'` → 188 + 10 + 22
passed, `theDemoFrameMatchesTheValuesRecordedOnMacOS` and
`everyProductionTreeBuildsOnAOneMegabyteThread` green.

**Real window.** Lock probe: `CGSSessionScreenIsLocked = 1`, `displayAsleep
main: 1` — locked; `capture.sh` not run. Owed to the Record phase (with lane
2's).

### 7.4 Mutations

Each from a committed tree (`1f65b62`; M3h′'s re-run and M3e′ from `52fd4b6`),
the file copied and restored, whole suite unfiltered, `git status --short` empty
after each.

| id | site | mutation | reddened (issues) |
|---|---|---|---|
| M3a | `IdentifiedGroup.slot` (both entries) | `name: nil` (positional) | E3.1 (4), E3.2 (2), E3.3, E3.4 (2), E3.6 (2), E3.7 (2) — 13 |
| M3b | untyped entry | content under `parent` with the outer cursor | E3.1 (2, `Row` arm), E3.3, E3.4 (3) — 6 |
| M3b′ | typed entry | the same edit | E3.1 (2, `VStack` arm), E3.2 (2), E3.6 (2), E3.7 (2) — 8 |
| M3c | typed entry | content under an extra one-child `ZStack` | E3.5 alone (node count) |
| M3d | `GlobalElementID.child(of:at:name:)` | name ignored | 97 tests, 308 issues, E3.8 and E3.9 among them (and E3.1–E3.3, E3.6, E3.7, `twoSiblingsWithTheSameIDShareOneStateEntry`, `theSevenRetentionSlotsAreMutuallyDistinct`, the `List` and animation suites) |
| M3e′ | `StyledElement.id` | `@_disfavoredOverload` (+ `List`'s row box via `elementID`) | test target does not build; G3.1's fixtures against the mutant module: positive exit 1, control exit 0 (`ID-Q` item 1) |
| M3f | `IdentifiedGroup` | conditional conformance deleted (`ExplicitIdentityTests.swift` set aside: it no longer compiles) | G3.2 alone (1473 tests) |
| M3g | `BackgroundModifier.paint` | background painted after the primary | B3.1, `aBackgroundIsProposedThePrimarysSizeAlignedAndPaintedBeneath` — 2 |
| M3h | untyped entry | background side under `id` at the primary's cursor | B3.1, B3.2 (3), `aBackgroundsContentKeepsItsStateWhenThePrimaryChangesShape` (3) — 7 |
| M3h′ | typed entry | the same edit | at `1f65b62`: **none** (1482 passed); after B3.2's typed arm (`52fd4b6`): B3.2 alone (1) |
| M3i | `BackgroundModifier.attach` | primary `prefix(1)` | B3.3 alone (2; the child exits 0) |
| M3j | `.background(alignment:content:)` | declared on `ProposalElementGroup` again (`LegacyBackgroundTests.swift` set aside) | G3.3, T `backgroundCannotBeCalledOnAComponent` — 2 (1479 tests) |
| M3k | `lowerShownLegacyFrameLayer` | the row at `alignment: .center` | N3.1 alone |
| MT | `Component` | `background(_: ColorToken) -> Self` declared | T `backgroundCannotBeCalledOnAComponent` alone (2) |
| V5 | `BackgroundModifier.attach` | `let primary = contentNodes` (no lowering) | at `c3c9bc9`: **none** (1482 passed; the verifier's run); after B3.4 (`3af2ad2`): B3.4 alone (1, report `[box.flexGrow.unconsumed]`) |
| V6 | `BackgroundModifier.attach` | `let secondary = backgroundNodes` (no lowering) | at `c3c9bc9`: **none** (1482 passed); after B3.4: B3.4 alone (2, report `[box.margin.unconsumed]`, `nodeCount` 8 for 7) |

**V5 and V6 are the fix round's** (`ID-Q` item 6): `ID-J`'s central claim, both
sides through `lowerAttachmentChildren`, was pinned by nothing — B3.1–B3.3 use
fixed-size leaves with no item field, which the lowering leaves alone. B3.4
(`aLegacyBackgroundLowersBothSidesAsAFrameLayerDoes`) copies the overlay's two
pins onto the background; each mutant was a whole unfiltered run from the
committed `3af2ad2`, the file restored from a copy, `git status --short` empty
after; the unmutated tree read `Test run with 1483 tests in 3 suites passed`.

**M3e′ is the one guard mutation whose red was read from the guard's fixtures,
not from the running guard.** Under it the test target stops building
(`AXEmitSiteTests`, `ElementGroupTrapTests`, `ElementLayoutTests`,
`HitRegionTests`; with those set aside, seven more through their helpers), so
the positive and the control were typechecked with the guard's own arguments
(`-swift-version 6 -I <Modules>` plus the C module maps) against the mutant's
built `MetalUI`: positive `cannot convert value of type
'IdentifiedGroup<Box<EmptyGroup>>' to specified type 'Box<EmptyGroup>'` (and the
chain's), control exit 0 — the guard's `#expect(positive.succeeded)` and
`#expect(!control.succeeded)` both fail. The same instrument against the
lane-3 module: positive exit 0, control exit 1, and the spec's control spelling
exit 0 (`ID-Q` item 1).

### 7.5 Deferred

- The real-window capture (locked screen), to the Record phase.
- **A group that returns to a name it used earlier** (`.id("a")` → `"b"` →
  `"a"`): neither SwiftUI's answer nor MetalUI's is probed or pinned; the spec
  asks only for a changed name to reset (E3.1–E3.3, E3.8, E3.9). Owner: none
  named; a probe arm and a test if it matters.
- Record phase: record §04 retires 48 and amends 56 (N3.1 pins its alignment
  sub-row) and adds 73 (B3.3 and N1.7 its pins); CLAUDE.md's "Component"
  paragraph (`.id()` via `IdentifiedGroup`; `.background { }` offered, the token
  one not), the grid bullet ("no built-in proposal element has `.id()`"), the
  vocabulary list (`.id(_:)`, `IdentifiedGroup`, the legacy `.background { }`),
  counts (1483 after the fix round's B3.4) and guards (88, `ExplicitIdentityCompileGuards` 3).

## 8. The task's close (Record phase, 2026-09-25, PDT)

Spec §6's accounting and gates, re-checked independently at `ea95cc4` (the
fix round's own commit — the last one before this section), not by re-reading
the three lanes' own claims. All three lane verdicts read `ok: true`, so no
fix/re-verify round was owed here (Practices: "Re-verify only on a finding").

### 8.1 Suite, guards, goldens

`swift package clean`, then `swift build --build-system native --build-tests`
and `swift build --build-tests` (default): both `Build complete!`, 0
`error:`, the only `warning:` SwiftPM's own deprecation notice under native
(0 under the default). Unfiltered `swift test --build-system native
--no-parallel` → **`Test run with 1483 tests in 3 suites passed after 82.720
seconds`**, the log carrying `FR-J no-argument frame: succeeded=true
deprecations=2` (guards ran) and `CONDITIONAL GUARD G2.1`/`EXPLICIT IDENTITY
GUARD G3.1`/`G3.2`/`G3.3` each `positive: succeeded=true`, `control:
succeeded=false`. **Eleven** gated tests skipped, unchanged from `e3cb3e9`
(`recordDemoFrames`, the FreeType/HarfBuzz/portable-text/line-breaking/
lines-emission (two)/content-sizes/font-fallback/bidi `measure*` oracles,
`aListsWorkIsTheSameFor100kRowsAsFor500`).

`find Tests/MetalUILayoutTests -name "*.json" | wc -l` reads **0** (stage 7a;
unmoved). Guards: `grep -c canTypecheck` per file across the seventeen files
`CLAUDE.md`'s "Guards" bullet names, plus this task's two new ones —
`ConditionalIdentityCompileGuards.swift` (1, G2.1) and
`ExplicitIdentityCompileGuards.swift` (3, G3.1–G3.3) — sums to 90 raw hits;
less `Tests/MetalUITestSupport/Typecheck.swift`'s declaration (not counted,
CLAUDE.md's own exclusion) and `UnitSafetyTests`' one comment-line hit gives
**88 = 84 + 4**, matching lane 3's §7.3 figure exactly. All four new guard
tests typecheck a whole-file `typecheckFile` fixture (none use the
Swift-5-in-a-function `typecheck` helper), so the "two helpers" split moves
40/44 → **40/48**.

**Retirement accounting (`goldensUnchanged`).** No test was deleted outright.
**Nine** retirement rows in all — one in lane 1 (§5.3, E8 renamed) and eight
in lane 2 (§6.3: the eight-row table) — cover every renamed or re-answered
`@Test`; lane 3 renamed or removed none. Spot-checked two ways at `ea95cc4`:
a grep for each of the nine "was" names in the table above the retirement
rows returns zero hits in `Tests/`, and a grep for each "now" name returns
exactly one, at its declaration — no name is both present and absent, which
would mean a rename half-landed.

### 8.2 Must-not-move greens

All read `passed` in the 1483-test run above:
`theSevenRetentionSlotsAreMutuallyDistinct`,
`everyProductionTreeBuildsOnAOneMegabyteThread`,
`everyProductionRootsDeepestNativeLevelIsMeasured`,
`theLegacyEngineSymbolsAreAbsentFromTheTestProcess`,
`theDemoFrameMatchesTheValuesRecordedOnMacOS`. `Frame.legacyRootLayoutCounter`
is not touched by any lane (no lane's diff names it).

### 8.3 Pixels

`docs/probes/demo-pixels/compare.sh <scratch> e3cb3e9 ea95cc4` (a fresh
scratch directory, independent of every lane's own run): every control at its
recorded `e3cb3e9` value — light vs dark 1 048 576, default vs modal
1 031 003, default vs animation 454 895 (bbox (16,113)–(987,1007)), f0 vs f3
0, preview 1 048 576, chrome pair 0, distinct 544/216, prod default vs modal
491 221, distinct `prod-default-light` 529, indicator rects 0 in all
twelve — and **all fourteen images read `differing=0`, scene identical**,
matching all three lanes' own readings (§5.3, §6.3, §7.3). `Expected.swift`
(`DemoFrameDeterminismTests`) is unedited by any lane. Lane 2 moves the
demo's ids (the modal's `if` gains a structural slot) and no pixel moved —
consistent with the spec's prediction (§6, "the images are static frames, the
`List` holds no cross-frame state").

### 8.4 Elsewhere

- **`MetalUILayout` imports only `MetalUICore`**: anchored grep over
  `Sources/MetalUILayout/*.swift`'s `import` lines, no other hit.
- **`Backends/SDL`** (`.accesskit` already fetched;
  `PKG_CONFIG_PATH=$PWD/.accesskit swift build --build-tests` then `swift
  test --no-parallel`): 0 `error:`, the only `warning:` the pre-existing SDL
  dylib deployment-target linker note (`prohibited flag(s):
  -Wl,-rpath,/opt/homebrew/lib`, unrelated to this task); **`Test run with 21
  tests` and `19 tests` passed** (`ReplayFixtureTests`, `MetalUISDLTests`),
  unmoved from lane 3's own reading (§7.3) — no lane touches `Backends/SDL`.
- **`swift:6.4-noble`** (Docker, aarch64), re-run independently over `git
  archive HEAD` (`ea95cc4`) rather than re-read any lane's own measurement:
  `swift build --build-tests` → `Build complete!`, 0 `error:`/`warning:`;
  `swift test --skip-build --filter
  'MetalUICoreTests|MetalUILayoutTests|MetalUICrossPlatformTests'` →
  **188 + 10 + 22 passed** (`MetalUILayoutTests`, `MetalUICrossPlatformTests`,
  `MetalUICoreTests`), matching lane 3's reading exactly;
  `theDemoFrameMatchesTheValuesRecordedOnMacOS` and
  `everyProductionTreeBuildsOnAOneMegabyteThread` green off Apple. Windows
  itself was not run locally (no Windows host in this environment); its build
  is `root-windows` CI's job, unchanged by a task that touches only
  `Sources/MetalUI` files already portable.

### 8.5 Real window — still owed

`xcrun swiftc -O docs/probes/appkit-screen-lock-state.swift -o /tmp/lockstate
&& /tmp/lockstate`, run twice this phase (once before the rebuild above, once
after): both times `session CGSSessionScreenIsLocked = 1`, `displayAsleep
main: 1`, `displayActive main: 0` — the screen was locked throughout, as it
was at all three lanes' own checks (§5.3, §6.3, §7.3). `capture.sh` was not
run. **This is the same debt every lane deferred, not a new one**: lane 2
moves the demo's ids and lane 3 adds `.id(_:)`/a legacy `.background {}`, and
neither is reachable from the demo tree (it holds no `AnyElement`, no value
placed twice, no `.id` on a group and no legacy `.background { content }`),
so the offscreen 0-px reading above is the only evidence available and the
real-window capture would show nothing new if taken. It remains owed to a
human with an unlocked screen, alongside stage 6b's still-open real-window
debt (record §03) — a separate, unrelated capture this task neither closes
nor adds to.

### 8.6 Not done, owners already assigned

- **A group that returns to a name it used earlier** (`.id("a")` → `"b"` →
  `"a"`): neither SwiftUI's nor MetalUI's answer is probed or pinned. **Owner:
  none named** (§7.5) — a probe arm and a test if it matters; the spec asked
  only for a changed name to reset, which is pinned (E3.1–E3.3, E3.8, E3.9).
- **Divergence 74** (an element a `for` loop stops producing keeps its state
  and hands it back if the loop grows again): **plan task 10** (`ForEach`,
  §4).
- **Divergence 54** (a lowered `ScrollView`'s cross axis): unchanged by this
  task, already **plan task 10**'s (record §54 §10.3; this task's audit did
  not reopen it).
- **The `ModifiedElement` typealias, and the eight deprecated sizing
  modifiers**: unchanged by this task, already **plan task 15**'s (closeout).

### 8.7 Docs updated to match this close

`docs/superpowers/specs/2026-09-25-composition-identity-design.md`'s Status
line moves to **DELIVERED**; the decisions doc's Status line is updated the
same way; `CLAUDE.md`/`AGENTS.md` gain a plan-task-8 line in "Where things
are", a new "Counts" bullet, the "Guards" bullet's two new files and helper
split, the rewritten "Identity is structural", "`@State`" and "`Component`"
paragraphs, the grid bullet's `.id()` sentence, the `ID-` prefix line and the
Known-divergences/Declared-but-inert/Human-verification reference-table
bullets; record §04 gets a new dated section (18, 19, 48, 69 retire; 71–74
add; 56 amended); record §05 gets a new dated section (the `@State`-inside-
`AnyElement` row deleted); record §03 gets a new dated section (no look
added — pixels 0, real-window capture still owed, unrelated to stage 6b's own
debt); record §README.md gains this file's row; the plan's task 8 entry gets
a dated progress note and its checkbox moves, since every row of §3's audit
table above is disposed as **M**, **F** or **K** with an owner, matching the
task text's own three-way instruction exactly.

## 9. Adversarial branch check (`e3cb3e9..da2d820`, 2026-09-25, PDT)

One agent, after the Record phase, on the committed tree; every reading below
was re-taken here, none copied from §8.

### 9.1 Suite, guards, build systems, gates

- `swift package clean`, `swift build --build-system native --build-tests`
  (0 `error:`, the only `warning:` SwiftPM's deprecation notice), then
  unfiltered `swift test --build-system native --no-parallel`: **`Test run
  with 1483 tests in 3 suites passed after 84.357 seconds`**; the log carries
  `FR-J no-argument frame: succeeded=true`. `swift build --build-tests` under
  the default build system: 0 `error:`, 0 `warning:`.
- Guards: `grep -c canTypecheck` per file — `MetalUITests` 86 (the two new
  files 1 and 3) plus `UnitSafetyTests` 2 = **88**; at `e3cb3e9` 82 + 2 = 84.
  No goldens exist.
- Green in that run: `theSevenRetentionSlotsAreMutuallyDistinct`,
  `everyProductionTreeBuildsOnAOneMegabyteThread`,
  `theLegacyEngineSymbolsAreAbsentFromTheTestProcess`. `MetalUILayout`'s
  `import` lines: `MetalUICore` only. `cmp CLAUDE.md AGENTS.md` clean.
- **Removed `@Test`s: nine**, each with its retirement row (§5.3's
  `anEnvironmentPropertyInsideAnyElementIsInertAndReadsTheDefault`; §6.3's
  eight, the animation row included). Every other test name the changed docs
  cite resolves to exactly one `func` under `Tests/`, except the retired
  names, which are cited only as retired or in pre-task history rows.
  Every `ID-` id cited resolves (`ID-A`…`ID-Q`; `ID-R` only as "next").
- Pixels: `docs/probes/demo-pixels/compare.sh <scratch> e3cb3e9 da2d820` —
  **all fourteen images `differing=0`, scene identical**, the controls
  non-zero.
- `Backends/SDL` (`PKG_CONFIG_PATH=$PWD/.accesskit swift test`): **21 + 19
  passed**. `swift:6.4-noble` (Docker, aarch64) over `git archive da2d820`:
  `Build complete!`, then **188 + 10 + 22 passed**.
- Lock probe (the seventh reading): `CGSSessionScreenIsLocked = 1`,
  `displayAsleep main: 1`, `displayActive main: 0` — `capture.sh` not run; the
  real-window capture stays owed.

### 9.2 Two mutations of this check's own design

Each from the committed tree, restored from a copy, whole suite unfiltered,
`git status --short` clean after.

| id | mutation (spelling) | result |
|---|---|---|
| **B1** | `StateTable.isWindowRetained`: `id.component == focusRetentionName \|\| id.component == axRetentionName` → `id.component == focusRetentionName` (the `$ax` exemption alone dropped; lane 2's M2f dropped both) | `1483 tests … failed … with 1 issue`: **`aResetKeepsTheFocusAndAccessibilityRetentionSlots`** only (its `$ax` peek). No accessibility end-to-end test reddens, so the exemption's observable purpose (AX node identity across a toggle) is pinned by the table read, not by a VoiceOver-shaped assertion. |
| **B2** | `State.bind`: `if box.boundGeneration != table.generation { box.occurrences = nil }` → the branch left empty (occurrences kept across generations; `ID-F`'s "cleared on the first bind of a later generation") | **`1483 tests … passed`** — reddens nothing. **The mutant differs**, proven by a throwaway test (deleted, never committed): one leaf value placed as `Row { p; Box { p } }` for one frame, then as `Row { Box { p } }`; a write dispatched to the second frame's occurrence lands on its own slot on the original (reads 1) and on the **stale** first-frame occurrence's slot under the mutant (own slot `nil`, stale slot 1). **Finding (test coverage, low)**: the clearing clause is unpinned; `Environment.Box`'s copy of it (`EnvironmentProperty.swift`, `box.occurrences = nil`) was not mutated here and is presumably the same. |

### 9.3 A name that returns — the audit's one open row

§7.5 left "a group that returns to a name it used earlier" unprobed. Probe
revision 3 (arms X9–X11, appended at the end of `run()`; both forms
byte-identical, exit 0, stderr empty; the 51 earlier lines unchanged):

```
X9 .id a, b, a (3 generations): p 72 / 73 / 74
X10 .id a, a, a (3 generations, control for X9): p 75 / 75 / 75
X11 HStack .id a, b, a (3 generations): in 76 / 77 / 78
```

SwiftUI gives the returning name **new** state. MetalUI, one throwaway test
through `Frame.render` against one `StateTable` (deleted): `Row { Box { probe
}.id(n) }` over names a, a, b, a reads **3** (the old count, 2, plus the
returning frame), control a, a, a, a reads 4, and `VStack { HStack { probe
}.id(n) }` (`IdentifiedGroup`) over a, a, b, a reads **3** too. A departed
name's entries are unmarked, not deleted, and `sweep()` reaps them only past
`TB-AH`'s bound, so a name that returns within it finds them. This is a
state-retention difference the task text asks to be closed or documented; it
is not in record §04's table, has no ruling and no pin. **The plan's task 8
box is therefore un-ticked** with a dated progress note; record §04's task-8
section names it for the next round (next unused label 75).

### 9.4 Doc defects fixed by this check

- Record §04's task-8 section: 48's bullet said the width "overwrites" each
  member "where SwiftUI does the same" (SwiftUI frames each member); 71's
  said SwiftUI "has no analogue" (S5: its own occurrence); 73's named a
  token form that does not exist on a multi-member primary; 56's described
  only the alignment sub-row and read L8 as a top-aligned parent. Each
  re-worded, with a corrections paragraph at the section's end.
- `CLAUDE.md`/`AGENTS.md`: the `Component` paragraph's and the divergence
  bullet's "overwrite" (the retired CSS answer) → "frame each member"; the
  grid bullet's "untaken cell/row" wording → an `if` around a cell or row;
  the animation "Snaps" list gains an element returning inside an `if`
  (`ID-P` item 1's ruled change, which the file did not state); the explicit
  identity bullet gains §9.3's open row; the lock-probe count.
- The plan's task 8 entry: box un-ticked, progress note appended.
- Not fixed (code comments, not docs): `LoweringComponentTests`' doc comment
  on `aComponentsWidthFramesEachMember` still describes a "legacy authority"
  arm and divergence 48 as live.

### 9.5 Verdict

**Merge: yes** — no code defect found; identity, hit testing, accessibility
and animation move only where a ruling names the change (`ID-B`, `ID-C`,
`ID-F`, `ID-P` item 1), each with its test. **Task 8: not closed** until §9.3
is ruled and pinned.

## 10. The closeout (`89a8337..`, 2026-09-25, PDT)

One agent, on `feat/composition-identity-closeout` from `89a8337`, for §9's
three findings. Commits `7e31ba7` (red tests), `18e009d` (the fix), `71298eb`
(E3.12's inner arm re-spelled; 4.1's doc comment), then this section with
`ID-R`.

### 10.1 The open row — ruled a fix (`ID-R`), not divergence 75

**Probe first.** `docs/probes/swiftui-composition-identity.swift` re-run at
`89a8337` in both forms (`/usr/bin/swift …` and `xcrun swiftc … && ./probe`):
exit 0 each, stderr 0 lines each, the two stdouts byte-identical to each other
and to the header's recorded 55 lines (a `diff` against the header is empty),
X9–X11 included:

```
X9 .id a, b, a (3 generations): p 72 / 73 / 74
X10 .id a, a, a (3 generations, control for X9): p 75 / 75 / 75
X11 HStack .id a, b, a (3 generations): in 76 / 77 / 78
```

**Decision.** `EP-5` prefers SwiftUI's answer, and the one obstacle §9.3
implied — that a departed name is indistinguishable from a `List` row out of
its window — is a matter of saying which positions are evaluated. `ID-R`:
every site that mints a named id notes it at `(parent, cursor index)`; a
position whose name differs from the last completed frame's departs the old
name, and `sweep()` resets each departed name the frame produced nowhere (at
and under its id, `$focus`/`$ax` kept, the deletion shared with `ID-C`'s
`noteAbsent`). A `List`'s rows are exempt (`ListRows` →
`noteWindowedParent`): a row keeps its id while out of window — it is not
evaluated, not departed — so `TB-AH` is untouched. Only an evaluated position
departs a name; a loop shrinking at its tail (divergence 74), an `if` gone
false (`ID-C`'s own reset) and a name → no-name change (not noted, so unnamed
elements pay nothing) depart nothing here (`ID-R` item 4).

**Tests** (`ExplicitIdentityTests.swift`):

| test | shape | red before (`7e31ba7`'s tests on `89a8337`'s sources) |
|---|---|---|
| E3.10 `anIDThatReturnsToAnEarlierNameStartsFresh` | names a, a, b, a and a, a, a, a; `Box` in a `Row`, root `Box`, `IdentifiedGroup` in a `VStack` and in a `Row`, a named leaf counting at its own id | 5 issues: every changed arm reads **3** (the fresh answer is 1); the five controls read 4 |
| E3.11 `aNameThatMovesToASiblingsPositionKeepsItsState` | two named `Box`es swapping names every frame | green (pin): 3 and 3 |
| E3.12 `everyNamingSiteStartsAReturningNameFresh` | the same over `AnyElement`, a `Component` declaring `elementID`, a named inner modifier layer (`.padding(2).id(n).padding(4)`) | 3 issues, each arm **3** (E3.12's first inner spelling, `.id(n).padding(4)`, also read 3 but reached `enteringGroupMember`, not `innermostID` — see MRf) |

One existing test moved its fixture, not its assertion (`ID-R` item 5):
`StateTableTests.anElementThatStopsBeingProducedLosesLivenessButKeepsItsValue`
rendered root `"a"` then root `"b"` — a rename now, which reset `a` (2 issues
on the fix's first run); its second root is unnamed.

### 10.2 `ID-F`'s generation clause (the branch check's B2)

`OccurrenceIdentityTests.swift`: **O1.11**
`aStateBoxForgetsTheOccurrencesOfAnEarlierGeneration` — one value as `Row { p;
Box { p } }` for a frame, then `Row { Box { p } }`; a write dispatched to frame
2's occurrence (`root/0/0/0`) lands on its own slot, not frame 1's `root/0/0`.
**O1.12** `anEnvironmentBoxForgetsTheOccurrencesOfAnEarlierGeneration` — the
same shape through `Environment` (scopes 7 and 9, then 5): the dispatched read
is 5. Both green before (pins of an unpinned clause); each reddened by its own
copy's mutation alone (B2, B2e below). **B2e was unpinned too**: the whole
suite under it reddens O1.12 alone.

### 10.3 Mutations

Each from the committed tree (`18e009d`, then `71298eb` for MRf/MRi's re-run),
applied by exact-string substitution to one site, whole suite unfiltered, file
restored from a copy, `git status --short Sources` empty after each.

| id | site and spelling | reddened (issues) |
|---|---|---|
| MRa | `StateTable.noteNamed`: `guard case .named = id.component, false` (records nothing) | E3.10 (5), E3.12 (3) |
| MRb | `sweep()`: `for name in departedNames` (the produced-anywhere check dropped) | E3.11 (1), `aNamedComponentKeepsItsStateThroughAReorderAndAnUnnamedOneDoesNot` (2), `reorderingANamedListCarriesEachItemsState` (3) |
| MRc | `noteWindowedParent`: `_ = parent` (the `List` exemption dropped) | `aListRowsStateSurvivesABoundedExcursionButNotALongerOne` (1), `aConditionalInAWindowedListRowIsNotResetByAnExcursion` (1) |
| MRd | `AnyElement`'s group entry: its `noteNamed` line commented out | E3.12 (1, the `AnyElement` arm) |
| MRe | untyped `Component.requestGroupLayout`: its `noteNamed` line deleted | E3.12 (1, the `Component` arm) |
| MRf | `ModifiedContent.innermostID`: `table.noteNamed(innermostID, at: 0)` → `_ = table` | at `18e009d`: **none** (1488 passed — E3.12's inner arm, `Box { p }.id(n).padding(4)`, names the chain's content, noted by `enteringGroupMember`); after `71298eb`'s re-spelling (`.padding(2).id(n).padding(4)`): E3.12 (1) alone |
| MRg | `IdentifiedGroup.slot`: its note → `_ = table` (both entries share it) | E3.10 (2, the two `IdentifiedGroup` arms) |
| MRh | `Frame.render`'s root note → `_ = rootID` | E3.10 (1, the root arm) |
| MRi | `GlobalElementID.enteringGroupMember`: its note deleted | at `18e009d`: E3.10 (2), E3.12 (1, the then inner arm); at `71298eb`: E3.10 (2) — the `Box` and named-leaf arms |
| MRj | `resetEntries`: `(includingRoot && false && id == root)` (the departed id itself kept) | E3.10 (1, the named leaf counting at its own id) |
| MRk | `resetEntries`: `&& !Self.isWindowRetained(id)` dropped (the shared exemption, both resets) | `aResetKeepsTheFocusAndAccessibilityRetentionSlots` (2), `aFocusedTextFieldInsideAToggledIfKeepsFocusAndStartsItsEditStateFresh` (3), `focusOnAnElementThatStopsBeingProducedIsRetainedWithinTheWindow` (1), `aFocusRequestWhileDisabledLeavesNoRetentionSlot` (1) |
| B2 | `State.bind`: the `box.occurrences = nil` branch left empty | O1.11 (2) alone |
| B2e | `Environment.bind`: the same | O1.12 (1) alone |
| MSw | `Frame.render`: `stateTable.sweep()` moved to the start of the build | `anElementThatStopsBeingProducedLosesLivenessButKeepsItsValue` (1) alone — its moved fixture still pins the ordering |

MRk reaches only `noteAbsent`'s tests, not a rename test: a rename that keeps
`$focus`/`$ax` is asserted by nothing of its own; the exemption is one line
both resets share, so the four tests above pin it for both.

### 10.4 Gates

- `swift package clean`, `swift build --build-system native --build-tests`:
  `Build complete!`, 0 `error:`, the only `warning:` SwiftPM's deprecation
  notice. Unfiltered `swift test --build-system native --no-parallel`:
  **`Test run with 1488 tests in 3 suites passed after 83.901 seconds`**; the
  log carries `FR-J no-argument frame: succeeded=true deprecations=2` (guards
  ran), `CONDITIONAL GUARD G2.1 positive: succeeded=true`, `EXPLICIT IDENTITY
  GUARD G3.1 positive: succeeded=true`; eleven gated tests skipped. **1488 =
  1483 + 5** (E3.10, E3.11, E3.12, O1.11, O1.12). Guards **88**, unmoved (no
  new guard); goldens 0.
- Green in that run: `everyProductionTreeBuildsOnAOneMegabyteThread`,
  `theSevenRetentionSlotsAreMutuallyDistinct`,
  `theLegacyEngineSymbolsAreAbsentFromTheTestProcess`,
  `theDemoFrameMatchesTheValuesRecordedOnMacOS`, and every allocation pin.
  `METALUI_RUN_100K_LIST_TEST=1 … aListsWorkIsTheSameFor100kRowsAsFor500`:
  passed (27.6 s).
- `swift build --build-tests` (default build system): 0 `error:`, 0
  `warning:`.
- Pixels: `docs/probes/demo-pixels/compare.sh <scratch> 89a8337 71298eb` —
  controls at their recorded values (light/dark 1 048 576, default vs modal
  1 031 003, default vs animation 454 895, f0 vs f3 0, preview 1 048 576,
  chrome pair 0, distinct 544/216/529, prod default vs modal 491 221,
  indicator rects 0) and **all fourteen images `differing=0`, scene
  identical**. The demo names nothing that changes.
- Not re-run: `Backends/SDL` and the `swift:6.4-noble` container (no file
  either reads changed beyond `Sources/MetalUI`, already portable, and no
  new API); the real-window capture stays owed (§8.5), unchanged by a fix the
  demo cannot reach.

### 10.5 Result

§9's three findings are closed: the open row is fixed and pinned (E3.10–E3.12,
`ID-R`), the generation clause is pinned on both copies (O1.11, O1.12), and
4.1's comment is history. No divergence is added (75 stays unused); record
§04's task-8 section gains a closeout note. **Plan task 8's box is ticked.**
