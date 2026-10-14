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

// A borrowed device under the window's own frames (ruling `GA-E` item 4, spec
// §6 C9). The renderer draws offscreen, so a frame runs where the Linux image's
// offscreen video driver presents none; the draw runs inside `finishFrame` with
// a real `SDLGPUDrawContext`.

private let width = 32, height = 32
private let bounds = MUIBounds(origin: MUIPoint(x: 0, y: 0), size: MUISize(width: 16, height: 16))
private let target = SurfaceTarget(id: SurfaceID(rawValue: 1), width: 16, height: 16)
private let threadCount = 1024
private let expectedCount = (0..<threadCount).filter { ($0 * 7) % 13 < 5 }.count

private func surfaceScene() -> Scene {
    var scene = Scene()
    let all = MUIBounds(origin: MUIPoint(x: 0, y: 0), size: MUISize(width: Float(width), height: Float(height)))
    let none = MUICorners(topLeft: 0, topRight: 0, bottomRight: 0, bottomLeft: 0)
    let black = MUIHsla(h: 0, s: 0, l: 0, a: 1)
    scene.insert(MUIRect(bounds: all, contentMask: all, maskCornerRadii: none, background: black, borderColor: black,
                         cornerRadii: none, borderWidths: MUIEdges(top: 0, right: 0, bottom: 0, left: 0),
                         order: 0, shape: 0))
    scene.insert(MUIImage(bounds: bounds, contentMask: bounds, maskCornerRadii: none, opacity: 1, texture: 0,
                          filter: MUIUInt(MUIImageFilterLinear.rawValue), order: 1), surface: target)
    scene.finalize()
    return scene
}

/// Hands the draw's device to the test the first time it runs.
private final class DeviceBox: @unchecked Sendable {
    nonisolated(unsafe) var device: SDLGPUDevice?
}

/// **C9.** 200 frames of a continuously drawn surface while 50 append batches
/// run on the window's own (borrowed) device, off the main actor: no fault, every
/// fence signals, every result is the CPU's count. This is a stress pin, not a
/// mutation-verified one: removing the creation lock reddens nothing
/// deterministically (record the unproven instrument, practices). It runs on
/// Linux and Windows too, since the offscreen renderer draws without a presented
/// frame.
@MainActor
@Test(.enabled(if: GPUTestSupport.available, GPUTestSupport.skipReason))
func aBatchOnTheWorkerRacesTheWindowFrameWithoutFault() async throws {
    #if os(macOS)
    armMainRunLoopExitCheck()
    #endif
    let renderer = try SDLWindowRenderer(offscreenWidth: width, height: height)
    let box = DeviceBox()
    let request = SurfaceDrawRequest(target: target, scaleFactor: 1, time: 0, policy: .continuous, value: nil) { ctx in
        if box.device == nil, let sdl = ctx as? SDLGPUDrawContext { box.device = SDLGPUDevice(borrowing: sdl) }
        ctx.clear(red: 0, green: 0, blue: 1, alpha: 1)
    }
    let scene = surfaceScene()
    let atlas = GlyphAtlas(width: 16, height: 16)
    try #require(renderer.beginFrame() != nil)
    try #require(renderer.finishFrame(scene: scene, atlas: atlas, surfaces: [request]))
    let device = try #require(box.device, "the first draw handed over its device")
    let library = try SDLGPUShaderLibrary(directory: GPUTestSupport.compiledShaders)
    let pipeline = try #require(device.makeComputePipeline(try library.compute("append", for: device)))
    let bytes = 4 * (threadCount + 1)
    let zeros = [UInt8](repeating: 0, count: bytes)

    let batches = Task { () -> [Int] in
        var counters: [Int] = []
        for _ in 0..<50 {
            guard let buffer = device.makeBuffer(size: bytes, usage: [.computeStorageRead, .computeStorageWrite]),
                  await device.upload(zeros, to: buffer),
                  let fence = try? await device.submitBatch({ commandBuffer in
                      guard let pass = commandBuffer.beginComputePass(readWrite: [buffer]) else { return }
                      pass.bind(pipeline)
                      pass.push(uniform: GPUTestSupport.bytes(of: [UInt32(threadCount), 0, 0, 0]), at: 0)
                      pass.dispatch(x: 16, y: 1, z: 1)
                      pass.end()
                  }) else { counters.append(-1); continue }
            await fence.wait()
            let result = await device.download(buffer, range: 0..<4).map { GPUTestSupport.words(from: $0)[0] }
            counters.append(Int(result ?? 0xFFFF))
        }
        return counters
    }
    for _ in 0..<200 {
        try #require(renderer.beginFrame() != nil)
        try #require(renderer.finishFrame(scene: scene, atlas: atlas, surfaces: [request]))
        await Task.yield()
    }
    let counters = await batches.value
    #expect(counters == Array(repeating: expectedCount, count: 50), "\(counters)")
}
