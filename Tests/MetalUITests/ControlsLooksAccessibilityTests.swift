import Testing
import AppKit
import MetalUICore
@testable import MetalUIPlatform
@testable import MetalUIAppKit
@testable import MetalUI

// C10 lane 1: the three roles this branch adds (ruling `LK-G`) on the AppKit
// bridge — `.progressIndicator` (`AXProgressIndicator`, its value the
// fraction as an `NSNumber`, probe `V7`/`V8`), `.busyIndicator`
// (`AXBusyIndicator`, no value, `V8`) and `.colorWell` (`AXColorWell`, its
// `rgb R G B A` string, `C1`). The AccessKit half is
// `Backends/SDL/Tests/MetalUISDLTests/AccessKitControlsLooksTests.swift`.

@MainActor private final class NoPoster: AccessibilityNotificationPosting {
    func post(_ notification: NSAccessibility.Notification, for element: Any) {}
}

@MainActor private final class Running: AccessibilityClientSignal {
    func observe(_ handler: @escaping @MainActor (Bool) -> Void) { handler(true) }
}

/// **1.38** (`LK-G`). The three roles reach AppKit one to one, the progress
/// indicator's value an `NSNumber` (0.5), the busy indicator's none, the well's
/// its string. Mutation: map `.colorWell` to `.group`.
@Test @MainActor func theThreeNewRolesHaveRowsOnTheAppKitBridge() throws {
    let cases: [(String, AccessibilityRole, String?, NSAccessibility.Role)] = [
        ("progress", .progressIndicator, "0.5", .progressIndicator),
        ("busy", .busyIndicator, nil, NSAccessibility.Role(rawValue: "AXBusyIndicator")),
        ("well", .colorWell, "rgb 1 0 0 1", .colorWell),
    ]
    let frame = Bounds(origin: Point(x: controlPx(0), y: controlPx(0)),
                       size: Size(width: controlPx(10), height: controlPx(10)))
    var nodes: [AccessibilityNodeID: AccessibilityNode] = [:]
    var geometry: [AccessibilityNodeID: AccessibilityGeometry] = [:]
    for (name, role, value, _) in cases {
        nodes[AccessibilityNodeID(name)] = AccessibilityNode(role: role, label: name, value: value)
        geometry[AccessibilityNodeID(name)] = AccessibilityGeometry(frame: frame, visibleFrame: frame)
    }
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 200),
                          styleMask: [.titled], backing: .buffered, defer: true)
    window.isReleasedWhenClosed = false
    let view = NSView(frame: NSRect(x: 0, y: 0, width: 200, height: 200))
    window.contentView = view
    let bridge = AppKitAccessibilityBridge(signal: Running(), poster: NoPoster())
    bridge.hostView = view
    bridge.publish(AccessibilityTree(roots: cases.map { AccessibilityNodeID($0.0) }, nodes: nodes,
                                     geometry: geometry, focused: nil))
    let progress = bridge.element(for: AccessibilityNodeID("progress"))
    #expect(progress.accessibilityRole() == .progressIndicator, "\(String(describing: progress.accessibilityRole()))")
    let fraction = try #require(progress.accessibilityValue() as? NSNumber,
                                "the fraction is an NSNumber: \(String(describing: progress.accessibilityValue()))")
    #expect(fraction.doubleValue == 0.5)
    let busy = bridge.element(for: AccessibilityNodeID("busy"))
    #expect(busy.accessibilityRole()?.rawValue == "AXBusyIndicator", "\(String(describing: busy.accessibilityRole()))")
    #expect(busy.accessibilityValue() == nil, "a busy indicator has no value")
    let well = bridge.element(for: AccessibilityNodeID("well"))
    #expect(well.accessibilityRole() == .colorWell, "\(String(describing: well.accessibilityRole()))")
    #expect(well.accessibilityValue() as? String == "rgb 1 0 0 1")
}
