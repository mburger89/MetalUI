import Foundation
import MetalUIScene

/// The pixels an ``Image`` draws — MetalUI's stand-in for SwiftUI's `CGImage`
/// argument (plan task 11, part 2, ruling `TE-AL`), so no Apple type crosses
/// the portable module.
///
/// `width × height` texels of RGBA8, sRGB gamma space (never linearized,
/// spec §7.8), row-major from the top-left. **Straight alpha in, premultiplied
/// stored**: `init(width:height:rgba:)` takes what an author writes and
/// premultiplies it through `ImageTexture(width:height:straightRGBA:)` (probe
/// I12: half-alpha red over white reads (255, 127, 127) in SwiftUI;
/// `TE-AR` item 2 put the premultiply in `ImageTexture`, so it is done once).
/// The bitmap's texture is created here, once, and shared by every copy and
/// every frame that draws it, so a renderer uploads it once (`TE-AF`: the
/// cache is keyed on the texture's identity).
public struct ImageBitmap: Sendable {
    let texture: ImageTexture

    /// The bitmap's width in pixels.
    public var width: Int { texture.width }
    /// The bitmap's height in pixels.
    public var height: Int { texture.height }

    /// `rgba` is `width × height × 4` bytes of straight-alpha R, G, B, A.
    /// **A zero side, or any other byte count, traps**, naming `ImageBitmap`
    /// (test `anImageBitmapOfTheWrongByteCountOrAZeroSideTraps`).
    public init(width: Int, height: Int, rgba: [UInt8]) {
        precondition(width > 0 && height > 0, "ImageBitmap: \(width)×\(height) has a zero side")
        precondition(rgba.count == width * height * 4,
                     "ImageBitmap: \(rgba.count) bytes for \(width)×\(height) (needs \(width * height * 4))")
        texture = ImageTexture(width: width, height: height, straightRGBA: rgba)
    }

    init(texture: ImageTexture) {
        self.texture = texture
    }

    /// Decodes the image file at `path`, on every platform (ruling `PX-E`).
    ///
    /// **PNG and JPEG** decode through MetalUI's own decoder (stb_image,
    /// vendored), so a file gives the same bytes on macOS, Linux and Windows
    /// (`PX-C`): every PNG colour type and bit depth, Adam7, baseline and
    /// progressive JPEG; 16-bit samples rounded to 8; **colour profiles
    /// ignored** — every sample is taken as sRGB (a Display P3 or
    /// gamma-tagged file draws shifted from what SwiftUI shows, divergence
    /// 138). **Other formats** (TIFF, GIF, HEIC, …) decode through ImageIO on
    /// Apple platforms only — colour-managed, the first frame — and are `nil`
    /// elsewhere.
    ///
    /// `nil` when the file is missing, a directory or unreadable, or when it
    /// is corrupt or truncated (a PNG with a bad CRC or no `IEND`, a JPEG with
    /// no end marker — never a partial image), or wider or taller than 16384
    /// pixels (`PX-D`). Never cached: a file read twice is decoded twice; for
    /// a resource that should decode once, use
    /// ``init(resource:withExtension:subdirectory:bundle:)``.
    public init?(contentsOfFile path: String) {
        guard let data = FileManager.default.contents(atPath: path) else { return nil }
        self.init(data: data)
    }

    /// Decodes an image held in memory — a downloaded or embedded file —
    /// exactly as ``init(contentsOfFile:)`` decodes the same bytes (ruling
    /// `PX-E` item 2); empty data is `nil`.
    public init?(data: Data) {
        guard let texture = data.withUnsafeBytes({ decodeImageTexture($0) }) else { return nil }
        self.texture = texture
    }

    /// Decodes the resource `name`.`ext` in `bundle` (in `subdirectory` when
    /// given; `ext` `nil` when `name` carries its extension) — e.g. an SwiftPM
    /// target's `Bundle.module` — as ``init(data:)`` does (ruling `PX-E`
    /// item 3). `nil` when the resource does not exist or does not decode.
    ///
    /// **Decoded once per resolved path per process**: every later call for
    /// the same file returns the same bitmap — the same texture identity, so
    /// a renderer uploads it once (`TE-AF`) — including a cached `nil`.
    /// Bundle resources are taken as immutable while the process runs; the
    /// cache is never evicted. A file that changes at run time belongs to
    /// ``init(contentsOfFile:)``, which never caches.
    ///
    /// MetalUI-only: SwiftUI's `Image(_:bundle:)` reads an asset catalog, not
    /// loose files (probe `swiftui-bundle-image`), so MetalUI does not offer
    /// that spelling; draw this bitmap with `Image(_:scale:label:)`.
    public init?(resource name: String, withExtension ext: String? = "png",
                 subdirectory: String? = nil, bundle: Bundle) {
        guard let url = bundle.url(forResource: name, withExtension: ext, subdirectory: subdirectory),
              let bitmap = ImageResourceCache.shared.bitmap(at: url.standardizedFileURL.path)
        else { return nil }
        self = bitmap
    }
}

/// `ImageBitmap(resource:…)`'s decodes, one per resolved file path, for the
/// life of the process (ruling `PX-E` item 3). Lock-guarded: a resource may be
/// loaded from any thread; the decode runs under the lock so a path is never
/// decoded twice.
final class ImageResourceCache: @unchecked Sendable {
    static let shared = ImageResourceCache()

    private let lock = NSLock()
    private var bitmaps: [String: ImageBitmap?] = [:]

    func bitmap(at path: String) -> ImageBitmap? {
        lock.lock()
        defer { lock.unlock() }
        if let cached = bitmaps[path] { return cached }
        let decoded = ImageBitmap(contentsOfFile: path)
        bitmaps[path] = .some(decoded)
        return decoded
    }
}
