import MetalUICore

/// A pointer (cursor) shape at the platform seam (ruling `CI-H` item 8): the
/// kinds MetalUI's `PointerStyle` lowers to, with no SwiftUI type crossing the
/// seam. `Window` hands one to `PlatformWindow.setPointerStyle(_:)` only when
/// the resolved style changes. AppKit maps each to the `NSCursor` the probe
/// `swiftui-input-apis.swift` read (`P1`–`P19`); SDL to a system cursor, with
/// both hands as its move cursor and both zooms as its default (SDL has no
/// hand or zoom cursor — a documented platform constraint).
public enum PlatformPointerStyle: Sendable, Hashable {
    /// The arrow: SwiftUI's `.default`.
    case arrow
    /// The horizontal text I-beam: `.horizontalText`.
    case iBeam
    /// The vertical text I-beam: `.verticalText`.
    case verticalIBeam
    /// The crosshair: `.rectSelection`.
    case crosshair
    /// The open hand: `.grabIdle`.
    case openHand
    /// The closed hand: `.grabActive`.
    case closedHand
    /// The pointing hand: `.link`.
    case pointingHand
    /// The left-right resize: `.columnResize`.
    case columnResize
    /// The up-down resize: `.rowResize`.
    case rowResize
    /// The magnifying glass with a plus: `.zoomIn`.
    case zoomIn
    /// The magnifying glass with a minus: `.zoomOut`.
    case zoomOut
    /// A window-frame resize at `edge`, the arrows showing the directions the
    /// edge can move: `inward`, `outward`, or both (both when neither is set).
    case frameResize(edge: PlatformResizeEdge, inward: Bool, outward: Bool)
}

/// An edge or corner of a resizable frame (ruling `CI-H` item 8), in the
/// layout direction: `leading` is the left in a left-to-right layout.
public enum PlatformResizeEdge: Sendable, Hashable {
    /// The top edge.
    case top
    /// The leading edge.
    case leading
    /// The bottom edge.
    case bottom
    /// The trailing edge.
    case trailing
    /// The top-leading corner.
    case topLeading
    /// The top-trailing corner.
    case topTrailing
    /// The bottom-leading corner.
    case bottomLeading
    /// The bottom-trailing corner.
    case bottomTrailing
}
