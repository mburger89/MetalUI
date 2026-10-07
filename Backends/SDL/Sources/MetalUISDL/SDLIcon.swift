// Compiled only under the `SDL` trait (ruling PX-H item 2).
#if SDL
import MetalUIScene
import SDLBridge

/// The application icon's conversion to SDL (ruling AI-F): MetalUI's
/// premultiplied `ImageTexture`s become one straight-alpha RGBA32
/// `SDL_Surface` with alternates.
enum SDLIcon {
    /// The texture's texels with alpha un-premultiplied — SDL surfaces, and
    /// the Windows (`CreateIconIndirect`) and X11 (`_NET_WM_ICON`) icon
    /// formats SDL converts to, are straight alpha. Per texel with alpha `a`:
    /// `a == 0` gives (0, 0, 0, 0); else each colour `c` becomes
    /// `min(255, (c × 255 + a / 2) / a)`, the clamp covering a texture built
    /// through `ImageTexture(premultipliedRGBA:)` with a colour above its
    /// alpha. Lossy at low alpha: (100, 50, 25, 128), what `ImageBitmap`
    /// stores for straight (200, 100, 50, 128), comes back (199, 100, 50, 128).
    static func straightRGBA(_ texture: ImageTexture) -> [UInt8] {
        var out = texture.pixels
        var i = 0
        while i + 3 < out.count {
            let a = UInt32(out[i + 3])
            if a == 0 {
                out[i] = 0; out[i + 1] = 0; out[i + 2] = 0
            } else {
                for c in 0..<3 {
                    out[i + c] = UInt8(min(255, (UInt32(out[i + c]) * 255 + a / 2) / a))
                }
            }
            i += 4
        }
        return out
    }

    /// One `SDL_Surface` for `textures` (the platform contract, `AI-B`: ordered
    /// smallest area first): the first is the primary — `SDL_SetWindowIcon`'s
    /// 100%-scale image — and every other an alternate
    /// (`SDL_AddSurfaceAlternateImage`), which SDL picks by display scale.
    /// `nil` for `[]` or when SDL cannot create the primary; an alternate SDL
    /// refuses is left out. The caller destroys the result
    /// (`mui_surface_destroy`).
    static func makeSurface(_ textures: [ImageTexture]) -> UnsafeMutableRawPointer? {
        guard let first = textures.first, let primary = surface(first) else { return nil }
        for texture in textures.dropFirst() {
            guard let alternate = surface(texture) else { continue }
            _ = mui_icon_surface_add_alternate(primary, alternate)
            mui_surface_destroy(alternate)   // the primary holds its own reference
        }
        return primary
    }

    private static func surface(_ texture: ImageTexture) -> UnsafeMutableRawPointer? {
        straightRGBA(texture).withUnsafeBufferPointer {
            mui_icon_surface_create(Int32(texture.width), Int32(texture.height), $0.baseAddress)
        }
    }
}
#endif
