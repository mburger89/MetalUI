import Foundation
import Testing
import MetalUISDLGPU
@testable import MetalUISDLGPU

// The graphics gaps MetalCreator's xp-3 3D viewport asked for (rulings GB-B to
// GB-E, GB-I, GB-J; spec tests V1-V4, W1-W2, F1-F3, A1-A2): viewport and scissor
// on a render pass, a colour write mask, `r32Float` and sampler anisotropy.
// Every draw test renders into an app-made texture on an owned device and reads
// it back. The red-first state of each is a compile failure (the API is absent);
// the mutation each pin must redden is on its doc comment.

private let side = 32
private let blue: [UInt8] = [0, 0, 255, 255]
private let red: [UInt8] = [255, 0, 0, 255]
private let green: [UInt8] = [0, 255, 0, 255]

private func library() throws -> SDLGPUShaderLibrary {
    try SDLGPUShaderLibrary(directory: GPUTestSupport.compiledShaders)
}

private func makePipeline(_ device: SDLGPUDevice, vertex: String, fragment: String,
                          colorFormat: SDLGPUTextureFormat = .r8g8b8a8Unorm,
                          depth: SDLGPUDepthState? = nil, writesColor: Bool = true) throws -> SDLGPUGraphicsPipeline {
    let library = try library()
    let description = SDLGPUGraphicsPipelineDescription(
        vertex: try library.vertex(vertex, for: device), fragment: try library.fragment(fragment, for: device),
        colorFormat: colorFormat, depth: depth, writesColor: writesColor)
    return try #require(device.makeGraphicsPipeline(description), "\(SDLGPUError("graphics pipeline"))")
}

private func colorTarget(_ device: SDLGPUDevice) throws -> SDLGPUTexture {
    try #require(device.makeTexture(SDLGPUTextureDescription(
        width: side, height: side, format: .r8g8b8a8Unorm, usage: [.colorTarget, .sampler])))
}

private func texel(_ pixels: [UInt8], _ x: Int, _ y: Int) -> [UInt8] {
    let i = (y * side + x) * 4
    return Array(pixels[i..<i + 4])
}

/// What a recorded closure learned (a `@Sendable` closure cannot capture a var).
private final class Answers: @unchecked Sendable {
    nonisolated(unsafe) var values: [Bool] = []
}

/// Draws the fullscreen red triangle into a blue-cleared target after `configure`
/// has set the pass state, and reads the target back.
private func drawRed(_ device: SDLGPUDevice, answers: Answers = Answers(),
                     configure: @escaping @Sendable (SDLGPURenderPass, Answers) -> Void) async throws -> [UInt8] {
    let target = try colorTarget(device)
    let red = try makePipeline(device, vertex: "fullscreen", fragment: "flat")
    let fence = try await device.submitBatch { commandBuffer in
        guard let pass = commandBuffer.beginRenderPass(
            color: SDLGPUColorAttachment(texture: target, clearColor: (0, 0, 1, 1))) else { return }
        pass.bind(red)
        configure(pass, answers)
        pass.draw(vertexCount: 3)
        pass.end()
    }
    await fence.wait()
    return try #require(await device.download(target))
}

@MainActor @Suite(.serialized) struct SDLGPUGapsTests {
    /// **V1.** A fullscreen red draw into a 32 x 32 blue target under
    /// `setViewport(8, 8, 16, 16)`: pixels well inside are red, pixels outside are
    /// still the clear colour. Mutation: `setViewport` ignores its arguments.
    @Test(.enabled(if: GPUTestSupport.available, GPUTestSupport.skipReason))
    func aViewportConfinesADrawToItsRect() async throws {
        let device = try GPUTestSupport.requireDevice()
        let pixels = try await drawRed(device) { pass, answers in
            answers.values.append(pass.setViewport(x: 8, y: 8, width: 16, height: 16))
        }
        for y in 0..<side {
            for x in 0..<side {
                let inside = (9...22).contains(x) && (9...22).contains(y)
                let outside = x <= 6 || x >= 25 || y <= 6 || y >= 25
                if inside { #expect(texel(pixels, x, y) == red, "(\(x),\(y)) inside") }
                if outside { #expect(texel(pixels, x, y) == blue, "(\(x),\(y)) outside") }
            }
        }
    }

    /// **V2.** The same under `setScissor(4, 12, 10, 8)`. Mutation: the scissor
    /// body is empty.
    @Test(.enabled(if: GPUTestSupport.available, GPUTestSupport.skipReason))
    func aScissorConfinesADrawToItsRect() async throws {
        let device = try GPUTestSupport.requireDevice()
        let pixels = try await drawRed(device) { pass, _ in _ = pass.setScissor(x: 4, y: 12, width: 10, height: 8) }
        for y in 0..<side {
            for x in 0..<side {
                let inside = (5...12).contains(x) && (13...18).contains(y)
                let outside = x <= 2 || x >= 15 || y <= 10 || y >= 21
                if inside { #expect(texel(pixels, x, y) == red, "(\(x),\(y)) inside") }
                if outside { #expect(texel(pixels, x, y) == blue, "(\(x),\(y)) outside") }
            }
        }
    }

    /// **V3.** A zero, negative or NaN viewport size and a negative scissor size
    /// answer `false`, make no SDL call and trap nothing: the whole target is
    /// drawn. A legal call answers `true`. Mutation: the refusal guards removed.
    @Test(.enabled(if: GPUTestSupport.available, GPUTestSupport.skipReason))
    func aDegenerateViewportOrScissorIsRefusedWithoutATrap() async throws {
        let device = try GPUTestSupport.requireDevice()
        let answers = Answers()
        let pixels = try await drawRed(device, answers: answers) { pass, answers in
            answers.values = [
                pass.setViewport(x: 0, y: 0, width: 0, height: 8),
                pass.setViewport(x: 0, y: 0, width: 8, height: -1),
                pass.setViewport(x: 0, y: 0, width: .nan, height: 8),
                pass.setViewport(x: .infinity, y: 0, width: 8, height: 8),
                pass.setScissor(x: 0, y: 0, width: -1, height: 8),
                pass.setScissor(x: 0, y: 0, width: 8, height: -3),
            ]
        }
        #expect(answers.values == Array(repeating: false, count: 6))
        for (x, y) in [(0, 0), (31, 31), (16, 16), (0, 31), (31, 0)] { #expect(texel(pixels, x, y) == red) }
        let legal = Answers()
        _ = try await drawRed(device, answers: legal) { pass, answers in
            answers.values = [pass.setViewport(x: 0, y: 0, width: 32, height: 32), pass.setScissor(x: 0, y: 0, width: 32, height: 32)]
        }
        #expect(legal.values == [true, true])
    }

    /// **V4.** A scissor past the target is clamped to the intersection, and an
    /// empty intersection draws nothing and does not trap. Mutation: the clamp
    /// removed.
    @Test(.enabled(if: GPUTestSupport.available, GPUTestSupport.skipReason))
    func aScissorIsClampedToTheTarget() async throws {
        let device = try GPUTestSupport.requireDevice()
        let low = try await drawRed(device) { pass, _ in _ = pass.setScissor(x: -4, y: -4, width: 12, height: 12) }
        #expect(texel(low, 0, 0) == red && texel(low, 7, 7) == red)
        #expect(texel(low, 8, 8) == blue && texel(low, 9, 0) == blue && texel(low, 0, 9) == blue)
        let high = try await drawRed(device) { pass, _ in _ = pass.setScissor(x: 28, y: 28, width: 100, height: 100) }
        #expect(texel(high, 28, 28) == red && texel(high, 31, 31) == red)
        #expect(texel(high, 27, 27) == blue && texel(high, 27, 31) == blue && texel(high, 31, 27) == blue)
        let answers = Answers()
        let none = try await drawRed(device, answers: answers) { pass, answers in
            answers.values = [pass.setScissor(x: 40, y: 40, width: 5, height: 5), pass.setScissor(x: -9, y: 0, width: 4, height: 4)]
        }
        #expect(answers.values == [true, true])
        for (x, y) in [(0, 0), (31, 31), (16, 16), (3, 3)] { #expect(texel(none, x, y) == blue) }
    }

    /// Two passes over one blue colour target and one depth texture: pass 1 is a
    /// depth-only prepass (fullscreen at depth 0) with `writesColor`; pass 2 loads
    /// the colour, loads or clears the depth, and draws the triangle set.
    private func twoPasses(writesColor: Bool, clearsDepthInPass2: Bool) async throws -> [UInt8] {
        let device = try GPUTestSupport.requireDevice()
        let target = try colorTarget(device)
        let depth = try #require(device.makeTexture(SDLGPUTextureDescription(
            width: side, height: side, format: .d32Float, usage: [.depthStencilTarget])))
        let prepass = try makePipeline(device, vertex: "fullscreen", fragment: "flat",
                                       depth: SDLGPUDepthState(compare: .less, write: true), writesColor: writesColor)
        let triangles = try makePipeline(device, vertex: "tri", fragment: "tri", depth: SDLGPUDepthState(compare: .less, write: true))
        let fence = try await device.submitBatch { commandBuffer in
            if let first = commandBuffer.beginRenderPass(
                color: SDLGPUColorAttachment(texture: target, clearColor: (0, 0, 1, 1)),
                depth: SDLGPUDepthAttachment(texture: depth, storeOp: .store)) {
                first.bind(prepass)
                first.draw(vertexCount: 3)
                first.end()
            }
            if let second = commandBuffer.beginRenderPass(
                color: SDLGPUColorAttachment(texture: target, loadOp: .load),
                depth: SDLGPUDepthAttachment(texture: depth, loadOp: clearsDepthInPass2 ? .clear : .load)) {
                second.bind(triangles)
                second.draw(vertexCount: 3, instanceCount: 3)
                second.end()
            }
        }
        await fence.wait()
        return try #require(await device.download(target))
    }

    private func count(_ color: [UInt8], in pixels: [UInt8]) -> Int {
        (0..<side * side).filter { Array(pixels[$0 * 4..<$0 * 4 + 4]) == color }.count
    }

    /// **W1.** A depth-only prepass (`writesColor: false`) leaves the blue colour
    /// untouched while writing depth 0, so the second pass's triangles (depths
    /// 0.3 to 0.7, `LESS`, depth loaded) draw nothing: the target is all blue.
    /// Controls: with `writesColor: true` the prepass makes the target all red;
    /// with the depth cleared in pass 2 the triangles show (green is drawn).
    /// Mutation: the write mask never set (the target turns red).
    @Test(.enabled(if: GPUTestSupport.available, GPUTestSupport.skipReason))
    func aPipelineThatWritesNoColourLeavesColourAndWritesDepth() async throws {
        let masked = try await twoPasses(writesColor: false, clearsDepthInPass2: false)
        #expect(count(blue, in: masked) == side * side, "colour untouched and depth 0 rejects every triangle")
        let written = try await twoPasses(writesColor: true, clearsDepthInPass2: false)
        #expect(count(red, in: written) == side * side, "control: a colour-writing prepass paints red")
        let cleared = try await twoPasses(writesColor: false, clearsDepthInPass2: true)
        #expect(count(green, in: cleared) > 20, "control: without the prepass depth the triangles draw")
    }

    /// **W2.** `writesColor` defaults to `true` and is stored when `false`.
    /// Mutation: the initialiser ignores its parameter.
    @Test(.enabled(if: GPUTestSupport.available, GPUTestSupport.skipReason))
    func writesColorDefaultsToTrueAndIsStored() async throws {
        let device = try GPUTestSupport.requireDevice()
        let library = try library()
        let vertex = try library.vertex("fullscreen", for: device), fragment = try library.fragment("flat", for: device)
        #expect(SDLGPUGraphicsPipelineDescription(vertex: vertex, fragment: fragment).writesColor)
        #expect(!SDLGPUGraphicsPipelineDescription(vertex: vertex, fragment: fragment, writesColor: false).writesColor)
    }

    private static let floats: [Float] = [0.1, -2.5, 1e20, .infinity, 0, 3.5, -0.0, 7]

    /// **F1.** Eight floats uploaded to an `r32Float` texture and downloaded are
    /// bit-equal. Mutation: `sdl` maps to `R32_UINT` with a zero `bytesPerTexel`
    /// (the upload refuses).
    @Test(.enabled(if: GPUTestSupport.available, GPUTestSupport.skipReason))
    func anR32FloatTextureRoundTripsExactFloats() async throws {
        let device = try GPUTestSupport.requireDevice()
        let texture = try #require(device.makeTexture(SDLGPUTextureDescription(
            width: 8, height: 1, format: .r32Float, usage: [.sampler])))
        let bytes = GPUTestSupport.bytes(of: Self.floats.map(\.bitPattern))
        try #require(await device.upload(bytes, to: texture))
        let back = try #require(await device.download(texture))
        #expect(back == bytes)
    }

    /// **F2.** `copy.frag` samples an `r32Float` texture with a nearest sampler
    /// into an `r32Float` colour target: the downloaded floats equal the source.
    /// Mutation: the sampler built `linear` (lavapipe and Metal still copy texel
    /// centres, so this one mutates the shader to scale `.x`).
    @Test(.enabled(if: GPUTestSupport.available, GPUTestSupport.skipReason))
    func anR32FloatTextureSampledNearestEqualsItsSource() async throws {
        let device = try GPUTestSupport.requireDevice()
        let source = try #require(device.makeTexture(SDLGPUTextureDescription(
            width: 8, height: 1, format: .r32Float, usage: [.sampler])))
        let destination = try #require(device.makeTexture(SDLGPUTextureDescription(
            width: 8, height: 1, format: .r32Float, usage: [.colorTarget, .sampler])))
        let bytes = GPUTestSupport.bytes(of: Self.floats.map(\.bitPattern))
        try #require(await device.upload(bytes, to: source))
        let sampler = try #require(device.makeSampler(SDLGPUSamplerDescription(filter: .nearest, mipmapFilter: .nearest)))
        let copy = try makePipeline(device, vertex: "fullscreen", fragment: "copy", colorFormat: .r32Float)
        let fence = try await device.submitBatch { commandBuffer in
            guard let pass = commandBuffer.beginRenderPass(color: SDLGPUColorAttachment(texture: destination)) else { return }
            pass.bind(copy)
            pass.bindFragmentSamplers([(texture: source, sampler: sampler)])
            pass.draw(vertexCount: 3)
            pass.end()
        }
        await fence.wait()
        let back = try #require(await device.download(destination))
        #expect(back == bytes, "bit-equal floats \(GPUTestSupport.words(from: back))")
    }

    /// **F3.** `r32Float` is four bytes a texel. Mutation: the table arm 0.
    @Test func r32FloatIsFourBytesPerTexel() {
        #expect(SDLGPUTextureFormat.r32Float.bytesPerTexel == 4)
        let description = SDLGPUTextureDescription(width: 5, height: 3, format: .r32Float, usage: [.sampler])
        #expect(description.width * description.height * description.format.bytesPerTexel == 60)
    }

    /// **A1.** The internal create-info: 1 disables anisotropy, 4 enables 4, 64 is
    /// clamped to 16, NaN and 0.5 disable it. Mutation: the enable test `>= 1`.
    @Test func anisotropyFieldsReachTheSamplerCreateInfo() {
        func info(_ value: Float) -> SDL_GPUSamplerCreateInfo {
            var description = SDLGPUSamplerDescription()
            description.maxAnisotropy = value
            return description.createInfo()
        }
        #expect(!info(1).enable_anisotropy)
        #expect(info(4).enable_anisotropy && info(4).max_anisotropy == 4)
        #expect(info(64).enable_anisotropy && info(64).max_anisotropy == 16)
        #expect(!info(.nan).enable_anisotropy)
        #expect(!info(0.5).enable_anisotropy)
        #expect(SDLGPUSamplerDescription(maxAnisotropy: 64).effectiveMaxAnisotropy == 16)
        #expect(SDLGPUSamplerDescription().maxAnisotropy == 1)
    }

    /// **A2.** `makeSampler` builds a 16x sampler on an owned device and the
    /// sampler reads its configuration back; the default reads 1. Mutation: the
    /// configuration not stored on the sampler.
    @Test(.enabled(if: GPUTestSupport.available, GPUTestSupport.skipReason))
    func aSamplerWithAnisotropyIsBuiltAndReadsBack() throws {
        let device = try GPUTestSupport.requireDevice()
        let sampler = try #require(device.makeSampler(SDLGPUSamplerDescription(maxAnisotropy: 16)))
        #expect(sampler.configuration.maxAnisotropy == 16)
        #expect(sampler.configuration.effectiveMaxAnisotropy == 16)
        let plain = try #require(device.makeSampler(SDLGPUSamplerDescription()))
        #expect(plain.configuration.maxAnisotropy == 1)
    }
}
