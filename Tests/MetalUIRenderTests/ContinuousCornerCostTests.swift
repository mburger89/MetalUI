import Testing
import Foundation
import Metal
import MetalUICore
import MetalUIShaderTypes
@testable import MetalUIRender

// GPU cost of the continuous rect kind (record 226, plan §8 (ii)). Record 105's numbers are CPU-only and "a time is
// never a test pin", so this is a measure, not an assertion: `METALUI_CORNER_COST=1` prints the median over 50 frames
// of `gpuEndTime - gpuStartTime` for 10,000 overlapping opaque rects in a 2560 x 1440 target (the 2x of 1280 x 720), per
// kind. `docs/probes/continuous-corner-cost/run.sh` drives it on this branch and, with the branch's shader files put
// back to the base's, on master (`METALUI_CORNER_COST_KINDS=0` there: kind 2 is a value master's shader does not know).
// Two shapes: `big` 96 x 64 at r 20 (the pin's frame: the corner bands are a small share of the fragments) and `small`
// 24 x 24 at r 12 (a circle-sized rect, every fragment near a corner: the worst case).

private func median(_ values: [Double]) -> Double { values.sorted()[values.count / 2] }

@Test(.enabled(if: ProcessInfo.processInfo.environment["METALUI_CORNER_COST"] == "1"))
@MainActor func theGPUCostOfTheContinuousKind() throws {
    let device = try #require(MTLCreateSystemDefaultDevice(), "no Metal device; run on macOS hardware")
    let renderer = try Renderer(device: device)
    let width = 2560, height = 1440
    let kinds = (ProcessInfo.processInfo.environment["METALUI_CORNER_COST_KINDS"] ?? "0,2").split(separator: ",").compactMap { UInt32($0) }
    let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: Renderer.pixelFormat, width: width, height: height, mipmapped: false)
    descriptor.usage = .renderTarget
    descriptor.storageMode = .private
    let target = try #require(device.makeTexture(descriptor: descriptor))
    let view = SurfaceView(colorTexture: target, viewport: MTLViewport(originX: 0, originY: 0, width: Double(width), height: Double(height), znear: 0, zfar: 1),
                           projection: matrix_identity_float4x4)
    let full = Bounds(origin: Point(x: ScaledPixels(0), y: ScaledPixels(0)), size: Size(width: ScaledPixels(Float(width)), height: ScaledPixels(Float(height))))
    for (name, w, h, r) in [("big", Float(96), Float(64), Float(20)), ("small", 24, 24, 12)] {
        for kind in kinds {
            var scene = Scene()
            for i in 0..<10_000 {
                let x = Float((i * 37) % 100) / 100 * Float(width - 100) + Float(i % 7) * 0.25
                let y = Float((i / 100) % 100) / 100 * Float(height - 70) + Float(i % 5) * 0.25
                scene.insert(MUIRect(bounds: Bounds(origin: Point(x: ScaledPixels(x), y: ScaledPixels(y)), size: Size(width: ScaledPixels(w), height: ScaledPixels(h))),
                                     contentMask: full, background: Hsla(h: Float(i % 12) / 12, s: 0.7, l: 0.5, a: 1), borderColor: .transparent,
                                     cornerRadii: Corners(all: ScaledPixels(r)), borderWidths: Edges(all: ScaledPixels(0)), order: 0,
                                     shape: try #require(PrimitiveShape(rawValue: kind))))
            }
            scene.finalize()
            var times: [Double] = []
            for frame in 0..<60 {
                let commandBuffer = try #require(renderer.commandQueue.makeCommandBuffer())
                try renderer.encode(scene, view: view, in: commandBuffer)
                commandBuffer.commit()
                commandBuffer.waitUntilCompleted()
                if frame >= 10 { times.append((commandBuffer.gpuEndTime - commandBuffer.gpuStartTime) * 1000) }
            }
            print("COST \(name) \(Int(w))x\(Int(h)) r\(Int(r)) kind \(kind): median \(String(format: "%.3f", median(times))) ms, min \(String(format: "%.3f", times.min()!)), max \(String(format: "%.3f", times.max()!)) (50 frames, 10000 rects, \(width)x\(height))")
        }
    }
}
