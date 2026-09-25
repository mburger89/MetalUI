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
// entry, how often it uses an id, or when. Test 8 was pinned wrong on purpose
// until CN-L closed it (test 7 retired at stage 9 with the legacy registrars);
// test 9 pins the run-time backstop for a stored id.

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

// MARK: - 7: retired

// Test 7, `anOrphanLegacyRegistrationBesideATypedLeafIsNotRejected` (MC-G holes 2
// and 6, pinned wrong on purpose: an orphan LEGACY registration during a typed
// entry was not rejected), retired at stage 9: no legacy node can be registered
// any more, so the holes it pinned are closed by deletion (`LR-FF`, record §51).

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

/// **One native node registered under two parents traps (`MC-G` hole 4,
/// closed by plan task 6's ruling CN-L).** No SwiftUI spelling reaches it: a
/// view value has no node id. Until CN-L this test pinned the hole wrong on
/// purpose as `aNativeNodeRegisteredTwiceIsNotRejected` (arm a: the leaf was
/// placed once, at the second slot of a 20-wide stack; arm b: drawn where the
/// last frame put it); it became this exit test before the precondition landed,
/// because a trap in-process truncates the suite (record §10).
///
/// - **Arm a:** one leaf listed twice in one horizontal stack exits with
///   failure, at the parent record's check.
/// - **Arm b:** one leaf handed to two frames exits with failure there too.
/// - **The reset arm** (`LayoutTree.reset(generation:)` clears the record): a
///   leaf under a frame, a reset, then a fresh leaf under a fresh frame at the
///   same indices lays out and exits successfully. Without the clear, index 0
///   would still hold its old parent and trap.
///
/// Before CN-L both arms exit successfully. Mutations: delete the precondition
/// (arms a and b); do not clear the record in `reset` (the reset arm).
@Test func aNativeNodeRegisteredTwiceTraps() async {
    let listedTwice = await #expect(processExitsWith: .failure, observing: [\.standardErrorContent]) {
        await MainActor.run {
            let probe = TypedIDProbe()
            var root = VStack { HStack { LeafListedTwice(probe: probe) } }
            Frame(contentSize: frameSize, scaleFactor: 1).render(&root)
        }
    }
    let stderrA = String(decoding: listedTwice?.standardErrorContent ?? [], as: UTF8.self)
    #expect(stderrA.contains("MC-G hole 4"), "arm a aborted, but not at the parent record:\n\(stderrA)")

    let inTwoFrames = await #expect(processExitsWith: .failure, observing: [\.standardErrorContent]) {
        await MainActor.run {
            let probe = TypedIDProbe()
            var root = VStack { HStack { LeafInTwoFrames(probe: probe) } }
            Frame(contentSize: frameSize, scaleFactor: 1).render(&root)
        }
    }
    let stderrB = String(decoding: inTwoFrames?.standardErrorContent ?? [], as: UTF8.self)
    #expect(stderrB.contains("MC-G hole 4"), "arm b aborted, but not at the parent record:\n\(stderrB)")

    await #expect(processExitsWith: .success) {
        let tree = LayoutTree(generation: 0)
        let old = tree.newNativeLeaf { _ in LayoutMeasurement(size: SizeD(width: 10, height: 10)) }
        _ = tree.newNativeFrame(child: old, width: 20, height: 20)
        tree.reset(generation: 1)
        let leaf = tree.newNativeLeaf { _ in LayoutMeasurement(size: SizeD(width: 10, height: 10)) }
        let frame = tree.newNativeFrame(child: leaf, width: 20, height: 20)
        tree.computeNativeLayout(root: frame, proposal: ProposedSize(width: 20, height: 20),
                                 in: LayoutRect(x: 0, y: 0, width: 20, height: 20))
        precondition(tree.layout(leaf) == LayoutRect(x: 5, y: 5, width: 10, height: 10))
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
