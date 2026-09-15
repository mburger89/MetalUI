import MetalUICore

/// SKELETON (lane 2 red run): the shape only.
struct AccessibilityTreeChanges: Equatable {
    var removed: [AccessibilityNodeID] = []
    var structureChanged = false
    var labelChanged: [AccessibilityNodeID] = []
    var valueChanged: [AccessibilityNodeID] = []
    var rowCountChanged: [AccessibilityNodeID] = []
    var focusChanged = false

    init(from old: AccessibilityTree, to new: AccessibilityTree) {}
}
