# Accessibility bridge design

**Milestone:** SwiftUI alignment plan task 12, **accessibility-bridge half only**
(`plans/2026-09-12-swiftui-alignment.md`). Gesture composition, button
semantics, disabled behaviour and content shapes wait for task 9 and are not
here.

**Status (2026-09-15): lanes 1, 2 and 3 implemented and verified (lane 2 and
lane 3 each by two independent verifier rounds; the track ends at `531b6fc`
plus the record's closing commit, 1141 tests, 97 goldens unchanged). Open: the
human VoiceOver look (script in the record), ten unpinned lane-2 rules the
second verifier found (record), and the merge contract's joint work below. Plan
task 12 is not complete: its interaction half waits for task 9, and the bridge
is not yet validated with VoiceOver.** Written
against `f64e58a` on `feat/ax-bridge`, revised after one critic round, and
revised again after a second critic round that followed lane 1. Lane 1's
deviations from the text below are marked **"Lane 1 as built"** in place and
ruled in `AB-AA`; its red runs and mutations are in the record. Changes the
second round made are marked **"Second critic round"** in place. Lane 2's
deviations are marked **"Lane 2 as built"** and ruled in `AB-AE` and `AB-AF`.
Lane 3's are marked **"Lane 3 as built"** and ruled in `AB-AG`.
Rulings are
prefixed **`AB-`** and lettered, in
`docs/superpowers/2026-09-15-accessibility-bridge-decisions.md`; a bare `AB-3`
is a typo, not a citation. That doc's last two sections map each critic's
findings (fourteen, then fifteen) to the ruling that applies or rejects them.

**SwiftUI evidence** is three committed probes, each carrying its recorded
output in its header:

- `docs/probes/swiftui-accessibility-bridge.swift`. "Arm N" means its arm N.
- `docs/probes/swiftui-accessibility-bridge-rules.swift`, the first critic
  round. "Arm Rn" or "arm Q" means its arms.
- `docs/probes/swiftui-accessibility-bridge-critic2.swift`, the second critic
  round. "Arm Cn", "Pn" or "En" means its arms.

**AppKit evidence** is five more (the last two added by lane 2, `AB-AE`):

- `docs/probes/appkit-accessibility-overrides-typecheck.swift`: the
  re-runnable typecheck of every AppKit override spelling lane 2 uses, with a
  negative control;
- `docs/probes/appkit-voiceover-signal-isolation.swift`: the signal's
  isolation (`AB-AB`), read by grepping for `warning:`;
- `docs/probes/appkit-accessibility-activation-clients.swift`: what an
  out-of-process client reaches on a host view (`AB-B`);
- `docs/probes/appkit-accessibility-override-isolation-typecheck.swift`: the
  overrides' isolation, compiled to SIL, with three controls;
- `docs/probes/appkit-accessibility-override-isolation.swift`: the thread an
  out-of-process request arrives on, and the helper's off-main fallback.

## What exists today, and what is wrong with it

Design spec §9 specified emission, identity, bridge, focus and virtualization.
The tombstones-and-AX milestone built emission and identity and stopped:

- `Frame.axNodes` and `Frame.axNode(for:)` are written every frame and **read
  by nothing** (record §05).
- A node is emitted only when `Handlers.axNode` is declared non-empty. No
  public API declares one except `List`, which always emits its own `container`
  node with `logicalCount = data.count`. A `Text`, an `onClick` box and a
  focusable box expose nothing.
- `AXNode.children` is always `[]` (ruling `TB-M`). A container has no child
  ids to pass, and order cannot be recovered from `axNodes`' keys.
- **`Frame.emitAXNode` stores the untranslated `bounds`**
  (`Frame.swift:745-746`), while `insertHitbox` adds `activeOffset`
  (`Frame.swift:564-567`). By reading, a node inside a scrolled `ScrollView`
  therefore reports its content-space rect, not where it is on screen. Lane
  1's `aNodeInsideAScrolledScrollViewReportsItsOnScreenFrame` is the first
  measurement of this.
- The proposal path (`HStack`, `ProposalText`, …) emits nothing
  (plan, "Proposal interaction coverage").
- `MetalHostView` is a plain `NSView`, so AppKit sees one opaque view.

## What this design delivers

Three lanes, implemented **in this order**:

| lane | one line |
|---|---|
| 1. **tree and seam** | per-frame emission **records**, kept only while a client is active and never written to `StateTable`; a platform-neutral `AccessibilityTree` with its geometry split from its structure; hierarchy that honours portals and `display: none`; a two-requirement `PlatformWindow` seam; requests routed back through `Window`'s existing dispatch; the emission-frame fix |
| 2. **AppKit bridge** | `NSAccessibilityElement` objects created **lazily**, when a client reads them, and keyed by node id; the host view as an `AXGroup`; screen frames read at query time; hit testing on the clipped rect; per-instance action gating; a second activation trigger from `NSWorkspace.isVoiceOverEnabled`; coalesced notifications, posted only for elements a client has seen |
| 3. **defaults, modifiers, List** | what a `Text`, an `onClick` element, a focusable element and a `List` row publish without a declaration; `accessibilityLabel`/`accessibilityValue`/`accessibilityAdjustableAction` with SwiftUI's distribution through containers and wrappers; a button's combined label; no rows while a `List`'s window is unbounded; the demo's labels and the human VoiceOver script |

**Why this order.** Lane 2's element objects are a function of lane 1's tree
type, and its tests build trees by hand, so they do not need lane 3. Lane 3's
defaults are only observable through lane 1's builder. Its end-to-end check, a
real VoiceOver look, needs lane 2. If the track runs short, cut lane 3: the
bridge then works for declared nodes and `List`, and `Text` is silent.

## Scope boundaries (ruling `AB-Q`)

**In:** everything in the table above, on the legacy element path (`Box`,
`Column`, `Row`, `Stack`, `Text`, `List`, `ScrollView`, `FrameModifier`, or
`ModifiedElement` after the modifier-composition merge; see `AB-Z`).
`OnTapModifier` routes a press like any other hitbox but **synthesizes no
node** (`AB-Y`).

**Deferred, each with an owner:**

1. **Proposal-path emission.** `ProposalText`, `HStack`/`VStack`/`ZStack`,
   `ProposalScrollView` and `OnTapModifier` emit nothing. Tasks 6, 7 and 11
   port them and reuse the internal `registerHandlers(…accessibleText:)`
   overload from lane 3.
2. **Scroll areas.** There is no `AXScrollArea` role and no
   `accessibilityScrollToVisible`, so **VoiceOver cannot move to a `List` row
   that is not realized** (task 10).
3. **`Stack` order.** SwiftUI lists a `ZStack`'s topmost child first (probe
   arm 4). MetalUI publishes declaration order (`AB-P`, a recorded divergence).
4. **Modal isolation.** Content under a `Deferred` scrim stays in the tree and
   pressable (task 12's interaction half).
5. **Task 9's button half.** `accessibilityHidden`,
   `accessibilityElement(children:)`, traits beyond `selected`/`disabled`,
   custom actions, `AXNode.actions` as a declaration (`AB-H`), and a
   non-button way to absorb clicks (the demo panel, `AB-Y`).
6. **System settings** (Reduce Motion, Increase Contrast): task 13.
7. **iOS/`UIAccessibility`**: task 14. The neutral tree is shaped so a UIKit
   conformer can consume it, and nothing more is claimed.
8. `Frame.axNode(for:)`'s tombstone query stays unread (`AB-D`).
9. Writing the derived hierarchy back into `Frame.axNodes[id].children`
   (`AB-C`).
10. A **third-party virtualized container** cannot publish row indices:
    `AXNode.logicalIndex` is internal (`AB-L`).

## Hard constraints carried from the dispatch

- **Tests.** `swift test --no-parallel` passes with 0 `error:` / 0 `warning:`,
  read from the "Test run with N tests" line.
- **Goldens.** The 97 goldens do not change. This track touches no file under
  `Sources/MetalUILayout/`.
- **Timing.** No test sleeps, and nothing spins a run loop for time.
- **Performance claims are counts, never wall clock:** emission records, built
  trees, structural and geometry publishes, created elements, posted
  notifications, `StateTable.count`.
- **Traps.** A trap, if one is added, is pinned with an exit test.
- **Typecheck guards.** None are planned. A new one would be mutated red once
  under `--build-system native`.
- **SwiftUI claims.** Every one below cites a probe arm.
- **Devices.** A test that opens a real window through `App.openWindow` begins
  with `try #require(MTLCreateSystemDefaultDevice())`, CLAUDE.md's
  CI convention.
- **`swift package clean` before the first test run of lane 1 and of lane 3.**
  Both add stored properties to public types that cross into a test target
  (`AXNode.logicalIndex`, the `PlatformWindow` requirements). CLAUDE.md's
  Build section records that shape as producing impossible failures.

Shared-file edits are kept additive and small. Each is listed per lane with its
line budget, and **"Merge contract"** at the end states the combined form of
every shared function another track also edits (`AB-Z`).

---

## Lane 1 — tree and seam

### New file `Sources/MetalUIPlatform/AccessibilityTree.swift`

Platform-neutral. Imports only `MetalUICore`.

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

/// What a node says and what it can do. No geometry: see AccessibilityGeometry.
public struct AccessibilityNode: Equatable {
    public var role: AccessibilityRole
    public var label: String?
    public var value: String?
    public var isSelected: Bool
    public var isEnabled: Bool
    public var isFocusable: Bool
    public var actions: AccessibilityActions
    public var children: [AccessibilityNodeID]
    public var rowCount: Int?          // AXRowCount for a .table (AB-L)
    public var rowIndex: Int?          // AXIndex for a .row (AB-L)
    public init(role:label:value:isSelected:isEnabled:isFocusable:actions:children:rowCount:rowIndex:)
}

/// Where a node is. Window content space: logical points, top-left origin,
/// scroll offset applied.
public struct AccessibilityGeometry: Equatable {
    public var frame: Bounds<Pixels>          // NOT clipped: accessibilityFrame (AB-E)
    public var visibleFrame: Bounds<Pixels>   // frame ∩ active clip: hit testing (AB-W)
    public init(frame:visibleFrame:)
}

public struct AccessibilityTree: Equatable {
    public var roots: [AccessibilityNodeID]
    public var nodes: [AccessibilityNodeID: AccessibilityNode]
    public var geometry: [AccessibilityNodeID: AccessibilityGeometry]
    public var focused: AccessibilityNodeID?
    public init(roots:nodes:geometry:focused:)
    public static let empty: AccessibilityTree
    /// `roots`, `nodes` and `focused` equal; `geometry` ignored (AB-K).
    public func hasSameStructure(as other: AccessibilityTree) -> Bool
}

/// What an accessibility client asked the window to do. It has `onInput`'s
/// shape: the answer says whether anything handled it.
public enum AccessibilityRequest: Equatable {
    case activate                       // a client is present (AB-B)
    case press(AccessibilityNodeID)
    case increment(AccessibilityNodeID)
    case decrement(AccessibilityNodeID)
    case focus(AccessibilityNodeID)
}
```

`Sendable` is deliberately not declared. Every value crosses only between
`@MainActor` code, and `AnyHashable`'s conformance would have to be argued.

**Lane 1 as built (`AB-AA`).** `AccessibilityRole` and `AccessibilityActions`
do declare `Sendable`: each carries a `static let`, which Swift 6 rejects on a
non-`Sendable` public type, and neither holds more than a tag.
`AccessibilityTree.empty` is a computed `static var` for the same reason.
`AccessibilityNode.init` defaults every parameter but `role`.

### `Sources/MetalUIPlatform/Platform.swift` (+2 requirements, ~15 lines with docs)

```swift
/// Fired by the platform when an accessibility client asks for something.
var onAccessibilityRequest: ((AccessibilityRequest) -> Bool)? { get set }
/// Replaces the tree the platform exposes. Called only after `.activate`,
/// and only when the tree differs from the last one published (AB-M).
func publishAccessibilityTree(_ tree: AccessibilityTree)
```

**No default implementations** (`AB-R`). A conformer that forgets either fails
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

### New file `Sources/MetalUI/AXEmission.swift`

```swift
/// One `registerHandlers` call that has something to say, recorded ONLY while
/// collecting. A record, not an emission: it writes neither `Frame.axNodes`
/// nor `StateTable` (AB-U).
struct AXEmission {
    let id: GlobalElementID
    let declared: AXNode             // handlers.axNode as written, logicalIndex included
    let text: String?                // lane 3: Text's string
    let isClickable: Bool            // handlers.onClick != nil
    let isEnabled: Bool              // true on this branch; the environment merge fills it (AB-Z)
    let synthesizes: Bool            // false for OnTapModifier (AB-Y)
    let portal: Int                  // 0 outside every Deferred; else that portal's ordinal (AB-V)
    let geometry: AccessibilityGeometry
}
```

### `Sources/MetalUI/Frame.swift` (~45 lines)

1. `init(…, collectsAccessibility: Bool = false)`, stored as a `let`.
2. `private(set) var axEmissions: [AXEmission] = []`, appended **only when
   `collectsAccessibility`**.
3. **The emission-frame fix.** `emitAXNode` stores `bounds` translated by
   `activeOffset`, exactly as `insertHitbox` does (`AB-E`). This is
   unconditional and changes only the stored rect.
4. **`registerHandlers`' AX block.** Its public signature is unchanged. An
   internal overload adds `accessibleText: String? = nil` and
   `synthesizesAccessibility: Bool = true`, and the three-argument form
   forwards to it. The block:

   ```swift
   var declaration = handlers.axNode
   declaration.logicalIndex = nil               // a row hint is not a declaration (AB-L)
   if !declaration.isEmpty {                    // today's gate, unchanged in effect
       emitAXNode(handlers.axNode, at: bounds, id: id, children: [])
   }
   if collectsAccessibility, !isAccessibilitySuppressed(for: id) {
       let adjustable = handlers.actions[ObjectIdentifier(AccessibilityAdjustment.self)] != nil
       let hasSomethingToSay = !declaration.isEmpty || handlers.axNode.logicalIndex != nil
           || (synthesizesAccessibility
               && (handlers.onClick != nil || handlers.isFocusable || adjustable || accessibleText != nil))
       if hasSomethingToSay { axEmissions.append(AXEmission(…)) }
   }
   ```

   **Lane 1 as built (`AB-AA`).** `AXNode.logicalIndex` does not exist until
   lane 3, so lane 1 has no strip and tests `!handlers.axNode.isEmpty`
   directly; lane 3 adds the field, the strip and the `logicalIndex` term
   together. The overload's two parameters are required on `Frame` and
   defaulted only on `PrepaintPass`.

   With no client active, the frame does what it does today, plus one `Bool`
   read. `noConformerEmitsAnAXNodeItDidNotDeclare` stays true as written,
   whether or not a client is active: a synthesized node never reaches
   `axNodes`.
5. **Portals (`AB-V`).** While collecting, `pushLayer`/`popLayer` maintain
   `portalStack: [Int]` from a per-frame `portalCount`. A record's `portal` is
   `portalStack.last ?? 0`.
6. **Suppression scopes (`AB-O`, `AB-X`).**
   `withAccessibilitySuppressed(except: GlobalElementID?, _ body:)` increments
   a depth. `isAccessibilitySuppressed(for:)` is true when the depth is
   non-zero and `id` is not the outermost scope's exception. Both are no-ops
   while not collecting.

### `Sources/MetalUI/ElementGroup.swift` (+4 lines, `AB-O`)

In `Element.prepaintGroup`, while `pass.frame.collectsAccessibility`, if
`pass.frame.style(layout.node).display == .none`, the `prepaint` call runs
inside `pass.frame.withAccessibilitySuppressed(except: nil)`. This is the
"one check in `Element`'s group walk" that `Box.focusable()`'s doc names, and
it is applied to accessibility only.

**Second critic round (`AB-AD`).** `Frame.render` applies the same check to the
root's `prepaint`, which does not go through `prepaintGroup`. After the
modifier-composition merge, `ModifiedElement`'s layer loop applies it at its
first hidden layer (`AB-Z` item 4).

### `Sources/MetalUI/Passes.swift` (+~8 lines)

- `LayoutPass.collectsAccessibility` and `PrepaintPass.collectsAccessibility`,
  internal, forwarding to `frame`.
- The internal
  `PrepaintPass.registerHandlers(_:at:id:accessibleText:synthesizesAccessibility:)`
  overload, which `Text.prepaint` (lane 3) and `OnTapModifier.prepaint`
  (lane 3) call.

### New file `Sources/MetalUI/AccessibilityTreeBuilder.swift`

```swift
@MainActor
enum AccessibilityTreeBuilder {
    static func build(emissions: [AXEmission],
                      focused: GlobalElementID?,
                      hitboxes: [Hitbox],
                      focusRegistry: FocusRegistry) -> AccessibilityTree
}
```

Lane 1's algorithm (`AB-C`, `AB-H`, `AB-O`, `AB-V`):

1. **Collect.** Walk `emissions` and keep one record per id, at the position of
   its first occurrence and with the content of its last. Two siblings given
   the same `.id(_:)` mint one `GlobalElementID`, and today's `axNodes` keeps
   the last write. **No zero-area filter**: arms R6 and R11 publish zero-height
   labelled views, and hidden content never records.
2. **Parent.** The parent is the nearest `GlobalElementID.parent` ancestor
   that is kept **and has the same `portal`**. If there is none, the node is a
   root. A child appends to its parent's `children` in record order. Do this
   in a second pass, so that a parent recorded after its child still works.
3. **Actions are derived, not declared.**
   - `.press` iff `hitboxes` holds an entry for the id with
     `handlers.onClick != nil`. So `allowsHitTesting(false)` removes it, as it
     removes the click.
   - `.increment`/`.decrement` iff
     `focusRegistry.actionHandler(for:type: ObjectIdentifier(AccessibilityAdjustment.self))`
     is non-nil.
4. **Focus.** `isFocusable` comes from `focusRegistry.isFocusable`. `focused`
   is the window's read-back focus if that id was kept, else `nil`.
5. **Role map.**

   | condition | role |
   |---|---|
   | `logicalCount != nil`, **whatever the declared role** (`AB-L`, arm R16) | `.table` |
   | `logicalIndex != nil` | `.row` |
   | `button` | `.button` |
   | `text` | `.staticText` |
   | `image` | `.image` |
   | `generic`, `container` | `.group` |

   On lane 1 alone, a `generic` node that is clickable is `.button`.
   **Lane 1 as built:** the `.row` line waits for lane 3's `logicalIndex`;
   "clickable" is `record.isClickable` (`handlers.onClick`), not `.press`, so
   a button under `allowsHitTesting(false)` stays a button with no press.
   **Traits:** `.selected` sets `isSelected`. `.disabled`, or
   `record.isEnabled == false`, sets `isEnabled = false`. `.updatesFrequently`
   has no AppKit counterpart and is dropped.
6. **Geometry** is copied from the record.
7. Lane 3 inserts distribution, text resolution and button combination between
   steps 2 and 5.

### New file `Sources/MetalUI/AccessibilityAdjustment.swift`

```swift
public enum AccessibilityAdjustmentDirection: Equatable, Sendable { case increment, decrement }
public struct AccessibilityAdjustment: Action {
    public let direction: AccessibilityAdjustmentDirection
    public init(direction: AccessibilityAdjustmentDirection)
}
```

Lane 1's tests register a handler with the existing `onAction(AccessibilityAdjustment.self)`.

### New file `Sources/MetalUI/WindowAccessibility.swift`

```swift
@MainActor
final class WindowAccessibility {
    private(set) var isActive = false
    private(set) var lastPublished = AccessibilityTree.empty
    private(set) var buildCount = 0          // test observable, AB-M
    private(set) var publishCount = 0        // test observable, AB-M
    private(set) var lastEmissionCount = 0   // test observable, AB-M; written every frame
    func activate() -> Bool                  // true only on the first call
    func frameDidRender(emissionCount: Int,
                        _ tree: @autoclosure () -> AccessibilityTree,
                        to platformWindow: any PlatformWindow)
}

extension Window {
    func handleAccessibilityRequest(_ request: AccessibilityRequest) -> Bool
}
```

`frameDidRender` sets `lastEmissionCount` unconditionally. It builds only when
active, and publishes only when the tree is `!=` `lastPublished`. Geometry
counts toward that comparison. Lane 2 makes a geometry-only publish cheap on the
platform side (`AB-K`).

`handleAccessibilityRequest` (`AB-B`, `AB-H`, `AB-J`):

- `.activate`: the first time, set active and `setNeedsRedraw()`. Return
  `true`.
- `.press(id)`: unwrap `id.base as? GlobalElementID` and find the **last**
  `lastHitboxes` entry with that id and an `onClick`. Run it, `setNeedsRedraw()`
  and return `true`. Otherwise return `false`.
- `.increment`/`.decrement`: run `lastFocusRegistry.actionHandler(…)` for
  `AccessibilityAdjustment` with the direction, dirty the window and return
  `true`.
- `.focus(id)`: if `lastFocusRegistry.isFocusable(gid)`, call `focus(gid)` and
  return `true`. Otherwise return `false` and leave focus unchanged.

### `Sources/MetalUI/Window.swift` (+~8 lines)

1. `let accessibility = WindowAccessibility()`.
2. In `init`, beside `onInput`:
   `platformWindow.onAccessibilityRequest = { [weak self] in self?.handleAccessibilityRequest($0) ?? false }`.
3. `Frame(…, collectsAccessibility: accessibility.isActive)`.
4. After the focus read-back and the `hasActiveAnimations` assignment, and
   before `renderer.upload`:
   `accessibility.frameDidRender(emissionCount: frame.axEmissions.count, AccessibilityTreeBuilder.build(…), to: platformWindow)`.

### Lane 1 tests — `Tests/MetalUITests/AccessibilityTreeTests.swift` (new)

**Lane 1 as built: 15 tests, not 14 (`AB-AA`).** The table's fourteen plus one
new test, and four of the fourteen strengthened, because a mutation the table
did not name survived or a named one could not redden its test:

- `declaredRolesLabelsValuesAndTraitsReachThePublishedNode` (new): the
  builder's `.staticText`/`.image`/`.group` roles, its `value` copy and both
  trait mappings, one distinct value per field.
- `aNodeInsideAScrolledScrollViewReportsItsOnScreenFrame` also asserts
  `hasSameStructure` true across a scroll and false across a label change.
- `hiddenContentIsNot…` also focuses the hidden box (it is focusable, and
  `hidden()` keeps focus) and asserts the published `focused` is `nil`.
- `publishedFocusIs…` gains a last arm, `window.focus(c)` then a draw: the
  frame clears it and the published `focused` is `nil`. **Without it, this
  table's own mutation ("build `focused` from the handed-in focus") cannot
  redden the test**: in every earlier arm the handed-in and read-back focus
  are equal.
- `anUnchangedFrameIsNotRepublished` changes its `@State` label by pressing
  the element through `.press`, from a `Component`.
- `anInactiveWindowBuildsAndPublishesNothing` compiles against the red
  skeleton and is green there; its evidence is its two mutations.

**Second critic round: 18 tests.** Committed after lane 1's record, and
re-taken against all 39 mutations in the record:

- `eachLiveHandlerAloneMakesAnUndeclaredElementRecord` (new): a click target,
  a focusable box and an adjustable box, none declaring a node, each record; a
  plain sized box does not. Hunting mutants H05 and H06 (drop the focusable or
  the adjustment term from synthesis) survived every earlier fixture.
- `childrenFollowDeclarationOrderWhereIDsAloneCannot` uses six children in two
  orders, one the other's reverse (M08 survived the two-child fixture twice).
- `portalContentIsARoot…` adds a sibling declared after the `Deferred`, which
  is the ancestor's child only if the portal is popped.
- `aPressRequestRuns…` adds two siblings sharing an `.id`: a press runs the
  last registration (H02).
- `hiddenContentIsNot…`'s hidden box is itself a click target, so excepting it
  from its own suppression is observable (H14), and the duplicated id
  straddles the divider.
- `aNodeInsideAScrolledScrollView…` also pins root order and focus as
  structure; `anIncrementRequest…` pins that an adjustment dirties.
- **`aHiddenRootPublishesNothing`** (new, `AB-AD`): `Frame.render` over a
  collecting frame whose root is `Box { declared, sized, clickable box }.hidden()`
  records nothing; the same root without `hidden()` records the inner box. Red
  before `Frame.render`'s check.
- **`aHiddenInnerModifierLayerSuppressesEverythingInsideIt`** (new, `AB-Z` item
  4): a declared, sized, clickable box written `.padding(4).hidden().padding(4)`
  records nothing, and `.padding(4).padding(4)` records it. Green on this
  branch by construction; it is the modifier-composition merge's check.

**Footing.** Frame-level tests use `Frame.render` over a bare `Frame`, which is
`AXEmitSiteTests`' footing and needs no Metal device. Window-level tests use
`makeFakeWindow`.

**Fixture rules.** Every element a published tree must contain has an
**explicit size**: `Box().onClick {}` with no size is 0×0 under `EP-8`. Every
lookup of a node a later assertion reads is `try #require`d.

| test | red before | mutation that must redden it after |
|---|---|---|
| `aFrameThatDoesNotCollectRecordsNothingAndSynthesisWritesNoRetentionSlot` — `Box().width(40).height(20).onClick{}.focusable()`. Non-collecting frame: `axNodes`, `axEmissions` empty, no `$ax` slot under the box. Collecting frame: `axEmissions.count == 1`, `axNodes` **still** empty, **still** no `$ax` slot, and `stateTable.count` equal to the non-collecting frame's | does not compile (`collectsAccessibility`, `axEmissions`) | record regardless of the flag; route a synthesized record through `emitAXNode` (slot appears, counts differ) |
| `anInactiveWindowBuildsAndPublishesNothing` — fake window, three drawn frames of a tree with a `List` and a sized `onClick` box, no request: `publishedAccessibilityTrees.isEmpty`, `accessibility.buildCount == 0`, **`accessibility.lastEmissionCount == 0`** | does not compile | pass `collectsAccessibility: true` in `Window` (`lastEmissionCount` becomes non-zero); drop the `isActive` guard in `frameDidRender` (`buildCount` rises) |
| `anActivationRequestDirtiesACleanWindowAndItsNextFramePublishes` — draw until clean. `.activate` returns `true` and sets `needsRedraw`. Draw: exactly one published tree, and it `#require`s a node for the 40×20 button. A second `.activate` does not dirty | does not compile | delete `setNeedsRedraw()` in `.activate` (no publish); make `activate()` return `true` every time (the second call dirties) |
| `childrenFollowDeclarationOrderWhereIDsAloneCannot` — `TB-M`'s own counterexample: a declared container over sized `Box().id("x")` and `Box().id("y")`, then the same with the two swapped, each child declaring a node. `children` reads `[x, y]`, then `[y, x]` | does not compile | reverse the record order in the builder; build `children` by iterating a dictionary |
| `aNodesParentIsItsNearestEmittingAncestor` — declared container `Box { Column { Box(declared) } }`: `roots == [box]`, `box.children == [inner]`, `Column` absent | does not compile | use `id.parent` without walking (the inner node becomes an orphan root) |
| `portalContentIsARootEvenWhenDeclaredInsideAnEmittingAncestor` (`AB-V`) — a sized declared `.button` box containing `Deferred { Box(declared "Tip").width(30).height(10) }`: `roots == [button, tip]`, `button.children == []` | does not compile | ignore `portal` when finding the parent (tip becomes the button's child) |
| `aNodeInsideAScrolledScrollViewReportsItsOnScreenFrame` — `ScrollView` 100pt tall over 400pt of content, `ScrollState.offset` seeded to 40 (`DeferredTests.swift:387`'s spelling), a declared 20pt box at content y = 100. **Written first as a Frame-only test that compiles on `f64e58a`:** `frame.axNodes[id].frame.origin.y == 60`, **red before: reads 100**. After lane 1, extended with: the published geometry's `frame.origin.y == 60`; and a second box at content y = 0 has `frame.origin.y == -40`, with `visibleFrame` height 0 (fully clipped) | red (100) for the Frame half; the published half does not compile | delete the `activeOffset` translation in `emitAXNode` (Frame half); build `visibleFrame` from `frame` (clipped half) |
| `aPressRequestRunsOnClickThroughTheLastFramesHitboxes` — two 40×20 boxes, both **declaring** a node (`AXNode(role: .button, label: …)`), only one clickable. `try #require` both published nodes. Press the clickable one: returns `true`, counter 1, `needsRedraw`. Press the other: `false`, counter unchanged, and its node's `actions` has no `.press` | does not compile | return `true` from `.press` without running the handler; derive `.press` for every node (the declared non-clickable one gains it) |
| `aPressIsRefusedWhereHitTestingIsDisabled` — a test-local wrapper element whose `prepaint` calls `pass.allowsHitTesting(false) { … }` around a sized, declared, clickable `Box`. `try #require` its node: no `.press`, the request returns `false`, the closure does not run. The same box without the wrapper is pressable | does not compile | route press through the element's `Handlers` instead of `lastHitboxes` |
| `publishedFocusIsTheWindowsFocusAndAFocusRequestMovesIt` — sized focusable `a` and `b`, plain declared `c`. `window.focus(a)`, draw: `tree.focused == a`. `.focus(b)` returns `true`; draw: `focused == b` and `window.focusedElement == b`. `.focus(c)` returns `false` and focus stays `b` | does not compile | build `focused` from the handed-in focus rather than the read-back; drop the `isFocusable` check |
| `anUnchangedFrameIsNotRepublished` — active, draw, `setNeedsRedraw()`, draw: `publishCount == 1`, `buildCount == 2`. A `@State` label change and a third draw: `publishCount == 2` | does not compile | remove the `!=` comparison |
| `hiddenContentIsNotPublishedButAZeroHeightNodeIsAndADuplicatedIDIsPublishedOnce` (`AB-O`, arms R6, R9) — `Column { Box { Box(declared "in").width(10).height(10) }.width(20).height(20).hidden(); Box(declared "divider").width(20).height(0); Row { Box(declared).id("x"); Box(declared).id("x") } }`: `"in"` absent; `"divider"` present with height 0; `x` published once, once among its parent's children | does not compile | remove the `display: .none` suppression (`"in"` appears at `(0,0) 0×0`); restore a zero-area filter (`"divider"` vanishes); remove the seen-set |
| `anIncrementRequestRunsTheAdjustmentHandler` — a sized `Box().onAction(AccessibilityAdjustment.self) { … }` that records directions: published actions `[.increment, .decrement]`; `.increment(id)` and `.decrement(id)` return `true`, `true`, recorded in that order. On a sized declared box with no handler, both return `false` | does not compile | swap the two directions; advertise adjustment for every node |
| `aLabelledListIsStillATable` (`AB-L`, arm R16) — a 500-row `List` whose `handlers.axNode.label = "Contacts"` is set through `handling` (`@testable`): role `.table`, label `"Contacts"`, `rowCount == 500` | does not compile | map `.table` only from `container` with `logicalCount` (the labelled node's role stays `generic`, so it becomes `.group`) |

---

## Lane 2 — AppKit bridge

### Lane 1 files lane 2 extends (second critic round, `AB-W`)

- `AccessibilityGeometry` gains `public var layer: Int` and
  `public var order: Int`, defaulted to 0 in its initializer.
- `Frame.accessibilityGeometry(for:)` fills `layer` from `activeLayer`.
- `AccessibilityTreeBuilder` fills `order` from the kept record's index in its
  `order` array (first occurrence).
- A lane-1 test pins both: `portalContentIsARoot…`'s tip has `layer ==
  Frame.rootLayer` and the button `layer == 0`, and `order` rises through
  `childrenFollowDeclarationOrder…`'s six children. Mutations: fill `layer`
  with 0; fill `order` with 0.

### New file `Sources/MetalUIPlatform/AccessibilityTreeChanges.swift`

A pure structural diff. It is neutral, so it is testable without AppKit and
reusable by a UIKit conformer. Called only when `hasSameStructure` is `false`.

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

### New file `Sources/MetalUIPlatform/AppKit/AppKitAccessibility.swift`

```swift
@MainActor protocol AccessibilityNotificationPosting: AnyObject {
    func post(_ notification: NSAccessibility.Notification, for element: Any)
}
@MainActor final class SystemAccessibilityNotificationPoster: AccessibilityNotificationPosting
    // NSAccessibility.post(element:notification:)

/// Whether a screen reader is known to be running (AB-B's second trigger).
@MainActor protocol AccessibilityClientSignal: AnyObject {
    /// Calls `handler` with the current value before returning, then on every
    /// change, possibly after a main-actor hop (AB-AB).
    func observe(_ handler: @escaping @MainActor (Bool) -> Void)
}
@MainActor final class VoiceOverSignal: AccessibilityClientSignal
    // AB-AB, exactly the spelling docs/probes/appkit-voiceover-signal-isolation.swift
    // typechecks with 0 `warning:` lines:
    //   observation = NSWorkspace.shared.observe(\.isVoiceOverEnabled, options: [.new]) { _, change in
    //       let value = change.newValue ?? false
    //       Task { @MainActor in handler(value) }
    //   }
    //   handler(NSWorkspace.shared.isVoiceOverEnabled)      // synchronous, after observing
    // No MainActor.assumeIsolated. NOT `.initial` inside the KVO closure: that
    // spelling warns [#ActorIsolatedCall], and -warnings-as-errors exits 0 on it.

@MainActor final class AppKitAccessibilityBridge {
    weak var hostView: NSView?
    var poster: any AccessibilityNotificationPosting
    var onRequest: ((AccessibilityRequest) -> Bool)?
    init(signal: any AccessibilityClientSignal, poster: any AccessibilityNotificationPosting)
    private(set) var isActive: Bool
    private(set) var tree: AccessibilityTree
    /// Only elements a client has been handed (AB-X). Never pre-populated.
    private(set) var elements: [AccessibilityNodeID: AppKitAccessibilityElement]
    private(set) var parents: [AccessibilityNodeID: AccessibilityNodeID]
    private(set) var createdElementCount: Int      // test observable
    private(set) var structuralPublishCount: Int   // test observable
    private(set) var geometryPublishCount: Int     // test observable
    func activateIfNeeded()
    func publish(_ tree: AccessibilityTree)
    func element(for id: AccessibilityNodeID) -> AppKitAccessibilityElement   // vends, creating once
    func rootElements() -> [Any]
    func hitTest(screenPoint: NSPoint) -> Any?
    func focusedElement() -> Any?
    func screenFrame(forContentRect rect: Bounds<Pixels>) -> NSRect
}

@MainActor final class AppKitAccessibilityElement: NSAccessibilityElement {
    let id: AccessibilityNodeID
    weak var bridge: AppKitAccessibilityBridge?
    private(set) var lastNode: AccessibilityNode
    private(set) var lastGeometry: AccessibilityGeometry
    private(set) var isDetached: Bool
    // overrides, each reading the bridge's current tree (or lastNode/lastGeometry once detached):
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
    override func accessibilityHitTest(_ point: NSPoint) -> Any?  // activate; greatest (layer, order) visible
    override var accessibilityFocusedUIElement: Any? { get } // does NOT activate (AB-B); focused or self
}
```

**Lane 2 as built (`AB-AE`, `AB-AF`).**

- **Every override above is nonisolated**, because AppKit's `NSAccessibility`
  protocol and `NSAccessibilityElement` carry no main-actor annotation. Each
  body runs through `mainActorAnswer(_:fallback:_:)`, which answers on the main
  thread and returns a fallback, running nothing, off it. The element's logic
  is in `@MainActor` members the overrides hand `self` to. The typecheck probe
  below could not see this: its bodies were constants.
- **`AccessibilityRequest` is ambiguous** in any file that imports `AppKit`
  beside `MetalUIPlatform` (`Accessibility.framework` exports the same Swift
  name); tests qualify it. A rename is left to the integration step.
- `isAccessibilitySelectorAllowed` also offers row attributes only on tables
  and rows; `parents` is rebuilt on every structural publish, active or not;
  an element's last node and geometry are seeded at creation.
- **18 platform tests**: `anOffMainThreadQueryAnswersNothingAndDoesNotTrap`, an
  exit test, is added.
- **Two mutation predictions below were wrong, measured.** In
  `layoutChangedIsPostedOncePerClientRead`, "the third step posts 0" is the
  mutant whose children read does not re-arm the flag; never resetting it posts
  11 at the second step. In `aHeldElementWhoseIDIsAdoptedPressesTheAdopter`,
  skipping the detach cannot make arm 2's press run `second`: `Window` finds no
  hitbox for the vanished id; the arm reddens on its parent assertion instead.
- **The arm-Q end-to-end test calls the host view's `mouseDown`/`mouseUp`
  after `sendEvent`**, with a control that every event arrived: in the test
  process AppKit spends a synthesized click on activating the inactive app.

Every override spelling above compiles in
`docs/probes/appkit-accessibility-overrides-typecheck.swift`, with
`xcrun swiftc -typecheck -swift-version 6 -warnings-as-errors`: exit 0. Its
negative control, `accessibilityFocusedUIElement` spelled as a method, fails
with "method does not override any method from its superclass". **That probe
never calls a signal handler, so its exit status says nothing about the
signal's isolation** (second critic round): the signal's spelling is checked by
`appkit-voiceover-signal-isolation.swift`, by grepping for `warning:`.

**Ownership (`AB-D`).**

| holder | holds | strength |
|---|---|---|
| `AppKitWindow` | the bridge | strong |
| `MetalHostView.accessibilityBridge` | the bridge | strong |
| the bridge | `hostView` | weak |
| the bridge | its `elements` | strong, until detach |
| an element | the bridge | weak |

A detached element is retained only by whichever client still holds it, and
there is no cycle. `MetalHostView` gains that one stored property in its class
body. `AppKitWindow` owns the bridge, built with its signal and
`SystemAccessibilityNotificationPoster()`, and sets it on the host view.
`onAccessibilityRequest` and `publishAccessibilityTree` forward to the bridge.
`hostView` loses `private` so platform tests can reach it.

**How a test forces the signal (`AB-AC`, second critic round).**

- `AppKitWindow.init(device:title:size:accessibilitySignal:)`, internal; the
  existing three-argument init is removed rather than kept beside it.
- `AppKitPlatform` gains an internal
  `init(device:accessibilitySignal: @escaping @MainActor () -> any AccessibilityClientSignal)`;
  the public `init(device:)` delegates with `{ VoiceOverSignal() }`, and
  `openWindow` passes `accessibilitySignal()` through.
- `App.openWindow` is unchanged and cannot pass one, so the end-to-end tests
  build `AppKitPlatform(device:accessibilitySignal:)` themselves, open the
  platform window, and construct `Window(platformWindow:renderer:startsDisplayLink:content:)`
  over it, as `makeFakeWindow` does.

**Behaviour.**

- **Activation (`AB-B`).** There are two triggers, and either sends
  `.activate` exactly once per bridge:
  - the host's `accessibilityChildren` or `accessibilityHitTest`;
    **`accessibilityFocusedUIElement` is not a trigger** (second critic round:
    a focus-polling utility reaches it, measured);
  - the signal reporting `true`: synchronously during `observe` at bridge
    creation, or later through its hop (`AB-AB`). **At creation nobody is
    listening yet** (`Window.init` assigns `onAccessibilityRequest` after
    `AppKitWindow.init` built the bridge), so the bridge records `isActive` and
    sends the pending `.activate` from `onRequest`'s `didSet`, once.
- **Lazy identity (`AB-D`, `AB-X`).**
  - **Created on read.** An element is created the first time the bridge hands
    it to a client: through the host's children, hit test or focused element,
    or through an element's parent, children, rows or visible rows. It is
    stored in `elements`, and `createdElementCount` is incremented.
  - **`publish`** never creates an element. The one exception is focus: when
    focus changes, the bridge vends the element it posts
    `.focusedUIElementChanged` on.
  - **A removed id.** If `elements` holds an element for an id that is no
    longer in the tree, that element is detached and dropped from `elements`.
    It then answers:
    - `accessibilityParent() == nil`;
    - children `[]`;
    - `isAccessibilitySelectorAllowed` `false` for the perform selectors, and
      every perform returns `false`;
    - its last role, label and value (probe arm 12);
    - `accessibilityFrame()`: its last content rect, converted through the host
      view while the view is alive, `.zero` once it is gone (arm 12 reads the
      removed node's last frame).
  - **An id that returns** gets a new object.
- **Frames (`AB-E`).** `accessibilityFrame()` computes at read time:
  `window.convertToScreen(hostView.convert(localRect, to: nil))`. The host view
  is flipped, so no manual flip. Nothing screen-space is cached.
- **Parent.** The parent node's element, or the host view for a root.
- **Actions (`AB-H`).** `isAccessibilitySelectorAllowed` answers per instance
  from `node.actions`. A perform method sends the request and returns its
  answer. A disallowed one returns `false` without sending.
- **Focus (`AB-J`).** `isAccessibilityFocused()` is `tree.focused == id`.
  `setAccessibilityFocused(true)` sends `.focus(id)`, and `false` is ignored.
- **Rows (`AB-L`).**
  - A `.table` answers `accessibilityRowCount` from `rowCount`.
  - `accessibilityRows` is its `.row` children.
  - `accessibilityVisibleRows` is those whose `visibleFrame` has non-zero area.
  - A `.row` answers `accessibilityIndex` from `rowIndex`.
- **Hit test (`AB-W`).** Among every published element whose
  **`visibleFrame`** contains the point, the one with the greatest
  `(geometry.layer, geometry.order)`: click dispatch's own ranking. If none
  does, the host view. Before activation it activates and answers the host view.
- **Publish (`AB-K`).**
  1. If `!isActive`, store the tree and return.
  2. If `tree.hasSameStructure(as: old)`, store it,
     `geometryPublishCount += 1`, and return. **No element is touched and
     nothing is posted.**
  3. Otherwise `structuralPublishCount += 1`, compute
     `AccessibilityTreeChanges`, update `parents`, and post in this order:
     - one `.uiElementDestroyed` per removed id **that had a vended element**;
     - one `.layoutChanged` on the host view, if `structureChanged` **and a
       client has read a children list, hit test or focused element since the
       last `.layoutChanged`** (the read flag; the activating query counts);
     - `.titleChanged` / `.valueChanged` / `.rowCountChanged` per changed id
       **that has a vended element**;
     - if `focusChanged`, one `.focusedUIElementChanged` on the newly focused
       element (vending it), or on the host view when focus clears.

   Nothing is posted for a created element.

### Lane 2 tests — `Tests/MetalUIPlatformTests/AppKitAccessibilityTests.swift` (new)

**Footing.**

- Real `AppKitPlatform` windows. The platform tests may close theirs.
- Trees built by hand.
- A recording poster and a scripted `AccessibilityClientSignal`, both injected.
- Everything is read through the NSAccessibility protocol methods the AX server
  calls, on the host view and on the vended elements.
- No deprecated informal API (it warns), no VoiceOver, no permission.

| test | red before | mutation that must redden it after |
|---|---|---|
| `theHostViewIsAGroupWhoseChildrenAreThePublishedRoots` — two roots: host `isAccessibilityElement()`, role `.group`, two children in root order, each child's parent the host view | fails: a plain `NSView` answers `nil` children | return roots in dictionary order; answer `nil` for a root's parent |
| `rolesLabelsValuesAndTraitsMapOneToOne` — one node per role, label and value distinct strings, one selected, one disabled | fails to compile | swap label and value; map `.staticText` to `.group`; ignore `isEnabled` |
| `elementsAreCreatedOnlyWhenAClientReadsThem` (`AB-X`) — publish a table with 1,000 row children after activation: `createdElementCount == 0`. Host children: 1. The table's `accessibilityChildren()`: 1,001. Read again: still 1,001 | fails to compile | create elements in `publish` (1,001 after the first publish) |
| `aVendedElementKeepsItsIdentityAndIsDetachedWhenItsIDGoes` — publish `{a, b}` and read both. Publish with `a`'s label changed: same objects. Publish `{a}`: `b.accessibilityParent() == nil`, `b` is not among the host's children, `b.accessibilityPerformPress() == false` with no request sent, `b` still reads its label, and `b.accessibilityFrame()` equals the screen rect it had before removal. Publish `{a, b}` and read: the new `b` is `!==` the old | fails to compile | recreate every element on publish; skip `isDetached` (the parent stays the host); answer `.zero` for a detached element's frame while the host is alive |
| `anElementsFrameIsItsHostRectInScreenCoordinatesReadAtQueryTime` — 200×100 content window, node `(10, 0, 20, 16)`. The expected screen rect is literal arithmetic over `window.contentRect(forFrameRect: window.frame)`, `(minX + 10, maxY - 0 - 16, 20, 16)`, not a call to the conversion under test. Then `setFrameOrigin` by (+37, +23), with no republish: the rect moves by the same amount | fails to compile | drop the flip (use `minY + y` instead of `maxY - y - h`); cache the screen rect at publish |
| `onlyAdvertisedActionsAreAllowedAndPerformingSendsTheRequest` — a `[.press]` node and a `[]` node. The selector is allowed or refused per node. Press on the first sends `.press(id)` and returns the closure's answer: `true`, then `false` when the closure returns `false`. Press on the second sends nothing. Increment and decrement likewise | fails to compile | allow every selector; return `true` regardless of the closure |
| `focusIsReportedFromTheTreeAndAFocusRequestIsSent` — `focused = b`: the host's `accessibilityFocusedUIElement` is `b`'s element, and `b.isAccessibilityFocused()`. `setAccessibilityFocused(true)` on `a` sends `.focus(a)`. `focused = nil`: the host returns itself | fails to compile | report the first focusable node (SwiftUI's answer, arm 13; `AB-J`); send nothing from the setter |
| `aTableReportsItsRowCountAndItsRowsTheirIndices` — a table with `rowCount = 500` and rows at indices 40, 41, 42, where 40's `visibleFrame` has zero height: row count 500; rows 3; visible rows 2; indices 40, 41, 42 | fails to compile | report `children.count` as the row count; report the position in `children` as the index; report all rows as visible |
| `hitTestingUsesVisibleFramesSoAClippedRowNeverWins` (`AB-W`) — the shape a scrolled `List` really publishes: root header `frame = visibleFrame = (0, 0, 200, 20)`, `order 0`; root table, declared after it, with the unclipped `frame (0, -8, 200, 14000)` and `visibleFrame (0, 20, 200, 100)`; its overscan row `frame (0, -8, 200, 28)` with a zero-height `visibleFrame`; its second row `(0, 20, 200, 28)`, fully visible, holding a child; `order` rising in that pre-order. A point at `(5, 15)` returns the header; a point in the second row's child returns the child; a point outside everything returns the host. **Modal arm (second critic round):** add a root modal panel `(0, 30, 200, 40)` with `layer 1` and **`order 1`, recorded before the table** (a `Deferred` declared above the list in tree order), and a child label inside it: a point inside both the panel's label and the second row's child returns the **modal's label**, and a point in the second row's child **above** the panel (y between 20 and 30) still returns the row's child | fails to compile | hit-test on `frame` (the later root, the table, contains `(5, 15)` and its overscan row wins); return the first match; stop at roots; **rank by `order` alone, or by depth** (the deeper, later row child beats the modal) |
| `aHostQueryActivatesExactlyOnce` — signal `false`. Call `accessibilityChildren()` and `accessibilityHitTest` twice each: one `.activate` | fails: nothing sends it | drop the sticky flag (four requests) |
| `aFocusedElementQueryDoesNotActivate` (`AB-B`, second critic round) — signal `false`. Read `accessibilityFocusedUIElement` three times: zero requests, and each read answers the host view. **Control:** then `accessibilityChildren()`: one `.activate` | fails to compile | activate from `accessibilityFocusedUIElement` (three requests before the control) |
| `aRunningScreenReaderActivatesTheWindowBeforeAnyQuery` (`AB-B`, `AB-AB`) — a scripted signal that, like `VoiceOverSignal`, calls its handler **synchronously inside `observe`**. `true` at creation: `isActive` is already `true` when the initializer returns, and assigning `onRequest` afterwards (as `Window.init` does, after `AppKitWindow.init` built the bridge) delivers exactly one `.activate` **synchronously, before any query and with no run-loop turn**. `false` at creation: none; flip it `true`: one; flip `false` then `true` again: still one | fails to compile | ignore the signal (zero); send on every `true` (two); deliver the initial value through a `Task` (zero at assignment); drop the send at `onRequest` assignment (zero: the initial `true` arrived before anyone listened) |
| `nothingIsPostedBeforeActivation` — signal `false`. Publish two different trees without any host query: the recorder is empty. Query once, publish a third: posts appear | fails to compile | post regardless of `isActive` |
| `aGeometryOnlyChangeTouchesNoElementAndPostsNothing` (`AB-K`) — vend every element, move every frame by 5 points and republish, then republish the identical tree: 0 posts, `structuralPublishCount` unchanged, `geometryPublishCount == 2`, the same element objects, and each element's `accessibilityFrame()` reflects the moved rect | fails to compile | treat geometry as structure (posts `.layoutChanged`, count moves); cache frames in elements at publish (the rect does not move) |
| `destroyedIsPostedOnlyForElementsAClientWasHanded` (`AB-X`) — a tree of 3 roots, each with 10 leaves. Read the host's children and the first root's children. Remove every leaf: exactly 10 `.uiElementDestroyed`, on the 10 vended objects. Nothing for the 20 never read | fails to compile | post destroyed per removed id (30); create elements for removed ids to post on |
| `layoutChangedIsPostedOncePerClientRead` (`AB-K`) — activate by reading the host's children. Publish a structure change: 1 `.layoutChanged`. Publish 10 further structure changes with no read: 0 more. Read an element's children and publish a change: 1 more | fails to compile | post on every structural publish (11 after the second step); never reset the read flag (the third step posts 0) |
| `labelValueRowCountAndFocusChangesPostOnlyForTheElementThatChanged` — vend all elements, then publish four times: change one label, a different node's value, the table's row count, and the focus. One post each, on the right element, with the right name. Then the same label change on a never-vended node: no post | fails to compile | post `.valueChanged` for label changes; post focus on the old element; post label changes for unvended ids |

**End-to-end** tests go in `Tests/MetalUITests/AccessibilityEndToEndTests.swift`
(new). Each starts with `try #require(MTLCreateSystemDefaultDevice())`.

| test | red before | mutation |
|---|---|---|
| `aRealAppKitWindowPublishesItsFrameAndAPressRunsOnClick` — **`AppKitPlatform(device:accessibilitySignal: { scripted false })`** (`AB-AC`), a unique title, `Window(platformWindow:renderer:startsDisplayLink: false, content:)` over a `Column` holding a 40×20 `Box` declaring `AXNode(role: .button, label: "Increment")` with an `onClick` counter. Reach the host view through the platform window. Ask it for `accessibilityChildren()`, which activates. `drawFrameIfNeeded()`, then ask again: one child, role `.button`, label `"Increment"`. `accessibilityPerformPress()` returns `true`, the counter reads 1, and the window is dirty | fails: no children | leave `AppKitWindow.publishAccessibilityTree` storing rather than forwarding; drop the `onAccessibilityRequest` forward |
| `aKeyWindowReceivingEventsIsNeverActivatedWithoutAClient` (`AB-B`, arm Q) — the same construction, signal forced `false`, a recorder on `onAccessibilityRequest` installed after `Window.init`'s. `makeKeyAndOrderFront`, `makeFirstResponder(hostView)`. Send a synthesized left mouse down and up and a key down through `window.sendEvent`. Resize. Draw 5 frames. Result: zero `.activate`, `accessibility.buildCount == 0`. **Depends on the machine** (`AB-AC`): an out-of-process mouse-follow utility with the pointer over the window reaches the hit-test trigger; the doc and failure message say so and name `appkit-accessibility-activation-clients.swift` | green on arrival; this pins arm Q's AppKit answer | send `.activate` from `MetalHostView.keyDown` or `mouseDown` |
| `aHeldElementWhoseIDIsAdoptedPressesTheAdopter` (`AB-H`'s recorded hazard, second critic round) — the same construction over `Column { if model.showFirst { declared "First" 40×20 box, onClick → first += 1 }; declared "Second" 40×20 box, onClick → second += 1 }`, `showFirst` true. Activate, draw, and hold the element for the column's child 0 (`"First"`). Set `showFirst = false`, draw. **Arm 1, unnamed:** the held element is not detached, its label reads `"Second"`, and `accessibilityPerformPress()` returns `true` with `first == 0` and **`second == 1`**. **Arm 2, the remedy:** the same with `.id("second")` on the trailing box: the held element is detached, its press returns `false`, and both counters read 0. `try #require` the held element before the change in both arms | fails to compile | detach an element whose label changed across a publish (arm 1 press refused); skip detaching (arm 2 press runs `second`) |

---

## Lane 3 — defaults, modifiers, `List`

**Lane 3 as built (`AB-AG`).** The design below held; no rule changed. What
differs from the text, each with its reason in `AB-AG` and its measurement in
the record:

- **15 tests, not the table's 14.** `aListInsideHiddenContentIsNotPublishedEvenOnItsUnboundedFrame`
  is added: it is the only fixture that nests a `List`'s own suppression scope
  inside another, so it pins that the **outermost** scope's exception decides
  (mutant N29).
- **The strip's guard is widened.** `AB-AA` named `aClientDoesNotChangeStateRetention`
  the guard for the `logicalIndex` strip, but the table's fixture held no `List`,
  so it could not see a row hint. It gains a bounded `List`, and
  `synthesizedNodesCostNothingWhileNoClientIsActive` renders its `List` inside a
  scroller over two frames so the second is bounded (mutant N30).
- **Fixture choices in the cost tests.** The retry test's cap and inactive arms
  use 500 rows (the main arm keeps 5,000); its frame 1 asserts exactly 10 rows,
  by `visibleRange`'s arithmetic, not "at most 12". The bridge the cost tests
  feed is over a plain `NSView`, which has none of `MetalHostView`'s overrides,
  so a host children read is spelled `noteClientRead()` plus `rootElements()`;
  the table's rows are read through the element's own `accessibilityRows()`.
- **Arms added against surviving mutants**, over two rounds: a clickable text
  with a declared label (N49), a kept intermediate with children between a
  button and its texts (N46), a child's own value under a distributed one
  (N09v), a clickable text inside a click target (N60), and an active list
  outside any scroller that must not retry (N52).
- **A lane-1 fixture changed.** In
  `portalContentIsARootEvenWhenDeclaredInsideAnEmittingAncestor` the sibling
  `after` is now focusable: step C folds a declared `.button`'s non-interactive
  descendants away, which would hide the child the test reads.
- **`frameDidRender(emissionCount:retry:_:to:)`** takes `retry` as a required
  argument and returns the `Bool` without `@discardableResult`; the retry flag is
  stored on every drawn frame, active or not.
- **`windowIsBounded`** is `visibleRange`'s own guard, so a non-positive
  `rowHeight` is unbounded too, beside the two causes named below.
- **Step B absorbs lane 1's "clickable `generic` is a button".** The role map
  now maps `generic` to `.group` only; step B has already made every clickable
  `generic` node a button.
- **A folded button with no contribution keeps a `nil` label**, never `""`.
- **`AXEmission.synthesizes` has no reader.** A non-synthesizing conformer
  records only what it declared, which `registerHandlers`' gate already decides.
- **Demo labels are written at the call site**,
  `button("-", minus).accessibilityLabel("Decrement")`, not inside `button`.

### `Sources/MetalUI/AXNode.swift` (+~10 lines)

`var logicalIndex: Int?` is **internal**: not on the public initializer, not
`public`. Lane 1's gate strips it before the declaration test, so a row hint is
never a declaration and never writes `$ax` (`AB-L`, `AB-U`). Run
`swift package clean` first.

### `Frame.registerHandlers` callers

- `Text.prepaint` calls the internal overload with
  `accessibleText: string.isEmpty ? nil : string` (second critic round, `AB-F`,
  arms E0–E2: SwiftUI omits `Text("")` and publishes `Text(" ")`).
- `OnTapModifier.prepaint` (`NativeTappable.swift`, one line) calls it with
  `synthesizesAccessibility: false` (`AB-Y`).
- `Box`, `Stack`, `ScrollView` and `FrameModifier` are untouched.

### `AccessibilityTreeBuilder` — distribution, resolution, combination

These run after lane 1's steps 1–2 and before its role map.

**Step A — distribution (`AB-T`; arms R3, R4, R5, R8, R10, R14, R15, R18).**
Walk top-down. A kept node is a **distributor** when all of these hold:

- its declared role is `generic`;
- it has no `logicalCount` and no `logicalIndex`;
- it is not clickable, not focusable and not adjustable (**focusable and
  adjustable are a recorded divergence**, second critic round: SwiftUI
  distributes from both and copies the adjustable action to each child, arms
  C1, C5, C5i; `AB-T` gives the reasons);
- it declared a label or a value;
- it has at least one kept child.

A distributor is removed from the tree, and its children take its place, in
order, among its parent's children (or the roots). For each child, the
distributor's declared label overwrites the child's declared label, and its
declared value overwrites the child's declared value. **The outer declaration
wins** (arms R8, R15). Distribution recurses, so a chain of wrappers collapses
from the outside in. A labelled generic node with **no** kept child is not a
distributor. It publishes as a labelled `.group` (arms R6, R11 give
`AXUnknown`; `AB-F`'s recorded divergence).

**Step B — text resolution (`AB-F`, `AB-G`).** Per node, with `text` from the
record:

```
if text != nil:
    if clickable:
        label = label ?? text                                   // arms 5, 8, R12
    else if value == nil:
        value = label ?? text; label = nil                      // arms 1, 3, 10a, R4
    else:
        label = label ?? text                                   // arm 11, R1, R2, R18
    if role == .generic: role = clickable ? .button : .text
else if role == .generic and clickable:
    role = .button
```

**Step C — combination (`AB-G`; arms 5, 6, R5).**

- **A `.button` whose kept descendants are all non-interactive** (no actions,
  not focusable) publishes **no children**.
  - If its label is `nil`, it takes `label = descendants' (label ?? value)
    joined by ", "` in tree order.
  - If its value is `nil`, it takes `value = descendants' value, for each
    descendant that has BOTH a label and a value, joined by ", "`, or `nil`
    when none has (second critic round, `AB-G`; arms C3, C6, C7, and C4 for
    the label-only half). A plain text's value is its string and already went
    to the label.
  - Arm 6: `Button { HStack { Text A; Text B } }` is one `AXButton` labelled
    `A, B` with zero children.
  - Arm R5: a labelled button also has zero children.
- **A button with an interactive descendant** keeps its children and its
  label, `nil` included.
  - This is a MetalUI rule, and arm R7 measures SwiftUI doing otherwise: it
    collapses into the `Toggle`, giving one `AXCheckBox` labelled `A`.
  - That is `AB-G`'s recorded divergence.
- **Portal content** is never a descendant for this purpose, because it is a
  root (`AB-V`).

### `Sources/MetalUI/List.swift` (+~14 lines, `AB-L`, `AB-X`)

- `requestLayout` stores `private var windowIsBounded: Bool`. It is `false`
  exactly when `visibleRange` returned its unbounded `0..<count` because no
  vertical context was present or `viewportExtent == 0`: every `ScrollView`'s
  first frame (MP-I).
- When `pass.collectsAccessibility` and the window is bounded, each realized
  row `Box` gets `handlers.axNode.logicalIndex = window.lowerBound + offset`.
- The list's own node is unchanged: `container`, or whatever was declared, plus
  `logicalCount`.
- `prepaint`: when collecting and **not** bounded, it runs
  `box.prepaint` inside `pass.frame.withAccessibilitySuppressed(except: id)`.
  Frame 0 then publishes the table and its row count, with **no rows and no
  row text**. The next frame publishes the realized window.
- **That next frame must be produced (`AB-X` rule 3, second critic round).**
  `requestLayout` also stores `private var windowAwaitsViewport: Bool`: the
  window is unbounded **because** `pass.scrollContext` is vertical with
  `viewportExtent == 0`. `prepaint`, when collecting and that flag is set,
  calls `pass.frame.requestAccessibilityRetry()`. Nothing else in `List` or
  `ScrollView` would dirty the window: `ScrollView` stores the viewport through
  `withState`, which fires no `onWrite`.

### `Sources/MetalUI/Frame.swift` and `WindowAccessibility.swift` (lane 3, +~12 lines, `AB-X` rule 3)

- `Frame`: `private(set) var wantsAccessibilityRetry = false` and
  `func requestAccessibilityRetry()`, a no-op unless `collectsAccessibility`.
  **Not** `requestAnotherFrame()`: `wantsAnotherFrame` is honoured on every
  frame, so a zero-height scroller would keep the display link awake forever.
- `WindowAccessibility.frameDidRender` gains `retry: Bool` and returns whether
  the window should be dirtied: `retry && !lastFrameRetried`, then
  `lastFrameRetried = retry`. `Window` passes `frame.wantsAccessibilityRetry`
  and calls `setNeedsRedraw()` on `true`. One extra frame per run of unbounded
  frames, never a loop.

### New file `Sources/MetalUI/AccessibilityModifiers.swift`

```swift
extension StyledElement {
    public func accessibilityLabel(_ label: String) -> Self
    public func accessibilityValue(_ value: String) -> Self
    public func accessibilityAdjustableAction(
        _ handler: @escaping @MainActor (AccessibilityAdjustmentDirection) -> Void) -> Self
}
```

- Each writes one field through `handling`. After the modifier-composition
  merge, `handling` writes the outermost layer; distribution makes that the
  right place (`AB-T`, `AB-Z`).
- `accessibilityAdjustableAction` is `onAction(AccessibilityAdjustment.self)`.
- Not offered on `Component`, on `onClick`'s footing: a distributing modifier
  would amend every top-level node.
- `Handlers` gains no member, so `HandlerShape` needs no field.
  `ModifierTests`' case list is not extended: these are not layout modifiers.

### Demo (`Sources/MetalUIDemo/main.swift`, three lines)

- Label `CounterPanel.button`'s two squares `"Decrement"` and `"Increment"`,
  with `.accessibilityLabel` after `.onClick`. Unlabelled, they would combine
  to `"-"` and `"+"` (`AB-G`).
- Label the modal scrim `Stack` `"Close modal"`. The panel inside it is
  interactive (its click-absorbing `.onClick {}`), so the scrim stays a button
  labelled `"Close modal"` with its children intact.
- The panel is **not** labelled. It publishes as a button whose combined label
  reads the modal's text, and pressing it does nothing. A label would hide that
  text (`AB-Y` records why, and the script lists it).
- The row string is **not** changed (`AB-Y`); the script accounts for it.
- **The demo's state-table figures move** (second critic round). The two
  labels and the scrim label are **declared** nodes, so each writes a `$ax`
  slot every frame, active or not (`AB-U` exempts only synthesized records).
  CLAUDE.md's warm resident `StateTable` counts (165 at 40 rows, 63 at 500)
  are therefore stale after lane 3; the record owes the integration step a
  re-take, from the same harness §07 names.

### Lane 3 tests — `Tests/MetalUITests/AccessibilityDefaultsTests.swift` (new)

The fixture rules are lane 1's: explicit sizes, and `try #require` on every
looked-up node.

| test | red before | mutation that must redden it after |
|---|---|---|
| `aTextIsPublishedAsStaticTextWhoseValueIsItsString` (arms 1, 3, E0–E2) — `Column { Text("A"); Text("B") }`: two roots, `.staticText`, `value` `"A"`/`"B"`, `label == nil`, no column node. **Empty arm (second critic round):** `Column { Text(""); Text("B") }` publishes one root, `"B"`; `Column { Text(" "); Text("B") }` publishes two, the first with `value " "` | fails: no nodes | put the string in `label`; give `Column` a node; pass `accessibleText: string` for an empty string (the empty arm gains a root) |
| `labelAndValueFollowSwiftUIsStaticTextRules` (arms 10a, 11, R1, R2, R12) — four arms. (1) `Text("Hello").accessibilityLabel("Greeting")` gives `value "Greeting"`, `label nil`. (2) **`Text("vol").accessibilityValue("5")` gives `label "vol"`, `value "5"`**, the value-only case. (3) `Text("vol").accessibilityLabel("L").accessibilityValue("5")` gives `"L"`/`"5"`. (4) `Text("vol").onClick{}.accessibilityValue("5")` gives `.button`, `"vol"`/`"5"` | does not compile | **delete the `label = label ?? text` branch** (arm 2 reads `label nil`); skip the label-to-value move (arm 1); apply it when a value is present (arm 3 reads `value "L"`) |
| `aClickableTextIsAButtonLabelledByItsString` — `Text("Go").onClick{}`: `.button`, `label "Go"`, `value nil`, `.press` | fails | keep role `.text` for a clickable text |
| `aLabelOrValueOnAPlainContainerOrWrapperIsDistributedToItsChildren` (`AB-T`; arms R3, R4, R5, R8, R10, R15, R18) — seven arms. (1) `Column { Text("A"); Text("B") }.accessibilityLabel("L")`: two `.staticText` with `value "L"`, no group. (2) `Text("Go").padding(4).accessibilityLabel("X")`: one `.staticText` with `value "X"`, no group. (3) `Text("Go").accessibilityLabel("In").padding(4).accessibilityLabel("Out")`: `value "Out"`. (4) `Text("Go").frame(width: 120).accessibilityLabel("X")`: `value "X"`. (5) `Row { Text("Go") }.width(40).height(20).onClick{}.padding(4).accessibilityLabel("X")`: one `.button`, `label "X"`, no children. (6) `Column { Text("A"); Text("B") }.accessibilityValue("V")`: labels `"A"`/`"B"`, values `"V"`. (7) **a divergence pin and a control** (second critic round): `Column { Text("A") }.width(40).height(20).focusable().accessibilityLabel("L")` stays a labelled `.group` with one child, **the opposite of SwiftUI's arm C1** (and an adjustable arm, `accessibilityAdjustableAction`, likewise, against C5/C5i), its doc citing both; and the control `Box().width(20).height(0).accessibilityLabel("L")` is a labelled `.group` | fails: no nodes | publish the label on the wrapper (arms 1–5 gain a group); let the inner declaration win (arm 3 reads `"In"`); distribute from a focusable node (the divergence pin loses its group) |
| `aClickableContainerCombinesItsTextsIntoOneButtonLabel` (arms 6, R7, C3, C4, C6, C7) — `Row { Text("A"); Text("B") }.width(60).height(20).onClick{}` gives one `.button`, `label "A, B"`, `value nil`, `children == []`. The same with `Box().width(10).height(10).focusable()` as a third child gives an unlabelled button with **three** children (the divergence from arm R7). **Value arms (second critic round):** `Row { Text("vol").accessibilityValue("5"); Text("B") }…onClick{}` gives `label "vol, B"`, `value "5"` (C3); `Row { Text("A"); Text("vol").accessibilityValue("5") }` gives `"A, vol"`/`"5"` (C7); both texts valued `"1"`/`"2"` gives `"a, b"`/`"1, 2"` (C6); `Row { Text("A").accessibilityLabel("X"); Text("B") }` gives `"X, B"`/`nil` (C4) | fails | join with `" "`; keep children when combining; combine across an interactive descendant; **drop the value half** (C3 reads `nil`); **take a plain text's value into the button's value** (the first arm reads `"A, B"`) |
| `aDeferredInsideAClickableBoxIsNotFoldedIntoItsLabel` (`AB-V`) — `Row { Text("A"); Deferred { Text("Tip") } }.width(60).height(20).onClick{}`: the button's label is `"A"`, and `"Tip"` is a root `.staticText` | fails | ignore `portal` (label `"A, Tip"`) |
| `theAdjustableActionModifierRegistersTheAdjustmentHandler` (arm 11) — `Text("vol").accessibilityAdjustableAction { … }`: published actions `[.increment, .decrement]`; `.increment(id)` runs the closure with `.increment` | does not compile | register the handler under a different `Action` type; pass a constant direction |
| `aScrolledListPublishesItsLogicalCountAndItsRealizedRowsWithTheirIndices` (`AB-L`) — a 500-row `List`, `rowHeight` 28, in a 200pt `ScrollView`, offset seeded to 28 × 40, drawn twice. The list node is `.table`, `rowCount 500`. Its children are `.row`s whose `rowIndex` equals the realized window's indices, the first `>= 38`, and each row's text is its child. **Labelled arm (arm R16):** the same with `accessibilityLabel("Contacts")` on the `List`: still `.table`, `rowCount 500`, `label "Contacts"`, the same rows | fails: rows emit nothing | `logicalIndex = offset` (no `lowerBound`); drop `rowCount`; distribute the list's label (the labelled arm loses its table) |
| `activatingBeforeTheFirstFramePublishesNoRowsUntilTheWindowIsBounded` (`AB-X`) — a fake window over a 5,000-row `List` in a 200pt `ScrollView`, `.activate` **before the first draw**. Frame 0 (`drawFrameIfNeeded()`): `lastEmissionCount` is at most 3; the published table has `rowCount 5000` and **0** children; **`window.needsRedraw` is `true`**. Frame 1 is drawn with `drawFrameIfNeeded()` **and no `setNeedsRedraw()` or input between frames 0 and 1** (second critic round): children equal the realized window's size (at most 12 at 28pt rows with overscan 2), and `needsRedraw` is `false` after it. **Cap arm:** the same `List` in a `ScrollView` of height 0: frame 0 leaves it dirty, frame 1 is drawn, and after frame 1 `needsRedraw` is `false` (no loop). **Inactive arm:** the 200pt window with no `.activate`: after frame 0, `needsRedraw` is `false` (rendering is unchanged). The trees go into an `AppKitAccessibilityBridge` over a plain `NSView` in an `NSWindow` (no Metal): across frames 0 and 1, `createdElementCount == 0` and **0** `.uiElementDestroyed` | fails: rows emit nothing | drop the unbounded suppression (frame 0 records about 10,000); create elements eagerly in `publish` (about 10,000 destroyed posts on frame 1 once suppression is also dropped); **drop the retry** (frame 1 is never drawn: `drawFrameIfNeeded` returns without drawing and the table still has 0 children); **uncap it** (the cap arm is still dirty after frame 1); **retry while not collecting** (the inactive arm is dirty) |
| `scrollingAListPostsBoundedNotificationsAndBuildsOncePerFrame` (`AB-K`, `AB-X`) — the same harness over a 500-row `List`, active and drawn until bounded. Read the host's children and the table's rows (vending about 12 rows). Then scroll 20pt per frame for 60 frames through `simulateInput`. `buildCount` rose by exactly 60. `.layoutChanged` total **1**. `.uiElementDestroyed` equals the number of rows vended at the start (each once; 1,200pt carries every one out). No title or value posts. `createdElementCount` unchanged after the initial read | fails | post `.layoutChanged` per structural publish (about 43); post destroyed per departing id (about 43 + text children) |
| `anAnimationWithAClientActivePostsNothingAndTouchesNoElement` (`AB-K`) — active, a declared 40×20 box whose width animates to 120 inside `withAnimation`, all elements vended, 30 `simulateTick`s. Posts **0**. `structuralPublishCount` unchanged. `geometryPublishCount` equals `publishCount`'s rise, and both are greater than 0 and at most 30. The vended element is the same object, and its `accessibilityFrame()` width reads the last published width | fails | treat geometry as structure |
| `aClientDoesNotChangeStateRetention` (`AB-U`) — a `Column` of 130 `Text`s and 10 sized `onClick` boxes, drawn 3 frames in two fake windows, one active and one not: equal `window.stateTable.count` | green before (nothing records); its red evidence is the mutation, see the note | write the `$ax` slot for synthesized records (the active count rises by 140) |
| `synthesizedNodesCostNothingWhileNoClientIsActive` — a non-collecting frame of `Text`, a sized clickable box and a 500-row `List`: `axNodes.count == 1` (the list's own, today's contract), `axEmissions.isEmpty`. The same tree collecting: `axEmissions.count > 1` and `axNodes.count == 1` | fails to compile | make `Text.prepaint` or `List` record regardless of the flag |
| `anOnTapModifierPublishesNothingButItsHitboxStillPresses` (`AB-Y`) — `HStack { Rectangle(width: 40, height: 20, color: .accent).onTap { n += 1 } }` in an active fake window: zero records and zero published nodes. `.press(AccessibilityNodeID(tapID))`, with the id read from `lastHitboxes`, returns `true`, and `n == 1` | fails to compile | pass `synthesizesAccessibility: true` from `OnTapModifier` (one unlabelled button appears) |

**Note on `aClientDoesNotChangeStateRetention`.** It is green before lane 1,
because nothing records. Its red evidence is the mutation, which must be run
and named in the record. Shape 15 of `verifying-tests-can-fail.md` applies: it
first `try #require`s that the active window really recorded
(`lastEmissionCount >= 140`), so the equal counts are not two idle windows.

### The human look (open: lane 3 has landed, nobody has run it)

The script is in `docs/record/12-accessibility-bridge.md`. A human runs it with
VoiceOver, because the suite cannot hear what VoiceOver says.

---

## Merge contract (`AB-Z`)

Three tracks edit shared functions. The integration step applies these combined
forms. Each is written so either merge order produces it. **Rewritten in the
second critic round** against `feat/environment` at `f4dcad8` (its lane 3 as
redesigned at `e9afded`) and `feat/modifier-composition` at `ec65da6`; the
first version was written against `bbd4d66` and `1c6f686`.

### `Frame.registerHandlers`, merged with the environment track's lane 3

The environment track's gate is taken **exactly as its spec's "Lane 3" block
writes it** (`EV-F`, `EV-T`, and its finding 7's gated `$focus` write). This
track's record path is added after it, and **synthesis reads the ungated
`handlers`** (`EV-W` item 4).

```swift
func registerHandlers(_ handlers: Handlers, at bounds: Bounds<Pixels>, id: GlobalElementID,
                      accessibleText: String?, synthesizesAccessibility: Bool) {
    let enabled = environmentTop.isEnabled                                // environment: in place
    if enabled { focusRegistry.register(handlers, id: id) }               // environment (EV-F): a disabled
                                                                          // element is out of the keyboard —
                                                                          // no focus, actions, onKey, keyContext
    if let focused = focusedElement, id == focused {
        focusedElementProducedThisFrame = true                            // unchanged, ungated
        if enabled { /* the existing $focus slot write */ }               // environment (EV-F, its finding 7)
    }
    if hitTestingDisabledDepth == 0, handlers.isPointerTarget {
        if enabled {
            _ = insertHitbox(bounds, id: id, opaque: true, handlers: handlers)
        } else {                                                          // environment (EV-E, EV-T):
            _ = insertHitbox(bounds, id: .child(of: id, at: 0, name: ElementID("$disabled")),
                             opaque: true, handlers: Handlers())          // DERIVED id, empty handlers
        }
    }
    var declaration = handlers.axNode
    declaration.logicalIndex = nil                                        // this track (AB-L)
    if !declaration.isEmpty {
        var node = handlers.axNode
        if !enabled { node.traits.insert(.disabled) }                     // environment
        emitAXNode(node, at: bounds, id: id, children: [])
    }
    if collectsAccessibility, !isAccessibilitySuppressed(for: id) {       // this track
        // UNGATED `handlers` (EV-W item 4): a disabled control is still published.
        let adjustable = handlers.actions[ObjectIdentifier(AccessibilityAdjustment.self)] != nil
        let hasSomethingToSay = !declaration.isEmpty || handlers.axNode.logicalIndex != nil
            || (synthesizesAccessibility
                && (handlers.onClick != nil || handlers.isFocusable || adjustable || accessibleText != nil))
        if hasSomethingToSay {
            axEmissions.append(AXEmission(id: id, declared: handlers.axNode, text: accessibleText,
                                          isClickable: handlers.onClick != nil, isEnabled: enabled,
                                          synthesizes: synthesizesAccessibility,
                                          portal: portalStack.last ?? 0,
                                          geometry: accessibilityGeometry(for: bounds)))
        }
    }
}
```

**What the merge must preserve.**

- **Published, and marked disabled.** A disabled element that is only
  clickable, only focusable or only adjustable records, and the builder
  publishes `isEnabled == false` from `record.isEnabled`. SwiftUI publishes a
  disabled control (arm P2: `AXButton`, `enabled=0`).
- **Its actions and focusability are the gated ones, with no builder edit.**
  - `.press` comes from `hitboxes`. The blocker sits under the derived id with
    `Handlers()`, so no entry for `id` has an `onClick`:
    `actions` has no `.press`, and `handleAccessibilityRequest(.press(id))`
    returns `false`.
  - `.increment`/`.decrement` come from `focusRegistry.actionHandler`. A
    disabled element is not registered, so they are absent and the requests
    return `false`.
  - `isFocusable` comes from `focusRegistry.isFocusable`, `false` for the same
    reason, and `.focus(id)` returns `false`.
- **The environment track's own spec** names our first version's
  `AXNode.synthesized(declared:handlers:text:)`, which no longer exists: its
  "trait after synthesis" is this form's `isEnabled: enabled` on the record.

**Joint test, written by the integration step** (`.disabled` does not exist on
this branch):
`aDisabledElementPublishesDisabledWithTheGatedActionsAndRefusesEveryRequest`.
An active fake window, root `Row { … }` (a scope cannot be a root, `EV-B`),
three arms, each with a control identical minus `.disabled(true)`:

| arm | fixture | disabled | control |
|---|---|---|---|
| clickable only | `Box().width(40).height(20).onClick { n += 1 }.disabled(true)` | one `.button`, `isEnabled false`, `actions []`; `.press(id)` → `false`, `n == 0` | `isEnabled`, `.press`; press → `true`, `n == 1` |
| focusable only | `Box().width(40).height(20).focusable().disabled(true)` | **published** (a node exists for the id), `isEnabled false`, `isFocusable false`; `.focus(id)` → `false`, `window.focusedElement == nil` | `isFocusable`; `.focus(id)` → `true`, focused |
| adjustable only | `Box().width(40).height(20).onAction(AccessibilityAdjustment.self) { k += 1 }.disabled(true)` | **published**, `isEnabled false`, `actions []`; `.increment(id)` → `false`, `k == 0` | `[.increment, .decrement]`; `.increment` → `true`, `k == 1` |

Mutations that must redden it, each separately:

- build the record's `isEnabled` as `true` (all three disabled arms read enabled);
- synthesize from a gated set, `if enabled` around the synthesized terms (the
  focusable-only and adjustable-only arms publish nothing);
- register the ungated `handlers` with the focus registry when disabled (the
  focusable arm is focusable; the adjustable arm advertises actions);
- register the blocker under `id` with the enabled `handlers` (the clickable
  arm is pressable).

### `Frame.init`, and `Window`'s `Frame(…)` call

The environment track adds **no** init parameter (`EV-H`). This track's
`collectsAccessibility:` lands alone. `Window` gains that track's one statement
after the `Frame(…)` expression: an adjacent-line textual conflict only.
`Passes.swift`: both tracks add internal or public accessors to
`LayoutPass`/`PrepaintPass`, with distinct names, purely additive.
`Frame.render`: the environment track edits its root `StateBinder.bind` call;
this track's `AB-AD` edits its root `prepaint` call a few lines below. Keep
both.

### `ElementGroup.swift`

The environment track replaces
`StateBinder.bind(self, table: pass.frame.stateTable, id: layout.id)` with
`StateBinder.bind(self, in: pass.frame, id: layout.id)` in
`Element.prepaintGroup`: **the line directly above** this track's
`display: none` block. Keep both, the bind first. The modifier-composition
track's lane 3 edits `Element`'s default `requestGroupLayout`, a different
function; its lane 2 adds two protocol requirements, additively.

### Modifier composition (`MetalUI-modifier-composition`)

- **`FrameModifier.swift` is deleted there.** Nothing in this track edits it.
  Wherever this spec or `AB-C` names `FrameModifier` as a conformer, read
  `ModifiedElement`: every layer calls `registerHandlers` with its own id, and
  only the outermost layer carries the handlers `StyledElement` writes.
- **`ModifiedElement`'s layer loop must carry `AB-O`'s check** (second critic
  round). Its `prepaint` registers layers k = n-1 down to 0 in its own body,
  then calls `content.prepaintGroup` once, so `Element.prepaintGroup`'s
  `display: none` test sees only the outermost layer's node. The combined
  `prepaint`:

  ```swift
  // k = n-1 … 0, outermost first; `hidden` is the first k whose style is display: none
  let hidden = pass.collectsAccessibility
      ? (0..<n).reversed().first { pass.frame.style(node[$0]).display == .none } : nil
  for k in stride(from: n - 1, to: hidden ?? -1, by: -1) { register(k) }
  if let hidden {
      pass.frame.withAccessibilitySuppressed(except: nil) {
          for k in stride(from: hidden, through: 0, by: -1) { register(k) }
          content.prepaintGroup(…)
      }
  } else {
      content.prepaintGroup(…)
  }
  ```

  Registration order is unchanged (outermost first), so `MC-F`'s order test is
  unaffected. **Joint check:** lane 1's
  `aHiddenInnerModifierLayerSuppressesEverythingInsideIt`, green on this branch
  with nested `Box`es, must pass after the merge **unchanged**.
- **`.padding`/`.frame` become `ModifiedElement`.** A label written through
  `handling` lands on the outermost layer, the arm R4 situation. `AB-T`'s
  distribution makes that correct whatever the representation.
  `aLabelOrValueOnAPlainContainerOrWrapperIsDistributedToItsChildren` arms 2–5
  are the joint check and must pass after the merge **unchanged**.
- **`AXEmitSiteTests.swift`'s arm list** changes there. This track does not edit
  that file, and its `noConformerEmitsAnAXNodeItDidNotDeclare` stays true (the
  synthesized path never reaches `axNodes`), so the two edits do not interact.

---

## Test and count accounting

About 52 new tests (second critic round):

| where | tests |
|---|---|
| lane 1 | 18 (15 as built, one added against hunting mutants, two in the second critic round) |
| lane 2, platform | 18 as built (`aFocusedElementQueryDoesNotActivate` added in design; `anOffMainThreadQueryAnswersNothingAndDoesNotTrap` added by `AB-AE`) |
| lane 2, end-to-end | 3 (`aHeldElementWhoseIDIsAdoptedPressesTheAdopter` added) |
| lane 3 | 15 as built: the table's 14, plus `aListInsideHiddenContentIsNotPublishedEvenOnItsUnboundedFrame` (`AB-AG`) |
| integration, the joint disabled test | 1 |

Counts are design-time and go stale the moment a test lands; the record
re-measures. Goldens: 97, unchanged. Typecheck guards: none added. Every count
the lanes report is re-taken, per CLAUDE.md, from the summary line of an
unfiltered run.
