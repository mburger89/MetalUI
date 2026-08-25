import Metal
import MetalUICore
import MetalUIRender
import MetalUIPlatform

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
        windows.append(window)
        return window
    }

    public func run() {
        platform.run()
    }
}
