import MetalUICore
import MetalUILayout

// MARK: - Named coordinate spaces (rulings `OV-D`, `OV-E`, `OV-M`, `OV-N`)
//
// Probe `docs/probes/swiftui-overlays-coords.swift`, arms G1–G7. One
// transparent scope, `CoordinateSpaceScope` (`GeometryChangeScope`'s shape):
// in layout it records its content's nodes; in PREPAINT it builds the space's
// map from its content's frame — the union of the nodes, scrolled, under the
// innermost open render effect's composed map — and pushes it on
// `Frame.namedSpaces` around its content's prepaint. Geometry resolves a name
// against that stack in prepaint; hover and gestures against the snapshot each
// hitbox took at registration (`Frame.hitboxNamedSpaces`).

/// One named space in force (`OV-E` item 2): its name and both directions of
/// its map — `toSpace` takes a window point to a point in the space (`nil`
/// when the map is degenerate, a zero scale: the space then resolves as
/// missing), `toWindow` the reverse.
///
/// `@unchecked Sendable` for `CoordinateSpace`'s reason (`OV-L`): the name is
/// an `AnyHashable`, read only on the main actor.
struct NamedSpace: @unchecked Sendable, Equatable {
    let name: AnyHashable
    let toSpace: Affine2D?
    let toWindow: Affine2D

    /// The innermost entry named `name` in `stack`, or `nil` when none is or
    /// the innermost such entry is degenerate (`OV-E` items 2–3) — a
    /// degenerate entry never falls through to an outer one of the same name.
    static func resolve(_ name: AnyHashable, in stack: [NamedSpace]) -> NamedSpace? {
        guard let entry = stack.last(where: { $0.name == name }), entry.toSpace != nil else { return nil }
        return entry
    }
}

/// The name a declarer's own space carries (`Frame.localSpace(of:)`): no app
/// name can equal it, since the type is private to the module.
private struct LocalSpaceName: Hashable {}

extension Frame {
    /// The space whose origin is the top-leading corner of `bounds` (this
    /// element's, unscrolled, in the current offset) and which moves with the
    /// open render effects (`OV-E` item 2, `OV-N`): `toWindow` is the
    /// innermost open effect's composed map after the scrolled origin's
    /// translation; `toSpace` its inverse.
    func localSpace(of bounds: Bounds<Pixels>, name: AnyHashable = AnyHashable(LocalSpaceName())) -> NamedSpace {
        let moved = scrolled(bounds)
        let origin = Affine2D.translation(x: Double(moved.origin.x.value), y: Double(moved.origin.y.value))
        let toWindow = prepaintEffects.last.map { $0.composed.concatenating(origin) } ?? origin
        return NamedSpace(name: name, toSpace: toWindow.inverted, toWindow: toWindow)
    }

    /// `localSpace(of:name:)` at the union of `nodes`' bounds, or `nil` for no
    /// node (`OV-N`: the computation `noteGeometry`, the scope and an overlay's
    /// `.local` share).
    func localSpace(of nodes: [LayoutNodeID], name: AnyHashable = AnyHashable(LocalSpaceName())) -> NamedSpace? {
        guard !nodes.isEmpty else { return nil }
        return localSpace(of: union(of: nodes), name: name)
    }

    /// The union of `nodes`' bounds (at least one node).
    func union(of nodes: [LayoutNodeID]) -> Bounds<Pixels> {
        var union = bounds(of: nodes[0])
        for node in nodes.dropFirst() {
            let b = bounds(of: node)
            let minX = min(union.origin.x.value, b.origin.x.value)
            let minY = min(union.origin.y.value, b.origin.y.value)
            let maxX = max(union.origin.x.value + union.size.width.value, b.origin.x.value + b.size.width.value)
            let maxY = max(union.origin.y.value + union.size.height.value, b.origin.y.value + b.size.height.value)
            union = Bounds(origin: Point(x: Pixels(minX), y: Pixels(minY)),
                           size: Size(width: Pixels(maxX - minX), height: Pixels(maxY - minY)))
        }
        return union
    }

    /// The innermost named space in force called `name`, or `nil` (missing or
    /// degenerate) — prepaint's resolution (`OV-E` item 3): geometry and an
    /// overlay's `.named` point.
    func namedSpace(_ name: AnyHashable) -> NamedSpace? {
        NamedSpace.resolve(name, in: namedSpaces)
    }

    /// `body` — a scope's content prepaint — with `space` the innermost named
    /// space. Closure form, so an unbalanced stack is not expressible.
    func withNamedSpace<R>(_ space: NamedSpace, _ body: () -> R) -> R {
        namedSpaces.append(space)
        defer { namedSpaces.removeLast() }
        return body()
    }
}

/// A `CoordinateSpaceScope`'s layout: its content's and the content's nodes.
public struct CoordinateSpaceScopeLayout<ContentLayout> {
    var content: ContentLayout
    var nodes: [LayoutNodeID]
}

/// `content` declaring a named coordinate space — what `coordinateSpace(_:)`
/// returns (ruling `OV-E` item 1).
///
/// **Transparent** like `GeometryChangeScope`: `parent` and `cursor` are
/// forwarded, no node, no identity level, no `StateTable` slot. **A
/// `Self`-returning decoration written after this scope does not compile**
/// (divergence 120's footing, `KF-V` item 1): write it first.
public struct CoordinateSpaceScope<Content: ElementGroup>: ElementGroup {
    var content: Content
    let name: AnyHashable

    init(content: Content, name: AnyHashable) {
        self.content = content
        self.name = name
    }

    /// Lays the content out with the caller's parent and cursor.
    public mutating func requestGroupLayout(under parent: GlobalElementID?,
                                            at cursor: inout Int,
                                            pass: inout LayoutPass)
        -> ([LayoutNodeID], CoordinateSpaceScopeLayout<Content.GroupLayout>) {
        let (nodes, layout) = content.requestGroupLayout(under: parent, at: &cursor, pass: &pass)
        return (nodes, CoordinateSpaceScopeLayout(content: layout, nodes: nodes))
    }

    /// Prepaints the content with this space the innermost named space
    /// (`OV-E` item 2); content that registered nothing declares nothing.
    public mutating func prepaintGroup(layout: inout CoordinateSpaceScopeLayout<Content.GroupLayout>,
                                       pass: inout PrepaintPass) -> Content.GroupPrepaint {
        guard let space = pass.frame.localSpace(of: layout.nodes, name: name) else {
            return content.prepaintGroup(layout: &layout.content, pass: &pass)
        }
        return pass.frame.withNamedSpace(space) {
            content.prepaintGroup(layout: &layout.content, pass: &pass)
        }
    }

    /// Paints the content unchanged.
    public mutating func paintGroup(layout: inout CoordinateSpaceScopeLayout<Content.GroupLayout>,
                                    prepaint: inout Content.GroupPrepaint,
                                    pass: inout PaintPass) {
        content.paintGroup(layout: &layout.content, prepaint: &prepaint, pass: &pass)
    }
}

extension CoordinateSpaceScope: ProposalElementGroup where Content: ProposalElementGroup {
    /// The typed entry: a line-for-line copy of the untyped one, pinned on its
    /// own (test A8).
    public mutating func requestProposalGroupLayout(under parent: GlobalElementID?,
                                                    at cursor: inout Int,
                                                    pass: inout LayoutPass)
        -> ([ProposalNodeID], CoordinateSpaceScopeLayout<Content.GroupLayout>) {
        let (nodes, layout) = content.requestProposalGroupLayout(under: parent, at: &cursor, pass: &pass)
        return (nodes, CoordinateSpaceScopeLayout(content: layout, nodes: nodes.map(\.layoutNodeID)))
    }
}

extension ElementGroup {
    /// Declares a named coordinate space on this group — SwiftUI's
    /// `coordinateSpace(_:)` (ruling `OV-D`; probe arms G1–G7). A descendant's
    /// `frame(in: .named(name))`, `onContinuousHover(coordinateSpace:)`,
    /// `DragGesture(coordinateSpace:)` or `SpatialTapGesture(coordinateSpace:)`
    /// reports relative to this group's top-leading corner; the space moves with
    /// enclosing scroll offsets and with render effects written **after** this
    /// modifier (a rotated space reports unrotated frames, G6). The nearest
    /// ancestor wins; a name no ancestor declares falls back to `.global`.
    /// A presentation's content (`.popover`, `Deferred`) resolves its
    /// declarer's spaces (`OV-M` item 2).
    ///
    /// Only `.named(_:)` can be spelled (`NamedCoordinateSpace`); SwiftUI's
    /// deprecated `coordinateSpace(name:)` is not offered. Transparent: no
    /// node, no identity level (`CoordinateSpaceScope`).
    public func coordinateSpace(_ space: NamedCoordinateSpace) -> CoordinateSpaceScope<Self> {
        CoordinateSpaceScope(content: self, name: space.name)
    }
}
