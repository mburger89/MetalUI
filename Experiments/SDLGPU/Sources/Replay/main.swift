import Foundation
import Metal
import simd
import MetalUI
import MetalUIText
import MetalUIShaderTypes
import MetalUIPortableText
import ReplayFixture
import SDLReplay
import AppKit

struct ProbeError: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}
func require(_ condition: Bool, _ message: String) throws {
    if !condition { throw ProbeError(message) }
}

// Rebind the existing MSL for SDL's documented uniform-then-storage convention.
// Keep the shader math shared: this first experiment isolates backend plumbing.
func sdlSource() throws -> String {
    var source = try ShaderLibrary.combinedSource()
    func replace(_ old: String, _ new: String) throws {
        try require(source.contains(old), "Shader adaptation anchor missing: \(old)")
        source = source.replacingOccurrences(of: old, with: new)
    }
    source = "struct ReplayViewport { float width, height; uint firstInstance, padding; };\n" + source
    try replace("constant MUISize &viewport", "constant ReplayViewport &viewport")
    try replace("constant MUISize  &viewport", "constant ReplayViewport &viewport")
    try replace("float2 unit = unitVertices[vertexID];", "instanceID += viewport.firstInstance;\n    float2 unit = unitVertices[vertexID];")
    for prefix in ["MUIRect", "MUIGlyph"] {
        try replace("\(prefix)BufferVertices   = 0", "\(prefix)BufferVertices   = 2")
        let data = prefix == "MUIRect" ? "Rects" : "Glyphs"
        let spaces = prefix == "MUIRect" ? "      " : "     "
        try replace("\(prefix)Buffer\(data)\(spaces)= 1", "\(prefix)Buffer\(data)\(spaces)= 3")
        try replace("\(prefix)BufferViewport   = 2", "\(prefix)BufferViewport   = 0")
        try replace("\(prefix)BufferProjection = 3", "\(prefix)BufferProjection = 1")
    }
    try replace("constant MUIRect *rects [[buffer(MUIRectBufferRects)]]", "constant MUIRect *rects [[buffer(0)]]")
    try replace("constant MUIGlyph *glyphs   [[buffer(MUIGlyphBufferGlyphs)]]", "constant MUIGlyph *glyphs   [[buffer(0)]]")
    // An explicit normalized sampler makes the sampling contract expressible
    // by SDL's API, unlike Metal's constexpr pixel-coordinate sampler.
    try replace("texture2d<float>   atlas    [[texture(MUIGlyphTextureAtlas)]]",
                "texture2d<float>   atlas    [[texture(MUIGlyphTextureAtlas)]], sampler sdlSampler [[sampler(0)]]")
    try replace("atlas.sample(atlas_sampler, in.atlasPosition)",
                "atlas.sample(sdlSampler, in.atlasPosition / float2(atlas.get_width(), atlas.get_height()))")
    return source
}

func bounds(_ x: Float, _ y: Float, _ w: Float, _ h: Float) -> MUIBounds {
    MUIBounds(origin: MUIPoint(x: x, y: y), size: MUISize(width: w, height: h))
}
func corners(_ radius: Float) -> MUICorners {
    MUICorners(topLeft: radius, topRight: radius, bottomRight: radius, bottomLeft: radius)
}
func color(_ h: Float, _ s: Float, _ l: Float, _ a: Float = 1) -> MUIHsla {
    MUIHsla(h: h, s: s, l: l, a: a)
}

@MainActor
func fixture(width: Int, height: Int, atlas: GlyphAtlas, addedText: Bool) throws -> Scene {
    var scene = Scene()
    let mask = bounds(0, 0, Float(width), Float(height))
    var order: UInt32 = 0
    func rect(_ b: MUIBounds, _ c: MUIHsla, radius: Float = 0, border: Float = 0,
              clip: MUIBounds? = nil, clipRadius: Float = 0) {
        scene.insert(MUIRect(bounds: b, contentMask: clip ?? mask,
            maskCornerRadii: corners(clipRadius), background: c,
            borderColor: color(0.13, 0.85, 0.7), cornerRadii: corners(radius),
            borderWidths: MUIEdges(top: border, right: border, bottom: border, left: border),
            order: order, _reserved: 0))
        order += 1
    }
    func text(_ value: String, x: Double, y: Double, size: Double, clip: MUIBounds? = nil) throws {
        let font = FontResolver.resolve(family: nil, size: size)
        let shaped = Shaper.shape(value, font: font, wrappingAt: Double(width - 70))
        for placed in shaped.placedGlyphs(at: (x, y), font: font, scaleFactor: 1) {
            let key = placed.key
            guard let packed = atlas.packed(for: key, rasterize: {
                GlyphRaster.rasterize(glyph: key.glyph, font: placed.font,
                    subpixelVariant: key.subpixelVariant, scaleFactor: key.scaleFactor)
            }) else { throw ProbeError("fixture atlas full") }
            if packed.slot.width == 0 || packed.slot.height == 0 { continue }
            scene.insert(MUIGlyph(
                bounds: bounds(Float(placed.pixelX + packed.left), Float(placed.baselineY - packed.top),
                               Float(packed.slot.width), Float(packed.slot.height)),
                atlasBounds: bounds(Float(packed.slot.x), Float(packed.slot.y), Float(packed.slot.width), Float(packed.slot.height)),
                contentMask: clip ?? mask, maskCornerRadii: corners(clip == nil ? 0 : 12),
                color: color(0.55, 0.1, 0.95), order: order, _reserved: 0))
            order += 1
        }
    }
    atlas.beginFrame()
    defer { atlas.endFrame() }
    rect(mask, color(0.62, 0.22, 0.12))
    rect(bounds(18.25, 18.75, Float(width - 36), Float(height - 36)), color(0.61, 0.25, 0.2), radius: 22, border: 2)
    try text("MetalUI / SDL GPU", x: 36.25, y: 33, size: 26)
    try text("Same scene. Two renderers.", x: 37, y: 72, size: 15)
    rect(bounds(36.5, 112.25, 160, 105), color(0.48, 0.75, 0.43), radius: 24, border: 5)
    rect(bounds(160, 139, 145, 70), color(0.94, 0.8, 0.6, 0.55), radius: 17)
    try text("overlap / clipping", x: 48, y: 146, size: 19)
    // A later translucent rectangle must cover some glyphs: draw order matters.
    rect(bounds(155, 152, 92, 25), color(0.08, 0.95, 0.5, 0.65), radius: 5)
    let clip = bounds(36, 237, Float(width - 72), 58)
    rect(bounds(20, 230, Float(width), 82), color(0.73, 0.5, 0.45), clip: clip, clipRadius: 12)
    try text("Rounded clip: abcdefghijklmnopqrstuvwxyz", x: 25, y: 249, size: 21, clip: clip)
    if addedText { try text("Atlas update: Ω Ж 日本語", x: 37, y: 315, size: 19) }
    scene.finalize()
    return scene
}

/// The repository's `Tests/Fonts/`, from this file's path.
func repositoryFont(_ file: String) throws -> [UInt8] {
    let url = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()   // main.swift -> Replay
        .deletingLastPathComponent()   // Sources
        .deletingLastPathComponent()   // SDLGPU
        .deletingLastPathComponent()   // Experiments
        .deletingLastPathComponent()   // the repository
        .appendingPathComponent("Tests/Fonts").appendingPathComponent(file)
    return [UInt8](try Data(contentsOf: url))
}

/// Frame 4 (ruling PT-G): the same layout as ``fixture``, with every glyph and
/// its coverage made by `PortableText` — HarfBuzz shapes, FreeType rasterizes,
/// into a `GlyphAtlas` no CoreText call has touched. Everything is emitted at
/// `order: 0`, as production does, so emission sequence alone is paint order
/// and the translucent rectangle still covers glyphs drawn before it.
func portableFixture(width: Int, height: Int, atlas: GlyphAtlas) throws -> Scene {
    var scene = Scene()
    let mask = bounds(0, 0, Float(width), Float(height))
    let bytes = try repositoryFont("NotoSans-Regular.ttf")
    var fonts: [Double: PortableFont] = [:]
    func rect(_ b: MUIBounds, _ c: MUIHsla, radius: Float = 0, border: Float = 0,
              clip: MUIBounds? = nil, clipRadius: Float = 0) {
        scene.insert(MUIRect(bounds: b, contentMask: clip ?? mask,
            maskCornerRadii: corners(clipRadius), background: c,
            borderColor: color(0.13, 0.85, 0.7), cornerRadii: corners(radius),
            borderWidths: MUIEdges(top: border, right: border, bottom: border, left: border),
            order: 0, _reserved: 0))
    }
    // `emit` takes the baseline, not the box's top-left: `size` below the top
    // is close to where ``fixture``'s CoreText lines sit, and nothing compares
    // the two frames' positions.
    func text(_ value: String, x: Double, y: Double, size: Double, clip: MUIBounds? = nil) throws {
        let font: PortableFont
        if let cached = fonts[size] { font = cached } else {
            font = try PortableFont(data: bytes, size: size)
            fonts[size] = font
        }
        try PortableText.emit(value, font: font, origin: (x, y + size), scaleFactor: 1,
                              color: color(0.55, 0.1, 0.95), contentMask: clip ?? mask,
                              maskCornerRadii: corners(clip == nil ? 0 : 12),
                              into: &scene, atlas: atlas)
    }
    atlas.beginFrame()
    defer { atlas.endFrame() }
    rect(mask, color(0.62, 0.22, 0.12))
    rect(bounds(18.25, 18.75, Float(width - 36), Float(height - 36)), color(0.61, 0.25, 0.2), radius: 22, border: 2)
    try text("MetalUI / SDL GPU", x: 36.25, y: 33, size: 26)
    try text("Portable text: HarfBuzz + FreeType.", x: 37, y: 72, size: 15)
    rect(bounds(36.5, 112.25, 160, 105), color(0.48, 0.75, 0.43), radius: 24, border: 5)
    rect(bounds(160, 139, 145, 70), color(0.94, 0.8, 0.6, 0.55), radius: 17)
    try text("overlap / clipping", x: 48, y: 146, size: 19)
    rect(bounds(155, 152, 92, 25), color(0.08, 0.95, 0.5, 0.65), radius: 5)
    let clip = bounds(36, 237, Float(width - 72), 58)
    rect(bounds(20, 230, Float(width), 82), color(0.73, 0.5, 0.45), clip: clip, clipRadius: 12)
    // Rounded like frames 0–3: `emit` takes the mask's corner radii.
    try text("Rounded clip: abcdefghijklmnopqrstuvwxyz", x: 25, y: 249, size: 21, clip: clip)
    // Through the clip's bottom-left 12 px corner, so the rounded mask decides
    // pixels: the line above sits between the corners and cannot see it.
    try text("WWW corner", x: 30, y: 274, size: 21, clip: clip)
    try text("Kerning AV To Ty, ligatures fi fl ffi, Ω Ж", x: 37.4, y: 315, size: 19)
    // LB-J: a paragraph wrapped by `emitLines` — UAX #14 breaks, one
    // `lineHeight` between baselines, the box's top-left as its origin.
    let paragraphFont = try PortableFont(data: bytes, size: 13)
    try PortableText.emitLines("Wrapped by emitLines: line breaks from libunibreak, "
                               + "one baseline every lineHeight, kerning kept across a break (AV To).",
                               font: paragraphFont, origin: (330.5, 108.25), wrappingAt: 262,
                               scaleFactor: 1, color: color(0.55, 0.1, 0.95), contentMask: mask,
                               into: &scene, atlas: atlas)
    scene.finalize()
    return scene
}

@MainActor
func metalPixels(_ scene: Scene, atlas: GlyphAtlas, renderer: Renderer,
                 width: Int, height: Int, projection: simd_float4x4) throws -> [UInt8] {
    let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm,
        width: width, height: height, mipmapped: false)
    descriptor.storageMode = .shared
    descriptor.usage = [.renderTarget, .shaderRead]
    guard let target = renderer.device.makeTexture(descriptor: descriptor),
          let command = renderer.commandQueue.makeCommandBuffer() else { throw ProbeError("Metal allocation failed") }
    renderer.upload(atlas)
    try renderer.encode(scene, view: SurfaceView(colorTexture: target,
        viewport: MTLViewport(originX: 0, originY: 0, width: Double(width), height: Double(height), znear: 0, zfar: 1),
        projection: projection), in: command)
    command.commit()
    command.waitUntilCompleted()
    try require(command.status == .completed, "Metal GPU failure: \(String(describing: command.error))")
    var bytes = [UInt8](repeating: 0, count: width * height * 4)
    target.getBytes(&bytes, bytesPerRow: width * 4, from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)
    return bytes
}

func savePNG(_ bytes: [UInt8], width: Int, height: Int, path: URL) throws {
    guard let provider = CGDataProvider(data: Data(bytes) as CFData),
          let image = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
            bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue).union(.byteOrder32Little),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent),
          let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
    else { throw ProbeError("PNG encoding failed") }
    try png.write(to: path)
}

/// Column-major, as `simd_float4x4` stores it and the shaders read it.
func floats(_ m: simd_float4x4) -> [Float] {
    withUnsafeBytes(of: m) { Array($0.bindMemory(to: Float.self)) }
}

@MainActor
func run() throws {
    let output = URL(fileURLWithPath: ProcessInfo.processInfo.environment["REPLAY_OUTPUT"] ?? "output", isDirectory: true)
    try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
    guard let device = MTLCreateSystemDefaultDevice() else { throw ProbeError("No Metal device") }
    let renderer = try Renderer(device: device)
    let source = try sdlSource()
    let arguments = CommandLine.arguments
    // --driver implies the portable shaders: only they exist as SPIR-V/DXIL.
    let driver = arguments.firstIndex(of: "--driver").flatMap { $0 + 1 < arguments.count ? arguments[$0 + 1] : nil }
    let portable = arguments.contains("--portable") || driver != nil
    let shaderDirectory = ProcessInfo.processInfo.environment["REPLAY_SHADERS"] ?? "Portable/Shaders/compiled"
    let replayer = portable
        ? try SDLReplayer(shaderDirectory: shaderDirectory, driver: driver ?? "metal")
        : try SDLReplayer(msl: source)
    print("Shader path: \(portable ? (driver == "vulkan" ? "HLSL -> SPIR-V" : driver == "direct3d12" ? "HLSL -> SPIR-V -> DXIL" : "HLSL -> SPIR-V -> MSL") : "adapted native MSL")")
    print("SDL GPU driver: \(replayer.driver); reference device: \(device.name)")
    let atlas = GlyphAtlas(width: 1024, height: 1024)
    // --record <dir> writes each frame as a fixture Portable/ can replay alone.
    let record = arguments.firstIndex(of: "--record").flatMap { $0 + 1 < arguments.count ? arguments[$0 + 1] : nil }
    if let record { try FileManager.default.createDirectory(atPath: record, withIntermediateDirectories: true) }
    var report = [String]()
    var reference = [UInt8]()
    var lastScene = Scene()
    // Frame 4's text is PortableText's, into its own atlas (ruling PT-G).
    let portableAtlas = GlyphAtlas(width: 1024, height: 1024)
    for (index, dimensions) in [(640, 380), (420, 360), (640, 380), (640, 380), (640, 380)].enumerated() {
        let (width, height) = dimensions
        let portable = index == 4
        let frameAtlas = portable ? portableAtlas : atlas
        let scene = portable
            ? try portableFixture(width: width, height: height, atlas: portableAtlas)
            : try fixture(width: width, height: height, atlas: atlas, addedText: index > 0)
        var projection = matrix_identity_float4x4
        if index == 3 { projection.columns.0.x = 0.85; projection.columns.1.y = 0.85 }
        let metal = try metalPixels(scene, atlas: frameAtlas, renderer: renderer, width: width, height: height, projection: projection)
        let sdl = try replayer.render(scene, atlas: frameAtlas, width: width, height: height, projection: floats(projection))
        let delta = pixelDifference(metal, sdl)
        let line = "frame \(index)\(portable ? " (portable text)" : "") \(width)x\(height): \(scene.rects.count) rects, \(scene.glyphs.count) glyphs, \(scene.drawList.count) runs; differing pixels=\(delta.pixels), max channel delta=\(delta.maxDelta)"
        print(line); report.append(line)
        try savePNG(metal, width: width, height: height, path: output.appendingPathComponent("metal-\(index).png"))
        try savePNG(sdl, width: width, height: height, path: output.appendingPathComponent("sdl-\(index).png"))
        try require(delta.maxDelta <= 1, "Parity failed: \(line)")
        if let record {
            let path = URL(fileURLWithPath: record).appendingPathComponent("frame-\(index).muireplay")
            try Data(ReplayFixture(scene: scene, atlas: frameAtlas, width: UInt32(width), height: UInt32(height),
                                   projection: floats(projection), reference: metal).encoded()).write(to: path)
        }
        // This tolerance only permits UNORM rounding, never misplaced edges.
        // The control below stays on frame 3, whose projection it assumes.
        if index == 3 { reference = metal; lastScene = scene }
    }
    var projection = matrix_identity_float4x4
    projection.columns.0.x = 0.85; projection.columns.1.y = 0.85
    // Positive control: make the backend violate painter order, without changing the Metal reference.
    let last = try ReplayFixture(scene: lastScene, atlas: atlas, width: 640, height: 380,
                                 projection: floats(projection), reference: reference)
    let mutant = try replayer.render(lastScene, atlas: atlas, width: 640, height: 380,
                                     projection: floats(projection), runs: last.orderMutatedRuns)
    let delta = pixelDifference(reference, mutant)
    try savePNG(mutant, width: 640, height: 380, path: output.appendingPathComponent("mutant-order.png"))
    try require(delta.pixels > 100 && delta.maxDelta > 16, "Broken comparison: draw-order mutation did not move enough pixels")
    let control = "draw-order mutation: differing pixels=\(delta.pixels), max channel delta=\(delta.maxDelta) (detected)"
    print(control); report.append(control)
    // Restore the final live window to the correct scene after the control.
    _ = try replayer.render(lastScene, atlas: atlas, width: 640, height: 380, projection: floats(matrix_identity_float4x4))
    try report.joined(separator: "\n").appending("\n").write(to: output.appendingPathComponent("results.txt"), atomically: true, encoding: .utf8)
    if CommandLine.arguments.contains("--show") {
        try replayer.show(seconds: 30)
    }
    print("PASS; artifacts: \(output.path)")
}

do { try run() } catch { fputs("ERROR: \(error)\n", stderr); exit(1) }
