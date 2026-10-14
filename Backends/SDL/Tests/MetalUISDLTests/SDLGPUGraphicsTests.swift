import Foundation
import Testing
import MetalUICore
import MetalUIPlatform
import MetalUIScene
import MetalUIShaderTypes
import MetalUISDLGPU
@testable import MetalUISDL
@testable import MetalUISDLGPU
import ReplayFixture

// Graphics into a texture and into a GPUSurface (rulings GA-H, GA-M; spec §6
// G1-G5, plus G6 for the vertex-buffer and blend fields the spec's list left
// unpinned). Every test draws into an app-made texture on an owned device and
// reads it back; G1s also draws into the real surface target of an offscreen
// `SDLWindowRenderer`, which runs surface draws without a presented frame
// (C9 relies on it), so GA-M's `windowsPresentFrames` gate is not needed.
//
// The triangle set (`AppShaders/tri.vert.hlsl`): one triangle, three
// instances shifted by (0,0), (0.25,0.25), (0.5,0.5) NDC at depths 0.5, 0.3, 0.7,
// coloured red, green, blue. Instance 1 is nearest everywhere it overlaps; the
// draw order 0, 1, 2 makes a missing depth test show instance 2 over it.

private let size = 32

/// The CPU reference: which instance covers a point, by exact edge functions.
private enum TriangleSet {
    static let corners: [(Double, Double)] = [(-0.9, -0.9), (0.1, -0.9), (-0.9, 0.1)]
    static let shifts: [(Double, Double)] = [(0, 0), (0.25, 0.25), (0.5, 0.5)]
    static let depths: [Double] = [0.5, 0.3, 0.7]
    static let colors: [[UInt8]] = [[255, 0, 0, 255], [0, 255, 0, 255], [0, 0, 255, 255]]

    static func contains(_ instance: Int, ndcX x: Double, ndcY y: Double) -> Bool {
        let (sx, sy) = shifts[instance]
        let points = corners.map { ($0.0 + sx, $0.1 + sy) }
        func edge(_ a: (Double, Double), _ b: (Double, Double)) -> Double {
            (b.0 - a.0) * (y - a.1) - (b.1 - a.1) * (x - a.0)
        }
        let e = [edge(points[0], points[1]), edge(points[1], points[2]), edge(points[2], points[0])]
        return e.allSatisfy { $0 > 0 }
    }

    /// The nearest of the first `instances` instances covering the pixel's
    /// centre, or `nil` for the background.
    static func label(x: Int, y: Int, instances: Int) -> Int? {
        let ndcX = (Double(x) + 0.5) / Double(size) * 2 - 1
        let ndcY = 1 - (Double(y) + 0.5) / Double(size) * 2
        let covering = (0..<instances).filter { contains($0, ndcX: ndcX, ndcY: ndcY) }
        return covering.min { depths[$0] < depths[$1] }
    }

    /// The pixels whose 3 × 3 neighbourhood of centres is all one label: no
    /// triangle edge crosses the hull of those centres, which holds every sample
    /// position of the pixel, so its colour is exact whatever the sample pattern.
    static func stablePixels(instances: Int) -> [(x: Int, y: Int, label: Int?)] {
        var result: [(Int, Int, Int?)] = []
        for y in 1..<(size - 1) {
            for x in 1..<(size - 1) {
                let here = label(x: x, y: y, instances: instances)
                var same = true
                for dy in -1...1 { for dx in -1...1 where label(x: x + dx, y: y + dy, instances: instances) != here { same = false } }
                if same { result.append((x, y, here)) }
            }
        }
        return result
    }
}

private func library() throws -> SDLGPUShaderLibrary {
    try SDLGPUShaderLibrary(directory: GPUTestSupport.compiledShaders)
}

private func pipeline(_ device: SDLGPUDevice, vertex: String, fragment: String,
                      colorFormat: SDLGPUTextureFormat, sampleCount: SDLGPUSampleCount = .one,
                      depth: SDLGPUDepthState? = nil, blend: SDLGPUBlend = .none,
                      vertexBuffers: [SDLGPUVertexBufferDescription] = [],
                      vertexAttributes: [SDLGPUVertexAttribute] = []) throws -> SDLGPUGraphicsPipeline {
    let library = try library()
    let description = SDLGPUGraphicsPipelineDescription(
        vertex: try library.vertex(vertex, for: device), fragment: try library.fragment(fragment, for: device),
        vertexBuffers: vertexBuffers, vertexAttributes: vertexAttributes, colorFormat: colorFormat,
        blend: blend, sampleCount: sampleCount, depth: depth)
    return try #require(device.makePipelineOrNil(description), "\(SDLGPUError("graphics pipeline"))")
}

extension SDLGPUDevice {
    fileprivate func makePipelineOrNil(_ description: SDLGPUGraphicsPipelineDescription) -> SDLGPUGraphicsPipeline? {
        makeGraphicsPipeline(description)
    }
}

/// The sample count the colour pass of G1 runs at (mutation G1-a sets `.one`).
private let samples: SDLGPUSampleCount = .four
/// How many instances the colour pass of G1 draws (mutation G1-c sets 2).
private let instanceCount = 3

/// The textures of one triangle-set render at `format`/`samples`: where the
/// colour pass draws (the multisample texture, or `resolved` itself at one sample)
/// and the depth texture.
private struct TriangleTargets {
    let resolved: SDLGPUTexture
    let multisample: SDLGPUTexture?
    let depth: SDLGPUTexture

    var drawTarget: SDLGPUTexture { multisample ?? resolved }

    init(device: SDLGPUDevice, resolved: SDLGPUTexture, format: SDLGPUTextureFormat, samples: SDLGPUSampleCount) throws {
        self.resolved = resolved
        if samples == .one {
            multisample = nil
        } else {
            let made: SDLGPUTexture = try #require(device.makeTexture(SDLGPUTextureDescription(
                width: size, height: size, format: format, usage: [.colorTarget], sampleCount: samples)))
            multisample = made
        }
        depth = try #require(device.makeTexture(SDLGPUTextureDescription(
            width: size, height: size, format: .d32Float, usage: [.depthStencilTarget], sampleCount: samples)))
    }

    /// Records the colour pass: clear to opaque black, draw `instances`
    /// instances of the triangle, resolve into `resolved` when multisampled.
    func record(into commandBuffer: SDLGPUCommandBuffer, pipeline: SDLGPUGraphicsPipeline, instances: Int,
                clear: (red: Float, green: Float, blue: Float, alpha: Float) = (0, 0, 0, 1)) {
        let color = SDLGPUColorAttachment(
            texture: drawTarget, loadOp: .clear, clearColor: clear,
            storeOp: multisample == nil ? .store : .resolve, resolveTexture: multisample == nil ? nil : resolved)
        guard let pass = commandBuffer.beginRenderPass(color: color, depth: SDLGPUDepthAttachment(texture: depth)) else { return }
        pass.bind(pipeline)
        pass.draw(vertexCount: 3, instanceCount: instances)
        pass.end()
    }
}

/// RGBA at (x, y) of a tightly packed 4-byte-texel image `size` wide.
private func texel(_ pixels: [UInt8], _ x: Int, _ y: Int, bgra: Bool) -> [UInt8] {
    let i = (y * size + x) * 4
    return bgra ? [pixels[i + 2], pixels[i + 1], pixels[i], pixels[i + 3]] : Array(pixels[i..<i + 4])
}

/// Checks a colour image against the reference: every stable pixel is its
/// label's colour (opaque black for the background); returns how many pixels are
/// none of the four pure colours (the resolved edges).
private func verifyTriangleSet(_ pixels: [UInt8], bgra: Bool, instances: Int) throws -> Int {
    #expect(pixels.count == size * size * 4)
    let stable = TriangleSet.stablePixels(instances: instances)
    try #require(stable.count > 400, "the reference has interior pixels to compare")
    for instance in 0..<instances {
        try #require(stable.filter { $0.label == instance }.count >= 20, "instance \(instance) has pixels of its own")
    }
    var wrong: [String] = []
    for (x, y, label) in stable {
        let expected = label.map { TriangleSet.colors[$0] } ?? [0, 0, 0, 255]
        let actual = texel(pixels, x, y, bgra: bgra)
        if actual != expected && wrong.count < 6 { wrong.append("(\(x),\(y)) \(actual) want \(expected)") }
    }
    #expect(wrong.isEmpty, "stable pixels differing from the reference: \(wrong)")
    let pure: [[UInt8]] = TriangleSet.colors + [[0, 0, 0, 255]]
    var partial = 0
    for y in 0..<size { for x in 0..<size where !pure.contains(texel(pixels, x, y, bgra: bgra)) { partial += 1 } }
    return partial
}

@MainActor @Suite(.serialized) struct SDLGPUGraphicsTests {
    /// **G1.** Three instances of one triangle at different depths with
    /// overlapping area, depth-tested `LESS`, 4× multisampled and resolved into
    /// an RGBA texture on an owned device; read back. Every pixel whose
    /// neighbourhood no edge crosses equals the CPU reference's colour (the
    /// nearest instance wins, not the last drawn), and edge pixels are partial
    /// blends — the resolve happened.
    /// Mutations: `samples` 4 to 1 (no partial pixel), depth `LESS` to `ALWAYS` in
    /// the compare mapping (the overlap shows the last instance), `instanceCount`
    /// 3 to 2 (instance 2 absent), the `.resolve` store mapped to `DONT_CARE`
    /// (the resolve texture unwritten).
    @Test(.enabled(if: GPUTestSupport.available, GPUTestSupport.skipReason))
    func anInstancedDepthTestedMSAAResolvedTriangleSetMatchesItsReference() async throws {
        let device = try GPUTestSupport.requireDevice()
        let resolved = try #require(device.makeTexture(SDLGPUTextureDescription(
            width: size, height: size, format: .r8g8b8a8Unorm, usage: [.colorTarget, .sampler])))
        let targets = try TriangleTargets(device: device, resolved: resolved, format: .r8g8b8a8Unorm, samples: samples)
        let triangles = try pipeline(device, vertex: "tri", fragment: "tri", colorFormat: .r8g8b8a8Unorm,
                                     sampleCount: samples, depth: SDLGPUDepthState())
        let fence = try await device.submitBatch { commandBuffer in
            targets.record(into: commandBuffer, pipeline: triangles, instances: instanceCount)
        }
        await fence.wait()
        let pixels = try #require(await device.download(resolved))
        let partial = try verifyTriangleSet(pixels, bgra: false, instances: 3)
        #expect(partial > 0, "a multisampled resolve leaves partially covered edge pixels")
    }

    /// **G1s.** The same render into a real `GPUSurface` target: the draw takes
    /// the typed view of its frame, builds its pipeline, multisample and depth
    /// textures on the borrowed device on the first draw, draws into
    /// `view.target` (the resolve texture) and the offscreen renderer
    /// composites the surface over opaque black. The composite equals the
    /// reference at every stable pixel and resolves edges.
    @Test(.enabled(if: GPUTestSupport.available, GPUTestSupport.skipReason))
    func theSameTriangleSetDrawnIntoARealSurfaceTargetMatchesItsReference() async throws {
        #if os(macOS)
        armMainRunLoopExitCheck()
        #endif
        let renderer = try SDLWindowRenderer(offscreenWidth: size, height: size)
        final class State: @unchecked Sendable {
            nonisolated(unsafe) var targets: TriangleTargets?
            nonisolated(unsafe) var pipeline: SDLGPUGraphicsPipeline?
            nonisolated(unsafe) var failure: String?
        }
        let state = State()
        let surfaceTarget = SurfaceTarget(id: SurfaceID(rawValue: 1), width: size, height: size)
        let request = SurfaceDrawRequest(target: surfaceTarget, scaleFactor: 1, time: 0, policy: .continuous, value: nil) { ctx in
            guard let sdl = ctx as? SDLGPUDrawContext else { state.failure = "not an SDL draw context"; return }
            let view = sdl.view
            do {
                if state.pipeline == nil {
                    state.pipeline = try pipeline(view.device, vertex: "tri", fragment: "tri", colorFormat: .b8g8r8a8Unorm,
                                                  sampleCount: samples, depth: SDLGPUDepthState())
                    state.targets = try TriangleTargets(device: view.device, resolved: view.target,
                                                        format: .b8g8r8a8Unorm, samples: samples)
                }
                state.targets?.record(into: view.commandBuffer, pipeline: state.pipeline!, instances: instanceCount)
            } catch { state.failure = "\(error)" }
        }
        let scene = surfaceScene(side: size, target: surfaceTarget)
        try #require(renderer.beginFrame() != nil)
        try #require(renderer.finishFrame(scene: scene, atlas: GlyphAtlas(width: 16, height: 16), surfaces: [request]))
        try #require(state.failure == nil, "\(state.failure ?? "")")
        let pixels = try renderer.readPixels(width: size, height: size)
        let partial = try verifyTriangleSet(pixels, bgra: true, instances: 3)
        #expect(partial > 0, "the surface target holds the resolved edges")
    }

    /// **G2.** An ID pass: the instance index plus one written to an `R32_UINT`
    /// target, depth-tested, read back. Every stable pixel holds its label's
    /// id (0 for the background), and all four values occur — picking reads the
    /// nearest instance under a pixel.
    /// Mutation: `id.frag.hlsl` returns `instance + 2` (blobs rebuilt).
    @Test(.enabled(if: GPUTestSupport.available, GPUTestSupport.skipReason))
    func anIDPassReadsBackTheInstanceUnderAPixel() async throws {
        let device = try GPUTestSupport.requireDevice()
        let ids = try #require(device.makeTexture(SDLGPUTextureDescription(
            width: size, height: size, format: .r32Uint, usage: [.colorTarget, .sampler])))
        let targets = try TriangleTargets(device: device, resolved: ids, format: .r32Uint, samples: .one)
        let picking = try pipeline(device, vertex: "tri", fragment: "id", colorFormat: .r32Uint, depth: SDLGPUDepthState())
        let fence = try await device.submitBatch { commandBuffer in
            targets.record(into: commandBuffer, pipeline: picking, instances: 3, clear: (0, 0, 0, 0))
        }
        await fence.wait()
        let words = GPUTestSupport.words(from: try #require(await device.download(ids)))
        try #require(words.count == size * size)
        let stable = TriangleSet.stablePixels(instances: 3)
        var wrong: [String] = []
        for (x, y, label) in stable {
            let expected = UInt32((label ?? -1) + 1)
            if words[y * size + x] != expected && wrong.count < 6 { wrong.append("(\(x),\(y)) \(words[y * size + x]) want \(expected)") }
        }
        #expect(wrong.isEmpty, "\(wrong)")
        #expect(Set(stable.map { words[$0.y * size + $0.x] }) == [0, 1, 2, 3], "background and all three instances occur")
    }

    /// **G3.** A 16 × 16 `R8` texture's mip chain generated by the GPU: mip 1 and
    /// mip 2 equal the box average of their parents within quantisation (the
    /// downsample rounds at each level; measured, never more than 2).
    /// Mutation: the `generateMipmaps` call skipped (the levels read zero).
    @Test(.enabled(if: GPUTestSupport.available, GPUTestSupport.skipReason))
    func generatedMipmapsOfAnR8TextureAverageTheirParents() async throws {
        let device = try GPUTestSupport.requireDevice()
        let texture = try #require(device.makeTexture(SDLGPUTextureDescription(
            width: 16, height: 16, format: .r8Unorm, usage: [.sampler, .colorTarget], levelCount: 5)))
        let level0 = (0..<256).map { UInt8(truncatingIfNeeded: ($0 % 16) * 13 + ($0 / 16) * 29 + ($0 * 7) % 11) }
        try #require(await device.upload(level0, to: texture))
        let fence = try await device.submitBatch { commandBuffer in commandBuffer.generateMipmaps(of: texture) }
        await fence.wait()
        for level in [1, 2] {
            let side = 16 >> level, block = 1 << level
            let actual = try #require(await device.download(texture, mipLevel: level))
            try #require(actual.count == side * side)
            var worst = 0
            for y in 0..<side { for x in 0..<side {
                var sum = 0
                for dy in 0..<block { for dx in 0..<block { sum += Int(level0[(y * block + dy) * 16 + x * block + dx]) } }
                let mean = Double(sum) / Double(block * block)
                worst = max(worst, Int((abs(Double(actual[y * side + x]) - mean)).rounded(.up)))
            } }
            #expect(worst <= 2, "mip \(level) is within 2 levels of its box average (worst \(worst))")
        }
    }

    /// **G4.** The vertex stage reads its positions from a storage buffer
    /// (`pos.vert.hlsl`, `StructuredBuffer` in space0), one cyan triangle: every
    /// stable pixel equals the reference, inside and out.
    /// Mutation: the buffer bound at slot 1 (the shader reads zeros).
    @Test(.enabled(if: GPUTestSupport.available, GPUTestSupport.skipReason))
    func aVertexStageReadsAStorageBuffer() async throws {
        let device = try GPUTestSupport.requireDevice()
        let target = try #require(device.makeTexture(SDLGPUTextureDescription(
            width: size, height: size, format: .r8g8b8a8Unorm, usage: [.colorTarget, .sampler])))
        let positions: [Float] = TriangleSet.corners.flatMap { [Float($0.0), Float($0.1), 0.5, 1] }
        let buffer = try #require(device.makeBuffer(size: positions.count * 4, usage: [.graphicsStorageRead]))
        try #require(await device.upload(positions.withUnsafeBytes { Array($0) }, to: buffer))
        let storage = try pipeline(device, vertex: "pos", fragment: "tri", colorFormat: .r8g8b8a8Unorm)
        let fence = try await device.submitBatch { commandBuffer in
            guard let pass = commandBuffer.beginRenderPass(
                color: SDLGPUColorAttachment(texture: target, clearColor: (0, 0, 0, 1))) else { return }
            pass.bind(storage)
            pass.bindVertexStorageBuffers([buffer], firstSlot: 0)
            pass.draw(vertexCount: 3)
            pass.end()
        }
        await fence.wait()
        let pixels = try #require(await device.download(target))
        var wrong: [String] = []
        for (x, y, label) in TriangleSet.stablePixels(instances: 1) {
            let expected: [UInt8] = label == nil ? [0, 0, 0, 255] : [0, 255, 255, 255]
            let actual = texel(pixels, x, y, bgra: false)
            if actual != expected && wrong.count < 6 { wrong.append("(\(x),\(y)) \(actual) want \(expected)") }
        }
        #expect(wrong.isEmpty, "\(wrong)")
    }

    /// **G5.** A fragment stage samples one mip level of an `R8` texture through a
    /// sampler and a pushed uniform: a full-screen triangle over a 4 × 4 target
    /// at level 2 reproduces mip 2's bytes exactly (nearest filters, texel centres).
    /// Mutation: the pushed level 2 changed to 1.
    @Test(.enabled(if: GPUTestSupport.available, GPUTestSupport.skipReason))
    func aFragmentStageSamplesAMipLevelThroughASampler() async throws {
        let device = try GPUTestSupport.requireDevice()
        let texture = try #require(device.makeTexture(SDLGPUTextureDescription(
            width: 16, height: 16, format: .r8Unorm, usage: [.sampler, .colorTarget], levelCount: 5)))
        let level0 = (0..<256).map { UInt8(truncatingIfNeeded: ($0 % 16) * 13 + ($0 / 16) * 29 + ($0 * 7) % 11) }
        try #require(await device.upload(level0, to: texture))
        let mips = try await device.submitBatch { $0.generateMipmaps(of: texture) }
        await mips.wait()
        let expected = try #require(await device.download(texture, mipLevel: 2))
        let target = try #require(device.makeTexture(SDLGPUTextureDescription(
            width: 4, height: 4, format: .r8g8b8a8Unorm, usage: [.colorTarget, .sampler])))
        let sampler = try #require(device.makeSampler(SDLGPUSamplerDescription(filter: .nearest, mipmapFilter: .nearest)))
        let sampling = try pipeline(device, vertex: "fullscreen", fragment: "tex", colorFormat: .r8g8b8a8Unorm)
        let level: [UInt8] = Float(2).bitPattern.littleEndianBytes + [UInt8](repeating: 0, count: 12)
        let fence = try await device.submitBatch { commandBuffer in
            guard let pass = commandBuffer.beginRenderPass(color: SDLGPUColorAttachment(texture: target)) else { return }
            pass.bind(sampling)
            pass.bindFragmentSamplers([(texture, sampler)])
            pass.pushFragmentUniform(level, at: 0)
            pass.draw(vertexCount: 3)
            pass.end()
        }
        await fence.wait()
        let pixels = try #require(await device.download(target))
        let grey = (0..<16).map { pixels[$0 * 4] }
        #expect(grey == expected, "sampled \(grey) want \(expected)")
        #expect((0..<16).allSatisfy { pixels[$0 * 4 + 1] == pixels[$0 * 4] && pixels[$0 * 4 + 3] == 255 })
    }

    /// **G6.** An interleaved vertex buffer (position `float2`, premultiplied colour
    /// `float4`) and premultiplied blending: a half-transparent red triangle over
    /// opaque white leaves (255, 128, 128, 255) inside and white outside, within one
    /// level (the blend rounds).
    /// Mutations: `blend` `.premultipliedAlpha` mapped to no blend (inside is
    /// half red), the colour attribute's offset 8 changed to 0 (the colour reads
    /// the position).
    @Test(.enabled(if: GPUTestSupport.available, GPUTestSupport.skipReason))
    func anInterleavedVertexBufferAndPremultipliedBlendDrawTheReferenceImage() async throws {
        let device = try GPUTestSupport.requireDevice()
        let target = try #require(device.makeTexture(SDLGPUTextureDescription(
            width: size, height: size, format: .r8g8b8a8Unorm, usage: [.colorTarget, .sampler])))
        let vertices: [Float] = TriangleSet.corners.flatMap { [Float($0.0), Float($0.1), 0.5, 0, 0, 0.5] }
        let buffer = try #require(device.makeBuffer(size: vertices.count * 4, usage: [.vertex]))
        try #require(await device.upload(vertices.withUnsafeBytes { Array($0) }, to: buffer))
        let drawing = try pipeline(
            device, vertex: "vbuf", fragment: "tri", colorFormat: .r8g8b8a8Unorm, blend: .premultipliedAlpha,
            vertexBuffers: [SDLGPUVertexBufferDescription(slot: 0, pitch: 24)],
            vertexAttributes: [SDLGPUVertexAttribute(location: 0, format: .float2, offset: 0),
                               SDLGPUVertexAttribute(location: 1, format: .float4, offset: 8)])
        let fence = try await device.submitBatch { commandBuffer in
            guard let pass = commandBuffer.beginRenderPass(
                color: SDLGPUColorAttachment(texture: target, clearColor: (1, 1, 1, 1))) else { return }
            pass.bind(drawing)
            pass.bindVertexBuffers([buffer])
            pass.draw(vertexCount: 3)
            pass.end()
        }
        await fence.wait()
        let pixels = try #require(await device.download(target))
        var wrong: [String] = []
        for (x, y, label) in TriangleSet.stablePixels(instances: 1) {
            let expected = label == nil ? [255, 255, 255, 255] : [255, 128, 128, 255]
            let actual = texel(pixels, x, y, bgra: false).map { Int($0) }
            if zip(actual, expected).contains(where: { abs($0 - $1) > 1 }) && wrong.count < 6 {
                wrong.append("(\(x),\(y)) \(actual) want \(expected)")
            }
        }
        #expect(wrong.isEmpty, "\(wrong)")
    }
}

extension UInt32 {
    fileprivate var littleEndianBytes: [UInt8] { (0..<4).map { UInt8(truncatingIfNeeded: self >> UInt32(8 * $0)) } }
}

/// A `side` × `side` scene: opaque black, then the surface's quad over all of it.
@MainActor
func surfaceScene(side: Int, target: SurfaceTarget) -> Scene {
    var scene = Scene()
    let bounds = MUIBounds(origin: MUIPoint(x: 0, y: 0), size: MUISize(width: Float(side), height: Float(side)))
    let none = MUICorners(topLeft: 0, topRight: 0, bottomRight: 0, bottomLeft: 0)
    let black = MUIHsla(h: 0, s: 0, l: 0, a: 1)
    scene.insert(MUIRect(bounds: bounds, contentMask: bounds, maskCornerRadii: none, background: black, borderColor: black,
                         cornerRadii: none, borderWidths: MUIEdges(top: 0, right: 0, bottom: 0, left: 0),
                         order: 0, shape: 0))
    scene.insert(MUIImage(bounds: bounds, contentMask: bounds, maskCornerRadii: none, opacity: 1, texture: 0,
                          filter: MUIUInt(MUIImageFilterLinear.rawValue), order: 1), surface: target)
    scene.finalize()
    return scene
}
