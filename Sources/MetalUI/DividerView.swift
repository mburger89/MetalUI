import MetalUICore
import MetalUILayout

// Platform services, lane 3 — `Divider()` as a view (ruling `SV-O`; spec
// §4.3). The declaration is `MenuContent.swift`'s (a menu separator, `MN-H`
// item 3); this file makes the same type an element. SwiftUI's side is
// `docs/probes/swiftui-platform-services.swift`, arms `V1`–`V15`.

/// `Divider` in an element builder: a native leaf **1 point across** the
/// nearest enclosing linear stack's axis and its proposal along it (`SV-O`
/// items 2–3; `V1`–`V11`):
///
/// - vertical — 1 wide, the proposed height tall — inside an `HStack` or a
///   legacy `Row`;
/// - horizontal — 1 tall, the proposed width wide — inside a `VStack` or a
///   `Column`, and **outside any stack** (a `ZStack` and a `Grid` are no
///   stack, `V3`, `V4`); every other wrapper (`.frame`, `.padding`, an
///   environment scope) is transparent;
/// - 10 long with no proposal along its length (`V3`, `V7`'s nil arm) —
///   otherwise greedy, so a `Divider` in an `HStack` makes the stack fill the
///   proposed height (`V7`).
///
/// It paints one rect of the theme's `.separator` token, resolved through the
/// element's scheme (divergence 127: SwiftUI's is black or white at α 0.098,
/// `V12`), registers no handler and publishes no accessibility node (`V15`).
/// The axis is read from `Frame`'s stack-axis stack at the layout request —
/// a new linear container pushes its axis around its children's request.
extension Divider: Element, ProposalElement {
    /// The layout a `Divider` keeps: its leaf node.
    public struct Layout { var node: LayoutNodeID }

    public mutating func requestProposalLayout(_ id: GlobalElementID,
                                               pass: inout LayoutPass) -> (ProposalNodeID, Layout) {
        let vertical = pass.frame.stackAxis == .horizontal
        let node = pass.requestNativeLeaf { Self.measurement(for: $0, vertical: vertical) }
        return (node, Layout(node: node.layoutNodeID))
    }

    /// 1 across, the proposal (or 10) along (`SV-O` item 3).
    nonisolated static func measurement(for proposal: ProposedSize, vertical: Bool) -> LayoutMeasurement {
        vertical
            ? LayoutMeasurement(size: SizeD(width: 1, height: proposal.height ?? 10))
            : LayoutMeasurement(size: SizeD(width: proposal.width ?? 10, height: 1))
    }

    public mutating func prepaint(_ id: GlobalElementID, bounds: Bounds<Pixels>,
                                  layout: inout Layout, pass: inout PrepaintPass) {}

    /// One rect of `.separator` over the leaf's bounds (`SV-O` item 4).
    public mutating func paint(_ id: GlobalElementID, bounds: Bounds<Pixels>,
                               layout: inout Layout, prepaint: inout Void, pass: inout PaintPass) {
        pass.fill(bounds, color: pass.resolve(Color(.separator)), cornerRadii: Corners(all: Pixels(0)))
    }
}
