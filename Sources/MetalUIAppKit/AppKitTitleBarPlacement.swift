import AppKit

// App-chosen title-bar band and window-button inset under the hidden title bar (ruling `AS-R`; MetalCreator
// gap AS-a). AppKit has no public API for either: a toolbar style, a bottom accessory and the toolbar's items
// each give a fixed per-style height and leave the buttons at the system x. So the placement is manual, as
// Electron's `trafficLightPosition` does it: resize the title-bar container view — the buttons' superview's
// superview — and move the three standard buttons inside it. **That relies on the private view hierarchy**
// (`standardWindowButton(_:).superview` is an `NSTitlebarView`, its superview an `NSTitlebarContainerView`);
// when the buttons have no such superview the placement does nothing and the system layout stands.
//
// AppKit resets that layout on the first `setFrame`, on a toolbar change and on full screen, so a hook keeps
// it: KVO on the three buttons' and the two views' `frame`, **deferred one run-loop pass** (a synchronous
// re-place from inside the observer re-enters AppKit's layout and crashes) and coalesced; every write is
// **guarded by equality** (a write re-fires the observer, so an unguarded one loops forever); and nothing
// is written in full screen, where the system lays the buttons out and the container sits above the screen.
// `NSWindow` notifications are a backstop for a reset the observers miss (probe: a `title` change fires none,
// the observers catch it). Measured in the AS-a probe (record 249).
//
// **The deferred pass alone shows the system layout during a live resize** (Alloy; record 401): each
// `setFrame` resets the buttons inside the title-bar view's own layout, the pass puts them back one run-loop
// pass later, and the frames displayed in between sit about 20 pt high and 20 pt left. So a `LayoutAnchor`,
// an invisible subview filling the title-bar view, re-places **synchronously from its `layout()`**, which AppKit
// runs after the reset and before display (measured over 30 steps: 0 layouts, draws or post-`setFrame` reads at
// the system position, against 30 of 30 and 23 of 50 draws with the deferred pass alone). That write is a
// subview's layout, not a KVO callback, so it does not re-enter AppKit; it is equality-guarded and does not
// call `onReplaced`. The deferred pass stays for what no layout reports: a `title` change, a toolbar, key
// changes and full-screen exit.

@MainActor
final class TitleBarPlacement {
    private weak var window: NSWindow?
    private(set) var height: CGFloat?
    private(set) var leading: CGFloat?
    private let isFullScreen: () -> Bool
    private var frameObservations: [NSKeyValueObservation] = []
    private var notificationTokens: [NSObjectProtocol] = []
    private var pending = false
    private var isPlacing = false
    private var removed = false
    /// The layout anchor (see ``LayoutAnchor``): a zero-cost subview of the titlebar view whose `layout()` runs
    /// after AppKit's own reset of the buttons and before the window draws.
    private var anchor: LayoutAnchor?
    /// Each button's left edge relative to the close button's, captured once from the system layout.
    private var offsets: [NSWindow.ButtonType: CGFloat] = [:]
    /// How many frame writes ``place()`` made (tests: a settled placement writes nothing more).
    private(set) var writeCount = 0
    /// How many times ``place()`` ran past its guards.
    private(set) var placeCount = 0
    /// Called after a deferred re-placement that moved something (`AS-R` item 6): the window's insets read
    /// the buttons' frames, so a reset that was read before the re-placement left them stale. `init` and
    /// `update(height:leading:)` place synchronously and their caller republishes.
    var onReplaced: (() -> Void)?

    static let buttons: [NSWindow.ButtonType] = [.closeButton, .miniaturizeButton, .zoomButton]
    static let backstopNotifications: [Notification.Name] = [
        NSWindow.didResizeNotification, NSWindow.didEndLiveResizeNotification,
        NSWindow.didExitFullScreenNotification, NSWindow.didBecomeKeyNotification,
        NSWindow.didResignKeyNotification,
    ]

    /// Places at once and hooks the window. `observesFrames` is a test seam: `false` leaves the
    /// notification backstop alone.
    init?(window: NSWindow, height: CGFloat?, leading: CGFloat?, observesFrames: Bool = true,
          isFullScreen: (() -> Bool)? = nil) {
        guard Self.views(of: window) != nil else { return nil }
        self.window = window
        self.height = height
        self.leading = leading
        self.isFullScreen = isFullScreen ?? { [weak window] in window?.styleMask.contains(.fullScreen) ?? true }
        if let close = window.standardWindowButton(.closeButton) {
            for type in Self.buttons {
                if let button = window.standardWindowButton(type) { offsets[type] = button.frame.minX - close.frame.minX }
            }
        }
        if observesFrames, let (container, bar) = Self.views(of: window) {
            var views: [NSView] = [container, bar]
            views += Self.buttons.compactMap { window.standardWindowButton($0) }
            for view in views {
                frameObservations.append(view.observe(\.frame, options: []) { [weak self] _, _ in
                    MainActor.assumeIsolated { self?.schedule() }
                })
            }
        }
        if observesFrames, let (_, bar) = Self.views(of: window) {
            let anchor = LayoutAnchor(frame: bar.bounds)
            anchor.onLayout = { [weak self] in self?.placeInLayout() }
            bar.addSubview(anchor)
            self.anchor = anchor
        }
        for name in Self.backstopNotifications {
            notificationTokens.append(NotificationCenter.default.addObserver(
                forName: name, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.schedule() }
            })
        }
        place()
    }

    /// The container and the titlebar view, or `nil` when the buttons do not sit where this expects.
    static func views(of window: NSWindow) -> (container: NSView, bar: NSView)? {
        guard let bar = window.standardWindowButton(.closeButton)?.superview, let container = bar.superview else {
            return nil
        }
        return (container, bar)
    }

    /// Changes the pair and places again.
    func update(height: CGFloat?, leading: CGFloat?) {
        // A field that was set and no longer is has to be given back: AppKit only lays out afresh on a resize.
        // The new pair is stored first: the layout anchor places from it during that resize.
        let dropped = (self.height != nil && height == nil) || (self.leading != nil && leading == nil)
        self.height = height
        self.leading = leading
        if dropped { restoreSystemLayout() }
        place()
    }

    /// The synchronous half of the hook: runs from the anchor's `layout()`, after AppKit has reset the buttons
    /// for this resize and before anything is drawn, so no frame shows the system layout. Counts nothing when
    /// the frames are already right (`place()` writes only a difference). It does not call ``onReplaced``: that
    /// republishes the geometry, which must not run inside AppKit's layout, and the host view's resize, which
    /// reads the insets, comes after this layout (measured), so it already sees the placed buttons.
    private func placeInLayout() { place() }

    /// Re-places in the next run-loop pass, once however many resets arrive before it.
    func schedule() {
        guard !pending, !removed else { return }
        pending = true
        RunLoop.main.perform(inModes: [.common]) { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.pending = false
                let before = self.writeCount
                self.place()
                if self.writeCount != before { self.onReplaced?() }
            }
        }
    }

    /// Writes the container and the buttons where the pair puts them, each only if it differs; does nothing
    /// in full screen. Height centres the buttons vertically in a band that tall; leading puts the close
    /// button's left edge there and keeps the system spacing between the three.
    func place() {
        guard !removed, !isPlacing, !isFullScreen(), let window, let (container, bar) = Self.views(of: window),
              let host = container.superview else { return }
        isPlacing = true
        defer { isPlacing = false }
        placeCount += 1
        if let height {
            let frame = NSRect(x: 0, y: host.bounds.height - height, width: host.bounds.width, height: height)
            if container.frame != frame { container.frame = frame; writeCount += 1 }
            if bar.frame != container.bounds { bar.frame = container.bounds; writeCount += 1 }
        }
        for type in Self.buttons {
            guard let button = window.standardWindowButton(type) else { continue }
            var origin = button.frame.origin
            if height != nil { origin.y = ((bar.bounds.height - button.frame.height) / 2).rounded() }
            if let leading { origin.x = leading + (offsets[type] ?? 0) }
            if button.frame.origin != origin { button.setFrameOrigin(origin); writeCount += 1 }
        }
    }

    /// Stops the hook and gives the system layout back. AppKit lays the title bar out afresh on a resize
    /// (measured; `needsLayout` and `layoutIfNeeded` do not), so the window is made one point wider and
    /// narrower again without display.
    func remove() {
        guard !removed else { return }
        removed = true
        anchor?.onLayout = nil
        anchor?.removeFromSuperview()
        anchor = nil
        frameObservations.removeAll()
        for token in notificationTokens { NotificationCenter.default.removeObserver(token) }
        notificationTokens.removeAll()
        restoreSystemLayout()
    }

    /// Makes AppKit lay the title bar out afresh (see ``remove()``).
    private func restoreSystemLayout() {
        guard let window, !isFullScreen() else { return }
        var frame = window.frame
        let original = frame
        frame.size.width += 1
        window.setFrame(frame, display: false)
        window.setFrame(original, display: false)
    }
}

/// An invisible subview of the title-bar view that fills it and re-runs the placement from `layout()`.
/// AppKit resets the buttons (and the container) inside the title-bar view's own layout, which runs from
/// each `setFrame`; a subview's `layout()` runs after that and before display, which a KVO observer or a
/// notification cannot promise (measured, record 401: the deferred pass left every live-resize frame at the
/// system position). It takes no events and no accessibility.
@MainActor
private final class LayoutAnchor: NSView {
    var onLayout: (() -> Void)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        autoresizingMask = [.width, .height]
    }

    required init?(coder: NSCoder) { nil }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func isAccessibilityElement() -> Bool { false }

    /// Every size change of the title-bar view reaches here through the autoresizing mask; lay out again.
    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        needsLayout = true
    }

    override func layout() {
        super.layout()
        onLayout?()
    }
}
