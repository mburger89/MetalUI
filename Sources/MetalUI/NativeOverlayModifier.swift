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

    /// **One cursor is threaded through the primary and then the overlay**, as
    /// `Pair` threads it and every legacy container does (ruling MC-E): the
    /// primary's elements take indices from 0 under this modifier's id, and the
    /// overlay's continue where the primary's stopped.
    ///
    /// **Until 2026-09-15 the overlay started a second cursor at 0**, so a
    /// one-element primary and a one-element overlay received the SAME id, and
    /// with it one `@State` slot, one hitbox id and one `$anim` slot. Measured
    /// through a real `Window`: an overlay never clicked read the primary's 3
    /// taps, and with the pointer over the primary only, both painted their
    /// hover fills (60pt and 10pt wide).
    ///
    /// **The cost of threading:** the overlay's index depends on how many
    /// indices the primary consumed, which its node count does not fix — an
    /// empty `Component` consumes an index and contributes no node. A primary
    /// `{ if flag { EmptyComponent() }; Rectangle() }` moves the overlay between
    /// index 2 and 1 as `flag` toggles, and its state is read from a different
    /// entry. That is record §01's trailing-sibling rule; keep the primary's
    /// index-consuming shape fixed, or name the overlay's element.
    ///
    /// Pinned by `theOverlaysPrimaryAndOverlayElementsHaveDistinctIdentities`,
    /// `aTapOnAnOverlaysPrimaryWritesOnlyThePrimarysState`,
    /// `hoveringAnOverlaysPrimaryDoesNotHoverTheOverlay` and, for the index
    /// shift, `anOverlaysIdentityFollowsTheIndicesItsPrimaryConsumed`
    /// (`ModifierCompositionProofTests.swift`); all four are red with the
    /// second cursor restored.
    public mutating func requestLayout(_ id: GlobalElementID,
                                       pass: inout LayoutPass) -> (LayoutNodeID, Layout) {
        var cursor = 0
        let (contentNodes, contentLayout) = content.requestGroupLayout(under: id, at: &cursor,
                                                                        pass: &pass)
        let (overlayNodes, overlayLayout) = overlay.requestGroupLayout(under: id, at: &cursor,
                                                                        pass: &pass)
        precondition(contentNodes.count == 1 && overlayNodes.count == 1,
                     "a native overlay modifier requires one primary and one overlay node")
        let node = pass.requestNativeOverlayAttachment(child: contentNodes[0], overlay: overlayNodes[0],
                                                       alignment: alignment)
        return (node, Layout(node: node, content: contentLayout, overlay: overlayLayout))
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
