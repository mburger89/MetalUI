# Input APIs for viewports and canvases — design

User request 2026-10-02, an item of the gpui-gap priority list (**not a plan
task**), motivated by MetalCreator (`/Users/maxburger/Developer/MetalCreator`,
`docs/metalui-gaps.md` "Reported 2026-10-07 (C7)" and "C7 status and
provisional API names"; never edited from here). Rulings: prefix **`CI-`** in
[`../2026-10-08-input-apis-decisions.md`](../2026-10-08-input-apis-decisions.md)
(`CI-A`…`CI-W`; `CI-P`…`CI-W` are the critic's corrections, and win where they differ). Evidence: [`../../probes/swiftui-input-apis.swift`](../../probes/swiftui-input-apis.swift).
Record: `docs/record/81-input-apis.md` (the Record phase writes it).

Branch `feat/input-apis` from `70ed000`, worktree
`/Users/maxburger/Developer/worktrees/MetalUI/input-apis`. Agents run one at a
time; lanes in order **1 → 2 → 3** (`CI-O`).

## §0 Baseline (measured at `70ed000` by the design session)

`swift build --build-system native --build-tests`, then `swift test
--build-system native --no-parallel`, unfiltered: **2672 tests in 3 suites
passed**, `FR-J no-argument frame: succeeded=true` present, 0 `error:`, the
only `warning:` SwiftPM's `--build-system native` deprecation notice. Guards
175, census 2536, divergences 105 live / next label **139** (record §80 §4,
not re-taken here). Human checks A–X; this branch adds **Y**.

## §1 API

### §1.1 The seam (`MetalUIPlatform`; lane 1; `CI-E`, `CI-I`, `CI-J`)

```swift
public enum InputPhase: Sendable, Hashable { case none, mayBegin, began, changed, ended, cancelled }

public struct MouseEvent: Sendable {          // existing; gains:
    public var buttonNumber: Int               // AppKit numbering: 0 primary, 1 secondary, 2 middle, 3 back, 4 forward
    public init(position:, modifiers: = [], clickCount: = 1, buttonNumber: Int = 0)
}

public struct ScrollEvent: Sendable {          // existing; gains:
    public var phase: InputPhase               // .none where the platform has none (SDL)
    public var momentumPhase: InputPhase
    public var isPrecise: Bool                 // false: delta is lines × 10 (a wheel mouse; SDL always)
    public var location: Point<Pixels>         // local to the receiving element; == position at the seam
    public var isMomentum: Bool { get set }    // now computed: momentumPhase != .none; set true → .changed, false → .none (CI-V)
    public init(position:delta:modifiers: = [], isMomentum: Bool = false, timestamp: = 0)   // unchanged spelling
    public init(position:delta:modifiers: = [], phase: InputPhase, momentumPhase: InputPhase,
                isPrecise: Bool, timestamp: Double)
}

public struct MagnifyEvent: Sendable { position; magnification: Double /* this event's additive delta */;
                                       phase: InputPhase; modifiers: Modifiers; timestamp: Double; init(…) }
public struct RotateEvent: Sendable  { position; rotation: Double /* this event's delta, degrees, clockwise-positive */;
                                       phase; modifiers; timestamp; init(…) }

public enum InputEvent {                       // new cases (migration: CI-E item 5)
    case rightMouseDragged(MouseEvent)
    case otherMouseDown(MouseEvent), otherMouseDragged(MouseEvent), otherMouseUp(MouseEvent)
    case magnify(MagnifyEvent)
    case rotate(RotateEvent)
}

public enum PlatformPointerStyle: Sendable, Hashable {
    case arrow, iBeam, verticalIBeam, crosshair, openHand, closedHand, pointingHand,
         columnResize, rowResize, zoomIn, zoomOut
    case frameResize(edge: PlatformResizeEdge, inward: Bool, outward: Bool)
}
public enum PlatformResizeEdge: Sendable, Hashable { case top, leading, bottom, trailing,
                                                         topLeading, topTrailing, bottomLeading, bottomTrailing }

public protocol PlatformWindow {               // one new requirement, NO default (CI-J item 2)
    func setPointerStyle(_ style: PlatformPointerStyle)
}
```

`Modifiers`/`EventModifiers` are unchanged. Every new public declaration has a
doc comment and an inventory row (§8.2).

### §1.2 Gestures (`MetalUI`; lane 2; `CI-B`, `CI-C`, `CI-F`, `CI-G`)

```swift
public enum CoordinateSpace: Sendable, Hashable { case local, global }        // global = window content space (divergence 139)

public struct MouseButton: Sendable, Hashable {
    public let buttonNumber: Int
    public static let primary: MouseButton      // 0
    public static let secondary: MouseButton    // 1
    public static let middle: MouseButton       // 2
    public static func other(_ buttonNumber: Int) -> MouseButton
}

public struct SpatialTapGesture: Gesture {
    public struct Value: Equatable, Sendable { public var location: Point<Pixels> }
    public var count: Int
    public var coordinateSpace: CoordinateSpace
    public init(count: Int = 1, coordinateSpace: CoordinateSpace = .local)
    public func onEnded(_ action: @escaping @MainActor (Value) -> Void) -> SpatialTapGesture
}

public struct MagnifyGesture: Gesture {
    public struct Value: Equatable, Sendable {
        public var magnification: Double         // 1 + Σ deltas (probe M1)
        public var startLocation: Point<Pixels>  // local, at the first event
        public var startAnchor: UnitPoint        // startLocation / hit-region size
    }
    public var minimumScaleDelta: Double
    public init(minimumScaleDelta: Double = 0.01)
    public func onChanged(_ action: @escaping @MainActor (Value) -> Void) -> MagnifyGesture
    public func onEnded(_ action: @escaping @MainActor (Value) -> Void) -> MagnifyGesture
}

public struct RotateGesture: Gesture {
    public struct Value: Equatable, Sendable {
        public var rotation: Angle               // cumulative, clockwise-positive (probe Q1)
        public var startLocation: Point<Pixels>
        public var startAnchor: UnitPoint
    }
    public var minimumAngleDelta: Angle
    public init(minimumAngleDelta: Angle = .degrees(1))
    public func onChanged(_:) -> RotateGesture
    public func onEnded(_:) -> RotateGesture
}

extension DragGesture {
    // Value gains:
    //   public var modifiers: EventModifiers            (divergence 140)
    //   public init(startLocation:location:modifiers:)  (the old init keeps its spelling, modifiers [])
    public var coordinateSpace: CoordinateSpace
    public var button: MouseButton
    public init(minimumDistance: Pixels = Pixels(10), coordinateSpace: CoordinateSpace = .local,
                button: MouseButton = .primary)     // replaces init(minimumDistance:); source-compatible
}

extension StyledElement {   // and ProposalElementGroup → GestureModifier<Self>
    public func onTapGesture(count: Int = 1, coordinateSpace: CoordinateSpace = .local,
                             perform action: @escaping @MainActor (Point<Pixels>) -> Void) -> Self
}
```

`Gesture.swift`'s "Not offered" doc loses `SpatialTapGesture`,
`MagnifyGesture`, `RotateGesture`, "a tap with a location" and
`coordinateSpace:`; it gains `CoordinateSpace.named`, `time`/`velocity`/
`predictedEnd*` on values, and `GestureInputKinds`.

**Internal interface lane 2 hands lane 3** (names binding; lane 3 calls only
these):

```swift
// GestureLeaf.Kind gains:
//   .tap(count:) carries `spatial: CoordinateSpace?` (nil for TapGesture)
//   .drag(minimumDistance:, coordinateSpace:, button: MouseButton)
//   .magnify(minimumScaleDelta: Double), .rotate(minimumAngleDelta: Double /* degrees */)
// GestureLeaf gains: spatialTapEnded, magnifyChanged/Ended, rotateChanged/Ended.

enum ArenaMode: Equatable { case press, button(Int), pinch }
GestureArena.init?(target:ancestors:draggableAbove:mode: ArenaMode = .press)
    // .press: today's arena; magnify/rotate leaves and non-primary drags failed at formation.
    // .button(n): only .drag leaves with button n live; onClick not added; nil with no live leaf.
    // .pinch: only .magnify/.rotate leaves live; onClick not added; nil with no live leaf.
mutating func press(at:clickCount:continuing:modifiers:) -> [GestureCallback]   // modifiers added
mutating func move(to:modifiers:) -> [GestureCallback]
mutating func release(at:clickCount:modifiers:click:) -> [GestureCallback]
mutating func magnify(_ event: MagnifyEvent) -> [GestureCallback]               // pinch mode
mutating func rotate(_ event: RotateEvent) -> [GestureCallback]                 // pinch mode
var activatedAnyDrag: Bool { get }   // button mode: some drag leaf reached its minimum (CI-F item 4)
var isAlive: Bool                    // pinch: some begun kind not yet ended
// GestureArena keeps no Window reference; `global` values need the window point, which the
// arena already has (event positions are window points).
```

The old `press(at:clickCount:continuing:)`/`move(to:)`/`release(at:clickCount:click:)`
spellings stay as forwarding overloads passing `[]`, so the existing arena
tests compile unchanged.

### §1.3 Wheel and pointer style (`MetalUI`; lane 3; `CI-H`, `CI-I`)

```swift
public struct PointerStyle: Sendable, Hashable {
    public static let `default`, horizontalText, verticalText, rectSelection, grabIdle, grabActive,
                      link, zoomIn, zoomOut, columnResize, rowResize: PointerStyle
    public static func frameResize(position: FrameResizePosition,
                                   directions: FrameResizeDirection.Set = .all) -> PointerStyle
}
public enum FrameResizePosition: Sendable, Hashable { case top, leading, bottom, trailing,
                                                        topLeading, topTrailing, bottomLeading, bottomTrailing }
public enum FrameResizeDirection: Sendable, Hashable {
    case inward, outward
    public struct Set: OptionSet, Sendable, Hashable { inward, outward, all }
}

extension StyledElement {
    public func pointerStyle(_ style: PointerStyle?) -> Self                       // Handlers member; nil attaches nothing
    public func onScrollWheel(perform action: @escaping @MainActor (ScrollEvent) -> Bool) -> Self
}
extension ProposalElementGroup {
    public func pointerStyle(_ style: PointerStyle?) -> PointerStyleModifier<Self>   // HoverModifier's recipe
    public func onScrollWheel(perform: …) -> ScrollWheelModifier<Self>
}
public struct PointerStyleModifier<Content: ProposalElementGroup>: Element, ProposalElement
public struct ScrollWheelModifier<Content: ProposalElementGroup>: Element, ProposalElement
```

`Handlers` gains **one** member, `pointer: PointerAttachment?` — a class box
holding the wheel handler and the style (`CI-Q`: `Handlers` already has
**seventeen** members, and `MemoryLayout<Handlers>.size` is pinned at 472 by
`handlersGainsOneReferenceMember` and `theNewDeclarationsCostHandlersAtMostOnePointer`;
seventeen → **eighteen**, 472 → **480**, both pins edited by lane 3).
`HandlerShape` (`ModifierTests`) and `HandlerFingerprint`
(`OuterModifierMatrixTests`) each gain one field, and every hook added to
`Element`'s group defaults is mirrored per layer (`MC-B`) — none is needed:
the member rides `Handlers` through the existing registration.

**Located context menu** (`CI-R`; lane 2):

```swift
extension StyledElement {      // and ProposalElementGroup → ContextualModifier<Self>
    public func contextMenu<M: MenuContent>(
        @MenuContentBuilder menuItems: @escaping @MainActor (Point<Pixels>?) -> M) -> Self
    // the secondary press's point, local to the contextual region; nil for a keyboard
    // (MN-G) or accessibility open. Selected by closure arity beside the existing overload.
}
```

### §1.4 Dispatch (lane 3; `CI-D`, `CI-F`, `CI-H`, `CI-I`)

The `Window.onInput` order, new stages in **bold**:

1. pointer state (`updatePointerState`: other/right-drag events move
   `lastMousePosition` only); dialogs/alerts/toolbar results; hover
   **and the pointer style** recompute on every pointer event, the new four
   button cases, `.magnify`, `.rotate` included;
2. the drawn alert (modal: the new cases are taken); the tooltip (hides on
   `.otherMouseDown`, `.magnify`, `.rotate`); external drop; drag session;
3. the in-window menu (**takes `.otherMouseDown` — an outside one dismisses —
   `.otherMouseDragged`, `.otherMouseUp`, `.rightMouseDragged`, `.magnify`,
   `.rotate`**); popovers (**an `.otherMouseDown` outside dismisses and passes
   on, `MN-Y`**); the context-menu stage (**defers on a secondary press whose
   button arena has a live leaf, `CI-F` item 4; opens on that press's release
   if `activatedAnyDrag` is false**);
4. **the wheel chain** (`CI-I` item 4) in place of `applyScroll`'s target
   lookup;
5. **the pinch arena** (`.magnify`/`.rotate`, `CI-D`), **the button arena**
   (`.rightMouseDown/Dragged/Up` for a live secondary arena,
   `.otherMouseDown/Dragged/Up`, `CI-F`) — each claims the event when it ran a
   callback or holds a live arena;
6. text input, value track, the primary arena, keys, … unchanged.

The pointer style: `Window.resolvedPointerStyle` (last sent), recomputed in
`updatePointerStyle(at:)` called from the end of `updateHover(at:reportsMoves:)`
(both its call sites: every pointer event and after every adopted frame), with
`pointerStyleVisits` counting the per-hitbox visits (`SV-U`'s shape: a frame
with no style region and the default style already sent does no work).

## §2 Files (re-cut by `CI-W`)

| Lane | Files (only these; new files **bold**) |
| --- | --- |
| 1 | `Sources/MetalUIPlatform/InputEvent.swift`, `Sources/MetalUIPlatform/Platform.swift`, **`Sources/MetalUIPlatform/PointerStyle.swift`** (`PlatformPointerStyle`, `PlatformResizeEdge`), `Sources/MetalUIAppKit/AppKitPlatform.swift`, **`Sources/MetalUIAppKit/AppKitCursor.swift`** (incl. the pure `frameResize(for:)` value table, `CI-P`), `Backends/SDL/Sources/SDLBridge/SDLBridge.c`, `Backends/SDL/Sources/SDLBridge/include/SDLBridge.h`, `Backends/SDL/Sources/MetalUISDL/SDLPlatform.swift`, **`Backends/SDL/Sources/MetalUISDL/SDLInputMapping.swift`** (`SDLPinch`, the cursor table, button numbering), `Tests/MetalUITests/Fakes.swift`, every `Tests/MetalUITests/*CompileGuards.swift` conformer template (the new member), `Tests/MetalUITests/AppKitMenuTests.swift` (`CI-T`: test 2.4's control-drag), **`Tests/MetalUITests/InputAPISeamCompileGuards.swift`**, **`Tests/MetalUITests/AppKitInputAPITests.swift`**, `Tests/MetalUIPlatformTests/PlatformTests.swift` (scroll phase arms), **`Backends/SDL/Tests/MetalUISDLTests/SDLInputAPITests.swift`**, `docs/migration.md` (seam notes) |
| 2 | `Sources/MetalUI/Gesture.swift`, `Sources/MetalUI/GestureModifiers.swift`, **`Sources/MetalUI/SpatialGestures.swift`** (`CoordinateSpace`, `MouseButton`, `SpatialTapGesture`, `MagnifyGesture`, `RotateGesture`), `Sources/MetalUI/ContextMenu.swift` (`CI-R`), `Sources/MetalUI/MenuSession.swift`, `Sources/MetalUI/Popover.swift`, `Sources/MetalUI/Tooltip.swift`, `Sources/MetalUI/Window.swift` (**the press, pinch, button-arena and context-menu stages only**), **`Tests/MetalUITests/InputAPIGestureArenaTests.swift`**, **`Tests/MetalUITests/InputAPIGestureCompileGuards.swift`**, **`Tests/MetalUITests/InputAPIGestureWindowTests.swift`** (3.1, 3.26–3.34, 2.21–2.24), `docs/migration.md` (gesture notes) |
| 3 | `Sources/MetalUI/Window.swift` (**the wheel stage and the hover/style recompute**, on lane 2's commit), `Sources/MetalUI/Frame.swift`, `Sources/MetalUI/Handlers.swift`, `Sources/MetalUI/Hover.swift`, **`Sources/MetalUI/PointerStyle.swift`**, **`Sources/MetalUI/ScrollWheel.swift`**, **`Sources/MetalUIDemoContent/CanvasDemo.swift`**, `Sources/MetalUIDemo/main.swift`, `Backends/SDL/Sources/MetalUISDLDemo/main.swift` (the env switch), `Tests/MetalUITests/ModifierTests.swift` (`HandlerShape`), `Tests/MetalUITests/OuterModifierMatrixTests.swift` (`HandlerFingerprint`), `Tests/MetalUITests/ContextMenuTests.swift` + `Tests/MetalUITests/AccessibilityModifierTests.swift` (the two `Handlers` size pins, `CI-Q`), `Tests/MetalUICrossPlatformTests/DemoStackBudgetTests.swift` (one arm), **`Tests/MetalUITests/InputAPIWindowTests.swift`**, **`Tests/MetalUITests/CanvasDemoTests.swift`**, `docs/divergences.md` (139–141 and the Not-offered rows, `CI-U` item 2), `docs/probes/closeout-inventory-map.tsv` + `closeout-public-api.tsv` (census re-recorded, every lane's declarations), `docs/api-overview.md`, `docs/migration.md` (API notes), `docs/verification/human-checks.md` (group Y), `docs/record/81-input-apis.md` (the Record phase) |

Every lane appends rulings and spec amendments (the decisions doc and this
spec are shared, appended in order; only one agent runs at a time). A file
named in two lanes (`Window.swift`, `docs/migration.md`) is edited by the later
lane on top of the earlier lane's commit (`CI-W`).

## §3 Lanes (`CI-W`, amending `CI-O`; order 1 → 2 → 3)

- **Lane 1 — seam and platforms.** §1.1; AppKit overrides (`otherMouse*`,
  `rightMouseDragged`, the control-drag and its existing test, `CI-T`;
  `magnify`/`rotate` with the rotation negated once, scroll phases),
  `AppKitCursor` (the probe's table as values for frame resize, `CI-P`; the
  `.cursorUpdate` tracking option, `cursorUpdate(with:)`); SDL bridge kinds
  appended, `SDLPinch`, the cursor cache and table, `pointerStyles` record;
  `FakePlatformWindow.setPointerStyle` recording `pointerStyles`, its
  `simulateInput` setting `ScrollEvent.location = position`. `swift package
  clean` after the stored properties land. **`Window` needs no change to build**
  (its switches have `default:`); lane 1 confirms the suite count is the
  baseline plus its own tests. Runs the Linux image (§5).
- **Lane 2 — gestures end to end.** §1.2 and the located context menu; the
  arena tested pure (2.1–2.20), then its `Window` integration: tap location on
  both vocabularies, the pinch arena, the button arena, the context menu's
  deferral and location, the menu/popover/tooltip handling of the new events
  (3.1, 3.26–3.34, 2.21–2.25). Three guards (2.1, 2.2, 2.25).
- **Lane 3 — wheel, pointer style, demo, registries.** §1.3 (without the
  menu), §1.4's wheel and style stages, `CI-Q`, `CI-S`, the demo, the registry
  rows, human checks group Y, the census. Runs the demo-pixel compare and the
  Linux image (the `Backends/SDL` demo main changes).

## §4 Tests — by name, red before, and the mutation that must redden each

"Red before" is the state at the lane's start (a test of a declaration that
does not exist yet is red by not compiling, recorded as such). Each mutation is
applied once, on the lane's branch, **to the spelling named**, with the full
unfiltered suite; the lane records every test it reddened. A mutation that
reddens nothing is a finding.

### §4.1 Lane 1 — seam and platforms

| # | Test | Red before | Mutation that must redden it |
| --- | --- | --- | --- |
| 1.1 | `anExhaustiveInputEventSwitchWithoutTheInputAPICasesDoesNotCompile` (guard, `typecheckFile`, plain `import MetalUIPlatform`): a switch naming every case but the six fails; with them it compiles | "with" arm fails (no cases) | delete `case otherMouseDragged` from `InputEvent` → the "with" arm fails |
| 1.2 | `aPlatformWindowWithoutSetPointerStyleDoesNotCompile` (guard; `CR-M`'s shape; positive control = the migration note's spelling) | positive arm fails | a protocol-extension default `func setPointerStyle(_:) {}` → the negative compiles |
| 1.3 | `theOldScrollEventInitialiserKeepsItsMeaning`: `ScrollEvent(position:delta:isMomentum: true)` → `momentumPhase == .changed`, `isMomentum`, `phase == .none`, `isPrecise`, `location == position` | no fields | the old init leaves `momentumPhase` `.none` → red; (`CI-V` item 1) a setter arm: `e.isMomentum = true` → `.changed`, `= false` → `.none`; mutation: the setter ignores `false` → red |
| 1.4 | `appKitScrollWheelCarriesPhaseMomentumAndPrecision`: real scroll `CGEvent`s (`.scrollWheelEventScrollPhase`, `.scrollWheelEventMomentumPhase` set; a line event and a pixel event) through `MetalHostView.scrollWheel(with:)` → `phase`, `momentumPhase`, `isPrecise` | no fields | map `momentumPhase` from `phase` → red |
| 1.5 | `appKitMagnifyAndRotateReachOnInputWithDeltasAndPhases`: the probe's CG gesture recipe (type 29, field 110 = 8/5, 113/114, 132) → `.magnify(0.1, .changed)` and `.rotate(−10, .changed)` for AppKit +10; began/ended phases | no cases | drop the negation in `rotate(with:)` → red |
| 1.6 | `appKitOtherButtonsAndRightDragReachOnInput`: CG-made `otherMouseDown/Dragged/Up` (button 2) and `NSEvent` `rightMouseDragged` → the four cases, `buttonNumber` 2/1 | no cases | remove the `otherMouseDragged(with:)` override → red |
| 1.7 | `aControlDragOnAppKitIsASecondaryDrag` (migration of `MN-AC` item 1) | control-drag dropped | restore the `if controlClickInFlight { return }` → red |
| 1.8 | `appKitPointerStylesMapAsTheProbeMeasured`: every non-frame `PlatformPointerStyle` → the `NSCursor` the probe read (`P1`–`P10`, `P15`, `P16`); the eight frame-resize edges × three direction sets compared **as values** from `AppKitCursor.frameResize(for:)` (`P9`, `P17`–`P19`; `NSCursor ==` cannot separate opposite edges, `CI-P`) | no table | swap `openHand`/`closedHand` → red; swap `top`/`bottom` in the frame table → red |
| 1.9 | `appKitSetPointerStyleSetsTheCursorAndCursorUpdateKeepsIt`: `setPointerStyle(.crosshair)`, then the host view's `cursorUpdate(with:)` → `NSCursor.current == .crosshair` | no requirement | `cursorUpdate(with:)` sets `arrow` → red |
| 1.10 | `theHostViewsTrackingAreaRequestsCursorUpdates` | option absent | drop `.cursorUpdate` from the options → red |
| 1.11 | `sdlMiddleAndExtraButtonsBecomeOtherMouseEventsWithAppKitNumbers`: raw `SDL_BUTTON_MIDDLE/X1/X2` down/up pushed → `buttonNumber` 2/3/4; left/right unchanged | dropped | map X1 → 4 → red |
| 1.12 | `sdlMotionWithRightOrMiddleHeldIsARightOrOtherDrag`: masks R → `.rightMouseDragged`, M → `.otherMouseDragged(2)`, L+R → `.mouseDragged` | dropped/move | test RMASK before LMASK → red |
| 1.13 | `sdlPinchBecomesMagnifyAtTheLastPointerPosition`: motion (30,40), pushed pinch BEGIN/UPDATE 1.1/UPDATE 1.25/END under the offscreen driver (cumulative) → `.magnify` deltas 0.1, 0.15, phases, position (30,40) | dropped | ratio rule on a cumulative driver (`scale − 1`) → second delta 0.25 → red |
| 1.14 | `sdlPinchDeltaIsARatioOnCocoaAndCumulativeElsewhere` (pure `SDLPinch.delta`) | absent | swap the two branches → red |
| 1.15 | `aPinchWithNoWindowGoesToTheMouseFocusThenTheKeyboardFocus` (pure `SDLPinch.route`) | absent | prefer keyboard focus → red |
| 1.16 | `sdlWheelHasNoPhaseMomentumOrPrecision` (`.none`, `.none`, `false`, `location == position`) | fields absent | `isPrecise: true` → red |
| 1.17 | `sdlPointerStylesMapToSystemCursorsAndAreRecorded` (table incl. grab → `MOVE`, zoom → `DEFAULT`; `SDLWindow.pointerStyles`) | absent | grabIdle → `DEFAULT` → red |
| 1.18 | `theNewBridgeKindsAreAppendedAfterMouseLeave`: the existing kinds' C values unchanged (literal pins), the four new kinds and `MUI_EVENT_PINCH` greater than `MUI_EVENT_MOUSE_LEAVE` | absent | insert `MUI_EVENT_PINCH` before `MUI_EVENT_DIALOG` → red |
| 1.19 | `theFakeWindowRecordsPointerStylesAndStampsScrollLocation` | absent | the fake ignores `location` → red |

SDL tests convert every C enum `rawValue` explicitly and each helper creating
an `SDLPlatform` arms `armMainRunLoopExitCheck()`; none needs a presented frame.

### §4.2 Lane 2 — gestures and the arena (pure)

| # | Test | Red before | Mutation |
| --- | --- | --- | --- |
| 2.1 | `anOutsideModuleCanSpellTheInputAPIGestures` (guard, plain `import MetalUI`): `SpatialTapGesture(count: 2, coordinateSpace: .local).onEnded { _ = $0.location }`, `MagnifyGesture(minimumScaleDelta: 0.02).onChanged { _ = ($0.magnification, $0.startAnchor) }`, `RotateGesture().onEnded { _ = $0.rotation.degrees }`, `DragGesture(minimumDistance: 0, coordinateSpace: .global, button: .middle).onChanged { _ = $0.modifiers.contains(.option) }`, `MouseButton.other(4)`, the old `DragGesture(minimumDistance:)`; negative arm: `MagnifyGesture().onChanged { _ = $0.velocity }` fails (deferred) | positive fails | make `MouseButton.other` internal → positive fails |
| 2.2 | `onTapGestureResolvesByClosureArity` (guard): on a `Box` and a proposal `Text`, `.onTapGesture { }` and `.onTapGesture { p in _ = p.x }` and `.onTapGesture(count: 2, coordinateSpace: .global) { _ in }` compile; negative `{ a, b in }` fails | positive fails | remove the location overload → positive fails |
| 2.3 | `aSpatialTapReportsItsReleasePointInLocalSpace`: region origin (40,30), press (50,60), release (52,61) → (12,31) | absent | report the press point → (10,30) |
| 2.4 | `aSpatialTapInGlobalSpaceReportsTheWindowPoint` → (52,61) | absent | ignore `coordinateSpace` → red |
| 2.5 | `aSpatialDoubleTapReportsTheSecondRelease` | absent | record the first release → red |
| 2.6 | `aSpatialTapThroughARotationReportsWhereOnItselfItWasTapped` (a hitbox with a 90° effect) | absent | skip `localPoint` → red |
| 2.7 | `aDragValueCarriesTheModifiersOfItsEvent`: press `[]`, move `[.option]`, release `[.shift]` → change `.option`, end `.shift` | absent | always the press's modifiers → red |
| 2.8 | `aGlobalDragReportsWindowPoints` | absent | ignore `coordinateSpace` → red |
| 2.9 | `aPressArenaFailsPinchLeavesAndNonPrimaryDrags`: `MagnifyGesture().exclusively(before: DragGesture(minimumDistance: 0))` drags on a press; a `DragGesture(button: .secondary)` on the same target reports nothing | magnify blocks / absent | do not fail pinch leaves at formation → the drag never reports |
| 2.10 | `aButtonArenaHasOnlyItsButtonsDragLeaves`: `.button(1)`: the secondary drag live, `DragGesture()`, a tap and the target's `onClick` dead; `.button(2)` with no middle leaf → `nil` | absent | add the click member in button mode → red |
| 2.11 | `aSecondaryDragActivatesAtItsMinimumDistance`: 9 pt nothing, 10 pt `onChanged`, release `onEnded`; `activatedAnyDrag` false then true | absent | `>` for `>=` → red |
| 2.12 | `magnificationIsCumulativeAndAdditiveFromOne`: began, +0.1, +0.1, ended → 1.1, 1.2, end 1.2 (probe `M1`) | absent | multiply → 1.21 |
| 2.13 | `aMagnifyActivatesOnlyAtItsMinimumScaleDelta` (minimum 0.05: +0.03 nothing, +0.03 → 1.06) | absent | activate on the first event → red |
| 2.14 | `aMagnifyThatNeverActivatedEndsWithNoCallback` | absent | always run `onEnded` → red |
| 2.15 | `rotationIsCumulativeFromTheSeamsClockwiseDeltas` (10, 10 → 10°, 20°) | absent | subtract → red |
| 2.16 | `startLocationAndAnchorAreTheFirstEventsLocalPoint` (region 100×100 at (40,30), began at (60,50) → (20,20), (0.2,0.2); later positions do not move it) | absent | recompute per event → red |
| 2.17 | `aMagnifyAndARotateOnNestedElementsDoNotBlockEachOther` | absent | let any live leaf ahead block → the outer rotate never reports |
| 2.18 | `theInnermostMagnifyWinsUnlessAnOuterOneIsHighPriority` | absent | outermost-first for normal members → red |
| 2.19 | `aSimultaneousMagnifyAndRotateCompositionReportsBoth` | absent | treat `.simultaneous` as exclusive in pinch mode → red |
| 2.20 | `aPinchArenaRunsNoTapDragOrClick` | absent | keep the click member in pinch mode → red |
| 2.21 | `aLocatedContextMenuReceivesThePressPointInLocalSpace` (region at (40,30), secondary press (50,60) → (10,30); both vocabularies) | absent | pass the window point → red |
| 2.22 | `aDeferredLocatedMenuReceivesThePressPointNotTheRelease` (a secondary `DragGesture` declared; press (50,60), release (53,61) under its minimum → menu at release with (10,30)) | absent | pass the release point → red |
| 2.23 | `aKeyboardOrAccessibilityOpenPassesNoLocation` (Shift-F10, `MN-G`; show-menu, C11 → `nil`) | absent | pass the region's origin → red |
| 2.24 | `aLocatedMenuThroughARotationReportsWhereOnItselfItWasPressed` | absent | skip `localPoint` → red |
| 2.25 | `contextMenuResolvesByClosureArity` (guard, plain `import MetalUI`): `.contextMenu { Button("a") {} }` and `.contextMenu { p in Button("a") { _ = p?.x } }` compile on a `Box` and a proposal `Text`; negative `{ a, b in … }` fails | positive fails | remove the located overload → positive fails |
| — | Every existing arena test (`GestureArena…`, `IX-C`/`IX-D`/`DN-D` pins) stays green **unedited** — the forwarding overloads keep their spellings | — | — |

### §4.3 Lane 3 — integration, wheel, pointer style, demo

| # | Test | Red before | Mutation |
| --- | --- | --- | --- |
| 3.1 | `onTapGestureWithALocationRunsOnBothVocabulariesInLocalSpace` | absent | the proposal overload passes `.global` → red |
| 3.2 | `onScrollWheelReceivesTheEventInLocalSpaceUnderStateDispatch` (a `@State` write lands; `delta`, `phase`, `momentumPhase`, `modifiers` passed through; `location` local) | absent | pass `position` as `location` → red |
| 3.3 | `aWheelHandlerThatClaimsStopsAnEnclosingScrollView` | absent | consult each id's scroll region before its descendants' handlers (outermost first) → red |
| 3.4 | `aWheelHandlerThatDeclinesPassesToTheEnclosingScrollView` | absent | treat `false` as claimed → red |
| 3.5 | `aWheelHandlerOutsideAScrollViewSeesNothingTheScrollerClaimed` (+ arm: a **proposal** `.onScrollWheel` on a `ScrollView` sees nothing, `CI-V` item 2) | absent | call every handler on the chain → red; consult a wrapper's handler before its child's scroll region → the proposal arm red |
| 3.6 | `aLegacyWheelHandlerOnAScrollViewRunsBeforeItsScrollingAndCanVetoIt` | absent | scroll region before the same-id handler → red |
| 3.7 | `aWheelOverAClickTargetInsideACanvasReachesTheCanvasHandler` | absent | stop at the opaque cover → red |
| 3.8 | `anOverlaidSiblingClickTargetStopsTheCanvasWheel` | absent | drop the ancestry test (any containing region) → red |
| 3.9 | `aWheelRegionIsWithdrawnByDisabledAllowsHitTestingAndHidden` (three arms) | absent | register outside the `allowsHitTesting` gate → that arm red |
| 3.10 | `aPopoverAboveACanvasTakesItsWheelPinchStyleAndButtonDrags` (four arms) | absent | drop the layer clause in the wheel chain → wheel arm red |
| 3.11 | `aGPUSurfaceViewportReceivesWheelPinchButtonDragsAndStyle` (`GPUSurface` wrapped in each modifier) | absent | — (coverage pin; reddens with 3.2/3.30/3.25 mutations) |
| 3.12 | `aWheelThroughAScaleEffectReportsALocalLocationAndARawDelta` | absent | transform the delta → red |
| 3.13 | `anUnclaimedWheelOverOnlyANonOpaqueHandlerReachesTheWindowsOnInput` | absent | claim whenever a handler ran → red |
| 3.14 | `aFrameWithNoWheelOrStyleRegionRegistersNoExtraHitbox` (a fixed tree's hitbox count equals `70ed000`'s literal) | absent | register both regions unconditionally → red |
| 3.15 | `pointerStyleReachesThePlatformOnlyOnAChange` (`FakePlatformWindow.pointerStyles`) | absent | drop the dedupe → red |
| 3.16 | `theInnermostPointerStyleWinsAndNilDefers` (probe `P11`, `P11c`, `P12`; both vocabularies) | absent | first (outermost) candidate → red |
| 3.17 | `anOpaqueTargetAboveCoversAPointerStyleBeneath` (`P13`, `P13c`) | absent | eligibility without `opaque` → red |
| 3.18 | `aPaintOnlyOverlayDoesNotCoverAPointerStyle` (divergence 141's pin) | absent | — (pins the divergence; a fix reddens it) |
| 3.19 | `pointerStyleIsWithdrawnByDisabledAllowsHitTestingAndHidden` | absent | register outside the disabled gate → red |
| 3.20 | `aPressHoldsThePressedTargetsStyleWhileThePointerLeaves` (a `@State` switch to `.grabActive` at the drag's start; the pointer leaves; release recomputes `.default`) | absent | resolve under the pointer during a press → red |
| 3.21 | `contentMovingUnderAStillPointerChangesTheStyleAfterTheFrame` | absent | recompute only on pointer events → red |
| 3.22 | `anInWindowMenuOrDrawnAlertResetsTheStyleToDefault` | absent | ignore `hoverIsSuppressed` → red |
| 3.23 | `aPointerReEntryResendsTheStyleEvenWhenItIsDefault` (`CI-S`: crosshair region, exit, re-enter over a default region → the fake records `.arrow` again) | absent | on exit set the last-sent style to `.default` → red |
| 3.24 | `aPointerStyleThroughARotationFollowsTheDrawing` | absent | test containment with the untransformed rect → red |
| 3.25 | `aFrameWithNoStyleRegionDoesNoPointerStyleWork` (`pointerStyleVisits == 0` across ten moves) | absent | remove the early return → red |
| 3.26 | `aMiddleDragReachesOnlyAMiddleButtonDragGesture` (also a primary `DragGesture`, a tap, an `onClick` on the chain; `active` and focus unchanged) | absent | form the press arena for `.otherMouseDown` → red |
| 3.27 | `aSecondaryDragOpensNoContextMenu` (press: no menu; past 10 pt: `onChanged`; release: `onEnded`, no menu) | absent | open on the press regardless → red |
| 3.28 | `aSecondaryClickWithASecondaryDragDeclaredOpensTheMenuOnRelease` (at the press point) | absent | never open the deferred menu → red |
| 3.29 | `withoutASecondaryDragTheMenuStillOpensOnThePress` | — (green before: `MN-E`) | always defer → red |
| 3.30 | `secondaryAndOtherPressesStillNeverPressTapOrDragPrimaryGestures` | — (green before for the right button) | let a button arena include primary drags → red |
| 3.31 | `anOtherPressDismissesAPopoverAndAnOpenInWindowMenuTakesItAndPinches` | absent | `dispatchMenuSession` `default: false` for the new cases → red |
| 3.32 | `aMiddleDragDuringAPendingPrimaryTapSequenceDisturbsNeither` | absent | one shared arena → red |
| 3.33 | `aMagnifyEventReachesTheMagnifyGestureUnderThePointer` (both vocabularies, `@State` write) | absent | form the pinch arena at the last mouse position instead of the event's → red |
| 3.34 | `aPinchIsWithdrawnByDisabledAndAllowsHitTesting` | absent | — (rides the pointer hitbox; reddens with a gate mutation in `Frame.registerHandlers`, recorded) |
| 3.35 | `theCanvasDemoPansZoomsAboutThePointerPicksAndShowsACrosshair` (`CanvasDemoTests`, headless: a middle drag moves the pan by its translation; ⌘-wheel and a pinch keep the canvas point under the pointer fixed — literal derived before the run; a spatial tap selects the node under it; the fake records `.crosshair`) | absent | zoom about the canvas origin → red |
| 3.36 | `everyProductionTreeBuildsOnAOneMegabyteThread` gains the canvas demo's arm | arm absent | inline the demo's body into the composer (stack depth) — recorded, may be green (a green mutant is the measurement) |
| — | Unchanged and green: the `DD-Y` pins (`aClickTargetInsideAScrollViewPassesTheWheelToItsScroller`, `aClickTargetOverlaidOnAScrollViewButNotInsideItStillSwallowsTheWheel`, `aDeferredScrimDeclaredInsideAScrollViewStillSwallowsTheWheel`, `aSingleLineTextFieldInsideAScrollViewPassesTheWheelToItsScroller`, `scrollingPastTheEndDoesNotBankAnOffsetTheUserMustUnwind`, `theTopmostOverlappingRegionWinsAndTheOtherDoesNotMove`), every `MN-B`/`MN-E`/`SV-N` pin, `theSevenRetentionSlotsAreMutuallyDistinct`, `theLegacyEngineSymbolsAreAbsentFromTheTestProcess` | — | — |

| 3.37 | `handlersGainsOneReferenceMember` (== 480) and `theNewDeclarationsCostHandlersAtMostOnePointer` (<= 440 + 8 × 5), edited (`CI-Q`) | red at 472 after the box lands | store the wheel closure inline in `Handlers` → red |

**Lane assignment (`CI-W`)**: 3.1 and 3.26–3.34 run in **lane 2** (ids
kept); every other 3.x in lane 3.

Guards added: **5** (1.1, 1.2, 2.1, 2.2, 2.25), each mutated red once by the
lane that adds it.

## §5 CI and commands

Every lane: `swift build --build-system native --build-tests` and `swift test
--build-system native --no-parallel` unfiltered (one summary line; the `FR-J`
line), `swift build --build-tests` with 0 warnings, `swift package clean` after
lane 1's stored properties, `zsh docs/probes/closeout-inventory-check.sh` and
`zsh docs/probes/closeout-undocumented.sh` print nothing (lane 3 re-records the
census with `docs/probes/closeout-public-api.sh`; lanes 1 and 2 add their rows).
Lanes 1 and 3: `python3 Backends/SDL/scripts/fetch-accesskit.py` once, then in
`Backends/SDL` `PKG_CONFIG_PATH=$PWD/.accesskit swift build --build-tests` and
`swift test`; the Linux image: `docker build -t metalui-portable -f
Backends/SDL/linux/Dockerfile Backends/SDL` then `docker run --rm -v
"$PWD":/work -v metalui-sdl-build:/tmp/build -w /work/Backends/SDL
metalui-portable bash -c 'swift build --build-tests --scratch-path /tmp/build
&& swift test --skip-build --scratch-path /tmp/build'` (OrbStack; `orb start`
if needed), plus the `swift:6.4-noble` portable-target build. Lane 3:
`docs/probes/demo-pixels/compare.sh <scratch> 70ed000 HEAD` — **0 px in all
fourteen images**; `Expected.swift` unedited.

## §6 Demo expectation (lane 3)

`METALUI_CANVAS_DEMO=1 swift run MetalUIDemo` (and the SDL demo with the same
variable): one function `canvasDemo()` in `CanvasDemo.swift`, passed to the
composer (Windows 1 MB stack). A 640×420 node-graph canvas: a dot grid and six
rounded-rect "nodes" placed in canvas coordinates under a `pan`/`zoom` state.
**Middle-drag or right-drag pans** (`.grabActive` while dragging; `.grabIdle`
over a pan strip along the canvas's top — `CI-V` item 3), **two-finger scroll pans** with momentum, **⌘-scroll and pinch
zoom about the pointer** (the canvas point under the pointer stays put;
`startLocation` for a pinch), **a click picks** the node under the
`SpatialTapGesture` location (a selection outline), a **right-click on a node
opens a located context menu** naming the node under the press point (`CI-R`;
on release — a right-drag pans instead), the pointer is
**`.rectSelection` (crosshair)** over empty canvas and `.link` over a node; one
node carries a `RotateGesture` (it turns with a two-finger twist, inside the
canvas's `MagnifyGesture` — human check Y4's corner); a **style strip** below
the canvas has one swatch per `PointerStyle` (human checks Y5/Y6); a status line
shows pan, zoom, rotation, the last scroll phase/momentum phase/`isPrecise` and
the modifiers of the current drag. No existing demo tree changes.

## §7 Human checks — group Y (lane 3 writes it; an agent cannot run it)

- **Y1** Trackpad two-finger scroll on the demo canvas pans and keeps gliding
  (momentum); release mid-glide and the status line's momentum phase reads
  `changed` then `ended`.
- **Y2** Pinch on the canvas zooms about the pinch centre on AppKit; the node
  under the fingers stays under them.
- **Y3** Rotate (two-finger twist) reports clockwise-positive degrees in the
  status line.
- **Y4** Nested magnify/rotate (`CI-D` item 3's unmeasured corner): note what a
  pinch with twist does over the demo's rotate-able inner node.
- **Y5** Every pointer style over the demo's style strip on AppKit: default,
  crosshair, open/closed hand, pointing hand, column/row/frame resize, I-beams,
  zoom in/out — each as named; the grab hand stays closed while a fast pan
  leaves the canvas.
- **Y6** The same strip under SDL on Linux and Windows: hands show `MOVE`, zoom
  shows the arrow (`CI-H` item 8), the rest as named.
- **Y7** SDL pinch on Wayland or X11 with a trackpad: zoom speed matches the
  macOS SDL build (`CI-K` item 1's cumulative reading).
- **Y8** A real mouse: middle-drag pans; right-drag pans and opens no menu; a
  right-click on a node opens its menu on release.
- **Y9** ⌥ pressed mid-drag shows in the status line at the next move.
- **Y10** Windows precision touchpad: a pinch arrives as control+wheel and the
  demo zooms (no `MagnifyGesture`).
- **Y11** A notched wheel mouse: `isPrecise` false, steps of 10 points.

## §8 Migration notes and registry rows

### §8.1 Migration (`docs/migration.md`; lane 1 the seam, lane 3 the API)

1. An exhaustive `switch` over `InputEvent` adds `.rightMouseDragged`,
   `.otherMouseDown`, `.otherMouseDragged`, `.otherMouseUp`, `.magnify`,
   `.rotate` or a `default:` (`CI-E` item 5).
2. A `PlatformWindow` conformer adds `func setPointerStyle(_ style:
   PlatformPointerStyle) {}` (`CI-J` item 2).
3. On AppKit a control-drag is now a secondary drag (`.rightMouseDragged`), not
   dropped (`CI-E` item 3).
4. `DragGesture.Value`'s equality compares `modifiers` (`CI-G`).
5. ~~`ScrollEvent.isMomentum` is computed; code that assigned it sets
   `momentumPhase`~~ — struck by `CI-V` item 1: it keeps a setter.
6. `MemoryLayout<Handlers>.size` 472 → 480 (`CI-Q`; internal).

### §8.2 Registry rows

Divergences (lane 3 writes them; labels **139–141**): 139 `.global` is the
content space (`CI-B` item 4, pin 2.4); 140 `DragGesture.Value.modifiers`
(`CI-G`, pin 2.7); 141 a paint-only view does not cover a pointer style
(`CI-H` item 5, pin 3.18). Inventory: a family **`input-apis-seam`** (M:
`InputPhase`, `MagnifyEvent`, `RotateEvent`, `PlatformPointerStyle`,
`PlatformResizeEdge`, the six `InputEvent` cases, `MouseEvent.buttonNumber`,
`ScrollEvent`'s four fields and new init, `PlatformWindow.setPointerStyle`);
**`input-apis-gestures`** (A: `SpatialTapGesture`, `MagnifyGesture`,
`RotateGesture`, `onTapGesture(count:coordinateSpace:perform:)`; A/D 139:
`CoordinateSpace`; M: `MouseButton`, `DragGesture.button`/`coordinateSpace`
and its new init; D 140: `DragGesture.Value.modifiers`);
**`input-apis-pointer-and-wheel`** (A: `PointerStyle`, `FrameResizePosition`,
`FrameResizeDirection`, `pointerStyle(_:)` (D 141); M: `onScrollWheel`,
`ScrollWheelModifier`, `PointerStyleModifier`, the located
`contextMenu(menuItems:)` overload on both vocabularies, `CI-R`). **Not offered**
rows in `docs/divergences.md` for `CI-U` item 2's list.

### §8.3 Owed to the Record phase

CLAUDE.md/AGENTS.md (the `CI-` prefix and next id, a rule paragraph, Handlers
"sixteen" (stale since `SV-AH`) → **eighteen**, the new `PlatformWindow` requirement in the defaultless
list, counts), README, `docs/record/README.md`, record §03/§04 rows, record 81.

## §9 Deferred (each with reason and owner; `CI-A`)

Gesture values' `time`/`velocity`/`predictedEnd*` (no `Date`, no estimator;
owner none) · `PointerStyle.image`/`.shape`/`columnResize(directions:)`/
`rowResize(directions:)` (needs image cursors on both backends; owner none) ·
`onModifierKeysChanged` (owner none) · `CoordinateSpace.named` (owner none) ·
I-beam over text fields and a hand over links by default (text input must not
move; owner none) · `RotateGesture` on SDL, magnify on Windows, wheel
phase/momentum/precision on SDL (SDL has none; owner none) · `inputKinds:`
(owner none) · scroll chaining (owner none).

## §10 Must not move (checked by every lane)

`theSevenRetentionSlotsAreMutuallyDistinct`; `MC-A`/`MC-C`/`MC-P` numbering;
`.id()` outermost; hit testing's one ranking (no second lookup — every new
query is `topmostHitbox`/`topmostOpaqueHitbox`); accessibility; animation;
focus; `List` windowing and `TB-AH`; `Deferred`; text input; the fourteen demo
images at 0 px against `70ed000`; `Expected.swift` unedited; 0 `warning:` on
both build systems; `MetalUILayout` imports only `MetalUICore`;
`MetalUIScene` imports only `MetalUIShaderTypes`; `Backends/SDL` and a
`swift:6.4-noble` container build; `theLegacyEngineSymbolsAreAbsentFromTheTestProcess`
green; no shader change.
