import Testing
import MetalUICore
import MetalUILayout
@testable import MetalUI

// Lane 3 of `docs/superpowers/specs/2026-09-15-modifier-composition-design.md`:
// what the typed native node id does NOT close (ruling MC-G's holes 2, 4, 6 and
// 7), measured end to end through a real `Frame`.
//
// `ProposalNodeID` constrains WHO mints a native node id — only `MetalUI`'s
// registrars — and the typed requirement constrains WHAT a proposal container
// receives. Neither constrains what else an element registers during its typed
// entry, how often it uses an id, or when. Tests 7 and 8 are pinned wrong on
// purpose, at the values measured; test 9 pins the run-time backstop for a
// stored id.

@MainActor
private final class TypedIDProbe: @unchecked Sendable {
    nonisolated(unsafe) var measureCalls = 0
    var bounds: [String: Bounds<Pixels>] = [:]
    var ids: [String: GlobalElementID] = [:]
}

/// A 10×10 native leaf whose measurement counts itself.
@MainActor
private func tenByTen(_ pass: inout LayoutPass, _ probe: TypedIDProbe) -> ProposalNodeID {
    pass.requestNativeLeaf { _ in
        probe.measureCalls += 1
        return LayoutMeasurement(size: SizeD(width: 10, height: 10))
    }
}

private let frameSize = Size(width: Pixels(140), height: Pixels(90))

// MARK: - 7: an orphan legacy registration beside a typed leaf (MC-G holes 2 and 6)

/// Hole 2's element: its typed entry registers a LEGACY node, discards it, and
/// returns a typed leaf.
private struct OrphanLegacyNode: ProposalElement {
    var probe: TypedIDProbe

    mutating func requestProposalLayout(_ id: GlobalElementID,
                                        pass: inout LayoutPass) -> (ProposalNodeID, Void) {
        _ = pass.requestNode(style: Style(), children: [])
        return (tenByTen(&pass, probe), ())
    }

    mutating func prepaint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Void,
                           pass: inout PrepaintPass) {
        probe.bounds["typed leaf"] = bounds
    }

    mutating func paint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Void,
                        prepaint: inout Void, pass: inout PaintPass) {}
}

/// A legacy leaf that writes its own `@State` from 7 to 8 during layout, and
/// records the id it was laid out under.
private struct StatefulLegacyLeaf: Element {
    @State var value = 7
    var probe: TypedIDProbe

    mutating func requestLayout(_ id: GlobalElementID, pass: inout LayoutPass) -> (LayoutNodeID, Void) {
        value += 1
        probe.ids["legacy leaf"] = id
        return (pass.requestNode(style: Style(), children: []), ())
    }

    mutating func prepaint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Void,
                           pass: inout PrepaintPass) {}

    mutating func paint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Void,
                        prepaint: inout Void, pass: inout PaintPass) {}
}

/// The orphan subtree, sized so that it paints a visible rect wherever it is
/// actually attached (the disagreeing oracle renders it as a root).
@MainActor
private func orphanBox(_ probe: TypedIDProbe) -> Box<StatefulLegacyLeaf> {
    Box { StatefulLegacyLeaf(probe: probe) }
        .width(Pixels(30)).height(Pixels(30))
        .background(.accent)
}

/// Hole 6's element: its typed entry lays out a discarded legacy SUBTREE through
/// the untyped group entry, then returns a typed leaf.
private struct OrphanLegacySubtree: ProposalElement {
    var probe: TypedIDProbe

    mutating func requestProposalLayout(_ id: GlobalElementID,
                                        pass: inout LayoutPass) -> (ProposalNodeID, Void) {
        probe.ids["element"] = id
        var orphan = orphanBox(probe)
        var cursor = 0
        _ = orphan.requestGroupLayout(under: id, at: &cursor, pass: &pass)
        return (tenByTen(&pass, probe), ())
    }

    mutating func prepaint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Void,
                           pass: inout PrepaintPass) {
        probe.bounds["typed leaf"] = bounds
    }

    mutating func paint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Void,
                        prepaint: inout Void, pass: inout PaintPass) {}
}

/// **PINNED WRONG ON PURPOSE (`MC-G` holes 2 and 6): a legacy registration made
/// during a typed entry and never handed to a container is not rejected.** The
/// type sees only the id the entry RETURNS; a node or a whole subtree registered
/// on the side is invisible to it, and nothing at run time checks for orphans.
///
/// - **Arm a (hole 2):** one orphan legacy node beside a typed leaf. No trap; the
///   typed leaf lays out and prepaints at 10×10; the only rect is the 5×5
///   `Rectangle`; the orphan is counted in `nodeCount`.
/// - **Arm b (hole 6):** an orphan `Box` over a leaf that writes its `@State`
///   during layout. It is NOT inert: the leaf's `$state0` slot is bound, reads
///   8 and is live, and the `Box`'s `$anim` slot is live — state entries and
///   animation baselines kept moving for elements that never paint. Its accent
///   fill is never emitted. The disagreeing oracle renders the same `Box` as a
///   root and requires that it paints its 30×30 rect, so "no rect" is a reading
///   the instrument could have got wrong.
///
/// **Whoever closes the holes.** An orphan check in `LayoutPass.requestNode`
/// during a typed entry traps this test's process — measured (lane 3, record
/// §10): the suite printed no summary line, stopping here after 953 tests — so
/// the test becomes an exit test first. Nothing in this design closes arm b
/// short of detecting state bound by an unregistered subtree.
@MainActor
@Test func anOrphanLegacyRegistrationBesideATypedLeafIsNotRejected() throws {
    // Arm a.
    do {
        let probe = TypedIDProbe()
        let frame = Frame(contentSize: frameSize, scaleFactor: 1)
        var root = VStack {
            HStack { OrphanLegacyNode(probe: probe) }
            Rectangle(width: Pixels(5), height: Pixels(5), color: .accent)
        }
        frame.render(&root)
        let rects = frame.finalizedScene().rects
        print("MC-G hole 2 (arm a): typed leaf \(String(describing: probe.bounds["typed leaf"])), "
              + "rects \(rects.map { ($0.bounds.size.width, $0.bounds.size.height) }), "
              + "nodeCount \(frame.tree.nodeCount), measure calls \(probe.measureCalls)")
        let leaf = try #require(probe.bounds["typed leaf"], "the typed leaf was never prepainted")
        #expect(leaf.size == Size(width: Pixels(10), height: Pixels(10)))
        try #require(rects.count == 1, "arm a: \(rects.count) rects")
        #expect(rects[0].bounds.size.width == 5 && rects[0].bounds.size.height == 5)
        // VStack, HStack, orphan, typed leaf, Rectangle.
        #expect(frame.tree.nodeCount == 5)
    }

    // Arm b's disagreeing oracle: the orphan subtree, attached, paints.
    do {
        let probe = TypedIDProbe()
        let frame = Frame(contentSize: frameSize, scaleFactor: 1)
        var attached = orphanBox(probe)
        frame.render(&attached)
        let rects = frame.finalizedScene().rects
        try #require(rects.count == 1 && rects[0].bounds.size.width == 30,
                     "the attached orphan subtree must paint its 30×30 rect, or \"no rect\" cannot fail: \(rects.count)")
    }

    // Arm b.
    do {
        let probe = TypedIDProbe()
        let frame = Frame(contentSize: frameSize, scaleFactor: 1)
        var root = VStack {
            HStack { OrphanLegacySubtree(probe: probe) }
            Rectangle(width: Pixels(5), height: Pixels(5), color: .accent)
        }
        frame.render(&root)
        let rects = frame.finalizedScene().rects
        let element = try #require(probe.ids["element"], "the typed entry never ran")
        let legacyLeaf = try #require(probe.ids["legacy leaf"], "the orphan subtree was never laid out")
        let box = GlobalElementID.child(of: element, at: 0, name: nil)
        try #require(legacyLeaf == GlobalElementID.child(of: box, at: 0, name: nil),
                     "the orphan leaf's id is not under the orphan Box: \(legacyLeaf)")
        let stateSlot = GlobalElementID.child(of: legacyLeaf, at: 0, name: ElementID("$state0"))
        let table = frame.stateTable
        print("MC-G hole 6 (arm b): typed leaf \(String(describing: probe.bounds["typed leaf"])), "
              + "rects \(rects.map { ($0.bounds.size.width, $0.bounds.size.height) }), "
              + "nodeCount \(frame.tree.nodeCount), $state0 \(String(describing: table.peek(stateSlot, as: Int.self))) "
              + "live \(table.isLive(stateSlot)), box $anim live \(table.isLive(animRetentionSlot(for: box)))")
        let leaf = try #require(probe.bounds["typed leaf"], "the typed leaf was never prepainted")
        #expect(leaf.size == Size(width: Pixels(10), height: Pixels(10)))
        #expect(table.peek(stateSlot, as: Int.self) == 8)
        #expect(table.isLive(stateSlot))
        #expect(table.isLive(animRetentionSlot(for: box)))
        try #require(rects.count == 1, "arm b: \(rects.count) rects")
        #expect(rects[0].bounds.size.width == 5 && rects[0].bounds.size.height == 5)
        // VStack, HStack, orphan Box, orphan leaf, typed leaf, Rectangle.
        #expect(frame.tree.nodeCount == 6)
    }
}

// MARK: - 8: one native node registered twice (MC-G hole 4)

/// One typed leaf listed twice in one linear stack.
private struct LeafListedTwice: ProposalElement {
    var probe: TypedIDProbe

    mutating func requestProposalLayout(_ id: GlobalElementID,
                                        pass: inout LayoutPass) -> (ProposalNodeID, ProposalNodeID) {
        let leaf = tenByTen(&pass, probe)
        return (pass.requestNativeLinearStack(children: [leaf, leaf], axis: .horizontal), leaf)
    }

    mutating func prepaint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout ProposalNodeID,
                           pass: inout PrepaintPass) {
        probe.bounds["stack"] = bounds
        probe.bounds["leaf"] = pass.bounds(of: layout.layoutNodeID)
    }

    mutating func paint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout ProposalNodeID,
                        prepaint: inout Void, pass: inout PaintPass) {}
}

/// One typed leaf handed to two frames in one linear stack.
private struct LeafInTwoFrames: ProposalElement {
    var probe: TypedIDProbe

    mutating func requestProposalLayout(_ id: GlobalElementID,
                                        pass: inout LayoutPass) -> (ProposalNodeID, ProposalNodeID) {
        let leaf = tenByTen(&pass, probe)
        let first = pass.requestNativeFrame(child: leaf, width: 30, height: 30, alignment: .topLeading)
        let second = pass.requestNativeFrame(child: leaf, width: 50, height: 50, alignment: .bottomTrailing)
        return (pass.requestNativeLinearStack(children: [first, second], axis: .horizontal), leaf)
    }

    mutating func prepaint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout ProposalNodeID,
                           pass: inout PrepaintPass) {
        probe.bounds["stack"] = bounds
        probe.bounds["leaf"] = pass.bounds(of: layout.layoutNodeID)
    }

    mutating func paint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout ProposalNodeID,
                        prepaint: inout Void, pass: inout PaintPass) {}
}

private func rect(_ x: Float, _ y: Float, _ width: Float, _ height: Float) -> Bounds<Pixels> {
    Bounds(origin: Point(x: Pixels(x), y: Pixels(y)), size: Size(width: Pixels(width), height: Pixels(height)))
}

/// **PINNED WRONG ON PURPOSE (`MC-G` hole 4): one typed id used twice is not
/// rejected.** A type with an internal initializer constrains who mints an id,
/// not how often it is used, and `LayoutTree.appendNode` checks only the id's
/// generation.
///
/// - **Arm a:** one leaf listed twice in a horizontal stack reserves both slots
///   (the stack is 20 wide) and is placed once, at the SECOND slot. It is
///   measured at four distinct proposals since plan task 6's ruling CN-B: the
///   stack's one priority group of two probes it at (∞, h) and (0, h), then
///   offers it half the width and then the width less the 10 it answered.
/// - **Arm b:** one leaf handed to a 30×30 top-leading frame and a 50×50
///   bottom-trailing frame is drawn where the LAST placement puts it, the first
///   frame's slot empty; it is measured twice.
///
/// Values measured at design review with untyped ids, which a `ProposalNodeID`
/// wraps unchanged, and re-measured here through the typed registrars.
///
/// **Whoever closes the hole** with a duplicate-parent precondition in
/// `LayoutTree.appendNode` traps this test's process — measured (lane 3, record
/// §10): no summary line, stopping here after 955 tests, and no test before it
/// tripped the check — so the test becomes an exit test first.
@MainActor
@Test func aNativeNodeRegisteredTwiceIsNotRejected() throws {
    do {
        let probe = TypedIDProbe()
        let frame = Frame(contentSize: frameSize, scaleFactor: 1)
        var root = VStack { HStack { LeafListedTwice(probe: probe) } }
        frame.render(&root)
        print("MC-G hole 4 (arm a): stack \(String(describing: probe.bounds["stack"])), "
              + "leaf \(String(describing: probe.bounds["leaf"])), measure calls \(probe.measureCalls), "
              + "nodeCount \(frame.tree.nodeCount)")
        #expect(probe.bounds["stack"] == rect(60, 0, 20, 10))
        #expect(probe.bounds["leaf"] == rect(70, 0, 10, 10))
        #expect(probe.measureCalls == 4)
        #expect(frame.tree.nodeCount == 4)
    }
    do {
        let probe = TypedIDProbe()
        let frame = Frame(contentSize: frameSize, scaleFactor: 1)
        var root = VStack { HStack { LeafInTwoFrames(probe: probe) } }
        frame.render(&root)
        print("MC-G hole 4 (arm b): stack \(String(describing: probe.bounds["stack"])), "
              + "leaf \(String(describing: probe.bounds["leaf"])), measure calls \(probe.measureCalls), "
              + "nodeCount \(frame.tree.nodeCount)")
        #expect(probe.bounds["stack"] == rect(30, 0, 80, 50))
        #expect(probe.bounds["leaf"] == rect(100, 40, 10, 10))
        #expect(probe.measureCalls == 2)
        #expect(frame.tree.nodeCount == 6)
    }
}

// MARK: - 9: a typed id stored from an earlier frame (MC-G hole 7)

@MainActor
private final class StoredIDBox {
    var stored: ProposalNodeID?
}

/// Registers a native leaf on its first frame and stores the id. On a later
/// frame it returns the STORED id when `reusesStoredID`, or registers afresh.
private struct StoresItsNodeID: ProposalElement {
    var box: StoredIDBox
    var reusesStoredID: Bool

    mutating func requestProposalLayout(_ id: GlobalElementID,
                                        pass: inout LayoutPass) -> (ProposalNodeID, Void) {
        if reusesStoredID, let stored = box.stored { return (stored, ()) }
        let node = pass.requestNativeLeaf { _ in LayoutMeasurement(size: SizeD(width: 10, height: 10)) }
        box.stored = node
        return (node, ())
    }

    mutating func prepaint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Void,
                           pass: inout PrepaintPass) {}

    mutating func paint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Void,
                        prepaint: inout Void, pass: inout PaintPass) {}
}

/// **A typed id cached from an earlier frame traps when it is used (`MC-G` hole
/// 7).** `ProposalNodeID` is `Hashable, Sendable` and storable, so the type check
/// passes; the backstop is run-time. Every `Frame` builds its `LayoutTree` at a
/// fresh generation (ruling C-3), and the `HStack`'s registration looks each
/// child up through `LayoutTree.slot`, whose precondition rejects an id from
/// another generation.
///
/// **The control** is the same element registering a fresh id on frame 2, which
/// exits 0 — so the failure is about the stored id, not about rendering this
/// element twice. Its red run: the trapping arm also registers afresh on frame 2,
/// and the failure expectation reddens (record §10).
///
/// **Which check reports it:** `LayoutTree.newNativeLinearStack`'s child loop
/// (`nativeNode(_:)` → `slot`), by reading; with that loop deleted the test
/// stays green, because `appendNode`'s own `slot` loop then reports it with the
/// same message (measured).
@Test func aTypedNodeIDStoredFromAnEarlierFrameTraps() async {
    await #expect(processExitsWith: .success) {
        await MainActor.run {
            let box = StoredIDBox()
            for _ in 0..<2 {
                var root = HStack { StoresItsNodeID(box: box, reusesStoredID: false) }
                Frame(contentSize: Size(width: Pixels(140), height: Pixels(90)), scaleFactor: 1)
                    .render(&root)
            }
        }
    }

    let result = await #expect(processExitsWith: .failure,
                               observing: [\.standardErrorContent]) {
        await MainActor.run {
            let box = StoredIDBox()
            for _ in 0..<2 {
                var root = HStack { StoresItsNodeID(box: box, reusesStoredID: true) }
                Frame(contentSize: Size(width: Pixels(140), height: Pixels(90)), scaleFactor: 1)
                    .render(&root)
            }
        }
    }
    let stderr = String(decoding: result?.standardErrorContent ?? [], as: UTF8.self)
    print("MC-G hole 7: \(stderr)")
    #expect(stderr.contains("outlived the tree that issued it"),
            "aborted, but not at the stale-generation check this test is about:\n\(stderr)")
}
