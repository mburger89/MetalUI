import MetalUICore
import MetalUIRender

@MainActor
public protocol PlatformWindow: AnyObject {
    var contentSize: Size<Pixels> { get }
    var scaleFactor: Float { get }
    var surface: any RenderSurface { get }
    var title: String { get set }

    var onInput: ((InputEvent) -> Bool)? { get set }
    var onResize: ((Size<Pixels>, Float) -> Void)? { get set }
    var onClose: (() -> Void)? { get set }

    /// Begin delivering frame ticks. The callback runs on the main actor.
    func startDisplayLink(_ tick: @escaping () -> Void)
    /// Pausing lets an idle window permit display downclocking (spec 4.4).
    func setDisplayLinkPaused(_ paused: Bool)
}

@MainActor
public protocol Platform: AnyObject {
    func openWindow(title: String, size: Size<Pixels>) throws -> any PlatformWindow
    func run()
}

public enum PlatformError: Error, CustomStringConvertible {
    case windowCreationFailed
    public var description: String { "could not create a platform window" }
}
