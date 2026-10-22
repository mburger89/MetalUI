import MetalUICore
import MetalUILayout
import MetalUIPath
import MetalUIPlatform
import MetalUIScene

// `PointerStyle.shape(_:eoFill:size:hotSpot:fill:outline:)` (rulings `BG-K`...`BG-M`, divergence 735; record
// 144; spec `docs/superpowers/specs/2026-10-22-presentation-extras-design.md`). SwiftUI declares
// `PointerStyle.shape(_:eoFill:size:)` for visionOS only (`@available(macOS, unavailable)`, probe
// `swiftui-presentation-extras-typecheck.sh` `T1`), so there is no macOS behaviour to match: the spelling is
// MetalUI's own, with three extra defaulted parameters. The shape is rasterized on the CPU through
// `MetalUIPath` at the window's integer display scale and reaches the platform as the image cursor it
// already serves (`IC-`): no seam requirement, no platform code.

/// What a shape cursor is, by value: the outline in the shape's own `size`-point space, the fill rule, the
/// size, the hot spot and the two colours. `Hashable` by value, so a shape rebuilt in every build is one
/// `PointerStyle` and the window sends it once (`IC-A`, `IC-F`).
struct ShapeCursorSpec: Sendable, Hashable {
    /// The shape's outline in `(0, 0, width, height)`.
    let geometry: PathGeometry
    let eoFill: Bool
    /// The shape's size in points, each side in `1...ShapeCursorSpec.maximumSide`.
    let width: Float
    let height: Float
    /// The hot spot as a fraction of the shape, clamped to the unit square.
    let hotSpotX: Float
    let hotSpotY: Float
    let fill: Color
    let outline: Color

    /// The largest side, in points (the practical cursor limit of SDL and AppKit, `BG-L`).
    static let maximumSide: Float = 128
    /// The outline's total width in points: centred on the edge, so one point shows outside the fill.
    static let outlineWidth: Double = 2
    /// The margin the outline needs on each side, in points.
    static let margin: Float = 1
}

extension PointerStyle {
    /// A pointer drawn from `shape`, filled `fill` with an `outline` around it — SwiftUI's
    /// `PointerStyle.shape(_:eoFill:size:)` spelling, which SwiftUI offers on **visionOS only**
    /// (`@available(macOS, unavailable)`), so on macOS this is MetalUI's own look (ruling `BG-K`,
    /// divergence 735: black fill, a 1-point white outline, the shape's centre on the pointer). A call
    /// written for visionOS, `shape(s, eoFill: x, size: z)`, compiles unchanged.
    ///
    /// - Parameters:
    ///   - shape: Whatever outline; its `path(in:)` is taken in `(0, 0, size)`.
    ///   - eoFill: Fill by the even-odd rule instead of nonzero.
    ///   - size: The shape's size in points; required, as SwiftUI's. A side that is not finite or not
    ///     positive makes the style `.default`; a side over 128 points clamps to 128 (`BG-L`).
    ///   - hotSpot: The point of the shape on the pointer, as a fraction of its size from the top-left;
    ///     outside the unit square it clamps per axis (as `image(_:hotSpot:)`, divergence 465).
    ///   - fill: The fill colour. A token or dynamic colour resolves in the light scheme.
    ///   - outline: The 1-point ring around the fill, so the cursor reads on any background.
    ///
    /// **The cursor is rasterized at the window's display scale** (rounded up to a whole number) and is
    /// `size + 2` points square including the ring; it is cached per window by value (eight at most), so
    /// rebuilding the shape in every build is one cursor and one raster. A window moved to a display of
    /// another scale is sent a new raster once. Not an element: nothing is laid out or painted in a frame.
    @MainActor
    public static func shape(_ shape: some Shape, eoFill: Bool = false, size: Size<Pixels>,
                             hotSpot: UnitPoint = .center, fill: Color = .black,
                             outline: Color = .white) -> PointerStyle {
        let w = size.width.value, h = size.height.value
        guard w.isFinite, h.isFinite, w > 0, h > 0 else { return .default }
        let width = min(w, ShapeCursorSpec.maximumSide), height = min(h, ShapeCursorSpec.maximumSide)
        func unit(_ value: Double) -> Float { value.isNaN ? 0 : Float(min(max(value, 0), 1)) }
        let local = Bounds(origin: Point(x: Pixels(0), y: Pixels(0)),
                           size: Size(width: Pixels(width), height: Pixels(height)))
        return PointerStyle(.shape(ShapeCursorSpec(
            geometry: shape.path(in: local).storage, eoFill: eoFill, width: width, height: height,
            hotSpotX: unit(hotSpot.x), hotSpotY: unit(hotSpot.y), fill: fill, outline: outline)))
    }
}

extension ShapeCursorSpec {
    /// The cursor's pixels at integer `scale`: `(size × scale) + 2 × margin × scale` a side, straight RGBA —
    /// the outline stroked first, the fill over it (`BG-L`).
    func bitmap(scale: Int) -> ImageBitmap {
        let s = Double(scale)
        let margin = Int(Self.margin) * scale
        let pixelWidth = Int((width * Float(scale)).rounded(.up)) + 2 * margin
        let pixelHeight = Int((height * Float(scale)).rounded(.up)) + 2 * margin
        let clip = RasterRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight)
        let transform = PathAffine(a: s, b: 0, c: 0, d: s, tx: Double(margin), ty: Double(margin))
        var rasterizer = CoverageRasterizer()
        var scratch = RasterScratch()
        let ring = PathRaster.stroke(geometry, style: StrokeParameters(width: Self.outlineWidth, join: .round),
                                     transform: transform, clip: clip, rasterizer: &rasterizer, scratch: &scratch)
        let body = PathRaster.fill(geometry, rule: eoFill ? .evenOdd : .nonZero, transform: transform, clip: clip,
                                   antialiased: true, rasterizer: &rasterizer, scratch: &scratch)
        let fillRGBA = fill.resolved(theme: .light, scheme: .light).toRgba()
        let ringRGBA = outline.resolved(theme: .light, scheme: .light).toRgba()
        var rgba = [UInt8](repeating: 0, count: pixelWidth * pixelHeight * 4)
        for y in 0..<pixelHeight {
            for x in 0..<pixelWidth {
                let f = Float(body.value(atX: x, y: y)) / 255 * fillRGBA.a
                let o = Float(ring.value(atX: x, y: y)) / 255 * ringRGBA.a
                let alpha = f + o * (1 - f)
                guard alpha > 0 else { continue }
                func channel(_ fc: Float, _ oc: Float) -> UInt8 {
                    let c = (fc * f + oc * o * (1 - f)) / alpha
                    return UInt8(min(max(c * 255 + 0.5, 0), 255))
                }
                let i = (y * pixelWidth + x) * 4
                rgba[i] = channel(fillRGBA.r, ringRGBA.r)
                rgba[i + 1] = channel(fillRGBA.g, ringRGBA.g)
                rgba[i + 2] = channel(fillRGBA.b, ringRGBA.b)
                rgba[i + 3] = UInt8(min(max(alpha * 255 + 0.5, 0), 255))
            }
        }
        return ImageBitmap(width: pixelWidth, height: pixelHeight, rgba: rgba)
    }

    /// The hot spot in points from the cursor's top-left: past the outline's margin, then the fraction of
    /// the shape.
    var hotSpot: (x: Float, y: Float) {
        (Self.margin + hotSpotX * width, Self.margin + hotSpotY * height)
    }
}

/// A window's shape cursors: an LRU of eight `PlatformCursorImage`s keyed by `(spec, integer scale)` (`BG-M`),
/// so one value is one raster and one texture identity however often a build produces it. **Not** the
/// window's `RasterCache`: a cursor is not a frame leaf and moves none of its counters.
@MainActor
final class ShapeCursorCache {
    private struct Key: Hashable { let spec: ShapeCursorSpec; let scale: Int }

    /// The cache's size: SDL's own cursor table holds eight.
    static let capacity = 8
    private var entries: [(key: Key, image: PlatformCursorImage)] = []
    /// Rasters made, ever (tests; work, never time).
    private(set) var rasterCount = 0
    /// Entries held now.
    var count: Int { entries.count }

    /// The cursor for `spec` at `scale`, rastered on a miss; the hit is the most recent.
    func image(for spec: ShapeCursorSpec, scale: Int) -> PlatformCursorImage {
        let key = Key(spec: spec, scale: scale)
        if let index = entries.firstIndex(where: { $0.key == key }) {
            let entry = entries.remove(at: index)
            entries.append(entry)
            return entry.image
        }
        rasterCount += 1
        let hot = spec.hotSpot
        let image = PlatformCursorImage(texture: spec.bitmap(scale: scale).texture, scale: Float(scale),
                                        hotSpot: hot)
        entries.append((key, image))
        if entries.count > Self.capacity { entries.removeFirst() }
        return image
    }
}

extension Window {
    /// The platform's cursor for `style`: a shape is rastered (or taken from the cache) at the display
    /// scale rounded up to a whole number, every other style is its own seam kind (`BG-M`).
    func resolvedPlatformStyle(_ style: PointerStyle) -> PlatformPointerStyle {
        guard case .shape(let spec) = style.kind else { return style.platformStyle }
        let scale = max(1, Int(lastDisplayScale.isFinite ? lastDisplayScale.rounded(.up) : 1))
        return .image(shapeCursors.image(for: spec, scale: scale))
    }

    /// Records the scale a frame is built at. A change while a shape cursor is the sent style forgets what
    /// was sent, so the next pointer resolution re-sends it once at the new scale (`BG-M`, test 35).
    func noteDisplayScale(_ scale: Float) {
        guard scale != lastDisplayScale else { return }
        let previous = max(1, Int(lastDisplayScale.rounded(.up)))
        lastDisplayScale = scale
        if case .shape? = resolvedPointerStyle?.kind, max(1, Int(scale.rounded(.up))) != previous {
            resolvedPointerStyle = nil
        }
    }
}
