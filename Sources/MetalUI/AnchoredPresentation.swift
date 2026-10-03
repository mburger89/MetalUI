import MetalUICore
import MetalUILayout

// Menus, popovers and tooltips, lane 3 — the anchored presentation a popover
// is drawn through (rulings `MN-M`, `MN-Z`; spec §3.7). Lane 3's red stub.

/// An open popover as a frame registered it (spec §3.7): the declaring
/// wrapper's id, the chrome's bounds and the anchor's, in window points, and
/// how to dismiss it from input. Frame-scoped, never `StateTable`.
struct OpenPopover {
    let id: GlobalElementID
    let bounds: Bounds<Pixels>
    let anchor: Bounds<Pixels>
    let dismiss: @MainActor () -> Void
}

/// Where a popover goes (`MN-M` item 3) — pure.
enum PopoverPlacement {
    /// The gap between the anchor and the popover (the arrow's room).
    static let gap: Float = 8
    /// The margin a popover keeps from the window's edges.
    static let margin: Float = 8

    /// The popover's origin for a chrome of `size` on `edge`'s side of
    /// `anchor` in a `window`-sized window.
    static func origin(anchor: Bounds<Pixels>, size: Size<Pixels>, edge: Edge, window: Size<Pixels>) -> Point<Pixels> {
        Point(x: Pixels(0), y: Pixels(0))
    }
}
