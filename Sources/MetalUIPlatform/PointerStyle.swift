import MetalUICore
import MetalUIScene

/// A pointer (cursor) shape at the platform seam (ruling `CI-H` item 8): the
/// kinds MetalUI's `PointerStyle` lowers to, with no SwiftUI type crossing the
/// seam. `Window` hands one to `PlatformWindow.setPointerStyle(_:)` only when
/// the resolved style changes. AppKit maps each to the `NSCursor` the probe
/// `swiftui-input-apis.swift` read (`P1`–`P19`); SDL to a system cursor, with
/// both hands as its move cursor and both zooms as its default (SDL has no
/// hand or zoom cursor — a documented platform constraint).
///
/// **The image cursor is the `.image` case** (`IC-A`, which `CI-AC` foretold):
/// `PointerStyle.image(_:hotSpot:)` lowers to it, so an outside `PlatformWindow`
/// conformer's exhaustive `switch` in `setPointerStyle(_:)` owes `.image` or
/// `default:` — a migration note (`docs/migration.md`). `.shape(…)` is still
/// not offered (`CI-A`, `IC-G`). **`PH-A` and `PH-F` add three more** (`columnResizeOneWay`,
/// `rowResizeOneWay`, `hidden`): the same owing, a `default:` shows the arrow or leaves the pointer
/// visible.
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
    /// A divider that moves one way only (`columnResize(directions:)` with one
    /// direction, `PH-A`): the left-right resize with one arrow, towards the
    /// trailing side when `towardTrailing`, else the leading side.
    case columnResizeOneWay(towardTrailing: Bool)
    /// `rowResize(directions:)` with one direction: the up-down resize with one
    /// arrow, down when `towardDown`, else up.
    case rowResizeOneWay(towardDown: Bool)
    /// No pointer is drawn: `pointerVisibility(.hidden)` (`PH-F`). A platform
    /// shows the pointer again on the next style it is sent.
    case hidden
    /// The magnifying glass with a plus: `.zoomIn`.
    case zoomIn
    /// The magnifying glass with a minus: `.zoomOut`.
    case zoomOut
    /// A window-frame resize at `edge`, the arrows showing the directions the
    /// edge can move: `inward`, `outward`, or both (both when neither is set).
    case frameResize(edge: PlatformResizeEdge, inward: Bool, outward: Bool)
    /// A cursor drawn from an app's bitmap: `PointerStyle.image(_:hotSpot:)`
    /// (`IC-A`). A platform that cannot make it leaves the current cursor
    /// (`IC-C` 3).
    case image(PlatformCursorImage)
}

/// An image cursor at the platform seam (ruling `IC-A`): the bitmap's
/// premultiplied texture, the scale that gives its point size, and the hot
/// spot in points from the top-left, **already resolved and clamped** by
/// `Window`'s side (`IC-C`).
///
/// **Equality and hash are the texture's identity**, the scale and the hot
/// spot, never the bytes: two bitmaps with equal pixels are two cursors, and
/// one bitmap rebuilt into an `Image` every frame is one (`IC-F`), so a
/// platform can cache its native cursor per value.
public struct PlatformCursorImage: Sendable, Hashable {
    /// The cursor's pixels, premultiplied RGBA8 sRGB (`TE-AF`, `AI-E`).
    public let texture: ImageTexture
    /// Pixels per point: the cursor is `pixelWidth / scale` points wide.
    public let scale: Float
    /// The hot spot's x in points from the left edge.
    public let hotSpotX: Float
    /// The hot spot's y in points from the top edge.
    public let hotSpotY: Float

    /// A cursor image. `hotSpot` is in points from the top-left; it is not
    /// clamped here (`PointerStyle.image(_:hotSpot:)` clamps it). Public
    /// because the `Backends/SDL` package and an outside conformer's tests
    /// build one.
    public init(texture: ImageTexture, scale: Float, hotSpot: (x: Float, y: Float)) {
        self.texture = texture
        self.scale = scale
        self.hotSpotX = hotSpot.x
        self.hotSpotY = hotSpot.y
    }

    /// The bitmap's width in pixels.
    public var pixelWidth: Int { texture.width }
    /// The bitmap's height in pixels.
    public var pixelHeight: Int { texture.height }
    /// The cursor's width in points: `pixelWidth / scale`.
    public var pointWidth: Float { Float(texture.width) / scale }
    /// The cursor's height in points: `pixelHeight / scale`.
    public var pointHeight: Float { Float(texture.height) / scale }

    /// Texture identity, scale and hot spot (`IC-A` 2).
    public static func == (lhs: PlatformCursorImage, rhs: PlatformCursorImage) -> Bool {
        lhs.texture === rhs.texture && lhs.scale == rhs.scale
            && lhs.hotSpotX == rhs.hotSpotX && lhs.hotSpotY == rhs.hotSpotY
    }

    /// Hashes what `==` compares.
    public func hash(into hasher: inout Hasher) {
        hasher.combine(ObjectIdentifier(texture))
        hasher.combine(scale)
        hasher.combine(hotSpotX)
        hasher.combine(hotSpotY)
    }
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
