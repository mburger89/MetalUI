import MetalUICore
import MetalUILayout

public enum ScrollAxis: Sendable, Equatable { case vertical, horizontal }

/// Cross-frame scroll position, in logical points along the scroll axis.
public struct ScrollState: Sendable {
    public var offset: Double = 0
    public init(offset: Double = 0) { self.offset = offset }
}

/// A clipped, scrollable viewport over content taller (or wider) than itself.
///
/// **SwiftUI's shape, not CSS's** (ruling EP-5): `ScrollView { … }` rather than
/// `Box.overflow(.scroll)`. `Style.overflow` stays the substrate this element
/// writes into, the way `Column.init` writes `alignItems` without `Style`'s
/// default moving (ruling EP-8).
///
/// **Two layout nodes, and the reason is measured rather than assumed.** A
/// viewport node takes the offered size; a content node inside it overflows.
/// What makes it overflow is CSS Sizing §4.5's automatic minimum — `min-height:
/// auto` floors the content node at its content size, divergence FS-3's
/// mechanism — and NOT `flexShrink: 0`, which the design's first draft claimed.
/// Measured 2026-08-28: with `min-height: auto` the content is 200pt tall
/// whatever `flexShrink` says; with an explicit `min-height: 0` AND the default
/// `flexShrink`, it collapses to the viewport's 100 and scrolling dies.
///
/// `flexShrink = 0` is still set below, but **measured as dead code in THIS
/// type**, not as the belt an earlier draft of this comment claimed. The
/// required mutation — delete `contentStyle.flexShrink = 0` from
/// `requestLayout`, run the full 468-test suite, revert — reddened nothing.
/// The reason is specific rather than "flexShrink doesn't matter": this
/// element never gives its content node an explicit `min-height: 0` — the
/// automatic minimum from `min-height: auto` is the only value this content
/// node's `minSize` ever holds — so the row of the measured table where
/// `flexShrink` is load-bearing (the fourth) is unreachable through
/// `ScrollView`'s own API today. That row is real and pinned at the engine
/// level by `aContentNodeWithAnExplicitZeroMinimumStillOverflows`
/// (`Tests/MetalUILayoutTests/ScrollLayoutTests.swift`), which builds its own
/// tree by hand with an explicit zero minimum rather than going through this
/// type — which is exactly why deleting the line here cannot redden it. Kept
/// rather than deleted, as defense for the day something here (or a future
/// modifier) gives the content node a non-`auto` minimum; delete this row
/// once that day comes and the mutation actually reddens something.
///
/// **Scroll position is `StateTable` state, so it inherits §4.3's adoption
/// rule**: a `ScrollView` inside a vanishing `if` hands its offset to the
/// trailing sibling, not to a fresh zero — a list silently inheriting another
/// list's scroll position is a confusing thing to meet cold. The remedy is the
/// counter-intuitive one CLAUDE.md records — name the **trailing sibling**, not
/// the conditional content, to keep this element's offset from drifting onto
/// whatever renders after it vanishes.
public struct ScrollView<Content: ElementGroup>: Element {
    public var axis: ScrollAxis
    public var elementID: ElementID?
    public var content: Content

    public init(_ axis: ScrollAxis = .vertical, elementID: ElementID? = nil,
                @ElementBuilder content: () -> Content) {
        self.axis = axis
        self.elementID = elementID
        self.content = content()
    }

    public struct Layout {
        public var node: LayoutNodeID       // viewport
        public var contentNode: LayoutNodeID
        var inner: Content.GroupLayout
    }

    /// `0 ... max(0, content - viewport)`.
    ///
    /// **Clamped on read, not on write.** The wheel handler that writes the
    /// offset (Task 7) has no access to the current layout, and the layout that
    /// would validate it does not exist until the next frame — so a stored
    /// value may legitimately be out of range when content shrinks between
    /// frames. `aStoredOffsetPastTheEndIsClampedWhenItIsRead` in
    /// `ScrollViewTests.swift` is what this guarantees.
    static func clamp(offset: Double, content: Double, viewport: Double) -> Double {
        min(max(0, offset), max(0, content - viewport))
    }

    public mutating func requestLayout(_ id: GlobalElementID,
                                       pass: inout LayoutPass) -> (LayoutNodeID, Layout) {
        var cursor = 0
        let (children, inner) = content.requestGroupLayout(under: id, at: &cursor, pass: &pass)

        var contentStyle = Style()
        contentStyle.flexDirection = axis == .vertical ? .column : .row
        // Measured, not assumed: removing this line moves nothing in the full
        // 468-test suite. See the type's doc above for why — this content
        // node never gets an explicit `min-height: 0`, so the row of the
        // measured table where `flexShrink` matters is unreachable here.
        // Kept as defense against a future change that gives it one.
        contentStyle.flexShrink = 0
        let contentNode = pass.requestNode(style: contentStyle, children: children)

        var viewportStyle = Style()
        viewportStyle.flexDirection = axis == .vertical ? .column : .row
        // Written for the model's sake. The engine reads `overflow` nowhere
        // today — measured: removing this line moved no number in the layout
        // probe — so it documents intent rather than driving behaviour. See
        // CLAUDE.md's declared-but-inert table.
        viewportStyle.overflow = Axes(both: .scroll)
        let node = pass.requestNode(style: viewportStyle, children: [contentNode])

        return (node, Layout(node: node, contentNode: contentNode, inner: inner))
    }

    public mutating func prepaint(_ id: GlobalElementID, bounds: Bounds<Pixels>,
                                  layout: inout Layout,
                                  pass: inout PrepaintPass) -> Content.GroupPrepaint {
        let offset = resolvedOffset(id, bounds: bounds, layout: layout, pass: pass)
        var result: Content.GroupPrepaint!
        pass.clipped(to: bounds, offsetBy: delta(-offset)) {
            result = content.prepaintGroup(layout: &layout.inner, pass: &pass)
        }
        return result
    }

    public mutating func paint(_ id: GlobalElementID, bounds: Bounds<Pixels>,
                               layout: inout Layout, prepaint: inout Content.GroupPrepaint,
                               pass: inout PaintPass) {
        let offset = resolvedOffset(id, bounds: bounds, layout: layout, pass: pass)
        pass.clipped(to: bounds, offsetBy: delta(-offset)) {
            content.paintGroup(layout: &layout.inner, prepaint: &prepaint, pass: &pass)
        }
    }

    // Two overloads, one per pass type, rather than one function taking a
    // shared protocol. `PrepaintPass` and `PaintPass` have no common protocol
    // to write this against — `Passes.swift` records why: a `StatefulPass`
    // requirement would force `frame` public on both, and `PaintPass.frame`
    // leaking makes `scaleFactor` reachable through it, which is exactly the
    // double-application hazard `PaintPass` is built to keep out of element
    // code. Three lines duplicated is cheaper than that leak.
    private func resolvedOffset(_ id: GlobalElementID, bounds: Bounds<Pixels>,
                                layout: Layout, pass: PrepaintPass) -> Double {
        let viewport = extent(bounds.size)
        let content = extent(pass.bounds(of: layout.contentNode).size)
        var stored: Double = 0
        pass.withState(id, initial: ScrollState()) { stored = $0.offset }
        return Self.clamp(offset: stored, content: content, viewport: viewport)
    }

    private func resolvedOffset(_ id: GlobalElementID, bounds: Bounds<Pixels>,
                                layout: Layout, pass: PaintPass) -> Double {
        let viewport = extent(bounds.size)
        let content = extent(pass.bounds(of: layout.contentNode).size)
        var stored: Double = 0
        pass.withState(id, initial: ScrollState()) { stored = $0.offset }
        return Self.clamp(offset: stored, content: content, viewport: viewport)
    }

    private func delta(_ v: Double) -> Point<Pixels> {
        axis == .vertical ? Point(x: Pixels(0), y: Pixels(Float(v)))
                          : Point(x: Pixels(Float(v)), y: Pixels(0))
    }

    func extent(_ size: Size<Pixels>) -> Double {
        Double(axis == .vertical ? size.height.value : size.width.value)
    }
}
