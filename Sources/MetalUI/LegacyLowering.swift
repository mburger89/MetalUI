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
            plans = planLegacyItems(received, parent: declared, parentKind: .stack, parentSite: .modifierLayer,
                                    fields: &fields)
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
    /// stack, the container's main factor and the stack's spacing.
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
        -> (nodes: [LayoutNodeID], mainFactor: Double, spacing: Double) {
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
        return (nodes, legacyMainFactor(animated), spacing)
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
            case .stack, .leaf, .frameLayer:
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
                case .stack, .leaf, .frameLayer:
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
