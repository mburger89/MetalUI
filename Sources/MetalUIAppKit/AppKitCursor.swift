#if os(macOS)
import AppKit
import MetalUIPlatform

/// The seam's pointer styles as AppKit cursors (ruling `CI-H` item 8), as the
/// probe `swiftui-input-apis.swift` read SwiftUI's `pointerStyle(_:)` setting
/// them (`P1`–`P10`, `P15`–`P19`).
///
/// **On macOS 14** the cursors macOS 15 added — `columnResize`, `rowResize`,
/// `zoomIn`, `zoomOut` and `frameResize(position:directions:)` — do not exist,
/// and each falls back (ruling `CI-X` item 2): column and row resizes and the
/// four edges to `resizeLeftRight`/`resizeUpDown` (or the one-way
/// `resizeLeft`…`resizeDown` when only one direction is allowed), the zooms
/// and the corners to the arrow.
enum AppKitCursor {
    /// The cursor for `style`.
    static func cursor(for style: PlatformPointerStyle) -> NSCursor {
        switch style {
        case .arrow: return .arrow
        case .iBeam: return .iBeam
        case .verticalIBeam: return .iBeamCursorForVerticalLayout
        case .crosshair: return .crosshair
        case .openHand: return .openHand
        case .closedHand: return .closedHand
        case .pointingHand: return .pointingHand
        case .columnResize:
            if #available(macOS 15, *) { return .columnResize }
            return .resizeLeftRight
        case .rowResize:
            if #available(macOS 15, *) { return .rowResize }
            return .resizeUpDown
        case .zoomIn:
            if #available(macOS 15, *) { return .zoomIn }
            return .arrow
        case .zoomOut:
            if #available(macOS 15, *) { return .zoomOut }
            return .arrow
        case .frameResize(let edge, let inward, let outward):
            if #available(macOS 15, *) {
                let mapped = frameResize(for: edge, inward: inward, outward: outward)
                return .frameResize(position: mapped.position, directions: mapped.directions)
            }
            return legacyFrameResize(edge: edge, inward: inward, outward: outward)
        }
    }

    /// The frame-resize table **as values** (ruling `CI-P` item 3): each edge
    /// at its natural AppKit position (`leading` → `.left`, `trailing` →
    /// `.right`, `topLeading` → `.topLeft`, …; probe `P9`, `P17`) and the
    /// directions as asked, both when neither is set. Compared as values by
    /// `appKitPointerStylesMapAsTheProbeMeasured`, because `NSCursor ==`
    /// compares images and with `.all` a position equals its opposite.
    @available(macOS 15, *)
    static func frameResize(for edge: PlatformResizeEdge, inward: Bool, outward: Bool)
        -> (position: NSCursor.FrameResizePosition, directions: NSCursor.FrameResizeDirection.Set) {
        let position: NSCursor.FrameResizePosition = switch edge {
        case .top: .top
        case .leading: .left
        case .bottom: .bottom
        case .trailing: .right
        case .topLeading: .topLeft
        case .topTrailing: .topRight
        case .bottomLeading: .bottomLeft
        case .bottomTrailing: .bottomRight
        }
        let directions: NSCursor.FrameResizeDirection.Set =
            inward == outward ? .all : (inward ? .inward : .outward)
        return (position, directions)
    }

    /// macOS 14's nearest cursor for a frame resize (ruling `CI-X` item 2).
    private static func legacyFrameResize(edge: PlatformResizeEdge, inward: Bool, outward: Bool) -> NSCursor {
        let both = inward == outward
        switch edge {
        case .leading: return both ? .resizeLeftRight : (inward ? .resizeRight : .resizeLeft)
        case .trailing: return both ? .resizeLeftRight : (inward ? .resizeLeft : .resizeRight)
        case .top: return both ? .resizeUpDown : (inward ? .resizeDown : .resizeUp)
        case .bottom: return both ? .resizeUpDown : (inward ? .resizeUp : .resizeDown)
        case .topLeading, .topTrailing, .bottomLeading, .bottomTrailing: return .arrow
        }
    }
}
#endif
