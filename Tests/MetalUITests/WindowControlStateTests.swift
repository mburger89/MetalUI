import Metal
import Testing
import MetalUICore
import MetalUILayout
import MetalUIPlatform
@testable import MetalUI

// Plan task 9's closing half, lane 3: the seam
// (`docs/superpowers/specs/2026-09-25-environment-control-state-design.md`
// §6, tests T3.1–T3.3; rulings `EV-AA` and `EV-AB`). The window takes its
// root's `controlActiveState` from `PlatformWindow`'s new pair and its
// `displayScale` from the drawable's scale (`WindowRenderer.beginFrame()`),
// and a change to either reaches the next frame.
//
// **The fake fires its callback on every `simulate…` call, a no-op included**
// — unlike `AppKitWindow` and `SDLWindow`, which guard their own callbacks —
// so the change guard exercised here is `Window`'s.
//
// This file uses no `Dimension`, so importing `Metal` is safe here
// (`makeFakeWindowOnDefaultDevice`'s note).
//
// The mutation each test is named for, and every test it reddened, are
// recorded under the ruling it cites and in
// `docs/record/56-environment-control-state.md`.

// MARK: - Fixtures

/// Whole `EnvironmentValues` snapshots per label, taken in paint (the last
/// phase, so a frame that reached paint read what every phase read — the
/// three-phase reading is lane 1's T1.1).
@MainActor
private final class PaintLog {
    var paint: [String: EnvironmentValues] = [:]
}

/// A native 10×10 leaf that records `pass.environment` in paint.
private struct PaintRecorder: Element {
    let label: String
    let log: PaintLog

    func requestLayout(_ id: GlobalElementID, pass: inout LayoutPass) -> (LayoutNodeID, Void) {
        (pass.requestNativeLeaf { _ in LayoutMeasurement(size: SizeD(width: 10, height: 10)) }.layoutNodeID, ())
    }

    func prepaint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Void,
                  pass: inout PrepaintPass) {}

    func paint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Void,
               prepaint: inout Void, pass: inout PaintPass) {
        log.paint[label] = pass.environment
    }
}

/// A fake platform window whose key state is `initial` **before** the
/// `Window` is built over it, so `Window.init`'s read is what the first frame
/// shows.
@MainActor
private func makeWindow<Root: Element>(
    controlActiveState initial: ControlActiveState,
    content: @escaping @MainActor () -> Root
) throws -> (Window, FakePlatformWindow) {
    let device = try #require(MTLCreateSystemDefaultDevice(), "no Metal device; run on macOS hardware")
    let platformWindow = try FakePlatformWindow(device: device)
    platformWindow.controlActiveState = initial
    let window = Window(platformWindow: platformWindow, startsDisplayLink: false, content: content)
    return (window, platformWindow)
}

// MARK: - T3.1: the stamp, and a change repaints (EV-AB)

/// **T3.1.** The window's root `controlActiveState` is its platform window's,
/// read at construction (a fake starting `.inactive`, so the bare `.key` of
/// `Window.environment` cannot pass for it); a change reported through
/// `onControlActiveStateChange` dirties the window and the next frame reads
/// it; a report of the state the window already has does not dirty it.
///
/// Mutations (spec §6): **M3.1** `Window.init` does not assign the callback
/// (the `.key` arm stays clean); **M3.2** the stamp omitted at draw (the first
/// frame reads `.key`); **M3.3** the `!=` guard dropped (the no-op arm dirties).
@MainActor
@Test func theWindowStampsItsPlatformsControlActiveStateAndAChangeRepaints() throws {
    let log = PaintLog()
    let (window, platformWindow) = try makeWindow(controlActiveState: .inactive) {
        Row { PaintRecorder(label: "r", log: log) }
    }
    try #require(window.environment.controlActiveState == .key,
                 "Window.environment must hold a different value from the platform's, or the stamp is unobservable")

    #expect(window.controlActiveState == .inactive)
    window.drawFrameIfNeeded()
    #expect(window.needsRedraw == false)
    #expect(log.paint["r"]?.controlActiveState == .inactive)

    platformWindow.simulateControlActiveStateChange(to: .key)
    #expect(window.needsRedraw == true, "a key-state change must repaint")
    #expect(window.controlActiveState == .key)
    window.drawFrameIfNeeded()
    #expect(log.paint["r"]?.controlActiveState == .key)

    platformWindow.simulateControlActiveStateChange(to: .active)
    #expect(window.needsRedraw == true)
    window.drawFrameIfNeeded()
    #expect(log.paint["r"]?.controlActiveState == .active)

    #expect(window.needsRedraw == false)
    platformWindow.simulateControlActiveStateChange(to: .active)
    #expect(window.needsRedraw == false, "a report of the state the window already has must not repaint")
}

// MARK: - T3.2: a scope wins below it; Window.environment does not (EV-AB)

/// **T3.2.** A scope write of `controlActiveState` wins below it, beside an
/// unscoped sibling that reads the platform's (probe C4); and
/// `window.environment.controlActiveState = .key` — the third field of
/// `Window.environment` that is not the root's source — changes nothing at the
/// root, because the window stamps its own copy **over** `Window.environment`.
/// (The write still dirties the window: `EV-H`'s no-equality rule.)
///
/// Mutation: **M3.4** the stamp applied before `Window.environment` rather
/// than over it.
@MainActor
@Test func aScopeWriteOfControlActiveStateWinsBelowItAndTheWindowsEnvironmentDoesNot() throws {
    let log = PaintLog()
    let (window, _) = try makeWindow(controlActiveState: .inactive) {
        Row {
            PaintRecorder(label: "root", log: log)
            PaintRecorder(label: "scoped", log: log).environment(\.controlActiveState, .key)
        }
    }
    window.drawFrameIfNeeded()
    #expect(log.paint["root"]?.controlActiveState == .inactive)
    #expect(log.paint["scoped"]?.controlActiveState == .key)

    // Start from a value that is not `.key`, so the write below is a change
    // of `Window.environment` and not a no-op the stamp could hide behind.
    window.environment.controlActiveState = .active
    window.drawFrameIfNeeded()
    window.environment.controlActiveState = .key
    #expect(window.needsRedraw == true, "a Window.environment write dirties (EV-H)")
    window.drawFrameIfNeeded()
    #expect(log.paint["root"]?.controlActiveState == .inactive,
            "Window.environment.controlActiveState is not the root's source")
    #expect(log.paint["scoped"]?.controlActiveState == .key)
}

// MARK: - T3.3: a backing-scale change reaches displayScale (EV-AA)

/// **T3.3.** A backing-scale change — reported the way both platforms report
/// one, through `onResize` — dirties the window, and the next frame's root
/// reads the new `displayScale` and the `pixelLength` derived from it.
///
/// **Separating arm**: the drawable's scale (the surface's, returned by
/// `WindowRenderer.beginFrame()`) set to 3 while `PlatformWindow.scaleFactor`
/// stays at 2 reads **3**: the scale the frame is drawn at is the source
/// (probe S1), not the platform window's report. `try #require` that the two
/// disagree first.
///
/// Mutations: **M3.5** `onResize` does not dirty; **M3.6**
/// `Frame(scaleFactor: platformWindow.scaleFactor)` (the separating arm).
@MainActor
@Test func aBackingScaleChangeReachesTheDisplayScaleOnTheNextFrame() throws {
    let log = PaintLog()
    let (window, platformWindow) = try makeWindow(controlActiveState: .key) {
        Row { PaintRecorder(label: "r", log: log) }
    }
    try #require(platformWindow.scaleFactor == 1 && platformWindow.fakeSurface.scaleFactor == 1)
    window.drawFrameIfNeeded()
    #expect(log.paint["r"]?.displayScale == 1)
    #expect(log.paint["r"]?.pixelLength == 1)

    #expect(window.needsRedraw == false)
    platformWindow.simulateBackingScaleChange(to: 2)
    #expect(window.needsRedraw == true, "a backing-scale change must repaint")
    window.drawFrameIfNeeded()
    #expect(log.paint["r"]?.displayScale == 2)
    #expect(log.paint["r"]?.pixelLength == 0.5)

    platformWindow.fakeSurface.scaleFactor = 3
    try #require(Float(platformWindow.fakeSurface.scaleFactor) != platformWindow.scaleFactor,
                 "the drawable's scale and the platform window's must disagree for this arm to separate them")
    window.setNeedsRedraw()
    window.drawFrameIfNeeded()
    #expect(log.paint["r"]?.displayScale == 3, "the drawable's scale is the source, not PlatformWindow.scaleFactor")
    #expect(log.paint["r"]?.pixelLength == 1.0 / 3.0)
}
