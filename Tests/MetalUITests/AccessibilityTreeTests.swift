import Testing
import Metal
import MetalUICore
import MetalUILayout
import MetalUIPlatform
import MetalUIText
@testable import MetalUI

// Lane 1 of the accessibility bridge: the per-frame records, the neutral tree,
// the seam, and requests routed back through `Window`'s dispatch (spec
// `docs/superpowers/specs/2026-09-15-accessibility-bridge-design.md`, "Lane 1").
//
// **Two footings.** Frame-level tests render a bare `Frame` built with
// `collectsAccessibility: true` and hand its records to `AccessibilityTreeBuilder`
// exactly as `Window` does — no Metal device, `AXEmitSiteTests`' footing.
// Window-level tests use `makeFakeWindow` and read what the fake platform was
// handed; each begins with `try #require(MTLCreateSystemDefaultDevice())`.
//
// **Fixture rules.** Every element a published tree must contain has an
// explicit size: `Box().onClick {}` with none is 0×0 under `EP-8`, and a 0×0
// node is published (AB-O) but cannot be told apart by its geometry. Every
// node a later assertion reads is `try #require`d.

private func px(_ v: Float) -> Pixels { Pixels(v) }

private func rect(_ x: Float, _ y: Float, _ w: Float, _ h: Float) -> Bounds<Pixels> {
    Bounds(origin: Point(x: px(x), y: px(y)), size: Size(width: px(w), height: px(h)))
}

/// Declares `node` on a `Box`, through the same `handling` a public modifier
/// writes (`@testable`: no public modifier declares an `AXNode` on lane 1).
@MainActor private func declared<C: ElementGroup>(_ box: Box<C>, _ node: AXNode) -> Box<C> {
    box.handling { $0.axNode = node }
}

/// Renders `element` into a collecting `Frame` and builds the tree the way
/// `Window.drawFrameIfNeeded` does.
@MainActor private func collect<E: Element>(_ element: E, stateTable: StateTable = StateTable(),
                                           width: Float = 300, height: Float = 300)
    -> (Frame, AccessibilityTree) {
    var element = element
    let frame = Frame(contentSize: Size(width: px(width), height: px(height)), scaleFactor: 1,
                      stateTable: stateTable, theme: Theme.forAppearance(.light),
                      collectsAccessibility: true)
    frame.render(&element)
    let tree = AccessibilityTreeBuilder.build(emissions: frame.axEmissions,
                                              focused: frame.focusedElement,
                                              hitboxes: frame.hitboxes,
                                              focusRegistry: frame.focusRegistry)
    return (frame, tree)
}

private extension AccessibilityTree {
    /// The one node carrying `label`, or `nil` when none or several do.
    func id(labelled label: String) -> AccessibilityNodeID? {
        let matches = nodes.filter { $0.value.label == label }
        return matches.count == 1 ? matches.first?.key : nil
    }
}

private extension AccessibilityNodeID {
    var gid: GlobalElementID? { base as? GlobalElementID }
}

/// Draws until the window reports clean, at most `limit` times.
@MainActor private func drawUntilClean(_ window: Window, limit: Int = 5) {
    for _ in 0..<limit where window.needsRedraw { window.drawFrameIfNeeded() }
}

@MainActor private final class Tally {
    var count = 0
    var directions: [AccessibilityAdjustmentDirection] = []
}

private struct Item: Identifiable { let id: Int }

// MARK: - Records (AB-U, AB-B)

/// With no client, a frame records nothing; while collecting it records the
/// synthesized node and still writes neither `axNodes` nor a `$ax` slot.
@Test @MainActor func aFrameThatDoesNotCollectRecordsNothingAndSynthesisWritesNoRetentionSlot() {
    func tree() -> some Element { Box().width(px(40)).height(px(20)).onClick {}.focusable() }
    let rootID = GlobalElementID.child(of: nil, at: 0, name: nil)
    let axSlot = GlobalElementID.child(of: rootID, at: 0, name: ElementID("$ax"))

    let idleTable = StateTable()
    var idle = tree()
    let idleFrame = Frame(contentSize: Size(width: px(300), height: px(300)), scaleFactor: 1,
                          stateTable: idleTable, theme: Theme.forAppearance(.light))
    idleFrame.render(&idle)
    #expect(idleFrame.axNodes.isEmpty)
    #expect(idleFrame.axEmissions.isEmpty, "a frame with no client records nothing")
    #expect(idleTable.peek(axSlot, as: AXNode.self) == nil)

    let activeTable = StateTable()
    let (activeFrame, _) = collect(tree(), stateTable: activeTable)
    #expect(activeFrame.axEmissions.count == 1, "the clickable, focusable box has something to say")
    #expect(activeFrame.axNodes.isEmpty, "a synthesized node is a record, never an emission (AB-U)")
    #expect(activeTable.peek(axSlot, as: AXNode.self) == nil, "and it writes no $ax retention slot")
    #expect(activeTable.count == idleTable.count,
            "a client must not change what the state table retains")
}

/// Three drawn frames of a tree that would record (a `List` and a sized click
/// target) with no activation: nothing is collected, built or published.
@Test @MainActor func anInactiveWindowBuildsAndPublishesNothing() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let items = (0..<50).map(Item.init)
    let (window, platform) = try makeFakeWindow(device: device, size: 200) {
        Column {
            Box {
                ScrollView(.vertical) {
                    List(items, rowHeight: px(28)) { _ in Box().width(px(20)).height(px(28)) }
                }
            }.width(px(100)).height(px(100))
            Box().width(px(40)).height(px(20)).onClick {}
        }
    }
    for _ in 0..<3 {
        window.setNeedsRedraw()
        window.drawFrameIfNeeded()
    }
    #expect(window.framesDrawn == 3, "control: three frames really drew")
    #expect(platform.publishedAccessibilityTrees.isEmpty)
    #expect(window.accessibility.buildCount == 0)
    #expect(window.accessibility.lastEmissionCount == 0,
            "an inactive window's frames record nothing, so the build autoclosure is not the only guard")
}

/// `.activate` dirties a clean window, its next frame publishes, and a second
/// `.activate` changes nothing.
@Test @MainActor func anActivationRequestDirtiesACleanWindowAndItsNextFramePublishes() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let (window, platform) = try makeFakeWindow(device: device, size: 200) {
        Column { Box().width(px(40)).height(px(20)).onClick {} }
    }
    drawUntilClean(window)
    try #require(!window.needsRedraw, "precondition: the window is clean")

    #expect(platform.simulateAccessibilityRequest(.activate))
    #expect(window.needsRedraw, "activation must dirty the window, or nothing collects until input")
    window.drawFrameIfNeeded()

    try #require(platform.publishedAccessibilityTrees.count == 1)
    let tree = platform.publishedAccessibilityTrees[0]
    let button = try #require(tree.geometry.first {
        $0.value.frame.size == Size(width: px(40), height: px(20))
    }?.key)
    #expect(tree.nodes[button]?.role == .button, "an onClick box is a button on lane 1")

    drawUntilClean(window)
    try #require(!window.needsRedraw)
    #expect(platform.simulateAccessibilityRequest(.activate), "activation is sticky and still answers true")
    #expect(!window.needsRedraw, "a second activation must not dirty the window")
}

// MARK: - Hierarchy (AB-C, AB-V)

/// `TB-M`'s counterexample: named children in either order give the same key
/// set, and record order still tells them apart.
@Test @MainActor func childrenFollowDeclarationOrderWhereIDsAloneCannot() throws {
    func container(swapped: Bool) -> some Element {
        let x = declared(Box().width(px(10)).height(px(10)).id("x"), AXNode(label: "x"))
        let y = declared(Box().width(px(10)).height(px(10)).id("y"), AXNode(label: "y"))
        return declared(Box {
            if swapped { y; x } else { x; y }
        }.width(px(100)).height(px(50)), AXNode(role: .container, label: "c"))
    }
    for swapped in [false, true] {
        let (_, tree) = collect(container(swapped: swapped))
        let c = try #require(tree.id(labelled: "c"))
        #expect(tree.roots == [c])
        let labels = try #require(tree.nodes[c]).children.map { tree.nodes[$0]?.label }
        #expect(labels == (swapped ? ["y", "x"] : ["x", "y"]),
                "children must follow declaration order (swapped: \(swapped))")
    }
}

/// A container that records nothing is transparent: the declared box inside a
/// `Column` inside a declared box is the outer box's child.
@Test @MainActor func aNodesParentIsItsNearestEmittingAncestor() throws {
    let (_, tree) = collect(declared(Box {
        Column { declared(Box().width(px(10)).height(px(10)), AXNode(label: "inner")) }
    }.width(px(100)).height(px(100)), AXNode(role: .container, label: "outer")))
    let outer = try #require(tree.id(labelled: "outer"))
    let inner = try #require(tree.id(labelled: "inner"))
    #expect(tree.roots == [outer])
    #expect(tree.nodes[outer]?.children == [inner])
    #expect(tree.nodes.count == 2, "the Column records nothing and publishes nothing")
    #expect(inner.gid?.parent != outer.gid,
            "control: the inner box's id parent is the Column, so one parent step does not reach the outer box")
}

/// `Deferred` content is hoisted, so it is a root even when an emitting
/// ancestor declares it (AB-V).
@Test @MainActor func portalContentIsARootEvenWhenDeclaredInsideAnEmittingAncestor() throws {
    let (_, tree) = collect(declared(Box {
        Deferred { declared(Box().width(px(30)).height(px(10)), AXNode(label: "Tip")) }
    }.width(px(40)).height(px(20)), AXNode(role: .button, label: "B")))
    let button = try #require(tree.id(labelled: "B"))
    let tip = try #require(tree.id(labelled: "Tip"))
    #expect(tree.roots == [button, tip])
    #expect(tree.nodes[button]?.children == [])
}

// MARK: - Roles, labels, values, traits (AB-F, AB-L)

/// What a node declared reaches the published node field by field, with a
/// distinct value in every field (taxonomy shape 1).
///
/// **Not in the spec's lane-1 table, added by the implementer**: without it the
/// builder's role map beyond `.button`/`.table`, its `value` copy and both trait
/// mappings had no lane-1 pin. Green on arrival (written after the builder);
/// its evidence is the mutations named in the record.
@Test @MainActor func declaredRolesLabelsValuesAndTraitsReachThePublishedNode() throws {
    let (_, tree) = collect(Column {
        declared(Box().width(px(10)).height(px(10)),
                 AXNode(role: .text, label: "L1", value: "V1", traits: [.selected]))
        declared(Box().width(px(10)).height(px(10)),
                 AXNode(role: .image, label: "L2", value: "V2", traits: [.disabled, .updatesFrequently]))
        declared(Box().width(px(10)).height(px(10)), AXNode(role: .generic, label: "L3"))
        declared(Box().width(px(10)).height(px(10)).onClick {}, AXNode(role: .container, label: "L4"))
        declared(Box().width(px(10)).height(px(10)).onClick {}, AXNode(role: .generic, label: "L5"))
    })
    let text = try #require(tree.id(labelled: "L1").flatMap { tree.nodes[$0] })
    let image = try #require(tree.id(labelled: "L2").flatMap { tree.nodes[$0] })
    let generic = try #require(tree.id(labelled: "L3").flatMap { tree.nodes[$0] })
    let clickableContainer = try #require(tree.id(labelled: "L4").flatMap { tree.nodes[$0] })
    let clickableGeneric = try #require(tree.id(labelled: "L5").flatMap { tree.nodes[$0] })

    #expect(text.role == .staticText && text.value == "V1")
    #expect(text.isSelected && text.isEnabled)
    #expect(image.role == .image && image.value == "V2")
    #expect(!image.isSelected && !image.isEnabled, "a declared .disabled trait disables the node")
    #expect(generic.role == .group && generic.value == nil && generic.actions == [])
    #expect(clickableContainer.role == .group && clickableContainer.actions == [.press],
            "a declared container stays a group even when clickable")
    #expect(clickableGeneric.role == .button && clickableGeneric.actions == [.press],
            "an undeclared-role click target is a button")
}

// MARK: - Geometry (AB-E, AB-W, AB-K)

/// A node inside a scrolled `ScrollView` reports where it is on screen, not
/// where it is in content space (`AB-E`).
///
/// A 100pt-tall `ScrollView` over 400pt of content, scrolled by 40. The target
/// box sits at content y = 100, so on screen it is at 100 - 40 = 60.
///
/// **The first half compiles on `f64e58a` and was run red there first**:
/// `frame.axNodes[target].frame.origin.y` read 100 (record, lane 1).
@Test @MainActor func aNodeInsideAScrolledScrollViewReportsItsOnScreenFrame() throws {
    func makeTree() -> some Element {
        ScrollView(.vertical, elementID: ElementID("outer")) {
            declared(Box().width(px(20)).height(px(20)), AXNode(role: .button, label: "top"))
            Box().width(px(20)).height(px(80))
            declared(Box().width(px(20)).height(px(20)), AXNode(role: .button, label: "target"))
            Box().width(px(20)).height(px(280))
        }
    }
    let stateTable = StateTable()
    var unscrolled = makeTree()
    let frame1 = Frame(contentSize: Size(width: px(200), height: px(100)), scaleFactor: 1,
                       stateTable: stateTable, theme: Theme.forAppearance(.light))
    frame1.render(&unscrolled)
    let target1 = try #require(frame1.axNodes.values.first { $0.label == "target" })
    try #require(target1.frame.origin.y == 100, "control: the target sits at content y = 100 unscrolled")

    let outerID = try #require(frame1.scrollRegions.first).id
    stateTable.withState(outerID, initial: ScrollState()) { $0.offset = 40 }

    var scrolled = makeTree()
    let frame2 = Frame(contentSize: Size(width: px(200), height: px(100)), scaleFactor: 1,
                       stateTable: stateTable, theme: Theme.forAppearance(.light))
    frame2.render(&scrolled)
    let target2 = try #require(frame2.axNodes.values.first { $0.label == "target" })
    #expect(target2.frame.origin.y == 60,
            "the emitted frame must carry the scroll translation, as the hitbox does")

    // The published half: the same scroll, collected.
    let (_, tree) = collect(makeTree(), stateTable: stateTable, width: 200, height: 100)
    let target = try #require(tree.id(labelled: "target"))
    let top = try #require(tree.id(labelled: "top"))
    let targetGeometry = try #require(tree.geometry[target])
    let topGeometry = try #require(tree.geometry[top])
    #expect(targetGeometry.frame == rect(0, 60, 20, 20))
    #expect(targetGeometry.visibleFrame == rect(0, 60, 20, 20), "control: wholly inside the viewport")
    #expect(topGeometry.frame == rect(0, -40, 20, 20), "frame is unclipped (AB-E)")
    #expect(topGeometry.visibleFrame.size.height == 0,
            "visibleFrame is clipped to the viewport, and this box is scrolled fully out (AB-W)")

    // Geometry is not structure (AB-K): the same tree unscrolled differs only in frames.
    stateTable.withState(outerID, initial: ScrollState()) { $0.offset = 0 }
    let (_, unscrolledTree) = collect(makeTree(), stateTable: stateTable, width: 200, height: 100)
    try #require(unscrolledTree != tree, "control: the two trees really differ")
    #expect(unscrolledTree.hasSameStructure(as: tree), "a scroll that changes only frames is not structural")
    var relabelled = tree
    relabelled.nodes[target]?.label = "moved"
    #expect(!relabelled.hasSameStructure(as: tree), "a label is structure")
}

// MARK: - Actions (AB-H, AB-I)

/// A press runs `onClick` through the last frame's hitboxes; a node with no
/// click handler advertises no press and refuses one.
@Test @MainActor func aPressRequestRunsOnClickThroughTheLastFramesHitboxes() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let tally = Tally()
    let (window, platform) = try makeFakeWindow(device: device, size: 200) {
        Column {
            declared(Box().width(px(40)).height(px(20)).onClick { tally.count += 1 },
                     AXNode(role: .button, label: "clickable"))
            declared(Box().width(px(40)).height(px(20)), AXNode(role: .button, label: "inert"))
        }
    }
    platform.simulateAccessibilityRequest(.activate)
    drawUntilClean(window)
    let tree = try #require(platform.publishedAccessibilityTrees.last)
    let clickable = try #require(tree.id(labelled: "clickable"))
    let inert = try #require(tree.id(labelled: "inert"))
    #expect(tree.nodes[clickable]?.actions == [.press])
    #expect(tree.nodes[inert]?.actions == [], "a declared node with no onClick advertises no press")
    try #require(!window.needsRedraw)

    #expect(platform.simulateAccessibilityRequest(.press(clickable)))
    #expect(tally.count == 1)
    #expect(window.needsRedraw, "a press may have changed anything, so the window is dirtied")

    #expect(!platform.simulateAccessibilityRequest(.press(inert)))
    #expect(tally.count == 1)
}

/// A test-local wrapper that disables hit testing for its one child, the way
/// the proposal path's `allowsHitTesting(false)` does. The legacy path has no
/// such modifier.
private struct HitTestingDisabled<Content: Element>: Element {
    var content: Content

    mutating func requestLayout(_ id: GlobalElementID, pass: inout LayoutPass)
        -> (LayoutNodeID, Content.GroupLayout) {
        var cursor = 0
        let (nodes, layout) = content.requestGroupLayout(under: id, at: &cursor, pass: &pass)
        return (nodes[0], layout)
    }

    mutating func prepaint(_ id: GlobalElementID, bounds: Bounds<Pixels>,
                           layout: inout Content.GroupLayout,
                           pass: inout PrepaintPass) -> Content.GroupPrepaint {
        var result: Content.GroupPrepaint?
        pass.allowsHitTesting(false) {
            result = content.prepaintGroup(layout: &layout, pass: &pass)
        }
        return result!
    }

    mutating func paint(_ id: GlobalElementID, bounds: Bounds<Pixels>,
                        layout: inout Content.GroupLayout,
                        prepaint: inout Content.GroupPrepaint, pass: inout PaintPass) {
        content.paintGroup(layout: &layout, prepaint: &prepaint, pass: &pass)
    }
}

/// `allowsHitTesting(false)` removes the press exactly as it removes the click.
@Test @MainActor func aPressIsRefusedWhereHitTestingIsDisabled() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let disabled = Tally()
    let enabled = Tally()
    let (window, platform) = try makeFakeWindow(device: device, size: 200) {
        Column {
            HitTestingDisabled(content: declared(
                Box().width(px(40)).height(px(20)).onClick { disabled.count += 1 },
                AXNode(role: .button, label: "off")))
            declared(Box().width(px(40)).height(px(20)).onClick { enabled.count += 1 },
                     AXNode(role: .button, label: "on"))
        }
    }
    platform.simulateAccessibilityRequest(.activate)
    drawUntilClean(window)
    let tree = try #require(platform.publishedAccessibilityTrees.last)
    let off = try #require(tree.id(labelled: "off"))
    let on = try #require(tree.id(labelled: "on"))

    #expect(tree.nodes[off]?.actions == [])
    #expect(!platform.simulateAccessibilityRequest(.press(off)))
    #expect(disabled.count == 0)

    #expect(tree.nodes[on]?.actions == [.press], "control: the same box without the wrapper")
    #expect(platform.simulateAccessibilityRequest(.press(on)))
    #expect(enabled.count == 1)
}

/// An element that registers an `AccessibilityAdjustment` handler advertises
/// increment and decrement, and each request runs it with its direction.
@Test @MainActor func anIncrementRequestRunsTheAdjustmentHandler() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let tally = Tally()
    let (window, platform) = try makeFakeWindow(device: device, size: 200) {
        Column {
            declared(Box().width(px(40)).height(px(20))
                .onAction(AccessibilityAdjustment.self) { tally.directions.append($0.direction) },
                     AXNode(label: "adjustable"))
            declared(Box().width(px(40)).height(px(20)), AXNode(label: "plain"))
        }
    }
    platform.simulateAccessibilityRequest(.activate)
    drawUntilClean(window)
    let tree = try #require(platform.publishedAccessibilityTrees.last)
    let adjustable = try #require(tree.id(labelled: "adjustable"))
    let plain = try #require(tree.id(labelled: "plain"))

    #expect(tree.nodes[adjustable]?.actions == [.increment, .decrement])
    #expect(tree.nodes[plain]?.actions == [])
    #expect(platform.simulateAccessibilityRequest(.increment(adjustable)))
    #expect(platform.simulateAccessibilityRequest(.decrement(adjustable)))
    #expect(tally.directions == [.increment, .decrement])

    #expect(!platform.simulateAccessibilityRequest(.increment(plain)))
    #expect(!platform.simulateAccessibilityRequest(.decrement(plain)))
    #expect(tally.directions == [.increment, .decrement])
}

// MARK: - Focus (AB-J)

/// The published focus is the window's focus after the frame's read-back, and
/// a focus request moves it only onto something the last frame found focusable.
@Test @MainActor func publishedFocusIsTheWindowsFocusAndAFocusRequestMovesIt() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let (window, platform) = try makeFakeWindow(device: device, size: 200) {
        Column {
            declared(Box().width(px(40)).height(px(20)).focusable(), AXNode(label: "a"))
            declared(Box().width(px(40)).height(px(20)).focusable(), AXNode(label: "b"))
            declared(Box().width(px(40)).height(px(20)), AXNode(label: "c"))
        }
    }
    platform.simulateAccessibilityRequest(.activate)
    drawUntilClean(window)
    let first = try #require(platform.publishedAccessibilityTrees.last)
    let a = try #require(first.id(labelled: "a"))
    let b = try #require(first.id(labelled: "b"))
    let c = try #require(first.id(labelled: "c"))
    #expect(first.nodes[a]?.isFocusable == true && first.nodes[c]?.isFocusable == false)
    #expect(first.focused == nil)

    let aID: GlobalElementID = try #require(a.gid)
    window.focus(aID)
    drawUntilClean(window)
    #expect(platform.publishedAccessibilityTrees.last?.focused == a)

    #expect(platform.simulateAccessibilityRequest(.focus(b)))
    drawUntilClean(window)
    #expect(platform.publishedAccessibilityTrees.last?.focused == b)
    #expect(window.focusedElement == b.gid)

    #expect(!platform.simulateAccessibilityRequest(.focus(c)), "c is not focusable")
    #expect(window.focusedElement == b.gid, "a refused focus request leaves focus alone")

    // Focus handed to a frame that clears it: the published focus is the
    // read-back (nil), not what the frame was handed (c, which did publish).
    let cID: GlobalElementID = try #require(c.gid)
    window.focus(cID)
    drawUntilClean(window)
    #expect(window.focusedElement == nil, "control: the frame cleared the non-focusable focus")
    #expect(platform.publishedAccessibilityTrees.last?.focused == nil)
}

// MARK: - Publishing (AB-M)

/// A component whose declared label is `@State`, renamed by its own click.
private struct PressToRename: Component {
    @State var label = "before"

    var content: some ElementGroup {
        declared(Box().width(px(40)).height(px(20)).onClick { label = "after" },
                 AXNode(role: .button, label: label))
    }
}

/// A frame that builds the same tree does not republish it; a label change does.
@Test @MainActor func anUnchangedFrameIsNotRepublished() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let (window, platform) = try makeFakeWindow(device: device, size: 200) {
        Column { PressToRename() }
    }
    platform.simulateAccessibilityRequest(.activate)
    drawUntilClean(window)
    let buildsAfterFirst = window.accessibility.buildCount
    try #require(buildsAfterFirst >= 1)
    #expect(window.accessibility.publishCount == 1)

    window.setNeedsRedraw()
    window.drawFrameIfNeeded()
    #expect(window.accessibility.buildCount == buildsAfterFirst + 1, "every active frame builds")
    #expect(window.accessibility.publishCount == 1, "an identical tree is not republished")
    #expect(platform.publishedAccessibilityTrees.count == 1)

    let tree = try #require(platform.publishedAccessibilityTrees.last)
    let button = try #require(tree.id(labelled: "before"))
    #expect(platform.simulateAccessibilityRequest(.press(button)))
    drawUntilClean(window)
    #expect(window.accessibility.publishCount == 2)
    #expect(platform.publishedAccessibilityTrees.last?.nodes[button]?.label == "after")
}

// MARK: - What is and is not published (AB-O, AB-L)

/// `display: none` content records nothing; a zero-height node is published;
/// two siblings sharing an `.id` publish one node, once.
@Test @MainActor func hiddenContentIsNotPublishedButAZeroHeightNodeIsAndADuplicatedIDIsPublishedOnce() throws {
    let (frame, tree) = collect(Column {
        Box { declared(Box().width(px(10)).height(px(10)), AXNode(label: "in")) }
            .width(px(20)).height(px(20)).hidden()
        declared(Box().width(px(20)).height(px(0)), AXNode(label: "divider"))
        Row {
            declared(Box().width(px(10)).height(px(10)).id("x"), AXNode(label: "x-first"))
            declared(Box().width(px(10)).height(px(10)).id("x"), AXNode(label: "x-last"))
        }
    })
    #expect(frame.axNodes.values.contains { $0.label == "in" },
            "control: the hidden node is still emitted as today; only the record is suppressed")
    #expect(!tree.nodes.values.contains { $0.label == "in" }, "display: none content is not published")

    let divider = try #require(tree.id(labelled: "divider"))
    #expect(tree.geometry[divider]?.frame.size.height == 0, "a zero-height node is published (arm R6)")

    let x = try #require(tree.id(labelled: "x-last"), "one node per id, with its last content")
    #expect(!tree.nodes.values.contains { $0.label == "x-first" })
    #expect(tree.roots == [divider, x], "published once, at its first position")
}

/// A `List` publishes a table whose row count is its logical count, even when a
/// caller declared a label and so left its role `generic` (AB-L, arm R16).
@Test @MainActor func aLabelledListIsStillATable() throws {
    let items = (0..<500).map(Item.init)
    let (_, tree) = collect(
        List(items, rowHeight: px(28)) { _ in Box().width(px(20)).height(px(28)) }
            .handling { $0.axNode.label = "Contacts" })
    let list = try #require(tree.id(labelled: "Contacts"))
    #expect(tree.nodes[list]?.role == .table)
    #expect(tree.nodes[list]?.rowCount == 500)
}
