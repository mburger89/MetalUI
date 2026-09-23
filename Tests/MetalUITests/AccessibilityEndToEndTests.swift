import Testing
import Foundation
import Metal
import AppKit
import MetalUICore
import MetalUIRender
@testable import MetalUIPlatform
@testable import MetalUIAppKit
@testable import MetalUI

// Lane 2 of the accessibility bridge, end to end: a real `AppKitPlatform`
// window, a real `Window` over it, and a client's reads and actions made
// through the NSAccessibility protocol methods on the real host view (spec
// `docs/superpowers/specs/2026-09-15-accessibility-bridge-design.md`, "Lane 2",
// end-to-end table).
//
// **Construction (ruling AB-AC).** `App.openWindow` cannot pass a signal, so
// each test builds `AppKitPlatform(device:accessibilitySignal:)` with a scripted
// `false` signal, opens the platform window and constructs
// `Window(platformWindow:renderer:startsDisplayLink:content:)` over it, exactly
// as `makeFakeWindow` does. With the real `VoiceOverSignal`, every test here
// would fail on a machine running VoiceOver. Each test closes its window.

/// `Accessibility.framework` (imported through `AppKit`) also exports a Swift
/// `AccessibilityRequest` (`AXRequest`), so the bare name is ambiguous in any
/// file that imports both.
private typealias Request = MetalUIPlatform.AccessibilityRequest

private func px(_ v: Float) -> Pixels { Pixels(v) }

/// A signal that reports a constant, synchronously inside `observe`, as
/// `VoiceOverSignal` delivers its first value.
@MainActor private final class ConstantSignal: AccessibilityClientSignal {
    let value: Bool
    init(_ value: Bool) { self.value = value }
    func observe(_ handler: @escaping @MainActor (Bool) -> Void) { handler(value) }
}

@MainActor private final class Model {
    var showFirst = true
    var first = 0
    var second = 0
    var count = 0
}

@MainActor private func declared<C: ElementGroup>(_ box: Box<C>, _ node: AXNode) -> Box<C> {
    box.handling { $0.axNode = node }
}

/// A real AppKit window with the scripted signal and a `Window` over it.
@MainActor private func makeAppKitWindow<Root: Element>(
    width: Int = 200, height: Int = 200, content: @escaping @MainActor () -> Root
) throws -> (Window, AppKitWindow, NSWindow) {
    let device = try #require(MTLCreateSystemDefaultDevice(), "no Metal device; run on macOS hardware")
    let platform = AppKitPlatform(device: device, accessibilitySignal: { ConstantSignal(false) })
    let platformWindow = try platform.openWindow(
        title: "AX end-to-end \(UUID().uuidString)",
        size: Size(width: px(Float(width)), height: px(Float(height))))
    let appKit = try #require(platformWindow as? AppKitWindow)
    let nsWindow = try #require(appKit.hostView.window)
    let window = Window(platformWindow: platformWindow,
                        startsDisplayLink: false, content: content)
    return (window, appKit, nsWindow)
}

private func elements(_ list: [Any]?) -> [NSAccessibilityElement] {
    (list ?? []).compactMap { $0 as? NSAccessibilityElement }
}

/// A client reads a real window's published frame, and its press runs `onClick`.
@Test @MainActor func aRealAppKitWindowPublishesItsFrameAndAPressRunsOnClick() throws {
    let model = Model()
    let (window, appKit, nsWindow) = try makeAppKitWindow {
        Column {
            declared(Box().width(px(40)).height(px(20)).onClick { model.count += 1 },
                     AXNode(role: .button, label: "Increment"))
        }
    }
    defer { nsWindow.close() }
    let host = appKit.hostView

    #expect(elements(host.accessibilityChildren()).isEmpty, "the activating query is answered from the empty tree")
    #expect(window.accessibility.isActive, "a host query reached the window as .activate")
    window.drawFrameIfNeeded()
    try #require(window.framesDrawn == 1, "control: the frame really drew on the real surface")

    let children = elements(host.accessibilityChildren())
    try #require(children.count == 1)
    let button = children[0]
    #expect(button.accessibilityRole() == .button)
    #expect(button.accessibilityLabel() == "Increment")
    try #require(!window.needsRedraw)
    #expect(button.accessibilityPerformPress())
    #expect(model.count == 1)
    #expect(window.needsRedraw, "a press dirties the window")
}

/// Arm Q, against the real host view: a key window taking mouse and key events
/// and a resize, then five frames, with no client and the signal forced `false`,
/// is never activated.
///
/// **Depends on the machine** (ruling AB-AC): an out-of-process accessibility
/// client that asks for the element under the pointer — a mouse-follow utility,
/// Accessibility Inspector's hover — reaches `accessibilityHitTest`, which is an
/// activation trigger (measured by `docs/probes/appkit-accessibility-activation-clients.swift`).
/// With such a client running and the pointer over this test's window, this
/// test reddens for a reason that is not a bridge defect.
///
/// **Whether AppKit delivers the synthesized clicks also depends on the
/// environment** (the app's activation state); the test routes each click to the
/// host view itself only when `sendEvent` did not, so either way the control
/// sees each event exactly once.
@Test @MainActor func aKeyWindowReceivingEventsIsNeverActivatedWithoutAClient() throws {
    let (window, appKit, nsWindow) = try makeAppKitWindow {
        Column { Box().width(px(40)).height(px(20)).onClick {} }
    }
    defer { nsWindow.close() }
    var requests: [Request] = []
    let windowsHandler = appKit.onAccessibilityRequest
    try #require(windowsHandler != nil, "precondition: Window.init installed its handler")
    appKit.onAccessibilityRequest = { request in
        requests.append(request)
        return windowsHandler?(request) ?? false
    }

    // Control: the events really reach the host view's overrides. Without it,
    // a synthesized event AppKit swallowed leaves "no activation" vacuous: lane
    // 2's mutation L44 (`mouseDown` activating) survived the first version of
    // this test, whose mouse events never reached the view.
    var inputs: [String] = []
    let windowsInput = appKit.onInput
    appKit.onInput = { event in
        switch event {
        case .mouseDown: inputs.append("down")
        case .mouseUp: inputs.append("up")
        case .keyDown: inputs.append("key")
        default: break
        }
        return windowsInput?(event) ?? false
    }

    nsWindow.makeKeyAndOrderFront(nil)
    nsWindow.makeFirstResponder(appKit.hostView)
    let inside = NSPoint(x: 20, y: nsWindow.contentRect(forFrameRect: nsWindow.frame).height - 10)
    for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
        let event = try #require(NSEvent.mouseEvent(
            with: type, location: inside, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: nsWindow.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
        let delivered = inputs.count
        nsWindow.sendEvent(event)
        // **AppKit usually swallows a synthesized mouse event here** (measured:
        // in the test process the app is not active and the window is not key,
        // so `sendEvent` spends the click on activation and the host view's
        // `mouseDown` never runs, while the key event below does arrive). The
        // AppKit path is still taken above; the override is called directly
        // ONLY when AppKit did not deliver, so an environment where it does (an
        // active app, e.g. under Xcode) sees each event once, not twice.
        if inputs.count == delivered {
            if type == .leftMouseDown { appKit.hostView.mouseDown(with: event) } else { appKit.hostView.mouseUp(with: event) }
        }
    }
    let key = try #require(NSEvent.keyEvent(
        with: .keyDown, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
        windowNumber: nsWindow.windowNumber, context: nil, characters: "a", charactersIgnoringModifiers: "a",
        isARepeat: false, keyCode: 0))
    nsWindow.sendEvent(key)
    nsWindow.setContentSize(NSSize(width: 260, height: 180))
    for _ in 0..<5 {
        window.setNeedsRedraw()
        window.drawFrameIfNeeded()
    }
    try #require(window.framesDrawn == 5, "control: five frames really drew")
    try #require(inputs == ["down", "up", "key"], "control: every synthesized event reached the host view")

    #expect(requests.isEmpty, """
        a window with no accessibility client was activated. If an out-of-process AX client \
        (a mouse-follow utility, Accessibility Inspector) was running with the pointer over the \
        test window, this is the machine, not the bridge: see \
        docs/probes/appkit-accessibility-activation-clients.swift and ruling AB-AC
        """)
    #expect(window.accessibility.buildCount == 0)
    #expect(!window.accessibility.isActive)
}

/// **`AB-H`'s recorded hazard, pinned with two arms that disagree.** A client
/// holding the element for a conditional's id, when the conditional vanishes and
/// an unnamed trailing sibling adopts that id, is holding the adopter: its press
/// runs the adopter's `onClick`. Naming the trailing sibling — the identity
/// rule's own remedy — detaches the held element and refuses the press.
@Test @MainActor func aHeldElementWhoseIDIsAdoptedPressesTheAdopter() throws {
    for named in [false, true] {
        let model = Model()
        let (window, appKit, nsWindow) = try makeAppKitWindow {
            Column {
                if model.showFirst {
                    declared(Box().width(px(40)).height(px(20)).onClick { model.first += 1 },
                             AXNode(role: .button, label: "First"))
                }
                // One expression of one type in both arms, so the only
                // difference between them is the name.
                let trailing = declared(Box().width(px(40)).height(px(20)).onClick { model.second += 1 },
                                        AXNode(role: .button, label: "Second"))
                named ? trailing.id("second") : trailing
            }
        }
        defer { nsWindow.close() }
        let host = appKit.hostView
        _ = host.accessibilityChildren()
        window.drawFrameIfNeeded()
        let before = elements(host.accessibilityChildren())
        try #require(before.count == 2, "named: \(named)")
        let held = before[0]
        try #require(held.accessibilityLabel() == "First", "named: \(named)")

        model.showFirst = false
        window.setNeedsRedraw()
        window.drawFrameIfNeeded()
        let after = elements(host.accessibilityChildren())
        try #require(after.count == 1, "named: \(named)")
        #expect(after[0].accessibilityLabel() == "Second")

        let pressed = held.accessibilityPerformPress()
        if named {
            #expect(held.accessibilityParent() == nil, "the named sibling never held this id: detached")
            #expect(!pressed, "a detached element refuses the press")
            #expect(model.first == 0 && model.second == 0)
        } else {
            #expect(held.accessibilityParent() as AnyObject === host, "the adopted id is still published")
            #expect(held === after[0], "the held element IS the adopter's element")
            #expect(held.accessibilityLabel() == "Second")
            #expect(pressed, "the press runs the adopter's onClick")
            #expect(model.first == 0 && model.second == 1)
        }
    }
}
