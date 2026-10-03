import MetalUICore
import MetalUILayout

/// A native proposal-layout horizontal stack.
///
/// Its content must resolve exclusively to native layout nodes such as
/// ``Rectangle`` and ``Spacer``. The boundary is intentionally structural: a
/// legacy element does not satisfy `Content: ProposalElementGroup`, and content
/// can hand the stack only `ProposalNodeID`s, which only native registrars mint
/// (ruling MC-G). A legacy node that reaches it anyway — through a `@testable`
/// mint, MC-G's hole 3 — traps when the layout pass registers the stack, instead
/// of silently handing a CSS child to the native algorithm.
///
/// Its width is distributed as SwiftUI's `HStack` distributes it (ruling CN-B,
/// `LayoutTree.solveLinearStack`): by layout priority, lower groups' minimums
/// reserved, least flexible child first, answering the sum of its children's
/// answers; a ``Spacer`` is served last.
///
/// **Spacing** (ruling CN-H): `nil`, the default, is SwiftUI's platform
/// default — 8 between two views and none beside a ``Spacer``, decided per
/// edge through its wrappers (probe S, SP2, SP3, K3); a number is used for
/// every gap. MetalUI does not adopt SwiftUI's font-derived vertical spacing at
/// a text edge (a `VStack` of ``ProposalText``s gets 8 where SwiftUI's is 0).
public struct HStack<Content: ProposalElementGroup>: Element {
    /// The stack's children, laid out left to right.
    public var content: Content
    /// `nil` is the platform default (CN-H).
    public var spacing: Pixels?
    /// How children of different heights line up vertically (`CN-I`).
    public var alignment: VerticalAlignment

    /// SwiftUI's `HStack(alignment:spacing:content:)` (ruling CN-I).
    public init(alignment: VerticalAlignment = .center, spacing: Pixels? = nil,
                @ElementBuilder content: () -> Content) {
        self.content = content()
        self.spacing = spacing
        self.alignment = alignment
    }

    /// The spacing-first spelling over the nine-case alignment. It reads only
    /// `alignment`'s vertical factor, so `.leading` places as `.center`; its
    /// spacing is explicit, never the platform default.
    @available(*, deprecated, message: "Use init(alignment:spacing:content:) with a VerticalAlignment, in SwiftUI's argument order.")
    public init(spacing: Pixels, alignment: ProposalAlignment,
                @ElementBuilder content: () -> Content) {
        self.init(alignment: VerticalAlignment(verticalFactorOf: alignment), spacing: spacing,
                  content: content)
    }

    public struct Layout {
        var node: LayoutNodeID
        var content: Content.GroupLayout
    }

    public mutating func requestProposalLayout(_ id: GlobalElementID,
                                               pass: inout LayoutPass) -> (ProposalNodeID, Layout) {
        var cursor = 0
        let (children, contentLayout) = content.requestProposalGroupLayout(under: id, at: &cursor,
                                                                           pass: &pass)
        let node = pass.requestNativeLinearStack(children: children, axis: .horizontal,
                                                 spacing: spacing.map { Double($0.value) },
                                                 alignment: alignment.proposalAlignment,
                                                 baseline: alignment.textBaseline)
        return (node, Layout(node: node.layoutNodeID, content: contentLayout))
    }

    public mutating func prepaint(_ id: GlobalElementID, bounds: Bounds<Pixels>,
                                  layout: inout Layout,
                                  pass: inout PrepaintPass) -> Content.GroupPrepaint {
        content.prepaintGroup(layout: &layout.content, pass: &pass)
    }

    public mutating func paint(_ id: GlobalElementID, bounds: Bounds<Pixels>,
                               layout: inout Layout, prepaint: inout Content.GroupPrepaint,
                               pass: inout PaintPass) {
        content.paintGroup(layout: &layout.content, prepaint: &prepaint, pass: &pass)
    }
}

/// A native proposal-layout vertical stack, distributing its height as
/// ``HStack`` distributes its width (ruling CN-B), with the same spacing rule
/// (CN-H).
public struct VStack<Content: ProposalElementGroup>: Element {
    /// The stack's children, laid out top to bottom.
    public var content: Content
    /// `nil` is the platform default (CN-H).
    public var spacing: Pixels?
    /// How children of different widths line up horizontally (`CN-I`).
    public var alignment: HorizontalAlignment

    /// SwiftUI's `VStack(alignment:spacing:content:)` (ruling CN-I).
    public init(alignment: HorizontalAlignment = .center, spacing: Pixels? = nil,
                @ElementBuilder content: () -> Content) {
        self.content = content()
        self.spacing = spacing
        self.alignment = alignment
    }

    /// The spacing-first spelling over the nine-case alignment. It reads only
    /// `alignment`'s horizontal factor, so `.top` places as `.center`; its
    /// spacing is explicit, never the platform default.
    @available(*, deprecated, message: "Use init(alignment:spacing:content:) with a HorizontalAlignment, in SwiftUI's argument order.")
    public init(spacing: Pixels, alignment: ProposalAlignment,
                @ElementBuilder content: () -> Content) {
        self.init(alignment: HorizontalAlignment(horizontalFactorOf: alignment), spacing: spacing,
                  content: content)
    }

    public struct Layout {
        var node: LayoutNodeID
        var content: Content.GroupLayout
    }

    public mutating func requestProposalLayout(_ id: GlobalElementID,
                                               pass: inout LayoutPass) -> (ProposalNodeID, Layout) {
        var cursor = 0
        let (children, contentLayout) = content.requestProposalGroupLayout(under: id, at: &cursor,
                                                                           pass: &pass)
        let node = pass.requestNativeLinearStack(children: children, axis: .vertical,
                                                 spacing: spacing.map { Double($0.value) },
                                                 alignment: alignment.proposalAlignment)
        return (node, Layout(node: node.layoutNodeID, content: contentLayout))
    }

    public mutating func prepaint(_ id: GlobalElementID, bounds: Bounds<Pixels>,
                                  layout: inout Layout,
                                  pass: inout PrepaintPass) -> Content.GroupPrepaint {
        content.prepaintGroup(layout: &layout.content, pass: &pass)
    }

    public mutating func paint(_ id: GlobalElementID, bounds: Bounds<Pixels>,
                               layout: inout Layout, prepaint: inout Content.GroupPrepaint,
                               pass: inout PaintPass) {
        content.paintGroup(layout: &layout.content, prepaint: &prepaint, pass: &pass)
    }
}

/// A native proposal-layout overlay, analogous to SwiftUI's `ZStack`.
///
/// Measures every child at its proposal and answers the union (probe A4).
/// Places every child at a proposal equal to its own placed size and aligns
/// each answer within the union of those answers, at its own origin (ruling
/// CN-E; probe Z1–Z4, A3, A5). As a window root it is centred at its answer
/// (ruling CN-J).
public struct ZStack<Content: ProposalElementGroup>: Element {
    /// The children, layered first-at-the-back.
    public var content: Content
    /// Where each child sits within the union of their sizes (`CN-E`).
    public var alignment: ProposalAlignment

    /// An overlaying stack, SwiftUI's `ZStack(alignment:content:)`.
    public init(alignment: ProposalAlignment = .center,
                @ElementBuilder content: () -> Content) {
        self.content = content()
        self.alignment = alignment
    }

    public struct Layout {
        var node: LayoutNodeID
        var content: Content.GroupLayout
    }

    public mutating func requestProposalLayout(_ id: GlobalElementID,
                                               pass: inout LayoutPass) -> (ProposalNodeID, Layout) {
        var cursor = 0
        let (children, contentLayout) = content.requestProposalGroupLayout(under: id, at: &cursor,
                                                                           pass: &pass)
        let node = pass.requestNativeOverlay(children: children, alignment: alignment)
        return (node, Layout(node: node.layoutNodeID, content: contentLayout))
    }

    public mutating func prepaint(_ id: GlobalElementID, bounds: Bounds<Pixels>,
                                  layout: inout Layout,
                                  pass: inout PrepaintPass) -> Content.GroupPrepaint {
        content.prepaintGroup(layout: &layout.content, pass: &pass)
    }

    public mutating func paint(_ id: GlobalElementID, bounds: Bounds<Pixels>,
                               layout: inout Layout, prepaint: inout Content.GroupPrepaint,
                               pass: inout PaintPass) {
        content.paintGroup(layout: &layout.content, prepaint: &prepaint, pass: &pass)
    }
}

/// Temporary source-compatible name for ``HStack``.
@available(*, deprecated, renamed: "HStack")
public typealias NativeRow<Content: ProposalElementGroup> = HStack<Content>

/// Temporary source-compatible name for ``VStack``.
@available(*, deprecated, renamed: "VStack")
public typealias NativeColumn<Content: ProposalElementGroup> = VStack<Content>

/// Temporary source-compatible name for ``ZStack``.
@available(*, deprecated, renamed: "ZStack")
public typealias NativeOverlay<Content: ProposalElementGroup> = ZStack<Content>

/// A proposal-layout frame whose content contributes exactly one native node.
///
/// Prefer the `.frame(...)` modifier on a `ProposalElementGroup` when possible;
/// this builder exists for the few declarations that need a stored wrapper.
///
/// **Two initializers, SwiftUI's two `frame` overloads**, so a fixed and a
/// flexible dimension cannot be passed together (ruling SA-K item 6). The
/// stored properties stay one set; the kernel validates them when the frame
/// registers (ruling SA-J).
public struct ProposalFrame<Content: ProposalElementGroup>: Element {
    /// The framed child.
    public var content: Content
    /// A fixed width; `nil` leaves the axis to the child or the flexible
    /// bounds.
    public var width: Pixels?
    /// A fixed height; `nil` leaves the axis to the child or the flexible
    /// bounds.
    public var height: Pixels?
    /// The least width the frame answers. With `nil` there is no declared floor:
    /// the frame answers at least 0, and under a maximum at least its child
    /// (FR-M).
    public var minWidth: Pixels?
    /// The width the frame answers when offered none.
    public var idealWidth: Pixels?
    /// The greatest width the frame answers; `.infinity` fills (`FR-A`).
    public var maxWidth: Pixels?
    /// The least height the frame answers. With `nil` there is no declared floor:
    /// the frame answers at least 0, and under a maximum at least its child
    /// (FR-M).
    public var minHeight: Pixels?
    /// The height the frame answers when offered none.
    public var idealHeight: Pixels?
    /// The greatest height the frame answers; `.infinity` fills (`FR-A`).
    public var maxHeight: Pixels?
    /// Where the child sits within the frame.
    public var alignment: ProposalAlignment

    /// A fixed frame: SwiftUI's `frame(width:height:alignment:)`.
    public init(width: Pixels? = nil, height: Pixels? = nil,
                alignment: ProposalAlignment = .center,
                @ElementBuilder content: () -> Content) {
        self.content = content()
        self.width = width
        self.height = height
        self.alignment = alignment
    }

    /// A flexible frame: SwiftUI's
    /// `frame(minWidth:idealWidth:maxWidth:minHeight:idealHeight:maxHeight:alignment:)`.
    public init(minWidth: Pixels? = nil, idealWidth: Pixels? = nil, maxWidth: Pixels? = nil,
                minHeight: Pixels? = nil, idealHeight: Pixels? = nil, maxHeight: Pixels? = nil,
                alignment: ProposalAlignment = .center,
                @ElementBuilder content: () -> Content) {
        self.content = content()
        self.minWidth = minWidth
        self.idealWidth = idealWidth
        self.maxWidth = maxWidth
        self.minHeight = minHeight
        self.idealHeight = idealHeight
        self.maxHeight = maxHeight
        self.alignment = alignment
    }

    public struct Layout {
        var node: LayoutNodeID
        var content: Content.GroupLayout
    }

    public mutating func requestProposalLayout(_ id: GlobalElementID,
                                               pass: inout LayoutPass) -> (ProposalNodeID, Layout) {
        var cursor = 0
        let (children, contentLayout) = content.requestProposalGroupLayout(under: id, at: &cursor,
                                                                           pass: &pass)
        precondition(children.count == 1, "ProposalFrame content must contribute one native node")
        let node = pass.requestNativeFrame(
            child: children[0], width: width.map { Double($0.value) },
            height: height.map { Double($0.value) }, minWidth: minWidth.map { Double($0.value) },
            idealWidth: idealWidth.map { Double($0.value) }, maxWidth: maxWidth.map { Double($0.value) },
            minHeight: minHeight.map { Double($0.value) }, idealHeight: idealHeight.map { Double($0.value) },
            maxHeight: maxHeight.map { Double($0.value) }, alignment: alignment
        )
        return (node, Layout(node: node.layoutNodeID, content: contentLayout))
    }

    public mutating func prepaint(_ id: GlobalElementID, bounds: Bounds<Pixels>,
                                  layout: inout Layout,
                                  pass: inout PrepaintPass) -> Content.GroupPrepaint {
        content.prepaintGroup(layout: &layout.content, pass: &pass)
    }

    public mutating func paint(_ id: GlobalElementID, bounds: Bounds<Pixels>,
                               layout: inout Layout, prepaint: inout Content.GroupPrepaint,
                               pass: inout PaintPass) {
        content.paintGroup(layout: &layout.content, prepaint: &prepaint, pass: &pass)
    }
}

/// Temporary source-compatible name for ``ProposalFrame``.
@available(*, deprecated, renamed: "ProposalFrame")
public typealias NativeFrame<Content: ProposalElementGroup> = ProposalFrame<Content>

/// Native outer padding around one native child.
public struct Padding<Content: ProposalElementGroup>: Element {
    /// The padded child.
    public var content: Content
    /// The inset on each edge.
    public var insets: Edges<Pixels>

    /// Pads `content` by `insets`; the child is placed at its own size
    /// (`LR-AU`).
    public init(_ insets: Edges<Pixels>, @ElementBuilder content: () -> Content) {
        self.content = content()
        self.insets = insets
    }

    public struct Layout {
        var node: LayoutNodeID
        var content: Content.GroupLayout
    }

    public mutating func requestProposalLayout(_ id: GlobalElementID,
                                               pass: inout LayoutPass) -> (ProposalNodeID, Layout) {
        var cursor = 0
        let (children, contentLayout) = content.requestProposalGroupLayout(under: id, at: &cursor,
                                                                           pass: &pass)
        precondition(children.count == 1, "Padding content must contribute one native node")
        let insets = Edges<Double>(top: Double(insets.top.value), right: Double(insets.right.value),
                                   bottom: Double(insets.bottom.value), left: Double(insets.left.value))
        let node = pass.requestNativePadding(child: children[0], insets: insets)
        return (node, Layout(node: node.layoutNodeID, content: contentLayout))
    }

    public mutating func prepaint(_ id: GlobalElementID, bounds: Bounds<Pixels>,
                                  layout: inout Layout,
                                  pass: inout PrepaintPass) -> Content.GroupPrepaint {
        content.prepaintGroup(layout: &layout.content, pass: &pass)
    }

    public mutating func paint(_ id: GlobalElementID, bounds: Bounds<Pixels>,
                               layout: inout Layout, prepaint: inout Content.GroupPrepaint,
                               pass: inout PaintPass) {
        content.paintGroup(layout: &layout.content, prepaint: &prepaint, pass: &pass)
    }
}

/// A builder-style background that paints beneath its content without
/// affecting that content's proposal, measurement, or placement.
public struct Background<Content: ProposalElementGroup>: Element {
    /// The content painted over the background.
    public var content: Content
    /// The fill painted beneath the content's bounds (a `Color` since
    /// `CR-E` item 3).
    public var color: Color

    /// Paints `color` beneath `content`, leaving its layout alone.
    public init(_ color: Color, @ElementBuilder content: () -> Content) {
        self.content = content()
        self.color = color
    }

    /// Paints `token` beneath `content` — the `ColorToken` spelling, kept
    /// (`CR-E` item 1).
    @_disfavoredOverload
    public init(_ color: ColorToken, @ElementBuilder content: () -> Content) {
        self.init(Color(color), content: content)
    }

    public struct Layout { var content: Content.GroupLayout }

    public mutating func requestProposalLayout(_ id: GlobalElementID,
                                               pass: inout LayoutPass) -> (ProposalNodeID, Layout) {
        var cursor = 0
        let (children, contentLayout) = content.requestProposalGroupLayout(under: id, at: &cursor,
                                                                           pass: &pass)
        precondition(children.count == 1, "Background content must contribute one native node")
        return (children[0], Layout(content: contentLayout))
    }

    public mutating func prepaint(_ id: GlobalElementID, bounds: Bounds<Pixels>,
                                  layout: inout Layout,
                                  pass: inout PrepaintPass) -> Content.GroupPrepaint {
        content.prepaintGroup(layout: &layout.content, pass: &pass)
    }

    public mutating func paint(_ id: GlobalElementID, bounds: Bounds<Pixels>,
                               layout: inout Layout, prepaint: inout Content.GroupPrepaint,
                               pass: inout PaintPass) {
        pass.fill(bounds, color: pass.resolve(color), cornerRadii: Corners(all: Pixels(0)))
        content.paintGroup(layout: &layout.content, prepaint: &prepaint, pass: &pass)
    }
}

/// Temporary source-compatible name for ``Background``.
@available(*, deprecated, renamed: "Background")
public typealias NativeBackground<Content: ProposalElementGroup> = Background<Content>

/// A native proposal-layout wrapper that preserves its content's intrinsic
/// measurement on the selected axes.
///
/// This is the builder-style counterpart to ``ElementGroup/nativeFixedSize(horizontal:vertical:)``.
/// It withholds the selected axis from its child proposal; it does not mutate
/// the child's size after measurement.
public struct FixedSize<Content: ProposalElementGroup>: Element {
    /// The child whose proposal is withheld.
    public var content: Content
    /// Whether the child is measured at its ideal width.
    public var horizontal: Bool
    /// Whether the child is measured at its ideal height.
    public var vertical: Bool

    /// Withholds the selected axes from `content`'s proposal, SwiftUI's
    /// `.fixedSize(horizontal:vertical:)`.
    public init(horizontal: Bool = true, vertical: Bool = true,
                @ElementBuilder content: () -> Content) {
        self.content = content()
        self.horizontal = horizontal
        self.vertical = vertical
    }

    public struct Layout {
        var node: LayoutNodeID
        var content: Content.GroupLayout
    }

    public mutating func requestProposalLayout(_ id: GlobalElementID,
                                               pass: inout LayoutPass) -> (ProposalNodeID, Layout) {
        var cursor = 0
        let (children, contentLayout) = content.requestProposalGroupLayout(under: id, at: &cursor,
                                                                           pass: &pass)
        precondition(children.count == 1, "FixedSize content must contribute one native node")
        let node = pass.requestNativeFixedSize(child: children[0], horizontal: horizontal,
                                               vertical: vertical)
        return (node, Layout(node: node.layoutNodeID, content: contentLayout))
    }

    public mutating func prepaint(_ id: GlobalElementID, bounds: Bounds<Pixels>,
                                  layout: inout Layout,
                                  pass: inout PrepaintPass) -> Content.GroupPrepaint {
        content.prepaintGroup(layout: &layout.content, pass: &pass)
    }

    public mutating func paint(_ id: GlobalElementID, bounds: Bounds<Pixels>,
                               layout: inout Layout, prepaint: inout Content.GroupPrepaint,
                               pass: inout PaintPass) {
        content.paintGroup(layout: &layout.content, prepaint: &prepaint, pass: &pass)
    }
}

/// Temporary source-compatible name for ``Padding``.
@available(*, deprecated, renamed: "Padding")
public typealias NativePadding<Content: ProposalElementGroup> = Padding<Content>

/// Temporary source-compatible name for ``FixedSize``.
@available(*, deprecated, renamed: "FixedSize")
public typealias NativeFixedSize<Content: ProposalElementGroup> = FixedSize<Content>

/// A flexible proposal-layout spacer for use inside ``HStack`` or ``VStack``.
///
/// A nil `minLength` is 8, SwiftUI's platform default
/// (`ProposalSpacing.platformDefault`; ruling CN-C). Inside a stack it takes
/// what the other children leave (priority −∞) and answers 0 on the stack's
/// cross axis, through `.padding`, `.frame`, `.fixedSize`, `.aspectRatio`,
/// `.layoutPriority` and either side of `.overlay`; outside a stack, or inside
/// a ``ZStack``, it is flexible on both axes. A stack with no `spacing:` puts
/// no spacing beside it, through the same wrappers except a non-zero padding
/// edge and an overlay's content side (ruling CN-H).
public struct Spacer: Element {
    /// The least length on the stack's axis; `nil` is the default, 8 (`CN-B`).
    public var minLength: Pixels?

    /// A flexible space, SwiftUI's `Spacer(minLength:)`.
    public init(minLength: Pixels? = nil) {
        self.minLength = minLength
    }

    public struct Layout { var node: LayoutNodeID }

    public mutating func requestProposalLayout(_ id: GlobalElementID,
                                               pass: inout LayoutPass) -> (ProposalNodeID, Layout) {
        let node = pass.requestNativeSpacer(minLength: minLength.map { Double($0.value) })
        return (node, Layout(node: node.layoutNodeID))
    }

    public mutating func prepaint(_ id: GlobalElementID, bounds: Bounds<Pixels>,
                                  layout: inout Layout, pass: inout PrepaintPass) {}

    public mutating func paint(_ id: GlobalElementID, bounds: Bounds<Pixels>,
                               layout: inout Layout, prepaint: inout Void, pass: inout PaintPass) {}
}

/// SwiftUI's `Rectangle`, a ``Shape`` since plan task 11 part 2 (`TE-AH`).
///
/// Its no-argument form follows SwiftUI's `Rectangle`: it responds with the
/// concrete dimensions a parent proposes and uses a 10pt ideal on an
/// unspecified axis (probe S1), and it fills with the foreground style
/// (`foregroundStyle ?? .textPrimary`, probes F1, F2). `init(width:height:color:)`
/// remains the explicit fixed leaf convenience used by the existing migration
/// preview and tests, and keeps its `.surface` default.
///
/// **`color` is `Color?` since the colour work (`CR-E` item 3), `ColorToken?`
/// since plan task 11 part 2** (`TE-AQ` item 2, a
/// ruled public break): `nil` is the foreground style, which a bare
/// `Rectangle()` stores. **Migration**: a reader writes `rect.color ?? token`;
/// a writer is unchanged. A ``ShapeView``'s layers never read it.
public struct Rectangle: Shape, Hashable {
    /// The width answered when the rectangle does not respond to the proposal.
    public var width: Pixels
    /// The height answered when the rectangle does not respond to the proposal.
    public var height: Pixels
    /// The fill, or `nil` for the foreground style (`TE-AH`); a `Color`
    /// since `CR-E` item 3.
    public var color: Color?
    private var respondsToProposal: Bool

    public typealias Layout = ShapeLayout

    /// A fixed-size rectangle filled with `color`.
    public init(width: Pixels, height: Pixels, color: Color = .surface) {
        self.width = width
        self.height = height
        self.color = color
        respondsToProposal = false
    }

    /// A fixed-size rectangle filled with `token` — the `ColorToken` spelling,
    /// kept (`CR-E` item 1).
    @_disfavoredOverload
    public init(width: Pixels, height: Pixels, color: ColorToken = .surface) {
        self.init(width: width, height: height, color: Color(color))
    }

    /// A rectangle that answers its proposal and fills with the foreground
    /// style.
    public init() {
        width = Pixels(10)
        height = Pixels(10)
        color = nil
        respondsToProposal = true
    }

    /// A proposal-responsive rectangle filled with `color`.
    @available(*, deprecated, message: "use Rectangle().fill(_:)")
    public init(color: ColorToken) {
        width = Pixels(10)
        height = Pixels(10)
        self.color = Color(color)
        respondsToProposal = true
    }

    public func geometry(in rect: Bounds<Pixels>) -> ShapeGeometry {
        .roundedRectangle(rect, cornerRadii: Corners(all: Pixels(0)))
    }

    public nonisolated func sizeThatFits(_ proposal: ProposedSize) -> SizeD {
        Self.measurement(for: proposal, width: Double(width.value), height: Double(height.value),
                         respondsToProposal: respondsToProposal).size
    }

    public mutating func requestProposalLayout(_ id: GlobalElementID,
                                               pass: inout LayoutPass) -> (ProposalNodeID, ShapeLayout) {
        let width = Double(width.value)
        let height = Double(height.value)
        let respondsToProposal = respondsToProposal
        let node = pass.requestNativeLeaf { proposal in
            Self.measurement(for: proposal, width: width, height: height,
                             respondsToProposal: respondsToProposal)
        }
        return (node, ShapeLayout(node: node.layoutNodeID))
    }

    nonisolated static func measurement(for proposal: ProposedSize, width: Double = 10,
                                        height: Double = 10,
                                        respondsToProposal: Bool = true) -> LayoutMeasurement {
        guard respondsToProposal else {
            return LayoutMeasurement(size: SizeD(width: width, height: height))
        }
        return LayoutMeasurement(size: SizeD(width: proposal.width ?? width,
                                              height: proposal.height ?? height))
    }

    public mutating func prepaint(_ id: GlobalElementID, bounds: Bounds<Pixels>,
                                  layout: inout ShapeLayout, pass: inout PrepaintPass) {}

    public mutating func paint(_ id: GlobalElementID, bounds: Bounds<Pixels>,
                               layout: inout ShapeLayout, prepaint: inout Void, pass: inout PaintPass) {
        paintShapeFill(geometry(in: bounds), color: color, pass: pass)
    }
}

/// `Color` as a view: a colour field that accepts every concrete proposal it
/// receives (ruling `CR-D` — the conformance is this extension, so the value
/// and its statics stay usable off the main actor).
///
/// This is the native equivalent of a SwiftUI `Color` used as a background:
/// an overlay can offer it the window's current size and it responds with that
/// size, rather than retaining an initial fixed canvas. Like SwiftUI `Color`,
/// an unspecified axis uses a 10pt ideal so it remains a useful stack child.
@MainActor
extension Color: Element {
    /// The layout a `Color` view keeps: its leaf node.
    public struct Layout { var node: LayoutNodeID }

    public mutating func requestProposalLayout(_ id: GlobalElementID,
                                               pass: inout LayoutPass) -> (ProposalNodeID, Layout) {
        let node = pass.requestNativeLeaf { Self.measurement(for: $0) }
        return (node, Layout(node: node.layoutNodeID))
    }

    nonisolated static func measurement(for proposal: ProposedSize) -> LayoutMeasurement {
        LayoutMeasurement(size: SizeD(width: proposal.width ?? 10,
                                      height: proposal.height ?? 10))
    }

    public mutating func prepaint(_ id: GlobalElementID, bounds: Bounds<Pixels>,
                                  layout: inout Layout, pass: inout PrepaintPass) {}

    public mutating func paint(_ id: GlobalElementID, bounds: Bounds<Pixels>,
                               layout: inout Layout, prepaint: inout Void, pass: inout PaintPass) {
        pass.fill(bounds, color: pass.resolve(self), cornerRadii: Corners(all: Pixels(0)))
    }
}

/// Temporary source-compatible name for ``Spacer``.
@available(*, deprecated, renamed: "Spacer")
public typealias NativeSpacer = Spacer

/// Temporary source-compatible name for ``Rectangle``.
@available(*, deprecated, renamed: "Rectangle")
public typealias NativeRectangle = Rectangle

/// Temporary source-compatible name for ``Color``.
@available(*, deprecated, renamed: "Color")
public typealias NativeColorFill = Color
