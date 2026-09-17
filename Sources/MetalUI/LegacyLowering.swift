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
// linear stack. A `display: .stack` container still reports `(site, "noLowering")`
// until lane 4.

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
    /// `legacyContainerDiagnostics`, before anything is registered. The children
    /// may be native nodes of any origin — a lowered legacy element or a proposal
    /// element such as an `HStack` — because under this authority every node is
    /// native (ruling LR-T).
    ///
    /// A `display: .stack` container still reports `(site, "noLowering")`: the
    /// overlay lowering is lane 4's.
    func lowerLegacyNode(_ style: Style, declared: Style, children: [LayoutNodeID],
                         site: LoweringSite) -> LayoutNodeID {
        guard !children.isEmpty else {
            return lowerLegacyLeaf(style, declared: declared, site: site) {
                frame.requestNativeLeaf { _ in LayoutMeasurement(size: SizeD(width: 0, height: 0)) }
            }
        }
        let fields = legacyContainerDiagnostics(declared, childCount: children.count, site: site)
        if !fields.isEmpty { return report(fields) }

        let isRow = style.flexDirection.isRow
        let main = alignmentFactor(style.justifyContent)
        let cross = alignmentFactor(style.alignItems)
        // `Axes.horizontal` is the gap between a row's items, `vertical` between a
        // column's (CSS `column-gap` / `row-gap`); the cross-axis gap separates
        // lines, and a no-wrap container has one.
        let spacing = resolvedLength(isRow ? style.gap.horizontal : style.gap.vertical)
        // The stack reads only the cross-axis factor of its alignment.
        let stack = frame.requestNativeLinearStack(
            children: children, axis: isRow ? .horizontal : .vertical, spacing: spacing,
            alignment: isRow ? proposalAlignment(horizontal: 0, vertical: cross)
                             : proposalAlignment(horizontal: cross, vertical: 0))
        return paddedAndSized(stack, style,
                              alignment: isRow ? proposalAlignment(horizontal: main, vertical: cross)
                                               : proposalAlignment(horizontal: cross, vertical: main))
    }

    /// The container table's "otherwise" column (spec §5.4, **containers**), then
    /// the **every node** table's (`legacyLeafDiagnostics`), for a container's
    /// **declared** style with `childCount` layout children. `display: none` is
    /// checked first and alone (ruling LR-J); a `display: .stack` container reports
    /// `noLowering` alone (lane 4). The container rows, in order:
    ///
    /// - `reverse` — `.rowReverse`/`.columnReverse`;
    /// - `gap.percent` — a percentage **main-axis** gap (the cross-axis gap is read
    ///   by nothing on a single line, so it is not reported);
    /// - `alignItems.baseline`;
    /// - `alignItems.stretch` — `nil`/`.stretch` (a `Box`'s default) unless there is
    ///   no free cross space for it to show: exactly one child **and** no declared
    ///   cross-axis size (ruling LR-E principle 3);
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
        if declared.display == .stack { return [entry("noLowering")] }
        var fields: [UnlowerableField] = []
        let isRow = declared.flexDirection.isRow
        if declared.flexDirection.isReverse { fields.append(entry("reverse")) }
        if case .percent = isRow ? declared.gap.horizontal : declared.gap.vertical {
            fields.append(entry("gap.percent"))
        }
        let crossSize = isRow ? declared.size.height : declared.size.width
        let mainSize = isRow ? declared.size.width : declared.size.height
        switch declared.alignItems {
        case .baseline:
            fields.append(entry("alignItems.baseline"))
        case nil, .stretch:
            if childCount != 1 || crossSize != .auto { fields.append(entry("alignItems.stretch")) }
        case .flexStart, .center, .flexEnd:
            break
        }
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
    /// the node is a 0×0 native leaf.
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
        if !fields.isEmpty { return report(fields) }
        return paddedAndSized(content(), style, alignment: .topLeading)
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

        let auto = Size<Dimension>(width: .auto, height: .auto)
        if declared.minSize != auto { fields.append(entry("minSize")) }
        if declared.maxSize != auto { fields.append(entry("maxSize")) }
        let margin = declared.margin
        if [margin.top, margin.right, margin.bottom, margin.left].contains(where: { !isZero($0) }) {
            fields.append(entry("margin"))
        }
        let border = declared.border
        if [border.top, border.right, border.bottom, border.left].contains(where: { !isZero(.length($0)) }) {
            fields.append(entry("border"))
        }
        if declared.position != .static { fields.append(entry("position")) }
        if declared.inset != Edges(all: .auto) { fields.append(entry("inset")) }
        if declared.flexGrow != 0 { fields.append(entry("flexGrow")) }
        if declared.flexShrink != 1 { fields.append(entry("flexShrink")) }
        if declared.flexBasis != .auto { fields.append(entry("flexBasis")) }
        if declared.alignSelf != nil { fields.append(entry("alignSelf")) }
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
