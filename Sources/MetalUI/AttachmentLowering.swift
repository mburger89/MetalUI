import MetalUICore
import MetalUILayout

// Plan task 7, stage 11, lane 2 (`docs/superpowers/specs/2026-09-25-engine-stage-11-design.md`
// §5; ruling `LR-FX`): the legacy `.overlay`. `OverlayModifier` takes any
// `ElementGroup` on either side, so a side's nodes may be lowered legacy
// elements carrying a `LoweredItem` — and a record nobody consumes is reported
// by name (`LR-AQ`), a production trap since stage 6b. This file is the one
// place an attachment consumes them.

extension LayoutPass {
    /// The nodes one side of an overlay attachment registers in place of
    /// `nodes`: exactly a frame layer's children (`lowerShownLegacyFrameLayer`,
    /// `LR-AZ`) — an overlay attachment is a one-primary stack.
    ///
    /// 1. A presentation's placeholder leaves (`droppingPresentations`, `LR-CK`),
    ///    as every lowered container drops it: a `Deferred` over absolute content
    ///    presents against the window, not against the attachment. A primary
    ///    that is a presentation is thereby left with **zero** nodes, which the
    ///    attachment's precondition then names (`LR-FX` item 4).
    /// 2. Each remaining node's record is **consumed** and planned at
    ///    `parentKind: .stack`: `flexGrow`, `flexShrink`, `flexBasis`, `alignSelf`
    ///    and `margin` are dropped, as a stack or frame-layer parent drops them;
    ///    a px/rem `minSize` on an `auto` axis still becomes the item frame's
    ///    minimum; a `maxSize` off a greedy axis and an absolute child outside a
    ///    `Deferred` still report at the child's own site. The parent style
    ///    aligns `.center` on both axes, so nothing is stretched — an overlay is
    ///    proposed its primary's size, it is not a CSS box that stretches its
    ///    items.
    /// 3. `parentSite: .modifierLayer` names only `flexGrow.weights`, which a
    ///    `.stack` plan never raises (`LR-BM`), so reusing it adds no
    ///    unreachable site to `everyLegacySiteIsReportedByNameWhenDiagnosticsAreOn`.
    ///
    /// A proposal node carries no record: it gets an empty plan and is returned
    /// **unwrapped**, so a proposal overlay mints exactly the nodes it minted
    /// before stage 11 (`aProposalOverlayRegistersExactlyTheNodesItDidBeforeUnification`).
    ///
    /// Anything reported: in production the first entry traps; under
    /// diagnostics every entry is recorded and the side is replaced by the one
    /// 0×0 leaf `Frame.unlowerable` returns, so the frame completes.
    func lowerAttachmentChildren(_ nodes: [LayoutNodeID]) -> [LayoutNodeID] {
        let nodes = frame.lowering.droppingPresentations(nodes)
        let received = nodes.map { frame.lowering.consume($0) }
        var parent = Style()
        parent.justifyItems = .center
        parent.alignItems = .center
        var fields: [UnlowerableField] = []
        let plans = planLegacyItems(received, parent: parent, parentKind: .stack,
                                    parentSite: .modifierLayer, fields: &fields)
        guard fields.isEmpty else {
            for field in fields.dropLast() { frame.noteUnlowerable(field) }
            return [frame.unlowerable(fields[fields.count - 1])]
        }
        return registerLegacyItems(nodes, plans)
    }
}
