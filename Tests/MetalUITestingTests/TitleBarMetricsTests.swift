import MetalUI
import MetalUIScene
import MetalUITesting
import Observation
import Testing

// `.windowTitleBarMetrics(height:controlsLeading:)` (ruling `AS-R`; MetalCreator gap AS-a): collected like the
// other window preferences, sent to the platform only under the hidden style and only when it changes, and
// reported back through `titleBarInsets`. The headless platform answers as AppKit does (band `height`,
// `left = leading + 60`); the AppKit window's own placement is `AppKitAppShellTests`. Plain imports,
// portable.

/// A headless platform answering as AppKit's hidden bar: band 32, the zoom button's right edge at 69.
private let appKitLike = HeadlessPlatformWindow.Options(
    hiddenTitleBarInsets: Edges(top: Pixels(32), right: Pixels(0), bottom: Pixels(0), left: Pixels(69)))

@MainActor private final class MetricsModel {
    var height: Pixels? = nil
    var leading: Pixels? = nil
    var applies = true
}

@MainActor @Observable private final class MetricsToggle { var on = true }

private struct MetricsReader: Component {
    @Environment(\.titleBarInsets) var insets
    let log: MetricsLog
    var content: some ElementGroup {
        let _ = log.note(insets)
        Color.clear.frame(width: Pixels(400), height: Pixels(300))
    }
}
@MainActor private final class MetricsLog {
    var last: Edges<Pixels>?
    func note(_ insets: Edges<Pixels>) -> Int { last = insets; return 0 }
}

private struct MetricsPage: Component {
    let height: Pixels?
    let leading: Pixels?
    let log: MetricsLog
    var content: some ElementGroup {
        MetricsReader(log: log).windowTitleBarMetrics(height: height, controlsLeading: leading)
    }
}

@MainActor private func metricsWindow(options: HeadlessPlatformWindow.Options = appKitLike,
                                      style: WindowStyle = .hiddenTitleBar, height: Pixels? = nil,
                                      leading: Pixels? = nil, log: MetricsLog = MetricsLog()) throws -> TestWindow {
    let app = try TestApp(textSystem: harnessTextSystem)
    let window = try app.openWindow(size: sz(400, 300), windowStyle: style, options: options) {
        VStack(spacing: Pixels(0)) { MetricsPage(height: height, leading: leading, log: log) }
    }
    window.tick()
    window.tick()
    return window
}

/// **AS-R 1**: with no modifier the platform is never asked and the insets are the system's. Mutation: send
/// `(nil, nil)` on the first build (the request list is not empty).
@Test @MainActor func noMetricsAsksThePlatformNothing() throws {
    let log = MetricsLog()
    let window = try metricsWindow(log: log)
    #expect(window.platformWindow.titleBarMetricsRequests.isEmpty)
    #expect(log.last == Edges(top: Pixels(32), right: Pixels(0), bottom: Pixels(0), left: Pixels(69)))
}

/// **AS-R 2**: a height alone is the band; `left` stays the system's zoom edge. Mutation: `top` ignores the
/// chosen height (the insets read 32).
@Test @MainActor func aHeightAloneIsTheBandAndKeepsTheSystemLeft() throws {
    let log = MetricsLog()
    let window = try metricsWindow(height: Pixels(68), log: log)
    #expect(window.platformWindow.titleBarMetricsRequests.count == 1)
    #expect(window.platformWindow.titleBarMetricsRequests.first?.height == 68)
    #expect(window.platformWindow.titleBarMetricsRequests.first?.controlsLeading == nil)
    #expect(log.last == Edges(top: Pixels(68), right: Pixels(0), bottom: Pixels(0), left: Pixels(69)),
            "stamped one frame after the build that reported it: \(String(describing: log.last))")
}

/// **AS-R 3**: both fields: the band and the moved buttons' right edge, 27 + 60. Mutation: `left` keeps the
/// system edge.
@Test @MainActor func bothFieldsMoveTheBandAndTheButtonsEdge() throws {
    let log = MetricsLog()
    let window = try metricsWindow(height: Pixels(68), leading: Pixels(27), log: log)
    #expect(log.last == Edges(top: Pixels(68), right: Pixels(0), bottom: Pixels(0), left: Pixels(87)))
    #expect(window.platformWindow.titleBarMetricsRequests.count == 1, "sent once, however many frames")
}

/// **AS-R 4**: the standard style ignores the modifier: nothing is sent, the insets are zero. Mutation: drop
/// the `titleBarStyleApplied` condition of `reconcileTitleBarMetrics`.
@Test @MainActor func theStandardStyleIgnoresTheMetrics() throws {
    let log = MetricsLog()
    let window = try metricsWindow(style: .titleBar, height: Pixels(68), leading: Pixels(27), log: log)
    #expect(window.platformWindow.titleBarMetricsRequests.isEmpty)
    #expect(log.last == Edges(all: Pixels(0)))
}

/// **AS-R 5**: leaving the hidden style clears the metrics, and coming back sends them again.
@Test @MainActor func leavingTheHiddenStyleClearsTheMetrics() throws {
    let log = MetricsLog()
    let window = try metricsWindow(height: Pixels(68), leading: Pixels(27), log: log)
    window.window.windowStyle = .titleBar
    window.tick()
    window.tick()
    let requests = window.platformWindow.titleBarMetricsRequests
    #expect(requests.count == 2 && requests[1].height == nil && requests[1].controlsLeading == nil, "\(requests)")
    #expect(log.last == Edges(all: Pixels(0)))
    window.window.windowStyle = .hiddenTitleBar
    window.tick()
    window.tick()
    #expect(window.platformWindow.titleBarMetricsRequests.count == 3)
    #expect(log.last?.top == Pixels(68))
}

/// **AS-R 6**: the modifier leaving the tree restores the system layout. Mutation: keep the last metrics
/// when the build reports none. `async` and settled with `runUntilIdle()`, not two ticks: off macOS a
/// Swift Testing `@MainActor` test need not run on the process's main thread, so `markDirtyFromObservation`
/// takes its main-actor-hop branch and the `@Observable` write dirties the window a turn later.
@Test @MainActor func theModifierLeavingRestoresTheSystemLayout() async throws {
    let toggle = MetricsToggle()
    let log = MetricsLog()
    let app = try TestApp(textSystem: harnessTextSystem)
    let window = try app.openWindow(size: sz(400, 300), windowStyle: .hiddenTitleBar, options: appKitLike) {
        VStack(spacing: Pixels(0)) { MetricsToggled(toggle: toggle, log: log) }
    }
    window.tick(); window.tick()
    #expect(log.last?.top == Pixels(68))
    toggle.on = false
    try await window.runUntilIdle()
    #expect(log.last == Edges(top: Pixels(32), right: Pixels(0), bottom: Pixels(0), left: Pixels(69)))
    let requests = window.platformWindow.titleBarMetricsRequests
    #expect(requests.count == 2 && requests[1].height == nil && requests[1].controlsLeading == nil)
}
private struct MetricsToggled: Component {
    let toggle: MetricsToggle
    let log: MetricsLog
    var content: some ElementGroup {
        if toggle.on {
            MetricsReader(log: log).windowTitleBarMetrics(height: Pixels(68), controlsLeading: Pixels(27))
        } else {
            MetricsReader(log: log)
        }
    }
}

/// **AS-R 7**: post-order precedence — an inner modifier beats an enclosing one.
@Test @MainActor func anInnerModifierBeatsAnEnclosingOne() throws {
    let log = MetricsLog()
    let app = try TestApp(textSystem: harnessTextSystem)
    let window = try app.openWindow(size: sz(400, 300), windowStyle: .hiddenTitleBar, options: appKitLike) {
        VStack(spacing: Pixels(0)) {
            MetricsReader(log: log).windowTitleBarMetrics(height: Pixels(50)).windowTitleBarMetrics(height: Pixels(90))
        }
    }
    window.tick(); window.tick()
    #expect(log.last?.top == Pixels(50))
}

/// **AS-R 8**: a platform that refuses is asked once and keeps the system band; the drawn cluster is not
/// moved either. Mutation: `titleBarMetricsHonoured` ignores the answer (the cluster moves anyway).
@Test @MainActor func aPlatformThatRefusesKeepsTheSystemBandAndCluster() throws {
    var options = HeadlessPlatformWindow.Options.sdlChrome
    options.hiddenTitleBarInsets = Edges(top: Pixels(32), right: Pixels(0), bottom: Pixels(0), left: Pixels(70))
    options.appliesTitleBarMetrics = false
    let log = MetricsLog()
    let window = try metricsWindow(options: options, height: Pixels(68), leading: Pixels(27), log: log)
    #expect(window.platformWindow.titleBarMetricsRequests.count == 1)
    #expect(log.last?.top == Pixels(32))
    let close = try window.element(label: "Close")
    #expect(close.frame == rect(13, 10, 12, 12))
}

/// **AS-R 9**: where the platform has no buttons (SDL under macOS: left cluster) the drawn circles are
/// centred in the chosen band at the chosen inset: the default's x 13 moves by `27 - 8`, y centres in 68.
/// Mutation: the strip ignores `leading` (x stays 13) or `bandHeight` (y stays 10).
@Test @MainActor func theDrawnLeftClusterCentresInTheBandAtTheInset() throws {
    var options = HeadlessPlatformWindow.Options.sdlChrome
    options.hiddenTitleBarInsets = Edges(top: Pixels(32), right: Pixels(0), bottom: Pixels(0), left: Pixels(70))
    let log = MetricsLog()
    let window = try metricsWindow(options: options, height: Pixels(68), leading: Pixels(27), log: log)
    let close = try window.element(label: "Close")
    let zoom = try window.element(label: "Zoom")
    #expect(close.frame == rect(32, 28, 12, 12), "\(close.frame)")
    #expect(zoom.frame == rect(72, 28, 12, 12), "\(zoom.frame)")
    #expect(log.last?.top == Pixels(68))
}

/// **AS-R 10**: a right-hand cluster (Windows, Linux) follows the height and ignores the inset.
@Test @MainActor func aRightHandClusterIgnoresTheInset() throws {
    let log = MetricsLog()
    let window = try metricsWindow(options: .sdlChrome, height: Pixels(68), leading: Pixels(27), log: log)
    #expect(log.last == Edges(top: Pixels(68), right: Pixels(138), bottom: Pixels(0), left: Pixels(0)))
    let close = try window.element(label: "Close")
    #expect(close.frame == rect(354, 0, 46, 68), "\(close.frame)")
}
