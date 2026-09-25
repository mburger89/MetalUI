import MetalUICore
import MetalUILayout

/// A native SwiftUI-style background attachment: `.background(alignment:content:)`.
///
/// Laid out exactly as ``OverlayModifier``: the background content is proposed
/// the primary's resolved size, placed at that proposal and positioned by its
/// answer and `alignment` (probe A9, K5e, K5h, R4), and never changes the
/// primary's reported size. Several background views are one centred `ZStack`
/// that `alignment` positions; none leaves the primary alone (A11b). Ruling CN-K.
///
/// **Prepaints AND paints `background` before `content`.** Painting first puts
/// it beneath; prepainting first registers its hitboxes first, so the
/// primary's rank above them in `topmostOpaqueHitbox` and a click over both
/// reaches the primary (overlay-presentation probe H1). A primary with no
/// click handler does not block a clickable background beneath it, where
/// SwiftUI's view does (H3) — the kind of difference divergence 23 records.
///
/// **Identity** is `OverlayModifier`'s (ruling MC-P): the primary numbers from
/// 0 under this modifier's id, the background content from 0 under
/// `.child(of: id, at: -1, name: nil)`, so the content's state does not depend
/// on how many indices the primary consumed.
public struct BackgroundModifier<Content: ProposalElementGroup, Background: ProposalElementGroup>: Element {
    public var content: Content
    public var background: Background
    public var alignment: ProposalAlignment

    public init(content: Content, alignment: ProposalAlignment = .center,
                @ElementBuilder background: () -> Background) {
        self.content = content
        self.background = background()
        self.alignment = alignment
    }

    public struct Layout {
        var node: LayoutNodeID
        var content: Content.GroupLayout
        var background: Background.GroupLayout
    }

    public mutating func requestProposalLayout(_ id: GlobalElementID,
                                               pass: inout LayoutPass) -> (ProposalNodeID, Layout) {
        var contentCursor = 0
        let (contentNodes, contentLayout) = content.requestProposalGroupLayout(under: id, at: &contentCursor,
                                                                                pass: &pass)
        var backgroundCursor = 0
        let backgroundSide = GlobalElementID.child(of: id, at: -1, name: nil)
        let (backgroundNodes, backgroundLayout) = background.requestProposalGroupLayout(under: backgroundSide,
                                                                                         at: &backgroundCursor,
                                                                                         pass: &pass)
        let node = pass.requestSecondaryContentAttachment(primary: contentNodes.map(\.layoutNodeID),
                                                          secondary: backgroundNodes.map(\.layoutNodeID),
                                                          alignment: alignment, modifier: "background")
        return (ProposalNodeID(node), Layout(node: node, content: contentLayout, background: backgroundLayout))
    }

    public mutating func prepaint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Layout,
                                  pass: inout PrepaintPass) -> (Content.GroupPrepaint, Background.GroupPrepaint) {
        let behind = background.prepaintGroup(layout: &layout.background, pass: &pass)
        return (content.prepaintGroup(layout: &layout.content, pass: &pass), behind)
    }

    public mutating func paint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Layout,
                               prepaint: inout (Content.GroupPrepaint, Background.GroupPrepaint),
                               pass: inout PaintPass) {
        background.paintGroup(layout: &layout.background, prepaint: &prepaint.1, pass: &pass)
        content.paintGroup(layout: &layout.content, prepaint: &prepaint.0, pass: &pass)
    }
}

extension ProposalElementGroup {
    /// Places `content` behind this view, proposed this view's size and
    /// positioned by `alignment` (ruling CN-K). The `ColorToken` overload,
    /// `.background(_:)`, fills this view's bounds instead.
    public func background<Background: ProposalElementGroup>(alignment: ProposalAlignment = .center,
                                                             @ElementBuilder content: () -> Background)
        -> BackgroundModifier<Self, Background> {
        BackgroundModifier(content: self, alignment: alignment, background: content)
    }
}

extension LayoutPass {
    /// The lowering `OverlayModifier` and `BackgroundModifier` share (ruling
    /// CN-K): exactly one primary node; no secondary node registers nothing and
    /// answers the primary; several are one kernel `overlay` (a `ZStack`)
    /// aligned `.center` whatever `alignment` is (probe K5g, K5h), which the
    /// attachment then positions with `alignment`.
    ///
    /// **Takes `LayoutNodeID`s since stage 11** (ruling `LR-FX`): a legacy
    /// overlay's sides are lowered legacy nodes, handed here by
    /// `OverlayModifier.attach` after `lowerAttachmentChildren`; a proposal
    /// modifier maps its `ProposalNodeID`s. The precondition's message is the
    /// named answer for a presentation primary (`got 0`) and a multi-member
    /// `Component` primary (`got 2`), pinned by exit tests
    /// `anOverlayOnAPresentationTrapsNamingItsPrimaryCount` and
    /// `aLegacyOverlayOnATwoMemberComponentTrapsNamingItsPrimaryCount`.
    mutating func requestSecondaryContentAttachment(primary: [LayoutNodeID], secondary: [LayoutNodeID],
                                                    alignment: ProposalAlignment,
                                                    modifier: String) -> LayoutNodeID {
        precondition(primary.count == 1,
                     "a native \(modifier) modifier requires one primary node, got \(primary.count)")
        let content: LayoutNodeID
        switch secondary.count {
        case 0: return primary[0]
        case 1: content = secondary[0]
        default: content = frame.requestNativeOverlay(children: secondary, alignment: .center)
        }
        return frame.requestNativeOverlayAttachment(child: primary[0], overlay: content, alignment: alignment)
    }
}
