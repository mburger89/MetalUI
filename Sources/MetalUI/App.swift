import Metal
import MetalUIPlatform
import MetalUIAppKit

// MetalUI is the umbrella module: a client writes `import MetalUI` and gets the
// geometry, unit and colour types its elements must name, the `Style` values
// its modifiers write, the `Scene` its paint fills, and — since the window grew
// an `onInput` hook — the `InputEvent` that hook is handed.
@_exported import MetalUICore
@_exported import MetalUILayout
@_exported import MetalUIRender
@_exported import MetalUIPlatform
@_exported import MetalUITextSystem

#if canImport(AppKit)
import AppKit
#endif

public enum AppError: Error, CustomStringConvertible {
    case noMetalDevice
    public var description: String { "no Metal device is available on this system" }
}

@MainActor
public final class App {
    public let device: any MTLDevice
    private let renderer: Renderer
    private let platform: any Platform
    private var windows: [Window] = []
    /// Makes each window's text engine (ruling TS-A); `nil` is CoreText.
    private let makeTextSystem: (@MainActor () -> any TextSystem)?

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
        self.renderer = try Renderer(device: device)
        self.platform = AppKitPlatform(renderer: renderer)
    }

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
        // only way out.
        platformWindow.onClose = {
            #if canImport(AppKit)
            NSApplication.shared.terminate(nil)
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
