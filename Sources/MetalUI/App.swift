import MetalUIPlatform
#if canImport(MetalUIAppKit)
import AppKit
import Metal
import MetalUIAppKit
#endif

// MetalUI is the umbrella module: a client writes `import MetalUI` and gets the
// geometry, unit and colour types its elements must name, the `Style` values
// its modifiers write, the `Scene` its paint fills, and — since the window grew
// an `onInput` hook — the `InputEvent` that hook is handed.
@_exported import MetalUICore
@_exported import MetalUILayout
@_exported import MetalUIPlatform
@_exported import MetalUIPrimitives
@_exported import MetalUITextSystem
#if canImport(MetalUIRender)
@_exported import MetalUIRender
#endif

public enum AppError: Error, CustomStringConvertible {
    case noMetalDevice
    public var description: String { "no Metal device is available on this system" }
}

/// An application: one platform, its windows, and the text engine every
/// window draws with (ruling XP-B). On macOS the default is AppKit with Metal
/// and CoreText; anywhere, ``init(platform:textSystem:)`` takes any
/// `Platform` — `Backends/SDL`'s `SDLPlatform` on Linux and Windows — and a
/// `TextSystem`, which a non-Apple build must supply (it has no CoreText).
@MainActor
public final class App {
    private let platform: any Platform
    private var windows: [Window] = []
    /// Makes each window's text engine (ruling TS-A); `nil` is CoreText.
    private let makeTextSystem: (@MainActor () -> any TextSystem)?
    /// Whether closing the last window ends the process through AppKit.
    private let terminatesThroughAppKit: Bool

    #if canImport(MetalUIAppKit)
    /// The Metal device the AppKit platform draws with; `nil` for an app on
    /// another platform.
    public let device: (any MTLDevice)?

    public convenience init() throws {
        guard let device = MTLCreateSystemDefaultDevice() else { throw AppError.noMetalDevice }
        try self.init(device: device)
    }

    /// - Parameter textSystem: makes the text engine every window of this app
    ///   measures and draws through — once per window, since each keeps its
    ///   own caches. `nil` (the default) is CoreText; a `PortableTextSystem`
    ///   draws with HarfBuzz, FreeType and libunibreak instead, the path a
    ///   non-Apple platform takes.
    public init(device: any MTLDevice, textSystem: (@MainActor () -> any TextSystem)? = nil) throws {
        self.device = device
        self.makeTextSystem = textSystem
        self.platform = AppKitPlatform(renderer: try Renderer(device: device))
        self.terminatesThroughAppKit = true
    }

    /// An app on `platform` — the SDL platform on macOS too — drawing text
    /// with `textSystem` (`nil`: CoreText).
    public init(platform: any Platform, textSystem: (@MainActor () -> any TextSystem)? = nil) {
        self.device = nil
        self.makeTextSystem = textSystem
        self.platform = platform
        self.terminatesThroughAppKit = platform is AppKitPlatform
    }
    #else
    /// An app on `platform` — `Backends/SDL`'s `SDLPlatform` — drawing text
    /// with `textSystem`, which is required here: there is no CoreText to fall
    /// back on (ruling XP-B).
    public init(platform: any Platform, textSystem: @escaping @MainActor () -> any TextSystem) {
        self.makeTextSystem = textSystem
        self.platform = platform
        self.terminatesThroughAppKit = false
    }
    #endif

    /// Opens a window whose content is one root element, rebuilt every frame.
    ///
    /// `content` is a plain closure and **not** `@ElementBuilder`-annotated. The
    /// builder's job is to fold several children into one group — `Pair`,
    /// `ArrayGroup` — and a group is not an `Element`, so a two-statement block
    /// here would fail to satisfy `Root: Element` with a diagnostic about
    /// `Pair` rather than about the window. A window has exactly one root;
    /// wrapping several children in a `Column` says so at the call site.
    @discardableResult
    public func openWindow<Root: Element>(
        title: String,
        size: Size<Pixels>,
        startsDisplayLink: Bool = true,
        content: @escaping @MainActor () -> Root
    ) throws -> Window {
        let platformWindow = try platform.openWindow(title: title, size: size)
        let window = Window(platformWindow: platformWindow,
                            startsDisplayLink: startsDisplayLink,
                            textSystem: makeTextSystem?(),
                            content: content)
        // Closing the last window must end the process: there is no app delegate
        // and no menu bar anywhere in the framework, so this close button is the
        // only way out. AppKit's run loop is ended here; SDL's `run()` returns
        // on its own once its last window has closed.
        let terminates = terminatesThroughAppKit
        platformWindow.onClose = {
            #if canImport(AppKit)
            if terminates { NSApplication.shared.terminate(nil) }
            #endif
        }
        windows.append(window)

        // Paint once now rather than waiting for a display-link tick. The link
        // does not fire while the view is hidden or off-display, which would
        // otherwise leave a window that opens occluded blank indefinitely. The
        // surface geometry is already valid from the platform window's init, and
        // a missing drawable simply leaves the window dirty for the link to retry.
        window.drawFrameIfNeeded()
        return window
    }

    public func run() {
        platform.run()
    }
}
