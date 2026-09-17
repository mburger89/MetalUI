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
// alignment frame — and still reports the item fields later lanes own, at the
// child's site, after the container's own rows.

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
    /// the cross axis by `alignItems` → native **padding** (`Style.padding`) → a
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
                                    fields: &fields)
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
        let main = alignmentFactor(style.justifyContent)
        let cross = alignmentFactor(style.alignItems)
        let contentAlignment = isRow ? proposalAlignment(horizontal: main, vertical: cross)
                                     : proposalAlignment(horizontal: cross, vertical: main)
        if !fields.isEmpty {
            return recordLoweredItem(report(fields), animated: style, declared: declared, site: site,
                                     contentAlignment: contentAlignment, kind: kind)
        }
        // `Axes.horizontal` is the gap between a row's items, `vertical` between a
        // column's (CSS `column-gap` / `row-gap`); the cross-axis gap separates
        // lines, and a no-wrap container has one.
        let spacing = resolvedLength(isRow ? style.gap.horizontal : style.gap.vertical)
        // The stack reads only the cross-axis factor of its alignment.
        let stack = frame.requestNativeLinearStack(
            children: registerLegacyItems(children, plans), axis: isRow ? .horizontal : .vertical,
            spacing: spacing,
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
    /// - `reverse` — `.rowReverse`/`.columnReverse`;
    /// - `gap.percent` — a percentage **main-axis** gap (the cross-axis gap is read
    ///   by nothing on a single line, so it is not reported);
    /// - `alignItems.baseline`;
    /// - (`alignItems.stretch` is no longer a container row: since stage 2 each
    ///   child it reaches is wrapped by `planLegacyItems`, ruling LR-AC);
    /// - `justifyContent.spaceBetween`/`.spaceAround`/`.spaceEvenly` — unless there
    ///   is no declared main-axis size;
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
        if declared.flexDirection.isReverse { fields.append(entry("reverse")) }
        if case .percent = isRow ? declared.gap.horizontal : declared.gap.vertical {
            fields.append(entry("gap.percent"))
        }
        let mainSize = isRow ? declared.size.width : declared.size.height
        if declared.alignItems == .baseline { fields.append(entry("alignItems.baseline")) }
        if mainSize != .auto {
            switch declared.justifyContent {
            case .spaceBetween: fields.append(entry("justifyContent.spaceBetween"))
            case .spaceAround: fields.append(entry("justifyContent.spaceAround"))
            case .spaceEvenly: fields.append(entry("justifyContent.spaceEvenly"))
            case nil, .flexStart, .center, .flexEnd: break
            }
        }
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
        return recordLoweredItem(paddedAndSized(content(), style, alignment: .topLeading), animated: style,
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
    /// - A **`.frame` layer** lowers to ONE native frame (ruling LR-H): fixed
    ///   `width`/`height`, and finite minima and maxima, from the **animated**
    ///   style's fields that `FrameSpec.style()` wrote (`size`, `minSize`,
    ///   `maxSize`), so an animated frame lays out its interpolated value; ideals,
    ///   infinite maxima and the alignment from `frameSpec`, which `Style` cannot
    ///   carry. The kernel frame is SwiftUI's (`FR-A`/`FR-M`): a finite maximum is
    ///   greedy and a single infinite maximum fills its axis (spec 4.5), where the
    ///   legacy layer clamps (`FR-E`) or is inert (`FR-O`). Over no node the frame
    ///   wraps a 0×0 native leaf. What cannot be lowered is reported by
    ///   `legacyFrameLayerDiagnostics`.
    func lowerLegacyLayer(_ layer: ModifierLayer, declared: Style,
                          children: [LayoutNodeID]) -> LayoutNodeID {
        guard let spec = layer.frameSpec else {
            return lowerLegacyNode(layer.style, declared: declared, children: children,
                                   site: .modifierLayer)
        }
        let received = children.map { frame.lowering.consume($0) }
        var fields = legacyFrameLayerDiagnostics(layer, declared: declared, childCount: children.count)
        if declared.display == .none { return report(fields) }
        // A frame over one node is a stack (`CN-N`): it stretches nothing (its
        // `FrameSpec.style()` alignment is never `stretch`) and ignores its child's
        // flex fields; a child's `minSize`, `maxSize` or `margin` still reports.
        var plans: [LegacyItemPlan] = received.map { _ in LegacyItemPlan() }
        if children.count == 1 {
            plans = planLegacyItems(received, parent: declared, parentKind: .stack, fields: &fields)
        }
        if !fields.isEmpty {
            return recordLoweredItem(report(fields), animated: layer.style, declared: declared,
                                     site: .modifierLayer, contentAlignment: spec.alignment, kind: .frameLayer)
        }
        let child = registerLegacyItems(children, plans).first
            ?? frame.requestNativeLeaf { _ in LayoutMeasurement(size: SizeD(width: 0, height: 0)) }
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
        let node = frame.requestNativeFrame(
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
    ///    what is compared;
    /// 3. `frame.multipleNodes` — a frame over more than one node (a multi-member
    ///    `Component`), which the legacy engine lays out as a flex row and SwiftUI
    ///    frames member by member (component-distribution `G7`); stage 3's (ruling
    ///    LR-Z).
    func legacyFrameLayerDiagnostics(_ layer: ModifierLayer, declared: Style,
                                     childCount: Int) -> [UnlowerableField] {
        func entry(_ name: String) -> UnlowerableField { UnlowerableField(site: .modifierLayer, field: name) }
        guard let spec = layer.frameSpec else { return [] }
        if declared.display == .none { return [entry("display.none")] }
        var fields: [UnlowerableField] = []
        if declared != layer.lowered(spec.style(), childCount: childCount) { fields.append(entry("style")) }
        if childCount > 1 { fields.append(entry("frame.multipleNodes")) }
        return fields
    }

    /// Records every entry of a non-empty diagnostics list: in production the first
    /// entry traps; under diagnostics each is recorded and the frame completes on
    /// one 0×0 leaf, which is returned.
    private func report(_ fields: [UnlowerableField]) -> LayoutNodeID {
        for field in fields.dropLast() { frame.noteUnlowerable(field) }
        return frame.unlowerable(fields[fields.count - 1])
    }

    /// `node` → native padding (`style.padding`, when any edge is non-zero) → a
    /// fixed native frame (`style.size`, when either axis is declared) aligned by
    /// `alignment`. Returns the outermost node registered.
    private func paddedAndSized(_ node: LayoutNodeID, _ style: Style,
                                alignment: ProposalAlignment) -> LayoutNodeID {
        var node = node
        let insets = Edges(top: resolvedLength(style.padding.top),
                           right: resolvedLength(style.padding.right),
                           bottom: resolvedLength(style.padding.bottom),
                           left: resolvedLength(style.padding.left))
        if insets.top != 0 || insets.right != 0 || insets.bottom != 0 || insets.left != 0 {
            node = frame.requestNativePadding(child: node, insets: insets)
        }
        let width = resolvedDimension(style.size.width)
        let height = resolvedDimension(style.size.height)
        if width != nil || height != nil {
            node = frame.requestNativeFrame(child: node, width: width, height: height,
                                            alignment: alignment)
        }
        return node
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
    /// Padding reports one entry at most: `padding.percent` (a percentage resolves
    /// against a containing block the kernel does not have), else `padding.floor`
    /// (a declared size below the padding sum on an axis, where CSS floors the
    /// border box, `BM-4`), else — **on a `Text`**, whose legacy leaf ignores its
    /// padding — `padding.text`.
    func legacyLeafDiagnostics(_ declared: Style, site: LoweringSite) -> [UnlowerableField] {
        func entry(_ name: String) -> UnlowerableField { UnlowerableField(site: site, field: name) }
        if declared.display == .none { return [entry("display.none")] }
        var fields: [UnlowerableField] = []

        let size = declared.size
        if isPercent(size.width) || isPercent(size.height) { fields.append(entry("size.percent")) }

        let padding = declared.padding
        let paddingEdges = [padding.top, padding.right, padding.bottom, padding.left]
        if paddingEdges.contains(where: { if case .percent = $0 { true } else { false } }) {
            fields.append(entry("padding.percent"))
        } else if let width = resolvedDimension(size.width),
                  width < resolvedLength(padding.left) + resolvedLength(padding.right) {
            fields.append(entry("padding.floor"))
        } else if let height = resolvedDimension(size.height),
                  height < resolvedLength(padding.top) + resolvedLength(padding.bottom) {
            fields.append(entry("padding.floor"))
        } else if site == .text, paddingEdges.contains(where: { resolvedLength($0) != 0 }) {
            fields.append(entry("padding.text"))
        }

        let border = declared.border
        if [border.top, border.right, border.bottom, border.left].contains(where: { !isZero(.length($0)) }) {
            fields.append(entry("border"))
        }
        if declared.position != .static { fields.append(entry("position")) }
        if declared.inset != Edges(all: .auto) { fields.append(entry("inset")) }
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
/// §3 item 2): at most the item frame W and the alignment frame, innermost first.
/// Lane 1 plans the cross axis only.
struct LegacyItemPlan {
    /// W's bounds per axis — `(minimum, maximum)` — on each axis it is greedy on;
    /// `nil` on an axis it hugs. W is registered when either axis is set.
    var itemFrameWidth: (min: Double, max: Double)?
    var itemFrameHeight: (min: Double, max: Double)?
    var itemFrameAlignment: ProposalAlignment = .topLeading
    /// The alignment frame: greedy on one axis (`horizontal` for a column parent's
    /// cross axis), placing the child by `factor` there.
    var alignmentFrame: (horizontal: Bool, factor: Double)?
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
    /// **declared** style is `parent`, and appends — in child order, each child's in
    /// `LR-AQ`'s field order — the item fields this stage cannot lower yet, at the
    /// child's own site (spec §4's report order: after the container's own rows).
    /// `received[i]` is `nil` for a child no legacy site recorded (a proposal
    /// element), which gets no wrapper.
    ///
    /// **Stretch** (ruling LR-AC): a child whose cross size is `auto` and whose
    /// effective alignment — `alignSelf`, else the parent's `alignItems` (a stack
    /// parent: `justifyItems` horizontally, `alignItems` vertically) — is `nil` or
    /// `.stretch` gets W greedy on that axis, **unless the parent has exactly one
    /// child and no declared size on that axis** (the elision; stage 1's `LR-E`
    /// principle 3). W carries the child's own `minSize`/`maxSize` on that axis from
    /// its animated style (`LR-AG`, `LR-AS`), a minimum of **0** when none is
    /// declared — CSS's stretched size is the line even below the content (`LR-AW`)
    /// — and is aligned by the child's content alignment. A `.frame` layer child is
    /// stretched the same way on an axis its frame leaves `nil` (`MC-Q` finding 7).
    ///
    /// **`alignSelf`** in a flex parent (ruling LR-AD): where the child is not
    /// stretched and its alignment factor (`.stretch` and `.baseline` place at the
    /// start) differs from the parent's, an alignment frame greedy on the cross axis
    /// places it — in a one-child container too (`LR-AR`). A stack parent ignores
    /// `alignSelf`, as the legacy stack does.
    ///
    /// **The free-space re-check** (ruling LR-AR, the stretch half): a child flex
    /// container that W makes greedy on its own **main** axis, with no declared main
    /// size and `justifyContent` `space-*`, reports `justifyContent.<case>` at its
    /// site.
    ///
    /// **Reported, lane 1** (a flex parent): `flexGrow`, `flexShrink`, `flexBasis`
    /// (lane 2), `alignSelf.baseline` (task 11), `minSize`/`maxSize` anywhere but a
    /// stretched axis, or a percentage there (lanes 2 and 4), `margin` (lane 4). A
    /// stack parent reports only `minSize`/`maxSize` off a stretched axis and
    /// `margin`. A `.frame` layer child reports nothing: its item fields are its own
    /// frame's.
    func planLegacyItems(_ received: [LoweredItem?], parent: Style, parentKind: LoweredItem.Kind,
                         fields: inout [UnlowerableField]) -> [LegacyItemPlan] {
        let single = received.count == 1
        var plans: [LegacyItemPlan] = []
        for item in received {
            var plan = LegacyItemPlan()
            guard let item else {
                plans.append(plan)
                continue
            }
            let d = item.declared, a = item.animated
            func stretches(_ value: AlignItems?) -> Bool { value == nil || value == .stretch }
            // Whether the child is stretched on each axis.
            var horizontal = false, vertical = false
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
                if isRow { vertical = stretched } else { horizontal = stretched }
                if item.kind != .frameLayer {
                    if d.flexGrow != 0 { reports.append("flexGrow") }
                    if d.flexShrink != 1 { reports.append("flexShrink") }
                    if d.flexBasis != .auto { reports.append("flexBasis") }
                    if d.alignSelf == .baseline { reports.append("alignSelf.baseline") }
                }
                if !stretched {
                    let parentFactor = alignmentFactor(parent.alignItems)
                    let childFactor = d.alignSelf.map(alignmentFactor) ?? parentFactor
                    if childFactor != parentFactor {
                        plan.alignmentFrame = (horizontal: !isRow, factor: childFactor)
                    }
                }
            case .stack, .leaf, .frameLayer:
                horizontal = alignsByStretching(parent.justifyItems) && d.size.width == .auto
                    && !(single && parent.size.width == .auto)
                vertical = stretches(parent.alignItems) && d.size.height == .auto
                    && !(single && parent.size.height == .auto)
            }
            if item.kind != .frameLayer {
                func reported(_ size: Size<Dimension>) -> Bool {
                    (size.width != .auto && !(horizontal && !isPercent(size.width)))
                        || (size.height != .auto && !(vertical && !isPercent(size.height)))
                }
                if reported(d.minSize) { reports.append("minSize") }
                if reported(d.maxSize) { reports.append("maxSize") }
                if LoweredItem.hasMargin(d) { reports.append("margin") }
            }
            if case .flex(let childIsRow) = item.kind,
               childIsRow ? horizontal : vertical,
               (childIsRow ? d.size.width : d.size.height) == .auto {
                switch d.justifyContent {
                case .spaceBetween?: reports.append("justifyContent.spaceBetween")
                case .spaceAround?: reports.append("justifyContent.spaceAround")
                case .spaceEvenly?: reports.append("justifyContent.spaceEvenly")
                case nil, .flexStart?, .center?, .flexEnd?: break
                }
            }
            fields += reports.map { UnlowerableField(site: item.site, field: $0) }

            func bounds(_ minimum: Dimension, _ maximum: Dimension) -> (min: Double, max: Double) {
                let lo = resolvedDimension(minimum) ?? 0
                return (lo, Swift.max(lo, Swift.max(0, resolvedDimension(maximum) ?? .infinity)))
            }
            if horizontal { plan.itemFrameWidth = bounds(a.minSize.width, a.maxSize.width) }
            if vertical { plan.itemFrameHeight = bounds(a.minSize.height, a.maxSize.height) }
            plan.itemFrameAlignment = item.contentAlignment
            plans.append(plan)
        }
        return plans
    }

    /// Registers each child's planned wrappers, innermost first, aliasing the child's
    /// node to its item frame (ruling LR-AB item 3), and returns the nodes the
    /// container registers in the children's place.
    func registerLegacyItems(_ children: [LayoutNodeID], _ plans: [LegacyItemPlan]) -> [LayoutNodeID] {
        var nodes: [LayoutNodeID] = []
        for (child, plan) in zip(children, plans) {
            var node = child
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
}
