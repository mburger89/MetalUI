# Stack Container Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A `Stack` container that layers its children at the same position, sizing to its largest child on each axis.

**Architecture:** `Display` gains a `.stack` case — the same place CSS puts the decision. `layOutChildren` branches on it and returns items in a new `stackItems` field instead of `lines`; `placeNode` branches to a new `positionStackItems` that aligns each child independently on both axes. The `Stack` element translates a single SwiftUI-style `Alignment` into the substrate's `alignItems` and a new `justifyItems`.

**Tech Stack:** Swift 6.3 (`swiftLanguageModes: [.v6]`, strict concurrency), swift-testing (`@Test`/`#expect`/`#require`), WKWebView layout oracle.

**Spec:** `docs/superpowers/specs/2026-08-28-stack-container-design.md`

## Global Constraints

- **`MetalUILayout` must import only `MetalUICore`.** Verify with an anchored pattern — an unanchored `Metal` also matches the legitimate `import MetalUICore`.
- **No existing golden may move.** 67 fixtures in `Tests/MetalUILayoutTests/Golden/` are downstream of `layOutChildren`, which this plan modifies. **A moved golden means STOP and report** — it means the stack path perturbed the flex path.
- **Read the test-run summary line, never the exit status.** `swift test --no-parallel 2>&1 | grep -E "Test run with"`. A run can die with no summary line and still exit 0 — that is a failed run. Baseline at plan start: **504 tests**.
- **Any count a later loop indexes on must be `try #require`, not `#expect`.**
- Build warning-free: `swift build 2>&1 | grep -cE "error:|warning:"` returns 0.
- **Comments explain mechanism, not milestones.** "Arrives in M5" is a defect; "needs X, which does not exist because Y" is correct.
- **SwiftUI is the design authority, CSS the substrate** (ruling EP-5). Where they differ, take SwiftUI's answer and record the divergence.
- **Read `docs/practices/verifying-tests-can-fail.md` before writing tests.** Thirteen shapes of test that cannot fail, all observed in this repo.

---

### Task 1: The probe, and two declarations with no reader

**Files:**
- Modify: `Sources/MetalUILayout/Style.swift`
- Test: `Tests/MetalUILayoutTests/StackLayoutTests.swift` (create)

**Interfaces:**
- Consumes: nothing.
- Produces: `Display.stack`, `JustifyItems`, `Style.justifyItems`. Task 2 reads them.

**Why this task exists in this shape.** Spec §3.4 records an *expectation* about percentage-sized children that could not be probed while writing the spec, because the path did not exist. It is probed here, before anything is built on it. This project's most expensive recent mistake was a ruling made on a claim about engine behaviour that was never measured.

- [ ] **Step 1: Probe the percentage question against the real engine**

Create a throwaway file `Tests/MetalUILayoutTests/ZZProbe.swift`:

```swift
import Testing
import MetalUICore
@testable import MetalUILayout

// THROWAWAY probe for the Stack spec §3.4. Deleted in Step 3.
@Test func zzPercentChildProbe() {
    let tree = LayoutTree(generation: 0)

    // A 50%-wide child alongside a fixed 80x30 one, in a FLEX container with no
    // definite width — the same shape a stack will have. What we need to know is
    // what the percentage child contributes to the container's measured size.
    var pct = Style()
    pct.size = Size(width: .length(.percent(0.5)), height: .length(.pixels(Pixels(20))))
    let pctNode = tree.newNode(style: pct, children: [])

    var fixed = Style()
    fixed.size = Size(width: .length(.pixels(Pixels(80))),
                      height: .length(.pixels(Pixels(30))))
    let fixedNode = tree.newNode(style: fixed, children: [])

    var container = Style()
    container.flexDirection = .row
    let node = tree.newNode(style: container, children: [pctNode, fixedNode])

    // Measure with an INDEFINITE width — the intrinsic pass.
    let ctx = LayoutContext(rootFontSize: 16)
    let measured = measureNode(ctx, tree, node, known: .unspecified,
                               available: AvailableSpaceSize(width: .maxContent,
                                                             height: .maxContent),
                               containingBlockWidth: nil)
    print("PROBE measured (indefinite):", measured)

    // And with a definite one — the placement pass.
    computeLayout(tree, root: node,
                  available: AvailableSpaceSize(width: .definite(200), height: .definite(100)))
    print("PROBE container:", tree.layout(node))
    print("PROBE pct child:", tree.layout(pctNode))
    print("PROBE fixed child:", tree.layout(fixedNode))
}
```

- [ ] **Step 2: Run it and record the numbers**

Run: `swift test --no-parallel --filter zzPercentChildProbe 2>&1 | grep -E "PROBE|error:"`

If the API shapes differ from the above, fix the probe by reading a working call site (`grep -n "measureNode(ctx" Tests/MetalUILayoutTests/*.swift`) rather than guessing. **Write every printed number into your report**, and into spec §3.4 replacing its "expectation, not a measurement" paragraph with what you measured.

The question being answered: **does a percentage child contribute its resolved width, its `auto` width, or zero, when the container's own width is indefinite?** Whatever the answer, it is now a measured fact and Task 2 is built on it.

- [ ] **Step 3: Delete the probe**

```bash
rm Tests/MetalUILayoutTests/ZZProbe.swift
```

Confirm `git status --short` shows it gone.

- [ ] **Step 4: Add the two declarations**

In `Sources/MetalUILayout/Style.swift`, line 3 currently reads:

```swift
public enum Display: Sendable, Equatable { case flex, none }
```

Replace with:

```swift
/// How a container lays its children out.
///
/// `.stack` layers every child at the same position and sizes the container to
/// the largest of them on each axis — CSS's one-cell grid, SwiftUI's `ZStack`.
/// It reads neither `flexDirection` nor any flex property on its children;
/// `flexGrow`, `flexShrink` and `flexBasis` are flex-container properties and a
/// stack ignores them, as CSS does.
public enum Display: Sendable, Equatable { case flex, stack, none }
```

Add beside `AlignItems` (around line 17):

```swift
/// Inline-axis alignment of each item within its own area — CSS's
/// `justify-items`.
///
/// **Read only by the stack path**, and that is not a declared-but-inert entry:
/// it has a production reader. It is also what CSS does — `justify-items` has no
/// effect on a flex container there either, so the inertness belongs to the
/// model rather than to this implementation. Do not add it to CLAUDE.md's table.
///
/// Four cases rather than CSS's full set: `start`/`end` instead of
/// `flexStart`/`flexEnd` because a stack has no flex-relative axis to be the
/// start of, and no `baseline` because `AlignItems.baseline` is itself
/// unimplemented and falls back to `flexStart` (CLAUDE.md's inert table). Adding
/// a case later is additive.
public enum JustifyItems: Sendable, Equatable { case start, center, end, stretch }
```

And the stored property, beside `alignItems`:

```swift
    /// `nil` means CSS's `stretch`, matching `alignItems`'s convention. See
    /// ``JustifyItems``.
    public var justifyItems: JustifyItems? = nil
```

- [ ] **Step 5: Write the test that the new cases change nothing yet**

Create `Tests/MetalUILayoutTests/StackLayoutTests.swift`:

```swift
import Testing
import MetalUICore
@testable import MetalUILayout

/// `Display.stack` exists and is inert until Task 2 gives it a reader.
///
/// This test is deliberately weak and is deleted in Task 2 — its only job is to
/// prove the enum gained a case without disturbing the flex path, so that a
/// golden moving in Task 2 is unambiguously Task 2's doing.
@Test func displayStackIsDeclaredAndNotYetRead() {
    let tree = LayoutTree(generation: 0)
    var kid = Style()
    kid.size = Size(width: .length(.pixels(Pixels(40))),
                    height: .length(.pixels(Pixels(20))))
    let child = tree.newNode(style: kid, children: [])

    var s = Style()
    s.display = .stack           // set, and read by nothing yet
    s.flexDirection = .row
    let node = tree.newNode(style: s, children: [child])

    computeLayout(tree, root: node,
                  available: AvailableSpaceSize(width: .definite(100),
                                                height: .definite(50)))
    // Still laid out as a flex row, because nothing reads `.stack` yet.
    #expect(tree.layout(child).width == 40)
    #expect(tree.layout(child).height == 20)
}

/// `justifyItems` defaults to `nil` and is read by nothing yet.
@Test func justifyItemsDefaultsToNil() {
    #expect(Style().justifyItems == nil)
}
```

- [ ] **Step 6: Run the whole suite**

Run: `swift test --no-parallel 2>&1 | grep -E "error:|warning:|Test run with"`
Expected: `Test run with 506 tests in 0 suites passed` (504 + 2).

**If any golden moved, STOP and report** — adding an unread enum case cannot move a golden, so it would mean something else changed.

- [ ] **Step 7: Commit**

```bash
git add Sources/MetalUILayout/Style.swift Tests/MetalUILayoutTests/StackLayoutTests.swift docs/superpowers/specs/2026-08-28-stack-container-design.md
git commit -m "feat: declare Display.stack and Style.justifyItems, and measure the percentage question

Both are inert -- no reader until the next task -- so a golden moving
later is unambiguously that task's doing.

Spec 3.4 recorded an EXPECTATION about percentage-sized children that
could not be probed when it was written, because the path did not exist.
It is measured now, before anything is built on it, and the spec carries
the numbers instead of the expectation."
```

---

### Task 2: The stack path in `layOutChildren`

**Files:**
- Modify: `Sources/MetalUILayout/FlexEngine.swift`
- Test: `Tests/MetalUILayoutTests/StackLayoutTests.swift`

**Interfaces:**
- Consumes: `Display.stack` (Task 1).
- Produces:
  ```swift
  struct StackItem { let node: LayoutNodeID; var size: SizeD }
  // ContainerLayout gains:
  var stackItems: [StackItem]     // empty for a flex container
  ```
  Task 3 positions them.

**Context you need.** `layOutChildren` (`FlexEngine.swift:592`) returns a `ContainerLayout` with `lines: [FlexLine]`, `contentSize: SizeD`, `edges: SizeD`, and `box: (origin:, size:)`. Both `measureNode` and `placeNode` call it. `contentSize` is the container's **content** box measured from the items; `edges` is padding + border; `contentSize + edges` is what `measureNode` reports.

**Why a separate field rather than reusing `FlexLine`/`FlexItem`.** `FlexItem` carries eleven fields — `baseSize`, `hypotheticalMainSize`, `minMain`, `maxMain`, `targetMainSize`, `frozen` and more — and eight of them are meaningless for a stack, which has no main axis and never flexes. Reusing it would require a convention ("a stack writes width into `targetMainSize`") that a future reader would misread as flex semantics. `stackItems` is empty for a flex container and `lines` is empty for a stack; each is honest about what it holds.

- [ ] **Step 1: Write the failing tests**

Replace the two placeholder tests in `Tests/MetalUILayoutTests/StackLayoutTests.swift` (Task 1's, which said `.stack` was unread) with:

```swift
private func px(_ v: Double) -> MetalUICore.Dimension { .length(.pixels(Pixels(Float(v)))) }

private func sized(_ tree: LayoutTree, _ w: Double, _ h: Double) -> LayoutNodeID {
    var s = Style()
    s.size = Size(width: px(w), height: px(h))
    return tree.newNode(style: s, children: [])
}

private func stack(_ tree: LayoutTree, _ children: [LayoutNodeID],
                   align: AlignItems? = .center,
                   justify: JustifyItems? = .center) -> LayoutNodeID {
    var s = Style()
    s.display = .stack
    s.alignItems = align
    s.justifyItems = justify
    return tree.newNode(style: s, children: children)
}

/// A stack sizes to the LARGEST child on each axis, independently.
///
/// **Three children of three different sizes, and the winner differs per axis.**
/// A stack that returned its first child, its last child, or the child that won
/// the other axis would all give a different answer here. With uniform children
/// none of those could be told apart — the corpus-uniformity hazard that hid
/// divergence 6 for four milestones.
@Test func aStackSizesToItsLargestChildOnEachAxisIndependently() {
    let tree = LayoutTree(generation: 0)
    let wide  = sized(tree, 90, 10)   // widest, shortest
    let tall  = sized(tree, 20, 70)   // narrowest, tallest
    let mid   = sized(tree, 50, 40)
    let node = stack(tree, [wide, tall, mid])

    let ctx = LayoutContext(rootFontSize: 16)
    let measured = measureNode(ctx, tree, node, known: .unspecified,
                               available: AvailableSpaceSize(width: .maxContent,
                                                             height: .maxContent),
                               containingBlockWidth: nil)
    #expect(measured.width == 90, "widest child is 90")
    #expect(measured.height == 70, "tallest child is 70 — a DIFFERENT child")
}

/// Every child keeps its own size; none is stretched, and none is flexed.
@Test func aStackDoesNotResizeItsChildren() {
    let tree = LayoutTree(generation: 0)
    let a = sized(tree, 90, 10)
    let b = sized(tree, 20, 70)
    let node = stack(tree, [a, b])

    computeLayout(tree, root: node,
                  available: AvailableSpaceSize(width: .definite(200),
                                                height: .definite(200)))
    #expect(tree.layout(a).width == 90)
    #expect(tree.layout(a).height == 10)
    #expect(tree.layout(b).width == 20)
    #expect(tree.layout(b).height == 70)
}

/// A stack ignores `flexGrow` — it is a flex-container property and there is no
/// main axis to grow along. Without this, a child with `flexGrow(1)` inside a
/// stack would silently take the container's whole width and nothing would say why.
@Test func aStackIgnoresFlexGrowOnItsChildren() {
    let tree = LayoutTree(generation: 0)
    var greedy = Style()
    greedy.size = Size(width: px(30), height: px(30))
    greedy.flexGrow = 1
    let a = tree.newNode(style: greedy, children: [])
    let node = stack(tree, [a])

    computeLayout(tree, root: node,
                  available: AvailableSpaceSize(width: .definite(300),
                                                height: .definite(300)))
    #expect(tree.layout(a).width == 30, "flexGrow must not stretch a stack child")
}

/// An empty stack is 0x0, like a childless Box.
@Test func anEmptyStackMeasuresZero() {
    let tree = LayoutTree(generation: 0)
    let node = stack(tree, [])
    let ctx = LayoutContext(rootFontSize: 16)
    let measured = measureNode(ctx, tree, node, known: .unspecified,
                               available: AvailableSpaceSize(width: .maxContent,
                                                             height: .maxContent),
                               containingBlockWidth: nil)
    #expect(measured.width == 0)
    #expect(measured.height == 0)
}

/// Padding and border are added back exactly as they are for a flex container —
/// the stack path shares `contentBox` and the `edges` bookkeeping.
@Test func aStacksPaddingIsAddedToItsMeasuredSize() {
    let tree = LayoutTree(generation: 0)
    let kid = sized(tree, 40, 20)
    var s = Style()
    s.display = .stack
    s.padding = Edges(all: .pixels(Pixels(7)))
    let node = tree.newNode(style: s, children: [kid])

    let ctx = LayoutContext(rootFontSize: 16)
    let measured = measureNode(ctx, tree, node, known: .unspecified,
                               available: AvailableSpaceSize(width: .maxContent,
                                                             height: .maxContent),
                               containingBlockWidth: nil)
    #expect(measured.width == 54, "40 + 7 + 7")
    #expect(measured.height == 34, "20 + 7 + 7")
}
```

- [ ] **Step 2: Run to verify they fail**

Run: `swift test --no-parallel --filter StackLayoutTests 2>&1 | grep -E "recorded an issue|Test run with"`
Expected: the sizing tests fail — `.stack` still lays out as flex, so a row of 90+20+50 measures 160 wide rather than 90.

- [ ] **Step 3: Add `StackItem` and the `ContainerLayout` field**

In `Sources/MetalUILayout/FlexEngine.swift`, beside `ContainerLayout` (line ~530):

```swift
/// One child of a `.stack` container, at its own size.
///
/// Deliberately NOT a `FlexItem`: eight of that type's eleven fields —
/// `baseSize`, `hypotheticalMainSize`, `minMain`, `maxMain`, `targetMainSize`,
/// `frozen` among them — are meaningless here, because a stack has no main axis
/// and never runs §9.7. Reusing it would need a convention ("width goes in
/// `targetMainSize`") that reads as flex semantics to anyone who did not write it.
struct StackItem {
    let node: LayoutNodeID
    var size: SizeD
}
```

Add to `ContainerLayout`:

```swift
    /// The children of a `.stack` container, each at its own size.
    ///
    /// Empty for a flex container, exactly as `lines` is empty for a stack.
    /// Each field is honest about what it holds rather than one field carrying
    /// two meanings.
    var stackItems: [StackItem]
```

Every existing `ContainerLayout(...)` construction now needs `stackItems: []`. Find them with `grep -n "ContainerLayout(" Sources/MetalUILayout/FlexEngine.swift`.

- [ ] **Step 4: Branch `layOutChildren` on `display`**

Near the top of `layOutChildren`, after the content box is computed and before the flex-specific work begins, add the stack branch. Read the existing code to find where `contentBox` has been computed and `edges` is known — the branch goes there, so padding/border handling stays shared.

```swift
    if s.display == .stack {
        return layOutStack(ctx, tree, container, box: box, edges: edges,
                           intrinsic: intrinsic,
                           containingBlockWidth: containingBlockWidth)
    }
```

Then add the function:

```swift
/// A `.stack` container: every child at its own size, the container at the
/// maximum of them on each axis.
///
/// **No main axis, so no §9.7.** There is no flex base size, no freeze loop, no
/// line breaking and no distribution — each child is measured once against the
/// space the stack itself was offered, and the container reports the largest.
private func layOutStack(
    _ ctx: LayoutContext,
    _ tree: LayoutTree,
    _ container: LayoutNodeID,
    box: (origin: (Double, Double), size: SizeD),
    edges: SizeD,
    intrinsic: IntrinsicQuery,
    containingBlockWidth: Double?
) -> ContainerLayout {
    var items: [StackItem] = []
    var maxWidth = 0.0
    var maxHeight = 0.0

    for kid in tree.children(container) where tree.style(kid).display != .none {
        let size = measureNode(ctx, tree, kid,
                               known: .unspecified,
                               available: AvailableSpaceSize(
                                   width: .definite(box.size.width),
                                   height: .definite(box.size.height)),
                               containingBlockWidth: box.size.width)
        items.append(StackItem(node: kid, size: size))
        maxWidth = max(maxWidth, size.width)
        maxHeight = max(maxHeight, size.height)
    }

    return ContainerLayout(lines: [],
                           contentSize: SizeD(width: maxWidth, height: maxHeight),
                           edges: edges,
                           box: box,
                           stackItems: items)
}
```

**Adjust the `available:` and `containingBlockWidth:` arguments above to match what Task 1's probe measured.** The probe answered what a percentage child does under an indefinite container; if the measured behaviour contradicts passing `.definite(box.size.width)` here, use what the probe showed and say so in your report. Do not preserve this code against a measurement.

Also verify `tree.children(_:)` is the accessor's real name — `grep -n "func children" Sources/MetalUILayout/LayoutTree.swift`.

- [ ] **Step 5: Run the whole suite**

Run: `swift test --no-parallel 2>&1 | grep -E "error:|warning:|Test run with"`
Expected: `Test run with 509 tests in 0 suites passed` (506 − 2 deleted placeholders + 5 new).

**If any of the 67 goldens moved, STOP and report.** The flex path must be untouched.

- [ ] **Step 6: Measure the mutations**

Each against the FULL suite, reddened test **names** recorded — never only a count — then reverted:

1. `maxHeight = max(maxHeight, size.width)` (wrong axis) → expect `aStackSizesToItsLargestChildOnEachAxisIndependently`.
2. Return `contentSize` from the *first* item rather than the max → expect the same test.
3. Delete the `where tree.style(kid).display != .none` filter and add a `.none` child to one test → **if nothing reddens, that filter is unguarded**; add a test rather than banking a gap.

- [ ] **Step 7: Commit**

```bash
git add Sources/MetalUILayout/FlexEngine.swift Tests/MetalUILayoutTests/StackLayoutTests.swift
git commit -m "feat: a stack layout path — one pass, max over children, no flexing

layOutChildren branches on display and returns stackItems instead of
lines. StackItem is deliberately not a FlexItem: eight of that type's
eleven fields are meaningless without a main axis, and reusing it would
need a convention that reads as flex semantics to the next reader."
```

---

### Task 3: `positionStackItems` — all nine alignments

**Files:**
- Modify: `Sources/MetalUILayout/FlexEngine.swift` (`placeNode`, plus the new function)
- Test: `Tests/MetalUILayoutTests/StackLayoutTests.swift`

**Interfaces:**
- Consumes: `StackItem`, `ContainerLayout.stackItems` (Task 2).
- Produces: placed rects for stack children. Task 4's fixtures compare them against WebKit.

**Context.** `placeNode` (`FlexEngine.swift:876`) calls `layOutChildren`, computes `childOrigin` as the container's origin plus `laid.box.origin`, then loops `laid.lines` calling `positionItems`. `positionItems` is `private` at line 1525 and takes `(ctx, tree, container, items:, lineCross:, lineCrossStart:, containerOrigin:, containerSize:)`.

- [ ] **Step 1: Write the failing tests**

Append to `Tests/MetalUILayoutTests/StackLayoutTests.swift`:

```swift
/// All nine alignments, each at a distinct position.
///
/// **The geometry is chosen so no two alignments coincide.** A 100x60 stack
/// holding one 20x10 child leaves 80 of horizontal slack and 50 of vertical:
/// start 0, centre 40, end 80 across; start 0, centre 25, end 50 down. Nine
/// distinct (x, y) pairs. A fixture where the child filled the container, or
/// where the slack were zero on an axis, could not tell centre from start —
/// which is the corpus-uniformity hazard this repo has been bitten by three times.
@Test func allNineAlignmentsPlaceTheChildAtNineDistinctPositions() throws {
    // (alignItems = block/vertical, justifyItems = inline/horizontal, x, y)
    let cases: [(AlignItems, JustifyItems, Double, Double)] = [
        (.flexStart, .start,  0,  0), (.flexStart, .center, 40,  0), (.flexStart, .end, 80,  0),
        (.center,    .start,  0, 25), (.center,    .center, 40, 25), (.center,    .end, 80, 25),
        (.flexEnd,   .start,  0, 50), (.flexEnd,   .center, 40, 50), (.flexEnd,   .end, 80, 50),
    ]
    var seen: Set<String> = []
    for (align, justify, x, y) in cases {
        let tree = LayoutTree(generation: 0)
        let kid = sized(tree, 20, 10)
        let node = stack(tree, [kid], align: align, justify: justify)
        computeLayout(tree, root: node,
                      available: AvailableSpaceSize(width: .definite(100),
                                                    height: .definite(60)))
        let r = tree.layout(kid)
        #expect(r.x == x, "\(align)/\(justify) x")
        #expect(r.y == y, "\(align)/\(justify) y")
        seen.insert("\(r.x),\(r.y)")
    }
    try #require(seen.count == 9, "all nine must be distinct, got \(seen.count): \(seen)")
}

/// `stretch` fills the container on that axis — the CSS default this framework
/// deliberately does NOT take for `Stack`, kept reachable through `Style`.
@Test func stretchFillsTheContainerOnThatAxis() {
    let tree = LayoutTree(generation: 0)
    let kid = sized(tree, 20, 10)
    let node = stack(tree, [kid], align: .stretch, justify: .stretch)
    computeLayout(tree, root: node,
                  available: AvailableSpaceSize(width: .definite(100),
                                                height: .definite(60)))
    let r = tree.layout(kid)
    #expect(r.width == 100)
    #expect(r.height == 60)
    #expect(r.x == 0)
    #expect(r.y == 0)
}

/// Children overlap: two children at the same alignment share an origin.
/// This is the property the container exists for, and nothing else asserts it.
@Test func twoChildrenAtTheSameAlignmentShareAnOrigin() {
    let tree = LayoutTree(generation: 0)
    let a = sized(tree, 40, 20)
    let b = sized(tree, 60, 30)
    let node = stack(tree, [a, b], align: .center, justify: .center)
    computeLayout(tree, root: node,
                  available: AvailableSpaceSize(width: .definite(100),
                                                height: .definite(100)))
    // Centred independently, so their origins differ by half the size difference
    // rather than being sequenced — 40 wide centres at 30, 60 wide at 20.
    #expect(tree.layout(a).x == 30)
    #expect(tree.layout(b).x == 20)
    #expect(tree.layout(a).y == 40)
    #expect(tree.layout(b).y == 35)
}

/// A stack's padding offsets its children, and alignment is measured inside the
/// CONTENT box — not the border box. Getting this wrong puts `.start` at the
/// padding edge on one axis and the border edge on the other, which reads as an
/// off-by-a-few rather than as a wrong box.
@Test func alignmentIsMeasuredInsideTheContentBox() {
    let tree = LayoutTree(generation: 0)
    let kid = sized(tree, 20, 10)
    var s = Style()
    s.display = .stack
    s.alignItems = .flexEnd
    s.justifyItems = .end
    s.padding = Edges(all: .pixels(Pixels(10)))
    let node = tree.newNode(style: s, children: [kid])
    computeLayout(tree, root: node,
                  available: AvailableSpaceSize(width: .definite(100),
                                                height: .definite(60)))
    let r = tree.layout(kid)
    #expect(r.x == 70, "100 - 10 padding - 20 wide")
    #expect(r.y == 40, "60 - 10 padding - 10 tall")
}
```

- [ ] **Step 2: Run to verify they fail**

Run: `swift test --no-parallel --filter StackLayoutTests 2>&1 | grep -E "recorded an issue|Test run with"`
Expected: the alignment tests fail — nothing positions stack items yet, so children sit at the origin or are unplaced.

- [ ] **Step 3: Branch `placeNode`**

In `placeNode`, replace the `for line in laid.lines` loop with:

```swift
    if tree.style(node).display == .stack {
        positionStackItems(ctx, tree, node, items: laid.stackItems,
                           containerOrigin: childOrigin,
                           containerSize: laid.box.size,
                           containingBlockWidth: containingBlockWidth)
    } else {
        for line in laid.lines {
            // ... existing positionItems call, unchanged ...
        }
    }
```

- [ ] **Step 4: Implement `positionStackItems`**

```swift
/// Places a `.stack` container's children, each aligned independently on both
/// axes within the container's content box.
///
/// **A separate function rather than a branch inside `positionItems`.** That one
/// is dense with flex-specific work — `justifyContent` distribution, gap
/// arithmetic, `wrap-reverse`'s cross-axis flip and §9.4.2's flex-relative
/// start/end mapping — none of which a stack has. Sharing it would mean
/// threading a "there is no main axis" flag through all of it.
///
/// `alignItems` is the block (vertical) axis and `justifyItems` the inline
/// (horizontal) one, unconditionally: a stack does not read `flexDirection`, so
/// there is no axis swap to apply.
private func positionStackItems(
    _ ctx: LayoutContext,
    _ tree: LayoutTree,
    _ container: LayoutNodeID,
    items: [StackItem],
    containerOrigin: (Double, Double),
    containerSize: SizeD,
    containingBlockWidth: Double?
) {
    let s = tree.style(container)
    // `nil` reads as CSS's `stretch` on both axes, matching `alignItems`'s
    // existing convention. `Stack.init` always writes an explicit value; a
    // hand-built `Style` may not.
    let vertical = s.alignItems ?? .stretch
    let horizontal = s.justifyItems ?? .stretch

    for item in items {
        var size = item.size
        if horizontal == .stretch { size.width = containerSize.width }
        if vertical == .stretch { size.height = containerSize.height }

        let x: Double
        switch horizontal {
        case .start, .stretch: x = 0
        case .center:          x = (containerSize.width - size.width) / 2
        case .end:             x = containerSize.width - size.width
        }

        let y: Double
        switch vertical {
        case .flexStart, .stretch: y = 0
        case .center:              y = (containerSize.height - size.height) / 2
        case .flexEnd:             y = containerSize.height - size.height
        // `baseline` falls back to the start edge, exactly as it does in
        // `crossAxisOffset` — the engine cannot see an item's baseline at all,
        // because a `MeasureFunction` returns a `SizeD`. See CLAUDE.md's inert
        // table row for what is missing.
        case .baseline:            y = 0
        }

        placeNode(ctx, tree, item.node,
                  origin: (containerOrigin.0 + x, containerOrigin.1 + y),
                  size: size,
                  containingBlockWidth: containingBlockWidth)
    }
}
```

- [ ] **Step 5: Run the whole suite**

Run: `swift test --no-parallel 2>&1 | grep -E "error:|warning:|Test run with"`
Expected: `Test run with 513 tests in 0 suites passed` (509 + 4).

**If any golden moved, STOP and report.**

- [ ] **Step 6: Measure the mutations**

1. Swap `alignItems` and `justifyItems` (vertical reads `justifyItems`) → expect the nine-alignment test. **This is the mutation that matters**: with a square container and a square child the swap is invisible, which is why the fixture is 100×60 with a 20×10 child.
2. `x = containerSize.width - size.width` for `.center` → expect the nine-alignment test.
3. Drop the `stretch` size assignment (keep the origin logic) → expect `stretchFillsTheContainerOnThatAxis`.
4. Use `laid.contentSize` instead of `laid.box.size` as `containerSize` → expect `allNineAlignmentsPlaceTheChildAtNineDistinctPositions`, because the content size is the child's own extent and every alignment would collapse to 0. **If this reddens nothing, the container-vs-content distinction is unguarded.**

- [ ] **Step 7: Commit**

```bash
git add Sources/MetalUILayout/FlexEngine.swift Tests/MetalUILayoutTests/StackLayoutTests.swift
git commit -m "feat: positionStackItems, all nine alignments

Each child aligned independently on both axes inside the content box.
Separate from positionItems, which is dense with flex-only work a stack
has none of. The nine-position fixture is 100x60 holding 20x10 so that no
two alignments coincide -- a square fixture cannot tell a swapped axis
from a correct one."
```

---

### Task 4: Browser fixtures — CSS grid one-cell as the oracle

**Files:**
- Create: `Tests/MetalUILayoutTests/Fixtures/stack_alignment_center.html`
- Create: `Tests/MetalUILayoutTests/Fixtures/stack_alignment_topleading.html`
- Create: `Tests/MetalUILayoutTests/Fixtures/stack_alignment_bottomtrailing.html`
- Create: `Tests/MetalUILayoutTests/Fixtures/stack_sizes_to_largest.html`
- Create: `Tests/MetalUILayoutTests/Fixtures/stack_stretch.html`
- Create: `Tests/MetalUILayoutTests/StackFixtureTests.swift`
- Goldens generated into `Tests/MetalUILayoutTests/Golden/`

**Interfaces:**
- Consumes: the stack path (Tasks 2-3).
- Produces: five new goldens. Task 6 adds nesting fixtures.

**Context.** There is **no CSS parser**. A fixture test hand-builds the Swift tree and compares it against a golden JSON that WebKit produced from the HTML. Read `Tests/MetalUILayoutTests/FitContentFixtureTests.swift` for the idiom, and `Tests/MetalUILayoutTests/GeneratorTests.swift` for how goldens are regenerated.

**The oracle's shape**, and every fixture must use it:

```css
#root { display: grid; justify-items: center; align-items: center; }
#root > div { grid-area: 1 / 1; }
```

**`justify-items` and `align-items` must be stated explicitly in every fixture.** CSS grid defaults both to `stretch`; `Stack` defaults to centre (SwiftUI's answer, spec §2). A fixture that omits them measures stretch and will disagree with the engine — and it will read as an engine bug rather than a fixture bug.

- [ ] **Step 1: Write the fixtures**

`stack_sizes_to_largest.html` — the one that proves max-over-children, with a different winner per axis:

```html
<!DOCTYPE html>
<html><head><style>
  body { margin: 0; }
  /* A stack: one grid cell, every child in it.
     `justify-items`/`align-items` are stated because grid defaults to stretch
     and this framework's Stack centres (SwiftUI's answer, spec §2). */
  #root { display: grid; justify-items: center; align-items: center;
          width: 300px; height: 200px; }
  #root > div { grid-area: 1 / 1; }
  .wide { width: 90px;  height: 10px; }
  .tall { width: 20px;  height: 70px; }
  .mid  { width: 50px;  height: 40px; }
</style></head><body>
  <div id="root">
    <div class="wide"></div>
    <div class="tall"></div>
    <div class="mid"></div>
  </div>
</body></html>
```

The other four follow the same shape:
- `stack_alignment_center.html` — `justify-items: center; align-items: center`, root 300×200, one 20×10 child.
- `stack_alignment_topleading.html` — `justify-items: start; align-items: start`, same geometry.
- `stack_alignment_bottomtrailing.html` — `justify-items: end; align-items: end`, same geometry.
- `stack_stretch.html` — `justify-items: stretch; align-items: stretch`, same geometry.

**The three alignment fixtures share geometry deliberately**: same root, same child, three alignments, three different answers. That is what makes them a differential rather than three unrelated numbers.

- [ ] **Step 2: Generate the goldens against live WebKit**

Read `GeneratorTests.swift` for the regeneration entry point — there is a deliberately-disabled `regenerateAllGoldens` test. Follow whatever mechanism it documents; do not hand-write a golden file.

**Expected: they match the engine on first generation.** If any disagrees, **STOP and report the disagreement with both numbers** — do not adjust the fixture until it matches. A disagreement here is either a real engine bug or a real CSS misunderstanding, and both are worth more than a green test.

- [ ] **Step 3: Write the fixture tests**

Create `Tests/MetalUILayoutTests/StackFixtureTests.swift`, hand-building each tree and calling the same `assertMatchesGolden` helper the other fixture tests use. Head the file with:

```swift
/// **The oracle is CSS grid's one-cell layout**, not a stack — because CSS has
/// no stack. `display: grid` with every child at `grid-area: 1 / 1` sizes the
/// container to the largest item and overlaps them all, which is exactly what
/// `Display.stack` must do.
///
/// **Nothing checks that the HTML and the Swift tree describe the same layout.**
/// That is true of all 67 fixtures here, but flex-HTML against flex-`Style` is a
/// small conceptual gap and grid-HTML against stack-`Style` is a larger one: a
/// reader has to know the two are *intended* to be equivalent. They are, and the
/// mapping is: `display: grid` + `grid-area: 1/1` on every child ⇒
/// `display: .stack`; `justify-items` ⇒ `justifyItems`; `align-items` ⇒
/// `alignItems`.
///
/// **Every fixture states `justify-items` and `align-items` explicitly**, because
/// grid defaults both to `stretch` while `Stack` centres (spec §2). A fixture
/// relying on grid's defaults measures the wrong thing and reads as an engine bug.
```

- [ ] **Step 4: Run the whole suite**

Run: `swift test --no-parallel 2>&1 | grep -E "error:|warning:|Test run with"`
Expected: `Test run with 518 tests in 0 suites passed` (513 + 5), and **72 goldens** — the 67 existing, unmoved, plus 5.

Verify: `git status --short Tests/MetalUILayoutTests/Golden/` shows five additions and **zero modifications**.

- [ ] **Step 5: Commit**

```bash
git add Tests/MetalUILayoutTests/Fixtures Tests/MetalUILayoutTests/Golden Tests/MetalUILayoutTests/StackFixtureTests.swift
git commit -m "test: five browser fixtures for Stack, oracled by CSS grid one-cell

CSS has no stack, so the oracle is display:grid with every child at
grid-area 1/1 -- same sizing, same overlap. Every fixture states
justify-items and align-items explicitly, because grid defaults to
stretch while Stack centres: a fixture relying on grid's defaults
measures the wrong thing and reads as an engine bug."
```

---

### Task 5: `Alignment`, the `Stack` element, and the file rename

**Files:**
- Rename: `Sources/MetalUI/Stack.swift` → `Sources/MetalUI/Flex.swift`
- Create: `Sources/MetalUI/Stack.swift` (the new element)
- Test: `Tests/MetalUITests/StackElementTests.swift` (create)

**Interfaces:**
- Consumes: `Display.stack`, `Style.justifyItems`, the engine path.
- Produces: `Alignment`, `Stack`. Task 6 nests it; Task 7 demos it.

**Context.** `Sources/MetalUI/Stack.swift` currently holds `Column` (line 24) and `Row` (line 93) — it is named for the SwiftUI concept those belong to, not for a type. Read `Column.init` before writing `Stack.init`: it writes `flexDirection`, `alignItems = .center` and `gap`, which is the pattern to match (ruling EP-8 — the element writes the substrate, `Style`'s defaults do not move).

- [ ] **Step 1: Rename the existing file**

```bash
git mv Sources/MetalUI/Stack.swift Sources/MetalUI/Flex.swift
```

Update its header comment to say it holds the flex containers. Run `swift build` and confirm nothing broke — a rename alone changes no symbols.

- [ ] **Step 2: Write the failing tests**

Create `Tests/MetalUITests/StackElementTests.swift`:

```swift
import Testing
import MetalUICore
import MetalUILayout
@testable import MetalUI

/// `Stack.init` writes the substrate; `Style`'s defaults do not move.
///
/// The same division `Column.init` uses (ruling EP-8): the element translates
/// SwiftUI's single `Alignment` into `alignItems` + `justifyItems`, and a
/// hand-built `Style` still defaults to `nil` on both.
@Test @MainActor func stackWritesDisplayAndBothAlignmentFields() throws {
    var element = Stack(alignment: .topLeading) { Box() }
    let (style, _) = try styleOfRoot(&element)
    #expect(style.display == .stack)
    #expect(style.alignItems == .flexStart)
    #expect(style.justifyItems == .start)
    // The default has not moved.
    #expect(Style().display == .flex)
    #expect(Style().justifyItems == nil)
}

/// All nine `Alignment` cases map to a distinct (alignItems, justifyItems) pair.
/// A mapping where two cases collided would silently make one unreachable.
@Test @MainActor func allNineAlignmentsMapToDistinctPairs() throws {
    let all: [Alignment] = [.topLeading, .top, .topTrailing,
                            .leading, .center, .trailing,
                            .bottomLeading, .bottom, .bottomTrailing]
    var seen: Set<String> = []
    for a in all {
        var element = Stack(alignment: a) { Box() }
        let (style, _) = try styleOfRoot(&element)
        seen.insert("\(String(describing: style.alignItems)),\(String(describing: style.justifyItems))")
    }
    try #require(seen.count == 9, "nine alignments must give nine pairs, got \(seen.count)")
}

/// The default is `.center` — SwiftUI's answer, not CSS's `stretch`.
@Test @MainActor func stackDefaultsToCentreNotStretch() throws {
    var element = Stack { Box() }
    let (style, _) = try styleOfRoot(&element)
    #expect(style.alignItems == .center)
    #expect(style.justifyItems == .center)
}
```

`styleOfRoot` does not exist. Write it in this file using whatever affordance `Tests/MetalUITests/` already has for building a `Frame` and reading a node's `Style` back — `grep -n "func laidOut\|Frame(contentSize:" Tests/MetalUITests/*.swift` shows working call sites. **If no affordance can read a `Style` back, assert on the resulting layout instead** — a `.topLeading` stack places its child at (0, 0) and a `.center` one does not — and say in the doc comment that you did so and why.

- [ ] **Step 3: Run to verify they fail**

Run: `swift test --no-parallel --filter StackElementTests 2>&1 | grep -E "error:" | head -3`
Expected: `cannot find 'Stack' in scope`.

- [ ] **Step 4: Implement**

Create `Sources/MetalUI/Stack.swift`:

```swift
import MetalUICore
import MetalUILayout

/// Where a `Stack` places each child within itself.
///
/// SwiftUI's nine-position `Alignment`, and its spelling, because SwiftUI is
/// this framework's design authority (ruling EP-5). One value covers both axes;
/// `Stack.init` translates it into the substrate's `alignItems` (block axis) and
/// `justifyItems` (inline axis).
public enum Alignment: Sendable, Equatable {
    case topLeading,    top,    topTrailing
    case leading,       center, trailing
    case bottomLeading, bottom, bottomTrailing

    var blockAxis: AlignItems {
        switch self {
        case .topLeading, .top, .topTrailing:             return .flexStart
        case .leading, .center, .trailing:                return .center
        case .bottomLeading, .bottom, .bottomTrailing:    return .flexEnd
        }
    }

    var inlineAxis: JustifyItems {
        switch self {
        case .topLeading, .leading, .bottomLeading:       return .start
        case .top, .center, .bottom:                      return .center
        case .topTrailing, .trailing, .bottomTrailing:    return .end
        }
    }
}

/// A container that layers its children at the same position.
///
/// The container sizes to its largest child on each axis — independently, so the
/// widest and the tallest child may be different children — and every child is
/// placed within that box by `alignment`.
///
/// **Not absolute positioning.** A `Stack`'s children participate in its sizing.
/// Absolutely-positioned children are removed from flow and contribute nothing
/// to their parent's size; that is a different feature, the one modals and
/// popovers need, and `Style.position`/`Style.inset` are still read by no
/// production code (CLAUDE.md's declared-but-inert table).
///
/// **Children paint in declaration order, first at the back.** That ordering is
/// only real because `Scene.finalize`'s draw list orders primitives across types
/// — before it, every rect drew beneath every glyph regardless of `order`, so a
/// background could not be layered under text.
///
/// **The default is `.center`, which is SwiftUI's answer and not CSS's.** A CSS
/// one-cell grid stretches its items; `ZStack` centres them at their natural
/// size. Ruling EP-5 takes SwiftUI's, as EP-8 already did for `Column`/`Row`.
public struct Stack<Content: ElementGroup>: Element, StyledElement {
    public var style: Style
    public var decoration: Decoration
    public var elementID: ElementID?
    public var content: Content

    public init(alignment: Alignment = .center,
                elementID: ElementID? = nil,
                @ElementBuilder content: () -> Content) {
        var style = Style()
        style.display = .stack
        style.alignItems = alignment.blockAxis
        style.justifyItems = alignment.inlineAxis
        self.style = style
        self.decoration = Decoration()
        self.elementID = elementID
        self.content = content()
    }

    // requestLayout / prepaint / paint: copy `Box`'s implementations verbatim —
    // a stack differs from a box only in its `Style`, and the three phases are
    // identical. Read `Sources/MetalUI/Box.swift` and mirror it.
}
```

**Write the three phase methods out in full** by mirroring `Box`'s (`Sources/MetalUI/Box.swift:57-97`). Do not leave the comment above in place of code.

- [ ] **Step 5: Run the whole suite**

Run: `swift test --no-parallel 2>&1 | grep -E "error:|warning:|Test run with"`
Expected: `Test run with 521 tests in 0 suites passed` (518 + 3). No golden moved.

- [ ] **Step 6: Measure the mutations**

1. `Alignment.blockAxis` returns `.center` for every case → expect `allNineAlignmentsMapToDistinctPairs`.
2. `Stack.init` omits `style.justifyItems` → expect `stackWritesDisplayAndBothAlignmentFields` and `stackDefaultsToCentreNotStretch`.
3. Default the `alignment:` parameter to `.topLeading` → expect `stackDefaultsToCentreNotStretch`.

- [ ] **Step 7: Commit**

```bash
git add -A Sources/MetalUI Tests/MetalUITests/StackElementTests.swift
git commit -m "feat: the Stack element and a nine-case Alignment

Stack.init writes display, alignItems and justifyItems; Style's defaults
do not move (EP-8's division). The default is .center -- SwiftUI's
answer, not CSS grid's stretch (EP-5).

Stack.swift held Column and Row and is renamed Flex.swift, so the file
that holds the flex containers is named for them and Stack.swift holds
Stack."
```

---

### Task 6: Nesting — a stack in a flex container and a flex container in a stack

**Files:**
- Create: `Tests/MetalUILayoutTests/Fixtures/stack_in_flex.html`
- Create: `Tests/MetalUILayoutTests/Fixtures/flex_in_stack.html`
- Modify: `Tests/MetalUILayoutTests/StackFixtureTests.swift`

**Interfaces:**
- Consumes: everything from Tasks 2-5.
- Produces: two more goldens.

**Why this task is separate.** `layOutChildren` is shared by both paths, and a dispatch bug hides exactly where they meet: a stack whose parent is a flex container must contribute its measured size to that container's line, and a flex container inside a stack must be sized and then aligned as a single item. Neither is exercised by a fixture where the stack is the root.

- [ ] **Step 1: Write the fixtures**

`stack_in_flex.html` — a stack as one item of a flex row, with siblings:

```html
<!DOCTYPE html>
<html><head><style>
  body { margin: 0; }
  #root { display: flex; flex-direction: row; width: 400px; height: 150px;
          align-items: flex-start; }
  .before { width: 40px; height: 30px; }
  .after  { width: 60px; height: 20px; }
  /* The stack: one cell, children overlapped, sized to the largest. */
  .stack { display: grid; justify-items: center; align-items: center; }
  .stack > div { grid-area: 1 / 1; }
  .wide { width: 90px; height: 10px; }
  .tall { width: 20px; height: 70px; }
</style></head><body>
  <div id="root">
    <div class="before"></div>
    <div class="stack"><div class="wide"></div><div class="tall"></div></div>
    <div class="after"></div>
  </div>
</body></html>
```

`flex_in_stack.html` — a flex row as one child of a stack, alongside a larger sibling:

```html
<!DOCTYPE html>
<html><head><style>
  body { margin: 0; }
  #root { display: grid; justify-items: center; align-items: center;
          width: 300px; height: 200px; }
  #root > div { grid-area: 1 / 1; }
  .backdrop { width: 200px; height: 120px; }
  .row { display: flex; flex-direction: row; }
  .row > div { width: 30px; height: 25px; }
</style></head><body>
  <div id="root">
    <div class="backdrop"></div>
    <div class="row"><div></div><div></div><div></div></div>
  </div>
</body></html>
```

The `.row` measures 90×25 from its three children, and the backdrop is larger on both axes — so the stack sizes to the backdrop and the row is centred inside it. **A fixture where the nested flex container were the largest child could not tell "the stack measured the row correctly" from "the stack ignored the row and used the backdrop".** These numbers distinguish them.

- [ ] **Step 2: Generate the goldens against live WebKit**

Same mechanism as Task 4. **Expected to match on first generation; if not, STOP and report both numbers.**

- [ ] **Step 3: Add the fixture tests**

Append to `StackFixtureTests.swift`, hand-building both trees. State in each test's doc comment what a dispatch bug would look like: for `stack_in_flex`, the stack contributing its *children's sum* rather than their max to the row's line; for `flex_in_stack`, the nested row being laid out at the stack's full width rather than its own 90.

- [ ] **Step 4: Run the whole suite**

Run: `swift test --no-parallel 2>&1 | grep -E "error:|warning:|Test run with"`
Expected: `Test run with 523 tests in 0 suites passed` (521 + 2), **74 goldens, zero modified**.

- [ ] **Step 5: Measure the mutation**

Make `layOutStack` sum the children's widths instead of taking the max → expect **both** `stack_in_flex` and `aStackSizesToItsLargestChildOnEachAxisIndependently`. If the nesting fixture does not redden, it is not reaching the composition and needs different geometry.

- [ ] **Step 6: Commit**

```bash
git add Tests/MetalUILayoutTests
git commit -m "test: nesting fixtures — a stack in a flex row, a flex row in a stack

layOutChildren is shared by both paths and a dispatch bug hides where
they meet. Geometry chosen so the nested flex container is NOT the
largest child, which is what distinguishes 'the stack measured it' from
'the stack ignored it'."
```

---

### Task 7: Demo, documentation, human verification

**Files:**
- Modify: `Sources/MetalUIDemo/main.swift`
- Modify: `CLAUDE.md`
- Create: `docs/superpowers/2026-08-28-stack-decisions.md`

- [ ] **Step 1: Put a `Stack` in the demo**

Something whose layering is visually obvious and whose z-order is checkable by eye — a badge over a tile, or a translucent scrim over content with a label on top. It must have **at least three children of different sizes** so the container's sizing is visible, and the topmost child must be one that would look wrong if the order inverted.

- [ ] **Step 2: Verify the build and smoke-run**

```bash
swift package clean && swift build 2>&1 | grep -cE "error:|warning:"   # expect 0
swift run MetalUIDemo   # confirm it launches; this is NOT the human look
```

- [ ] **Step 3: Update CLAUDE.md**

- Add `Stack` to the containers described near `Column`/`Row`, and note that `Stack.swift` holds it while `Flex.swift` holds `Column`/`Row`.
- **`Style.justifyItems` must NOT enter the declared-but-inert table** — it has a production reader. If a future reader would expect it there, add one sentence saying why it is absent.
- **`Style.position` and `Style.inset` stay in the table.** A `Stack` is not absolute positioning and does not make them live. Re-run the table's own re-check command and state what it returns.
- Re-count `grep -cE "^    public var " Sources/MetalUILayout/Style.swift` and state the number the command actually returns — it gained `justifyItems`.
- Update the build line: re-measure, do not add.

- [ ] **Step 4: Write the decisions doc**

`docs/superpowers/2026-08-28-stack-decisions.md`, rulings prefixed **`ST-`** and **lettered** (`ST-A`, `ST-B`, …) per this repo's convention, so a bare `ST-3` is a typo rather than a citation. At minimum:

- SwiftUI's centre default over CSS grid's stretch, and what it costs (every oracle fixture must state `justify-items`/`align-items` explicitly).
- `StackItem` as its own type rather than a reused `FlexItem`.
- `positionStackItems` as its own function rather than a branch.
- `justifyItems` on `Style` rather than an `Alignment` field, and why it is not inert.
- Whatever Task 1's probe measured about percentage children.

- [ ] **Step 5: Re-measure everything the docs claim**

```bash
swift package clean && swift test --no-parallel 2>&1 | grep "Test run with"
ls Tests/MetalUILayoutTests/Golden/*.json | wc -l
grep -cE "^    public var " Sources/MetalUILayout/Style.swift
```

- [ ] **Step 6: Human verification**

Ask the user to run `swift run MetalUIDemo` and report on: whether the layered children are stacked rather than sequenced, whether the **topmost child is on top** and not behind, whether the container is sized to its largest child, and whether alignment looks right.

**Record what the look could NOT establish**, as the M2 and clipping-and-scroll entries do.

**Z-order is why this criterion exists**: a z-order inversion is invisible to every test that checks positions, because both orderings produce identical rects. Say so in the record.

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "docs: record the Stack milestone

Demo has a layered Stack; CLAUDE.md gains the container and keeps
position/inset in the inert table (a Stack is not absolute positioning);
ST- decisions doc."
```

---

## Self-Review

**Spec coverage.** §1's five in-scope items → Tasks 1-5. §2 (SwiftUI's default) → Task 4's fixture requirement and Task 5's `stackDefaultsToCentreNotStretch`. §3.1 → Task 2. §3.2 → Task 2. §3.3 → Task 3. §3.4 → Task 1's probe. §4 → Tasks 1 and 5. §4.1 (rename) → Task 5. §5 → Task 4. §6's requirements → Tasks 2, 3, 4, 6. §7's exit criteria → Task 7.

**One gap found and closed:** §6 requires "a stretch differential — a fixture where SwiftUI's centre and CSS's stretch give different numbers." Task 4's `stack_stretch.html` plus `stack_alignment_center.html` are that pair, on identical geometry; Task 3's `stretchFillsTheContainerOnThatAxis` is the unit-level half.

**Placeholder scan.** Task 5's phase methods are described as "mirror `Box`'s" with an explicit instruction to write them out rather than leave the comment — the alternative was transcribing forty lines of an existing file into the plan, which is the "Similar to Task N" anti-pattern in the other direction. Task 4 Step 2 and Task 6 Step 2 defer to `GeneratorTests.swift`'s documented mechanism rather than inventing a command, because the plan should not guess at a harness entry point it did not read.

**Type consistency.** `StackItem { node, size }` (Task 2) is consumed unchanged in Tasks 3 and 6. `JustifyItems` has the same four cases in Tasks 1, 3 and 5. `Alignment.blockAxis`/`inlineAxis` (Task 5) return `AlignItems`/`JustifyItems` as declared in Task 1. `positionStackItems`'s signature in Task 3 Step 3's call site matches Step 4's definition.

**Test-count arithmetic is cumulative and will drift** if a task adds a case this plan did not anticipate. Every task reads the summary line; treat the predicted number as a check, not a gate.
