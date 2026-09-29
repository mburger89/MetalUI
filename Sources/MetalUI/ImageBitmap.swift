import MetalUIScene
#if canImport(ImageIO)
import Foundation
import CoreGraphics
import ImageIO
#endif

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

    public var width: Int { texture.width }
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

    #if canImport(ImageIO)
    /// Decodes the image file at `path` through ImageIO — macOS only (`TE-AL`;
    /// off Apple no decoder is vendored, spec §9). `nil` when the file does not
    /// exist or does not decode. The first frame of a multi-frame file.
    ///
    /// The decoded image is drawn into a premultiplied sRGB RGBA8 context, so
    /// its colours are converted to sRGB and its rows read top-down, as the
    /// file stores them.
    public init?(contentsOfFile path: String) {
        let url = URL(fileURLWithPath: path) as CFURL
        guard let source = CGImageSourceCreateWithURL(url, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
              image.width > 0, image.height > 0,
              let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        let width = image.width
        let height = image.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height,
                                          bitsPerComponent: 8, bytesPerRow: width * 4, space: space,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                                              | CGBitmapInfo.byteOrder32Big.rawValue)
            else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return nil }
        texture = ImageTexture(width: width, height: height, premultipliedRGBA: pixels)
    }
    #endif
}
