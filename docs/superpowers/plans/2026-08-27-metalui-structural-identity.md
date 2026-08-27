# Structural Identity Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give every element identity by default, keyed on structural position, with `.id()` as an override.

**Architecture:** `GlobalElementID` becomes a persistent linked list of `PathComponent` values (`.positional(Int)` or `.named(ElementID)`) with a hash cached at construction, so building a child is one allocation regardless of depth. Indices are supplied by the enclosing group through an `inout` cursor threaded only through `requestGroupLayout`, in a flat index space. `nil` leaves the type entirely, so "every element has identity" becomes a compiler guarantee.

**Tech Stack:** Swift 6.3, `swiftLanguageModes: [.v6]`, strict concurrency, Swift Testing. No third-party dependencies.

**Spec:** `docs/superpowers/specs/2026-08-27-structural-identity-design.md`

## Global Constraints

- `swift build` and `swift test` must be **warning-free**. Warnings are defects to fix, never suppress.
- No third-party dependencies. No `.unsafeFlags`.
- **`MetalUILayout` must import only `MetalUICore`.** Verify with an *anchored* pattern — an unanchored `Metal` also matches the legitimate `import MetalUICore`.
- **Goldens are browser-generated and must never move in this milestone.** Nothing here touches layout. `git status --short Tests/MetalUILayoutTests/Golden` must be empty at every commit.
- Use `swift package clean`, **never** `rm -rf .build`.
- **Mutation hygiene:** commit before mutating, and **commit before editing a doc**. `cp` a file aside and `cp` it back — `git checkout` restores nothing on an untracked file and discards *all* uncommitted work on a tracked one.
- **Suite integrity (taxonomy shape 11):** after every full run read the **summary line and test count**, never the exit status alone.
- **Ruling CS-M:** take every mutation count under `--no-parallel`. A parallel run drops failing-test names from the log body; the summary line's issue count is stable, a scraped test count is not.
- **Ruling CS-N:** a mutation count is only reproducible with its spelling. Quote the exact edit beside any number, and prefer "this test reddens" to "N tests redden".
- **Ruling CS-C:** a test asserting something does **not** trap must use `await #expect(processExitsWith: .success) { … }`. Bodies must be non-capturing.
- Every "cannot happen" comment names a **mechanism**, not a milestone.
- Read `docs/practices/verifying-tests-can-fail.md` before writing tests. It is the review standard.

---

### Task 1: `PathComponent`, the linked-list `GlobalElementID`, and the call sites

**Files:**
- Modify: `Sources/MetalUI/ElementID.swift`
- Test: `Tests/MetalUITests/GlobalElementIDTests.swift` (create)

**Interfaces:**
- Consumes: nothing.
- Produces: `enum PathComponent { case positional(Int); case named(ElementID) }`; `final class GlobalElementID` with `let component: PathComponent`, `let parent: GlobalElementID?`, `init(component:parent:)`, and `static func child(of parent: GlobalElementID?, at index: Int, name: ElementID?) -> GlobalElementID`.

**Ruling SI-C — this task originally stopped at the type, and that was impossible.** The first draft added the new type "beside" the existing one and left the call sites to a second task. Swift cannot have a struct and a class share one name in a module, so replacing `GlobalElementID` breaks `ElementGroup.swift:81`, `:421` and `Frame.swift:188` immediately — measured, 10 `error:` diagnostics at exactly those three sites, zero inside `ElementID.swift`. The suite could not build, let alone stay green. **A type replacement cannot be staged behind its own call sites.** The two tasks are merged; the former Task 2's call-site shim is Step 4b below.

The gate survives the merge and is the reason for the shim: **this task changes no behaviour.** All 342 existing tests stay green — including the four asserting the nil-poisoning rule — and no golden may change. Those four are rewritten in Task 2, deliberately and with comments naming what changed.

- [ ] **Step 1: Write the failing tests**

```swift
import Testing
@testable import MetalUI

@Test func aRootIdHasNoParent() {
    let root = GlobalElementID.child(of: nil, at: 0, name: nil)
    #expect(root.parent == nil)
    #expect(root.component == .positional(0))
}

@Test func aNameReplacesThePositionRatherThanJoiningIt() {
    let named = GlobalElementID.child(of: nil, at: 3, name: ElementID("a"))
    #expect(named.component == .named(ElementID("a")))
}

/// Structural equality, not reference identity. Two paths built separately —
/// as two frames do — are `==` and never `===`.
@Test func twoSeparatelyBuiltIdenticalPathsAreEqualButNotIdentical() {
    let a = GlobalElementID.child(of: GlobalElementID.child(of: nil, at: 0, name: nil),
                                  at: 1, name: nil)
    let b = GlobalElementID.child(of: GlobalElementID.child(of: nil, at: 0, name: nil),
                                  at: 1, name: nil)
    #expect(a == b)
    #expect(a !== b)
    #expect(a.hashValue == b.hashValue)
}

/// **The most dangerous line in this milestone.** If the cached hash omits the
/// parent, two paths differing only in an ancestor land in the same bucket and
/// compare by a hash that cannot tell them apart — two unrelated elements
/// silently share state.
@Test func pathsDifferingOnlyInAnAncestorAreNotEqual() {
    let left = GlobalElementID.child(of: nil, at: 0, name: nil)
    let right = GlobalElementID.child(of: nil, at: 1, name: nil)
    let underLeft = GlobalElementID.child(of: left, at: 0, name: ElementID("item"))
    let underRight = GlobalElementID.child(of: right, at: 0, name: ElementID("item"))

    #expect(underLeft != underRight)

    var set: Set<GlobalElementID> = []
    set.insert(underLeft)
    set.insert(underRight)
    #expect(set.count == 2)
}

/// Equality must walk the chain. A hash-equality shortcut turns a collision
/// into a wrong answer rather than a slow lookup.
@Test func differentDepthsWithTheSameTailAreNotEqual() {
    let shallow = GlobalElementID.child(of: nil, at: 0, name: nil)
    let deep = GlobalElementID.child(of: GlobalElementID.child(of: nil, at: 0, name: nil),
                                     at: 0, name: nil)
    #expect(shallow != deep)
}

/// A named component and a positional one never coincide, whatever the index.
@Test func aNamedComponentNeverEqualsAPositionalOne() {
    let named = GlobalElementID.child(of: nil, at: 0, name: ElementID("0"))
    let positional = GlobalElementID.child(of: nil, at: 0, name: nil)
    #expect(named != positional)
}
```

- [ ] **Step 2: Run them and confirm they fail**

Run: `swift test --filter GlobalElementIDTests`
Expected: FAIL — `PathComponent` does not exist and `child(of:at:name:)` does not exist.

- [ ] **Step 3: Add `PathComponent`**

```swift
/// One component of an element's identity path (spec §4.3).
///
/// **A name replaces a position; it never joins it.** That is SwiftUI's rule and
/// the reason is reordering: inside a list keyed by id, the id *is* the identity,
/// so an item moving from index 0 to index 1 must keep its state. If the index
/// were also in the key the move would mint a new key and reset the item's
/// scroll offset, hover and animation progress — the opposite of what `.id()`
/// exists for. Where no name is given, the position is the identity, which is
/// what lets an anonymous element hold state at all.
public enum PathComponent: Hashable, Sendable {
    case positional(Int)
    case named(ElementID)
}
```

- [ ] **Step 4: Replace `GlobalElementID` with the linked list**

```swift
/// An element's identity: the path of `PathComponent`s from the root (§4.3).
///
/// **A persistent linked list, not an array, and that is a cost decision.**
/// Every element builds a path every frame. The array form
/// (`GlobalElementID(parent.path + [component])`) copies O(depth) per node, and
/// before this milestone only *named* subtrees paid it. Universal identity makes
/// every node pay it, on a hot path in a framework that rebuilds every element
/// every frame. Sharing the tail makes a child one allocation regardless of
/// depth: O(n) per frame rather than O(n·depth).
///
/// **`cachedHash` is a fast reject, never a proof of equality.** `==` walks both
/// chains. A hash-equality shortcut would let two unrelated elements share one
/// state entry — the same failure shape as content sizing's memo key shipping
/// without `containingBlockWidth`.
public final class GlobalElementID: Hashable, Sendable {
    public let component: PathComponent
    public let parent: GlobalElementID?
    private let cachedHash: Int

    init(component: PathComponent, parent: GlobalElementID?) {
        self.component = component
        self.parent = parent
        var hasher = Hasher()
        hasher.combine(parent?.cachedHash ?? 0)
        hasher.combine(component)
        self.cachedHash = hasher.finalize()
    }

    /// The identity of a child at `index` under `parent`, named or not.
    ///
    /// **Never returns nil.** Before this milestone the equivalent returned `nil`
    /// when either end was anonymous, so an unnamed container poisoned its whole
    /// subtree. `index` is supplied unconditionally and `name` decides the
    /// component, so the name-replaces-position rule lives here rather than at
    /// every call site.
    public static func child(of parent: GlobalElementID?,
                             at index: Int,
                             name: ElementID?) -> GlobalElementID {
        GlobalElementID(component: name.map(PathComponent.named) ?? .positional(index),
                        parent: parent)
    }

    public static func == (l: GlobalElementID, r: GlobalElementID) -> Bool {
        if l === r { return true }
        if l.cachedHash != r.cachedHash { return false }
        var a: GlobalElementID? = l
        var b: GlobalElementID? = r
        while let x = a, let y = b {
            if x === y { return true }
            if x.component != y.component { return false }
            a = x.parent
            b = y.parent
        }
        return a == nil && b == nil
    }

    public func hash(into hasher: inout Hasher) { hasher.combine(cachedHash) }
}
```

**Try plain `Sendable` first.** Every stored property is a `let` of a `Sendable` type, and the recursive `parent` reference is fine — the compiler handles that. Fall back to `@unchecked Sendable` **only if it does not compile**, and if you do, state the exact diagnostic at the declaration as the reason. Do not reach for `@unchecked` pre-emptively: it silences a check rather than satisfying it.

- [ ] **Step 4b: Switch the three call sites, keeping today's nil semantics**

At `ElementGroup.swift:81` and `:421`, replace `let id = GlobalElementID.child(of: parent, elementID)` with:

```swift
// Index 0 for every member until Task 2 threads the cursor. Siblings collide
// meanwhile; the nil short-circuit below is what still separates them, and it
// is deleted in Task 2 together with this line.
let id: GlobalElementID? = parent.flatMap { p in
    elementID.map { GlobalElementID.child(of: p, at: 0, name: $0) }
}
```

At `Frame.swift:188`, replace `GlobalElementID.child(of: .root, element.elementID)` with:

```swift
let rootID: GlobalElementID? = element.elementID.map {
    GlobalElementID.child(of: nil, at: 0, name: $0)
}
```

`SingleElementLayout.id` and `AnyElement.GroupLayout.id` stay `GlobalElementID?`; dropping the optional is Task 2.

- [ ] **Step 5: Run the tests**

Run: `swift test --filter GlobalElementIDTests`
Expected: PASS, 6 tests.

- [ ] **Step 6: Run the whole suite**

Run: `swift test --no-parallel`
Expected: a summary line reading **348** (342 + 6). `git status --short Tests/MetalUILayoutTests/Golden` empty.

- [ ] **Step 7: Prove the guards**

```bash
# 1. Drop the parent from the cached hash: `hasher.combine(component)` only.
#    Expect: `pathsDifferingOnlyInAnAncestorAreNotEqual` reddens.
# 2. Make `==` return `l.cachedHash == r.cachedHash`.
#    Expect: report what reddens. If NOTHING does, say so — that means no test
#    constructs a genuine hash collision, and the guard is the chain walk being
#    present rather than a test. Record which it is; do not claim coverage you
#    did not measure.
# 3. Make `child` ignore `name` and always return `.positional(index)`.
#    Expect: `aNameReplacesThePositionRatherThanJoiningIt` reddens.
```

Restore each with `cp`, never `git checkout`. Report measured counts under `--no-parallel` with the exact edit quoted.

- [ ] **Step 8: Commit**

```bash
git add Sources/MetalUI/ElementID.swift Tests/MetalUITests/GlobalElementIDTests.swift
git commit -m "feat(element): GlobalElementID becomes a persistent linked list"
```

---

### Task 2: The cursor, the flat index space, and the end of `nil`

**Files:**
- Modify: `Sources/MetalUI/ElementGroup.swift` (the protocol's `requestGroupLayout`, and every conformance: `Element`, `EmptyGroup`, `Pair`, `OptionalGroup`, `EitherGroup`, `ArrayGroup`, `AnyElement`)
- Modify: `Sources/MetalUI/Element.swift` (three phase signatures), `Sources/MetalUI/Frame.swift`, `Sources/MetalUI/StateTable.swift`, `Sources/MetalUI/Passes.swift`
- Test: `Tests/MetalUITests/StateTableTests.swift`, `Tests/MetalUITests/ElementLayoutTests.swift`, `Tests/MetalUITests/IdentityTests.swift` (create)

**Interfaces:**
- Consumes: Task 1's type, Task 2's call sites.
- Produces:
  ```swift
  mutating func requestGroupLayout(under parent: GlobalElementID?,
                                   at cursor: inout Int,
                                   pass: inout LayoutPass) -> ([LayoutNodeID], GroupLayout)
  ```
  `Element`'s three phases take `GlobalElementID` (non-optional). `SingleElementLayout.id` and `AnyElement.GroupLayout.id` become non-optional.

**This is where behaviour changes.** `parent` stays optional in `requestGroupLayout` only because the root's parent is genuinely absent; everything below is non-optional.

- [ ] **Step 1: Write the failing tests**

```swift
import Testing
import MetalUICore
@testable import MetalUI

/// The rule this milestone exists for: an element with no `.id()` holds state
/// across frames. Before this, an unnamed element got scratch state that was
/// discarded on return.
@MainActor
@Test func anAnonymousElementHoldsStateAcrossFrames() {
    let table = StateTable()
    let size = Size<Pixels>(width: Pixels(100), height: Pixels(100))
    for _ in 0..<3 {
        let frame = Frame(contentSize: size, scaleFactor: 1, stateTable: table)
        var element = CountingElement(nil)     // no name
        frame.render(&element)
    }
    #expect(table.count == 1)
}

/// Position discriminates siblings, so two unnamed siblings do not collide.
/// Before this milestone neither had an identity at all.
@MainActor
@Test func twoUnnamedSiblingsDoNotShareOneStateEntry() {
    let table = StateTable()
    let size = Size<Pixels>(width: Pixels(100), height: Pixels(100))
    let frame = Frame(contentSize: size, scaleFactor: 1, stateTable: table)
    var row = Row { CountingElement(nil); CountingElement(nil) }
    frame.render(&row)
    #expect(table.count == 2)
}

/// The flat index space: the builder nests `Pair`s, identity does not.
@MainActor
@Test func theIndexSpaceIsFlatRatherThanNested() {
    let table = StateTable()
    let size = Size<Pixels>(width: Pixels(200), height: Pixels(100))
    let frame = Frame(contentSize: size, scaleFactor: 1, stateTable: table)
    var row = Row { CountingElement(nil); CountingElement(nil); CountingElement(nil) }
    frame.render(&row)
    // Three children of one row: 0, 1, 2 — not [0], [1,0], [1,1].
    let root = GlobalElementID.child(of: nil, at: 0, name: nil)
    for index in 0..<3 {
        #expect(table.peek(GlobalElementID.child(of: root, at: index, name: nil),
                           as: Int.self) == 1)
    }
    #expect(table.count == 3)
}
```

/// **A named list carries state through a reorder.** This is the whole reason a
/// name replaces a position rather than joining it: if the index were also in
/// the key, moving an item would mint a new key and reset it.
@MainActor
@Test func reorderingANamedListCarriesEachItemsState() {
    let table = StateTable()
    let size = Size<Pixels>(width: Pixels(300), height: Pixels(100))

    let first = Frame(contentSize: size, scaleFactor: 1, stateTable: table)
    var forward = Row { for n in ["a", "b"] { CountingElement(n) } }
    first.render(&forward)

    // Same two elements, opposite order. Each keeps its own entry and count.
    let second = Frame(contentSize: size, scaleFactor: 1, stateTable: table)
    var reversed = Row { for n in ["b", "a"] { CountingElement(n) } }
    second.render(&reversed)

    let root = GlobalElementID.child(of: nil, at: 0, name: nil)
    #expect(table.peek(GlobalElementID.child(of: root, at: 0, name: ElementID("a")),
                       as: Int.self) == 2)
    #expect(table.peek(GlobalElementID.child(of: root, at: 0, name: ElementID("b")),
                       as: Int.self) == 2)
    #expect(table.count == 2)
}

/// **An unnamed list does not**, because position IS the identity there. The
/// counts stay at 2 but they belong to the slots, not to the items — which is
/// exactly why `.id()` exists.
@MainActor
@Test func reorderingAnUnnamedListKeepsStateWithThePositionNotTheItem() {
    let table = StateTable()
    let size = Size<Pixels>(width: Pixels(300), height: Pixels(100))
    for _ in 0..<2 {
        let frame = Frame(contentSize: size, scaleFactor: 1, stateTable: table)
        var row = Row { CountingElement(nil); CountingElement(nil) }
        frame.render(&row)
    }
    let root = GlobalElementID.child(of: nil, at: 0, name: nil)
    #expect(table.peek(GlobalElementID.child(of: root, at: 0, name: nil), as: Int.self) == 2)
    #expect(table.peek(GlobalElementID.child(of: root, at: 1, name: nil), as: Int.self) == 2)
    #expect(table.count == 2)
}
```

Add `CountingElement` an initialiser taking `String?` if it does not already accept one; it exists in `StateTableTests.swift`.

- [ ] **Step 2: Run them and confirm they fail**

Run: `swift test --filter IdentityTests`
Expected: FAIL — anonymous elements have no identity yet.

- [ ] **Step 3: Add the cursor to the protocol and every conformance**

The protocol's `requestGroupLayout` gains `at cursor: inout Int`. `prepaintGroup` and `paintGroup` **do not** — they read the stored `layout.id`, which is why only one phase needs it.

`Element`'s default implementation:

```swift
public mutating func requestGroupLayout(under parent: GlobalElementID?,
                                        at cursor: inout Int,
                                        pass: inout LayoutPass)
    -> ([LayoutNodeID], SingleElementLayout<Self>) {
    let id = GlobalElementID.child(of: parent, at: cursor, name: elementID)
    cursor += 1
    let (node, state) = requestLayout(id, pass: &pass)
    return ([node], SingleElementLayout(id: id, node: node, state: state))
}
```

`Pair` forwards the same cursor to both halves in order, which is what makes the space flat:

```swift
let (firstNodes, firstLayout) = first.requestGroupLayout(under: parent, at: &cursor, pass: &pass)
let (secondNodes, secondLayout) = second.requestGroupLayout(under: parent, at: &cursor, pass: &pass)
```

`ArrayGroup` forwards it per element. `EmptyGroup` consumes nothing. `OptionalGroup` forwards when present and consumes nothing when absent.

**`EitherGroup`'s branches must not share a component.** Give the first branch `.positional(cursor)` and the second `.positional(cursor + 1)`, advancing the cursor by 2 in both cases, so flipping the branch changes the identity and the state resets — SwiftUI's behaviour, and the one this project's existing `EitherGroup` trap already treats as a different subtree.

- [ ] **Step 4: Drop the optional from `Element`'s phases and `StateTable`**

`Element`'s three phases take `GlobalElementID`. `SingleElementLayout.id` and `AnyElement.GroupLayout.id` become `GlobalElementID`. In `StateTable.withState`, **delete** the scratch branch:

```swift
    func withState<S>(_ id: GlobalElementID,
                      initial: @autoclosure () -> S,
                      _ body: (inout S) -> Void) {
        marked.insert(id)
        var value = (storage[id] as? S) ?? initial()
        body(&value)
        storage[id] = value
    }
```

`Frame.render` builds the root directly:

```swift
let rootID = GlobalElementID.child(of: nil, at: 0, name: element.elementID)
```

`PrepaintPass`/`PaintPass`'s `withState` overloads lose their optional too.

- [ ] **Step 5: Rewrite the four falsified tests — do not delete them**

In `StateTableTests.swift`, `anIdentifiedChildOfAnAnonymousParentHasNoIdentity` and `twoAnonymousSiblingsChildrenCannotCollideBecauseNeitherHasIdentity` assert the rule this task reverses. Rewrite each to the opposite assertion under a name that says what is now true — for example `anIdentifiedChildOfAnAnonymousParentHasItsOwnIdentity` — and give each a comment naming what changed and why, so the reversal is visible rather than silent.

`twoSiblingsWithTheSameIDShareOneStateEntryForNow` loses its "for now": the collision is deliberate and matches SwiftUI's documented duplicate-id hazard. Rename and rewrite the comment; keep the assertion.

- [ ] **Step 6: Run the whole suite**

Run: `swift test --no-parallel`
Expected: a summary line and the full count. Goldens unmoved — this task touches no layout.

- [ ] **Step 7: Prove it**

```bash
# 1. Make the cursor not advance (delete `cursor += 1`).
#    Expect: `twoUnnamedSiblingsDoNotShareOneStateEntry` reddens.
# 2. Give EitherGroup's two branches the same component.
#    Expect: report what reddens. If nothing does, no test covers a branch flip
#    carrying state — say so and add one.
# 3. Make `child` include the index even when a name is given.
#    Expect: `reorderingANamedListCarriesEachItemsState` reddens — the moved
#    item mints a new key and its count restarts at 1.
```

Report measured counts under `--no-parallel` with each exact edit quoted.

- [ ] **Step 8: Commit**

```bash
git add Sources/MetalUI Tests/MetalUITests
git commit -m "feat(element): structural identity, and nil leaves the type"
```

---

### Task 3: Delete the dead `parent` parameter

**Files:**
- Modify: `Sources/MetalUI/ElementGroup.swift` (`prepaintGroup` and `paintGroup` on the protocol and every conformance)

**Interfaces:**
- Consumes: Task 3's shape.
- Produces: `prepaintGroup(layout:pass:)` and `paintGroup(layout:prepaint:pass:)` — no `under parent:`.

**`under parent:` on the two later phases has no reader.** Every conformance either ignores it (`Element`, `AnyElement`, `EmptyGroup`) or forwards it unchanged (`Pair`, `ArrayGroup`, `OptionalGroup`, `EitherGroup`), because the identity those phases use is the one **stored** in the layout state — deliberately, so that all three phases see the same path even if the element's `elementID` changes between them. A threaded parameter nothing reads is the inert-API shape CLAUDE.md's table exists for, and this milestone is what makes it obvious.

Kept as its own task so a reviewer can reject it while approving Task 2.

- [ ] **Step 1: Confirm it is genuinely dead before removing it**

```bash
grep -n "under parent" Sources/MetalUI/ElementGroup.swift
```

For each `prepaintGroup`/`paintGroup` body, confirm `parent` is either unused or only passed onward. **If any body reads it for anything else, stop and report** — the parameter is not dead and this task is wrong.

- [ ] **Step 2: Remove it from the protocol and every conformance**

- [ ] **Step 3: Run the whole suite**

Run: `swift test --no-parallel`
Expected: unchanged count, summary line present, goldens unmoved.

- [ ] **Step 4: Commit**

```bash
git add Sources/MetalUI
git commit -m "refactor(element): drop the unread parent from prepaint and paint"
```

---

### Task 4: Measure the cost, and update what this falsified

**Files:**
- Modify: `CLAUDE.md`, `docs/superpowers/specs/2026-08-24-metalui-design.md` §4.3
- Create: `docs/superpowers/2026-08-27-structural-identity-decisions.md`

**Interfaces:**
- Consumes: everything above.
- Produces: documentation matching the code.

- [ ] **Step 1: Measure path construction on a branching tree**

The design claims O(1) per node replacing O(depth). Measure it rather than asserting it, on a **branching** tree — a chain cannot show the difference, which is the mistake content sizing's Task 6 made and had to correct.

Build a throwaway timing test (delete it afterwards; a spike's output is a number, not code): render a depth-12 branch-2 tree and a depth-10 branch-3 tree through `Frame`, timing `render`. Record both, and say plainly whether the improvement is visible above noise — **if it is not, say that**. An unmeasurable improvement honestly reported is worth more than a number nobody can reproduce.

- [ ] **Step 2: Record the figures in CLAUDE.md**

Label them with **when and how** they were taken — "measured 2026-08-27, debug unless a column says release" — and add a re-measure warning. An unlabelled performance number that was accurate when taken is the shape-10 pattern the last milestone hit six times.

- [ ] **Step 3: Update §4.3 of the design spec**

It currently says state is "keyed by `GlobalElementID`: the path of `ElementID` components from the root". That is now the path of `PathComponent`s, identity is structural by default, and `.id()` is an override. Update the section; leave the two consequences it records (AX tombstones, exit transitions) intact — this milestone does not change the sweep.

Add one sentence that universal identity **helps** §9: every element can now back an AX node, where an unnamed ancestor previously made whole subtrees unaddressable.

- [ ] **Step 4: Write the decisions doc**

Match `docs/superpowers/2026-08-26-content-sizing-decisions.md`'s shape: each ruling with its reasoning and what it costs if wrong. Record at minimum: why a name replaces a position rather than joining it; why the linked list rather than the array; why the index space is flat; why `EitherGroup`'s branches differ; and the duplicate-sibling-id collision as deliberate rather than pending.

Add the doc to CLAUDE.md's "Start here" list and its ruling-namespace note (`SI-` = structural identity).

- [ ] **Step 5: Sweep for claims this milestone falsified**

```bash
grep -rniE "anonymous|poison|no identity|scratch|nil" Sources/MetalUI/
```

`Box.swift:191`, `Passes.swift:132`, `StateTable.swift:64`, `Frame.swift:183-186` and `ElementGroup.swift:30` all describe the old rule in prose. Correct each — **do not delete them**; a comment that named a real hazard should say what replaced it.

- [ ] **Step 6: Update every count and commit**

Re-run, read the summary line, and update every test count you touch to the measured number. Do not propagate arithmetic on faith.

```bash
git add CLAUDE.md docs/superpowers Sources/MetalUI
git commit -m "docs: record structural identity and retire the anonymous-element rule"
```

## Exit criteria

- [ ] `swift test` completes with a **summary line** and the full count; `swift package clean && swift build` warning-free
- [ ] `GlobalElementID?` appears nowhere in `Sources/` except `requestGroupLayout`'s `parent` and `GlobalElementID.parent` itself
- [ ] An anonymous element holds state across frames, pinned
- [ ] Two unnamed siblings do not share a state entry, pinned
- [ ] The index space is flat, pinned against the builder's `Pair` nesting
- [ ] The parent-in-hash test exists and its omission mutation reddens exactly it
- [ ] Every mutation named in Tasks 1 and 2 measured under `--no-parallel`, with its exact edit quoted
- [ ] Path-construction cost measured on a **branching** tree and recorded in CLAUDE.md with when and how
- [ ] The falsified tests rewritten, not deleted, each naming what changed
- [ ] §4.3 updated; decisions doc written and listed in CLAUDE.md's "Start here"
- [ ] **No golden moved at any commit** — this milestone touches no layout

## Deliberately NOT in this plan

- **Tombstones and exit transitions** (§4.3, §14) — a change to the sweep, not the key.
- **A `ForEach` element.** `ArrayGroup` already exists and is what a builder's `for` loop produces.
- **EP-6's re-decision** (`Column`/`Row` centring by default) — unblocked by content sizing, unrelated to this.
- **Any change to mark-and-sweep.** Only the key changes.
- **Trapping on duplicate sibling ids.** It would forbid an `ArrayGroup` whose data genuinely holds duplicate keys, turning a data bug into a crash in a shipping app.

## Risks carried in

- **The parent-in-hash omission is the milestone's worst failure mode**: two unrelated elements silently sharing state, invisible to every layout and paint assertion. One test guards it.
- **`==` must walk the chain.** A hash-equality shortcut converts a collision into a wrong answer. The chain walk is cheap because `cachedHash` rejects first.
- **Adding a sibling shifts later siblings' identity** and resets their state. This is SwiftUI's behaviour and is pinned as deliberate — but it will surprise someone, so the pin's comment must say so.
- **Reference semantics are new.** `===` becomes spellable next to `==` and they differ: two structurally identical paths from different frames are `==` and never `===`. Only `==` may be used for lookup.
- **Layout is untouched, so the goldens cannot vouch for this milestone.** Every guard here is a hand-written test; there is no browser oracle for identity.
