import MetalUIShaderTypes

/// The pixels an image primitive samples (ruling TE-AF): `width` × `height`
/// texels of **premultiplied** RGBA8 in sRGB gamma space — no linearization,
/// spec §7.8 — row-major from the top-left.
///
/// **Immutable, and a class on purpose.** Each renderer caches one GPU texture
/// per `ImageTexture` *identity* and holds the object strongly while it does,
/// so an `ObjectIdentifier` it keys on cannot be reused by a new bitmap while
/// the cache entry lives; an entry the frame's scene no longer references is
/// released (an image stream — a new bitmap every frame — must not accumulate
/// the way the grow-only glyph atlas does). A value type could not be keyed
/// this way, and a mutable one could change under a cached upload.
public final class ImageTexture: Sendable {
    public let width: Int
    public let height: Int
    /// `width × height × 4` bytes, premultiplied R, G, B, A per texel.
    public let pixels: [UInt8]

    /// `pixels` must already be premultiplied (`ImageBitmap` does that for a
    /// straight-alpha source). A zero side, or a byte count other than
    /// `width × height × 4`, traps: a renderer uploads exactly that many bytes.
    public init(width: Int, height: Int, premultipliedRGBA pixels: [UInt8]) {
        precondition(width > 0 && height > 0,
                     "ImageTexture: \(width)×\(height) has a zero side")
        precondition(pixels.count == width * height * 4,
                     "ImageTexture: \(pixels.count) bytes for \(width)×\(height) (needs \(width * height * 4))")
        self.width = width
        self.height = height
        self.pixels = pixels
    }

    /// Premultiplies straight-alpha RGBA8 (`c × a / 255`, rounded to nearest)
    /// and stores the result, so the renderers' `(one, oneMinusSourceAlpha)`
    /// blend composites it source-over (probe I12: half-alpha red over white
    /// reads (255, 127, 127) in SwiftUI). Straight (200, 100, 50, 128) is
    /// stored (100, 50, 25, 128); composited unpremultiplied over white it
    /// would read (255, 227, 177) instead of (227, 177, 152). The same
    /// preconditions as the premultiplied initialiser.
    public convenience init(width: Int, height: Int, straightRGBA pixels: [UInt8]) {
        var premultiplied = pixels
        var i = 0
        while i + 3 < premultiplied.count {
            let a = UInt32(premultiplied[i + 3])
            for c in 0..<3 {
                premultiplied[i + c] = UInt8((UInt32(premultiplied[i + c]) * a + 127) / 255)
            }
            i += 4
        }
        self.init(width: width, height: height, premultipliedRGBA: premultiplied)
    }
}

/// How an image samples its texture (`MUIImage.filter`).
///
/// `linear` is bilinear with clamped edges (SwiftUI's default, `.low` and
/// `.medium`, probe I8/I11); `nearest` reads the texel under the pixel
/// (`.none`) — `texture.read`/`Texture2D.Load`, so neither renderer needs a
/// second sampler.
public enum ImageFilter: UInt32, Sendable, Hashable {
    case linear = 0
    case nearest = 1
}

/// Which outline an `MUIRect` holds (`MUIRect.shape`, ruling TE-AE).
public enum PrimitiveShape: UInt32, Sendable, Hashable {
    /// A rectangle with per-corner circular radii — every rect before the
    /// field existed.
    case roundedRectangle = 0
    /// The ellipse inscribed in the bounds; the corner radii are ignored and
    /// the top border width is the band SwiftUI's `strokeBorder` draws.
    case ellipse = 1
}
