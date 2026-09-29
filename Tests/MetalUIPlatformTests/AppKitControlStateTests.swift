import Testing
import Foundation
import Metal
import AppKit
import MetalUICore
@testable import MetalUIPlatform
@testable import MetalUIAppKit
import MetalUIRender

// EV-AB (amended by EV-AF): an AppKit window's control active state is a live
// read of `isKeyWindow`, then `NSApp.isActive`, re-read on the window's key
// notifications and the application's activation notifications, observed
// explicitly on an injectable `NotificationCenter`. A locked or headless
// session cannot make a window key or the app active, so `keyStatus` is
// scripted; the observer path is the production one. The application
// notifications are posted only on a private center — posting
// `didResignActive` on the default center would reach AppKit's own observers
// in the shared test process.

@MainActor
private func openAppKitWindow(_ label: String) throws -> (AppKitWindow, NSWindow) {
    let device = try #require(MTLCreateSystemDefaultDevice(), "no Metal device; run on macOS hardware")
    let signal = ScriptedAccessibilitySignal(false)
    let platform = AppKitPlatform(device: device, accessibilitySignal: { signal })
    let window = try platform.openWindow(title: "\(label) \(UUID().uuidString)",
                                         size: Size(width: Pixels(160), height: Pixels(120)))
    let appKit = try #require(window as? AppKitWindow)
    let nsWindow = try #require(appKit.hostView.window)
    #expect(nsWindow.isReleasedWhenClosed == false)
    return (appKit, nsWindow)
}

/// T2.4. The callback carries each change once, through the observers
/// production registers; a second window proves `.default` is what production
/// observes.
@MainActor
@Test func theAppKitWindowReportsKeyChangesThroughItsCallback() throws {
    let (window, nsWindow) = try openAppKitWindow("Control state")
    defer { nsWindow.close() }
    let center = NotificationCenter()
    window.notificationCenter = center
    var status: (isKeyWindow: Bool, isApplicationActive: Bool) = (false, false)
    window.keyStatus = { status }
    // Settle the last-reported value on the scripted starting point before
    // anyone listens (the live state at construction is the machine's).
    window.refreshControlActiveState()
    try #require(window.controlActiveState == .inactive)

    var fired: [ControlActiveState] = []
    window.onControlActiveStateChange = { fired.append($0) }

    status = (true, true)
    center.post(name: NSWindow.didBecomeKeyNotification, object: nsWindow)
    #expect(fired == [.key])
    #expect(window.controlActiveState == .key)

    status = (false, true)
    center.post(name: NSWindow.didResignKeyNotification, object: nsWindow)
    #expect(fired == [.key, .active])
    #expect(window.controlActiveState == .active)

    status = (false, false)
    center.post(name: NSApplication.didResignActiveNotification, object: NSApplication.shared)
    #expect(fired == [.key, .active, .inactive])
    #expect(window.controlActiveState == .inactive)

    // The same post again changes nothing and calls nothing.
    center.post(name: NSApplication.didResignActiveNotification, object: NSApplication.shared)
    #expect(fired == [.key, .active, .inactive])

    // Production wiring: a window left on its default center hears the
    // window-scoped key notification posted there.
    let (wired, wiredNSWindow) = try openAppKitWindow("Control state wiring")
    defer { wiredNSWindow.close() }
    var wiredStatus: (isKeyWindow: Bool, isApplicationActive: Bool) = (false, false)
    wired.keyStatus = { wiredStatus }
    wired.refreshControlActiveState()
    try #require(wired.controlActiveState == .inactive)
    var wiredFired: [ControlActiveState] = []
    wired.onControlActiveStateChange = { wiredFired.append($0) }
    wiredStatus = (true, true)
    NotificationCenter.default.post(name: NSWindow.didBecomeKeyNotification, object: wiredNSWindow)
    #expect(wiredFired == [.key])
    // The first window left the default center: it heard nothing.
    #expect(fired == [.key, .active, .inactive])
}

/// T2.5. Key before active before inactive. A key non-activating panel in an
/// inactive app reads key; `(false, false)` is the probe's measured row (C0).
@Test func theAppKitMappingPutsKeyBeforeActiveBeforeInactive() {
    #expect(AppKitWindow.controlActiveState(isKeyWindow: true, isApplicationActive: true) == .key)
    #expect(AppKitWindow.controlActiveState(isKeyWindow: true, isApplicationActive: false) == .key)
    #expect(AppKitWindow.controlActiveState(isKeyWindow: false, isApplicationActive: true) == .active)
    #expect(AppKitWindow.controlActiveState(isKeyWindow: false, isApplicationActive: false) == .inactive)
}

/// T2.6. A backing-properties change (a move between displays of different
/// scale) reaches `onResize` with the window's backing scale — the path
/// `displayScale` follows (EV-AA). Pins a path that predates EV-AA and that
/// nothing pinned.
@MainActor
@Test func aBackingPropertiesChangeReachesOnResize() throws {
    let (window, nsWindow) = try openAppKitWindow("Backing")
    defer { nsWindow.close() }
    var scales: [Float] = []
    window.onResize = { _, scale in scales.append(scale) }
    window.hostView.viewDidChangeBackingProperties()
    #expect(scales == [Float(nsWindow.backingScaleFactor)])
}
