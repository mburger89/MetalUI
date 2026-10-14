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

// The debug contract check of a surface draw (rulings GA-I, GA-M; spec §6 D1-D4).
// The offscreen `SDLWindowRenderer` runs a real `finishFrame`, so the renderer's
// two guard lines run on every platform and the exit tests need no presented
// frame (GA-M's test entry is not needed). The traps exist in a debug build only.

private let side = 16

@MainActor
private func frame(draw: @escaping @MainActor (any GPUSurfaceContext) -> Void,
                   renderer: SDLWindowRenderer) throws {
    let target = SurfaceTarget(id: SurfaceID(rawValue: 1), width: side, height: side)
    let request = SurfaceDrawRequest(target: target, scaleFactor: 1, time: 0, policy: .continuous, value: nil, draw: draw)
    try #require(renderer.beginFrame() != nil)
    try #require(renderer.finishFrame(scene: surfaceScene(side: side, target: target),
                                      atlas: GlyphAtlas(width: 16, height: 16), surfaces: [request]))
}

@MainActor
private func offscreenRenderer() throws -> SDLWindowRenderer {
    #if os(macOS)
    armMainRunLoopExitCheck()
    #endif
    return try SDLWindowRenderer(offscreenWidth: side, height: side)
}

/// A typed pass begun on the frame view's target and never ended.
@MainActor
private func leaveAPassOpen(_ ctx: any GPUSurfaceContext) {
    guard let sdl = ctx as? SDLGPUDrawContext else { return }
    let view = sdl.view
    _ = view.beginRenderPass(color: SDLGPUColorAttachment(texture: view.target, clearColor: (0, 0, 1, 1)))
}

@MainActor @Suite(.serialized) struct SDLGPUContractTests {
    #if DEBUG
    /// **D1.** A draw that returns with a typed pass open traps in a debug build,
    /// naming the contract. Mutations: the open-pass count not incremented in
    /// `notePassBegan` (no trap), the guard's `beginDraw` moved after the draw in
    /// `finishFrame` (it resets the count the draw raised).
    @Test(.enabled(if: GPUTestSupport.available, GPUTestSupport.skipReason))
    func anOpenPassAtTheEndOfADrawTrapsInDebug() async throws {
        let result = await #expect(processExitsWith: .failure, observing: [\.standardErrorContent]) {
            let renderer = try await offscreenRenderer()
            try await frame(draw: leaveAPassOpen, renderer: renderer)
        }
        let stderr = String(decoding: result?.standardErrorContent ?? [], as: UTF8.self)
        #expect(stderr.contains("still open"), "the trap says a pass was left open: \(stderr)")
    }

    /// **D2.** `waitForIdle` called inside a draw traps in a debug build, naming the
    /// call and the contract. Mutation: the guard's `beginDraw` moved after the
    /// draw (the flag is set too late: no trap).
    @Test(.enabled(if: GPUTestSupport.available, GPUTestSupport.skipReason))
    func aWaitInsideADrawTrapsInDebug() async throws {
        let result = await #expect(processExitsWith: .failure, observing: [\.standardErrorContent]) {
            let renderer = try await offscreenRenderer()
            try await frame(draw: { ctx in
                guard let sdl = ctx as? SDLGPUDrawContext else { return }
                sdl.view.device.waitForIdle()
            }, renderer: renderer)
        }
        let stderr = String(decoding: result?.standardErrorContent ?? [], as: UTF8.self)
        #expect(stderr.contains("waitForIdle was called inside a surface draw"), "the trap names the call: \(stderr)")
    }
    #endif

    /// **D3.** The frame view declares no verb that would end the frame's
    /// buffer (`submit`, `cancel`, `wait`, `acquire`): a source scan of the view,
    /// and of every `func` the command-buffer and pass types declare. A typecheck
    /// guard cannot reach here (the root package builds without the `SDL` trait,
    /// and `MetalUISDLGPU` exists only under it).
    /// Mutation: `func submit()` added to the view.
    @Test func theFrameViewDeclaresNoSubmittingVerb() throws {
        let sources = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Sources/MetalUISDLGPU")
        func code(_ name: String) throws -> [String] {
            try String(contentsOf: sources.appendingPathComponent(name), encoding: .utf8)
                .split(separator: "\n", omittingEmptySubsequences: false)
                .map { String($0) }.filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
        }
        let forbidden = ["submit", "cancel", "wait", "acquire"]
        let view = try code("SDLGPUFrameView.swift")
        try #require(view.contains { $0.contains("class SDLGPUFrameView") }, "the scan found the view")
        for line in view {
            for word in forbidden { #expect(!line.lowercased().contains(word), "the view's code mentions \(word): \(line)") }
        }
        for name in ["SDLGPUCompute.swift", "SDLGPUGraphics.swift", "SDLGPUTexture.swift"] {
            for line in try code(name) where line.contains("func ") {
                for word in forbidden {
                    #expect(!line.lowercased().contains(word), "\(name) declares a \(word) verb: \(line)")
                }
            }
        }
    }

    /// **D4.** A draw through the typed view adds no submission: it records into
    /// the very buffer the renderer submits (`view.commandBuffer.raw` is
    /// `frameCommandBuffer`), the frame's submission count moves by exactly what a
    /// draw that only clears moves it, and no fence is released unsignalled.
    /// (The renderer's counter cannot see a raw SDL submit, so the identity of the
    /// buffer is the pin; spec §6's "begin pass submits" mutation is the view
    /// recording into a buffer of its own, which this reddens.)
    @Test(.enabled(if: GPUTestSupport.available, GPUTestSupport.skipReason))
    func theSurfaceDrawStillAddsNoSubmission() throws {
        final class Seen: @unchecked Sendable {
            nonisolated(unsafe) var viewBuffer: OpaquePointer?
            nonisolated(unsafe) var frameBuffer: OpaquePointer?
        }
        let seen = Seen()
        let renderer = try offscreenRenderer()
        try frame(draw: { ctx in ctx.clear(red: 0, green: 0, blue: 1, alpha: 1) }, renderer: renderer)
        let beforePlain = renderer.submissionCount
        try frame(draw: { ctx in ctx.clear(red: 0, green: 0, blue: 1, alpha: 1) }, renderer: renderer)
        let plainDelta = renderer.submissionCount - beforePlain

        let before = renderer.submissionCount
        try frame(draw: { ctx in
            guard let sdl = ctx as? SDLGPUDrawContext else { return }
            let view = sdl.view
            seen.viewBuffer = view.commandBuffer.raw
            seen.frameBuffer = renderer.frameCommandBuffer
            guard let pass = view.beginRenderPass(color: SDLGPUColorAttachment(texture: view.target, clearColor: (0, 1, 0, 1)))
            else { return }
            pass.end()
        }, renderer: renderer)
        #expect(renderer.submissionCount - before == plainDelta, "a typed pass adds no submission")
        #expect(seen.viewBuffer != nil && seen.viewBuffer == seen.frameBuffer, "the view records into the frame's own buffer")
        #expect(renderer.unsignaledFenceReleaseCount == 0)
    }

    /// **D5.** The guard is off outside a draw: after a frame whose draw used the
    /// typed view, `waitForIdle` and a download on the same device do not trap
    /// (the flag and the open-pass count are cleared when the draw returns).
    /// Mutation: `endDraw` leaves `drawingThread` set.
    @Test(.enabled(if: GPUTestSupport.available, GPUTestSupport.skipReason))
    func theGuardIsOffAfterTheDrawReturns() async throws {
        final class Box: @unchecked Sendable { nonisolated(unsafe) var device: SDLGPUDevice? }
        let box = Box()
        let renderer = try offscreenRenderer()
        try frame(draw: { ctx in
            guard let sdl = ctx as? SDLGPUDrawContext else { return }
            let view = sdl.view
            box.device = view.device
            guard let pass = view.beginRenderPass(color: SDLGPUColorAttachment(texture: view.target)) else { return }
            pass.end()
        }, renderer: renderer)
        let device = try #require(box.device)
        #expect(!SDLGPUWindowGuard.isInsideDraw)
        device.waitForIdle()
        let buffer = try #require(device.makeBuffer(size: 16, usage: [.computeStorageRead]))
        #expect(await device.download(buffer, range: 0..<16) != nil)
    }
}
