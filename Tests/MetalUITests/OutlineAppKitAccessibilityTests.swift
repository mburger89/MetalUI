import Testing
import AppKit
import MetalUICore
@testable import MetalUIPlatform
@testable import MetalUIAppKit
@testable import MetalUI

// Lane 5 of the hierarchical lists, the AppKit half of the outline's accessibility (ruling `OG-F`; probe
// `docs/probes/swiftui-outline.swift` arms `P-A1`/`P-A2`): an outline row is an `AXRow`/`AXOutlineRow` with
// `AXDisclosureLevel`, `AXDisclosing` (settable on a group), `AXDisclosedByRow` and `AXDisclosedRows`, and no
// `AXExpanded`; a group row's one child is an `AXCell` holding an `AXDisclosureTriangle` (value 1 or 0, `AXPress` toggles).
// Read through the bridge's elements, as `ListSelectionTests` reads a list's.

private typealias Request = MetalUIPlatform.AccessibilityRequest

@MainActor private final class Running: AccessibilityClientSignal {
    func observe(_ handler: @escaping @MainActor (Bool) -> Void) { handler(true) }
}

@MainActor private final class NoPoster: AccessibilityNotificationPosting {
    func post(_ notification: NSAccessibility.Notification, for element: Any) {}
}

private struct Entry: Identifiable {
    var id: String
    var kids: [Entry]?
}

private func entries() -> [Entry] {
    [Entry(id: "A", kids: [Entry(id: "A/B", kids: [Entry(id: "A/B/D"), Entry(id: "A/B/E")]), Entry(id: "A/C")]),
     Entry(id: "Z")]
}

@MainActor private final class Open {
    var set: Set<String> = []
    func binding(_ id: String) -> Binding<Bool> {
        Binding(get: { self.set.contains(id) }, set: { if $0 { self.set.insert(id) } else { self.set.remove(id) } })
    }
}

private struct Folder: Component {
    let entry: Entry
    let model: Open
    @ElementBuilder var content: some ElementGroup {
        if let kids = entry.kids {
            DisclosureGroup(isExpanded: model.binding(entry.id)) {
                ForEach(kids) { Folder(entry: $0, model: model) }
            } label: { ProposalText(entry.id) }
        } else {
            ProposalText(entry.id)
        }
    }
}

@MainActor private func outlineWindow(_ model: Open, enabled: Bool = true) throws -> (Window, FakePlatformWindow) {
    let nodes = entries()
    let (window, platform) = try controlWindow(size: 300) {
        ProposalScrollView {
            List(selection: .constant(Optional<String>.none)) { ForEach(nodes) { Folder(entry: $0, model: model) } }
                .disabled(!enabled)
        }
    }
    platform.simulateAccessibilityRequest(.activate)
    for _ in 0..<6 { controlRedraw(window) }
    return (window, platform)
}

@MainActor private struct Rig {
    let window: Window
    let platform: FakePlatformWindow
    let bridge: AppKitAccessibilityBridge
    let host: NSWindow

    init(_ model: Open, enabled: Bool = true) throws {
        (window, platform) = try outlineWindow(model, enabled: enabled)
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
        for _ in 0..<2 { controlRedraw(window) }
        if let tree = platform.publishedAccessibilityTrees.last { bridge.publish(tree) }
    }

    var tree: AccessibilityTree { bridge.tree }

    /// The element of the row whose content's text is `name`.
    func row(_ name: String) throws -> AppKitAccessibilityElement {
        func holds(_ id: AccessibilityNodeID) -> Bool {
            guard let node = tree.nodes[id] else { return false }
            if node.role == .staticText, node.value == name { return true }
            return node.children.contains(where: holds)
        }
        let id = try #require(tree.nodes.first { $0.value.role == .row && holds($0.key) }?.key, "row \(name)")
        return bridge.element(for: id)
    }

    func name(of element: Any?) -> String? {
        guard let element = element as? AppKitAccessibilityElement else { return nil }
        func text(_ id: AccessibilityNodeID) -> String? {
            guard let node = tree.nodes[id] else { return nil }
            if node.role == .staticText { return node.value }
            return node.children.lazy.compactMap(text).first
        }
        return text(element.id)
    }
}

/// **P-A1/P-A2.** A row reads `AXRow`/`AXOutlineRow`; its `AXDisclosureLevel` is the depth; `AXDisclosing` is 1 open and 0
/// closed (0 and not settable on a leaf); `AXDisclosedByRow` is the parent row (none for a root); `AXDisclosedRows` the
/// realised children in order (none for a leaf); and `AXExpanded` is not an attribute. Mutations: the level not the depth;
/// the disclosed rows taken as every later row; `isAccessibilityExpanded` overridden.
@Test @MainActor func anOutlineRowReadsItsLevelStateParentAndChildren() throws {
    let model = Open()
    model.set = ["A", "A/B"]
    let rig = try Rig(model)
    let a = try rig.row("A"), b = try rig.row("A/B"), d = try rig.row("A/B/D"), c = try rig.row("A/C"), z = try rig.row("Z")
    #expect(a.accessibilityRole() == .row && a.accessibilitySubrole() == .outlineRow, "AXRow, AXOutlineRow")
    #expect([a, b, d, c, z].map { $0.accessibilityDisclosureLevel() } == [0, 1, 2, 1, 0])
    #expect([a, b, d, z].map { $0.isAccessibilityDisclosed() } == [true, true, false, false], "AXDisclosing 1 or 0")
    #expect(rig.name(of: a.accessibilityDisclosedByRow()) == nil, "a root has no AXDisclosedByRow")
    #expect(rig.name(of: b.accessibilityDisclosedByRow()) == "A" && rig.name(of: d.accessibilityDisclosedByRow()) == "A/B")
    let aRows = try #require(a.accessibilityDisclosedRows() as? [Any])
    #expect(aRows.compactMap(rig.name(of:)) == ["A/B", "A/C"], "A discloses its direct children in order")
    let bRows = try #require(b.accessibilityDisclosedRows() as? [Any])
    #expect(bRows.compactMap(rig.name(of:)) == ["A/B/D", "A/B/E"])
    #expect((try #require(d.accessibilityDisclosedRows() as? [Any])).isEmpty, "a leaf discloses none")
    // Settable on a group, not on a leaf.
    let setter = #selector(NSAccessibilityElement.setAccessibilityDisclosed(_:))
    #expect(a.isAccessibilitySelectorAllowed(setter) && b.isAccessibilitySelectorAllowed(setter), "AXDisclosing is settable on a group")
    #expect(!d.isAccessibilitySelectorAllowed(setter) && !z.isAccessibilitySelectorAllowed(setter), "and not on a leaf")
    // `AXExpanded` is not an attribute of an outline row (P-A1): the element does not override `isAccessibilityExpanded`
    // (and does override `isAccessibilityDisclosed`, the control).
    func overrides(_ selector: Selector) -> Bool {
        AppKitAccessibilityElement.instanceMethod(for: selector) != NSAccessibilityElement.instanceMethod(for: selector)
    }
    #expect(overrides(#selector(NSAccessibilityElement.isAccessibilityDisclosed)), "control: AXDisclosing is answered")
    #expect(!overrides(#selector(NSAccessibilityElement.isAccessibilityExpanded)), "AXExpanded is not")
}

/// **P-A1.** Setting `AXDisclosing` expands a collapsed group (the binding is written) and collapses an open one, through the
/// window's disclosure handler. A leaf, and a row already in the state, send nothing. Mutations: the setter ignored; the
/// request sent for a leaf.
@Test @MainActor func settingAXDisclosingExpandsAndCollapsesAGroup() throws {
    let model = Open()
    let rig = try Rig(model)
    var requests: [Request] = []
    let forwarding = rig.bridge.onRequest
    rig.bridge.onRequest = { requests.append($0); return forwarding?($0) ?? false }
    let a = try rig.row("A")
    a.setAccessibilityDisclosed(true)
    rig.republish()
    #expect(model.set == ["A"], "AXDisclosing = true expanded A and wrote the binding: \(model.set)")
    #expect(requests.count == 1)
    let opened = try rig.row("A")
    opened.setAccessibilityDisclosed(true)
    #expect(requests.count == 1, "already open: nothing sent")
    try rig.row("Z").setAccessibilityDisclosed(true)
    #expect(requests.count == 1 && model.set == ["A"], "a leaf: nothing sent")
    opened.setAccessibilityDisclosed(false)
    rig.republish()
    #expect(model.set.isEmpty, "AXDisclosing = false collapsed it: \(model.set)")
}

/// **P-A2.** A group row's one child is an `AXCell` whose first child is an `AXDisclosureTriangle`, `AXValue` 1 open or 0
/// closed, and `AXPress` toggles the group. Mutations: the triangle's press not wired; the value inverted.
@Test @MainActor func aGroupRowsTriangleLivesInACellAndAXPressTogglesIt() throws {
    let model = Open()
    model.set = ["A"]
    let rig = try Rig(model)
    let a = try rig.row("A")
    let cells = try #require(a.accessibilityChildren() as? [AppKitAccessibilityElement])
    #expect(cells.count == 1 && cells[0].accessibilityRole() == .cell, "the row's one child is an AXCell")
    let inside = try #require(cells[0].accessibilityChildren() as? [AppKitAccessibilityElement])
    let triangle = try #require(inside.first)
    #expect(triangle.accessibilityRole() == .disclosureTriangle, "its first child is the disclosure triangle")
    #expect(triangle.accessibilityValue() as? String == "1", "open reads 1: \(String(describing: triangle.accessibilityValue()))")
    #expect(triangle.isAccessibilitySelectorAllowed(#selector(NSAccessibilityElement.accessibilityPerformPress)), "AXPress")
    #expect(triangle.accessibilityPerformPress())
    rig.republish()
    #expect(model.set.isEmpty, "AXPress collapsed A: \(model.set)")
    let closed = try rig.row("A")
    let closedCells = try #require(closed.accessibilityChildren() as? [AppKitAccessibilityElement])
    let closedTriangle = try #require((closedCells[0].accessibilityChildren() as? [AppKitAccessibilityElement])?.first)
    #expect(closedTriangle.accessibilityValue() as? String == "0", "closed reads 0")
    #expect(closedTriangle.accessibilityPerformPress())
    rig.republish()
    #expect(model.set == ["A"], "and a second press expanded it again")
    let z = try rig.row("Z")
    let zKids = try #require(z.accessibilityChildren() as? [AppKitAccessibilityElement])
    #expect(zKids.map { $0.accessibilityRole() } == [.staticText], "a leaf row's child is its text, no cell")
}

/// **OG-F, the disabled gate.** A disabled outline's rows offer no `AXDisclosing` setter and no triangle press, and a set
/// changes nothing. Mutation: the handler registered past the disabled gate.
@Test @MainActor func aDisabledOutlineRefusesAXDisclosingAndTheTrianglePress() throws {
    let model = Open()
    let rig = try Rig(model, enabled: false)
    let a = try rig.row("A")
    let setter = #selector(NSAccessibilityElement.setAccessibilityDisclosed(_:))
    #expect(!a.isAccessibilitySelectorAllowed(setter), "AXDisclosing is not settable")
    a.setAccessibilityDisclosed(true)
    rig.republish()
    #expect(model.set.isEmpty, "and a set changed nothing")
    let cells = try #require(a.accessibilityChildren() as? [AppKitAccessibilityElement])
    let triangle = try #require((cells[0].accessibilityChildren() as? [AppKitAccessibilityElement])?.first)
    #expect(!triangle.accessibilityPerformPress() && model.set.isEmpty, "the triangle's press is refused")
}
