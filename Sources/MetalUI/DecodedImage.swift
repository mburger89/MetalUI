import Foundation

/// An image decoded to plain pixels, with the orientation its file reports — MetalUI's public
/// decoder (rulings `IB-A`…`IB-D`, record 113). MetalUI-only: SwiftUI has no pixel-level decode API
/// (its `Image` takes a `CGImage` or `NSImage` you decode yourself).
///
/// **Straight alpha**, sRGB samples, row-major from the top-left, no row padding
/// (``bytesPerRow`` is `width × 4` for ``Format/rgba``, `width` for ``Format/grey``). It is a
/// different value from an ``ImageBitmap``, which stores premultiplied texels for drawing
/// (`IB-A`); build one with ``ImageBitmap/init(_:)``.
///
/// The decoder is the one ``ImageBitmap/init(data:)`` uses (vendored stb_image, the same on every
/// platform): PNG and JPEG only (no ImageIO fallback, `IB-J`), colour profiles ignored (divergence
/// 138), `nil` for a missing, corrupt or truncated file or one over 16384 pixels a side
/// (`IB-I`). **Grey** (`IB-B`): a grey source is returned exactly; an RGB or RGBA source goes
/// through `(77 r + 150 g + 29 b) >> 8` (Rec. 601 integer luma) with the **alpha dropped, not
/// composited**; a 16-bit sample rounds to 8 bits as the RGBA path does.
///
/// **The orientation is reported, never applied** (`IB-C`): ``pixels`` are the stored pixels and
/// ``width``/``height`` their size; ``orientation`` is the EXIF tag of a JPEG `APP1` or a PNG
/// `eXIf` chunk (`.up` when there is none or it is damaged). Use ``orientedSize`` and
/// ``applyingOrientation()`` to turn the pixels upright.
public struct DecodedImage: Sendable, Equatable {
    /// The sample layout of ``pixels``.
    public enum Format: Sendable, Hashable {
        /// Four bytes per pixel: straight-alpha R, G, B, A.
        case rgba
        /// One byte per pixel: the grey (luma) value.
        case grey
    }

    /// The layout of ``pixels``.
    public let format: Format
    /// The stored width in pixels, before ``orientation``.
    public let width: Int
    /// The stored height in pixels, before ``orientation``.
    public let height: Int
    /// Bytes from one row to the next: `width × 4` for ``Format/rgba``, `width` for ``Format/grey``.
    public let bytesPerRow: Int
    /// `bytesPerRow × height` bytes, row-major from the top-left, straight alpha.
    public let pixels: [UInt8]
    /// The orientation the file reports; `.up` when it says nothing usable.
    public let orientation: Image.Orientation

    /// The size the image has once ``orientation`` is applied: width and height swap for a
    /// rotated one (``Image/Orientation/swapsAxes``).
    public var orientedSize: (width: Int, height: Int) {
        orientation.swapsAxes ? (height, width) : (width, height)
    }

    /// A decoded image over `pixels` (`bytesPerRow × height` bytes; traps otherwise).
    init(format: Format, width: Int, height: Int, pixels: [UInt8], orientation: Image.Orientation) {
        let perPixel = format == .rgba ? 4 : 1
        precondition(width > 0 && height > 0 && pixels.count == width * height * perPixel,
                     "DecodedImage: \(pixels.count) bytes for \(width)×\(height) \(format)")
        self.format = format
        self.width = width
        self.height = height
        self.bytesPerRow = width * perPixel
        self.pixels = pixels
        self.orientation = orientation
    }

    /// Decodes PNG or JPEG bytes in `format`, or `nil` (never a trap) for any other or damaged
    /// input. See the type's comment for the grey rule and the orientation.
    public init?(data: Data, format: Format = .rgba) {
        // The unlimited spelling of ``init(data:format:limits:)`` (`IH-I`): the header's size must
        // equal the decoder's.
        guard let decoded = DecodedImage.limitedDecode(data: data, format: format, limits: Limits(), trace: nil)
        else { return nil }
        self = decoded
    }

    /// Decodes the PNG or JPEG file at `path` as ``init(data:format:)`` does; `nil` when the file
    /// cannot be read.
    public init?(contentsOfFile path: String, format: Format = .rgba) {
        guard let data = FileManager.default.contents(atPath: path) else { return nil }
        self.init(data: data, format: format)
    }

    /// The same image with its pixels turned upright: ``orientation`` is `.up` in the result and
    /// ``width``/``height``/``bytesPerRow`` are the oriented ones. A permutation (no sample
    /// changes); `.up` returns `self`.
    public func applyingOrientation() -> DecodedImage {
        guard orientation != .up else { return self }
        let turned = permuteSamples(pixels, width: width, height: height,
                                    bytesPerPixel: format == .rgba ? 4 : 1, orientation: orientation)
        return DecodedImage(format: format, width: turned.width, height: turned.height,
                            pixels: turned.samples, orientation: .up)
    }
}

extension ImageBitmap {
    /// A drawable bitmap of `decoded`'s stored pixels (premultiplied once, as
    /// ``init(width:height:rgba:)``). A ``DecodedImage/Format/grey`` image becomes R = G = B = the
    /// grey value, A = 255. **The orientation is ignored**: apply it first with
    /// ``DecodedImage/applyingOrientation()`` to draw upright. MetalUI-only.
    public init(_ decoded: DecodedImage) {
        switch decoded.format {
        case .rgba:
            self.init(width: decoded.width, height: decoded.height, rgba: decoded.pixels)
        case .grey:
            var rgba = [UInt8](repeating: 255, count: decoded.pixels.count * 4)
            for (index, value) in decoded.pixels.enumerated() {
                rgba[index * 4] = value
                rgba[index * 4 + 1] = value
                rgba[index * 4 + 2] = value
            }
            self.init(width: decoded.width, height: decoded.height, rgba: rgba)
        }
    }
}
