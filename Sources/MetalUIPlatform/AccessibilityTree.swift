import MetalUICore

// The platform-neutral accessibility tree a window publishes through
// `PlatformWindow.publishAccessibilityTree(_:)` (ruling AB-A, spec
// `docs/superpowers/specs/2026-09-15-accessibility-bridge-design.md`, lane 1).
//
// **A value, not a live view.** `MetalUIPlatform` cannot import `MetalUI`, so it
// never sees a `GlobalElementID`, an `AXNode` or an element. `Window` builds one
// of these per drawn frame while an accessibility client is active (AB-B) and
// pushes it across the seam; the platform answers every client query from the
// last value it was handed and sends `AccessibilityRequest`s back.
//
// **`Sendable` is deliberately not declared on the id or the tree.** Every value
// crosses only between `@MainActor` code, and `AnyHashable`'s conformance would
// have to be argued. `AccessibilityRole` and `AccessibilityActions` declare it
// because each carries a `static let` (Swift 6 rejects a global of a
// non-`Sendable` public type) and neither holds anything but a tag.

/// Opaque, hashable identity of a published node. `MetalUI` wraps a
/// `GlobalElementID`; the platform never looks inside (AB-A).
///
/// Stable across frames for as long as the element keeps its structural
/// identity, so a platform may key one element object per id (AB-D).
public struct AccessibilityNodeID: Hashable {
    /// The wrapped identity, compared and hashed by value.
    public let base: AnyHashable
    /// An id wrapping any hashable identity, typically a `GlobalElementID`.
    public init<Base: Hashable>(_ base: Base) { self.base = AnyHashable(base) }
}

/// The platform-neutral role vocabulary. Deliberately small: one case per
/// NSAccessibility role the bridge publishes.
public enum AccessibilityRole: Equatable, Sendable {
    case group, button, staticText, image, table, row
    /// An editable line of text (ruling TI-C).
    case textField
    /// Editable multi-line text (ruling TI-H).
    case textArea
    /// A checkbox — `Toggle` (ruling `DD-U` item 1; AppKit `.checkBox`).
    case checkBox
    /// One option of a `Picker` (`DD-U`; AppKit `.radioButton`).
    case radioButton
    /// A `Picker` (`DD-U`; AppKit `.radioGroup`).
    case radioGroup
    /// A `Slider` (`DD-U`; AppKit `.slider`).
    case slider
    /// A `Stepper` (`DD-U`; AppKit `.incrementor`).
    case incrementor
    /// A heading — the `.isHeader` trait (plan task 12 part 2, `IX-X`; AppKit
    /// `AXHeading`, AccessKit `HEADING`).
    case heading
    /// A link — the `.isLink` trait (`IX-X`; AppKit `AXLink`, AccessKit `LINK`).
    case link
    /// A menu — one level of a drawn menu panel (ruling `MN-R`; AppKit
    /// `AXMenu`, AccessKit `MENU`).
    case menu
    /// One item of a menu (`MN-R`; AppKit `AXMenuItem`, AccessKit `MENU_ITEM`).
    case menuItem
    /// A menu item with an on/off state, its value `"1"` or `"0"` (`MN-R`;
    /// AppKit `AXMenuItem` with a `✓` mark character when on, AccessKit
    /// `MENU_ITEM_CHECK_BOX`).
    case menuItemCheckBox
    /// A button that opens a menu — `Menu("…")` (`MN-H` item 2; AppKit
    /// `AXMenuButton`, AccessKit `BUTTON` with a menu popup).
    case menuButton
    /// A popover's panel (`MN-O`; AppKit `AXPopover`, AccessKit a non-modal
    /// `DIALOG`).
    case popover
    /// A pop-up button showing its selection and opening a menu of choices —
    /// a `.menu` `Picker` (ruling `SV-S`; AppKit `AXPopUpButton`, the probe's
    /// `P0`–`P3`; AccessKit `COMBO_BOX` with a menu popup — `accesskit.h` 0.23
    /// has no pop-up-button role).
    case popUpButton
    /// An alert drawn in the window (ruling `SV-S`; AppKit `AXGroup` with
    /// subrole `AXDialog` — never published there, whose alert is native;
    /// AccessKit `ALERT_DIALOG`).
    case alert
    /// A determinate `ProgressView`, its value the fraction 0…1 (ruling
    /// `LK-G`, probe `V7`/`V8`; AppKit `AXProgressIndicator` with an
    /// `NSNumber` value, AccessKit `PROGRESS_INDICATOR` with a numeric value
    /// over 0…1).
    case progressIndicator
    /// An indeterminate `ProgressView`, no value (`LK-G`, `V8`; AppKit
    /// `AXBusyIndicator`, AccessKit `PROGRESS_INDICATOR` with no numeric value
    /// — `accesskit.h` 0.23 has no busy role).
    case busyIndicator
    /// A `ColorPicker`'s well, its value `rgb R G B A` (`LK-G`, `LK-C` item 7,
    /// probe `C1`; AppKit `AXColorWell`, AccessKit `COLOR_WELL`).
    case colorWell
}

/// What a client may ask a node to do. **Derived from live handlers, never from
/// a declaration** (AB-H): advertising an action with no handler would tell a
/// screen reader a control works when it does nothing.
public struct AccessibilityActions: OptionSet, Equatable, Sendable {
    public let rawValue: UInt8
    /// An action set from its raw bits; prefer the named statics.
    public init(rawValue: UInt8) { self.rawValue = rawValue }
    /// The node can be pressed.
    public static let press = AccessibilityActions(rawValue: 1 << 0)
    /// The node's value can be increased.
    public static let increment = AccessibilityActions(rawValue: 1 << 1)
    /// The node's value can be decreased.
    public static let decrement = AccessibilityActions(rawValue: 1 << 2)
    /// The node has a context menu a client may open (ruling `MN-G` item 2;
    /// AppKit `accessibilityPerformShowMenu`, AccessKit `SHOW_CONTEXT_MENU`).
    public static let showMenu = AccessibilityActions(rawValue: 1 << 3)
}

/// What a node says and what it can do. No geometry: see `AccessibilityGeometry`,
/// and `AccessibilityTree.hasSameStructure(as:)` for why the two are apart.
public struct AccessibilityNode: Equatable {
    /// The node's role, translated by each bridge to its platform's role.
    public var role: AccessibilityRole
    /// The accessible name; `nil` publishes none.
    public var label: String?
    /// The accessible value; `nil` publishes none.
    public var value: String?
    /// Whether the node is selected.
    public var isSelected: Bool
    /// Whether the node is enabled; a disabled node advertises no actions.
    public var isEnabled: Bool
    /// Whether the node can take keyboard focus.
    public var isFocusable: Bool
    /// The actions a client may request, derived from the last frame's live
    /// handlers (`AB-H`).
    public var actions: AccessibilityActions
    /// In published order: the order the elements recorded during prepaint,
    /// which is declaration order (AB-C).
    public var children: [AccessibilityNodeID]
    /// `AXRowCount` for a `.table`: the logical count a virtualized container
    /// represents, not its realized children (AB-L).
    public var rowCount: Int?
    /// `AXIndex` for a `.row` (AB-L): a realized row's logical index, which
    /// `List` gives each row it realizes while a client is active and its
    /// window is bounded.
    public var rowIndex: Int?
    /// A declared hint (plan task 12 part 2, `IX-W`): AppKit's `AXHelp`,
    /// AccessKit's `description`.
    public var hint: String?
    /// A declared identifier (`IX-W`): AppKit's `AXIdentifier`, AccessKit's
    /// `author_id`. Never spoken.
    public var identifier: String?
    /// The node's custom actions' names, in published order (`IX-Y`). A client
    /// runs one with `AccessibilityRequest.customAction(id, index)`, the index
    /// into this array.
    public var customActions: [String]
    /// A row a client may select directly (`IX-AA`): a row of a
    /// `List(selection:)`. AppKit allows `setAccessibilitySelected(_:)` on it
    /// and `setAccessibilitySelectedRows(_:)` on its table; AccessKit publishes
    /// its `selected` state as `false` as well as `true`.
    public var isSelectable: Bool

    /// A node; every field but `role` defaults to absent, enabled and not
    /// focusable.
    public init(role: AccessibilityRole, label: String? = nil, value: String? = nil,
                isSelected: Bool = false, isEnabled: Bool = true, isFocusable: Bool = false,
                actions: AccessibilityActions = [], children: [AccessibilityNodeID] = [],
                rowCount: Int? = nil, rowIndex: Int? = nil, hint: String? = nil,
                identifier: String? = nil, customActions: [String] = [], isSelectable: Bool = false) {
        self.role = role
        self.label = label
        self.value = value
        self.isSelected = isSelected
        self.isEnabled = isEnabled
        self.isFocusable = isFocusable
        self.actions = actions
        self.children = children
        self.rowCount = rowCount
        self.rowIndex = rowIndex
        self.hint = hint
        self.identifier = identifier
        self.customActions = customActions
        self.isSelectable = isSelectable
    }
}

/// Where a node is. Window content space: logical points, top-left origin, the
/// scroll offset applied (AB-E).
public struct AccessibilityGeometry: Equatable {
    /// NOT clipped: what `accessibilityFrame` reports. A row scrolled out of a
    /// `ScrollView` still has its full rect here, as SwiftUI's do (arm R17).
    public var frame: Bounds<Pixels>
    /// `frame` intersected with the clip active where the node recorded — the
    /// rect a hitbox registers at. Used only for hit testing (AB-W); zero-area
    /// when the node is scrolled fully out of its viewport.
    public var visibleFrame: Bounds<Pixels>
    /// The paint layer the node recorded on: 0 outside every `Deferred`,
    /// `Frame.rootLayer` inside one — `Hitbox.layer`'s value. The hit test's
    /// primary key, so portal content outranks what it covers wherever it was
    /// declared (AB-W).
    public var layer: Int
    /// The node's position in the frame's record order (first occurrence,
    /// AB-O): pre-order, so a descendant outranks its ancestor and a later
    /// sibling an earlier one. The hit test's tiebreak within a layer (AB-W).
    public var order: Int

    /// A node's geometry: its `frame`, the part of it `visibleFrame` shows, and
    /// its hit-test `layer` and `order`.
    public init(frame: Bounds<Pixels>, visibleFrame: Bounds<Pixels>, layer: Int = 0, order: Int = 0) {
        self.frame = frame
        self.visibleFrame = visibleFrame
        self.layer = layer
        self.order = order
    }
}

/// One window's published accessibility tree: nodes, their geometry kept apart,
/// and the focused node (`AB-K`).
public struct AccessibilityTree: Equatable {
    /// Nodes with no published parent, in published order. `Deferred` content
    /// is always a root (AB-V).
    public var roots: [AccessibilityNodeID]
    /// Every published node by id.
    public var nodes: [AccessibilityNodeID: AccessibilityNode]
    /// Kept apart from `nodes` so that an animation tick, which moves frames and
    /// nothing else, is a cheap comparison on the platform side (AB-K).
    public var geometry: [AccessibilityNodeID: AccessibilityGeometry]
    /// The window's keyboard focus when that element published a node (AB-J).
    public var focused: AccessibilityNodeID?

    /// A tree from its roots, nodes, geometry and focused node.
    public init(roots: [AccessibilityNodeID], nodes: [AccessibilityNodeID: AccessibilityNode],
                geometry: [AccessibilityNodeID: AccessibilityGeometry],
                focused: AccessibilityNodeID?) {
        self.roots = roots
        self.nodes = nodes
        self.geometry = geometry
        self.focused = focused
    }

    /// No nodes, nothing focused. What a platform exposes before the first
    /// publish. Computed rather than a `static let`: the tree is not `Sendable`.
    public static var empty: AccessibilityTree {
        AccessibilityTree(roots: [], nodes: [:], geometry: [:], focused: nil)
    }

    /// `roots`, `nodes` and `focused` equal; `geometry` ignored (AB-K).
    ///
    /// **What a platform uses to tell an animation tick or a scroll that moved
    /// no id from a change a client must hear about.** `Window` compares whole
    /// trees with `==` (geometry included) to decide whether to publish at all
    /// (AB-M); the platform then asks this to decide whether the publish is a
    /// stored assignment or a diff with notifications.
    public func hasSameStructure(as other: AccessibilityTree) -> Bool {
        roots == other.roots && focused == other.focused && nodes == other.nodes
    }
}

/// What an accessibility client asked the window to do. It has `onInput`'s
/// shape: the answer says whether anything handled it.
public enum AccessibilityRequest: Equatable {
    /// A client is present (AB-B). Sticky: the window collects from then on.
    case activate
    /// Run the node's `onClick`, through the last frame's hitboxes (AB-H).
    case press(AccessibilityNodeID)
    case increment(AccessibilityNodeID)
    case decrement(AccessibilityNodeID)
    /// Move keyboard focus to the node, if the last frame found it focusable
    /// (AB-J).
    case focus(AccessibilityNodeID)
    /// Run the node's custom action at this index into its `customActions`
    /// (plan task 12 part 2, `IX-Y`).
    case customAction(AccessibilityNodeID, Int)
    /// Replace the selection of the row's list with this row (`IX-AA`; AppKit
    /// `setAccessibilitySelected(true)`, SwiftUI arms LA2, LB3).
    case select(AccessibilityNodeID)
    /// Set the table's selection to exactly these rows (`IX-AA`; AppKit
    /// `setAccessibilitySelectedRows(_:)`, LA3, LB2). A single-selection list
    /// ignores a request for more than one row (LA4).
    case selectRows(AccessibilityNodeID, [AccessibilityNodeID])
    /// Open the node's context menu, anchored at its bottom-leading corner
    /// (ruling `MN-G` item 2). Refused for a node without one (C11n, `MN-W`).
    ///
    /// **Migration** (`MN-R`): an exhaustive `switch` over
    /// `AccessibilityRequest` or `AccessibilityRole` outside this package adds
    /// the new cases or a `default:`.
    case showMenu(AccessibilityNodeID)
}
