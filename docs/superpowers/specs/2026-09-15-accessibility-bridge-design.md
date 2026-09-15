# Accessibility bridge design

**Milestone:** SwiftUI alignment plan task 12, **accessibility-bridge half only**
(`plans/2026-09-12-swiftui-alignment.md`). Gesture composition, button
semantics, disabled behaviour and content shapes wait for task 9 and are not
here.

**Status (2026-09-15): design only.** Written against `f64e58a` on
`feat/ax-bridge`. No source has changed. Rulings are prefixed **`AB-`** and
lettered, in `docs/superpowers/2026-09-15-accessibility-bridge-decisions.md`.
A bare `AB-3` is a typo, not a citation. The SwiftUI evidence is one committed
probe, `docs/probes/swiftui-accessibility-bridge.swift`, whose header carries
its recorded output; "probe arm N" below means that file's arm N.

## What exists today, and what is wrong with it

Design spec §9 specified emission, identity, bridge, focus and virtualization.
The tombstones-and-AX milestone built emission and identity and stopped:

- `Frame.axNodes` and `Frame.axNode(for:)` are written every frame and **read
  by nothing** (record §05).
- A node is emitted only when `Handlers.axNode` is declared non-empty, and no
  public API declares one except `List`, which always emits its own
  `container` node with `logicalCount = data.count`. A `Text`, an `onClick`
  box and a focusable box expose nothing.
- `AXNode.children` is always `[]` (ruling `TB-M`): a container has no child
  ids to pass, and order cannot be recovered from `axNodes`' keys.
- **`Frame.emitAXNode` stores the untranslated `bounds`**
  (`Frame.swift:745-746`) while `insertHitbox` adds `activeOffset`
  (`Frame.swift:564-567`). By reading, a node inside a scrolled `ScrollView`
  reports its content-space rect, not where it is on screen. Lane 1's
  `aNodeInsideAScrolledScrollViewReportsItsOnScreenFrame` is the first
  measurement of it.
- The proposal path (`HStack`, `ProposalText`, …) emits nothing
  (plan, "Proposal interaction coverage").
- `MetalHostView` is a plain `NSView`: AppKit sees one opaque view.

## What this design delivers

Three lanes, implemented **in this order**:

| lane | one line |
|---|---|
| 1. **tree and seam** | a platform-neutral `AccessibilityTree` built from a frame when, and only when, a client has asked; a two-requirement `PlatformWindow` seam; requests routed back through `Window`'s existing dispatch; the emission-frame fix |
| 2. **AppKit bridge** | `NSAccessibilityElement` objects keyed by node id, the host view as an `AXGroup`, screen-coordinate frames read lazily, per-instance action gating, and change notifications diffed between published trees |
| 3. **defaults, modifiers, List** | what a `Text`, an `onClick` element, a focusable element and a `List` row publish without a declaration; `accessibilityLabel`/`accessibilityValue`/`accessibilityAdjustableAction`; a button's combined label; the demo's labels and the human VoiceOver script |

**Why this order.** Lane 2's element objects are a function of lane 1's tree
type, and its tests build trees by hand, so they do not need lane 3. Lane 3's
defaults are only observable through lane 1's builder, and its end-to-end
check (a real VoiceOver look) needs lane 2. Lane 3 is the one to cut if the
track runs short: without it the bridge works for declared nodes and `List`,
and `Text` is silent.

## Scope boundaries (ruling `AB-Q`)

**In:** everything in the table above, on the legacy element path (`Box`,
`Column`, `Row`, `Stack`, `Text`, `List`, `FrameModifier`) plus
`OnTapModifier` (it already calls `registerHandlers`).

**Deferred, each with an owner:**

1. Proposal-path emission: `ProposalText`, `HStack`/`VStack`/`ZStack`,
   `ProposalScrollView` emit nothing (task 6/11 port them; they reuse
   `Frame.registerHandlers(…accessibleText:)` from lane 3).
2. Scroll areas: no `AXScrollArea` role, no `accessibilityScrollToVisible`, so
   **VoiceOver cannot move to a `List` row that is not realized** (task 10).
3. `Stack` order: SwiftUI lists a `ZStack`'s topmost child first (probe arm 4);
   MetalUI publishes declaration order (`AB-P`, a recorded divergence).
4. Modal isolation: content under a `Deferred` scrim stays in the tree and
   pressable (task 12's interaction half).
5. `accessibilityHidden`, `accessibilityElement(children:)`, traits beyond
   `selected`/`disabled`, custom actions, `AXNode.actions` as a declaration
   (task 9's button half; `AB-H`).
6. System settings (Reduce Motion, Increase Contrast) — task 13.
7. iOS/`UIAccessibility` — task 14. The neutral tree is shaped so a UIKit
   conformer can consume it, and nothing more is claimed.
8. `Frame.axNode(for:)`'s tombstone query stays unread (`AB-D`).
9. Writing the derived hierarchy back into `Frame.axNodes[id].children`
   (`AB-C`).

## Hard constraints carried from the dispatch

`swift test --no-parallel` passes with 0 `error:` / 0 `warning:`, read from the
"Test run with N tests" line. The 97 goldens do not change (this track touches
no file under `Sources/MetalUILayout/`). No test sleeps; nothing spins a run
loop for time. Performance claims are counts (published trees, built trees,
posted notifications, `$ax` slots), never wall clock. A trap, if one is added,
is pinned with an exit test. New typecheck guards (none are planned) would be
mutated red once under `--build-system native`. Every SwiftUI claim below cites
the probe. **`swift package clean` before the first test run of lane 1 and of
lane 3**: both add stored properties to public types that cross into a test
target (`AXNode.logicalIndex`, the `PlatformWindow` requirements), the shape
CLAUDE.md's Build section records as producing impossible failures.

Shared-file edits are kept additive and small; each is listed per lane with
its line budget so the integration step can merge the three tracks.

---

## Lane 1 — tree and seam

### New file `Sources/MetalUIPlatform/AccessibilityTree.swift`

Platform-neutral, imports only `MetalUICore`.

```swift
/// Opaque, hashable identity of a published node. `MetalUI` wraps a
/// `GlobalElementID`; the platform never looks inside (AB-A).
public struct AccessibilityNodeID: Hashable {
    public let base: AnyHashable
    public init<Base: Hashable>(_ base: Base)
}

public enum AccessibilityRole: Equatable {
    case group, button, staticText, image, table, row
}

public struct AccessibilityActions: OptionSet, Equatable {
    public let rawValue: UInt8
    public init(rawValue: UInt8)
    public static let press, increment, decrement: AccessibilityActions
}

public struct AccessibilityNode: Equatable {
    public var role: AccessibilityRole
    public var label: String?
    public var value: String?
    public var isSelected: Bool
    public var isEnabled: Bool
    public var isFocusable: Bool
    public var actions: AccessibilityActions
    /// Window content space: logical points, top-left origin, scroll offset
    /// applied, NOT clipped (AB-E).
    public var frame: Bounds<Pixels>
    public var children: [AccessibilityNodeID]
    /// `AXRowCount` for a `.table` (AB-L).
    public var rowCount: Int?
    /// `AXIndex` for a `.row` (AB-L).
    public var rowIndex: Int?
    public init(role:label:value:isSelected:isEnabled:isFocusable:actions:frame:children:rowCount:rowIndex:)
}

public struct AccessibilityTree: Equatable {
    public var roots: [AccessibilityNodeID]
    public var nodes: [AccessibilityNodeID: AccessibilityNode]
    public var focused: AccessibilityNodeID?
    public init(roots:nodes:focused:)
    public static let empty: AccessibilityTree
}

/// What an accessibility client asked the window to do. `onInput`'s shape:
/// the answer says whether anything handled it.
public enum AccessibilityRequest: Equatable {
    case activate                       // a client queried the host (AB-B)
    case press(AccessibilityNodeID)
    case increment(AccessibilityNodeID)
    case decrement(AccessibilityNodeID)
    case focus(AccessibilityNodeID)
}
```

`Sendable` is deliberately not declared: every value crosses only between
`@MainActor` code, and `AnyHashable`'s conformance would have to be argued.

### `Sources/MetalUIPlatform/Platform.swift` (+2 requirements, ~15 lines with docs)

```swift
/// Fired by the platform when an accessibility client asks for something.
var onAccessibilityRequest: ((AccessibilityRequest) -> Bool)? { get set }
/// Replaces the tree the platform exposes. Called only after `.activate`,
/// and only when the tree differs from the last one published (AB-M).
func publishAccessibilityTree(_ tree: AccessibilityTree)
```

**No default implementations** (`AB-R`): a conformer that forgets either fails
to compile, rather than compiling into a window VoiceOver cannot see.

### `Sources/MetalUIPlatform/AppKit/AppKitPlatform.swift` (lane 1: +6 lines)

`AppKitWindow` gains `var onAccessibilityRequest` and a
`publishAccessibilityTree` that stores the tree in
`private(set) var publishedAccessibilityTree`. Lane 2 replaces the body.

### `Tests/MetalUITests/Fakes.swift` (+~20 lines, additive)

```swift
var onAccessibilityRequest: ((AccessibilityRequest) -> Bool)?
private(set) var publishedAccessibilityTrees: [AccessibilityTree] = []
func publishAccessibilityTree(_ tree: AccessibilityTree)   // appends
@discardableResult
func simulateAccessibilityRequest(_ request: AccessibilityRequest) -> Bool
```

### `Sources/MetalUI/Frame.swift` (~25 lines)

1. `init(…, collectsAccessibility: Bool = false)`, stored `let`.
2. `private(set) var axEmissionOrder: [GlobalElementID] = []`, appended in
   `emitAXNode` **only when `collectsAccessibility`** (a `List` emits every
   frame; an unconditional append is a per-frame allocation in every app).
3. `emitAXNode` stores `bounds` translated by `activeOffset`, exactly as
   `insertHitbox` does (`AB-E`). Unclipped.
4. `registerHandlers` synthesizes a node when collecting and nothing was
   declared, for an element that is clickable, focusable or adjustable —
   through one internal function, `AXNode.synthesized(declared:handlers:text:)`,
   which lives in the new file below. The existing `!handlers.axNode.isEmpty`
   emission is unchanged when not collecting, so
   `noConformerEmitsAnAXNodeItDidNotDeclare` stays true as written.

   Lane 1 synthesizes only the handler-driven part (role `.button` for a
   clickable element whose role is `.generic`; an otherwise-empty node for a
   focusable one). Lane 3 adds `text:`.

### `Sources/MetalUI/Passes.swift` (+2 lines)

`LayoutPass.collectsAccessibility` and `PrepaintPass.collectsAccessibility`,
internal, forwarding to `frame`.

### New file `Sources/MetalUI/AXSynthesis.swift`

`extension AXNode { static func synthesized(declared: AXNode, handlers: Handlers, text: String?) -> AXNode? }`
— returns the node to emit, or `nil` for "emit nothing". Rules in `AB-F`/`AB-G`.

### New file `Sources/MetalUI/AccessibilityTreeBuilder.swift`

```swift
@MainActor
enum AccessibilityTreeBuilder {
    static func build(axNodes: [GlobalElementID: AXNode],
                      order: [GlobalElementID],
                      focused: GlobalElementID?,
                      hitboxes: [Hitbox],
                      focusRegistry: FocusRegistry) -> AccessibilityTree
}
```

Algorithm (`AB-C`, `AB-H`, `AB-O`):

1. Walk `order`, skipping an id already seen (two siblings given the same
   `.id(_:)` mint one `GlobalElementID`; the second emission overwrote the
   first in `axNodes`) and any node whose frame has zero width or height (a
   `hidden()` subtree prepaints at `(0,0) 0×0`).
2. Parent = the nearest `GlobalElementID.parent` ancestor present in the kept
   set; none means root. A child appends to its parent's `children` in `order`
   position. Do this in a second pass, so a parent emitted *after* its child
   would still work (today every conformer emits before its children).
3. Actions are **derived, not declared**: `.press` iff `hitboxes` holds an
   entry for the id with `handlers.onClick != nil` (so `allowsHitTesting(false)`
   removes it, as it removes the click); `.increment`/`.decrement` iff
   `focusRegistry.actionHandler(for:type: ObjectIdentifier(AccessibilityAdjustment.self))`
   is non-nil. The two types are defined in lane 1 (below) so this compiles;
   lane 3 adds the modifier that registers a handler for them.
4. `isFocusable` from `focusRegistry.isFocusable`. `focused` is the window's
   read-back focus if that id was kept, else `nil`.
5. Role map: `generic`/`container` → `.group`; `button` → `.button`; `text` →
   `.staticText`; `image` → `.image`; `container` with `logicalCount` →
   `.table`; any node with `logicalIndex` → `.row` (lane 3 adds the field).
   Traits: `.selected` → `isSelected`; `.disabled` → `isEnabled = false`;
   `.updatesFrequently` has no AppKit counterpart and is dropped.
6. Button label combination is lane 3.

### New file `Sources/MetalUI/AccessibilityAdjustment.swift`

```swift
public enum AccessibilityAdjustmentDirection: Equatable, Sendable { case increment, decrement }
public struct AccessibilityAdjustment: Action {
    public let direction: AccessibilityAdjustmentDirection
    public init(direction: AccessibilityAdjustmentDirection)
}
```

Lane 1 tests register a handler with the existing `onAction(AccessibilityAdjustment.self)`.

### New file `Sources/MetalUI/WindowAccessibility.swift`

```swift
@MainActor
final class WindowAccessibility {
    private(set) var isActive = false
    private(set) var lastPublished = AccessibilityTree.empty
    private(set) var buildCount = 0      // test observable, AB-M
    private(set) var publishCount = 0    // test observable, AB-M
    func activate() -> Bool             // true only on the first call
    func frameDidRender(_ tree: @autoclosure () -> AccessibilityTree,
                        to platformWindow: any PlatformWindow)
}

extension Window {
    func handleAccessibilityRequest(_ request: AccessibilityRequest) -> Bool
}
```

`frameDidRender` builds only when active and publishes only when the tree is
`!=` `lastPublished`.

`handleAccessibilityRequest` (`AB-B`, `AB-H`, `AB-J`):

- `.activate`: first time, set active and `setNeedsRedraw()`; return `true`.
- `.press(id)`: unwrap `id.base as? GlobalElementID`; find the **last**
  `lastHitboxes` entry with that id and an `onClick`; run it,
  `setNeedsRedraw()`, return `true`; otherwise `false`.
- `.increment`/`.decrement`: `lastFocusRegistry.actionHandler(…)` for
  `AccessibilityAdjustment`, run with the direction, dirty, `true`.
- `.focus(id)`: `lastFocusRegistry.isFocusable(gid)` → `focus(gid)`, `true`;
  otherwise `false`, focus unchanged.

### `Sources/MetalUI/Window.swift` (+~8 lines)

1. `let accessibility = WindowAccessibility()`.
2. In `init`, beside `onInput`:
   `platformWindow.onAccessibilityRequest = { [weak self] in self?.handleAccessibilityRequest($0) ?? false }`.
3. `Frame(…, collectsAccessibility: accessibility.isActive)`.
4. After the focus read-back and `hasActiveAnimations` assignment, before
   `renderer.upload`: `accessibility.frameDidRender(AccessibilityTreeBuilder.build(…), to: platformWindow)`.

### Lane 1 tests — `Tests/MetalUITests/AccessibilityTreeTests.swift` (new)

Frame-level tests use `Frame.render` over a bare `Frame`, `AXEmitSiteTests`'
footing (no Metal device). Window-level tests use `makeFakeWindow`.

| test | red before | mutation that must redden it after |
|---|---|---|
| `aFrameThatDoesNotCollectEmitsNothingUndeclaredAndRecordsNoOrder` — `Box().onClick{}.focusable()` in a non-collecting frame: `axNodes` empty, `axEmissionOrder` empty, no `$ax` slot under the box's id; the same tree collecting: one node, order `[id]`, the slot exists | does not compile (`collectsAccessibility`, `axEmissionOrder`) | make `registerHandlers` synthesize regardless of the flag; separately, append to `axEmissionOrder` unconditionally |
| `anInactiveWindowBuildsAndPublishesNothing` — fake window, three drawn frames of a tree with a `List` and an `onClick` box, no request: `publishedAccessibilityTrees.isEmpty`, `accessibility.buildCount == 0` | does not compile | pass `collectsAccessibility: true` in `Window`; drop the `isActive` guard in `frameDidRender` |
| `anActivationRequestDirtiesACleanWindowAndItsNextFramePublishes` — draw until clean, `.activate` returns `true`, `needsRedraw`, draw, exactly one published tree containing the button; a second `.activate` does not dirty | does not compile | delete `setNeedsRedraw()` in `.activate` (no publish); make `activate()` return `true` every time (second call dirties) |
| `childrenFollowDeclarationOrderWhereIDsAloneCannot` — `TB-M`'s own counterexample: a container node over `Box().id("x")`, `Box().id("y")` and the same with the two swapped, each child declaring a node; `children` reads `[x, y]` then `[y, x]` | does not compile | reverse `order` in the builder; build `children` by iterating `axNodes`' keys |
| `aNodesParentIsItsNearestEmittingAncestor` — declared container `Box { Column { Text (declared) } }`: `roots == [box]`, `box.children == [text]`, `Column` absent | does not compile | use `id.parent` without walking (the text becomes an orphan root) |
| `aNodeInsideAScrolledScrollViewReportsItsOnScreenFrame` — `ScrollView` whose `ScrollState.offset` is seeded to 40 (`DeferredTests.swift:387`'s spelling), child declared at content y = 100: `frame.axNodes[id].frame.origin.y == 60` and the published node agrees | fails today: reads 100 (by reading; this test is its first measurement) | delete the `activeOffset` translation in `emitAXNode` |
| `aPressRequestRunsOnClickThroughTheLastFramesHitboxes` — two boxes, only one clickable; press the clickable one: returns `true`, counter 1, `needsRedraw`; press the other: `false`, counter unchanged; its published node has no `.press` | does not compile | return `true` from `.press` without running the handler; derive `.press` for every node |
| `aPressIsRefusedWhereHitTestingIsDisabled` — `.onTap {}` under `.allowsHitTesting(false)`: no `.press` in the published node, the request returns `false`, the closure does not run; the same without the modifier is pressable | does not compile | route press through the element's `Handlers` instead of `lastHitboxes` |
| `publishedFocusIsTheWindowsFocusAndAFocusRequestMovesIt` — focusable `a`, `b`, plain `c`: `window.focus(a)`, draw → `tree.focused == a`; `.focus(b)` → `true`, draw → `focused == b` and `window.focusedElement == b`; `.focus(c)` → `false`, focus stays `b` | does not compile | build `focused` from the handed-in focus rather than the read-back; drop the `isFocusable` check |
| `anUnchangedFrameIsNotRepublished` — active, draw, `setNeedsRedraw()`, draw: `publishCount == 1`, `buildCount == 2`; a `@State` label change and a third draw: `publishCount == 2` | does not compile | remove the `!=` comparison |
| `aHiddenSubtreeIsNotPublishedAndADuplicatedIDIsPublishedOnce` — a declared node under `.hidden()` is absent; `Row { Box(declared).id("x"); Box(declared).id("x") }` (two siblings minting one `GlobalElementID`) publishes one node for that id, once in `roots` | does not compile | remove the zero-area filter; remove the seen-set |
| `anIncrementRequestRunsTheAdjustmentHandler` — `Box().onAction(AccessibilityAdjustment.self) { … }` records directions: published actions `[.increment, .decrement]`; `.increment(id)`, `.decrement(id)` → `true`, `true`, recorded in that order; on a box with no handler both return `false` | does not compile | swap the two directions; advertise adjustment for every node |

---

## Lane 2 — AppKit bridge

### New file `Sources/MetalUIPlatform/AccessibilityTreeChanges.swift`

A pure diff, neutral, so it is testable without AppKit and reusable by a UIKit
conformer:

```swift
struct AccessibilityTreeChanges: Equatable {
    var removed: [AccessibilityNodeID]        // in old-tree order
    var structureChanged: Bool                // id set, roots, any children, or any role
    var labelChanged: [AccessibilityNodeID]
    var valueChanged: [AccessibilityNodeID]
    var rowCountChanged: [AccessibilityNodeID]
    var focusChanged: Bool
    init(from old: AccessibilityTree, to new: AccessibilityTree)
}
```

A frame-only difference produces an all-empty value (`AB-K`).

### New file `Sources/MetalUIPlatform/AppKit/AppKitAccessibility.swift`

```swift
@MainActor protocol AccessibilityNotificationPosting: AnyObject {
    func post(_ notification: NSAccessibility.Notification, for element: Any)
}
@MainActor final class SystemAccessibilityNotificationPoster: AccessibilityNotificationPosting
    // NSAccessibility.post(element:notification:)

@MainActor final class AppKitAccessibilityBridge {
    weak var hostView: NSView?
    var poster: any AccessibilityNotificationPosting
    var onRequest: ((AccessibilityRequest) -> Bool)?
    private(set) var isActive: Bool
    private(set) var tree: AccessibilityTree
    private(set) var elements: [AccessibilityNodeID: AppKitAccessibilityElement]
    private(set) var parents: [AccessibilityNodeID: AccessibilityNodeID]
    func activateIfNeeded()
    func publish(_ tree: AccessibilityTree)
    func rootElements() -> [Any]
    func hitTest(screenPoint: NSPoint) -> Any?
    func focusedElement() -> Any?
    func screenFrame(for id: AccessibilityNodeID) -> NSRect
}

@MainActor final class AppKitAccessibilityElement: NSAccessibilityElement {
    let id: AccessibilityNodeID
    private(set) var node: AccessibilityNode
    private(set) var isDetached: Bool
    // overrides, each reading `node` or asking the bridge:
    // accessibilityRole, accessibilityLabel, accessibilityValue,
    // accessibilityParent, accessibilityChildren, accessibilityFrame,
    // isAccessibilityElement, isAccessibilityEnabled, isAccessibilitySelected,
    // accessibilityRowCount, accessibilityRows, accessibilityVisibleRows,
    // accessibilityIndex, isAccessibilityFocused, setAccessibilityFocused(_:),
    // accessibilityPerformPress/Increment/Decrement,
    // isAccessibilitySelectorAllowed(_:)
}

extension MetalHostView {
    override func isAccessibilityElement() -> Bool          // true
    override func accessibilityRole() -> NSAccessibility.Role?   // .group
    override func accessibilityChildren() -> [Any]?          // activate; roots
    override func accessibilityHitTest(_ point: NSPoint) -> Any?  // activate; deepest
    override var accessibilityFocusedUIElement: Any? { get } // activate; focused or self
}
```

The design session typechecked every override spelling above, on an `NSView`
subclass extension and an `NSAccessibilityElement` subclass, with
`xcrun swiftc -typecheck -swift-version 6 -warnings-as-errors`: 0 diagnostics.
Two spellings differ from a guess: `accessibilityFocusedUIElement` is a
property on `NSView`, not a method; the overrides compile in an extension.

`MetalHostView` gains one stored property in its class body,
`var accessibilityBridge: AppKitAccessibilityBridge?`. `AppKitWindow` owns the
bridge, sets it on the host view, forwards `onAccessibilityRequest` to
`bridge.onRequest`, and forwards `publishAccessibilityTree` to `bridge.publish`.
`hostView` loses `private` so platform tests can reach it.

Behaviour:

- **Activation** (`AB-B`): the three host entry points call
  `activateIfNeeded()`, which sends `.activate` once and never again.
- **Identity** (`AB-D`): `publish` reuses the element for every id still
  present, updating `node`; creates one for each new id; for each removed id
  sets `isDetached`, drops it from `elements`, and it then answers
  `accessibilityParent() == nil`, children `[]`, `isAccessibilitySelectorAllowed`
  `false` for the perform selectors, and every perform `false`. It keeps its
  last role/label/value (probe arm 12: a removed SwiftUI node keeps its value
  and reads `parent=nil`). An id that returns gets a new object.
- **Frames** (`AB-E`): `accessibilityFrame()` computes at read time from the
  host view: `window.convertToScreen(hostView.convert(localRect, to: nil))`.
  The host view is flipped, so the node's top-left rect converts without a
  manual flip. Nothing is cached at publish.
- **Parent**: the parent node's element, or the host view for a root.
- **Actions** (`AB-H`): `isAccessibilitySelectorAllowed` answers per
  instance from `node.actions`; a perform method sends the request and returns
  its answer; a disallowed one returns `false` without sending.
- **Focus** (`AB-J`): `isAccessibilityFocused()` is `tree.focused == id`;
  `setAccessibilityFocused(true)` sends `.focus(id)`; `false` is ignored.
- **Rows** (`AB-L`): `.table` answers `accessibilityRowCount` from
  `rowCount`, `accessibilityRows`/`accessibilityVisibleRows` from its `.row`
  children; `.row` answers `accessibilityIndex` from `rowIndex`.
- **Hit test**: the deepest element containing the point, the later sibling
  winning a tie; the host view if none.
- **Notifications** (`AB-K`), posted in `publish` from
  `AccessibilityTreeChanges`, **only when active**, in this order:
  one `.uiElementDestroyed` per removed element; one `.layoutChanged` on the
  host view if `structureChanged`; `.titleChanged` / `.valueChanged` /
  `.rowCountChanged` per changed element; one `.focusedUIElementChanged` on the
  newly focused element (the host view when focus clears). Nothing for a frame
  change, nothing for a created element.

### Lane 2 tests — `Tests/MetalUIPlatformTests/AppKitAccessibilityTests.swift` (new)

Real `AppKitPlatform` windows (the platform tests may close theirs), trees
built by hand, a recording poster injected through `bridge.poster`. Everything
is read through the NSAccessibility protocol methods the AX server calls, on
the host view and the vended elements. No deprecated informal API (it warns),
no VoiceOver, no permission.

| test | red before | mutation that must redden it after |
|---|---|---|
| `theHostViewIsAGroupWhoseChildrenAreThePublishedRoots` — two roots: host `isAccessibilityElement()`, role `.group`, two children in root order, each child's parent the host view | fails: plain `NSView` answers `nil` children | return roots in dictionary order; answer `nil` for a root's parent |
| `rolesLabelsValuesAndTraitsMapOneToOne` — one node per role, label and value distinct strings, one selected, one disabled | fails to compile | swap label and value; map `.staticText` to `.group`; ignore `isEnabled` |
| `anElementKeepsItsIdentityAcrossPublishesAndIsDetachedWhenItsIDGoes` — publish `{a, b}`, keep both objects; publish with `a`'s label changed: same objects; publish `{a}`: `b.accessibilityParent() == nil`, `b` not in the host's children, `b.accessibilityPerformPress() == false` and no request sent, `b` still reads its label; publish `{a, b}`: the new `b` is `!==` the old | fails to compile | recreate every element on publish; skip `isDetached` (parent stays the host) |
| `anElementsFrameIsItsHostRectInScreenCoordinatesReadAtQueryTime` — 200×100 content window; node `(10, 0, 20, 16)`: expected screen rect is literal arithmetic over `window.contentRect(forFrameRect: window.frame)` — `(minX + 10, maxY - 0 - 16, 20, 16)`, not a call to the conversion under test; then `setFrameOrigin` by (+37, +23) with no republish and the rect moves by the same | fails to compile | drop the flip (use `maxY` → `minY + y`); cache the screen rect at publish |
| `onlyAdvertisedActionsAreAllowedAndPerformingSendsTheRequest` — a `[.press]` node and a `[]` node: selector allowed/refused per node; press on the first sends `.press(id)` and returns the closure's answer (`true`, then `false` when the closure returns `false`); press on the second sends nothing; increment/decrement likewise | fails to compile | allow every selector; return `true` regardless of the closure |
| `focusIsReportedFromTheTreeAndAFocusRequestIsSent` — `focused = b`: host `accessibilityFocusedUIElement` is `b`'s element and `b.isAccessibilityFocused()`; `setAccessibilityFocused(true)` on `a` sends `.focus(a)`; `focused = nil`: the host returns itself | fails to compile | report the first focusable node; send nothing from the setter |
| `aTableReportsItsRowCountAndItsRowsTheirIndices` — table `rowCount = 500` with rows at indices 40, 41, 42 | fails to compile | report `children.count` as the row count; report the position in `children` as the index |
| `hitTestingReturnsTheDeepestLatestElementUnderThePoint` — two overlapping roots, the second with a child: a point in all three returns the child; a point only in the first returns the first; outside, the host | fails to compile | return the first match; stop at roots |
| `aHostQueryActivatesExactlyOnce` — call `accessibilityChildren()`, `accessibilityHitTest`, `accessibilityFocusedUIElement` twice each: one `.activate` request | fails: nothing sends it | drop the sticky flag (six requests) |
| `nothingIsPostedBeforeActivation` — publish two different trees without any host query: recorder empty; query once; publish a third: posts appear | fails to compile | post regardless of `isActive` |
| `aFrameOnlyChangeAndAnIdenticalRepublishPostNothing` — move every frame by 5 points and republish; republish the identical tree: zero posts | fails to compile | treat frame as structure; post `.layoutChanged` on every publish |
| `aStructureChangePostsOneLayoutChangedAndOneDestroyedPerRemovedElement` — remove three leaves and add two: exactly 3 `.uiElementDestroyed` (on the three old objects), 1 `.layoutChanged` (on the host view), 0 other | fails to compile | post `.layoutChanged` per change; post destroyed for created elements too |
| `labelValueRowCountAndFocusChangesPostOnlyForTheElementThatChanged` — change one label, a different node's value, the table's row count and the focus, in four publishes: one post each, on the right element, of the right name | fails to compile | post `.valueChanged` for label changes; post focus on the old element |

End-to-end, lane 2's last test, in `Tests/MetalUITests/AccessibilityEndToEndTests.swift` (new):

| test | red before | mutation |
|---|---|---|
| `aRealAppKitWindowPublishesItsFrameAndAPressRunsOnClick` — `App.openWindow` (unique title, **not closed**, `FrameLoopTests`' rule) over a `Column` holding a `Box` declaring `AXNode(role: .button, label: "Increment")` with an `onClick` counter; find the `NSWindow` by title, ask its content view for `accessibilityChildren()` (activation), `drawFrameIfNeeded()`, ask again: one child, role `.button`, label `"Increment"`; `accessibilityPerformPress()` returns `true` and the counter reads 1; the window is dirty | fails: no children | leave `AppKitWindow.publishAccessibilityTree` storing rather than forwarding; drop the `onAccessibilityRequest` forward |

---

## Lane 3 — defaults, modifiers, `List`

### `Sources/MetalUI/AXNode.swift` (+~10 lines)

`public var logicalIndex: Int?` on `logicalCount`'s footing (a declared field,
public initializer parameter defaulting to `nil`). `swift package clean` first.

### `Sources/MetalUI/AXSynthesis.swift` — the full rules (`AB-F`, `AB-G`)

Applied only when collecting, in `Frame.registerHandlers(_:at:id:accessibleText:)`
(a new internal overload; the public three-argument one forwards with `nil`):

```
clickable  = handlers.onClick != nil
adjustable = handlers.actions[ObjectIdentifier(AccessibilityAdjustment.self)] != nil
node = declared
if text != nil:
    if node.label == nil and node.value == nil:
        clickable ? (node.label = text) : (node.value = text)      // probe arms 1, 3
    else if node.value == nil and not clickable:
        node.value = node.label; node.label = nil                   // probe arm 10a
    if node.role == .generic: node.role = clickable ? .button : .text
else if node.role == .generic and clickable:
    node.role = .button
emit node if !node.isEmpty or clickable or handlers.isFocusable or adjustable
```

`Text.prepaint` calls the overload with its string. `Box`, `Stack`,
`FrameModifier` and `OnTapModifier` are untouched.

### `AccessibilityTreeBuilder` — button label combination (`AB-G`)

A `.button` node with `label == nil` whose kept descendants are all
non-interactive (no actions, not focusable) takes
`label = descendants' (label ?? value) joined by ", "` in tree order and
publishes no children (probe arm 6: `Button { HStack { Text A; Text B } }` is
one `AXButton` labelled `A, B` with zero children). A descendant that is
interactive leaves the button unlabelled with its children intact — a MetalUI
rule; the probe has no such arm and no SwiftUI claim is made.

### `Sources/MetalUI/List.swift` (+~6 lines)

When `pass.collectsAccessibility`, each realized row `Box` gets
`handlers.axNode = AXNode(logicalIndex: window.lowerBound + offset)`. The
`List`'s own node is unchanged (`container` + `logicalCount`), so the builder
maps it to `.table` and the rows to `.row`.

### New file `Sources/MetalUI/AccessibilityModifiers.swift`

```swift
extension StyledElement {
    public func accessibilityLabel(_ label: String) -> Self
    public func accessibilityValue(_ value: String) -> Self
    public func accessibilityAdjustableAction(
        _ handler: @escaping @MainActor (AccessibilityAdjustmentDirection) -> Void) -> Self
}
```

Each writes one field through `handling`. `accessibilityAdjustableAction` is
`onAction(AccessibilityAdjustment.self)`. Not offered on `Component`, on
`onClick`'s footing (a distributing label would label every top-level node).
`Handlers` gains no member, so `HandlerShape` needs no field; `ModifierTests`'
case list is not extended (these are not layout modifiers).

### Demo (`Sources/MetalUIDemo/main.swift`, a few lines)

Label `CounterPanel.button`'s two squares `"Decrement"` and `"Increment"`
(`.accessibilityLabel` after `.onClick`); nothing else. Without the labels
they would combine to `"-"` and `"+"` (`AB-G`). The human script reads them.

### Lane 3 tests — `Tests/MetalUITests/AccessibilityDefaultsTests.swift` (new)

| test | red before | mutation that must redden it after |
|---|---|---|
| `aTextIsPublishedAsStaticTextWhoseValueIsItsString` (probe arms 1, 3) — `Column { Text("A"); Text("B") }`: two roots, `.staticText`, `value` `"A"`/`"B"`, `label == nil`, no column node | fails: no nodes | put the string in `label`; give `Column` a node |
| `aLabelledTextReportsTheLabelAsItsValueAndAnAdjustableOneKeepsBoth` (arms 10a, 11) — `Text("Hello").accessibilityLabel("Greeting")` → `value "Greeting"`, `label nil`; `Text("vol").accessibilityLabel("vol").accessibilityValue("5")` → `label "vol"`, `value "5"` | does not compile | skip the label-to-value move; apply it when a value is present |
| `aClickableTextIsAButtonLabelledByItsString` — `Text("Go").onClick{}`: `.button`, `label "Go"`, `value nil`, `.press` | fails | keep role `.text` for a clickable text |
| `aClickableContainerCombinesItsTextsIntoOneButtonLabel` (arm 6) — `Row { Text("A"); Text("B") }.onClick{}` → one `.button`, `label "A, B"`, `children == []`; with a focusable child instead, unlabelled with two children | fails | join with `" "`; keep children when combining; combine across an interactive descendant |
| `theAdjustableActionModifierRegistersTheAdjustmentHandler` (arm 11) — `Text("vol").accessibilityAdjustableAction { … }`: published actions `[.increment, .decrement]`; `.increment(id)` runs the closure with `.increment` | does not compile | register the handler under a different `Action` type; write the direction constant |
| `aScrolledListPublishesItsLogicalCountAndItsRealizedRowsWithTheirIndices` — 500-row `List`, `rowHeight` 28, offset seeded to 28 × 40: the list node is `.table`, `rowCount 500`; its children are `.row` with `rowIndex` equal to the realized window's indices, first `>= 38`; every row's text is its child | fails: rows emit nothing | `logicalIndex = offset` (no `lowerBound`); drop `rowCount` |
| `publishedNodeCountTracksRealizedRowsNotDataCount` — the same viewport over 500 and 5,000 rows publishes the same node count, and `buildCount`/`publishCount` equal 1 per drawn frame | fails | build a row node per datum rather than per realized row |
| `synthesizedNodesCostNothingWhileNoClientIsActive` — a non-collecting frame of `Text`, a clickable box and a 500-row `List`: `axNodes.count == 1` (the list's own, today's contract), no `$ax` slot under any text or row id; the same collecting: slots present | fails to compile | make `Text.prepaint` or `List` synthesize regardless of the flag |

### The human look (open when this track ends)

Written into `docs/record/12-accessibility-bridge.md` in lane 3 and run by a
human with VoiceOver; the suite cannot see what VoiceOver says. The draft is in
that file now.

---

## Test and count accounting

About 35 new tests: 12 in lane 1, 14 in lane 2 (13 platform, 1 end-to-end), 8 in lane 3 (counts are
design-time and go stale the moment a test lands; the record re-measures).
Goldens: 97, unchanged. Typecheck guards: none added. Every count the lanes
report is re-taken, per CLAUDE.md, from the summary line of an unfiltered run.
