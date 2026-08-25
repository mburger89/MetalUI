import Metal
import MetalUIPlatform

// MetalUI is the umbrella module: a client writes `import MetalUI` and gets the
// geometry, unit, and colour types its content closures must name.
@_exported import MetalUICore
@_exported import MetalUIRender

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

    public convenience init() throws {
        guard let device = MTLCreateSystemDefaultDevice() else { throw AppError.noMetalDevice }
        try self.init(device: device)
    }

    public init(device: any MTLDevice) throws {
        self.device = device
        self.renderer = try Renderer(device: device)
        self.platform = AppKitPlatform(device: device)
    }

    @discardableResult
    public func openWindow(title: String,
                           size: Size<Pixels>,
                           startsDisplayLink: Bool = true,
                           content: @escaping FrameContent) throws -> Window {
        let platformWindow = try platform.openWindow(title: title, size: size)
        let window = Window(platformWindow: platformWindow,
                            renderer: renderer,
                            content: content,
                            startsDisplayLink: startsDisplayLink)
        // Closing the last window must end the process: M0 ships no app delegate
        // and no menu bar, so this close button is the only way out.
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
