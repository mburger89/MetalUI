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

    /// The last `mouseDragged` event, which an `NSDraggingSession` must start
    /// from (ruling `DN-K` item 2).
    var lastDragEvent: NSEvent?

    /// The event AppKit is dispatching — `NSApp.currentEvent` in production; a
    /// test scripts it (ruling `MN-AA`: an Edit action tells a menu click from
    /// a declined key equivalent by it).
    var currentEvent: @MainActor () -> NSEvent? = { NSApp.currentEvent }

    /// The last key equivalent offered to the window, by identity (`MN-J` item
    /// 3): AppKit may hand the same declined event to `keyDown(with:)`, and an
    /// Edit action may run with it current (`MN-AA`); neither delivers it again.
    var lastOfferedKeyEquivalent: NSEvent?

    /// Whether a control-press is in flight (`MN-B`, `MN-AC` item 1): it went
    /// out as `.rightMouseDown`, so its up is `.rightMouseUp` and a drag in
    /// between is a secondary drag, `.rightMouseDragged` (`CI-E` item 3).
    var controlClickInFlight = false

    /// The cursor `AppKitWindow.setPointerStyle(_:)` last chose (ruling `CI-H`
    /// item 8); `cursorUpdate(with:)` answers with it.
    var pointerCursor: NSCursor = .arrow

    init(surface: MetalLayerSurface) {
        self.surface = surface
        super.init(frame: .zero)
        // Order matters: assign the layer first. Setting `wantsLayer` first makes
        // AppKit create its own backing layer, and the CAMetalLayer is discarded.
        layer = surface.backingLayer
        wantsLayer = true
        layerContentsRedrawPolicy = .duringViewResize
        registerForDraggedTypes(AppKitDragAndDrop.registeredTypes)   // DN-L
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
    /// what makes `mouseExited(with:)` below fire — declared for §8.1's future
    /// `mouseExited` hook, which `SV-N` item 7 finally consumes (the pointer
    /// leaving the window, `.pointerExited`). `.activeInKeyWindow` is what keeps a
    /// background window's tracking area from firing hover into a window the
    /// user is not interacting with. `.inVisibleRect` is the mechanism this
    /// whole override exists to pair with. `.cursorUpdate` makes AppKit call
    /// `cursorUpdate(with:)` on entry, so the pointer style `Window` chose
    /// shows there (ruling `CI-H` item 8).
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(
            rect: .zero, // ignored: `.inVisibleRect` tracks the view's own bounds
            options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect, .cursorUpdate],
            owner: self, userInfo: nil)
        addTrackingArea(area)
        trackingArea = area
    }

    /// AppKit asks for the cursor when the pointer enters the view and when
    /// cursor rects are re-evaluated — the tracking area's `.cursorUpdate`
    /// option (ruling `CI-H` item 8). Answered with the style `Window` last
    /// chose, never `super` (which would set the arrow). Pinned by
    /// `appKitSetPointerStyleSetsTheCursorAndCursorUpdateKeepsIt` and
    /// `theHostViewsTrackingAreaRequestsCursorUpdates`.
    override func cursorUpdate(with event: NSEvent) {
        pointerCursor.set()
    }

    /// Whether the pointer is inside this view now — the window's own reading,
    /// so a style chosen between events shows at once.
    var pointerIsInside: Bool {
        guard let window else { return false }
        return bounds.contains(convert(window.mouseLocationOutsideOfEventStream, from: nil))
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

    /// `event` as a `MouseEvent` carrying `buttonNumber` — 0 and 1 by
    /// construction for the primary and secondary cases (ruling `CI-E` item 1:
    /// `NSEvent.mouseEvent` reports 0 for a made right-button event), the
    /// event's own for the other buttons.
    private func mouseEvent(_ event: NSEvent, button: Int = 0) -> MouseEvent {
        MouseEvent(position: point(event), modifiers: modifiers(event), clickCount: event.clickCount,
                   buttonNumber: button)
    }

    /// A control-press is a secondary press on AppKit alone (rulings `MN-B`,
    /// `MN-AC` item 1 — SDL keeps it primary for `List`'s toggle): it goes out
    /// as `.rightMouseDown`, its release as `.rightMouseUp`, and a drag between
    /// them as `.rightMouseDragged` (`CI-E` item 3). **Migration**: a
    /// control-click no longer presses a `Button` or runs an `onClick`/tap
    /// here, and a control-drag is a secondary drag.
    override func mouseDown(with event: NSEvent) {
        if event.modifierFlags.contains(.control) {
            controlClickInFlight = true
            _ = onInput?(.rightMouseDown(mouseEvent(event, button: 1)))
            return
        }
        _ = onInput?(.mouseDown(mouseEvent(event)))
    }

    override func mouseUp(with event: NSEvent) {
        if controlClickInFlight {
            controlClickInFlight = false
            _ = onInput?(.rightMouseUp(mouseEvent(event, button: 1)))
            return
        }
        _ = onInput?(.mouseUp(mouseEvent(event)))
    }

    /// The secondary button (`MN-B`): overridden whole, so `NSView`'s default —
    /// popping up `self.menu` and passing the event on — never runs.
    override func rightMouseDown(with event: NSEvent) {
        _ = onInput?(.rightMouseDown(mouseEvent(event, button: 1)))
    }

    override func rightMouseUp(with event: NSEvent) {
        _ = onInput?(.rightMouseUp(mouseEvent(event, button: 1)))
    }

    /// Motion with the secondary button held (ruling `CI-E` items 1 and 3):
    /// overridden whole, no `super`. Pinned by
    /// `appKitOtherButtonsAndRightDragReachOnInput`.
    override func rightMouseDragged(with event: NSEvent) {
        _ = onInput?(.rightMouseDragged(mouseEvent(event, button: 1)))
    }

    /// The middle and every further button (ruling `CI-E` items 1 and 3),
    /// carrying AppKit's `buttonNumber`; overridden whole, no `super`. Pinned
    /// by `appKitOtherButtonsAndRightDragReachOnInput`.
    override func otherMouseDown(with event: NSEvent) {
        _ = onInput?(.otherMouseDown(mouseEvent(event, button: event.buttonNumber)))
    }

    override func otherMouseDragged(with event: NSEvent) {
        _ = onInput?(.otherMouseDragged(mouseEvent(event, button: event.buttonNumber)))
    }

    override func otherMouseUp(with event: NSEvent) {
        _ = onInput?(.otherMouseUp(mouseEvent(event, button: event.buttonNumber)))
    }

    /// AppKit's phase as the seam's (ruling `CI-I` item 1). `NSEvent.Phase`
    /// is an option set; an event carries one phase, `.stationary` (fingers
    /// resting mid-gesture) reading as `.changed`.
    nonisolated static func inputPhase(_ phase: NSEvent.Phase) -> InputPhase {
        if phase.contains(.cancelled) { return .cancelled }
        if phase.contains(.ended) { return .ended }
        if phase.contains(.began) { return .began }
        if phase.contains(.changed) || phase.contains(.stationary) { return .changed }
        if phase.contains(.mayBegin) { return .mayBegin }
        return .none
    }

    /// A trackpad pinch step (ruling `CI-J` item 1): this event's additive
    /// magnification and phase. Pinned by
    /// `appKitMagnifyAndRotateReachOnInputWithDeltasAndPhases`.
    override func magnify(with event: NSEvent) {
        _ = onInput?(.magnify(MagnifyEvent(position: point(event), magnification: Double(event.magnification),
                                           phase: Self.inputPhase(event.phase), modifiers: modifiers(event),
                                           timestamp: event.timestamp)))
    }

    /// A trackpad rotation step (ruling `CI-J` item 1). **Negated once, here**
    /// (`CI-C` item 2, probe `Q1`): AppKit's `rotation` is counterclockwise-
    /// positive, the seam's clockwise-positive on a y-down screen. Pinned by
    /// `appKitMagnifyAndRotateReachOnInputWithDeltasAndPhases`.
    override func rotate(with event: NSEvent) {
        _ = onInput?(.rotate(RotateEvent(position: point(event), rotation: -Double(event.rotation),
                                         phase: Self.inputPhase(event.phase), modifiers: modifiers(event),
                                         timestamp: event.timestamp)))
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

    /// The pointer left the view (ruling `SV-N` item 7): the tracking area's
    /// `.mouseEnteredAndExited` option — declared since M3 for exactly this
    /// hook — makes AppKit call it. Pinned by
    /// `appKitMouseExitedDeliversPointerExited` (a real `NSEvent` to this
    /// override; real pointer tracking is human check U8).
    override func mouseExited(with event: NSEvent) {
        _ = onInput?(.pointerExited)
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

    /// The gesture phase from `NSEvent.phase`, the momentum phase from
    /// `NSEvent.momentumPhase`, `isPrecise` from `hasPreciseScrollingDeltas`
    /// (ruling `CI-I` item 6). Pinned by
    /// `appKitScrollWheelCarriesPhaseMomentumAndPrecision`.
    override func scrollWheel(with event: NSEvent) {
        _ = onInput?(.scrollWheel(ScrollEvent(
            position: point(event),
            delta: Self.scrollDelta(x: event.scrollingDeltaX, y: event.scrollingDeltaY,
                                    precise: event.hasPreciseScrollingDeltas),
            modifiers: modifiers(event),
            phase: Self.inputPhase(event.phase),
            momentumPhase: Self.inputPhase(event.momentumPhase),
            isPrecise: event.hasPreciseScrollingDeltas,
            timestamp: event.timestamp)))
    }

    override func mouseDragged(with event: NSEvent) {
        if controlClickInFlight {   // a control-press's drag is a secondary drag (CI-E item 3)
            _ = onInput?(.rightMouseDragged(MouseEvent(position: point(event), modifiers: modifiers(event),
                                                       buttonNumber: 1)))
            return
        }
        lastDragEvent = event   // an NSDraggingSession starts from it (DN-K item 2)
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
        // A key equivalent the window already declined (`MN-J` item 3): AppKit
        // hands the same event here after the main menu passed on it.
        if event === lastOfferedKeyEquivalent { return }
        if textInputCaret != nil, !event.modifierFlags.contains(.command) {
            keyInFlight = event
            defer { keyInFlight = nil }
            if inputContext?.handleEvent(event) == true { return }
        }
        _ = onInput?(.keyDown(keyEvent(event)))
    }

    /// A ⌘-key reaches the window **before the main menu** (ruling `MN-J` item
    /// 3): while this view is first responder, AppKit's key-equivalent pass
    /// offers the event here first and the answer is the window's claim — so a
    /// `Button`'s, a field's or a command's ⌘-key wins over the menu, and the
    /// menu sees only what the window declined (Quit, Hide, Minimize…). A ⌃-key
    /// is offered the same way (`MN-AI`), so a ⌃K command cannot take ⌃K from a
    /// `Button` or a field's editing keys — except while marked text is
    /// composing, when it belongs to the input method. The event is remembered
    /// by identity and never offered twice; `keyDown(with:)` and the Edit
    /// actions (`MN-AA`) skip it.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let flags = event.modifierFlags
        let offered = flags.contains(.command) || (flags.contains(.control) && !hasMarkedText())
        guard event.type == .keyDown, offered, window?.firstResponder === self else {
            return super.performKeyEquivalent(with: event)
        }
        if event === lastOfferedKeyEquivalent { return false }
        lastOfferedKeyEquivalent = event
        return onInput?(.keyDown(keyEvent(event))) ?? false
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
    /// Internal, not private, so `AppKitPresentations.swift` can attach sheets
    /// to it (rulings `SV-F`, `SV-J`, `SV-M`).
    let window: NSWindow
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

    // MARK: Reduce Motion (plan task 13, ruling AN-AD)

    /// A live read of `NSWorkspace.shared.accessibilityDisplayShouldReduceMotion`,
    /// never a cache — the source SwiftUI reads (probe
    /// `swiftui-transactions-animation.swift` R1, R2).
    var accessibilityReduceMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    /// Fired with the new value when a re-read differs from the last one.
    var onAccessibilityReduceMotionChange: ((Bool) -> Void)?

    /// The value the last re-read saw, updated whether or not a callback is
    /// set (`lastControlActiveState`'s reason).
    private var lastAccessibilityReduceMotion = false

    /// Where the display-options notification is observed —
    /// `NSWorkspace.shared.notificationCenter` in production (a workspace
    /// notification is posted there, not on `.default`); a test assigns a
    /// private center. Selector-based, so the path a test drives is the one
    /// production runs.
    var workspaceNotificationCenter: NotificationCenter = NSWorkspace.shared.notificationCenter {
        didSet {
            oldValue.removeObserver(self, name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
                                    object: nil)
            observeAccessibilityReduceMotion()
        }
    }

    private func observeAccessibilityReduceMotion() {
        workspaceNotificationCenter.addObserver(
            self, selector: #selector(accessibilityDisplayOptionsNotification(_:)),
            name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil)
    }

    @objc private func accessibilityDisplayOptionsNotification(_ notification: Notification) {
        refreshAccessibilityReduceMotion()
    }

    /// Re-reads the setting and reports it if it changed — what SwiftUI does
    /// on the same notification (R2).
    func refreshAccessibilityReduceMotion() {
        let reduceMotion = accessibilityReduceMotion
        guard reduceMotion != lastAccessibilityReduceMotion else { return }
        lastAccessibilityReduceMotion = reduceMotion
        onAccessibilityReduceMotionChange?(reduceMotion)
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
        lastAccessibilityReduceMotion = accessibilityReduceMotion
        observeAccessibilityReduceMotion()
        lastReportedAppearance = appearance
        accessibilityBridge.hostView = hostView
        hostView.accessibilityBridge = accessibilityBridge
        hostView.onInput = { [weak self] event in self?.onInput?(event) ?? false }
        hostView.onGeometryChange = { [weak self] in self?.syncSurfaceGeometry() }
        hostView.onAppearanceChange = { [weak self] in
            guard let self else { return }
            self.reportAppearance()
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

    /// The appearance last handed to `onAppearanceChange`, so
    /// `setPreferredColorScheme(_:)` reports a forced change exactly once
    /// whether or not AppKit calls `viewDidChangeEffectiveAppearance`
    /// synchronously from the `NSWindow.appearance` write.
    private var lastReportedAppearance: Appearance?

    private func reportAppearance() {
        let current = appearance
        lastReportedAppearance = current
        onAppearanceChange?(current)
    }

    /// Sets the `NSWindow`'s own appearance (ruling `CR-M`): `.aqua` or
    /// `.darkAqua`, or `nil` to follow the application again (probe
    /// `swiftui-colour.swift` `P8b`) — so the title bar, native menus and
    /// context menus match the content. The resulting effective appearance
    /// is reported through `onAppearanceChange` (once, if it changed), so
    /// `Window`'s platform appearance agrees with the forced one. Pinned by
    /// `settingAPreferredColorSchemeSetsTheNSWindowsAppearanceAndReportsIt`.
    func setPreferredColorScheme(_ colorScheme: ColorScheme?) {
        window.appearance = colorScheme.map { NSAppearance(named: $0 == .dark ? .darkAqua : .aqua) } ?? nil
        if appearance != lastReportedAppearance { reportAppearance() }
    }

    /// Shows `style` (ruling `CI-H` item 8): the host view keeps the mapped
    /// `NSCursor` for every `cursorUpdate(with:)`, and it is set at once while
    /// the pointer is inside the view. Pinned by
    /// `appKitSetPointerStyleSetsTheCursorAndCursorUpdateKeepsIt`.
    func setPointerStyle(_ style: PlatformPointerStyle) {
        let cursor = AppKitCursor.cursor(for: style)
        hostView.pointerCursor = cursor
        if hostView.pointerIsInside { cursor.set() }
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

    /// Hands a drag leaving the window to AppKit (ruling `DN-K`): an
    /// `NSDraggingSession` from the last `mouseDragged` event, one item carrying
    /// every representation with AppKit's picture of the payload (`DN-K` item
    /// 2). `false` when no drag event has been seen — there is nothing to start
    /// a session from. AppKit's session then owns the drag, its release
    /// included.
    func beginExternalDrag(_ representations: [DragRepresentation], at position: Point<Pixels>) -> Bool {
        guard let event = hostView.lastDragEvent else { return false }
        let item = AppKitDragAndDrop.draggingItem(
            for: representations,
            at: NSPoint(x: CGFloat(position.x.value), y: CGFloat(position.y.value)))
        startDraggingSession([item], event)
        return true
    }

    /// Shows `menu` as a native `NSMenu` (ruling `MN-C` item 2) popped up at
    /// `position` in the host view — flipped, so MetalUI's point is the host
    /// view's — and answers `true`. AppKit's tracking loop runs inside the
    /// call; the outcome, the chosen item's id or `nil` for a dismissal, is
    /// delivered as `.menuAction` **after** the call returns (`MN-C` item 4), so
    /// `Window`'s dispatch is never re-entered.
    func presentMenu(_ menu: PlatformMenu, at position: Point<Pixels>) -> Bool {
        let target = AppKitMenuTarget()
        let built = AppKitMenuBuilder.menu(from: menu, target: target)
        menuPresenter(built, NSPoint(x: CGFloat(position.x.value), y: CGFloat(position.y.value)), hostView)
        let outcome = MenuActionEvent(menu: menu.token, item: target.chosen)
        scheduleMenuOutcome { [weak self] in _ = self?.onInput?(.menuAction(outcome)) }
        return true
    }

    /// Pops `menu` up at `point` (host-view coordinates) in `view` and returns
    /// once AppKit's tracking loop ends — `NSMenu.popUp(positioning:at:in:)`
    /// in production; a test injects a presenter that performs an item or
    /// dismisses (spec §3.5).
    var menuPresenter: @MainActor (NSMenu, NSPoint, NSView) -> Void = { menu, point, view in
        menu.popUp(positioning: nil, at: point, in: view)
    }

    /// Runs `deliver` after `presentMenu` has returned, never inside it (`MN-C`
    /// item 4) — the next main-actor turn in production; a test holds the block
    /// and runs it after the call.
    var scheduleMenuOutcome: @MainActor (_ deliver: @escaping @MainActor () -> Void) -> Void = { deliver in
        Task { @MainActor in deliver() }
    }

    /// Starts an `NSDraggingSession` from `event` — the host view's own in
    /// production; a test injects a recorder (ruling `DN-X` item 1).
    lazy var startDraggingSession: @MainActor ([NSDraggingItem], NSEvent) -> Void = { [weak self] items, event in
        guard let host = self?.hostView else { return }
        host.beginDraggingSession(with: items, event: event, source: host)
    }

    /// The sheets this window has begun and not yet answered, by token
    /// (rulings `SV-F`, `SV-J`; `AppKitPresentations.swift`).
    var presentations: [Int: AppKitPresentation] = [:]

    /// Run at the end of AppKit's sheet completion handler, after the answer
    /// was queued — a test's view of what was delivered *during* that call
    /// (spec test 1.3). `nil` in production.
    var onSheetCompletionForTesting: (() -> Void)?

    func setDisplayLinkPaused(_ paused: Bool) {
        displayLink?.isPaused = paused
    }

    /// The window's `NSToolbar` and its native controls (ruling `MD-J` item 3,
    /// `AppKitToolbar.swift`); outcomes reach `onInput` as `.toolbarAction`.
    /// Internal so a test can reach the controller.
    lazy var toolbarController = AppKitToolbarController { [weak self] event in
        _ = self?.onInput?(event)
    }

    /// Shows `toolbar` as a real `NSToolbar` of native controls and answers
    /// `true` (ruling `MD-J` item 3): updated in place while the ids and kinds
    /// stay (`UP`), rebuilt otherwise; `nil` removes it. The window grows to
    /// keep its content size (`TB1`). Pinned by
    /// `theAppKitToolbarBuildsNativeItemsAndUpdatesThemInPlace`.
    func setToolbar(_ toolbar: PlatformToolbar?) -> Bool {
        // The content keeps its size and the window grows (or shrinks) by the
        // toolbar (`TB1`). AppKit alone does not hold it for a window built
        // here — measured: a 900 × 200 content read 900 × 232 after the
        // toolbar was set, the frame 52 taller — so it is restored explicitly.
        let content = window.contentLayoutRect.size
        toolbarController.apply(toolbar, to: window)
        if window.contentLayoutRect.size != content { window.setContentSize(content) }
        return true
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

/// The macOS platform: AppKit windows drawn with Metal, every window sharing
/// one `Renderer` (`RS-C`). `App`'s default on macOS.
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

    /// Opens an AppKit window titled `title` with a content size of `size`
    /// points, drawn by the shared renderer.
    public func openWindow(title: String, size: Size<Pixels>) throws -> any PlatformWindow {
        let renderer = try sharedRenderer ?? Renderer(device: device)
        sharedRenderer = renderer
        let window = try AppKitWindow(device: device, renderer: renderer, title: title, size: size,
                                      accessibilitySignal: makeAccessibilitySignal())
        windows.append(window)
        window.makeKeyAndVisible()
        return window
    }

    /// The icon this platform last assigned to
    /// `NSApplication.applicationIconImage`, `nil` after `[]` (ruling `AI-I`:
    /// the getter returns a snapshot, never this object, so tests read this).
    private(set) var iconImage: NSImage?

    /// Sets the Dock icon (ruling `AI-E`): one `NSImage` holding a
    /// representation per texture, its bytes used as stored (premultiplied
    /// RGBA8, sRGB — no second premultiply), sized as the largest texture so
    /// AppKit picks a representation by pixel density, assigned to
    /// `NSApplication.applicationIconImage`. `[]` assigns `nil`, which restores
    /// the bundle's icon, else the generic executable icon. The image is
    /// assigned again when ``run()`` starts the application.
    public func setApplicationIcon(_ images: [ImageTexture]) {
        iconImage = AppKitIcon.image(from: images)
        NSApplication.shared.applicationIconImage = iconImage
    }

    /// The installed menu bar's delegate and command target, kept alive here
    /// (an `NSMenu`'s delegate and an item's target are weak).
    private var installedMenuBar: AppKitMenuBar?

    /// Installs `NSApp.mainMenu` built from `menuBar` (ruling `MN-I` item 3):
    /// each top-level menu rebuilt from fresh content when it opens, standard
    /// items on AppKit's own selectors (the application menu's targeting
    /// `NSApp`, the rest the responder chain — the host view answers the Edit
    /// items, `MN-K`), command items running `menuBar.perform`. A later call
    /// replaces the bar.
    public func setMenuBar(_ menuBar: PlatformMenuBar) {
        let bar = AppKitMenuBar(menuBar)
        installedMenuBar = bar
        NSApplication.shared.mainMenu = bar.makeMainMenu()
    }

    /// Runs `NSApplication`'s event loop; returns when the application stops.
    public func run() {
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        // `AI-E` item 4: an icon set before `run()` is assigned again once the
        // process is a regular application with a Dock tile. Defensive and
        // **pinned by no test** (`AI-K`: no headless test can call `run()`);
        // human check O1 is its only check.
        if let iconImage { app.applicationIconImage = iconImage }
        app.activate(ignoringOtherApps: true)
        app.run()
    }
}
#endif
