import MetalUICore
import MetalUIIconData
import MetalUILayout

// `Icon`: MetalUI's own vector icon (record 232, prefix `SYM-`, rulings `SYM-I`, `SYM-J`). MetalUI-only (class M): SwiftUI has
// no such type. It is the one drawing the bundled Lucide subset is made of, and the tool for an app that wants identical art
// on every platform.

/// A vector icon: layers of `Path`s on a view box, each stroked or filled in the foreground style — MetalUI-only
/// (record 232). ``Image/init(icon:label:)`` draws it at the size a symbol of the environment's font and
/// ``Image/Scale`` would have, in the foreground colour; the stroke scales with the box (`side / viewBox`) and with the
/// font's weight (``Icon/Layer/Paint/stroke(width:cap:join:)``), so an icon is crisp at any size and follows `.bold()`.
///
/// ``bundled(_:)`` is the icon `Image(systemName:)` draws for a name on Linux and Windows (a Lucide icon; ISC, MIT
/// portions, `THIRD-PARTY-NOTICES.md`), whichever platform asks.
public struct Icon: Hashable, Sendable {
    /// One layer of an icon: a path, how it is painted and how much of the foreground it shows.
    public struct Layer: Hashable, Sendable {
        /// How a layer's path is painted.
        public enum Paint: Hashable, Sendable {
            /// The path stroked `width` wide in view-box units (scaled with the box, and by the font weight relative to
            /// regular), with these ends and corners.
            case stroke(width: Pixels, cap: LineCap, join: LineJoin)
            /// The path filled under `style`.
            case fill(FillStyle)
        }

        /// How strongly a layer shows under ``SymbolRenderingMode/hierarchical``.
        public enum Level: Hashable, Sendable {
            /// The foreground style itself.
            case primary
            /// The foreground style at the secondary level, half (`HY-A`'s factor 0.5), under `.hierarchical`; in full
            /// under `.monochrome` and `.multicolor`.
            case secondary
        }

        /// The outline, in view-box units.
        public var path: Path
        /// How it is painted.
        public var paint: Paint
        /// How strongly it shows under a hierarchical rendering mode.
        public var level: Level

        /// A layer of `path` painted `paint` at `level`.
        public init(_ path: Path, paint: Paint, level: Level = .primary) {
            self.path = path
            self.paint = paint
            self.level = level
        }

        public static func == (lhs: Layer, rhs: Layer) -> Bool {
            lhs.path == rhs.path && lhs.paint == rhs.paint && lhs.level == rhs.level
        }

        public func hash(into hasher: inout Hasher) {
            hasher.combine(path.storage)
            hasher.combine(paint)
            hasher.combine(level)
        }
    }

    /// The coordinate space the layers' paths are in; the icon is drawn uniformly scaled so the larger side fills the box,
    /// centred.
    public var viewBox: Size<Pixels>
    /// The layers, drawn first to last.
    public var layers: [Layer]

    /// An icon of `layers` on `viewBox`.
    public init(viewBox: Size<Pixels>, layers: [Layer]) {
        self.viewBox = viewBox
        self.layers = layers
    }

    /// The bundled icon that `Image(systemName:)` draws for the SF Symbol name `systemName` off Apple platforms (and on
    /// Apple platforms under the test seam), or `nil` when no bundled icon stands for it (`SYM-I`). A `.fill` name
    /// returns the filled outline (play, stop, circle, square, triangle, star) and every other `.fill` name `nil`.
    @MainActor
    public static func bundled(_ systemName: String) -> Icon? {
        BundledSymbols.icon(forExactName: systemName)
    }
}

extension Image {
    /// An image of `icon`, an accessibility client reads as an `.image` labelled by `label`'s string (MetalUI-only). It lays
    /// out like a symbol: a square box of the environment font's point size times the ``Image/Scale`` factor, with a
    /// first and last baseline (`SYM-J`); ``resizable()`` answers the proposal. Drawn in the foreground style; under
    /// ``SymbolRenderingMode/hierarchical`` its ``Icon/Layer/Level/secondary`` layers draw at half.
    public init(icon: Icon, label: Text) {
        content = .icon(icon)
        accessibilityLabelText = label.string
    }

    /// An image of `icon` that accessibility clients skip (MetalUI-only); otherwise ``init(icon:label:)``.
    public init(decorative icon: Icon) {
        content = .icon(icon)
    }
}
