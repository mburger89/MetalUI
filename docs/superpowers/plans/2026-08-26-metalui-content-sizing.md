# Content Sizing Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give the layout engine a way for a subtree to report its own size, so an `auto` size measures content instead of resolving to 0.

**Architecture:** Split `layoutContainer` into a pure, cacheable `measureNode` and a layout-writing `placeNode` over shared internals, threaded through a per-run `LayoutContext` class holding the memo cache. Containers and leaves then answer the same question, so the four sites that today return a constant take one call.

**Tech Stack:** Swift 6.3, `swiftLanguageModes: [.v6]`, strict concurrency, Swift Testing. No third-party dependencies. WebKit (`WKWebView`) as the golden-file oracle.

**Spec:** `docs/superpowers/specs/2026-08-26-content-sizing-design.md`

## Global Constraints

- `swift build` and `swift test` must be **warning-free**. Warnings are defects to fix, never suppress.
- No third-party dependencies. No `.unsafeFlags`.
- **`MetalUILayout` must import only `MetalUICore`.** Verify with an *anchored* pattern — an unanchored `Metal` also matches the legitimate `import MetalUICore`.
- **Goldens are browser-generated, never hand-edited.** Regenerate with `METALUI_REGENERATE_GOLDENS=1 swift test --filter regenerateAllGoldens`.
- Pixel format is `bgra8Unorm`, never `_sRGB`.
- Use `swift package clean`, **never** `rm -rf .build`.
- **Mutation hygiene:** commit before mutating. `cp` a file aside and `cp` it back — `git checkout` restores nothing on an untracked file and discards *all* uncommitted work on a tracked one.
- **Suite integrity (taxonomy shape 11):** after every full run read the **summary line and test count**, never the exit status alone. A run that exits 0 with no summary line has silently skipped tests.
- Every "cannot happen" / "unreachable" comment names a **mechanism**, not a milestone.
- Read `docs/practices/verifying-tests-can-fail.md` before writing tests. It is the review standard.

---

### Task 1: `LayoutContext`, the mutation guard, and the cycle guard

**Files:**
- Create: `Sources/MetalUILayout/LayoutContext.swift`
- Modify: `Sources/MetalUILayout/LayoutTree.swift` (add `isLayingOut`, guard `setStyle`)
- Modify: `Sources/MetalUILayout/FlexEngine.swift:61-92` (`computeLayout` creates the context)
- Test: `Tests/MetalUILayoutTests/LayoutContextTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces: `final class LayoutContext` with `let rootFontSize: Double`, `func enter(_ node: LayoutNodeID)`, `func leave()`; `LayoutTree.isLayingOut: Bool` (internal, private(set)); `LayoutTree.beginLayout()` / `endLayout()`.

This task adds the scaffolding and its guards, and changes **no layout behaviour**. All existing tests must stay green and no golden may move.

- [ ] **Step 1: Write the failing tests**

```swift
import Testing
import MetalUICore
@testable import MetalUILayout

@Test func aStyleWrittenDuringLayoutTraps() async {
    await #expect(processExitsWith: .failure) {
        let tree = LayoutTree(generation: 0)
        var style = Style()
        style.size = Size(width: .length(.pixels(Pixels(10))),
                          height: .length(.pixels(Pixels(10))))
        let node = tree.newNode(style: style, children: [])
        tree.beginLayout()
        tree.setStyle(node, style)   // traps: layout is in progress
    }
}

/// The positive control. Without it the test above passes when `setStyle`
/// traps unconditionally.
@Test func aStyleWrittenOutsideLayoutDoesNotTrap() {
    let tree = LayoutTree(generation: 0)
    let node = tree.newNode(style: Style(), children: [])
    var style = Style()
    style.flexGrow = 1
    tree.setStyle(node, style)
    #expect(tree.style(node).flexGrow == 1)
}

/// `endLayout` must clear the flag, or the first layout poisons the tree for
/// every later caller.
@Test func layoutClearsTheGuardWhenItFinishes() {
    let tree = LayoutTree(generation: 0)
    let node = tree.newNode(style: Style(), children: [])
    computeLayout(tree, root: node,
                  available: AvailableSpaceSize(width: .definite(100),
                                                height: .definite(100)))
    #expect(tree.isLayingOut == false)
    tree.setStyle(node, Style())   // must not trap
}

@Test func aCycleInTheChildListTrapsRatherThanHanging() async {
    await #expect(processExitsWith: .failure) {
        let ctx = LayoutContext(rootFontSize: 16)
        let fake = LayoutNodeID(generation: 0, index: 0)
        for _ in 0...LayoutContext.maxDepth { ctx.enter(fake) }
    }
}

@Test func nestingBelowTheDepthLimitDoesNotTrap() {
    let ctx = LayoutContext(rootFontSize: 16)
    let fake = LayoutNodeID(generation: 0, index: 0)
    for _ in 0..<LayoutContext.maxDepth { ctx.enter(fake) }
    for _ in 0..<LayoutContext.maxDepth { ctx.leave() }
    #expect(ctx.depth == 0)
}
```

- [ ] **Step 2: Run them and confirm they fail**

Run: `swift test --filter LayoutContextTests`
Expected: FAIL — `LayoutContext` does not exist, `beginLayout` does not exist.

- [ ] **Step 3: Create `LayoutContext`**

```swift
/// Per-run layout state: the memo cache (Task 3) and the values every level of
/// the recursion needs.
///
/// **A `final class`, not a `struct`, and that is load-bearing.** A struct
/// threaded by value gives every recursion level its own copy of the cache, so
/// nothing is ever shared, every lookup misses, and the engine stays *correct*
/// while doing exponential work. The only guard that can see that failure is
/// `theCacheIsActuallyConsulted` in Task 3.
///
/// It is created in `computeLayout` and dies with it. It deliberately does not
/// live on `LayoutTree`: the tree is storage, and a cache outliving a run is the
/// stale-data shape ruling C-3 spent a milestone closing.
final class LayoutContext {
    let rootFontSize: Double

    /// How deep the recursion currently is. `LayoutTree.newNode` accepts
    /// arbitrary child ids, so a cycle is constructible and would otherwise
    /// recurse until the stack dies with no attribution.
    private(set) var depth: Int = 0

    /// Deeper than any real UI and shallower than the stack can take. A tree
    /// legitimately this deep is a bug in the caller, not a limit worth raising.
    static let maxDepth = 256

    init(rootFontSize: Double) {
        self.rootFontSize = rootFontSize
    }

    func enter(_ node: LayoutNodeID) {
        depth += 1
        precondition(depth <= LayoutContext.maxDepth,
                     "layout recursion exceeded \(LayoutContext.maxDepth) levels at node \(node) — the child lists contain a cycle")
    }

    func leave() {
        depth -= 1
    }
}
```

- [ ] **Step 4: Add the mutation guard to `LayoutTree`**

In `Sources/MetalUILayout/LayoutTree.swift`, add the flag and guard `setStyle`:

```swift
    /// True while `computeLayout` is running over this tree.
    ///
    /// Task 3 memoizes `measureNode` on the assumption that styles do not change
    /// during a run. Nothing enforced that before this flag, and a style written
    /// mid-layout would hand back a cached size computed for the *old* style —
    /// a wrong answer no fixture could catch, because the fixture and the golden
    /// would both be generated from the settled tree.
    ///
    /// The flag lives here rather than on `LayoutContext` because `setStyle` is a
    /// tree method and has no context in hand.
    public private(set) var isLayingOut = false

    func beginLayout() {
        precondition(!isLayingOut, "computeLayout re-entered on the same tree")
        isLayingOut = true
    }

    func endLayout() { isLayingOut = false }
```

and change `setStyle` to:

```swift
    public func setStyle(_ id: LayoutNodeID, _ s: Style) {
        precondition(!isLayingOut,
                     "setStyle called while computeLayout is running — measured sizes are memoized against the styles this would change")
        styles[slot(id)] = s
    }
```

- [ ] **Step 5: Have `computeLayout` create the context and bracket the run**

In `FlexEngine.swift`, replace `computeLayout`'s body so it builds a context and brackets the run. `defer` is required: an early return or a trap inside layout must not leave the tree permanently poisoned.

```swift
public func computeLayout(
    _ tree: LayoutTree,
    root: LayoutNodeID,
    available: AvailableSpaceSize,
    rootFontSize: Double = 16
) {
    let ctx = LayoutContext(rootFontSize: rootFontSize)
    tree.beginLayout()
    defer { tree.endLayout() }

    let rootSize = resolveRootSize(tree, root, available: available, rootFontSize: ctx.rootFontSize)
    // The remaining ~25 lines of today's body are unchanged and are NOT retyped
    // here: keep `tree.setLayout(root, …)`, the `rootContainingBlockWidth`
    // computation with its FS-1 comment, the `layoutContainer` call, and
    // `roundStoredRects`, substituting `ctx.rootFontSize` for `rootFontSize`.
}
```

Leave every other signature alone in this task. Threading `ctx` through the recursion happens in Task 2, where the split gives it somewhere to go.

- [ ] **Step 6: Run the tests**

Run: `swift test --filter LayoutContextTests`
Expected: PASS, 5 tests.

- [ ] **Step 7: Run the whole suite and read the summary line**

Run: `swift test`
Expected: `Test run with 309 tests in 0 suites passed` (304 + 5). **No golden may move** — confirm with `git status --short Tests/MetalUILayoutTests/Golden`, which must be empty.

- [ ] **Step 8: Prove the guards**

```bash
# 1. Delete the `precondition` in `setStyle`.
#    Expect: `aStyleWrittenDuringLayoutTraps` reddens, and nothing else.
# 2. Delete `defer { tree.endLayout() }`.
#    Expect: `layoutClearsTheGuardWhenItFinishes` reddens.
# 3. Delete the `precondition` in `enter`.
#    Expect: `aCycleInTheChildListTrapsRatherThanHanging` reddens.
# Restore each with `cp`, never `git checkout`.
```

Record the measured red counts in the report — not the predicted ones.

- [ ] **Step 9: Commit**

```bash
git add Sources/MetalUILayout/LayoutContext.swift Sources/MetalUILayout/LayoutTree.swift Sources/MetalUILayout/FlexEngine.swift Tests/MetalUILayoutTests/LayoutContextTests.swift
git commit -m "feat(layout): add LayoutContext with cycle and style-mutation guards"
```

---

### Task 2: Split `layoutContainer` into `measureNode` and `placeNode`

**Files:**
- Modify: `Sources/MetalUILayout/FlexEngine.swift:400-566` (`layoutContainer`), `:940-966` (the recursion), `:568` (`collectItems` signature)
- Test: `Tests/MetalUILayoutTests/MeasureNodeTests.swift`

**Interfaces:**
- Consumes: `LayoutContext` from Task 1.
- Produces:
  ```swift
  func measureNode(_ ctx: LayoutContext, _ tree: LayoutTree, _ node: LayoutNodeID,
                   known: OptionalSizeD, available: AvailableSpaceSize,
                   containingBlockWidth: Double?) -> SizeD
  func placeNode(_ ctx: LayoutContext, _ tree: LayoutTree, _ node: LayoutNodeID,
                 origin: (Double, Double), size: SizeD,
                 containingBlockWidth: Double?)
  ```
  `measureNode` returns the node's **border box** and never writes layout.

**This task is behaviour-preserving.** Nothing calls `measureNode` yet except its own tests. Every existing test stays green and **no golden moves** — that is the review gate. Wiring the call sites is Task 4.

- [ ] **Step 1: Write the failing tests**

```swift
import Testing
import MetalUICore
@testable import MetalUILayout

private func px(_ v: Double) -> Dimension { .length(.pixels(Pixels(Float(v)))) }

/// A container reports the size its own children imply, with no layout written.
@Test func measuringARowContainerReturnsItsContentSize() {
    let tree = LayoutTree(generation: 0)
    var kid = Style()
    kid.size = Size(width: px(60), height: px(20))
    let a = tree.newNode(style: kid, children: [])
    let b = tree.newNode(style: kid, children: [])

    var row = Style()
    row.flexDirection = .row
    let container = tree.newNode(style: row, children: [a, b])

    let ctx = LayoutContext(rootFontSize: 16)
    let size = measureNode(ctx, tree, container,
                           known: .unspecified,
                           available: AvailableSpaceSize(width: .maxContent,
                                                         height: .maxContent),
                           containingBlockWidth: nil)
    #expect(size.width == 120)
    #expect(size.height == 20)
}

/// **The purity guard.** A `measureNode` that called `setLayout` would return
/// the correct size and pass every golden in the corpus; this is the only thing
/// that can see it. Asserts on the stored rects of *every* node, not just the
/// container's, because the recursion writes children first.
@Test func measuringWritesNoLayout() {
    let tree = LayoutTree(generation: 0)
    var kid = Style()
    kid.size = Size(width: px(60), height: px(20))
    let a = tree.newNode(style: kid, children: [])
    var row = Style()
    row.flexDirection = .row
    let container = tree.newNode(style: row, children: [a])

    let sentinel = LayoutRect(x: -1, y: -2, width: -3, height: -4)
    tree.setLayout(a, sentinel)
    tree.setLayout(container, sentinel)

    let ctx = LayoutContext(rootFontSize: 16)
    _ = measureNode(ctx, tree, container, known: .unspecified,
                    available: AvailableSpaceSize(width: .maxContent, height: .maxContent),
                    containingBlockWidth: nil)

    #expect(tree.layout(a) == sentinel)
    #expect(tree.layout(container) == sentinel)
}

/// A known size wins over the measured one — the `known` half of §5.5's contract.
@Test func aKnownSizeOverridesTheMeasuredOne() {
    let tree = LayoutTree(generation: 0)
    var kid = Style()
    kid.size = Size(width: px(60), height: px(20))
    let a = tree.newNode(style: kid, children: [])
    var row = Style()
    row.flexDirection = .row
    let container = tree.newNode(style: row, children: [a])

    let ctx = LayoutContext(rootFontSize: 16)
    let size = measureNode(ctx, tree, container,
                           known: OptionalSizeD(width: 200, height: nil),
                           available: AvailableSpaceSize(width: .definite(200),
                                                         height: .maxContent),
                           containingBlockWidth: nil)
    #expect(size.width == 200)
    #expect(size.height == 20)
}

/// A leaf with a measure function answers from it, so callers cannot tell a
/// leaf from a container. `newLeaf` has no production caller — this builds one.
@Test func measuringALeafUsesItsMeasureFunction() {
    let tree = LayoutTree(generation: 0)
    let leaf = tree.newLeaf(style: Style()) { _, available in
        if case .minContent = available.width { return SizeD(width: 30, height: 40) }
        return SizeD(width: 90, height: 20)
    }
    let ctx = LayoutContext(rootFontSize: 16)
    let wide = measureNode(ctx, tree, leaf, known: .unspecified,
                           available: AvailableSpaceSize(width: .maxContent, height: .maxContent),
                           containingBlockWidth: nil)
    let narrow = measureNode(ctx, tree, leaf, known: .unspecified,
                             available: AvailableSpaceSize(width: .minContent, height: .maxContent),
                             containingBlockWidth: nil)
    #expect(wide == SizeD(width: 90, height: 20))
    #expect(narrow == SizeD(width: 30, height: 40))
}

/// A container with no children measures 0, not a trap. `layoutContainer`'s
/// `guard !items.isEmpty else { return }` becomes a returned size here.
@Test func measuringAnEmptyContainerIsZeroNotATrap() {
    let tree = LayoutTree(generation: 0)
    let container = tree.newNode(style: Style(), children: [])
    let ctx = LayoutContext(rootFontSize: 16)
    let size = measureNode(ctx, tree, container, known: .unspecified,
                           available: AvailableSpaceSize(width: .maxContent, height: .maxContent),
                           containingBlockWidth: nil)
    #expect(size == SizeD.zero)
}
```

- [ ] **Step 2: Run them and confirm they fail**

Run: `swift test --filter MeasureNodeTests`
Expected: FAIL — `measureNode` does not exist.

- [ ] **Step 3: Extract the shared body**

Refactor `layoutContainer` (`FlexEngine.swift:400`) so its sizing work is reachable without its writing work. The existing body already separates cleanly: everything from `contentBox` through the `positionItems` call is sizing; `positionItems` and the recursion at `:960` are placement.

Introduce a private function holding the sizing half and returning what both callers need:

```swift
/// The result of running §9.2–§9.7 over a container's children, before anything
/// is positioned. `placeNode` goes on to position from it; `measureNode` reads
/// only `contentSize` and discards the rest.
private struct ContainerLayout {
    var lines: [FlexLine]
    /// The container's resolved CONTENT box — what the items actually occupy.
    var contentSize: SizeD
    var box: (origin: (Double, Double), size: SizeD)
}

private func layOutChildren(
    _ ctx: LayoutContext, _ tree: LayoutTree, _ container: LayoutNodeID,
    containerSize: SizeD, containingBlockWidth: Double?
) -> ContainerLayout?
```

Move the body of today's `layoutContainer` from the `contentBox` call down to (but not including) `positionItems` into `layOutChildren`, returning `nil` where today's code does `guard !items.isEmpty else { return }`.

- [ ] **Step 4: Write `placeNode` in terms of it**

```swift
func placeNode(_ ctx: LayoutContext, _ tree: LayoutTree, _ node: LayoutNodeID,
               origin: (Double, Double), size: SizeD,
               containingBlockWidth: Double?) {
    ctx.enter(node)
    defer { ctx.leave() }

    guard let laid = layOutChildren(ctx, tree, node, containerSize: size,
                                    containingBlockWidth: containingBlockWidth)
    else { return }

    // `positionItems` is called with exactly today's arguments, now read off
    // `laid` instead of recomputed: `laid.lines`, `laid.box.origin` as the child
    // origin, and `laid.box.size` as the container's content box. Its body does
    // not change in this task.
    positionItems(ctx, tree, node, lines: laid.lines,
                  childOrigin: laid.box.origin, contentSize: laid.box.size)
}
```

The recursion at `FlexEngine.swift:960` becomes `placeNode(ctx, tree, item.node, origin: (x, y), size: size, containingBlockWidth: containerSize.width)`.

- [ ] **Step 5: Write `measureNode`**

```swift
/// The size `node` reports for itself, **without writing any layout**.
///
/// A leaf answers from its `MeasureFunction`; a container answers by running the
/// flex algorithm over its children and returning the border box that implies.
/// Callers cannot tell which happened, which is the whole point: the four sites
/// that used to substitute a constant for a container's content size now make
/// one call that works for both.
///
/// **Purity is not enforced by the type system.** A `setLayout` added anywhere
/// below this function would return the right size and pass every golden;
/// `measuringWritesNoLayout` is the guard.
func measureNode(_ ctx: LayoutContext, _ tree: LayoutTree, _ node: LayoutNodeID,
                 known: OptionalSizeD, available: AvailableSpaceSize,
                 containingBlockWidth: Double?) -> SizeD {
    ctx.enter(node)
    defer { ctx.leave() }

    if let measure = tree.measure(node) {
        return measure(known, available)
    }

    // A container: run the algorithm and report what the children imply,
    // letting a known size on either axis win over the measured one.
    let probe = SizeD(width: known.width ?? availableExtent(available.width),
                      height: known.height ?? availableExtent(available.height))
    guard let laid = layOutChildren(ctx, tree, node, containerSize: probe,
                                    containingBlockWidth: containingBlockWidth)
    else { return SizeD(width: known.width ?? 0, height: known.height ?? 0) }

    return SizeD(width: known.width ?? laid.contentSize.width,
                 height: known.height ?? laid.contentSize.height)
}

/// `.minContent` and `.maxContent` carry no number; a probe under them uses an
/// unbounded extent and lets the children's own sizes decide.
private func availableExtent(_ a: AvailableSpace) -> Double {
    if case .definite(let v) = a { return v }
    return .infinity
}
```

- [ ] **Step 6: Run the new tests**

Run: `swift test --filter MeasureNodeTests`
Expected: PASS, 5 tests.

- [ ] **Step 7: Run the whole suite — this is the gate**

Run: `swift test`
Expected: `Test run with 314 tests in 0 suites passed` (309 + 5). **`git status --short Tests/MetalUILayoutTests/Golden` must be empty.** A moved golden here means the refactor changed behaviour and is a defect, not a discovery — Task 4 is where behaviour changes.

- [ ] **Step 8: Prove the split**

```bash
# 1. Make `measureNode` call `tree.setLayout(node, LayoutRect(x: 0, y: 0,
#    width: 1, height: 1))` before returning.
#    Expect: `measuringWritesNoLayout` reddens and NOTHING ELSE does — which is
#    the finding, not the failure. Record how many tests redden.
# 2. Make `measureNode` ignore `known` and always return the measured size.
#    Expect: `aKnownSizeOverridesTheMeasuredOne` reddens.
# 3. Make `measureNode` ignore the leaf branch and fall through to the container
#    path.
#    Expect: `measuringALeafUsesItsMeasureFunction` reddens.
```

- [ ] **Step 9: Commit**

```bash
git add Sources/MetalUILayout/FlexEngine.swift Tests/MetalUILayoutTests/MeasureNodeTests.swift
git commit -m "refactor(layout): split layoutContainer into measureNode and placeNode"
```

---

### Task 3: The memo cache

**Files:**
- Modify: `Sources/MetalUILayout/LayoutContext.swift`
- Modify: `Sources/MetalUILayout/FlexEngine.swift` (`measureNode` consults the cache)
- Test: `Tests/MetalUILayoutTests/MeasureCacheTests.swift`

**Interfaces:**
- Consumes: `LayoutContext`, `measureNode` from Tasks 1-2.
- Produces: `LayoutContext.cachedMeasure(_:_:) -> SizeD?`, `LayoutContext.storeMeasure(_:_:_:)`, `LayoutContext.hits: Int`, `LayoutContext.misses: Int`.

Memoization here is a correctness-of-cost requirement, not an optimisation: each level issues three queries per child (min-content, max-content, real layout), so work multiplies with depth — roughly 700× at depth 6.

- [ ] **Step 1: Write the failing tests**

```swift
import Testing
import MetalUICore
@testable import MetalUILayout

private func px(_ v: Double) -> Dimension { .length(.pixels(Pixels(Float(v)))) }

private func nestedTree() -> (LayoutTree, LayoutNodeID) {
    let tree = LayoutTree(generation: 0)
    var kid = Style()
    kid.size = Size(width: px(30), height: px(10))
    var row = Style()
    row.flexDirection = .row
    var node = tree.newNode(style: kid, children: [])
    for _ in 0..<4 {
        node = tree.newNode(style: row, children: [node, tree.newNode(style: kid, children: [])])
    }
    return (tree, node)
}

/// **The only test that can see whether the cache is a cache.** A `storeMeasure`
/// that never stores, or a `cachedMeasure` that always returns nil, leaves every
/// other test in this repo green and the engine exponentially slow.
@Test func theCacheIsActuallyConsulted() {
    let (tree, root) = nestedTree()
    let ctx = LayoutContext(rootFontSize: 16)
    let q = AvailableSpaceSize(width: .maxContent, height: .maxContent)
    _ = measureNode(ctx, tree, root, known: .unspecified, available: q, containingBlockWidth: nil)
    let firstMisses = ctx.misses
    _ = measureNode(ctx, tree, root, known: .unspecified, available: q, containingBlockWidth: nil)

    #expect(ctx.hits > 0)
    // The second identical query must add no misses at all.
    #expect(ctx.misses == firstMisses)
}

/// A cached answer must equal the uncached one. Guards a key that collides.
@Test func aCachedAnswerMatchesAFreshOne() {
    let (tree, root) = nestedTree()
    let q = AvailableSpaceSize(width: .maxContent, height: .maxContent)
    let warm = LayoutContext(rootFontSize: 16)
    _ = measureNode(warm, tree, root, known: .unspecified, available: q, containingBlockWidth: nil)
    let second = measureNode(warm, tree, root, known: .unspecified, available: q, containingBlockWidth: nil)

    let cold = LayoutContext(rootFontSize: 16)
    let fresh = measureNode(cold, tree, root, known: .unspecified, available: q, containingBlockWidth: nil)
    #expect(second == fresh)
}

/// Different queries must not share an entry. A key that ignored `available`
/// would pass every other test here.
@Test func minContentAndMaxContentDoNotShareACacheEntry() {
    let tree = LayoutTree(generation: 0)
    let leaf = tree.newLeaf(style: Style()) { _, available in
        if case .minContent = available.width { return SizeD(width: 30, height: 40) }
        return SizeD(width: 90, height: 20)
    }
    var row = Style()
    row.flexDirection = .row
    let container = tree.newNode(style: row, children: [leaf])

    let ctx = LayoutContext(rootFontSize: 16)
    let narrow = measureNode(ctx, tree, container, known: .unspecified,
                             available: AvailableSpaceSize(width: .minContent, height: .maxContent),
                             containingBlockWidth: nil)
    let wide = measureNode(ctx, tree, container, known: .unspecified,
                           available: AvailableSpaceSize(width: .maxContent, height: .maxContent),
                           containingBlockWidth: nil)
    #expect(narrow.width == 30)
    #expect(wide.width == 90)
}

/// A new run starts cold. The cache must not outlive its `LayoutContext` —
/// the stale-data shape ruling C-3 closed for `LayoutNodeID`.
@Test func eachRunStartsWithAnEmptyCache() {
    let (tree, root) = nestedTree()
    let q = AvailableSpaceSize(width: .maxContent, height: .maxContent)
    let first = LayoutContext(rootFontSize: 16)
    _ = measureNode(first, tree, root, known: .unspecified, available: q, containingBlockWidth: nil)
    let second = LayoutContext(rootFontSize: 16)
    #expect(second.hits == 0)
    #expect(second.misses == 0)
    _ = measureNode(second, tree, root, known: .unspecified, available: q, containingBlockWidth: nil)
    #expect(second.misses > 0)
}
```

- [ ] **Step 2: Run them and confirm they fail**

Run: `swift test --filter MeasureCacheTests`
Expected: FAIL — `hits` and `misses` do not exist.

- [ ] **Step 3: Add the cache to `LayoutContext`**

```swift
    /// A measurement query. `Double`s are hashed by `bitPattern` so the key is
    /// deterministic: a near-miss on floating-point equality costs a recompute
    /// and never a wrong answer, which is the right direction for this to fail.
    struct MeasureKey: Hashable {
        var node: LayoutNodeID
        var knownWidth: Double?
        var knownHeight: Double?
        var availableWidth: AvailableSpace
        var availableHeight: AvailableSpace

        static func == (l: MeasureKey, r: MeasureKey) -> Bool {
            l.node == r.node
                && l.knownWidth?.bitPattern == r.knownWidth?.bitPattern
                && l.knownHeight?.bitPattern == r.knownHeight?.bitPattern
                && l.availableWidth == r.availableWidth
                && l.availableHeight == r.availableHeight
        }

        func hash(into hasher: inout Hasher) {
            hasher.combine(node)
            hasher.combine(knownWidth?.bitPattern)
            hasher.combine(knownHeight?.bitPattern)
            hasher.combine(availableWidth)
            hasher.combine(availableHeight)
        }
    }

    private var memo: [MeasureKey: SizeD] = [:]

    /// Cache observability. **Test-only in intent and the only way to see that
    /// the cache is a cache** — a `storeMeasure` that never stores leaves every
    /// behavioural test green. Pinned by `theCacheIsActuallyConsulted`.
    private(set) var hits = 0
    private(set) var misses = 0

    func cachedMeasure(_ key: MeasureKey) -> SizeD? {
        if let v = memo[key] { hits += 1; return v }
        misses += 1
        return nil
    }

    func storeMeasure(_ key: MeasureKey, _ size: SizeD) { memo[key] = size }
```

`AvailableSpace` must be `Hashable`; it is already `Equatable` and `Sendable` in `MeasureFunction.swift`, so add `Hashable` to its conformance list.

- [ ] **Step 4: Consult the cache in `measureNode`**

Wrap the body added in Task 2:

```swift
    let key = LayoutContext.MeasureKey(
        node: node, knownWidth: known.width, knownHeight: known.height,
        availableWidth: available.width, availableHeight: available.height)
    if let hit = ctx.cachedMeasure(key) { return hit }
    // ... existing body, into `let result` ...
    ctx.storeMeasure(key, result)
    return result
```

- [ ] **Step 5: Run the new tests**

Run: `swift test --filter MeasureCacheTests`
Expected: PASS, 4 tests.

- [ ] **Step 6: Run the whole suite**

Run: `swift test`
Expected: `Test run with 318 tests in 0 suites passed`. Goldens unmoved.

- [ ] **Step 7: Prove the cache**

```bash
# 1. Make `storeMeasure` a no-op.
#    Expect: `theCacheIsActuallyConsulted` reddens. Record whether ANYTHING
#    ELSE does — if nothing else reddens, that is the finding this test exists
#    for, and it belongs in the report.
# 2. Drop `availableWidth`/`availableHeight` from `MeasureKey`'s == and hash.
#    Expect: `minContentAndMaxContentDoNotShareACacheEntry` reddens.
# 3. Make `memo` a `static var` on LayoutContext (shared across runs).
#    Expect: `eachRunStartsWithAnEmptyCache` reddens.
```

- [ ] **Step 8: Commit**

```bash
git add Sources/MetalUILayout/LayoutContext.swift Sources/MetalUILayout/MeasureFunction.swift Sources/MetalUILayout/FlexEngine.swift Tests/MetalUILayoutTests/MeasureCacheTests.swift
git commit -m "feat(layout): memoize measureNode per run"
```

---

### Task 4: Wire the four call sites and re-baseline the corpus

**Files:**
- Modify: `Sources/MetalUILayout/FlexBaseSize.swift:43`
- Modify: `Sources/MetalUILayout/FlexEngine.swift:622` (§4.5 automatic minimum), `:463` and `collectItems`' cross-size branch (auto cross), `resolveRootSize` (auto axis)
- Modify: `Tests/MetalUILayoutTests/Golden/*.json` (regenerated, never hand-edited)
- Create: `docs/superpowers/2026-08-26-content-sizing-decisions.md`

**Interfaces:**
- Consumes: `measureNode` from Tasks 2-3.
- Produces: content sizing live. No new public API.

**This is the task where behaviour changes and goldens move.** The golden diff is the review artifact.

The largest consequence is not the auto-cross fix it is named for: **`min-width: auto` becomes live for containers.** That is CSS's default on every flex item, today floorless because the content suggestion returns `nil`. After this, items stop shrinking below their content.

- [ ] **Step 1: Wire the four sites**

Replace each constant with a `measureNode` call:

```swift
// FlexBaseSize.swift:43 — §9.2 content branch. Was: `else { return 0 }`.
let measured = measureNode(ctx, tree, item, known: .unspecified,
                           available: AvailableSpaceSize(width: .maxContent, height: .maxContent),
                           containingBlockWidth: containerMain)
return isRow ? measured.width : measured.height
```

```swift
// FlexEngine.swift:622 — CSS Sizing §4.5 content suggestion. Was: `else { return nil }`.
let probe = measureNode(ctx, tree, kid, known: .unspecified,
                        available: AvailableSpaceSize(width: .minContent, height: .minContent),
                        containingBlockWidth: containerSize.width)
```

```swift
// collectItems — an `auto` cross size. Was: 0.
// Main axis known, cross axis measured: that is what §9.4.8 asks for.
let crossKnown = isRow ? OptionalSizeD(width: base, height: nil)
                       : OptionalSizeD(width: nil, height: base)
let measured = measureNode(ctx, tree, kid, known: crossKnown,
                           available: AvailableSpaceSize(width: .maxContent, height: .maxContent),
                           containingBlockWidth: containerSize.width)
```

```swift
// resolveRootSize — an `auto` root axis. Was: the offered space.
// Only the AUTO case changes. A root with a definite or percentage size keeps
// today's answer: the root's percentage width resolving against nil is a
// separate documented divergence about containing blocks, and reaching into it
// from here is explicitly out of scope (spec §2).
```

Thread `ctx` into `flexBaseSize` and `collectItems`, whose signatures gain it as their first parameter.

- [ ] **Step 2: Run the suite and record what breaks, before regenerating**

Run: `swift test --filter MetalUILayoutTests`

Expected: several golden comparisons FAIL. **Do not regenerate yet.** Write down every failing fixture and, for each, one sentence on which of the four sites moved it. That list is the raw material for Step 4 and is the only moment it is cheap to collect.

- [ ] **Step 3: Regenerate the corpus**

```bash
METALUI_REGENERATE_GOLDENS=1 swift test --filter regenerateAllGoldens
git diff --stat Tests/MetalUILayoutTests/Golden
```

- [ ] **Step 4: Explain every moved golden**

Create `docs/superpowers/2026-08-26-content-sizing-decisions.md`. It must contain:

- **A table of every golden that moved**, with the fixture name, the numbers before and after, and which of the four sites caused it. A moved golden with no explanation is a regression wearing a regeneration's clothes.
- **The list of goldens that did NOT move**, which is a map of what the corpus never covered — as valuable as the movers, and the input to Task 5's fixture list.
- Rulings `CS-1`… for every judgement made during execution, each with its reasoning and what it costs if wrong.

- [ ] **Step 5: Confirm the engine still matches the browser**

Run: `swift test --filter committedGoldensMatchTheBrowser`
Expected: PASS. This is the live-WebKit gate; a regenerated golden that still disagrees with WebKit means the engine is wrong, not the golden.

- [ ] **Step 6: Run the whole suite and read the summary line**

Run: `swift test`
Expected: a summary line, and the full count. Any test that asserted the old `0` behaviour is now wrong and must be updated to assert the new answer **with a comment naming what changed** — never deleted.

- [ ] **Step 7: Prove the wiring**

```bash
# 1. Revert `measureNode` to return 0 for containers.
#    Expect: the auto-cross fixture reddens SPECIFICALLY. Record the count.
# 2. Swap `.minContent` and `.maxContent` at the two sites that use them.
#    Expect: reddens. If it does NOT, the corpus has no fixture where the two
#    differ — say so in the report; Task 5 must add one.
```

- [ ] **Step 8: Commit**

```bash
git add Sources/MetalUILayout Tests/MetalUILayoutTests docs/superpowers/2026-08-26-content-sizing-decisions.md
git commit -m "feat(layout): measure content instead of resolving auto sizes to zero"
```

---

### Task 5: Fixtures for what the corpus never covered

**Files:**
- Create: `Tests/MetalUILayoutTests/Fixtures/flex_nested_auto_cross.html`, `flex_auto_height_two_levels.html`, `flex_wrap_min_vs_max_content.html`, `flex_item_floored_by_content.html`
- Modify: `Tests/MetalUILayoutTests/GeneratorTests.swift` (`allFixtures`)
- Create: the four corresponding goldens (generated, never hand-written)

**Interfaces:**
- Consumes: content sizing live, from Task 4.
- Produces: four fixtures in `allFixtures`.

- [ ] **Step 1: Write `flex_nested_auto_cross.html` — the divergence repro**

This is the exact case CLAUDE.md records: a 200×200 `wrap` root holding a `width: 120px` nested flex container. WebKit gives the nested container `120×50`; this engine gave `120×0` before Task 4, collapsing the line and stacking the next one on top of it.

```html
<!DOCTYPE html>
<html><head><style>
  body { margin: 0; }
  #root { display: flex; flex-wrap: wrap; width: 200px; height: 200px; }
  .mid { display: flex; width: 120px; }
  .mid > div { width: 40px; height: 50px; }
  .after { width: 60px; height: 30px; }
</style></head>
<body><div id="root">
  <div class="mid"><div></div></div>
  <div class="after"></div>
</div></body></html>
```

**Geometry avoids `x.5`** — every extent here is an integer, per the 1/64 quantization hazard.

- [ ] **Step 2: Write the other three fixtures**

`flex_auto_height_two_levels.html` — a column with no height, containing a column with no height, containing fixed-height children. Pins that an auto height propagates two levels.

```html
<!DOCTYPE html>
<html><head><style>
  body { margin: 0; }
  #root { display: flex; flex-direction: column; width: 300px; }
  .inner { display: flex; flex-direction: column; width: 180px; }
  .inner > div { width: 60px; height: 24px; }
</style></head>
<body><div id="root">
  <div class="inner"><div></div><div></div></div>
</div></body></html>
```

`flex_wrap_min_vs_max_content.html` — a nested `wrap` container narrow enough that its min-content and max-content sizes differ, so a `.minContent`/`.maxContent` swap reddens.

```html
<!DOCTYPE html>
<html><head><style>
  body { margin: 0; }
  #root { display: flex; width: 260px; height: 160px; }
  .mid { display: flex; flex-wrap: wrap; max-width: 100px; }
  .mid > div { width: 40px; height: 20px; }
</style></head>
<body><div id="root">
  <div class="mid"><div></div><div></div><div></div></div>
</div></body></html>
```

`flex_item_floored_by_content.html` — an item that would shrink below its content, now floored by the automatic minimum. This is the fixture for the change with the widest blast radius.

```html
<!DOCTYPE html>
<html><head><style>
  body { margin: 0; }
  #root { display: flex; width: 100px; height: 60px; }
  .squeezed { display: flex; flex: 1 1 0; }
  .squeezed > div { width: 80px; height: 20px; }
  .other { flex: 1 1 0; }
</style></head>
<body><div id="root">
  <div class="squeezed"><div></div></div>
  <div class="other"></div>
</div></body></html>
```

- [ ] **Step 3: Register them and generate the goldens**

Add all four to `allFixtures` in `GeneratorTests.swift` with viewport `(800, 600)`, then:

```bash
METALUI_REGENERATE_GOLDENS=1 swift test --filter regenerateAllGoldens
```

- [ ] **Step 4: Run the differential on every fixture — do not predict it**

For each of the four, change the declaration the fixture is named for, regenerate, and confirm the numbers move:

- `flex_nested_auto_cross` — give `.mid` an explicit `height: 10px`.
- `flex_auto_height_two_levels` — give `#root` an explicit `height: 500px`.
- `flex_wrap_min_vs_max_content` — raise `.mid`'s `max-width` to `200px` so it stops wrapping.
- `flex_item_floored_by_content` — shrink `.squeezed > div` to `width: 10px` so the floor stops binding.

**Run each one.** The wrapping milestone hand-derived sixteen sibling swaps and four were wrong. Restore each fixture with `cp` afterwards and regenerate.

Record the four measured before/after pairs in the report. A fixture whose numbers do **not** move is not pinning what its name claims and must be re-cut.

- [ ] **Step 5: Run the whole suite**

Run: `swift test`
Expected: a summary line and the full count, all passing.

- [ ] **Step 6: Commit**

```bash
git add Tests/MetalUILayoutTests
git commit -m "test(layout): fixtures for auto cross, auto height, min-vs-max content, and the automatic minimum"
```

---

### Task 6: Update the claims this milestone falsified

**Files:**
- Modify: `CLAUDE.md`
- Modify: `docs/superpowers/2026-08-26-content-sizing-decisions.md`
- Modify: `Sources/MetalUILayout/FlexEngine.swift` (comments citing the old behaviour)

**Interfaces:**
- Consumes: everything above.
- Produces: documentation matching the code.

On this project a false claim in `CLAUDE.md` is a defect, not a stale note. The last milestone corrected eight such claims and three had been introduced by the very commit that disproved a sibling — so treat this task as load-bearing, and **verify each row by re-measuring rather than by reading**.

- [ ] **Step 1: Delete the auto-cross divergence row**

CLAUDE.md's inert table has a long row beginning "An `auto` cross size on **any** item, stretched or not". That behaviour is gone. Delete the row and add its resolution to the decisions doc.

- [ ] **Step 2: Shrink the `MeasureFunction` row rather than deleting it**

The row says `MeasureFunction`/`tree.measure()` has "two callers, never populated". After this milestone the *containers* path is live but `newLeaf` still has no production caller, so the row narrows to leaves and M2 rather than disappearing. Re-measure with `grep -rn "newLeaf" Sources/` and state the actual count.

- [ ] **Step 3: Re-examine ruling FS-3**

FS-3 records that CSS Sizing §4.5's automatic minimum is `min(specified suggestion, content suggestion)` and that only the content half exists. This milestone supplies the content half **for containers**. State precisely what is now implemented and what is not, in the decisions doc, and correct FS-3's citation in CLAUDE.md if its reach changed.

- [ ] **Step 4: Sweep the engine's comments for claims this milestone falsified**

```bash
grep -rniE "cannot|unreachable|no test|never|0 uses|until M2|not implemented" Sources/MetalUILayout/
```

For each hit, check the mechanism it names rather than the milestone. Ruling WR-4's comment at `FlexEngine.swift:188` explicitly says "a measure function is not the only thing missing, a nested flex container has a content cross size today and the engine does not compute it" — that is now false and must be corrected, not deleted.

- [ ] **Step 5: Update the counts**

Re-run `swift test`, read the summary line, and update every test count in `CLAUDE.md` and the decisions doc to the measured number. Do not propagate arithmetic on faith.

- [ ] **Step 6: Commit**

```bash
git add CLAUDE.md docs/superpowers Sources/MetalUILayout
git commit -m "docs: retire the auto-cross divergence and correct what content sizing falsified"
```

## Exit criteria

- [ ] `swift test` completes with a **summary line** and the full count; `swift package clean && swift build` warning-free
- [ ] `MetalUILayout` still imports only `MetalUICore` (anchored grep)
- [ ] `measureNode` answers for containers and leaves alike, honouring `.definite`, `.minContent` and `.maxContent`
- [ ] The WebKit repro (`120×50`, not `120×0`) matches, pinned by `flex_nested_auto_cross`
- [ ] All 57 existing goldens regenerated; **every moved golden explained** in the decisions doc, and every non-mover listed
- [ ] Every mutation named in Tasks 1-5 measured and recorded — including the ones that redden only one test
- [ ] Cache hit-count asserted; `measureNode` purity asserted; the cycle guard traps with the node id
- [ ] `setStyle` during layout traps, with a positive control
- [ ] CLAUDE.md's auto-cross row deleted, `MeasureFunction` row narrowed, FS-3 re-examined
- [ ] Every new "cannot happen" comment names a mechanism, not a milestone

## Deliberately NOT in this plan

- **Structural identity (§4.3)** — its own milestone, different module, no shared code.
- **The root's percentage width** — a containing-block bug, not a content bug. It moves the root's stored size, which every descendant consumes.
- **Ruling BM-4's over-constrained box** — concerns padding exceeding a *specified* size.
- **Attaching a production `MeasureFunction`** — that is M2 text. Containers exercise the new path; leaves stay test-only.
- **`Column`/`Row` centring by default (EP-6)** — this milestone removes the *reason* the default is `stretch`, but changing it is EP-5's own follow-up.

## Risks carried in

- **`min-width: auto` going live is the widest change here**, not the auto-cross fix the milestone is named for. If the regenerated corpus moves far more than expected, that is why — check it against WebKit before assuming a bug.
- **The cache is invisible.** Only `theCacheIsActuallyConsulted` can see it working. If that test is ever weakened, exponential layout cost returns silently.
- **`measureNode`'s purity is unenforced by the type system.** A `setLayout` added below it returns the right size and passes every golden.
- **Taxonomy shape 9** — this milestone's whole subject is a composition (measurement × wrapping × margins × the freeze loop). The last time a task multiplied against three shipped features it produced three engine bugs. Ask what each change composes with, and check that pair against the browser.
- **Two guarantees still lapse under plausible CI configurations** (the ABI probe without a Metal device; `committedGoldensMatchTheBrowser` as the only live-WebKit consumer), plus a third: 25 tests gate on `canTypecheck`. All three must be required, non-gateable jobs.
