import MetalUIScene
import SDLBridge

/// The application icon's conversion to SDL (ruling AI-F): MetalUI's
/// premultiplied `ImageTexture`s become one straight-alpha RGBA32
/// `SDL_Surface` with alternates.
enum SDLIcon {
    /// SKELETON (lane 2 red): returns the premultiplied bytes unchanged.
    static func straightRGBA(_ texture: ImageTexture) -> [UInt8] {
        texture.pixels
    }

    /// SKELETON (lane 2 red): builds nothing.
    static func makeSurface(_ textures: [ImageTexture]) -> UnsafeMutableRawPointer? {
        nil
    }
}
