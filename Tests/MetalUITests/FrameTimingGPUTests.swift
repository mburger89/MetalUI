import Testing
import Foundation
import Metal
import MetalUICore
import MetalUIPlatform
import MetalUIScene
@testable import MetalUI
@testable import MetalUIRender

// Per-frame GPU time on the Metal renderer (ruling `FP-P`, record 289): a real `MetalWindowRenderer` drawing into
// the fake surface. Skipped, by throwing `NoMetalDevice`, where there is no Metal device.

@MainActor private func gpuWindow() throws -> (Window, FakePlatformWindow) {
    try makeFakeWindowOnDefaultDevice { Box().frame(width: 20, height: 20) }
}

@MainActor private func draw(_ window: Window) {
    window.setNeedsRedraw()
    window.drawFrameIfNeeded()
}

/// Lets the main actor run the completion hops until `done`, up to five seconds.
@MainActor private func waitUntil(_ done: () -> Bool) async {
    let deadline = Date().addingTimeInterval(5)
    while !done(), Date() < deadline { try? await Task.sleep(nanoseconds: 5_000_000) }
}

/// 1.42 — with a `FrameTiming` on, a rendered Metal frame gets a GPU time above 0 in its sample, and the trace
/// line carries it in the `gpu` column. Mutations: the completed handler not installed (the sample stays `nil`);
/// `gpuStartTime` and `gpuEndTime` swapped or both read before completion (0, so `nil`); the token off by one
/// (the time lands on another frame).
@Test @MainActor func aMetalFrameGetsItsGPUTimeInItsSampleAndTraceLine() async throws {
    let (window, _) = try gpuWindow()
    let timing = FrameTiming()
    window.frameTiming = timing
    draw(window)
    await waitUntil { timing.last?.gpuNanos != nil }
    let sample = try #require(timing.last)
    let gpu = try #require(sample.gpuNanos, "no GPU time arrived")
    #expect(gpu > 0)
    let line = FrameTiming.traceLine(for: sample, interval: nil)
    let column = line.components(separatedBy: " | ")[1].split(separator: " ").last.map(String.init)
    #expect(column == String(format: "%.2f", Double(gpu) / 1e6), "\(line)")
    #expect(column != "-")
}

/// 1.43 — with no `FrameTiming` the renderer adds no completion handler (the zero cost of `FP-P`), and none again
/// once the timing is removed. Mutation: the handler installed unconditionally (the count rises on the first
/// frame).
@Test @MainActor func aMetalFrameInstallsNoCompletionHandlerWhileTimingIsOff() async throws {
    let (window, platform) = try gpuWindow()
    window.frameTiming = nil
    draw(window); draw(window)
    #expect(platform.windowRenderer.gpuCompletionHandlersInstalled == 0)
    let timing = FrameTiming()
    window.frameTiming = timing
    draw(window)
    #expect(platform.windowRenderer.gpuCompletionHandlersInstalled == 1)
    window.frameTiming = nil
    draw(window); draw(window)
    #expect(platform.windowRenderer.gpuCompletionHandlersInstalled == 1, "off again, no more handlers")
    await waitUntil { timing.last?.gpuNanos != nil }
}
