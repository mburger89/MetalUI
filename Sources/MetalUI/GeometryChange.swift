import MetalUICore
import MetalUILayout

// MARK: - `onGeometryChange(for:of:action:)` (rulings `KF-J`, `KF-S`, `KF-V` item 1)
//
// Probe `docs/probes/swiftui-key-focus.swift`, arms G1–G7. STUB (lane B red):
// the API compiles and the scope forwards its content; nothing is noted.

/// The geometry an `onGeometryChange` transform reads (ruling `KF-J` item 1):
/// the content's size and its frame in a coordinate space. MetalUI's geometry
/// types; `Sendable` where SwiftUI's proxy is not (`KF-S`).
public struct GeometryProxy: Sendable {
    /// The content's laid-out size — the union of its nodes, before any render
    /// effect (a `scaleEffect` does not change it).
    public let size: Size<Pixels>
    let globalFrame: Bounds<Pixels>

    init(size: Size<Pixels>, globalFrame: Bounds<Pixels>) {
        self.size = size
        self.globalFrame = globalFrame
    }

    /// The content's frame in `space`: `.local` is `size` at the origin;
    /// `.global` is the window's content space (divergence 139's), moved by
    /// enclosing scroll offsets and the bounding box under enclosing render
    /// effects (an `.offset` written after the modifier included, G4a).
    public func frame(in space: CoordinateSpace) -> Bounds<Pixels> {
        switch space {
        case .local: Bounds(origin: Point(x: Pixels(0), y: Pixels(0)), size: size)
        case .global: globalFrame
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
/// the scope's store key (`nil` when the content registered nothing).
public struct GeometryChangeScopeLayout<ContentLayout> {
    var content: ContentLayout
    var nodes: [LayoutNodeID]
    var key: GlobalElementID?
    var owner: GlobalElementID?
}

/// `content` with a geometry action — what `onGeometryChange(for:of:action:)`
/// returns (ruling `KF-J`).
///
/// **Transparent** like `LifecycleScope`: `parent` and `cursor` are forwarded,
/// no node, no `StateTable` slot. **A `Self`-returning decoration written
/// after this scope does not compile** (divergence 120, `KF-V` item 1): write
/// it first.
public struct GeometryChangeScope<Content: ElementGroup>: ElementGroup {
    var content: Content
    let watch: GeometryWatch

    init(content: Content, watch: GeometryWatch) {
        self.content = content
        self.watch = watch
    }

    /// Lays the content out with the caller's parent and cursor.
    public mutating func requestGroupLayout(under parent: GlobalElementID?,
                                            at cursor: inout Int,
                                            pass: inout LayoutPass)
        -> ([LayoutNodeID], GeometryChangeScopeLayout<Content.GroupLayout>) {
        let (nodes, layout) = content.requestGroupLayout(under: parent, at: &cursor, pass: &pass)
        return (nodes, GeometryChangeScopeLayout(content: layout, nodes: nodes, key: nil, owner: nil))
    }

    /// Prepaints the content.
    public mutating func prepaintGroup(layout: inout GeometryChangeScopeLayout<Content.GroupLayout>,
                                       pass: inout PrepaintPass) -> Content.GroupPrepaint {
        content.prepaintGroup(layout: &layout.content, pass: &pass)
    }

    /// Paints the content unchanged.
    public mutating func paintGroup(layout: inout GeometryChangeScopeLayout<Content.GroupLayout>,
                                    prepaint: inout Content.GroupPrepaint,
                                    pass: inout PaintPass) {
        content.paintGroup(layout: &layout.content, prepaint: &prepaint, pass: &pass)
    }
}

extension GeometryChangeScope: ProposalElementGroup where Content: ProposalElementGroup {
    /// The typed entry: a line-for-line copy of the untyped one, pinned on its
    /// own (spec test B14).
    public mutating func requestProposalGroupLayout(under parent: GlobalElementID?,
                                                    at cursor: inout Int,
                                                    pass: inout LayoutPass)
        -> ([ProposalNodeID], GeometryChangeScopeLayout<Content.GroupLayout>) {
        let (nodes, layout) = content.requestProposalGroupLayout(under: parent, at: &cursor, pass: &pass)
        return (nodes, GeometryChangeScopeLayout(content: layout, nodes: nodes.map(\.layoutNodeID),
                                                 key: nil, owner: nil))
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
