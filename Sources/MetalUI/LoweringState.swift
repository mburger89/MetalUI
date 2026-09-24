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
        /// A childless `Box`, a `Text`, or — since stage 3 — a `ScrollView`'s kernel
        /// scroll **viewport** (ruling LR-BB): it is a leaf to its parent, whatever
        /// its content is, and its own record's `declared` is a bare `Style()`
        /// because `ScrollView` has no modifier surface.
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
        /// A `Deferred` presentation's **placeholder** (plan task 7, stage 5,
        /// rulings `LR-CH`, `LR-CK`): the 0×0 native leaf a presentation root hands
        /// its parent in place of its content, which is laid out in its own run
        /// against the window (`LoweringState.presentations`). Its `declared` is a
        /// bare `Style()` and its site `deferred`. **Every lowered container drops
        /// it at entry** (`LoweringState.droppingPresentations(_:)`), as the legacy
        /// engine filters an absolute child out of flow (`AP-B`).
        case presentation
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

/// A frame's lowering state.
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
    /// lowered `Text` carries a padding.
    var textLeaves: [LayoutNodeID: LayoutNodeID] = [:]
    /// Every presentation registered this frame, in registration order (plan task
    /// 7, stage 5, rulings `LR-CH`, `LR-CM`): the placeholder its `Deferred`
    /// returned and the root of its own native run, which `Frame.computeRootLayout`
    /// lays out against the window **before** the frame's root.
    var presentations: [(placeholder: LayoutNodeID, root: LayoutNodeID)] = []

    /// `children` without the presentation placeholders (ruling `LR-CK`): the
    /// lowering's collection sites — `lowerLegacyNode`, `lowerLegacyLayer`'s frame
    /// arm — call this **at entry**, before `consume`, `planLegacyItems` and the
    /// single-child stretch elision count, as the legacy engine removes an
    /// absolute child from flow at its two collection sites (`AP-B`). A container
    /// whose only child was a placeholder lowers as an empty one.
    func droppingPresentations(_ children: [LayoutNodeID]) -> [LayoutNodeID] {
        guard !presentations.isEmpty else { return children }
        return children.filter { items[$0]?.kind != .presentation }
    }

    /// Whether `node` is a presentation placeholder.
    func isPresentation(_ node: LayoutNodeID) -> Bool {
        items[node]?.kind == .presentation
    }

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
    /// registration order — then, since stage 5, `position` and `inset` for an
    /// `.absolute` record (ruling `LR-CK`). Production traps on the first, as every
    /// report does. A presentation placeholder is never reported.
    ///
    /// **The root's** `flexGrow`, `flexShrink`, `flexBasis` and `alignSelf` lower as
    /// absent: the legacy root ignores each — measured, not assumed, by
    /// `anItemFieldNoLoweredContainerConsumesIsReportedByName`'s root arms, which
    /// compare the legacy root with and without the field. Its `minSize`, `maxSize`
    /// and `margin` report (CSS applies them to a root) — **except, since stage 6b, a
    /// px/rem `minSize`/`maxSize` on an axis the root declares in px/rem** (ruling
    /// `LR-DO` item 1, honouring `LR-AQ`'s "a root frame is stage 6b's placement
    /// ruling"): the element's own fixed frame already folds it into the declared size
    /// at registration (`paddedAndSized`, `max(min, min(size, max))`, `LR-AG`), and CSS
    /// gives the same used size because `CS-I` does not touch a declared root axis, so
    /// nothing is left unlowered and it stops reporting
    /// (`aRootsMinimumAndMaximumFoldIntoItsDeclaredSize`). A bound on an **auto** root
    /// axis, a percentage on either side, a margin and `.absolute` still report — and
    /// in production trap (`aRootFieldWithNoLoweringTrapsInAProductionWindow`). A
    /// `.frame` layer's record reports nothing of its own fields — they are its own
    /// frame's (`LoweredItem.Kind.frameLayer`) — **except, since stage 8, `position`
    /// and `inset` when its declared style is absolute** (ruling `LR-FA`): `LR-EV`
    /// exempts those two from the layer's `modifierLayer.style` comparison, so
    /// without this a framed absolute root would lower silently where the own-box
    /// spelling reports (`aFramedAbsoluteBoxStillReportsEveryOtherFieldAndItsPositionOutsideADeferred`,
    /// arm 4).
    func reportUnconsumedLoweredItems(root: LayoutNodeID) {
        for node in lowering.order {
            guard let item = lowering.items[node], !item.consumed,
                  item.kind != .presentation else { continue }
            let d = item.declared
            // Stage 8 (`LR-FA`): a `.frame` layer's own fields are its frame's and
            // are never reported — but an absolute one no `Deferred` consumed (the
            // root, in practice) reports `position` and `inset` exactly as the
            // own-box spelling it replaces does, and nothing else.
            if item.kind == .frameLayer {
                guard d.position == .absolute else { continue }
                var names = ["position"]
                if d.inset != Edges(all: .auto) { names.append("inset") }
                for name in names {
                    noteUnlowerable(UnlowerableField(site: item.site, field: "\(name).unconsumed"))
                }
                continue
            }
            var names: [String] = []
            if node != root {
                if d.flexGrow != 0 { names.append("flexGrow") }
                if d.flexShrink != 1 { names.append("flexShrink") }
                if d.flexBasis != .auto { names.append("flexBasis") }
                if d.alignSelf != nil { names.append("alignSelf") }
            }
            let auto = Size<Dimension>(width: .auto, height: .auto)
            if node == root {
                if !Self.rootBoundFolds(d.minSize, into: d.size) { names.append("minSize") }
                if !Self.rootBoundFolds(d.maxSize, into: d.size) { names.append("maxSize") }
            } else {
                if d.minSize != auto { names.append("minSize") }
                if d.maxSize != auto { names.append("maxSize") }
            }
            if LoweredItem.hasMargin(d) { names.append("margin") }
            // Stage 5 (`LR-CK`): an `.absolute` box no `Deferred` consumed — the
            // root included, whose insets the legacy root ignores (measured (0, 0))
            // — is removed from the proposal authority, under the names a reader
            // already knows.
            if d.position == .absolute {
                names.append("position")
                if d.inset != Edges(all: .auto) { names.append("inset") }
            }
            for name in names {
                noteUnlowerable(UnlowerableField(site: item.site, field: "\(name).unconsumed"))
            }
        }
    }
}

extension Frame {
    /// Whether a root's `bound` (its `minSize` or its `maxSize`) folds into its
    /// declared `size` on every axis it names (ruling `LR-DO` item 1): each axis is
    /// either `auto` in `bound`, or a px/rem length in both `bound` and `size` — the
    /// case `paddedAndSized` folds. An `auto` size or a percentage on either side does
    /// not fold.
    fileprivate static func rootBoundFolds(_ bound: Size<Dimension>, into size: Size<Dimension>) -> Bool {
        func isLength(_ d: Dimension) -> Bool {
            switch d {
            case .length(.pixels), .length(.rems): true
            case .auto, .length(.percent): false
            }
        }
        func folds(_ b: Dimension, _ s: Dimension) -> Bool {
            b == .auto || (isLength(b) && isLength(s))
        }
        return folds(bound.width, size.width) && folds(bound.height, size.height)
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
