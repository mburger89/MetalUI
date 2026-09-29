# Interaction — design (plan task 12, part 1)

Branch `feat/interaction` from `31f2e7a` (master, task 11 closed, record §61).
Rulings `IX-A`…`IX-O` in a new decisions doc,
[`../2026-09-29-interaction-decisions.md`](../2026-09-29-interaction-decisions.md)
(next unused **`IX-Q`**; `IX-O` is the critic round's, `IX-P` lane 1's landing). Evidence: `docs/probes/swiftui-interaction.swift`
(**new**, arm ids `G…` gestures, `H…` hierarchy precedence, `B…` buttons, `PX…`
looks, `F…`/`K0` focus, `C…` content shapes, `X1`–`X4` the critic round's;
its header carries the recorded output, what the instrument cannot see, and
the reading), and three existing
probes **re-run** this session, compiled, reading their recorded values:
`swiftui-content-shape-hit-region.swift`, `swiftui-disabled-interaction.swift`,
`swiftui-disabled-ancestor-and-order.swift`. Record: `docs/record/62-interaction.md`
(the Record phase writes it).

**Status: DESIGNED, critic round applied (`IX-O`).** This is the plan's task 12 **first sentence** —
"Specify gesture composition, button semantics, disabled behaviour, keyboard
focus, pointer hit testing and content shapes." The second sentence — deliver
and validate the accessibility bridge with VoiceOver — is **part 2** (`IX-A`).
**Task 12's box stays unticked.**

## 1. Baseline

`31f2e7a`, this worktree with its own `.build`: `swift build --build-system
native --build-tests` then unfiltered `swift test --build-system native
--no-parallel` → **`Test run with 1773 tests in 3 suites passed after 110.836
seconds`** (re-taken by this design session; 0 `error:`, the one `warning:`
SwiftPM's deprecation notice; the log carries `FR-J no-argument frame:
succeeded=true`, so the guards ran); **108** typecheck guards
(CLAUDE.md's count at `31f2e7a`), 0 goldens, **68** live divergences, next
label **94**.

The probe ran with the screen **locked** (lock probe:
`CGSSessionScreenIsLocked = 1`, `displayAsleep main: 1`), compiled, twice,
byte-identical, 156 lines. The synthesized click/key harness works locked:
every positive control passes (`G0`, `K0`, `C0`, `PX0`). Its blind spots —
text and bezel pixels, a real key window, the focus ring — are listed in its
header and every rule resting on one is stated as MetalUI's choice
(`IX-E` item 3, `IX-G` item 2, `IX-H` item 2). The real-window capture is
**not taken** (screen locked; `docs/probes/window-capture/capture.sh` stays
owed, as at every task since stage 6b).

## 2. The audit — every item addressed to plan task 12 (`IX-A`)

Collected by `grep -rn -i "task 12"` over `docs/superpowers/`, `docs/record/`
(excluding frozen §19), `Sources/`, `Tests/` and the plan, 2026-09-29.
"Arm" is this session's probe arm, or **unmeasured**.

| # | item (source) | SwiftUI arm | MetalUI at `31f2e7a` | verdict | where |
|---|---|---|---|---|---|
| 1 | gesture composition: tap/count, long press, drag, `gesture`/`simultaneousGesture`/`highPriorityGesture`, `exclusively`/`simultaneously` (plan text; `DD-AB` 7; `ClickDispatch.swift` doc) | G0–G9, H0–H17 | `onClick` only; one hitbox, no chaining | **built** | lane 1, `IX-B`–`IX-D` |
| 2 | a public tap-with-modifiers (`DD-Z` 9, `DD-AC`) | unmeasured | internal `ClickDispatch` | not offered | owner none, `IX-B` |
| 3 | `sequenced`, `@GestureState`, `GestureMask`, custom `body` gestures, location taps | unmeasured | — | not offered | owner none, `IX-B` |
| 4 | `Button(role:)` (`DD-AB` 7) | B4c, B4d, B5; look blind (PX3, PX13, PX14) | — | **built**, role reads nothing (inert row) | lane 2, `IX-E` 1 |
| 5 | `.buttonStyle(.bordered/.borderless/.plain)` (`DD-AB` 7; `DD-AC` "a plain-looking button") | BT1 sizes (controls probe) | automatic only | **built** | lane 2, `IX-E` 2 |
| 6 | `ButtonStyle`/`PrimitiveButtonStyle` protocols, `.borderedProminent`, `.link` (`DD-AB` 7) | — | — | not offered | owner none, `IX-E` 2 |
| 7 | pressed state and look (`DD-AB` 7; `Button.swift` doc; `PaintPass.isActive` inert row, record §05) | B0–B3; look blind (PX21, PX22) | no look | **built** | lane 2, `IX-E` 3 |
| 8 | `.keyboardShortcut` (`DD-AB` 7, KY3) | B4a–B4l; K3/K4 re-run | — | **built**, `Button` only | lane 2, `IX-F` |
| 9 | a disabled look (plan note 2026-09-15; record §11; `DD-AB` 7) | blind (PX2, PX6, PX8, PX10, PX12) | none | **built**, MetalUI's choice | lane 2, `IX-G` 2 |
| 10 | divergence 21: focus retention on disable (`EV-F`; plan note) | K2 re-run | focus lost at once | **kept** | owner none, `IX-G` 1 |
| 11 | divergence 22: raw keys on a disabled ancestor (`EV-F`) | K6, K8 re-run | refused | **kept** | owner none, `IX-G` 1 |
| 12 | an inactive-window look (`EV-AE`; `ControlActiveState.swift`, `EnvironmentValues.swift`; record §05 inert row) | PX17–PX20 | inert | **built** | lane 2, `IX-H` 1 |
| 13 | focus ring policy (`DD-AB` 7; controls spec §2) | blind (F7 = F8) | opt-in `focusBorder`; controls draw none | **built** for controls | lane 2, `IX-H` 2 |
| 14 | `@FocusState` / `.focused(_:)` (the brief) | K0, F1, F2, F4 | `Window.focus(_:)` only | **built** | lane 3, `IX-J` |
| 15 | focus after an identity rename or an `if` (`ID-R` 9; record §55 §10.6, §04; C2.13; C2.8, C2.12's exemption) | F1, F2 | kept, returns with the element | **fixed** (behaviour change, migration note) | lane 3, `IX-I` |
| 16 | Full Keyboard Access, divergence 80, Tab to controls (`DD-T` 3; record §60; `DD-` doc "focusable controls are task 12's") | F5, F6 (FKA off) | everything focusable | **kept, amended** (now measured) | owner none, `IX-K` 1 |
| 17 | click-to-focus (`Window.focus(_:)`'s "a policy decision") | F3, F4 | a click never focuses | **divergence 94 added**, kept | owner none, `IX-K` 2 |
| 18 | focus and keys under `hidden()` (`LR-AK`/`LR-AV`/`LR-DH`; `focusable()` doc) | F9; X1 (a hidden button's shortcut fires) | a hidden focusable takes focus and keys | **fixed** (focus/keys out; shortcuts stay) | lane 3, `IX-K` 3 |
| 18b | a hidden scroll region still takes the wheel (`LR-AV` item 5; `OM-AK`) | unmeasured | takes the wheel | **kept** | owner none, `IX-K` 3 |
| 19 | `.contentShape` taking a `Shape` (`OM-J`/`OM-AB`, outer-modifiers §; shapes spec §9; `DecorationCompileGuards`) | C1, C2, C10, C11, C13 | `contentShape(inset:)` only | **built** | lane 2, `IX-L` 1 |
| 20 | `contentShape(kind:)`, `eoFill` (outer-modifiers "deferred to task 12 by name") | — | — | not offered | owner none, `IX-L` 1 |
| 21 | hit behaviour under `clipShape` (`TE-AQ` 4; shapes spec §4) | C3, C4, C8, C9 | clip rect intersects | **pinned**; divergence 43 amended | lane 2, `IX-L` 2 |
| 22 | divergence 57: a non-clickable primary blocking its background's click (`CN-K`; containers carried table) | H18, C12 | passes through | **kept, pinned** (was unpinned) | lane 2, `IX-L` 3 |
| 23 | a shape's default hit region | C5–C7 | its frame | divergence 41 amended | owner none, `IX-L` 4 |
| 24 | menus, `.contextMenu`, `.pickerStyle(.menu)`, divergence 81 (`DD-V` 4; `DD-AB` 7; `Picker.swift` doc) | — | none | **not built** | owner none, `IX-M` |
| 25 | `ToggleStyle` `.switch`/`.button` (`DD-AB` 7) | — | — | not offered | owner none, `IX-M` |
| 26 | proposal-path focus (modifier-composition carried table) | — | — | not offered | owner none, `IX-M` |
| 27 | the VoiceOver script (plan text; record §12) | human | — | — | **part 2** (a human) |
| 28 | settable `AXSelected`/`AXSelectedRows`, divergence 83 (`DD-Z` 8) | LA2–LB3 | press only | — | **part 2** |
| 29 | `accessibilityElement(children:)`, hidden/combination modifiers, extra traits, custom and declared actions, a non-button click absorber (`AB-` table; `EV-AE`) | — | — | — | **part 2** |
| 30 | `AB-H`'s press question, divergence 28; whether an accessibility press focuses (`DD-` doc, "if task 12 rules that a press must not focus") | P0/P1 | refused under hit-testing-off | — | **part 2** |
| 31 | modal isolation and press occlusion (`AB-` table; `AB-H` "not checked") | — | — | — | **part 2** |
| 32 | divergence 32; accessibility scrolling to unrealised rows (`DD-AB` 4, `AB-L`) | LA0 | — | — | **part 2** |
| 33 | divergence 82 (`DD-U`) | — | — | — | **part 2** |
| 34 | `AB-Q` proposal-path accessibility, grids included | — | — | — | **part 2** |
| 35 | an `onTap` control's and an image's VoiceOver presence (`TE-O`; `Image.swift` doc) | — | — | — | **part 2** |
| 36 | `AXNode.actions`' inert row (`AB-` doc) | — | — | — | **part 2** |
| 37 | the `DD-` rulings' "if task 12's VoiceOver validation prefers…" costs | — | — | — | **part 2** |
| 38 | `controlSize`'s consumers (`EV-AE` table) | — | delivered by tasks 10/11 | nothing left here | — |

## 3. What the probe measured (the short form)

The probe header has every line; the rulings cite arms. In one paragraph: a
tap ends on the release and fails on a 5-pt move; a single tap beside a double
waits ~0.33 s; a long press ends while held; a drag starts at exactly its
minimum distance and ends wherever it is released; inner normal gestures beat
outer ones, outer high-priority ones beat inner, simultaneous ones fire too
and first, and a lower gesture ends only after every higher one failed — on
one view exactly as across a parent and child. `isPressed` is "pressed and
over it". A role binds no key; shortcuts match exactly, need no focus, lose to
a focused key handler and to nothing disabled. Accent controls lose their
accent when inactive. Focus drops with its identity and does not return; a
click focuses a `.focusable()` view; with Full Keyboard Access off, Tab moves
nothing; a hidden view cannot be focused, but a hidden button's shortcut still
fires (`X1`). A focused text field takes Return ahead of the default button
(`X2`); a parent drag behind a child `Button` neither changes nor ends (`X3`,
`X4`). `contentShape` restricts a hit; `clipShape` does not.

## 4. Public API (spelling ruled against the SDK interfaces)

**Lane 1 — gestures** (`IX-B`):

```swift
public protocol Gesture { associatedtype Value }          // closed: an internal requirement
public struct TapGesture: Gesture { public init(count: Int = 1)
    public func onEnded(_ action: @escaping @MainActor () -> Void) -> TapGesture }
public struct LongPressGesture: Gesture { public init(minimumDuration: Double = 0.5, maximumDistance: Pixels = Pixels(10))
    public func onEnded(_ action: @escaping @MainActor (Bool) -> Void) -> LongPressGesture
    public func onChanged(_ action: @escaping @MainActor (Bool) -> Void) -> LongPressGesture }
public struct DragGesture: Gesture { public init(minimumDistance: Pixels = Pixels(10))
    public struct Value: Equatable, Sendable { public var startLocation: Point<Pixels>
        public var location: Point<Pixels>; public var translation: Size<Pixels> }
    public func onChanged(_ action: @escaping @MainActor (Value) -> Void) -> DragGesture
    public func onEnded(_ action: @escaping @MainActor (Value) -> Void) -> DragGesture }
public struct ExclusiveGesture<First: Gesture, Second: Gesture>: Gesture { … }
public struct SimultaneousGesture<First: Gesture, Second: Gesture>: Gesture { … }
extension Gesture {
    public func exclusively<Other: Gesture>(before other: Other) -> ExclusiveGesture<Self, Other>
    public func simultaneously<Other: Gesture>(with other: Other) -> SimultaneousGesture<Self, Other>
}
extension StyledElement {                                   // each APPENDS, returns Self
    public func onTapGesture(count: Int = 1, perform action: @escaping @MainActor () -> Void) -> Self
    public func onLongPressGesture(minimumDuration: Double = 0.5, maximumDistance: Pixels = Pixels(10),
                                   perform action: @escaping @MainActor () -> Void,
                                   onPressingChanged: (@MainActor (Bool) -> Void)? = nil) -> Self
    public func gesture<G: Gesture>(_ gesture: G) -> Self
    public func simultaneousGesture<G: Gesture>(_ gesture: G) -> Self
    public func highPriorityGesture<G: Gesture>(_ gesture: G) -> Self
}
extension ProposalElementGroup {                            // the same five, each a GestureModifier<Self>
    public func onTapGesture(count: Int = 1, perform: …) -> GestureModifier<Self>   // …and the other four
}
public struct GestureModifier<Content: ProposalElementGroup>: Element { … }        // OnTapModifier's shape
```

`onClick` and the proposal `onTap` are unchanged (`IX-D` item 2); `onClick`'s
doc comment is corrected ("SwiftUI's `onTapGesture`" → Button semantics:
press and release on the same element, excursion allowed).

**Lane 2 — buttons** (`IX-E`, `IX-F`):

```swift
public struct ButtonRole: Equatable, Sendable { public static let destructive, cancel, confirm, close: ButtonRole }
extension Button where Label == Text { public init(_ title: String, role: ButtonRole?, action: …) }
extension Button { public init(role: ButtonRole?, action: …, @ElementBuilder label: () -> Label) }
public struct ButtonStyle: Equatable, Sendable {            // closed, PickerStyle's precedent
    public static let automatic, bordered, borderless, plain: ButtonStyle }
extension Button {
    public func buttonStyle(_ style: ButtonStyle) -> Self
    public func keyboardShortcut(_ key: KeyEquivalent, modifiers: EventModifiers = .command) -> Self
    public func keyboardShortcut(_ shortcut: KeyboardShortcut) -> Self
    public func keyboardShortcut(_ shortcut: KeyboardShortcut?) -> Self
}
public struct KeyEquivalent: Equatable, Sendable, ExpressibleByExtendedGraphemeClusterLiteral {
    public init(_ character: Character); public let character: Character
    public static let `return`, escape, space, tab, delete, deleteForward, upArrow, downArrow,
                      leftArrow, rightArrow, home, end, pageUp, pageDown, clear: KeyEquivalent }
public struct KeyboardShortcut: Equatable, Sendable {
    public init(_ key: KeyEquivalent, modifiers: EventModifiers = .command)
    public let key: KeyEquivalent; public let modifiers: EventModifiers
    public static let defaultAction, cancelAction: KeyboardShortcut }
public typealias EventModifiers = Modifiers                 // narrower than SwiftUI's (IX-F 1)
```

**Lane 3 — focus** (`IX-J`); **content shapes are lane 2's** (`IX-L`, moved by `IX-O`):

```swift
@propertyWrapper public struct FocusState<Value: Hashable> {
    public init() where Value == Bool
    public init<T: Hashable>() where Value == T?
    public var wrappedValue: Value { get nonmutating set }
    public var projectedValue: Binding { get }
    @MainActor public struct Binding { … }                   // FocusState<Value>.Binding, SwiftUI's name
}
extension StyledElement {
    public func focused(_ condition: FocusState<Bool>.Binding) -> Self
    public func focused<Value: Hashable>(_ binding: FocusState<Value>.Binding, equals value: Value) -> Self
    public func contentShape<S: Shape>(_ shape: S) -> Self
}
extension OnTapModifier { public func contentShape<S: Shape>(_ shape: S) -> Self }
extension GestureModifier { public func contentShape<S: Shape>(_ shape: S) -> Self }
```

## 5. Dispatch (`IX-D`, `IX-F`, `IX-I`, `IX-L`)

`Window.onInput`'s order becomes (**bold** is new; everything else unchanged):
pointer state → wheel routing → text-field pointer/text → slider track →
**gesture arena** (in place of `dispatchClick`, which it contains exactly when
the arena holds only the target's `onClick`) → keymap → a focused field's
editing keys → raw `onKey` bubble → **keyboard shortcuts** → Tab traversal →
`Window.onInput`'s fallback.

- **One hitbox list, one ranking.** The arena is formed from
  `topmostOpaqueHitbox(in: lastHitboxes, at:)` and the target id's ancestor
  chain; its ancestor members are `lastHitboxes` entries matched by id and
  `Hitbox.contains(_:)`. `Hitbox.contains(_:)` (lane 1 adds it as
  `bounds.contains`; lane 2 adds the shape) is the single region test, called by
  `topmostOpaqueHitbox` and the arena. No second copy of the
  `(layer, registration index)` rule.
- **Time.** The window stamps a pending long press or deferred tap at the first
  display-link tick after it (`IX-C` 4), advances the arena at the start of
  `drawFrameIfNeeded` (before the frame builds, so a callback's `@State` write
  lands in that frame and is not a phase write), and calls
  `requestAnotherFrame`-equivalent dirtying only while something is pending.
  Tests drive `simulateTick(timestamp:)`; nothing sleeps.
- **Shortcuts** ride `Handlers` into `FocusRegistry` (registration order = tree
  order), so the one `isEnabled` gate covers them; `allowsHitTesting(false)`
  does not, and **neither does lane 3's hidden condition** (`X1`; `IX-K` 3
  gates the keyboard focus half only).
- **Withheld members** (`IX-D` 3, `X4`): a member behind a pending one reports
  neither a change nor an end; `onClick` does not fail on a move, so a
  target's `onClick` holds an ancestor's normal drag off for the whole press.
- **One region test**: `topmostOpaqueHitbox` and
  `Window.enclosingScroller(of:at:)` both call `Hitbox.contains(_:)` (the
  latter calls `bounds.contains` itself at `31f2e7a`). The second call site is
  a consistency edit with **no reachable difference** — a scroll region never
  carries a content shape — so it is pinned by the recorded grep (no
  `bounds.contains(` outside `Hitbox.contains`), not by a mutation that could
  not redden.
- **Focus.** Lane 3's `$focus` reset and `@FocusState` reconciliation both run
  at the frame boundary beside `Frame.resolveFocus()`.

## 6. Lanes — AT MOST THREE, run in order 1, 2, 3 (`IX-N`, re-cut by `IX-O`)

Every lane: tests red first (each test below names why it is red at the lane's
start), then green; every **new** typecheck guard mutated red once; each named
mutation applied from a commit, restored from a copy, the whole suite run
unfiltered, `git status --short` clean after, the reddened tests named. A lane
appends its section to the record only through its landing ruling (`IX-O`…) in
the decisions doc; the Record phase writes record §62.

`HandlerShape` (`ModifierTests`) and `HandlerFingerprint`
(`OuterModifierMatrixTests`) gain one field per new `Handlers` member, in the
lane that adds it (CLAUDE.md "StyledElement"). **Every lane adding a
`Handlers` member** records `MemoryLayout<Handlers>.size` before and after and
the smallest thread building every production tree (**592 KB** at `31f2e7a`,
re-measured by lane 1 — the 528 KB first written here was CLAUDE.md's stale
figure, record §59 had 592; 608 KB after lane 1, `IX-P`; each new member one reference, array or small optional, a
`Shape` in a class box — `IX-N`); `everyProductionTreeBuildsOnAOneMegabyteThread`
green. `Handlers` and `Hitbox` gain stored properties and `Handlers` is public and
read across the test-module boundary, so such a lane takes its counts after
`swift package clean` (CLAUDE.md "Build and test").

### Lane 1 — gestures and the arena

**Files.** New `Sources/MetalUI/Gesture.swift` (protocol, the five gesture
types, recognizers, `GestureArena` — pure, no `Window`), new
`Sources/MetalUI/GestureModifiers.swift` (the `StyledElement` and proposal
modifiers, `GestureModifier`), `Handlers.swift` (member `gestures`,
`isPointerTarget`), `Hitbox.swift` (`contains(_:)` only; the ranking calls it),
`Window.swift` (the arena in the pointer path; the tick advance),
`Frame.swift` (the `insertHitbox` call only: the hitbox records the element's
unclipped origin for local drag values), `Box.swift` (`onClick`'s doc comment
only), `ClickDispatch.swift` (doc only). Tests: new
`Tests/MetalUITests/GestureTests.swift` (through a real `Window` on a
`FakePlatformWindow`), `GestureArenaTests.swift` (the pure arena),
`GestureCompileGuards.swift`.

| id | test | red before because | mutation that must redden it |
|---|---|---|---|
| 1.1 | `aTapGestureEndsOnTheReleaseNotThePress` (G1) | no `onTapGesture` | M1a: end on `mouseDown` |
| 1.2 | `aTapGestureFailsOnceThePointerMovesFivePoints` (G2g 4 pt fires; G2b 5 pt does not) | no API | M1b: slop 5 → 6 (reddens the 5-pt arm); M1b′: slop check removed |
| 1.3 | `aTapReleasedAfterAnExcursionDoesNotFireWhereOnClickDoes` (G2d vs B1) | no API | M1b′ |
| 1.4 | `aCountTwoTapEndsOnTheSecondReleaseByClickCount` (G3a, G3b) | no API | M1c: compare the tap count with `>=` 1 |
| 1.5 | `aSingleTapBesideADoubleWaitsAThirdOfASecondThenFires` (G5e: nothing at a tick 0.30 s after the release's stamp tick, fired at the first tick ≥ 0.33 s after it — `IX-C` 4) | no API | M1d: deferral 0.33 → 0 |
| 1.6 | `aDoubleClickRunsOnlyTheDoubleWhicheverIsInner` (G4b, G5b, H15b) | no API | M1e: drop the count dependency (single ends at its release) |
| 1.7 | `aLongPressEndsWhileHeldAtItsDuration` (G6a: ticks at 0.2 nothing, 0.35 fired, before the release) | no API | M1f: end the long press at the release |
| 1.8 | `aLongPressFailsOnAQuickClickAndPastItsMaximumDistance` (G6b, G6c 30 pt, G6d 5 pt ends) | no API | M1g: max distance unchecked |
| 1.9 | `onLongPressGestureBracketsThePressWithPressingChanges` (G6e, G6f) | no API | M1h: no `false` on a failed press |
| 1.10 | `aDragChangesFromExactlyItsMinimumDistanceInLocalYDownSpace` (G8a, G8b: first change (10,0); upward (0,−50); start (100,100) in a 200×200 element placed at (50,50) of the window) | no API | M1i: `>=` → `>`; M1i′: window coordinates |
| 1.11 | `aDragShortOfItsMinimumReportsNothingAndMinimumZeroReportsAClick` (G8c, G8d, G8e) | no API | M1i″: end a drag that never started |
| 1.12 | `aDragEndsWhereverItIsReleased` (G8f: released outside the window) | no API | M1j: end only inside the element |
| 1.13 | `anInnerGestureBeatsAnOuterNormalOneOnAChildOrOneElement` (H0, H1, H12) | no API | M1k: normal members outermost-first |
| 1.14 | `anOuterHighPriorityGestureBeatsTheInnerOneAndAButton` (H2, H8, H11, H14) | no API | M1l: high priority treated as normal |
| 1.15 | `aSimultaneousGestureFiresFirstBesideTheWinner` (H3, H7, H10, H13: order `p` then `c`) | no API | M1m: simultaneous callbacks after the winner's |
| 1.16 | `aFailedHigherGestureHandsThePressToTheNextOne` (H4a/H4b, H5a/H5b, H6a/H6b, G7a/G7b, G9a/G9b) | no API | M1n: a member ends without waiting for the members ahead |
| 1.17 | `exclusivelyTriesItsFirstMemberAndSimultaneouslyRunsBoth` (H15a, H16a, H16b) | no API | M1o: `simultaneously` resolved exclusively |
| 1.18 | `aParentsOnClickStillNeverSeesAChildsPress` (a parent `onClick` over a child whose drag fails: nothing fires — `IX-D` 2) | green today, **written first and kept green**; reddened only by the mutation | M1p: ancestors' `onClick` join the arena |
| 1.19 | `aDisabledOrHitTestingOffGestureLeavesThePressToItsParent` (H17, N1) | no API | M1q: gestures registered outside the hitbox gate |
| 1.20 | `aGestureCallbackWritesTheOccurrenceThatDispatchedIt` (`ID-F`: one value placed twice) | no API | M1r: callback run without `StateDispatch` |
| 1.21 | `aProposalGestureModifierRecognizesAsTheLegacyOneDoes` (1.1, 1.10, 1.14 on an `HStack` child) | no API | M1s: `GestureModifier` registers no gestures |
| 1.22 | `aPendingGestureKeepsFramesComingOnlyWhilePending` (`framesDrawn` over ticks: frames while a long press is held, none after it ends) | no API | M1t: request frames unconditionally while pressed |
| 1.23 | `aChildsOnClickHoldsOffAParentsDragWhichReportsNothing` (X3, X4: click and a 30-pt move inside the child both run the child's `onClick`, the parent drag's `onChanged`/`onEnded` never run; released outside the child: no callback at all — `IX-D` 3's unmeasured corner) | no API | M1u: withhold ends only (a behind member's `onChanged` runs) |
| G1.1 | `anOutsideTypeCannotConformToGesture` (plain-import `typecheckFile`; control arm: `TapGesture()` compiles) | new guard | mutate red once (make the requirement public) |
| G1.2 | `theGestureSpellingsCompileFromAPlainImport` (every §4 lane-1 spelling; negative arm: `sequenced(before:)` does not) | new guard | mutate red once |

**Must stay green, unedited**: every existing click, hover, active, wheel and
`ClickDispatch` test (the arena with only an `onClick` is `dispatchClick`),
`InputDispatchTests`, `aPressHeldAcrossARebuildClicksItsOwnTargetAndAVanishedTargetClicksNothing`,
the `List` selection tests. **Grep check** (recorded): `topmostOpaqueHitbox`
is still the only function comparing `(layer, offset)`; after lane 2,
`grep -n "bounds.contains(" Sources/MetalUI` finds only `Hitbox.contains`.

### Lane 2 — buttons, shortcuts, the disabled and inactive looks, the ring

**Files.** `Button.swift`, new `Sources/MetalUI/ButtonStyle.swift` (`ButtonRole`,
`ButtonStyle`), new `Sources/MetalUI/KeyboardShortcut.swift` (`KeyEquivalent`,
`KeyboardShortcut`, `EventModifiers`, the matcher, `Window`'s
`dispatchShortcut` as an extension), `Handlers.swift` (member
`keyboardShortcut`, `isKeyTarget` — one member), `Focus.swift` (the shortcut
table in registration order), `Window.swift` (**one** call, between the raw
`onKey` bubble and Tab traversal), `Toggle.swift`, `Slider.swift`,
`Stepper.swift`, `Picker.swift` (disabled scope, accent-when-key, ring), a
shared helper in new `Sources/MetalUI/ControlLook.swift`
(`controlAccent(_ environment:)`, `paintControl(disabled:)`), `EnvironmentValues.swift`
and `ControlActiveState.swift` (doc comments only). **Content shapes (moved from
lane 3 by `IX-O`)**: `Handlers.swift` (member `contentShape` — a shape box),
`Hitbox.swift` (the geometry on the record, `contains(_:)`'s shape half),
`Window.swift` (`enclosingScroller`'s filter through `Hitbox.contains`),
`Shape.swift` (`ShapeGeometry.contains(_:)`), `Box.swift` (`contentShape(_:)`),
`NativeTappable.swift` (`contentShape` on `OnTapModifier`),
`GestureModifiers.swift` (`contentShape` on `GestureModifier`, one method).
Tests: new `ButtonSemanticsTests.swift`, `KeyboardShortcutTests.swift`,
`ControlLookTests.swift`, `ContentShapeTests.swift`, `ButtonCompileGuards.swift`;
`DecorationCompileGuards.swift` gains one new guard `@Test` (G2.2).

| id | test | red before because | mutation that must redden it |
|---|---|---|---|
| 2.1 | `aButtonRoleBindsNoKeyAndChangesNothingDrawn` (B4c, B4d, B5: Escape/Return do nothing; the scene equals the role-less button's) | no `role:` | M2a: `.cancel` binds Escape |
| 2.2 | `plainAndBorderlessButtonsAreTheirLabelsSize` (BT1: the label's size; `.bordered` = `.automatic` = today's `textW + 24 × max(textH, 24)`) | no `buttonStyle` | M2b: `.plain` keeps the padding |
| 2.3 | `aButtonPaintsPressedOnlyWhilePressedAndOverIt` (B0–B3 through a real `Window`: down → the wash quad present; drag out → absent; back → present; up → absent) | no look | M2c: `isActive` alone (reddens the "out" arm) |
| 2.4 | `aShortcutFiresItsButtonWithoutFocusOnAnExactModifierMatch` (B4e, B4f, B4g) | no API | M2d: modifiers compared as a subset |
| 2.5 | `defaultActionIsReturnAndCancelActionIsEscape` (B4a, B4b) | no API | M2e: swap the two |
| 2.6 | `theFirstButtonInTreeOrderTakesASharedShortcut` (B4h) | no API | M2f: last registered wins |
| 2.7 | `aFocusedKeyHandlerAndAKeymapBindingClaimTheKeystrokeFirst` (B4i; the keymap arm is `IX-F` 4's choice) | no API | M2g: shortcut stage before the raw bubble |
| 2.8 | `aDisabledButtonsShortcutIsSilentAndHitTestingOffIsNot` (B4l, K4; allows-hit-testing K1) | no API | M2h: shortcut registered outside the `isEnabled` gate |
| 2.9 | `anInvisibleButtonsShortcutStillFires` (B4j: `.opacity(0)`) | no API | M2i: skip shortcuts under an opacity-0 scope |
| 2.10 | `aDisabledControlPaintsInsideOneHalfOpacityScope` (`Button` ×4 styles, `Toggle`, `Slider`, `Stepper`, `Picker`; enabled arms paint no such scope) | no look | M2j: gate on `!isFocused` instead of `!isEnabled` |
| 2.11 | `aControlsAccentIsPaintedOnlyInTheKeyWindow` (`Toggle` on, `Slider` fill, `Picker` selection; `.key` accent, `.active` and `.inactive` `.separator`, driven through `FakePlatformWindow`'s active-state change) | inert | M2k: `!= .inactive` (reddens the `.active` arm) |
| 2.12 | `aFocusedControlDrawsItsRingAndAnUnfocusedOneDoesNot` (each of the five controls) | no ring | M2l: ring token `.separator` always |
| 2.13 | `aFocusedTextFieldClaimsReturnAheadOfTheDefaultButton` (X2: a focused `TextField` beside a `.defaultAction` `Button`, Return → the field's submit, the button silent; unfocused field → the button fires) | no API | M2m: shortcut stage before a focused field's editing keys |
| 2.14 | `aCircularContentShapeRefusesTheCornerAndTakesTheCentre` (C1, C11 rounded, C13 with padding; legacy `onClick`) — was 3.15 | no API | M3i: `contains` ignores the shape |
| 2.15 | `aContentShapeWrittenAfterAProposalTapShapesItsHit` (C2, C10) — was 3.16 | no API | M3i |
| 2.16 | `hoverActiveAndTheGestureArenaFollowTheContentShape` (the corner neither hovers, presses nor starts a lane-1 drag; a wheel over the corner reaches the scroller beneath) — was 3.17 | no API | M3j: the shape tested in `Window.dispatchClick` only (a second copy) |
| 2.17 | `aClipShapesCornersStayHittableAndItsRectBoundsTheHit` (C3, C4, C9 agree at a same-size clip's corners; a smaller clip cuts — divergence 43) — was 3.18 | green; **written first** | M3k: intersect with the clip's rounded geometry |
| 2.18 | `aDrawnElementWithoutAPointerTargetDoesNotBlockAClickBeneathIt` (divergence **57**, wrong on purpose, H18, C12) — was 3.19 | green; **written first** | M3l: register a hitbox for every painted element |
| G2.1 | `theButtonSpellingsCompileFromAPlainImport` (role, style, the three shortcut overloads, `KeyEquivalent` literal; negative arms: `.buttonStyle(.link)`, `Text("x").keyboardShortcut("k")`, `EventModifiers.function`) | new guard | mutate red once |
| G2.2 | `aProposalElementCannotSpellContentShapeBeforeItsTap` (a new `@Test` in `DecorationCompileGuards`, beside the existing `contentShape(inset:)` refusal; control arm: `.onTap { }.contentShape(Circle())` compiles) — was G3.2 | new guard | mutate red once |

**Must stay green, unedited**: `Button`'s BT0 chrome and `controlSize` metrics
tests, every control key test, `controlSizeReachesNoBuiltInMeasurement`, the
controls-demo tests. `PaintPass.isActive`'s "by reading, unpinned" note in
`allowsHitTesting`'s doc becomes pinned by 2.3.

### Lane 3 — focus

**Files.** `StateTable.swift` (`isWindowRetained` keeps `$ax` only; the
cleared-focus report), `Frame.swift` (`resolveFocus` and the frame-boundary
`@FocusState` reconciliation; the hidden condition on the one gate in
`registerHandlers`' 5-argument implementation), `Element.swift`,
`ModifiedElement.swift`, `AnyElement.swift` (the hidden scope's keyboard
counter, mirrored at each copy — `MC-B`), new `Sources/MetalUI/FocusState.swift`,
`StateReflection.swift` (seeding the box), `Box.swift` (`focused`;
`focusable()`'s doc, whose `hidden()` hazard is fixed). Tests: new
`FocusStateTests.swift`, `FocusIdentityTests.swift`,
`FocusStateCompileGuards.swift`; edits to `ConditionalIdentityTests.swift`
(C2.8, C2.12 re-derived, C2.13 retired), `FocusTests.swift`
(`focusOnAnElementThatStopsBeingProducedIsRetainedWithinTheWindow` re-derived
as 3.2) and `AccessibilityTreeTests.swift`
(`hiddenContentIsNotPublishedButAZeroHeightNodeIsAndADuplicatedIDIsPublishedOnce`'s
focus control re-derived, `IX-K` 3).

| id | test | red before because | mutation that must redden it |
|---|---|---|---|
| 3.1 | `focusDropsWhenItsElementIsRenamedAndDoesNotReturn` (F1; **replaces C2.13**'s rename arm, retirement row: its answer inverts by `IX-I`) — after the first away frame `focusedElement == nil`; back to `a`: still nil, `@State` fresh | focus retained | MRk′: `$focus` exempt again |
| 3.2 | `focusDropsWhenAnIfRemovesItsElement` (F2; **replaces C2.13**'s `if` arm) — **the re-derived and renamed** `FocusTests.focusOnAnElementThatStopsBeingProducedIsRetainedWithinTheWindow` (its `if` removal inverts; `IX-I`, `IX-O` 5), not a new test | retained | MRk′ |
| 3.3 | `aResetKeepsTheAccessibilitySlotButNotFocus` (**C2.8 re-derived**, renamed from `aResetKeepsTheFocusAndAccessibilityRetentionSlots`: `$ax` present, `$focus` and `$state0` gone, focus nil) | retained | MRk′; M2f of `ID-C` (no `$ax` exemption) still reddens the `$ax` half |
| 3.4 | `aFocusedTextFieldInsideAToggledIfLosesFocusAndStartsFresh` (**C2.12 re-derived**: focus nil, `setTextInputArea(nil)`, fresh `TextEditState`) | retained | MRk′ |
| 3.5 | `aForEachThatDropsItsFocusedElementDropsFocus` (`DD-C`'s loop reset) | retained | MRk′ |
| 3.6 | the **existing** `aFocusedListRowSurvivesABoundedExcursionButNotALongerOne` (`FocusTests`, `TB-J`/`TB-AH`), unedited, green throughout | green | MRl: reset unevaluated rows too (`noteWindowedParent` dropped) |
| 3.7 | `aFocusStateWriteFromInputMovesFocusOnTheNextFrame` (Bool and `equals:`) | no API | M3a: reconcile before `resolveFocus` validates (focuses a non-focusable) |
| 3.8 | `aFocusStateReadsTheWindowsFocusAfterEveryMover` (Tab, `Window.focus`, a `TextField` press, `IX-I`'s drop — F1's `focused=false`) | no API | M3b: read only its own writes |
| 3.9 | `writingFalseOrNilClearsFocusOnlyIfItsElementHoldsIt` | no API | M3c: clear unconditionally |
| 3.10 | `focusedDoesNotMakeAnElementFocusable` (a `.focused` box without `.focusable()` never takes focus) | no API | M3d: `.focused` sets `isFocusable` |
| 3.11 | `aFocusStateWriteNamingADisabledElementFocusesNothing` (K1) | no API | M3e: bypass `resolveFocus` |
| 3.12 | `aFocusStateNeverWritesFromAPhase` (steady frames: no `StateTable` write, `needsRedraw` stays false; only a focus change writes, once) | no API | M3f: write the value every frame |
| 3.13 | `aHiddenFocusableElementCannotTakeFocusOrKeys` (F9; and a focused element that becomes hidden loses focus at the next boundary; the `AccessibilityTreeTests` control above re-derived in the same commit) | registers | M3g: the hidden condition dropped from the gate; M3g′: dropped from `ModifiedElement`'s copy only |
| 3.14 | `clickingAFocusableElementDoesNotFocusIt` (divergence **94**, wrong on purpose, F3) | green; **written first and kept green** | M3h: a press focuses the target's focusable ancestor |
| 3.14b | `aHiddenButtonsShortcutStillFires` (X1: `.hidden()` over a `Button` with ⌘K; control: the same button `.disabled(true)` is silent) | green at lane 3's start (lane 2's table ignores `hidden()`); **written first and kept green** | M3n: the shortcut table behind the hidden condition |
| 3.20 | `aFocusStateSurvivesInsideAComponentAndAnAnyElement` (`ID-E`'s binding sites) | no API | M3m: skip seeding under `AnyElementBox` |
| G3.1 | `theFocusStateSpellingsCompileFromAPlainImport` (`@FocusState var f: Bool`, `enum Field? `, `.focused($f)`, `.focused($g, equals: .a)`) | new guard | mutate red once |

**Retirement rows** (the Record phase's "goldensUnchanged" field): C2.13
`focusOutlivesARenameAndAnIfUntilItsElementReturns` retired, replaced by 3.1
and 3.2; `focusOnAnElementThatStopsBeingProducedIsRetainedWithinTheWindow`
renamed 3.2 and its focus clause inverted (T row); C2.8 renamed and its focus
clause inverted (3.3); C2.12 renamed and its focus clause inverted (3.4);
`hiddenContentIsNotPublishedButAZeroHeightNodeIsAndADuplicatedIDIsPublishedOnce`
keeps its name, its focus control re-derived (T row, `IX-K` 3). **No other
test changes its answer**; a test `MRk′`'s inverse or 3.13's gate reddens
that is not in this list is a finding the lane records and stops on.

## 7. The demo

**No demo tree changes, and no demo pixel may move**: the demo builds no
gesture, `Button`, control, `.focused` binding or `contentShape`; its one
`.focusable()` panel is never inside a conditional that goes false in the
fourteen captured states, and `hidden()` is not used on it. So **0 px against
`31f2e7a` in all fourteen offscreen images** (`docs/probes/demo-pixels/compare.sh`)
at every lane; `DemoFrameDeterminismTests`' `Expected.swift` unedited.
`METALUI_CONTROLS_DEMO=1` (not captured) may gain a `.plain` button, a
destructive one and a ⌘K shortcut in lane 2 — a look for the human list, not a
pixel exit.

## 8. For the Record phase

- **Critic round** (`IX-O`): probe group `X` (X1–X4) added and recorded;
  the audit gains row 18b; the lanes were re-cut (content shapes to lane 2).
- **Divergences**: 94 **added** (`IX-K` 2); 80 **amended** (now measured,
  F5/F6), 43 **amended** (`clipShape`), 41 **amended** (shapes), 57 **pinned**
  (owner none), 81 **re-owned** (none), 21 and 22 **re-owned** (none, kept);
  live 68 → **69**, next label **95**. `ID-R` item 9's unnumbered difference is
  **closed** (fixed), not numbered.
- **Declared but inert**: `controlActiveState` row **deleted** (read by the
  controls, `IX-H`); `PaintPass.isActive` row **deleted** (`IX-E` 3);
  `ButtonRole` row **added** (`IX-E` 1); the `hidden()`-on-focusable hazard
  (`focusable()`'s doc, record §05) **deleted** (`IX-K` 3).
- **Human looks added**: gestures on a trackpad (tap slop, double-tap timing,
  long press) against Finder/SwiftUI; the pressed, disabled and inactive looks
  and the focus ring beside a native SwiftUI window (all unmeasured here); the
  real-window capture, still owed.
- **CLAUDE.md**: "Hit testing" (the arena, `contentShape(_:)`), "Focus"
  (`@FocusState`, focus leaves with its identity, hidden is out of the
  keyboard), "Environment" (`controlActiveState` has consumers), "Identity"
  (`$focus` no longer exempt from `ID-C`/`ID-R`/`DD-C` resets — a migration
  note), "StyledElement" (`Handlers` members 10 → 14: `gestures`,
  `keyboardShortcut`, `contentShape`, and lane 3's `focusBinding` — the first
  design read 13, corrected by `IX-T`), the guard list (three new guard files).
- **Plan**: task 12 stays unticked; a dated progress note naming part 2's
  items (§2 rows 27–37) and the human VoiceOver run.

## 9. Counts (expected, re-measured by each lane)

Baseline 1773 tests / 108 guards. Lane 1: **+23** tests (1.1–1.23), +2
guards. Lane 2: **+18** tests (2.1–2.13 and 2.14–2.18, the last five moved from
lane 3), +2 guards (G2.1; G2.2, a new `@Test` in `DecorationCompileGuards`).
Lane 3: 16 rows listed (3.1–3.14, 3.14b, 3.20); 3.2, 3.3 and 3.4 are renames
and 3.6 is an existing test, so **12 are new**, and C2.13 retires: **net +11**,
+1 guard (G3.1). Expected close: **1773 + 23 + 18 + 11 = 1825 tests, 108 + 5 =
113 guards** (re-cut by `IX-O`; the first design read 1824) — each lane re-takes
the count and corrects this line in its landing ruling if its own arithmetic
differs. **Measured close (`IX-T`): 1837 tests, 113 guards** —
lanes 1 and 2 added more than predicted (lane 1 +30 with its fix round,
`IX-P`/`IX-Q`; lane 2 +22 with its fix round, `IX-R`), lane 3 +12 (net 11 and
G3.1): 1773 + 30 + 22 + 12 = 1837.
