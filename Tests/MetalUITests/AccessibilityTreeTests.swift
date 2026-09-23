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
/// **`authority` since stage 4's lane 4**: `aLabelledListIsStillATable` is this
/// file's one `List` test that can pin anything about a table (its other `List`
/// usage asserts absence), and it runs under both. Every other caller takes the
/// default `.legacy`.
@MainActor private func collect<E: Element>(_ element: E, stateTable: StateTable = StateTable(),
                                           width: Float = 300, height: Float = 300,
                                           focusedElement: GlobalElementID? = nil,
                                           authority: LayoutAuthority = .legacy)
    -> (Frame, AccessibilityTree) {
    var element = element
    let frame = Frame(contentSize: Size(width: px(width), height: px(height)), scaleFactor: 1,
                      stateTable: stateTable, theme: Theme.forAppearance(.light),
                      focusedElement: focusedElement, collectsAccessibility: true,
                      layoutAuthority: authority)
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
    var first = 0
    var last = 0
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

/// Each live handler **alone** makes an undeclared element record: a click
/// target, a focusable element, an adjustable element. A plain sized box
/// records nothing.
///
/// Every other fixture that uses `focusable()` or an adjustment also declares
/// an `AXNode` or an `onClick`, so dropping either term from the synthesis
/// condition reddened nothing (hunting mutants H05, H06; record, lane 1).
@Test @MainActor func eachLiveHandlerAloneMakesAnUndeclaredElementRecord() throws {
    let column = GlobalElementID.child(of: nil, at: 0, name: nil)
    let (frame, tree) = collect(Column {
        Box().width(px(10)).height(px(10)).onClick {}
        Box().width(px(10)).height(px(10)).focusable()
        Box().width(px(10)).height(px(10)).onAction(AccessibilityAdjustment.self) { _ in }
        Box().width(px(10)).height(px(10))
    })
    let recorded = frame.axEmissions.map(\.id)
    #expect(recorded == (0..<3).map { GlobalElementID.child(of: column, at: $0, name: nil) },
            "click, focus and adjustment each record; the plain fourth box does not")
    #expect(frame.axNodes.isEmpty, "control: nothing here declared a node")
    try #require(tree.nodes.count == 3)
    let focusable = AccessibilityNodeID(GlobalElementID.child(of: column, at: 1, name: nil))
    let adjustable = AccessibilityNodeID(GlobalElementID.child(of: column, at: 2, name: nil))
    #expect(tree.nodes[focusable]?.isFocusable == true)
    #expect(tree.nodes[adjustable]?.actions == [.increment, .decrement])
    #expect(tree.nodes.values.allSatisfy { $0.label == nil && $0.value == nil },
            "a synthesized node declared no label, and publishes none rather than an empty one")
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
///
/// **Six children in two unsorted orders, one the other's reverse.** With two,
/// a mutant iterating the record dictionary's keys (M08) matched declaration
/// order by chance in both arms and survived twice: `Dictionary` order is
/// per-process, so a two-child fixture's kill was luck. Six give 720 orders; a
/// hash order matching one arm matches the other only if it is its own reverse.
@Test @MainActor func childrenFollowDeclarationOrderWhereIDsAloneCannot() throws {
    func child(_ name: String) -> Box<EmptyGroup> {
        declared(Box().width(px(10)).height(px(10)).id(name), AXNode(label: name))
    }
    func container(reversed: Bool) -> some Element {
        declared(Box {
            if reversed {
                child("b"); child("e"); child("c"); child("f"); child("a"); child("d")
            } else {
                child("d"); child("a"); child("f"); child("c"); child("e"); child("b")
            }
        }.width(px(100)).height(px(50)), AXNode(role: .container, label: "container"))
    }
    let declaredOrder = ["d", "a", "f", "c", "e", "b"]
    for reversed in [false, true] {
        let (_, tree) = collect(container(reversed: reversed))
        let c = try #require(tree.id(labelled: "container"))
        #expect(tree.roots == [c])
        let labels = try #require(tree.nodes[c]).children.map { tree.nodes[$0]?.label }
        #expect(labels == (reversed ? declaredOrder.reversed() : declaredOrder),
                "children must follow declaration order (reversed: \(reversed))")
        // Lane 2 (AB-W): `order` is the record position the hit test breaks
        // layer ties on, so it rises through pre-order — the container first,
        // then its children in declaration order. A builder filling 0 reddens.
        let ordered = [c] + (try #require(tree.nodes[c])).children
        let orders = ordered.map { tree.geometry[$0]?.order }
        #expect(orders == Array(0..<7), "order must rise through record order (reversed: \(reversed))")
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
/// ancestor declares it (AB-V) — and leaving the portal restores the ancestor's
/// portal, so a sibling declared after the `Deferred` is that ancestor's child.
///
/// **The trailing sibling is the leaving half's only pin**: with the portal
/// never popped, `after` keeps the `Deferred`'s ordinal, finds no ancestor in
/// it, and becomes a root.
///
/// **`after` is focusable since lane 3** (ruling AB-AG): a button whose
/// descendants are all non-interactive folds them into its label and publishes
/// no children (AB-G), which would hide the very child this test reads. An
/// interactive descendant keeps the button's children.
@Test @MainActor func portalContentIsARootEvenWhenDeclaredInsideAnEmittingAncestor() throws {
    let (_, tree) = collect(declared(Box {
        Deferred { declared(Box().width(px(30)).height(px(10)), AXNode(label: "Tip")) }
        declared(Box().width(px(10)).height(px(10)).focusable(), AXNode(label: "after"))
    }.width(px(40)).height(px(20)), AXNode(role: .button, label: "B")))
    let button = try #require(tree.id(labelled: "B"))
    let tip = try #require(tree.id(labelled: "Tip"))
    let after = try #require(tree.id(labelled: "after"))
    #expect(tree.roots == [button, tip])
    #expect(tree.nodes[button]?.children == [after],
            "content declared after a Deferred is back in its ancestor's portal")
    // Lane 2 (AB-W): the hit test ranks on the layer first, so portal content
    // carries `Frame.rootLayer` and what it covers carries 0. A geometry
    // filling 0 for the layer reddens the tip.
    #expect(try #require(tree.geometry[tip]).layer == Frame.rootLayer)
    #expect(try #require(tree.geometry[button]).layer == 0)
    #expect(try #require(tree.geometry[after]).layer == 0, "leaving the portal leaves its layer")
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

    // The published half: the same scroll, collected. Stage 6b (`LR-DG`,
    // R-centre — predicted "fill", but the root is a `ScrollView`, which takes
    // no `Self`-returning size): under the proposal authority the viewport
    // fills its proposal on the scrolling axis and hugs its 20pt content on the
    // cross axis (`LR-BB`), and the root is centred at that answer (`CN-J`):
    // x = (200 - 20) / 2 = 90, y = (100 - 100) / 2 = 0. Only x moves; the
    // halves above read y alone and hold on both authorities.
    let (_, tree) = collect(makeTree(), stateTable: stateTable, width: 200, height: 100,
                            authority: .proposal)
    let target = try #require(tree.id(labelled: "target"))
    let top = try #require(tree.id(labelled: "top"))
    let targetGeometry = try #require(tree.geometry[target])
    let topGeometry = try #require(tree.geometry[top])
    #expect(targetGeometry.frame == rect(90, 60, 20, 20))
    #expect(targetGeometry.visibleFrame == rect(90, 60, 20, 20), "control: wholly inside the viewport")
    #expect(topGeometry.frame == rect(90, -40, 20, 20), "frame is unclipped (AB-E)")
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
    var reordered = tree
    reordered.roots.reverse()
    try #require(reordered.roots != tree.roots, "control: two roots, so reversing them changes the order")
    #expect(!reordered.hasSameStructure(as: tree), "root order is structure")
    var refocused = tree
    refocused.focused = target
    try #require(tree.focused == nil, "control: nothing was focused")
    #expect(!refocused.hasSameStructure(as: tree), "focus is structure")
}

// MARK: - Actions (AB-H, AB-I)

/// A press runs `onClick` through the last frame's hitboxes; a node with no
/// click handler advertises no press and refuses one; a duplicated id's press
/// runs its last registration.
@Test @MainActor func aPressRequestRunsOnClickThroughTheLastFramesHitboxes() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let tally = Tally()
    let (window, platform) = try makeFakeWindow(device: device, size: 200) {
        Column {
            declared(Box().width(px(40)).height(px(20)).onClick { tally.count += 1 },
                     AXNode(role: .button, label: "clickable"))
            declared(Box().width(px(40)).height(px(20)), AXNode(role: .button, label: "inert"))
            declared(Box().width(px(40)).height(px(20)).id("dup").onClick { tally.first += 1 },
                     AXNode(role: .button, label: "dup-first"))
            declared(Box().width(px(40)).height(px(20)).id("dup").onClick { tally.last += 1 },
                     AXNode(role: .button, label: "dup-last"))
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

    // Two siblings sharing an `.id` publish one node; a press on it runs the
    // LAST registration's handler, as click dispatch ranks a later hitbox above
    // an earlier one (hunting mutant H02 took the first).
    let dup = try #require(tree.id(labelled: "dup-last"))
    #expect(platform.simulateAccessibilityRequest(.press(dup)))
    #expect(tally.last == 1 && tally.first == 0)
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
    try #require(!window.needsRedraw)
    #expect(platform.simulateAccessibilityRequest(.increment(adjustable)))
    #expect(window.needsRedraw, "an adjustment may have changed anything, so the window is dirtied")
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
/// two siblings sharing an `.id` publish one node, once, at the first
/// occurrence's position with the last occurrence's content. The two
/// occurrences straddle the divider, so first and last position publish
/// different root orders.
///
/// The hidden box is also focusable and focused: `hidden()` does not stop
/// focus (CLAUDE.md's inert table), so the frame keeps that focus, and the
/// published `focused` must still be `nil` because its node was not published.
/// The hidden box is itself a click target, so the suppression scope's `nil`
/// exception is observable: excepting the hidden element would publish it as a
/// root (hunting mutant H14).
///
/// **Both authorities since stage 6b's lane 1** (`LR-DH`): under the proposal authority
/// `hidden()` lowers as if shown and joins `Frame.hiddenNodes`, which the suppression
/// reads; before the lane a `.proposal` frame over this fixture trapped on
/// `box.display.none`.
@Test(arguments: AuthorityCoverage.authorities) @MainActor
func hiddenContentIsNotPublishedButAZeroHeightNodeIsAndADuplicatedIDIsPublishedOnce(_ authority: LayoutAuthority) throws {
    AuthorityCoverage.record(#function, authority)
    let column = GlobalElementID.child(of: nil, at: 0, name: nil)
    let hiddenBox = GlobalElementID.child(of: column, at: 0, name: nil)
    let hiddenFocusable = GlobalElementID.child(of: hiddenBox, at: 0, name: nil)
    let (frame, tree) = collect(Column {
        Box { declared(Box().width(px(10)).height(px(10)).focusable(), AXNode(label: "in")) }
            .width(px(20)).height(px(20)).hidden().onClick {}
        declared(Box().width(px(10)).height(px(10)).id("x"), AXNode(label: "x-first"))
        declared(Box().width(px(20)).height(px(0)), AXNode(label: "divider"))
        declared(Box().width(px(10)).height(px(10)).id("x"), AXNode(label: "x-last"))
    }, focusedElement: hiddenFocusable, authority: authority)
    #expect(frame.axNodes.values.contains { $0.label == "in" },
            "control: the hidden node is still emitted as today; only the record is suppressed")
    #expect(!tree.nodes.values.contains { $0.label == "in" }, "display: none content is not published")
    try #require(frame.focusedElement == hiddenFocusable, "control: the hidden focusable box kept focus")
    #expect(tree.focused == nil, "focus on an element that published no node is not published")

    let divider = try #require(tree.id(labelled: "divider"))
    #expect(tree.geometry[divider]?.frame.size.height == 0, "a zero-height node is published (arm R6)")

    let x = try #require(tree.id(labelled: "x-last"), "one node per id, with its last content")
    #expect(!tree.nodes.values.contains { $0.label == "x-first" })
    #expect(tree.roots == [x, divider],
            "published once, at its first position: before the divider its two occurrences straddle")
}

/// A window root with `display: none` records nothing (AB-AD). `Frame.render`
/// calls the root's `prepaint` directly, not through `prepaintGroup`, so the
/// check there cannot reach it; `hidden()` filters layout and not prepaint
/// (CLAUDE.md's inert table), so without a check of its own the root and
/// everything in it would record.
///
/// The root is itself a click target and holds a declared, sized, clickable
/// box, so both the root's own record and its content's are observable. The
/// control is the same root without `hidden()`.
///
/// **Both authorities since stage 6b's lane 1** (`LR-DH` item 3): under the proposal
/// authority the root's node is native, so `render`'s check reads `Frame.isHidden`
/// (`display == .none ∨ hiddenNodes`), not the style alone.
@Test(arguments: AuthorityCoverage.authorities) @MainActor
func aHiddenRootPublishesNothing(_ authority: LayoutAuthority) throws {
    AuthorityCoverage.record(#function, authority)
    func root(hidden: Bool) -> Box<Box<EmptyGroup>> {
        let box = Box { declared(Box().width(px(10)).height(px(10)).onClick {}, AXNode(label: "in")) }
            .width(px(20)).height(px(20)).onClick {}
        return hidden ? box.hidden() : box
    }
    let (shownFrame, shown) = collect(root(hidden: false), authority: authority)
    try #require(shownFrame.axEmissions.count == 2, "control: the shown root and its box both record")
    #expect(shown.id(labelled: "in") != nil)

    let (hiddenFrame, hidden) = collect(root(hidden: true), authority: authority)
    #expect(hiddenFrame.axNodes.values.contains { $0.label == "in" },
            "control: the hidden root still prepaints, so its content still emits as today")
    #expect(hiddenFrame.axEmissions.isEmpty, "a hidden root records nothing")
    #expect(hidden.nodes.isEmpty && hidden.roots.isEmpty)
}

/// `display: none` on an INNER wrapper layer hides everything inside it
/// (AB-O, AB-Z item 4). `x.padding(4).hidden().padding(4)` hides the middle
/// layer, while `prepaintGroup` reads the outermost layer's style.
///
/// **Written on `feat/ax-bridge` for the merge, and red on it** (measured at
/// integration: 2 issues, :682 and :683, at the merge commit). There each
/// `.padding` was a nested `Box` whose own `prepaintGroup` suppressed; after the
/// modifier-composition merge the same spelling is one `ModifiedElement` whose
/// inner layers get no `prepaintGroup`. Green since
/// `ModifiedElement.prepaintLayer` wraps each inner layer in
/// `Frame.suppressingAccessibilityIfHidden` (MC-B's per-layer mirroring);
/// deleting that wrap reddens exactly these two lines. The control,
/// `.padding(4).padding(4)`, records the box.
///
/// **Both authorities since stage 6b's lane 1** (`LR-DH` item 4): the lowered
/// `.hidden()` layer joins `Frame.hiddenNodes`, which the per-layer wrap reads.
@Test(arguments: AuthorityCoverage.authorities) @MainActor
func aHiddenInnerModifierLayerSuppressesEverythingInsideIt(_ authority: LayoutAuthority) throws {
    AuthorityCoverage.record(#function, authority)
    func target() -> Box<EmptyGroup> {
        declared(Box().width(px(10)).height(px(10)).onClick {}, AXNode(label: "in"))
    }
    let (shownFrame, shown) = collect(Row { target().padding(px(4)).padding(px(4)) }, authority: authority)
    try #require(shownFrame.axEmissions.count == 1, "control: the unhidden box records")
    #expect(shown.id(labelled: "in") != nil)

    let (hiddenFrame, hidden) = collect(Row { target().padding(px(4)).hidden().padding(px(4)) },
                                        authority: authority)
    #expect(hiddenFrame.axNodes.values.contains { $0.label == "in" },
            "control: the box inside the hidden layer still prepaints and emits as today")
    #expect(hiddenFrame.axEmissions.isEmpty, "nothing inside a hidden inner layer records")
    #expect(hidden.nodes.isEmpty)
}

/// `display: none` on a one-node legacy FRAME layer hides everything inside it
/// from an accessibility client (AB-O), outermost (`.frame(…).hidden()`, which
/// `Element.prepaintGroup` checks) and inner (`.frame(…).hidden().padding(4)`,
/// which `ModifiedElement.prepaintLayer` checks), for both frame overloads.
///
/// **The by-reading claim in record §17's "Branch checker" was right.**
/// `Frame.suppressingAccessibilityIfHidden` reads the style the layer
/// REGISTERED, and `CN-N`'s `ModifierLayer.lowered(_:childCount:)` registered
/// `display: .stack` over `hidden()`'s `.none`. Red at `b442c9e` on all four
/// arms (8 issues: one emission recorded and one node published per arm); at
/// `9e439cb` each arm recorded 0 emissions and published 0 nodes (a `git
/// archive` build, record §17 "Closeout"). The control, the framed box
/// unhidden, records it; each arm's box still prepaints and emits its declared
/// node, so the suppression — not a missing element — is what is measured.
///
/// **Both authorities since stage 6b's lane 1** (`LR-DH`): the lowered frame layer is
/// laid out as if shown and its node joins `Frame.hiddenNodes`.
@Test(arguments: AuthorityCoverage.authorities) @MainActor
func aHiddenOneNodeFrameLayerPublishesNothingToAnAccessibilityClient(_ authority: LayoutAuthority) throws {
    AuthorityCoverage.record(#function, authority)
    func target() -> Box<EmptyGroup> {
        declared(Box().width(px(10)).height(px(10)).onClick {}, AXNode(label: "in"))
    }
    let (shownFrame, shown) = collect(Row { target().frame(width: px(40), height: px(40)) },
                                      authority: authority)
    try #require(shownFrame.axEmissions.count == 1, "control: the framed, unhidden box records")
    #expect(shown.id(labelled: "in") != nil)

    let arms: [(chain: String, frame: Frame, tree: AccessibilityTree)] = [
        { let (f, t) = collect(Row { target().frame(width: px(40), height: px(40)).hidden() }, authority: authority)
          return ("frame(width:height:).hidden()", f, t) }(),
        { let (f, t) = collect(Row { target().frame(minWidth: px(40), maxWidth: px(80)).hidden() }, authority: authority)
          return ("frame(minWidth:maxWidth:).hidden()", f, t) }(),
        { let (f, t) = collect(Row { target().frame(width: px(40), height: px(40)).hidden().padding(px(4)) }, authority: authority)
          return ("frame(width:height:).hidden().padding(4)", f, t) }(),
        { let (f, t) = collect(Row { target().frame(minWidth: px(40), maxWidth: px(80)).hidden().padding(px(4)) }, authority: authority)
          return ("frame(minWidth:maxWidth:).hidden().padding(4)", f, t) }(),
    ]
    for arm in arms {
        #expect(arm.frame.axNodes.values.contains { $0.label == "in" },
                "control, \(arm.chain): the box inside the hidden frame still prepaints and emits")
        #expect(arm.frame.axEmissions.isEmpty,
                "\(arm.chain): nothing inside a hidden frame layer records, got \(arm.frame.axEmissions.count)")
        #expect(arm.tree.nodes.isEmpty, "\(arm.chain): published \(arm.tree.nodes.count) nodes")
    }
}

/// A `List` publishes a table whose row count is its logical count, even when a
/// caller declared a label and so left its role `generic` (AB-L, arm R16).
///
/// **Both authorities since stage 4's lane 4**, for completeness only (spec §6
/// lane 4): this file is not that lane's subject — `AccessibilityDefaultsTests`
/// holds the table's rows, their indices and the two window rules — but this is
/// the one `List` assertion here that a table could fail, so it costs one
/// argument to keep it honest on both paths.
@Test(arguments: AuthorityCoverage.authorities) @MainActor
func aLabelledListIsStillATable(_ authority: LayoutAuthority) throws {
    AuthorityCoverage.record(#function, authority)
    let items = (0..<500).map(Item.init)
    let (_, tree) = collect(
        List(items, rowHeight: px(28)) { _ in Box().width(px(20)).height(px(28)) }
            .handling { $0.axNode.label = "Contacts" },
        authority: authority)
    let list = try #require(tree.id(labelled: "Contacts"))
    #expect(tree.nodes[list]?.role == .table)
    #expect(tree.nodes[list]?.rowCount == 500)
}
