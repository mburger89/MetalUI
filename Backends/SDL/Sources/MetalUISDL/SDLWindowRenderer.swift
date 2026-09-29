import Foundation
import MetalUIPlatform
import MetalUIScene
import SDLBridge

public struct SDLRendererError: Error, CustomStringConvertible {
    public let description: String
    init(_ what: String) { description = "\(what): \(String(cString: replay_error()))" }
}

/// The SDL GPU ``WindowRenderer`` (ruling RS-D): MetalUI frames drawn by SDL3's
/// GPU API — Metal on macOS, Vulkan on Linux, Direct3D 12 on Windows — from
/// the same `Scene` bytes and atlas the Metal renderer draws, with the shaders
/// compiled from `Shaders/replay.hlsl`. Draws into a claimed SDL window, or,
/// with none, into an offscreen target ``readPixels()`` returns (how it is
/// tested against the Metal renderer).
@MainActor
public final class SDLWindowRenderer: WindowRenderer {
    private let renderer: OpaquePointer
    private let window: OpaquePointer?
    private let offscreenScaleFactor: Float

    /// The compiled shader stages in this package's source tree
    /// (`Shaders/compiled`), found from this file's path: the backend is built
    /// from source, like everything in this repository.
    public nonisolated static var bundledShaderDirectory: String {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Shaders").appendingPathComponent("compiled").path
    }

    /// The SDL GPU driver this platform's shaders are for.
    public nonisolated static var defaultDriver: String {
        #if os(Windows)
        "direct3d12"
        #elseif os(macOS)
        "metal"
        #else
        "vulkan"
        #endif
    }

    /// A renderer drawing into `window` (an `SDL_Window *`).
    public init(window: OpaquePointer, driver: String = defaultDriver,
                shaderDirectory: String = bundledShaderDirectory) throws {
        guard let renderer = mui_renderer_create(shaderDirectory, driver) else {
            throw SDLRendererError("SDL GPU device")
        }
        guard mui_renderer_claim_window(renderer, UnsafeMutableRawPointer(window)) else {
            let error = SDLRendererError("claiming the window")
            mui_renderer_destroy(renderer)
            throw error
        }
        self.renderer = renderer
        self.window = window
        self.offscreenScaleFactor = 1
    }

    /// A windowless renderer drawing into a `width`×`height` device-pixel
    /// target, reported at `scaleFactor`.
    public init(offscreenWidth width: Int, height: Int, scaleFactor: Float = 1,
                driver: String = defaultDriver, shaderDirectory: String = bundledShaderDirectory) throws {
        guard let renderer = mui_renderer_create(shaderDirectory, driver) else {
            throw SDLRendererError("SDL GPU device")
        }
        guard mui_renderer_set_offscreen_size(renderer, UInt32(width), UInt32(height)) else {
            let error = SDLRendererError("offscreen target")
            mui_renderer_destroy(renderer)
            throw error
        }
        self.renderer = renderer
        self.window = nil
        self.offscreenScaleFactor = scaleFactor
    }

    // The renderer is only ever touched on the main actor; deinit is its end.
    nonisolated deinit {
        MainActor.assumeIsolated {
            for entry in textures.values { mui_renderer_release_texture(renderer, entry.handle) }
            mui_renderer_destroy(renderer)
        }
    }

    /// The GPU copy of each `ImageTexture` a recent frame drew (ruling TE-AF
    /// item 3), as the Metal renderer keeps them: keyed by identity **and
    /// holding the object**, so the identifier cannot be reused while the
    /// entry lives; uploaded once (`mui_renderer_create_texture`, never
    /// written again) and released as soon as a frame's scene stops
    /// referencing it — SDL frees the texture once no submitted frame uses it.
    private var textures: [ObjectIdentifier: (source: ImageTexture, handle: UnsafeMutableRawPointer)] = [:]

    /// The `ImageTexture` identities with a GPU copy cached right now.
    package var cachedTextureIdentities: Set<ObjectIdentifier> { Set(textures.keys) }
    /// How many image textures have been uploaded, ever.
    package private(set) var textureUploadCount = 0

    /// The SDL GPU driver in use (`metal`, `vulkan`, `direct3d12`).
    public var driver: String { String(cString: mui_renderer_driver(renderer)) }

    public func beginFrame() -> Float? {
        var width: UInt32 = 0, height: UInt32 = 0
        guard mui_renderer_begin(renderer, &width, &height) == 1 else { return nil }
        if let window { return mui_window_pixel_density(UnsafeMutableRawPointer(window)) }
        return offscreenScaleFactor
    }

    /// Each of `scene.textures`' GPU handles, in order — uploading what is not
    /// cached, releasing what the scene does not reference. `nil` when an
    /// upload failed (the frame is then not drawn).
    private func prepareTextures(for scene: Scene) -> [UnsafeMutableRawPointer]? {
        var kept: [ObjectIdentifier: (source: ImageTexture, handle: UnsafeMutableRawPointer)] = [:]
        var handles: [UnsafeMutableRawPointer] = []
        var failed = false
        for source in scene.textures {
            let key = ObjectIdentifier(source)
            if let cached = textures[key] ?? kept[key] {
                kept[key] = cached
                handles.append(cached.handle)
                continue
            }
            guard let handle = source.pixels.withUnsafeBufferPointer({
                mui_renderer_create_texture(renderer, $0.baseAddress, UInt32(source.width), UInt32(source.height))
            }) else { failed = true; break }
            textureUploadCount += 1
            kept[key] = (source, handle)
            handles.append(handle)
        }
        for (key, entry) in textures where kept[key] == nil {
            mui_renderer_release_texture(renderer, entry.handle)
        }
        textures = kept
        return failed ? nil : handles
    }

    public func finishFrame(scene: Scene, atlas: GlyphAtlas) -> Bool {
        // Exhaustive (ruling TE-AF): the old `kind == .glyph ? 1 : 0` drew an
        // image run as rects.
        let runs = scene.drawList.map { run -> ReplayRun in
            let kind: UInt32
            switch run.kind {
            case .rect: kind = 0
            case .glyph: kind = 1
            case .image: kind = 2
            }
            return ReplayRun(kind: kind, start: UInt32(run.start), count: UInt32(run.count))
        }
        guard let handles = prepareTextures(for: scene) else { return false }
        // Device-pixel coordinates, as the Metal renderer's surfaces use.
        let identity: [Float] = [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1]
        let dirty = atlas.dirtyRect != nil
        let optionalHandles: [UnsafeMutableRawPointer?] = handles
        let ok = scene.rects.withUnsafeBytes { rects in
            scene.glyphs.withUnsafeBytes { glyphs in
                scene.images.withUnsafeBytes { images in
                    optionalHandles.withUnsafeBufferPointer { textureBuffer in
                        runs.withUnsafeBufferPointer { runBuffer in
                            atlas.pixels.withUnsafeBufferPointer { pixels in
                                identity.withUnsafeBufferPointer { matrix in
                                    mui_renderer_finish(renderer,
                                                        rects.baseAddress, UInt32(rects.count),
                                                        glyphs.baseAddress, UInt32(glyphs.count),
                                                        images.baseAddress, UInt32(images.count),
                                                        textureBuffer.baseAddress, UInt32(optionalHandles.count),
                                                        runBuffer.baseAddress, UInt32(runs.count),
                                                        pixels.baseAddress, UInt32(atlas.width), UInt32(atlas.height),
                                                        dirty, matrix.baseAddress)
                                }
                            }
                        }
                    }
                }
            }
        }
        // As the Metal renderer does after its upload.
        if ok { atlas.clearDirtyRect() }
        return ok
    }

    /// The last offscreen frame, BGRA, row-major. Throws for a window renderer.
    public func readPixels(width: Int, height: Int) throws -> [UInt8] {
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        guard mui_renderer_read_offscreen(renderer, &pixels) else { throw SDLRendererError("readback") }
        return pixels
    }
}
