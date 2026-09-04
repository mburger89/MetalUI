# `Component` (M4 spec 2) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a `Component` protocol so an element author writes only `content` — layout-transparent (contributes no node of its own) and identity-opaque (consumes one cursor index, so `@State` works).

**Architecture:** `Component` refines `ElementGroup` rather than `Element`. One protocol extension supplies the whole conformance: it mints the component's `GlobalElementID`, binds its `@State`, materializes `content` **once** into a stashed value, forwards to `content.requestGroupLayout(under: myID, at: &innerCursor, …)`, and returns the content's `[LayoutNodeID]` **unchanged**. Modifiers are not attached — they wrap the component in a `Box`, which is what SwiftUI's `ModifiedContent` does.

**Tech Stack:** Swift 6.3, `@resultBuilder` (`ElementBuilder`, already complete), Swift Testing. Package floor `.macOS(.v14)`, unchanged.

**Spec:** `docs/superpowers/specs/2026-09-03-component-design.md`

## Global Constraints

- **Read the test summary line, never the exit status.** `swift test --no-parallel`, unfiltered, and read `Test run with N tests in 1 suite passed after …`. A run that dies mid-suite prints no summary line.
- **Baseline is 791 tests, 87 goldens, 32 `swiftc -typecheck` guards, warning-free.** Verify with `find Tests -name "*.json" | wc -l` = 87 and a full-log `grep -ci "warning:"` = 0.
- **No golden may move and none may be added.** This spec touches no layout code; `git diff --name-only <base>..HEAD -- Sources/MetalUILayout/` must be **empty** for the whole branch. A moved golden means something reached the engine that should not have — stop and report, do not regenerate.
- **Assert counts and structure, never wall-clock times.**
- **`hasActiveAnimations` must not exist in `Sources/`.** M4 spec 3 owns it, and introduces it together with its writer.
- **A mutation that reddens nothing is a broken instrument or it is the finding.** Where a task says "run this mutation", run it and report the actual output — never predict it.
- **Anything a mutation teaches must be walked back to the mutated LINE in the same pass**, not only into the task report.
- **Do not add a `Style` property, and do not make `Component` conform to `StyledElement`.** Spec §3 records why: a `Style` must attach to a layout node, which would make every component layout-opaque.
- **Do not change the demo.** Spec §7 permits converting `CounterPanel` only if no rect moves; this plan forbids it outright — see the note after Task 3.
- **Do not add a SwiftUI test target.** The SwiftUI-flattening claim is labelled derived (spec §2) and stays that way.

---

## File Structure

| File | Responsibility | Task |
|---|---|---|
| `Sources/MetalUI/Component.swift` (create) | The `Component` protocol, `ComponentLayout`, and the one extension supplying the `ElementGroup` conformance. | 1 |
| `Tests/MetalUITests/ComponentTests.swift` (create) | Every assertion this spec owns. New file rather than extending `ElementLayoutTests`, which owns the builder-and-plumbing surface. | 1, 2, 3 |
| `Sources/MetalUI/Component.swift` (modify) | The forwarded modifiers. | 3 |
| `CLAUDE.md`, `docs/superpowers/specs/2026-08-24-metalui-design.md`, `docs/superpowers/2026-09-03-component-decisions.md` (create) | The record, and §4.2's correction. | 4 |

**Test harness to reuse rather than reinvent** (all in `Tests/MetalUITests/`):
- `Frame(contentSize: Size(width: px(300), height: px(40)), scaleFactor: 1)` then `frame.render(&root)` — the driver every element test uses (`ElementLayoutTests.swift:377-382`).
- `ElementLog` (`ElementLayoutTests.swift:26`) — a `@MainActor final class` recording `registered: [String]`, `bounds: [String: Bounds<Pixels>]`, `nodes: [String: LayoutNodeID]`. A **class** because phases are `mutating` on value types.
- `Probe(_ name: String, log: ElementLog)` (`ElementLayoutTests.swift:57`) — an `Element, StyledElement` leaf taking `.width(px(…))`/`.height(px(…))`.
- `rect(_:)` and `px(_:)` helpers, used as `#expect(rect(log.bounds["first"]!) == (0, 15, 30, 10))`.
- `CounterElement` (`StateTests.swift:77`) — the `@State`-increments-in-`requestLayout` idiom for state probes.

These are `private`/file-scoped where they live. **Declare your own copies in `ComponentTests.swift`**; do not widen an access level to share them, and do not move them to `Fakes.swift` (that is a refactor this plan has no room to review).

---

### Task 1: The protocol, the conformance, and layout transparency

**Files:**
- Create: `Sources/MetalUI/Component.swift`
- Create: `Tests/MetalUITests/ComponentTests.swift`

**Interfaces:**
- Consumes: `ElementGroup` (`Sources/MetalUI/ElementGroup.swift:44`) — associated types `GroupLayout`, `GroupPrepaint`; methods `requestGroupLayout(under:at:pass:)`, `prepaintGroup(layout:pass:)`, `paintGroup(layout:prepaint:pass:)`. `GlobalElementID.child(of:at:name:)` (public). `StateBinder.bind(_:table:id:)` (`StateReflection.swift:79`, internal, generic over any type). `ElementBuilder` (`ElementBuilder.swift:41`).
- Produces: `public protocol Component: ElementGroup` with `associatedtype Content: ElementGroup`, `@ElementBuilder var content: Content { get }`, `var elementID: ElementID? { get }` (defaulted `nil`); `public struct ComponentLayout<C: Component>`.

- [ ] **Step 1: Write the failing tests**

Create `Tests/MetalUITests/ComponentTests.swift`:

```swift
import Testing
import MetalUICore
import MetalUILayout
@testable import MetalUI

// M4 spec 2. A `Component` is TRANSPARENT to layout and OPAQUE to identity:
// it contributes no layout node of its own, and it consumes one cursor index so
// that its `@State` has an id to hang on. Those are separate axes and this is
// the first type in the framework to use them differently — every other element
// is opaque to both.
//
// The assertions below are structural and geometric together. A component that
// wrongly contributed its own flex container would still produce the right
// CHILD COUNT in some trees while moving every rect, so counting alone cannot
// see the defect this file exists to prevent.

// MARK: - Probes

/// Records what each phase was handed, by name. A **class** because `Element`'s
/// phases are `mutating` on a value type, so anything recorded into a struct
/// would be observed on whichever copy the driver happened to keep.
@MainActor
final class ComponentLog {
    var registered: [String] = []
    var bounds: [String: Bounds<Pixels>] = [:]
}

/// A styled leaf that reports its own name and rect.
private struct Leaf: Element, StyledElement {
    var style = Style()
    var decoration = Decoration()
    var elementID: ElementID?
    var handlers = Handlers()
    let name: String
    let log: ComponentLog

    init(_ name: String, log: ComponentLog) {
        self.name = name
        self.log = log
    }

    func requestLayout(_ id: GlobalElementID,
                       pass: inout LayoutPass) -> (LayoutNodeID, LayoutNodeID) {
        log.registered.append(name)
        let node = pass.requestNode(style: style, children: [])
        return (node, node)
    }

    func prepaint(_ id: GlobalElementID, bounds: Bounds<Pixels>,
                  layout: inout LayoutNodeID,
                  pass: inout PrepaintPass) -> LayoutNodeID {
        log.bounds[name] = bounds
        return layout
    }

    func paint(_ id: GlobalElementID, bounds: Bounds<Pixels>,
               layout: inout LayoutNodeID, prepaint: inout LayoutNodeID,
               pass: inout PaintPass) {}
}

/// Two leaves and nothing else — the shape that distinguishes a transparent
/// component from an opaque one. If `TwoLeaves` contributed a node, `a` and `b`
/// would be children of THAT node rather than of the enclosing container.
private struct TwoLeaves: Component {
    let log: ComponentLog
    var elementID: ElementID?

    var content: some ElementGroup {
        Leaf("a", log: log).width(px(30)).height(px(10))
        Leaf("b", log: log).width(px(50)).height(px(10))
    }
}

private func px(_ v: Float) -> Pixels { Pixels(v) }

private func rect(_ b: Bounds<Pixels>) -> (Float, Float, Float, Float) {
    (b.origin.x.value, b.origin.y.value, b.size.width.value, b.size.height.value)
}

// MARK: - Layout transparency

/// Spec §2. `Row { TwoLeaves() }` must lay `a` and `b` out as the ROW's own
/// children, side by side, exactly as `Row { Leaf; Leaf }` would.
///
/// The geometry is the load-bearing half. A component that contributed its own
/// flex container would still register both leaves in the right order — so
/// `registered` alone cannot see the defect — but `b` would sit inside a nested
/// row and the two rects would differ from the inline spelling's.
@MainActor
@Test func aComponentsContentFlattensIntoItsParent() {
    let componentLog = ComponentLog()
    let frame = Frame(contentSize: Size(width: px(300), height: px(40)), scaleFactor: 1)
    var withComponent = Row { TwoLeaves(log: componentLog) }
    frame.render(&withComponent)

    let inlineLog = ComponentLog()
    let inlineFrame = Frame(contentSize: Size(width: px(300), height: px(40)), scaleFactor: 1)
    var inline = Row {
        Leaf("a", log: inlineLog).width(px(30)).height(px(10))
        Leaf("b", log: inlineLog).width(px(50)).height(px(10))
    }
    inlineFrame.render(&inline)

    #expect(componentLog.registered == ["a", "b"])
    #expect(componentLog.registered == inlineLog.registered)
    // The differential IS the assertion: a wrapped component and the inline
    // spelling must be geometrically indistinguishable.
    #expect(rect(componentLog.bounds["a"]!) == rect(inlineLog.bounds["a"]!))
    #expect(rect(componentLog.bounds["b"]!) == rect(inlineLog.bounds["b"]!))
    // Literal numbers alongside, because two runs of a broken engine agree with
    // each other. A 40-tall row centres a 10-tall child at y = 15 (ruling EP-8).
    #expect(rect(componentLog.bounds["a"]!) == (0, 15, 30, 10))
    #expect(rect(componentLog.bounds["b"]!) == (30, 15, 50, 10))
}

/// Spec §2. The node count for a tree holding a component equals the count for
/// the same tree written inline. This is the direct form of "contributes no
/// layout node", and it is the assertion a wrapping node reddens first.
@MainActor
@Test func aComponentContributesNoLayoutNodeOfItsOwn() {
    let frame = Frame(contentSize: Size(width: px(300), height: px(40)), scaleFactor: 1)
    var withComponent = Row { TwoLeaves(log: ComponentLog()) }
    frame.render(&withComponent)
    let withCount = frame.layoutNodeCount

    let inlineFrame = Frame(contentSize: Size(width: px(300), height: px(40)), scaleFactor: 1)
    let log = ComponentLog()
    var inline = Row {
        Leaf("a", log: log).width(px(30)).height(px(10))
        Leaf("b", log: log).width(px(50)).height(px(10))
    }
    inlineFrame.render(&inline)

    #expect(withCount == inlineFrame.layoutNodeCount,
            "a component must add no layout node; got \(withCount) against \(inlineFrame.layoutNodeCount)")
}

/// Spec §6 assertion 8. Two identity levels, zero layout nodes.
@MainActor
@Test func aComponentInsideAComponentFlattensThroughBothLevels() {
    struct Outer: Component {
        let log: ComponentLog
        var elementID: ElementID?
        var content: some ElementGroup { TwoLeaves(log: log) }
    }

    let log = ComponentLog()
    let frame = Frame(contentSize: Size(width: px(300), height: px(40)), scaleFactor: 1)
    var root = Row { Outer(log: log) }
    frame.render(&root)

    #expect(log.registered == ["a", "b"])
    #expect(rect(log.bounds["a"]!) == (0, 15, 30, 10))
    #expect(rect(log.bounds["b"]!) == (30, 15, 50, 10))
}

/// Spec §4.3. `EmptyGroup` is an `ElementGroup`, so a component with an empty
/// content block is legal and contributes zero nodes — consistent with `Box()`,
/// which is also childless. Not an error.
@MainActor
@Test func anEmptyComponentContributesNoNodes() {
    struct Nothing: Component {
        var elementID: ElementID?
        var content: some ElementGroup { EmptyGroup() }
    }

    let frame = Frame(contentSize: Size(width: px(300), height: px(40)), scaleFactor: 1)
    var root = Row { Nothing() }
    frame.render(&root)

    let bareFrame = Frame(contentSize: Size(width: px(300), height: px(40)), scaleFactor: 1)
    var bare = Row { EmptyGroup() }
    bareFrame.render(&bare)

    #expect(frame.layoutNodeCount == bareFrame.layoutNodeCount)
}
```

**`frame.layoutNodeCount` may not exist.** Before writing the two count assertions, check: `grep -n "nodeCount\|var count" Sources/MetalUILayout/LayoutTree.swift Sources/MetalUI/Frame.swift`. If there is no such accessor, **do not add one to production code** — instead assert the count through whatever `LayoutTree` already exposes under `@testable`, or replace the two count assertions with a structural one that reads the row's children directly. Report which you used and why. The claim is "adds no node"; the spelling is yours.

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --no-parallel --filter ComponentTests 2>&1 | tail -20`
Expected: the file does not compile — `cannot find type 'Component' in scope`. That is the correct red: the protocol does not exist yet.

- [ ] **Step 3: Create the protocol and its conformance**

Create `Sources/MetalUI/Component.swift`:

```swift
/// The user-facing element surface (design spec §4.2): an author writes
/// `content` and gets a working element.
///
/// **A `Component` is TRANSPARENT to layout and OPAQUE to identity**, and those
/// are separate axes in this framework. Every other element is opaque to both —
/// a `Box` consumes one cursor index *and* contributes one layout node.
///
/// - **Layout-transparent**: a component contributes **no layout node of its
///   own**; its content's nodes pass through to its parent unchanged. So
///   `Column { MyRow(); MyRow() }` lays the rows' children out as the
///   `Column`'s own children. That is SwiftUI's shape — a custom `View`
///   contributes no layout container, and `.padding()` introduces a layer by
///   wrapping the view in `ModifiedContent` rather than by attaching to it.
///   **That description of SwiftUI is DERIVED from its documented behaviour and
///   is not measured here**: there is no SwiftUI test target in this repo. If
///   SwiftUI turns out to differ, this is a divergence and the label is
///   available.
/// - **Identity-opaque**: a component consumes one cursor index and its content
///   nests beneath the component's own `GlobalElementID`. **This is not a
///   choice.** `@State` slots are `.named("$state\(n)")` children of the
///   element's own id (`StateBinder.bind`), so a component with no id of its
///   own could not hold state — and holding state is the main reason to write a
///   component rather than a function returning elements.
///
/// **No `StyledElement` conformance, deliberately** (spec §3). A `Style` must
/// attach to a layout node, and `Style.display` defaults to `.flex` with no
/// `contents` case in the engine — so conforming would force a component to
/// contribute a real flex container and make it layout-opaque, which is the
/// exact divergence this design exists to avoid. Modifiers wrap instead; see
/// the extension below.
///
/// **No `.id()` modifier**, for the same reason: that method lives on
/// `StyledElement`. An author who needs a stable name declares the property:
///
/// ```swift
/// struct Row: Component {
///     let item: Item
///     var elementID: ElementID? { ElementID(String(describing: item.id)) }
///     var content: some ElementGroup { … }
/// }
/// ```
@MainActor
public protocol Component: ElementGroup {
    associatedtype Content: ElementGroup

    @ElementBuilder var content: Content { get }

    /// The component's local name among its siblings, or `nil` to be identified
    /// by **position**. Same contract as `Element.elementID`: a name replaces a
    /// position, so a named component keeps its state through a reorder.
    var elementID: ElementID? { get }
}

/// What a `Component`'s `requestGroupLayout` hands to the later phases.
///
/// `content` is stored because the protocol's `content` is **computed**:
/// re-evaluating it in `prepaintGroup` would build fresh element structs and
/// discard whatever `requestGroupLayout` wrote into them. Design spec §4.2's
/// "materializes `content` once" is this field.
public struct ComponentLayout<C: Component> {
    var id: GlobalElementID
    var content: C.Content
    var contentLayout: C.Content.GroupLayout
}

extension Component {
    public var elementID: ElementID? { nil }

    public mutating func requestGroupLayout(under parent: GlobalElementID?,
                                            at cursor: inout Int,
                                            pass: inout LayoutPass)
        -> ([LayoutNodeID], ComponentLayout<Self>) {
        // The component's own identity level. `child(of:at:name:)` decides
        // whether that is a `.named` component or a `.positional` one — the
        // name-replaces-position rule lives in the constructor, not here.
        let id = GlobalElementID.child(of: parent, at: cursor, name: elementID)

        // Binds the COMPONENT's own `@State`. Nothing else does this for a
        // component: `Element`'s default `requestGroupLayout` is not reached,
        // because a `Component` is not an `Element`.
        StateBinder.bind(self, table: pass.frame.stateTable, id: id)

        // One index from the PARENT's cursor, and a fresh cursor for the
        // content. Threading the outer cursor into the content instead would
        // give the content its siblings' positions and silently collide their
        // state.
        cursor += 1
        var materialized = content
        var innerCursor = 0
        let (nodes, contentLayout) =
            materialized.requestGroupLayout(under: id, at: &innerCursor, pass: &pass)

        // `nodes` returned UNCHANGED — this is layout transparency. Wrapping
        // them, or replacing them with a node of the component's own, is what
        // makes a component layout-opaque.
        return (nodes, ComponentLayout(id: id,
                                       content: materialized,
                                       contentLayout: contentLayout))
    }

    public mutating func prepaintGroup(layout: inout ComponentLayout<Self>,
                                       pass: inout PrepaintPass)
        -> Content.GroupPrepaint {
        layout.content.prepaintGroup(layout: &layout.contentLayout, pass: &pass)
    }

    public mutating func paintGroup(layout: inout ComponentLayout<Self>,
                                    prepaint: inout Content.GroupPrepaint,
                                    pass: inout PaintPass) {
        layout.content.paintGroup(layout: &layout.contentLayout,
                                  prepaint: &prepaint, pass: &pass)
    }
}
```

**Three notes for the build:**

1. **`materialized.requestGroupLayout(…)`, never `requestLayout(…)`.** That call is what reaches `StateBinder.bind` for every element inside the content. Calling `requestLayout` directly is the live `AnyElement` defect in CLAUDE.md's declared-but-inert table: `@State` returns its initial value forever with **no diagnostic**. Task 2 mutates this line.
2. **Associated-type inference.** `GroupLayout` and `GroupPrepaint` should be inferred as `ComponentLayout<Self>` and `Content.GroupPrepaint` from the method signatures. If the compiler cannot infer them, add explicit `public typealias GroupLayout = ComponentLayout<Self>` and `public typealias GroupPrepaint = Content.GroupPrepaint` in the extension — and report that you had to.
3. **`ComponentLayout`'s stored properties are `internal`** while the struct is `public`. That is deliberate — a caller has no business reading them — and matches `SingleElementLayout` (`ElementGroup.swift:54-56`), which does the same. If it does not compile because the extension is public, make the properties `public internal(set)` rather than fully `public`, and say so.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --no-parallel --filter ComponentTests 2>&1 | tail -20`
Expected: all four PASS.

- [ ] **Step 5: Run the whole suite unfiltered**

Run: `swift test --no-parallel 2>&1 | tail -5`
Expected: `Test run with 795 tests in 1 suite passed after …` (791 + 4).

```bash
git status --short -- 'Tests/**/*.json'; find Tests -name "*.json" | wc -l
git diff --name-only -- Sources/MetalUILayout/
```
Expected: empty, `87`, empty.

- [ ] **Step 6: Commit**

```bash
git add Sources/MetalUI/Component.swift Tests/MetalUITests/ComponentTests.swift
git commit -m "feat: Component — transparent to layout, opaque to identity

An author writes \`content\` and gets a working element. The conformance is one
protocol extension: it mints the component's own GlobalElementID, binds its
@State, materializes content once into a stashed value, forwards to
content.requestGroupLayout under that id with a fresh cursor, and returns the
content's layout nodes UNCHANGED.

Returning the nodes unchanged is what makes Column { MyRow(); MyRow() } lay the
rows' children out as the Column's own — SwiftUI's shape. Consuming one cursor
index is what gives the component an id for @State to hang on, which is not
optional: state slots are named children of the element's own id.

Content is \`some ElementGroup\`, not \`some Element\`, so a component may have
two top-level children — a bare block builds a Pair, and Pair is not an Element.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01FN1rUy2Qkdyd53wiM3pKnK"
```

---

### Task 2: `@State` inside a component, and the four mutations

**Files:**
- Modify: `Tests/MetalUITests/ComponentTests.swift`

**Interfaces:**
- Consumes: `Component`, `ComponentLayout` from Task 1. `@State` (`Sources/MetalUI/State.swift`). `StateTable` under `@testable`.

This is the task whose assertions the whole design rests on: identity opacity exists *only* to make `@State` work, and a component whose state silently returns its initial value forever is the `AnyElement` defect with a new name.

- [ ] **Step 1: Write the tests**

The cross-frame idiom is `StateTests.swift:146-152`'s, and it is simpler than a
`StateTable.peek`: thread one `StateTable` through several `Frame`s and read the value back
**through the element's own property**, because `@State`'s box is shared between copies.

Append to `Tests/MetalUITests/ComponentTests.swift`:

```swift
// MARK: - Identity opacity: `@State` inside a component

/// A component holding one `@State` slot it increments every frame — the
/// `CounterElement` idiom (`StateTests.swift:77`) at the component level.
///
/// Writing `@State` from `requestLayout` is forbidden in PRODUCTION (it keeps
/// the window permanently dirty, which is milestone 4's exit criterion
/// sabotaged from an element). It is the established idiom in tests, where no
/// display link runs, and it is the only way to watch the slot advance without
/// an input path.
private struct Counter: Component {
    @State var count = 0
    var elementID: ElementID?
    let log: ComponentLog
    let name: String

    init(_ name: String, log: ComponentLog, elementID: ElementID? = nil) {
        self.name = name
        self.log = log
        self.elementID = elementID
    }

    var content: some ElementGroup {
        Counting(count: $count, name: name, log: log)
    }
}

/// The leaf that performs the component's increment. It lives here rather than
/// in `Counter.content`'s getter because a computed property is not a phase:
/// `content` is evaluated once per frame by `requestGroupLayout`, but writing
/// from a getter would make the write order depend on when the getter runs.
private struct Counting: Element {
    @Binding var count: Int
    let name: String
    let log: ComponentLog
    var elementID: ElementID?

    func requestLayout(_ id: GlobalElementID,
                       pass: inout LayoutPass) -> (LayoutNodeID, LayoutNodeID) {
        count += 1
        log.registered.append(name)
        var style = Style()
        style.size = Size(width: .length(.pixels(px(10))),
                          height: .length(.pixels(px(10))))
        let node = pass.requestNode(style: style, children: [])
        return (node, node)
    }

    func prepaint(_ id: GlobalElementID, bounds: Bounds<Pixels>,
                  layout: inout LayoutNodeID,
                  pass: inout PrepaintPass) -> LayoutNodeID { layout }

    func paint(_ id: GlobalElementID, bounds: Bounds<Pixels>,
               layout: inout LayoutNodeID, prepaint: inout LayoutNodeID,
               pass: inout PaintPass) {}
}
```

**`@Binding` may not exist in this framework** — `grep -rn "propertyWrapper" Sources/MetalUI/`
to check. If it does not, **do not add it**: instead have `Counter` increment its own `@State`
directly inside `content`'s getter and note in a comment that the getter runs exactly once per
frame (`requestGroupLayout` materializes it once, spec §4.2), which is what makes that safe
here. Report which shape you used.

Then the five assertions:

```swift
/// Spec §6 assertion 3. The component's own `@State` must survive across frames,
/// which requires its own `GlobalElementID`, which is what the extension's
/// `cursor += 1` buys.
@MainActor
@Test func aComponentsOwnStateSurvivesAcrossFrames() {
    let table = StateTable()
    let size = Size<Pixels>(width: px(100), height: px(100))
    var tree = Box(content: Counter("c", log: ComponentLog()))

    for _ in 0..<3 {
        Frame(contentSize: size, scaleFactor: 1, stateTable: table).render(&tree)
    }

    #expect(tree.content.count == 3,
            "the component's own @State must accumulate, not reset; got \(tree.content.count)")
}

/// Spec §6 assertion 4. Two sibling instances of the same component type hold
/// INDEPENDENT state. This is what the outer `cursor += 1` and the fresh
/// `innerCursor` buy together — a shared cursor collides them, and each would
/// read 6 or 0 rather than 3.
@MainActor
@Test func twoSiblingComponentsHoldIndependentState() {
    let table = StateTable()
    let size = Size<Pixels>(width: px(100), height: px(100))
    let log = ComponentLog()
    var tree = Box {
        Counter("a", log: log)
        Counter("b", log: log)
    }

    for _ in 0..<3 {
        Frame(contentSize: size, scaleFactor: 1, stateTable: table).render(&tree)
    }

    #expect(tree.content.first.count == 3, "got \(tree.content.first.count)")
    #expect(tree.content.second.count == 3, "got \(tree.content.second.count)")
}

/// Spec §6 assertion 5, both halves in one test, because the ASYMMETRY is the
/// evidence — the pattern `namingTheLaterSiblingIsWhatSurvivesAVanishingIf`
/// already uses. A named component keeps its own count through a swap; an
/// unnamed one's count follows the position.
@MainActor
@Test func aNamedComponentKeepsItsStateThroughAReorderAndAnUnnamedOneDoesNot() {
    let size = Size<Pixels>(width: px(100), height: px(100))

    // Named: the counts travel with the names.
    let namedTable = StateTable()
    let log = ComponentLog()
    var forward = Box {
        Counter("a", log: log, elementID: ElementID("a"))
        Counter("b", log: log, elementID: ElementID("b"))
    }
    Frame(contentSize: size, scaleFactor: 1, stateTable: namedTable).render(&forward)
    Frame(contentSize: size, scaleFactor: 1, stateTable: namedTable).render(&forward)

    var swapped = Box {
        Counter("b", log: log, elementID: ElementID("b"))
        Counter("a", log: log, elementID: ElementID("a"))
    }
    Frame(contentSize: size, scaleFactor: 1, stateTable: namedTable).render(&swapped)

    #expect(swapped.content.first.count == 3, "\"b\" kept its own slot across the swap")
    #expect(swapped.content.second.count == 3, "\"a\" kept its own slot across the swap")

    // Unnamed: the counts stay with the POSITIONS, so the swap is invisible to
    // the table and both still read 3 — but for the opposite reason. To make
    // the asymmetry observable, give the two different starting counts by
    // rendering the unnamed pair an unequal number of times before swapping.
    let unnamedTable = StateTable()
    var first = Box { Counter("a", log: log) }
    Frame(contentSize: size, scaleFactor: 1, stateTable: unnamedTable).render(&first)
    Frame(contentSize: size, scaleFactor: 1, stateTable: unnamedTable).render(&first)

    var pair = Box {
        Counter("x", log: log)
        Counter("y", log: log)
    }
    Frame(contentSize: size, scaleFactor: 1, stateTable: unnamedTable).render(&pair)

    // Position 0 inherits the slot the single unnamed component built up.
    #expect(pair.content.first.count == 3,
            "an unnamed component at position 0 ADOPTS the slot a previous \
             unnamed component at position 0 left; got \(pair.content.first.count)")
    #expect(pair.content.second.count == 1,
            "position 1 is fresh; got \(pair.content.second.count)")
}

/// Spec §4.3 second half. A childless component still has an identity level,
/// so its own `@State` still works.
@MainActor
@Test func anEmptyComponentStillHoldsItsOwnState() {
    struct Quiet: Component {
        @State var count = 0
        var elementID: ElementID?
        var content: some ElementGroup {
            count += 1
            return EmptyGroup()
        }
    }

    let table = StateTable()
    let size = Size<Pixels>(width: px(100), height: px(100))
    var tree = Box(content: Quiet())

    for _ in 0..<3 {
        Frame(contentSize: size, scaleFactor: 1, stateTable: table).render(&tree)
    }

    #expect(tree.content.count == 3, "got \(tree.content.count)")
}

/// Spec §4.2's load-bearing line: the content is reached through
/// `requestGroupLayout`, which is what calls `StateBinder.bind` for every
/// element inside it. Forwarding to `requestLayout` instead is the live
/// `AnyElement` defect — `@State` returns its initial value forever, with no
/// diagnostic.
///
/// **This and `aComponentsOwnStateSurvivesAcrossFrames` must be reddened by
/// DIFFERENT mutations**, or one of the two is proving less than it claims.
@MainActor
@Test func stateInsideAComponentsContentIsAlsoSeeded() {
    struct Wrapper: Component {
        let inner: CounterLeaf
        var elementID: ElementID?
        var content: some ElementGroup { inner }
    }

    let table = StateTable()
    let size = Size<Pixels>(width: px(100), height: px(100))
    var tree = Box(content: Wrapper(inner: CounterLeaf()))

    for _ in 0..<3 {
        Frame(contentSize: size, scaleFactor: 1, stateTable: table).render(&tree)
    }

    #expect(tree.content.inner.count == 3,
            "@State inside a component's CONTENT must be seeded too; got \(tree.content.inner.count)")
}
```

`CounterLeaf` is a plain `Element` with `@State var count = 0` incremented in `requestLayout` —
copy `StateTests.swift:77`'s `CounterElement` shape into this file rather than widening its
access level.

**If `Box { … }`'s two-statement form does not give `tree.content.first`/`.second`**, check
`Pair`'s member names (`ElementGroup.swift:156-158` declares `public var first` and
`public var second`) and adjust. Report any spelling that differed.

- [ ] **Step 2: Run the tests to verify they behave as expected on arrival**

Run: `swift test --no-parallel --filter ComponentTests 2>&1 | tail -20`

Expected: the five new tests **PASS** on arrival, because Task 1 already built the
mechanism they pin. That is correct and is not a reason to change them — they are bounds on
an implementation that must already exist for the bound to be measurable at all. Their
evidence comes from the mutations in Steps 4-6, not from a red-first cycle.

**If any of the five fails, stop and report before mutating anything.** A failure here means
Task 1's conformance is wrong in a way its own four assertions could not see, which is a
finding about Task 1 rather than a test to adjust.

- [ ] **Step 3: Confirm the count**

Run: `swift test --no-parallel 2>&1 | tail -5`
Expected: `Test run with 800 tests in 1 suite passed after …` (795 + 5).

- [ ] **Step 4: MUTATION — forward to `requestLayout` instead of `requestGroupLayout`**

In `Sources/MetalUI/Component.swift`, this is not a one-line swap (the signatures differ), so instead **delete the `StateBinder.bind(self, …)` call** — the equivalent defect at the component level — and separately confirm the content-level path by whatever minimal edit expresses it.

Run: `swift test --no-parallel 2>&1 | tail -20`

Expected: `aComponentsOwnStateSurvivesAcrossFrames` FAILS with readings `[1, 1, 1]`. **Report the actual readings and which other tests moved.** If it stays green, the state read in Step 2 is not observing what it claims — that is the finding, not a nuisance.

Then mutate the content path: change `materialized.requestGroupLayout(under: id, at: &innerCursor, pass: &pass)` so the content's own elements are not bound (the smallest edit that expresses "content state is not seeded"; describe what you did). Expected: `stateInsideAComponentsContentIsAlsoSeeded` FAILS and `aComponentsOwnStateSurvivesAcrossFrames` stays green — **the two must be reddened by different mutations**, or one of them is proving less than it claims.

Restore and re-run to green.

- [ ] **Step 5: MUTATION — thread the outer cursor into the content**

Replace `var innerCursor = 0` / `at: &innerCursor` with `at: &cursor`.

Run: `swift test --no-parallel 2>&1 | tail -20`
Expected: `twoSiblingComponentsHoldIndependentState` FAILS. **This is the mutation most likely to redden nothing on a single-component fixture** — the two-sibling fixture exists for it. If it stays green, the fixture cannot express the defect (ruling `MP-J`'s shape) and that is the finding. Report the actual output; restore.

- [ ] **Step 6: MUTATION — drop `cursor += 1`**

Run: `swift test --no-parallel 2>&1 | tail -20`
Expected: something reddens. **If this mutation and Step 5's redden exactly the same set of tests, say so explicitly** — it means the two assertions are not separating the two mechanisms, and one of them is weaker than the plan claims. Report; restore.

- [ ] **Step 7: Walk the results back to the lines**

For each of the four mutations, add or amend a comment **at the mutated line** in `Sources/MetalUI/Component.swift` naming the test that reddens and what it reported. Do not leave the numbers only in the report — that is this project's first record-mechanism.

- [ ] **Step 8: Run the whole suite and commit**

Run: `swift test --no-parallel 2>&1 | tail -5`
Expected: `Test run with 800 tests in 1 suite passed after …` (795 + 5).

Confirm `git diff --stat Sources/` shows only the comment amendments from Step 7, then:

```bash
git add Sources/MetalUI/Component.swift Tests/MetalUITests/ComponentTests.swift
git commit -m "test: @State inside a component, and the four mutations that pin it

Identity opacity exists only to make @State work, so these are the assertions
the design rests on. Five tests: the component's own state surviving frames,
state inside its CONTENT being seeded too, two siblings holding independent
state, a named component keeping state through a reorder while an unnamed one
does not, and a childless component still holding state.

Four mutations were run rather than predicted, and the results are recorded at
the mutated lines: dropping the component's own StateBinder.bind, breaking the
content's binding path, threading the outer cursor into the content, and
dropping cursor += 1. The first two must redden DIFFERENT tests, or one of the
two state assertions is proving less than it claims.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01FN1rUy2Qkdyd53wiM3pKnK"
```

---

### Task 3: Modifiers that DISTRIBUTE

**Files:**
- Modify: `Sources/MetalUI/Component.swift`
- Modify: `Tests/MetalUITests/ComponentTests.swift`

**Interfaces:**
- Consumes: `Component`, `ComponentLayout` from Task 1. `LayoutTree.style(_:)` and
  `LayoutTree.setStyle(_:_:)` (`Sources/MetalUILayout/LayoutTree.swift:102-108`).
- Produces: `public struct StyledComponent<C: Component>: ElementGroup` and the modifier
  methods on `Component` that return it.

**This task was rewritten after measurement.** Its first version had modifiers **wrap** the
component in a `Box`. A probe measured SwiftUI and found it **distributes** instead:
`MyRow().padding(8)`, where `MyRow`'s body is a 30×10 and a 50×10 view, is **120×26** —
`(30+16) + 8 + (50+16)` — bit-identical to `Group { A; B }.padding(8)`, where a wrapping
implementation predicts 96–104. Spec §5 carries both measurements.

**The mechanism exists already** (feasibility probe, spec §5): `LayoutTree.setStyle` amends a
registered node's `Style` in place; registration derives nothing from style, so amendment is
sound; its `isLayingOut` precondition is a phase boundary the request walk completes before;
and it operates on raw `LayoutNodeID`s, so it does not care whether a child is a
`StyledElement`. `setStyle` has **zero production callers** today — this is its first.

- [ ] **Step 1: Check what `LayoutPass` already forwards**

Run: `grep -n "func requestNode\|func requestLeaf\|func style\|func setStyle\|var tree\|frame.tree" Sources/MetalUI/Passes.swift`

`LayoutPass` wraps `Frame`, which owns the `LayoutTree`. You need read and write access to a
node's style from inside `requestGroupLayout`. If `LayoutPass` already forwards them, use
what is there. If not, add exactly two forwarding methods mirroring `requestNode`'s shape —
**no more**, and no new capability beyond reading and writing a node's `Style`.

Report which you found and what you added.

- [ ] **Step 2: Write the failing tests**

Append to `Tests/MetalUITests/ComponentTests.swift`:

```swift
// MARK: - Modifiers distribute

/// Spec §5. A modifier on a component applies to EACH top-level node its content
/// contributed, and the component stays layout-transparent — no node is added.
///
/// **Measured against SwiftUI, which is why it is distribution and not wrapping**:
/// `HStack { MyRow().padding(8) }` is 120x26 where `MyRow`'s body is a 30x10 and
/// a 50x10, which is `(30+16) + 8 + (50+16)` — each child padded — and is
/// bit-identical to `Group { A; B }.padding(8)`. Wrapping predicts 96-104.
///
/// **Both halves are asserted and both are needed.** The node count alone cannot
/// tell distribution from a modifier that did nothing at all; the rects alone
/// cannot tell distribution from wrapping in every fixture. Together they can.
@MainActor
@Test func aModifierOnAComponentDistributesToEachTopLevelChild() {
    let bareLog = ComponentLog()
    let bareFrame = Frame(contentSize: Size(width: px(300), height: px(60)), scaleFactor: 1)
    var bare = Row { TwoLeaves(log: bareLog) }
    bareFrame.render(&bare)

    let padLog = ComponentLog()
    let padFrame = Frame(contentSize: Size(width: px(300), height: px(60)), scaleFactor: 1)
    var padded = Row { TwoLeaves(log: padLog).padding(px(4)) }
    padFrame.render(&padded)

    // Transparency survives the modifier: still no node of the component's own.
    #expect(padFrame.tree.nodeCount == bareFrame.tree.nodeCount,
            "a modified component must still add no node; got \(padFrame.tree.nodeCount) against \(bareFrame.tree.nodeCount)")

    // And EACH leaf grew by the padding on both axes — distribution, not one
    // padding around the pair.
    let bareA = rect(bareLog.bounds["a"]!)
    let padA = rect(padLog.bounds["a"]!)
    #expect(padA.2 == bareA.2 + 8, "leaf a's width gains 2x4; got \(padA.2) against \(bareA.2)")
    let bareB = rect(bareLog.bounds["b"]!)
    let padB = rect(padLog.bounds["b"]!)
    #expect(padB.2 == bareB.2 + 8, "leaf b's width gains 2x4 too — this is the assertion \
                                    that separates distribution from wrapping")
}

/// Spec §5's limit. Only `Style`-backed modifiers can be distributed, because
/// `setStyle` reaches `LayoutTree` and nothing reaches `Decoration`/`Handlers`
/// per node. So `background`, `onClick` and `focusable` are NOT offered on a
/// component at all — offering them with wrapping semantics beside a
/// distributing `padding` would be two modifiers that read alike at the call
/// site and behave differently.
///
/// Type-level, because no layout assertion can see an absent method.
@MainActor
@Test func decorationBackedModifiersAreNotOfferedOnAComponent() {
    // `.padding` exists and returns a StyledComponent, not a Box.
    let styled = TwoLeaves(log: ComponentLog()).padding(px(4))
    let name = String(describing: type(of: styled))
    #expect(name.hasPrefix("StyledComponent<"))
    #expect(name.contains("TwoLeaves"))
}
```

**`.background()` must not compile on a component.** Add a `swiftc -typecheck` guard for that
in the style of `Tests/MetalUITests/ErasureCompileGuards.swift`, using the shared
`canTypecheck` machinery in `Tests/MetalUITestSupport/Typecheck.swift`. **That raises the
guard count from 32 to 33** — say so in your report, because that count is quoted in
`CLAUDE.md` and Task 4 must update it. If the guard cannot be written (the probe file cannot
reach the module, the diagnostic text differs), report that rather than dropping the
assertion silently.

- [ ] **Step 3: Run them to verify they fail**

Run: `swift test --no-parallel --filter ComponentTests 2>&1 | tail -20`
Expected: compile failure — `value of type 'TwoLeaves' has no member 'padding'`.

- [ ] **Step 4: Implement `StyledComponent` and the modifiers**

Append to `Sources/MetalUI/Component.swift`:

```swift
/// A component with a `Style` amendment applied to each of its top-level nodes.
///
/// **Modifiers on a `Component` DISTRIBUTE rather than wrap, and that is
/// measured** (spec §5). SwiftUI's `MyRow().padding(8)`, where `MyRow`'s body is
/// a 30x10 and a 50x10 view, measures 120x26 — `(30+16) + 8 + (50+16)`, each
/// child padded — bit-identical to `Group { A; B }.padding(8)`. A wrapping
/// implementation predicts 96-104. The two are one mechanism with §2's
/// transparency: `MyRow()` IS its children, so a modifier applied to it applies
/// to each of them, because there is no single thing to wrap.
///
/// This type contributes **no layout node of its own** — it returns the
/// component's nodes unchanged, having amended their styles — so a modified
/// component is exactly as layout-transparent as a bare one.
///
/// **Only `Style`-backed modifiers can work this way.** `LayoutTree.setStyle`
/// reaches a node's `Style`; nothing reaches `Decoration` or `Handlers` per
/// node, because those are per-ELEMENT state registered by each
/// `StyledElement`'s own `prepaint`. So `background`, `onClick`, `focusable`
/// and `keyContext` are deliberately **not** offered on a component. See the
/// decisions doc for the mechanism that would close it.
public struct StyledComponent<C: Component>: ElementGroup {
    var component: C
    var amend: @Sendable (inout Style) -> Void
    // …requestGroupLayout forwards to `component`, then for each returned node
    //   reads the style, applies `amend`, writes it back with `setStyle`, and
    //   returns the SAME nodes. prepaintGroup/paintGroup forward unchanged.
}

extension Component {
    /// Padding on each top-level child (spec §5). Signature matches
    /// `StyledElement.padding(_ points:)` (`Box.swift:643`) exactly — a
    /// forwarded modifier whose parameter type drifts from its original is
    /// worse than none, because a caller reads the two as the same modifier.
    public func padding(_ points: Pixels) -> StyledComponent<Self> {
        StyledComponent(component: self) { $0.padding = Edges(all: .pixels(points)) }
    }
}
```

**Fill in `requestGroupLayout`/`prepaintGroup`/`paintGroup` yourself** from `Component`'s own
extension as the model — the shape is the same, minus the identity level, because
`StyledComponent` is a modifier and not an element: **it must NOT mint its own
`GlobalElementID` and must NOT call `StateBinder.bind`.** Forward the parent and cursor it was
given straight through to the component, so `MyComponent()` and `MyComponent().padding(4)`
have the **identical** identity — otherwise adding a modifier would silently reset the
component's `@State`, which is the sharpest hazard in this task. Assert that.

**Then choose which further `Style`-backed modifiers to forward** and say why in the report.
Suggested floor: `padding`, `width`, `height`. For each, confirm the `StyledElement` original
is live (has a production reader) rather than in the inert table, and match its signature
exactly. **Do not forward `background`, `onClick`, `focusable`, `keyContext`,
`hoverBackground` or `focusBackground`** — those are `Decoration`/`Handlers`-backed and cannot
distribute.

- [ ] **Step 5: Add the identity test**

```swift
/// A modifier must NOT change a component's identity. `StyledComponent` forwards
/// the parent and cursor it was given straight through, minting no id of its own
/// — so `MyComponent()` and `MyComponent().padding(4)` hold the SAME `@State`.
///
/// If this fails, adding a modifier silently resets a component's state, which
/// is the sharpest hazard in this design and one no rect assertion could see.
@MainActor
@Test func addingAModifierDoesNotResetAComponentsState() {
    // Render a stateful component for two frames unmodified, then a third frame
    // with the SAME component modified, against one shared StateTable. The count
    // must continue rather than restart.
}
```

Write the body using Task 2's `Counter` fixture and the `StateTests.swift:146-152` cross-frame
idiom (thread one `StateTable` through several `Frame`s; read the value back through the
element's own property). If `Counter` is `private` to a different section of the same file it
is reachable; if the shapes do not compose, say what you changed.

- [ ] **Step 6: Run the tests**

Run: `swift test --no-parallel --filter ComponentTests 2>&1 | tail -20`
Expected: all three PASS.

- [ ] **Step 7: MUTATION — make the modifier wrap instead of distribute**

Change `StyledComponent.requestGroupLayout` to return a single wrapping node carrying the
amended style, instead of amending each child's style.

Run: `swift test --no-parallel 2>&1 | tail -20`
Expected: `aModifierOnAComponentDistributesToEachTopLevelChild` FAILS on both halves — the
node count and leaf `b`'s width. **Report the actual output.** If only one half fails, say
which; that tells us which assertion is carrying the claim. Restore and re-run.

- [ ] **Step 8: MUTATION — mint an identity level in `StyledComponent`**

Add a `GlobalElementID.child(of: parent, at: cursor, name: nil)` and `cursor += 1` to
`StyledComponent.requestGroupLayout`, passing the new id down as the component's parent.

Run: `swift test --no-parallel 2>&1 | tail -20`
Expected: `addingAModifierDoesNotResetAComponentsState` FAILS. **If it stays green, that is
the finding** — the identity claim is unpinned and the fixture cannot express it. Report and
restore.

- [ ] **Step 9: Run the whole suite and commit**

Run: `swift test --no-parallel 2>&1 | tail -5`
Expected: `Test run with 804 tests in 1 suite passed after …` (801 + 3). Report the actual
number; the guard added in Step 2 counts toward the total even though it is a compile guard.

Confirm `git diff --stat Sources/` carries no leftover mutation, goldens 87 unmodified, and
`git diff --name-only -- Sources/MetalUILayout/` **empty** — `setStyle` is *called* from
`MetalUI`, not changed in `MetalUILayout`.

```bash
git add Sources/MetalUI/Component.swift Tests/MetalUITests/ComponentTests.swift Tests/MetalUITests/ErasureCompileGuards.swift
git commit -m "feat: modifiers on a Component distribute to each top-level child

Measured against SwiftUI rather than assumed: MyRow().padding(8) is 120x26,
which is (30+16) + 8 + (50+16) — each child padded — and bit-identical to
Group { A; B }.padding(8). A wrapping implementation predicts 96-104. This
replaces the first design, which wrapped in a Box.

StyledComponent amends the style of each node its component contributed and
returns those same nodes, so a modified component stays layout-transparent. It
mints no GlobalElementID and calls no StateBinder.bind, so adding a modifier
does not reset the component's @State — pinned, because no rect assertion could
see that.

The mechanism needed no engine change: LayoutTree.setStyle already existed with
zero production callers, registration derives nothing from style, and its
isLayingOut guard is a phase boundary the request walk completes before.

Only Style-backed modifiers can distribute. Decoration- and Handlers-backed ones
are per-element state with no per-node table, so background/onClick/focusable
are not offered at all rather than offered with different semantics from
padding.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01FN1rUy2Qkdyd53wiM3pKnK"
```

**The demo is NOT converted, and this plan forbids it** even though spec §7 permits it
conditionally. Converting `CounterPanel` to a `Component` adds an identity level, which
changes its `@State` slot ids *and* the `GlobalElementID` its self-focusing `Window.focus(_:)`
call uses. The demo's focus-at-launch behaviour is a documented human-verification item that
took a fix wave to get right once already. Say in the report that the conversion was declined
on this ground rather than not considered.

### Task 4: The record

**Files:**
- Create: `docs/superpowers/2026-09-03-component-decisions.md`
- Modify: `docs/superpowers/specs/2026-08-24-metalui-design.md` — §4.2
- Modify: `CLAUDE.md`

**Interfaces:**
- Consumes: every measurement from Tasks 1-3.

- [ ] **Step 1: Correct design spec §4.2 in place**

`docs/superpowers/specs/2026-08-24-metalui-design.md` §4.2 declares:

```swift
protocol Component: Element {
    associatedtype Content: Element
    @ElementBuilder var content: Content { get }
}
```

**Two things in that are wrong as shipped**, and both must be corrected in place with the original visible, in the `>`-quoted style §4.3 and §9 already use:

- `Component: Element` — it refines `ElementGroup`, so a component can contribute zero or many layout nodes rather than exactly one. That is what layout transparency requires.
- `Content: Element` — a bare `{ Text(…); Text(…) }` block builds a `Pair`, which is an `ElementGroup` and not an `Element`, so under the literal text a component could never have two top-level children.

§4.2 also says the extension "materializes `content` once during `requestLayout`, stashes it in `LayoutState`, and forwards all three phases" — **that half is accurate** and shipped as written (`ComponentLayout.content`). Say so; a correction block that does not distinguish the right half from the wrong half teaches a reader to distrust all of it.

- [ ] **Step 2: Write the decisions doc**

Create `docs/superpowers/2026-09-03-component-decisions.md`, following `docs/superpowers/2026-09-02-reactivity-decisions.md`'s shape: one section per ruling, each with its reasoning and what it costs if wrong. **Prefix every ruling `CO-` and letter them** (`CO-A`, `CO-B`, …), matching this project's convention that a bare `CO-3` is a typo rather than a citation.

At minimum, one ruling each for: layout transparency and why identity opacity is not a
choice; the `StyledElement` rejection with the `display: .flex` mechanism that forces it;
`display: contents` deferred on scope with what it would take; `Content: ElementGroup`
diverging from §4.2; no `.id()` modifier and the defaulted property instead; the demo
conversion declined; and — the two the branch measured rather than assumed — **SwiftUI's
layout transparency, confirmed by probe with its four subview counts and its control**, and
**modifiers distributing rather than wrapping**, with the four sizes, the control, and the
fact that this OVERTURNED the spec's first design. Record `LayoutTree.setStyle` gaining its
first production caller, and the `Decoration`/`Handlers` limit with the mechanism that would
close it.

**Both probes carry a passing positive control and neither is committed** — a committed
version would pin SwiftUI's behaviour rather than this framework's, which is the same footing
this repo uses for WebKit oracle probes. Record the technique so it can be re-run.

Include the **actual** mutation results from Task 2, not the ones this plan predicted.

- [ ] **Step 3: Update `CLAUDE.md`**

Add, in the appropriate existing sections rather than as a new top-level block:

- A `Component` bullet beside the `Stack`/`List`/`Deferred` bullets, leading with the transparent-to-layout / opaque-to-identity pairing, because that is the thing a reader will otherwise get wrong. State that modifiers wrap, and that a modified component is layout-opaque.
- The SwiftUI-flattening claim, **labelled as derived and not measured**, on ruling `RX-P`'s footing.
- A note that `display: contents` does not exist and is what "styled and transparent" would need — so a reader who wants it finds the follow-up rather than re-deriving it.
- The Build section's climb: baseline 791, and the per-task figures each task actually read.

**Do not add rows to the declared-but-inert table** for the forwarded modifiers — they have live originals and real callers in tests. If any forwarded modifier turns out to have no live original, that is a finding: report it and do not forward it.

- [ ] **Step 4: Verify every claim by running it**

For each grep or count this task writes, run it and paste the real output:

```bash
swift test --no-parallel 2>&1 | tail -3
find Tests -name "*.json" | wc -l
git diff --name-only master -- Sources/MetalUILayout/
grep -rn "hasActiveAnimations" Sources/ | wc -l
grep -rn "protocol Component" Sources/
for f in Tests/MetalUITests/PhaseSeparationTests.swift Tests/MetalUITests/ErasureCompileGuards.swift Tests/MetalUITests/ElementGroupTrapTests.swift Tests/MetalUICoreTests/UnitSafetyTests.swift Tests/MetalUITests/AXNodeTests.swift; do echo -n "$f "; grep -c canTypecheck $f; done
```

Expected: the suite line, `87`, **empty** for the layout diff, `0`, one hit in `Component.swift`, and the guard counts summing to 32 (`UnitSafetyTests` reads 3 because one is a comment).

- [ ] **Step 5: Commit**

```bash
git add CLAUDE.md docs/
git commit -m "docs: the Component record, and a correction to design spec 4.2

§4.2 declared \`Component: Element\` with \`Content: Element\`. Both are wrong as
shipped: Component refines ElementGroup so it can contribute zero or many
layout nodes rather than exactly one, and a bare two-statement content block
builds a Pair, which is not an Element — so under the literal text a component
could never have two top-level children. Corrected in place with the original
visible. §4.2's other half — materialize content once and stash it — is
accurate and shipped as written, and the correction says so.

Decisions doc carries rulings CO-A onward with the mutation results actually
observed rather than the ones the plan predicted.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01FN1rUy2Qkdyd53wiM3pKnK"
```

---

## Expected final state

- **804 tests**, 87 goldens, **33** typecheck guards (32 + the one Task 3 adds for
  `.background()` not compiling on a component), warning-free.
- `grep -rn "protocol Component" Sources/` returns one hit, in `Component.swift`.
- `grep -rn "hasActiveAnimations" Sources/` returns **0**.
- `git diff --name-only master..HEAD -- Sources/MetalUILayout/` is **empty**.
- `Component` does not conform to `StyledElement`, and no `Style` property was added anywhere.
- Modifiers on a `Component` **distribute** — `MyComponent().padding(4)` adds no layout node
  and pads each top-level child — and `.background()` does **not** compile on one.
- `LayoutTree.setStyle` has its first production caller; `Sources/MetalUILayout/` is
  nonetheless untouched, because the call is made from `MetalUI`.
- The demo is untouched.
- Design spec §4.2 carries a correction block; `CLAUDE.md` carries the `Component` bullet and the climb.
