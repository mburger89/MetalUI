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
    public let base: AnyHashable
    public init<Base: Hashable>(_ base: Base) { self.base = AnyHashable(base) }
}

/// The platform-neutral role vocabulary. Deliberately small: one case per
/// NSAccessibility role the bridge publishes.
public enum AccessibilityRole: Equatable, Sendable {
    case group, button, staticText, image, table, row
}

/// What a client may ask a node to do. **Derived from live handlers, never from
/// a declaration** (AB-H): advertising an action with no handler would tell a
/// screen reader a control works when it does nothing.
public struct AccessibilityActions: OptionSet, Equatable, Sendable {
    public let rawValue: UInt8
    public init(rawValue: UInt8) { self.rawValue = rawValue }
    public static let press = AccessibilityActions(rawValue: 1 << 0)
    public static let increment = AccessibilityActions(rawValue: 1 << 1)
    public static let decrement = AccessibilityActions(rawValue: 1 << 2)
}

/// What a node says and what it can do. No geometry: see `AccessibilityGeometry`,
/// and `AccessibilityTree.hasSameStructure(as:)` for why the two are apart.
public struct AccessibilityNode: Equatable {
    public var role: AccessibilityRole
    public var label: String?
    public var value: String?
    public var isSelected: Bool
    public var isEnabled: Bool
    public var isFocusable: Bool
    public var actions: AccessibilityActions
    /// In published order: the order the elements recorded during prepaint,
    /// which is declaration order (AB-C).
    public var children: [AccessibilityNodeID]
    /// `AXRowCount` for a `.table`: the logical count a virtualized container
    /// represents, not its realized children (AB-L).
    public var rowCount: Int?
    /// `AXIndex` for a `.row` (AB-L). No producer until lane 3 gives `List`'s
    /// realized rows a logical index.
    public var rowIndex: Int?

    public init(role: AccessibilityRole, label: String? = nil, value: String? = nil,
                isSelected: Bool = false, isEnabled: Bool = true, isFocusable: Bool = false,
                actions: AccessibilityActions = [], children: [AccessibilityNodeID] = [],
                rowCount: Int? = nil, rowIndex: Int? = nil) {
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

    public init(frame: Bounds<Pixels>, visibleFrame: Bounds<Pixels>) {
        self.frame = frame
        self.visibleFrame = visibleFrame
    }
}

public struct AccessibilityTree: Equatable {
    /// Nodes with no published parent, in published order. `Deferred` content
    /// is always a root (AB-V).
    public var roots: [AccessibilityNodeID]
    public var nodes: [AccessibilityNodeID: AccessibilityNode]
    /// Kept apart from `nodes` so that an animation tick, which moves frames and
    /// nothing else, is a cheap comparison on the platform side (AB-K).
    public var geometry: [AccessibilityNodeID: AccessibilityGeometry]
    /// The window's keyboard focus when that element published a node (AB-J).
    public var focused: AccessibilityNodeID?

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
}
