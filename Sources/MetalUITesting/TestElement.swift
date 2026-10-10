import MetalUI

/// One accessibility element of a ``TestWindow``, as the window last
/// published it (ruling `HT-G` item 1): a **value snapshot** of one node of
/// the `AccessibilityTree` — the model XCUITest queries and the tree both
/// platform bridges hand VoiceOver and AccessKit. A later frame does not
/// update it; query again after an action.
///
/// Geometry is window content space in logical points, top-left origin, the
/// scroll offset applied. **Not `Sendable`** (ruling `HT-R` item 2): its `id`
/// wraps an `AnyHashable`; every harness API is `@MainActor`, so nothing
/// sends one. MetalUI-only (`HT-B`).
public struct TestElement: Equatable {
    /// The node's identity in the published tree — stable across frames while
    /// the element keeps its structural identity.
    public var id: AccessibilityNodeID
    /// The node's role.
    public var role: AccessibilityRole
    /// The accessible name, if any. A `Text`'s string is its `value`, not its
    /// label (``TestWindow/element(label:)`` matches both for a static text).
    public var label: String?
    /// The accessible value, if any: a `Text`'s string, a field's text, a
    /// toggle's `"1"`/`"0"`.
    public var value: String?
    /// The declared `.accessibilityIdentifier`, if any.
    public var identifier: String?
    /// The declared `.accessibilityHint` or `.help`, if any.
    public var hint: String?
    /// The element's whole rect, not clipped — a row scrolled out of view
    /// keeps its full rect here.
    public var frame: Bounds<Pixels>
    /// ``frame`` cut by the clip where the element drew: what a click can
    /// reach. Zero-area when scrolled fully out of its viewport.
    public var visibleFrame: Bounds<Pixels>
    /// Whether the element is enabled.
    public var isEnabled: Bool
    /// Whether the element is selected.
    public var isSelected: Bool
    /// Whether the element has the window's keyboard focus.
    public var isFocused: Bool
    /// The element's children's ids, in published order.
    public var children: [AccessibilityNodeID]

    /// A snapshot of `id`'s node in `tree`; `nil` when the tree has no such
    /// node.
    init?(_ id: AccessibilityNodeID, in tree: AccessibilityTree) {
        guard let node = tree.nodes[id] else { return nil }
        let zero = Bounds(origin: Point(x: Pixels(0), y: Pixels(0)), size: Size(width: Pixels(0), height: Pixels(0)))
        let geometry = tree.geometry[id]
        self.id = id
        self.role = node.role
        self.label = node.label
        self.value = node.value
        self.identifier = node.identifier
        self.hint = node.hint
        self.frame = geometry?.frame ?? zero
        self.visibleFrame = geometry?.visibleFrame ?? zero
        self.isEnabled = node.isEnabled
        self.isSelected = node.isSelected
        self.isFocused = tree.focused == id
        self.children = node.children
    }

    /// How the element reads in an error: its role and its first non-empty
    /// identifier, label or value.
    var summary: String {
        let name = [identifier, label, value].compactMap { $0 }.first { !$0.isEmpty }
        return name.map { "\(role) \"\($0)\"" } ?? "\(role)"
    }
}
