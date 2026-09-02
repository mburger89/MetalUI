import Testing
import MetalUICore
import MetalUILayout
import MetalUIText
import MetalUITestSupport
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
    // `frame`/`children` are `internal(set)` — unreachable through the public
    // initializer at all (see `AXNode`'s own doc) — so this file, which is
    // `@testable import`, reaches them the only way anything can: direct
    // property assignment from inside the module, after construction.
    var declaredButIgnored = AXNode(role: .button)
    declaredButIgnored.frame = rect(999, 999, 1, 1)
    declaredButIgnored.children = [eid("stale")]
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

// MARK: - `AXNode.frame`/`.children` are unreachable from a REAL external caller
//
// Every test above imports `MetalUI` with `@testable`, which grants this whole
// file `internal`-level access — so it could still write `n.frame = …` despite
// `internal(set)`, and would prove nothing about the actual public surface an
// app author sees. These two compile a fixture against the *built module*,
// imported plainly, the way `ErasureCompileGuards.swift` and
// `PhaseSeparationTests.swift` pin every other "this must not compile" claim
// in this repo (ruling EP-1) — `@testable`'s access widening cannot reach in
// here at all.

private let skipReason: Comment =
    "built module directory .build/<triple>/debug/Modules holding MetalUI not found — AXNode guard skipped"

/// The load-bearing positive: a plain, non-`@testable` importer can still
/// construct and read an `AXNode` at all. Without this, the negative below
/// would pass just as well if `AXNode` did not exist, or `MetalUI` failed to
/// import, or `role`/`label` were also unreachable — none of which is the
/// claim this pair exists to isolate.
@Test(.enabled(if: canTypecheck(module: "MetalUI"), skipReason))
func aPlainImporterCanConstructAndReadAnAXNode() throws {
    let result = try typecheck("""
        let node = AXNode(role: .button, label: "Go")
        _ = node.frame
        _ = node.children
        """, importing: "MetalUI")
    #expect(result.succeeded,
            "a plain importer must be able to construct and READ an AXNode:\n\(result.output)")
}

/// The negative: a plain importer cannot WRITE `.frame` — the public
/// initializer takes no `frame:` parameter and the property's setter is
/// `internal`, so this must fail exactly the way writing to any other
/// module's `internal(set)` property would.
@Test(.enabled(if: canTypecheck(module: "MetalUI"), skipReason))
func aPlainImporterCannotSetAnAXNodesFrame() throws {
    let result = try typecheck("""
        var node = AXNode(role: .button)
        node.frame = node.frame
        """, importing: "MetalUI")
    #expect(!result.succeeded,
            "`frame` is `internal(set)` — a plain importer must not be able to assign it")
    // Verified against the real diagnostic rather than guessed: `swiftc` says
    // "cannot assign to property: 'frame' setter is inaccessible" — checked
    // here so a future change that breaks the fixture for an unrelated reason
    // (a typo, `AXNode` losing `role`) fails this assertion rather than
    // passing for the wrong cause, `messages`-not-`output`'s own reason
    // (`TypecheckResult.messages`'s own doc).
    #expect(result.messages.contains("setter is inaccessible") && result.messages.contains("frame"),
            "must fail because the setter is inaccessible, not for an unrelated reason:\n\(result.output)")
}
