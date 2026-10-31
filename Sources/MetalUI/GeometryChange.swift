import MetalUICore
import MetalUILayout

// MARK: - `onGeometryChange(for:of:action:)` (rulings `KF-J`, `KF-S`, `KF-V` item 1)
//
// Probe `docs/probes/swiftui-key-focus.swift`, arms G1–G7. One transparent
// scope, `GeometryChangeScope`, the shape of `LifecycleScope`: in layout it
// records its position key and its content's nodes; in PREPAINT it computes
// the proxy, calls the transform and notes the value into the window's
// `LifecycleStore`, whose `endFrame` turns a new or changed value into an event
// that `Window.drainLifecycle` runs after the build, under `StateDispatch`,
// ahead of the lifecycle's own events (`KF-J` items 3–4). Nothing runs in a
// phase but the transform, which must not write.

/// The geometry an `onGeometryChange` transform reads (ruling `KF-J` item 1):
/// the content's size and its frame in a coordinate space. MetalUI's geometry
/// types; `Sendable` where SwiftUI's proxy is not (`KF-S`).
public struct GeometryProxy: Sendable {
    /// The content's laid-out size — the union of its nodes, before any render
    /// effect (a `scaleEffect` does not change it).
    public let size: Size<Pixels>
    let globalFrame: Bounds<Pixels>
    /// The union, scrolled — window points before the open render effects —
    /// and the innermost open effect's composed map (`nil`: none), for a named
    /// frame (`OV-M` item 1).
    let scrolledFrame: Bounds<Pixels>
    let composed: Affine2D?
    /// The named spaces in force at the scope, innermost last (`OV-E`).
    let namedSpaces: [NamedSpace]

    init(size: Size<Pixels>, globalFrame: Bounds<Pixels>, scrolledFrame: Bounds<Pixels>? = nil,
         composed: Affine2D? = nil, namedSpaces: [NamedSpace] = []) {
        self.size = size
        self.globalFrame = globalFrame
        self.scrolledFrame = scrolledFrame ?? globalFrame
        self.composed = composed
        self.namedSpaces = namedSpaces
    }

    /// The content's frame in `space`: `.local` is `size` at the origin;
    /// `.global` is the window's content space (divergence 139's), moved by
    /// enclosing scroll offsets and the bounding box under enclosing render
    /// effects (an `.offset` written after the modifier included, G4a).
    /// `.named(n)` is relative to the nearest ancestor that declared
    /// `.coordinateSpace(.named(n))` (`OV-E`, `OV-M`): the content mapped
    /// through its own effects and then the space's inverse map, boxed once —
    /// so a space rotated as a whole reports the unrotated frame (G6) and an
    /// effect between the space and the content its bounding box in the space
    /// (G7). A name no ancestor declares reads `.global` (G1, G5).
    public func frame(in space: CoordinateSpace) -> Bounds<Pixels> {
        switch space {
        case .local:
            return Bounds(origin: Point(x: Pixels(0), y: Pixels(0)), size: size)
        case .global:
            return globalFrame
        case .named(let name):
            guard let toSpace = NamedSpace.resolve(name, in: namedSpaces)?.toSpace else { return globalFrame }
            let map = composed.map { toSpace.concatenating($0) } ?? toSpace
            return map.boundingBox(of: scrolledFrame)
        }
    }
}

/// What one `GeometryChangeScope` watches, with its value type erased.
struct GeometryWatch {
    let transform: (GeometryProxy) -> Any
    let isEqual: (Any, Any) -> Bool
    let action: (Any, Any) -> Void
}

/// A `GeometryChangeScope`'s layout: its content's, the content's nodes and
/// the scope's store key (`nil` when the content registered nothing) — or, for
/// a scope with a decoration written after it (ruling `ES-J`), the layout of
/// the one legacy layer that wraps the undecorated scope.
public struct GeometryChangeScopeLayout<ContentLayout> {
    var content: ContentLayout?
    var nodes: [LayoutNodeID]
    var key: GlobalElementID?
    var owner: GlobalElementID?
    var layered: Any? = nil

    /// The store key and owner of a scope at `cursor` under `parent`
    /// (`KF-J` item 3): the owner — which the action is dispatched to — is the
    /// position; the key is `.named("$geometry<depth>")` under it, `depth` the
    /// geometry scopes enclosing this one. Two scopes stacked at one position
    /// are kept as two entries by `LifecycleStore.noteGeometry`'s occurrence
    /// ordinal, not by `depth`: replacing `depth` with 0 reddens nothing
    /// (`KF-Y` item 4, equivalent per `LR-X`); `depth` stays as `LC-C` item 2's
    /// spelling. A store key, never a `StateTable` id (no reserved name, no
    /// `noteNamed`).
    static func key(under parent: GlobalElementID?, at cursor: Int,
                    depth: Int) -> (GlobalElementID?, GlobalElementID?) {
        let owner = GlobalElementID.child(of: parent, at: cursor, name: nil)
        return (GlobalElementID.child(of: owner, at: 0, name: ElementID("$geometry\(depth)")), owner)
    }
}

extension Frame {
    /// Notes a geometry scope's value this build (prepaint, `KF-J` item 3):
    /// the union of `nodes`' bounds is the size (untransformed); the global
    /// frame is that rect moved by the scroll translation in force
    /// (`activeOffset`, as a hitbox is) under the innermost open render
    /// effect's composed map, as a bounding box (as accessibility frames are),
    /// so an `.offset` written after the modifier is included (G4a).
    func noteGeometry(_ watch: GeometryWatch, key: GlobalElementID, owner: GlobalElementID,
                      nodes: [LayoutNodeID]) {
        let contentUnion = union(of: nodes)
        let moved = scrolled(contentUnion)
        let composed = prepaintEffects.last?.composed
        let global = composed.map { $0.boundingBox(of: moved) } ?? moved
        let value = watch.transform(GeometryProxy(size: contentUnion.size, globalFrame: global, scrolledFrame: moved,
                                                  composed: composed, namedSpaces: namedSpaces))
        // A ledger replays the note (`RG-A`, replacing `RK-E`'s taint): the store forgets a key a build did not note.
        prepaintLog?.geometry.append(GeometryNoteRecord(
            watch: watch, key: key, owner: owner, value: value, global: global, size: contentUnion.size, moved: moved,
            composed: composed, chain: currentEffectChain(), namedSpaces: namedSpaces))
        animationStore.lifecycle.noteGeometry(value, watch: watch, key: key, owner: owner)
    }
}

/// `content` with a geometry action — what `onGeometryChange(for:of:action:)`
/// returns (ruling `KF-J`).
///
/// **Transparent** like `LifecycleScope`: `parent` and `cursor` are forwarded,
/// no node, no `StateTable` slot.
///
/// **A `Self`-returning decoration written after it sits outside the measured
/// geometry** (ruling `ES-J`, lifting `ES-B`; `ES-H`'s mechanism): over a
/// `StyledElement` the scope is a `StyledElement` whose accessors read and
/// write one legacy layer of its own (`outer`, a `.padding(0)` layer), created
/// by the first decoration written after it. A decorated scope lays out,
/// prepaints and paints as `ModifiedElement<Self>` over the undecorated scope,
/// so the size it reports is its content's alone, and the layer's render
/// effects are open when it notes: an `.offset(x: 10)` after it moves the
/// reported global frame by 10, as SwiftUI's G4a. Forwarding the decoration onto
/// the content instead opened the offset after the note (the global frame did
/// not move).
public struct GeometryChangeScope<Content: ElementGroup>: ElementGroup {
    var content: Content
    let watch: GeometryWatch
    /// The legacy layer a decoration written after the scope configures; `nil`
    /// until one is (ruling `ES-J`).
    var outer: ModifierLayer?

    init(content: Content, watch: GeometryWatch) {
        self.content = content
        self.watch = watch
        self.outer = nil
    }

    /// `body` run on the decorated form, `ModifiedElement<Self>` over this scope
    /// without its layer, and what it changed written back (`ES-H`'s `withLayer`).
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
    /// scope lays out as its layer over the undecorated scope (`ES-J`).
    public mutating func requestGroupLayout(under parent: GlobalElementID?,
                                            at cursor: inout Int,
                                            pass: inout LayoutPass)
        -> ([LayoutNodeID], GeometryChangeScopeLayout<Content.GroupLayout>) {
        if outer != nil {
            let (nodes, layout) = withLayer { $0.requestGroupLayout(under: parent, at: &cursor, pass: &pass) }
            return (nodes, GeometryChangeScopeLayout(content: nil, nodes: nodes, key: nil, owner: nil,
                                                     layered: layout))
        }
        let start = cursor
        let store = pass.frame.animationStore.lifecycle
        let depth = store.geometryDepth
        let (nodes, layout) = store.withGeometryScope {
            content.requestGroupLayout(under: parent, at: &cursor, pass: &pass)
        }
        let (key, owner) = nodes.isEmpty ? (nil, nil) : GeometryChangeScopeLayout<Content.GroupLayout>
            .key(under: parent, at: start, depth: depth)
        return (nodes, GeometryChangeScopeLayout(content: layout, nodes: nodes, key: key, owner: owner))
    }

    /// Prepaints the content; a decorated scope's layer registers first, so its
    /// effects are open when the geometry is noted (`ES-J`).
    public mutating func prepaintGroup(layout: inout GeometryChangeScopeLayout<Content.GroupLayout>,
                                       pass: inout PrepaintPass) -> Content.GroupPrepaint {
        if var layered = layout.layered as? SingleElementLayout<ModifiedElement<Self>> {
            defer { layout.layered = layered }
            return withLayer { $0.prepaintGroup(layout: &layered, pass: &pass) }
        }
        if let key = layout.key, let owner = layout.owner {
            pass.frame.noteGeometry(watch, key: key, owner: owner, nodes: layout.nodes)
        }
        return content.prepaintGroup(layout: &layout.content!, pass: &pass)
    }

    /// Paints the content unchanged; a decorated scope's layer paints around it.
    public mutating func paintGroup(layout: inout GeometryChangeScopeLayout<Content.GroupLayout>,
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

extension GeometryChangeScope: ProposalElementGroup where Content: ProposalElementGroup {
    /// The typed entry: a line-for-line copy of the untyped one, pinned on its
    /// own (spec test B14). A decorated scope (only over a `StyledElement`, never
    /// proposal content) takes the untyped entry's layer path (`ES-J`).
    public mutating func requestProposalGroupLayout(under parent: GlobalElementID?,
                                                    at cursor: inout Int,
                                                    pass: inout LayoutPass)
        -> ([ProposalNodeID], GeometryChangeScopeLayout<Content.GroupLayout>) {
        if outer != nil {
            let (nodes, layout) = requestGroupLayout(under: parent, at: &cursor, pass: &pass)
            return (nodes.map(ProposalNodeID.init), layout)
        }
        let start = cursor
        let store = pass.frame.animationStore.lifecycle
        let depth = store.geometryDepth
        let (nodes, layout) = store.withGeometryScope {
            content.requestProposalGroupLayout(under: parent, at: &cursor, pass: &pass)
        }
        let (key, owner) = nodes.isEmpty ? (nil, nil) : GeometryChangeScopeLayout<Content.GroupLayout>
            .key(under: parent, at: start, depth: depth)
        return (nodes, GeometryChangeScopeLayout(content: layout, nodes: nodes.map(\.layoutNodeID),
                                                 key: key, owner: owner))
    }
}

// MARK: - Decorations after the scope sit outside the measurement (`ES-J`)

/// `ES-J`: the scope over an element is an element (a window root, `Deferred` content, a `List` row) — noting the
/// element's own node, keyed under the element's id, which owns the action — and over a `StyledElement` a
/// `StyledElement` whose accessors configure the scope's own layer, outside the measurement. A decorated scope on
/// this path is its layer as an element over the undecorated scope as that layer's content.
extension GeometryChangeScope: Element where Content: Element {
    public typealias LayoutState = ScopeLayerState<GeometryChangeScopeLayout<Content.LayoutState>>
    public typealias PrepaintState = ScopeLayerState<Content.PrepaintState>

    public mutating func requestLayout(_ id: GlobalElementID, pass: inout LayoutPass)
        -> (LayoutNodeID, ScopeLayerState<GeometryChangeScopeLayout<Content.LayoutState>>) {
        if outer != nil {
            let (node, layout) = withLayer { $0.requestLayout(id, pass: &pass) }
            return (node, ScopeLayerState(plain: nil, layered: layout))
        }
        let store = pass.frame.animationStore.lifecycle
        let depth = store.geometryDepth
        let (node, state) = store.withGeometryScope { content.requestLayout(id, pass: &pass) }
        let key = GlobalElementID.child(of: id, at: 0, name: ElementID("$geometry\(depth)"))
        return (node, ScopeLayerState(plain: GeometryChangeScopeLayout(content: state, nodes: [node], key: key,
                                                                       owner: id),
                                      layered: nil))
    }

    public mutating func prepaint(_ id: GlobalElementID, bounds: Bounds<Pixels>,
                                  layout: inout ScopeLayerState<GeometryChangeScopeLayout<Content.LayoutState>>,
                                  pass: inout PrepaintPass) -> ScopeLayerState<Content.PrepaintState> {
        if var layered = layout.layered as? ModifiedElement<Self>.Layout {
            defer { layout.layered = layered }
            let inner = withLayer { $0.prepaint(id, bounds: bounds, layout: &layered, pass: &pass) }
            return ScopeLayerState(plain: nil, layered: inner)
        }
        if let key = layout.plain!.key, let owner = layout.plain!.owner {
            pass.frame.noteGeometry(watch, key: key, owner: owner, nodes: layout.plain!.nodes)
        }
        let state = content.prepaint(id, bounds: bounds, layout: &layout.plain!.content!, pass: &pass)
        return ScopeLayerState(plain: state, layered: nil)
    }

    public mutating func paint(_ id: GlobalElementID, bounds: Bounds<Pixels>,
                               layout: inout ScopeLayerState<GeometryChangeScopeLayout<Content.LayoutState>>,
                               prepaint: inout ScopeLayerState<Content.PrepaintState>, pass: inout PaintPass) {
        if var layered = layout.layered as? ModifiedElement<Self>.Layout,
           var inner = prepaint.layered as? Content.GroupPrepaint {
            defer { layout.layered = layered; prepaint.layered = inner }
            withLayer { $0.paint(id, bounds: bounds, layout: &layered, prepaint: &inner, pass: &pass) }
            return
        }
        content.paint(id, bounds: bounds, layout: &layout.plain!.content!, prepaint: &prepaint.plain!, pass: &pass)
    }
}

extension GeometryChangeScope: StyledElement where Content: StyledElement {
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

extension GeometryChangeScope {
    /// Writes the scope's own layer, creating it (a `.padding(0)` layer) on the
    /// first decoration written after the scope (`ES-J`).
    mutating func configureLayer(_ change: (inout ModifierLayer) -> Void) {
        var layer = outer ?? ModifierLayer(style: Style())
        change(&layer)
        outer = layer
    }

    /// Names the scope **together with** its content and layer (ruling `ES-C`,
    /// carried by `ES-J`): this member wins over `StyledElement`'s own
    /// `id(_:) -> Self`, which would name the layer only.
    public func id(_ name: String) -> IdentifiedGroup<Self> {
        IdentifiedGroup(content: self, name: ElementID(name))
    }
}

extension ElementGroup {
    /// Runs `action` with the value `transform` reads from this group's
    /// geometry — once with the initial value, before `onAppear`, then each
    /// time it changes (SwiftUI's `onGeometryChange(for:of:action:)`, macOS
    /// 15; ruling `KF-J`).
    public func onGeometryChange<T: Equatable>(for type: T.Type,
                                               of transform: @escaping (GeometryProxy) -> T,
                                               action: @escaping (_ newValue: T) -> Void)
        -> GeometryChangeScope<Self> {
        GeometryChangeScope(content: self, watch: GeometryWatch(
            transform: { transform($0) },
            isEqual: { ($0 as? T) == ($1 as? T) },
            action: { _, new in if let new = new as? T { action(new) } }))
    }

    /// The two-parameter form of `onGeometryChange(for:of:action:)`: the
    /// action receives the old and the new value; the initial call passes the
    /// initial value as both (G1).
    public func onGeometryChange<T: Equatable>(for type: T.Type,
                                               of transform: @escaping (GeometryProxy) -> T,
                                               action: @escaping (_ oldValue: T, _ newValue: T) -> Void)
        -> GeometryChangeScope<Self> {
        GeometryChangeScope(content: self, watch: GeometryWatch(
            transform: { transform($0) },
            isEqual: { ($0 as? T) == ($1 as? T) },
            action: { old, new in
                if let old = old as? T, let new = new as? T { action(old, new) }
            }))
    }
}
