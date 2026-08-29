# Absolute Positioning and Overlays Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Absolutely-positioned boxes removed from flow and placed against a containing block, plus a `Deferred` element that hoists its subtree above everything and escapes clipping.

**Architecture:** `Position` gains `.static` and it becomes the default, which is what makes containing-block resolution possible. Absolute children are filtered out of both flow-collection sites and placed in a second pass by `placeNode`, which **threads the containing block downward** rather than walking up — `LayoutTree` has no parent pointer. The paint half adds a `layer` to `Scene`'s sort key as CPU-side metadata, so it needs no ABI change.

**Tech Stack:** Swift 6.3 (`swiftLanguageModes: [.v6]`, strict concurrency), swift-testing, WKWebView layout oracle.

**Spec:** `docs/superpowers/specs/2026-08-28-absolute-positioning-design.md`

## Global Constraints

- **`MetalUILayout` must import only `MetalUICore`.** Verify with an anchored pattern — an unanchored `Metal` also matches the legitimate `import MetalUICore`.
- **No existing golden may move.** 76 in `Tests/MetalUILayoutTests/Golden/`. **If one moves, STOP and report.**
- **Read the test-run summary line, never the exit status.** `swift test --no-parallel 2>&1 | grep -E "Test run with"`. A run can die with no summary line and still exit 0 — that is a failed run. Baseline: **538 tests**.
- **Any count a later loop indexes on must be `try #require`, not `#expect`.**
- Build warning-free: `swift build 2>&1 | grep -cE "error:|warning:"` returns 0.
- **Comments explain mechanism, not milestones.**
- **A percentage `inset` does NOT follow CLAUDE.md's percentage-inset constraint.** That sentence (`CLAUDE.md:997`) is about `padding` and `border`, where CSS resolves every percentage against the containing block's **width**. `Style.inset` differs: `left`/`right` against **width**, `top`/`bottom` against **height**. Do not cite that constraint for insets.
- **`LayoutTree` has no parent accessor.** Containing blocks are threaded **downward**; do not add a parent array.
- Read `docs/practices/verifying-tests-can-fail.md` before writing tests.

---

### Task 1: `Position.static` becomes the default — inert

**Files:**
- Modify: `Sources/MetalUILayout/Style.swift:30, 89`
- Test: `Tests/MetalUILayoutTests/AbsolutePositioningTests.swift` (create)

**Interfaces:**
- Consumes: nothing.
- Produces: `Position.static`, and `Style.position` defaulting to it. Task 2 reads it.

**Why inert first.** Adding a case and moving a default cannot change layout while nothing is `.absolute`, so a golden moving in Task 2 is unambiguously Task 2's doing. This is the same shape the Stack milestone used and it paid off there.

- [ ] **Step 1: Write the tests**

Create `Tests/MetalUILayoutTests/AbsolutePositioningTests.swift`:

```swift
import Testing
import MetalUICore
@testable import MetalUILayout

/// `.static` is the default, and is not yet read by anything.
///
/// Deliberately weak and deleted in Task 2 — its only job is to prove the enum
/// gained a case and the default moved without disturbing the flex path.
@Test func positionDefaultsToStaticAndIsNotYetRead() {
    #expect(Style().position == .static)

    let tree = LayoutTree(generation: 0)
    var kid = Style()
    kid.size = Size(width: .length(.pixels(Pixels(40))),
                    height: .length(.pixels(Pixels(20))))
    kid.position = .absolute          // set, read by nothing yet
    let child = tree.newNode(style: kid, children: [])

    var row = Style()
    row.flexDirection = .row
    let node = tree.newNode(style: row, children: [child])

    computeLayout(tree, root: node,
                  available: AvailableSpaceSize(width: .definite(200),
                                                height: .definite(100)))
    // Still laid out in flow, because nothing reads `.absolute` yet.
    #expect(tree.layout(child).width == 40)
    #expect(tree.layout(child).x == 0)
}

/// `.relative` survives as the opt-in: it is how a caller becomes a containing
/// block without positioning itself. A two-case enum could not express that.
@Test func relativeIsStillDistinctFromStatic() {
    #expect(Position.relative != Position.static)
    #expect(Position.absolute != Position.static)
}
```

- [ ] **Step 2: Run to verify they fail**

Run: `swift test --no-parallel --filter AbsolutePositioningTests 2>&1 | grep -E "error:|Test run with"`
Expected: compile failure — `type 'Position' has no member 'static'`.

- [ ] **Step 3: Add the case and move the default**

`Sources/MetalUILayout/Style.swift:30` currently reads:

```swift
public enum Position: Sendable, Equatable { case relative, absolute }
```

Replace with:

```swift
/// Whether a box participates in its container's flow, and whether it acts as
/// the containing block for absolutely-positioned descendants.
///
/// **`.static` is the default and is the reason this enum has three cases.**
/// An `.absolute` box is placed against the nearest ancestor that is *not*
/// `.static`; with only `relative`/`absolute` every ancestor would qualify and
/// an absolute box could never reach past its immediate parent — a modal buried
/// in the tree could not cover the window.
///
/// `.relative` is therefore the opt-in: it makes a box a containing block
/// without moving it. This engine does not implement `relative`'s *offset*
/// behaviour (CSS shifts a relative box by its own inset while leaving its
/// in-flow space reserved); a `.relative` box lays out exactly as `.static` does.
public enum Position: Sendable, Equatable { case `static`, relative, absolute }
```

And at `:89`:

```swift
    public var position: Position = .static
```

- [ ] **Step 4: Run the whole suite**

Run: `swift package clean && swift test --no-parallel 2>&1 | grep -E "error:|warning:|Test run with"`
Expected: `Test run with 540 tests in 0 suites passed` (538 + 2).

**`swift package clean` is not optional here.** Adding a case to a public enum crossing module boundaries has produced stale incremental-build corruption on two consecutive milestones — a SIGSEGV with no summary line, or an assertion comparing against a value its own source cannot produce. If you see either, clean before investigating anything else.

**If any golden moved, STOP and report.** Moving a default that nothing reads cannot move a golden.

- [ ] **Step 5: Commit**

```bash
git add Sources/MetalUILayout/Style.swift Tests/MetalUILayoutTests/AbsolutePositioningTests.swift
git commit -m "feat: Position gains .static and it becomes the default

Inert -- nothing reads .absolute yet -- so a golden moving in the next
task is unambiguously that task's doing.

.static exists so an absolute box can skip past ancestors to a further
containing block. With only relative/absolute every ancestor qualifies
and a modal could never escape its parent."
```

---

### Task 2: Absolute children leave the flow

**Files:**
- Modify: `Sources/MetalUILayout/FlexEngine.swift:970` (`layOutStack`), `:1402-1403` (`collectItems`)
- Test: `Tests/MetalUILayoutTests/AbsolutePositioningTests.swift`

**Interfaces:**
- Consumes: `Position.static` (Task 1).
- Produces: containers whose measured size ignores absolute children. Task 3 places them.

**Context.** Two sites enumerate a container's children and filter `display != .none`:

- `collectItems` (`:1402`) — `tree.children(container).filter { tree.style($0).display != .none }.map { … }`
- `layOutStack` (`:970`) — `for kid in tree.children(container) where tree.style(kid).display != .none`

Both gain the same second condition. **Absolute children are still visited by `placeNode`** — they remain in `tree.children` — they are simply not *flow items*. Task 3 gives them positions; until then they will be left at whatever `placeNode` last wrote, which is fine because nothing asserts their position yet.

- [ ] **Step 1: Write the failing tests**

Replace Task 1's two placeholder tests with:

```swift
private func px(_ v: Double) -> MetalUICore.Dimension { .length(.pixels(Pixels(Float(v)))) }

private func sized(_ tree: LayoutTree, _ w: Double, _ h: Double,
                   position: Position = .static) -> LayoutNodeID {
    var s = Style()
    s.size = Size(width: px(w), height: px(h))
    s.position = position
    return tree.newNode(style: s, children: [])
}

/// An absolute child contributes nothing to its container's measured size.
///
/// **The absolute child is deliberately LARGER than the in-flow one on both
/// axes.** With a smaller absolute child, "removed from flow" and "included but
/// not the maximum" give identical answers and the test could not tell them
/// apart — the uniformity hazard that hid divergence 6 for four milestones.
@Test func anAbsoluteChildDoesNotContributeToItsContainersSize() {
    let tree = LayoutTree(generation: 0)
    let inFlow = sized(tree, 40, 20)
    let abs = sized(tree, 500, 300, position: .absolute)
    var row = Style()
    row.flexDirection = .row
    let node = tree.newNode(style: row, children: [inFlow, abs])

    let ctx = LayoutContext(rootFontSize: 16)
    let measured = measureNode(ctx, tree, node, known: .unspecified,
                               available: AvailableSpaceSize(width: .maxContent,
                                                             height: .maxContent),
                               containingBlockWidth: nil)
    #expect(measured.width == 40, "the 500-wide absolute child must not count")
    #expect(measured.height == 20, "nor its 300 height")
}

/// The same, for a stack — `layOutStack` is a separate enumeration site and a
/// fix applied to only one of the two is the shape this test exists to catch.
@Test func anAbsoluteChildDoesNotContributeToAStacksSize() {
    let tree = LayoutTree(generation: 0)
    let inFlow = sized(tree, 40, 20)
    let abs = sized(tree, 500, 300, position: .absolute)
    var s = Style()
    s.display = .stack
    s.alignItems = .center
    s.justifyItems = .center
    let node = tree.newNode(style: s, children: [inFlow, abs])

    let ctx = LayoutContext(rootFontSize: 16)
    let measured = measureNode(ctx, tree, node, known: .unspecified,
                               available: AvailableSpaceSize(width: .maxContent,
                                                             height: .maxContent),
                               containingBlockWidth: nil)
    #expect(measured.width == 40)
    #expect(measured.height == 20)
}

/// An absolute child does not shift its in-flow siblings either — it is not
/// merely excluded from the size, it occupies no space on the main axis.
@Test func anAbsoluteChildDoesNotShiftItsInFlowSiblings() {
    let tree = LayoutTree(generation: 0)
    let first = sized(tree, 40, 20)
    let abs = sized(tree, 500, 300, position: .absolute)
    let third = sized(tree, 30, 20)
    var row = Style()
    row.flexDirection = .row
    let node = tree.newNode(style: row, children: [first, abs, third])

    computeLayout(tree, root: node,
                  available: AvailableSpaceSize(width: .definite(400),
                                                height: .definite(100)))
    #expect(tree.layout(first).x == 0)
    #expect(tree.layout(third).x == 40, "not 540 — the absolute child takes no room")
}
```

- [ ] **Step 2: Run to verify they fail**

Run: `swift test --no-parallel --filter AbsolutePositioningTests 2>&1 | grep -E "recorded an issue|Test run with"`
Expected: all three fail — the absolute child is still a flow item, so the row measures 540 wide.

- [ ] **Step 3: Filter both sites**

In `collectItems` (`FlexEngine.swift:1402-1403`):

```swift
    return tree.children(container)
        // **Two exclusions, and they are different kinds.** `display: none`
        // removes a box entirely; `position: absolute` removes it from *flow*
        // while leaving it in the tree for `placeNode` to position against its
        // containing block. An absolute box contributes nothing to this
        // container's size and occupies no space on either axis.
        .filter { tree.style($0).display != .none && tree.style($0).position != .absolute }
```

In `layOutStack` (`:970`):

```swift
    for kid in tree.children(container)
    where tree.style(kid).display != .none && tree.style(kid).position != .absolute {
```

- [ ] **Step 4: Run the whole suite**

Run: `swift test --no-parallel 2>&1 | grep -E "error:|warning:|Test run with"`
Expected: `Test run with 541 tests in 0 suites passed` (540 − 2 placeholders + 3).

**If any golden moved, STOP and report** — no existing fixture uses `.absolute`, so none can be affected.

- [ ] **Step 5: Measure the mutations**

Each against the FULL suite, reddened test **names** recorded, then reverted:

1. Filter only in `collectItems`, leaving `layOutStack` unfiltered → expect the stack test **and not** the flex ones. That split is what proves the two sites are separately covered.
2. Filter only in `layOutStack` → expect the two flex tests.
3. Use `== .absolute` instead of `!= .absolute` (excluding everything *but* absolutes) → expect widespread reddening; record the count as evidence the filter is load-bearing.

- [ ] **Step 6: Commit**

```bash
git add Sources/MetalUILayout/FlexEngine.swift Tests/MetalUILayoutTests/AbsolutePositioningTests.swift
git commit -m "feat: absolute children are removed from flow at both collection sites

collectItems and layOutStack each enumerate a container's children, so a
filter applied to one of the two is a half fix. The mutation split proves
both are separately covered.

An absolute child contributes nothing to its container's measured size
and occupies no space on either axis -- the defining difference from a
Stack child, which does participate in sizing."
```

---

### Task 3: Containing blocks, threaded downward

**Files:**
- Modify: `Sources/MetalUILayout/FlexEngine.swift` (`placeNode`, `computeLayout`)
- Test: `Tests/MetalUILayoutTests/AbsolutePositioningTests.swift`

**Interfaces:**
- Consumes: the flow filter (Task 2).
- Produces: absolute children placed at their containing block's padding-box origin. Task 4 adds insets.

**The design decision this task turns on, and why the spec does not settle it.** `LayoutTree` has **no parent accessor** — `grep -n "func parent" Sources/MetalUILayout/LayoutTree.swift` finds nothing. So "walk up to the nearest non-`.static` ancestor" is not directly expressible.

**Thread the containing block downward instead.** `placeNode` already threads `containingBlockWidth: Double?`; it gains a containing-block parameter alongside. As it recurses, a node whose `position != .static` becomes the containing block for its descendants. **Do not add a parent array to `LayoutTree`** — it is redundant state that must be kept in sync, and the downward thread is how the engine already carries context.

- [ ] **Step 1: Write the failing tests**

```swift
/// An absolute child is placed against the nearest NON-STATIC ancestor, not its
/// parent.
///
/// **The parent is deliberately `.static` and offset from the containing
/// block.** A fixture where the parent *is* the containing block cannot
/// distinguish "walked the chain" from "used the parent" — and using the parent
/// is exactly the wrong implementation this test exists to catch.
@Test func anAbsoluteChildIsPlacedAgainstTheNearestNonStaticAncestor() {
    let tree = LayoutTree(generation: 0)
    let abs = sized(tree, 20, 10, position: .absolute)

    // A static wrapper, pushed away from the origin by a sibling.
    var staticWrapper = Style()
    staticWrapper.flexDirection = .row
    let wrapper = tree.newNode(style: staticWrapper, children: [abs])

    let spacer = sized(tree, 60, 10)

    // The containing block: relative, so it qualifies.
    var cb = Style()
    cb.flexDirection = .row
    cb.position = .relative
    cb.padding = Edges(all: .pixels(Pixels(5)))
    let containingBlock = tree.newNode(style: cb, children: [spacer, wrapper])

    computeLayout(tree, root: containingBlock,
                  available: AvailableSpaceSize(width: .definite(200),
                                                height: .definite(100)))

    // The wrapper sits at x = 65 (5 padding + 60 spacer). The absolute child
    // must ignore that and land on the containing block's PADDING box: (5, 5).
    #expect(tree.layout(wrapper).x == 65, "sanity: the static wrapper is offset")
    #expect(tree.layout(abs).x == 5, "not 65 — placed against the containing block")
    #expect(tree.layout(abs).y == 5)
}

/// With no non-static ancestor, the root is the containing block.
@Test func withNoPositionedAncestorTheRootIsTheContainingBlock() {
    let tree = LayoutTree(generation: 0)
    let abs = sized(tree, 20, 10, position: .absolute)
    let spacer = sized(tree, 60, 10)
    var row = Style()
    row.flexDirection = .row
    let inner = tree.newNode(style: row, children: [spacer, abs])
    var outer = Style()
    outer.flexDirection = .row
    let node = tree.newNode(style: outer, children: [inner])

    computeLayout(tree, root: node,
                  available: AvailableSpaceSize(width: .definite(200),
                                                height: .definite(100)))
    #expect(tree.layout(abs).x == 0)
    #expect(tree.layout(abs).y == 0)
}

/// The containing block is the ancestor's PADDING box, not its border box.
/// Getting this wrong shifts every absolute child by the border width — a
/// small uniform error that reads as a rounding problem rather than a bug.
@Test func theContainingBlockIsThePaddingBoxNotTheBorderBox() {
    let tree = LayoutTree(generation: 0)
    let abs = sized(tree, 20, 10, position: .absolute)
    var cb = Style()
    cb.position = .relative
    cb.border = Edges(all: .pixels(Pixels(7)))
    cb.padding = Edges(all: .pixels(Pixels(3)))
    let node = tree.newNode(style: cb, children: [abs])

    computeLayout(tree, root: node,
                  available: AvailableSpaceSize(width: .definite(200),
                                                height: .definite(100)))
    // Padding box starts inside the border: 7, not 0 and not 10.
    #expect(tree.layout(abs).x == 7)
    #expect(tree.layout(abs).y == 7)
}
```

- [ ] **Step 2: Run to verify they fail**

Run: `swift test --no-parallel --filter AbsolutePositioningTests 2>&1 | grep -E "recorded an issue|Test run with"`
Expected: the three new tests fail — nothing positions absolute children yet.

- [ ] **Step 3: Thread the containing block through `placeNode`**

Add a type near `StackItem`:

```swift
/// The rect an absolutely-positioned descendant is placed against.
///
/// Threaded **downward** through `placeNode` rather than resolved by walking up:
/// `LayoutTree` has no parent accessor, and adding one would be redundant state
/// to keep in sync. A node whose `position` is not `.static` replaces this for
/// its own descendants.
///
/// The rect is the containing block's **padding box** — inside its border, per
/// CSS. `origin` is absolute to the root, the same space `placeNode` positions in.
struct ContainingBlock {
    var origin: (Double, Double)
    var size: SizeD
}
```

Give `placeNode` a `containingBlock: ContainingBlock` parameter. `computeLayout` seeds it with the root's own padding box.

Inside `placeNode`, after the in-flow items are positioned:

```swift
    // The containing block for THIS node's descendants: itself if it is
    // positioned, otherwise whatever was threaded in.
    let childCB = s.position == .static
        ? containingBlock
        : ContainingBlock(origin: childOrigin, size: laid.box.size)

    // Absolute children, placed against `childCB` rather than in flow. They were
    // filtered out of `laid.lines`/`laid.stackItems` by Task 2, so this is the
    // only thing that positions them.
    for kid in tree.children(node)
    where tree.style(kid).display != .none && tree.style(kid).position == .absolute {
        placeAbsolute(ctx, tree, kid, in: childCB)
    }
```

And a placement function that, for this task, places at the containing block's origin at the child's own resolved size:

```swift
/// Places one absolutely-positioned box against its containing block.
///
/// **Insets are Task 4's.** This task places at the containing block's origin,
/// which is also the final behaviour for all-`auto` insets — spec §3.5 records
/// that as a deliberate divergence from CSS's static position.
private func placeAbsolute(_ ctx: LayoutContext, _ tree: LayoutTree,
                           _ node: LayoutNodeID, in cb: ContainingBlock) {
    let size = measureNode(ctx, tree, node,
                           known: .unspecified,
                           available: AvailableSpaceSize(width: .definite(cb.size.width),
                                                         height: .definite(cb.size.height)),
                           containingBlockWidth: cb.size.width)
    tree.setLayout(node, LayoutRect(x: cb.origin.0, y: cb.origin.1,
                                    width: size.width, height: size.height))
    placeNode(ctx, tree, node, origin: (cb.origin.0, cb.origin.1), size: size,
              containingBlockWidth: cb.size.width, containingBlock: cb)
}
```

**Read `placeNode`'s existing body before editing** — `childOrigin` and `laid` are its own locals and the names must match. If `laid.box.size` is not the padding box, use whatever local holds it; the requirement is the padding box, not a particular expression.

- [ ] **Step 4: Run the whole suite**

Run: `swift test --no-parallel 2>&1 | grep -E "error:|warning:|Test run with"`
Expected: `Test run with 544 tests in 0 suites passed` (541 + 3). **No golden may move.**

- [ ] **Step 5: Measure the mutations**

1. `childCB` always takes the threaded value (never replaced) → expect the nearest-ancestor test.
2. `childCB` is replaced unconditionally, ignoring `.static` → expect the nearest-ancestor test. **Both mutations must redden it**, from opposite directions.
3. Use the border box instead of the padding box → expect the padding-box test.

- [ ] **Step 6: Commit**

```bash
git add Sources/MetalUILayout/FlexEngine.swift Tests/MetalUILayoutTests/AbsolutePositioningTests.swift
git commit -m "feat: containing blocks, threaded downward through placeNode

LayoutTree has no parent accessor, so 'walk up to the nearest non-static
ancestor' is not directly expressible. Threading the containing block
down is how the engine already carries context (placeNode threads
containingBlockWidth), and it avoids a redundant parent array."
```

---

### Task 4: Insets and sizing

**Files:**
- Modify: `Sources/MetalUILayout/FlexEngine.swift` (`placeAbsolute`)
- Test: `Tests/MetalUILayoutTests/AbsolutePositioningTests.swift`

**Interfaces:**
- Consumes: `ContainingBlock`, `placeAbsolute` (Task 3).
- Produces: fully positioned absolute boxes. Task 5 oracles them.

**The rule, and the documentation trap.** `Style.inset` is `Edges<Dimension>` with `top`/`right`/`bottom`/`left`, defaulting to `.auto`.

| edge | percentage resolves against |
|---|---|
| `left`, `right` | containing block **width** |
| `top`, `bottom` | containing block **height** |

**CLAUDE.md:997 says "a percentage inset resolves against the CONTAINING BLOCK's width — not the box's own width, and not a height."** That sentence is about `padding` and `border`, where CSS *does* resolve everything against width. It is **wrong for `Style.inset`** on two of four edges, and it uses the word "inset". Do not cite it.

**Sizing, per axis:**

- Both insets given, size `auto` → `cb - leading - trailing`.
- One inset and a size → positioned from that edge at that size.
- Both insets and a size (over-constrained) → CSS drops `right` (LTR). Follow it.
- All `auto` → the containing block's origin at the box's own size. **This is a deliberate divergence** from CSS's static position (spec §3.5, §7.1) — measure WebKit's answer and record it, do not implement it.

- [ ] **Step 1: Write the failing tests**

```swift
private func inset(_ t: Double?, _ r: Double?, _ b: Double?, _ l: Double?) -> Edges<MetalUICore.Dimension> {
    Edges(top: t.map(px) ?? .auto, right: r.map(px) ?? .auto,
          bottom: b.map(px) ?? .auto, left: l.map(px) ?? .auto)
}

/// A single inset positions from that edge.
@Test func aSingleInsetPositionsFromThatEdge() {
    let tree = LayoutTree(generation: 0)
    var s = Style()
    s.size = Size(width: px(20), height: px(10))
    s.position = .absolute
    s.inset = inset(15, nil, nil, 25)
    let abs = tree.newNode(style: s, children: [])
    var cb = Style()
    cb.position = .relative
    let node = tree.newNode(style: cb, children: [abs])

    computeLayout(tree, root: node,
                  available: AvailableSpaceSize(width: .definite(200),
                                                height: .definite(100)))
    #expect(tree.layout(abs).x == 25)
    #expect(tree.layout(abs).y == 15)
    #expect(tree.layout(abs).width == 20)
}

/// Opposite insets with an `auto` size stretch the box between them.
@Test func oppositeInsetsWithAnAutoSizeStretchTheBox() {
    let tree = LayoutTree(generation: 0)
    var s = Style()
    s.position = .absolute
    s.inset = inset(10, 30, 20, 40)     // size stays .auto
    let abs = tree.newNode(style: s, children: [])
    var cb = Style()
    cb.position = .relative
    let node = tree.newNode(style: cb, children: [abs])

    computeLayout(tree, root: node,
                  available: AvailableSpaceSize(width: .definite(200),
                                                height: .definite(100)))
    #expect(tree.layout(abs).x == 40)
    #expect(tree.layout(abs).width == 130, "200 - 40 left - 30 right")
    #expect(tree.layout(abs).y == 10)
    #expect(tree.layout(abs).height == 70, "100 - 10 top - 20 bottom")
}

/// Over-constrained: both insets AND a size. CSS drops `right`.
@Test func anOverConstrainedBoxIgnoresItsRightInset() {
    let tree = LayoutTree(generation: 0)
    var s = Style()
    s.size = Size(width: px(50), height: .auto)
    s.position = .absolute
    s.inset = inset(0, 30, 0, 40)
    let abs = tree.newNode(style: s, children: [])
    var cb = Style()
    cb.position = .relative
    let node = tree.newNode(style: cb, children: [abs])

    computeLayout(tree, root: node,
                  available: AvailableSpaceSize(width: .definite(200),
                                                height: .definite(100)))
    #expect(tree.layout(abs).x == 40, "left wins")
    #expect(tree.layout(abs).width == 50, "the declared width wins; right is dropped")
}

/// **Percentage insets resolve per axis, and this is the test that catches
/// following CLAUDE.md's padding constraint by mistake.**
///
/// The containing block is deliberately NON-SQUARE — 200 wide, 100 tall. On a
/// square containing block `top: 10%` and `left: 10%` give the same number and
/// a width-only implementation passes. Here they differ: 10 vs 20.
@Test func percentageInsetsResolveAgainstWidthForXAndHeightForY() {
    let tree = LayoutTree(generation: 0)
    var s = Style()
    s.size = Size(width: px(20), height: px(10))
    s.position = .absolute
    s.inset = Edges(top: .length(.percent(0.10)), right: .auto,
                    bottom: .auto, left: .length(.percent(0.10)))
    let abs = tree.newNode(style: s, children: [])
    var cb = Style()
    cb.position = .relative
    let node = tree.newNode(style: cb, children: [abs])

    computeLayout(tree, root: node,
                  available: AvailableSpaceSize(width: .definite(200),
                                                height: .definite(100)))
    #expect(tree.layout(abs).x == 20, "10% of the 200 WIDTH")
    #expect(tree.layout(abs).y == 10, "10% of the 100 HEIGHT — not the width")
}
```

- [ ] **Step 2: Run to verify they fail**

Run: `swift test --no-parallel --filter AbsolutePositioningTests 2>&1 | grep -E "recorded an issue|Test run with"`
Expected: all four fail — insets are not read yet, so every box sits at the containing block's origin.

- [ ] **Step 3: Implement**

In `placeAbsolute`, resolve each edge with the correct basis and apply the three cases per axis. Use the existing `resolveDimension(_:against:rootFontSize:)` (`Resolve.swift:61`), which returns `nil` for `.auto` — that `nil` is how you distinguish "not given" from "given as 0".

```swift
    // **Per-axis bases, and this is NOT CLAUDE.md:997's rule.** That constraint
    // is about `padding` and `border`, where CSS resolves every percentage
    // against the containing block's width. An inset does not: `left`/`right`
    // resolve against width, `top`/`bottom` against height.
    let left = resolveDimension(s.inset.left, against: cb.size.width, rootFontSize: ctx.rootFontSize)
    let right = resolveDimension(s.inset.right, against: cb.size.width, rootFontSize: ctx.rootFontSize)
    let top = resolveDimension(s.inset.top, against: cb.size.height, rootFontSize: ctx.rootFontSize)
    let bottom = resolveDimension(s.inset.bottom, against: cb.size.height, rootFontSize: ctx.rootFontSize)
```

Then per axis: if both insets are non-`nil` and the declared size is `.auto`, the extent is `cb − leading − trailing`; if a size is declared, it wins and the trailing inset is dropped; if only the trailing inset is given, position from the far edge; if neither, use the containing block's origin.

**Verify `ctx.rootFontSize` is the real accessor** — `grep -n "rootFontSize" Sources/MetalUILayout/LayoutContext.swift`.

- [ ] **Step 4: Run the whole suite**

Run: `swift test --no-parallel 2>&1 | grep -E "error:|warning:|Test run with"`
Expected: `Test run with 548 tests in 0 suites passed` (544 + 4). No golden may move.

- [ ] **Step 5: Measure the mutations**

1. Resolve `top`/`bottom` against **width** (the CLAUDE.md rule applied wrongly) → expect the percentage test. **This is the mutation the non-square containing block exists for**; on a square one it reddens nothing.
2. Drop `left` instead of `right` when over-constrained → expect the over-constrained test.
3. Ignore the trailing inset when the size is `auto` → expect the stretch test.

- [ ] **Step 6: Commit**

```bash
git add Sources/MetalUILayout/FlexEngine.swift Tests/MetalUILayoutTests/AbsolutePositioningTests.swift
git commit -m "feat: insets, with CSS's per-axis percentage bases

left/right resolve against the containing block's width, top/bottom
against its height. CLAUDE.md's percentage-inset constraint says width
for everything -- that sentence is about padding and border, and
following it here is wrong on two of four edges. The fixture's
containing block is non-square precisely so the difference is visible."
```

---

### Task 5: Browser fixtures

**Files:**
- Create: `Tests/MetalUILayoutTests/Fixtures/abs_containing_block_skips_static.html`
- Create: `Tests/MetalUILayoutTests/Fixtures/abs_percent_insets_nonsquare.html`
- Create: `Tests/MetalUILayoutTests/Fixtures/abs_removed_from_flow.html`
- Create: `Tests/MetalUILayoutTests/Fixtures/abs_over_constrained.html`
- Create: `Tests/MetalUILayoutTests/AbsoluteFixtureTests.swift`
- Modify: `Tests/MetalUILayoutTests/GeneratorTests.swift` (`allFixtures`)

**Interfaces:**
- Consumes: everything from Tasks 1-4.
- Produces: four goldens.

**The oracle needs no translation here** — `position: absolute` is directly expressible, unlike `Stack`, which had to be oracled through a one-cell grid.

**Each fixture's geometry is its assertion**, per spec §5:

- `abs_containing_block_skips_static` — the absolute box's **parent is `static`** and offset from the containing block. A fixture where the parent *is* the containing block cannot distinguish walking the chain from using the parent.
- `abs_percent_insets_nonsquare` — containing block **200×100**, percentage insets on both axes. Square would make the two bases indistinguishable.
- `abs_removed_from_flow` — the absolute child is **larger than the in-flow content on both axes**, so "removed" and "included but not the maximum" differ.
- `abs_over_constrained` — both insets plus a width, asserting `right` is dropped.

Remember CSS's default is `position: static`, which now matches this engine's default — so a fixture's non-containing-block ancestors need no markup, and the containing block needs `position: relative` explicitly.

- [ ] **Step 1: Write the fixtures**

`abs_containing_block_skips_static.html`:

```html
<!DOCTYPE html>
<html><head><style>
  body { margin: 0; }
  /* The containing block: `relative`, so an absolute descendant resolves here. */
  #root { position: relative; width: 200px; height: 100px; padding: 5px; }
  /* A STATIC wrapper, pushed right by a spacer. The absolute box inside it must
     ignore this and resolve against #root — that is the whole fixture. */
  .wrapper { display: flex; flex-direction: row; }
  .spacer { width: 60px; height: 10px; }
  .abs { position: absolute; left: 0; top: 0; width: 20px; height: 10px; }
</style></head><body>
  <div id="root">
    <div class="wrapper"><div class="spacer"></div><div class="abs"></div></div>
  </div>
</body></html>
```

Write the other three in the same shape, following the geometry above.

- [ ] **Step 2: Register them and generate the goldens**

Add all four to `GeneratorTests.swift`'s `allFixtures` — **a fixture not registered there is never generated**, so the test would compare against an absent golden. Then regenerate per the mechanism `regenerateAllGoldens` documents.

**Expected: all four match on first generation. If any disagrees, STOP and report both numbers** — do not adjust a fixture to match. A disagreement is either a real engine bug or a real CSS misunderstanding, and both are worth more than a green test.

- [ ] **Step 3: Write the fixture tests**

Create `AbsoluteFixtureTests.swift`, hand-building each tree — there is **no CSS parser**; read `Tests/MetalUILayoutTests/StackFixtureTests.swift` for the idiom. State in each test's doc comment what wrong implementation its numbers catch.

- [ ] **Step 4: Run the whole suite**

Run: `swift test --no-parallel 2>&1 | grep -E "error:|warning:|Test run with"`
Expected: `Test run with 552 tests in 0 suites passed`, **80 goldens** — 76 existing unmoved, plus 4.

Verify: `git status --short Tests/MetalUILayoutTests/Golden/` shows four additions and **zero modifications**.

- [ ] **Step 5: Measure the static-position divergence**

Spec §7.1 records that all-`auto` insets place at the containing block's origin rather than CSS's static position. **Measure WebKit's answer** with a throwaway probe — an absolute box with no insets, after an in-flow sibling — record both numbers in the spec's §7, and add a pin naming this engine's answer as deliberate. Delete the probe.

- [ ] **Step 6: Commit**

```bash
git add Tests/MetalUILayoutTests
git commit -m "test: four browser fixtures for absolute positioning

position: absolute is directly expressible, so unlike Stack this needs no
oracle translation. Each fixture's geometry is its assertion: the parent
is static and offset, the containing block is non-square, the absolute
child is larger than the in-flow content, and the over-constrained case
asserts right is the edge dropped."
```

---

### Task 6: `Scene` gains a layer

**Files:**
- Modify: `Sources/MetalUIRender/Scene.swift`
- Test: `Tests/MetalUIRenderTests/DrawListTests.swift`

**Interfaces:**
- Consumes: nothing from Tasks 1-5 — this is the paint half and shares no code with the engine half.
- Produces: `Scene.insert(_:layer:)` and a `(layer, order, sequence)` sort. Task 7's `Deferred` drives it.

**This is CPU-side metadata, not GPU data.** The GPU never reads a layer; it only changes ordering. So the layer rides in a parallel array exactly as `sequence` already does (`Scene.swift:36`), and **there is no ABI change** — no `MetalUIShaderTypes.h` edit, no `abi_probe` extension, no `sizeof` change, and **none of the `swift package clean` hazard** that cost two implementers a bisection on the clipping milestone.

- [ ] **Step 1: Write the failing tests**

```swift
/// A higher layer draws later regardless of `order`.
@Test func aHigherLayerDrawsAfterALowerOneWhateverTheOrder() throws {
    var scene = Scene()
    scene.insert(rect(order: 99), layer: 0)
    scene.insert(rect(order: 0), layer: 1)
    scene.finalize()
    #expect(scene.rects.map(\.order) == [99, 0],
            "layer 1 draws last even though its order is lower")
}

/// Within one layer, `order` still decides — layering does not replace ordering.
@Test func withinOneLayerOrderStillDecides() throws {
    var scene = Scene()
    scene.insert(rect(order: 5), layer: 0)
    scene.insert(rect(order: 1), layer: 0)
    scene.finalize()
    #expect(scene.rects.map(\.order) == [1, 5])
}

/// Equal layer AND equal order still fall back to emission sequence — the
/// tiebreak `finalize` already depends on must survive the new key.
@Test func equalLayerAndOrderKeepEmissionSequenceAcrossTypes() throws {
    var scene = Scene()
    scene.insert(glyph(order: 5), layer: 0)
    scene.insert(rect(order: 5), layer: 0)
    scene.finalize()
    let runs = scene.drawList
    try #require(runs.count == 2)
    #expect(runs[0].kind == .glyph, "emitted first, so drawn first")
}

/// A deferred primitive crosses type boundaries: a layer-1 RECT draws after a
/// layer-0 GLYPH, which the draw list must express as two runs in that order.
@Test func aHigherLayerRectDrawsAfterALowerLayerGlyph() throws {
    var scene = Scene()
    scene.insert(glyph(order: 0), layer: 0)
    scene.insert(rect(order: 0), layer: 1)
    scene.finalize()
    let runs = scene.drawList
    try #require(runs.count == 2)
    #expect(runs[0].kind == .glyph)
    #expect(runs[1].kind == .rect)
}
```

`rect(order:)` and `glyph(order:)` already exist in that file.

- [ ] **Step 2: Run to verify they fail**

Expected: compile failure — `insert` takes no `layer:` argument.

- [ ] **Step 3: Implement**

Give `insert` a `layer: Int = 0` parameter, store it in a parallel dictionary beside `sequence`, and change `finalize()`'s sort key from `($0.0, $0.1)` (`Scene.swift:100`) to `(layer, order, sequence)`. Reset the layer arrays in `clear()` alongside `sequence`.

**The default matters:** `layer: 0` means every existing call site keeps compiling and behaving identically.

- [ ] **Step 4: Run the whole suite**

Expected: `Test run with 556 tests in 0 suites passed` (552 + 4). **No golden may move** — this touches no layout.

- [ ] **Step 5: Measure the mutations**

1. Sort by `(order, layer, sequence)` — the two keys transposed → expect the first two tests.
2. Drop `layer` from the key entirely → expect the layer tests and not the within-layer one.
3. Drop `sequence` from the key → expect the tiebreak test. **That key was load-bearing before this change and must stay so.**

- [ ] **Step 6: Commit**

```bash
git add Sources/MetalUIRender/Scene.swift Tests/MetalUIRenderTests/DrawListTests.swift
git commit -m "feat: Scene sorts by (layer, order, sequence)

Layer is CPU-side sort metadata, not GPU data -- the GPU never reads it
-- so it rides in a parallel array beside the existing sequence
bookkeeping. No ABI change, no abi_probe extension, no swift package
clean hazard.

layer: 0 defaults so every existing call site is unchanged."
```

---

### Task 7: `Deferred`

**Files:**
- Modify: `Sources/MetalUI/Frame.swift` (layer stack, `fill`, `draw`)
- Modify: `Sources/MetalUI/Passes.swift` (`deferred` on both passes)
- Create: `Sources/MetalUI/Deferred.swift`
- Test: `Tests/MetalUITests/DeferredTests.swift` (create)

**Interfaces:**
- Consumes: `Scene.insert(_:layer:)` (Task 6), the clip stack (`Frame.swift:121`).
- Produces: `Deferred` and `pass.deferred { … }`.

**`Deferred` is a portal — it does two things:**

1. Hoists its subtree to the root layer.
2. **Resets the clip stack to the whole surface.**

That second one is what makes a modal inside a `ScrollView` cover the window instead of being clipped to the viewport. Spec §2 and §7.2 record the resulting divergence from CSS, which clips absolutely-positioned descendants whose containing block sits inside the clipper.

**It goes on `PrepaintPass` as well as `PaintPass`**, because spec §4.5 puts hoisting in prepaint and the reason is **hit-testing**: the scroll-region registry is built there, and a tooltip that paints above its siblings while receiving events below them is worse than one that does neither.

`Frame` gains a layer stack shaped exactly like its clip stack (`Frame.swift:121`, `pushClip`/`popClip`/`activeClip`). `fill` and `draw` stamp the active layer the way they already stamp the active clip.

- [ ] **Step 1: Write the failing tests**

Write tests asserting: a `Deferred` subtree's primitives carry a higher layer than their siblings'; a `Deferred` subtree inside a `clipped(to:)` block carries the **whole-surface** mask rather than the clip's; the layer and clip both **pop** when the block returns; and `Deferred` on `PrepaintPass` does not gain the ability to emit primitives.

**Write these bodies out in full when implementing**, reading `Tests/MetalUITests/ClipStackTests.swift` for the `Frame`-construction idiom. For each, state what wrong implementation it catches.

- [ ] **Step 2: Run to verify they fail**

Expected: `value of type 'PaintPass' has no member 'deferred'`.

- [ ] **Step 3: Implement**

`Frame` gains `private var layerStack: [Int]` with `activeLayer`, `pushLayer`/`popLayer`. `deferred` on both passes pushes the root layer **and** a whole-surface clip, balanced by `defer` so an unbalanced stack is not expressible. `Deferred` is a one-child element wrapping its content in `pass.deferred { … }` in both `prepaint` and `paint`.

- [ ] **Step 4: Run the whole suite**

Expected: 556 + your test count. **No golden may move.**

- [ ] **Step 5: Measure the mutations**

1. `deferred` hoists the layer but does **not** reset the clip → expect the clip-escape test. **This is the mutation that distinguishes a portal from a plain layer hoist.**
2. `deferred` omits its `defer { popLayer() }` → expect the pop test.
3. `deferred` is absent from `PrepaintPass` → expect a compile failure in the prepaint test, which is the guard that hit-testing order is covered.

- [ ] **Step 6: Commit**

```bash
git add Sources/MetalUI Tests/MetalUITests/DeferredTests.swift
git commit -m "feat: Deferred hoists to the root layer and escapes clipping

A portal: one rule rather than a walk up the ancestor chain. A modal
inside a ScrollView covers the window instead of being clipped to the
viewport. On both passes, because hoisting affects hit-test order and
the registry is built in prepaint."
```

---

### Task 8: Demo, documentation, human verification

**Files:**
- Modify: `Sources/MetalUIDemo/main.swift`, `CLAUDE.md`
- Create: `docs/superpowers/2026-08-28-absolute-positioning-decisions.md`

- [ ] **Step 1: Put a modal in the demo**

A `Deferred` containing an absolutely-positioned panel, **inside the `ScrollView`** so the clip escape is visible, with a scrim behind it. It must be plainly wrong if either mechanism fails: clipped to the viewport if the portal does not reset the clip, or behind the rows if the layer does not hoist.

- [ ] **Step 2: Verify the build and smoke-run**

```bash
swift package clean && swift build 2>&1 | grep -cE "error:|warning:"   # expect 0
swift run MetalUIDemo   # confirm it launches; this is NOT the look
```

- [ ] **Step 3: CLAUDE.md — four things**

1. **Delete the `position`, `inset` row from the declared-but-inert table.** Both are live. That table then has two rows fewer than it has had since M0.
2. **Narrow the percentage-inset constraint at `CLAUDE.md:997`** to name `padding` and `border` explicitly, and say that `Style.inset` resolves `top`/`bottom` against **height**. That sentence's current wording is a trap this plan had to route around.
3. **Re-count** `grep -cE "^    public var " Sources/MetalUILayout/Style.swift` and state what it returns.
4. Add `Deferred` to the containers/elements described, and record the clip-escape divergence.

- [ ] **Step 4: Write the decisions doc**

`docs/superpowers/2026-08-28-absolute-positioning-decisions.md`, rulings prefixed **`AP-`** and **lettered** (`AP-A`, `AP-B`, …) so a bare `AP-3` is a typo rather than a citation. At minimum: `.static` as the default and why a two-case enum could not work; threading the containing block downward rather than adding a parent pointer; the per-axis percentage bases and the constraint that misleads; cutting static position; and `Deferred` as a portal.

- [ ] **Step 5: Re-measure everything the docs claim**

```bash
swift package clean && swift test --no-parallel 2>&1 | grep "Test run with"
ls Tests/MetalUILayoutTests/Golden/*.json | wc -l
grep -cE "^    public var " Sources/MetalUILayout/Style.swift
```

- [ ] **Step 6: Human verification**

Ask the user to run `swift run MetalUIDemo` and report: whether the modal covers the window rather than being clipped to the scroll viewport, whether it paints above the rows, and whether the scrim sits behind it but above everything else.

**Record what the look could NOT establish**, as the M2, clipping-and-scroll and Stack entries do. Both properties here — layer order and clip escape — produce identical rects under inversion, so no positional assertion can see either.

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "docs: record the absolute-positioning milestone

Demo has a modal escaping the ScrollView's clip; CLAUDE.md loses the
position/inset inert row and gains a narrowed percentage constraint;
AP- decisions doc."
```

---

## Self-Review

**Spec coverage.** §1's six in-scope items → Tasks 1, 2, 3, 4, 6, 7. §3.1 → Task 1. §3.2 → Task 2. §3.3 → Task 3. §3.4 → Task 4. §3.5 → Task 4 plus Task 5's divergence measurement. §4.1 → Task 6. §4.2 → Task 7. §5 → Task 5. §6 → Task 8. §7's two divergences → Task 5 Step 5 and Task 7.

**One gap found and closed:** §5 requires a fixture proving removal from flow, which the engine-half tasks only cover with unit tests; `abs_removed_from_flow.html` is that fixture.

**Placeholder scan.** Task 7's four test bodies are named with their assertions stated but not written, because they depend on `ClipStackTests`' `Frame`-construction idiom, which the implementer reads. Every one says what it must assert. Task 5's three remaining fixtures are described by geometry rather than transcribed, since the first is given in full and the shape is mechanical.

**Type consistency.** `ContainingBlock { origin, size }` (Task 3) is consumed unchanged in Task 4. `placeAbsolute`'s signature matches between its definition and its call site. `Scene.insert(_:layer:)` (Task 6) is what Task 7's `fill`/`draw` drive. `Position`'s three cases are the same in Tasks 1, 2 and 3.

**Test-count arithmetic is cumulative and will drift** if a task adds a case this plan did not anticipate. Every task reads the summary line; the predicted number is a check, not a gate.
