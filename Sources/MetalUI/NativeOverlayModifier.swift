import MetalUICore
import MetalUILayout

/// A native SwiftUI-style overlay attachment.
///
/// Its overlay is measured against the primary content's resolved size and
/// does not change the primary content's reported size.
public struct OverlayModifier<Content: ProposalElementGroup, Overlay: ProposalElementGroup>: Element {
    public var content: Content
    public var overlay: Overlay
    public var alignment: ProposalAlignment

    public init(content: Content, alignment: ProposalAlignment = .center,
                @ElementBuilder overlay: () -> Overlay) {
        self.content = content
        self.overlay = overlay()
        self.alignment = alignment
    }

    public struct Layout {
        var node: LayoutNodeID
        var content: Content.GroupLayout
        var overlay: Overlay.GroupLayout
    }

    /// **The primary's elements number from 0 under this modifier's id; the
    /// overlay's number from 0 under a child id no cursor can produce,
    /// `.child(of: id, at: -1, name: nil)`** (ruling MC-P, which replaces MC-E's
    /// threaded cursor). So the overlay's identity is independent of the
    /// primary's shape, as SwiftUI's is.
    ///
    /// **Until 2026-09-15 the overlay started a second cursor at 0 under the
    /// same id**, so a one-element primary and a one-element overlay received
    /// the SAME id, and with it one `@State` slot, one hitbox id and one `$anim`
    /// slot. Measured through a real `Window`: an overlay never clicked read the
    /// primary's 3 taps, and with the pointer over the primary only, both
    /// painted their hover fills (60pt and 10pt wide).
    ///
    /// **The first fix threaded ONE cursor through both (`6ff2d31`), and that
    /// diverged from SwiftUI.** The overlay's index then depended on how many
    /// indices the primary consumed, which its node count does not fix: an
    /// empty `Component` consumes an index and contributes no node, so a
    /// primary `{ if flag { EmptyComponent() }; Rectangle() }` moved the
    /// overlay between index 2 and 1 as `flag` toggled, and it read 3, 0, 3
    /// taps. SwiftUI keeps an overlay's state through such a flip — ZStack,
    /// Group, multi-view-body and `EmptyView` primaries alike
    /// (`docs/probes/swiftui-overlay-primary-shape.swift`, with controls).
    ///
    /// **Why `-1` and not a reserved name or a level on both sides.** A
    /// `.positional(-1)` component is unreachable from any cursor (cursors
    /// start at 0 and only grow), so it cannot collide with a primary element
    /// however many indices the primary consumes, and it adds no name to
    /// CLAUDE.md's seven unguarded reserved names. Putting the primary under an
    /// intermediate id too would move every overlaid primary one level deeper
    /// and re-seed its state (the demo preview's `PreviewToggle` among them).
    ///
    /// Pinned by `theOverlaysPrimaryAndOverlayElementsHaveDistinctIdentities`,
    /// `aTapOnAnOverlaysPrimaryWritesOnlyThePrimarysState`,
    /// `hoveringAnOverlaysPrimaryDoesNotHoverTheOverlay` and, for the primary's
    /// shape, `anOverlaysIdentityDoesNotDependOnTheIndicesItsPrimaryConsumed`
    /// (`ModifierCompositionProofTests.swift`). The shared-cursor-at-0 mutation
    /// reddens all four; the threaded cursor reddens the first and the last.
    public mutating func requestProposalLayout(_ id: GlobalElementID,
                                               pass: inout LayoutPass) -> (ProposalNodeID, Layout) {
        var contentCursor = 0
        let (contentNodes, contentLayout) = content.requestProposalGroupLayout(under: id, at: &contentCursor,
                                                                                pass: &pass)
        var overlayCursor = 0
        let overlaySide = GlobalElementID.child(of: id, at: -1, name: nil)
        let (overlayNodes, overlayLayout) = overlay.requestProposalGroupLayout(under: overlaySide,
                                                                                at: &overlayCursor,
                                                                                pass: &pass)
        precondition(contentNodes.count == 1 && overlayNodes.count == 1,
                     "a native overlay modifier requires one primary and one overlay node")
        let node = pass.requestNativeOverlayAttachment(child: contentNodes[0], overlay: overlayNodes[0],
                                                       alignment: alignment)
        return (node, Layout(node: node.layoutNodeID, content: contentLayout, overlay: overlayLayout))
    }

    public mutating func prepaint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Layout,
                                  pass: inout PrepaintPass) -> (Content.GroupPrepaint, Overlay.GroupPrepaint) {
        (content.prepaintGroup(layout: &layout.content, pass: &pass),
         overlay.prepaintGroup(layout: &layout.overlay, pass: &pass))
    }

    public mutating func paint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Layout,
                               prepaint: inout (Content.GroupPrepaint, Overlay.GroupPrepaint),
                               pass: inout PaintPass) {
        content.paintGroup(layout: &layout.content, prepaint: &prepaint.0, pass: &pass)
        overlay.paintGroup(layout: &layout.overlay, prepaint: &prepaint.1, pass: &pass)
    }
}

extension ProposalElementGroup {
    public func overlay<Overlay: ProposalElementGroup>(alignment: ProposalAlignment = .center,
                                               @ElementBuilder content: () -> Overlay)
        -> OverlayModifier<Self, Overlay> {
        OverlayModifier(content: self, alignment: alignment, overlay: content)
    }

    /// Temporary source-compatible spelling for the native migration surface.
    @available(*, deprecated, renamed: "overlay")
    public func nativeOverlay<Overlay: ProposalElementGroup>(alignment: ProposalAlignment = .center,
                                                      @ElementBuilder content: () -> Overlay)
        -> OverlayModifier<Self, Overlay> {
        overlay(alignment: alignment, content: content)
    }
}

/// Temporary source-compatible name for ``OverlayModifier``.
@available(*, deprecated, renamed: "OverlayModifier")
public typealias NativeOverlayModifier<Content: ProposalElementGroup, Overlay: ProposalElementGroup>
    = OverlayModifier<Content, Overlay>
