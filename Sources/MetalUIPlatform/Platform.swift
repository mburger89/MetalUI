import MetalUICore
import MetalUIRender

@MainActor
public protocol PlatformWindow: AnyObject {
    var contentSize: Size<Pixels> { get }
    var scaleFactor: Float { get }
    var surface: any RenderSurface { get }
    var title: String { get set }

    /// The host's current colour environment (spec §7.9). Read at window
    /// construction and re-read on every `onAppearanceChange`.
    var appearance: Appearance { get }

    var onInput: ((InputEvent) -> Bool)? { get set }
    var onResize: ((Size<Pixels>, Float) -> Void)? { get set }
    /// Fired when the host switches between light and dark (spec §7.9:
    /// "`NSApp.effectiveAppearance` / `traitCollectionDidChange` swap the active
    /// theme and mark §4.4's dirty flag").
    ///
    /// A callback carrying the new value rather than a bare "something changed":
    /// the `appearance` getter is a live read of AppKit state, and AppKit
    /// delivers the change notification *while* the effective appearance is
    /// already the new one, so the two agree — but only a passed value makes
    /// that agreement the platform's obligation rather than the caller's
    /// assumption.
    var onAppearanceChange: ((Appearance) -> Void)? { get set }
    var onClose: (() -> Void)? { get set }

    /// Begin delivering frame ticks. The callback runs on the main actor and
    /// receives the display link's timestamp in seconds.
    ///
    /// **The timestamp is the link's, not a wall-clock read.** Every element in
    /// one frame must see the same instant, and `CACurrentMediaTime()` sampled
    /// per element would not give them one.
    func startDisplayLink(_ tick: @escaping (Double) -> Void)
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
