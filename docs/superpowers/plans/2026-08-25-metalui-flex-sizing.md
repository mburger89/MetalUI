# MetalUI — Flex Base Size and the Freeze Loop

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `flex-grow`, `flex-shrink` and `flex-basis` working, so a row of `flex: 1` / `flex: 2` children divides free space the way a browser does.

**Architecture:** CSS Flexbox §9.2 (flex base size) and §9.7 (resolve flexible lengths) implemented against the existing WebKit golden corpus. The current one-pass `layoutChildren` is split into collect → resolve → position first, because the freeze loop cannot run inside a loop that positions as it goes.

**Tech Stack:** Swift 6.3, Swift Testing. No third-party dependencies.

**Spec:** `docs/superpowers/specs/2026-08-24-metalui-design.md` §5.

**Prior work:** M1a is merged (79 tests). Read `docs/superpowers/2026-08-25-m1a-decisions.md` — its "Readiness for flex base size" section is the direct input to this plan, and its rulings PF-3, A-4, C-3 and D-2 all constrain this work.

## Global Constraints

- **Swift tools 6.3**, `swiftLanguageModes: [.v6]`, strict concurrency ON. Warnings are errors to fix, never suppress.
- **No third-party dependencies. No `.unsafeFlags`.**
- **`MetalUILayout` imports only `MetalUICore`.** Verify anchored — an unanchored `Metal` also matches `import MetalUICore`:
  ```bash
  grep -rnE "^import (Metal|AppKit|UIKit|WebKit|MetalUIRender|MetalUIPlatform)$" \
    Sources/MetalUILayout/ && echo "LAYERING VIOLATION" || echo "clean"
  ```
- **Box model is `border-box` only.** Every fixture declares `box-sizing: border-box` and `body { margin: 0 }`.
- **All stored rects are absolute to the root**, never parent-relative. `roundLayout` keeps no cross-rect state, so its no-drift guarantee depends on it. Pinned by `nestedContainersStoreAbsoluteNotRelativeCoordinates` — **the browser corpus cannot detect this class**, so that test is the only guard.
- **Out of scope:** alignment (`justify-content`, `align-*`), wrapping, absolute positioning, reverse directions, the box model, aspect ratio, Grid. Each is its own plan.

### Read before writing code: `docs/practices/verifying-tests-can-fail.md`

M1a produced six documented cases of behaviour no test could see, all found by mutation rather than inspection. Every task here ends by breaking what it just built and confirming the suite notices.

### Two traps that have bitten repeatedly

- **`git checkout <file>` silently restores nothing on an untracked file.** Commit before mutating; verify a revert with `git status --short`, not by assuming.
- **`swift package clean`, not `rm -rf .build`,** after touching `Sources/MetalUIRender/Shaders/MetalUIShaderTypes.h`. Nothing here should touch it.

---

## The structural problem this plan solves first

`layoutChildren` currently sizes, positions and recurses **in one pass** (`FlexEngine.swift:112-135`). §9.7's freeze loop needs every item's base size known *before* any position is assigned, because free space is a function of the whole line. The loop must therefore be split before any grow code exists.

Two further traps, both named in M1a's final review:

1. **`resolveNodeSize` serves both the root (`:40`) and every item (`:120`).** Flex base size applies only to items. Adding a `flexBasis` check *inside* it is the natural-looking move and is **exactly what ruling PF-3 forbids** — it extends the scope-boundary fallback instead of replacing it. A separate `flexBaseSize(item:)` entry point forecloses that.
2. **`roundLayout` has no pipeline slot.** It has zero production callers today, and raw-vs-rounded is undetectable because every current fixture is integral. `flex: 1` across seven children produces `100/7` immediately — wire it in this plan, or the grow work is validated by a comparison that provably cannot tell the difference.

---

### Task 1: Split the pass, wire rounding, delete the fallback

**Files:**
- Modify: `Sources/MetalUILayout/FlexEngine.swift`
- Modify: `Tests/MetalUILayoutTests/FlexEngineTests.swift`
- Test: `Tests/MetalUILayoutTests/FlexEngineTests.swift`

**Interfaces:**
- Consumes: `LayoutTree`, `Style`, `resolveDimension`, `resolveLength`, `clamp`, `roundLayout`, `LayoutRect`, `SizeD`, `OptionalSizeD`, `AvailableSpaceSize`.
- Produces:
  - `struct FlexItem { let node: LayoutNodeID; var baseSize: Double; var hypotheticalMainSize: Double; var targetMainSize: Double; var crossSize: Double; var frozen: Bool }`
  - `func collectItems(_ tree:_:containerSize:rootFontSize:) -> [FlexItem]` — phase 1, sizes nothing flexible yet
  - `func positionItems(_ tree:_:items:containerOrigin:containerSize:rootFontSize:)` — phase 3, assigns rects and recurses
  - `computeLayout` unchanged in signature, now ending with a rounding pass

**No behaviour change is intended except two**, both deliberate and both pinned: auto-sized items become 0 rather than the container's extent, and every stored rect is rounded.

- [ ] **Step 1: Write the failing test**

Add to `Tests/MetalUILayoutTests/FlexEngineTests.swift`:

```swift
@Test func computeLayoutRoundsEveryStoredRect() {
    // 3 children of 100/3 in a 100 row. Cumulative rounding must make the
    // widths 33/34/33 and close the row exactly on the parent.
    let tree = LayoutTree()
    func third() -> LayoutNodeID {
        var s = Style()
        s.size = Size(width: MetalUICore.Dimension.length(.pixels(Pixels(Float(100.0 / 3.0)))),
                      height: px(10))
        return tree.newNode(style: s, children: [])
    }
    let a = third(), b = third(), c = third()
    var rootStyle = Style()
    rootStyle.flexDirection = .row
    rootStyle.size = Size(width: px(100), height: px(10))
    let root = tree.newNode(style: rootStyle, children: [a, b, c])

    computeLayout(tree, root: root,
                  available: AvailableSpaceSize(width: .definite(400), height: .definite(400)))

    // Every stored value is a whole number — nothing fractional survives.
    for n in [root, a, b, c] {
        let r = tree.layout(n)
        #expect(r.x == r.x.rounded(), "x \(r.x) not rounded")
        #expect(r.width == r.width.rounded(), "width \(r.width) not rounded")
    }
    #expect(tree.layout(a).width + tree.layout(b).width + tree.layout(c).width == 100)
    #expect(tree.layout(c).x + tree.layout(c).width == 100)
}

@Test func autoSizedChildIsZeroUntilFlexBaseSizeLands() {
    // Replaces `autoSizedChildTakesItsContainersExtentForNow`. The Task 7
    // fallback (auto -> container extent) is deleted here; the real content
    // size arrives with flex base size in Task 2. Zero is the honest
    // placeholder: visibly wrong rather than plausibly wrong.
    let tree = LayoutTree()
    let kid = tree.newNode(style: Style(), children: [])   // size defaults to .auto
    var rootStyle = Style()
    rootStyle.size = Size(width: px(300), height: px(100))
    let root = tree.newNode(style: rootStyle, children: [kid])

    computeLayout(tree, root: root,
                  available: AvailableSpaceSize(width: .definite(800), height: .definite(600)))

    #expect(tree.layout(kid).width == 0)
    #expect(tree.layout(kid).height == 0)
}
```

Delete the existing `autoSizedChildTakesItsContainersExtentForNow` test — its behaviour is being removed on purpose, and ruling PF-3 required exactly this to be a visible, deliberate act.

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter FlexEngineTests`
Expected: `computeLayoutRoundsEveryStoredRect` FAILS (widths 33.333…), `autoSizedChildIsZeroUntilFlexBaseSizeLands` FAILS (width 300, the fallback still in place).

- [ ] **Step 3: Replace `FlexEngine.swift`'s body**

Keep the existing file-level doc comment, and **delete from it the reverse-direction and box-model paragraphs only if you implement them — you are not, so leave both in place.** Replace `computeLayout`, `resolveNodeSize` and `layoutChildren` with:

```swift
/// One flex item, carried through the three phases of a line's layout.
///
/// Split out because §9.7 resolves free space across the *whole* line before any
/// item is positioned — a single loop that sizes and places as it goes cannot
/// express that.
struct FlexItem {
    let node: LayoutNodeID
    /// §9.2 flex base size, before min/max clamping.
    var baseSize: Double
    /// §9.2 base size clamped by min/max.
    var hypotheticalMainSize: Double
    /// The size after §9.7 distributes free space. Starts at hypothetical.
    var targetMainSize: Double
    var crossSize: Double
    /// §9.7 freezes an item once its size is final.
    var frozen: Bool
}

public func computeLayout(
    _ tree: LayoutTree,
    root: LayoutNodeID,
    available: AvailableSpaceSize,
    rootFontSize: Double = 16
) {
    let rootSize = resolveNodeSize(tree, root, parent: .unspecified,
                                   available: available, rootFontSize: rootFontSize)
    tree.setLayout(root, LayoutRect(x: 0, y: 0, width: rootSize.width, height: rootSize.height))
    layoutContainer(tree, root, containerOrigin: (0, 0), containerSize: rootSize,
                    rootFontSize: rootFontSize)

    // Round last, over the finished absolute rects. Spec §5.7 designates the
    // rounded layout as the comparison space, so the engine must apply the same
    // pass the golden generator does — otherwise a fractional layout is compared
    // against a rounded one and the difference is invisible.
    roundStoredRects(tree, root)
}

/// Apply `roundLayout` to every node's stored rect, depth-first.
///
/// `roundLayout` is stateless per rect — it rounds each rect's own cumulative
/// edges — so applying it node-by-node is equivalent to applying it to the whole
/// tree at once, and requires no traversal order.
private func roundStoredRects(_ tree: LayoutTree, _ node: LayoutNodeID) {
    tree.setLayout(node, roundLayout([tree.layout(node)])[0])
    for kid in tree.children(node) {
        roundStoredRects(tree, kid)
    }
}

/// Resolve a node's own border-box size from its style.
///
/// This is for nodes whose size comes from their own style alone — the root, and
/// an item's cross axis. **It is deliberately not the flex-item path:** a flex
/// item's main size comes from `flexBaseSize(_:)` and §9.7, never from here.
/// Adding a `flexBasis` branch to this function would recreate the scope-boundary
/// fallback that ruling PF-3 exists to prevent.
private func resolveNodeSize(
    _ tree: LayoutTree,
    _ node: LayoutNodeID,
    parent: OptionalSizeD,
    available: AvailableSpaceSize,
    rootFontSize: Double
) -> SizeD {
    let s = tree.style(node)

    func axis(_ dim: Dimension, _ minDim: Dimension, _ maxDim: Dimension,
              parentExtent: Double?) -> Double {
        let resolved = resolveDimension(dim, against: parentExtent, rootFontSize: rootFontSize)
        let lower = resolveDimension(minDim, against: parentExtent, rootFontSize: rootFontSize)
        let upper = resolveDimension(maxDim, against: parentExtent, rootFontSize: rootFontSize)
        // An unresolvable size is 0 here. For a flex item's MAIN axis that is
        // never reached — §9.2 supplies the base size instead.
        return clamp(resolved ?? 0, min: lower, max: upper)
    }

    return SizeD(
        width: axis(s.size.width, s.minSize.width, s.maxSize.width, parentExtent: parent.width),
        height: axis(s.size.height, s.minSize.height, s.maxSize.height, parentExtent: parent.height))
}

/// Lay out one container: collect its items, resolve flexible lengths, position.
private func layoutContainer(
    _ tree: LayoutTree,
    _ container: LayoutNodeID,
    containerOrigin: (Double, Double),
    containerSize: SizeD,
    rootFontSize: Double
) {
    let items = collectItems(tree, container, containerSize: containerSize,
                             rootFontSize: rootFontSize)
    guard !items.isEmpty else { return }
    // §9.7 lands here in Task 3. Until then every item keeps its hypothetical
    // main size, which is what the pre-split code did.
    positionItems(tree, container, items: items, containerOrigin: containerOrigin,
                  containerSize: containerSize, rootFontSize: rootFontSize)
}

/// Phase 1 — size every item without positioning any of them.
private func collectItems(
    _ tree: LayoutTree,
    _ container: LayoutNodeID,
    containerSize: SizeD,
    rootFontSize: Double
) -> [FlexItem] {
    let s = tree.style(container)
    let isRow = s.flexDirection.isRow
    let parent = OptionalSizeD(width: containerSize.width, height: containerSize.height)

    return tree.children(container)
        .filter { tree.style($0).display != .none }
        .map { kid in
            let size = resolveNodeSize(tree, kid, parent: parent,
                                       available: AvailableSpaceSize(
                                           width: .definite(containerSize.width),
                                           height: .definite(containerSize.height)),
                                       rootFontSize: rootFontSize)
            let main = isRow ? size.width : size.height
            let cross = isRow ? size.height : size.width
            return FlexItem(node: kid, baseSize: main, hypotheticalMainSize: main,
                            targetMainSize: main, crossSize: cross, frozen: false)
        }
}

/// Phase 3 — assign absolute rects and recurse.
private func positionItems(
    _ tree: LayoutTree,
    _ container: LayoutNodeID,
    items: [FlexItem],
    containerOrigin: (Double, Double),
    containerSize: SizeD,
    rootFontSize: Double
) {
    let s = tree.style(container)
    let isRow = s.flexDirection.isRow
    let gap = resolveLength(isRow ? s.gap.horizontal : s.gap.vertical,
                            against: isRow ? containerSize.width : containerSize.height,
                            rootFontSize: rootFontSize) ?? 0

    var cursor: Double = 0
    for (index, item) in items.enumerated() {
        // Between items only. A trailing gap is invisible today because `cursor`
        // dies with the loop, but `justify-content` will read the final cursor as
        // the line's content size, where it is a real off-by-`gap` bug.
        if index > 0 { cursor += gap }

        let x = containerOrigin.0 + (isRow ? cursor : 0)
        let y = containerOrigin.1 + (isRow ? 0 : cursor)
        let size = isRow
            ? SizeD(width: item.targetMainSize, height: item.crossSize)
            : SizeD(width: item.crossSize, height: item.targetMainSize)

        tree.setLayout(item.node, LayoutRect(x: x, y: y, width: size.width, height: size.height))
        layoutContainer(tree, item.node, containerOrigin: (x, y), containerSize: size,
                        rootFontSize: rootFontSize)

        cursor += item.targetMainSize
    }
}
```

- [ ] **Step 4: Run the whole suite**

Run: `swift test`
Expected: all pass. The split is a refactor — every existing assertion must survive it unchanged. If a WebKit comparison breaks, the split is wrong; do not adjust the golden.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "refactor(layout): split flex layout into collect/resolve/position and round stored rects"
```

- [ ] **Step 6: Prove the new guards can fail**

Now that the file is tracked, mutate and confirm each reddens:

```bash
# 1. Remove the rounding pass.
python3 - <<'PY'
p="Sources/MetalUILayout/FlexEngine.swift"
s=open(p).read()
s=s.replace("    roundStoredRects(tree, root)", "    // MUTANT: rounding removed")
open(p,"w").write(s)
PY
swift test --filter computeLayoutRoundsEveryStoredRect 2>&1 | grep -c "Expectation failed"
git checkout Sources/MetalUILayout/FlexEngine.swift

# 2. Restore the deleted fallback.
python3 - <<'PY'
p="Sources/MetalUILayout/FlexEngine.swift"
s=open(p).read()
s=s.replace("return clamp(resolved ?? 0, min: lower, max: upper)",
            "return clamp(resolved ?? containerFallbackMUTANT, min: lower, max: upper)")
open(p,"w").write(s)
PY
swift build 2>&1 | grep -c "error" && echo "compile-caught, acceptable"
git checkout Sources/MetalUILayout/FlexEngine.swift

# 3. Position relative instead of absolute.
python3 - <<'PY'
p="Sources/MetalUILayout/FlexEngine.swift"
s=open(p).read()
s=s.replace("let x = containerOrigin.0 + (isRow ? cursor : 0)", "let x = (isRow ? cursor : 0)")
s=s.replace("let y = containerOrigin.1 + (isRow ? 0 : cursor)", "let y = (isRow ? 0 : cursor)")
open(p,"w").write(s)
PY
swift test 2>&1 | grep -c "Expectation failed"
git checkout Sources/MetalUILayout/FlexEngine.swift
git status --short   # must be empty
swift test 2>&1 | tail -2
```

Expected: mutation 1 reddens the rounding test; mutation 3 reddens `nestedContainersStoreAbsoluteNotRelativeCoordinates` **and nothing else** — confirming again that the browser corpus cannot see it. Clean tree and a green suite at the end.

- [ ] **Step 7: Commit any test additions from Step 6**

```bash
git add -A && git commit -m "test(layout): record mutation results for the split" || echo "nothing to commit"
```

---

### Task 2: Flex base size (§9.2)

**Files:**
- Modify: `Sources/MetalUILayout/FlexEngine.swift`
- Create: `Sources/MetalUILayout/FlexBaseSize.swift`
- Test: `Tests/MetalUILayoutTests/FlexBaseSizeTests.swift`

**Interfaces:**
- Consumes: `Style`, `LayoutTree`, `resolveDimension`, `clamp`, `MeasureFunction`, `AvailableSpace`.
- Produces: `func flexBaseSize(_ tree: LayoutTree, item: LayoutNodeID, isRow: Bool, containerMain: Double?, containerCross: Double?, rootFontSize: Double) -> Double`

**This is the entry point ruling PF-3 requires** — separate from `resolveNodeSize`, so the deleted fallback cannot come back by accident.

§9.2's cascade, in order:
1. `flex-basis` is definite → that value.
2. `flex-basis: auto` and the main size property is definite → the main size.
3. Otherwise → **content size**, obtained from the item's measure function at max-content. No measure function means 0.

- [ ] **Step 1: Write the failing test**

Create `Tests/MetalUILayoutTests/FlexBaseSizeTests.swift`:

```swift
import Testing
import MetalUICore
@testable import MetalUILayout

private func px(_ v: Double) -> MetalUICore.Dimension { .length(.pixels(Pixels(Float(v)))) }

@Test func definiteFlexBasisWins() {
    let tree = LayoutTree()
    var s = Style()
    s.flexBasis = px(120)
    s.size = Size(width: px(50), height: px(10))   // must be ignored
    let item = tree.newNode(style: s, children: [])
    #expect(flexBaseSize(tree, item: item, isRow: true,
                         containerMain: 700, containerCross: 100, rootFontSize: 16) == 120)
}

@Test func autoBasisFallsBackToTheDefiniteMainSize() {
    let tree = LayoutTree()
    var s = Style()
    s.flexBasis = .auto
    s.size = Size(width: px(80), height: px(10))
    let item = tree.newNode(style: s, children: [])
    #expect(flexBaseSize(tree, item: item, isRow: true,
                         containerMain: 700, containerCross: 100, rootFontSize: 16) == 80)
    // In a column the main axis is height, so the same style yields 10.
    #expect(flexBaseSize(tree, item: item, isRow: false,
                         containerMain: 700, containerCross: 100, rootFontSize: 16) == 10)
}

@Test func autoBasisWithNoDefiniteSizeMeasuresContent() {
    let tree = LayoutTree()
    var s = Style()
    s.flexBasis = .auto                              // size stays .auto
    let item = tree.newLeaf(style: s) { known, available in
        // A leaf that reports 137 wide at max-content.
        if case .maxContent = available.width { return SizeD(width: 137, height: 20) }
        return SizeD(width: 40, height: 20)
    }
    #expect(flexBaseSize(tree, item: item, isRow: true,
                         containerMain: 700, containerCross: 100, rootFontSize: 16) == 137)
}

@Test func autoBasisWithNoMeasureFunctionIsZero() {
    let tree = LayoutTree()
    let item = tree.newNode(style: Style(), children: [])
    #expect(flexBaseSize(tree, item: item, isRow: true,
                         containerMain: 700, containerCross: 100, rootFontSize: 16) == 0)
}

@Test func percentageBasisResolvesAgainstTheContainerMainAxis() {
    let tree = LayoutTree()
    var s = Style()
    s.flexBasis = .length(.percent(0.25))
    let item = tree.newNode(style: s, children: [])
    #expect(abs(flexBaseSize(tree, item: item, isRow: true,
                             containerMain: 800, containerCross: 100, rootFontSize: 16) - 200) < 1e-4)
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --filter FlexBaseSizeTests`
Expected: FAIL — `cannot find 'flexBaseSize' in scope`.

- [ ] **Step 3: Implement §9.2**

Create `Sources/MetalUILayout/FlexBaseSize.swift`:

```swift
import MetalUICore

/// CSS Flexbox §9.2 — a flex item's base size, before min/max clamping.
///
/// **This is deliberately not part of `resolveNodeSize`.** An item's main size
/// comes from this cascade; only its cross size comes from its own style. Merging
/// the two would recreate the "auto means the container's extent" fallback that
/// ruling PF-3 removed, and that failure is silent.
///
/// The cascade, in spec order:
/// 1. a definite `flex-basis` wins outright, even over an explicit `width`;
/// 2. `flex-basis: auto` defers to the main size property, if that is definite;
/// 3. otherwise the item is content-sized — its measure function at max-content.
///
/// An item with no measure function and no definite size is 0. That is honest
/// rather than convenient: nothing measures content until the text system lands,
/// and a zero-width box is visibly wrong where a container-width box is
/// plausibly wrong.
func flexBaseSize(
    _ tree: LayoutTree,
    item: LayoutNodeID,
    isRow: Bool,
    containerMain: Double?,
    containerCross: Double?,
    rootFontSize: Double
) -> Double {
    let s = tree.style(item)

    // 1. Definite flex-basis.
    if let basis = resolveDimension(s.flexBasis, against: containerMain,
                                    rootFontSize: rootFontSize) {
        return basis
    }

    // 2. flex-basis: auto -> the main size property, if definite.
    let mainDim = isRow ? s.size.width : s.size.height
    if let main = resolveDimension(mainDim, against: containerMain,
                                   rootFontSize: rootFontSize) {
        return main
    }

    // 3. Content size, at max-content in the main axis.
    guard let measure = tree.measure(item) else { return 0 }
    let known = OptionalSizeD(
        width: isRow ? nil : resolveDimension(s.size.width, against: containerCross,
                                              rootFontSize: rootFontSize),
        height: isRow ? resolveDimension(s.size.height, against: containerCross,
                                         rootFontSize: rootFontSize) : nil)
    let available = AvailableSpaceSize(
        width: isRow ? .maxContent : (containerCross.map { .definite($0) } ?? .maxContent),
        height: isRow ? (containerCross.map { .definite($0) } ?? .maxContent) : .maxContent)
    let measured = measure(known, available)
    return isRow ? measured.width : measured.height
}
```

- [ ] **Step 4: Wire it into `collectItems`**

In `FlexEngine.swift`, replace `collectItems`' body so the **main** axis comes from `flexBaseSize` and the **cross** axis from `resolveNodeSize`:

```swift
private func collectItems(
    _ tree: LayoutTree,
    _ container: LayoutNodeID,
    containerSize: SizeD,
    rootFontSize: Double
) -> [FlexItem] {
    let s = tree.style(container)
    let isRow = s.flexDirection.isRow
    let containerMain = isRow ? containerSize.width : containerSize.height
    let containerCross = isRow ? containerSize.height : containerSize.width
    let parent = OptionalSizeD(width: containerSize.width, height: containerSize.height)

    return tree.children(container)
        .filter { tree.style($0).display != .none }
        .map { kid in
            let base = flexBaseSize(tree, item: kid, isRow: isRow,
                                    containerMain: containerMain,
                                    containerCross: containerCross,
                                    rootFontSize: rootFontSize)

            let ks = tree.style(kid)
            let minMain = resolveDimension(isRow ? ks.minSize.width : ks.minSize.height,
                                           against: containerMain, rootFontSize: rootFontSize)
            let maxMain = resolveDimension(isRow ? ks.maxSize.width : ks.maxSize.height,
                                           against: containerMain, rootFontSize: rootFontSize)
            let hypothetical = clamp(base, min: minMain, max: maxMain)

            // Cross size still comes from the item's own style. Stretch and
            // content-based cross sizing arrive with the alignment work.
            let own = resolveNodeSize(tree, kid, parent: parent,
                                      available: AvailableSpaceSize(
                                          width: .definite(containerSize.width),
                                          height: .definite(containerSize.height)),
                                      rootFontSize: rootFontSize)
            let cross = isRow ? own.height : own.width

            return FlexItem(node: kid, baseSize: base, hypotheticalMainSize: hypothetical,
                            targetMainSize: hypothetical, crossSize: cross, frozen: false)
        }
}
```

- [ ] **Step 5: Run the whole suite**

Run: `swift test`
Expected: all pass, including every existing WebKit comparison. Fixed-size children have a definite main size, so step 2 of the cascade returns exactly what `resolveNodeSize` used to.

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "feat(layout): implement CSS Flexbox 9.2 flex base size"
```

- [ ] **Step 7: Prove the cascade order is load-bearing**

```bash
# Swap steps 1 and 2 — main size consulted before flex-basis.
python3 - <<'PY'
p="Sources/MetalUILayout/FlexBaseSize.swift"
s=open(p).read()
a=s.index("    // 1. Definite flex-basis.")
b=s.index("    // 3. Content size")
one=s[a:s.index("    // 2. flex-basis: auto")]
two=s[s.index("    // 2. flex-basis: auto"):b]
open(p,"w").write(s[:a] + two + one + s[b:])
PY
swift test --filter FlexBaseSizeTests 2>&1 | grep -c "Expectation failed"
git checkout Sources/MetalUILayout/FlexBaseSize.swift
git status --short   # must be empty
```

Expected: a non-zero count — `definiteFlexBasisWins` must catch the reordering. If it does not, the test is pinning nothing.

---

### Task 3: The freeze loop (§9.7)

**Files:**
- Create: `Sources/MetalUILayout/ResolveFlexibleLengths.swift`
- Modify: `Sources/MetalUILayout/FlexEngine.swift`
- Create: `Tests/MetalUILayoutTests/Fixtures/flex_row_grow_uneven.html`
- Create: `Tests/MetalUILayoutTests/Fixtures/flex_row_shrink.html`
- Test: `Tests/MetalUILayoutTests/FreezeLoopTests.swift`
- Modify: `Tests/MetalUILayoutTests/GeneratorTests.swift` (register both fixtures)
- Modify: `Tests/MetalUILayoutTests/FlexEngineTests.swift` (wire the unused golden)

**Interfaces:**
- Consumes: `FlexItem`, `Style`, `LayoutTree`, `resolveDimension`, `clamp`.
- Produces: `func resolveFlexibleLengths(_ tree: LayoutTree, _ container: LayoutNodeID, items: inout [FlexItem], containerMain: Double, gap: Double, isRow: Bool, rootFontSize: Double)`

**Exit criterion worth noting:** `flex_row_fixed_and_grow.json` has been committed since Task 4 of M1a and **nothing has ever compared against it** — only the staleness guard reads it. This task is what finally makes it load-bearing. That is a case of taxonomy shape 3 in the practices doc, closed.

- [ ] **Step 1: Write the two fixtures**

`Tests/MetalUILayoutTests/Fixtures/flex_row_grow_uneven.html`:

```html
<!doctype html>
<html><head><meta charset="utf-8"><style>
  * { box-sizing: border-box; margin: 0; padding: 0; border: 0; }
  body { margin: 0; }
  #root { display: flex; flex-direction: row; width: 640px; height: 40px; }
  .a { flex: 1 1 0; }
  .b { flex: 3 1 0; }
  .c { flex: 0 0 140px; }
</style></head><body>
  <div id="root" data-id="root">
    <div class="a" data-id="a"></div>
    <div class="b" data-id="b"></div>
    <div class="c" data-id="c"></div>
  </div>
</body></html>
```

`Tests/MetalUILayoutTests/Fixtures/flex_row_shrink.html`:

```html
<!doctype html>
<html><head><meta charset="utf-8"><style>
  * { box-sizing: border-box; margin: 0; padding: 0; border: 0; }
  body { margin: 0; }
  #root { display: flex; flex-direction: row; width: 300px; height: 40px; }
  .a { flex: 0 1 200px; }
  .b { flex: 0 2 200px; }
  .c { flex: 0 0 100px; }
</style></head><body>
  <div id="root" data-id="root">
    <div class="a" data-id="a"></div>
    <div class="b" data-id="b"></div>
    <div class="c" data-id="c"></div>
  </div>
</body></html>
```

Register both in `allFixtures` in `GeneratorTests.swift`, at viewport 800×600.

- [ ] **Step 2: Write the failing test**

Create `Tests/MetalUILayoutTests/FreezeLoopTests.swift`:

```swift
import Testing
import Foundation
import MetalUICore
@testable import MetalUILayout

private func px(_ v: Double) -> MetalUICore.Dimension { .length(.pixels(Pixels(Float(v)))) }

private func flexChild(_ tree: LayoutTree, grow: Float, shrink: Float,
                       basis: MetalUICore.Dimension, cross: Double = 40) -> LayoutNodeID {
    var s = Style()
    s.flexGrow = grow
    s.flexShrink = shrink
    s.flexBasis = basis
    s.size = Size(width: .auto, height: px(cross))
    return tree.newNode(style: s, children: [])
}

private func row(_ tree: LayoutTree, width: Double, _ kids: [LayoutNodeID]) -> LayoutNodeID {
    var s = Style()
    s.flexDirection = .row
    s.size = Size(width: px(width), height: px(40))
    return tree.newNode(style: s, children: kids)
}

@Test func growDistributesFreeSpaceInProportionToFlexGrow() {
    let tree = LayoutTree()
    let a = flexChild(tree, grow: 1, shrink: 1, basis: px(0))
    let b = flexChild(tree, grow: 2, shrink: 1, basis: px(0))
    let c = flexChild(tree, grow: 0, shrink: 0, basis: px(100))
    let root = row(tree, width: 700, [a, b, c])

    computeLayout(tree, root: root,
                  available: AvailableSpaceSize(width: .definite(800), height: .definite(600)))

    // 700 - 100 = 600 free, split 1:2.
    #expect(tree.layout(a).width == 200)
    #expect(tree.layout(b).width == 400)
    #expect(tree.layout(c).width == 100)
    #expect(tree.layout(a).x == 0)
    #expect(tree.layout(b).x == 200)
    #expect(tree.layout(c).x == 600)
}

@Test func shrinkIsWeightedByBaseSize() {
    // §9.7: shrink is scaled by base size, so equal shrink factors do NOT
    // remove equal amounts. a=200 b=200 c=100 in a 300 row: 200 overflow.
    // Scaled factors: a 1*200=200, b 2*200=400, c frozen. Total 600.
    // a loses 200*(200/600)=66.67 -> 133.33; b loses 200*(400/600)=133.33 -> 66.67.
    let tree = LayoutTree()
    let a = flexChild(tree, grow: 0, shrink: 1, basis: px(200))
    let b = flexChild(tree, grow: 0, shrink: 2, basis: px(200))
    let c = flexChild(tree, grow: 0, shrink: 0, basis: px(100))
    let root = row(tree, width: 300, [a, b, c])

    computeLayout(tree, root: root,
                  available: AvailableSpaceSize(width: .definite(800), height: .definite(600)))

    #expect(tree.layout(a).width == 133)   // 133.33 rounded
    #expect(tree.layout(b).width == 67)    // 66.67 rounded
    #expect(tree.layout(c).width == 100)
    #expect(tree.layout(c).x + tree.layout(c).width == 300)
}

@Test func gapIsRemovedFromFreeSpaceBeforeDistribution() {
    let tree = LayoutTree()
    let a = flexChild(tree, grow: 1, shrink: 1, basis: px(0))
    let b = flexChild(tree, grow: 1, shrink: 1, basis: px(0))
    var rootStyle = Style()
    rootStyle.flexDirection = .row
    rootStyle.size = Size(width: px(220), height: px(40))
    rootStyle.gap = Axes(both: .pixels(Pixels(20)))
    let root = tree.newNode(style: rootStyle, children: [a, b])

    computeLayout(tree, root: root,
                  available: AvailableSpaceSize(width: .definite(800), height: .definite(600)))

    // 220 - 20 gap = 200 free, split evenly.
    #expect(tree.layout(a).width == 100)
    #expect(tree.layout(b).width == 100)
    #expect(tree.layout(b).x == 120)
}

@MainActor
@Test func growMatchesWebKitOnTheUnusedGolden() throws {
    // flex_row_fixed_and_grow.json has been committed since M1a Task 4 and
    // nothing has ever compared against it. This is what makes it load-bearing.
    let golden = try loadGolden("flex_row_fixed_and_grow")
    let byID = Dictionary(uniqueKeysWithValues: golden.rounded.map { ($0.id, $0) })

    let tree = LayoutTree()
    let a = flexChild(tree, grow: 1, shrink: 1, basis: px(0), cross: 100)
    let b = flexChild(tree, grow: 2, shrink: 1, basis: px(0), cross: 100)
    var cs = Style()
    cs.size = Size(width: px(100), height: px(100))
    let c = tree.newNode(style: cs, children: [])
    var rootStyle = Style()
    rootStyle.flexDirection = .row
    rootStyle.size = Size(width: px(700), height: px(100))
    let root = tree.newNode(style: rootStyle, children: [a, b, c])

    computeLayout(tree, root: root,
                  available: AvailableSpaceSize(width: .definite(800), height: .definite(600)))

    for (node, id) in [(root, "root"), (a, "a"), (b, "b"), (c, "c")] {
        let ours = tree.layout(node)
        let theirs = try #require(byID[id])
        #expect(abs(ours.x - theirs.x) <= 0.1, "\(id).x ours \(ours.x) vs \(theirs.x)")
        #expect(abs(ours.width - theirs.width) <= 0.1, "\(id).w ours \(ours.width) vs \(theirs.width)")
    }
}
```

- [ ] **Step 3: Run to verify it fails**

Run: `swift test --filter FreezeLoopTests`
Expected: FAIL — grow and shrink are not implemented, so every item keeps its base size.

- [ ] **Step 4: Implement §9.7**

Create `Sources/MetalUILayout/ResolveFlexibleLengths.swift`:

```swift
import MetalUICore

/// CSS Flexbox §9.7 — resolve flexible lengths for one line.
///
/// The loop exists because clamping an item to its min or max frees space that
/// must be redistributed among the others. Each pass freezes the items whose
/// size is now final and repeats with what is left.
///
/// Two details that are easy to get wrong and that the tests pin:
///
/// - **Shrink is weighted by base size**, grow is not. Two items with equal
///   `flex-shrink` but different base sizes do not lose equal amounts — a larger
///   item gives up proportionally more. §9.7.4.b.
/// - **Gaps come out of free space before distribution.** They are part of the
///   line's consumed space, not something items may grow into.
func resolveFlexibleLengths(
    _ tree: LayoutTree,
    _ container: LayoutNodeID,
    items: inout [FlexItem],
    containerMain: Double,
    gap: Double,
    isRow: Bool,
    rootFontSize: Double
) {
    guard !items.isEmpty else { return }

    let totalGap = gap * Double(items.count - 1)
    let hypotheticalTotal = items.reduce(0) { $0 + $1.hypotheticalMainSize }
    let usingGrow = hypotheticalTotal + totalGap < containerMain

    // §9.7.1 — freeze items that cannot flex in the chosen direction.
    for i in items.indices {
        let s = tree.style(items[i].node)
        let factor = usingGrow ? s.flexGrow : s.flexShrink
        let inflexible = factor == 0
            || (usingGrow && items[i].baseSize > items[i].hypotheticalMainSize)
            || (!usingGrow && items[i].baseSize < items[i].hypotheticalMainSize)
        if inflexible {
            items[i].targetMainSize = items[i].hypotheticalMainSize
            items[i].frozen = true
        } else {
            items[i].targetMainSize = items[i].baseSize
        }
    }

    // The loop terminates because every pass freezes at least one item.
    while items.contains(where: { !$0.frozen }) {
        let frozenTotal = items.filter(\.frozen).reduce(0) { $0 + $1.targetMainSize }
        let unfrozenBase = items.filter { !$0.frozen }.reduce(0) { $0 + $1.baseSize }
        let remaining = containerMain - totalGap - frozenTotal - unfrozenBase

        // §9.7.4.b — distribute in proportion to the flex factor.
        let factors: [Double] = items.map { item in
            guard !item.frozen else { return 0 }
            let s = tree.style(item.node)
            return usingGrow ? Double(s.flexGrow) : Double(s.flexShrink) * item.baseSize
        }
        let factorTotal = factors.reduce(0, +)

        if factorTotal > 0 {
            for i in items.indices where !items[i].frozen {
                items[i].targetMainSize = items[i].baseSize + remaining * (factors[i] / factorTotal)
            }
        }

        // §9.7.4.c/d — clamp, then freeze according to the sign of the total
        // violation. Freezing only the violating items is what makes the loop
        // converge instead of oscillating.
        var totalViolation: Double = 0
        var violation: [Int: Double] = [:]
        for i in items.indices where !items[i].frozen {
            let s = tree.style(items[i].node)
            let lower = resolveDimension(isRow ? s.minSize.width : s.minSize.height,
                                         against: containerMain, rootFontSize: rootFontSize)
            let upper = resolveDimension(isRow ? s.maxSize.width : s.maxSize.height,
                                         against: containerMain, rootFontSize: rootFontSize)
            // An item may never go negative, whatever its min says.
            let bounded = max(0, clamp(items[i].targetMainSize, min: lower, max: upper))
            let v = bounded - items[i].targetMainSize
            violation[i] = v
            totalViolation += v
            items[i].targetMainSize = bounded
        }

        // §9.7.4.e — freeze ONLY the items that violated, in the direction the
        // total says. Freezing everything on a nonzero violation would skip the
        // redistribution this loop exists to perform; freezing nothing would
        // never terminate. Termination holds because a nonzero total guarantees
        // at least one item violated in that direction.
        if totalViolation == 0 {
            for i in items.indices { items[i].frozen = true }
        } else if totalViolation > 0 {
            for (i, v) in violation where v > 0 { items[i].frozen = true }   // min violations
        } else {
            for (i, v) in violation where v < 0 { items[i].frozen = true }   // max violations
        }
    }
}
```

- [ ] **Step 5: Call it from `layoutContainer`**

Replace the placeholder comment in `layoutContainer`:

```swift
    var items = collectItems(tree, container, containerSize: containerSize,
                             rootFontSize: rootFontSize)
    guard !items.isEmpty else { return }

    let s = tree.style(container)
    let isRow = s.flexDirection.isRow
    let containerMain = isRow ? containerSize.width : containerSize.height
    let gap = resolveLength(isRow ? s.gap.horizontal : s.gap.vertical,
                            against: containerMain, rootFontSize: rootFontSize) ?? 0

    resolveFlexibleLengths(tree, container, items: &items, containerMain: containerMain,
                           gap: gap, isRow: isRow, rootFontSize: rootFontSize)

    positionItems(tree, container, items: items, containerOrigin: containerOrigin,
                  containerSize: containerSize, rootFontSize: rootFontSize)
```

- [ ] **Step 6: Run and iterate against the browser**

Run: `swift test --filter FreezeLoopTests`

The hand-written expectations and the WebKit comparison must **both** pass. If they disagree, **the browser is right** — that is the entire reason the oracle exists. Report both outcomes separately.

- [ ] **Step 7: Generate the new goldens and add their comparisons**

```bash
METALUI_REGENERATE_GOLDENS=1 swift test --filter regenerateAllGoldens
ls Tests/MetalUILayoutTests/Golden/
```

Then add a WebKit comparison for `flex_row_grow_uneven` and `flex_row_shrink` mirroring `growMatchesWebKitOnTheUnusedGolden`, reading via `loadGolden`.

- [ ] **Step 8: Run the whole suite**

Run: `rm -rf .build && swift test`
Expected: all pass, no warnings.

- [ ] **Step 9: Commit**

```bash
git add -A
git commit -m "feat(layout): implement CSS Flexbox 9.7 resolve-flexible-lengths"
```

- [ ] **Step 10: Prove the subtle parts are load-bearing**

Each of these must redden something. Commit first, mutate one at a time, revert, and confirm `git status --short` is empty at the end.

```bash
# 1. Drop the base-size weighting from shrink — makes shrink behave like grow.
#    Expect: shrinkIsWeightedByBaseSize and the shrink fixture comparison fail.
#    In ResolveFlexibleLengths.swift replace
#      Double(s.flexShrink) * item.baseSize
#    with
#      Double(s.flexShrink)

# 2. Stop subtracting gaps from free space.
#    Expect: gapIsRemovedFromFreeSpaceBeforeDistribution fails.
#    Replace `let totalGap = gap * Double(items.count - 1)` with `let totalGap = 0.0`

# 3. Freeze nothing on a zero violation (delete the `totalViolation == 0` branch).
#    Expect: a hang or a failure — either proves the branch is load-bearing.
#    Run with a timeout so a hang does not wedge the suite.
```

Report which tests fired for each. **If mutation 1 reddens nothing, `shrinkIsWeightedByBaseSize` is not pinning the weighting** and must be fixed before this task is done.

---

### Task 4: Automatic minimum size (`min-width: auto`)

**Files:**
- Modify: `Sources/MetalUILayout/FlexEngine.swift`
- Create: `Tests/MetalUILayoutTests/Fixtures/flex_row_explicit_min.html`
- Test: `Tests/MetalUILayoutTests/FreezeLoopTests.swift`
- Modify: `Tests/MetalUILayoutTests/GeneratorTests.swift`

**Interfaces:**
- Consumes: `flexBaseSize`, `FlexItem`, `resolveDimension`, `MeasureFunction`.
- Produces: no new symbols — `collectItems` gains the automatic-minimum-size rule.

**Spec §5.2 requires this in v1.** Without it a shrinkable item collapses to zero, which is what makes an unstyled flex row look broken.

**Read this before writing code — it is the whole subtlety of the task.**

CSS §4.5's automatic minimum size is the **content-based minimum size** — the item's *min-content* size — **not its flex base size.** The distinction decides the task:

- An **empty** `<div>` has no content, so its automatic minimum is **0**, and `flex: 0 1 300px; min-width: auto` shrinks freely. Every existing fixture in this corpus is empty divs.
- An item **with** content cannot shrink below what its content needs.

Two consequences, both load-bearing:

1. **Using the flex base size as the minimum would be wrong**, and it would break Task 3's `shrinkIsWeightedByBaseSize` — items with `basis: 200` would gain `min: 200` and stop shrinking at all. If you find yourself writing `if case .auto = minDim { return base }`, that is the bug.
2. **This rule cannot be browser-verified yet.** The browser's content size comes from real content; our engine measures nothing until the text system lands in M2. So automatic minimum size is pinned by hand-written tests with explicit measure closures, and the browser fixture in this task covers **explicit** `min-width`/`max-width` only. Say so in the code comment — a rule the corpus cannot check is exactly the kind of thing that silently rots.

- [ ] **Step 1: Write the fixture (explicit min/max only)**

`Tests/MetalUILayoutTests/Fixtures/flex_row_explicit_min.html`:

```html
<!doctype html>
<html><head><meta charset="utf-8"><style>
  * { box-sizing: border-box; margin: 0; padding: 0; border: 0; }
  body { margin: 0; }
  #root { display: flex; flex-direction: row; width: 300px; height: 40px; }
  /* Both want 250px in a 300px row. `a` may not shrink below 120, so it stops
     there and `b` absorbs the rest of the overflow. */
  .a { flex: 0 1 250px; min-width: 120px; }
  .b { flex: 0 1 250px; }
</style></head><body>
  <div id="root" data-id="root">
    <div class="a" data-id="a"></div>
    <div class="b" data-id="b"></div>
  </div>
</body></html>
```

Register it in `allFixtures` at 800×600. This exercises the freeze loop's redistribution: `a` hits its floor, freezes, and the space it could not give up moves to `b`.

- [ ] **Step 2: Write the failing tests**

Add to `Tests/MetalUILayoutTests/FreezeLoopTests.swift`:

```swift
@Test func automaticMinimumSizeUsesContentSizeNotFlexBasis() {
    // A leaf whose min-content width is 80. `min-width: auto` must resolve to
    // 80 — NOT to its 300px flex basis, which would stop it shrinking at all.
    let tree = LayoutTree()
    var s = Style()
    s.flexGrow = 0
    s.flexShrink = 1
    s.flexBasis = px(300)
    s.size = Size(width: .auto, height: px(40))
    let a = tree.newLeaf(style: s) { _, available in
        if case .minContent = available.width { return SizeD(width: 80, height: 40) }
        return SizeD(width: 300, height: 40)
    }
    let b = flexChild(tree, grow: 0, shrink: 1, basis: px(100))
    let root = row(tree, width: 200, [a, b])

    computeLayout(tree, root: root,
                  available: AvailableSpaceSize(width: .definite(800), height: .definite(600)))

    // `a` shrinks, but stops at its content-based minimum of 80.
    #expect(tree.layout(a).width == 80)
    #expect(tree.layout(a).width < 300)
}

@Test func anItemWithNoContentHasNoAutomaticMinimum() {
    // An empty box has no content, so `min-width: auto` is 0 and it shrinks
    // freely. Every fixture in the corpus is empty divs, which is why the
    // browser cannot verify the rule above.
    let tree = LayoutTree()
    let a = flexChild(tree, grow: 0, shrink: 1, basis: px(300))
    let b = flexChild(tree, grow: 0, shrink: 1, basis: px(300))
    let root = row(tree, width: 200, [a, b])

    computeLayout(tree, root: root,
                  available: AvailableSpaceSize(width: .definite(800), height: .definite(600)))

    #expect(tree.layout(a).width == 100)
    #expect(tree.layout(b).width == 100)
}

@Test func anExplicitMinSizeOverridesTheAutomaticOne() {
    let tree = LayoutTree()
    var s = Style()
    s.flexGrow = 0
    s.flexShrink = 1
    s.flexBasis = px(250)
    s.minSize = Size(width: px(120), height: .auto)
    s.size = Size(width: .auto, height: px(40))
    let a = tree.newNode(style: s, children: [])
    let b = flexChild(tree, grow: 0, shrink: 1, basis: px(250))
    let root = row(tree, width: 300, [a, b])

    computeLayout(tree, root: root,
                  available: AvailableSpaceSize(width: .definite(800), height: .definite(600)))

    // `a` floors at 120; `b` absorbs the remaining overflow.
    #expect(tree.layout(a).width == 120)
    #expect(tree.layout(b).width == 180)
}
```

- [ ] **Step 3: Run to verify they fail**

Run: `swift test --filter FreezeLoopTests`
Expected: `automaticMinimumSizeUsesContentSizeNotFlexBasis` FAILS (`a` shrinks past 80 toward 0). The other two may already pass — note which, since a test that passes before its feature exists is pinning nothing.

- [ ] **Step 4: Implement the rule in `collectItems`**

Where `minMain` is computed, replace it with:

```swift
            // CSS §4.5 automatic minimum size. `min-width: auto` on a flex item
            // resolves to its CONTENT-based minimum — the min-content size —
            // not to 0 and NOT to its flex base size. Using the base size here
            // would stop every `flex-basis` item shrinking at all.
            //
            // An item with no measure function has no content, so its automatic
            // minimum is 0 and it shrinks freely. Every fixture in this corpus
            // is empty divs, which is why this rule is pinned by hand-written
            // tests with measure closures rather than by the browser: WebKit's
            // content size comes from real content, and nothing here measures
            // any until the text system lands.
            let minDim = isRow ? ks.minSize.width : ks.minSize.height
            let minMain: Double? = {
                if case .auto = minDim {
                    guard let measure = tree.measure(kid) else { return nil }
                    let probe = measure(.unspecified,
                                        AvailableSpaceSize(width: isRow ? .minContent : .maxContent,
                                                           height: isRow ? .maxContent : .minContent))
                    return isRow ? probe.width : probe.height
                }
                return resolveDimension(minDim, against: containerMain, rootFontSize: rootFontSize)
            }()
```

- [ ] **Step 5: Run the whole suite**

Run: `swift test`
Expected: all pass, **including Task 3's `shrinkIsWeightedByBaseSize`**. If that test now fails, the automatic minimum is being taken from the flex base size — re-read the note above.

- [ ] **Step 6: Generate the golden and compare**

```bash
METALUI_REGENERATE_GOLDENS=1 swift test --filter regenerateAllGoldens
```

Add a WebKit comparison for `flex_row_explicit_min` via `loadGolden`.

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "feat(layout): resolve min-width auto to the content-based minimum"
```

- [ ] **Step 8: Prove it can fail**

Three mutations, each after a commit, each reverted with `git status --short` verified empty:

```bash
# 1. Resolve automatic min to 0 instead of the content size.
#    Replace the `guard let measure` block with `return nil`.
#    Expect: automaticMinimumSizeUsesContentSizeNotFlexBasis fails.

# 2. Resolve automatic min to the flex base size — the tempting wrong answer.
#    Replace the block with `return base`.
#    Expect: shrinkIsWeightedByBaseSize AND anItemWithNoContentHasNoAutomaticMinimum
#            both fail. This is the cross-task conflict; if neither fires, the
#            Task 3 tests are not pinning shrink.

# 3. Probe at max-content instead of min-content.
#    Expect: automaticMinimumSizeUsesContentSizeNotFlexBasis fails (gets 300, not 80).
```

Report which tests fired for each.

## Exit criteria

- [ ] `swift test` passes, no warnings; `rm -rf .build && swift build` clean
- [ ] `MetalUILayout` imports only `MetalUICore`
- [ ] `flex_row_fixed_and_grow.json` — committed since M1a and never compared — is now read by an engine test
- [ ] Every new golden is browser-generated, and regenerating leaves `git status` clean
- [ ] Each of these mutations reddens at least one test: removing the rounding pass; positioning relative instead of absolute; reordering the §9.2 cascade; removing shrink's base-size weighting; not subtracting gaps from free space; resolving `min-width: auto` to 0
- [ ] `docs/CLAUDE.md`'s inert-API table has had `flexGrow`, `flexShrink`, `flexBasis` and `roundLayout` **removed**, since they are now live

## Deliberately NOT in this plan

Each needs its own fixtures and its own review:

- **Alignment** — `justify-content`, `align-items`, `align-self`, `align-content`. **Its first test must be the one M1a's review specified:** make `layoutContainer` return its final cursor and assert a 3×50 row with `gap: 12` reports **174, not 186**. That pins the trailing-gap fix, which today has no killing test because nothing reads the cursor.
- **Multi-line** — `flex-wrap`, line collection, cross-axis stacking.
- **The box model** — wiring `resolveEdges` into the engine. Currently a documented silent gap.
- **Reverse directions** — still silently laying out forward.
- **Absolute positioning**, **aspect ratio**, **`MeasureCache`**, **Grid**.

## Risks carried in from M1a

- **`LayoutNodeID` has no generation counter** (ruling C-3). A stale ID after `reset()` traps safely if the new tree is smaller but **silently addresses a different node** if larger. Nothing calls `reset()` mid-flight yet. If this plan introduces a caller, close the hazard first.
- **Two guarantees lapse under plausible CI configurations** — the ABI probe skips without a Metal device, and `committedGoldensMatchTheBrowser` is the only live-WebKit consumer. Both must be required, non-gateable jobs when CI lands.
