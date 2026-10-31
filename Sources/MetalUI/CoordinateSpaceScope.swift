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

/// A `CoordinateSpaceScope`'s layout: its content's and the content's nodes —
/// or, for a scope with a decoration written after it (ruling `ES-H`), the
/// layout of the one legacy layer that wraps the undecorated scope.
public struct CoordinateSpaceScopeLayout<ContentLayout> {
    var content: ContentLayout?
    var nodes: [LayoutNodeID]
    var layered: Any?
}

/// `content` declaring a named coordinate space — what `coordinateSpace(_:)`
/// returns (ruling `OV-E` item 1).
///
/// **Transparent** like `GeometryChangeScope`: `parent` and `cursor` are
/// forwarded, no node, no identity level, no `StateTable` slot.
///
/// **A `Self`-returning decoration written after it sits outside the space**
/// (ruling `ES-H`, lifting `ES-F`): over a `StyledElement` the scope is a
/// `StyledElement` whose accessors read and write one legacy layer of its own
/// (`outer`, a `.padding(0)` layer), created by the first decoration written
/// after it. A decorated scope lays out, prepaints and paints as
/// `ModifiedElement<Self>` over the undecorated scope — exactly
/// `.coordinateSpace(...).padding(0).offset(...)` — so the layer's render
/// effects are open when the space is built and an `.offset(x: 7, y: 9)` after
/// the scope moves the space with the view: a child reads (0, 0) in it, as
/// SwiftUI's G3. Forwarding the decoration onto the content instead put it
/// inside the space (the child read (7, 9), record 168). The layer is one node
/// and one identity level, present whenever a decoration is written after the
/// scope (a static property of the expression, so it never appears at run time).
public struct CoordinateSpaceScope<Content: ElementGroup>: ElementGroup {
    var content: Content
    let name: AnyHashable
    /// The legacy layer a decoration written after the scope configures; `nil`
    /// until one is (ruling `ES-H`).
    var outer: ModifierLayer?

    init(content: Content, name: AnyHashable) {
        self.content = content
        self.name = name
        self.outer = nil
    }

    /// `body` run on the decorated form, `ModifiedElement<Self>` over this scope
    /// without its layer, and what it changed written back (a layer stores its
    /// animated style in layout, which later phases read).
    private mutating func withLayer<R>(_ body: (inout ModifiedElement<Self>) -> R) -> R {
        var bare = self
        bare.outer = nil
        var layered = ModifiedElement(content: bare, layer: outer ?? ModifierLayer(style: Style()))
        defer {
            content = layered.content.content
            outer = layered.outermost
        }
        return body(&layered)
    }

    /// Lays the content out with the caller's parent and cursor; a decorated
    /// scope lays out as its layer over the undecorated scope (`ES-H`).
    public mutating func requestGroupLayout(under parent: GlobalElementID?,
                                            at cursor: inout Int,
                                            pass: inout LayoutPass)
        -> ([LayoutNodeID], CoordinateSpaceScopeLayout<Content.GroupLayout>) {
        if outer != nil {
            let (nodes, layout) = withLayer { $0.requestGroupLayout(under: parent, at: &cursor, pass: &pass) }
            return (nodes, CoordinateSpaceScopeLayout(content: nil, nodes: nodes, layered: layout))
        }
        let (nodes, layout) = content.requestGroupLayout(under: parent, at: &cursor, pass: &pass)
        return (nodes, CoordinateSpaceScopeLayout(content: layout, nodes: nodes, layered: nil))
    }

    /// Prepaints the content with this space the innermost named space
    /// (`OV-E` item 2); content that registered nothing declares nothing. A
    /// decorated scope's layer registers first, so its effects are open when the
    /// space is built (`ES-H`).
    public mutating func prepaintGroup(layout: inout CoordinateSpaceScopeLayout<Content.GroupLayout>,
                                       pass: inout PrepaintPass) -> Content.GroupPrepaint {
        if var layered = layout.layered as? SingleElementLayout<ModifiedElement<Self>> {
            defer { layout.layered = layered }
            return withLayer { $0.prepaintGroup(layout: &layered, pass: &pass) }
        }
        guard let space = pass.frame.localSpace(of: layout.nodes, name: name) else {
            return content.prepaintGroup(layout: &layout.content!, pass: &pass)
        }
        return pass.frame.withNamedSpace(space) {
            content.prepaintGroup(layout: &layout.content!, pass: &pass)
        }
    }

    /// Paints the content unchanged; a decorated scope's layer paints around it.
    public mutating func paintGroup(layout: inout CoordinateSpaceScopeLayout<Content.GroupLayout>,
                                    prepaint: inout Content.GroupPrepaint,
                                    pass: inout PaintPass) {
        if var layered = layout.layered as? SingleElementLayout<ModifiedElement<Self>> {
            defer { layout.layered = layered }
            withLayer { $0.paintGroup(layout: &layered, prepaint: &prepaint, pass: &pass) }
            return
        }
        content.paintGroup(layout: &layout.content!, prepaint: &prepaint, pass: &pass)
    }
}

extension CoordinateSpaceScope: ProposalElementGroup where Content: ProposalElementGroup {
    /// The typed entry: a line-for-line copy of the untyped one, pinned on its
    /// own (test A8). A decoration can be written after the scope only over a
    /// `StyledElement`, which is never proposal content, so a decorated scope
    /// takes the untyped entry's layer path (`ES-H`).
    public mutating func requestProposalGroupLayout(under parent: GlobalElementID?,
                                                    at cursor: inout Int,
                                                    pass: inout LayoutPass)
        -> ([ProposalNodeID], CoordinateSpaceScopeLayout<Content.GroupLayout>) {
        if outer != nil {
            let (nodes, layout) = requestGroupLayout(under: parent, at: &cursor, pass: &pass)
            return (nodes.map(ProposalNodeID.init), layout)
        }
        let (nodes, layout) = content.requestProposalGroupLayout(under: parent, at: &cursor, pass: &pass)
        return (nodes, CoordinateSpaceScopeLayout(content: layout, nodes: nodes.map(\.layoutNodeID), layered: nil))
    }
}

// MARK: - Decorations after the scope sit outside the space (`ES-H`)

/// `ES-H`: the scope over an element is an element (a window root, `Deferred` content, a `List` row) — the space
/// built from the element's own bounds around its content's prepaint — and over a `StyledElement` a
/// `StyledElement` whose accessors configure the scope's own layer, outside the space. A decorated scope on this
/// path is its layer as an element over the undecorated scope as that layer's content.
extension CoordinateSpaceScope: Element where Content: Element {
    public typealias LayoutState = ScopeLayerState<Content.LayoutState>
    public typealias PrepaintState = ScopeLayerState<Content.PrepaintState>

    public mutating func requestLayout(_ id: GlobalElementID, pass: inout LayoutPass)
        -> (LayoutNodeID, ScopeLayerState<Content.LayoutState>) {
        if outer != nil {
            let (node, layout) = withLayer { $0.requestLayout(id, pass: &pass) }
            return (node, ScopeLayerState(plain: nil, layered: layout))
        }
        let (node, state) = content.requestLayout(id, pass: &pass)
        return (node, ScopeLayerState(plain: state, layered: nil))
    }

    public mutating func prepaint(_ id: GlobalElementID, bounds: Bounds<Pixels>,
                                  layout: inout ScopeLayerState<Content.LayoutState>,
                                  pass: inout PrepaintPass) -> ScopeLayerState<Content.PrepaintState> {
        if var layered = layout.layered as? ModifiedElement<Self>.Layout {
            defer { layout.layered = layered }
            let inner = withLayer { $0.prepaint(id, bounds: bounds, layout: &layered, pass: &pass) }
            return ScopeLayerState(plain: nil, layered: inner)
        }
        let space = pass.frame.localSpace(of: bounds, name: name)
        let state = pass.frame.withNamedSpace(space) {
            content.prepaint(id, bounds: bounds, layout: &layout.plain!, pass: &pass)
        }
        return ScopeLayerState(plain: state, layered: nil)
    }

    public mutating func paint(_ id: GlobalElementID, bounds: Bounds<Pixels>,
                               layout: inout ScopeLayerState<Content.LayoutState>,
                               prepaint: inout ScopeLayerState<Content.PrepaintState>, pass: inout PaintPass) {
        if var layered = layout.layered as? ModifiedElement<Self>.Layout,
           var inner = prepaint.layered as? Content.GroupPrepaint {
            defer { layout.layered = layered; prepaint.layered = inner }
            withLayer { $0.paint(id, bounds: bounds, layout: &layered, prepaint: &inner, pass: &pass) }
            return
        }
        content.paint(id, bounds: bounds, layout: &layout.plain!, prepaint: &prepaint.plain!, pass: &pass)
    }
}

extension CoordinateSpaceScope: StyledElement where Content: StyledElement {
    public var style: Style {
        get { outer?.style ?? Style() }
        set { configureLayer { $0.style = newValue } }
    }
    public var decoration: Decoration {
        get { outer?.decoration ?? Decoration() }
        set { configureLayer { $0.decoration = newValue } }
    }
    public var elementID: ElementID? {
        get { outer?.elementID }
        set { configureLayer { $0.elementID = newValue } }
    }
    public var handlers: Handlers {
        get { outer?.handlers ?? Handlers() }
        set { configureLayer { $0.handlers = newValue } }
    }
}

extension CoordinateSpaceScope {
    /// Writes the scope's own layer, creating it (a `.padding(0)` layer) on the
    /// first decoration written after the scope (`ES-H`).
    mutating func configureLayer(_ change: (inout ModifierLayer) -> Void) {
        var layer = outer ?? ModifierLayer(style: Style())
        change(&layer)
        outer = layer
    }

    /// Names the scope **together with** its content and layer (ruling `ES-C`,
    /// carried by `ES-H`): this member wins over `StyledElement`'s own
    /// `id(_:) -> Self`, which would name the layer only.
    public func id(_ name: String) -> IdentifiedGroup<Self> {
        IdentifiedGroup(content: self, name: ElementID(name))
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
