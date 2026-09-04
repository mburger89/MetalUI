import Testing
import MetalUICore
import MetalUILayout
@testable import MetalUI

// M4 spec 2. A `Component` is TRANSPARENT to layout and OPAQUE to identity:
// it contributes no layout node of its own, and it consumes one cursor index so
// that its `@State` has an id to hang on. Those are separate axes and this is
// the first type in the framework to use them differently — every other element
// is opaque to both. **This file pins the layout-transparency half only.** The
// identity-opaque half's own mechanics — the cursor arithmetic that gives a
// component an id, `content` materialized once rather than re-evaluated per
// phase — are Task 2's `ComponentTests` additions to pin, not this file's.
//
// The assertions below are structural and geometric together. A component that
// wrongly contributed its own flex container would still produce the right
// CHILD COUNT in some trees while moving every rect, so counting alone cannot
// see the defect this file exists to prevent — but the geometry only sees it
// when the fixture's leaves DISAGREE in height; see `TwoLeaves`' own doc for
// the mutation that found this the hard way.
//
// **Node-count spelling.** `frame.layoutNodeCount` does not exist on `Frame`.
// `LayoutTree.nodeCount` does (`Sources/MetalUILayout/LayoutTree.swift:59`,
// `public var nodeCount: Int { styles.count }`), and `Frame.tree` is an
// internal, unqualified `let` (`Sources/MetalUI/Frame.swift:123`) — reachable
// here only because this file is `@testable import MetalUI`. `frame.tree.nodeCount`
// is also the exact idiom the existing suite already uses for this question
// (`Tests/MetalUITests/ElementLayoutTests.swift:365`), so this file matches it
// rather than inventing a second spelling.

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
///
/// **`a` and `b` have DIFFERENT heights, and that is load-bearing.** A wrapping
/// node built from a default `Style` is an `auto`-sized flex row, and with
/// equal-height leaves it shrink-wraps to exactly the leaves' own extent and
/// the outer `Row` centres it to the same `y` the leaves would have gotten
/// directly — so a component that wrongly wraps its content is byte-identical
/// on rects to a correct one, and only the node COUNT would tell them apart.
/// Measured: with both leaves at height 10, mutating `requestGroupLayout` to
/// wrap `nodes` in `pass.requestNode(style: Style(), children: nodes)` left
/// both rect-based tests below green. With `b` at 30, the wrapper's own cross
/// size (30, from its tallest child) no longer matches the outer `Row`'s
/// height (40), so `a` centres at a different `y` when it is laid out
/// directly under the `Row` (15) than when it is laid out under an
/// intervening 30-tall wrapper (5) — the two cases separate.
private struct TwoLeaves: Component {
    let log: ComponentLog
    var elementID: ElementID?

    var content: some ElementGroup {
        Leaf("a", log: log).width(px(30)).height(px(10))
        Leaf("b", log: log).width(px(50)).height(px(30))
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
/// `registered` alone cannot see the defect — but `TwoLeaves`' own doc records
/// why an equal-height fixture would have let the rects agree anyway; `a` and
/// `b` differ in height precisely so a wrapping node's own cross size (bounded
/// by its tallest child) pulls `a`'s `y` away from what the `Row` would give it
/// directly.
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
        Leaf("b", log: inlineLog).width(px(50)).height(px(30))
    }
    inlineFrame.render(&inline)

    #expect(componentLog.registered == ["a", "b"])
    #expect(componentLog.registered == inlineLog.registered)
    // The differential IS the assertion: a wrapped component and the inline
    // spelling must be geometrically indistinguishable.
    #expect(rect(componentLog.bounds["a"]!) == rect(inlineLog.bounds["a"]!))
    #expect(rect(componentLog.bounds["b"]!) == rect(inlineLog.bounds["b"]!))
    // Literal numbers alongside, because two runs of a broken engine agree with
    // each other. A 40-tall row centres each leaf INDEPENDENTLY on the cross
    // axis (ruling EP-8): the 10-tall `a` at y = 15, the 30-tall `b` at y = 5.
    #expect(rect(componentLog.bounds["a"]!) == (0, 15, 30, 10))
    #expect(rect(componentLog.bounds["b"]!) == (30, 5, 50, 30))
}

/// Spec §2. The node count for a tree holding a component equals the count for
/// the same tree written inline. This is the direct form of "contributes no
/// layout node", and it is the assertion a wrapping node reddens first.
@MainActor
@Test func aComponentContributesNoLayoutNodeOfItsOwn() {
    let frame = Frame(contentSize: Size(width: px(300), height: px(40)), scaleFactor: 1)
    var withComponent = Row { TwoLeaves(log: ComponentLog()) }
    frame.render(&withComponent)
    let withCount = frame.tree.nodeCount

    let inlineFrame = Frame(contentSize: Size(width: px(300), height: px(40)), scaleFactor: 1)
    let log = ComponentLog()
    var inline = Row {
        Leaf("a", log: log).width(px(30)).height(px(10))
        Leaf("b", log: log).width(px(50)).height(px(30))
    }
    inlineFrame.render(&inline)

    #expect(withCount == inlineFrame.tree.nodeCount,
            "a component must add no layout node; got \(withCount) against \(inlineFrame.tree.nodeCount)")
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
    #expect(rect(log.bounds["b"]!) == (30, 5, 50, 30))
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

    #expect(frame.tree.nodeCount == bareFrame.tree.nodeCount)
}
