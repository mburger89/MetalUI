import Testing
import Foundation
import Metal
import AppKit
import ObjectiveC
import MetalUICore
@testable import MetalUIPlatform
@testable import MetalUIAppKit
import MetalUIRender

// MT-D: an AppKit window's Reduce Transparency is a live read of
// `NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency`, re-read on
// `NSWorkspace.accessibilityDisplayOptionsDidChangeNotification` (the one observer
// that serves Reduce Motion serves it too) -- the source SwiftUI reads. The system
// setting is a protected user preference and is NOT written: the getter is swizzled
// in-process for the test's duration and restored in a `defer`, as
// `AppKitReduceMotionTests` does.

@MainActor private var swizzledReduceTransparency = false

private final class ReduceTransparencySwizzle: NSObject {
    @objc dynamic var fakeReduceTransparency: Bool {
        MainActor.assumeIsolated { swizzledReduceTransparency }
    }
}

@MainActor
private func swizzleReduceTransparency() throws -> () -> Void {
    let getter = #selector(getter: NSWorkspace.accessibilityDisplayShouldReduceTransparency)
    let original = try #require(class_getInstanceMethod(NSWorkspace.self, getter))
    let replacement = try #require(class_getInstanceMethod(
        ReduceTransparencySwizzle.self, #selector(getter: ReduceTransparencySwizzle.fakeReduceTransparency)))
    let originalIMP = method_getImplementation(original)
    method_setImplementation(original, method_getImplementation(replacement))
    return { method_setImplementation(original, originalIMP) }
}

@MainActor
private func openAppKitWindow(_ label: String) throws -> (AppKitWindow, NSWindow) {
    let device = try #require(MTLCreateSystemDefaultDevice(), "no Metal device; run on macOS hardware")
    let signal = ScriptedAccessibilitySignal(false)
    let platform = AppKitPlatform(device: device, accessibilitySignal: { signal })
    let window = try platform.openWindow(title: "\(label) \(UUID().uuidString)",
                                         size: Size(width: Pixels(160), height: Pixels(120)))
    let appKit = try #require(window as? AppKitWindow)
    let nsWindow = try #require(appKit.hostView.window)
    return (appKit, nsWindow)
}

/// **13.** The getter reads NSWorkspace (the swizzled answer, both values); the
/// workspace's display-options notification fires the callback once per change and
/// never for an unchanged value; and a window on the default center hears the
/// workspace's own post. Mutation: the observer's handler stops refreshing
/// Reduce Transparency.
@MainActor
@Test func theAppKitWindowReadsReduceTransparencyFromNSWorkspace() throws {
    let restore = try swizzleReduceTransparency()
    defer { restore(); swizzledReduceTransparency = false }

    swizzledReduceTransparency = false
    let (window, nsWindow) = try openAppKitWindow("Reduce transparency")
    defer { nsWindow.close() }
    #expect(window.accessibilityReduceTransparency == false)
    swizzledReduceTransparency = true
    #expect(window.accessibilityReduceTransparency == true, "a live read of the workspace's getter")

    let center = NotificationCenter()
    window.workspaceNotificationCenter = center
    swizzledReduceTransparency = false
    window.refreshAccessibilityReduceTransparency()
    var fired: [Bool] = []
    window.onAccessibilityReduceTransparencyChange = { fired.append($0) }

    swizzledReduceTransparency = true
    center.post(name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: NSWorkspace.shared)
    #expect(fired == [true], "the display-options notification re-reads and reports the change")
    center.post(name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: NSWorkspace.shared)
    #expect(fired == [true], "an unchanged value calls nothing")
    swizzledReduceTransparency = false
    center.post(name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: NSWorkspace.shared)
    #expect(fired == [true, false])

    let (wired, wiredNSWindow) = try openAppKitWindow("Reduce transparency wiring")
    defer { wiredNSWindow.close() }
    var wiredFired: [Bool] = []
    wired.onAccessibilityReduceTransparencyChange = { wiredFired.append($0) }
    swizzledReduceTransparency = true
    NSWorkspace.shared.notificationCenter.post(
        name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: NSWorkspace.shared)
    #expect(wiredFired == [true], "production observes NSWorkspace.shared.notificationCenter")
}
