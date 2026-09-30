import Testing
import Foundation
import Metal
import AppKit
import ObjectiveC
import MetalUICore
@testable import MetalUIPlatform
@testable import MetalUIAppKit
import MetalUIRender

// AN-AD: an AppKit window's Reduce Motion is a live read of
// `NSWorkspace.shared.accessibilityDisplayShouldReduceMotion`, re-read on
// `NSWorkspace.accessibilityDisplayOptionsDidChangeNotification` from
// `NSWorkspace.shared.notificationCenter` — the source and the refresh SwiftUI
// uses (probe `swiftui-transactions-animation.swift`, R1 and R2). The system
// setting is a protected user preference and is NOT written: the getter is
// swizzled in-process for the test's duration and restored in a `defer`, as
// the probe did.

/// The swizzle's answer while installed.
@MainActor private var swizzledReduceMotion = false

private final class ReduceMotionSwizzle: NSObject {
    @objc dynamic var fakeReduceMotion: Bool {
        MainActor.assumeIsolated { swizzledReduceMotion }
    }
}

/// Replaces NSWorkspace's getter with one answering `swizzledReduceMotion`,
/// returning a closure that puts the original implementation back.
@MainActor
private func swizzleReduceMotion() throws -> () -> Void {
    let getter = #selector(getter: NSWorkspace.accessibilityDisplayShouldReduceMotion)
    let original = try #require(class_getInstanceMethod(NSWorkspace.self, getter))
    let replacement = try #require(class_getInstanceMethod(
        ReduceMotionSwizzle.self, #selector(getter: ReduceMotionSwizzle.fakeReduceMotion)))
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

/// **1.17.** The getter reads NSWorkspace (the swizzled answer, both values);
/// the workspace's display-options notification fires the callback once per
/// change and never for an unchanged value; and a window left on its default
/// center — `NSWorkspace.shared.notificationCenter` — hears the post there, so
/// that center is what production observes. Mutation **M1.17**: observe a
/// different notification.
@MainActor
@Test func theAppKitWindowReadsReduceMotionFromNSWorkspace() throws {
    let restore = try swizzleReduceMotion()
    defer { restore(); swizzledReduceMotion = false }

    swizzledReduceMotion = false
    let (window, nsWindow) = try openAppKitWindow("Reduce motion")
    defer { nsWindow.close() }
    #expect(window.accessibilityReduceMotion == false)
    swizzledReduceMotion = true
    #expect(window.accessibilityReduceMotion == true, "a live read of the workspace's getter")

    let center = NotificationCenter()
    window.workspaceNotificationCenter = center
    // Settle the last-reported value before anyone listens.
    swizzledReduceMotion = false
    window.refreshAccessibilityReduceMotion()
    var fired: [Bool] = []
    window.onAccessibilityReduceMotionChange = { fired.append($0) }

    swizzledReduceMotion = true
    center.post(name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: NSWorkspace.shared)
    #expect(fired == [true], "the display-options notification re-reads and reports the change")
    center.post(name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: NSWorkspace.shared)
    #expect(fired == [true], "an unchanged value calls nothing")
    swizzledReduceMotion = false
    center.post(name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: NSWorkspace.shared)
    #expect(fired == [true, false])

    // Production wiring: a window on its default center hears the workspace's.
    let (wired, wiredNSWindow) = try openAppKitWindow("Reduce motion wiring")
    defer { wiredNSWindow.close() }
    var wiredFired: [Bool] = []
    wired.onAccessibilityReduceMotionChange = { wiredFired.append($0) }
    swizzledReduceMotion = true
    NSWorkspace.shared.notificationCenter.post(
        name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: NSWorkspace.shared)
    #expect(wiredFired == [true], "production observes NSWorkspace.shared.notificationCenter")
    #expect(fired == [true, false], "the first window left that center: it heard nothing")
}
