#if os(macOS)
import AppKit
import Metal
import QuartzCore
import MetalUICore
import MetalUIRender

/// Hosts the CAMetalLayer and funnels AppKit events into InputEvent.
@MainActor
final class MetalHostView: NSView {
    var onInput: ((InputEvent) -> Bool)?
    var onGeometryChange: (() -> Void)?
    var onAppearanceChange: (() -> Void)?

    private let surface: MetalLayerSurface

    init(surface: MetalLayerSurface) {
        self.surface = surface
        super.init(frame: .zero)
        // Order matters: assign the layer first. Setting `wantsLayer` first makes
        // AppKit create its own backing layer, and the CAMetalLayer is discarded.
        layer = surface.backingLayer
        wantsLayer = true
        layerContentsRedrawPolicy = .duringViewResize
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not supported") }

    override var acceptsFirstResponder: Bool { true }
    override var isFlipped: Bool { true }   // top-left origin, matching our geometry

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        onGeometryChange?()
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        onGeometryChange?()
    }

    /// The tracking area `mouseMoved` needs to fire at all — M3's hit-testing
    /// milestone (design spec §3.3) is what finally reads a hover position, so
    /// this is that milestone's half of the wire the `mouseMoved` override
    /// below has carried since M0 with nothing driving it.
    private var trackingArea: NSTrackingArea?

    /// Removes and re-adds `trackingArea` on every geometry change AppKit
    /// reports through this override — resize, the view moving to a new
    /// window, becoming key — rather than installing one once in `init`
    /// against whatever rect existed then.
    ///
    /// **`.inVisibleRect` still needs this override, and that is easy to get
    /// backwards.** The option keeps the *tracked rect* pinned to the view's
    /// current visible rect automatically, without a new `NSTrackingArea`
    /// being constructed on every frame — but `updateTrackingAreas()` is the
    /// hook AppKit already calls after each geometry change is settled, and
    /// the existing area has to be removed first or `addTrackingArea` grows
    /// the view's tracking-area list by one on every call instead of
    /// replacing it.
    ///
    /// Options: `.mouseMoved` is what makes `mouseMoved(with:)` below fire at
    /// all (its own doc comment used to say M3 would add exactly this — see
    /// there for the standing NOTE this closes). `.mouseEnteredAndExited` is
    /// declared for §8.1's future use (a `mouseExited` hook) even though
    /// nothing consumes `NSTrackingArea`'s entered/exited callbacks yet — this
    /// view is not their delegate, so declaring the option alone costs
    /// nothing and having it already in place is one less thing to get wrong
    /// when something does consume it. `.activeInKeyWindow` is what keeps a
    /// background window's tracking area from firing hover into a window the
    /// user is not interacting with. `.inVisibleRect` is the mechanism this
    /// whole override exists to pair with.
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(
            rect: .zero, // ignored: `.inVisibleRect` tracks the view's own bounds
            options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self, userInfo: nil)
        addTrackingArea(area)
        trackingArea = area
    }

    // Spec §7.9. AppKit calls this after `effectiveAppearance` has already
    // changed, so the callback's reader sees the new value — this is not an
    // "about to change" hook.
    //
    // **This method's firing IS tested**, unlike the layer/`wantsLayer` ordering
    // in `init` above, and the distinction is worth keeping straight because an
    // earlier version of this comment lumped the two together. Setting
    // `NSApplication.shared.appearance` changes `effectiveAppearance` for every
    // view under it and this override runs synchronously —
    // `theWindowFollowsTheApplicationsEffectiveAppearance` in
    // `PlatformTests.swift` asserts both directions. What no test can still see
    // is whether the resulting frame lands in a drawable anyone is looking at.
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        onAppearanceChange?()
    }

    private func point(_ event: NSEvent) -> Point<Pixels> {
        let p = convert(event.locationInWindow, from: nil)
        return Point(x: Pixels(Float(p.x)), y: Pixels(Float(p.y)))
    }

    private func modifiers(_ event: NSEvent) -> Modifiers {
        var m: Modifiers = []
        if event.modifierFlags.contains(.shift) { m.insert(.shift) }
        if event.modifierFlags.contains(.control) { m.insert(.control) }
        if event.modifierFlags.contains(.option) { m.insert(.option) }
        if event.modifierFlags.contains(.command) { m.insert(.command) }
        return m
    }

    override func mouseDown(with event: NSEvent) {
        _ = onInput?(.mouseDown(MouseEvent(position: point(event),
                                           modifiers: modifiers(event),
                                           clickCount: event.clickCount)))
    }

    override func mouseUp(with event: NSEvent) {
        _ = onInput?(.mouseUp(MouseEvent(position: point(event),
                                         modifiers: modifiers(event),
                                         clickCount: event.clickCount)))
    }

    // This fires because `updateTrackingAreas()` above installs a tracking
    // area with `.mouseMoved` — M3's hit-testing milestone (design spec
    // §3.3), closing the standing NOTE this comment used to carry: "mouseMoved
    // only fires once a tracking area exists; M0 does not add one, because
    // nothing depends on hover yet; M3 adds it with hit testing." If
    // `mouseMoved` ever appears not to fire again, suspect the tracking area
    // (a removed/never-added one, or a window that lost key status under
    // `.activeInKeyWindow`) before suspecting this method.
    //
    // **Nothing in this repo can drive real AppKit mouse tracking**, so
    // nothing here is asserted by a test — `updateTrackingAreas()`'s own doc
    // comment says the same. A human running the app is what closes this;
    // see Task 11's human-verification list.
    override func mouseMoved(with event: NSEvent) {
        _ = onInput?(.mouseMoved(MouseEvent(position: point(event),
                                            modifiers: modifiers(event))))
    }

    override func scrollWheel(with event: NSEvent) {
        let momentum = event.momentumPhase != []
        _ = onInput?(.scrollWheel(ScrollEvent(
            position: point(event),
            delta: Point(x: Pixels(Float(event.scrollingDeltaX)),
                         y: Pixels(Float(event.scrollingDeltaY))),
            modifiers: modifiers(event),
            isMomentum: momentum,
            timestamp: event.timestamp)))
    }

    override func keyDown(with event: NSEvent) {
        _ = onInput?(.keyDown(KeyEvent(
            charactersIgnoringModifiers: event.charactersIgnoringModifiers ?? "",
            characters: event.characters ?? "",
            modifiers: modifiers(event),
            isRepeat: event.isARepeat,
            timestamp: event.timestamp)))
    }

    override func keyUp(with event: NSEvent) {
        _ = onInput?(.keyUp(KeyEvent(
            charactersIgnoringModifiers: event.charactersIgnoringModifiers ?? "",
            characters: event.characters ?? "",
            modifiers: modifiers(event),
            timestamp: event.timestamp)))
    }

    override func flagsChanged(with event: NSEvent) {
        _ = onInput?(.modifiersChanged(modifiers(event)))
    }
}

@MainActor
final class AppKitWindow: NSObject, PlatformWindow, NSWindowDelegate {
    private let window: NSWindow
    private let hostView: MetalHostView
    private let metalSurface: MetalLayerSurface
    private var displayLink: CADisplayLink?
    private var tick: ((Double) -> Void)?

    var onInput: ((InputEvent) -> Bool)?
    var onResize: ((Size<Pixels>, Float) -> Void)?
    var onAppearanceChange: ((Appearance) -> Void)?
    var onClose: (() -> Void)?

    init(device: any MTLDevice, title: String, size: Size<Pixels>) throws {
        metalSurface = MetalLayerSurface(device: device)
        hostView = MetalHostView(surface: metalSurface)

        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0,
                                width: CGFloat(size.width.value),
                                height: CGFloat(size.height.value)),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false)
        window.title = title
        // `NSWindow(contentRect:…)` defaults `isReleasedWhenClosed` to **true**,
        // a manual-retain-release convention that predates ARC. `window` above is
        // a strong stored property, so ARC already owns this object: leaving the
        // default on means `close()` sends it an extra `release` and every later
        // reference — this property, `contentSize`, `title`, AppKit's own
        // teardown — is to freed memory.
        //
        // The crash it produced is **not** at `close()`. AppKit defers the
        // window's close animation (`_NSWindowTransformAnimation`) into an
        // autorelease pool that CoreAnimation pops from a run-loop observer, so
        // the over-release lands in `-[_NSWindowTransformAnimation dealloc]` ->
        // `objc_release` -> `EXC_BAD_ACCESS` the next time the main run loop
        // spins a CA commit. In `swift test` that is whenever a later `async`
        // test awaits — which is why closing a window here killed the process
        // inside the WebKit layout-oracle tests and nowhere else. See the
        // practices doc, shape 11.
        window.isReleasedWhenClosed = false
        window.contentView = hostView
        window.center()

        super.init()
        window.delegate = self
        hostView.onInput = { [weak self] event in self?.onInput?(event) ?? false }
        hostView.onGeometryChange = { [weak self] in self?.syncSurfaceGeometry() }
        hostView.onAppearanceChange = { [weak self] in
            guard let self else { return }
            self.onAppearanceChange?(self.appearance)
        }
        syncSurfaceGeometry()
    }

    var contentSize: Size<Pixels> {
        let f = hostView.bounds.size
        return Size(width: Pixels(Float(f.width)), height: Pixels(Float(f.height)))
    }

    var scaleFactor: Float { Float(window.backingScaleFactor) }

    /// Resolved through `bestMatch(from:)` rather than by comparing
    /// `effectiveAppearance.name` to `.darkAqua` directly.
    ///
    /// **An earlier version of this comment named the wrong appearance**, and
    /// the correction is the useful part. It said the accessibility
    /// high-contrast appearances "are *dark* and would each fail an equality
    /// test". Probed: `.accessibilityHighContrastDarkAqua` resolves to plain
    /// `NSAppearanceNameDarkAqua`, so equality would have handled it fine.
    ///
    /// The name that actually diverges is the **vibrant** one:
    /// `.vibrantDark` and `.accessibilityHighContrastVibrantDark` both resolve
    /// to `NSAppearanceNameVibrantDark`, which is not `.darkAqua` — so an
    /// equality test reports **light** for a dark window, and paints a light
    /// theme over it. `bestMatch` answers `darkAqua` for all three. Pinned by
    /// `aVibrantDarkAppearanceIsReportedAsDark` in `PlatformTests.swift`, which
    /// needs no system setting: the appearance is set on the `NSWindow`.
    var appearance: Appearance {
        let dark = hostView.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        return dark ? .dark : .light
    }

    var surface: any RenderSurface { metalSurface }

    var title: String {
        get { window.title }
        set { window.title = newValue }
    }

    func makeKeyAndVisible() {
        window.makeKeyAndOrderFront(nil)
    }

    private func syncSurfaceGeometry() {
        let scale = window.backingScaleFactor
        let bounds = hostView.bounds.size
        let pixelSize = CGSize(width: max(bounds.width * scale, 1),
                               height: max(bounds.height * scale, 1))
        metalSurface.resize(pixelSize: pixelSize, scaleFactor: scale)
        onResize?(contentSize, Float(scale))
    }

    func startDisplayLink(_ tick: @escaping (Double) -> Void) {
        self.tick = tick
        // NSView.displayLink supersedes CVDisplayLink, deprecated in full as of
        // macOS 15. It returns a CADisplayLink and fires on the main run loop,
        // so there is no thread hop into the MainActor frame (spec 4.4).
        let link = hostView.displayLink(target: self, selector: #selector(displayLinkFired))
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    func setDisplayLinkPaused(_ paused: Bool) {
        displayLink?.isPaused = paused
    }

    @objc private func displayLinkFired() {
        tick?(displayLink?.timestamp ?? 0)
    }

    func windowWillClose(_ notification: Notification) {
        displayLink?.invalidate()
        displayLink = nil
        onClose?()
    }
}

@MainActor
public final class AppKitPlatform: Platform {
    private let device: any MTLDevice
    private var windows: [AppKitWindow] = []

    public init(device: any MTLDevice) {
        self.device = device
    }

    public func openWindow(title: String, size: Size<Pixels>) throws -> any PlatformWindow {
        let window = try AppKitWindow(device: device, title: title, size: size)
        windows.append(window)
        window.makeKeyAndVisible()
        return window
    }

    public func run() {
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        app.activate(ignoringOtherApps: true)
        app.run()
    }
}
#endif
