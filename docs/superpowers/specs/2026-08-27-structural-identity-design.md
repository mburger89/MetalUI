# Structural Identity — Design

**Date:** 2026-08-27
**Status:** Approved design; implementation plan not yet written.
**Parent spec:** `docs/superpowers/specs/2026-08-24-metalui-design.md` §4.3 (identity and cross-frame state), §9 (accessibility)
**Ruling this milestone serves:** EP-5 — where CSS and SwiftUI answer a design question differently, take SwiftUI's answer.

---

## 1. Goal

Give every element an identity by default, keyed on its structural position, with
`.id()` as an override.

Today identity is opt-in and its absence is contagious.
`GlobalElementID.child(of:_:)` returns `nil` when *either* the parent path or the
child's local id is `nil`, so an unnamed container poisons the entire subtree
beneath it: no descendant can hold cross-frame state, however carefully it is
named. That is a DOM-ish rule — identity exists because someone wrote an
attribute. SwiftUI's is the inverse, and it is the one EP-5 selects: a view's
identity is *structural* by default, and `.id()` changes it rather than creating
it.

**This is a prerequisite EP-5 created, not a feature.** Together with content
sizing (merged 2026-08-27) it completes the set; neither blocks the other.

## 2. Scope

**In:** the §4.3 identity key, its construction, and every call site.

**Out, deliberately:**

- **Tombstones and exit transitions.** §4.3 records that AX identity needs
  entries to survive the sweep as invalid-reporting tombstones, and that exit
  transitions are impossible until that exists. Universal identity makes
  tombstones *more* useful and no easier; it is a separate change to the sweep.
- **A `ForEach` element.** `ArrayGroup` already exists and is what a `for` loop
  in a builder produces. Nothing new is introduced to carry ids.
- **EP-6's re-decision** (`Column`/`Row` centring by default). Unblocked by
  content sizing, unrelated to this.
- **Any change to `StateTable`'s mark-and-sweep.** Only the key changes.

## 3. Architecture

### 3.1 The key

A path component becomes an either/or, which makes "a name replaces a position"
enforceable by the type rather than by convention:

```swift
enum PathComponent: Hashable, Sendable {
    case positional(Int)
    case named(ElementID)
}
```

**Why a name replaces a position rather than combining with it.** Inside a
`ForEach`, SwiftUI's explicit id *is* the identity, so reordering a list carries
each item's state with it. If the index were also in the key, an item moving from
index 0 to 1 would get a new key and lose its scroll offset, hover, and animation
progress on every move — the opposite of what `.id()` exists for. Outside such a
list, structural position is the identity, which is what gives anonymous elements
state at all.

**Accepted cost:** two siblings both given `.id("a")` collide into one entry.
That is SwiftUI's documented duplicate-id hazard, and it is pinned rather than
trapped — trapping would forbid an `ArrayGroup` whose data genuinely contains
duplicate keys, turning a data bug into a crash in a shipping app.

### 3.2 `GlobalElementID` becomes a persistent linked list

```swift
public final class GlobalElementID: Hashable, Sendable {
    let component: PathComponent
    let parent: GlobalElementID?
    private let cachedHash: Int      // combine(parent?.cachedHash, component)
}
```

All stored properties are `let`, so the class is `Sendable`. Building a child is
**one allocation regardless of depth**, and tails are shared rather than copied.

Note this changes `GlobalElementID` from a struct to a class, so `===` becomes
spellable alongside `==`. They are not the same: two structurally identical paths
built on different frames are `==` and never `===`, and **`==` is the only one
that may be used as a key or a comparison.** `StateTable` is keyed on
`Hashable`, so it uses `==` by construction; the hazard is a hand-written
comparison elsewhere. No production code compares ids today apart from the table.

This is a cost decision, not an aesthetic one. Today `child(of:_:)` does
`GlobalElementID(parent.path + [component])` — an array copy per level, O(depth)
per node — and only *named* subtrees pay it. Making identity universal makes
every node pay it every frame, on a hot path in a framework that rebuilds every
element every frame and whose layout already costs ~40 µs/node in debug after
content sizing's 4.9× (CLAUDE.md). The linked list removes the depth factor:
O(n) per frame rather than O(n·depth).

**Equality must walk the chain.** `cachedHash` is a fast *reject* only. A
hash-equality shortcut would turn a collision into two unrelated elements
silently sharing state — the same failure shape as the memo key that shipped
without `containingBlockWidth` during content sizing.

**The parent must be in the hash — but this section originally overstated why,
and the overstatement was falsified by measurement during Task 1.**

It called the omission "the single most dangerous line in the milestone" and
claimed a test whose mutation is exactly that omission. Measured, `--no-parallel`,
reconfirmed after a clean build: **dropping the parent from `cachedHash` reddens
nothing**, and **replacing `==` with `l.cachedHash == r.cachedHash` also reddens
nothing.** Neither is dangerous alone.

The accurate statement: `cachedHash` and `==` are safe individually and unsafe
only **together**. `==` uses the hash as a fast *reject*, so a collision falls
through to the chain walk, which is independent of hash quality; and
`Set`/`Dictionary` correctness depends on `==`, not on distribution. `Hashable`
permits collisions.

So a degraded hash alone is a **performance** defect — though a sharp one
*because of this milestone*: once every node is identified, most components are
`.positional(k)`, so every node at the same index in the whole tree hashes into
one bucket and `StateTable` lookups go quadratic per frame. Symmetrically, a
hash-shortcut `==` is correct exactly while the hash is good.

**The load-bearing line is `==`'s chain walk, not the hash formula.** The hash
half *is* guardable and gets a test — `theHashItselfDistinguishesPathsDifferingOnlyInAnAncestor`,
asserting on the public `hashValue`, which needs no visibility change because
`hash(into:)` is `hasher.combine(cachedHash)`. The `==` half is **not** guardable:
a 64-bit collision is not constructible against a per-process-seeded `Hasher`, so
per taxonomy shape 6 the mechanism is stated at `==` rather than left silent.

Retention: a `StateTable` key holds its whole ancestor chain alive, bounded by
live entries and released by the sweep. The array representation held the same
data; nothing changes.

### 3.3 `nil` leaves the type

The constructor is:

```swift
static func child(of parent: GlobalElementID?,
                  at index: Int,
                  name: ElementID?) -> GlobalElementID
```

**`parent` is optional and §3.5 is why** — an earlier draft declared it
non-optional, which contradicts "the root element's id is simply the one with
`parent: nil`" two sections later. Both could not hold, and the optional form is
the only one that lets `Frame.render` build a root at all.

It returns a **non-optional**, and `name` decides the component: non-`nil` gives
`.named(name)`, `nil` gives `.positional(index)`. The `index` is passed
unconditionally even when a name is present, so a caller never has to decide
which of the two to supply — that decision lives in one place. Consequently:

- `Element`'s three phases take `GlobalElementID`, not `GlobalElementID?`.
- `StateTable.withState`'s `guard let id else { …scratch… }` branch is **deleted**.
- "Every element has identity" stops being a rule a reader must remember and
  becomes something the compiler enforces.

This is the bulk of the diff — three phase signatures plus `ElementGroup`'s three,
rippling through every conformance and every hand-built test element — and it is
mechanical.

### 3.4 Indices come from the enclosing group, and the space is flat

An element cannot supply its own index: `Element` refines `ElementGroup`, so a
`Box` is a list of one and does not know where it sits. The cursor is threaded:

```swift
func requestGroupLayout(under parent: GlobalElementID,
                        at cursor: inout Int,
                        pass: inout LayoutPass) -> GroupLayout
```

The single-element default implementation consumes one index and advances; `Pair`
recurses into `.0` then `.1` with the same cursor; `ArrayGroup` recurses per
element.

**The index space is flat, and deliberately does not inherit the builder's
nesting.** `Column { A; B; C }` has the type `Column<Pair<A, Pair<B, C>>>` —
pinned by an existing type-level test — but identity is `A=0, B=1, C=2`, not
`A=[0], B=[1,0], C=[1,1]`. Flat is SwiftUI's model (a `TupleView`'s children are
positionally flat whatever the tuple shape) and it is more stable: under nesting,
changing *how* the builder groups could shift paths when the visible child order
did not.

The three phases each restart the cursor at 0 and traverse in the same order, so
they agree by construction. A traversal that disagreed would already trap on
`ElementGroup`'s existing phase-mismatch preconditions — that machinery was built
during the element pipeline and this reuses it rather than adding a parallel
guard.

### 3.5 Two sub-decisions, both following SwiftUI

- **`EitherGroup`'s branches get distinct components** (`.positional(0)` and
  `.positional(1)`), so flipping an `if/else` resets state rather than carrying it
  across two structurally different subtrees.
- **`Frame.render`'s root** is `.positional(0)` unless the root element is named.

  **The `.root` sentinel disappears, and it must** — an earlier draft of this
  section said it "remains the empty path", which contradicts §3.2: every
  `GlobalElementID` has a component, so an empty path is not constructible. The
  root element's id is simply the one with `parent: nil`. Where `Frame.render`
  today writes `child(of: .root, element.elementID)`, it constructs the root id
  directly.

## 4. What this falsifies

Four committed tests encode the old rule **in their names** —
`anIdentifiedChildOfAnAnonymousParentHasNoIdentity`,
`twoAnonymousSiblingsChildrenCannotCollideBecauseNeitherHasIdentity`, and their
siblings in `StateTableTests.swift`. They are **rewritten to the opposite
assertion, never deleted**, each carrying a comment naming what changed, so the
reversal is visible rather than silent.

`twoSiblingsWithTheSameIDShareOneStateEntryForNow` loses its "for now": the
collision is now deliberate and matches SwiftUI.

## 5. Testing

| Behaviour | Mutation that must redden it |
|---|---|
| An anonymous element holds state across frames | revert `child` to the nil-propagating form |
| Reordering a **named** `ArrayGroup` carries state | make `.named` also include the index |
| Reordering an **unnamed** one does not | make positional components constant |
| The **hash** distinguishes paths differing only in an ancestor | drop `parent` from the cached hash |
| `==` respects the ancestor whatever the hash says | make components compare equal regardless of parent |
| Flipping an `EitherGroup` branch resets state | give both branches the same component |
| Adding a sibling shifts later siblings' identity | pinned as **deliberate**, SwiftUI's matching behaviour named in the comment |

Every count is taken under `--no-parallel` with the exact edit quoted beside it
(rulings CS-M and CS-N: a parallel run drops failing-test names from the log body,
and a mutation count is only reproducible with its spelling).

**Performance is measured, not asserted.** The claim is O(1) per node replacing
O(depth). The branching-tree harness used during content sizing measures it
directly; the figure goes in CLAUDE.md labelled with when and how it was taken.

## 6. Exit criteria

- [ ] `swift test` completes with a **summary line** and the full count;
      `swift package clean && swift build` warning-free
- [ ] `GlobalElementID?` appears nowhere in `Sources/` — `nil` is gone from the type
- [ ] An anonymous element holds state across frames, pinned
- [ ] A named `ArrayGroup` carries state through a reorder; an unnamed one does not
- [ ] Every mutation in §5 measured and recorded, `--no-parallel`, spelling quoted
- [ ] The parent-in-hash test exists, asserts on `hashValue`, and its omission
      mutation reddens **exactly** it
- [ ] `==`'s chain walk carries a stated mechanism explaining why no test can
      guard it and why the danger is a combination — shape 6 requires the
      statement where the test cannot exist
- [ ] Path-construction cost measured on a branching tree and recorded in
      CLAUDE.md with when and how
- [ ] The four falsified tests rewritten, not deleted, each naming what changed
- [ ] §4.3 of the design spec updated to describe structural identity
- [ ] Every new "cannot happen" comment names a **mechanism**, not a milestone
