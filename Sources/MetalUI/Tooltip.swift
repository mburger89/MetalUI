import MetalUICore
import MetalUILayout
import MetalUIPlatform

// Menus, popovers and tooltips, lane 3 — `.help` and the drawn tooltip
// (rulings `MN-P`, `MN-U`, `MN-V` item 3; spec §3.10).

/// A tooltip on screen: its text and panel in window points.
struct VisibleTooltip: Equatable {
    let text: String
    let frame: Bounds<Pixels>
}

/// Where a tooltip goes (`MN-P` item 2) — pure.
enum TooltipPlacement {
    /// Below the pointer, so the cursor does not cover it.
    static let below: Float = 18
    /// The margin a tooltip keeps from the window's edges.
    static let margin: Float = 4

    /// The tooltip's origin for a panel of `size` with the pointer at
    /// `pointer` in a `window`-sized window.
    static func origin(pointer: Point<Pixels>, size: Size<Pixels>, window: Size<Pixels>) -> Point<Pixels> {
        Point(x: Pixels(0), y: Pixels(0))
    }
}

extension StyledElement {
    /// Explains this element — SwiftUI's `help(_:)` (ruling `MN-P`).
    public func help(_ text: String) -> Self { self }
}

extension ProposalElementGroup {
    /// `StyledElement.help(_:)` on the proposal path.
    public func help(_ text: String) -> ContextualModifier<Self> {
        ContextualModifier(content: self, attachment: ContextualAttachment(menu: nil, help: nil))
    }
}

extension Window {
    /// The open popovers the last frame registered, in registration order.
    var lastOpenPopovers: [OpenPopover] { [] }
    /// The tooltip on screen, if any.
    var visibleTooltip: VisibleTooltip? { nil }
}
