# Drag and drop — design

Branch `feat/drag-and-drop` from `053a3b3` (master, plan task 15 merged, PR
#35). User request 2026-10-01 — **not a plan task**. Rulings **`DN-A`…`DN-R`**
in a new decisions doc,
[`../2026-10-01-drag-and-drop-decisions.md`](../2026-10-01-drag-and-drop-decisions.md)
(next unused **`DN-S`**). Evidence:
[`../../probes/swiftui-drag-and-drop.swift`](../../probes/swiftui-drag-and-drop.swift)
(**new**; groups `T` Transferable, `R` fake `NSDraggingInfo`, `A`
accessibility, `P` real pointer drags at the HID tap; header carries the
recorded output). Record: `docs/record/68-drag-and-drop.md` (the Record phase
writes it).

**Status: DESIGNED.** Baseline at `053a3b3`, re-taken by this design session
after a clean build: **1976 tests in 3 suites** (`Test run with 1976 tests in
3 suites passed after 107.503 seconds`, the FR-J line present), 0 `error:`,
the one native deprecation `warning:`; 121 typecheck guards, 0 goldens, 66
live divergences (next label 100).

---

## 1. What MetalUI has today, and what SwiftUI does (inventory and probe)

**Today.** No drag and drop anywhere: no `.draggable`/`.dropDestination`/
`.onDrag`/`.onDrop`, no `NSDraggingSource`/`NSDraggingDestination` on
`MetalHostView`, no `SDL_EVENT_DROP_*` in `SDLBridge.c`. `DragGesture`
(`IX-B`…`IX-D`) moves a pointer inside the window and transfers nothing.
The pieces this design builds on:

| piece | where | used for |
|---|---|---|
| `Window.onInput`'s dispatch chain (`updatePointerState` → scroll → text input → value track → gestures → keys) | `Sources/MetalUI/Window.swift` ~625–735 | the session branch goes first for an open session; drops are a new event kind |
| the gesture arena, one per press, from the one ranking | `Gesture.swift` (`GestureArena`, `isBlocked`, `act`), `Window.dispatchGestures`/`makeGestureArena` | the draggable is an arena member (`DN-D`) |
| `topmostOpaqueHitbox(in:at:)` — the single `(layer, index)` ranking | `Hitbox.swift` | generalized to `topmostHitbox(in:at:where:)` (`DN-F`) |
| `Frame.registerHandlers` — the one disabled gate, the `allowsHitTesting` gate, `insertHitbox(_:id:opaque:…)` | `Frame.swift` ~1125–1280 | the non-opaque draggable and destination regions (`DN-E`, `DN-F`) |
| `Frame.transitionScopes` / `TransitionPaintScope` / `insertThroughTransitions` / `insertIntoScene` / `TransitionEffect` | `Frame.swift` ~2284–2320, `Transition.swift`, `TransitionStore.swift` | capturing the source's primitives and replaying them as the preview (`DN-J`) |
| `PaintPass.paintDecoration` — every `StyledElement` site's paint helper | `AnimatedColor.swift` ~427 | where a `StyledElement` source's capture is pushed |
| `Deferred` presentation roots (`LR-CH`…) | `Deferred.swift`, `Frame.computeRootLayout` | a custom `preview:` closure's layout (`DN-J` item 3) |
| `PlatformWindow`, `InputEvent` | `Sources/MetalUIPlatform/Platform.swift`, `InputEvent.swift` | the seam (`DN-C`) |
| `MetalHostView` / `AppKitWindow` | `Sources/MetalUIAppKit/AppKitPlatform.swift` | AppKit in and out (`DN-K`, `DN-L`) |
| `SDLWindow.handle(_:)`, `MUIEvent`, `mui_poll` translation | `Backends/SDL/Sources/MetalUISDL/SDLPlatform.swift`, `Sources/SDLBridge/SDLBridge.c` ~705 | SDL in (`DN-M`) |
| `FakePlatformWindow` (+ two compile-guard `Conformer` fixtures) | `Tests/MetalUITests/Fakes.swift`, `ControlStateCompileGuards.swift`, `TransactionCompileGuards.swift` | every window test; the new requirement |
| the accessibility bridges | `AccessibilityTreeBuilder.swift`, `AppKitAccessibility.swift`, `AccessKitTree.swift` | unchanged; parity pinned (`DN-N`) |

**SwiftUI's surface on this SDK** (`SwiftUI.swiftinterface`, macOS 27 SDK,
lines 2701–2729, 32470–32523): `draggable(_:)`, `draggable(_:preview:)`,
`dropDestination(for:action:isTargeted:)` (**soft-deprecated**, `100000.0`,
toward `dropDestination(for:isEnabled:action:)` with a `DropSession`),
`onDropSessionUpdated`, `dropConfiguration`, `onDrag`, `onDrop` (four
overloads + `DropDelegate`), `draggable(containerItemID:)`, `dragContainer`,
`onDragSessionUpdated`, `dragConfiguration`, `dragPreviewsFormation`. All
compile today without a warning (`api.swift` scratch typecheck, the design
session). `DN-A` picks the subset.

**What the probe measured** (each line one arm; the header has the raw output):

- **Transferable** (`T1`–`T7e`): String ⇄ `public.utf8-plain-text` only, UTF-8;
  URL imports `public.url`/`public.file-url`, a web URL exports `[url]`, a file
  URL `[url, file-url]`; neither String nor URL imports the other's type;
  `Data` exports and imports `public.data`.
- **Drop sequencing** (`R…`, fake info — callback order and types only): the
  destination view registers `public.data|public.item` (`R0b`–`R0e`), nothing
  without a destination (`R0a`, `R0f`); `isTargeted(true)` on enter,
  `false` on exit and **before** the action (`R1`, `R1b`); a wrong type answers
  no operation and never targets (`R3`–`R3c`); two items arrive as two
  (`R3f`); a `Data` destination takes a String (`R3g`); an action returning
  `false` still answers `true` (`R4`); `hidden()` refuses (`R5d`); two chained
  destinations deliver to the outer (`R6e`).
- **Real pointer** (`P…`): control `P0` drops, `P0b` (no draggable) does not;
  precedence `P1`–`P3`, `P21`, `P22` (`DN-D`); `List` rows `P4`; `ScrollView`
  `P5`; session start at 1 pt `P17`, not at 0 `P17z`; phases and leaving the
  window `P6`; Escape `P7`; disabled `P8`/`P9`; re-entry `P10`; self-drop
  `P11`; local location `P12a`; nested and sibling destinations `P13`, `P14`;
  covers and `allowsHitTesting(false)` `P15`; type mismatch `P16`; preview
  pixels `P18`; hold `P19`; field and slider `P20`.
- **Accessibility** (`A0`–`A4`): nothing published differs (`DN-N`).

**Unmeasured, ruled as MetalUI's choice** (and listed again in §8 as looks):
the preview's exact opacity, shadow and anchor; a presentation blocking a drop
beneath it; a draggable that is not itself hit-testable; SwiftUI's behaviour
with a trackpad's jitter; drops in a `.sheet` (a separate window in SwiftUI).

---

## 2. Public API

### 2.1 `MetalUI` — `Sources/MetalUI/Transferable.swift` (new)

```swift
/// A uniform type identifier and the identifiers it conforms to (DN-B item 2).
public struct ContentType: Hashable, Sendable {
    public let identifier: String
    public let conformance: Set<String>          // transitive; never contains `identifier`
    public init(_ identifier: String, conformingTo parents: [ContentType] = [.data])
    public func conforms(to other: ContentType) -> Bool   // == or contained
    public static let item, data, text, plainText, utf8PlainText, url, fileURL: ContentType
}

public protocol Transferable {
    var exportedContentTypes: [ContentType] { get }
    static var importedContentTypes: [ContentType] { get }
    func exported(as contentType: ContentType) -> Data?
    init?(importing data: Data, contentType: ContentType)
}
extension String: Transferable {}   // [utf8PlainText] both ways, UTF-8
extension URL: Transferable {}      // imports [url, fileURL]; a web URL exports [url], a file URL [url, fileURL]; absoluteString UTF-8
extension Data: Transferable {}     // [data] both ways; imports any offered type (everything conforms to data)
```

`.data` conforms to `.item`; `.item` conforms to nothing; `.text` ⊂ data,
`.plainText` ⊂ text, `.utf8PlainText` ⊂ plainText, `.url` ⊂ data, `.fileURL`
⊂ url. `ContentType.init` defaults its parents to `[.data]`, so a custom type
conforms to `data` and `item` unless declared otherwise.

### 2.2 `MetalUI` — `Sources/MetalUI/DragAndDrop.swift` (new)

```swift
extension StyledElement {
    public func draggable<T: Transferable>(_ payload: @autoclosure @escaping () -> T) -> Self
    public func draggable<T: Transferable, P: Element>(_ payload: @autoclosure @escaping () -> T,
        @ElementBuilder preview: () -> P) -> DraggablePreviewModifier<Self, P>
    public func dropDestination<T: Transferable>(for payloadType: T.Type = T.self,
        action: @escaping @MainActor (_ items: [T], _ location: Point<Pixels>) -> Bool,
        isTargeted: @escaping @MainActor (Bool) -> Void = { _ in }) -> Self
}
extension ProposalElementGroup {
    public func draggable<T: Transferable>(_ payload: @autoclosure @escaping () -> T) -> DraggableModifier<Self>
    public func draggable<T: Transferable, P: ProposalElementGroup>(_ payload: @autoclosure @escaping () -> T,
        @ElementBuilder preview: () -> P) -> DraggablePreviewModifier<Self, P>
    public func dropDestination<T: Transferable>(for payloadType: T.Type = T.self,
        action: @escaping @MainActor (_ items: [T], _ location: Point<Pixels>) -> Bool,
        isTargeted: @escaping @MainActor (Bool) -> Void = { _ in }) -> DropDestinationModifier<Self>
}
public struct DraggableModifier<Content: ProposalElementGroup>: Element, ProposalElement
public struct DropDestinationModifier<Content: ProposalElementGroup>: Element, ProposalElement
public struct DraggablePreviewModifier<Content, Preview>: Element   // + ProposalElement where Content: ProposalElementGroup
```

The payload autoclosure runs **once, when the drag begins** (SwiftUI's
`@autoclosure` has the same timing); its `exportedContentTypes` are each
exported then, into the session's representations. The preview builder's
exact generic constraints (legacy `Element` vs `ProposalElementGroup`
content) are lane 1's to settle against the typechecker; the spellings above
are the contract the guard G1.1 pins.

### 2.3 `MetalUIPlatform` — the seam (`InputEvent.swift`, `Platform.swift`)

```swift
public struct PasteboardType: Sendable, Hashable { public var identifier: String; public var conformsTo: [String] }
public struct DragRepresentation: Sendable, Equatable { public var type: PasteboardType; public var bytes: [UInt8] }
public struct DropItem: Sendable {
    public var types: [PasteboardType]                                   // offered, most preferred first
    public var load: @MainActor @Sendable (_ identifier: String) -> [UInt8]?
}
public enum DropEvent: Sendable {
    case entered(position: Point<Pixels>, items: [DropItem]?)   // nil: unknown until the drop (SDL)
    case moved(position: Point<Pixels>)
    case exited
    case performed(position: Point<Pixels>, items: [DropItem])
}
public enum InputEvent { …; case drop(DropEvent) }

public protocol PlatformWindow {
    …
    /// Hands an in-window drag to the operating system when the pointer leaves
    /// the window (DN-K). `false` when the platform cannot. No default (DN-C).
    func beginExternalDrag(_ representations: [DragRepresentation], at position: Point<Pixels>) -> Bool
}
```

Positions are window points, top-left origin, as `MouseEvent.position`.

---

## 3. How it works

### 3.1 Registration (`Frame.registerHandlers`, `Handlers`)

- `Handlers.gestures` gains a draggable attachment (`GestureAttachment` with
  a new leaf kind `.draggable(DragSource)`; `DragSource` is a class box holding
  the payload closure, and the preview kind). `isPointerTarget` counts every
  gesture **except** a draggable (`DN-E` item 1).
- `Handlers.dropDestination: DropDestinationTarget?` (internal, one reference):
  the imported types, the importer-and-action closure, `isTargeted`.
- In `registerHandlers`, after the existing opaque insertion:
  - `enabled && hitTestingDisabledDepth == 0 && !isPointerTarget && hasDraggable`
    → `insertHitbox(region, id, opaque: false, handlers: handlers, …)` (a
    pointer target already rides its opaque hitbox, draggable included);
  - `enabled && handlers.dropDestination != nil` → one **more** non-opaque
    hitbox at the element's own bounds (no content shape) carrying a
    `Handlers` with only `dropDestination` set — outside the
    `allowsHitTesting` gate (`DN-F` item 3), inside the disabled gate (`DN-G`).
    `hidden()` registers nothing, as today.
- `topmostHitbox(in:at:where:)` in `Hitbox.swift`; `topmostOpaqueHitbox` is
  `topmostHitbox(in:at:where: \.opaque)`, so the ordering exists once.

### 3.2 The arena (`Gesture.swift`, `Window.makeGestureArena`)

- `GestureLeaf.Kind.draggable` — `press` records the press point; `move`
  marks it ready on the first move with distance `> 0` (`DN-D` item 1);
  `release` fails it.
- `isBlocked(leaf, ahead:)`: for a draggable leaf, an ahead member whose
  undecided leaves are all taps, long presses or clicks does not block
  (`DN-D` item 2). Everything else is the existing rule (`DN-D` items 3, 5).
- `act` on a ready draggable: `status = .ended`, appends
  `.beginDrag(owner:source:at:)` (new `GestureCallback` case), and marks every
  other leaf failed without an end. Simultaneous members already resolved on
  this event keep their callbacks, which precede it (`DN-D` item 4).
- `makeGestureArena` joins the topmost non-opaque draggable region above the
  target (or alone, with no opaque target) per `DN-E` item 2.

### 3.3 The session (`Sources/MetalUI/DragSession.swift`, new; `Window.swift`)

`Window.dragSession: DragSession?` — source id, representations, press point,
pointer, target id, preview kind, last snapshot. `Window.onInput` checks an
open session **first**, after `updatePointerState`:

| event | session open |
|---|---|
| `mouseDragged(p)` | outside the content bounds and not yet offered: `beginExternalDrag`; `true` → end silently (target `false`, clear `active`, arena, preview); else update the pointer, re-resolve the target (§3.4), `setNeedsRedraw`; claimed |
| `mouseUp(p)` | resolve at `p`; an accepting target → `isTargeted(false)`, import, action; otherwise target `false`; end; claimed (never a click) |
| `keyDown` Escape | cancel (target `false`); claimed, ahead of the keymap |
| anything else | unchanged dispatch |

`.beginDrag` (from `runGestureCallbacks`): export the payload, open the
session, clear `active`, drop the arena, resolve the target at the current
pointer, `setNeedsRedraw`.

`InputEvent.drop` (any time, no in-window session needed): `.entered`/`.moved`
resolve and return "accepts"; `.exited` un-targets; `.performed` resolves at
the position, un-targets, imports through `DropItem.load` (only the types the
destination imports), runs the action, returns whether it ran. One resolver
and one importer serve both paths; an in-window session's items are
`DropItem`s whose `load` returns the representation's bytes.

### 3.4 Target resolution and import

`dropTarget(at:)`: `i = topmostHitbox(lastHitboxes, p, where: dropDestination != nil)`;
none → nil; if `topmostOpaqueHitbox(lastHitboxes, p)` has `layer > lastHitboxes[i].layer`
→ nil (`DN-F` item 4); accepts = items unknown (`nil`) **or** some item
offers a type satisfying one of the destination's imported types; the target
is `i`'s id **only if it accepts** (`DN-F` item 2). Location =
`p − lastHitboxes[i].origin` (`DN-H` item 2). Import: for each item in
order, the first offered type satisfying an imported type, `load` it,
`T(importing:contentType:)`; failures skipped; empty → no action.

### 3.5 The preview (`Frame.swift`, `DragSession.swift`)

`Frame.dragSourceID` (set by `Window` from the open session, nil otherwise).
`paintDecoration` and `DraggableModifier.paint` push an identity
`TransitionPaintScope` around their body when their id is it, and hand its
captures to the session. After `paintGhosts`, `Frame` replays the snapshot —
`TransitionEffect` with a translate of `(pointer − press)` and alpha 0.7,
every primitive's mask replaced by the translated snapshot bounds, inserted on
`highest layer used + 1`. A `DraggablePreviewModifier` instead lays out its
`preview` as a `Deferred` presentation (`.position(.absolute).inset(left:top:)`
at the pointer less the press offset, `allowsHitTesting(false)`, opacity 0.7)
only while its id is the session's source; its content numbers from 0, the
preview at cursor 1.

### 3.6 AppKit (`Sources/MetalUIAppKit/AppKitDragAndDrop.swift`, new; `AppKitPlatform.swift`)

- `MetalHostView.registerForDraggedTypes([.item, .data, .URL, .fileURL, utf8PlainText])`
  in its initializer; `draggingEntered`/`draggingUpdated`/`draggingExited`/
  `performDragOperation` (+ `prepareForDragOperation` → `true`) per `DN-L`;
  `wantsPeriodicDraggingUpdates` → `false`.
- Pure conversions, unit-testable: `dropItems(from: NSPasteboard) -> [DropItem]`
  (types with `UTType(identifier)?.supertypes`, lazy `load`) and
  `draggingItem(for: [DragRepresentation], at:) -> NSDraggingItem` (an
  `NSPasteboardItem` with each type's data; image per `DN-K` item 2).
- `mouseDragged` keeps `lastDragEvent`; `AppKitWindow.beginExternalDrag`
  returns `false` with no drag event seen, else starts
  `beginDraggingSession(with:event:source:)`, source answering `.copy` in
  both contexts.

### 3.7 SDL (`SDLBridge.c` + header, `SDLPlatform.swift`)

`MUI_EVENT_DROP_BEGIN/POSITION/FILE/TEXT/COMPLETE` appended to the `MUI_EVENT`
enum (after `MUI_EVENT_FOCUS_LOST`, so no existing raw value moves);
`SDLWindow.handle` runs `DN-M`'s session; `fileURLString(fromPath:)` is a pure
static function (percent-encoding RFC 3986 unreserved + `/`, a `C:\…` path
becoming `file:///C:/…`). `beginExternalDrag` returns `false`.

---

## 4. Divergences and absences this creates (`docs/divergences.md`)

| # | what differs | SwiftUI | MetalUI | ruling | pin |
|---|---|---|---|---|---|
| 100 | a disabled drag source or drop destination | still drags (P9) and still takes the drop (P8) | the one disabled gate removes both | `DN-G` | `aDisabledSourceDoesNotDragAndADisabledDestinationRefuses` |
| 101 | a drag leaving the window | a system session from the start; its translucent preview leaves with it (P6c, P18) | AppKit hands off at the edge with the payload's own image (file icon, text badge); on SDL a drag cannot leave the window | `DN-K` | `leavingTheWindowHandsTheDragToThePlatformWhenItCan`, `anSDLWindowCannotBeginAnExternalDrag` |
| 102 | hovering an external drop on SDL | targets only a destination whose type matches (P16) | SDL gives no types until the drop, so the deepest destination is targeted whatever its type, and a browser URL arrives as text | `DN-M` | `anExternalDropWithUnknownTypesTargetsOptimistically`, `sdlDropEventsBecomeOneDropSession` |

"Not offered" gains one row: `.onDrag`/`.onDrop`/`DropDelegate`, the
`DropSession` family (`dropDestination(for:isEnabled:action:)`,
`onDropSessionUpdated`, `dropConfiguration`, `onDragSessionUpdated`,
`dragConfiguration`, `dragContainer`, `draggable(containerItemID:)`,
`dragPreviewsFormation`) — `DN-A` item 2. Live count 66 → **69**, next label
**103**.

---

## 5. Lanes (three, run in order, files disjoint)

| lane | owns | adds outside its own files |
|---|---|---|
| **1 — seam + MetalUI** | `Sources/MetalUIPlatform/InputEvent.swift`, `Platform.swift`; `Sources/MetalUI/Transferable.swift` (new), `DragAndDrop.swift` (new), `DragSession.swift` (new), `Handlers.swift`, `Gesture.swift`, `Hitbox.swift`, `Frame.swift`, `Window.swift`, `AnimatedColor.swift` (the `paintDecoration` capture push only); `Tests/MetalUITests/Fakes.swift`, `ControlStateCompileGuards.swift`, `TransactionCompileGuards.swift` (fixture members), `DragAndDropTests.swift` (new), `DragAndDropCompileGuards.swift` (new); `Tests/MetalUICrossPlatformTests/TransferableTests.swift` (new) | **exactly one member each**, so both packages build: `AppKitWindow.beginExternalDrag` returning `false` with a `// lane 2 replaces` comment (`AppKitPlatform.swift`), and `SDLWindow.beginExternalDrag` returning `false` — SDL's final answer (`SDLPlatform.swift`). Lanes 2 and 3 own those files afterwards. |
| **2 — AppKit** | `Sources/MetalUIAppKit/AppKitPlatform.swift`, `AppKitDragAndDrop.swift` (new); `Tests/MetalUITests/AppKitDragAndDropTests.swift` (new) | none |
| **3 — SDL, accessibility, demo, docs** | `Backends/SDL/Sources/SDLBridge/SDLBridge.c` + `include/*.h`, `Backends/SDL/Sources/MetalUISDL/SDLPlatform.swift`, `Backends/SDL/Sources/MetalUISDLDemo/main.swift`; `Backends/SDL/Tests/MetalUISDLTests/SDLDropTests.swift`, `AccessKitDragAndDropTests.swift` (new); `Tests/MetalUITests/DragAndDropAccessibilityTests.swift` (new), `DemoStackBudgetTests` (one arm); `Sources/MetalUIDemoContent/DragAndDropDemo.swift` (new), `Sources/MetalUIDemo/main.swift`; `docs/verification/human-checks.md`, `docs/divergences.md`, `docs/api-overview.md` | none |

Each lane commits red first (its tests, failing for the stated reason), then
green, then its mutation table — committed first, restored from a copy, full
unfiltered suite, `git status --short` after each, every reddened test named.
Each new guard is mutated red once. `swift package clean` after lane 1 (new
stored properties on public `Handlers`… and a new `InputEvent` case crossing
module boundaries).

---

## 6. Tests

Red-before is the reason the test fails before its lane's implementation (a
new API's test first fails to compile; the column says what it asserts once
it compiles against a stub that does nothing). Each mutation is applied to
the named spelling only and must redden **at least** the named test.

### 6.1 Lane 1 — `TransferableTests` (`Tests/MetalUICrossPlatformTests`, portable)

| # | test | asserts (evidence) | red-before | mutation that must redden it |
|---|---|---|---|---|
| 1.1 | `aStringExportsAndImportsUTF8PlainTextOnly` | types `[utf8PlainText]` both ways; `"héllo"` exports 6 UTF-8 bytes; imports back (T1, T5, T7) | stub exports `[]` | **M1a** String's exported types gain `.plainText` |
| 1.2 | `aWebURLExportsURLAndAFileURLExportsBoth` | web `[url]`, file `[url, fileURL]`; bytes = absolute string (T4, T6, T6b) | stub `[]` | **M1b** a file URL exports `[url]` only |
| 1.3 | `importingFollowsContentTypeConformance` | String ✗ from `url` data (T7b); URL ✗ from plain text (T7c); URL ✓ from `url` (T7d); `Data` ✓ from `utf8PlainText` (P16b); `.fileURL.conforms(to: .url)`, `.utf8PlainText.conforms(to: .data)`, not `.url.conforms(to: .plainText)` | stub conforms nothing | **M1c** `.url`'s parents gain `.plainText` |
| 1.4 | `aCustomContentTypeConformsThroughItsDeclaredParents` | `ContentType("com.example.note", conformingTo: [.utf8PlainText])` conforms to text, data, item; not url | stub | **M1d** conformance not transitive (parents only) |

### 6.2 Lane 1 — `DragAndDropTests` (`Tests/MetalUITests`, through `FakePlatformWindow`)

Fixture: a 400×200 window, a 200×200 source at the left (`Box` with
`.draggable("s")`), a 200×200 String destination at the right logging
`isTargeted` and the action into one ordered array — the probe's `pair`.

| # | test | asserts (evidence) | red-before | mutation |
|---|---|---|---|---|
| 1.5 | `aDraggableBeginsOnTheFirstMoveAndDropsOnADestination` | press, move 1 pt → session open (preview emitted next frame); move over the destination → `[T=true]`; release → `[T=true, T=false, drop(["s"])]` (P0, P17) | nothing begins | **M1e** the draggable leaf waits for `tapSlop` |
| 1.6 | `aZeroDistanceDragIsAClickNotADrag` | `.draggable` + `.onTapGesture`: press, a dragged event at the same point, release → `tap`, no session (P17z, P1a) | (passes vacuously before; red once 1.5's impl lands with M1f) | **M1f** begin on any dragged event (`>= 0`) |
| 1.7 | `aDraggableBeatsATapAClickAndALongPressOnItsElementAndItsChildren` | five arms: `.draggable` then `.onTapGesture`, the reverse, a `Button`'s own `.draggable`, a draggable parent over a `Button` child, `.onLongPressGesture` — each drag drops and runs no tap/click/long press; each click (no move) runs the tap/click (P1, P2f, P3, P22a–c) | no drag | **M1g** delete the `isBlocked` exception |
| 1.8 | `aDragGestureThatOutranksADraggableWinsAndAnOuterOneLoses` | inner `.gesture(DragGesture())` (declared before), a child's, `.highPriorityGesture` → changes + end, no drop; outer normal, parent's → drop, no change (P2a–d, P22d) | | **M1h** the draggable at `.high` priority |
| 1.9 | `aSimultaneousDragGestureChangesForTheStartingMoveAndNeverEnds` | `.simultaneousGesture(DragGesture(minimumDistance: 1))` + `.draggable`: one change, the drop, no end (P2e) | | **M1i** let simultaneous members keep receiving after the drag begins |
| 1.10 | `aDraggableRowsClickStillSelectsAndItsDragDoesNot` | `List(selection:)` whose row content is draggable: a click selects row 1; a drag from row 2 drops `"row2"` and leaves the selection at row 1 (P4a, P4b) | | **M1j** count a draggable in `isPointerTarget` (opaque) |
| 1.11 | `aTextFieldAndASliderKeepTheirPressUnderADraggable` | a draggable `TextField` drag selects text, no session; a draggable `Slider` drag writes values, no session (P20, P20b) | | **M1k** run the session/arena check ahead of `dispatchTextInput` |
| 1.12 | `theDeepestDestinationTakesTheDropAndCoversDoNotBlockIt` | nested String/String: inner drops, outer `T=true,T=false` as the pointer crosses; outside inner → outer; a destination under a plain `Box`, an `onClick` box and a `Button` still drops (P13a, P13b, P15a–d) | | **M1l** resolve with `topmostOpaqueHitbox` |
| 1.13 | `aDestinationThatRefusesTheTypeTargetsNothing` | outer String, inner URL: String drag over inner → outer `false`, inner never targeted, release drops nowhere; a URL payload over a String destination → no callback at all (P13c, P16) | | **M1m** fall through to the nearest accepting ancestor destination |
| 1.14 | `isTargetedTurnsFalseBeforeTheNextTrueAndBeforeTheAction` | siblings A→B: `AT=true, AT=false, BT=true, BT=false, B(…)`; leave and re-enter: `T=true,T=false,T=true,T=false,drop`; holding still adds nothing (P14, P10, P19) | | **M1n** call the new target's `true` before the old one's `false` |
| 1.15 | `theDropLocationIsLocalToTheDestination` | window (330, 140) → `(130, 140)` (P12a) | | **M1o** pass the window point |
| 1.16 | `escapeCancelsADragWithNoDropAndNoClick` | Escape over the destination: `T=true, T=false`, no drop; the release clicks nothing; a keymap binding for Escape does not run (P7) | | **M1p** let Escape reach the keymap first |
| 1.17 | `aDisabledSourceDoesNotDragAndADisabledDestinationRefuses` | divergence 100's two arms: no session from a `.disabled(true)` source; a disabled destination never targeted, no drop | | **M1q** register the destination region outside the disabled gate |
| 1.18 | `aDestinationUnderAllowsHitTestingFalseStillReceives` | (P15e) | | **M1r** register the destination region inside the `allowsHitTesting` gate |
| 1.19 | `aPresentationAboveADestinationBlocksADropBeneathIt` | a `Deferred` modal with an `onClick` scrim over the destination: no target, no drop; the same scrim on the destination's own layer (an `.overlay`) does not block (`DN-F` item 4) | | **M1s** drop the layer comparison |
| 1.20 | `theDefaultPreviewReplaysTheSourceAboveEverythingAtSeventyPercent` | after a 50 pt move: the scene holds the source's primitives unchanged at their place **and** a copy translated by (50, 0) with alpha × 0.7 on a layer greater than every other primitive's; masks equal the translated source bounds; gone after the drop (`DN-J`) | | **M1t** replay at opacity 1 / **M1u** replay untranslated |
| 1.21 | `aCustomPreviewReplacesTheSnapshot` | `draggable("s") { Rectangle().fill(.accent).frame(60×60) }`: the replay is the 60×60 fill at the pointer, opacity 0.7, and no source copy (P18b) | | **M1v** emit the snapshot as well |
| 1.22 | `leavingTheWindowHandsTheDragToThePlatformWhenItCan` | fake answers `true`: the first move outside calls `beginExternalDrag` once with `[utf8PlainText: "s" bytes]` at that position; the session ends (no preview next frame, `active == nil`); the release does nothing. Fake answers `false`: called once, session continues, release outside cancels (`DN-K`) | | **M1w** offer on every outside move / **M1x** never offer |
| 1.23 | `anExternalDropFindsTheSameDestinationAndLoadsOnlyWhatItImports` | `.drop(.entered)` over the destination with an item offering `[public.png, utf8PlainText]` → `onInput` true, `T=true`; `.moved` outside → false, `T=false`; `.performed` over it → true, action `["x"]`; `load` called once, for `public.utf8-plain-text` (`DN-C`, `DN-L`) | | **M1y** load every offered type |
| 1.24 | `anExternalDropWithUnknownTypesTargetsOptimistically` | `.entered(items: nil)` → true, `T=true` on a URL destination; `.performed` with a text item → `T=false`, no action, false (divergence 102's MetalUI half) | | **M1z** treat unknown types as refusing |
| 1.25 | `aDragNeitherFocusesNorAddsAStateEntry` | a drag from a focusable source onto a focusable destination leaves focus unchanged and the `StateTable` entry count unchanged frame over frame (`DN-O`, `DN-H` item 6) | | **M1aa** run the source's `ClickDispatch` focus request at drag begin |
| 1.26 | `theStyledSpellingsMoveNoIDAndTheProposalOnesWrapOnce` | a `Box` with and without `.draggable`/`.dropDestination` registers its hitbox under the same id; a proposal `Rectangle().draggable(…)`'s rectangle is one level below the wrapper (`DN-P`) | | **M1ab** wrap `StyledElement` in a modifier element |
| 1.27 | `aSourceThatVanishesMidDragStillDelivers` | toggling the source's `if` off mid-drag: the preview keeps its last snapshot, the drop delivers `"s"` (`DN-H` item 4) | | **M1ac** end the session when the source is not produced |
| 1.28 | `aFrameWithoutADragCapturesNothingAndAddsNoHitbox` | a tree with no draggable/destination: hitbox count and captured-primitive count equal the baseline's literals; with a destination but no session, captures stay 0 (work counted, not timed) | | **M1ad** push the capture scope for every `paintDecoration` |

### 6.3 Lane 1 — `DragAndDropCompileGuards` (whole-file `typecheckFile`, each mutated red once)

| # | guard | asserts |
|---|---|---|
| G1.1 | `theDragAndDropSpellingsCompileFromAPlainImport` | §2.2's spellings compile under `import MetalUI`; a second fixture spelling `.onDrop(of:isTargeted:perform:)` and `.onDrag { }` does **not** (`DN-A` item 2) |
| G1.2 | `anOutsideTypeCanConformToTransferable` | a struct with a custom `ContentType` conforms and is accepted by `draggable`/`dropDestination` |
| G1.3 | `aPlatformWindowWithoutBeginExternalDragDoesNotCompile` | a `PlatformWindow` conformer lacking it fails; with it, compiles (`DN-C` item 2) |

T rows (retained tests whose fixture changes, answers unchanged):
`ControlStateCompileGuards`' and `TransactionCompileGuards`' `Conformer`
fixtures gain `beginExternalDrag`; `Fakes.swift`'s `FakePlatformWindow`
gains it (records `[([DragRepresentation], Point<Pixels>)]`, answers
`externalDragResult`, default `false`) and a `simulateDrop(_:)` helper.

### 6.4 Lane 2 — `AppKitDragAndDropTests` (`Tests/MetalUITests`, a real `AppKitWindow`)

Driven with the probe's `FakeDrag` (`NSDraggingInfo`) against the window's
own `MetalHostView` — valid for MetalUI, which resolves from
`draggingLocation` (unlike SwiftUI, `R`'s caveat).

| # | test | asserts | mutation |
|---|---|---|---|
| 2.1 | `theHostViewRegistersForDraggedTypes` | the five types of `DN-L` | **M2a** register none |
| 2.2 | `aFinderFileDropReachesAURLDestination` | file-URL pasteboard: `draggingEntered` `.copy`, `T=true`; `performDragOperation` `true`; action gets the file URL at the destination-local point, y flipped from AppKit's bottom-left | **M2b** skip the y flip |
| 2.3 | `aStringDropOnAURLDestinationAnswersNoOperation` | `draggingEntered` `[]`, no `T` | **M2c** answer `.copy` unconditionally |
| 2.4 | `draggingExitedUnTargets` | `T=true` then `T=false` | **M2d** ignore `draggingExited` |
| 2.5 | `onlyTheImportedTypeIsReadFromThePasteboard` | an `NSPasteboardItemDataProvider` counting reads: one read, the destination's type | **M2e** eager `data(forType:)` for every type |
| 2.6 | `pasteboardTypesCarryTheirUTTypeSupertypes` | `public.png` → `conformsTo` ⊇ `public.image`, `public.data`; `public.file-url` ⊇ `public.url` | **M2f** empty `conformsTo` |
| 2.7 | `anExternalDragItemCarriesEveryRepresentationAndAnImage` | `draggingItem(for:at:)`'s pasteboard item holds each representation's bytes; its image is non-empty; a file URL's is the workspace icon's size | **M2g** write the first representation only |
| 2.8 | `beginExternalDragNeedsADragEvent` | no `mouseDragged` seen → `false`; after a synthesized one through `MetalHostView.mouseDragged` → `true` **if** AppKit starts a session headless — the lane measures this first; if AppKit refuses without a real pointer, the `true` arm becomes human check N3 and the test keeps the `false` arm only (recorded) | **M2h** return `true` with no event |
| 2.9 | `theSourceOffersCopyInBothContexts` | `draggingSession(_:sourceOperationMaskFor:)` `.copy` for `.withinApplication` and `.outsideApplication` (P6b) | **M2i** `.move` |

### 6.5 Lane 3 — SDL, accessibility, demo

| # | test | where | asserts | mutation |
|---|---|---|---|---|
| 3.1 | `sdlDropEventsBecomeOneDropSession` | `Backends/SDL` | `BEGIN, POSITION(10,20), POSITION(30,40), FILE(/tmp/a.txt), COMPLETE` through `SDLWindow.handle` → `onInput` sees `.entered((10,20), nil)`, `.moved((30,40))`, `.performed((30,40), [file-url "file:///tmp/a.txt"])` | **M3a** send `.performed` with no items |
| 3.2 | `aCompleteWithNoItemsIsAnExit` | `Backends/SDL` | `BEGIN, POSITION, COMPLETE` → `.entered`, `.exited` | **M3b** perform an empty drop |
| 3.3 | `aDroppedPathBecomesAFileURLString` | `Backends/SDL` | `/tmp/a b.txt` → `file:///tmp/a%20b.txt`; `C:\Users\x y.txt` → `file:///C:/Users/x%20y.txt`; `é` percent-encoded as UTF-8 | **M3c** no percent-encoding |
| 3.4 | `droppedTextIsUTF8PlainText` | `Backends/SDL` | `TEXT("hi")` → one item, type `public.utf8-plain-text` ⊂ plain-text, text, data | **M3d** type `public.text` |
| 3.5 | `anSDLWindowCannotBeginAnExternalDrag` | `Backends/SDL` | `false` (`DN-K` item 4) | **M3e** `true` |
| 3.6 | `ordinaryPointerMotionEndsAnOpenDropSession` | `Backends/SDL` | `BEGIN, POSITION, MOUSE_MOVE` → `.entered`, `.exited`, then the move | **M3f** ignore motion |
| 3.7 | `theBridgeTranslatesEverySDLDropEvent` | `Backends/SDL` | a test-only bridge entry pushes each `SDL_DropEvent` kind; `mui_poll` yields the matching `MUI_EVENT_DROP_*` with `x`, `y`, `text` (arms `armMainRunLoopExitCheck()`, the SDL run-loop hazard) | **M3g** drop `POSITION` from the switch |
| 3.8 | `aDraggableAndADropDestinationPublishNothingNew` | root | the neutral `AccessibilityTree` and the AppKit bridge's attributes for a draggable `Text`, a draggable `Button`, a labelled destination and a destination `Text` equal the same tree without the modifiers (A0–A4) | **M3h** give a destination an `AXNode` custom action |
| 3.9 | `accessKitPublishesADraggableAndADropDestinationUnchanged` | `Backends/SDL` | AccessKit's node for the same four equals the control's | (3.8's mutation, through AccessKit) |
| 3.10 | `everyProductionTreeBuildsOnAOneMegabyteThread` — **T row**, its builder list gains `dragAndDropDemoContent()` | root | still green | **M3i** inline every demo section into one builder (expect red on a 1 MB thread; lane records the measured frame size either way) |
| 3.11 | `theDragAndDropDemoDropsAChipOnTheTextWell` | root | the demo tree through `FakePlatformWindow`: dragging the "Apple" chip onto the Text well shows "Apple" in the well's text; the Disabled well refuses | **M3j** the demo's well ignores its items |

### 6.6 Counts

Root suite **1976 → 2018**: lane 1 +31 (1.1–1.28 + G1.1–G1.3; four of them,
1.1–1.4, in `MetalUICrossPlatformTests`), lane 2 +9, lane 3 +2 (3.8, 3.11;
3.10 is a T row). Guards **121 → 124**. `Backends/SDL` `MetalUISDLTests`
+8 (3.1–3.7, 3.9). Linux/Windows `MetalUICrossPlatformTests` +4. No golden,
no test retired; every T row above names its unchanged answer.

---

## 7. The demo (`METALUI_DND_DEMO=1`)

"MetalUI — Drag and Drop", 920×560 (`MetalUIDemo`; `MetalUISDLDemo` honours
the same variable). Left column, top to bottom: three chips — **Apple**
(`.draggable("Apple")`), **example.com** (`.draggable(URL(string:
"https://example.com")!)`), **Custom preview** (`.draggable("Custom") {
a 60×60 accent square }`) — and a `ScrollView { List(0..<20, selection:) }`
whose row content is `.draggable("Row n")`. Right column: four wells, each
a rounded box showing its last drop and filling with `.accent` while
`isTargeted`: **Text** (`String`), **Links and files** (`URL`), **Anything**
(`Data`, shows the byte count), **Disabled** (`String`, `.disabled(true)`).

Expected looks (human checks N1–N7, §8): a chip dragged from the left follows
the pointer translucently with the press point under it, the chip itself
staying put; the Text well fills while hovered and shows "Apple" on release;
Escape mid-drag snaps nothing and fills nothing; the URL chip is refused by
the Text well (no fill) and taken by Links; every chip is refused by
Disabled; a row clicks to select and drags without selecting; a file from
Finder fills Links and lists its `file://` URL; text from TextEdit fills
Text; a chip dragged out of the window onto TextEdit inserts "Apple" (AppKit)
— on SDL the chip stops at the window edge.

---

## 8. Human checks (`docs/verification/human-checks.md`, new group N)

N1 in-window drag (preview translucency, anchor, source unchanged, drop),
N2 `isTargeted` highlight on enter/leave/re-enter and Escape, N3 a chip
dragged out of the window to TextEdit and Finder (AppKit hand-off, drag
image), N4 a file from Finder and text from TextEdit onto the wells (AppKit),
N5 the same two drops onto `MetalUISDLDemo` on macOS and, if available, Linux
and Windows (SDL positions, optimistic highlight — divergence 102), N6 a
`List` row: click selects, drag does not, N7 (optional) VoiceOver reads the
chips and wells exactly as without drag and drop (`DN-N`). Each names its
headless pin, as the existing groups do.

---

## 9. Must not move

State retention (`StateTable`, `theSevenRetentionSlotsAreMutuallyDistinct`,
`MC-A`/`MC-C`/`MC-P` numbering, `.id()` outermost) — no id path changes
(`DN-P`); hit testing, focus, accessibility, animation, the scrim, `List`
windowing and `TB-AH`, `Deferred`, `TextField`/`TextEditor`: unchanged for
every tree without a draggable or destination (1.28 counts it). **0 px
against `053a3b3` in all fourteen offscreen images**
(`docs/probes/demo-pixels/compare.sh`); `Expected.swift` unedited;
`everyProductionTreeBuildsOnAOneMegabyteThread`,
`theLegacyEngineSymbolsAreAbsentFromTheTestProcess` green; 0 `error:`, only
the native deprecation `warning:`, on both build systems; `MetalUILayout`
imports only `MetalUICore`; `MetalUIPlatform` imports only `MetalUICore` and
`MetalUIScene`; `Backends/SDL` and a `swift:6.4-noble` container build.
`MemoryLayout<Handlers>.size` +8 (one reference), measured by lane 1 with the
smallest thread building every production tree. Real-window capture per the
lock probe at each lane's close.
