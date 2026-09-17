import MetalUICore
import MetalUILayout

// Plan task 7, stage 2 (`docs/superpowers/specs/2026-09-17-engine-stage-2-design.md`
// §3 and §5; rulings LR-AB, LR-AQ, LR-AT): the proposal lowering's per-frame state —
// one stored property on `Frame` (`Frame.lowering`), defined here so a later lane
// adds fields to this type rather than to `Frame`.

/// One lowered legacy element as a flex **item**: what its parent needs to lower the
/// fields that mean something only on the parent's axes (`flexGrow`, stretch,
/// `alignSelf`, `flexShrink`, `flexBasis`, `minSize`/`maxSize`, `margin`).
///
/// Legacy registration is post-order, so the child records and the parent decides
/// (ruling LR-AB): every lowered site records one for the node it returns, and
/// reports none of these fields itself.
struct LoweredItem {
    enum Kind: Equatable {
        /// A childless `Box` or a `Text`.
        case leaf
        /// A flex container: a `Box` with children, and so `Row`, `Column` and a
        /// `.padding` layer.
        case flex(isRow: Bool)
        /// A `display: .stack` container: `Stack`, or a `Box` declaring it.
        case stack
        /// A `.frame` layer. Its item fields are written by `FrameSpec.style()`, not
        /// by an author, and its own kernel frame already lowers them (ruling LR-H);
        /// a parent only stretches it on an axis the frame leaves `nil` (`MC-Q`
        /// finding 7).
        case frameLayer
    }

    /// The pre-animation style: **structure** — which wrappers exist, on which axis
    /// W is greedy, every report (ruling LR-AS).
    var declared: Style
    /// The animated style: **values** — W's minima and maxima (ruling LR-AS).
    var animated: Style
    var site: LoweringSite
    /// Where the element's content sits when its box grows: the alignment its own
    /// lowering placed its content with (a leaf `.topLeading`, a flex container its
    /// main and cross factors, a stack or frame layer its nine-point alignment).
    var contentAlignment: ProposalAlignment
    var kind: Kind
    /// Set by the lowered container (or `noLowering` site) that receives the node
    /// (ruling LR-AQ).
    var consumed = false
}

/// A frame's lowering state. **Empty under the legacy authority.**
struct LoweringState {
    /// Each lowered element's item record, by the node it returned.
    var items: [LayoutNodeID: LoweredItem] = [:]
    /// The recorded nodes in registration order, for `LR-AQ`'s report order.
    var order: [LayoutNodeID] = []
    /// Element node → the item frame W its parent registered around it.
    private(set) var aliases: [LayoutNodeID: LayoutNodeID] = [:]
    /// A **padded** lowered `Text`'s element node → its text leaf (stage 2, lane 4,
    /// ruling LR-AH as amended). The element node is the outermost node
    /// `paddedAndSized` registered, so its rect and measured width are the padded
    /// box's; the glyphs belong at the LEAF's origin and wrap at the LEAF's measured
    /// width, or a stretched padded text would wrap at its item frame's width and
    /// overflow its trailing padding (critic round 1's finding 5). Empty when no
    /// lowered `Text` carries a padding — and under the legacy authority.
    var textLeaves: [LayoutNodeID: LayoutNodeID] = [:]

    mutating func record(_ item: LoweredItem, for node: LayoutNodeID) {
        if items[node] == nil { order.append(node) }
        items[node] = item
    }

    /// Marks `node`'s record consumed and returns it — `nil` for a node no legacy
    /// site recorded (a proposal element's).
    mutating func consume(_ node: LayoutNodeID) -> LoweredItem? {
        guard items[node] != nil else { return nil }
        items[node]!.consumed = true
        return items[node]
    }

    /// Records that `element`'s rect is `itemFrame`'s (ruling LR-AB item 3): a grown
    /// or stretched CSS box IS the bigger box — its background, hitbox, accessibility
    /// frame and text wrap width.
    mutating func alias(_ element: LayoutNodeID, to itemFrame: LayoutNodeID) {
        aliases[element] = itemFrame
    }

    /// The node whose rect is `node`'s element rect: its item frame, or itself.
    /// Read by `Frame.bounds(of:)` and `PaintPass.measuredWidth(of:)`, the only two
    /// readers of an element's rect (ruling LR-AT).
    func alias(_ node: LayoutNodeID) -> LayoutNodeID {
        aliases[node] ?? node
    }
}

extension Frame {
    /// Ruling LR-AQ: after the root's registration returns, every record no lowered
    /// container consumed reports each non-default item field as
    /// `<site>.<field>.unconsumed` — `flexGrow`, `flexShrink`, `flexBasis`,
    /// `alignSelf`, `minSize`, `maxSize`, `margin`, in that order, records in
    /// registration order. Production traps on the first, as every report does.
    ///
    /// **The root's** `flexGrow`, `flexShrink`, `flexBasis` and `alignSelf` lower as
    /// absent: the legacy root ignores each — measured, not assumed, by
    /// `anItemFieldNoLoweredContainerConsumesIsReportedByName`'s root arms, which
    /// compare the legacy root with and without the field. Its `minSize`, `maxSize`
    /// and `margin` report (CSS applies them to a root). A `.frame` layer's record is
    /// never reported: its fields are its own frame's (`LoweredItem.Kind.frameLayer`).
    func reportUnconsumedLoweredItems(root: LayoutNodeID) {
        guard layoutAuthority == .proposal else { return }
        for node in lowering.order {
            guard let item = lowering.items[node], !item.consumed, item.kind != .frameLayer else { continue }
            let d = item.declared
            var names: [String] = []
            if node != root {
                if d.flexGrow != 0 { names.append("flexGrow") }
                if d.flexShrink != 1 { names.append("flexShrink") }
                if d.flexBasis != .auto { names.append("flexBasis") }
                if d.alignSelf != nil { names.append("alignSelf") }
            }
            let auto = Size<Dimension>(width: .auto, height: .auto)
            if d.minSize != auto { names.append("minSize") }
            if d.maxSize != auto { names.append("maxSize") }
            if LoweredItem.hasMargin(d) { names.append("margin") }
            for name in names {
                noteUnlowerable(UnlowerableField(site: item.site, field: "\(name).unconsumed"))
            }
        }
    }
}

extension LoweredItem {
    /// A margin on any edge that is not a zero length. **`.auto` does not count**
    /// since stage 2's lane 4 (ruling LR-AH): the legacy engine resolves it to 0 on
    /// both axes, so it lowers to nothing and reports nothing — where stage 1's
    /// every-node check counted it.
    static func hasMargin(_ style: Style) -> Bool {
        let m = style.margin
        return [m.top, m.right, m.bottom, m.left].contains { edge in
            switch edge {
            case .auto: false
            case .length(.pixels(let p)): p.value != 0
            case .length(.rems(let r)): r.value != 0
            case .length(.percent(let f)): f != 0
            }
        }
    }

    /// A fractional margin on any edge, which has no one-to-one SwiftUI spelling and
    /// reports `margin.percent` (ruling LR-AI, stage 8's recipe).
    static func hasPercentMargin(_ style: Style) -> Bool {
        let m = style.margin
        return [m.top, m.right, m.bottom, m.left].contains { edge in
            if case .length(.percent(let f)) = edge { f != 0 } else { false }
        }
    }
}
