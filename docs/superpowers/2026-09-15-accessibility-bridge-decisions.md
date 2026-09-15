# Accessibility bridge — decisions

Rulings for the accessibility-bridge half of plan task 12
(`docs/superpowers/plans/2026-09-12-swiftui-alignment.md`). Prefixed **`AB-`**
and **lettered** (`AB-A`, `AB-B`, …). **A bare `AB-3` is a typo, not a
citation.** The next unused letter is `AB-T`.

Read alongside:

- `docs/superpowers/specs/2026-09-15-accessibility-bridge-design.md` — the
  three lanes, their API, tests and mutations.
- `docs/probes/swiftui-accessibility-bridge.swift` — the SwiftUI evidence, with
  its recorded output in the header. "Arm N" below means that file's arm N.
- `docs/record/12-accessibility-bridge.md` — this track's record, including
  the human VoiceOver script.
- Rulings this track leans on: `TB-M` (children stay a field; order is not
  recoverable from keys), `TB-AG` (AX data on `Handlers.axNode`), `TB-S`
  (the `$ax` slot's footprint), `EP-5` (prefer SwiftUI above the engine).

## How to read the letters

**Written at design time (2026-09-15, at `f64e58a`), before any lane runs.**
Each ruling says what, why, the evidence (probe arm, measurement or reading —
and which of the three), and what it costs if wrong. Implementation lanes
append their red runs and mutation records under the ruling they exercise,
the way `SA-J`…`SA-M` carry theirs.

- `AB-A`…`AB-E`: the tree, the seam, identity and geometry (lanes 1–2).
- `AB-F`…`AB-J`: what a node says and what a client can do with it (lanes 1–3).
- `AB-K`…`AB-M`: notifications, virtualization, and the cost instruments.
- `AB-N`…`AB-P`: smaller shape decisions and one recorded divergence.
- `AB-Q`: scope and deferrals. `AB-R`: the seam has no defaults. `AB-S`: what
  the probe can and cannot prove.

---

## AB-A — the bridge is a neutral tree pushed through a two-requirement seam

**What.** `Window` builds an `AccessibilityTree` (a value in `MetalUIPlatform`,
no AppKit) and hands it to `PlatformWindow.publishAccessibilityTree(_:)`. The
platform answers clients from that value and sends `AccessibilityRequest`s back
through `onAccessibilityRequest`. Diffing, element objects and notifications
live on the platform side. Node identity is `AccessibilityNodeID`, an opaque
`AnyHashable` wrapper that `MetalUI` fills with a `GlobalElementID`.

**Why.** `MetalUIPlatform` cannot import `MetalUI` (one-way target
dependencies), so it cannot see `GlobalElementID` or `AXNode`. A value tree
also lets the fake platform record exactly what was published — the dispatch's
"implement it in the fake platform so tests can assert what is published" —
and gives a future UIKit conformer the same input. `onInput(InputEvent) -> Bool`
is the existing precedent for the request shape.

**Evidence.** Reading (`Package.swift` target graph; `Platform.swift`).

**Cost if wrong.** If the platform needed live access to the element tree (for
example to realize off-screen `List` rows on demand for VoiceOver), a pushed
value is not enough and a pull requirement is added. That is additive to this
seam, not a rewrite. `AnyHashable` could cost an allocation per id per build;
it is paid only while a client is active (`AB-B`), and a `UInt64` token table
in `Window` is the fallback.

## AB-B — nothing is collected until a client asks; activation is sticky

**What.** A window collects and publishes nothing until the host view's first
accessibility query (`accessibilityChildren`, `accessibilityHitTest` or
`accessibilityFocusedUIElement`) sends `.activate`. `Window` then marks itself
dirty; every later frame is built with `collectsAccessibility = true`. It never
deactivates. The first query is answered from the empty tree; the tree arrives
one frame later with a `.layoutChanged` notification.

**Why.** Synthesizing nodes for every `Text` and `onClick` element costs a
`$ax` `StateTable` slot and a dictionary entry per element per frame
(`TB-S`). Paying that in every app, VoiceOver or not, would move the warm
resident-entry counts and divergence 18's thresholds that record §07 and
CLAUDE.md quote. SwiftUI also builds nothing until a client is signalled.

**Evidence.** Probe arms 1 and 2. A hosted `Text` exposes **0** accessibility
children on an in-process ask and still **0** after a second ask and a run-loop
spin; after the process sets `AXEnhancedUserInterface` on `NSApp`, the same
host exposes **1** child (`AXStaticText`, value `Hello`). So SwiftUI builds
nothing until it believes an assistive client is present.

**Where MetalUI differs, deliberately.** SwiftUI's trigger is the application
attribute; arm 1 shows an in-process query is *not* its trigger. MetalUI's
trigger is the query itself, because a query is observable on our own view and
the application attribute is not observable without subclassing
`NSApplication` (which `App` does not own). Any real client that reads this
window reaches the host view.

**Cost if wrong.** (1) A client whose first read is taken as final sees an
empty window. VoiceOver re-reads on `.layoutChanged`; whether it does so
promptly is item 1 of the human script. The fallback is to answer the first
query by building a tree synchronously from the last frame's handler records
(no `Text` values). (2) Anything in-process that queries the host view
(a test, a debugging tool) turns collection on for the window's lifetime —
a cost, not a defect. (3) An accessibility utility that reads other
apps' windows (unmeasured which ones do) would activate every MetalUI window
it reads, the population SwiftUI also pays for if those utilities set the
application attribute (also unmeasured).

## AB-C — hierarchy is the nearest emitting ancestor, ordered by emission

**What.** A node's parent is the nearest `GlobalElementID.parent` ancestor that
emitted a node this frame; none makes it a root. Siblings are ordered by the
order `emitAXNode` ran (`Frame.axEmissionOrder`, recorded only while
collecting). Containers that emit nothing are transparent. The hierarchy lives
in the published `AccessibilityTree`; `Frame.axNodes[id].children` stays `[]`.

**Why.** `TB-M` proved order cannot come from `axNodes`' keys: a name
discards the positional index, so `x, y` and `y, x` give identical key sets. It
did not weigh emission order, which is a different source: prepaint visits
children in declaration order and every conformer emits before descending, so
emission order is a pre-order traversal and unambiguous. No `ElementGroup`
associated-type change is needed. Flattening matches SwiftUI.

**Evidence.** Probe arms 3 and 9: `VStack { Text A; Text B }`, with or without
`.onTapGesture`, exposes two `AXStaticText` children directly under the host,
no group. The emission-order claim is by reading (`Box`, `Stack`, `FrameModifier`
and `OnTapModifier` each call `registerHandlers` on the line before
`content.prepaintGroup`; `Text` is a leaf; `Deferred` prepaints inline under
`pass.deferred`); lane 1's `childrenFollowDeclarationOrderWhereIDsAloneCannot`
is its measurement, on `TB-M`'s own counterexample.

**Why not write `AXNode.children` back.** `Frame.axNodes` is a per-frame
emission record whose tests pin "declared nothing, emitted nothing"; filling
children there means a second pass over every frame's nodes, including `List`'s
always-on node, when no client exists. The integration step should update
record §05's `AXNode.children` row: still always empty, but no longer because
the hierarchy is unrecoverable.

**Cost if wrong.** A conformer that emits after its children, or a container
that prepaints children out of declaration order, silently reorders
VoiceOver's navigation. The builder's two-pass assembly tolerates the first;
the second would need an explicit sort key.

## AB-D — one element object per id across consecutive trees; detached on first absence; no revival

**What.** The AppKit bridge keeps one `AppKitAccessibilityElement` per
`AccessibilityNodeID` for as long as every published tree contains the id. On
the first tree without it, the element is detached: parent `nil`, absent from
every children list, every action refused, last role/label/value kept, and one
`.uiElementDestroyed` posted. If the id returns, a new object is created. The
bridge does not use `Frame.axNode(for:)` (the `$ax` tombstone), which stays
unread.

**Why.** Design spec §9 asks that a held handle "reports itself invalid rather
than vanishing". A detached object does exactly that, without a second liveness
notion. Reviving the old object when a retained id returns would be worse than
useless here, because identity is structural: a vanishing `if` makes the
trailing sibling adopt the id, so a revived handle would silently point at a
different element.

**Evidence.** Probe arm 12. Across a value update (`Count 0` → `Count 1`)
SwiftUI keeps all three `AccessibilityNode` objects (`[true, true, true]`).
When the conditional `Text` vanishes, the survivors keep their objects, and the
removed node still reads `value=Conditional` with `parent=nil`. When the
conditional returns, its node is a **new** object (`false`).

**A MetalUI consequence the probe does not share.** In SwiftUI the two
survivors keep their objects because SwiftUI's identity for `if` content is not
positional. In MetalUI the trailing siblings adopt the vanished ids, so the
object that read `Conditional` now reads `Count 1` (a `.valueChanged`), and the
object for the last id is the one detached. That is CLAUDE.md's identity rule,
not a bridge defect; naming the trailing sibling is the same remedy.

**Cost if wrong.** A client that caches an element across a one-frame absence
(an element briefly culled) loses its place. No MetalUI element is culled for a
single frame today; `List` rows leaving the window are genuinely gone.

## AB-E — frames: content space, scroll-translated, unclipped, converted to screen at read time

**What.** A published frame is window-content points with a top-left origin,
with `Frame.activeOffset` applied and no clip. `Frame.emitAXNode` is fixed to
translate as `insertHitbox` does. The AppKit element computes its screen rect
in `accessibilityFrame()` from the host view (`convert(_:to: nil)`, then
`window.convertToScreen`) every time it is asked; nothing screen-space is
stored.

**Why.** An untranslated rect puts every node inside a scrolled `ScrollView`
at its content-space position: VoiceOver's cursor would outline the wrong place.
Converting at read time keeps frames right when the window moves, which
publishes nothing because no frame is drawn.

**Evidence.** The translation defect is by reading (`Frame.swift:745-746`
against `:564-567`); lane 1's `aNodeInsideAScrolledScrollViewReportsItsOnScreenFrame`
is its first measurement. Unclipped: probe arm 14b, where SwiftUI's lazy list
node reports `frame=(227.25, -513.0, 45.5, 813.0)` inside a 200pt scroll area.
Screen convention: every probe frame is bottom-left screen space (a 16pt `Text`
at the top of a 300pt content rect with origin y = 100 reads y = 384).

**Cost if wrong.** If `Deferred`'s root-clip reset also left a stale offset,
portal content would be displaced; lane 1's scroll test does not cover a portal
inside a scroller, so that combination is unpinned.

## AB-F — role, label and value follow SwiftUI's static-text rules; `generic` is `AXGroup`

**What.** When collecting:

- A `Text` with nothing declared publishes `.staticText` with its string as
  **value** and no label.
- A `Text` given only a label publishes that label as its **value** and no
  label.
- A `Text` given a label and a value publishes both unchanged.
- Role map: `generic` and `container` → `AXGroup`; `button` → `AXButton`;
  `text` → `AXStaticText`; `image` → `AXImage`; `container` with
  `logicalCount` → `AXTable`; a node with `logicalIndex` → `AXRow`.
- `selected` → `accessibilitySelected`, `disabled` → `accessibilityEnabled =
  false`; `updatesFrequently` is dropped (no macOS counterpart).
- A node whose frame has zero area is not published (`AB-O`).

**Evidence.** Probe arms 1/3 (`Text` → `AXStaticText`, `value=Hello`,
`label=nil`), 10a (`Text("Hello").accessibilityLabel("Greeting")` →
`value=Greeting`, `label=nil`), 11 (`label=vol value=5`).

**Divergence, recorded.** Arm 10b: a `Color` given a label is `AXUnknown`
with that label. MetalUI publishes `AXGroup` for a labelled `generic` node,
because a focusable or clickable generic node must be navigable, and
`AXUnknown` is the role AppKit gives to things it cannot classify. The human
script checks VoiceOver reads a labelled group.

**Cost if wrong.** If VoiceOver reads `AXGroup` as a container to enter rather
than an item, labelled leaves take an extra keystroke. Changing the one map
entry is the fix.

## AB-G — an `onClick` element is a button, AX press runs `onClick`, and a button combines its texts

**What.** When collecting, an element with `onClick` and no declared role
publishes `.button` with `.press`; a clickable `Text` is a button labelled by
its string. A button with no label whose published descendants are all
non-interactive takes their labels (or values) joined with `", "` and publishes
no children. `AXPress` on it runs the element's `onClick`.

**Why.** MetalUI has no `Button` until task 9; `onClick` is the only way to
make something activatable, and the dispatch requires "press → the element's
onClick/onTap". An unlabelled button with text children is the anti-pattern
screen-reader users hit most.

**Evidence.** Arm 5: SwiftUI `Button("Go")` is `AXButton`, `label=Go`, and
`accessibilityPerformPress` returns `true` with the closure run once. Arm 6:
`Button { HStack { Text A; Text B } }` is one `AXButton` labelled `A, B` with
zero children.

**Divergence, recorded and deliberate.** Arm 7: `Text("Tap").onTapGesture`
stays `AXStaticText`, and `accessibilityPerformPress` returns **`false`** with
the closure run **0** times. Arm 8: adding `.accessibilityAddTraits(.isButton)`
makes it `AXButton` labelled `Tap`, and press **still** returns `false`, closure
0 times. So on macOS 26 a SwiftUI tap gesture is not pressable through
accessibility even when it claims to be a button. MetalUI makes `onClick`
pressable. When task 9 adds `Button`, the question "should bare `onClick`
revert to SwiftUI's answer" belongs to that task.

**The combination rule is half measured.** Arm 6 measures the join and the
empty children. "Do not combine across an interactive descendant" has no probe
arm and is a MetalUI rule, stated so.

**Cost if wrong.** Clickable containers that are not conceptually buttons
(a row that selects) are announced as buttons. `accessibilityValue`/a declared
role override it.

## AB-H — advertised actions are derived from the last frame's live handlers

**What.** `.press` is advertised iff the last frame's `hitboxes` hold an
`onClick` for the id; `.increment`/`.decrement` iff the last frame's focus
registry holds an `AccessibilityAdjustment` action handler for it. A press is
dispatched by running that hitbox's `onClick`; an adjustment by running that
handler. `AXNode.actions` as declared by a caller is **not** consulted. The
AppKit element gates each perform selector per instance with
`isAccessibilitySelectorAllowed(_:)`.

**Why.** The dispatch says actions are "routed back through the existing
handler dispatch". `lastHitboxes` is the record click dispatch already resolves
against, so a press is refused exactly where a click would find nothing:
`allowsHitTesting(false)` removes both. Advertising an action with no handler
would tell VoiceOver a control works when it does nothing.

**Evidence.** Reading (`Window.dispatchClick`, `Frame.registerHandlers`'
`hitTestingDisabledDepth` gate). Lane 1's
`aPressIsRefusedWhereHitTestingIsDisabled` is the measurement.

**Not checked: occlusion.** A click lands on the topmost opaque hitbox; a
press goes to the named element even under a `Deferred` scrim. Deferred with
modal isolation (`AB-Q` item 4).

**Cost if wrong.** `AXNode.actions` becomes a declared-but-inert field. The
integration step should add it to the inert table until task 9 either reads it
or removes it.

## AB-I — adjustment is an `Action`, with SwiftUI's modifier name

**What.** `AccessibilityAdjustment: Action` carries an
`AccessibilityAdjustmentDirection`. `StyledElement.accessibilityAdjustableAction(_:)`
registers it through the existing `onAction`. Increment/decrement requests
dispatch it to the element's own handler only, not up the focus chain.

**Why.** It reuses the action registry the keyboard already uses, so no
`Handlers` member is added (and `HandlerShape` does not fall behind a third
time). Only the element itself: an ancestor's handler would make a node claim
an action on behalf of another.

**Evidence.** Arm 11: `accessibilityAdjustableAction` on a `Text` returns
`true` from both perform methods and its closure sees `["increment",
"decrement"]` in call order; the node stays `AXStaticText` with its label and
value.

**Cost if wrong.** A keymap binding to `AccessibilityAdjustment` also works
from the keyboard. Harmless, and arguably useful.

## AB-J — accessibility focus is `Window.focus`

**What.** The published `focused` is the window's focus after the frame's
read-back, when that element published a node. `accessibilityFocusedUIElement`
on the host view answers its element, or the host view when nothing is focused.
`setAccessibilityFocused(true)` sends `.focus(id)`, which calls
`Window.focus(_:)` only if the last frame found the id focusable.
`setAccessibilityFocused(false)` is ignored. The element reports the new focus
after the next frame publishes; a `.focusedUIElementChanged` is posted then.

**Why.** Design spec §9: "AX focus and §8.3 focus handles are the same focus;
the bridge reflects one into the other rather than maintaining two." Routing
through `Window.focus` inherits its validation and its dirtying.

**Evidence.** Probe arm 13 with a control: before any request, SwiftUI's host
reports the first focusable `Text` ("Other") as focused and the bound
`@FocusState` has seen no change (`[]`). After `setAccessibilityFocused(true)`
on the second `Text`, the `@FocusState` flips (`[true]`) and the host reports
the second node. So an accessibility focus request drives app focus state.

**Cost if wrong.** A one-frame window in which `isAccessibilityFocused()`
still answers the old element after a request. SwiftUI's arm read after a
0.5 s spin, so the probe cannot say whether SwiftUI has the same lag.

## AB-K — notifications: only real changes, only after activation, never for frames

**What.** Per publish, from `AccessibilityTreeChanges`: one
`.uiElementDestroyed` per removed element, one `.layoutChanged` on the host if
the id set, roots, any children list or any role changed, one `.titleChanged` /
`.valueChanged` / `.rowCountChanged` per element whose label / value / row count
changed, and one `.focusedUIElementChanged` on the new focus. Nothing when only
frames change. Nothing for a created element. Nothing before `.activate`.
`Window` does not publish a tree equal to the last one (`AB-M`), so an unchanged
frame reaches the bridge not at all.

**Why.** An animation moves frames every display-link tick; a notification per
tick is the "per-frame spam" the dispatch rules out, and frames are read lazily
(`AB-E`), so nothing needs announcing. `.created` is omitted because
`.layoutChanged` already tells a client to re-read children, and posting it
per `List` row entering the window is the spam again.

**Evidence.** None from SwiftUI: the probe reads state and cannot observe what
SwiftUI posts. This is AppKit's documented notification vocabulary applied by
judgement. Lane 2's recorder tests pin each count.

**Cost if wrong.** If VoiceOver needs `.created` or `.moved` to keep its cursor
on a scrolling row, the human look shows a lost cursor while scrolling; the fix
is additive in `publish`.

## AB-L — a virtualized `List` is an `AXTable` whose row count is its logical count

**What.** `List`'s node (`container` + `logicalCount`) publishes as `AXTable`
with `accessibilityRowCount = logicalCount`. While collecting, each realized
row `Box` emits a node with `logicalIndex = window.lowerBound + offset`,
published as `AXRow` with `accessibilityIndex`. `accessibilityRows` and
`accessibilityVisibleRows` are the realized rows.

**Why.** The dispatch: "List's logicalCount must map to a row count." Design
spec §9's "3 of 500" needs both halves: the 500 (row count) and the 3 (row
index), which `TB-M`'s blocker had left without anything to attach to.

**Evidence.** Arm 14a: SwiftUI's `List(0..<500)` is an AppKit
`SwiftUIOutlineListView`, `AXOutline`, `rows=500` — every logical row present
as an element. Arm 14b: `ScrollView { LazyVStack { ForEach(0..<500) } }`
exposes an `AXOpaqueProviderGroup`/`AXOpaqueProviderList` with **25** realized
children.

**Divergence, recorded.** MetalUI is neither: `AXTable` rather than
`AXOutline` (no disclosure levels exist), and realized rows rather than 500
row elements. Whether VoiceOver announces "row 41 of 500" from `AXRowCount` and
`AXIndex` — rather than counting `AXRows` — is **unmeasured** and is the human
script's item 4. Rows outside the window cannot be reached (`AB-Q` item 2).

**Cost if wrong.** VoiceOver says "N of 17". The alternatives are `AXList`
(children counted) or synthesizing placeholder row elements for the full count,
which is the allocation `List` exists to avoid.

## AB-M — the cost instruments are counts, and an unchanged tree is not republished

**What.** `WindowAccessibility.buildCount` and `.publishCount`, the fake's
`publishedAccessibilityTrees`, the recorder's posted notifications, the
presence of `$ax` slots and `Frame.axEmissionOrder`'s length are the
performance evidence. `frameDidRender` builds only when active and publishes
only when the tree differs (`Equatable`).

**Why.** CLAUDE.md: performance tests count work, never wall clock. The
dispatch: "No per-frame allocation regressions: count published
elements/notifications." The inactive path's cost is one `Bool` read per
`registerHandlers` call; lane 1's and lane 3's inactive tests pin that nothing
else runs. A `malloc_logger` count (`FreezeLoopAllocationTests`' instrument)
was considered and not used: there is no pre-feature baseline to compare a
frame's allocation count against inside one build, and the work counters
discriminate the mutations that matter (collecting unconditionally).

**Cost if wrong.** An allocation added on the inactive path that none of the
counters see (for example in `Frame.init`) goes unnoticed. The equality check
is O(nodes) per drawn frame while active, paid instead of an unconditional
publish.

## AB-N — the host view is an `AXGroup` element

**What.** `MetalHostView` answers `isAccessibilityElement() == true` and role
`AXGroup`; roots are its children and their parent.

**Evidence.** Every SwiftUI arm: `NSHostingView role=AXGroup
sub=AXHostingView`, parent `NSWindow`. The private `AXHostingView` subrole is
not copied.

**Cost if wrong.** VoiceOver announces one extra group level on entering the
window.

## AB-O — zero-area nodes are not published; a duplicated id is published once

**What.** The builder skips a node whose published frame has zero width or
height, and an id already seen in emission order.

**Why.** `hidden()` filters layout but not prepaint, so a hidden subtree
registers at `(0, 0) 0×0` (CLAUDE.md's inert table) and would otherwise be read
aloud. Two siblings with the same `.id(_:)` mint one `GlobalElementID`; the
second emission already overwrote the first in `axNodes`, so publishing the id
twice would give one object two parents.

**Evidence.** Reading. Lane 1's `aHiddenSubtreeIsNotPublishedAndADuplicatedIDIsPublishedOnce`.

**Cost if wrong.** A legitimately zero-height element with a label (a
divider marked for accessibility) is silent. No probe arm measures SwiftUI's
answer for a zero-area labelled view.

## AB-P — `Stack` publishes declaration order; SwiftUI publishes front to back

**What.** No reordering. A recorded divergence, deferred.

**Evidence.** Arm 4: `ZStack { Text Under; Text Over }` lists `Over` first,
`Under` second, and their x positions (104.5, 100.25) rule out a geometric
sort.

**Why deferred.** The builder cannot tell a `Stack`'s children from a
`Column`'s: neither emits a node. Fixing it needs `Stack` to mark its subtree,
which is a change to a shared element for an ordering no test here can see
through AppKit alone.

**Cost if wrong.** VoiceOver reads an overlay badge after the content under it.

## AB-Q — scope

**In:** lanes 1–3 of the spec, on the legacy element path plus
`OnTapModifier`. **Deferred, with owners:** proposal-path emission (tasks 6/11);
scroll areas and scrolling to unrealized rows (task 10); `Stack` order (`AB-P`);
modal isolation and press occlusion (task 12's interaction half); hidden,
children-combination modifiers, extra traits, custom actions and declared
actions (task 9's button half); system settings (task 13); iOS (task 14);
reading `Frame.axNode(for:)` (`AB-D`); writing `AXNode.children` back (`AB-C`).

**Cost if wrong.** The human look opens with gaps a user will hit in the demo:
the 500-row list cannot be walked past the realized rows, and the modal's
background stays reachable. Both are named in the human script so they are
not reported as bridge defects.

## AB-R — the seam's two requirements have no default implementations

**What.** `onAccessibilityRequest` and `publishAccessibilityTree(_:)` are
plain requirements. `AppKitWindow` and `FakePlatformWindow` implement them.

**Why.** A protocol-extension default compiles a conformer into a window
VoiceOver cannot see, with no diagnostic: this repo's most-recorded failure
shape. Three tracks merge afterwards; a merge that adds a conformer without
these fails to compile rather than silently.

**Cost if wrong.** Every future conformer carries two lines. That is the point.

## AB-S — what the probe proves, and what it does not

**What.** The probe reads SwiftUI's accessibility objects in-process after
setting `AXEnhancedUserInterface`, through KVC on the modern selectors and
typed IMP calls for the perform methods.

**Limits.** (1) It records what SwiftUI answers to those reads on macOS 26.6.2,
not what VoiceOver speaks. (2) `AXEnhancedUserInterface` is how *this* probe
switched SwiftUI's tree on; that VoiceOver uses the same switch is not
established. (3) Swift `as? NSAccessibilityProtocol` fails on SwiftUI's nodes
and the informal attribute API answers `nil` for them, so a reader repeating
this with either would conclude SwiftUI exposes nothing. (4) `responds(to:)` is
true for every selector on every object and is not evidence. (5) No arm observes
notifications (`AB-K` is judgement). (6) The AppKit `NSButton` control proves
the walker reads real attributes; it does not prove KVC reads the same values
AppKit's accessibility server would — both paths call the same selectors.

**Cost if wrong.** A ruling built on an arm that reads differently under
VoiceOver. The human script's items are chosen to check exactly the rulings
that lean hardest on the probe: `AB-B`, `AB-F`, `AB-G`, `AB-L`.
