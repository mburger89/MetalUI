#if os(macOS)
import AppKit
import MetalUIScene

/// The conversion behind `AppKitPlatform.setApplicationIcon(_:)` (rulings
/// `AI-E`, `AI-I`): an `ImageTexture`'s premultiplied RGBA8 sRGB bytes into a
/// `CGImage` and an `NSImage`, pure so a test can pin it pixel for pixel.
enum AppKitIcon {
    /// A `CGImage` over `texture`'s bytes **as stored**: 8 bits per component,
    /// 32 per pixel, `width × 4` bytes per row, sRGB,
    /// `premultipliedLast | byteOrder32Big`. No un-premultiply and no
    /// re-premultiply — the texture is already premultiplied (`TE-AF`), and
    /// labelling it `.last` would make CoreGraphics premultiply a second time
    /// (stored (100, 50, 25, 128) would draw as (50, 25, 13, 128); test A3).
    /// `nil` only if CoreGraphics refuses the description.
    static func cgImage(from texture: ImageTexture) -> CGImage? {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let provider = CGDataProvider(data: Data(texture.pixels) as CFData) else { return nil }
        return CGImage(width: texture.width, height: texture.height,
                       bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: texture.width * 4,
                       space: space,
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue
                                                    | CGBitmapInfo.byteOrder32Big.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: true,
                       intent: .defaultIntent)
    }

    /// One `NSImage` holding one `NSBitmapImageRep` per texture, in the order
    /// given (the platform contract: smallest first). The image's `size`, and
    /// every representation's, is the largest texture's pixel size, so the
    /// representations are resolutions of one picture and AppKit picks one by
    /// pixel density. `nil` for `[]`.
    static func image(from textures: [ImageTexture]) -> NSImage? {
        guard let largest = textures.max(by: { $0.width * $0.height < $1.width * $1.height })
        else { return nil }
        let size = NSSize(width: largest.width, height: largest.height)
        let image = NSImage(size: size)
        for texture in textures {
            guard let cgImage = cgImage(from: texture) else { continue }
            let rep = NSBitmapImageRep(cgImage: cgImage)
            rep.size = size
            image.addRepresentation(rep)
        }
        return image
    }
}
#endif
