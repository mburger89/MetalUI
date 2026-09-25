import MetalUICore
import MetalUIPlatform

/// A MetalUI accessibility tree as AccessKit wants it (ruling AX-B): numeric
/// ids, a window root, roles and actions in AccessKit's vocabulary, bounds in
/// the window's physical pixels. A plain value — the adapter turns it into an
/// `accesskit_tree_update`, on whatever thread AccessKit asks from.
public struct AccessKitSnapshot: Equatable, Sendable {
    public enum Role: Equatable, Sendable { case window, genericContainer, button, label, image, table, row, textInput, multilineTextInput }
    public enum Action: Equatable, Hashable, Sendable { case click, focus, increment, decrement }

    public struct Node: Equatable, Sendable {
        public var id: UInt64
        public var role: Role
        public var label: String?
        public var value: String?
        /// `(x0, y0, x1, y1)` in physical pixels, y down.
        public var bounds: (Double, Double, Double, Double)?
        public var children: [UInt64]
        public var actions: Set<Action>
        public var isDisabled: Bool
        public var isSelected: Bool

        public static func == (a: Node, b: Node) -> Bool {
            a.id == b.id && a.role == b.role && a.label == b.label && a.value == b.value
                && a.bounds.map { [$0.0, $0.1, $0.2, $0.3] } == b.bounds.map { [$0.0, $0.1, $0.2, $0.3] }
                && a.children == b.children && a.actions == b.actions
                && a.isDisabled == b.isDisabled && a.isSelected == b.isSelected
        }
    }

    /// The window's own node — AccessKit's tree root.
    public static let rootID: UInt64 = 0

    public var nodes: [Node]
    public var focus: UInt64

    public static func empty(title: String) -> AccessKitSnapshot {
        AccessKitSnapshot(nodes: [Node(id: rootID, role: .window, label: title, value: nil, bounds: nil,
                                       children: [], actions: [], isDisabled: false, isSelected: false)],
                          focus: rootID)
    }
}

/// Stable AccessKit ids for MetalUI's node ids (ruling AX-B): an id keeps its
/// number for as long as the node exists, as a screen reader expects; 0 is the
/// window.
final class AccessKitIDs {
    private var numbers: [AccessibilityNodeID: UInt64] = [:]
    private var nodes: [UInt64: AccessibilityNodeID] = [:]
    private var next: UInt64 = 1

    func number(for id: AccessibilityNodeID) -> UInt64 {
        if let number = numbers[id] { return number }
        let number = next
        next += 1
        numbers[id] = number
        nodes[number] = id
        return number
    }

    func node(for number: UInt64) -> AccessibilityNodeID? { nodes[number] }

    /// Forgets ids no longer in `live`, so the tables do not grow forever.
    func retain(only live: Set<AccessibilityNodeID>) {
        for (id, number) in numbers where !live.contains(id) {
            numbers[id] = nil
            nodes[number] = nil
        }
    }
}

extension AccessKitSnapshot {
    /// `tree` in AccessKit's terms, under a window node titled `title`.
    /// Geometry is MetalUI's (points, window content origin) times `scale`.
    static func translate(_ tree: AccessibilityTree, title: String, scale: Double,
                          ids: AccessKitIDs) -> AccessKitSnapshot {
        ids.retain(only: Set(tree.nodes.keys))
        var nodes = [Node(id: rootID, role: .window, label: title, value: nil, bounds: nil,
                          children: tree.roots.map(ids.number(for:)), actions: [],
                          isDisabled: false, isSelected: false)]
        // Depth first from the roots, so a parent precedes its children.
        var stack = Array(tree.roots.reversed())
        var seen = Set<AccessibilityNodeID>()
        while let id = stack.popLast() {
            guard !seen.contains(id), let node = tree.nodes[id] else { continue }
            seen.insert(id)
            var actions = Set<Action>()
            if node.actions.contains(.press) { actions.insert(.click) }
            if node.actions.contains(.increment) { actions.insert(.increment) }
            if node.actions.contains(.decrement) { actions.insert(.decrement) }
            if node.isFocusable { actions.insert(.focus) }
            let frame = tree.geometry[id]?.frame
            nodes.append(Node(
                id: ids.number(for: id), role: role(node.role), label: node.label, value: node.value,
                bounds: frame.map { f in
                    let x = Double(f.origin.x.value) * scale, y = Double(f.origin.y.value) * scale
                    return (x, y, x + Double(f.size.width.value) * scale, y + Double(f.size.height.value) * scale)
                },
                children: node.children.map(ids.number(for:)), actions: actions,
                isDisabled: !node.isEnabled, isSelected: node.isSelected))
            stack.append(contentsOf: node.children.reversed())
        }
        let focus = tree.focused.flatMap { tree.nodes[$0] != nil ? ids.number(for: $0) : nil } ?? rootID
        return AccessKitSnapshot(nodes: nodes, focus: focus)
    }

    static func role(_ role: AccessibilityRole) -> Role {
        switch role {
        case .group: .genericContainer
        case .button: .button
        case .staticText: .label
        case .image: .image
        case .table: .table
        case .row: .row
        case .textField: .textInput
        case .textArea: .multilineTextInput
        }
    }

    /// The MetalUI request an AccessKit action on node `number` means, if any.
    static func request(_ action: Action, number: UInt64, ids: AccessKitIDs) -> AccessibilityRequest? {
        guard let id = ids.node(for: number) else { return nil }
        switch action {
        case .click: return .press(id)
        case .focus: return .focus(id)
        case .increment: return .increment(id)
        case .decrement: return .decrement(id)
        }
    }
}
