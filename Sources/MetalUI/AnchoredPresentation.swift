import MetalUICore
import MetalUILayout

// Menus, popovers and tooltips, lane 3 — the anchored presentation a popover
// is drawn through (rulings `MN-M`, `MN-N` item 4, `MN-Z`; spec §3.7).
// `Deferred`'s three halves — the scroll context withheld in layout, the
// layer, clip and offset reset in prepaint and paint — with its own lowering:
// a presentation root laid out against the window, placed against an anchor.
// `Deferred` itself is unchanged (`MN-M` item 1).

/// An open popover as a frame registered it (spec §3.7): the declaring
/// wrapper's id, the chrome's bounds and the anchor's, in window points, and
/// how to dismiss it from input. Frame-scoped, never `StateTable`.
struct OpenPopover {
    let id: GlobalElementID
    let bounds: Bounds<Pixels>
    let anchor: Bounds<Pixels>
    let dismiss: @MainActor () -> Void
}

/// A popover's chrome hoisted above everything and placed against `anchor`
/// (`MN-M`): what a `PopoverModifier`'s slot holds while presented. It paints
/// the chrome's panel under its content (`MN-M` item 5).
///
/// **Its layout meaning.** The chrome is lowered into its own presentation
/// root — a `PopoverPlacement` custom layout, window-sized — queued in
/// `LoweringState.presentations` like a `Deferred` presentation's, so it is
/// laid out in its own native run before the frame's root against the window
/// (`LR-CM`). The chrome's `LoweredItem` is consumed here: its item fields have
/// no parent to act on (`LR-CK`'s footing). This element hands back a 0 × 0
/// placeholder aliased to the chrome's rect, which no container receives.
///
/// **Its prepaint** (`MN-Z`, `MN-N` item 4): inside `PrepaintPass.deferred`
/// (the root layer, the root clip, no scroller), a **raw opaque hitbox** at
/// the chrome's bounds — no handler, not focusable, publishing nothing — is
/// inserted **before** the content registers, so a press, wheel or drop on the
/// chrome's padding never reaches what lies beneath, and the content ranks
/// above it. Then the open-popover entry the window's dismissal stage reads.
struct AnchoredPresentation<Content: Element>: Element {
    var content: Content
    /// The declaring `PopoverModifier`'s id.
    let owner: GlobalElementID
    /// The anchor's bounds from the last completed frame, in window points.
    let anchor: Bounds<Pixels>
    let edge: Edge
    let dismiss: @MainActor () -> Void

    struct LayoutState {
        var content: Content.GroupLayout
    }

    mutating func requestLayout(_ id: GlobalElementID, pass: inout LayoutPass) -> (LayoutNodeID, LayoutState) {
        var cursor = 0
        let (nodes, contentLayout) = pass.withoutScrollContext {
            content.requestGroupLayout(under: id, at: &cursor, pass: &pass)
        }
        let node = nodes[0]
        let frame = pass.frame
        _ = frame.lowering.consume(node)
        let root = pass.lowerAnchoredPresentation(node, anchor: anchor, edge: edge)
        let placeholder = frame.requestNativeLeaf { _ in LayoutMeasurement(size: SizeD(width: 0, height: 0)) }
        frame.lowering.alias(placeholder, to: frame.lowering.alias(node))
        frame.lowering.presentations.append((placeholder: placeholder, root: root))
        return (placeholder, LayoutState(content: contentLayout))
    }

    mutating func prepaint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout LayoutState,
                           pass: inout PrepaintPass) -> Content.GroupPrepaint {
        var result: Content.GroupPrepaint!
        pass.deferred {
            let frame = pass.frame
            _ = frame.insertHitbox(bounds, id: id, opaque: true)   // `MN-Z`
            frame.registerOpenPopover(OpenPopover(id: owner, bounds: bounds,
                                                  anchor: frame.presentationAnchors[owner] ?? anchor,
                                                  dismiss: dismiss))
            result = content.prepaintGroup(layout: &layout.content, pass: &pass)
        }
        return result
    }

    mutating func paint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout LayoutState,
                        prepaint: inout Content.GroupPrepaint, pass: inout PaintPass) {
        pass.deferred {
            // The panel (`MN-M` item 5): one bordered rounded rect under the
            // default shadow, then the content on it.
            let frame = pass.frame
            frame.paintWithShadow(color: frame.theme[.shadow], radius: Pixels(PopoverChrome.shadowRadius),
                                  x: Pixels(0), y: Pixels(PopoverChrome.shadowY)) {
                frame.fill(bounds, color: frame.theme[.surface],
                           cornerRadii: Corners(all: Pixels(PopoverChrome.cornerRadius)),
                           borderColor: frame.theme[.separator], borderWidths: Edges(all: Pixels(1)))
            }
            content.paintGroup(layout: &layout.content, prepaint: &prepaint, pass: &pass)
        }
    }
}

extension LayoutPass {
    /// A popover's presentation root (`MN-M` item 1), beside
    /// `lowerPresentation`: a window-sized `PopoverPlacement` over `node`, the
    /// chrome — measured at a nil proposal (each axis capped at the window
    /// less 16) and placed against `anchor` in the same pass.
    func lowerAnchoredPresentation(_ node: LayoutNodeID, anchor: Bounds<Pixels>, edge: Edge) -> LayoutNodeID {
        let window = frame.contentSize
        return frame.requestNativeLayout(PopoverPlacement(anchor: anchor, edge: edge, window: window),
                                         children: [node])
    }
}

/// Where a popover goes (`MN-M` item 3): the placement rule as a pure
/// function, and the custom layout that applies it.
struct PopoverPlacement: ProposalLayout {
    /// The gap between the anchor and the popover (the arrow's room).
    static let gap: Float = 8
    /// The margin a popover keeps from the window's edges.
    static let margin: Float = 8

    let anchor: Bounds<Pixels>
    let edge: Edge
    let window: Size<Pixels>

    /// The window: a presentation root is window-sized.
    func sizeThatFits(proposal: ProposedSize, subviews: MeasurementSubviews) -> LayoutMeasurement {
        LayoutMeasurement(size: SizeD(width: Double(window.width.value), height: Double(window.height.value)))
    }

    func placeSubviews(in bounds: LayoutRect, proposal: ProposedSize, subviews: PlacementSubviews) {
        guard let child = subviews.first else { return }
        let maxWidth = Double(window.width.value - 2 * Self.margin)
        let maxHeight = Double(window.height.value - 2 * Self.margin)
        let ideal = child.sizeThatFits(ProposedSize()).size
        let capped = ProposedSize(width: ideal.width > maxWidth ? maxWidth : nil,
                                  height: ideal.height > maxHeight ? maxHeight : nil)
        let measured = capped == ProposedSize() ? ideal : child.sizeThatFits(capped).size
        let size = Size(width: Pixels(Float(min(measured.width, maxWidth))),
                        height: Pixels(Float(min(measured.height, maxHeight))))
        let origin = Self.origin(anchor: anchor, size: size, edge: edge, window: window)
        child.place(at: Point(x: bounds.x + Double(origin.x.value), y: bounds.y + Double(origin.y.value)),
                    anchor: .topLeading, proposal: capped)
    }

    /// The popover's origin for a chrome of `size` on `edge`'s side of
    /// `anchor` in a `window`-sized window: `gap` from the anchor on that
    /// side, centred on it along the other axis; flipped to the opposite side
    /// when it does not fit on its own (inside `margin`) and does there; then
    /// clamped inside the window with `margin`. `.leading` is left and
    /// `.trailing` right (left-to-right only).
    static func origin(anchor: Bounds<Pixels>, size: Size<Pixels>, edge: Edge, window: Size<Pixels>) -> Point<Pixels> {
        let minX = anchor.origin.x.value, minY = anchor.origin.y.value
        let maxX = minX + anchor.size.width.value, maxY = minY + anchor.size.height.value
        let w = size.width.value, h = size.height.value
        let W = window.width.value, H = window.height.value
        func before(_ start: Float, _ extent: Float) -> Float { start - gap - extent }
        func after(_ end: Float) -> Float { end + gap }
        var x = minX + (anchor.size.width.value - w) / 2
        var y = minY + (anchor.size.height.value - h) / 2
        switch edge {
        case .top, .bottom:
            let above = before(minY, h), below = after(maxY)
            let fitsAbove = above >= margin, fitsBelow = below + h <= H - margin
            if edge == .top {
                y = !fitsAbove && fitsBelow ? below : above
            } else {
                y = !fitsBelow && fitsAbove ? above : below
            }
        case .leading, .trailing:
            let left = before(minX, w), right = after(maxX)
            let fitsLeft = left >= margin, fitsRight = right + w <= W - margin
            if edge == .leading {
                x = !fitsLeft && fitsRight ? right : left
            } else {
                x = !fitsRight && fitsLeft ? left : right
            }
        }
        func clamp(_ value: Float, _ extent: Float, _ limit: Float) -> Float {
            max(margin, min(value, limit - margin - extent))
        }
        return Point(x: Pixels(clamp(x, w, W)), y: Pixels(clamp(y, h, H)))
    }
}
