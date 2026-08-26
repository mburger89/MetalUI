# MetalUI — The Element Pipeline

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Close milestone 1. A `Component` produces `Column`/`Row`/`Box` elements, the three-phase pipeline drives the flex engine, and the demo window shows a nested flex layout that **resizes correctly** and **switches light/dark**.

**Architecture:** Fresh element tree every frame, no diffing (§4.1). Three passes — `requestLayout` → `prepaint` → `paint` — over one `@MainActor final class Frame`, with thin pass structs so that emitting a rect during layout is a **compile error**. Cross-frame state lives in a side table keyed by `GlobalElementID`, marked on access and swept per frame (§4.3). `AnyElement` is a hand-written **struct** box (§4.6).

**Tech Stack:** Swift 6.3, Swift Testing. No third-party dependencies.

**Spec:** `docs/superpowers/specs/2026-08-24-metalui-design.md` §4, §3.1, §7.9.

**Prior work:** wrapping is merged — 207 tests, 57 fixtures. Read
`docs/superpowers/2026-08-25-wrapping-decisions.md` and **`docs/practices/verifying-tests-can-fail.md`,
especially shapes 9 and 10.** Ruling IDs here are prefixed **`EP-`**.

## Global Constraints

- **Swift tools 6.3**, `swiftLanguageModes: [.v6]`, strict concurrency ON. Warnings are errors to fix, never suppress.
- **No third-party dependencies. No `.unsafeFlags`.**
- **`MetalUILayout` imports only `MetalUICore`.** Verify anchored:
  ```bash
  grep -rnE "^import (Metal|AppKit|UIKit|WebKit|MetalUIRender|MetalUIPlatform)$" \
    Sources/MetalUILayout/ && echo "LAYERING VIOLATION" || echo "clean"
  ```
- **Dependencies stay one-way** (§3.1). This plan adds exactly one edge: `MetalUI` → `MetalUILayout`. Nothing else moves.
- **Everything user-facing is `@MainActor`.** The pipeline is single-threaded by design (§3.3).
- **`swift package clean`, never `rm -rf .build`.**
- **Mutation hygiene.** `git checkout <file>` restores nothing on an untracked file; on a tracked file it discards *all* uncommitted work in it. Commit before mutating; `cp` aside and back.
- **Out of scope:** text and `Text` (M2), hit-testing and input (M3), `@Observable` and animation (M4), Grid and `MetalView` (M5), virtualization (§4.7), accessibility nodes (§9), exit transitions (§14, and §4.3 explains why they need a tombstone mechanism).

---

## Why this milestone matters more than its feature list suggests

**The layout engine has no production consumer.** Six milestones, 207 tests, 57 browser-verified
fixtures — and:

```bash
grep -rln "MetalUILayout" Sources/ | grep -v "^Sources/MetalUILayout"   # → nothing
```

`MetalUI` does not even depend on it in `Package.swift`. Everything the engine does is exercised by
tests and by nothing else. That is the same shape as `roundLayout` (zero production callers until
flex sizing) and `resolveEdges` (zero until the box model), at **target scale** — and it is not in
CLAUDE.md's inert table, because that table tracks `Style` properties, not whole subsystems.

This plan is what makes layout load-bearing. Expect that to surface things the corpus could not: the
corpus feeds `LayoutTree` by hand, and a real producer builds it differently.

## What the spec already measured, so you do not have to rediscover it

Two findings in §4.6 are **empirical, recorded because they fail silently**, and this plan's Task 2
exists to encode them as tests:

1. **`any Element` cannot drive the pipeline.** `requestLayout` on an `inout any Element`
   type-checks; `prepaint` fails with `error: member 'prepaint' cannot be used on value of type
   'any Element' [#ExistentialMemberAccess]`, because `LayoutState` and `PrepaintState` appear in
   `inout` (invariant) position. Hence a hand-written erasure.
2. **The box must be a `struct`.** With a class box, two copies share one `LayoutState`:
   `Row { sep; sep }` reports `layoutState = 2` twice — wrong bounds, no error, no diagnostic. The
   struct box reports 1 then 2.

Finding 2 is a **silent-corruption trap**. Its test is not optional and it is not a formality.

## The uniformity traps specific to this milestone

| Trap | Where it collapses | Rule |
|---|---|---|
| a tree with **one** element of each type | a class box aliases nothing — the trap needs **two copies of the same element type as siblings** | `Row { sep; sep }` |
| an element whose state is never read back | aliasing is invisible if nobody observes the state | assert on the state in a **later** phase |
| a tree built once | mark-sweep does nothing without a rebuild | rebuild across frames, with membership changing |
| a **square** window | width/height threading is indistinguishable | resize non-square, and to a different aspect |
| a layout with one level | nested bounds accumulation is untested | at least two levels of nesting |
| light and dark with the same numbers | theming cannot be distinguished from a constant | assert on values that actually differ |

**Before committing a test, mutate the thing it is named for and confirm it reddens.** And per
shape 10: any comment you write of the form *"cannot happen"*, *"unreachable"*, *"needs M2"* is a
prediction about measurement — name the **mechanism**, not the milestone.

---

### Task 1: `Element`, `Frame`, and phase separation enforced by the compiler

**Files:**
- Create: `Sources/MetalUI/Element.swift`
- Create: `Sources/MetalUI/Frame.swift`
- Create: `Sources/MetalUI/Passes.swift`
- Create: `Tests/MetalUITests/PipelineTests.swift`
- Create: `Tests/MetalUITests/PhaseSeparationTests.swift`
- Modify: `Package.swift` (add the `MetalUILayout` dependency to `MetalUI`)

**Interfaces:**
- Produces: `protocol Element`, `final class Frame`, `struct LayoutPass`, `struct PrepaintPass`, `struct PaintPass`, `struct Bounds`.

Take the `Element` protocol verbatim from spec §4.1. `LayoutPass`/`PrepaintPass`/`PaintPass` are
thin structs over one `@MainActor final class Frame`, each exposing **only** what is legal in its
phase.

**The compile-error property is the task's deliverable, not a nicety.** "Emitting a rect during
layout is a compile error" is a claim about the *type system*, and a claim about what will not
compile can only be tested by trying to compile it.

- [ ] **Step 1: Write the compile-failure test first**

`Tests/MetalUICoreTests/UnitSafetyTests.swift` already does exactly this for units — it writes a
fixture, runs `swiftc -typecheck` against the built modules, and asserts the result. **Reuse its
approach; do not invent a second one.**

Read its `modulesDirectory()` first. It filters out `.build/index-build` because SourceKit populates
that with whatever toolchain the *editor* runs — a module there built by a different Swift version
makes the typecheck fail for a reason that has nothing to do with the code, and the failure presents
as a safety regression. That fix landed in `009768a`; your new tests inherit the hazard.

Assert **both** directions:

```swift
@Test func emittingAPrimitiveDuringLayoutDoesNotCompile() {
    // LayoutPass must expose no way to reach the Scene.
    let result = typecheck("""
        func fixture(pass: inout LayoutPass) { pass.fill(.zero, color: .white) }
        """)
    #expect(!result.succeeded)
    // And it must fail for the RIGHT reason — a typo in the fixture also
    // "fails to compile" and would pass a bare `!succeeded`.
    #expect(result.output.contains("fill"))
}

@Test func emittingAPrimitiveDuringPaintDoesCompile() {
    #expect(typecheck("func fixture(pass: inout PaintPass) { pass.fill(.zero, color: .white) }").succeeded)
}
```

**The positive case is what makes the negative one mean something.** A negative-only pair passes
just as well when `fill` does not exist at all.

- [ ] **Step 2: Run to verify it fails, then implement**

Expected: `cannot find type 'LayoutPass' in scope`.

Implement `Frame` as the single owner of per-frame state, and the three pass structs as views over
it. Registering a layout node is legal only in `LayoutPass`; hitboxes only in `PrepaintPass`;
primitives only in `PaintPass`.

- [ ] **Step 3: Add the layering edge**

`MetalUI` currently depends on `MetalUICore`, `MetalUIRender`, `MetalUIPlatform` — **not**
`MetalUILayout`, which is why the engine has no production consumer. Add it. Do not add any other
edge, and do not make `MetalUILayout` depend on anything new.

- [ ] **Step 4: Commit, then prove**

```bash
# 1. Give LayoutPass a `fill` method.
#    Expect: emittingAPrimitiveDuringLayoutDoesNotCompile reddens.
# 2. Rename PaintPass's `fill`.
#    Expect: emittingAPrimitiveDuringPaintDoesCompile reddens — proving the
#    positive case is load-bearing and not just decorative.
# 3. Point `modulesDirectory()` back at `.build/index-build`.
#    Expect: a confusing failure. This is the hazard from 009768a; confirm the
#    filter still guards your new tests, not only the unit ones.
```

---

### Task 2: `AnyElement` — the hand-written struct box

**Files:**
- Create: `Sources/MetalUI/AnyElement.swift`
- Modify: `Tests/MetalUITests/PipelineTests.swift`

**Interfaces:**
- Produces: `protocol ElementObject` (**not** `AnyObject`), `struct AnyElementBox<E: Element>: ElementObject`, `struct AnyElement`.

**Read §4.6 before writing anything.** Both of its findings are measured, and the second is a
silent-corruption trap that this task exists to pin.

- [ ] **Step 1: Write the aliasing test — the one the spec specifies**

Two **copies of the same element type as siblings**. One copy, or two different types, and a class
box aliases nothing:

```swift
/// Two sibling copies of the same element must not share `LayoutState`.
///
/// **Measured in the spec (§4.6): with a CLASS box this prints
/// `layoutState = 2` twice** — both copies see the second one's state, so the
/// first is laid out at the wrong bounds. No error, no diagnostic. With the
/// struct box it is 1 then 2.
///
/// This is why `AnyElementBox` is a struct, and why a future refactor that
/// "simplifies" it to a class is a silent-corruption regression rather than a
/// style change.
@Test func twoCopiesOfOneElementDoNotShareLayoutState() {
    // A probe element whose LayoutState is a counter incremented per instance,
    // read back in prepaint.
    ...
    #expect(observed == [1, 2])
}
```

- [ ] **Step 2: Run to verify it fails, then implement**

Implement the erasure exactly as §4.6 gives it. **`ElementObject` must not be `AnyObject`** — that
constraint is what would silently permit a class box.

- [ ] **Step 3: Record what does *not* work, and why**

Add a doc comment naming the two measured facts: `any Element` fails on `prepaint` with
`#ExistentialMemberAccess` because the associated types are in `inout` position, and
`struct AnyElement: ~Copyable` does not work either (`[AnyElement]` gives *"type 'AnyElement' does
not conform to protocol 'Copyable'"*), which is why gpui's move-only `Box<dyn ElementObject>` has no
Swift equivalent.

**Name the mechanism, not the Swift version.** "Does not work in Swift 6.3" is shape 10 waiting to
happen; "associated types in `inout` position cannot be opened" is checkable.

- [ ] **Step 4: Commit, then prove**

```bash
# 1. Change `struct AnyElementBox` to `final class AnyElementBox`.
#    Expect: twoCopiesOfOneElementDoNotShareLayoutState reddens with [2, 2].
#    IF IT DOES NOT, the probe element's state is not observed late enough —
#    fix the test, because this is the one trap the spec measured for you.
# 2. Add `: AnyObject` to `ElementObject`.
#    Expect: a compile error, or mutation 1 becomes expressible again.
```

---

### Task 3: Identity and the cross-frame state table

**Files:**
- Create: `Sources/MetalUI/ElementID.swift`
- Create: `Sources/MetalUI/StateTable.swift`
- Modify: `Sources/MetalUI/Frame.swift`
- Create: `Tests/MetalUITests/StateTableTests.swift`

**Interfaces:**
- Produces: `struct ElementID: Hashable`, `struct GlobalElementID: Hashable` (the **path** of `ElementID` components from the root), `final class StateTable`.

Per §4.3: state that must survive a rebuild lives in a side table keyed by `GlobalElementID`,
**marked on access and swept after each frame**. That dictionary plus mark-sweep **is** the entire
reconciliation story — there is no diffing anywhere in this framework.

- [ ] **Step 1: Write the failing tests**

Three properties, and the third is the one a naive implementation gets wrong:

```swift
@Test func stateSurvivesARebuildWhenTheElementIsProducedAgain()
@Test func stateIsSweptWhenTheElementStopsBeingProduced()

/// Identity is the PATH, not the local id. Two elements with the same local
/// `ElementID` under different parents must not share state.
///
/// A `[ElementID: State]` dictionary passes the first two tests and fails this
/// one — which is why the first two alone are not coverage.
@Test func sameLocalIDUnderDifferentParentsDoesNotShareState()
```

- [ ] **Step 2: Implement, and record the two consequences §4.3 calls load-bearing**

The sweep forces both, and both are cited elsewhere in the spec — put them in the doc comment where
someone changing the sweep will read them:

- **Accessibility identity rides this table** (§9). An AX client retains element references across
  frames, so a node it still holds must survive the sweep as a **tombstone that reports itself
  invalid**, not vanish. Not built here; named here.
- **Exit transitions are impossible without that tombstone mechanism**, which is *why* v1 does not
  have them (§14). An element that stops being produced has its animation state swept on that very
  frame. Adding exit transitions later is a change to §4.3, not a feature bolted onto animation.

- [ ] **Step 3: Commit, then prove**

```bash
# 1. Key the table on the local ElementID instead of the path.
#    Expect: sameLocalIDUnderDifferentParents... reddens, the other two do not.
# 2. Never sweep.
#    Expect: stateIsSweptWhen... reddens. Also check nothing else does — if a
#    later test depends on stale state surviving, that is a real finding.
# 3. Sweep before the frame instead of after.
#    Expect: stateSurvivesARebuild... reddens.
```

---

### Task 4: `Box`, `Column`, `Row`, and styling

**Files:**
- Create: `Sources/MetalUI/Box.swift`
- Create: `Sources/MetalUI/Stack.swift`
- Create: `Sources/MetalUI/ElementBuilder.swift`
- Create: `Tests/MetalUITests/ElementLayoutTests.swift`

**Interfaces:**
- Produces: `struct Box<Child: Element>: Element`, `struct Column<Child: Element>`, `struct Row<Child: Element>`, `@resultBuilder enum ElementBuilder`, and the styling modifiers.

**This is where the layout engine gets its first production caller.** `requestLayout` builds a
`LayoutTree` and calls `computeLayout`; `prepaint` reads the resolved rects as `Bounds`.

**Result builders must preserve concrete types** (§4.6, allocation mitigation 1):
`Column { Label(...); Button(...) }` builds `Column<Pair<Label, Button>>`, statically typed, **no
boxing**. Only genuinely dynamic children need `AnyElement`. A builder that erases everything to
`[AnyElement]` compiles, passes every behavioural test, and quietly defeats the whole allocation
story — pin it with a type-level test.

- [ ] **Step 1: Write the failing tests**

```swift
/// The builder preserves concrete types — nothing is boxed on the static path.
///
/// A builder returning `[AnyElement]` passes every layout test in this file and
/// silently defeats §4.6's first allocation mitigation. Assert the TYPE.
@Test func theBuilderPreservesConcreteTypesRatherThanBoxing() {
    let column = Column { Box(); Box() }
    #expect(String(describing: type(of: column)).contains("Pair"))
    #expect(!String(describing: type(of: column)).contains("AnyElement"))
}

/// A nested layout resolves to the same rects the engine produces directly.
///
/// Two levels, non-square, asymmetric — a one-level square tree cannot
/// distinguish width from height, nor bounds accumulation from bounds assignment.
@Test func aNestedLayoutMatchesTheEngineRunDirectly()
```

- [ ] **Step 2: Implement**

Styling modifiers map onto the existing `Style`. **Do not add new `Style` properties** — the model
is complete and CLAUDE.md's inert table tracks what is not yet read.

- [ ] **Step 3: Check what this makes newly live, and what it does not**

`Style` properties reachable from a modifier are still only as live as the *engine* makes them.
`position`, `inset`, `overflow`, `aspectRatio` remain inert — **exposing a modifier for an inert
property is worse than not exposing it**, because it looks implemented from the outside. Either omit
the modifier or add a CLAUDE.md row.

**`MeasureFunction` / `newLeaf` still has no production caller.** `Box` has no content to measure;
that changes in M2 with `Text`. Do not "fix" its inert row.

- [ ] **Step 4: Commit, then prove**

```bash
# 1. Make the builder return [AnyElement].
#    Expect: theBuilderPreservesConcreteTypes... reddens and NOTHING else does —
#    which is the point: no behavioural test can see it.
# 2. Drop the parent's origin when computing child Bounds.
#    Expect: aNestedLayoutMatchesTheEngine... reddens. If it does not, the tree
#    is one level deep or its origin is zero.
# 3. Swap width and height when handing Bounds to prepaint.
#    Expect: reddens — if not, the fixture is square.
```

---

### Task 5: Paint, theming, and a window that resizes

**Files:**
- Modify: `Sources/MetalUI/Frame.swift`, `Sources/MetalUI/Window.swift`, `Sources/MetalUI/App.swift`
- Create: `Sources/MetalUI/Theme.swift`
- Modify: `Sources/MetalUIDemo/main.swift`
- Create: `Tests/MetalUITests/ThemeTests.swift`

**Interfaces:**
- Produces: `struct Theme`, and `paint` emitting into the renderer's `Scene`.

Theming per §7.9. **Colours are authored in sRGB while the layer's colorspace is Display P3** — a
known, expected divergence recorded in CLAUDE.md, not a bug to chase.

- [ ] **Step 1: Wire `paint` to the renderer, and the frame loop to the window**

The renderer and `RenderSurface` already work and were verified on real hardware in M0.

- [ ] **Step 2: Theming**

Light and dark must differ in **values a test can distinguish** — a theme whose two variants share a
number is untestable at that point.

- [ ] **Step 3: The demo — milestone 1's exit criterion**

A nested flex layout, at least two levels, **non-square**, that resizes correctly, plus a light/dark
switch.

- [ ] **Step 4: Run it and look at it**

```bash
swift run MetalUIDemo
```

**No test can establish this**, and CLAUDE.md says so: `MetalLayerSurface` vends drawables whether
its `CAMetalLayer` is attached or orphaned, so a perfectly-rendered frame can go into a texture
nobody sees while the whole suite stays green. Resize the window. Toggle the appearance. Look at it.

Then update CLAUDE.md's "Verified on real hardware" section with what you actually saw — it currently
describes a single rounded rect.

- [ ] **Step 5: Commit, then prove**

```bash
# 1. Ignore the resize event.
#    Expect: nothing in the suite reddens — this is the same class as M0's
#    orphaned layer. RECORD that, and say what a human must check instead.
# 2. Return the light theme unconditionally.
#    Expect: the theme test reddens.
```

## Exit criteria

- [ ] `swift test` passes, no warnings; `swift package clean && swift build` clean
- [ ] `MetalUILayout` still imports only `MetalUICore`; the only new dependency edge is `MetalUI` → `MetalUILayout`
- [ ] **`grep -rln "MetalUILayout" Sources/ | grep -v "^Sources/MetalUILayout"` is no longer empty** — the engine has a production consumer for the first time
- [ ] Emitting a primitive during layout **does not compile**, and the positive case does
- [ ] Changing `AnyElementBox` to a class reddens a test
- [ ] The result builder preserves concrete types, pinned by a type-level assertion
- [ ] `swift run MetalUIDemo` shows a nested flex layout that resizes and switches light/dark — **verified by a human, recorded in CLAUDE.md**
- [ ] Every new "cannot happen" / "unreachable" comment names a **mechanism**, not a milestone (shape 10)

## Deliberately NOT in this plan

- **Text** (M2) — and so `MeasureFunction`/`newLeaf` stays without a production caller.
- **Hit-testing, input, focus, actions** (M3). `prepaint` gets the phase but registers nothing yet.
- **`@Observable`, dirty tracking, animation** (M4) — this milestone rebuilds every frame unconditionally.
- **Grid, paths, `MetalView`** (M5). **Virtualization** (§4.7). **Accessibility nodes** (§9).
- **Exit transitions** (§14) — §4.3 explains why they need a tombstone mechanism first.

## Risks carried in

- **The auto-cross collapse** is the one live layout divergence, now pinned by `autoCrossNestedContainerCollapsesItsLineUnlikeWebKit`. A real producer may reach it sooner than the corpus did.
- **BM-4's over-constrained box**, **the root's percentage width**, and **`margin: auto` on both axes** are documented divergences.
- **FS-9 and AL-4 together state one rule** — two independent engines agreeing outrank the spec's letter; one engine alone does not.
- **`LayoutNodeID` has no generation counter** (m1a ruling C-3). A stale ID after `reset()` traps if the new tree is smaller and **silently addresses a different node** if larger. **This plan calls `reset()` every frame for the first time** — if a `LayoutNodeID` can now outlive its frame, close the hazard rather than documenting it.
- **Two guarantees lapse under plausible CI configurations** — the ABI probe skips without a Metal device, and `committedGoldensMatchTheBrowser` is the only live-WebKit consumer. Both must be required, non-gateable jobs.
