import Testing
import MetalUICore
import MetalUIPlatform
@testable import MetalUISDL
import SDLBridge
#if canImport(AppKit)
import AppKit
#endif

// AX-A…AX-C: accessibility off Apple through AccessKit. The translation is
// pure and pinned field by field; the adapter's callbacks are driven the way
// AccessKit drives them; on macOS a real NSAccessibility client reads the tree
// back through AccessKit's subclassing adapter.

private func bounds(_ x: Float, _ y: Float, _ w: Float, _ h: Float) -> AccessibilityGeometry {
    let frame = Bounds(origin: Point(x: Pixels(x), y: Pixels(y)),
                       size: Size(width: Pixels(w), height: Pixels(h)))
    return AccessibilityGeometry(frame: frame, visibleFrame: frame)
}

/// A group holding a focusable button, a disabled image and a table with one
/// selected row, the row focused.
private func sampleTree() -> AccessibilityTree {
    AccessibilityTree(
        roots: [AccessibilityNodeID("group")],
        nodes: [
            AccessibilityNodeID("group"): AccessibilityNode(
                role: .group, children: [AccessibilityNodeID("button"), AccessibilityNodeID("image"),
                                         AccessibilityNodeID("table")]),
            AccessibilityNodeID("button"): AccessibilityNode(
                role: .button, label: "OK", isFocusable: true, actions: [.press]),
            AccessibilityNodeID("image"): AccessibilityNode(role: .image, label: "Logo", isEnabled: false),
            AccessibilityNodeID("table"): AccessibilityNode(
                role: .table, children: [AccessibilityNodeID("row")], rowCount: 1),
            AccessibilityNodeID("row"): AccessibilityNode(
                role: .row, label: "First", value: "3", isSelected: true, isFocusable: true,
                actions: [.increment, .decrement], rowIndex: 0),
        ],
        geometry: [
            AccessibilityNodeID("group"): bounds(0, 0, 100, 50),
            AccessibilityNodeID("button"): bounds(10, 5, 30, 20),
        ],
        focused: AccessibilityNodeID("row"))
}

/// Every field of every node, in AccessKit's vocabulary, parents first (AX-B).
@Test func aMetalUITreeTranslatesToAccessKitsVocabulary() throws {
    let ids = AccessKitIDs()
    let snapshot = AccessKitSnapshot.translate(sampleTree(), title: "Win", scale: 2, ids: ids)
    typealias Node = AccessKitSnapshot.Node
    let expected: [Node] = [
        Node(id: 0, role: .window, label: "Win", value: nil, bounds: nil, children: [1],
             actions: [], isDisabled: false, isSelected: false),
        Node(id: 1, role: .genericContainer, label: nil, value: nil, bounds: (0, 0, 200, 100),
             children: [2, 3, 4], actions: [], isDisabled: false, isSelected: false),
        Node(id: 2, role: .button, label: "OK", value: nil, bounds: (20, 10, 80, 50), children: [],
             actions: [.click, .focus], isDisabled: false, isSelected: false),
        Node(id: 3, role: .image, label: "Logo", value: nil, bounds: nil, children: [],
             actions: [], isDisabled: true, isSelected: false),
        Node(id: 4, role: .table, label: nil, value: nil, bounds: nil, children: [5],
             actions: [], isDisabled: false, isSelected: false),
        Node(id: 5, role: .row, label: "First", value: "3", bounds: nil, children: [],
             actions: [.increment, .decrement, .focus], isDisabled: false, isSelected: true),
    ]
    try #require(snapshot.nodes.count == expected.count)
    for (got, want) in zip(snapshot.nodes, expected) { #expect(got == want, "node \(want.id)") }
    #expect(snapshot.focus == 5)
    // Every role MetalUI has maps somewhere.
    #expect(AccessKitSnapshot.role(.staticText) == .label)
    #expect(AccessKitSnapshot.role(.textField) == .textInput)
    #expect(AccessKitSnapshot.role(.textArea) == .multilineTextInput)
}

/// A node keeps its number while it lives; a vanished one is forgotten and
/// its number is never handed out again (AX-B).
@Test func accessKitIDsAreStableAndNeverReused() {
    let ids = AccessKitIDs()
    let first = AccessKitSnapshot.translate(sampleTree(), title: "", scale: 1, ids: ids)
    var smaller = sampleTree()
    smaller.nodes[AccessibilityNodeID("image")] = nil
    smaller.nodes[AccessibilityNodeID("group")]!.children.removeAll { $0 == AccessibilityNodeID("image") }
    let second = AccessKitSnapshot.translate(smaller, title: "", scale: 1, ids: ids)
    #expect(first.nodes.map(\.id) == [0, 1, 2, 3, 4, 5])
    #expect(second.nodes.map(\.id) == [0, 1, 2, 4, 5])
    #expect(ids.node(for: 3) == nil)
    let third = AccessKitSnapshot.translate(sampleTree(), title: "", scale: 1, ids: ids)
    #expect(third.nodes.map(\.id) == [0, 1, 2, 6, 4, 5])
}

/// Every AccessKit action maps back to the MetalUI request it means, and an
/// unknown node means none (AX-C).
@Test func anAccessKitActionMeansAMetalUIRequest() {
    let ids = AccessKitIDs()
    _ = AccessKitSnapshot.translate(sampleTree(), title: "", scale: 1, ids: ids)
    let button = AccessibilityNodeID("button")
    #expect(AccessKitSnapshot.request(.click, number: 2, ids: ids) == .press(button))
    #expect(AccessKitSnapshot.request(.focus, number: 2, ids: ids) == .focus(button))
    #expect(AccessKitSnapshot.request(.increment, number: 5, ids: ids) == .increment(AccessibilityNodeID("row")))
    #expect(AccessKitSnapshot.request(.decrement, number: 5, ids: ids) == .decrement(AccessibilityNodeID("row")))
    #expect(AccessKitSnapshot.request(.click, number: 99, ids: ids) == nil)
    for action in [AccessKitSnapshot.Action.click, .focus, .increment, .decrement] {
        #expect(AccessKitSnapshot.action(AccessKitAdapter.code(action)) == action)
    }
}

@MainActor
private func hiddenWindow() throws -> (SDLPlatform, SDLWindow) {
    let platform = try SDLPlatform(hiddenWindows: true)
    let window = try platform.openSDLWindow(title: "MetalUI AccessKit test",
                                            size: Size(width: Pixels(320), height: Pixels(200)))
    return (platform, window)
}

/// What AccessKit's callbacks queue wakes the event loop and reaches
/// `onAccessibilityRequest` in order on the main thread; requests before the
/// handler exists are parked, as the AppKit bridge parks `.activate` (AX-C).
@MainActor
@Test func accessKitRequestsReachTheWindowInOrder() throws {
    let (platform, window) = try hiddenWindow()
    // Every platform has an adapter: AT-SPI needs no handle, and SDL gives
    // the NSWindow and the HWND the subclassing adapters take.
    #expect(window.isAccessibilityConnected)
    window.publishAccessibilityTree(sampleTree())
    window.simulateAccessKitRequest(.activate)
    // The wake arrives through SDL's queue, addressed to this window.
    var event = MUIEvent()
    var woke = false
    while mui_poll_event(&event) {
        if Int(event.kind) == Int(MUI_EVENT_ACCESSIBILITY) && event.window_id == window.id { woke = true }
    }
    #expect(woke)
    window.simulateAccessKitRequest(.action(.click, 2))
    window.simulateAccessKitRequest(.action(.increment, 99))  // unknown node: dropped
    platform.pumpEvents()
    var received: [MetalUIPlatform.AccessibilityRequest] = []
    window.onAccessibilityRequest = { received.append($0); return true }
    #expect(received == [.activate, .press(AccessibilityNodeID("button"))])
    window.simulateAccessKitRequest(.action(.focus, 5))
    platform.pumpEvents()
    #expect(received.last == .focus(AccessibilityNodeID("row")))
    #expect(received.count == 3)
}

#if canImport(AppKit)
/// On macOS the SDL window's NSWindow answers NSAccessibility with the
/// published tree: asking activates AccessKit (which MetalUI hears as
/// `.activate`) and AccessKit's elements carry MetalUI's labels (AX-C).
@MainActor
@Test func anNSAccessibilityClientReadsThePublishedTree() throws {
    let (platform, window) = try hiddenWindow()
    var received: [MetalUIPlatform.AccessibilityRequest] = []
    window.onAccessibilityRequest = { received.append($0); return true }
    window.publishAccessibilityTree(sampleTree())
    let pointer = try #require(mui_window_native_handle(window.rawHandle))
    let host = Unmanaged<NSWindow>.fromOpaque(pointer).takeUnretainedValue()
    let view = try #require(host.contentView)
    // AccessKit's elements answer the informal NSAccessibility methods;
    // reach them by dynamic lookup, as a client's selector would. The window
    // node is the view itself; MetalUI's label is AppKit's title.
    var seen: [String] = []
    func walk(_ element: AnyObject, depth: Int) {
        guard depth < 16 else { return }
        let role = element.accessibilityRole?()?.rawValue ?? "-"
        let title = element.accessibilityTitle?() ?? "-"
        let value = ((element as? NSAccessibilityProtocol)?.accessibilityValue() as? String) ?? (element.value(forKey: "accessibilityValue") as? String) ?? "-"
        seen.append("\(depth) \(role) \(title) \(value)")
        for child in element.accessibilityChildren?() ?? [] { walk(child as AnyObject, depth: depth + 1) }
    }
    for child in view.accessibilityChildren() ?? [] { walk(child as AnyObject, depth: 0) }
    platform.pumpEvents()
    #expect(received.first == .activate)
    #expect(seen == ["0 AXGroup - -", "1 AXButton OK -", "1 AXImage Logo -", "1 AXTable - -",
                     "2 AXRow First 3"])
}
#endif
