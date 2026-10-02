#if os(macOS)
import AppKit
import MetalUIScene

/// The conversion behind `AppKitPlatform.setApplicationIcon(_:)` (rulings
/// `AI-E`, `AI-I`): an `ImageTexture`'s premultiplied RGBA8 sRGB bytes into a
/// `CGImage` and an `NSImage`, pure so a test can pin it pixel for pixel.
enum AppKitIcon {
    // RED-FIRST SKELETON — replaced by the implementation commit.
    static func cgImage(from texture: ImageTexture) -> CGImage? { nil }
    static func image(from textures: [ImageTexture]) -> NSImage? { NSImage() }
}
#endif
