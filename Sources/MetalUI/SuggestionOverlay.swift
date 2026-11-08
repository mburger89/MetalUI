import MetalUICore
import MetalUILayout

// The suggestion overlay (ruling prefix `SOC-`; decisions
// `docs/superpowers/2026-11-07-suggestion-overlay-decisions.md`): a list anchored to a text
// field that never takes focus or keys. MetalUI-only (class `M`). It reuses the popover's
// presentation root (`AnchoredPresentation`, `PopoverModifier`) with three differences from
// `.popover` and `anchoredOverlay`: it is not in the window's dismissal stack (`MN-N`,
// `MN-Y`, `OV-A` item 3: no outside press and no Escape dismisses it), it publishes no
// `.popover` accessibility node (so it is a sibling group, not a modal one), and it is
// placed by `SuggestionPlacement` against the anchor's frame.

/// A vertical edge of a view — SwiftUI's `VerticalEdge`: `.top` or `.bottom`.
public enum VerticalEdge: Sendable, Hashable {
    /// The top edge.
    case top
    /// The bottom edge.
    case bottom
}

extension StyledElement {
    /// Shows `content` beside this element, on `edge`, while `isPresented` is `true`, without
    /// taking focus or keys — MetalUI-only (ruling `SOC-A`). The use is a chat composer's
    /// slash-command or `@file` list over its `TextField`: the user keeps typing, and the app
    /// moves its own selection from `.onKeyPress` on the field.
    ///
    /// **It is not a popover.** A popover takes Escape before the keymap and dismisses on any
    /// outside press (`MN-N`); this takes no key at all (`SOC-B`). Focus stays where it is, so
    /// the field keeps the caret and every key reaches it first: `↑ ↓ Return Tab Esc` are the
    /// app's to route with `onKeyPress` on the field (return `.handled` to consume, `.ignored`
    /// to let the field type), and nothing else is intercepted. **Nothing dismisses it but the
    /// app**: the binding is read, never written. An outside click, Escape or the field losing
    /// focus leaves it shown; the app writes `isPresented` (from `onKeyPress`, `onChange`,
    /// `onSubmit`, a tap on a row).
    ///
    /// **Input** (`SOC-C`): it is a layer above the window's content, so a press, wheel or drop
    /// on it never reaches what lies beneath, and a press on it neither moves focus nor blurs
    /// the focused field (`Window.focus` moves only for a control or `.focusable()` that
    /// takes the press; a row that is a `Button` or an `onTapGesture` does not focus). Rows
    /// are ordinary views: a `Button` or tap runs its action; a `ScrollView` scrolls under the
    /// wheel.
    ///
    /// **Placement** (`SOC-A`): `spacing` away from this element's frame in window points on
    /// `edge`'s side, its `alignment` edge flush with the field's (`.leading`, `.center`,
    /// `.trailing`), measured at its ideal size capped at the window. If it does not fit on
    /// `edge`'s side it moves to the other side when it fits there; when it fits on neither it
    /// takes the side with more room and is capped to it, so a `ScrollView` inside scrolls. It
    /// is then clamped horizontally inside the window. No chrome: the content draws its own
    /// background, border and shadow. Like `.popover` it appears on the frame after this
    /// element was first laid out and follows it within a frame when it moves.
    ///
    /// **Accessibility** (`SOC-D`): the content's nodes are exposed as ordinary siblings of the
    /// window's tree, not as a modal popover. Its `@State` starts fresh at each presentation
    /// (`ID-C`). One identity level, for its caller only (`PopoverModifier`).
    public func suggestionOverlay<P: ElementGroup>(isPresented: Binding<Bool>,
                                                   edge: VerticalEdge = .top,
                                                   alignment: HorizontalAlignment = .leading,
                                                   spacing: Pixels = Pixels(4),
                                                   @ElementBuilder content: @escaping @MainActor () -> P)
        -> PopoverModifier<Self, P> {
        PopoverModifier(content: self, kind: .suggestion(edge: edge, alignment: alignment, spacing: spacing.value),
                        presented: presenting(isPresented, content), dismiss: {})
    }
}

extension ProposalElementGroup {
    /// `StyledElement.suggestionOverlay(isPresented:edge:alignment:spacing:content:)` on the
    /// proposal path: the same wrapper, one identity level.
    public func suggestionOverlay<P: ElementGroup>(isPresented: Binding<Bool>,
                                                   edge: VerticalEdge = .top,
                                                   alignment: HorizontalAlignment = .leading,
                                                   spacing: Pixels = Pixels(4),
                                                   @ElementBuilder content: @escaping @MainActor () -> P)
        -> PopoverModifier<Self, P> {
        PopoverModifier(content: self, kind: .suggestion(edge: edge, alignment: alignment, spacing: spacing.value),
                        presented: presenting(isPresented, content), dismiss: {})
    }
}

/// Where a suggestion overlay goes (`SOC-A`): the placement rule as a pure function, and the
/// custom layout that applies it.
struct SuggestionPlacement: ProposalLayout {
    let anchor: Bounds<Pixels>
    let edge: VerticalEdge
    let alignment: HorizontalAlignment
    let spacing: Float
    let window: Size<Pixels>

    /// The window: a presentation root is window-sized.
    func sizeThatFits(proposal: ProposedSize, subviews: MeasurementSubviews) -> LayoutMeasurement {
        LayoutMeasurement(size: SizeD(width: Double(window.width.value), height: Double(window.height.value)))
    }

    func placeSubviews(in bounds: LayoutRect, proposal: ProposedSize, subviews: PlacementSubviews) {
        guard let child = subviews.first else { return }
        let (size, capped) = PopoverPlacement.measure(child, maxWidth: Double(window.width.value),
                                                      maxHeight: Double(window.height.value))
        let placed = Self.place(anchor: anchor, size: size, edge: edge, alignment: alignment,
                                spacing: spacing, window: window)
        var proposed = capped
        if placed.size.height.value < size.height.value {
            // Neither side held it: re-measured at the room the better side has.
            proposed = ProposedSize(width: capped.width, height: Double(placed.size.height.value))
        }
        child.place(at: Point(x: bounds.x + Double(placed.origin.x.value), y: bounds.y + Double(placed.origin.y.value)),
                    anchor: .topLeading, proposal: proposed)
    }

    /// The overlay's origin and size for content of `size` against `anchor` in a
    /// `window`-sized window. Vertically: `spacing` off the anchor on `edge`'s side; the other
    /// side when `edge`'s does not hold the whole height and the other does; when neither does,
    /// the side with more room, the height capped to that room. Horizontally: `alignment`'s
    /// edge flush with the anchor's, clamped inside the window.
    static func place(anchor: Bounds<Pixels>, size: Size<Pixels>, edge: VerticalEdge,
                      alignment: HorizontalAlignment, spacing: Float,
                      window: Size<Pixels>) -> (origin: Point<Pixels>, size: Size<Pixels>) {
        let minX = anchor.origin.x.value, minY = anchor.origin.y.value
        let maxY = minY + anchor.size.height.value
        let w = size.width.value, h = size.height.value
        let W = window.width.value, H = window.height.value
        let roomAbove = max(0, minY - spacing)
        let roomBelow = max(0, H - (maxY + spacing))
        var side = edge
        var height = h
        if (edge == .top ? roomAbove : roomBelow) < h {
            // It does not fit on `edge`'s side: the side with more room. When the other side
            // holds it that is the flip; when neither does the height is capped to the room.
            side = roomAbove >= roomBelow ? .top : .bottom
            height = min(h, side == .top ? roomAbove : roomBelow)
        }
        let y = side == .top ? minY - spacing - height : maxY + spacing
        let x: Float
        switch alignment {
        case .leading: x = minX
        case .center: x = minX + (anchor.size.width.value - w) / 2
        case .trailing: x = minX + anchor.size.width.value - w
        }
        let clampedX = max(0, min(x, W - w))
        return (Point(x: Pixels(clampedX), y: Pixels(y)), Size(width: Pixels(w), height: Pixels(height)))
    }
}
