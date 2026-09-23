import MetalUICore
import MetalUILayout

// Plan task 7, stage 1: legacy elements lowered onto the proposal kernel in place
// (`docs/superpowers/specs/2026-09-17-engine-replacement-design.md` §5.4; rulings
// LR-A, LR-E, LR-F). Under the proposal layout authority a legacy site keeps its
// type, ids, `prepaint` and `paint`, and registers kernel nodes from its `Style`
// here instead of a CSS node through `Frame.requestNode`.
//
// **Lane 2 lowers leaves** — a childless `Box` and a `Text`. **Lane 3 lowers
// containers** — a `Box` with children, and so `Row` and `Column` — onto a native
// linear stack. **Lane 4 lowers** a `display: .stack` container (`Stack`) onto a
// native overlay (ruling LR-G), and `ModifiedElement`'s layers: a `.padding` layer
// through the container lowering, a `.frame` layer onto one native frame
// (`lowerLegacyLayer`, ruling LR-H).
//
// **Stage 2 lowers flex ITEM fields by the parent** (`docs/superpowers/specs/2026-09-17-engine-stage-2-design.md`
// §3; rulings LR-AB, LR-AC, LR-AD, LR-AQ, LR-AR): every lowered site records a
// `LoweredItem` for the node it returns (`LoweringState.swift`) and reports no item
// field itself; a lowered container consumes its children's records and wraps each
// (`planLegacyItems`, below). Lane 1 lowers the cross axis — stretch as a greedy item
// frame W aliased as the element's rect, a non-stretch `alignSelf` as an unaliased
// alignment frame. Lane 2 lowers the main axis — `flexGrow` as W greedy on it
// (equal declared factors; unequal ones report `flexGrow.weights` on the parent), a
// zero `flexBasis` on an unsized grower as `auto`, `flexShrink: 0` as `fixedSize`,
// a positive shrink as nothing (SwiftUI's compression), a px/rem `minSize` as W's
// minimum and a `maxSize` as W's maximum on a greedy axis, both folded into a
// declared size (rulings LR-AE, LR-AF, LR-AG, LR-AS). The item fields later lanes
// own are still reported, at the child's site, after the container's own rows.
//
// **Lane 5 lowers the two remaining container fields** (ruling LR-AJ),
// in `arrangeLegacyMainAxis`: `justifyContent`'s three distributions, with a
// declared main size, as native spacers (and a rigid gap leaf beside them where the
// main gap is non-zero); `.rowReverse`/`.columnReverse` as the children's **nodes**
// in reverse order with the main alignment factor mirrored.

extension LayoutPass {
    /// Lowers one legacy node — `style` already animated — over native `children`.
    /// `declared` is the pre-animation style, read only by the checks, so an
    /// animation never trips one.
    ///
    /// A **childless** node (the legacy engine lays out no children for it) lowers
    /// through `lowerLegacyLeaf` over a 0×0 native leaf: a childless `Box` reports
    /// no content size of its own, only its padding and its declared size.
    ///
    /// A node **with children** (lane 3) lowers as spec §5.4's container table
    /// says, innermost first: a native **linear stack** on the main axis
    /// (`flexDirection`), spaced by the main-axis `gap` and aligning its children on
    /// the cross axis by `alignItems` — its children arranged by
    /// `arrangeLegacyMainAxis` since stage 2's lane 5, which interleaves
    /// `justifyContent`'s spacers and reverses the node list for a reverse direction
    /// — → native **padding** (`Style.padding`) → a
    /// fixed native **frame** (`Style.size`) aligning that content by
    /// `justifyContent` on the main axis and `alignItems` on the cross axis — CSS's
    /// border-box, where a content-sized line sits inside a larger box (ruling
    /// LR-E). What the table cannot lower is reported by
    /// `legacyContainerDiagnostics`, then — since stage 2 — each child's item fields
    /// this lane cannot lower by `planLegacyItems`, before anything is registered.
    /// Every child's item record is consumed first, and the node returned (the
    /// lowered container, or a reported 0×0 leaf) is recorded as this element's own
    /// item (ruling LR-AB); a hidden container records none. The children
    /// may be native nodes of any origin — a lowered legacy element or a proposal
    /// element such as an `HStack` — because under this authority every node is
    /// native (ruling LR-T).
    ///
    /// A `display: .stack` container (a `Stack`, lane 4) lowers to a native
    /// **overlay** of its children with its nine-point alignment — `justifyItems`
    /// horizontally, `alignItems` vertically — → native padding → a fixed frame
    /// with the same alignment (ruling LR-G). For fixed children this is the
    /// legacy stack's answer; the overlay proposes its own proposal to each child
    /// where the legacy stack offers fit-content (divergence 53, spec 4.2).
    func lowerLegacyNode(_ style: Style, declared: Style, children: [LayoutNodeID],
                         site: LoweringSite) -> LayoutNodeID {
        // Stage 5 (ruling `LR-CK`): a presentation's placeholder leaves the flow
        // here, before anything counts the children — `consume`, the container
        // rows, `planLegacyItems` and its single-child elision — as the legacy
        // engine takes an absolute child out of flow at its collection sites
        // (`AP-B`). Every caller of this function is a collection site: a flex or
        // stack `Box`, a `Stack`, a `.padding` layer, a `Component` wrap and a
        // `ScrollView`'s content node. A container left with no child lowers as an
        // empty one, below.
        let children = frame.lowering.droppingPresentations(children)
        guard !children.isEmpty else {
            return lowerLegacyLeaf(style, declared: declared, site: site) {
                frame.requestNativeLeaf { _ in LayoutMeasurement(size: SizeD(width: 0, height: 0)) }
            }
        }
        // Stage 2 (ruling LR-AQ): every record this container receives is consumed,
        // whether or not a field of it lowers — and whether or not this container
        // itself reports.
        let received = children.map { frame.lowering.consume($0) }
        var fields = legacyContainerDiagnostics(declared, childCount: children.count, site: site)
        // `display: none` is reported alone and records no item (ruling LR-J).
        if declared.display == .none { return report(fields) }
        let isStack = declared.display == .stack
        let plans = planLegacyItems(received, parent: declared,
                                    parentKind: isStack ? .stack : .flex(isRow: declared.flexDirection.isRow),
                                    parentSite: site, fields: &fields)
        let kind: LoweredItem.Kind = isStack ? .stack : .flex(isRow: declared.flexDirection.isRow)

        if style.display == .stack {
            let alignment = proposalAlignment(horizontal: alignmentFactor(style.justifyItems),
                                              vertical: alignmentFactor(style.alignItems))
            if !fields.isEmpty {
                return recordLoweredItem(report(fields), animated: style, declared: declared, site: site,
                                         contentAlignment: alignment, kind: kind)
            }
            let overlay = frame.requestNativeOverlay(children: registerLegacyItems(children, plans),
                                                     alignment: alignment)
            return recordLoweredItem(paddedAndSized(overlay, style, alignment: alignment), animated: style,
                                     declared: declared, site: site, contentAlignment: alignment, kind: kind)
        }

        let isRow = style.flexDirection.isRow
        // The main-axis arrangement (lane 5): `justifyContent`'s distributions and
        // the reverse directions. `mainFactor` is `justifyContent`'s factor,
        // mirrored by a reverse direction, and is both the container's own frame
        // alignment and the content alignment its parent's item frame reads.
        let main = legacyMainFactor(style)
        let cross = alignmentFactor(style.alignItems)
        let contentAlignment = isRow ? proposalAlignment(horizontal: main, vertical: cross)
                                     : proposalAlignment(horizontal: cross, vertical: main)
        if !fields.isEmpty {
            return recordLoweredItem(report(fields), animated: style, declared: declared, site: site,
                                     contentAlignment: contentAlignment, kind: kind)
        }
        let arrangement = arrangeLegacyMainAxis(registerLegacyItems(children, plans),
                                                declared: declared, animated: style)
        // The stack reads only the cross-axis factor of its alignment.
        let stack = frame.requestNativeLinearStack(
            children: arrangement.nodes, axis: isRow ? .horizontal : .vertical,
            spacing: arrangement.spacing,
            alignment: isRow ? proposalAlignment(horizontal: 0, vertical: cross)
                             : proposalAlignment(horizontal: cross, vertical: 0))
        return recordLoweredItem(paddedAndSized(stack, style, alignment: contentAlignment), animated: style,
                                 declared: declared, site: site, contentAlignment: contentAlignment, kind: kind)
    }

    /// The container table's "otherwise" column (spec §5.4, **containers**), then
    /// the **every node** table's (`legacyLeafDiagnostics`), for a container's
    /// **declared** style with `childCount` layout children. `display: none` is
    /// checked first and alone (ruling LR-J). A `display: .stack` container (lane
    /// 4) reads none of the flex rows below — the legacy engine branches to its
    /// stack layout before any of them — and reports `alignItems.baseline`, then the
    /// every-node rows (its stretch on either axis lowers per child since stage 2,
    /// `planLegacyItems`). The flex container rows, in order:
    ///
    /// - (`reverse` is no longer a row: since stage 2's lane 5 a `.rowReverse` or
    ///   `.columnReverse` container hands its stack the children's nodes in reverse
    ///   order with its main factor mirrored, `arrangeLegacyMainAxis`, ruling LR-AJ);
    /// - `gap.percent` — a percentage **main-axis** gap (the cross-axis gap is read
    ///   by nothing on a single line, so it is not reported);
    /// - `alignItems.baseline`;
    /// - (`alignItems.stretch` is no longer a container row: since stage 2 each
    ///   child it reaches is wrapped by `planLegacyItems`, ruling LR-AC);
    /// - (`justifyContent.spaceBetween`/`.spaceAround`/`.spaceEvenly` with a declared
    ///   main size is no longer a row either: since lane 5 it lowers to native
    ///   spacers, `arrangeLegacyMainAxis`. **Without** a declared main size it still
    ///   lowers as `flex-start`, and a parent that makes the container greedy on its
    ///   own main axis reports it there, `planLegacyItems`' re-check, `LR-AR`);
    /// - `flexWrap` (≠ `.noWrap`), `alignContent` (≠ `nil`) — deleted concepts.
    ///
    /// **Not reported: overflow** (ruling LR-I). Whether fixed children overflow a
    /// declared size is known only after measurement; CSS shrinks them, the lowered
    /// stack overflows (stack-algorithms probe G9), and the harness reports the
    /// disagreement.
    func legacyContainerDiagnostics(_ declared: Style, childCount: Int,
                                    site: LoweringSite) -> [UnlowerableField] {
        func entry(_ name: String) -> UnlowerableField { UnlowerableField(site: site, field: name) }
        if declared.display == .none { return [entry("display.none")] }
        var fields: [UnlowerableField] = []
        if declared.display == .stack {
            if declared.alignItems == .baseline { fields.append(entry("alignItems.baseline")) }
            return fields + legacyLeafDiagnostics(declared, site: site)
        }
        let isRow = declared.flexDirection.isRow
        if case .percent = isRow ? declared.gap.horizontal : declared.gap.vertical {
            fields.append(entry("gap.percent"))
        }
        if declared.alignItems == .baseline { fields.append(entry("alignItems.baseline")) }
        if declared.flexWrap != .noWrap { fields.append(entry("flexWrap")) }
        if declared.alignContent != nil { fields.append(entry("alignContent")) }
        return fields + legacyLeafDiagnostics(declared, site: site)
    }

    /// Lowers a legacy **leaf**: the leaf table's checks on `declared`, then
    /// `content()` → native padding (`Style.padding`, when any edge is non-zero)
    /// → a fixed native frame aligned `.topLeading` (`Style.size`, when either axis
    /// is declared). This is CSS's border-box spelled as SwiftUI modifiers (stage-1
    /// probe B1, ruling LR-E): the padding sits inside the declared size.
    ///
    /// Returns the element's node: the outermost registered, whose rect is the
    /// element's bounds and whose measured width a `Text` wraps its glyphs at
    /// (ruling LR-X). When anything is reported, `content()` is **not** called and
    /// the node is a 0×0 native leaf. Either node is recorded as the leaf's item for
    /// its parent (stage 2, ruling LR-AB), except under `display: none`.
    ///
    /// **Every container field is ignored** (`flexDirection`, `gap`, `alignItems`,
    /// `justifyContent`, `justifyItems`, `flexWrap`, `alignContent`, `display:
    /// .stack`), and so are `aspectRatio` and `overflow`: the legacy engine lays out
    /// no children for a leaf and reads neither of the last two (spec §5.4, critic
    /// round 1 finding 6). Every **node** field outside the stage-1 subset is
    /// reported by name — see `legacyLeafDiagnostics`.
    func lowerLegacyLeaf(_ style: Style, declared: Style, site: LoweringSite,
                         content: () -> LayoutNodeID) -> LayoutNodeID {
        let fields = legacyLeafDiagnostics(declared, site: site)
        if declared.display == .none { return report(fields) }
        if !fields.isEmpty {
            return recordLoweredItem(report(fields), animated: style, declared: declared, site: site,
                                     contentAlignment: .topLeading, kind: .leaf)
        }
        return recordLoweredItem(paddedAndSized(content(), style, alignment: .topLeading,
                                                textLeaf: site == .text),
                                 animated: style,
                                 declared: declared, site: site, contentAlignment: .topLeading, kind: .leaf)
    }

    /// Lowers one `ModifiedElement` layer — `layer.style` already animated — over
    /// the native `children` (plan task 7, lane 4). `declared` is the layer's style
    /// after `ModifierLayer.lowered(_:childCount:)` and before `animated(…)`, read
    /// only by the checks.
    ///
    /// - A **`.padding` layer** (no `frameSpec`) is a one-child container and
    ///   lowers through `lowerLegacyNode` at site `modifierLayer`: native padding
    ///   over the child, and whatever a caller's `Self`-returning modifier wrote on
    ///   the layer is checked by the container table.
    /// - A **`.frame` layer** lowers to ONE native frame **per child node** (rulings
    ///   LR-H, LR-BH): fixed `width`/`height`, and finite minima and maxima, from the
    ///   **animated** style's fields that `FrameSpec.style()` wrote (`size`,
    ///   `minSize`, `maxSize`), so an animated frame lays out its interpolated value;
    ///   ideals, infinite maxima and the alignment from `frameSpec`, which `Style`
    ///   cannot carry. The kernel frame is SwiftUI's (`FR-A`/`FR-M`): a finite maximum
    ///   is greedy and a single infinite maximum fills its axis (spec 4.5), where the
    ///   legacy layer clamps (`FR-E`) or is inert (`FR-O`). Over no node the frame
    ///   wraps a 0×0 native leaf; over **several** — a multi-member `Component`,
    ///   divergence 56 — the per-member frames are rowed horizontally at spacing 0.
    ///   What cannot be lowered is reported by `legacyFrameLayerDiagnostics`.
    func lowerLegacyLayer(_ layer: ModifierLayer, declared: Style,
                          children: [LayoutNodeID]) -> LayoutNodeID {
        guard let spec = layer.frameSpec else {
            return lowerLegacyNode(layer.style, declared: declared, children: children,
                                   site: .modifierLayer)
        }
        // Stage 5 (ruling `LR-CK`, as amended by `LR-CP` item 1): the placeholder
        // leaves here too — but the style check below keeps the **undropped**
        // count, because `declared` came from `ModifierLayer.lowered(_:childCount:)`
        // over the undropped children in `ModifiedElement.requestLayout`, and
        // comparing it against a dropped count would turn a one-node frame over a
        // presentation (1 → 0) into a flex row expected against a `.stack`
        // declared, and a two-member one (2 → 1) into the reverse.
        let undroppedCount = children.count
        let children = frame.lowering.droppingPresentations(children)
        let received = children.map { frame.lowering.consume($0) }
        var fields = legacyFrameLayerDiagnostics(layer, declared: declared, childCount: undroppedCount)
        if declared.display == .none { return report(fields) }
        // A frame is a stack (`CN-N`): it stretches nothing (its `FrameSpec.style()`
        // alignment is never `stretch`) and ignores its children's flex fields. A
        // child's `maxSize` off a greedy axis still reports and a `minSize` on an
        // `auto` axis still becomes W's minimum; its **margin** does NOT report — a
        // stack or frame-layer parent drops it outright (`LR-AZ`), as this comment
        // used to say it did not. Same for `flexGrow`, `flexShrink`, `flexBasis` and
        // `alignSelf`: consumed and dropped, which `loweredComponentFrame` inherits
        // by planning the same way (`LR-BO`).
        //
        // **Planned for EVERY child count, not only one** (`LR-BH` as amended):
        // `received` is consumed above whatever the count, so a `count > 1` arm that
        // left the plans at their defaults would drop every member's item fields
        // with no diagnostic — `reportUnconsumedLoweredItems` skips a consumed
        // record. Before this stage the `frame.multipleNodes` row short-circuited
        // ahead of it and the hole could not be reached.
        let plans = planLegacyItems(received, parent: declared, parentKind: .stack,
                                    parentSite: .modifierLayer, fields: &fields)
        if !fields.isEmpty {
            return recordLoweredItem(report(fields), animated: layer.style, declared: declared,
                                     site: .modifierLayer, contentAlignment: spec.alignment, kind: .frameLayer)
        }
        let items = registerLegacyItems(children, plans)
        let style = layer.style
        // A bound `FrameSpec.style()` wrote, read back from the animated style;
        // the declared style equals `style()`'s (the check above), so the case is a
        // px length whenever the spec names the bound.
        func bound(_ declared: Pixels?, _ dimension: Dimension) -> Double? {
            guard let declared else { return nil }
            return resolvedDimension(dimension) ?? Double(declared.value)
        }
        // A finite maximum is `maxSize`; an infinite one has no `Style` row
        // (`FrameSpec.style()` writes none) and passes through as +∞.
        func maximum(_ declared: Pixels?, _ dimension: Dimension) -> Double? {
            guard let declared else { return nil }
            return declared.value.isFinite ? bound(declared, dimension) : Double(declared.value)
        }
        func framed(_ child: LayoutNodeID) -> LayoutNodeID {
            frame.requestNativeFrame(
                child: child,
                width: bound(spec.width, style.size.width),
                height: bound(spec.height, style.size.height),
                minWidth: bound(spec.minWidth, style.minSize.width),
                idealWidth: spec.idealWidth.map { Double($0.value) },
                maxWidth: maximum(spec.maxWidth, style.maxSize.width),
                minHeight: bound(spec.minHeight, style.minSize.height),
                idealHeight: spec.idealHeight.map { Double($0.value) },
                maxHeight: maximum(spec.maxHeight, style.maxSize.height),
                alignment: spec.alignment)
        }
        // Over one node (or none) ONE frame, as before. Over several — a
        // `ModifiedElement` over a multi-member `Component`, divergence 56 — one
        // frame per member, rowed horizontally at spacing **0** (`LR-BH`): SwiftUI
        // frames each member too, and its 148pt pair is this 140 plus the enclosing
        // stack's own 8pt spacing, which in MetalUI the enclosing container supplies
        // (divergence 52). No row wrapper at one node, so the node count and every
        // existing single-node rect are unchanged.
        let node: LayoutNodeID
        if items.count > 1 {
            node = frame.requestNativeLinearStack(children: items.map(framed), axis: .horizontal,
                                                  spacing: 0, alignment: spec.alignment)
        } else {
            node = framed(items.first
                ?? frame.requestNativeLeaf { _ in LayoutMeasurement(size: SizeD(width: 0, height: 0)) })
        }
        return recordLoweredItem(node, animated: layer.style, declared: declared, site: .modifierLayer,
                                 contentAlignment: spec.alignment, kind: .frameLayer)
    }

    /// A frame layer's checks (ruling LR-H), for its **declared** style:
    ///
    /// 1. `display.none` alone — a `hidden()` written after the frame, which
    ///    `ModifierLayer.lowered` keeps (ruling LR-J);
    /// 2. `style` — the declared style differs from
    ///    `layer.lowered(frameSpec.style(), childCount:)`, the style an unmodified
    ///    frame layer registers with (the same `display: .stack` a one-node frame
    ///    gets): a caller's `Self`-returning modifier written after `.frame` —
    ///    `.width`, `.minWidth`, `.flexGrow`, `.alignItems`, `.position` — lands on
    ///    the layer. An animation never trips it, because the animated style is not
    ///    what is compared.
    ///
    /// There is no third check. A frame over **more than one node** (a multi-member
    /// `Component`) reported `frame.multipleNodes` until stage 3's lane 5, which
    /// lowers it to a row of per-member frames instead (ruling `LR-BH`, retiring
    /// `LR-Z`'s deferral). `childCount` survives for the `lowered(_:childCount:)`
    /// comparison alone, which reads it to know whether an unmodified layer's
    /// display is `.stack` (one node) or a flex row (several).
    func legacyFrameLayerDiagnostics(_ layer: ModifierLayer, declared: Style,
                                     childCount: Int) -> [UnlowerableField] {
        func entry(_ name: String) -> UnlowerableField { UnlowerableField(site: .modifierLayer, field: name) }
        guard let spec = layer.frameSpec else { return [] }
        if declared.display == .none { return [entry("display.none")] }
        var fields: [UnlowerableField] = []
        if declared != layer.lowered(spec.style(), childCount: childCount) { fields.append(entry("style")) }
        return fields
    }

    /// One `Component` **amend** — a caller's `.width`/`.height` — as ONE native
    /// frame around ONE member (stage 3, lane 4, ruling `LR-BG`). Registered once
    /// per member, since a `Component` is layout-transparent and its modifiers
    /// distribute (`CO-U`, `OM-F`).
    ///
    /// The legacy branch writes `size` onto the member's own `Style` and so
    /// OVERWRITES whatever the member declared (divergence 48); this frames it
    /// instead, which is SwiftUI's answer — component-distribution probe `G7`/`G8`
    /// (`Pair().frame(width: 70)` keeps its members 30 and 50 wide, each centred
    /// in its own 70) and stage-3 probe `W1`.
    ///
    /// **It consumes and plans the member's own record** (`LR-BG` as amended,
    /// critic round 1 finding 8), exactly as `lowerLegacyLayer`'s single-node arm
    /// does. Without the consume, `reportUnconsumedLoweredItems` emits
    /// `<site>.<field>.unconsumed` for every non-default item field the member
    /// declares — and in a production frame every report is a **trap**, so
    /// `MyComponent().width(70)` over a member declaring `.flexGrow(1)` would work
    /// under the legacy authority and abort under the proposal one at stage 6b.
    ///
    /// **The parent kind is `.stack`**, as a frame's is everywhere else in the
    /// lowering, so the member's `flexGrow`, `flexShrink`, `flexBasis`,
    /// `alignSelf` and `margin` are consumed and DROPPED (`LR-AZ`, `MC-Q` finding
    /// 7) while a `minSize` on an `auto` axis is planned into the item frame W.
    /// The drop is a rect disagreement the differential harness shows, and never a
    /// trap (`LR-BO`).
    ///
    /// Recorded with `kind: .frameLayer`, so a parent stretches it only on an axis
    /// the patch leaves `auto` (`MC-Q` finding 7) and its own record is never
    /// reported unconsumed.
    ///
    /// **`.frameLayer` is the second reason site `component` cannot report, and it
    /// is not today's decisive one** (verification round, record §12; the
    /// verifier's mutation Vj wrote this record as `kind: .stack` and the whole
    /// 1569-test suite stayed green). The decisive reason is that
    /// `componentFrameStyle` carries no field `reportUnconsumedLoweredItems`
    /// names — no `minSize`, no `maxSize`, no `margin`, no grow or shrink — so this
    /// record would stay silent even unconsumed and even as a `.stack`. The kind is
    /// what takes over the moment that stops being true: whoever puts a bound into
    /// `componentFrameStyle` (to carry a member's dropped minimum, say) owes a pin
    /// for it in the same change, or a stage-6b production trap arrives with no
    /// test seeing it go.
    func loweredComponentFrame(_ node: LayoutNodeID, _ size: Size<Dimension>) -> LayoutNodeID {
        // Stage 5 (ruling `LR-CK`): an amend over a presentation member. The legacy
        // amend overwrites the absolute box's OWN size (divergence 48's mechanism),
        // an answer not reproduced here, so it reports and frames nothing — the
        // placeholder is handed on, for the parent to drop.
        if frame.lowering.isPresentation(node) {
            frame.noteUnlowerable(UnlowerableField(site: .deferred, field: "amended"))
            return node
        }
        let alignment = componentFrameAlignment(size)
        let declared = componentFrameStyle(size)
        var fields: [UnlowerableField] = []
        let plans = planLegacyItems([frame.lowering.consume(node)], parent: declared,
                                    parentKind: .stack, parentSite: .component, fields: &fields)
        if !fields.isEmpty {
            return recordLoweredItem(report(fields), animated: declared, declared: declared,
                                     site: .component, contentAlignment: alignment, kind: .frameLayer)
        }
        let child = registerLegacyItems([node], plans).first ?? node
        let framed = frame.requestNativeFrame(child: child,
                                              width: resolvedDimension(size.width),
                                              height: resolvedDimension(size.height),
                                              alignment: alignment)
        return recordLoweredItem(framed, animated: declared, declared: declared, site: .component,
                                 contentAlignment: alignment, kind: .frameLayer)
    }

    /// An amend frame's alignment: **per axis** — `.center`'s factor on an axis
    /// the patch declares, `0` on an axis it leaves `auto` (ruling `LR-BG`).
    ///
    /// **The ground is the legacy answer the undeclared axis must preserve.**
    /// Recording `.center` unconditionally moved a width-only amend's members from
    /// y 0 to y **15** in the design's prototype, because the same value is the
    /// item's `contentAlignment` and the parent's item frame reads it — a second,
    /// undesigned divergence on an axis the caller never mentioned. Stage-3 probe
    /// arms `W7`/`W8`/`W9` show SwiftUI's single-axis frame is a real frame that
    /// aligns on the axis it declares, and `W2`/`W5` that the undeclared axis
    /// passes through at the child's own size; SwiftUI has no observable answer
    /// for how such a frame aligns where there is no free space, so those arms are
    /// the consistency check, not the source.
    func componentFrameAlignment(_ size: Size<Dimension>) -> ProposalAlignment {
        proposalAlignment(horizontal: size.width == .auto ? 0 : 0.5,
                          vertical: size.height == .auto ? 0 : 0.5)
    }

    /// The **declared** style an amend frame plans its member against: a stack
    /// whose size is the patch and whose two alignment fields are non-stretching
    /// on every axis, so the frame aligns its member and never stretches it —
    /// which is what `FrameSpec.style()`'s own `switch` guarantees for a `.frame`
    /// layer (`CN-N`).
    ///
    /// **Only "non-nil and non-stretching" is load-bearing here; the per-axis
    /// spelling is cosmetic** (verification round, record §12). Deleting both
    /// assignments reddens four tests (verifier mutation Vi), but replacing the two
    /// ternaries with a constant `.center` and dropping `display` entirely reddens
    /// nothing (Vk): `alignsByStretching` and `stretches` are false for `.start`,
    /// `.flexStart` and `.center` alike, and `parentKind: .stack` is passed to
    /// `planLegacyItems` explicitly, so this style's `display` is never consulted.
    /// The per-axis alignment lives entirely in `componentFrameAlignment` — do not
    /// mutate the ternary here expecting a rect to move.
    private func componentFrameStyle(_ size: Size<Dimension>) -> Style {
        var style = Style()
        style.display = .stack
        style.size = size
        style.justifyItems = size.width == .auto ? .start : .center
        style.alignItems = size.height == .auto ? .flexStart : .center
        return style
    }

    /// Records every entry of a non-empty diagnostics list: in production the first
    /// entry traps; under diagnostics each is recorded and the frame completes on
    /// one 0×0 leaf, which is returned.
    private func report(_ fields: [UnlowerableField]) -> LayoutNodeID {
        for field in fields.dropLast() { frame.noteUnlowerable(field) }
        return frame.unlowerable(fields[fields.count - 1])
    }

    /// `node` → native padding (`style.padding` **plus `style.border`**, when any edge
    /// is non-zero) → a fixed native frame (`style.size`, when either axis is declared)
    /// aligned by `alignment`. Returns the outermost node registered. Since stage 2's
    /// lane 2 a declared axis is folded with the style's own px/rem
    /// `minSize`/`maxSize`, `max(min, min(size, max))` — CSS's used size — from the
    /// animated style (the values half of ruling LR-AS).
    ///
    /// **Border is padding** (stage 2, lane 4, ruling LR-AH): CSS's border box puts
    /// `border` inside the declared size exactly where `padding` sits, and the legacy
    /// engine shrinks its content box by both (`FlexEngine.swift`'s `contentBox`).
    /// SwiftUI has no layout border, so native padding is the spelling for the sum.
    ///
    /// **A declared size below that sum keeps its frame** (lane 4, `LR-AH` as
    /// amended; stage-2 probe P1, P7, P8): the padding overflows the fixed frame,
    /// placed by `alignment`, where CSS floors the border box at the sum (`BM-4`).
    /// Nothing is reported for it — spec 4.3 pins the divergence.
    ///
    /// **A `Text`'s leaf is remembered** when padding is registered around it
    /// (`textLeaf`, lane 4): its glyphs are painted at the leaf's origin and wrapped
    /// at the leaf's measured width, not the element's (`Text.paintGlyphs`).
    private func paddedAndSized(_ node: LayoutNodeID, _ style: Style,
                                alignment: ProposalAlignment,
                                textLeaf: Bool = false) -> LayoutNodeID {
        let content = node
        var node = node
        func inset(_ padding: Length, _ border: Length) -> Double {
            resolvedLength(padding) + resolvedLength(border)
        }
        let insets = Edges(top: inset(style.padding.top, style.border.top),
                           right: inset(style.padding.right, style.border.right),
                           bottom: inset(style.padding.bottom, style.border.bottom),
                           left: inset(style.padding.left, style.border.left))
        var padded = false
        if insets.top != 0 || insets.right != 0 || insets.bottom != 0 || insets.left != 0 {
            node = frame.requestNativePadding(child: node, insets: insets)
            padded = true
        }
        defer { if textLeaf && padded { frame.lowering.textLeaves[node] = content } }
        // A declared size is folded with its own `minSize`/`maxSize` at registration,
        // CSS's used size `max(min, min(size, max))` (stage 2, lane 2, ruling LR-AG).
        func folded(_ size: Dimension, _ minimum: Dimension, _ maximum: Dimension) -> Double? {
            guard var value = resolvedDimension(size) else { return nil }
            if let hi = resolvedDimension(maximum) { value = Swift.min(value, hi) }
            if let lo = resolvedDimension(minimum) { value = Swift.max(value, lo) }
            return value
        }
        let width = folded(style.size.width, style.minSize.width, style.maxSize.width)
        let height = folded(style.size.height, style.minSize.height, style.maxSize.height)
        if width != nil || height != nil {
            node = frame.requestNativeFrame(child: node, width: width, height: height,
                                            alignment: alignment)
        }
        return node
    }

    // MARK: The main-axis arrangement (lane 5, ruling LR-AJ)

    /// The container's own main-axis factor: `justifyContent`'s, **mirrored by a
    /// reverse direction** — `flexStart`/`nil` → 1, `flexEnd` → 0, `center`
    /// unchanged (lane 5, ruling LR-AJ; stage-2 probe R1, R2). It is the fraction
    /// of the container's own free main space placed before its line, so it is
    /// both the alignment of the fixed frame `paddedAndSized` registers and the
    /// content alignment the element records for its parent's item frame (5.9).
    ///
    /// A `space-*` factor is `alignmentFactor`'s 0 (mirrored to 1), and is not
    /// read where it is lowered: the spacers fill the line, so no free main space
    /// is left for the frame to place.
    ///
    /// Neither `flexDirection` nor `justifyContent` is animatable, so reading the
    /// animated style here is reading the declared one (`LR-AS`).
    private func legacyMainFactor(_ style: Style) -> Double {
        let factor = alignmentFactor(style.justifyContent)
        return style.flexDirection.isReverse ? 1 - factor : factor
    }

    /// Arranges one lowered flex container's already-wrapped `items` on its main
    /// axis (lane 5, ruling LR-AJ), returning the nodes to hand the native linear
    /// stack and the stack's spacing. The container's main factor is **not**
    /// returned: `lowerLegacyNode` needs it before this call, to build the content
    /// alignment it reports with when a field is unlowerable, so it computes
    /// `legacyMainFactor(_:)` itself (`LR-BA` item 2, as amended); a second copy in
    /// this tuple had no reader.
    ///
    /// **`justifyContent`'s distributions lower to native spacers**, and only with a
    /// declared main size — an unsized container has no free space to distribute and
    /// keeps stage 1's `flex-start` (a parent that later grows it reports, `LR-AR`):
    ///
    /// - `spaceBetween` → `Spacer(minLength: main gap)` between each pair, and the
    ///   **stack's own spacing drops to 0** (probe J1, J2): a spacer takes the gap
    ///   plus its share, so a stack gap as well would double-count it while it fits
    ///   and, overflowing, place the line at `2 × gap` steps instead of one (J3);
    /// - `spaceEvenly` → `Spacer(minLength: 0)` at both ends and between each pair;
    ///   `spaceAround` → the same with the between-spacers **doubled** (J4, J7);
    /// - a non-zero main gap under either → a **rigid native leaf** of that length
    ///   beside each between-spacer (J8), never the spacer's own minimum, which
    ///   distributes differently (J5: 53.33/126.67 where CSS puts 50/130).
    ///
    /// Overflowing, every spacer collapses to its minimum and the line packs from
    /// the main start (J9) — which is also what `Alignment.swift`'s
    /// `distributeMainAxis` does, since it clamps its free space at 0 for all three
    /// distributions (lane 5's measurement, `LR-BA` item 1).
    ///
    /// **A reverse direction reverses the node list** — the spacer pattern with it,
    /// which is symmetric — and mirrors the main factor. The children's group order,
    /// ids, `@State` slots, paint order, hit order and accessibility order are
    /// untouched: this function sees only node ids, the element tree having already
    /// been walked in declaration order (5.7).
    ///
    /// Structure reads the **declared** style and lengths the **animated** one
    /// (`LR-AS`).
    func arrangeLegacyMainAxis(_ items: [LayoutNodeID], declared: Style, animated: Style)
        -> (nodes: [LayoutNodeID], spacing: Double) {
        let isRow = declared.flexDirection.isRow
        // `Axes.horizontal` is the gap between a row's items, `vertical` between a
        // column's (CSS `column-gap` / `row-gap`); the cross-axis gap separates
        // lines, and a no-wrap container has one.
        let gap = resolvedLength(isRow ? animated.gap.horizontal : animated.gap.vertical)
        let mainSize = isRow ? declared.size.width : declared.size.height
        var nodes = items
        var spacing = gap
        if mainSize != .auto, let distribution = declared.justifyContent,
           distribution == .spaceBetween || distribution == .spaceAround
               || distribution == .spaceEvenly {
            nodes = distributedLegacyItems(items, distribution, gap: gap, isRow: isRow)
            spacing = 0
        }
        if declared.flexDirection.isReverse { nodes.reverse() }
        return (nodes, spacing)
    }

    /// `items` interleaved with the spacers and rigid gap leaves `distribution`
    /// spells (see `arrangeLegacyMainAxis`). `gap` is the main-axis gap in points;
    /// at 0 no rigid leaf is registered.
    private func distributedLegacyItems(_ items: [LayoutNodeID], _ distribution: JustifyContent,
                                        gap: Double, isRow: Bool) -> [LayoutNodeID] {
        let ends = distribution != .spaceBetween
        let betweenCount = distribution == .spaceAround ? 2 : 1
        // `space-between`'s minimum IS the gap; the other two carry the gap as a
        // rigid leaf, so their spacers may collapse all the way to 0.
        let minimum = distribution == .spaceBetween ? gap : 0
        func spacer() -> LayoutNodeID { frame.requestNativeSpacer(minLength: minimum) }
        func gapLeaf() -> LayoutNodeID {
            let size = isRow ? SizeD(width: gap, height: 0) : SizeD(width: 0, height: gap)
            return frame.requestNativeLeaf { _ in LayoutMeasurement(size: size) }
        }
        var nodes: [LayoutNodeID] = []
        if ends { nodes.append(spacer()) }
        for (index, item) in items.enumerated() {
            if index > 0 {
                for _ in 0..<betweenCount { nodes.append(spacer()) }
                if ends && gap != 0 { nodes.append(gapLeaf()) }
            }
            nodes.append(item)
        }
        if ends { nodes.append(spacer()) }
        return nodes
    }

    /// The fraction of free space placed before the content: 0 for `flexStart`,
    /// ½ for `center`, 1 for `flexEnd`. Every other value — `nil`/`stretch`,
    /// `space-*`, `baseline` — is 0: each is lowered only where there is no free
    /// space on that axis, or is reported.
    private func alignmentFactor(_ value: AlignItems?) -> Double {
        switch value {
        case .center: 0.5
        case .flexEnd: 1
        case nil, .flexStart, .stretch, .baseline: 0
        }
    }

    private func alignmentFactor(_ value: JustifyItems?) -> Double {
        switch value {
        case .center: 0.5
        case .end: 1
        case nil, .start, .stretch: 0
        }
    }

    private func alignmentFactor(_ value: JustifyContent?) -> Double {
        switch value {
        case .center: 0.5
        case .flexEnd: 1
        case nil, .flexStart, .spaceBetween, .spaceAround, .spaceEvenly: 0
        }
    }

    /// The nine-point alignment whose factors are `horizontal` and `vertical`, each
    /// 0, ½ or 1.
    private func proposalAlignment(horizontal: Double, vertical: Double) -> ProposalAlignment {
        let table: [[ProposalAlignment]] = [[.topLeading, .top, .topTrailing],
                                            [.leading, .center, .trailing],
                                            [.bottomLeading, .bottom, .bottomTrailing]]
        return table[Int(vertical * 2)][Int(horizontal * 2)]
    }

    /// The leaf table's "otherwise" column (spec §5.4, **every node**), in the
    /// table's order, for a leaf's **declared** style. `display: none` is checked
    /// first and alone: a hidden node reports nothing else (ruling LR-J).
    ///
    /// **Item fields are not rows here since stage 2** (`minSize`, `maxSize`,
    /// `margin`, `flexGrow`, `flexShrink`, `flexBasis`, `alignSelf`): the parent
    /// reads them from the element's `LoweredItem` (`planLegacyItems`), and a record
    /// no lowered container consumes reports them `…unconsumed` (ruling LR-AQ).
    ///
    /// Padding and border each report **only** their percentage — `padding.percent`,
    /// `border.percent` — which resolves against a containing block the kernel does
    /// not have (ruling LR-AI, stage 8's recipe). Since stage 2's lane 4 a px/rem
    /// border lowers into the native padding's insets, a `Text`'s padding lowers
    /// around its leaf, and a declared size below the padding + border sum keeps its
    /// fixed frame (ruling LR-AH) — so `padding.floor` and `padding.text` are gone.
    func legacyLeafDiagnostics(_ declared: Style, site: LoweringSite) -> [UnlowerableField] {
        func entry(_ name: String) -> UnlowerableField { UnlowerableField(site: site, field: name) }
        if declared.display == .none { return [entry("display.none")] }
        var fields: [UnlowerableField] = []

        let size = declared.size
        if isPercent(size.width) || isPercent(size.height) { fields.append(entry("size.percent")) }

        func hasPercentEdge(_ edges: Edges<Length>) -> Bool {
            [edges.top, edges.right, edges.bottom, edges.left]
                .contains { if case .percent = $0 { true } else { false } }
        }
        if hasPercentEdge(declared.padding) { fields.append(entry("padding.percent")) }
        if hasPercentEdge(declared.border) { fields.append(entry("border.percent")) }
        // Stage 5 (ruling `LR-CK`): `.absolute` is reported by the CONSUMER, not
        // here — `planLegacyItems` for a child, `reportUnconsumedLoweredItems` for a
        // record nobody consumed — because a `Deferred` consumes it and lowers it
        // as a presentation (`lowerPresentation`). `.relative` and an inset on a
        // non-absolute box still report here, unchanged.
        if declared.position == .relative { fields.append(entry("position")) }
        if declared.position != .absolute && declared.inset != Edges(all: .auto) {
            fields.append(entry("inset"))
        }
        return fields
    }

    /// A px or rem length in points (rem × the frame's `rootFontSize`); a
    /// percentage is 0 here — every caller has already reported it.
    private func resolvedLength(_ length: Length) -> Double {
        switch length {
        case .pixels(let p): Double(p.value)
        case .rems(let r): Double(r.value) * frame.rootFontSize
        case .percent: 0
        }
    }

    /// A declared px or rem dimension in points; `nil` for `auto` (and for a
    /// percentage, which the checks report).
    private func resolvedDimension(_ dimension: Dimension) -> Double? {
        switch dimension {
        case .auto, .length(.percent): nil
        case .length(let length): resolvedLength(length)
        }
    }

    private func isPercent(_ dimension: Dimension) -> Bool {
        if case .length(.percent) = dimension { true } else { false }
    }

    /// A zero length in any unit; `auto` is not zero.
    private func isZero(_ dimension: Dimension) -> Bool {
        switch dimension {
        case .auto: false
        case .length(.pixels(let p)): p.value == 0
        case .length(.rems(let r)): r.value == 0
        case .length(.percent(let f)): f == 0
        }
    }
}

// MARK: - Stage 2: item records and the wrappers a parent registers around them

/// What a lowered container registers around one child (plan task 7, stage 2, spec
/// §3 item 2): at most `fixedSize`, the item frame W and the alignment frame,
/// innermost first. Lane 1 plans the cross axis; lane 2 the main axis.
struct LegacyItemPlan {
    /// `fixedSize` on the parent's main axis, for `flexShrink: 0` on an `auto` main
    /// size (lane 2, ruling LR-AF): `true` for a row parent (horizontal).
    var fixedSizeHorizontal: Bool?
    /// W's bounds per axis — `(minimum, maximum)` — on each axis it constrains: a
    /// greedy axis (stretched or grown) has a maximum (∞ when none is declared); a
    /// non-greedy axis with a declared minimum has only that minimum. `nil` on an
    /// axis W leaves to its child. W is registered when either axis is set.
    var itemFrameWidth: (min: Double?, max: Double?)?
    var itemFrameHeight: (min: Double?, max: Double?)?
    var itemFrameAlignment: ProposalAlignment = .topLeading
    /// The alignment frame: greedy on one axis (`horizontal` for a column parent's
    /// cross axis), placing the child by `factor` there.
    var alignmentFrame: (horizontal: Bool, factor: Double)?
    /// `margin` as native padding, **outermost** — outside W and outside the alignment
    /// frame, so the element's own rect still excludes it, as CSS's margin box does
    /// (lane 4, ruling LR-AH). `nil` when no px/rem margin is declared, and always
    /// `nil` under a stack or frame-layer parent, which ignore margins (`LR-AZ`).
    var marginInsets: Edges<Double>?
}

extension LayoutPass {
    /// Records `node` as `site`'s lowered item and returns it (ruling LR-AB item 1).
    func recordLoweredItem(_ node: LayoutNodeID, animated: Style, declared: Style,
                           site: LoweringSite, contentAlignment: ProposalAlignment,
                           kind: LoweredItem.Kind) -> LayoutNodeID {
        frame.lowering.record(LoweredItem(declared: declared, animated: animated, site: site,
                                          contentAlignment: contentAlignment, kind: kind),
                              for: node)
        return node
    }

    /// Plans each received child's wrappers for a parent of `parentKind` whose
    /// **declared** style is `parent`, and appends the item fields this stage cannot
    /// lower: `flexGrow.weights` once at `parentSite`, then — in child order, each
    /// child's in `LR-AQ`'s field order — the rest at the child's own site (spec §4's
    /// report order: after the container's own rows). `received[i]` is `nil` for a
    /// child no legacy site recorded (a proposal element), which gets no wrapper.
    ///
    /// **Which wrappers exist, and on which axis W is greedy, read the declared
    /// style; W's minima and maxima read the animated one** (ruling LR-AS).
    ///
    /// **Stretch** (ruling LR-AC): a child whose cross size is `auto` and whose
    /// effective alignment — `alignSelf`, else the parent's `alignItems` (a stack
    /// parent: `justifyItems` horizontally, `alignItems` vertically) — is `nil` or
    /// `.stretch` gets W greedy on that axis, **unless the parent has exactly one
    /// child and no declared size on that axis** (the elision; stage 1's `LR-E`
    /// principle 3). On a stretched axis W's minimum is the declared `minSize`, else
    /// **0** — CSS's stretched size is the line even below the content (`LR-AW`).
    /// A `.frame` layer child is stretched the same way on an axis its frame leaves
    /// `nil` (`MC-Q` finding 7).
    ///
    /// **Grow** (a flex parent, lane 2, ruling LR-AE): `flexGrow > 0` gets W greedy on
    /// the parent's main axis — in a one-child container too (`LR-AR`) — when every
    /// growing sibling's declared factor is equal; unequal factors report
    /// `flexGrow.weights` at the parent's site. On a grown axis W's minimum comes
    /// **only** from a declared `minSize` (F3: without one a greedy frame never
    /// answers below its child, CSS's automatic minimum for rigid content).
    ///
    /// **Basis** (lane 2, `LR-AE` as amended): `auto` lowers to nothing; a zero basis
    /// (any unit) on a grower with an `auto` main size lowers as `auto`; with a
    /// declared main size it lowers only when a main `minSize` is declared too (W's
    /// minimum is that minimum; the declared size stays on the element's own frame),
    /// and otherwise reports `flexBasis` (CSS's floor is min(size, content)). Any
    /// other basis reports `flexBasis`.
    ///
    /// **Shrink** (lane 2, ruling LR-AF): `flexShrink == 0` on an `auto` main size is
    /// `fixedSize` on the main axis, innermost; any positive shrink lowers to nothing
    /// (SwiftUI's compression, divergence 55); a negative one reports `flexShrink`.
    ///
    /// **Minima and maxima** (lane 2, ruling LR-AG), per axis whose `size` is
    /// `auto`: a px/rem `minSize` is W's minimum (a non-greedy axis too — a floor); a
    /// px/rem `maxSize` is W's maximum on a greedy axis and reports `maxSize`
    /// elsewhere. On an axis with a declared `size` both fold into the element's own
    /// frame at its registration (`paddedAndSized`), and W carries only a greedy
    /// axis's maximum. A percentage reports `minSize`/`maxSize` (lane 4 renames it).
    ///
    /// **`alignSelf`** in a flex parent (ruling LR-AD): where the child is not
    /// stretched and its alignment factor (`.stretch` and `.baseline` place at the
    /// start) differs from the parent's, an alignment frame greedy on the cross axis
    /// places it — in a one-child container too (`LR-AR`). A stack parent ignores
    /// `alignSelf`, `flexGrow`, `flexShrink` and `flexBasis`, as the legacy stack does.
    ///
    /// **The free-space re-check** (ruling LR-AR): a child flex container that W
    /// constrains on its own **main** axis — greedy (stretched or grown) or floored by
    /// a minimum, either of which can leave free space inside it — with no declared
    /// main size and `justifyContent` `space-*`, reports `justifyContent.<case>` at
    /// its site.
    ///
    /// **Still reported** at the child's site: `alignSelf.baseline` (task 11) and
    /// `margin` (lane 4). A `.frame` layer child reports nothing: its item fields are
    /// its own frame's.
    ///
    /// **`parentSite:` names exactly one report, `flexGrow.weights`** (ruling LR-BM).
    /// Every other entry this function appends is raised at `item.site`, the
    /// **child's** own — which is why a lowered container whose own site is
    /// otherwise unreachable (`scrollView`, stage 3) stays reachable through the
    /// weights check and through an unconsumed record, and not through, say, a
    /// child's `alignSelf: .baseline`.
    func planLegacyItems(_ received: [LoweredItem?], parent: Style, parentKind: LoweredItem.Kind,
                         parentSite: LoweringSite, fields: inout [UnlowerableField]) -> [LegacyItemPlan] {
        let single = received.count == 1
        // The weights check (LR-AE): every growing sibling's declared factor.
        var weightsReported = false
        if case .flex = parentKind {
            let factors = Set(received.compactMap { $0 }
                .filter { $0.kind != .frameLayer && $0.declared.flexGrow > 0 }
                .map(\.declared.flexGrow))
            if factors.count > 1 {
                fields.append(UnlowerableField(site: parentSite, field: "flexGrow.weights"))
                weightsReported = true
            }
        }
        var plans: [LegacyItemPlan] = []
        for item in received {
            var plan = LegacyItemPlan()
            guard let item else {
                plans.append(plan)
                continue
            }
            let d = item.declared, a = item.animated
            func stretches(_ value: AlignItems?) -> Bool { value == nil || value == .stretch }
            // Whether the child is stretched, and grown, on each axis.
            var stretchedH = false, stretchedV = false, grownH = false, grownV = false
            // Whether a zero basis takes W's main minimum from the declared minimum.
            var basisMinimum = false
            var reports: [String] = []
            switch parentKind {
            case .flex(let isRow):
                let effective: Bool
                switch d.alignSelf {
                case nil: effective = stretches(parent.alignItems)
                case .stretch?: effective = true
                case .flexStart?, .center?, .flexEnd?, .baseline?: effective = false
                }
                let crossAuto = (isRow ? d.size.height : d.size.width) == .auto
                let parentCross = isRow ? parent.size.height : parent.size.width
                let stretched = effective && crossAuto && !(single && parentCross == .auto)
                if isRow { stretchedV = stretched } else { stretchedH = stretched }
                if item.kind != .frameLayer {
                    let mainAuto = (isRow ? d.size.width : d.size.height) == .auto
                    let mainMinimum = isRow ? d.minSize.width : d.minSize.height
                    if d.flexGrow < 0 { reports.append("flexGrow") }
                    if d.flexGrow > 0 && !weightsReported {
                        if isRow { grownH = true } else { grownV = true }
                    }
                    if d.flexShrink < 0 {
                        reports.append("flexShrink")
                    } else if d.flexShrink == 0 && mainAuto {
                        plan.fixedSizeHorizontal = isRow
                    }
                    if d.flexBasis != .auto {
                        if isZero(d.flexBasis) && d.flexGrow > 0 {
                            if !mainAuto {
                                if resolvedDimension(mainMinimum) != nil { basisMinimum = true }
                                else { reports.append("flexBasis") }
                            }
                        } else {
                            reports.append("flexBasis")
                        }
                    }
                    if d.alignSelf == .baseline { reports.append("alignSelf.baseline") }
                }
                if !stretched {
                    let parentFactor = alignmentFactor(parent.alignItems)
                    let childFactor = d.alignSelf.map(alignmentFactor) ?? parentFactor
                    if childFactor != parentFactor {
                        plan.alignmentFrame = (horizontal: !isRow, factor: childFactor)
                    }
                }
            case .stack, .leaf, .frameLayer, .presentation:
                stretchedH = alignsByStretching(parent.justifyItems) && d.size.width == .auto
                    && !(single && parent.size.width == .auto)
                stretchedV = stretches(parent.alignItems) && d.size.height == .auto
                    && !(single && parent.size.height == .auto)
            }

            // W's bounds on one axis (nil: W leaves the axis to its child), and the
            // reports that axis's minimum and maximum make. A fraction is named
            // `minSize.percent`/`maxSize.percent` since lane 4 (ruling LR-AI); a
            // px/rem maximum off a greedy axis keeps the bare `maxSize` (stage 8).
            var minimumPercent = false, maximumPercent = false, maximumReported = false
            func axis(size: Dimension, declaredMin: Dimension, declaredMax: Dimension,
                      animatedMin: Dimension, animatedMax: Dimension,
                      stretched: Bool, grown: Bool) -> (min: Double?, max: Double?)? {
                if item.kind == .frameLayer {
                    // Lane 1: a frame layer's own bounds, repeated on a stretched axis.
                    guard stretched else { return nil }
                    let lo = resolvedDimension(animatedMin) ?? 0
                    return (lo, Swift.max(lo, Swift.max(0, resolvedDimension(animatedMax) ?? .infinity)))
                }
                if isPercent(declaredMin) { minimumPercent = true }
                if isPercent(declaredMax) { maximumPercent = true }
                let hasMin = resolvedDimension(declaredMin) != nil
                let hasMax = resolvedDimension(declaredMax) != nil
                let greedy = stretched || grown
                if size != .auto {
                    // Folded into the element's own frame; W carries a greedy axis's
                    // maximum, and a zero basis's declared minimum.
                    guard greedy else { return nil }
                    let lo = grown && basisMinimum ? resolvedDimension(animatedMin) : nil
                    return (lo, Swift.max(lo ?? 0, Swift.max(0, resolvedDimension(animatedMax) ?? .infinity)))
                }
                if greedy {
                    let lo = resolvedDimension(animatedMin) ?? (stretched ? 0 : nil)
                    return (lo, Swift.max(lo ?? 0, Swift.max(0, resolvedDimension(animatedMax) ?? .infinity)))
                }
                if hasMax { maximumReported = true }
                return hasMin ? (resolvedDimension(animatedMin), nil) : nil
            }
            plan.itemFrameWidth = axis(size: d.size.width, declaredMin: d.minSize.width, declaredMax: d.maxSize.width,
                                       animatedMin: a.minSize.width, animatedMax: a.maxSize.width,
                                       stretched: stretchedH, grown: grownH)
            plan.itemFrameHeight = axis(size: d.size.height, declaredMin: d.minSize.height,
                                        declaredMax: d.maxSize.height,
                                        animatedMin: a.minSize.height, animatedMax: a.maxSize.height,
                                        stretched: stretchedV, grown: grownV)
            if item.kind != .frameLayer {
                if minimumPercent { reports.append("minSize.percent") }
                if maximumPercent { reports.append("maxSize.percent") }
                if maximumReported { reports.append("maxSize") }
                // Margin (lane 4, rulings LR-AH, LR-AZ): a px/rem margin on either
                // sign is native padding outermost; a fraction reports
                // `margin.percent` (stage 8); `.auto` lowers as 0, which is what the
                // legacy engine resolves it to (CLAUDE.md's inert table). A **stack**
                // or **frame-layer** parent ignores a child's margin entirely, in
                // size and in position — measured on the legacy stack, not assumed.
                switch parentKind {
                case .flex:
                    if LoweredItem.hasMargin(d) {
                        if LoweredItem.hasPercentMargin(d) {
                            reports.append("margin.percent")
                        } else {
                            plan.marginInsets = Edges(top: marginEdge(a.margin.top),
                                                      right: marginEdge(a.margin.right),
                                                      bottom: marginEdge(a.margin.bottom),
                                                      left: marginEdge(a.margin.left))
                        }
                    }
                case .stack, .leaf, .frameLayer, .presentation:
                    break
                }
            }
            if case .flex(let childIsRow) = item.kind,
               (childIsRow ? plan.itemFrameWidth : plan.itemFrameHeight) != nil,
               (childIsRow ? d.size.width : d.size.height) == .auto {
                switch d.justifyContent {
                case .spaceBetween?: reports.append("justifyContent.spaceBetween")
                case .spaceAround?: reports.append("justifyContent.spaceAround")
                case .spaceEvenly?: reports.append("justifyContent.spaceEvenly")
                case nil, .flexStart?, .center?, .flexEnd?: break
                }
            }
            // Stage 5 (ruling `LR-CK`): an absolute child outside a `Deferred` is
            // removed from the proposal authority, reported at its own site after
            // its other item fields, under the names `legacyLeafDiagnostics` used to
            // raise. A frame layer's record is skipped: a `.position` written after
            // `.frame` is its own `style` report.
            if item.kind != .frameLayer && d.position == .absolute {
                reports.append("position")
                if d.inset != Edges(all: .auto) { reports.append("inset") }
            }
            fields += reports.map { UnlowerableField(site: item.site, field: $0) }
            plan.itemFrameAlignment = item.contentAlignment
            plans.append(plan)
        }
        return plans
    }

    /// Registers each child's planned wrappers, innermost first — `fixedSize`, the
    /// item frame W, the alignment frame — aliasing the child's node to W (ruling
    /// LR-AB item 3), and returns the nodes the container registers in the children's
    /// place.
    func registerLegacyItems(_ children: [LayoutNodeID], _ plans: [LegacyItemPlan]) -> [LayoutNodeID] {
        var nodes: [LayoutNodeID] = []
        for (child, plan) in zip(children, plans) {
            var node = child
            if let horizontal = plan.fixedSizeHorizontal {
                node = frame.requestNativeFixedSize(child: node, horizontal: horizontal, vertical: !horizontal)
            }
            if plan.itemFrameWidth != nil || plan.itemFrameHeight != nil {
                node = frame.requestNativeFrame(child: node,
                                                minWidth: plan.itemFrameWidth?.min,
                                                maxWidth: plan.itemFrameWidth?.max,
                                                minHeight: plan.itemFrameHeight?.min,
                                                maxHeight: plan.itemFrameHeight?.max,
                                                alignment: plan.itemFrameAlignment)
                frame.lowering.alias(child, to: node)
            }
            if let alignmentFrame = plan.alignmentFrame {
                node = alignmentFrame.horizontal
                    ? frame.requestNativeFrame(child: node, maxWidth: .infinity,
                                               alignment: proposalAlignment(horizontal: alignmentFrame.factor,
                                                                            vertical: 0))
                    : frame.requestNativeFrame(child: node, maxHeight: .infinity,
                                               alignment: proposalAlignment(horizontal: 0,
                                                                            vertical: alignmentFrame.factor))
            }
            // The margin is outside the box, as in CSS (lane 4, ruling LR-AH): it is
            // registered last and is NOT aliased, so `Frame.bounds(of:)` still reports
            // the border box. A negative inset overlaps, and the kernel's padding
            // response clamps at 0 per axis where CSS's margin box goes negative
            // (`SA-K` item 3; spec 4.5 pins the divergence).
            if let insets = plan.marginInsets {
                node = frame.requestNativePadding(child: node, insets: insets)
            }
            nodes.append(node)
        }
        return nodes
    }

    /// The fraction of free space an `alignSelf` places before the child: `.center`
    /// ½, `.flexEnd` 1, and 0 for `.flexStart`, `.stretch` (a declared cross size
    /// sits at the start) and `.baseline` (reported).
    private func alignmentFactor(_ value: AlignSelf) -> Double {
        switch value {
        case .center: 0.5
        case .flexEnd: 1
        case .flexStart, .stretch, .baseline: 0
        }
    }

    private func alignsByStretching(_ value: JustifyItems?) -> Bool {
        value == nil || value == .stretch
    }

    /// One margin edge in points: `.auto` is 0 — what the legacy engine resolves it to
    /// (CLAUDE.md's inert table) — and a percentage is 0 here, its caller having
    /// reported `margin.percent` already.
    private func marginEdge(_ dimension: Dimension) -> Double {
        switch dimension {
        case .auto: 0
        case .length(let length): resolvedLength(length)
        }
    }
}

// MARK: - Stage 5: a presentation's placement (rulings LR-CI, LR-CJ, LR-CK)

extension LayoutPass {
    /// Lowers a `Deferred`'s **absolute** content — `node`, whose record `item`
    /// the `Deferred` has just consumed — into a presentation root laid out against
    /// the window (plan task 7, stage 5, ruling `LR-CI`; overlay-presentation probe
    /// revision 2, group Q). Returns the root of the presentation's own native run,
    /// which `Frame.computeRootLayout` lays out before the frame's root (`LR-CM`).
    ///
    /// Per axis — horizontal reads `left`/`right` and `size.width`, vertical
    /// `top`/`bottom` and `size.height` — **which insets are given and whether the
    /// size is `auto` come from the declared style; the inset lengths from the
    /// animated one** (`LR-AS`; `inset` animates):
    ///
    /// | declared size | insets given | W on this axis | padding edges | frame alignment |
    /// |---|---|---|---|---|
    /// | `auto` | both | greedy, min 0, max ∞ (aliased) | leading and trailing | leading |
    /// | `auto` | leading only | none | leading | leading |
    /// | `auto` | trailing only | none | trailing | trailing |
    /// | any | neither | none | none | leading (divergence 9) |
    /// | px/rem | leading, or both | none | leading | leading |
    /// | px/rem | trailing only | none | trailing | trailing |
    ///
    /// Registered innermost first: `node` (the element's own lowering, with its
    /// padding, border and declared size folded with its min/max, `AP-E`) → **W**
    /// (one frame carrying both stretched axes' bounds, aligned by the element's
    /// `contentAlignment`, registered only when an axis is stretched and **aliased**
    /// as the element's rect, `LR-AB` item 3) → native padding (only when an edge
    /// is non-zero) → a fixed window-sized frame aligned per axis. Padding inside a
    /// filling frame is SwiftUI's own spelling (Q1, Q1c, Q2).
    ///
    /// **Two deliberate proposal-only answers** (`LR-CJ`): measured content on an
    /// axis with one inset is proposed the window minus the inset (Q3), where the
    /// legacy engine measures against the whole window; and W's minimum stays 0, so
    /// a stretched axis narrower than the element's padding keeps the inset box and
    /// lets the padding overflow, where the legacy engine floors it (`BM-4`).
    ///
    /// **Reported, and the presentation still registers** (`LR-CJ` item 3):
    /// `minSize`/`maxSize` on an `auto` axis → `<site>.minSize.absolute` /
    /// `<site>.maxSize.absolute` (the legacy engine ignores them; SwiftUI and CSS
    /// would not). A percentage `minSize`/`maxSize` on a declared axis reports
    /// `minSize.percent`/`maxSize.percent`, which the element's own fold ignores.
    /// **Dropped** (`LR-CK`): `flexGrow`, `flexShrink`, `flexBasis`, `alignSelf`
    /// and `margin` — the legacy engine ignores every one on an absolute box
    /// (measured), so the consumed record is their end.
    func lowerPresentation(_ node: LayoutNodeID, _ item: LoweredItem) -> LayoutNodeID {
        let d = item.declared, a = item.animated
        struct AxisPlan {
            var greedy = false
            var leading = 0.0
            var trailing = 0.0
            var factor = 0.0
            var minimumAbsolute = false, maximumAbsolute = false
            var minimumPercent = false, maximumPercent = false
        }
        func axis(size: Dimension, leading: Dimension, trailing: Dimension,
                  animatedLeading: Dimension, animatedTrailing: Dimension,
                  minimum: Dimension, maximum: Dimension, extent: Pixels) -> AxisPlan {
            var plan = AxisPlan()
            if size == .auto {
                plan.minimumAbsolute = minimum != .auto
                plan.maximumAbsolute = maximum != .auto
            } else {
                plan.minimumPercent = isPercent(minimum)
                plan.maximumPercent = isPercent(maximum)
            }
            func length(_ dimension: Dimension) -> Double {
                switch dimension {
                case .auto: 0
                case .length(.percent(let f)): Double(f) * Double(extent.value)
                case .length(let length): resolvedLength(length)
                }
            }
            let hasLeading = leading != .auto, hasTrailing = trailing != .auto
            if size == .auto && hasLeading && hasTrailing {
                plan.greedy = true
                plan.leading = length(animatedLeading)
                plan.trailing = length(animatedTrailing)
            } else if hasLeading {
                plan.leading = length(animatedLeading)
            } else if hasTrailing {
                plan.trailing = length(animatedTrailing)
                plan.factor = 1
            }
            return plan
        }
        let window = frame.contentSize
        let h = axis(size: d.size.width, leading: d.inset.left, trailing: d.inset.right,
                     animatedLeading: a.inset.left, animatedTrailing: a.inset.right,
                     minimum: d.minSize.width, maximum: d.maxSize.width, extent: window.width)
        let v = axis(size: d.size.height, leading: d.inset.top, trailing: d.inset.bottom,
                     animatedLeading: a.inset.top, animatedTrailing: a.inset.bottom,
                     minimum: d.minSize.height, maximum: d.maxSize.height, extent: window.height)
        var names: [String] = []
        if h.minimumAbsolute || v.minimumAbsolute { names.append("minSize.absolute") }
        if h.maximumAbsolute || v.maximumAbsolute { names.append("maxSize.absolute") }
        if h.minimumPercent || v.minimumPercent { names.append("minSize.percent") }
        if h.maximumPercent || v.maximumPercent { names.append("maxSize.percent") }
        for name in names { frame.noteUnlowerable(UnlowerableField(site: item.site, field: name)) }

        var root = node
        if h.greedy || v.greedy {
            root = frame.requestNativeFrame(child: node,
                                            minWidth: h.greedy ? 0 : nil,
                                            maxWidth: h.greedy ? .infinity : nil,
                                            minHeight: v.greedy ? 0 : nil,
                                            maxHeight: v.greedy ? .infinity : nil,
                                            alignment: item.contentAlignment)
            frame.lowering.alias(node, to: root)
        }
        let padding = Edges(top: v.leading, right: h.trailing, bottom: v.trailing, left: h.leading)
        if padding.top != 0 || padding.right != 0 || padding.bottom != 0 || padding.left != 0 {
            root = frame.requestNativePadding(child: root, insets: padding)
        }
        return frame.requestNativeFrame(child: root,
                                        width: Double(window.width.value),
                                        height: Double(window.height.value),
                                        alignment: proposalAlignment(horizontal: h.factor, vertical: v.factor))
    }

    /// Whether a presentation's content box **is** the window (ruling `LR-CL`): four
    /// zero insets, both sizes `auto` and no border, so its padding box — the
    /// containing block of any presentation registered inside it — is the window.
    /// The one nested case the legacy engine answers as the lowering does (the
    /// demo's card could hold a tooltip); every other nesting reports
    /// `deferred.nested`.
    func presentationCoversWindow(_ style: Style) -> Bool {
        let i = style.inset, b = style.border
        return [i.top, i.right, i.bottom, i.left].allSatisfy(isZero)
            && style.size.width == .auto && style.size.height == .auto
            && [b.top, b.right, b.bottom, b.left].allSatisfy { edge in
                switch edge {
                case .pixels(let p): p.value == 0
                case .rems(let r): r.value == 0
                case .percent(let f): f == 0
                }
            }
    }
}
