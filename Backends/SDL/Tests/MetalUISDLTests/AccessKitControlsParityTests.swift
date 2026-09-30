import Testing
import MetalUICore
import MetalUIPlatform
@testable import MetalUISDL
import CAccessKit

// Plan task 12 part 2, lane 3 (spec `2026-09-29-accessibility-design.md` §7
// row 3.7, ruling `IX-AD`): the controls demo's published tree through
// AccessKit, the same role/label/value/state table the root package's 3.6 and
// 3.9 assert through `Window`, in AccessKit's vocabulary.
//
// **The tree is transcribed, not rendered.** This test target depends on
// `MetalUIPlatform`, `MetalUICore` and `MetalUIScene` only (`Package.swift`),
// not on `MetalUI` or `MetalUIDemoContent`, and a `Window` needs a
// `PlatformWindow` fake the root package's tests own. So the nodes below are
// `theControlsDemoPublishesTheTreeTheVoiceOverScriptReads`' table (root
// `Tests/MetalUITests/AccessibilityAuditTests.swift`, 3.9) node for node —
// reading order, role, label, value, selected, actions, focusable — and the
// table's first seven realized rows at 920 × 560. A change to the demo's tree
// reddens 3.9 first; this one then needs the same edit (lane 3's landing
// ruling records the transcription).

private func nid(_ name: String) -> AccessibilityNodeID { AccessibilityNodeID(name) }

/// The controls demo's tree as 3.9 pins it.
private func controlsDemoTree() -> AccessibilityTree {
    let press: AccessibilityActions = [.press], adjust: AccessibilityActions = [.increment, .decrement]
    var nodes: [AccessibilityNodeID: AccessibilityNode] = [:]
    var roots: [AccessibilityNodeID] = []
    func add(_ name: String, _ node: AccessibilityNode, root: Bool = true) {
        nodes[nid(name)] = node
        if root { roots.append(nid(name)) }
    }
    add("title", AccessibilityNode(role: .staticText, value: "Controls"))
    add("press", AccessibilityNode(role: .button, label: "Press me", isFocusable: true, actions: press))
    add("count", AccessibilityNode(role: .staticText, value: "pressed 0 times"))
    add("wifi", AccessibilityNode(role: .checkBox, label: "Wi-Fi", value: "1", isFocusable: true, actions: press))
    add("slider", AccessibilityNode(role: .slider, value: "0.4", isFocusable: true, actions: adjust))
    add("volume", AccessibilityNode(role: .staticText, value: "volume 4"))
    add("stepper", AccessibilityNode(role: .incrementor, label: "Quantity 2", value: "2", isFocusable: true,
                                     actions: adjust, children: [nid("up"), nid("down")]))
    add("up", AccessibilityNode(role: .button, actions: press), root: false)
    add("down", AccessibilityNode(role: .button, actions: press), root: false)
    for (group, options, selected) in [("Flavor", ["Vanilla", "Chocolate", "Strawberry"], 1),
                                       ("Size", ["Small", "Medium", "Large"], 1)] {
        add(group, AccessibilityNode(role: .radioGroup, label: group, isFocusable: true,
                                     children: options.map(nid)))
        for (index, option) in options.enumerated() {
            add(option, AccessibilityNode(role: .radioButton, label: option, value: index == selected ? "1" : "0",
                                          isSelected: index == selected, actions: press), root: false)
        }
    }
    for (chore, done) in [("Water the plants", false), ("Take out the bins", true), ("Call the plumber", false)] {
        add(chore, AccessibilityNode(role: .checkBox, label: chore, value: done ? "1" : "0", isFocusable: true,
                                     actions: press))
    }
    add("table", AccessibilityNode(role: .table, isFocusable: true, children: (0..<7).map { nid("row\($0)") },
                                   rowCount: 40))
    for index in 0..<7 {
        add("row\(index)", AccessibilityNode(role: .row, isSelected: index == 2, actions: press,
                                             children: [nid("text\(index)")], rowIndex: index,
                                             isSelectable: true), root: false)
        add("text\(index)", AccessibilityNode(role: .staticText, value: "Row \(index)"), root: false)
    }
    return AccessibilityTree(roots: roots, nodes: nodes, geometry: [:], focused: nil)
}

/// **3.7.** The controls demo translates to AccessKit as to AppKit: every
/// control's role in AccessKit's vocabulary (`IX-AD`'s table — a check box is
/// `CHECK_BOX` with `toggled`, a slider `SLIDER` and a stepper `SPIN_BUTTON`
/// with a numeric value, a picker a `RADIO_GROUP` of `RADIO_BUTTON`s, the list
/// a `TABLE` of selectable `ROW`s with their counts), its label and value, its
/// selected state, and a press/increment/decrement/focus action for each one
/// the neutral node carries — both on the snapshot and on the `accesskit_node`
/// AccessKit is handed. Mutation M3g (`.incrementor` → `.button` in AccessKit)
/// must redden it.
@Test func theControlsDemoTranslatesToAccessKitAsToAppKit() throws {
    let tree = controlsDemoTree()
    let ids = AccessKitIDs()
    let snapshot = AccessKitSnapshot.translate(tree, title: "MetalUI — Controls", scale: 1, ids: ids)
    let byNumber = Dictionary(uniqueKeysWithValues: snapshot.nodes.map { ($0.id, $0) })
    func node(_ name: String) throws -> AccessKitSnapshot.Node {
        try #require(byNumber[ids.number(for: nid(name))], "\(name) translated")
    }
    try #require(snapshot.nodes.count == tree.nodes.count + 1, "every node and the window")

    struct Row {
        var name: String
        var role: AccessKitSnapshot.Role
        var accessKitRole: UInt32
        var label: String?
        var value: String?
        var actions: Set<AccessKitSnapshot.Action>
        var toggled: Bool? = nil
        var numeric: Double? = nil
        var selected: Bool? = nil
    }
    let pressFocus: Set<AccessKitSnapshot.Action> = [.click, .focus]
    let adjustFocus: Set<AccessKitSnapshot.Action> = [.increment, .decrement, .focus]
    let table: [Row] = [
        Row(name: "title", role: .label, accessKitRole: UInt32(ACCESSKIT_ROLE_LABEL.rawValue), value: "Controls", actions: []),
        Row(name: "press", role: .button, accessKitRole: UInt32(ACCESSKIT_ROLE_BUTTON.rawValue), label: "Press me",
            actions: pressFocus),
        Row(name: "wifi", role: .checkBox, accessKitRole: UInt32(ACCESSKIT_ROLE_CHECK_BOX.rawValue), label: "Wi-Fi", value: "1",
            actions: pressFocus, toggled: true),
        Row(name: "slider", role: .slider, accessKitRole: UInt32(ACCESSKIT_ROLE_SLIDER.rawValue), value: "0.4",
            actions: adjustFocus, numeric: 0.4),
        Row(name: "stepper", role: .spinButton, accessKitRole: UInt32(ACCESSKIT_ROLE_SPIN_BUTTON.rawValue), label: "Quantity 2",
            value: "2", actions: adjustFocus, numeric: 2),
        Row(name: "Flavor", role: .radioGroup, accessKitRole: UInt32(ACCESSKIT_ROLE_RADIO_GROUP.rawValue), label: "Flavor",
            actions: [.focus]),
        Row(name: "Chocolate", role: .radioButton, accessKitRole: UInt32(ACCESSKIT_ROLE_RADIO_BUTTON.rawValue),
            label: "Chocolate", value: "1", actions: [.click], toggled: true, selected: true),
        Row(name: "Vanilla", role: .radioButton, accessKitRole: UInt32(ACCESSKIT_ROLE_RADIO_BUTTON.rawValue), label: "Vanilla",
            value: "0", actions: [.click], toggled: false),
        Row(name: "Size", role: .radioGroup, accessKitRole: UInt32(ACCESSKIT_ROLE_RADIO_GROUP.rawValue), label: "Size",
            actions: [.focus]),
        Row(name: "Take out the bins", role: .checkBox, accessKitRole: UInt32(ACCESSKIT_ROLE_CHECK_BOX.rawValue),
            label: "Take out the bins", value: "1", actions: pressFocus, toggled: true),
        Row(name: "Water the plants", role: .checkBox, accessKitRole: UInt32(ACCESSKIT_ROLE_CHECK_BOX.rawValue),
            label: "Water the plants", value: "0", actions: pressFocus, toggled: false),
        Row(name: "table", role: .table, accessKitRole: UInt32(ACCESSKIT_ROLE_TABLE.rawValue), actions: [.focus]),
        Row(name: "row2", role: .row, accessKitRole: UInt32(ACCESSKIT_ROLE_ROW.rawValue), actions: [.click], selected: true),
        Row(name: "row3", role: .row, accessKitRole: UInt32(ACCESSKIT_ROLE_ROW.rawValue), actions: [.click], selected: false),
        Row(name: "text3", role: .label, accessKitRole: UInt32(ACCESSKIT_ROLE_LABEL.rawValue), value: "Row 3", actions: []),
    ]
    for row in table {
        let translated = try node(row.name)
        #expect(translated.role == row.role, "\(row.name): \(translated.role)")
        #expect(translated.label == row.label && translated.value == row.value, "\(row.name): \(translated)")
        #expect(translated.actions == row.actions, "\(row.name): \(translated.actions)")
        #expect(translated.toggled == row.toggled, "\(row.name): toggled \(String(describing: translated.toggled))")
        #expect(translated.numericValue == row.numeric, "\(row.name): numeric")
        #expect(translated.selectedState == row.selected, "\(row.name): selected")
        #expect(!translated.isDisabled, "\(row.name): enabled")
        let c = AccessKitAdapter.cNode(translated)
        defer { accesskit_node_free(c) }
        #expect(accesskit_node_role(c) == accesskit_role(row.accessKitRole), "\(row.name): AccessKit's own role")
    }
    #expect(try node("table").rowCount == 40, "the table's logical count")
    #expect(try node("row3").rowIndex == 3 && node("row3").isSelectable, "a row's index, selectable")
    #expect(try node("table").children.count == 7, "the realized rows")
}
