import Testing
import MetalUICore
import MetalUIPlatform
@testable import MetalUISDL
import CAccessKit

// Plan task 12 part 2, lane 1 (spec `2026-09-29-accessibility-design.md` §6,
// rulings `IX-AA`, `IX-AD`, `IX-AG`): the neutral tree's new fields through
// AccessKit. Every assertion reads the `accesskit_node` AccessKit is handed
// (`AccessKitAdapter.cNode`), through AccessKit's own getters, so a field set
// on the snapshot but never sent reddens too.

private func nid(_ name: String) -> AccessibilityNodeID { AccessibilityNodeID(name) }

/// Reads one node the way AccessKit will: `body` gets the C node, which is
/// freed afterwards.
private func withCNode<T>(_ node: AccessKitSnapshot.Node, _ body: (OpaquePointer) -> T) -> T {
    let c = AccessKitAdapter.cNode(node)
    defer { accesskit_node_free(c) }
    return body(c)
}

private func string(_ pointer: UnsafeMutablePointer<CChar>?) -> String? {
    guard let pointer else { return nil }
    defer { accesskit_string_free(pointer) }
    return String(cString: pointer)
}

/// The snapshot's nodes by label, the window dropped.
private func translate(_ tree: AccessibilityTree, ids: AccessKitIDs = AccessKitIDs())
    -> [AccessKitSnapshot.Node] {
    Array(AccessKitSnapshot.translate(tree, title: "", scale: 1, ids: ids).nodes.dropFirst())
}

/// The custom actions AccessKit holds for a node: `(id, description)`.
private func customActions(_ c: OpaquePointer) -> [(Int32, String?)] {
    guard let list = accesskit_node_custom_actions(c) else { return [] }
    defer { accesskit_custom_actions_free(list) }
    return (0..<list.pointee.length).map { index in
        let action = list.pointee.values[index]!
        return (accesskit_custom_action_id(action), string(accesskit_custom_action_description(action)))
    }
}

/// **1.5.** A hint is AccessKit's `description`, an identifier its
/// `author_id`, `.heading`/`.link` its `HEADING`/`LINK`, and custom actions are
/// pushed in order with their index as the id, `CUSTOM_ACTION` advertised.
/// Mutation M1e (the description not set) must redden it.
@Test func theAccessKitSnapshotCarriesHintIdentifierHeadingLinkAndCustomActions() throws {
    let tree = AccessibilityTree(
        roots: [nid("title"), nid("more"), nid("mail")],
        nodes: [
            nid("title"): AccessibilityNode(role: .heading, label: "Title", hint: "The page title",
                                            identifier: "page.title"),
            nid("more"): AccessibilityNode(role: .link, label: "More"),
            nid("mail"): AccessibilityNode(role: .button, label: "Mail", actions: [.press],
                                           customActions: ["Archive", "Delete"]),
        ],
        geometry: [:], focused: nil)
    let nodes = translate(tree)
    try #require(nodes.count == 3)
    let (title, more, mail) = (nodes[0], nodes[1], nodes[2])

    #expect(title.role == .heading && more.role == .link)
    #expect(AccessKitAdapter.role(.heading) == UInt8(ACCESSKIT_ROLE_HEADING.rawValue))
    #expect(AccessKitAdapter.role(.link) == UInt8(ACCESSKIT_ROLE_LINK.rawValue))
    withCNode(title) { c in
        #expect(accesskit_node_role(c) == accesskit_role(ACCESSKIT_ROLE_HEADING.rawValue))
        #expect(string(accesskit_node_description(c)) == "The page title", "the hint is the description")
        #expect(string(accesskit_node_author_id(c)) == "page.title", "the identifier is the author id")
        #expect(customActions(c).isEmpty)
        #expect(!accesskit_node_supports_action(c, accesskit_action(ACCESSKIT_ACTION_CUSTOM_ACTION.rawValue)))
    }
    withCNode(more) { c in
        #expect(accesskit_node_role(c) == accesskit_role(ACCESSKIT_ROLE_LINK.rawValue))
        #expect(string(accesskit_node_description(c)) == nil, "control: no hint, no description")
        #expect(string(accesskit_node_author_id(c)) == nil)
    }
    #expect(mail.actions == [.click, .customAction])
    withCNode(mail) { c in
        let actions = customActions(c)
        #expect(actions.map(\.0) == [0, 1], "each custom action's id is its index")
        #expect(actions.map(\.1) == ["Archive", "Delete"], "in published order")
        #expect(accesskit_node_supports_action(c, accesskit_action(ACCESSKIT_ACTION_CUSTOM_ACTION.rawValue)))
        #expect(accesskit_node_supports_action(c, accesskit_action(ACCESSKIT_ACTION_CLICK.rawValue)))
    }
}

/// **1.6.** A selectable row publishes `selected` false when not selected and
/// true when selected; a row of a list without `selection:` leaves it unset
/// (`IX-AA` item 2). Mutation M1f (`false` not set) must redden it.
@Test func aSelectableRowPublishesSelectedFalseToAccessKit() throws {
    let tree = AccessibilityTree(
        roots: [nid("table")],
        nodes: [
            nid("table"): AccessibilityNode(role: .table, children: [nid("off"), nid("on"), nid("plain")],
                                            rowCount: 3),
            nid("off"): AccessibilityNode(role: .row, label: "Off", rowIndex: 0, isSelectable: true),
            nid("on"): AccessibilityNode(role: .row, label: "On", isSelected: true, rowIndex: 1,
                                         isSelectable: true),
            nid("plain"): AccessibilityNode(role: .row, label: "Plain", rowIndex: 2),
        ],
        geometry: [:], focused: nil)
    let nodes = translate(tree)
    try #require(nodes.count == 4)
    func selected(_ node: AccessKitSnapshot.Node) -> accesskit_opt_bool {
        withCNode(node) { accesskit_node_is_selected($0) }
    }
    let off = selected(nodes[1]), on = selected(nodes[2]), plain = selected(nodes[3])
    #expect(off.has_value && !off.value, "selectable, not selected: false")
    #expect(on.has_value && on.value, "selected: true")
    #expect(!plain.has_value, "not selectable: unset")
}

/// **1.7.** AccessKit's `CUSTOM_ACTION` with `data.custom_action = 1` queues a
/// custom action at index 1, which means `.customAction(id, 1)`; one with no
/// data queues nothing. Mutation M1g (the index ignored, always 0) must redden it.
@Test func anAccessKitCustomActionMeansACustomActionRequest() throws {
    let ids = AccessKitIDs()
    let tree = AccessibilityTree(
        roots: [nid("mail")],
        nodes: [nid("mail"): AccessibilityNode(role: .button, label: "Mail", customActions: ["A", "B"])],
        geometry: [:], focused: nil)
    let number = try #require(translate(tree, ids: ids).first?.id)

    var request = accesskit_action_request()
    request.action = accesskit_action(ACCESSKIT_ACTION_CUSTOM_ACTION.rawValue)
    request.target_node = number
    request.data.has_value = true
    request.data.value.tag = ACCESSKIT_ACTION_DATA_CUSTOM_ACTION
    request.data.value.custom_action = 1
    let queued = try #require(AccessKitAdapter.queued(from: request))
    #expect(queued == .customAction(number, 1))
    #expect(AccessKitSnapshot.request(for: queued, ids: ids) == .customAction(nid("mail"), 1))

    request.data.has_value = false
    #expect(AccessKitAdapter.queued(from: request) == nil, "no data, no request")

    // Control: a click still queues and maps as before.
    var click = accesskit_action_request()
    click.action = accesskit_action(ACCESSKIT_ACTION_CLICK.rawValue)
    click.target_node = number
    #expect(AccessKitAdapter.queued(from: click) == .action(.click, number))
    #expect(AccessKitSnapshot.request(for: .action(.click, number), ids: ids) == .press(nid("mail")))
}

/// **1.8.** Every field of the neutral `AccessibilityNode` has an arm in
/// AccessKit (`IX-AD`): the table below must name exactly the fields a
/// `Mirror` of the node finds, and each arm is asserted on the C node built
/// from one node with every field set. Mutation M1h (drop the
/// `customActions` arm) must redden it.
@Test func everyAccessibilityNodeFieldHasAnAccessKitArm() throws {
    let full = AccessibilityNode(
        role: .row, label: "L", value: "V", isSelected: false, isEnabled: false, isFocusable: true,
        actions: [.press, .increment, .decrement], children: [nid("kid")], rowCount: 7, rowIndex: 3,
        hint: "H", identifier: "I", customActions: ["C"], isSelectable: true)
    let tree = AccessibilityTree(roots: [nid("full")],
                                 nodes: [nid("full"): full, nid("kid"): AccessibilityNode(role: .staticText)],
                                 geometry: [:], focused: nil)
    let ids = AccessKitIDs()
    let translated = translate(tree, ids: ids)
    try #require(translated.count == 2)
    let node = translated[0]
    let kid = translated[1].id

    typealias Arm = (OpaquePointer) -> Bool
    let arms: [String: Arm] = [
        "role": { accesskit_node_role($0) == accesskit_role(ACCESSKIT_ROLE_ROW.rawValue) },
        "label": { string(accesskit_node_label($0)) == "L" },
        "value": { string(accesskit_node_value($0)) == "V" },
        "isSelected": { let s = accesskit_node_is_selected($0); return s.has_value && !s.value },
        "isEnabled": { accesskit_node_is_disabled($0) },
        "isFocusable": { accesskit_node_supports_action($0, accesskit_action(ACCESSKIT_ACTION_FOCUS.rawValue)) },
        "actions": { c in
            [ACCESSKIT_ACTION_CLICK, ACCESSKIT_ACTION_INCREMENT, ACCESSKIT_ACTION_DECREMENT]
                .allSatisfy { accesskit_node_supports_action(c, accesskit_action($0.rawValue)) }
        },
        "children": { c in
            let list = accesskit_node_children(c)
            return list.length == 1 && list.values[0] == kid
        },
        "rowCount": { let n = accesskit_node_row_count($0); return n.has_value && n.value == 7 },
        "rowIndex": { let n = accesskit_node_row_index($0); return n.has_value && n.value == 3 },
        "hint": { string(accesskit_node_description($0)) == "H" },
        "identifier": { string(accesskit_node_author_id($0)) == "I" },
        "customActions": { c in customActions(c).map(\.1) == ["C"] },
        "isSelectable": { c in accesskit_node_is_selected(c).has_value },
    ]
    let fields = Set(Mirror(reflecting: full).children.compactMap(\.label))
    #expect(fields.count == 14, "the neutral node's field count: \(fields.sorted())")
    #expect(Set(arms.keys) == fields, "one arm per field — missing \(fields.subtracting(arms.keys).sorted())")
    withCNode(node) { c in
        for (field, arm) in arms.sorted(by: { $0.key < $1.key }) { #expect(arm(c), "\(field)'s arm") }
    }
}
