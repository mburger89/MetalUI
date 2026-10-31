import MetalUICore
import MetalUILayout

// Round 3 item R3-2 — `matchedGeometryEffect` (ruling family `MG-`,
// `docs/superpowers/2026-10-31-matched-geometry-decisions.md`). SwiftUI's side is
// `docs/probes/swiftui-matched-geometry.swift`. The bookkeeping is ``MatchedGeometryStore``.

/// Which parts of a view's frame a ``ElementGroup/matchedGeometryEffect(id:in:properties:anchor:isSource:)``
/// shares — SwiftUI's `MatchedGeometryProperties`.
public struct MatchedGeometryProperties: OptionSet, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    /// The position: the point at the effect's `anchor` (the centre by default).
    public static let position = MatchedGeometryProperties(rawValue: 1 << 0)
    /// The size.
    public static let size = MatchedGeometryProperties(rawValue: 1 << 1)
    /// Both the position and the size (SwiftUI's default).
    public static let frame: MatchedGeometryProperties = [.position, .size]
}

/// A `MatchedGeometryGroup`'s layout: its store key when it claimed its position, `nil` when it is inert, and
/// its content's layout.
public struct MatchedGeometryGroupLayout<ContentLayout> {
    var key: GlobalElementID?
    var content: ContentLayout
}

/// `content` with its geometry shared in a namespace — what `matchedGeometryEffect(id:in:...)` returns. See
/// ``ElementGroup/matchedGeometryEffect(id:in:properties:anchor:isSource:)``.
///
/// **Layout- and identity-TRANSPARENT**, the shape of ``TransitionGroup`` (`MG-A`): `parent` and `cursor` are
/// forwarded unchanged, so adding or removing the modifier moves no id and resets no `@State`; its bookkeeping
/// lives in the window's `AnimationStore`, never in `StateTable`. **Paint only:** it opens an affine
/// render-effect scope around its content, so hit testing, focus and accessibility keep the laid-out geometry
/// (divergence 895).
///
/// **Over a `StyledElement` it is a `StyledElement`** (`ES-E`'s shape): a decoration written after it lands on
/// the content inside the group and moves with it.
public struct MatchedGeometryGroup<Content: ElementGroup>: ElementGroup {
    var content: Content
    let spec: MatchedGeometryStore.Spec

    init(content: Content, spec: MatchedGeometryStore.Spec) {
        self.content = content
        self.spec = spec
    }

    public mutating func requestGroupLayout(under parent: GlobalElementID?,
                                            at cursor: inout Int,
                                            pass: inout LayoutPass)
        -> ([LayoutNodeID], MatchedGeometryGroupLayout<Content.GroupLayout>) {
        let key = pass.frame.claimMatchedGeometry(spec, under: parent, at: cursor)
        let (nodes, layout) = content.requestGroupLayout(under: parent, at: &cursor, pass: &pass)
        if let key { pass.frame.animationStore.matched.setNodes(nodes, for: key) }
        return (nodes, MatchedGeometryGroupLayout(key: key, content: layout))
    }

    public mutating func prepaintGroup(layout: inout MatchedGeometryGroupLayout<Content.GroupLayout>,
                                       pass: inout PrepaintPass) -> Content.GroupPrepaint {
        // Nothing: hit testing, focus and accessibility use the laid-out geometry.
        content.prepaintGroup(layout: &layout.content, pass: &pass)
    }

    public mutating func paintGroup(layout: inout MatchedGeometryGroupLayout<Content.GroupLayout>,
                                    prepaint: inout Content.GroupPrepaint,
                                    pass: inout PaintPass) {
        let frame = pass.frame
        guard let key = layout.key, let map = frame.animationStore.matched.beginPaint(key, frame: frame) else {
            content.paintGroup(layout: &layout.content, prepaint: &prepaint, pass: &pass)
            return
        }
        frame.paintWithDeviceMap(map) {
            content.paintGroup(layout: &layout.content, prepaint: &prepaint, pass: &pass)
        }
    }
}

/// **The typed entry is a line-for-line copy of the untyped one, pinned on its own** (`TransitionGroup`'s
/// rule): a copy of a pinned implementation is unpinned.
extension MatchedGeometryGroup: ProposalElementGroup where Content: ProposalElementGroup {
    public mutating func requestProposalGroupLayout(under parent: GlobalElementID?,
                                                    at cursor: inout Int,
                                                    pass: inout LayoutPass)
        -> ([ProposalNodeID], MatchedGeometryGroupLayout<Content.GroupLayout>) {
        let key = pass.frame.claimMatchedGeometry(spec, under: parent, at: cursor)
        let (nodes, layout) = content.requestProposalGroupLayout(under: parent, at: &cursor, pass: &pass)
        if let key { pass.frame.animationStore.matched.setNodes(nodes.map(\.layoutNodeID), for: key) }
        return (nodes, MatchedGeometryGroupLayout(key: key, content: layout))
    }
}

extension Frame {
    /// Claims `(parent, cursor)` for a matched-geometry group, reading the transaction's animation at it, and
    /// returns its store key — or `nil` when another group already holds the position.
    func claimMatchedGeometry(_ spec: MatchedGeometryStore.Spec, under parent: GlobalElementID?,
                              at cursor: Int) -> GlobalElementID? {
        let key = MatchedGeometryStore.key(under: parent, at: cursor)
        let claimed = animationStore.matched.claim(
            key: key, spec: spec, animation: conditionalAnimation,
            transitionKey: TransitionStore.key(under: parent, at: cursor))
        return claimed ? key : nil
    }
}

extension ElementGroup {
    /// Shares this group's geometry with the other views of `id` in `namespace` — SwiftUI's
    /// `matchedGeometryEffect(id:in:properties:anchor:isSource:)`.
    ///
    /// **The handoff.** When a view whose effect is a source leaves and a view with the same id and namespace
    /// appears **in the same transaction**, the newcomer is drawn at the leaver's frame and moves to its own
    /// under that transaction's animation: both position and size for `.frame` (probe S1, S3), the centre for
    /// `.position` with its own size kept (S9), the size for `.size` with its centre kept. Without a
    /// transaction the newcomer is at its own frame at once (MG1n). A leaver removed at once by an explicit
    /// `.transition(.identity)` hands nothing over (S2); a leaver that is not a source hands nothing over
    /// (S12). A view with no `.transition` is removed instantly in MetalUI (divergence 98) and still hands its
    /// frame over, as SwiftUI's default cross-fade does (S1).
    ///
    /// **Sources and followers.** Of several live views with one id and namespace the last source in tree
    /// order is the source; every other view is drawn at its frame as `properties` select (P1–P5). With no
    /// source (`isSource: false` everywhere) nothing is shared (P4).
    ///
    /// **Not SwiftUI:** the move is a paint map from the laid-out rectangle to the shown one, not a relayout at
    /// the shown size, so a `.size` change stretches the drawn content (divergence 896); hit testing keeps the
    /// laid-out frame (divergence 895); the leaver's own move toward the newcomer's frame (SwiftUI moves the
    /// outgoing view too, S12) is not drawn (divergence 897); `anchor` is MetalUI's reading of an unprobed
    /// parameter (`MG-D`).
    public func matchedGeometryEffect<ID: Hashable>(
        id: ID, in namespace: Namespace.ID, properties: MatchedGeometryProperties = .frame,
        anchor: UnitPoint = .center, isSource: Bool = true
    ) -> MatchedGeometryGroup<Self> {
        MatchedGeometryGroup(content: self, spec: MatchedGeometryStore.Spec(
            namespace: namespace, id: AnyHashable(id), properties: properties, anchor: anchor, isSource: isSource))
    }
}

// MARK: - Decorations chain through the group

extension MatchedGeometryGroup: Element where Content: Element {
    public typealias LayoutState = Content.LayoutState
    public typealias PrepaintState = Content.PrepaintState

    public mutating func requestLayout(_ id: GlobalElementID, pass: inout LayoutPass)
        -> (LayoutNodeID, Content.LayoutState) {
        content.requestLayout(id, pass: &pass)
    }

    public mutating func prepaint(_ id: GlobalElementID, bounds: Bounds<Pixels>,
                                  layout: inout Content.LayoutState, pass: inout PrepaintPass) -> Content.PrepaintState {
        content.prepaint(id, bounds: bounds, layout: &layout, pass: &pass)
    }

    public mutating func paint(_ id: GlobalElementID, bounds: Bounds<Pixels>,
                               layout: inout Content.LayoutState, prepaint: inout Content.PrepaintState,
                               pass: inout PaintPass) {
        content.paint(id, bounds: bounds, layout: &layout, prepaint: &prepaint, pass: &pass)
    }
}

extension MatchedGeometryGroup: StyledElement where Content: StyledElement {
    public var style: Style {
        get { content.style }
        set { content.style = newValue }
    }
    public var decoration: Decoration {
        get { content.decoration }
        set { content.decoration = newValue }
    }
    public var elementID: ElementID? {
        get { content.elementID }
        set { content.elementID = newValue }
    }
    public var handlers: Handlers {
        get { content.handlers }
        set { content.handlers = newValue }
    }
}

extension MatchedGeometryGroup {
    /// Names the scope **together with** its content (`ES-C`), as ``TransitionGroup/id(_:)`` does.
    public func id(_ name: String) -> IdentifiedGroup<Self> {
        IdentifiedGroup(content: self, name: ElementID(name))
    }
}
