import MetalUICore
import MetalUILayout

// Overlays and coordinates (C15), lane B — SwiftUI's `PopoverAttachmentAnchor`
// on `.popover` (ruling `OV-B`, divergence 225) and the MetalUI-only
// `anchoredOverlay` (rulings `OV-A`, `OV-K`, `OV-N`; spec
// `docs/superpowers/specs/2026-10-10-overlays-coords-design.md` §2.1, §3.2).
// SwiftUI's side is `docs/probes/swiftui-overlays-coords.swift`, arms A0–A7
// and B0–B2, and `docs/probes/swiftui-overlays-coords-typecheck.sh` T11–T15;
// gpui's is `anchored()` with `on_mouse_down_out`.

/// Where a popover attaches to the element that declares it — SwiftUI's
/// `PopoverAttachmentAnchor` (ruling `OV-B`; probe arms A1–A7, T11–T13).
///
/// `.rect(.bounds)`, the default, is the declarer's bounds; `.rect(.rect(r))`
/// is `r` in the **declarer's own space** (its top-leading corner at the
/// origin); `.point(p)` is a zero-size rect at the unit point `p` of the
/// declarer's bounds. The popover is placed against the resolved rect exactly
/// as against the bounds: on its arrow edge's side, 8 points away, centred
/// along the other axis, flipped then clamped inside the window (divergence
/// 111). **Divergence 225**: SwiftUI's rect source is `Anchor<CGRect>.Source`;
/// MetalUI has no `Anchor`, so `Source` is a nested struct and the rect a
/// `Bounds<Pixels>`. `Sendable` and `Hashable` are additive conformances
/// (`OV-L`): every payload is a value.
public enum PopoverAttachmentAnchor: Sendable, Hashable {
    /// A rect in the declarer's space: `.rect(.bounds)` or `.rect(.rect(r))`.
    case rect(Source)
    /// A zero-size rect at a unit point of the declarer's bounds.
    case point(UnitPoint)

    /// The rect a `.rect` attachment anchor names — SwiftUI's
    /// `Anchor<CGRect>.Source` (divergence 225).
    public struct Source: Sendable, Hashable {
        /// The rect in the declarer's space, or `nil` for its bounds.
        let rect: Bounds<Pixels>?

        /// The declarer's bounds.
        public static var bounds: Source { Source(rect: nil) }

        /// `r`, in the declarer's own space: its origin is the declarer's
        /// top-leading corner.
        public static func rect(_ r: Bounds<Pixels>) -> Source { Source(rect: r) }
    }

    /// The window rect this anchor names for a declarer at `bounds` (window
    /// points): a zero-size rect for a point.
    func resolve(in bounds: Bounds<Pixels>) -> Bounds<Pixels> {
        let x = bounds.origin.x.value, y = bounds.origin.y.value
        switch self {
        case .rect(let source):
            guard let r = source.rect else { return bounds }
            return Bounds(origin: Point(x: Pixels(x + r.origin.x.value), y: Pixels(y + r.origin.y.value)),
                          size: r.size)
        case .point(let unit):
            return Bounds(origin: Point(x: Pixels(x + Float(unit.x) * bounds.size.width.value),
                                        y: Pixels(y + Float(unit.y) * bounds.size.height.value)),
                          size: Size(width: Pixels(0), height: Pixels(0)))
        }
    }
}

extension StyledElement {
    /// Presents `content` with its `anchor` unit point at `point` while
    /// `isPresented` is `true` — **MetalUI-only** (ruling `OV-A`; gpui's
    /// `anchored()` with `on_mouse_down_out`): a command palette at the
    /// pointer, a node editor's inline menu.
    ///
    /// **No chrome**: no panel, border, shadow or padding — the content's own
    /// box is the overlay's (SwiftUI's `.presentationBackground(.clear)` keeps
    /// the macOS popover's frame, probe arm B1, so no SwiftUI spelling carries
    /// this).
    ///
    /// **Placement** (`OV-A` item 2, `OV-K`, `OV-N`): `point` is read fresh at
    /// each layout in `space` — `.local` is this element's own space, render
    /// effects included (the space `onContinuousHover` and gestures report
    /// `.local` in); `.global` the window's content space; `.named(n)` the
    /// nearest ancestor declaring `n` (`.global` when none does). The content
    /// is measured at its ideal size, capped at the window; on each axis, if it
    /// would leave the window, the mirrored unit point is used when the content
    /// then fits (gpui's `SwitchAnchor`); then it is clamped inside the
    /// window, with no margin. A point written with the binding is drawn there
    /// in the frame presenting the write; a resize re-places it. Only a
    /// `.local` or `.named` overlay whose declarer has not yet been laid out
    /// waits one frame for its space (`OV-S`).
    ///
    /// **Dismissal** (`OV-A` item 3): a press of any button outside every open
    /// popover and overlay writes `isPresented` `false` from input and then
    /// reaches what it lands on — a field it focuses, a slider it writes, a
    /// context menu it opens, **this element itself** (unlike `.popover`, a
    /// press on the declarer is not consumed). Escape with no modifiers
    /// dismisses the topmost, even while a field inside it is focused. A press,
    /// wheel or drop on the overlay never reaches what lies beneath it; keys
    /// reach a focused field inside it.
    ///
    /// Like `.popover`: a presentation on a higher layer, laid out against the
    /// window, published as a `.popover` node; its content's `@State` starts
    /// fresh at each presentation (`ID-C`); one identity level, for its caller
    /// only (`PopoverModifier`).
    public func anchoredOverlay<P: ElementGroup>(isPresented: Binding<Bool>, at point: Point<Pixels>,
                                                 in space: CoordinateSpace = .local,
                                                 anchor: UnitPoint = .topLeading,
                                                 @ElementBuilder content: @escaping @MainActor () -> P)
        -> PopoverModifier<Self, P> {
        PopoverModifier(content: self, kind: .overlay(point: point, space: space, anchor: anchor),
                        presented: presenting(isPresented, content), dismiss: { isPresented.wrappedValue = false })
    }

    /// `anchoredOverlay(isPresented:at:in:anchor:content:)` presenting
    /// `item`'s content while it is non-`nil`: a different item's id starts
    /// its content fresh (`ID-R`); dismissal writes `nil`.
    public func anchoredOverlay<Item: Identifiable, P: ElementGroup>(item: Binding<Item?>, at point: Point<Pixels>,
                                                                     in space: CoordinateSpace = .local,
                                                                     anchor: UnitPoint = .topLeading,
                                                                     @ElementBuilder content: @escaping @MainActor (Item) -> P)
        -> PopoverModifier<Self, P> {
        PopoverModifier(content: self, kind: .overlay(point: point, space: space, anchor: anchor),
                        presented: presenting(item, content), dismiss: { item.wrappedValue = nil })
    }
}

extension ProposalElementGroup {
    /// `StyledElement.anchoredOverlay(isPresented:at:in:anchor:content:)` on
    /// the proposal path: the same wrapper, one identity level.
    public func anchoredOverlay<P: ElementGroup>(isPresented: Binding<Bool>, at point: Point<Pixels>,
                                                 in space: CoordinateSpace = .local,
                                                 anchor: UnitPoint = .topLeading,
                                                 @ElementBuilder content: @escaping @MainActor () -> P)
        -> PopoverModifier<Self, P> {
        PopoverModifier(content: self, kind: .overlay(point: point, space: space, anchor: anchor),
                        presented: presenting(isPresented, content), dismiss: { isPresented.wrappedValue = false })
    }

    /// `StyledElement.anchoredOverlay(item:at:in:anchor:content:)` on the
    /// proposal path.
    public func anchoredOverlay<Item: Identifiable, P: ElementGroup>(item: Binding<Item?>, at point: Point<Pixels>,
                                                                     in space: CoordinateSpace = .local,
                                                                     anchor: UnitPoint = .topLeading,
                                                                     @ElementBuilder content: @escaping @MainActor (Item) -> P)
        -> PopoverModifier<Self, P> {
        PopoverModifier(content: self, kind: .overlay(point: point, space: space, anchor: anchor),
                        presented: presenting(item, content), dismiss: { item.wrappedValue = nil })
    }
}
