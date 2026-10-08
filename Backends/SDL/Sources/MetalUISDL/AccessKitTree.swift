// Compiled only under the `AccessKit` trait (ruling PX-H item 2): without it
// SDLPlatform has no screen-reader bridge.
#if AccessKit
import MetalUICore
import MetalUIPlatform

/// A MetalUI accessibility tree as AccessKit wants it (ruling AX-B): numeric
/// ids, a window root, roles and actions in AccessKit's vocabulary, bounds in
/// the window's physical pixels. A plain value — the adapter turns it into an
/// `accesskit_tree_update`, on whatever thread AccessKit asks from.
public struct AccessKitSnapshot: Equatable, Sendable {
    public enum Role: Equatable, Sendable {
        case window, genericContainer, button, label, image, table, row, textInput, multilineTextInput
        /// The five control roles (ruling `DD-U` item 1).
        case checkBox, radioButton, radioGroup, slider, spinButton
        /// `.heading` and `.link` (plan task 12 part 2, `IX-AD`).
        case heading, link
        /// The menu roles and a popover's dialog (ruling `MN-R`).
        case menu, menuItem, menuItemCheckBox, dialog
        /// A `.menu` picker's pop-up button and a drawn alert (ruling `SV-S`;
        /// `accesskit.h` 0.23 has no pop-up-button role, so a combo box with
        /// a menu popup).
        case comboBox, alertDialog
        /// A progress view — determinate or busy — and a colour well (ruling
        /// `LK-G`).
        case progressIndicator, colorWell
    }
    public enum Action: Equatable, Hashable, Sendable {
        case click, focus, increment, decrement
        /// Advertised when the node has custom actions (plan task 12 part 2,
        /// `IX-AD`); an incoming one carries its index as action data, so it
        /// is queued as `AccessKitAdapter.Queued.customAction`, never through
        /// `request(_:number:ids:)`.
        case customAction
        /// `SHOW_CONTEXT_MENU` — a node with a context menu (`MN-G` item 2).
        case showContextMenu
    }

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
        /// A check box's or radio button's state, from its `"1"`/`"0"` value
        /// (`DD-U` item 1); `nil` for every other role.
        public var toggled: Bool? = nil
        /// A slider's or stepper's value as a number, when it parses (`DD-U`
        /// item 1); `nil` otherwise.
        public var numericValue: Double? = nil
        /// A table's logical row count and a row's logical index (AB-L),
        /// AccessKit's `row_count`/`row_index` (plan task 12 part 2, `IX-AG`:
        /// the parity table found them untranslated).
        public var rowCount: Int? = nil
        public var rowIndex: Int? = nil
        /// The node's hint, sent as AccessKit's `description` (`IX-AD`).
        public var hint: String? = nil
        /// The node's identifier, sent as AccessKit's `author_id` (`IX-AD`).
        public var authorID: String? = nil
        /// Custom actions' names; each is pushed with its index as its id
        /// (`IX-AD`).
        public var customActions: [String] = []
        /// A selectable row: `selected` is sent as `false` when not selected,
        /// AccessKit's "selectable, not selected" (`IX-AA` item 2).
        public var isSelectable: Bool = false
        /// A button that opens a menu — `.menuButton` (ruling `MN-R`) and
        /// `.popUpButton` (`SV-S`): sent as AccessKit's `has_popup = MENU`.
        public var hasPopupMenu: Bool = false
        /// A determinate progress indicator's range, AccessKit's
        /// `min_numeric_value` 0 and `max_numeric_value` 1 (ruling `LK-G`).
        public var numericRange: Bool = false

        public static func == (a: Node, b: Node) -> Bool {
            a.id == b.id && a.role == b.role && a.label == b.label && a.value == b.value
                && a.bounds.map { [$0.0, $0.1, $0.2, $0.3] } == b.bounds.map { [$0.0, $0.1, $0.2, $0.3] }
                && a.children == b.children && a.actions == b.actions
                && a.isDisabled == b.isDisabled && a.isSelected == b.isSelected
                && a.toggled == b.toggled && a.numericValue == b.numericValue
                && a.rowCount == b.rowCount && a.rowIndex == b.rowIndex
                && a.hint == b.hint && a.authorID == b.authorID
                && a.customActions == b.customActions && a.isSelectable == b.isSelectable
                && a.hasPopupMenu == b.hasPopupMenu && a.numericRange == b.numericRange
        }

        /// What AccessKit's `selected` is set to: the selection when it is
        /// selected or selectable, unset otherwise (`IX-AA` item 2).
        var selectedState: Bool? {
            isSelected || isSelectable ? isSelected : nil
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
            if !node.customActions.isEmpty { actions.insert(.customAction) }
            if node.actions.contains(.showMenu) { actions.insert(.showContextMenu) }
            let frame = tree.geometry[id]?.frame
            nodes.append(Node(
                id: ids.number(for: id), role: role(node.role), label: node.label, value: node.value,
                bounds: frame.map { f in
                    let x = Double(f.origin.x.value) * scale, y = Double(f.origin.y.value) * scale
                    return (x, y, x + Double(f.size.width.value) * scale, y + Double(f.size.height.value) * scale)
                },
                children: node.children.map(ids.number(for:)), actions: actions,
                isDisabled: !node.isEnabled, isSelected: node.isSelected,
                toggled: toggled(node), numericValue: numericValue(node),
                rowCount: node.rowCount, rowIndex: node.rowIndex, hint: node.hint,
                authorID: node.identifier, customActions: node.customActions,
                isSelectable: node.isSelectable, hasPopupMenu: node.role == .menuButton || node.role == .popUpButton))
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
        case .checkBox: .checkBox
        case .radioButton: .radioButton
        case .radioGroup: .radioGroup
        case .slider: .slider
        case .incrementor: .spinButton
        case .heading: .heading
        case .link: .link
        // Menus (ruling `MN-R`): a menu button is a `BUTTON` with a menu popup
        // (`hasPopupMenu`), a popover a `DIALOG` never marked modal (`MN-O`).
        case .menu: .menu
        case .menuItem: .menuItem
        case .menuItemCheckBox: .menuItemCheckBox
        case .menuButton: .button
        case .popover: .dialog
        // Platform services (ruling `SV-S`): a pop-up button is a `COMBO_BOX`
        // with a menu popup (`hasPopupMenu`), a drawn alert an `ALERT_DIALOG`.
        case .popUpButton: .comboBox
        case .alert: .alertDialog
        case .progressIndicator, .busyIndicator, .colorWell: .genericContainer
        }
    }

    /// A check box's, radio button's or check-box menu item's toggled state
    /// from its `"1"`/`"0"` value (rulings `DD-U` item 1, `MN-R`); `nil` for
    /// any other role or value.
    static func toggled(_ node: AccessibilityNode) -> Bool? {
        guard node.role == .checkBox || node.role == .radioButton || node.role == .menuItemCheckBox else { return nil }
        switch node.value {
        case "1": return true
        case "0": return false
        default: return nil
        }
    }

    /// A slider's or stepper's value as a number when it parses (`DD-U` item
    /// 1); `nil` for any other role.
    static func numericValue(_ node: AccessibilityNode) -> Double? {
        guard node.role == .slider || node.role == .incrementor else { return nil }
        return node.value.flatMap(Double.init)
    }

    /// The MetalUI request an AccessKit action on node `number` means, if any.
    static func request(_ action: Action, number: UInt64, ids: AccessKitIDs) -> AccessibilityRequest? {
        guard let id = ids.node(for: number) else { return nil }
        switch action {
        case .click: return .press(id)
        case .focus: return .focus(id)
        case .increment: return .increment(id)
        case .decrement: return .decrement(id)
        case .customAction: return nil
        case .showContextMenu: return .showMenu(id)
        }
    }

    /// The MetalUI request a drained adapter item means, if any.
    static func request(for queued: AccessKitAdapter.Queued, ids: AccessKitIDs) -> AccessibilityRequest? {
        switch queued {
        case .activate: return .activate
        case let .action(action, number): return request(action, number: number, ids: ids)
        case let .customAction(number, index):
            guard let id = ids.node(for: number) else { return nil }
            return .customAction(id, index)
        }
    }
}
#endif
