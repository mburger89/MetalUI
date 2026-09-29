import MetalUICore
import MetalUILayout

/// A native SwiftUI-style overlay attachment.
///
/// Its overlay is proposed the primary content's resolved size, placed at that
/// proposal and positioned by its answer and `alignment` (probe A6–A8, K5), and
/// does not change the primary content's reported size.
///
/// **Any number of overlay views** (ruling CN-K): several are one centred
/// `ZStack` that `alignment` positions (A10, K5a, K5g); none leaves the primary
/// alone and registers no attachment (A11). The primary must contribute exactly
/// one node. Prepaints and paints the primary before the overlay, so the
/// overlay's hitboxes rank above the primary's (probe H2); `BackgroundModifier`
/// is the reverse.
///
/// **Either side may be legacy content** (plan task 7, stage 11, ruling
/// `LR-FX`): `CN-Q` handed the legacy `.overlay` to the modifier unification,
/// and this type already had the second generic parameter that needs. It is a
/// `ProposalElementGroup` — so it enters an `HStack` — only when **both** sides
/// are. Both sides' nodes pass through `lowerAttachmentChildren`
/// (`AttachmentLowering.swift`): each legacy record is consumed and planned as
/// a frame layer's child is (`LR-AZ` — a primary's `flexGrow` or an overlay's
/// `margin` is dropped), a presentation placeholder is dropped, and a proposal
/// node passes unwrapped. A primary that is a presentation (zero nodes) or a
/// multi-member `Component` (two or more) traps by the attachment's
/// precondition, naming the count (`LR-FX` item 4 as amended by `LR-GA` item
/// 3); per-member distribution is plan task 8's `Group` semantics.
public struct OverlayModifier<Content: ElementGroup, Overlay: ElementGroup>: Element {
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
    ///
    /// **Two entries, one body** (stage 11, spec §3.2's split): the untyped
    /// `requestLayout` — `Frame`'s root and a legacy parent — registers both
    /// sides through `requestGroupLayout`; the typed `requestProposalLayout` — a
    /// proposal parent, only when both sides are proposal content — through
    /// `requestProposalGroupLayout`. Only the two side-entry lines are written
    /// twice; the overlay side's id (`overlaySide(of:)`) and the attachment
    /// (`attach`) are shared, so a mutation of either reaches both entries.
    public mutating func requestLayout(_ id: GlobalElementID,
                                       pass: inout LayoutPass) -> (LayoutNodeID, Layout) {
        var contentCursor = 0
        let (contentNodes, contentLayout) = content.requestGroupLayout(under: id, at: &contentCursor,
                                                                       pass: &pass)
        var overlayCursor = 0
        let (overlayNodes, overlayLayout) = overlay.requestGroupLayout(under: Self.overlaySide(of: id),
                                                                       at: &overlayCursor, pass: &pass)
        let node = attach(contentNodes, overlayNodes, pass: &pass)
        return (node, Layout(node: node, content: contentLayout, overlay: overlayLayout))
    }

    /// The id the overlay side numbers under: `MC-P`'s `-1`, which no cursor
    /// can produce.
    static func overlaySide(of id: GlobalElementID) -> GlobalElementID {
        GlobalElementID.child(of: id, at: -1, name: nil)
    }

    /// Both sides lowered (`lowerAttachmentChildren`), then the attachment.
    func attach(_ contentNodes: [LayoutNodeID], _ overlayNodes: [LayoutNodeID],
                pass: inout LayoutPass) -> LayoutNodeID {
        let primary = pass.lowerAttachmentChildren(contentNodes)
        let secondary = pass.lowerAttachmentChildren(overlayNodes)
        return pass.requestSecondaryContentAttachment(primary: primary, secondary: secondary,
                                                      alignment: alignment, modifier: "overlay")
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

extension OverlayModifier: ProposalElementGroup, ProposalElement
    where Content: ProposalElementGroup, Overlay: ProposalElementGroup {
    /// The typed entry — a proposal parent: both sides through
    /// `requestProposalGroupLayout`, then the shared `attach`.
    public mutating func requestProposalLayout(_ id: GlobalElementID,
                                               pass: inout LayoutPass) -> (ProposalNodeID, Layout) {
        var contentCursor = 0
        let (contentNodes, contentLayout) = content.requestProposalGroupLayout(under: id, at: &contentCursor,
                                                                                pass: &pass)
        var overlayCursor = 0
        let (overlayNodes, overlayLayout) = overlay.requestProposalGroupLayout(under: Self.overlaySide(of: id),
                                                                                at: &overlayCursor,
                                                                                pass: &pass)
        let node = attach(contentNodes.map(\.layoutNodeID), overlayNodes.map(\.layoutNodeID), pass: &pass)
        return (ProposalNodeID(node), Layout(node: node, content: contentLayout, overlay: overlayLayout))
    }
}

extension ElementGroup {
    /// Places `content` over this view, proposed this view's size and
    /// positioned by `alignment` (ruling CN-K). **One overload, on
    /// `ElementGroup`** (plan task 7, stage 11, ruling `LR-FX` item 1): a legacy
    /// primary or overlay is lowered as a frame layer's child
    /// (`OverlayModifier`'s doc); the result enters a proposal container only
    /// when both sides are proposal content.
    public func overlay<Overlay: ElementGroup>(alignment: ProposalAlignment = .center,
                                               @ElementBuilder content: () -> Overlay)
        -> OverlayModifier<Self, Overlay> {
        OverlayModifier(content: self, alignment: alignment, overlay: content)
    }
}

extension ProposalElementGroup {
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
