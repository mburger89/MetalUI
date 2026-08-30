# `@State`, Hit Testing and Input Dispatch — Design

**Status:** approved in brainstorming 2026-08-29. Follows measure-path performance
(merged as `d1bb46a`). Implements the input half of design spec §12's milestone 3.

Three subsystems that depend on each other in one direction: `@State` gives a
handler somewhere to write, hit testing decides which handler runs, and focus and
keymaps route keystrokes to one. The exit criterion is §12's **counter demo**.

---

## 1. Why now, and what is already built

**Three milestones have recorded a limitation that ends at the same sentence.**
`Frame.scrollRegions` is the only hitbox list this framework has, so a `Deferred`
scrim registers no region at all and cannot block a wheel event; CLAUDE.md says
"nothing short of §8.1's general hitbox list will change that". This milestone is
that list.

**More exists than the gap suggests.** `InputEvent` already carries the full
mouse, key and modifier set (`Sources/MetalUIPlatform/InputEvent.swift`), and
`KeyEvent` already matches on `charactersIgnoringModifiers` — §8.3's Dvorak and
AZERTY rule, already obeyed.

**And `Frame.scrollRegions` is already a hitbox list in miniature**: bounds
intersected with the active clip, carrying a layer, registered in prepaint, picked
by `(layer, registration order)`. The generalisation has its precedent in the repo
rather than in a book.

---

## 2. `@State`

### 2.1 The storage and the key already exist

`StateTable` is the storage and `GlobalElementID` is the key. Universal structural
identity means every element has one. `ScrollView` is doing `@State` by hand
today — its offset lives in exactly that table through
`pass.withState(id, initial:)`.

Nothing new is stored in the element struct. That is what lets state survive the
fresh-tree-every-frame model.

### 2.2 The wrapper is a box, and that is what makes it possible in public Swift

`Mirror` hands back **copies** of a struct's stored properties, so it cannot write
into them. But if the wrapper's storage is a `final class` box, the copy shares the
same box. So the framework can walk an element's properties, find the `@State`
wrappers, and seed each box with its location.

```swift
@propertyWrapper
public struct State<Value> {
    final class Box { var location: (StateTable, GlobalElementID)? }
    let box = Box()
    let initialValue: Value
    public var wrappedValue: Value { get { … } nonmutating set { … } }
}
```

**Seeding happens in `requestGroupLayout`**, which is where the framework already
computes the element's id. No private runtime metadata, no field-offset
arithmetic — the box indirection is the whole trick.

### 2.3 Slots key by declaration ordinal, through a named child id

Two `@State` properties on one element need two distinct entries, and
`StateTable` is keyed by `GlobalElementID` alone.

**Each slot gets its own derived id: `GlobalElementID.child(of: id, at: n,
name: ElementID("$state\(n)"))`.** A name *replaces* a position rather than
joining it — verified at the source, `ElementID.swift:79` reads
`name.map(PathComponent.named) ?? .positional(index)` — so a slot id can never
collide with a positional child's, because positional children carry no name.

**Read that literally: when a name is given the `at:` index is IGNORED.** The
ordinal therefore has to live inside the name string, which is why the slot is
`"$state\(n)"` and not `at: n` with a constant name. Passing `at: n` alongside is
harmless and misleading; the implementation should pass whatever the call site
already has and rely on the name alone.

`n` is the **declaration ordinal**, not the property name. Order is stable across
a rename; names are not, and this repo already has a rule against keying on names.

**The collision this leaves**, stated because it is reachable: an element that
writes `.id("$state0")` by hand would collide with slot 0. The prefix makes it
unlikely and nothing more.

### 2.4 Seeding must MARK, and this is a change to the sweep's rule

`StateTable.withState` marks on **access**, and `sweep()` drops every unmarked
entry. Its own doc explains the choice: "an element that is produced but never
touches its state has nothing worth keeping."

**That rule is wrong for `@State`.** A conditional read —

```swift
if showDetail { Text("\(count)") }     // `count` read only on some frames
```

— would leave the slot unmarked on frames where the branch is not taken, and the
next `sweep()` would discard it. The counter would silently reset.

So **seeding marks**, whether or not the value is read. Declaring `@State` is
sufficient intent to keep it. This is an addition to the marking rule, not a
replacement: `withState`'s mark-on-access behaviour is unchanged for every
existing caller.

### 2.5 Reflection is cached per TYPE

`Mirror` over every element every frame would undo the milestone that just took
the demo tree to 1.273 ms. A type is reflected **once** — does it declare any
`@State`, at which ordinals — and the answer is reused for every instance
forever.

**The harness asserts this as a count**, in the shape that caught
`unbreakableRuns`: *reflection runs once per type, not once per element per
frame.* A count fails identically on any machine; a timing baseline would rot.

### 2.6 Writing marks the window dirty

SwiftUI's `@State` setter invalidates, and ruling EP-5 makes SwiftUI the design
authority where it and CSS differ. A `@State` you must manually request a redraw
after is a footgun.

Minimal: the setter raises a `needsDisplay` flag the window already consults.
Real dirty tracking — only the affected subtree — is §12's milestone 4 and stays
there.

### 2.7 The hazard `@State` makes reachable

CLAUDE.md documents that a vanishing `if` makes the trailing sibling **adopt**
the vanished element's identity slot rather than reset. Today that costs nothing,
because almost nothing holds cross-frame state. `@State` makes it reachable by
ordinary code for the first time: a counter after a conditional block inherits the
vanished element's count.

Not fixable here — it is a property of structural identity, and the documented
remedy (name the trailing sibling) already exists. **Pinned by a test and noted at
the wrapper**, so the first person to hit it finds the explanation rather than a
mystery.

---

## 3. Hit testing

### 3.1 Hitboxes subsume scroll regions

One ordering mechanism, not two. `Frame.scrollRegions` becomes a hitbox carrying a
scroll payload; dispatch walks one list.

This is what closes the recorded limitation: a `Deferred` scrim registers an
**opaque** hitbox and therefore swallows the wheel event that currently falls
through to the list beneath it.

**It touches scroll routing, which has shipped two intermittent defects that no
test caught and only a human found** — an offset clamped on read but unbounded on
write, and a fade clock read from a frozen display-link tick. The plan pins
existing routing behaviour **green, before anything changes.**

### 3.2 Registration

```swift
let hitbox = pass.insertHitbox(bounds, opaque: true)
```

In prepaint, exactly §8.1. The content mask and layer come from the active stacks,
as scroll regions already do.

Dispatch walks **in reverse** so the topmost opaque hit wins. A non-opaque hitbox
does not stop the walk.

> **Wording note, added at the end of the milestone.** "Walks in reverse" is no
> longer literally what the implementation does, and the difference is not drift.
> `topmostOpaqueHitbox(in:at:)` (`Sources/MetalUI/Hitbox.swift`) filters to the
> eligible records and takes the `.max` by `(layer, registration index)` — one
> expression, and there is exactly **one copy of it** where there were three
> before the scroll-region fold. The specified *behaviour* is unchanged: the
> record that would have won a reverse walk is the maximum of the same
> ordering, and it is now also the record with the highest layer, which a plain
> reverse walk over the registration order never expressed. A fourth copy of
> this rule must not be added; a reader comparing this paragraph to the code
> should read the code.

### 3.3 Hover resolves at the end of prepaint

§8.1 promises `hitbox.isHovered` is queryable during `paint` with no one-frame
lag. "Topmost wins" is not knowable until every hitbox is registered — so hover
resolves **once, at the prepaint/paint boundary** `Frame.render` already has,
against the last known mouse position.

Registration order alone cannot answer it, and resolving per-registration would
give a different answer depending on declaration order.

### 3.4 Active

The hitbox that received `mouseDown`, held until `mouseUp`, keyed by
`GlobalElementID` so it survives the frames between. A press that leaves the
hitbox and returns stays active — that is what makes a button feel like a button.

### 3.5 Cut from §8.2, deliberately

- **Capture phase.** With opaque hitboxes a modal already swallows, which is the
  motivating case §8.2 names for capture. Bubble-only until something needs more.
- **`phase`/`momentumPhase` beyond the existing `isMomentum` flag.** Native
  trackpad feel deserves its own attention, not a corner of this milestone.

---

## 4. Focus, keymaps, actions

### 4.1 Actions are types

```swift
struct Increment: Action {}
```

Dispatched by type identity, so a typo is a compile error rather than a silent
no-op. §8.3 is explicit that they are not strings.

### 4.2 Focus is a tree registered in prepaint

Alongside hitboxes — same phase, same shape. The focused node's id is **window**
state, since focus is singular per window. Key events dispatch from the focused
node upward through its ancestors, bubbling until handled.

### 4.3 Context predicates get a real parser

§8.3 specifies `identifier`, `key == value`, `&&`, `||`, `!`, contributed during
prepaint via `.keyContext("Editor", ["mode": "code"])`, matched **innermost-first**
from the focus chain.

A small pure function with no engine coupling — the most heavily testable unit in
the milestone, and worth building properly rather than as a substring match.

### 4.4 `KeyEvent` gains a timestamp, and the reason is a bug this repo already shipped

§8.3's two-stroke sequences need a **1-second** pending-prefix timeout.
`KeyEvent` carries no timestamp; `ScrollEvent` does, and its doc comment records
why: the clipping milestone shipped a fade clock read from the display link's last
tick, **which freezes while the link is paused**, so an event arriving after an
idle period computed a nonsense age and suppressed the indicator on the very frame
that should have shown it.

A keystroke timeout reading the display link reproduces that bug exactly. So
`KeyEvent` gains a timestamp from `NSEvent.timestamp`, and the timeout reads the
event's own clock.

**On expiry the prefix is dropped, not dispatched** (§8.3). Easy to get backwards.

---

## 5. Scope

**In:** §2 `@State`; §3 hit testing, hover, active; §4 focus, keymaps, actions,
predicates, two-stroke; the counter demo.

**Out, deliberately:**

- **Capture phase** and **trackpad phase handling** (§3.5).
- **Real dirty tracking** — §2.6 ships the one-line invalidation, not M4's
  subtree tracking.
- **The 100k-row list.** M3's other exit criterion, and a stress test of the
  previous milestone rather than this one.
- **AX nodes.** M3's third piece; it needs the tombstones design spec §4.3 names
  as absent, and is independent of everything here.
- **IME** (§8.4). Its own subsystem, and M6's.

**This is the largest milestone this project has run.** The natural cut, if it
sprawls during execution, is **after hover and active work and before focus
begins** — §2 and §3 are a coherent deliverable on their own.

---

## 6. Testing

**No oracle exists for input.** WebKit arbitrates layout; nothing arbitrates
"what does a click hit". So this leans on unit tests over synthetic hitbox lists,
with the predicate parser carrying the heaviest load as a pure function.

**A hard invariant: no golden may move.** 81 today. Input touches no layout, so a
moved golden means something reached the engine that should not have — stop and
report, do not regenerate.

**Counts, not timings**, wherever a performance property is asserted — §2.5's
per-type reflection especially. The measure-performance milestone established the
instrument.

**What no test here can see**, named in advance so nobody claims them later:
whether a click *feels* responsive, whether hover highlighting reads correctly,
and whether focus is visible. Three human looks, on the footing of z-order and
the scrim.

---

## 7. Exit criteria

1. `swift package clean`, warning-free build **including `MetalUIDemo`**, full
   `swift test` **summary line** read — never the exit status.
2. **No golden moved.** 81.
3. Reflection runs once per type, asserted as a count.
4. A `Deferred` scrim swallows a wheel event that reaches it — the limitation
   three milestones recorded, closed.
5. Existing scroll routing behaviour is pinned **before** hitboxes subsume it,
   and still passes after.
6. The counter demo works: click increments, and a keymap binding increments.
7. **A human runs it and reports** whether clicking feels responsive, whether
   hover reads correctly, and whether focus is visible.

---

## 8. Divergences and risks recorded up front

1. **`@State` slots can collide with a hand-written `.id("$state0")`** (§2.3).
   Unlikely; not prevented.
2. **A `@State` after a vanishing `if` adopts the vanished element's value**
   (§2.7). A property of structural identity, not of `@State`; the remedy is
   documented and the behaviour is pinned.
3. **Seeding marks, so a declared-but-never-read `@State` is never swept**
   (§2.4). Deliberate — the alternative silently resets a counter — but it means
   `@State` keeps entries `withState`'s rule would drop.
