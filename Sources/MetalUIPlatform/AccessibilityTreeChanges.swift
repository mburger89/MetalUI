import MetalUICore

/// What changed between two published trees that differ in structure (spec
/// `docs/superpowers/specs/2026-09-15-accessibility-bridge-design.md`, lane 2;
/// ruling AB-K).
///
/// **A pure diff over the neutral tree**, so it needs no AppKit and a UIKit
/// conformer can reuse it. The AppKit bridge computes one only when
/// `AccessibilityTree.hasSameStructure(as:)` is `false`: a geometry-only publish
/// (an animation tick, a scroll that moved no id) never gets here.
///
/// **Every list is in tree order** — pre-order from the roots, the order the
/// window recorded — never a dictionary's, so the notifications posted from it
/// come out in the same order on every run.
struct AccessibilityTreeChanges: Equatable {
    /// Ids in `old` and not in `new`, in old-tree order.
    var removed: [AccessibilityNodeID]
    /// The id set, the roots, any node's children, or any node's role changed:
    /// what makes a client re-read children (`.layoutChanged`).
    var structureChanged: Bool
    /// Ids in both trees whose label changed, in new-tree order.
    var labelChanged: [AccessibilityNodeID]
    /// Ids in both trees whose value changed, in new-tree order.
    var valueChanged: [AccessibilityNodeID]
    /// Ids in both trees whose `rowCount` changed, in new-tree order.
    var rowCountChanged: [AccessibilityNodeID]
    var focusChanged: Bool

    init(from old: AccessibilityTree, to new: AccessibilityTree) {
        removed = Self.preOrder(old).filter { new.nodes[$0] == nil }
        focusChanged = old.focused != new.focused
        var structureChanged = !removed.isEmpty || old.roots != new.roots
            || old.nodes.count != new.nodes.count
        var labelChanged: [AccessibilityNodeID] = []
        var valueChanged: [AccessibilityNodeID] = []
        var rowCountChanged: [AccessibilityNodeID] = []
        for id in Self.preOrder(new) {
            guard let before = old.nodes[id], let after = new.nodes[id] else {
                structureChanged = true          // added
                continue
            }
            if before.role != after.role || before.children != after.children { structureChanged = true }
            if before.label != after.label { labelChanged.append(id) }
            if before.value != after.value { valueChanged.append(id) }
            if before.rowCount != after.rowCount { rowCountChanged.append(id) }
        }
        self.structureChanged = structureChanged
        self.labelChanged = labelChanged
        self.valueChanged = valueChanged
        self.rowCountChanged = rowCountChanged
    }

    /// Every node reachable from the roots, parents before children, siblings
    /// in published order. Iterative, so a deep tree cannot exhaust the stack.
    static func preOrder(_ tree: AccessibilityTree) -> [AccessibilityNodeID] {
        var result: [AccessibilityNodeID] = []
        result.reserveCapacity(tree.nodes.count)
        var stack = Array(tree.roots.reversed())
        while let id = stack.popLast() {
            result.append(id)
            if let children = tree.nodes[id]?.children { stack.append(contentsOf: children.reversed()) }
        }
        return result
    }
}
