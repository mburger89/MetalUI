import Testing
import Foundation
import Metal
import AppKit
import MetalUICore
import MetalUIRender
@testable import MetalUIPlatform
@testable import MetalUIAppKit

// Window drag, lane 2, tests 4.1-4.3 (rulings `WD-D`, `WD-E`; spec
// `docs/superpowers/specs/2026-10-12-window-drag-design.md` section 5). A real
// `AppKitPlatform` window and real `NSEvent`s; `NSWindow.performDrag(with:)` is
// injected (`windowDragPerformer`) so no test runs its nested tracking loop.
// Red before: the file does not compile at `458ae26` (no `windowDragPerformer`).

@MainActor private final class ConstantSignal: AccessibilityClientSignal {
    func observe(_ handler: @escaping @MainActor (Bool) -> Void) { handler(false) }
}

@MainActor private func dragWindow(_ name: String) throws -> (AppKitWindow, NSWindow) {
    let device = try #require(MTLCreateSystemDefaultDevice(), "no Metal device; run on macOS hardware")
    let platform = AppKitPlatform(device: device, accessibilitySignal: { ConstantSignal() })
    let platformWindow = try platform.openWindow(title: "Window drag \(name) \(UUID().uuidString)",
                                                 size: Size(width: Pixels(400), height: Pixels(200)))
    let appKit = try #require(platformWindow as? AppKitWindow)
    let nsWindow = try #require(appKit.hostView.window)
    appKit.onInput = { _ in false }
    return (appKit, nsWindow)
}

@MainActor private func event(_ type: NSEvent.EventType, in window: NSWindow) throws -> NSEvent {
    try #require(NSEvent.mouseEvent(with: type, location: NSPoint(x: 100, y: 190), modifierFlags: [],
                                    timestamp: 0, windowNumber: window.windowNumber, context: nil,
                                    eventNumber: 0, clickCount: 1, pressure: 1))
}

/// **4.1** (`WD-E`). `performWindowDrag()` acts only while the host view is
/// dispatching the mouse-dragged of a held press: it drags with the stored
/// mouse-down event, once, and answers `true`; outside a dispatch, or with no
/// press held, it answers `false` and runs nothing. After it acts the press is
/// forgotten (`performDrag` consumes the mouse-up).
///
/// Mutation: drop the dispatching guard -> the outside arm red.
@MainActor
@Test func appKitWindowDragActsOnlyDuringTheDraggedEventOfAHeldPress() throws {
    let (appKit, nsWindow) = try dragWindow("4.1")
    defer { nsWindow.close() }
    var drags: [NSEvent] = []
    appKit.windowDragPerformer = { drags.append($0) }
    var answers: [Bool] = []
    appKit.onInput = { event in
        if case .mouseDragged = event { answers.append(appKit.performWindowDrag()) }
        return false
    }

    appKit.hostView.mouseDragged(with: try event(.leftMouseDragged, in: nsWindow))
    #expect(answers == [false] && drags.isEmpty, "no press held: nothing to drag with")

    let down = try event(.leftMouseDown, in: nsWindow)
    appKit.hostView.mouseDown(with: down)
    #expect(appKit.performWindowDrag() == false, "between the down and the drag: not dispatching")
    #expect(drags.isEmpty)

    appKit.hostView.mouseDragged(with: try event(.leftMouseDragged, in: nsWindow))
    #expect(answers == [false, true], "the drag dispatch acted")
    #expect(drags.count == 1 && drags.first === down, "once, with the stored mouse-down")
    #expect(appKit.performWindowDrag() == false, "outside the dispatch")

    appKit.hostView.mouseDragged(with: try event(.leftMouseDragged, in: nsWindow))
    #expect(answers == [false, true, false] && drags.count == 1, "the press was forgotten after acting")
}

/// **4.2** (`WD-E`). The held press is forgotten at the mouse-up and when the
/// window resigns key; a later drag dispatch finds none.
///
/// Mutation: keep it at the up (or at the resign) -> that arm red.
@MainActor
@Test func appKitForgetsThePressAtTheMouseUpAndOnResignKey() throws {
    let (appKit, nsWindow) = try dragWindow("4.2")
    defer { nsWindow.close() }
    let center = NotificationCenter()
    appKit.notificationCenter = center
    var drags: [NSEvent] = []
    appKit.windowDragPerformer = { drags.append($0) }
    var answers: [Bool] = []
    appKit.onInput = { event in
        if case .mouseDragged = event { answers.append(appKit.performWindowDrag()) }
        return false
    }

    appKit.hostView.mouseDown(with: try event(.leftMouseDown, in: nsWindow))
    appKit.hostView.mouseUp(with: try event(.leftMouseUp, in: nsWindow))
    appKit.hostView.mouseDragged(with: try event(.leftMouseDragged, in: nsWindow))
    #expect(answers == [false], "forgotten at the up")

    appKit.hostView.mouseDown(with: try event(.leftMouseDown, in: nsWindow))
    center.post(name: NSWindow.didResignKeyNotification, object: nsWindow)
    appKit.hostView.mouseDragged(with: try event(.leftMouseDragged, in: nsWindow))
    #expect(answers == [false, false], "forgotten on resign key")
    #expect(drags.isEmpty)
}

/// **4.3** (`WD-E`). A second primary down replaces the stored press; a
/// secondary down is not stored (and leaves the held press alone).
///
/// Mutation: store the first down only (or store the secondary) -> red.
@MainActor
@Test func appKitASecondDownReplacesTheStoredPressAndASecondaryDownIsNotStored() throws {
    let (appKit, nsWindow) = try dragWindow("4.3")
    defer { nsWindow.close() }
    var drags: [NSEvent] = []
    appKit.windowDragPerformer = { drags.append($0) }
    appKit.onInput = { event in
        if case .mouseDragged = event { _ = appKit.performWindowDrag() }
        return false
    }

    let first = try event(.leftMouseDown, in: nsWindow)
    let second = try event(.leftMouseDown, in: nsWindow)
    appKit.hostView.mouseDown(with: first)
    appKit.hostView.mouseDown(with: second)
    appKit.hostView.mouseDragged(with: try event(.leftMouseDragged, in: nsWindow))
    #expect(drags.count == 1 && drags.first === second, "the second down replaced the first")

    appKit.hostView.rightMouseDown(with: try event(.rightMouseDown, in: nsWindow))
    appKit.hostView.mouseDragged(with: try event(.leftMouseDragged, in: nsWindow))
    #expect(drags.count == 1, "the secondary down stored nothing, and the acted press stays forgotten")

    let third = try event(.leftMouseDown, in: nsWindow)
    appKit.hostView.mouseDown(with: third)
    appKit.hostView.rightMouseDown(with: try event(.rightMouseDown, in: nsWindow))
    appKit.hostView.mouseDragged(with: try event(.leftMouseDragged, in: nsWindow))
    #expect(drags.count == 2 && drags.last === third, "a secondary down does not replace the held primary")
}
