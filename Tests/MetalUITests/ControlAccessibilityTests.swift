import Testing
import AppKit
import MetalUICore
@testable import MetalUIPlatform
@testable import MetalUIAppKit
@testable import MetalUI

// Plan task 10, part 2, lane 1: the accessibility half (ruling `DD-U`; spec
// tests 1.21–1.23) — the five control roles on the AppKit bridge, the partial
// fold, and the selection hint. Helpers are `ButtonTests.swift`'s `control…`.

/// `Accessibility.framework` (through `AppKit`) exports its own
/// `AccessibilityRequest` (AB-AF item 1); this file never names it, but the
/// alias keeps a later edit from tripping over it.
private typealias Request = MetalUIPlatform.AccessibilityRequest

@MainActor private final class NoPoster: AccessibilityNotificationPosting {
    func post(_ notification: NSAccessibility.Notification, for element: Any) {}
}

@MainActor private final class Running: AccessibilityClientSignal {
    func observe(_ handler: @escaping @MainActor (Bool) -> Void) { handler(true) }
}

/// A collecting frame's tree, built as `Window` builds it.
@MainActor
private func tree<E: Element>(_ root: E, stateTable: StateTable = StateTable()) throws
    -> (Frame, AccessibilityTree) {
    var root = root
    let frame = Frame(contentSize: Size(width: controlPx(400), height: controlPx(200)), scaleFactor: 1,
                      stateTable: stateTable, collectsAccessibility: true, reportsUnlowerableFields: true)
    frame.render(&root)
    try #require(frame.unlowerableFields.isEmpty)
    let tree = AccessibilityTreeBuilder.build(emissions: frame.axEmissions, focused: frame.focusedElement,
                                              hitboxes: frame.hitboxes, focusRegistry: frame.focusRegistry)
    return (frame, tree)
}

/// **1.21.** The five roles reach AppKit one to one — `AXCheckBox`,
/// `AXRadioButton`, `AXRadioGroup`, `AXSlider`, `AXIncrementor` — and the four
/// valued roles answer `accessibilityValue` with an `NSNumber` (TA0 0/1, SA0 5,
/// STA0 1). M1r (`.checkBox` mapped to `.button` in AppKit) must redden it.
@Test @MainActor func theFiveControlRolesReachTheAppKitBridge() throws {
    let cases: [(String, AccessibilityRole, String?, NSAccessibility.Role, Double?)] = [
        ("check", .checkBox, "1", .checkBox, 1),
        ("radio", .radioButton, "0", .radioButton, 0),
        ("group", .radioGroup, nil, .radioGroup, nil),
        ("slider", .slider, "5", .slider, 5),
        ("stepper", .incrementor, "1", .incrementor, 1),
    ]
    let frame = Bounds(origin: Point(x: controlPx(0), y: controlPx(0)),
                       size: Size(width: controlPx(10), height: controlPx(10)))
    var nodes: [AccessibilityNodeID: AccessibilityNode] = [:]
    var geometry: [AccessibilityNodeID: AccessibilityGeometry] = [:]
    for (name, role, value, _, _) in cases {
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
    for (name, _, value, appKitRole, number) in cases {
        let element = bridge.element(for: AccessibilityNodeID(name))
        #expect(element.accessibilityRole() == appKitRole, "\(name): \(String(describing: element.accessibilityRole()))")
        let answer = element.accessibilityValue()
        if let number {
            let boxed = try #require(answer as? NSNumber, "\(name): the value \(String(describing: answer)) is not an NSNumber")
            #expect(boxed.doubleValue == number, "\(name): \(boxed)")
        } else {
            #expect(answer == nil || (answer as? String) == value, "\(name): no value")
        }
    }
}

/// **1.22.** The partial fold (`DD-U` item 3): a node declaring `.incrementor`
/// over a `Text` and two click targets takes the text as its label and keeps
/// the two as its children; the text is not published. M1n (the partial fold
/// removed) must redden it.
@Test @MainActor func aPartialFoldKeepsInteractiveChildrenAndTakesTheRestAsTheLabel() throws {
    var control = Row {
        Text("Qty")
        Box().cssWidth(controlPx(20)).cssHeight(controlPx(12)).onClick {}
        Box().cssWidth(controlPx(20)).cssHeight(controlPx(12)).onClick {}
    }
    control.handlers.axNode = AXNode(role: .incrementor, value: "1")
    let (_, published) = try tree(controlRoot { control })
    let (_, node) = try #require(published.nodes.first { $0.value.role == .incrementor },
                                 "no incrementor: \(published.nodes.values.map(\.role))")
    #expect(node.label == "Qty", "the text is the label")
    #expect(node.value == "1")
    let children = node.children.compactMap { published.nodes[$0] }
    #expect(children.map(\.role) == [.button, .button], "the two click targets stay children")
    #expect(!published.nodes.values.contains { $0.role == .staticText }, "the text is not published")
}

/// **1.23.** The selection hint (`DD-U` item 4): published as `isSelected`,
/// with no `Frame.axNodes` entry and no `$ax` slot in the `StateTable` — the
/// same ids as the unhinted box. The declared `.selected` trait is the
/// separating arm: it does write a `$ax` slot. M1s (the hint not stripped
/// before the emptiness test) must redden it.
@Test @MainActor func aSelectionHintPublishesSelectedAndWritesNoAXSlot() throws {
    func run(_ configure: (inout Handlers) -> Void) throws -> (AccessibilityNode?, Int, Set<GlobalElementID>) {
        var box = Box().cssWidth(controlPx(20)).cssHeight(controlPx(20))
        configure(&box.handlers)
        let table = StateTable()
        let (frame, published) = try tree(controlRoot { box }, stateTable: table)
        return (published.nodes.values.first, frame.axNodes.count, table.ids)
    }
    let (plainNode, plainNodes, plainIDs) = try run { _ in }
    let (hinted, hintedNodes, hintedIDs) = try run { $0.axNode.selectionHint = true }
    let (traited, traitedNodes, traitedIDs) = try run { $0.axNode.traits = [.selected] }

    #expect(plainNode == nil && plainNodes == 0, "control: a plain box says nothing")
    let node = try #require(hinted, "a hinted box publishes a node")
    #expect(node.isSelected, "the hint publishes isSelected")
    #expect(hintedNodes == 0, "the hint is not a declaration: no axNodes entry")
    #expect(hintedIDs == plainIDs, "and no $ax slot: \(hintedIDs.subtracting(plainIDs))")
    // The separating arm: a declared trait is a declaration.
    #expect(traited?.isSelected == true && traitedNodes == 1, "a declared .selected emits")
    #expect(traitedIDs.count == plainIDs.count + 1, "and writes one $ax slot")
}
