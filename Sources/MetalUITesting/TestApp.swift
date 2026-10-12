import MetalUI
import MetalUIScene

/// An application under test (ruling `HT-C`; gpui's `TestAppContext`, `HT-B`):
/// a real `App` over a ``HeadlessPlatform``, whose windows are
/// ``TestWindow``s. Commands, the menu bar, themes, the app shell's close and
/// terminate, the lifecycle drain and the colour scheme all run as in a
/// shipped app, because they are the shipped app's code.
///
/// ```swift
/// let app = try TestApp()
/// let window = try app.openWindow { rootView() }
/// ```
///
/// MetalUI-only (`HT-B`): SwiftUI tests UI out of process (XCUITest).
@MainActor
public final class TestApp {
    /// The real application — set `commands`, themes, `icon` and the shell's
    /// handlers on it as an app does.
    public let app: App

    /// The headless platform the app runs on.
    public let platform: HeadlessPlatform

    /// The windows this app opened that are still referenced, in open order.
    /// A ``TestWindow`` keeps its app alive, not the other way round.
    public var windows: [TestWindow] { windowRefs.compactMap(\.window) }
    private var windowRefs: [WeakTestWindow] = []

    /// An app over a new ``HeadlessPlatform``. `textSystem` makes each
    /// window's text engine; `nil` is CoreText on Apple platforms and throws
    /// ``TestHarnessError/textSystemRequired`` elsewhere (ruling `HT-J`) —
    /// pass a `PortableTextSystem` there.
    public init(textSystem: (@MainActor () -> any TextSystem)? = nil) throws {
        let platform = HeadlessPlatform()
        self.platform = platform
        if let textSystem {
            app = App(platform: platform, textSystem: textSystem)
        } else {
            guard App.hasDefaultTextSystem else { throw TestHarnessError.textSystemRequired }
            #if canImport(MetalUIText)
            app = App(platform: platform, textSystem: nil)
            #else
            throw TestHarnessError.textSystemRequired
            #endif
        }
    }

    /// Opens a window over `content` through the real `App.openWindow` and
    /// draws its first frame (ruling `HT-K`).
    ///
    /// - Parameters:
    ///   - colorScheme: the **system** appearance the window opens in, so a
    ///     `.dark` window's first frame is dark.
    ///   - scaleFactor: the backing scale.
    ///   - options: the platform answers; `nil` takes
    ///     `platform.nextWindowOptions` with `colorScheme` and `scaleFactor`
    ///     applied, a value is used as given.
    ///   - recordsLayout: whether ``TestWindow/frame(ofID:)`` can answer
    ///     (off for a benchmark: the frame then does production work only).
    public func openWindow<Root: Element>(
        title: String = "Test",
        size: Size<Pixels> = Size(width: Pixels(800), height: Pixels(600)),
        minSize: Size<Pixels>? = nil, maxSize: Size<Pixels>? = nil,
        windowResizability: WindowResizability = .automatic,
        windowStyle: WindowStyle = .automatic,
        colorScheme: ColorScheme = .light, scaleFactor: Float = 1,
        options: HeadlessPlatformWindow.Options? = nil,
        recordsLayout: Bool = true,
        content: @escaping @MainActor () -> Root
    ) throws -> TestWindow {
        let parts = try openParts(title: title, size: size, minSize: minSize, maxSize: maxSize,
                                  windowResizability: windowResizability, windowStyle: windowStyle,
                                  colorScheme: colorScheme, scaleFactor: scaleFactor,
                                  options: options, recordsLayout: recordsLayout, content: content)
        let window = TestWindow(testApp: self, parts: parts)
        register(window)
        return window
    }

    func register(_ window: TestWindow) {
        windowRefs.removeAll { $0.window == nil }
        windowRefs.append(WeakTestWindow(window: window))
    }

    /// Opens the real window and wires the harness to it before its first
    /// frame: the renderer's one-shot `onFirstBeginFrame` finds the `Window`
    /// through `App.testingWindow(for:)` (spec §3.1 item 3, `HT-R` item 1).
    func openParts<Root: Element>(
        title: String, size: Size<Pixels>, minSize: Size<Pixels>?, maxSize: Size<Pixels>?,
        windowResizability: WindowResizability, windowStyle: WindowStyle,
        colorScheme: ColorScheme, scaleFactor: Float,
        options: HeadlessPlatformWindow.Options?, recordsLayout: Bool,
        content: @escaping @MainActor () -> Root
    ) throws -> TestWindow.Parts {
        let saved = platform.nextWindowOptions
        var chosen = options ?? saved
        if options == nil {
            chosen.appearance = colorScheme
            chosen.scaleFactor = scaleFactor
        }
        platform.nextWindowOptions = chosen
        defer { platform.nextWindowOptions = saved }

        let recorder = FrameWorkRecorder(recordsLayout: recordsLayout)
        platform.onNextWindowOpened = { [weak app] platformWindow in
            platformWindow.headlessRenderer.onFirstBeginFrame = { [weak app, weak platformWindow] in
                guard let app, let platformWindow, let window = app.testingWindow(for: platformWindow) else {
                    return
                }
                recorder.attach(to: window)
            }
            platformWindow.headlessRenderer.onFramePresented = { renderer in recorder.closeFrame(renderer) }
        }
        let window = try app.openWindow(title: title, size: size, minSize: minSize, maxSize: maxSize,
                                        windowResizability: windowResizability, windowStyle: windowStyle,
                                        startsDisplayLink: true, content: content)
        platform.onNextWindowOpened = nil
        // `App.openWindow` asked the platform for exactly one window.
        guard let platformWindow = platform.openedWindows.last else {
            preconditionFailure("App.openWindow opened no platform window")
        }
        // The recorded fallback (spec §3.1 item 3): if the first frame found no
        // window, wire it now and draw once more.
        if !recorder.isAttached {
            recorder.attach(to: window)
            window.setNeedsRedraw()
            platformWindow.simulateTick(timestamp: 0)
        }
        return TestWindow.Parts(window: window, platformWindow: platformWindow, recorder: recorder)
    }
}

/// A weak handle, so a ``TestApp`` does not keep its windows alive.
@MainActor
private struct WeakTestWindow {
    weak var window: TestWindow?
}

/// Sums each build's work into the frame being built and closes the frame
/// when the renderer presents it (ruling `HT-I`).
@MainActor
final class FrameWorkRecorder {
    let recordsLayout: Bool
    private(set) var isAttached = false
    private var pending = FrameWork()
    var history: [FrameWork] = []
    private(set) var last = FrameWork()

    init(recordsLayout: Bool) { self.recordsLayout = recordsLayout }

    /// Turns on element-bounds recording and the build observer for `window`.
    func attach(to window: Window) {
        isAttached = true
        window.testingRecordsElementBounds = recordsLayout
        window.testingOnFrameAdopted { [weak self] work in self?.noteBuild(work) }
    }

    func noteBuild(_ work: BuildWork) {
        pending.builds += 1
        pending.layoutMeasureCalls += work.measureCalls
        pending.layoutCacheHits += work.cacheHits
        pending.layoutCacheMisses += work.cacheMisses
        pending.rasterizedPixels += work.rasterizedPixels
        pending.blurredPixels += work.blurredPixels
    }

    func closeFrame(_ renderer: HeadlessWindowRenderer) {
        pending.atlasUploadPixels = renderer.lastAtlasUploadPixels
        pending.newTextures = renderer.lastNewTextures
        pending.newTexturePixels = renderer.lastNewTexturePixels
        pending.rects = renderer.lastScene.rects.count
        pending.glyphs = renderer.lastScene.glyphs.count
        pending.images = renderer.lastScene.images.count
        history.append(pending)
        last = pending
        pending = FrameWork()
    }
}
