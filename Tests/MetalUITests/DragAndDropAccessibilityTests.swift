import Testing
import Foundation
import Metal
import AppKit
import MetalUICore
@testable import MetalUIPlatform
@testable import MetalUIAppKit
@testable import MetalUI
import MetalUIDemoContent

// Drag and drop, lane 3, tests 3.8 and 3.11 (rulings `DN-N`, `DN-Q`; spec
// `docs/superpowers/specs/2026-10-01-drag-and-drop-design.md` §6.5).
//
// 3.8: SwiftUI publishes nothing for `.draggable` or `.dropDestination`
// (probe arms A0–A4: the same roles, values, perform selectors and attribute
// counts, no custom action, no drag or drop attribute), and neither does
// MetalUI — the neutral tree and every AppKit bridge attribute read here are
// equal with and without the modifiers. 3.11: the demo variant's own drop
// path, driven through a `FakePlatformWindow`, its geometry read from the
// published accessibility tree (so the test finds a chip or a well by what it
// says, not by a hand-copied rectangle).

private func px(_ v: Float) -> Pixels { Pixels(v) }

/// A real `AppKitAccessibilityBridge` over a plain `NSView` in an `NSWindow`,
/// a client already running.
@MainActor private final class DNDRunning: AccessibilityClientSignal {
    func observe(_ handler: @escaping @MainActor (Bool) -> Void) { handler(true) }
}

@MainActor private final class DNDPoster: AccessibilityNotificationPosting {
    func post(_ notification: NSAccessibility.Notification, for element: Any) {}
}

@MainActor
private func dndBridge(_ platform: FakePlatformWindow) -> (AppKitAccessibilityBridge, NSWindow) {
    let host = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 400),
                        styleMask: [.titled], backing: .buffered, defer: true)
    host.isReleasedWhenClosed = false
    let view = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 400))
    host.contentView = view
    let bridge = AppKitAccessibilityBridge(signal: DNDRunning(), poster: DNDPoster())
    bridge.onRequest = { platform.simulateAccessibilityRequest($0) }
    bridge.hostView = view
    return (bridge, host)
}

/// Everything the AppKit bridge answers for one element that a client could
/// read, as one comparable string.
@MainActor
private func appKitFingerprint(_ element: AppKitAccessibilityElement) -> String {
    let selectors: [Selector] = [#selector(NSAccessibilityElement.accessibilityPerformPress),
                                 #selector(NSAccessibilityElement.accessibilityPerformShowMenu),
                                 #selector(NSAccessibilityElement.accessibilityPerformIncrement),
                                 #selector(NSAccessibilityElement.accessibilityPerformDecrement),
                                 #selector(NSAccessibilityElement.accessibilityPerformPick),
                                 #selector(NSAccessibilityElement.accessibilityPerformConfirm),
                                 #selector(NSAccessibilityElement.accessibilityPerformCancel)]
    let allowed = selectors.map { element.isAccessibilitySelectorAllowed($0) ? "1" : "0" }.joined()
    let custom = (element.accessibilityCustomActions() ?? []).map(\.name)
    return [
        "role=\(element.accessibilityRole()?.rawValue ?? "nil")",
        "subrole=\(element.accessibilitySubrole()?.rawValue ?? "nil")",
        "label=\(element.accessibilityLabel() ?? "nil")",
        "value=\(element.accessibilityValue().map { "\($0)" } ?? "nil")",
        "help=\(element.accessibilityHelp() ?? "nil")",
        "identifier=\(element.accessibilityIdentifier())",
        "enabled=\(element.isAccessibilityEnabled())",
        "selected=\(element.isAccessibilitySelected())",
        "children=\((element.accessibilityChildren() ?? []).count)",
        "selectors=\(allowed)",
        "custom=\(custom)",
    ].joined(separator: " ")
}

/// The published tree and every node's AppKit fingerprint for `content`.
@MainActor
private func publishedReading<Root: Element>(_ content: @escaping @MainActor () -> Root) throws
    -> (AccessibilityTree, [AccessibilityNodeID: String]) {
    let (window, platform) = try controlWindow(size: 400, content)
    defer { withExtendedLifetime(window) {} }
    let tree = try controlTree(window, platform)
    let (bridge, host) = dndBridge(platform)
    defer { withExtendedLifetime(host) {} }
    bridge.publish(tree)
    var prints: [AccessibilityNodeID: String] = [:]
    for id in tree.nodes.keys { prints[id] = appKitFingerprint(bridge.element(for: id)) }
    return (tree, prints)
}

/// **3.8** (`DN-N`, probe A0–A4). A draggable `Text`, a draggable `Button`, a
/// labelled destination and a destination `Text` publish exactly what the same
/// tree without the modifiers publishes — the neutral tree (roots, nodes,
/// geometry, focus) and, element by element, every attribute the AppKit bridge
/// answers (role, subrole, label, value, help, identifier, enabled, selected,
/// children, the perform selectors it allows, its custom actions). Mutation
/// **M3h** (give a destination an `AXNode` custom action) must redden it.
/// (Green on arrival: lanes 1 and 2 added no accessibility path, `DN-N` — the
/// mutation is the instrument.)
@MainActor
@Test func aDraggableAndADropDestinationPublishNothingNew() throws {
    let (plain, plainPrints) = try publishedReading {
        Column(gap: px(8)) {
            Text("Chip")
            Button("Go") {}
            Box().frame(width: px(60), height: px(60)).accessibilityLabel("Well")
            Text("Drop here")
        }
    }
    let (dnd, dndPrints) = try publishedReading {
        Column(gap: px(8)) {
            Text("Chip").draggable("chip")
            Button("Go") {}.draggable("go")
            Box().frame(width: px(60), height: px(60)).accessibilityLabel("Well")
                .dropDestination(for: String.self, action: { _, _ in true })
            Text("Drop here").dropDestination(for: String.self, action: { _, _ in true })
        }
    }
    // The control publishes all four, so equality below is not two empty trees.
    try #require(plain.nodes.count == 4, "the control's nodes: \(plain.nodes.values.map { "\($0)" })")
    #expect(Set(plain.nodes.values.map(\.role)) == [.staticText, .button, .group],
            "\(plain.nodes.values.map(\.role))")
    #expect(dnd == plain, "the neutral tree moved:\nplain \(plain)\ndnd \(dnd)")
    #expect(dndPrints == plainPrints, "the AppKit bridge moved:\nplain \(plainPrints)\ndnd \(dndPrints)")
    #expect(dnd.nodes.values.allSatisfy { $0.customActions.isEmpty }, "no custom action (A1–A4)")
    // The four nodes as `Backends/SDL`'s 3.9 transcribes them (that target
    // cannot render a MetalUI tree): change one here, change it there.
    let readings = dnd.roots.compactMap { dnd.nodes[$0] }.map {
        "\($0.role) label=\($0.label ?? "nil") value=\($0.value ?? "nil") actions=\($0.actions.rawValue) "
            + "focusable=\($0.isFocusable) children=\($0.children.count)"
    }
    #expect(readings == ["staticText label=nil value=Chip actions=0 focusable=false children=0",
                         "button label=Go value=nil actions=1 focusable=true children=0",
                         "group label=Well value=nil actions=0 focusable=false children=0",
                         "staticText label=nil value=Drop here actions=0 focusable=false children=0"],
            "\(readings)")
}

// MARK: - 3.11 the demo variant

/// The demo window as `METALUI_DND_DEMO=1` opens it — 920 × 560 — with an
/// accessibility client active, settled.
@MainActor
private func dndDemoWindow() throws -> (Window, FakePlatformWindow) {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let (window, platform) = try makeFakeWindow(device: device, size: 920, startsDisplayLink: true,
                                                content: dragAndDropDemoContent)
    platform.simulateResize(to: Size(width: px(920), height: px(560)))
    platform.simulateAccessibilityRequest(.activate)
    settle(window)
    return (window, platform)
}

@MainActor
private func settle(_ window: Window) {
    window.setNeedsRedraw()
    var frames = 0
    while window.needsRedraw && frames < 8 { window.drawFrameIfNeeded(); frames += 1 }
}

/// Every static text in the last published tree: its string and frame.
@MainActor
private func texts(_ platform: FakePlatformWindow) -> [(value: String, frame: Bounds<Pixels>)] {
    guard let tree = platform.publishedAccessibilityTrees.last else { return [] }
    return tree.nodes.compactMap { id, node -> (String, Bounds<Pixels>)? in
        guard node.role == .staticText, let value = node.value, let frame = tree.geometry[id]?.frame else {
            return nil
        }
        return (value, frame)
    }
}

private func centre(_ b: Bounds<Pixels>) -> Point<Pixels> {
    Point(x: px(b.origin.x.value + b.size.width.value / 2), y: px(b.origin.y.value + b.size.height.value / 2))
}

/// The one static text reading `value`.
@MainActor
private func text(_ value: String, _ platform: FakePlatformWindow,
                  sourceLocation: SourceLocation = #_sourceLocation) throws -> Bounds<Pixels> {
    let matches = texts(platform).filter { $0.value == value }
    try #require(matches.count == 1, "one text reading \(value): \(texts(platform).map(\.value))",
                 sourceLocation: sourceLocation)
    return matches[0].frame
}

/// The texts whose centre lies within `well`'s title's row band below it —
/// what the well shows under its title.
@MainActor
private func shown(below title: Bounds<Pixels>, _ platform: FakePlatformWindow) -> [String] {
    texts(platform).filter { t in
        let c = centre(t.frame)
        return c.y.value > title.origin.y.value + title.size.height.value
            && c.y.value < title.origin.y.value + title.size.height.value + 40
            && abs(t.frame.origin.x.value - title.origin.x.value) < 1
    }.map(\.value)
}

@MainActor
private func dragAndDrop(_ platform: FakePlatformWindow, _ window: Window, from: Point<Pixels>, to: Point<Pixels>) {
    platform.simulateInput(.mouseDown(MouseEvent(position: from)))
    platform.simulateInput(.mouseDragged(MouseEvent(position: Point(x: px(from.x.value + 10), y: from.y))))
    platform.simulateInput(.mouseDragged(MouseEvent(position: to)))
    platform.simulateInput(.mouseUp(MouseEvent(position: to)))
    settle(window)
}

/// **3.11** (`DN-Q`, spec §7). The demo variant drops: the **Apple** chip
/// dragged onto the **Text** well shows "Apple" there; dragged onto the
/// **Disabled** well it changes nothing (divergence 100); the URL chip onto
/// **Links and files** shows its URL, and onto **Text** nothing (a URL is not
/// text, `T6c`). Mutation **M3j** (the demo's well ignores its items) must
/// redden it.
@MainActor
@Test func theDragAndDropDemoDropsAChipOnTheTextWell() throws {
    let (window, platform) = try dndDemoWindow()
    defer { withExtendedLifetime(window) {} }
    let apple = try text("Apple", platform)
    let textWell = try text("Text", platform)
    let disabledWell = try text("Disabled", platform)
    let linksWell = try text("Links and files", platform)
    let url = try text("example.com", platform)
    try #require(shown(below: textWell, platform) == ["—"], "the Text well starts empty: \(shown(below: textWell, platform))")
    try #require(shown(below: disabledWell, platform) == ["—"])
    try #require(shown(below: linksWell, platform) == ["—"])

    dragAndDrop(platform, window, from: centre(apple), to: centre(disabledWell))
    #expect(shown(below: disabledWell, platform) == ["—"], "the Disabled well refuses (divergence 100)")

    dragAndDrop(platform, window, from: centre(url), to: centre(textWell))
    #expect(shown(below: textWell, platform) == ["—"], "a URL is not text: the Text well refuses it")

    dragAndDrop(platform, window, from: centre(apple), to: centre(textWell))
    #expect(shown(below: textWell, platform) == ["Apple"], "the Text well shows the dropped string")

    dragAndDrop(platform, window, from: centre(url), to: centre(linksWell))
    #expect(shown(below: linksWell, platform) == ["https://example.com"], "the Links well shows the URL")
}
