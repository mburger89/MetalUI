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
