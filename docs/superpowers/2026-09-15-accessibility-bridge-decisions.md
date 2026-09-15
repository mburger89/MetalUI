# Accessibility bridge — decisions

Rulings for the accessibility-bridge half of plan task 12
(`docs/superpowers/plans/2026-09-12-swiftui-alignment.md`). They are prefixed
**`AB-`** and **lettered** (`AB-A`, `AB-B`, …), with two-letter tails after
`AB-Z`. **A bare `AB-3` is a typo, not a citation.** The next unused letter is
`AB-AA`.

Read alongside:

- `docs/superpowers/specs/2026-09-15-accessibility-bridge-design.md`: the
  three lanes, their API, tests and mutations, and the merge contract.
- `docs/probes/swiftui-accessibility-bridge.swift`: the first SwiftUI probe.
  "Arm N" below means its arm N.
- `docs/probes/swiftui-accessibility-bridge-rules.swift`: the critic-round
  probe. "Arm Rn" and "arm Q" mean its arms.
- `docs/probes/appkit-accessibility-overrides-typecheck.swift`: the
  re-runnable typecheck of the AppKit spellings, with a negative control.
- `docs/record/12-accessibility-bridge.md`: this track's record, including the
  human VoiceOver script.
- Rulings this track leans on: `TB-M` (children stay a field; order is not
  recoverable from keys), `TB-AG` (AX data on `Handlers.axNode`), `TB-S` (the
  `$ax` slot's footprint), `EP-5` (prefer SwiftUI above the engine), `AP-I`
  (`Deferred` hoists to the root), `MP-I` (a `List`'s first frame is
  unbounded).

## How to read the letters

**Written at design time (2026-09-15, at `f64e58a`), before any lane runs, and
revised the same day after one critic round.** Each ruling gives:

- what was decided;
- why;
- the evidence, and which kind it is: a probe arm, a measurement, or a reading;
- what it costs if wrong.

A ruling the critic round changed says so under **Revised**. Implementation
lanes append their red runs and mutation records under the ruling they
exercise, the way `SA-J`…`SA-M` carry theirs.

- `AB-A`…`AB-E`: the tree, the seam, identity and geometry (lanes 1–2).
- `AB-F`…`AB-J`: what a node says, and what a client can do with it
  (lanes 1–3).
- `AB-K`…`AB-M`: notifications, virtualization, and the cost instruments.
- `AB-N`…`AB-P`: smaller shape decisions, and one recorded divergence.
- `AB-Q`: scope and deferrals. `AB-R`: the seam has no defaults. `AB-S`: what
  the probes can and cannot prove.
- `AB-T`…`AB-Z`: added by the critic round. They cover:
  - distribution;
  - records instead of emissions;
  - portals;
  - hit testing;
  - unbounded lists and lazy elements;
  - `OnTapModifier`;
  - the merge contract.
- **"Critic round"** at the end maps each finding to what was done.

---

## AB-A — the bridge is a neutral tree pushed through a two-requirement seam

**What.** `Window` builds an `AccessibilityTree` and hands it to
`PlatformWindow.publishAccessibilityTree(_:)`. The tree is a value in
`MetalUIPlatform`, with no AppKit. The platform answers clients from that value
and sends `AccessibilityRequest`s back through `onAccessibilityRequest`.
Diffing, element objects and notifications live on the platform side. Node
identity is `AccessibilityNodeID`, an opaque `AnyHashable` wrapper that
`MetalUI` fills with a `GlobalElementID`. **Geometry is a separate dictionary
from structure** (`AB-K`).

**Why.**

- `MetalUIPlatform` cannot import `MetalUI` (target dependencies are one-way),
  so it cannot see `GlobalElementID` or `AXNode`.
- A value tree lets the fake platform record exactly what was published. That
  is the dispatch's "implement it in the fake platform so tests can assert what
  is published".
- The same value gives a future UIKit conformer its input.
- `onInput(InputEvent) -> Bool` is the existing precedent for the request
  shape.

**Evidence.** Reading (`Package.swift` target graph; `Platform.swift`).

**Cost if wrong.**

- **A pull requirement.** The platform may need live access to the element
  tree, for example to realize off-screen `List` rows on demand for VoiceOver.
  A pushed value is then not enough, and a pull requirement is added. That is
  additive to this seam, not a rewrite.
- **Allocation.** `AnyHashable` could cost an allocation per id per build.
  That is paid only while a client is active (`AB-B`). A `UInt64` token table
  in `Window` is the fallback.

## AB-B — nothing is collected until a client is present; two triggers; activation is sticky

**What.** A window records and publishes nothing until the first of two
triggers sends `.activate`:

1. **A query.** The host view's first accessibility query:
   `accessibilityChildren`, `accessibilityHitTest` or
   `accessibilityFocusedUIElement`.
2. **The VoiceOver signal.** `NSWorkspace.shared.isVoiceOverEnabled` observed
   `true`, through KVO with `.initial`: at bridge creation if VoiceOver is
   already running, or when it starts.

`Window` then marks itself dirty, and every later frame is built with
`collectsAccessibility = true`. It never deactivates.

When only the first trigger fires, that first query is answered from the empty
tree, and the tree arrives one frame later with a `.layoutChanged`. With
VoiceOver already running, the window is active before its first frame. In
either case a `List`'s unbounded first frame publishes no rows (`AB-X`).

**Why collect nothing before a client.** Paying for records, a tree build and a
publish in every frame of every app, VoiceOver or not, is the per-frame cost
the dispatch rules out. SwiftUI also builds nothing until a client is
signalled.

**Why the query trigger stays.** `isVoiceOverEnabled` is VoiceOver's own flag.
Other clients never set it, including Switch Control, Voice Control,
Accessibility Inspector and third-party AX utilities. The only client-agnostic
signal observable on our own view is the query.

**Why add the VoiceOver trigger.** It answers the commonest real case, VoiceOver
already running when the window opens, without the empty first read and its
one-frame gap. `App` owns no `NSApplication` subclass, so the application
attribute SwiftUI reacts to (arm 2) is still not observable.

**Evidence.**

- **Probe arms 1 and 2.** A hosted `Text` exposes **0** accessibility children
  on an in-process ask, and still **0** after a second ask and a run-loop spin.
  After the process sets `AXEnhancedUserInterface` on `NSApp`, the same host
  exposes **1** child (`AXStaticText`, value `Hello`). So SwiftUI builds nothing
  until it believes a client is present, and an in-process query is not its
  trigger.
- **Arm Q.** A real key window, first responder, synthesized mouse and key
  events and a resize produce **no** accessibility call on a plain content
  view: `[]`. The positive control in the same arm logs
  `["isElement","focused","isElement","children","role"]` for in-process
  queries. So AppKit itself does not activate a window, and only a client (or
  in-process code) does.
- **Arm R13.** `observe(\.isVoiceOverEnabled, options: [.initial, .new])`
  delivers its initial value, `false`, on a machine without VoiceOver running.
  **Unmeasured:** that the value flips when VoiceOver starts. That is item 1 of
  the human script.
- **Pins.** Lane 2's `aRunningScreenReaderActivatesTheWindowBeforeAnyQuery`
  (scripted signal). End-to-end `aKeyWindowReceivingEventsIsNeverActivatedWithoutAClient`
  pins arm Q against the real host view.

**Revised (critic finding 13).** The first version had only the query trigger.
It dismissed the application attribute as unobservable without weighing the
public `NSWorkspace` property.

**Cost if wrong.**

- **The first read.** A non-VoiceOver client whose first read is taken as final
  sees an empty window. The fallback is to answer the first query synchronously
  from the last frame's hitboxes.
- **In-process queries.** Anything in-process that queries the host view (a
  test, a debugging tool) turns collection on for the window's lifetime. That is
  a cost, not a defect.
- **VoiceOver running elsewhere.** A VoiceOver user pays collection in every
  MetalUI window, including windows VoiceOver is not reading: the population
  SwiftUI also pays for.
- **A stale signal.** If `isVoiceOverEnabled` lags VoiceOver's start, the query
  trigger still catches it.

## AB-C — hierarchy is the nearest recorded ancestor in the same portal, ordered by record

**What.** A node's parent is the nearest `GlobalElementID.parent` ancestor that
recorded this frame **and has the same portal ordinal** (`AB-V`). If there is
none, the node is a root. Siblings are ordered by record order
(`Frame.axEmissions`, kept only while collecting). Containers that record
nothing are transparent, and so is a distributor (`AB-T`). The hierarchy lives
in the published `AccessibilityTree`; `Frame.axNodes[id].children` stays `[]`.

**Why.**

- **Keys cannot carry order.** `TB-M` proved it: a name discards the
  positional index, so `x, y` and `y, x` give identical key sets.
- **Record order can.** `TB-M` did not weigh it. Prepaint visits children in
  declaration order, and every conformer registers before descending, so record
  order is a pre-order traversal.
- **No protocol change.** No `ElementGroup` associated-type change is needed.
- **SwiftUI flattens too.**

**Evidence.**

- **Probe arms 3 and 9.** `VStack { Text A; Text B }`, with or without
  `.onTapGesture`, exposes two `AXStaticText` children directly under the host,
  and no group.
- **Record order, by reading.** `Box`, `Stack`, `FrameModifier` and
  `OnTapModifier` each call `registerHandlers` on the line before
  `content.prepaintGroup`. `Text` is a leaf. `Deferred` prepaints inline under
  `pass.deferred`.
- **The measurement.** Lane 1's `childrenFollowDeclarationOrderWhereIDsAloneCannot`
  measures record order, on `TB-M`'s own counterexample.

**Why not write `AXNode.children` back.** `Frame.axNodes` is a per-frame
emission record. Its tests pin "declared nothing, emitted nothing". Filling
children there would mean a second pass over every frame's nodes, including
`List`'s always-on node, when no client exists. The integration step should
update record §05's `AXNode.children` row: it is still always empty, but no
longer because the hierarchy is unrecoverable.

**Revised (critic finding 9).** The parent walk ignored portals, so `Deferred`
content attached to whichever recording ancestor declared it.

**Cost if wrong.**

- **Silent reordering.** VoiceOver's navigation reorders silently if a
  conformer registers after its children, or a container prepaints children out
  of declaration order.
- **Tolerated, and not.** The builder's two-pass assembly tolerates the first.
  The second would need an explicit sort key.

## AB-D — one element object per id while it stays published; detached on first absence; no revival; created only when read

**What.**

- **One object per id.** The AppKit bridge keeps one
  `AppKitAccessibilityElement` per `AccessibilityNodeID`. It is **created the
  first time a client is handed it** (`AB-X`), and kept for as long as every
  published tree contains the id.
- **Detach.** On the first tree without the id, a vended element is detached:
  - parent `nil`, and absent from every children list;
  - every action refused;
  - its last role, label and value kept;
  - `accessibilityFrame()` still its last content rect, converted through the
    host view while that view is alive, `.zero` after;
  - one `.uiElementDestroyed` posted.
- **Return.** If the id returns, a new object is created on the next read.
- **Tombstones.** The bridge does not use `Frame.axNode(for:)` (the `$ax`
  tombstone), which stays unread.

**Ownership.**

| holder | holds | strength |
|---|---|---|
| `AppKitWindow` | the bridge | strong |
| the host view | the bridge | strong |
| the bridge | the host view | weak |
| the bridge | vended elements | strong, until detach |
| an element | the bridge | weak |

After detach, only a client retains an element. There is no cycle.

**Why.**

- **A held handle reports itself invalid.** Design spec §9 asks that a held
  handle "reports itself invalid rather than vanishing". A detached object does
  exactly that, without a second liveness notion.
- **Reviving would be wrong.** Identity is structural: a vanishing `if` makes
  the trailing sibling adopt the id. A revived handle would silently point at a
  different element, which is worse than useless.

**Evidence.** Probe arm 12.

- **Across a value update** (`Count 0` → `Count 1`), SwiftUI keeps all three
  `AccessibilityNode` objects: `[true, true, true]`.
- **When the conditional `Text` vanishes**, the survivors keep their objects.
  The removed node still reads `value=Conditional`, `parent=nil`, and its last
  frame `(100.0, 384.0, 69.0, 16.0)`.
- **When the conditional returns**, its node is a **new** object: `false`.

**A MetalUI consequence the probe does not share.** In SwiftUI the two
survivors keep their objects because SwiftUI's identity for `if` content is not
positional. In MetalUI the trailing siblings adopt the vanished ids:

- the object that read `Conditional` now reads `Count 1`, a `.valueChanged`;
- the object for the last id is the one detached.

That is CLAUDE.md's identity rule, not a bridge defect, and naming the trailing
sibling is the same remedy.

**Revised (critic finding 14).** It now specifies a detached element's frame
and the ownership graph. It also specifies lazy creation (finding 4).

**Cost if wrong.** A client that caches an element across a one-frame absence
(an element briefly culled) loses its place. No MetalUI element is culled for a
single frame today, with one exception: a `List` on its unbounded first frame
publishes no rows (`AB-X`). No element exists for them yet, so there is nothing
to lose.

## AB-E — frames: content space, scroll-translated, unclipped for reading, converted to screen at read time

**What.** A published `AccessibilityGeometry.frame` is in window-content
points: top-left origin, `Frame.activeOffset` applied, **no clip**. Beside it,
`visibleFrame` is that rect intersected with the active clip, and it is used
only for hit testing (`AB-W`). `Frame.emitAXNode` is fixed to translate the way
`insertHitbox` does. The AppKit element computes its screen rect in
`accessibilityFrame()`, from the host view, every time it is asked: first
`convert(_:to: nil)`, then `window.convertToScreen`. Nothing screen-space is
stored.

**Why.**

- **Translation.** An untranslated rect puts every node inside a scrolled
  `ScrollView` at its content-space position, so VoiceOver's cursor would
  outline the wrong place.
- **Converting at read time** keeps frames right when the window moves. A move
  publishes nothing, because no frame is drawn.

**Evidence.**

- **The translation defect, by reading.** `Frame.swift:745-746` against
  `:564-567`. Lane 1's `aNodeInsideAScrolledScrollViewReportsItsOnScreenFrame`
  is its first measurement. It is written first as a Frame-only test that
  compiles on `f64e58a` and reads 100.
- **Unclipped children, arm R17.** `ScrollView { LazyVStack { ForEach(0..<500) } }`
  in a 200pt scroll area realizes 25 children. **12 lie wholly outside the
  scroll area and still report full 16pt frames**; the last is at
  `(227.25, -513.0, 45.5, 16.0)`. The other 13 intersect it, which is the
  control.
- **Unclipped container, arm 14b.** The lazy container itself reports
  `(227.25, -513.0, 45.5, 813.0)`.
- **Screen convention.** Every probe frame is bottom-left screen space. A 16pt
  `Text` at the top of a 300pt content rect with origin y = 100 reads
  y = 384.

**Revised (critic finding 10).** The first version cited arm 14b for
unclipped children, but it printed only the container and two visible rows.
Arm R17 is the measurement. The hit-test rect is split off into `AB-W`.

**Cost if wrong.** If `Deferred`'s root-clip reset left a stale offset, portal
content would be displaced. `pushRootClip` pushes a zero offset, by reading, so
this is not expected. No test covers a portal inside a scroller.

## AB-F — role, label and value follow SwiftUI's static-text rules; `generic` is `AXGroup`

**What.** While collecting, after distribution (`AB-T`):

**Text rules, for a `Text` that is not clickable:**

| declared | publishes | arms |
|---|---|---|
| nothing | `.staticText`, its string as **value**, no label | 1, 3 |
| only a label | that label as its **value**, no label | 10a, R4 |
| **a value** | label = the declared label, or its own string; value = the value | 11, R1, R2, R18 |

**Role map.**

| condition | role |
|---|---|
| `logicalCount != nil`, whatever the declared role (`AB-L`) | `AXTable` |
| `logicalIndex != nil` | `AXRow` |
| `generic`, `container` | `AXGroup` |
| `button` | `AXButton` |
| `text` | `AXStaticText` |
| `image` | `AXImage` |

**Traits.** `selected` → `accessibilitySelected`. `disabled`, **or the record's
`isEnabled == false`** (`AB-Z`) → `accessibilityEnabled = false`.
`updatesFrequently` is dropped: it has no macOS counterpart.

**Evidence.**

- **Arms 1 and 3:** `AXStaticText`, `value=Hello`, `label=nil`.
- **Arm 10a:** `Text("Hello").accessibilityLabel("Greeting")` gives
  `value=Greeting`, `label=nil`.
- **Arms R0 and R1:** `Text("vol").accessibilityValue("5")`, with and without
  the adjustable action, gives `label=vol value=5`. The label is the Text's own
  string.
- **Arm R2:** `Text("vol").accessibilityLabel("L").accessibilityValue("5")`
  gives `label=L value=5`.
- **Arm R18:** a value distributed onto `Text("A")` gives `label=A value=V`.
- **Arm R12, for a clickable node:** `Button("vol").accessibilityValue("5")`
  gives `label=vol value=5`.

**Revised (critic finding 1).** The first version's third bullet read "a label
and a value publish both unchanged". Its pseudocode had no branch for a value
with no label, so `Text("vol").accessibilityValue("5")` would have published
`label=nil value=5`. That is exactly the case arm 11 measured, and lane 3's
test sidestepped it by also declaring the label. The rule now has the branch,
and the test has the value-only arm, whose mutation deletes it.

**Divergence, recorded (arms 10b, R6, R11).** A labelled `Color` is
`AXUnknown` with that label, in SwiftUI. So is a labelled container whose only
child is inaccessible. MetalUI publishes `AXGroup` for a labelled `generic`
node:

- a focusable or clickable generic node must be navigable;
- `AXUnknown` is the role AppKit gives to things it cannot classify.

The human script checks that VoiceOver reads a labelled group.

**Cost if wrong.** If VoiceOver reads `AXGroup` as a container to enter rather
than an item, labelled leaves take an extra keystroke. The fix is one map entry.

## AB-G — an `onClick` element is a button, AX press runs `onClick`, and a button combines its texts

**What.** While collecting:

- **Role.** An element with `onClick` and no declared role publishes `.button`
  with `.press`.
- **A clickable `Text`** is a button labelled by its string, unless it declares
  a label.
- **A button whose kept descendants are all non-interactive publishes no
  children.** If it has no label, it takes their resolved labels (or values),
  joined with `", "`.
- **A button with an interactive descendant** keeps its children and its own
  label, `nil` included.
- **Portal content is not a descendant**, because it is a root (`AB-V`).
- `AXPress` on a button runs the element's `onClick`.

**Why.**

- MetalUI has no `Button` until task 9, so `onClick` is the only way to make
  something activatable. The dispatch requires "press → the element's onClick".
- An unlabelled button with text children is the anti-pattern screen-reader
  users hit most.

**Evidence.**

- **Arm 5:** SwiftUI `Button("Go")` is `AXButton`, `label=Go`.
  `accessibilityPerformPress` returns `true`, with the closure run once.
- **Arm 6:** `Button { HStack { Text A; Text B } }` is one `AXButton` labelled
  `A, B`, with zero children.
- **Arm R5:** a padded, labelled `Button` is `AXButton label=X` with zero
  children.

**Divergence, recorded and deliberate: tap gestures are pressable here.**

- **Arm 7:** `Text("Tap").onTapGesture` stays `AXStaticText`.
  `accessibilityPerformPress` returns **`false`**, with the closure run **0**
  times.
- **Arm 8:** adding `.accessibilityAddTraits(.isButton)` makes it `AXButton`
  labelled `Tap`, and press **still** returns `false`, closure 0 times.

So on macOS 26 a SwiftUI tap gesture is not pressable through accessibility,
even when it claims to be a button. MetalUI makes `onClick` pressable. When task
9 adds `Button`, the question "should bare `onClick` revert to SwiftUI's
answer" belongs to that task.

**Divergence, recorded: an interactive descendant (arm R7).**
`Button { HStack { Text A; Toggle B } }` collapses into **one `AXCheckBox`
labelled `A`, value `1`**. The button's own press is no longer a separate
element. MetalUI keeps the button unlabelled, with both children reachable,
for two reasons:

- collapsing would force choosing one of two handlers for one element's press;
- MetalUI has no `Toggle` whose semantics could absorb the button.

**Revised (critic finding 2).** The first version claimed the
interactive-descendant rule had no probe arm. Arm R7 now measures SwiftUI doing
the opposite, and it is recorded as a divergence. Arm R5 adds that a labelled
button also drops its children.

**Cost if wrong.** Clickable containers that are not conceptually buttons, such
as a row that selects, are announced as buttons. A declared role overrides
that. The R7 divergence makes such a composite read as "button, group of two"
where SwiftUI reads one checkbox.

## AB-H — advertised actions are derived from the last frame's live handlers

**What.**

- **Advertised.** `.press` is advertised iff the last frame's `hitboxes` hold
  an `onClick` for the id. `.increment`/`.decrement` are advertised iff the last
  frame's focus registry holds an `AccessibilityAdjustment` action handler for
  it.
- **Dispatched.** A press runs that hitbox's `onClick`, and an adjustment runs
  that handler.
- **Not consulted.** `AXNode.actions`, as declared by a caller.
- **Gated.** The AppKit element gates each perform selector per instance with
  `isAccessibilitySelectorAllowed(_:)`.

**Why.**

- The dispatch says actions are "routed back through the existing handler
  dispatch".
- `lastHitboxes` is the record click dispatch already resolves against, so a
  press is refused exactly where a click would find nothing.
  `allowsHitTesting(false)` removes both. After the environment merge, so does
  `.disabled(true)` (`AB-Z`).
- Advertising an action with no handler would tell VoiceOver a control works
  when it does nothing.

**Evidence.** Reading: `Window.dispatchClick`, and `Frame.registerHandlers`'
`hitTestingDisabledDepth` gate.

- **The allowsHitTesting measurement.** Lane 1's
  `aPressIsRefusedWhereHitTestingIsDisabled`. It uses a test-local wrapper
  calling `PrepaintPass.allowsHitTesting(false)`, because the legacy path has no
  such modifier.
- **The vacuous-mutation fix.** Lane 1's
  `aPressRequestRunsOnClickThroughTheLastFramesHitboxes` now gives its
  non-clickable box a declared node. Without one, the box published nothing, and
  "it has no `.press`" was vacuous (critic finding 8).

**Not checked: occlusion.** A click lands on the topmost opaque hitbox. A press
goes to the named element even under a `Deferred` scrim. That is deferred with
modal isolation (`AB-Q` item 4).

**Cost if wrong.** `AXNode.actions` becomes a declared-but-inert field. The
integration step should add it to the inert table until task 9 either reads it
or removes it.

## AB-I — adjustment is an `Action`, with SwiftUI's modifier name

**What.**

- `AccessibilityAdjustment: Action` carries an
  `AccessibilityAdjustmentDirection`.
- `StyledElement.accessibilityAdjustableAction(_:)` registers it through the
  existing `onAction`.
- Increment and decrement requests dispatch to the element's own handler only,
  not up the focus chain.

**Why.**

- It reuses the action registry the keyboard already uses. No `Handlers` member
  is added, so `HandlerShape` does not fall behind a third time.
- Only the element itself: an ancestor's handler would make a node claim an
  action on behalf of another.

**Evidence.** Arm 11: `accessibilityAdjustableAction` on a `Text` returns
`true` from both perform methods, and its closure sees `["increment",
"decrement"]` in call order. The node stays `AXStaticText` with its label and
value.

**Cost if wrong.** A keymap binding to `AccessibilityAdjustment` also works
from the keyboard. Harmless, and arguably useful.

## AB-J — accessibility focus is `Window.focus`

**What.**

- **Published.** `focused` is the window's focus after the frame's read-back,
  when that element published a node.
- **Host query.** `accessibilityFocusedUIElement` on the host view answers that
  element, or **the host view when nothing is focused**.
- **Setter.** `setAccessibilityFocused(true)` sends `.focus(id)`, which calls
  `Window.focus(_:)` only if the last frame found the id focusable.
  `setAccessibilityFocused(false)` is ignored.
- **Timing.** The element reports the new focus after the next frame publishes,
  and a `.focusedUIElementChanged` is posted then.

**Why.**

- Design spec §9: "AX focus and §8.3 focus handles are the same focus; the
  bridge reflects one into the other rather than maintaining two."
- Routing through `Window.focus` inherits its validation and its dirtying.

**Evidence.** Probe arm 13, with a control.

- **Before any request,** SwiftUI's host reports the first focusable `Text`
  ("Other") as focused, while the bound `@FocusState` has seen no change (`[]`).
- **After `setAccessibilityFocused(true)` on the second `Text`,** the
  `@FocusState` flips (`[true]`) and the host reports the second node.

So an accessibility focus request drives app focus state.

**Divergence, recorded (critic finding 14).** With nothing focused, SwiftUI's
host reports the **first focusable node** (arm 13). MetalUI reports the **host
view**. In MetalUI, focus is explicit ("clicking does not focus",
CLAUDE.md), and `Window.focusedElement == nil` means no element holds the
keyboard. Reporting one would tell VoiceOver the keyboard reaches an element
that ignores keystrokes. Lane 2's `focusIsReportedFromTheTreeAndAFocusRequestIsSent`
names "report the first focusable node" as the mutation it must redden.

**Cost if wrong.**

- **Lag.** There is a one-frame window in which `isAccessibilityFocused()`
  still answers the old element after a request. SwiftUI's arm read after a
  0.5 s spin, so the probe cannot say whether SwiftUI lags the same way.
- **The divergence.** If VoiceOver relies on a non-nil focused element to place
  its cursor, a MetalUI window with nothing focused starts VoiceOver at the
  window. That is item 5 of the human script.

## AB-K — notifications: only real structural changes, only for elements a client has seen, coalesced per read, never for geometry

**What.** Per publish, on the platform side:

1. **Before activation:** store the tree, post nothing.
2. **Geometry-only change** (`hasSameStructure`): store the tree. **No element
   is touched, nothing is posted.**
3. **Structural change**, from `AccessibilityTreeChanges`:
   - **One `.uiElementDestroyed` per removed id that had a vended element**
     (`AB-X`).
   - **One `.layoutChanged` on the host view,** if the id set, roots, any
     children list or any role changed, **and a client has read a children
     list, hit test or focused element since the last `.layoutChanged`**.
     Activating by query counts as a read.
   - **One `.titleChanged` / `.valueChanged` / `.rowCountChanged`** per changed
     id that has a vended element.
   - **One `.focusedUIElementChanged`** on the newly focused element (vending
     it), or on the host view when focus clears.
   - **Nothing for a created element.**

`Window` does not publish a tree equal to the last one (`AB-M`), so an
unchanged frame never reaches the bridge.

**The rate, recorded rather than argued away.** While a client is active,
anything that moves draws a frame, and each such frame costs one tree build
and one publish. That covers an animation, a scroll and a resize. On the
platform side:

- **An animation or a resize** is a geometry-only publish, which does a
  structure comparison and a stored assignment.
- **A `List` scroll that shifts the realized window** is a structural publish
  on most frames: a trackpad fling moves more than 28pt per frame. It does the
  diff and updates `parents`. It posts nothing unless a vended row left, or a
  client read since the last `.layoutChanged`.

Measured-by-design counts: lane 3's
`scrollingAListPostsBoundedNotificationsAndBuildsOncePerFrame` gives 60 builds,
1 `.layoutChanged`, and one destroyed post per vended row, over 60 frames.
`anAnimationWithAClientActivePostsNothingAndTouchesNoElement` gives 0 posts
over 30 ticks.

**Why.**

- **Posts.** A notification per tick is the "per-frame spam" the dispatch rules
  out. Frames are read lazily (`AB-E`), so nothing needs announcing.
- **No `.created`.** `.layoutChanged` already tells a client to re-read
  children, and posting per `List` row entering the window is the spam again.
- **Coalescing on read.** It bounds `.layoutChanged` to one per client read, so
  a client that is not reading is not told again and again that something it
  has not looked at moved.
- **Destroyed only for vended elements.** A client cannot hold an element it
  was never handed.

**Evidence.** None from SwiftUI: the probes read state and cannot observe what
SwiftUI posts. This is AppKit's documented notification vocabulary, applied by
judgement. Lane 2's recorder tests and lane 3's cost tests pin each count.

**Revised (critic finding 5).** The first version said nothing is posted "when
only frames change". It did not see that:

- a scrolling `List` changes the id set on most frames;
- geometry sat inside `AccessibilityTree`'s `Equatable`, so every animation
  tick republished and rebuilt element maps.

Geometry is now split out, posts are coalesced, and the rate is recorded.

**Cost if wrong.**

- **Coalescing.** Suppose VoiceOver keeps a children list without re-reading
  it, and relies on repeated `.layoutChanged` posts to notice later changes.
  Its view goes stale during a long scroll. Human script item 6 is the check.
  The fix is to key the flag per container, or to drop it.
- **Missing notifications.** If VoiceOver needs `.created` or `.moved` to keep
  its cursor on a scrolling row, item 6 shows a lost cursor. The fix is
  additive in `publish`.

## AB-L — a virtualized `List` is an `AXTable` whose row count is its logical count

**What.**

- **The list node.** Any node with `logicalCount` publishes as `AXTable`,
  **whatever its declared role**, with `accessibilityRowCount = logicalCount`.
- **Rows.** While collecting, and while the list's window is **bounded**
  (`AB-X`), each realized row `Box` carries the internal
  `logicalIndex = window.lowerBound + offset`. It publishes as `AXRow` with
  `accessibilityIndex`.
- **Row lists.** `accessibilityRows` is the realized rows.
  `accessibilityVisibleRows` is those with a non-empty `visibleFrame`.
- **Row hints are not declarations.** `logicalIndex` is stripped before the
  declaration test, so a row hint never writes `axNodes` or `$ax` (`AB-U`). It
  is internal, so a third-party container cannot set it (`AB-Q` item 10).

**Why.**

- The dispatch: "List's logicalCount must map to a row count."
- Design spec §9's "3 of 500" needs both halves: the 500 (row count) and the 3
  (row index). `TB-M`'s blocker had left nothing to attach them to.
- **Table whatever the role.** `List.requestLayout` sets `role = .container`
  only when `listHandlers.axNode.isEmpty` (`List.swift:389`). So
  `.accessibilityLabel("Contacts")` leaves the role `generic`, and a
  container-only table mapping would silently turn the list into a group with
  no row count.

**Evidence.**

- **Arm 14a:** SwiftUI's `List(0..<500)` is an AppKit
  `SwiftUIOutlineListView`, `AXOutline`, `rows=500`: every logical row present
  as an element.
- **Arm 14b:** `ScrollView { LazyVStack { ForEach(0..<500) } }` exposes an
  `AXOpaqueProviderGroup`/`AXOpaqueProviderList` with **25** realized children.
- **Arm R16:** a labelled `List(0..<500)` is still `AXOutline`, `label=Contacts`,
  `rows=500`.

**Divergence, recorded.** MetalUI is neither of those:

- `AXTable` rather than `AXOutline`, because no disclosure levels exist;
- realized rows rather than 500 row elements.

Whether VoiceOver announces "row 41 of 500" from `AXRowCount` and `AXIndex`,
rather than counting `AXRows`, is **unmeasured**. That is item 4 of the human
script. The demo's own row text also says "Row N of 500", so the script checks
with Accessibility Inspector as well as by ear (`AB-Y`). Rows outside the
window cannot be reached (`AB-Q` item 2).

**Revised (critic finding 3).** The first version mapped `.table` only from
`container` with `logicalCount`, so a labelled `List` lost its table.

**Cost if wrong.** VoiceOver says "N of 17". The alternatives are `AXList`
(children counted), or synthesizing placeholder row elements for the full
count, which is the allocation `List` exists to avoid.

## AB-M — the cost instruments are counts, and an unchanged tree is not republished

**What.** The performance evidence is counts:

| side | instrument |
|---|---|
| window | `WindowAccessibility.buildCount`, `.publishCount`, `.lastEmissionCount` (written every frame, active or not) |
| fake platform | `publishedAccessibilityTrees` |
| bridge | `createdElementCount`, `structuralPublishCount`, `geometryPublishCount` |
| recorder | posted notifications, by name and target |
| state | `StateTable.count`, active against inactive (`AB-U`) |

`frameDidRender` builds only when active, and publishes only when the tree
differs (`Equatable`, geometry included).

**Why.**

- CLAUDE.md: performance tests count work, never wall clock.
- The dispatch: "No per-frame allocation regressions: count published
  elements/notifications."
- **The inactive path** costs one `Bool` read per `registerHandlers` call, plus
  one `Int` store per frame. Lane 1's and lane 3's inactive tests pin that
  nothing else runs.
- **`lastEmissionCount` exists because of critic finding 7.** The first
  `anInactiveWindowBuildsAndPublishesNothing` could not be reddened by its own
  named mutation, "pass `collectsAccessibility: true`": the build is an
  autoclosure, so both of its assertions stayed green.
- **No `malloc_logger` count.** `FreezeLoopAllocationTests`' instrument was
  considered and not used. There is no pre-feature baseline to compare a
  frame's allocation count against inside one build, and the work counters
  discriminate the mutations that matter.

**Revised (critic finding 8).** `publishedNodeCountTracksRealizedRowsNotDataCount`
asserted one publish per drawn frame, which is false for identical frames under
this ruling. That assertion is gone. Lane 3's cost tests assert builds per
frame, and publishes only where a change is guaranteed.

**Cost if wrong.** An allocation added on the inactive path that none of the
counters see (for example in `Frame.init`) goes unnoticed. The equality check
is O(nodes) per drawn frame while active, paid instead of an unconditional
publish.

## AB-N — the host view is an `AXGroup` element

**What.** `MetalHostView` answers `isAccessibilityElement() == true` and role
`AXGroup`. Roots are its children, and it is their parent.

**Evidence.** Every SwiftUI arm reads `NSHostingView role=AXGroup
sub=AXHostingView`, parent `NSWindow`. The private `AXHostingView` subrole is
not copied.

**Cost if wrong.** VoiceOver announces one extra group level on entering the
window.

## AB-O — `display: none` content is not published; zero-area nodes are; a duplicated id is published once

**What.**

- **Hidden content.** While collecting, `Element.prepaintGroup` runs the
  `prepaint` of an element whose layout node has `display == .none` inside an
  accessibility suppression scope. Nothing in that subtree records.
- **No area filter.** A zero-width or zero-height node **is** published.
- **Duplicated ids.** The builder keeps one record per id, at its first
  position with its last content.

**Why.**

- **Hidden.** `hidden()` filters layout but not prepaint (CLAUDE.md's inert
  table), so a hidden subtree still registers, at `(0, 0) 0×0`.
- **The filter's target is `display: none`, not area.** A zero-height labelled
  view is a real, published thing in SwiftUI.
- **Scope.** The check is the "one check in `Element`'s group walk" that
  `Box.focusable()`'s doc names. It is applied to accessibility only; focus
  and paint keep their inert-table behaviour.
- **Duplicates.** Two siblings with the same `.id(_:)` mint one
  `GlobalElementID`. Publishing it twice would give one object two parents.

**Evidence.**

- **Arm R9:** `VStack { Text(H1).hidden(); VStack { Text(H2) }.hidden(); Text(Shown) }`
  publishes only `Shown`. That is `.hidden()` on a leaf and on a container, with
  a published control beside them.
- **Arm R6:** `Color.red.frame(width: 20, height: 0).accessibilityLabel("Divider")`
  **is** published: `AXUnknown label=Divider`.
- **Arm R11:** a labelled `VStack` over an inaccessible 20pt `Color` publishes
  one labelled node.
- **Duplicated ids:** reading. Lane 1's
  `hiddenContentIsNotPublishedButAZeroHeightNodeIsAndADuplicatedIDIsPublishedOnce`
  pins all three.

**Revised (critic finding 2, arm R6).** The first version filtered zero-area
nodes. That silenced a labelled divider, which SwiftUI publishes. It also
dropped every unsized fixture (`Box().onClick {}` is 0×0 under `EP-8`), which
hid defects in the first version's tests (finding 8). The spec now requires
explicit sizes.

**Cost if wrong.**

- **Unhidden decoration.** An unsized clickable or focusable element now
  publishes a 0×0 node that VoiceOver can land on with nothing drawn. It is a
  real element with a handler, so that is arguably correct.
- **Style lookup.** Reading `style(layout.node)` per element while collecting
  copies a `Style`. That is a cost only while a client is active.

## AB-P — `Stack` publishes declaration order; SwiftUI publishes front to back

**What.** No reordering. A recorded divergence, deferred.

**Evidence.** Arm 4: `ZStack { Text Under; Text Over }` lists `Over` first and
`Under` second. Their x positions (104.5, 100.25) rule out a geometric sort.

**Why deferred.** The builder cannot tell a `Stack`'s children from a
`Column`'s, since neither records. Fixing it needs `Stack` to mark its subtree:
a change to a shared element, for an ordering no test here can see through
AppKit alone.

**Cost if wrong.** VoiceOver reads an overlay badge after the content under it.

## AB-Q — scope

**In:** lanes 1–3 of the spec, on the legacy element path.
**`OnTapModifier`** routes a press but synthesizes nothing (`AB-Y`).

**Deferred, with owners:**

| deferred | owner |
|---|---|
| proposal-path emission | tasks 6, 7, 11 |
| scroll areas, and scrolling to unrealized rows | task 10 |
| `Stack` order | `AB-P` |
| modal isolation and press occlusion | task 12's interaction half |
| hidden and children-combination modifiers, extra traits, custom actions, declared actions, a non-button click absorber | task 9's button half |
| system settings | task 13 |
| iOS | task 14 |
| reading `Frame.axNode(for:)` | `AB-D` |
| writing `AXNode.children` back | `AB-C` |
| row indices for third-party virtualized containers (`logicalIndex` is internal) | unowned; any task that adds such a container |

**Cost if wrong.** The human look opens with gaps a user will hit in the demo:

- the 500-row list cannot be walked past the realized rows;
- the modal's background stays reachable;
- the preview toggle is silent.

All three are named in the human script, so they are not reported as bridge
defects.

## AB-R — the seam's two requirements have no default implementations

**What.** `onAccessibilityRequest` and `publishAccessibilityTree(_:)` are plain
requirements. `AppKitWindow` and `FakePlatformWindow` implement them.

**Why.**

- A protocol-extension default compiles a conformer into a window VoiceOver
  cannot see, with no diagnostic: this repo's most-recorded failure shape.
- Three tracks merge afterwards. A merge that adds a conformer without these
  fails to compile, rather than failing silently.

**Cost if wrong.** Every future conformer carries two lines. That is the point.

## AB-S — what the probes prove, and what they do not

**What.** The two SwiftUI probes read SwiftUI's accessibility objects
in-process, after setting `AXEnhancedUserInterface`. They use KVC on the modern
selectors and typed IMP calls for the perform methods. The AppKit typecheck
probe compiles spellings only.

**Limits.**

1. The probes record what SwiftUI answers to those reads on macOS 26.6.2, not
   what VoiceOver speaks.
2. `AXEnhancedUserInterface` is how *these* probes switched SwiftUI's tree on.
   That VoiceOver uses the same switch is not established.
3. **Misleading reads.** Swift `as? NSAccessibilityProtocol` fails on
   SwiftUI's nodes, and the informal attribute API answers `nil` for them. A
   reader repeating this with either would conclude that SwiftUI exposes
   nothing.
4. **`responds(to:)` is not evidence.** It is true for every selector on every
   object. Worse, KVC on a key a SwiftUI node does not implement **raises**
   (`accessibilityRows` on an `AccessibilityNode`, observed in the critic round),
   so the rules probe reads rows only from `NSTableView`.
5. No arm observes notifications (`AB-K` is judgement).
6. The AppKit `NSButton` control proves the walker reads real attributes. It
   does not prove that KVC reads the same values AppKit's accessibility server
   would, though both paths call the same selectors.
7. **Arm Q** shows AppKit sends no query with no client, **in one process on
   one machine**. A system service that queries every window
   (unmeasured) would activate MetalUI windows, and it is also the population
   SwiftUI pays for.

**Cost if wrong.** A ruling built on an arm that reads differently under
VoiceOver. The human script's items check exactly the rulings that lean
hardest on the probes: `AB-B`, `AB-F`, `AB-G`, `AB-L`, `AB-T`.

---

## AB-T — a label or value on a plain container or wrapper is distributed to its children; the outer declaration wins

**What.** A **distributor** is a kept node for which all of these hold:

- its declared role is `generic`;
- it has no `logicalCount` or `logicalIndex`;
- it is not clickable, not focusable and not adjustable;
- it declared a label or a value;
- it has at least one kept child.

A distributor is removed from the published tree, and its children take its
place. Each child's declared label is overwritten by the distributor's declared
label, if any. The same holds for the value. Only then do the child's own text
rules run (`AB-F`). Distribution recurses from the outside in, so in a chain of
wrappers **the outermost declaration wins**. A labelled generic node with no
kept child is not a distributor; it publishes as a labelled group (`AB-F`'s
divergence).

**Why.**

- **Measured SwiftUI behaviour, one rule.** SwiftUI's answer is one rule
  covering containers and wrappers alike, and `EP-5` prefers it.
- **Label placement.** It also settles where a label goes after `.padding` or
  `.frame` without knowing how those are represented. Today they return
  `Box<Self>` and `FrameModifier<Self>`. After the modifier-composition merge
  they return `ModifiedElement`, whose `handling` writes the outermost layer
  (`AB-Z`). In every representation the label lands on a non-interactive
  generic wrapper whose one recording child is the real content. Distribution
  moves it there.
- **The alternative rejected.** "Push the label to the innermost layer" at
  modifier time would need `accessibilityLabel` to know the layer structure. It
  would also not cover `Column { … }.accessibilityLabel`.

**Evidence.**

| arm | declaration | publishes |
|---|---|---|
| R3 | `VStack { Text A; Text B }.accessibilityLabel("L")` | two `AXStaticText`, each `value=L`; no group |
| R14 | `VStack { Text A; Button B }.accessibilityLabel("L")` | `AXStaticText value=L` and `AXButton label=L` |
| R15 | `VStack { Text A.accessibilityLabel("Own"); Text B }.accessibilityLabel("L")` | both `value=L`: the outer label overrides the child's own |
| R18 | `VStack { Text A; Text B }.accessibilityValue("V")` | `label=A value=V`, `label=B value=V` |
| R4 | `Text("Go").padding().accessibilityLabel("X")` | one `AXStaticText value=X` |
| R10 | `Text("Go").frame(width: 120).accessibilityLabel("X")` | one `AXStaticText value=X` |
| R5 | `Button{Text Go}.padding().accessibilityLabel("X")` | one `AXButton label=X` |
| R8 | `Text("Go").accessibilityLabel("In").padding().accessibilityLabel("Out")` | `value=Out` |

**Not measured, and a MetalUI rule.** A focusable or clickable generic node
keeps its label instead of distributing it: it is itself a navigable element.
Lane 3's control arm pins that.

**Cost if wrong.**

- **Repetition.** R3's answer, "L, L", reads worse than one labelled group, and
  a MetalUI author may expect the group. `accessibilityElement(children:)`
  (task 9) is SwiftUI's own escape, and it is not in this track.
- **Clickable wrappers.** If the modifier-composition merge ever makes a
  wrapper layer clickable when the content is, a label on that wrapper stops
  distributing. Arms 2–5 of lane 3's distribution test are the merge's joint
  check.

## AB-U — synthesized nodes are records, not emissions: no `axNodes` entry, no `$ax` slot

**What.** While collecting, `registerHandlers` appends an `AXEmission` record
for anything that has something to say. Only a **declared** node (non-empty
after stripping `logicalIndex`) still goes through `emitAXNode`, which writes
`Frame.axNodes` and the `$ax` `StateTable` slot. It does so exactly as it does
with no client active. Synthesized content never touches either. The builder
reads records, not `axNodes`.

**Why.**

- **Retention would change with VoiceOver.** Writing a `$ax` entry for every
  `Text`, row and clickable element while a client is active changes
  `StateTable`'s population. Reaping engages above `sweepThreshold` (256), so an
  app with about 130 texts would cross it only while VoiceOver runs. Divergence
  18's "retained indefinitely below 256" would then flip to "reaped after two
  generations" depending on whether VoiceOver is running: a semantic side
  effect of turning on a screen reader.
- **The write buys nothing.** `AB-D` never reads the `$ax` tombstone, so the
  write would be pure cost.

**Evidence.**

- **The retention mechanism, by reading:** `Frame.emitAXNode`'s
  `stateTable.withState` and `StateTable.sweepThreshold`.
- **The pin:** lane 3's `aClientDoesNotChangeStateRetention`, equal
  `StateTable.count` active against inactive over 140 synthesized nodes. Its
  mutation writes the slot for synthesized records.
- **The Frame-level pin:** lane 1's
  `aFrameThatDoesNotCollectRecordsNothingAndSynthesisWritesNoRetentionSlot`.

**Revised (critic finding 6).** The first version synthesized through
`emitAXNode`.

**Cost if wrong.** A future reader of `Frame.axNode(for:)` for synthesized
nodes finds nothing, and would have to read records instead. No such reader
exists or is planned.

## AB-V — `Deferred` content is a root

**What.** While collecting, `Frame.pushLayer` assigns each `Deferred` scope a
per-frame portal ordinal, and every record carries the innermost active one (0
outside any portal). A node's parent must share its portal ordinal; otherwise
the node is a root. Nested portals get distinct ordinals, so nested portal
content is a root too. Roots are ordered by record order.

**Why.**

- `AP-I` hoists portal content to the root layer, clip and offset reset.
- **Folded into a button.** A tooltip declared inside an `onClick` box, parented
  by id, would be folded into the button's combined label with its children
  dropped.
- **Under a row.** Declared inside a `List` row, it would become an `AXRow`'s
  child.
- **`Deferred.swift` is untouched.** The flag is recorded where `pass.deferred`
  already pushes the layer.

**Evidence.**

- **Reading:** `PrepaintPass.deferred` pushes `pushLayer`/`pushRootClip`
  around its body.
- **Tests:** lane 1's `portalContentIsARootEvenWhenDeclaredInsideAnEmittingAncestor`
  and lane 3's `aDeferredInsideAClickableBoxIsNotFoldedIntoItsLabel`. No
  SwiftUI arm: SwiftUI has no `Deferred`.

**Cost if wrong.** Portal content appears after, rather than beside, the
content it annotates. A tooltip is read at the end of the window rather than
next to its anchor. That matches paint order, and is the same class of problem
as `AB-P`.

## AB-W — hit testing uses the clipped rect

**What.** `AccessibilityGeometry.visibleFrame` is the record's translated rect
intersected with `Frame.activeClip`, the rect `insertHitbox` already computes.
The AppKit bridge's hit test returns the deepest element whose `visibleFrame`
contains the point, the later sibling winning a tie, and considers every
element, not only descendants of containing parents. `accessibilityFrame()`
still reports the unclipped `frame` (`AB-E`).

**Why.**

- **Overscan rows would win.** A `List` realizes two overscan rows beyond the
  viewport (`List.overscan`). The list's unclipped frame spans its whole content
  height, and it is recorded after anything above it in the same window. So
  with unclipped rects, a point over a header above the list lands on an
  overscan row VoiceOver cannot see.
- **Clicks agree.** A click there lands on the header, because hitboxes are
  clipped.

**Evidence.** Reading: `Frame.insertHitbox`'s `Self.intersect(activeClip,
translated)`, and `List.visibleRange`'s overscan. Lane 2's
`hitTestingUsesVisibleFramesSoAClippedRowNeverWins` uses exactly that shape,
with the list's unclipped frame containing the point.

**Revised (critic finding 10).**

**Cost if wrong.** A partially visible element can be hit only over its visible
part. That is the part the user can point at.

## AB-X — an unbounded `List` window publishes no rows; elements are created only when read

**What.** Two rules, one instrument.

1. **`List` suppresses its descendants' records while its window is
   unbounded.** An unbounded window is `visibleRange`'s `0..<count`, returned
   when there is no vertical context or `viewportExtent == 0`: every
   `ScrollView`'s first frame. The list's own node still records, with its
   row count.
2. **The AppKit bridge creates an element only when a client is handed it**,
   and posts `.uiElementDestroyed` only for such elements.

**Why.**

- **Frame 0 builds every row (`MP-I`).** A client already running when the
  window opens activates at or before frame 0. That is the VoiceOver trigger
  (`AB-B`), and human script item 1's second order.
- **Without rule 1,** frame 0 would record a row plus a text per datum. The
  bridge would create an element for each. At 100k rows, that is about 200k
  objects on frame 0 and about 200k destroyed posts on frame 1, when the window
  shrinks to about 12 rows.
- **Rule 2 bounds the rest.** Whatever structure a publish carries, element
  work and destroyed posts are proportional to what a client has read.

**Evidence.**

- **Reading:** `List.visibleRange`, and `MP-I`'s record of the first frame.
- **Pins:** lane 3's `activatingBeforeTheFirstFramePublishesNoRowsUntilTheWindowIsBounded`
  (5,000 rows, activated before the first draw), and lane 2's
  `elementsAreCreatedOnlyWhenAClientReadsThem` and
  `destroyedIsPostedOnlyForElementsAClientWasHanded`.

**Revised (critic finding 4).** No test in the first version activated before
the first frame.

**Cost if wrong.** A client that reads the window during frame 0's gap sees a
table with a row count and no rows, for one frame. The `.layoutChanged` that
follows is posted, because that read sets the flag.

## AB-Y — `OnTapModifier` synthesizes nothing; the demo's row text and modal panel stay as they are

**What.**

1. **`OnTapModifier`.** It calls the internal `registerHandlers` overload with
   `synthesizesAccessibility: false`. It records nothing, publishes nothing, and
   its hitbox still routes a `.press` request by id.
2. **The demo** (`Sources/MetalUIDemo/main.swift`):
   - labels the counter's two squares;
   - labels the modal scrim `"Close modal"`;
   - leaves the modal panel's click-absorbing `.onClick {}` unlabelled, so it
     is an expected "button" whose combined label reads the modal's text and
     whose press does nothing;
   - does **not** change the list's row string.
3. **The human script** lists every one of these nodes as expected, and reads
   `AXRowCount`/`AXIndex` in Accessibility Inspector as well as by ear.

**Why.**

- **`OnTapModifier` cannot be labelled.** Its content is proposal-path, which
  records nothing, and `accessibilityLabel` exists only on `StyledElement`.
  Synthesis would publish an unlabelled button for the preview toggle, and
  another for the inert `.onTap {}.allowsHitTesting(false)`, which could not
  even be pressed. SwiftUI's own tap gesture is not pressable either (arm 7).
  Plan task 7 retires this path.
- **The panel.** Labelling it would drop its children's text from the combined
  label, making the modal unreadable. Not labelling it reads the text, at the
  cost of an inert "button". The honest fix is a non-button click absorber,
  which is task 9's.
- **The row string.** The modifier-composition track captures the default demo
  and requires it unchanged. Changing a string on this branch would move that
  capture at merge. Inspector's `AXIndex` is unambiguous where hearing
  "Row 41 of 500" is not.

**Evidence.**

- **Reading:** `NativeTappable.swift:8-37`, `main.swift:751-816`, `:850`,
  `:920`, `:1008`.
- **Arm 7:** SwiftUI's tap gesture is not pressable.
- **Pin:** lane 3's `anOnTapModifierPublishesNothingButItsHitboxStillPresses`.

**Revised (critic finding 11).**

**Cost if wrong.** An `onTap` control is invisible to VoiceOver until task 7 or
task 11, which is a real gap in the proposal-path demo. Script item 7 names it.

## AB-Z — the merge contract with the environment and modifier-composition tracks

**What.** The spec's **"Merge contract"** section fixes three things:

- **`Frame.registerHandlers`.** The combined form merges the environment track's
  lane 3 `.disabled` gate with this track's record path.
- **`Frame.init` and the `Window` call.** Both parameters are defaulted
  (`environment:` and `collectsAccessibility:`).
- **`ModifiedElement`.** How `.padding`/`.frame` become `ModifiedElement`, and
  how `FrameModifier` is deleted, without breaking any rule here.

The integration step writes one joint test,
`aDisabledClickableElementPublishesDisabledWithNoPressAndRefusesAPress`, with
three named mutations.

**Why.** Both other tracks edit the same lines, and a naive merge fails in both
directions:

- **Environment.** Its `if !handlers.axNode.isEmpty { …traits.insert(.disabled) }`
  replaces the very block this track extends. Taking theirs drops records.
  Taking ours drops `.disabled`, so `AB-F`'s `isEnabled = false` has no producer
  for a synthesized button. Adjustability read from the unstripped
  `handlers.actions` would advertise actions a disabled element refuses.
- **Modifier composition** deletes `FrameModifier.swift`, which this track's
  first spec named as a conformer. It moves labels to the outermost layer
  (`AB-T`). It edits `AXEmitSiteTests.swift`.

**Evidence.**

- **Reading, across worktrees, read-only:**
  - `MetalUI-environment` at `bbd4d66`,
    `specs/2026-09-15-environment-design.md`, "Lane 3";
  - `MetalUI-modifier-composition` at `1c6f686`,
    `specs/2026-09-15-modifier-composition-design.md`, lane 2.
- **Environment test to cross-check:** its D12 test
  (`aDisabledElementsAXNodeCarriesTheDisabledTrait`) stays true under the
  combined form, because declared nodes still take the trait.
- **The missing overload:** `Text.prepaint` calls `PrepaintPass.registerHandlers`,
  so the spec now lists the internal `Passes.swift` overload (critic finding
  12).

**Cost if wrong.** The joint test is red after the merge, which is its job.
If the integration step skips it, a disabled synthesized button reads as
enabled and pressable, while a press silently does nothing.

---

## Critic round (2026-09-15) — findings applied and rejected

Each finding was checked against the source at `f64e58a`, and the SwiftUI arms
were re-run. The critic's arms R0–R7 and Q reproduced exactly, and the design
session added R8–R18.

| # | finding | done |
|---|---|---|
| 1 | value-only `Text` rule wrong for arm 11; test sidestepped it | **Applied.** Branch added (`AB-F`), value-only arm and its mutation in lane 3, R1/R2 committed, `AB-F` evidence corrected |
| 2 | SwiftUI answers unprobed and opposite (R3–R7) | **Applied.** Arms committed. R3/R4/R5 settled by changing the rules to distribution (`AB-T`, with R8/R10/R14/R15/R18). R6 settled by removing the zero-area filter, with hidden content filtered on `display: none` (`AB-O`, R9). R7 recorded as a divergence (`AB-G`). Label placement after `.padding`/`.frame`: distribution, tested in 4 arms |
| 3 | a labelled `List` stops being a table | **Applied.** `logicalCount` → `.table` whatever the role (`AB-L`, arm R16); lane 1 test plus a labelled arm in lane 3 |
| 4 | an activated frame 0 publishes every row | **Applied, both remedies.** No rows while unbounded, and lazy elements with destroyed posts only for vended elements (`AB-X`); a pre-first-draw test counting records, elements and posts across frames 0 and 1 |
| 5 | scrolling posts nearly every frame; geometry republishes every tick | **Applied, with one narrowing.** Geometry split from structure, and geometry-only publishes touch nothing. `.layoutChanged` is coalesced per client read. Rate recorded, with count tests over a 60-frame scroll and a 30-tick animation (`AB-K`). **Narrowed:** the read flag is window-wide, not per container as suggested. A per-container flag needs the bridge to map every structural change to its nearest vended ancestor. The window-wide flag already bounds posts to one per read. The per-container version is the named fix if human script item 6 shows staleness |
| 6 | VoiceOver changes `@State` retention through `$ax` writes | **Applied.** Synthesized content is recorded, never emitted (`AB-U`); equal-`StateTable.count` test |
| 7 | the inactive test cannot be reddened by its first mutation | **Applied.** `lastEmissionCount` added and asserted (`AB-M`) |
| 8 | fixtures that cannot show their claims | **Applied.** The declared non-clickable box with `try #require`; explicit sizes everywhere, as a stated fixture rule; the publish-per-frame assertion removed (`AB-M`) |
| 9 | `Deferred` content attaches to its declaring ancestor | **Applied.** A portal ordinal on the record, and portal content is a root (`AB-V`); a test in each of lanes 1 and 3 |
| 10 | hit testing on unclipped frames lets overscan rows win; 14b cited wrongly | **Applied.** `visibleFrame` carried and used for hit testing (`AB-W`), with an overscan arm; `AB-E` evidence replaced by arm R17 |
| 11 | demo idioms publish misleading nodes; script cannot tell outcomes apart | **Applied, except two bullets rejected with reasons.** Scrim labelled. `OnTapModifier` synthesizes nothing (`AB-Y`). Every such node listed in the script as expected. Row positions read in Accessibility Inspector. **Rejected:** changing the row string (it would move the modifier-composition track's demo capture at merge), and labelling the panel (a label would hide the modal's text from the combined label); both in `AB-Y` |
| 12 | merge collisions with environment and modifier composition | **Applied.** Merged `registerHandlers` stated, with `.disabled` from the record and adjustability from stripped actions; `Frame.init`/`Passes` merge noted; `FrameModifier` → `ModifiedElement` reading; the missing overload listed (`AB-Z`). **Deferred to the integration step, with its full spec:** the joint disabled test, because `.disabled` does not exist on this branch |
| 13 | `NSWorkspace.isVoiceOverEnabled` not weighed; AppKit's own queries unpinned | **Applied.** Adopted as a second trigger (`AB-B`, arm R13); scripted-signal test; real-key-window zero-activation end-to-end test (arm Q) |
| 14 | device require, detached frames and ownership, unre-runnable typecheck, focus divergence, the scroll test not compiling | **Applied.** `try #require(MTLCreateSystemDefaultDevice())`; detached frame and ownership graph (`AB-D`); `docs/probes/appkit-accessibility-overrides-typecheck.swift` with a negative control; divergence recorded (`AB-J`); the scroll test written first as a Frame-only test compiling on `f64e58a` over 400pt of content in a 100pt viewport |
