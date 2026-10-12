import MetalUIPlatform

// The test harness's read-back (ruling `HT-C` item 2): `package` members, in a
// file of their own, that `MetalUITesting` reads and an app cannot spell —
// `package` is unspellable outside this package (guard 3.2). Nothing here
// changes behaviour: each member reads or sets state `Window`/`App` already
// keep for test observability. **The harness owns `Window.onFrameAdopted` for
// the windows it opens** (`HT-C` item 4); nothing else in `Sources/` sets it.

/// One build's work, handed to ``Window/testingOnFrameAdopted(_:)`` after the
/// build is adopted (ruling `HT-I`): the root layout run's counts (`SA-M`)
/// and the window's CPU raster counters for the build (`GX-K`). A value, so
/// `Frame` stays internal.
package struct BuildWork: Sendable, Equatable {
    /// Leaf and custom `sizeThatFits` calls in the root's layout run.
    package var measureCalls: Int
    /// Cache hits in that run.
    package var cacheHits: Int
    /// Cache misses in that run.
    package var cacheMisses: Int
    /// Device pixels the build rasterized (`RasterCache.lastRasterizedPixels`).
    package var rasterizedPixels: Int
    /// Device pixels the build blurred (`RasterCache.lastBlurredPixels`).
    package var blurredPixels: Int
}

extension Window {
    /// Whether every frame records its element bounds (`recordsElementBounds`).
    package var testingRecordsElementBounds: Bool {
        get { recordsElementBounds }
        set { recordsElementBounds = newValue }
    }

    /// The last build's element bounds, by identity — empty unless
    /// ``testingRecordsElementBounds``. Window content space, logical points.
    package var testingElementBounds: [GlobalElementID: Bounds<Pixels>] { lastElementBounds }

    /// Calls `observer` with each build's ``BuildWork`` after the build is
    /// adopted; `nil` removes it. Sets `onFrameAdopted`, which the harness owns.
    package func testingOnFrameAdopted(_ observer: (@MainActor (BuildWork) -> Void)?) {
        guard let observer else {
            onFrameAdopted = nil
            return
        }
        onFrameAdopted = { [weak self] frame in
            let work = frame.tree.lastNativeLayoutWork
            let rasters = self?.animationStore.rasters
            observer(BuildWork(measureCalls: work.measureCalls, cacheHits: work.cacheHits,
                               cacheMisses: work.cacheMisses,
                               rasterizedPixels: rasters?.lastRasterizedPixels ?? 0,
                               blurredPixels: rasters?.lastBlurredPixels ?? 0))
        }
    }
}

extension App {
    /// The open window whose platform window is `platformWindow`, by identity
    /// — found from the renderer's first `beginFrame()`, since `openWindow`
    /// appends the window before drawing its first frame (`HT-R` item 1).
    package func testingWindow(for platformWindow: any PlatformWindow) -> Window? {
        windows.first { $0.platformWindow === platformWindow }
    }

    /// Whether `App(platform:textSystem:)` has a text system to fall back on
    /// when given none: CoreText, on Apple platforms only (ruling `HT-J`).
    package static var hasDefaultTextSystem: Bool {
        #if canImport(MetalUIText)
        true
        #else
        false
        #endif
    }
}
