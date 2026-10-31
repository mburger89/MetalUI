import MetalUICore
import MetalUILayout
import MetalUIPath

// `GlassEffectContainer` and the glass tags (rulings `LG-G`, `LG-H`, `LG-I`, `LG-U`; probe arms W9-W15 of
// `docs/probes/swiftui-liquid-glass.swift`). One transparent scope each, `CoordinateSpaceScope`'s shape: no layout
// node, no identity level, no `StateTable` slot. The members of a container register in PREPAINT (shape, glass,
// rect, union tag) into the open ``GlassGroup`` and emit nothing; the container emits its merged blobs at the start
// of its own paint, before its content, so a non-glass element between two members is under the blob (divergence
// 826). **A container's subtree refuses retention** by the taint `glassContainer`: the registration is a prepaint
// side effect that no ledger replays.

/// One tag a ``GlassTagScope`` pushes around its content's prepaint (`LG-H`, `LG-K`): the id and namespace of a
/// `glassEffectID` (carried, never read, no morph) or a `glassEffectUnion` (read by the container).
struct GlassTag {
    let id: AnyHashable?
    let namespace: Namespace.ID
    let isUnion: Bool
}

/// What a union joins on: the id inside its namespace.
struct GlassUnionKey: Hashable {
    let id: AnyHashable
    let namespace: Namespace.ID
}

/// One glass a container's content registered in prepaint: its shape in layout coordinates, its `Glass` and its
/// union key. A `Path` shape never registers (`LG-L`): it draws its own flat tint.
struct GlassMember {
    let bounds: Bounds<Pixels>
    let radii: Corners<Pixels>
    let isEllipse: Bool
    let glass: Glass
    let union: GlassUnionKey?
    let effectID: AnyHashable?
}

/// The registrations of one open container, in tree order. A class so the container reads what its content wrote.
final class GlassGroup {
    let spacing: Pixels?
    var members: [GlassMember] = []
    init(spacing: Pixels?) { self.spacing = spacing }

    /// The blend radius an unset spacing means: 8 points (`LG-G`, measured to lie in `(4, 12]`, probe W15).
    static let defaultSpacing: Float = 8
}

extension Frame {
    /// Registers a glass layer's shape with the innermost open container (`LG-I`); nothing when none is open, for
    /// `.identity`, or for a `Path` shape. The union tag is the innermost enclosing `glassEffectUnion`.
    func registerGlassMember(_ glass: Glass, shape: any Shape, bounds: Bounds<Pixels>) {
        guard let group = glassGroups.last, glass.variant != .identity else { return }
        let geometry = shape.geometry(in: bounds)
        guard geometry.pathAndStyle == nil else { return }
        let union = glassTags.last(where: { $0.isUnion && $0.id != nil })
            .flatMap { tag in tag.id.map { GlassUnionKey(id: $0, namespace: tag.namespace) } }
        let effectID = glassTags.last(where: { !$0.isUnion })?.id
        group.members.append(GlassMember(bounds: geometry.rect, radii: geometry.cornerRadii,
                                         isEllipse: geometry.primitiveShape == .ellipse, glass: glass,
                                         union: union, effectID: effectID))
    }

    /// The distance between two members' bounding rectangles (zero when they touch or overlap).
    private func glassGap(_ a: Bounds<Pixels>, _ b: Bounds<Pixels>) -> Float {
        let dx = max(0, max(a.origin.x.value, b.origin.x.value)
                        - min(a.origin.x.value + a.size.width.value, b.origin.x.value + b.size.width.value))
        let dy = max(0, max(a.origin.y.value, b.origin.y.value)
                        - min(a.origin.y.value + a.size.height.value, b.origin.y.value + b.size.height.value))
        return (dx * dx + dy * dy).squareRoot()
    }

    /// The blobs of a container's members, in tree order (`LG-G`, `LG-H`): members join when they share a union key,
    /// or when they hold equal glass and `2 × gap < spacing` (the smooth-min's own threshold, measured exactly); the
    /// joined sets are cut in greedy chunks of four, never merging across. Each chunk is `(member indices, blend
    /// radius in points)`; a union chunk widens the blend to reach its largest gap (`LG-H`).
    func glassBlobs(of group: GlassGroup) -> [(members: [Int], blendK: Float)] {
        let members = group.members
        let spacing = group.spacing?.value ?? GlassGroup.defaultSpacing
        var parent = Array(members.indices)
        func root(_ i: Int) -> Int {
            var r = i
            while parent[r] != r { r = parent[r] }
            return r
        }
        for i in members.indices {
            for j in members.indices where j > i {
                var joined = false
                if let a = members[i].union, let b = members[j].union, a == b {
                    joined = true
                } else if members[i].glass == members[j].glass,
                          2 * glassGap(members[i].bounds, members[j].bounds) < spacing {
                    joined = true
                }
                if joined {
                    let a = root(i), b = root(j)
                    if a != b { parent[max(a, b)] = min(a, b) }
                }
            }
        }
        var sets: [Int: [Int]] = [:]
        var order: [Int] = []
        for i in members.indices {
            let r = root(i)
            if sets[r] == nil { order.append(r) }
            sets[r, default: []].append(i)
        }
        var blobs: [(members: [Int], blendK: Float)] = []
        for r in order {
            let set = sets[r]!
            for chunk in GlassReference.chunks(ofMemberCount: set.count) {
                let indices = Array(set[chunk])
                var k = spacing
                if indices.count > 1, let key = members[indices[0]].union,
                   indices.allSatisfy({ members[$0].union == key }) {
                    var widest: Float = 0
                    for a in indices { for b in indices where b > a {
                        widest = max(widest, glassGap(members[a].bounds, members[b].bounds))
                    } }
                    k = max(spacing, 2 * widest + 2)
                }
                blobs.append((indices, k))
            }
        }
        return blobs
    }

    /// Emits the container's blobs (at the start of its paint, `LG-I`).
    func emitGlassBlobs(of group: GlassGroup) {
        for blob in glassBlobs(of: group) {
            let first = group.members[blob.members[0]]
            fillGlass(first.glass,
                      members: blob.members.map {
                          let m = group.members[$0]
                          return GlassMemberShape(rect: m.bounds, radii: m.radii, isEllipse: m.isEllipse)
                      },
                      blendK: Pixels(blob.blendK))
        }
    }
}

/// A container's prepaint product: its content's, and the group its members registered into.
public struct GlassContainerPrepaint<ContentPrepaint> {
    var content: ContentPrepaint
    let group: GlassGroup
}

/// SwiftUI's `GlassEffectContainer`: glass effects inside it that lie within `spacing` of each other merge into
/// one blob (rulings `LG-G`, `LG-H`). **Transparent**, like `CoordinateSpaceScope`: no node, no identity level, no
/// `StateTable` slot. Merging is a smooth-minimum of the shapes' signed distances with blend radius `spacing`
/// (two 60 pt circles with surface gap `g` merge exactly when `spacing > 2g`, probe W9, W10); a blob holds four
/// members, a container with more is cut in greedy chunks of four in tree order (divergence 826). The container's
/// glass is drawn **before** its content, so a non-glass sibling between two members is under the blob; an
/// `.equatable()` ancestor of a container is evaluated every frame, counted by the retention reason `glassContainer`.
public struct GlassEffectContainer<Content: ElementGroup>: ElementGroup {
    var content: Content
    let spacing: Pixels?

    /// A container of `content`. `spacing` is the blend radius in points (`LG-R`: `Pixels`, not `CGFloat`); `nil`
    /// is 8 (`LG-G`).
    public init(spacing: Pixels? = nil, @ProposalContentBuilder content: () -> Content) {
        self.content = content()
        self.spacing = spacing
    }

    /// Lays the content out with the caller's parent and cursor.
    public mutating func requestGroupLayout(under parent: GlobalElementID?, at cursor: inout Int,
                                            pass: inout LayoutPass)
        -> ([LayoutNodeID], Content.GroupLayout) {
        content.requestGroupLayout(under: parent, at: &cursor, pass: &pass)
    }

    /// Prepaints the content with a group open for its glass members; the subtree refuses retention.
    public mutating func prepaintGroup(layout: inout Content.GroupLayout, pass: inout PrepaintPass)
        -> GlassContainerPrepaint<Content.GroupPrepaint> {
        let frame = pass.frame
        frame.prepaintLog?.taint("glassContainer")
        frame.taintRetention("glassContainer")
        let group = GlassGroup(spacing: spacing)
        frame.glassGroups.append(group)
        defer { frame.glassGroups.removeLast() }
        let inner = content.prepaintGroup(layout: &layout, pass: &pass)
        return GlassContainerPrepaint(content: inner, group: group)
    }

    /// Emits the merged blobs, then paints the content with its members silent.
    public mutating func paintGroup(layout: inout Content.GroupLayout,
                                    prepaint: inout GlassContainerPrepaint<Content.GroupPrepaint>,
                                    pass: inout PaintPass) {
        let frame = pass.frame
        frame.emitGlassBlobs(of: prepaint.group)
        frame.glassContainerPaintDepth += 1
        defer { frame.glassContainerPaintDepth -= 1 }
        content.paintGroup(layout: &layout, prepaint: &prepaint.content, pass: &pass)
    }
}

extension GlassEffectContainer: ProposalElementGroup where Content: ProposalElementGroup {
    /// The typed entry: a line-for-line copy of the untyped one.
    public mutating func requestProposalGroupLayout(under parent: GlobalElementID?, at cursor: inout Int,
                                                    pass: inout LayoutPass)
        -> ([ProposalNodeID], Content.GroupLayout) {
        content.requestProposalGroupLayout(under: parent, at: &cursor, pass: &pass)
    }
}

/// What `glassEffectID(_:in:)` and `glassEffectUnion(id:namespace:)` return: `content` with a tag open around its
/// prepaint, read by the glass effects inside (`LG-H`, `LG-K`). Transparent like ``GlassEffectContainer``. Over a
/// `StyledElement` it is a `StyledElement` forwarding to its content (ruling `ES-D`).
public struct GlassTagScope<Content: ElementGroup>: ElementGroup {
    var content: Content
    let tag: GlassTag

    init(content: Content, tag: GlassTag) {
        self.content = content
        self.tag = tag
    }

    /// Lays the content out with the caller's parent and cursor.
    public mutating func requestGroupLayout(under parent: GlobalElementID?, at cursor: inout Int,
                                            pass: inout LayoutPass)
        -> ([LayoutNodeID], Content.GroupLayout) {
        content.requestGroupLayout(under: parent, at: &cursor, pass: &pass)
    }

    /// Prepaints the content with the tag open.
    public mutating func prepaintGroup(layout: inout Content.GroupLayout, pass: inout PrepaintPass)
        -> Content.GroupPrepaint {
        let frame = pass.frame
        frame.glassTags.append(tag)
        defer { frame.glassTags.removeLast() }
        return content.prepaintGroup(layout: &layout, pass: &pass)
    }

    /// Paints the content unchanged.
    public mutating func paintGroup(layout: inout Content.GroupLayout, prepaint: inout Content.GroupPrepaint,
                                    pass: inout PaintPass) {
        content.paintGroup(layout: &layout, prepaint: &prepaint, pass: &pass)
    }
}

extension GlassTagScope: ProposalElementGroup where Content: ProposalElementGroup {
    /// The typed entry: a line-for-line copy of the untyped one.
    public mutating func requestProposalGroupLayout(under parent: GlobalElementID?, at cursor: inout Int,
                                                    pass: inout LayoutPass)
        -> ([ProposalNodeID], Content.GroupLayout) {
        content.requestProposalGroupLayout(under: parent, at: &cursor, pass: &pass)
    }
}

// MARK: - Decorations chain through the tag (`ES-D`)

/// `ES-D`: the tag over an element is an element (the tag pushed around its content's prepaint), and over a
/// `StyledElement` a `StyledElement` forwarding to its content. A decoration written after the tag lands inside
/// it, which no reader can see: only the typed `glassEffect` registers with a container and reads the tag, and a
/// legacy decoration (`.glassEffect` on `StyledElement` among them) never registers (`LG-U`). The group entry
/// points above are unchanged.
extension GlassTagScope: Element where Content: Element {
    public typealias LayoutState = Content.LayoutState
    public typealias PrepaintState = Content.PrepaintState

    public mutating func requestLayout(_ id: GlobalElementID, pass: inout LayoutPass)
        -> (LayoutNodeID, Content.LayoutState) {
        content.requestLayout(id, pass: &pass)
    }

    public mutating func prepaint(_ id: GlobalElementID, bounds: Bounds<Pixels>,
                                  layout: inout Content.LayoutState, pass: inout PrepaintPass) -> Content.PrepaintState {
        let frame = pass.frame
        frame.glassTags.append(tag)
        defer { frame.glassTags.removeLast() }
        return content.prepaint(id, bounds: bounds, layout: &layout, pass: &pass)
    }

    public mutating func paint(_ id: GlobalElementID, bounds: Bounds<Pixels>,
                               layout: inout Content.LayoutState, prepaint: inout Content.PrepaintState,
                               pass: inout PaintPass) {
        content.paint(id, bounds: bounds, layout: &layout, prepaint: &prepaint, pass: &pass)
    }
}

extension GlassTagScope: StyledElement where Content: StyledElement {
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

extension GlassTagScope {
    /// Names the scope **together with** its content, not the content inside it (ruling `ES-C`, carried to
    /// this scope by `ES-D`). A `StyledElement` keeps its own `id(_:) -> Self`; forwarding that through the
    /// scope would name the content inside it. This member is the `ElementGroup` spelling, and it wins over the
    /// protocol extension's.
    public func id(_ name: String) -> IdentifiedGroup<Self> {
        IdentifiedGroup(content: self, name: ElementID(name))
    }
}
