import MetalUI
import MetalUIScene

/// A `Platform` with no screen and no event loop (ruling `HT-D`): its windows
/// are ``HeadlessPlatformWindow``s, every request is recorded and every
/// platform event can be simulated. ``run()`` returns at once — a test never
/// enters a run loop; the clock is the test's (`HT-E`, `HT-R` item 6).
///
/// ``TestApp`` builds an `App` over one; build one yourself to host your own
/// `App` headless. MetalUI-only (`HT-B`).
@MainActor
public final class HeadlessPlatform: Platform {
    /// The options the next ``openWindow(title:size:)`` gives its window.
    public var nextWindowOptions = HeadlessPlatformWindow.Options()

    /// Every window ``openWindow(title:size:)`` made, in order.
    public private(set) var openedWindows: [HeadlessPlatformWindow] = []

    /// Every `setApplicationIcon` argument, in order.
    public private(set) var applicationIcons: [[ImageTexture]] = []

    /// The menu bar the app last installed (`App.commands`), or `nil`.
    public private(set) var menuBar: PlatformMenuBar?

    /// Every `replyToTerminateRequest` argument, in order.
    public private(set) var terminateReplies: [Bool] = []

    /// How many times the app ended the event loop (`terminate()`).
    public private(set) var terminateCalls = 0

    /// Runs once with the next window ``openWindow(title:size:)`` makes, before
    /// it is returned — ``TestApp``'s hook for its first-frame setup.
    var onNextWindowOpened: (@MainActor (HeadlessPlatformWindow) -> Void)?

    /// URL batches that arrived before ``onOpenURLs`` was set.
    private var parkedURLs: [[String]] = []

    /// A platform with no windows.
    public init() {}

    /// A ``HeadlessPlatformWindow`` titled `title` of content size `size`, in
    /// ``nextWindowOptions``.
    public func openWindow(title: String, size: Size<Pixels>) throws -> any PlatformWindow {
        let window = HeadlessPlatformWindow(title: title, size: size, options: nextWindowOptions)
        openedWindows.append(window)
        if let opened = onNextWindowOpened {
            onNextWindowOpened = nil
            opened(window)
        }
        return window
    }

    /// Returns at once: there is no event loop to run.
    public func run() {}

    /// Records the icon list.
    public func setApplicationIcon(_ images: [ImageTexture]) { applicationIcons.append(images) }

    /// Keeps the menu bar, which ``TestApp/menuBar`` evaluates.
    public func setMenuBar(_ menuBar: PlatformMenuBar) { self.menuBar = menuBar }

    /// Installed by the app; asked by ``simulateTerminateRequest()``.
    public var onTerminateRequest: (() -> CloseRequestReply)?

    /// Records the reply.
    public func replyToTerminateRequest(_ shouldTerminate: Bool) { terminateReplies.append(shouldTerminate) }

    /// Counts the call: a headless platform has no loop to end.
    public func terminate() { terminateCalls += 1 }

    /// Installed by the app. URLs that arrived before it are delivered, each
    /// batch once, on assignment — the platforms' parking (`AS-G` item 4).
    public var onOpenURLs: (([String]) -> Void)? {
        didSet {
            guard let onOpenURLs, !parkedURLs.isEmpty else { return }
            let parked = parkedURLs
            parkedURLs = []
            for batch in parked { onOpenURLs(batch) }
        }
    }

    /// A termination request the way ⌘Q or `SDL_EVENT_QUIT` makes one: the
    /// app's answer, `.now` with no handler.
    public func simulateTerminateRequest() -> CloseRequestReply {
        onTerminateRequest?() ?? .now
    }

    /// Documents the system asks the app to open, as absolute URL strings —
    /// delivered now, or parked until the app installs its handler.
    public func simulateOpenURLs(_ urls: [String]) {
        if let onOpenURLs { onOpenURLs(urls) } else { parkedURLs.append(urls) }
    }
}
