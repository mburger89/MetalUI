# Accessibility bridge — decisions

Rulings for the accessibility-bridge half of plan task 12
(`docs/superpowers/plans/2026-09-12-swiftui-alignment.md`). They are prefixed
**`AB-`** and **lettered** (`AB-A`, `AB-B`, …), with two-letter tails after
`AB-Z`. **A bare `AB-3` is a typo, not a citation.** The next unused letter is
`AB-AH`.

Read alongside:

- `docs/superpowers/specs/2026-09-15-accessibility-bridge-design.md`: the
  three lanes, their API, tests and mutations, and the merge contract.
- `docs/probes/swiftui-accessibility-bridge.swift`: the first SwiftUI probe.
  "Arm N" below means its arm N.
- `docs/probes/swiftui-accessibility-bridge-rules.swift`: the critic-round
  probe. "Arm Rn" and "arm Q" mean its arms.
- `docs/probes/appkit-accessibility-overrides-typecheck.swift`: the
  re-runnable typecheck of the AppKit spellings, with a negative control.
- `docs/probes/swiftui-accessibility-bridge-critic2.swift`: the second critic
  round's SwiftUI arms. "Arm Cn", "arm Pn" and "arm En" mean its arms.
- `docs/probes/appkit-voiceover-signal-isolation.swift`: the isolation of the
  VoiceOver signal (`AB-AB`), read by grepping for `warning:`.
- `docs/probes/appkit-accessibility-activation-clients.swift`: a two-process
  probe of what an out-of-process client reaches on a host view (`AB-B`).
- `docs/probes/appkit-accessibility-override-isolation.swift` and
  `appkit-accessibility-override-isolation-typecheck.swift`: the overrides'
  isolation and the thread a client's request arrives on (`AB-AE`).
- `docs/record/12-accessibility-bridge.md`: this track's record, including the
  human VoiceOver script.
- Rulings this track leans on: `TB-M` (children stay a field; order is not
  recoverable from keys), `TB-AG` (AX data on `Handlers.axNode`), `TB-S` (the
  `$ax` slot's footprint), `EP-5` (prefer SwiftUI above the engine), `AP-I`
  (`Deferred` hoists to the root), `MP-I` (a `List`'s first frame is
  unbounded).

## How to read the letters

**Written at design time (2026-09-15, at `f64e58a`), before any lane runs,
revised the same day after one critic round, and revised again after a second
critic round that followed lane 1.** Each ruling gives:

- what was decided;
- why;
- the evidence, and which kind it is: a probe arm, a measurement, or a reading;
- what it costs if wrong.

A ruling a critic round changed says so under **Revised** (first round) or
**Revised (second critic round)**. Implementation
lanes append their red runs and mutation records under the ruling they
exercise, the way `SA-J`…`SA-M` carry theirs.

- `AB-A`…`AB-E`: the tree, the seam, identity and geometry (lanes 1–2).
- `AB-F`…`AB-J`: what a node says, and what a client can do with it
  (lanes 1–3).
- `AB-K`…`AB-M`: notifications, virtualization, and the cost instruments.
- `AB-N`…`AB-P`: smaller shape decisions, and one recorded divergence.
- `AB-Q`: scope and deferrals. `AB-R`: the seam has no defaults. `AB-S`: what
  the probes can and cannot prove.
- `AB-T`…`AB-Z`: added by the first critic round. They cover:
  - distribution;
  - records instead of emissions;
  - portals;
  - hit testing;
  - unbounded lists and lazy elements;
  - `OnTapModifier`;
  - the merge contract.
- `AB-AA`: lane 1 as built.
- `AB-AB`…`AB-AD`: added by the second critic round: the VoiceOver signal's
  isolation, how a test forces that signal, and a hidden root.
- `AB-AE`, `AB-AF`: lane 2 as built — the overrides' isolation, and the
  corrections and hazards it found.
- `AB-AG`: lane 3 as built — the corrections to the spec, two tests added (one
  after the verifier round) and two widened, and the hazards left for the integration step.
- **"Critic round"** and **"Second critic round"** at the end map each finding
  to what was done.

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

1. **A tree query.** The host view's first `accessibilityChildren` or
   `accessibilityHitTest`. **`accessibilityFocusedUIElement` is not a trigger**
   (second critic round): before activation it answers the host view and sends
   nothing.
2. **The VoiceOver signal.** `NSWorkspace.shared.isVoiceOverEnabled` reported
   `true`: read synchronously at bridge creation, so a window opened under a
   running VoiceOver is active before its first frame, and observed through KVO
   for a later start (`AB-AB` fixes the isolation).

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

**Why the focused-element query is not a trigger.** It is the one query a
client that is not reading the window makes: a text-expansion, grammar or
window-management utility polls the frontmost app's focused element to find a
text field. The two-process probe measured that such a poll, made from another
process with VoiceOver off, **does** reach the content view's
`accessibilityFocusedUIElement`. As a trigger it would therefore turn on
per-frame collection, for the window's lifetime, for users of those utilities
who run no screen reader. Dropping it costs a client whose very first request
is the focused element one empty answer: its next tree query activates the
window, and `.layoutChanged` follows (`AB-K`).

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
- **The two-process probe** (`appkit-accessibility-activation-clients.swift`,
  VoiceOver off, the client trusted). With the window idle for 4 s, the spy
  logs nothing (`passive: []`), and listing the app's windows reaches nothing
  (`windows: []`). An out-of-process `kAXFocusedUIElementAttribute` on the
  application reaches `["focused", "isElement"]`. An
  `AXUIElementCopyElementAtPosition` over the window reaches
  `["hitTest", "children", "role", "isElement"]`. **Limit:** the script process
  could not make its window key, and the client could not walk into the
  window's children (its elements resolved to `AXApplication`), so this probe
  says nothing about a tree walk. Arm Q's in-process control does.
- **Pins.** Lane 2's `aRunningScreenReaderActivatesTheWindowBeforeAnyQuery`
  (scripted signal) and `aFocusedElementQueryDoesNotActivate`. End-to-end
  `aKeyWindowReceivingEventsIsNeverActivatedWithoutAClient` pins arm Q against
  the real host view, with the signal forced `false` (`AB-AC`).

**Revised (critic finding 13).** The first version had only the query trigger.
It dismissed the application attribute as unobservable without weighing the
public `NSWorkspace` property.

**Revised (second critic round, findings 5 and 9).** The focused-element query
was a trigger; the two-process probe measured that a focus-polling utility
reaches it, so it no longer is. The signal's first spelling emitted a
concurrency warning; `AB-AB` gives the adopted one.

**Cost if wrong.**

- **The first read.** A non-VoiceOver client whose first read is taken as final
  sees an empty window. The fallback is to answer the first query synchronously
  from the last frame's hitboxes.
- **In-process queries.** Anything in-process that asks the host view for its
  children or a hit test (a test, a debugging tool) turns collection on for the
  window's lifetime.
- **Mouse-follow utilities, measured.** A utility that asks for the element
  under the pointer reaches `accessibilityHitTest`, which **is** still a
  trigger: with the pointer over a MetalUI window, it activates that window for
  good. That is kept because Accessibility Inspector's hover and VoiceOver's
  mouse-follow use the same query, and a hit-test-first client would otherwise
  see only the host view. How many such utilities users run is unmeasured;
  human script item 1 lists what was running.
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

**An empty string is no text** (arms E0–E2). `Text("")` passes
`accessibleText: nil`, so on its own it records nothing and publishes nothing,
and it adds no empty entry to a button's combined label. `Text(" ")` is not
empty and is published, as SwiftUI publishes it.

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

**Revised (second critic round, finding 11).** The empty-string rule is new:
the first spec's synthesis condition was `accessibleText != nil`, which would
have published `Text("")` as an empty `.staticText`. Arm E1,
`VStack { Text(""); Text B }`, publishes one child; E2 (`Text(" ")`) publishes
two; E0 is the control.

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
  children.** Each descendant, after its own text rules, contributes in tree
  order:
  - to the **label**, its label, or its value when it has no label;
  - to the **value**, its value, **only when it also has a label** (a plain
    text's value is its string, which already went to the label).

  If the button has no label, it takes the label contributions joined with
  `", "`. If it has no value, it takes the value contributions joined with
  `", "`, or `nil` when there are none.
- **A button with an interactive descendant** keeps its children and its own
  label, `nil` included.
- **Portal content is not a descendant**, because it is a root (`AB-V`).
- `AXPress` on a button runs the element's `onClick`.

**Why.**

- MetalUI has no `Button` until task 10, so `onClick` is the only way to make
  something activatable. The dispatch requires "press → the element's onClick".
  (*Re-pointed 2026-09-25, `EV-AE`/`EV-AF`: this doc was written when the
  interaction work was numbered task 9; a `Button` control's own existence is
  the plan's current task 10.*)
- An unlabelled button with text children is the anti-pattern screen-reader
  users hit most.

**Evidence.**

- **Arm 5:** SwiftUI `Button("Go")` is `AXButton`, `label=Go`.
  `accessibilityPerformPress` returns `true`, with the closure run once.
- **Arm 6:** `Button { HStack { Text A; Text B } }` is one `AXButton` labelled
  `A, B`, with zero children.
- **Arm R5:** a padded, labelled `Button` is `AXButton label=X` with zero
  children.
- **Arms C3, C4, C6, C7, the value.**

  | arm | button content | publishes |
  |---|---|---|
  | C3 | `Text("vol").accessibilityValue("5"); Text B` | `label="vol, B" value=5` |
  | C7 | `Text A; Text("vol").accessibilityValue("5")` | `label="A, vol" value=5` |
  | C6 | `Text("a").accessibilityValue("1"); Text("b").accessibilityValue("2")` | `label="a, b" value="1, 2"` |
  | C4 | `Text("A").accessibilityLabel("X"); Text B` | `label="X, B" value=nil` |

  C4 is the rule's other half: a labelled text with no declared value resolves
  to `value=X`, `label=nil` (`AB-F`), so it contributes to the label only.

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

**Revised (second critic round, finding 12).** The first rule joined
`label ?? value` into the label and gave the button no value, which drops C3's
`5`. The value half is new, and C6 and C7 (added by the design session) settle
how two values join and that the value follows the text carrying it, not the
first position.

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
  `allowsHitTesting(false)` removes both (a recorded divergence, below). After
  the environment merge, so does `.disabled(true)` (`AB-Z`), which agrees with
  SwiftUI (arm P2: `enabled=0`, press `false`, closure run 0 times).
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

**Divergence, recorded (second critic round, finding 3; arms P0, P1).**
`Button("Go"){…}.allowsHitTesting(false)` in SwiftUI is still `AXButton
label=Go`, and its press returns `true` with the closure run once, exactly as
the control `Button("Go")` (P0). MetalUI refuses the press and runs nothing
(`aPressIsRefusedWhereHitTestingIsDisabled`, now a divergence pin), and
`AB-AA` item 3 publishes such an element as a button with no `.press`, a state
SwiftUI never produces. Kept, for three reasons:

- **Nothing else stores the handler.** `Frame.registerHandlers` puts an
  `onClick` only into the hitbox list, and only outside
  `allowsHitTesting(false)`. Following SwiftUI would mean a second per-frame
  store of click handlers while collecting, and a second gate for the
  environment merge's `.disabled`, which today rides the same hitbox (`AB-Z`).
- **No legacy spelling reaches it.** The legacy path has no
  `allowsHitTesting` modifier; the only production caller is the demo's inert
  `.onTap {}.allowsHitTesting(false)`, and `OnTapModifier` publishes nothing
  (`AB-Y`), so no published node is affected today.
- **The owner is known.** Task 9's `Button` decides what a pressable control
  is; this divergence is re-weighed there.

Mutation M16 ("derive `.press` from `record.isClickable`") is the SwiftUI-side
half of this choice, and it reddens exactly that pin.

**Recorded hazard: a press can run a different element's `onClick` after
identity adoption (second critic round, finding 13).** `AB-D` keeps an element
object for as long as its id is published. MetalUI's identity is structural
(CLAUDE.md): when an `if` before a sibling vanishes, the trailing sibling
adopts the vanished id. An element VoiceOver is holding for that id is
therefore **not detached**; it now reads the adopter's label (one
`.titleChanged`), and a later VO-Space sends `.press(id)`, which runs the
**adopter's** `onClick`. This is CLAUDE.md's "a release can run the wrong
`onClick`", with seconds, not milliseconds, between announcement and press. It
is kept, not fixed:

- **Detaching on a label or role change was weighed and rejected.** Arm 12
  measures SwiftUI keeping an element across a label change (`Count 0` →
  `Count 1`); detaching would make every counter's element invalid on every
  increment, and VoiceOver would lose its place on the control it just pressed.
- **The remedy is the identity rule's own**: name the trailing sibling. Its id
  then never belonged to the vanished element, the held element is detached,
  and the press is refused.
- **Pinned** by lane 2's end-to-end
  `aHeldElementWhoseIDIsAdoptedPressesTheAdopter`, whose two arms disagree: the
  unnamed sibling's press runs the adopter's closure; the named sibling's is
  refused. Human script item 9 is the look.

**Not checked: occlusion.** A click lands on the topmost opaque hitbox. A press
goes to the named element even under a `Deferred` scrim. That is deferred with
modal isolation (`AB-Q` item 4).

**Cost if wrong.** `AXNode.actions` becomes a declared-but-inert field. The
integration step should add it to the inert table until task 12 either reads
it or removes it. (*Re-pointed 2026-09-25, `EV-AE`/`EV-AF`: written when the
interaction work was numbered task 9; it is the plan's current task 12
("gesture composition, button semantics, disabled behaviour, …").*)

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
- **Every place a `prepaint` runs for a node that is not its group walk's
  outermost** carries the same check (second critic round):
  - **the window root**, in `Frame.render` (`AB-AD`);
  - **after the modifier-composition merge, `ModifiedElement`'s layer loop.**
    `x.padding(4).hidden().padding(4)` gives the **middle** layer
    `display: none`, while `prepaintGroup` reads only the outermost node. The
    loop opens `withAccessibilitySuppressed(except: nil)` at the first
    (outermost-first) layer whose style is `display: none`, around that layer,
    every layer inside it and the content (`AB-Z`). On this branch that
    spelling is nested `Box`es and is suppressed already; lane 1's
    `aHiddenInnerModifierLayerSuppressesEverythingInsideIt` is green here and
    is the merge's check.

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

**Revised (second critic round, findings 2 and 14).** The check lived only in
`Element.prepaintGroup`. A hidden root and a hidden inner `ModifiedElement`
layer both escape it; the two sites above close them.

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
| hidden and children-combination modifiers, extra traits, custom actions, declared actions, a non-button click absorber | task 12's button half (*re-pointed 2026-09-25, `EV-AE`/`EV-AF`; written when this work was numbered task 9*) |
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
8. **The two-process probe** (second critic round) measures an out-of-process
   client's focused-element and position queries reaching a host view. It
   could not make its window key or walk into it, so it says nothing about a
   tree walk. A process listing on the probe machine found none of the common
   third-party AX utilities running; which utilities users run, and how often
   they query, is not measured.

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

**Divergence, recorded (second critic round, finding 4; arms C1, C2, C5, C5i).**
MetalUI does not distribute from a focusable or adjustable node: it publishes
a labelled `.group` with its children. SwiftUI distributes from both, and
takes the action with the label:

| arm | declaration | SwiftUI publishes |
|---|---|---|
| C0 (= R3, control) | `VStack { Text A; Text B }.accessibilityLabel("L")` | two `AXStaticText value=L` |
| C1 | the same with `.focusable()` | two `AXStaticText value=L`, no group |
| C5 | the same with `.accessibilityAdjustableAction {}` | two `AXStaticText value=L`, no group |
| C5i | increment on each of C5's two children | `true` both times; the one closure runs twice |
| C2 | the same with `.onTapGesture {}` | two `AXStaticText value=L`, no group |

So SwiftUI copies the adjustable action onto every child. MetalUI keeps the
node, for two reasons:

- **Actions route by the node's own id.** `AB-H`/`AB-I` advertise an
  adjustment exactly where the id's own handler is registered, and `Window`
  dispatches `.increment(id)` to that id's handler only. Copying the action to
  children would need the builder to publish a forwarding map and the window
  to honour it: machinery lane 3 does not budget, for a spelling no demo
  element uses.
- **Focus needs a node to land on.** `AB-J` publishes `focused` only for an id
  that published a node. A distributed focusable container would leave
  `Window.focus` on it unreportable, and `.focus(id)` would have no element to
  come from.

A **clickable** generic node is not a distributor either, but that is not this
divergence: a MetalUI click target is a button (`AB-G`), and a SwiftUI
`Button` keeps its label (arm R5). C2's `onTapGesture` distributes in SwiftUI
because a tap gesture is not a button there (arm 7), which is `AB-G`'s own
recorded divergence.

Lane 3's arm 7 of `aLabelOrValueOnAPlainContainerOrWrapperIsDistributedToItsChildren`
was called a control; it is **a divergence pin**, and its doc cites C1 and C5.

**Cost of the divergence.** VoiceOver reads a focusable or adjustable labelled
container as "L, group" with two children, where SwiftUI reads "L" twice with
the action on each. If the human look finds the group unusable, the forwarding
map is the named fix.

**Cost if wrong.**

- **Repetition.** R3's answer, "L, L", reads worse than one labelled group, and
  a MetalUI author may expect the group. `accessibilityElement(children:)`
  (task 12, re-pointed 2026-09-25 by `EV-AE`/`EV-AF` from "task 9", this
  work's number when this doc was written) is SwiftUI's own escape, and it is
  not in this track.
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
`accessibilityFrame()` still reports the unclipped `frame` (`AB-E`).

**The hit test ranks exactly as click dispatch does** (second critic round).
`AccessibilityGeometry` also carries:

- `layer`: `Frame.activeLayer` at the record, the key `Hitbox.layer` sorts on
  first (0 outside every `Deferred`, `Frame.rootLayer` inside one);
- `order`: the record's position in the frame's record order (its first
  occurrence, `AB-O`), the key `topmostOpaqueHitbox` breaks layer ties on.

Among every published element whose `visibleFrame` contains the point, the one
with the greatest `(layer, order)` wins, so portal content outranks what it
covers wherever it was declared, and within a layer the later record wins.
Record order is pre-order, so a descendant outranks its ancestor and a later
sibling outranks an earlier one, which is what "deepest, later sibling wins"
meant. If nothing contains the point, the host view.

**Why.**

- **Overscan rows would win.** A `List` realizes two overscan rows beyond the
  viewport (`List.overscan`). The list's unclipped frame spans its whole content
  height, and it is recorded after anything above it in the same window. So
  with unclipped rects, a point over a header above the list lands on an
  overscan row VoiceOver cannot see.
- **Clicks agree.** A click there lands on the header, because hitboxes are
  clipped.

**Evidence.** Reading: `Frame.insertHitbox`'s `Self.intersect(activeClip,
translated)`; `Hitbox.layer`'s doc ("Primary sort key, ahead of registration
order, so a `Deferred` subtree receives events above the siblings it paints
over"); and `List.visibleRange`'s overscan. Lane 2's
`hitTestingUsesVisibleFramesSoAClippedRowNeverWins` uses exactly that shape,
with the list's unclipped frame containing the point, and a modal arm.

**Why not "later root first, then depth"** (the critic's suggested order).
`Deferred` content records where it is declared, so a modal declared before a
list in tree order is an **earlier** root than the list, and root order would
let the covered row win. Depth has a second problem: a `List` row's text sits
two or three levels below the table root, deeper than a shallow modal. The
`(layer, order)` key is the one click dispatch already trusts.

**Revised (critic finding 10).**

**Revised (second critic round, finding 7).** "Deepest element wins" ignored
portals: with a `Deferred` modal over a `List`, the covered row's text is
deeper than the modal and would have won, so VoiceOver's mouse-follow would
announce what a click cannot reach.

**Cost if wrong.** A partially visible element can be hit only over its visible
part. That is the part the user can point at. `layer` and `order` are geometry:
they change only with a structural change, so they add no publishes of their
own.

## AB-X — an unbounded `List` window publishes no rows and asks for one more frame; elements are created only when read

**What.** Three rules.

1. **`List` suppresses its descendants' records while its window is
   unbounded.** An unbounded window is `visibleRange`'s `0..<count`, returned
   when there is no vertical context or `viewportExtent == 0`: every
   `ScrollView`'s first frame. The list's own node still records, with its
   row count.
2. **The AppKit bridge creates an element only when a client is handed it**,
   and posts `.uiElementDestroyed` only for such elements.
3. **A collecting `List` whose window is unbounded under a vertical scroll
   context asks for one more frame, and only one** (second critic round).
   `requestLayout` stores `windowAwaitsViewport`: the window is unbounded
   because `pass.scrollContext` is vertical with `viewportExtent == 0`. In
   `prepaint`, when `pass.collectsAccessibility` and that flag is set, it calls
   `Frame.requestAccessibilityRetry()`. `WindowAccessibility.frameDidRender`
   dirties the window when the frame asked **and the previous drawn frame did
   not**, so a scroller that never measures a viewport (zero height) costs one
   extra frame per run of unbounded frames, not a frame forever. A `List` with
   no scroll context never asks: nothing it could learn next frame would bound
   it (the documented blank-list requirement).

**Why rule 3.** `ScrollView` stores the measured `viewportExtent` through
`pass.withState`, and `StateTable.withState` does not fire `onWrite`
(`StateTable.swift:329-337`); the scroll indicator requests a frame only while
its fade is live, which on a first frame it is not (`lastScrollTime` is
`-infinity`). So a window drawn once while idle **stays unbounded**, and while
a client is active it publishes a table with a row count and **no rows**, until
unrelated input dirties it. VoiceOver already running at launch (`AB-B`'s
signal trigger) is exactly that case. A retry separate from
`Frame.requestAnotherFrame()` keeps the cap: `wantsAnotherFrame` is honoured on
every frame, which a zero-height scroller would turn into a display link that
never pauses.

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
- **Reading, rule 3:** `ScrollView.swift:513-519` (the extent written through
  `withState`), `StateTable.withState` (no `onWrite`), and
  `ScrollView.paintIndicator` (its `guard alpha > 0` before
  `requestAnotherFrame()`).
- **Pins:** lane 3's `activatingBeforeTheFirstFramePublishesNoRowsUntilTheWindowIsBounded`
  (5,000 rows, activated before the first draw, **frame 1 reached only through
  the list's own retry**: the test never calls `setNeedsRedraw()` between
  frames 0 and 1), with a zero-height-scroller arm for the cap and an inactive
  arm; and lane 2's `elementsAreCreatedOnlyWhenAClientReadsThem` and
  `destroyedIsPostedOnlyForElementsAClientWasHanded`.

**Revised (critic finding 4).** No test in the first version activated before
the first frame.

**Revised (second critic round, finding 8).** Rule 3 is new. The first version
assumed "the next frame publishes the realized window" without anything
producing that frame, and its planned test could only see frame 1 by forcing a
redraw, which hid the gap.

**Cost if wrong.** A client that reads the window during frame 0's gap sees a
table with a row count and no rows, for one frame. The `.layoutChanged` that
follows is posted, because that read sets the flag. If a real scroller ever
needs **two** frames to measure its viewport, the cap leaves its list unbounded
until input; the zero-height arm is the instrument that would have to change.

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
  which is task 12's (re-pointed 2026-09-25 by `EV-AE`/`EV-AF` from "task 9",
  this work's number when this doc was written).
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

**Integration status (2026-09-15, record §13).** Reconciled to the environment
track's `EV-W` item 4, which supersedes this contract on the `$disabled` blocker
hitbox, its mutation, the `keyboard` copy with stripped `isFocusable`/`actions`,
the ungated `$focus` write and the `environment:` init parameter — none of those
exists on the merged tree. A disabled element registers no hitbox and nothing in
the focus registry; presence and role read the ungated `handlers`, actions read
the gated registrations, and the record carries `isEnabled: enabled`. The joint
test is `aDisabledElementPublishesDisabledWithTheGatedActionsAndRefusesEveryRequest`
(`TrackInteractionTests.swift`, five arms with its mutations in record §13).
Item 4 (`ModifiedElement`) was **not** delivered by either track:
`aHiddenInnerModifierLayerSuppressesEverythingInsideIt` was red at the merge
commit (2 issues) and is green since `Frame.suppressingAccessibilityIfHidden`
wraps each inner layer (`fba579e`) — a per-layer wrap rather than the
"outermost-first hidden layer opens one scope" this item sketched; the two are
equivalent because nested suppression scopes with `except: nil` compose.

**What.** The spec's **"Merge contract"** section fixes four things, written
against the other tracks' **current** designs: `feat/environment` at
`f4dcad8` (its spec's "Lane 3" and "Owed to the integration step", unchanged
in substance since the redesign at `e9afded`) and
`feat/modifier-composition` at `ec65da6` (its spec's lane 2 "Phases" and
"Merge notes").

1. **`Frame.registerHandlers`.** The combined form takes the environment
   track's lane 3 gate **as that track now specifies it**, unmodified:
   - a disabled element is **not registered with the focus registry at all**
     (`if enabled { focusRegistry.register(handlers, id: id) }`), which removes
     its focusability, its actions, its raw `onKey` and its `keyContext`
     together (`EV-F`);
   - the `$focus` slot write is gated on `enabled`;
     `focusedElementProducedThisFrame` stays ungated;
   - a disabled pointer target registers a blocker hitbox with `Handlers()`
     **under the derived id** `.child(of: id, at: 0, name: ElementID("$disabled"))`
     (`EV-T`), not under `id`;
   - a declared node gains `.disabled` before `emitAXNode`.

   Into that it puts this track's record path, and **synthesis reads the
   ungated `handlers`** (`EV-W` item 4): a disabled element that is only
   clickable, only focusable or only adjustable still records and publishes,
   with the record's `isEnabled = false`. **Actions and focusability come from
   the gated registries**, which the builder already reads: `.press` from
   `hitboxes` (the blocker's derived id never matches), `.increment`/`.decrement`
   from `focusRegistry.actionHandler` and `isFocusable` from
   `focusRegistry.isFocusable` (a disabled element is in neither).
2. **`Frame.init` and `Window`'s `Frame(…)` call.** The environment track adds
   **no** init parameter (`EV-H`), so this track's `collectsAccessibility:`
   lands alone. `Window` gains that track's one statement after the `Frame(…)`
   expression: an adjacent-line textual conflict only.
3. **`ElementGroup.swift`.** The environment track replaces
   `StateBinder.bind(self, table: pass.frame.stateTable, id: layout.id)` with
   `StateBinder.bind(self, in: pass.frame, id: layout.id)` in
   `Element.prepaintGroup`: **the line directly above** this track's
   `display: none` block. Resolution: keep both, the bind first. The
   modifier-composition track's lane 3 edits `Element`'s default
   `requestGroupLayout`, a different function.
4. **`ModifiedElement`.** `.padding`/`.frame` become `ModifiedElement` and
   `FrameModifier.swift` is deleted. Its `prepaint` registers layers k = n-1…0
   in a loop inside its own body, not through `prepaintGroup`, so `AB-O`'s check
   does not reach an inner layer. **The loop must open
   `pass.frame.withAccessibilitySuppressed(except: nil)` at the first
   (outermost-first) layer whose style has `display == .none`**, around that
   layer's registration, every inner layer's, and `content.prepaintGroup`.

**Joint checks.**

- **Written now, on this branch, green here:** lane 1's
  `aHiddenInnerModifierLayerSuppressesEverythingInsideIt`. Its spelling,
  `declared-box.padding(4).hidden().padding(4)`, is nested `Box`es on this
  branch and a three-layer `ModifiedElement` after the merge, so the merge
  cannot pass it without item 4.
- **Written by the integration step** (`.disabled` does not exist here):
  `aDisabledElementPublishesDisabledWithTheGatedActionsAndRefusesEveryRequest`,
  three arms (clickable only, focusable only, adjustable only), each with an
  enabled control. The spec gives its fixture and mutations.
- The environment track's D12 gains its collecting-frame arm, as that track
  already lists.

**Why.**

- **Environment.** Both tracks edit `registerHandlers`' body. Taking theirs
  drops records; taking ours drops the gate. The first version of this ruling
  was written against `bbd4d66`, before that track's redesign, and differed
  from its current lane 3 in five places (below).
- **Synthesis on the ungated handlers.** SwiftUI publishes a disabled control:
  arm P2, `Button("Go").disabled(true)`, is `AXButton`, `enabled=0`, press
  `false`, closure run 0 times. Synthesizing from a gated set would publish
  nothing for a disabled element that is only focusable or only adjustable,
  and a screen-reader user would not learn the control exists.
- **Modifier composition.** Its layer loop is the one place a `prepaint` runs
  for a non-outermost node without passing through `prepaintGroup`.

**Evidence.**

- **Reading, across worktrees, read-only, through `git show`:**
  - `feat/environment` at `f4dcad8`: `specs/2026-09-15-environment-design.md`
    "Lane 3" (the `registerHandlers` block) and "Owed to the integration
    step"; decisions `EV-F`, `EV-H`, `EV-T`, `EV-W`;
  - `feat/modifier-composition` at `ec65da6`:
    `specs/2026-09-15-modifier-composition-design.md` lane 2 "Phases" (the
    layer loop) and "Merge notes".
- **Arm P2** (`swiftui-accessibility-bridge-critic2.swift`).
- **The `hidden()` spelling**, by reading: `hidden()` writes the outermost
  layer's `display`, so `.padding(4).hidden().padding(4)` hides the middle one.

**Revised (second critic round, findings 1 and 2).** The first version:

- stripped `isFocusable` and `actions` from a disabled element's registration,
  where the environment track now skips registration entirely and so also
  strips `onKey` and `keyContext`;
- inserted the blocker hitbox under `id`, where `EV-T` uses a derived id;
- called the `$focus` write "unchanged, ungated", where it is now gated;
- said both tracks add a defaulted `Frame.init` parameter, where `EV-H`
  removed the environment track's;
- read adjustability and focusability for synthesis from the stripped set,
  contradicting `EV-W` item 4: under it a disabled element that was only
  focusable or only adjustable published nothing;
- did not list the `ElementGroup.swift` adjacent-line collision, or
  `ModifiedElement`'s layer loop escaping `AB-O`.

**Cost if wrong.** The joint tests are red after the merge, which is their job.
If the integration step skips the disabled one, a disabled synthesized button
reads as enabled and pressable while a press silently does nothing. If it skips
item 4, hidden inner layers publish at their zero-size rects.

## AB-AA — lane 1 as built: four corrections to the spec, and three strengthened tests

**Added by lane 1's implementer (2026-09-15), after its red and green runs.**
The spec's lane-1 section carries a "Lane 1 as built" note at each site; the
red lines and the full mutation table are in `docs/record/12-accessibility-bridge.md`.

**What.**

1. **`logicalIndex` waits for lane 3.** The spec's lane-1 `registerHandlers`
   block strips `declaration.logicalIndex` and tests
   `handlers.axNode.logicalIndex != nil`, and its role map has a `.row` line,
   but the field is added by lane 3 (`AXNode.swift`). Lane 1 tests
   `!handlers.axNode.isEmpty` and has no `.row` mapping; lane 3 adds the
   field, the strip, the record term and the `.row` line in one change.
2. **`Sendable` on two tags.** `AccessibilityRole` and `AccessibilityActions`
   declare it, because each has a `static let` and Swift 6 rejects one of a
   non-`Sendable` public type. `AccessibilityTree.empty` is a computed
   `static var`. The id and the tree stay non-`Sendable`, as designed.
3. **"Clickable" for the role is `handlers.onClick`, not `.press`.** A generic
   click target under `allowsHitTesting(false)` is still a button and
   advertises no press; the press stays derived from hitboxes (`AB-H`).
4. **The `Frame` overload's two parameters are required;** only the
   `PrepaintPass` overload defaults them, so no call site can resolve the
   three-argument spelling ambiguously.

**Superseded in part by the second critic round.** An uncommitted rewrite of
lane 1's tests, found in the worktree after this ruling's record, was committed
(`71805eb`) and the whole mutation table re-taken against it (record, "Second
critic round"); the hidden-root claim below is withdrawn (`AB-AD`).

**Three tests strengthened, one added**, each because a mutation survived or a
named one could not redden its own test (shape: "a mutation that reddens
nothing is a broken instrument, or it is the finding"):

- `publishedFocusIsTheWindowsFocusAndAFocusRequestMovesIt`: the spec's named
  mutation, "build `focused` from the handed-in focus", **cannot redden the
  spec's fixture**, because every arm had handed-in focus equal to read-back
  focus. A last arm focuses the non-focusable `c` directly; the frame clears
  it, and the published `focused` must be `nil`. The mutation now reddens it.
- `hiddenContentIsNotPublished…`: the builder's "focused only if it
  published" filter survived the whole suite (mutation M30). The hidden box is
  now focusable and focused.
- `aNodeInsideAScrolledScrollViewReportsItsOnScreenFrame`: `hasSameStructure`
  had no lane-1 caller or test; two arms pin geometry out and nodes in.
- **Added** `declaredRolesLabelsValuesAndTraitsReachThePublishedNode`: role
  map beyond `.button`/`.table`, `value`, and both traits had no pin.

**Why.** Each is the smallest change that makes the lane compile against the
fields that exist, or makes a mutation the spec relies on observable.

**Evidence.** Measured: lane 1's red run (skeleton commit `bc3fbdc`), and the
35-mutation table in the record, every row taken from an unfiltered suite run.

**Left unpinned on lane 1, with owners.**

- **The suppression exception** (`isAccessibilitySuppressed` answering
  `outermost != id`): replacing it with "always suppressed" leaves the suite
  green (M33), because no lane-1 caller passes a non-nil exception. Lane 3's
  `activatingBeforeTheFirstFramePublishesNoRowsUntilTheWindowIsBounded`
  is its first reader and must redden under M33.
- **Nested portals get distinct ordinals**: only "every portal is ordinal 0"
  is pinned (M34). A `Deferred` inside a `Deferred` publishing its content as
  a child of the outer portal's content is unpinned.
- **A hidden root.** `Frame.render` calls the root's `prepaint` directly, not
  through `prepaintGroup`, so a root element with `display: none` is not
  suppressed. ~~Unreachable from `Window` in any real tree (a hidden root draws
  nothing at all)~~ **Withdrawn by the second critic round (finding 14):** that
  claim was not measured, and CLAUDE.md's inert table says `hidden()` filters
  layout but not paint, so a hidden root still prepaints and records. Fixed
  under `AB-AD`.

**Cost if wrong.** Item 1: if lane 3 forgets the strip, a `List` row writes a
`$ax` slot per row while a client is active — lane 3's
`aClientDoesNotChangeStateRetention` is the guard.

## AB-AB — the VoiceOver signal delivers its first value synchronously and later ones through a main-actor `Task`; no `assumeIsolated`

**What.** `VoiceOverSignal.observe(_:)`, on the main actor:

1. installs `NSWorkspace.shared.observe(\.isVoiceOverEnabled, options: [.new])`,
   whose change handler reads `change.newValue ?? false` into a `Bool` and
   delivers it with `Task { @MainActor in handler(value) }`;
2. **then** calls `handler(NSWorkspace.shared.isVoiceOverEnabled)` directly,
   before returning.

No `MainActor.assumeIsolated`. The protocol's doc says "calls `handler` with the
current value before returning, then on every change, possibly after a
main-actor hop". The bridge treats a repeated `true` as a no-op (activation is
sticky, `AB-B`).

**Why.**

- **The first spelling warned.** Calling the `@MainActor` handler from inside
  the KVO closure emits `warning: call to main actor-isolated parameter
  'handler' in a synchronous nonisolated context [#ActorIsolatedCall]`. The
  suite's constraint is 0 `warning:`.
- **`-warnings-as-errors` does not catch it,** so an exit status proves
  nothing. The probe greps for `warning:`, with an unused-variable control that
  the flag does turn into an error (exit 1).
- **`assumeIsolated` would trap** if a `.new` change arrived off the main
  thread. Nothing documents the delivery thread of this KVO property, and
  CLAUDE.md records the suite SIGTRAPping on exactly that collapse.
- **An all-`Task` hop would make the initial value asynchronous.**
  `aRunningScreenReaderActivatesTheWindowBeforeAnyQuery` requires one
  `.activate` before any query, and a window opened under a running VoiceOver
  should collect from its first frame (`AB-X` rule 3 covers the list's case).
- **Order.** Observing first and reading second means a flip between the two
  is delivered late rather than lost.

**Evidence.** Measured: `docs/probes/appkit-voiceover-signal-isolation.swift`.

| build | result |
|---|---|
| adopted spelling | 0 `warning:` lines, exit 0 |
| `-D SPEC_SHAPE` (the spec's first spelling) | the `#ActorIsolatedCall` warning, **exit 0** |
| `-D UNUSED_CONTROL` | `error: … never used [#NoUsage]`, exit 1 |
| `/usr/bin/swift`, adopted spelling | `initial values delivered before observe returned: [false]` |

**Cost if wrong.** If KVO delivers a change synchronously on the main thread
and a test depends on it arriving before the next statement, that test needs a
run-loop turn. No test does: every lane-2 test uses the scripted signal
(`AB-AC`), and the real signal's flip is human script item 1.

## AB-AC — a test forces the signal through an internal `AppKitPlatform` initializer; the arm-Q pin depends on the machine's AX clients

**What.**

- `AppKitPlatform` gains an **internal**
  `init(device:accessibilitySignal: @escaping @MainActor () -> any AccessibilityClientSignal)`.
  The public `init(device:)` delegates to it with `{ VoiceOverSignal() }`.
- `openWindow` passes `accessibilitySignal()` to an internal
  `AppKitWindow.init(device:title:size:accessibilitySignal:)`, which builds its
  bridge with it.
- Lane 2's end-to-end tests do not go through `App.openWindow`, which has no
  way to pass it. They build `AppKitPlatform(device:accessibilitySignal:)` with
  a scripted `false` signal, open the platform window, and construct
  `Window(platformWindow:renderer:startsDisplayLink:content:)` over it (internal,
  reached with `@testable import MetalUI`, exactly as `makeFakeWindow` does),
  with `@testable import MetalUIPlatform` for the initializer.
- `aKeyWindowReceivingEventsIsNeverActivatedWithoutAClient` states in its doc
  that it **depends on no out-of-process client querying the window** while it
  runs. A mouse-follow utility with the pointer over the test window reaches
  the hit-test trigger (`AB-B`, measured), and the test's failure message names
  that and the probe.

**Why.** The first spec named an `AppKitWindow` parameter but no path from a
test to it: `App.openWindow` → `AppKitPlatform.openWindow`
(`AppKitPlatform.swift:377`) → `AppKitWindow(device:title:size:)`. Both
end-to-end tests would have run against the real `VoiceOverSignal`, and
failed on any machine running VoiceOver.

**Evidence.** Reading: `AppKitPlatform.swift:369-385`, `App.swift:49-60`,
`Tests/MetalUITests/Fakes.swift` (`makeFakeWindow` builds `Window` directly).

**Cost if wrong.** A second construction path. `App.openWindow` also wires
`onClose` to terminate the process; the tests' path does not, so the platform
tests' rule applies: these windows may be closed.

## AB-AD — a hidden window root is suppressed in `Frame.render`

**What.** `Frame.render` runs the root element's `prepaint` inside
`withAccessibilitySuppressed(except: nil)` when collecting and the root's layout
node has `display == .none`: the same check `Element.prepaintGroup` applies to
every other element (`AB-O`).

**Why.** `Frame.render` calls the root's `prepaint` directly. `hidden()` filters
layout, not prepaint (CLAUDE.md's inert table), so `Window(root: Box { … }.hidden())`
compiles, prepaints, and would publish every record inside it. `AB-AA` called
that unreachable without measuring it.

**Evidence.** Measured: `aHiddenRootPublishesNothing`, red before the fix; the
red line and the mutation are in the record.

**Cost if wrong.** None known. The check costs one `Style` read per collecting
frame.

## AB-AE — AppKit's accessibility overrides are nonisolated: every override answers through a main-thread helper with a fallback

**Added by lane 2's implementer (2026-09-15).** The design did not see this.

**What.**

- `NSAccessibility` (the protocol) and `NSAccessibilityElement` carry no
  main-actor annotation, so **every override lane 2 writes is nonisolated** —
  on `AppKitAccessibilityElement` and on `MetalHostView` (an `NSView`) alike —
  even inside a `@MainActor` class.
- Every override body therefore runs through
  `mainActorAnswer(_ object:fallback:_ body: @MainActor (Object) -> T)`
  (`AppKitAccessibility.swift`): on the main thread it runs `body` with the
  object inside `MainActor.assumeIsolated`; **off the main thread it answers
  `fallback` and runs nothing** — no label, no children, no element, no
  action, no activation.
- The element's logic lives in `@MainActor` members; each override is a
  one-line hand-off. The object is a **parameter**, and both it and the answer
  cross the `assumeIsolated` boundary in `MainThreadAnswer`, an
  `@unchecked Sendable` box that is built and unwrapped on the main thread.

**Why.**

- **The first build warned dozens of times**
  (`main actor-isolated property … can not be referenced from a nonisolated
  context`), against a 0-`warning:` constraint. The committed overrides probe
  typechecked **constant** bodies, so it could not see it.
- **`assumeIsolated` requires a `Sendable` result**; an override returns `Any?`
  or `[Any]?` (probe control `UNBOXED`: `type 'T' does not conform to the
  'Sendable' protocol`).
- **Capturing `self` in the body is rejected**, and only at SIL: `sending
  'self' risks causing data races` (control `CAPTURE`). Under `-typecheck` that
  control reads **0 diagnostics**: the committed probe's blind spot, one
  compiler stage later. The typecheck probe is read under `-emit-sil`.
- **A fallback, not a trap.** An out-of-process client's hit test arrived on
  the main thread in three of three runs (arm B), so the fallback is expected
  never to run. But the arm observed one entry point; nothing documents the
  rest, `assumeIsolated` alone traps off the main thread (CLAUDE.md records the
  suite SIGTRAPping on that collapse elsewhere), and `DispatchQueue.main.sync`
  deadlocks against a main thread waiting on its caller.

**Evidence.** Measured, both probes with their output in their headers:

| probe arm | result |
|---|---|
| `appkit-accessibility-override-isolation-typecheck.swift`, `NONE` (adopted spelling), `-emit-sil` | 0 diagnostics |
| same, `NEGATIVE` (body reads main-actor state directly) | `warning: main actor-isolated property 'label' can not be referenced from a nonisolated context` |
| same, `CAPTURE` | `error: sending 'self' risks causing data races`; **0 under `-typecheck`** |
| same, `UNBOXED` | `error: type 'T' does not conform to the 'Sendable' protocol` |
| `appkit-accessibility-override-isolation.swift` arm B (two processes, client trusted) | `position: ["hitTest@main"]`, three runs |
| same, arm C (`offmain`) | main thread `label=live children=1`; background `label=nil children=0`; `no trap` |

**Pin.** `anOffMainThreadQueryAnswersNothingAndDoesNotTrap`
(`AppKitAccessibilityTests.swift`), an **exit test** because the failure it
guards is a trap: in a child process, the control on the main thread reads
the live label, one child, an allowed and successful press; the same element
from `Task.detached` reads `nil`, 0 children, press not allowed, press
`false`, and the child exits 0. Its mutation (L47, record) is removing the
thread check.

**Cost if wrong.**

- **If AppKit ever calls an override off the main thread** (a threaded
  accessibility mode, a future OS), that client reads an empty window rather
  than a crashed app. A client that trusts such an answer sees nothing; the
  fix would be a synchronous hop, with its deadlock weighed then.
- **Test count.** Lane 2's platform file has **18** tests, not the spec's 17.

## AB-AF — lane 2 as built: corrections to the spec, and two hazards for the integration step

**Added by lane 2's implementer (2026-09-15), after its red and green runs.**
The spec's lane-2 section carries a "Lane 2 as built" note; red lines and the
mutation table are in `docs/record/12-accessibility-bridge.md`.

**What.**

1. **`AccessibilityRequest` collides with `Accessibility.framework`.** That
   framework exports `AXRequest` to Swift as `AccessibilityRequest`, and
   `AppKit` brings it in. Any file importing both `AppKit` and
   `MetalUIPlatform` — including through `MetalUI`, which `@_exported`-imports
   `MetalUIPlatform` — gets `'AccessibilityRequest' is ambiguous for type
   lookup` on the bare name (measured: the first build of lane 2's tests). The
   source module is unaffected (its own type shadows the import), and so is
   every existing file (none spells the name beside `AppKit`). Lane 2's tests
   use a `private typealias Request = MetalUIPlatform.AccessibilityRequest`.
   **Not renamed here:** the type is lane 1's public seam in shared
   `Platform.swift`, and a rename is the integration step's call (candidate:
   `AccessibilityClientRequest`).
2. **`swift package clean` was needed mid-lane.** Turning
   `AppKitWindow.onAccessibilityRequest` from a stored into a computed property
   left the incremental test link failing with `Undefined symbols … direct
   field offset for MetalUIPlatform.AppKitWindow.onAccessibilityRequest`. A
   clean build fixed it: CLAUDE.md's Build-section hazard, a third shape.
3. **An element's `lastNode`/`lastGeometry` are seeded at creation** from the
   tree it was created against, and replaced at detach by the last tree that
   held the id. The spec named the fields without a source for their first
   value.
4. **`parents` is rebuilt on every structural publish, active or not.** The
   spec's step 1 returned before it while inactive; a tree stored before
   activation would then have been read with a stale parent map by the
   activating query. No element can exist before activation, so nothing else
   differs.
5. **`isAccessibilitySelectorAllowed` also gates table and row attributes by
   role**: `accessibilityRowCount`/`Rows`/`VisibleRows` only on a `.table`,
   `accessibilityIndex` only on a `.row`. Every element subclass implements
   all of them, so without the gate a button would advertise `AXRowCount 0`.
   Pinned in `aTableReportsItsRowCountAndItsRowsTheirIndices`.
6. **A detached element's press is refused twice over.** The spec's mutation
   for the end-to-end adoption test, "skip detaching (arm 2 press runs
   `second`)", cannot run `second`: a press for the vanished id reaches
   `Window`, finds no hitbox with that id, and returns `false`. The test's arm 2
   is reddened by its `accessibilityParent() == nil` assertion instead
   (record, L46).

7. **The spec's parenthetical for "never reset the read flag" was the other
   mutant.** Never resetting posts `.layoutChanged` on every structural publish
   (L35: 11 after the ten unread publishes); "the third step posts 0" is what a
   children read that does not re-arm the flag does (L36). Both redden
   `layoutChangedIsPostedOncePerClientRead`.
8. **Three tests were strengthened after the first mutation round**, each
   against a survivor shown to change behaviour first: the arm-Q test's
   synthesized mouse events never reached the host view in the test process
   (the app is inactive, so AppKit spends the click on activation; L44), and
   `AccessibilityTreeChanges` ignoring children order (L49) or roles (L50)
   changed no count any fixture read. The design's own arm Q probe never checked
   that its mouse events arrived either.

9. **The lane-2 verifier's hunting mutations left fifteen rules unguarded;
   fourteen are now pinned** (record, "Verifier round on lane 2", V01–V16,
   numbered after the verifier's own H01–H16, plus an added V08b; its H14 —
   the host's pre-activation hit test — stays unpinned because production
   cannot reach the difference). The two that mattered: the **parent half of the
   hierarchy** was pinned only for roots and detached elements — deleting the
   `parents` map, or answering the host view for every node, left 1123 tests
   green — and **`AB-E`'s choice of the unclipped frame over `visibleFrame`**
   was pinned only by fixtures whose two rects are equal (taxonomy shape 1).
   The coverage line below overstated `AB-E` until this item: L10, L11 and L31
   pin the conversion and when it is taken, not which rect is converted.
   Item 4 above (parents rebuilt while inactive) was unpinned until V03.
10. **A second lane-2 verifier (at `f419b4f`) found ten more rules unguarded,
    none pinned on this branch** (record, "Second verifier round on lane 2",
    rows `L2C01`…`L2C24` and `L2N01`…`L2N54`; 39 mutations, 28 killed, one
    equivalent, L2N04). The gaps: the selector gate's fall-through to `super`
    (L2N33, L2N33b), production's `VoiceOverSignal` wiring (L2N30), a roots-only
    reorder and a rows read as notification triggers (L2N03, L2N21), a detached
    element's focus request and its last-known node once its id returns
    (L2N09, L2N37), and the min edges of the hit test and the zero-width
    visible row (L2N14, L2N15, L2N15y). The record lists the five test changes
    that close them. No rule changes: each rule is as ruled, only unpinned.

**Lane 2's mutation evidence, by ruling** (52 rows, all killed at both
re-takes, plus the verifier round's 15 V-rows, all killed; the tables, with the
tests each reddens, are in the record): `AB-N` L01, L02, and nested parents
V01, V02; `AB-F` role and trait mapping L03–L05; `AB-X` lazy creation L06, L25,
L27, L32, L33, V08, V08b; `AB-D` identity and detach L07–L09, L45, L46, V06,
V07; `AB-E` the conversion and its read-time timing L10, L11, L31, and **which
rect (unclipped, not visible) V10 alone**; `AB-H` gating L12, L13, L52, V16;
`AB-J` L14, L15; `AB-L` L16–L18, L51, V13; `AB-W` L19–L22, L40, L41, V04;
`AB-B` and `AB-AB` activation L23–L29, L43, L44, V15; `AB-K` L29–L39, L48–L50,
V09, V11, V12; `AB-AC` and the seam L42, L43; `AB-AF` item 4 V03; `AB-AE` L47.

**Why.** Each is the smallest change that builds against the SDK and the
fields that exist, or makes a mutation the spec relies on observable.

**Cost if wrong.** Item 1: an app that imports `AppKit` and spells
`AccessibilityRequest` must qualify it until the rename.

## AB-AG — lane 3 as built: no rule changed; two tests added, two widened, four hazards

**Added by lane 3's implementer (2026-09-15), after its red and green runs.**
The spec's lane-3 section carries a "Lane 3 as built" note; the red lines and
the mutation tables are in `docs/record/12-accessibility-bridge.md`, "Lane 3".

**What.** Every rule `AB-F`, `AB-G`, `AB-L`, `AB-T`, `AB-X` and `AB-Y` states
was built as written. The corrections are to tests, fixtures and spellings:

1. **A fifteenth test.** The spec's table has 14 rows under a "15 tests" count.
   `aListInsideHiddenContentIsNotPublishedEvenOnItsUnboundedFrame` is added: a
   `List` on its unbounded frame inside `display: none` content. It is the only
   fixture that nests the list's own suppression scope (`except: id`) inside
   another (`except: nil`), so it pins that `isAccessibilitySuppressed`
   answers from the **outermost** scope: mutant N29 (innermost) reddens it; in
   each of the three rounds recorded it reddened no other test. Lane 1's M33 (always suppressed) reddens
   `activatingBeforeTheFirstFramePublishesNoRowsUntilTheWindowIsBounded`, as
   `AB-AA` required, and also this test and lane 1's
   `aLabelledListIsStillATable`.
2. **The `logicalIndex` strip had no guard that could see it.** `AB-AA` named
   `aClientDoesNotChangeStateRetention`, whose spec fixture (130 texts, 10
   click targets) holds no `List`, and the spec's
   `synthesizedNodesCostNothingWhileNoClientIsActive` renders its `List` with no
   scroll context, which is unbounded and so never carries a hint. Both now
   render a `List` bounded by its scroller (the first over three window
   frames, the second over two `Frame`s sharing a state table), each with a
   `#require` that rows were published. Forgetting the strip (N30) reddens
   both.
3. **A lane-1 fixture changed.** `AB-G`'s step C folds the non-interactive
   descendants of **any** `.button`, including a declared one, so lane 1's
   `portalContentIsARootEvenWhenDeclaredInsideAnEmittingAncestor` (a declared
   `.button` holding a declared sibling `after`) published no `after` once
   lane 3 landed: the first green run's one failure,
   `id(labelled: "after") → nil`. `after` is now focusable, so the button keeps
   its children. The portal mutants still redden it (N17, the parent walk
   ignoring portals; M38, `popLayer` not popping).
4. **Tests were strengthened twice against surviving mutants**, each survivor
   first shown to change a published value on an input no fixture had:
   - after the first round (`15f0dd2`): **N49** (a clickable text's string
     overriding its declared label; no fixture declared a label on a clickable
     text) and **N46** (combination looking one level down; no fixture put a
     kept node with children of its own between a button and its texts). The
     N46 arms use a `@testable` declared `.container` as the intermediate; **by
     reading, the public API reaches that shape only through a `List` inside a
     click target** (its table and rows are kept, non-interactive and have
     children). **N09v** (a distributed value not overwriting a child's own)
     was found by reading the same round, not run: arm 6's texts declared no
     value, so the condition it adds held for every child there. Arm 6 now
     declares one, and N09v reddens it;
   - after the second round (`ecb0504`): **N60** (only focusability makes a
     descendant interactive; the one clickable descendant under a button in
     any fixture, lane 1's `aHiddenRootPublishesNothing`, folds into a root
     labelled `"in"`, which that test's `id(labelled: "in")` still finds) and
     **N52** (a list with no scroll context retries once; no active window held
     such a list).
5. **Spellings.**
   - `WindowAccessibility.frameDidRender(emissionCount:retry:_:to:)` takes
     `retry` with no default and returns the `Bool` with no
     `@discardableResult`: its one caller must not drop it. The previous
     frame's flag is stored on every drawn frame, active or not; `retry` is
     `false` on every frame that did not collect.
   - `List.windowIsBounded` is `visibleRange`'s own guard, so a non-positive
     `rowHeight` also counts as unbounded, beside the spec's two causes.
   - Step B absorbs lane 1's "a clickable `generic` node is a button"; the role
     map maps `generic` to `.group` only.
   - A folded button with no contributions keeps a `nil` label, never `""`
     (N51 reddens lane 1's `eachLiveHandlerAloneMakesAnUndeclaredElementRecord`).
   - `AXEmission.synthesizes` has **no reader**: a conformer that does not
     synthesize records only what it declared, which `registerHandlers`' gate
     already decides. Its doc says so.
   - **The inactive path grows, by reading (unmeasured).** `AB-M`'s "one
     `Bool` read per `registerHandlers` call, plus one `Int` store per frame"
     now also pays, with no client: a copy of `handlers.axNode` for the
     `logicalIndex` strip per `registerHandlers` call, one `Bool` store per
     drawn frame (the retry flag), and per `List` two `Bool` stores in
     `requestLayout` and one `Bool` read in `prepaint`. None allocates by
     reading; no instrument measured it.
   - The demo's labels are written at the call site
     (`button("-", minus).accessibilityLabel("Decrement")`), not inside
     `CounterPanel.button`, and the scrim's after its `onClick`.
6. **The cost tests' footing.** Their bridge is over a plain `NSView`, which has
   none of `MetalHostView`'s overrides, so "read the host's children" is spelled
   `noteClientRead()` plus `rootElements()`; the table's rows are read through
   the vended element's own `accessibilityRows()`. The retry test's cap and
   inactive arms use 500 rows (its main arm keeps 5,000), and frame 1 asserts
   exactly 10 rows, from `visibleRange`'s arithmetic, where the spec said "at
   most 12". The animation test reads the landed width, 120, as a control.

**Why.** Items 1–4 are the smallest changes that make each rule a mutation can
break observable, and item 3 is forced by `AB-G` as written. Item 5's spellings
each remove a way to misuse an internal API or record what a field no longer
does.

**Evidence.** Measured: the red run on `2e5ca0a`; the first green run's one
failure (item 3); three mutation rounds, each over the whole table and the
unfiltered suite: `aa5d055` (46 rows; N46 and N49 survived, N19 did not build
and was re-spelled), `15f0dd2` (52 rows; N52 and N60 survived) and `ecb0504`
(57 rows). All in the record.

7. **The verifier round (after `4d97ba6`) added a sixteenth test and one arm.**
   The 57-row table had no survivor, but it had no mutant for three rules, and
   the verifier's hunting mutants on each survived the unfiltered suite, each
   first shown to change a published value:
   - **L3V01**, step C not recursing below a kept node that is not a folding
     button. No fixture put a combining button under a published node, though
     the demo's `CounterPanel` (a focusable container of click targets over
     texts) is exactly that shape. Pinned by a new arm in
     `aClickableContainerCombinesItsTextsIntoOneButtonLabel` and by the list
     arm below.
   - **L3V02**, step C gating on clickability instead of the published `.button`
     role. **The gate is the role deliberately**: a clickable `List` is a
     table (`AB-L`), and gating on clickability folds its rows into one label.
   - **L3V05**, `windowIsBounded` ignoring a non-positive `rowHeight` (item 5's
     spelling). Without the clause, a zero-`rowHeight` list in a measured
     scroller publishes every row on every frame.
   `combinationReachesButtonsInsideAListAndAClickableListKeepsItsRows` pins L3V01
   (click targets inside a bounded list's rows), L3V02 (a clickable list keeps its
   10 rows) and L3V05 (`rowHeight` 0 publishes no row). L3V01 reddens both tests;
   L3V02 and L3V05 redden the new one. `Resolving.isInteractive`'s doc comment,
   which described the negation of the property, was corrected.

**Hazards left for the integration step.**

- **The retry cap starves a list shown beside one that always asks.** `AB-X`
  rule 3's cap is a single window-wide `Bool` (one extra frame per run of
  asking frames). A `List` whose scroller never measures a viewport, such as a
  zero-height collapsed section, asks on every frame, so the run never ends and
  **no other list's retry is honoured again**. A list shown later publishes its
  table with no rows, and the window goes clean. The rows publish on the next
  frame drawn for any other reason. Measured in the record: with the
  zero-height list, the toggle took 1 frame and published 0 rows,
  `needsRedraw false`; without it, 2 frames and 10 rows. Unfixed and unpinned.
  The named fix keys the cap per list id: dirty whenever the set of asking ids
  gains a member that did not ask on the previous frame. That set is built only
  while collecting.

- **Distribution reads the gated registries.** A distributor must not be
  focusable or adjustable, and both are read from `FocusRegistry` (as `AB-H`'s
  actions and `AB-J`'s focusability are). After the environment merge a
  disabled element is not registered (`EV-F`), so a **disabled** focusable or
  adjustable labelled container becomes a distributor and its label moves onto
  its children. SwiftUI distributes from those containers anyway (arms C1,
  C5), so this lands nearer SwiftUI, not further; the joint disabled test in
  the merge contract does not exercise a labelled container, and nothing pins
  the interaction.
- **CLAUDE.md's demo `StateTable` figures are stale.** The demo's three labels
  are declared nodes and write `$ax` slots every frame, client or not (`AB-U`
  exempts only synthesized records), so the warm resident counts (165 at 40
  rows, 63 at 500) must be re-taken from record §07's harness. Not re-taken here.
- **Record §05's inert rows.** `AXNode.logicalCount` now has a reader (the
  builder publishes it as `AXRowCount`), and `AXNode.logicalIndex` is a new
  internal field with one writer (`List`) and one reader (the builder).
  `AXNode.children` is still always `[]` and `Frame.axNodes` still has no
  production reader: the bridge reads records.

**Cost if wrong.** Item 2: had the strip gone unguarded, a client reading a
bounded `List` would have written one `$ax` slot per realized row per frame,
changing `@State` retention with VoiceOver on, which is what `AB-U` exists to
prevent. Item 3: the portal test would have kept passing only if its fixture
stopped exercising a button, which is the case `AB-V` was written for.

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

## Second critic round (2026-09-15) — findings applied and rejected

A second critic reviewed the design and lane 1 at `53d3bf6`, re-ran the rules
probe (all 62 lines matched its header) and the overrides typecheck (exit 0),
and ran new SwiftUI and AppKit arms in its scratchpad. Every arm it cited was
re-run by the design session and committed with its output before a ruling
cites it: `swiftui-accessibility-bridge-critic2.swift` (C0–C5, P0–P2, E0–E2,
plus the session's C5i, C6, C7) and `appkit-voiceover-signal-isolation.swift`
(the warning). Its `axwindow.swift` check (an `NSAccessibilityElement` derives
its window from an overridden parent) is not committed, because no ruling
cites it.

| # | finding | done |
|---|---|---|
| 1 | `AB-Z` written against the environment track's superseded design; synthesis contradicts `EV-W` item 4 | **Applied.** `AB-Z` and the spec's merge contract rewritten against `f4dcad8`: registration skipped when disabled, derived-id blocker, gated `$focus` write, no `Frame.init` parameter. Synthesis reads the ungated handlers; actions and focusability come from the gated registries with no builder edit. The joint test gains focusable-only and adjustable-only arms, with four mutations. Arm P2 committed |
| 2 | `display: none` on an inner `ModifiedElement` layer escapes `AB-O`; `ElementGroup.swift` collision unlisted | **Applied.** The layer loop's suppression is specified, with a code shape (`AB-Z` item 4, `AB-O`); `aHiddenInnerModifierLayerSuppressesEverythingInsideIt` written now, green here, reddened by M20; the adjacent `StateBinder.bind` line listed (`AB-Z` item 3) |
| 3 | `allowsHitTesting(false)` removing the press is the opposite of SwiftUI | **Applied as a recorded divergence**, not a behaviour change (`AB-H`, arms P0/P1): no store holds the handler outside the hitbox list, no legacy spelling reaches it, and task 12 owns the question (re-pointed 2026-09-25 by `EV-AE`/`EV-AF` from "task 9", this work's number when this row was written). `aPressIsRefusedWhereHitTestingIsDisabled` is now named a divergence pin; M16 is SwiftUI's side |
| 4 | distribution exclusions for focusable/adjustable unprobed and opposite to SwiftUI | **Applied as a recorded divergence** (`AB-T`, arms C1, C2, C5, and the session's C5i, which showed SwiftUI copies the adjustable action to each child). Actions route by the node's own id, and focus needs a node; lane 3's arm 7 renamed a divergence pin |
| 5 | `VoiceOverSignal` as spelled warns, and the probe's exit code could not catch it | **Applied.** `AB-AB`: synchronous initial read after observing, later changes through a main-actor `Task`, no `assumeIsolated`; the probe calls the handler, is read by grep, and carries the spec's first spelling as a negative control and an unused-variable control. Pending activation is delivered when `onRequest` is assigned (the bridge exists before `Window.init` wires it), with a mutation for that |
| 6 | end-to-end tests cannot force the signal `false` | **Applied.** `AB-AC`: an internal `AppKitPlatform(device:accessibilitySignal:)`, the tests build `Window(platformWindow:…)` over it; the arm-Q test's machine dependency stated in its doc and failure message |
| 7 | "deepest element wins" ignores portals | **Applied, with a different key than suggested.** `AB-W`: geometry carries `layer` and `order`, and the hit test takes the greatest `(layer, order)`, click dispatch's own ranking. "Later root first" was rejected because a `Deferred` declared before a list is an earlier root. Modal arm added |
| 8 | activating before the first frame can leave a `List` with no rows indefinitely | **Applied, first option, with a cap.** `AB-X` rule 3: a collecting `List` awaiting its viewport requests one retry frame; `WindowAccessibility` honours it only if the previous frame did not. The test no longer forces a redraw, and gains a zero-height cap arm and an inactive arm |
| 9 | the focused-element trigger fires for non-VoiceOver users; unmeasured | **Applied: measured, then dropped.** The two-process probe shows an out-of-process focused-element query reaches `accessibilityFocusedUIElement`; it is no longer a trigger (`AB-B`). The same probe shows a position query reaches `accessibilityHitTest`, which stays a trigger, with the cost recorded. Script item 1 now lists and quits AX utilities first |
| 10 | uncommitted test changes contradict the record | **Applied: committed and re-taken.** Suite run as found (1100 passed), committed as `71805eb`; all 39 mutations (M01–M35, H02, H05, H06, H14, M36–M39) re-run unfiltered, plus M40 and two M08 repeats; the record's table replaced. M33 is the only survivor, owned by lane 3 as before |
| 11 | `Text("")` would publish; SwiftUI omits it | **Applied.** `accessibleText: string.isEmpty ? nil : string`; empty and blank arms (E0–E2) in lane 3's first test, with a mutation (`AB-F`) |
| 12 | button combination drops descendants' value | **Applied as a rule change.** `AB-G`: a descendant with both a label and a value contributes its value; values join with `", "`. Arms C3, C4 and the session's C6, C7; four value arms and two mutations in lane 3 |
| 13 | a press can run a different element's `onClick` after identity adoption | **Applied as a recorded hazard, pinned** (`AB-H`). Detaching on a label change rejected (arm 12, and every counter's element would die on each press). Lane 2's end-to-end `aHeldElementWhoseIDIsAdoptedPressesTheAdopter`, two disagreeing arms; script item 9 |
| 14 | "a hidden root draws nothing, unreachable" is unmeasured and contradicts CLAUDE.md | **Applied: measured and fixed.** `aHiddenRootPublishesNothing` red (two records, the root at 20×20), fixed in `Frame.render` (`AB-AD`, `6bd208c`), M40 reddens it; `AB-AA`'s claim withdrawn in place |
| 15 | lane 1 alone is inert in production; demo state counts will move | **Applied as record entries** owed to the integration step: an inert-table row to delete when lane 2 merges, and a re-take of CLAUDE.md's warm resident `StateTable` counts after lane 3 (the spec's demo section says why) |

