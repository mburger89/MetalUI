import Testing
import MetalUICore
import MetalUIPlatform
@testable import MetalUISDL
import CAccessKit

// Hierarchical lists, lane 5 (ruling `OG-F`, design section 4): an outline `List` is AccessKit's `TREE`, its rows
// `TREE_ITEM`s with `level` (1 for a root, ARIA's) and `expanded`, `EXPAND` and `COLLAPSE` routed to the same handlers
// as an accessibility press, and each row nested under its REALISED parent row (a row whose parent is scrolled out hangs
// under the tree). A flat list keeps `TABLE` and `ROW`. Names are read from AccessKit's own header
// (`accesskit-c` 0.23: `ACCESSKIT_ROLE_TREE`, `ACCESSKIT_ROLE_TREE_ITEM`, `accesskit_node_set_level`,
// `accesskit_node_set_expanded`, `ACCESSKIT_ACTION_EXPAND`, `ACCESSKIT_ACTION_COLLAPSE`), and each assertion below reads the
// `accesskit_node` AccessKit is handed.

private func nid(_ name: String) -> AccessibilityNodeID { AccessibilityNodeID(name) }

private func withCNode<T>(_ node: AccessKitSnapshot.Node, _ body: (OpaquePointer) -> T) -> T {
    let c = AccessKitAdapter.cNode(node)
    defer { accesskit_node_free(c) }
    return body(c)
}

/// The tree MetalUI publishes for the probe's outline with A open: the list; each row with its content under it, a group
/// row's content inside the cell after the triangle; the rows flat under the list in order, A/B and A/C disclosed by A, A/B/D
/// (whose parent A/B is NOT realised in this window) disclosed by nothing.
private func outlineTree(listIsOutline: Bool = true, actions: AccessibilityActions = [.expand]) -> AccessibilityTree {
    func text(_ value: String) -> AccessibilityNode { AccessibilityNode(role: .staticText, value: value) }
    var nodes: [AccessibilityNodeID: AccessibilityNode] = [:]
    nodes[nid("list")] = AccessibilityNode(role: .table, children: [nid("A"), nid("A/B"), nid("A/B/D"), nid("Z")],
                                           rowCount: 4, isOutline: listIsOutline)
    nodes[nid("A")] = AccessibilityNode(role: .row, children: [nid("A.cell")], rowIndex: 0, outlineLevel: 0, isExpanded: true)
    nodes[nid("A.cell")] = AccessibilityNode(role: .cell, children: [nid("A.triangle"), nid("A.text")])
    nodes[nid("A.triangle")] = AccessibilityNode(role: .disclosureTriangle, value: "1", actions: [.press])
    nodes[nid("A.text")] = text("A")
    nodes[nid("A/B")] = AccessibilityNode(role: .row, children: [nid("A/B.cell")], rowIndex: 1, outlineLevel: 1,
                                          isExpanded: false, disclosedBy: nid("A"))
    nodes[nid("A/B").self]?.actions = actions
    nodes[nid("A/B.cell")] = AccessibilityNode(role: .cell, children: [nid("A/B.triangle"), nid("A/B.text")])
    nodes[nid("A/B.triangle")] = AccessibilityNode(role: .disclosureTriangle, value: "0", actions: [.press])
    nodes[nid("A/B.text")] = text("A/B")
    nodes[nid("A/B/D")] = AccessibilityNode(role: .row, children: [nid("A/B/D.text")], rowIndex: 2, outlineLevel: 2)
    nodes[nid("A/B/D.text")] = text("A/B/D")
    nodes[nid("Z")] = AccessibilityNode(role: .row, children: [nid("Z.text")], rowIndex: 3, outlineLevel: 0)
    nodes[nid("Z.text")] = text("Z")
    return AccessibilityTree(roots: [nid("list")], nodes: nodes, geometry: [:], focused: nil)
}

private func snapshot(_ tree: AccessibilityTree, ids: AccessKitIDs = AccessKitIDs()) -> [UInt64: AccessKitSnapshot.Node] {
    Dictionary(uniqueKeysWithValues: AccessKitSnapshot.translate(tree, title: "", scale: 1, ids: ids).nodes.map { ($0.id, $0) })
}

/// **OG-F.** The outline is a `TREE`; each row a `TREE_ITEM` carrying `level` (depth + 1) and, for a group, `expanded`; rows nest
/// under their realised parent row after the row's own content; a row with an unrealised parent hangs under the tree; the
/// triangle and the cell are not published (the tree item carries both). Mutations: the rows left flat under the tree; the
/// cell and triangle kept; the level not offset; a leaf given an `expanded`.
@Test func anOutlineListIsATreeOfTreeItemsNestedUnderTheirRealisedParents() throws {
    let ids = AccessKitIDs()
    let nodes = snapshot(outlineTree(), ids: ids)
    let n = { (name: String) -> UInt64 in ids.number(for: nid(name)) }
    let list = try #require(nodes[n("list")])
    #expect(list.role == .tree, "the list is a TREE")
    #expect(list.children == [n("A"), n("A/B/D"), n("Z")],
            "the tree's children are the rows with no realised parent, in order: \(list.children)")
    let a = try #require(nodes[n("A")]), b = try #require(nodes[n("A/B")]), d = try #require(nodes[n("A/B/D")])
    let z = try #require(nodes[n("Z")])
    #expect([a, b, d, z].allSatisfy { $0.role == .treeItem }, "every row is a TREE_ITEM")
    #expect([a, b, d, z].map(\.level) == [1, 2, 3, 1], "level is the depth + 1: \([a, b, d, z].map(\.level))")
    #expect([a.expanded, b.expanded, d.expanded, z.expanded] == [true, false, nil, nil], "expanded on groups only")
    #expect(a.children == [n("A.text"), n("A/B")], "A holds its text, then the row it discloses: \(a.children)")
    #expect(b.children == [n("A/B.text")], "A/B holds its text only (its child D is under the tree)")
    let published = Set(AccessKitSnapshot.translate(outlineTree(), title: "", scale: 1, ids: ids).nodes.map(\.id))
    #expect(!published.contains(n("A.cell")) && !published.contains(n("A.triangle")), "neither the cell nor the triangle is published")
    #expect(published.contains(n("A.text")), "the row's text is")
}

/// **OG-F.** A flat list keeps `TABLE` and `ROW`, with no level and no expanded. Mutation: a table always a tree.
@Test func aFlatListKeepsItsTableAndRows() throws {
    let tree = AccessibilityTree(
        roots: [nid("list")],
        nodes: [nid("list"): AccessibilityNode(role: .table, children: [nid("r")], rowCount: 1),
                nid("r"): AccessibilityNode(role: .row, rowIndex: 0)],
        geometry: [:], focused: nil)
    let nodes = AccessKitSnapshot.translate(tree, title: "", scale: 1, ids: AccessKitIDs()).nodes.dropFirst()
    #expect(nodes.map(\.role) == [.table, .row])
    #expect(nodes.allSatisfy { $0.level == nil && $0.expanded == nil })
}

/// **OG-F, AccessKit's own getters.** `TREE`, `TREE_ITEM`, the level, `expanded` (set for a group both ways, unset for a leaf)
/// and the `EXPAND`/`COLLAPSE` actions as the node advertises them. Mutations: `set_expanded` not called; `set_level` not
/// called; the actions not translated.
@Test func theTreeItemReachesAccessKitWithLevelExpandedAndActions() throws {
    let ids = AccessKitIDs()
    let nodes = snapshot(outlineTree(actions: [.expand]), ids: ids)
    let n = { (name: String) -> UInt64 in ids.number(for: nid(name)) }
    withCNode(try #require(nodes[n("list")])) { c in
        #expect(accesskit_node_role(c) == accesskit_role(ACCESSKIT_ROLE_TREE.rawValue))
    }
    withCNode(try #require(nodes[n("A")])) { c in
        #expect(accesskit_node_role(c) == accesskit_role(ACCESSKIT_ROLE_TREE_ITEM.rawValue))
        let level = accesskit_node_level(c)
        #expect(level.has_value && level.value == 1, "level 1")
        let expanded = accesskit_node_is_expanded(c)
        #expect(expanded.has_value && expanded.value, "expanded true")
        #expect(!accesskit_node_supports_action(c, accesskit_action(ACCESSKIT_ACTION_EXPAND.rawValue)), "an open group offers no EXPAND here")
    }
    withCNode(try #require(nodes[n("A/B")])) { c in
        let expanded = accesskit_node_is_expanded(c)
        #expect(expanded.has_value && !expanded.value, "a collapsed group: expanded false")
        #expect(accesskit_node_supports_action(c, accesskit_action(ACCESSKIT_ACTION_EXPAND.rawValue)), "EXPAND")
        #expect(!accesskit_node_supports_action(c, accesskit_action(ACCESSKIT_ACTION_COLLAPSE.rawValue)))
    }
    withCNode(try #require(nodes[n("A/B/D")])) { c in
        #expect(!accesskit_node_is_expanded(c).has_value, "a leaf has no expanded state")
        let level = accesskit_node_level(c)
        #expect(level.has_value && level.value == 3)
    }
    let collapsible = snapshot(outlineTree(actions: [.collapse]), ids: ids)
    withCNode(try #require(collapsible[n("A/B")])) { c in
        #expect(accesskit_node_supports_action(c, accesskit_action(ACCESSKIT_ACTION_COLLAPSE.rawValue)), "COLLAPSE")
    }
}

/// **OG-F.** AccessKit's `EXPAND` and `COLLAPSE` mean the window's expand and collapse requests for that row (the same
/// handler an `AXDisclosing` set reaches). Mutation: either action unmapped.
@Test func accessKitExpandAndCollapseMeanTheWindowsRequests() throws {
    let ids = AccessKitIDs()
    let number = ids.number(for: nid("row"))
    for (code, queued, request) in [
        (ACCESSKIT_ACTION_EXPAND, AccessKitSnapshot.Action.expand, AccessibilityRequest.expand(nid("row"))),
        (ACCESSKIT_ACTION_COLLAPSE, .collapse, .collapse(nid("row"))),
    ] {
        var raw = accesskit_action_request()
        raw.action = accesskit_action(code.rawValue)
        raw.target_node = number
        #expect(AccessKitAdapter.queued(from: raw) == .action(queued, number), "\(queued) is queued")
        #expect(AccessKitSnapshot.request(for: .action(queued, number), ids: ids) == request, "\(queued) maps to \(request)")
    }
}
