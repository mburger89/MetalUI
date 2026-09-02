import Testing
import MetalUICore
import MetalUILayout
import MetalUIText
@testable import MetalUI

private func px(_ v: Float) -> Pixels { Pixels(v) }

private func pt(_ x: Float, _ y: Float) -> Point<Pixels> {
    Point(x: px(x), y: px(y))
}

private func rect(_ x: Float, _ y: Float, _ w: Float, _ h: Float) -> Bounds<Pixels> {
    Bounds(origin: pt(x, y), size: Size(width: px(w), height: px(h)))
}

/// A bare `Frame` with no element tree — most of this file drives
/// `PrepaintPass` directly, on `HitboxTests.swift`'s own footing: an
/// `AXNode` is emitted in prepaint and read back off the frame, and the
/// dictionary contract (`Frame.axNodes`) is testable without an element at
/// all.
@MainActor private func bareFrame(_ side: Float = 300) -> Frame {
    Frame(contentSize: Size(width: px(side), height: px(side)),
          scaleFactor: 1, stateTable: StateTable(),
          shapingCache: ShapingCache(), glyphAtlas: GlyphAtlas(width: 64, height: 64),
          theme: Theme.forAppearance(.light))
}

/// Distinct element ids, named rather than positional so they can never
/// collide with a frame's own root path — `HitboxTests.swift`'s `eid`.
@MainActor private func eid(_ name: String) -> GlobalElementID {
    GlobalElementID.child(of: nil, at: 0, name: ElementID(name))
}

// MARK: - The API contract, driven directly against `PrepaintPass`

/// The node's own step 1 test: an element emitting a node, retrievable by its
/// `GlobalElementID`, and a second, independent emission at a different id
/// does not disturb the first — a mutation that collapsed every emission onto
/// one dictionary entry (or ignored `id` and always overwrote the same key)
/// would still pass a single-node test but fails this one.
@Test @MainActor func anEmittedNodeIsRetrievableByItsGlobalElementID() throws {
    let frame = bareFrame()
    let pass = PrepaintPass(frame: frame)
    pass.emitAXNode(AXNode(role: .button, label: "Go"), at: rect(0, 0, 40, 20),
                    id: eid("a"), children: [])
    pass.emitAXNode(AXNode(role: .text, label: "Hi"), at: rect(0, 30, 40, 20),
                    id: eid("b"), children: [])

    let a = try #require(frame.axNodes[eid("a")])
    let b = try #require(frame.axNodes[eid("b")])
    #expect(a.role == .button && a.label == "Go")
    #expect(b.role == .text && b.label == "Hi")
    #expect(frame.axNodes[eid("c")] == nil, "nothing was emitted under this id")
}

/// The emitted node's `frame` is the resolved bounds `emitAXNode` was given —
/// **not** whatever the caller's own `AXNode` value happened to carry, which
/// is what proves `frame`/`children` are overwritten on the way in rather than
/// read from the declared value. `AXNode`'s own doc calls this out as the
/// reason a declared value carries neither meaningfully.
@Test @MainActor func anEmittedNodesFrameIsTheResolvedBoundsNotWhateverItDeclared() throws {
    let frame = bareFrame()
    let pass = PrepaintPass(frame: frame)
    let declaredButIgnored = AXNode(role: .button,
                                    frame: rect(999, 999, 1, 1),
                                    children: [eid("stale")])
    let resolvedBounds = rect(10, 20, 30, 40)
    pass.emitAXNode(declaredButIgnored, at: resolvedBounds, id: eid("target"), children: [])

    let node = try #require(frame.axNodes[eid("target")])
    #expect(node.frame == resolvedBounds,
            "the resolved bounds passed to `at:`, not the declared value's own stale frame")
    #expect(node.children.isEmpty,
            "the empty `children:` passed in, not the declared value's stale child")
}

/// Children come back in exactly the order they were declared — not sorted,
/// not reversed, not deduplicated. Ids are chosen out of alphabetical order
/// (`z`, `a`, `m`) so an implementation that silently sorted the array would
/// redden this and not a test using already-sorted names.
@Test @MainActor func childrenAreRetainedInDeclarationOrder() throws {
    let frame = bareFrame()
    let pass = PrepaintPass(frame: frame)
    let declared = [eid("z"), eid("a"), eid("m")]
    pass.emitAXNode(AXNode(role: .container), at: rect(0, 0, 10, 10),
                    id: eid("parent"), children: declared)

    let node = try #require(frame.axNodes[eid("parent")])
    #expect(node.children == declared,
            "declaration order preserved verbatim, including the out-of-order names")
    #expect(node.children.first == eid("z") && node.children.last == eid("m"),
            "sanity: `z` first and `m` last pins the actual order, not just set membership")
}

/// `emitAXNode` returns the resolved node, so a caller assembling a parent's
/// own children list from what its children just emitted needs no second
/// lookup into `Frame.axNodes` — see `PrepaintPass.emitAXNode`'s own doc.
@Test @MainActor func emitAXNodeReturnsTheResolvedValue() {
    let frame = bareFrame()
    let pass = PrepaintPass(frame: frame)
    let resolved = pass.emitAXNode(AXNode(role: .image), at: rect(1, 2, 3, 4),
                                   id: eid("returned"), children: [eid("kid")])
    #expect(resolved.role == .image)
    #expect(resolved.frame == rect(1, 2, 3, 4))
    #expect(resolved.children == [eid("kid")])
}

// MARK: - `AXNode.isEmpty`

/// The default value is empty and a declared one is not — `Handlers`' own
/// "empty means not a hit target" rule, checked at the type it was copied to.
@Test func aDefaultAXNodeIsEmptyAndADeclaredOneIsNot() {
    #expect(AXNode().isEmpty)
    #expect(!AXNode(label: "anything").isEmpty)
    #expect(!AXNode(role: .button).isEmpty)
}

// MARK: - Wired through a real `Box`, via a real `Frame.render`

/// A `Box` that declared an `AXNode` emits it, at its own resolved bounds,
/// under its own root id — the end-to-end path through `Box.prepaint` rather
/// than `PrepaintPass` driven by hand.
@Test @MainActor func aBoxWithADeclaredAXNodeEmitsItAtItsOwnResolvedBounds() throws {
    var box = Box(style: sized(40, 20), content: EmptyGroup())
    box.elementID = ElementID("root")
    box.handlers.axNode = AXNode(role: .button, label: "Go")

    let frame = bareFrame()
    frame.render(&box)

    // Named explicitly, rather than left `nil`, so this id is `.named("root")`
    // and cannot coincide with a mutation that hard-codes the unnamed root's
    // own key, `.positional(0)` — an unnamed `Box()` would make this test pass
    // under such a mutation by accident, which a probe found.
    let rootID = GlobalElementID.child(of: nil, at: 0, name: box.elementID)
    let node = try #require(frame.axNodes[rootID])
    #expect(node.role == .button && node.label == "Go")
    #expect(node.frame == rect(0, 0, 40, 20), "the box's own resolved bounds")
    #expect(node.children.isEmpty,
            "Box cannot yet enumerate its own children's ids — see Box.prepaint's own comment")
}

/// A `Box` that declared nothing accessible emits no node at all — the
/// positive control for the gate above, and the differential the "make
/// emission a no-op" mutation in this task's brief is checked against from
/// the other side.
@Test @MainActor func aBoxWithNoDeclaredAXNodeEmitsNothing() {
    var box = Box(style: sized(40, 20), content: EmptyGroup())

    let frame = bareFrame()
    frame.render(&box)

    #expect(frame.axNodes.isEmpty, "no AXNode was declared, so none should be emitted")
}

private func sized(_ w: Float, _ h: Float) -> Style {
    var s = Style()
    s.size = Size(width: .length(.pixels(px(w))), height: .length(.pixels(px(h))))
    return s
}
