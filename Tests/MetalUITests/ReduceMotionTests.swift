import Testing
import Observation
import Metal
import MetalUICore
import MetalUIPlatform
@testable import MetalUI

// Plan task 13, lane 1 — Reduce Motion as an environment value from the
// platform (ruling `AN-AD`). Spec
// `docs/superpowers/specs/2026-09-30-transactions-animation-design.md` §6.4,
// tests 1.13 and 1.16; SwiftUI's side is
// `docs/probes/swiftui-transactions-animation.swift`, arms R1–R10. What Reduce
// Motion changes — every transition but `.identity` becomes a cross-fade —
// is lane 3's (`TransitionTests`); this file pins where the value comes from
// and that property animations do not change under it (R3, R4, R6).

/// A fake platform window whose Reduce Motion is `initial` **before** the
/// `Window` is built over it, so `Window.init`'s read is what the first frame
/// shows.
@MainActor
private func makeReduceMotionWindow<Root: Element>(
    reduceMotion initial: Bool,
    content: @escaping @MainActor () -> Root
) throws -> (Window, FakePlatformWindow) {
    let device = try #require(MTLCreateSystemDefaultDevice(), "no Metal device; run on macOS hardware")
    let platformWindow = try FakePlatformWindow(device: device, size: 300)
    platformWindow.accessibilityReduceMotion = initial
    let window = Window(platformWindow: platformWindow, startsDisplayLink: true, content: content)
    return (window, platformWindow)
}

/// **1.13.** The window's root `accessibilityReduceMotion` is its platform
/// window's: read at construction (a fake starting `true`, so the bare `false`
/// of `Window.environment` cannot pass for it); a change reported through
/// `onAccessibilityReduceMotionChange` dirties the window and the next frame
/// reads it; a report of the value the window already has does not dirty it;
/// and `Window.environment`'s own value is not the root's source — the window
/// stamps over it. Mutations **M1.13a**: omit the stamp (the first arm);
/// **M1.13b**: `Window.init` does not wire the callback (the change arm).
@MainActor @Test func theWindowStampsReduceMotionFromItsPlatformWindow() throws {
    let log = TransactionLog()
    let (window, platform) = try makeReduceMotionWindow(reduceMotion: true) {
        Column { TransactionRecorder(label: "r", log: log) }
    }
    try #require(window.environment.accessibilityReduceMotion == false,
                 "Window.environment must hold a different value from the platform's, or the stamp is unobservable")

    #expect(window.accessibilityReduceMotion == true, "read at construction")
    window.drawFrameIfNeeded()
    #expect(log.reduceMotion["r"] == true, "the first frame reads the platform's value")
    #expect(window.needsRedraw == false)

    platform.simulateReduceMotionChange(to: false)
    #expect(window.needsRedraw == true, "a Reduce Motion change must redraw")
    window.drawFrameIfNeeded()
    #expect(log.reduceMotion["r"] == false, "and the next frame reads it")

    #expect(window.needsRedraw == false)
    platform.simulateReduceMotionChange(to: false)
    #expect(window.needsRedraw == false, "a report of the value the window already has must not redraw")

    // Window.environment is not the root's source (the stamp is OVER it).
    window.environment.accessibilityReduceMotion = true
    window.drawFrameIfNeeded()
    #expect(log.reduceMotion["r"] == false,
            "Window.environment.accessibilityReduceMotion changes nothing at the root")
}

/// **1.16 (R3, R4, R6).** Under Reduce Motion, property animations are
/// unchanged: `withAnimation`'s width (the layout helper) and background (the
/// paint helper, standing in for R4's render effect until lane 2 animates
/// opacity) and `.animation(_:value:)`'s width all read mid-flight values.
/// Mutation **M1.16**: snap every helper when the root reads Reduce Motion.
@MainActor @Test func propertyAnimationsRunUnchangedUnderReduceMotion() throws {
    let model = TransactionModel()
    let log = TransactionLog()
    let (window, platform) = try makeReduceMotionWindow(reduceMotion: true) {
        Column {
            TransactionRecorder(label: "r", log: log)
            Box().background(model.useAccent ? .accent : .background)
                .cssWidth(Pixels(model.width)).cssHeight(Pixels(40))
            Box().background(.accent)
                .cssWidth(Pixels(model.other)).cssHeight(Pixels(41))
                .animation(.linear(duration: 1), value: model.flag)
        }
    }
    platform.simulateTick(timestamp: 100)
    try #require(log.reduceMotion["r"] == true, "set up: the tree reads Reduce Motion on")
    let from = try #require(transactionRectColour(window, height: 40))

    withAnimation(.linear(duration: 1)) {
        model.width = 200
        model.useAccent = true
    }
    model.flag = 1
    model.other = 200
    platform.simulateTick(timestamp: 100.1)
    platform.simulateTick(timestamp: 100.6)
    #expect(transactionRectWidth(window, height: 40) == 150, "R3: withAnimation's width is unchanged")
    #expect(transactionRectWidth(window, height: 41) == 150, "R6: .animation(_:value:) is unchanged")
    let mid = try #require(transactionRectColour(window, height: 40))
    platform.simulateTick(timestamp: 101.1)
    let to = try #require(transactionRectColour(window, height: 40))
    try #require(from != to)
    #expect(mid != from && mid != to, "a paint-phase animation is unchanged too; got \(mid)")
}
