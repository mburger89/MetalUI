#if os(macOS)
import AppKit
import Metal
import QuartzCore
import MetalUICore
import MetalUIPlatform
import MetalUIRender

/// Hosts the CAMetalLayer and funnels AppKit events into InputEvent.
@MainActor
final class MetalHostView: NSView {
    var onInput: ((InputEvent) -> Bool)?
    var onGeometryChange: (() -> Void)?
    var onAppearanceChange: (() -> Void)?

    /// The accessibility bridge this view answers clients from
    /// (`AppKitAccessibility.swift`). Strong: the bridge holds this view weakly
    /// (ruling AB-D's ownership table).
    var accessibilityBridge: AppKitAccessibilityBridge?

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

    /// Points one line of a non-precise scroll device moves. AppKit's own
    /// default: a fresh `NSScrollView` reports `verticalLineScroll` and
    /// `horizontalLineScroll` of 10.0. The two tests that pin `scrollDelta`
    /// (in `PlatformTests.swift`) take their expected values from
    /// `NSScrollView` at test time, not from this constant.
    nonisolated static let pointsPerScrollLine: CGFloat = 10

    /// `NSEvent.scrollingDeltaX/Y` in points, whatever device produced them.
    ///
    /// **Those fields change unit with `hasPreciseScrollingDeltas`.** A precise
    /// device (trackpad, Magic Mouse) reports points; a non-precise one (a
    /// conventional wheel mouse) reports LINES. Measured by synthesizing
    /// `CGEvent(scrollWheelEvent2Source:units:.line …)` and converting with
    /// `NSEvent(cgEvent:)`: `hasPreciseScrollingDeltas` is false and
    /// `scrollingDeltaY` is the raw line count, 1.0 for one line. The seam
    /// used to copy that count into `ScrollEvent.delta` as points, so a wheel
    /// mouse moved content about a tenth as far as `NSScrollView` does, and
    /// every trackpad look passed because the precise arm was already right.
    ///
    /// Converted here, at the AppKit boundary, rather than by carrying the flag
    /// on `ScrollEvent`: that type is public and crosses into `MetalUI`.
    /// `event.deltaY` is not the answer either, since it reads 1.0 for a
    /// one-line event and also for a 10-point precise one.
    ///
    /// **What is not measured:** a physical wheel's per-detent line count after
    /// the window server's scroll acceleration. The synthesized event proves
    /// the unit, not what one click of a real wheel produces.
    ///
    /// Pinned by `aNonPreciseScrollDeltaIsScaledFromLinesToPointsAndAPreciseOneIsNot`
    /// (this function) and
    /// `aWheelMouseEventReachesOnInputInPointsAndATrackpadEventIsUnchanged`
    /// (the `scrollWheel(with:)` call site, with real `NSEvent`s).
    nonisolated static func scrollDelta(x: CGFloat, y: CGFloat, precise: Bool) -> Point<Pixels> {
        let scale: CGFloat = precise ? 1 : pointsPerScrollLine
        return Point(x: Pixels(Float(x * scale)), y: Pixels(Float(y * scale)))
    }

    override func scrollWheel(with event: NSEvent) {
        let momentum = event.momentumPhase != []
        _ = onInput?(.scrollWheel(ScrollEvent(
            position: point(event),
            delta: Self.scrollDelta(x: event.scrollingDeltaX, y: event.scrollingDeltaY,
                                    precise: event.hasPreciseScrollingDeltas),
            modifiers: modifiers(event),
            isMomentum: momentum,
            timestamp: event.timestamp)))
    }

    override func mouseDragged(with event: NSEvent) {
        _ = onInput?(.mouseDragged(MouseEvent(position: point(event),
                                              modifiers: modifiers(event))))
    }

    private func keyEvent(_ event: NSEvent) -> KeyEvent {
        KeyEvent(charactersIgnoringModifiers: event.charactersIgnoringModifiers ?? "",
                 characters: event.characters ?? "",
                 modifiers: modifiers(event),
                 isRepeat: event.isARepeat,
                 timestamp: event.timestamp)
    }

    // MARK: Text input (ruling TI-A)

    /// The caret `setTextInputArea` last gave, in view points; nil while no
    /// text field is focused, and then every key is a plain `keyDown`.
    var textInputCaret: Bounds<Pixels>? {
        didSet {
            if textInputCaret == nil && oldValue != nil && !markedText.isEmpty {
                markedText = ""
                inputContext?.discardMarkedText()
            }
        }
    }

    /// The input method's current marked text, for `hasMarkedText`.
    private(set) var markedText = ""

    /// The key event the input context is handling, so `doCommand(by:)` can
    /// re-deliver it as the `keyDown` it was.
    private var keyInFlight: NSEvent?

    /// While text input is active a non-command key goes through the input
    /// context first: it answers with `insertText`, `setMarkedText` or
    /// `doCommand(by:)`. A command key, or any key with text input off, is a
    /// plain `keyDown`, so shortcuts behave as before.
    override func keyDown(with event: NSEvent) {
        if textInputCaret != nil, !event.modifierFlags.contains(.command) {
            keyInFlight = event
            defer { keyInFlight = nil }
            if inputContext?.handleEvent(event) == true { return }
        }
        _ = onInput?(.keyDown(keyEvent(event)))
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

/// The host view is AppKit's text-input client (ruling TI-A): the input
/// context hands it committed text, marked text and editing commands, and
/// asks where the caret is for its candidate window. MetalUI's field owns the
/// text, so the ranges answered here describe only the marked text.
extension MetalHostView: @preconcurrency NSTextInputClient {
    private static func plain(_ string: Any) -> String {
        (string as? NSAttributedString)?.string ?? (string as? String) ?? ""
    }

    func insertText(_ string: Any, replacementRange: NSRange) {
        markedText = ""
        _ = onInput?(.textInput(Self.plain(string)))
    }

    func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
        let text = Self.plain(string)
        markedText = text
        _ = onInput?(.textComposition(TextComposition(
            text: text, selection: Self.characterRange(selectedRange, in: text))))
    }

    func unmarkText() {
        guard !markedText.isEmpty else { return }
        let text = markedText
        markedText = ""
        _ = onInput?(.textInput(text))
    }

    /// `doCommand(by:)` is the input context declining a key — an arrow,
    /// delete, return, escape — so it reaches MetalUI as the key it was.
    override func doCommand(by selector: Selector) {
        if let keyInFlight { _ = onInput?(.keyDown(keyEvent(keyInFlight))) }
    }

    func selectedRange() -> NSRange { NSRange(location: 0, length: 0) }

    func markedRange() -> NSRange {
        markedText.isEmpty ? NSRange(location: NSNotFound, length: 0)
            : NSRange(location: 0, length: (markedText as NSString).length)
    }

    func hasMarkedText() -> Bool { !markedText.isEmpty }

    func attributedSubstring(forProposedRange range: NSRange,
                             actualRange: NSRangePointer?) -> NSAttributedString? { nil }

    func validAttributesForMarkedText() -> [NSAttributedString.Key] { [] }

    /// The caret rectangle in screen coordinates, where the candidate window
    /// goes.
    func firstRect(forCharacterRange range: NSRange, actualRange: NSRangePointer?) -> NSRect {
        guard let caret = textInputCaret, let window else { return .zero }
        let local = NSRect(x: CGFloat(caret.origin.x.value), y: CGFloat(caret.origin.y.value),
                           width: CGFloat(caret.size.width.value), height: CGFloat(caret.size.height.value))
        return window.convertToScreen(convert(local, to: nil))
    }

    func characterIndex(for point: NSPoint) -> Int { NSNotFound }

    /// An `NSRange` of UTF-16 units in `text` as Character offsets, clamped.
    nonisolated static func characterRange(_ range: NSRange, in text: String) -> Range<Int> {
        // The Characters that end at or before `unit` — rounding down inside
        // a grapheme.
        func characters(upTo unit: Int) -> Int {
            var units = 0, characters = 0
            for character in text {
                units += character.utf16.count
                if units > unit { break }
                characters += 1
            }
            return characters
        }
        guard range.location != NSNotFound else { return text.count..<text.count }
        let lower = characters(upTo: range.location)
        let upper = max(lower, characters(upTo: range.location + range.length))
        return lower..<upper
    }
}

@MainActor
final class AppKitWindow: NSObject, PlatformWindow, NSWindowDelegate {
    private let window: NSWindow
    /// Internal, not private, so platform and end-to-end tests can ask it what
    /// an accessibility client would.
    let hostView: MetalHostView
    private let metalSurface: MetalLayerSurface
    private var displayLink: CADisplayLink?
    private var tick: ((Double) -> Void)?

    var onInput: ((InputEvent) -> Bool)?
    var onResize: ((Size<Pixels>, Float) -> Void)?
    var onAppearanceChange: ((Appearance) -> Void)?
    var onClose: (() -> Void)?

    // MARK: Control active state (ruling EV-AB, amended by EV-AF)

    /// `isKeyWindow` → `.key`; else the application active → `.active`; else
    /// `.inactive`. MetalUI's choice: SwiftUI's mapping is measured only for
    /// the last row (probe `swiftui-environment-control-state.swift` C0).
    nonisolated static func controlActiveState(isKeyWindow: Bool,
                                               isApplicationActive: Bool) -> ControlActiveState {
        if isKeyWindow { return .key }
        return isApplicationActive ? .active : .inactive
    }

    /// The two facts the state is read from — live reads of `isKeyWindow` and
    /// `NSApp.isActive` in production. Internal so a test can script them: a
    /// locked or headless session cannot make a window key.
    var keyStatus: @MainActor () -> (isKeyWindow: Bool, isApplicationActive: Bool)

    /// A live read, never a cache.
    var controlActiveState: ControlActiveState {
        let status = keyStatus()
        return Self.controlActiveState(isKeyWindow: status.isKeyWindow,
                                       isApplicationActive: status.isApplicationActive)
    }

    /// Fired with the new value when a re-read differs from the last one.
    var onControlActiveStateChange: ((ControlActiveState) -> Void)?

    /// The value the last re-read saw, updated **whether or not a callback is
    /// set**: `makeKeyAndOrderFront` can post `didBecomeKey` before `Window`
    /// assigns the callback, and `Window.init` reads the live getter anyway.
    private var lastControlActiveState: ControlActiveState = .inactive

    /// Where the key and activation notifications are observed — `.default`
    /// in production; a test assigns a private center so it may post the
    /// application notifications without reaching AppKit's own observers.
    /// Observed explicitly, selector-based, not through `NSWindowDelegate`,
    /// so the path a test drives by posting is the one production runs.
    var notificationCenter: NotificationCenter = .default {
        didSet {
            oldValue.removeObserver(self)
            observeControlActiveState()
        }
    }

    private func observeControlActiveState() {
        let center = notificationCenter
        let selector = #selector(controlActiveStateNotification(_:))
        center.addObserver(self, selector: selector, name: NSWindow.didBecomeKeyNotification, object: window)
        center.addObserver(self, selector: selector, name: NSWindow.didResignKeyNotification, object: window)
        center.addObserver(self, selector: selector, name: NSApplication.didBecomeActiveNotification, object: nil)
        center.addObserver(self, selector: selector, name: NSApplication.didResignActiveNotification, object: nil)
    }

    @objc private func controlActiveStateNotification(_ notification: Notification) {
        refreshControlActiveState()
    }

    /// Re-reads the state and reports it if it changed.
    func refreshControlActiveState() {
        let state = controlActiveState
        guard state != lastControlActiveState else { return }
        lastControlActiveState = state
        onControlActiveStateChange?(state)
    }

    /// Both accessibility requirements forward to the bridge, which answers
    /// clients on the host view (`AppKitAccessibility.swift`, lane 2 of the
    /// accessibility bridge). Assigning the handler delivers an activation the
    /// signal reported before anyone listened (AB-B).
    var onAccessibilityRequest: ((MetalUIPlatform.AccessibilityRequest) -> Bool)? {
        get { accessibilityBridge.onRequest }
        set { accessibilityBridge.onRequest = newValue }
    }
    func publishAccessibilityTree(_ tree: AccessibilityTree) { accessibilityBridge.publish(tree) }

    /// Ruling TI-A: the host view becomes a live text-input client while a
    /// caret is set.
    func setTextInputArea(_ caret: Bounds<Pixels>?) {
        let changed = hostView.textInputCaret != caret
        hostView.textInputCaret = caret
        if changed, caret != nil { hostView.inputContext?.invalidateCharacterCoordinates() }
    }

    func readClipboard() -> String? { NSPasteboard.general.string(forType: .string) }

    func writeClipboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    /// Owned here and by the host view; it holds the host view weakly (AB-D).
    let accessibilityBridge: AppKitAccessibilityBridge

    /// `accessibilitySignal` is `VoiceOverSignal()` in production; a test passes
    /// a scripted one through `AppKitPlatform(device:accessibilitySignal:)`
    /// (AB-AC). It is observed synchronously here, so a running screen reader
    /// activates the bridge before `Window.init` has assigned a handler.
    init(device: any MTLDevice, renderer: Renderer, title: String, size: Size<Pixels>,
         accessibilitySignal: any AccessibilityClientSignal) throws {
        metalSurface = MetalLayerSurface(device: device)
        windowRenderer = MetalWindowRenderer(renderer: renderer, surface: metalSurface)
        hostView = MetalHostView(surface: metalSurface)
        accessibilityBridge = AppKitAccessibilityBridge(signal: accessibilitySignal,
                                                        poster: SystemAccessibilityNotificationPoster())

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
        let nsWindow = window
        keyStatus = { (nsWindow.isKeyWindow, NSApplication.shared.isActive) }

        super.init()
        window.delegate = self
        lastControlActiveState = controlActiveState
        observeControlActiveState()
        accessibilityBridge.hostView = hostView
        hostView.accessibilityBridge = accessibilityBridge
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

    /// The layer surface, still reachable for the platform tests that draw
    /// into it directly; `Window` draws through ``renderer`` (ruling RS-C).
    var surface: any RenderSurface { metalSurface }

    /// This window's `WindowRenderer`: the platform's shared Metal renderer,
    /// drawing into this window's layer.
    let windowRenderer: MetalWindowRenderer
    var renderer: any WindowRenderer { windowRenderer }

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
        // `targetTimestamp`, not `timestamp` (design spec §4.4). `timestamp` is
        // when the *previous* frame was displayed; `targetTimestamp` is when
        // the frame this callback is building is expected to be presented —
        // one whole frame interval later (8.33 ms at 120 Hz). An animation
        // evaluated against `timestamp` is a frame behind from the moment it
        // reads the clock.
        //
        // The only current consumer is `ScrollView`'s indicator-fade age
        // (`age = timestamp - lastScrollTime` in `ScrollView.paint`), so today
        // this shifts that age by one frame interval — immaterial, unasserted,
        // and invisible to a human. Unpinned: `CADisplayLink` cannot be driven
        // from a test in this repo, and `FakePlatformWindow.simulateTick`
        // supplies whatever timestamp a test chooses, so no assertion here can
        // distinguish this clock from the one it replaces — the same footing
        // CLAUDE.md already records for the display-link pause itself and for
        // `NSTrackingArea`.
        tick?(displayLink?.targetTimestamp ?? 0)
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
    /// One Metal renderer for every window — the app's when it hands one in,
    /// else made on the first window.
    private var sharedRenderer: Renderer?
    private var windows: [AppKitWindow] = []
    private let makeAccessibilitySignal: @MainActor () -> any AccessibilityClientSignal

    /// Windows opened by this platform observe `NSWorkspace.isVoiceOverEnabled`
    /// as their accessibility signal (AB-B).
    public convenience init(device: any MTLDevice) {
        self.init(device: device, accessibilitySignal: { VoiceOverSignal() })
    }

    /// A platform whose windows draw with `renderer` — the one the app made.
    public convenience init(renderer: Renderer) {
        self.init(device: renderer.device, accessibilitySignal: { VoiceOverSignal() })
        sharedRenderer = renderer
    }

    /// The test path (AB-AC): `App.openWindow` cannot pass a signal, so a test
    /// that must not depend on whether VoiceOver runs on the machine builds the
    /// platform with a scripted one and constructs `Window` over the window it
    /// opens.
    init(device: any MTLDevice,
         accessibilitySignal: @escaping @MainActor () -> any AccessibilityClientSignal) {
        self.device = device
        self.makeAccessibilitySignal = accessibilitySignal
    }

    public func openWindow(title: String, size: Size<Pixels>) throws -> any PlatformWindow {
        let renderer = try sharedRenderer ?? Renderer(device: device)
        sharedRenderer = renderer
        let window = try AppKitWindow(device: device, renderer: renderer, title: title, size: size,
                                      accessibilitySignal: makeAccessibilitySignal())
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
