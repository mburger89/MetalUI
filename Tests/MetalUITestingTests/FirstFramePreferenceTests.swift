import MetalUI
import MetalUIScene
import MetalUITesting
import Testing

// First-frame cost of the window preferences and environment scopes an Alloy-shaped tree writes
// (`windowTitleBarMetrics`, `splitViewDivider`, `contentMargins`; rulings `AS-R`, `AS-T`). A profile showed
// `EnvironmentScope.reportingPreference` at +7.4 ms — an INCLUSIVE frame wrapping the subtree's layout, so
// the number is the tree's own layout moving under a new frame name. These tests count builds: a
// preference reported during the first build adds none, only a changed title-bar inset does (one
// frame, ruling `AS-R`), and a scope writing the environment adds none.

@MainActor private final class BuildCount { var n = 0 }

private struct Probe: Component {
    let count: BuildCount
    var content: some ElementGroup {
        let _ = { count.n += 1 }()
        Color.clear.frame(width: Pixels(100), height: Pixels(100))
    }
}

private let appKitLike = HeadlessPlatformWindow.Options(
    hiddenTitleBarInsets: Edges(top: Pixels(32), right: Pixels(0), bottom: Pixels(0), left: Pixels(69)))

/// Builds and frames after the first draw and two further ticks.
@MainActor private func firstFrames(metrics: Bool, scopes: Bool, style: WindowStyle) throws -> (builds: Int, frames: Int) {
    let count = BuildCount()
    let app = try TestApp(textSystem: harnessTextSystem)
    let window = try app.openWindow(size: sz(400, 300), windowStyle: style, options: appKitLike) {
        VStack(spacing: Pixels(0)) {
            if scopes {
                HSplitView {
                    Probe(count: count).contentMargins(Pixels(8))
                    Color.green
                }.splitViewDivider(.hidden, thickness: 0)
            } else {
                HSplitView {
                    Probe(count: count)
                    Color.green
                }
            }
        }
        .windowTitleBarMetrics(height: metrics ? Pixels(48) : nil, controlsLeading: metrics ? Pixels(12) : nil)
    }
    window.tick()
    window.tick()
    return (count.n, window.framesDrawn)
}

@Test @MainActor func environmentScopesAndPreferencesAddNoBuildToTheFirstFrame() throws {
    let plain = try firstFrames(metrics: false, scopes: false, style: .automatic)
    let scoped = try firstFrames(metrics: false, scopes: true, style: .automatic)
    print("FFP plain \(plain) scoped \(scoped)")
    #expect(scoped == plain, "scopes add no builds or frames: \(plain) vs \(scoped)")
}

@Test @MainActor func aTitleBarMetricsReportCostsOneFrameOnlyWhenTheInsetsChange() throws {
    let none = try firstFrames(metrics: false, scopes: true, style: .hiddenTitleBar)
    let some = try firstFrames(metrics: true, scopes: true, style: .hiddenTitleBar)
    print("FFP hidden none \(none) metrics \(some)")
    #expect(some.frames <= none.frames + 1, "at most the one inset-change frame: \(none) vs \(some)")
}
