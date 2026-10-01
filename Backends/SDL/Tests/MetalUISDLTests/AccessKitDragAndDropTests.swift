import Testing
import MetalUICore
import MetalUIPlatform
@testable import MetalUISDL
import CAccessKit

// Drag and drop, lane 3, test 3.9 (ruling `DN-N`; spec
// `docs/superpowers/specs/2026-10-01-drag-and-drop-design.md` §6.5).
//
// **The tree is transcribed, not rendered** — `AccessKitControlsParityTests`'
// footing: this target depends on `MetalUIPlatform`, `MetalUICore` and
// `MetalUIScene`, not on `MetalUI`, so it cannot build a `Window`. The four
// nodes below are what the root package's 3.8
// (`aDraggableAndADropDestinationPublishNothingNew`) pins, literal for literal,
// for a draggable `Text`, a draggable `Button`, a labelled destination and a
// destination `Text` — and 3.8 also pins that the same tree **without** the
// modifiers publishes exactly them. So AccessKit's node for each is the
// control's: a change on the root side reddens 3.8 first, and this one then
// needs the same edit.

private func nid(_ name: String) -> AccessibilityNodeID { AccessibilityNodeID(name) }

/// 3.8's four nodes, in reading order.
private func dragAndDropTree() -> AccessibilityTree {
    let names = ["chip", "go", "well", "drop"]
    let nodes: [AccessibilityNodeID: AccessibilityNode] = [
        nid("chip"): AccessibilityNode(role: .staticText, value: "Chip"),
        nid("go"): AccessibilityNode(role: .button, label: "Go", isFocusable: true, actions: [.press]),
        nid("well"): AccessibilityNode(role: .group, label: "Well"),
        nid("drop"): AccessibilityNode(role: .staticText, value: "Drop here"),
    ]
    return AccessibilityTree(roots: names.map(nid), nodes: nodes, geometry: [:], focused: nil)
}

/// **3.9** (`DN-N`). AccessKit's node for a draggable `Text`, a draggable
/// `Button`, a labelled destination and a destination `Text` is the control's:
/// a label, a button that clicks and focuses, a generic container labelled
/// "Well", a label — no custom action, no extra action, on the snapshot and on
/// the `accesskit_node` AccessKit is handed. Its mutation is 3.8's (**M3h**)
/// reaching AccessKit through 3.8's literal; an AccessKit-side mutation that
/// advertised anything drag-shaped (**M3h′**) must redden it here.
@Test func accessKitPublishesADraggableAndADropDestinationUnchanged() throws {
    let tree = dragAndDropTree()
    let ids = AccessKitIDs()
    let snapshot = AccessKitSnapshot.translate(tree, title: "MetalUI — Drag and Drop", scale: 1, ids: ids)
    try #require(snapshot.nodes.count == tree.nodes.count + 1, "every node and the window")
    let byNumber = Dictionary(uniqueKeysWithValues: snapshot.nodes.map { ($0.id, $0) })
    struct Row {
        var name: String
        var role: AccessKitSnapshot.Role
        var accessKitRole: UInt32
        var label: String?
        var value: String?
        var actions: Set<AccessKitSnapshot.Action>
    }
    let rows: [Row] = [
        Row(name: "chip", role: .label, accessKitRole: UInt32(ACCESSKIT_ROLE_LABEL.rawValue), value: "Chip", actions: []),
        Row(name: "go", role: .button, accessKitRole: UInt32(ACCESSKIT_ROLE_BUTTON.rawValue), label: "Go",
            actions: [.click, .focus]),
        Row(name: "well", role: .genericContainer, accessKitRole: UInt32(ACCESSKIT_ROLE_GENERIC_CONTAINER.rawValue),
            label: "Well", actions: []),
        Row(name: "drop", role: .label, accessKitRole: UInt32(ACCESSKIT_ROLE_LABEL.rawValue), value: "Drop here",
            actions: []),
    ]
    for row in rows {
        let node = try #require(byNumber[ids.number(for: nid(row.name))], "\(row.name) translated")
        #expect(node.role == row.role, "\(row.name): \(node.role)")
        #expect(node.label == row.label && node.value == row.value, "\(row.name): \(node)")
        #expect(node.actions == row.actions, "\(row.name): \(node.actions)")
        #expect(node.customActions.isEmpty, "\(row.name): \(node.customActions)")
        #expect(!node.isDisabled && !node.isSelected && node.hint == nil && node.authorID == nil, "\(row.name)")
        let c = AccessKitAdapter.cNode(node)
        defer { accesskit_node_free(c) }
        #expect(accesskit_node_role(c) == accesskit_role(row.accessKitRole), "\(row.name): AccessKit's own role")
    }
}
