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
/// Five 40pt rows in a 200×100 viewport, probed against the real engine:
///
/// | content node | height | overflows |
/// |---|---|---|
/// | `min-height: auto` (default), `flexShrink: 0` | 200 | yes |
/// | `min-height: auto` (default), `flexShrink` default | 200 | yes |
/// | `min-height: 0`, `flexShrink: 0` | 200 | yes |
/// | `min-height: 0`, `flexShrink` default | **100** | **no** |
///
/// **CSS Sizing §4.5's automatic minimum is the sole mechanism by which this
/// content node overflows** — `min-height: auto` floors it at its content
/// size, divergence FS-3's mechanism. Rows one and two agree with each other
/// regardless of `flexShrink`, which is what rules it out; only removing the
/// automatic minimum (rows three vs. four) changes the answer, and only then
/// does `flexShrink` matter.
///
/// **`flexShrink: 0` was specified in the design's first draft as the
/// mechanism, measured against this type, and removed.** The content node
/// here never carries an explicit `min-height: 0` — `ScrollView` conforms to
/// `Element`, not `StyledElement`, so it has no modifier surface, and nothing
/// inside `requestLayout` ever sets `contentStyle.minSize` away from its
/// `.auto` default. Row four, the one row where `flexShrink` matters, is
/// therefore unreachable through this type: there is no caller who can ever
/// put it there. Setting `flexShrink = 0` here was measured to be inert (the
/// required mutation — delete it, run the full 468-test suite, revert —
/// reddened nothing, including a differential built specifically to catch
/// it) and, being unreachable rather than merely untested today, it was
/// deleted rather than kept "for later": CLAUDE.md's declared-but-inert table
/// opens on exactly this hazard — an API that exists, compiles, and does
/// nothing reads as considered and invites the next container to cargo-cult
/// it. The engine fact that made `flexShrink: 0` worth specifying at all —
/// that it holds a node open once an explicit zero minimum removes the
/// automatic one — is real and is pinned independently of this type by
/// `flexShrinkHoldsAContentNodeOpenOnceItsAutomaticMinimumIsRemoved`
/// (`Tests/MetalUILayoutTests/ScrollLayoutTests.swift`). If a future change
/// gives this content node a real minimum override, that change is what adds
/// `flexShrink: 0` back, together with a test through `ScrollView` itself
/// that the mutation would then redden.
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
        // No `flexShrink` override: the type doc explains why one is
        // unreachable here (this node's `minSize` never leaves `.auto`, so
        // CSS Sizing §4.5's automatic minimum is what overflows it) and was
        // measured, then deleted, rather than kept inert.
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
        // Registered OUTSIDE `clipped(to:offsetBy:)`, using the bounds handed
        // in rather than anything computed inside the block: `bounds` here is
        // this viewport's rect in its PARENT's space, which is what a wheel
        // event's window-space position needs to be compared against. Inside
        // the block, `pass`'s active clip has already absorbed this rect, so a
        // nested `ScrollView` registers ITS rect intersected with this one —
        // see `Frame.registerScrollRegion`.
        pass.registerScrollRegion(bounds, id: id, axis: axis)
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
