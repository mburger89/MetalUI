import Testing
import AppKit
import MetalUICore
@testable import MetalUIPlatform
@testable import MetalUIAppKit
@testable import MetalUI

// The AppKit half of a split divider's accessibility (ruling `HS-K`; probe `docs/probes/swiftui-split-divider-ax.swift`): the
// element is an `AXSplitter` with `AXOrientation`, a numeric `AXValue` (the size of the pane before it, in points),
// `AXMinValue` 0 and `AXMaxValue` the pair's total, a settable value, and no increment or decrement.

@MainActor private final class Running: AccessibilityClientSignal {
    func observe(_ handler: @escaping @MainActor (Bool) -> Void) { handler(true) }
}

@MainActor private final class NoPoster: AccessibilityNotificationPosting {
    func post(_ notification: NSAccessibility.Notification, for element: Any) {}
}

@MainActor private struct Rig {
    let window: Window
    let platform: FakePlatformWindow
    let bridge: AppKitAccessibilityBridge
    let host: NSWindow

    init(fixed: Bool = false) throws {
        (window, platform) = try controlWindow(size: 400) {
            VStack(spacing: 0) {
            if fixed {
                HSplitView { Color.red.frame(width: 100); Color.green.frame(width: 100) }
            } else {
                HSplitView {
                    Color.red.frame(minWidth: 50, idealWidth: 100, maxWidth: 200)
                    Color.green
                    Color.blue.frame(minWidth: 60, idealWidth: 120, maxWidth: 240)
                }
            }
            }
        }
        platform.simulateAccessibilityRequest(.activate)
        host = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 100, height: 100), styleMask: [.titled],
                        backing: .buffered, defer: true)
        host.isReleasedWhenClosed = false
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 100, height: 100))
        host.contentView = view
        bridge = AppKitAccessibilityBridge(signal: Running(), poster: NoPoster())
        let platform = self.platform
        bridge.onRequest = { platform.simulateAccessibilityRequest($0) }
        bridge.hostView = view
        republish()
    }

    func republish() {
        for _ in 0..<3 { controlRedraw(window) }
        if let tree = platform.publishedAccessibilityTrees.last { bridge.publish(tree) }
    }

    /// The splitters' elements, in published order.
    func splitters() -> [AppKitAccessibilityElement] {
        bridge.tree.nodes.filter { $0.value.role == .splitter }
            .sorted { (bridge.tree.geometry[$0.key]?.frame.origin.x.value ?? 0) < (bridge.tree.geometry[$1.key]?.frame.origin.x.value ?? 0) }
            .map { bridge.element(for: $0.key) }
    }
}

private func number(_ value: Any?) -> Double? { (value as? NSNumber)?.doubleValue }

/// **The probe's attributes.** `AXSplitter`, `AXOrientation` vertical for an `HSplitView`'s line, `AXValue` a number, `AXMinValue`
/// 0, `AXMaxValue` the pair's total, enabled and settable. Mutations: the role is `.group`; the value stays a string; the max is
/// the window width.
@Test @MainActor func aDividerReadsAsAnAXSplitterWithValueRangeAndOrientation() throws {
    let rig = try Rig()
    let found = rig.splitters()
    #expect(found.count == 2)
    let first = try #require(found.first)
    #expect(first.accessibilityRole() == .splitter)
    #expect(first.accessibilityOrientation() == .vertical)
    #expect(number(first.accessibilityValue()) == 100 && number(found[1].accessibilityValue()) == 178,
            "\(String(describing: first.accessibilityValue())) \(String(describing: found[1].accessibilityValue()))")
    #expect(number(first.accessibilityMinValue()) == 0 && number(first.accessibilityMaxValue()) == 278)
    #expect(number(found[1].accessibilityMaxValue()) == 298)
    #expect(first.isAccessibilityEnabled())
    #expect(first.isAccessibilitySelectorAllowed(#selector(NSAccessibilityElement.setAccessibilityValue(_:))))
}

/// **Settable `AXValue`.** Writing a number sends `.setValue`, the divider moves, and the next publish reads the new value;
/// below the minimum clamps (probe: 0 became 50). Mutations: the setter ignored; the number sent as a fraction.
@Test @MainActor func writingAXValueMovesTheDivider() throws {
    let rig = try Rig()
    var requests: [MetalUIPlatform.AccessibilityRequest] = []
    let forwarding = rig.bridge.onRequest
    rig.bridge.onRequest = { requests.append($0); return forwarding?($0) ?? false }
    let first = try #require(rig.splitters().first)
    first.setAccessibilityValue(130 as NSNumber)
    #expect(requests == [.setValue(first.id, 130)], "\(requests)")
    rig.republish()
    let moved = try #require(rig.splitters().first)
    #expect(number(moved.accessibilityValue()) == 130 && number(rig.splitters()[1].accessibilityValue()) == 148)
    moved.setAccessibilityValue(0 as NSNumber)
    rig.republish()
    #expect(number(try #require(rig.splitters().first).accessibilityValue()) == 50, "clamped to the pane's minimum")
}

/// **No increment or decrement** (the probe: the splitter implements none); a non-number write is ignored. Mutation: the
/// increment selector allowed for a splitter.
@Test @MainActor func aDividerOffersNoIncrementAndIgnoresANonNumber() throws {
    let rig = try Rig()
    var requests: [MetalUIPlatform.AccessibilityRequest] = []
    let forwarding = rig.bridge.onRequest
    rig.bridge.onRequest = { requests.append($0); return forwarding?($0) ?? false }
    let first = try #require(rig.splitters().first)
    #expect(!first.isAccessibilitySelectorAllowed(#selector(NSAccessibilityElement.accessibilityPerformIncrement)))
    #expect(!first.isAccessibilitySelectorAllowed(#selector(NSAccessibilityElement.accessibilityPerformDecrement)))
    #expect(!first.accessibilityPerformIncrement())
    first.setAccessibilityValue("wide" as NSString)
    #expect(requests.isEmpty, "\(requests)")
}

/// **Disabled when the panes cannot move.** Two fixed panes: the element is not enabled, its value is not settable, and a
/// write sends nothing. Mutation: the node stays enabled.
@Test @MainActor func aDividerWhosePanesCannotMoveIsDisabledAndNotSettable() throws {
    let rig = try Rig(fixed: true)
    var requests: [MetalUIPlatform.AccessibilityRequest] = []
    rig.bridge.onRequest = { requests.append($0); return false }
    let only = try #require(rig.splitters().first)
    #expect(!only.isAccessibilityEnabled())
    #expect(!only.isAccessibilitySelectorAllowed(#selector(NSAccessibilityElement.setAccessibilityValue(_:))))
    only.setAccessibilityValue(150 as NSNumber)
    #expect(requests.isEmpty)
}
