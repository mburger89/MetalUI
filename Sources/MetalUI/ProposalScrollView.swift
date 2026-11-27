import MetalUICore
import MetalUILayout

/// A SwiftUI-style scrolling viewport for proposal-layout content.
///
/// `ProposalScrollView` keeps the existing ``ScrollView`` source-compatible
/// while providing a fully native migration path: its content must be a
/// ``ProposalElementGroup``, and its viewport/content relationship is solved
/// by `LayoutTree`'s proposal engine rather than the CSS flex engine.
public struct ProposalScrollView<Content: ProposalElementGroup>: Element {
    /// The axes the content scrolls along, SwiftUI's `axes` (`XS-A`).
    public var axes: Axis.Set
    /// The axis the content scrolls along: `.horizontal` for a horizontal-only scroller, `.vertical` otherwise (a two-axis
    /// scroller's primary axis is vertical, `XS-C`).
    public var axis: ScrollAxis {
        get { axes == .horizontal ? .horizontal : .vertical }
        set { axes = newValue == .horizontal ? .horizontal : .vertical }
    }
    public var elementID: ElementID?
    /// The scrolled content.
    public var content: Content
    /// The viewport's corner radius, clipping the content.
    public var cornerRadius: Pixels = Pixels(0)
    /// Whether the scroll indicator is drawn (`DD-H`).
    public var indicatorVisibility: ScrollIndicatorVisibility = .automatic
    /// The `scrollPosition(id:anchor:)` binding, if any (`SP-A`).
    var position: ScrollPositionBinding?
    /// The `defaultScrollAnchor` declarations, if any (`DSA-A`).
    var defaultAnchors = DefaultScrollAnchors()
    /// The padding written directly on this scroller (`SP-M`): `nil` when none, so the scroller lays out exactly as it
    /// always did. Folded into the scroller's own layout as one padding node around its viewport, never a wrapper element.
    var inset: Edges<Pixels>?
    /// The identifier written directly on this scroller (`SP-N`): `nil` when none. It names the scroller's own
    /// accessibility node, a group that contains its content and leaves each child's identifier alone.
    var accessibilityID: String?

    /// A scroller over proposal `content` along `axis`; `elementID` names it
    /// for its scroll state.
    public init(_ axis: ScrollAxis = .vertical, elementID: ElementID? = nil,
                @ProposalContentBuilder content: () -> Content) {
        self.axes = axis == .horizontal ? .horizontal : .vertical
        self.elementID = elementID
        self.content = content()
    }

    /// A scroller over proposal `content` along `axes` (`XS-A`): `[.horizontal, .vertical]` scrolls both ways.
    /// `@_disfavoredOverload`, so `ProposalScrollView(.horizontal)` keeps meaning ``ScrollAxis``.
    @_disfavoredOverload
    public init(_ axes: Axis.Set, elementID: ElementID? = nil, @ProposalContentBuilder content: () -> Content) {
        self.axes = axes
        self.elementID = elementID
        self.content = content()
    }

    /// Rounds the clips applied to both scrolling content and its indicator.
    public func cornerRadius(_ points: Pixels) -> Self {
        var copy = self
        copy.cornerRadius = points
        return copy
    }

    /// Sets whether the fading overlay scroll indicator is painted.
    public func scrollIndicators(_ visibility: ScrollIndicatorVisibility) -> Self {
        var copy = self
        copy.indicatorVisibility = visibility
        return copy
    }

    public struct Layout {
        /// The node this element registers: the viewport, or the padding node around it (`SP-M`).
        var node: LayoutNodeID
        /// The viewport itself; `node` when the scroller has no padding.
        var viewportNode: LayoutNodeID
        var contentNode: LayoutNodeID
        var content: Content.GroupLayout
    }

    public mutating func requestProposalLayout(_ id: GlobalElementID,
                                               pass: inout LayoutPass) -> (ProposalNodeID, Layout) {
        // Ruling `PE-V` (`docs/superpowers/2026-10-06-proposal-controls-decisions.md`):
        // the scroller publishes its `ScrollContext` to its subtree exactly as
        // `ScrollView.requestLayout` does — the raw stored offset and last
        // frame's viewport, from the one `ScrollState` both scrollers' chrome
        // writes — so a `List` inside it windows (`DD-F`). Until `PE-B` no
        // `List` could be its content, and publishing was declared-but-inert
        // (`LR-BF`); a sibling after the scroller still sees none (the
        // `withScrollContext` scope).
        var rawOffset: Double = 0
        var lastViewportExtent: Double = 0
        // A read, not a write (`RW-H`): the version moves only when an input or the prepaint clamp changes the entry.
        let scrollState = pass.readState(id, initial: ScrollState())
        rawOffset = ScrollChrome.layoutOffset(scrollState, now: pass.frame.timestamp, scale: pass.frame.scaleFactor)   // `SP-F`, `DSA-J`
        lastViewportExtent = scrollState.viewportExtent
        var cursor = 0
        position?.beginLayout(id, pass: &pass)   // `SP-A`
        defer { position?.endLayout(pass: &pass) }
        var context = ScrollContext(offset: rawOffset, viewportExtent: lastViewportExtent, axis: axis)
        context.followsEnd = chrome.layoutFollowsEnd(scrollState, raw: rawOffset)   // `DSA-C`
        if chrome.crossAxis { context.cross = chrome.crossContext(scrollState, now: pass.frame.timestamp, scale: pass.frame.scaleFactor) }   // `XS-H`
        let (children, contentLayout) = pass.withScrollContext(context) {
            content.requestProposalGroupLayout(under: id, at: &cursor, pass: &pass)
        }
        // SwiftUI's `ScrollView` lays several direct children out as a
        // centred, default-spacing `VStack` whatever its scrolling axis (probe
        // SC3: b at (10, 38) under a 50×30 a on `.vertical`, `.horizontal` and
        // both). Horizontal content is an explicit `HStack`, which remains a
        // single transparent child here. Default spacing is the platform
        // default per pair — 8 between views, none at a spacer's edge (ruling
        // CN-H, SC5) — rather than an explicit 8. The viewport answers this
        // content's size on its non-scrolling axis (ruling CN-M).
        let contentAxis: ProposalStackAxis = axis == .vertical ? .vertical : .horizontal
        var contentNode: ProposalNodeID
        if children.count == 1 {
            contentNode = children[0]
        } else {
            contentNode = pass.requestNativeLinearStack(children: children, axis: .vertical,
                                                         spacing: nil)
        }
        contentNode = ProposalNodeID(pass.frame.paddedForContentMargins(contentNode.layoutNodeID))   // `CMG-A`
        let node = axes.isOneAxis
            ? pass.requestNativeScrollViewport(child: contentNode, axis: contentAxis)
            : pass.requestNativeScrollViewport(child: contentNode, horizontal: axes.contains(.horizontal),
                                               vertical: axes.contains(.vertical))   // `XS-B`
        guard let inset else {
            return (node, Layout(node: node.layoutNodeID, viewportNode: node.layoutNodeID,
                                 contentNode: contentNode.layoutNodeID, content: contentLayout))
        }
        let padded = pass.requestNativePadding(child: node, insets: Edges(
            top: Double(inset.top.value), right: Double(inset.right.value),
            bottom: Double(inset.bottom.value), left: Double(inset.left.value)))   // `SP-M`
        return (padded, Layout(node: padded.layoutNodeID, viewportNode: node.layoutNodeID,
                               contentNode: contentNode.layoutNodeID, content: contentLayout))
    }

    /// The clamp, the offset resolution and the fading overlay indicator, all
    /// of which this element shares with ``ScrollView`` (ruling `LR-BD`).
    /// **Computed, not stored** — see `ScrollChrome`'s own doc for why, and for
    /// what the fold deliberately left alone. Until stage 3 these seven members
    /// lived here as private copies, untested and already drifting.
    var chrome: ScrollChrome {
        ScrollChrome(axis: axis, cornerRadius: cornerRadius, indicatorVisibility: indicatorVisibility,
                     anchors: defaultAnchors, crossAxis: axes == [.horizontal, .vertical])
    }

    public mutating func prepaint(_ id: GlobalElementID, bounds: Bounds<Pixels>,
                                  layout: inout Layout,
                                  pass: inout PrepaintPass) -> Content.GroupPrepaint {
        let bounds = layout.node == layout.viewportNode ? bounds : pass.bounds(of: layout.viewportNode)   // `SP-M`
        var chrome = self.chrome
        chrome.resolveLayoutDirection(rightToLeft: pass.frame.environmentTop.layoutDirection == .rightToLeft)   // `LD-E`
        chrome.resolveMargins(pass.frame.environmentTop.contentMargins)   // `CMG-A`
        let (offset, crossOffset) = chrome.resolvedOffsets(id, bounds: bounds, contentNode: layout.contentNode,
                                                           pass: pass)
        if !axes.isEmpty {   // `ScrollView([])` scrolls nothing and registers nothing (probe `L3`)
            pass.registerScrollRegion(bounds, id: id, axis: axis, chrome: chrome, offset: offset, cross: crossOffset,
                                      contentSize: pass.bounds(of: layout.contentNode).size)
        }
        if let accessibilityID {   // `SP-N`: the scroller's own node, a group that contains its content
            var handlers = Handlers()
            handlers.axNode.declarations.identifier = accessibilityID
            handlers.axNode.declarations.childBehavior = .contain
            pass.registerHandlers(handlers, at: bounds, id: id, accessibleText: nil, synthesizesAccessibility: true)
        }
        // `DD-F` item 2: the content prepaints inside this scroller's frame.
        let scroller = ScrollerFrame(scrollerID: id, axis: axis,
                                     contentOrigin: pass.bounds(of: layout.contentNode).origin,
                                     viewport: bounds, offset: offset,
                                     contentExtent: chrome.extent(pass.bounds(of: layout.contentNode).size),
                                     tracksPosition: position != nil, mirrored: chrome.mirrored,
                                     cross: chrome.crossAxis ? chrome.crossFrame(offset: crossOffset, bounds: bounds, contentSize: pass.bounds(of: layout.contentNode).size) : nil,
                                     inset: chrome.contentInset)
        var result: Content.GroupPrepaint?
        let noteMark = pass.frame.scrollTargetNoteCount
        pass.clipped(to: bounds, offsetBy: chrome.translation(offset: offset, cross: crossOffset),
                     cornerRadii: Corners(all: cornerRadius)) {
            pass.inScroller(scroller) {
                result = content.prepaintGroup(layout: &layout.content, pass: &pass)
            }
        }
        position?.finishPrepaint(id, scroller: scroller, since: noteMark, pass: pass)   // `SP-C`
        return scopeResult(result)
    }

    public mutating func paint(_ id: GlobalElementID, bounds: Bounds<Pixels>,
                               layout: inout Layout, prepaint: inout Content.GroupPrepaint,
                               pass: inout PaintPass) {
        let bounds = layout.node == layout.viewportNode ? bounds : pass.bounds(of: layout.viewportNode)   // `SP-M`
        var chrome = self.chrome
        chrome.resolveLayoutDirection(rightToLeft: pass.frame.environmentTop.layoutDirection == .rightToLeft)   // `LD-E`
        chrome.resolveMargins(pass.frame.environmentTop.contentMargins)   // `CMG-C`
        let (offset, crossOffset) = chrome.resolvedOffsets(id, bounds: bounds, contentNode: layout.contentNode,
                                                           pass: pass)
        pass.clipped(to: bounds, offsetBy: chrome.translation(offset: offset, cross: crossOffset),
                     cornerRadii: Corners(all: cornerRadius)) {
            content.paintGroup(layout: &layout.content, prepaint: &prepaint, pass: &pass)
        }
        // Outside the block above and emitted after it, for the reason
        // `ScrollView.paint` spells out: inside it the thumb would inherit the
        // `-offset` translation and scroll away with the content.
        // `ScrollChrome.paintIndicator` pushes its own clip at the same bounds
        // and radii with a ZERO offset.
        chrome.paintIndicator(id, bounds: bounds, offset: offset, cross: crossOffset,
                              contentNode: layout.contentNode, pass: &pass)
    }
}

extension ProposalScrollView: ProposalElement {}

// MARK: - Layout and accessibility modifiers folded into the scroller (`SP-M`, `SP-N`)

extension ProposalScrollView {
    /// The same padding on every edge, SwiftUI's `padding(_:)`: the scroller's viewport is inset inside its parent by
    /// `length` (`SP-M`). **Folded into the scroller's own layout**: it adds one native padding node around the
    /// viewport and no element, so it costs no element request over the unpadded scroller, where the generic
    /// ``ProposalElementGroup`` padding wraps it in a `ModifiedContent` element. Written again, it adds to what is there.
    public func padding(_ length: Pixels) -> Self {
        padding(Edges(all: length))
    }

    /// Padding on the edges in `edges` only, SwiftUI's `padding(_:_:)` (divergence 208), folded as
    /// ``padding(_:)-(Pixels)`` is.
    public func padding(_ edges: Edge.Set, _ length: Pixels) -> Self {
        padding(edges.insets(length))
    }

    /// Padding of `insets`, SwiftUI's `padding(_: EdgeInsets)`, folded as ``padding(_:)-(Pixels)`` is.
    public func padding(_ insets: EdgeInsets) -> Self {
        padding(insets.edges)
    }

    /// Per-edge padding in points, folded as ``padding(_:)-(Pixels)`` is.
    public func padding(_ insets: Edges<Pixels>) -> Self {
        var copy = self
        let held = inset ?? Edges(all: Pixels(0))
        copy.inset = Edges(top: held.top + insets.top, right: held.right + insets.right,
                           bottom: held.bottom + insets.bottom, left: held.left + insets.left)
        return copy
    }

    /// This scroller's own accessibility identifier, SwiftUI's `accessibilityIdentifier(_:)` on a `ScrollView`
    /// (`SP-N`; probe `I1`..`I3`: the identifier is the `AXScrollArea`'s, a child's own identifier stays and a child
    /// without one gets none). The scroller publishes a node that **contains** its content, so no identifier is pushed
    /// onto the leaves, and it is the scroller's own node: no wrapper element and no element request. It publishes
    /// as a group, not an `AXScrollArea` (divergence 250).
    public func accessibilityIdentifier(_ identifier: String) -> Self {
        var copy = self
        copy.accessibilityID = identifier
        return copy
    }
}
