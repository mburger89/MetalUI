import CoreGraphics
import Foundation
import ImageIO
import Metal
import MetalUI
import MetalUIRender
import MetalUIScene
import MetalUITesting
import UniformTypeIdentifiers

/// Why a snapshot could not be taken (ruling `HT-AB`).
public enum SnapshotError: Error, Equatable {
    /// The Mac has no Metal device.
    case noMetalDevice
    /// The window has presented no frame yet (it is closed, or never drew).
    case noFrame
    /// The pixels could not be wrapped as an image or encoded as PNG.
    case encodingFailed
}

extension TestWindow {
    /// The last presented frame as a bitmap, drawn through the real Metal renderer: the window's
    /// ``TestWindow/scene`` and ``TestWindow/glyphAtlas`` on an offscreen texture, so text is drawn and
    /// the window needs no screen (ruling `HT-AB`). macOS only; MetalUI-only.
    ///
    /// The image is the window's content size times its scale factor in device pixels (an 800 x 600
    /// window at `scaleFactor: 2` is 1600 x 1200), sRGB, premultiplied alpha, transparent where the
    /// tree paints nothing. Draw a background in the tree for an opaque screenshot. Throws
    /// ``SnapshotError``.
    public func snapshot() throws -> CGImage {
        guard let atlas = glyphAtlas else { throw SnapshotError.noFrame }
        return try Self.render(scene: scene, atlas: atlas, size: platformWindow.contentSize,
                               scale: platformWindow.headlessRenderer.scaleFactor)
    }

    /// ``snapshot()`` encoded as PNG.
    public func snapshotPNG() throws -> Data {
        let image = try snapshot()
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data, UTType.png.identifier as CFString, 1, nil) else { throw SnapshotError.encodingFailed }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw SnapshotError.encodingFailed }
        return data as Data
    }

    /// Draws `scene` with `atlas` at `size` points times `scale`. Package-visible so a test can pass
    /// an empty atlas and watch the glyph check fail.
    static func render(scene: Scene, atlas: GlyphAtlas, size: Size<Pixels>, scale: Float) throws -> CGImage {
        guard let device = MTLCreateSystemDefaultDevice() else { throw SnapshotError.noMetalDevice }
        let renderer = try Renderer(device: device)
        renderer.upload(atlas)
        let width = max(1, Int((size.width.value * scale).rounded()))
        let height = max(1, Int((size.height.value * scale).rounded()))
        let bgra = try renderer.renderOffscreen(
            scene, size: Size(width: DevicePixels(Int32(width)), height: DevicePixels(Int32(height))))
        // bgra8Unorm, premultiplied, little-endian.
        guard let provider = CGDataProvider(data: Data(bgra) as CFData),
              let image = CGImage(
                width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue
                                         | CGBitmapInfo.byteOrder32Little.rawValue),
                provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
        else { throw SnapshotError.encodingFailed }
        return image
    }
}
