import Testing
import MetalUICore
import MetalUIPlatform
@testable import MetalUISDL
import CAccessKit

// A split view's dividers (ruling `HS-K`, probe `docs/probes/swiftui-split-divider-ax.swift`): AccessKit's `SPLITTER` with its
// `orientation`, a numeric value (the size in points of the pane before the divider), `min_numeric_value` 0 and
// `max_numeric_value` the pair's total, and `SET_VALUE` (numeric action data) routed to the window's `.setValue` request;
// no increment or decrement. Each assertion reads the `accesskit_node` AccessKit is handed.

private func nid(_ name: String) -> AccessibilityNodeID { AccessibilityNodeID(name) }

private func withCNode<T>(_ node: AccessKitSnapshot.Node, _ body: (OpaquePointer) -> T) -> T {
    let c = AccessKitAdapter.cNode(node)
    defer { accesskit_node_free(c) }
    return body(c)
}

/// Record 310's nest, as the window publishes it: an outer vertical divider, an inner horizontal one and the innermost vertical
/// one, each with its own pair total and value.
private func nestedTree() -> AccessibilityTree {
    var nodes: [AccessibilityNodeID: AccessibilityNode] = [:]
    nodes[nid("outer")] = AccessibilityNode(role: .splitter, value: "320", actions: [.setValue],
                                            identifier: "editor.0", numericRange: 0...639, orientation: .vertical)
    nodes[nid("inner")] = AccessibilityNode(role: .splitter, value: "150", actions: [.setValue],
                                            numericRange: 0...479, orientation: .horizontal)
    nodes[nid("innermost")] = AccessibilityNode(role: .splitter, value: "100.5", actions: [.setValue],
                                                numericRange: 0...300, orientation: .vertical)
    nodes[nid("locked")] = AccessibilityNode(role: .splitter, value: "100", isEnabled: false,
                                             numericRange: 0...200, orientation: .vertical)
    return AccessibilityTree(roots: [nid("outer"), nid("inner"), nid("innermost"), nid("locked")], nodes: nodes,
                             geometry: [:], focused: nil)
}

private func snapshot(_ tree: AccessibilityTree, ids: AccessKitIDs) -> [UInt64: AccessKitSnapshot.Node] {
    Dictionary(uniqueKeysWithValues: AccessKitSnapshot.translate(tree, title: "", scale: 1, ids: ids).nodes.map { ($0.id, $0) })
}

/// **HS-K.** A divider is a `SPLITTER` with its orientation, numeric value, range 0...(pair total) and `SET_VALUE`, and no
/// `INCREMENT`/`DECREMENT`; each of several nested dividers keeps its own number, value and range; an immovable one is
/// disabled and offers no `SET_VALUE`; the identifier is the `author_id`. Mutations: the role left as a generic container; the
/// range omitted; orientation swapped; `SET_VALUE` not advertised; every divider given the first one's range.
@Test func aDividerIsASplitterWithOrientationValueRangeAndSetValue() throws {
    let ids = AccessKitIDs()
    let nodes = snapshot(nestedTree(), ids: ids)
    let n = { (name: String) -> UInt64 in ids.number(for: nid(name)) }
    #expect(Set(["outer", "inner", "innermost", "locked"].map(n)).count == 4, "distinct numbers")
    let expected: [(String, UInt8, Double, Double)] = [
        ("outer", UInt8(ACCESSKIT_ORIENTATION_VERTICAL.rawValue), 320, 639),
        ("inner", UInt8(ACCESSKIT_ORIENTATION_HORIZONTAL.rawValue), 150, 479),
        ("innermost", UInt8(ACCESSKIT_ORIENTATION_VERTICAL.rawValue), 100.5, 300)
    ]
    for (name, orientation, value, max) in expected {
        let node = try #require(nodes[n(name)])
        #expect(node.role == AccessKitSnapshot.Role.splitter, "\(name)")
        withCNode(node) { c in
            #expect(accesskit_node_role(c) == accesskit_role(ACCESSKIT_ROLE_SPLITTER.rawValue), "\(name): SPLITTER")
            let o = accesskit_node_orientation(c)
            #expect(o.has_value && o.value == orientation, "\(name): orientation")
            let v = accesskit_node_numeric_value(c), lo = accesskit_node_min_numeric_value(c), hi = accesskit_node_max_numeric_value(c)
            #expect(v.has_value && v.value == value, "\(name): value")
            #expect(lo.has_value && lo.value == 0 && hi.has_value && hi.value == max, "\(name): 0...\(max)")
            #expect(accesskit_node_supports_action(c, accesskit_action(ACCESSKIT_ACTION_SET_VALUE.rawValue)), "\(name): SET_VALUE")
            #expect(!accesskit_node_supports_action(c, accesskit_action(ACCESSKIT_ACTION_INCREMENT.rawValue)), "\(name): no INCREMENT")
            #expect(!accesskit_node_supports_action(c, accesskit_action(ACCESSKIT_ACTION_DECREMENT.rawValue)), "\(name): no DECREMENT")
            #expect(!accesskit_node_is_disabled(c))
        }
    }
    withCNode(try #require(nodes[n("outer")])) { c in
        let id = accesskit_node_author_id(c)
        #expect(id.map { String(cString: $0) } == "editor.0")
        accesskit_string_free(id)
    }
    let locked = try #require(nodes[n("locked")])
    #expect(locked.isDisabled && !locked.actions.contains(.setValue))
    withCNode(locked) { c in
        #expect(accesskit_node_is_disabled(c))
        #expect(!accesskit_node_supports_action(c, accesskit_action(ACCESSKIT_ACTION_SET_VALUE.rawValue)))
    }
}

/// **HS-K.** AccessKit's `SET_VALUE` carries its number as numeric action data and means the window's `.setValue` for that
/// divider; one without numeric data (or with a string) names no action. Mutations: the data ignored (0 sent); the string form
/// accepted; the action unmapped.
@Test func accessKitSetValueMeansTheWindowsSetValueRequest() throws {
    let ids = AccessKitIDs()
    let number = ids.number(for: nid("outer"))
    var raw = accesskit_action_request()
    raw.action = accesskit_action(ACCESSKIT_ACTION_SET_VALUE.rawValue)
    raw.target_node = number
    #expect(AccessKitAdapter.queued(from: raw) == nil, "no data, no action")
    raw.data.has_value = true
    raw.data.value.tag = ACCESSKIT_ACTION_DATA_NUMERIC_VALUE
    raw.data.value.numeric_value = 142.5
    let queued = try #require(AccessKitAdapter.queued(from: raw))
    #expect(queued == .setValue(number, 142.5), "\(queued)")
    #expect(AccessKitSnapshot.request(for: queued, ids: ids) == .setValue(nid("outer"), 142.5))
    raw.data.value.tag = ACCESSKIT_ACTION_DATA_VALUE
    #expect(AccessKitAdapter.queued(from: raw) == nil, "a string value is not a number")
}
