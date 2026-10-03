import Testing
import MetalUICore
import MetalUIPlatform
@testable import MetalUISDL
import CAccessKit

// Menus, popovers and tooltips, lane 1, tests S1.1–S1.2 (rulings `MN-C` item
// 3, `MN-G` item 2, `MN-R`; spec §6.1). Every assertion reads the
// `accesskit_node` AccessKit is handed (`AccessKitAdapter.cNode`), through
// AccessKit's own getters, so a field set on the snapshot but never sent
// reddens too. C enum raw values are converted explicitly (Windows `Int32`).

private func nid(_ name: String) -> AccessibilityNodeID { AccessibilityNodeID(name) }

private func withCNode<T>(_ node: AccessKitSnapshot.Node, _ body: (OpaquePointer) -> T) -> T {
    let c = AccessKitAdapter.cNode(node)
    defer { accesskit_node_free(c) }
    return body(c)
}


/// **S1.1** (`MN-R`, `MN-G` item 2). The menu roles reach AccessKit as `MENU`,
/// `MENU_ITEM`, `MENU_ITEM_CHECK_BOX` (toggled from its `"1"`), a menu button
/// as `BUTTON` with a menu popup, a popover as a non-modal `DIALOG`; a node
/// advertising `.showMenu` supports `SHOW_CONTEXT_MENU`, and an incoming
/// `SHOW_CONTEXT_MENU` means `.showMenu(id)`. Mutation: drop
/// `SHOW_CONTEXT_MENU`.
@Test func theAccessKitBridgeMapsTheMenuRolesAndShowContextMenu() throws {
    let tree = AccessibilityTree(
        roots: [nid("menu"), nid("button"), nid("popover")],
        nodes: [
            nid("menu"): AccessibilityNode(role: .menu, children: [nid("item"), nid("check")]),
            nid("item"): AccessibilityNode(role: .menuItem, label: "Copy", actions: [.press]),
            nid("check"): AccessibilityNode(role: .menuItemCheckBox, label: "Flag", value: "1", actions: [.press]),
            nid("button"): AccessibilityNode(role: .menuButton, label: "Actions", actions: [.press, .showMenu]),
            nid("popover"): AccessibilityNode(role: .popover),
        ],
        geometry: [:], focused: nil)
    let ids = AccessKitIDs()
    let nodes = Array(AccessKitSnapshot.translate(tree, title: "", scale: 1, ids: ids).nodes.dropFirst())
    try #require(nodes.count == 5)
    let byLabel = { (label: String?) in nodes.first { $0.label == label } }
    let menu = try #require(nodes.first { $0.children.count == 2 })
    let item = try #require(byLabel("Copy")), check = try #require(byLabel("Flag"))
    let button = try #require(byLabel("Actions"))
    let popover = try #require(nodes.first { $0.label == nil && $0.children.isEmpty })

    #expect(withCNode(menu) { accesskit_node_role($0) } == accesskit_role(ACCESSKIT_ROLE_MENU.rawValue))
    #expect(withCNode(item) { accesskit_node_role($0) } == accesskit_role(ACCESSKIT_ROLE_MENU_ITEM.rawValue))
    withCNode(check) { c in
        #expect(accesskit_node_role(c) == accesskit_role(ACCESSKIT_ROLE_MENU_ITEM_CHECK_BOX.rawValue))
        let toggled = accesskit_node_toggled(c)
        #expect(toggled.has_value && toggled.value == accesskit_toggled(ACCESSKIT_TOGGLED_TRUE.rawValue),
                "the check item is toggled on")
    }
    withCNode(button) { c in
        #expect(accesskit_node_role(c) == accesskit_role(ACCESSKIT_ROLE_BUTTON.rawValue))
        let popup = accesskit_node_has_popup(c)
        #expect(popup.has_value && popup.value == accesskit_has_popup(ACCESSKIT_HAS_POPUP_MENU.rawValue),
                "a menu button has a menu popup")
        #expect(accesskit_node_supports_action(c, accesskit_action(ACCESSKIT_ACTION_SHOW_CONTEXT_MENU.rawValue)),
                "show-menu is advertised")
    }
    withCNode(popover) { c in
        #expect(accesskit_node_role(c) == accesskit_role(ACCESSKIT_ROLE_DIALOG.rawValue))
        #expect(!accesskit_node_is_modal(c), "not modal (MN-O)")
    }
    #expect(!withCNode(item) { accesskit_node_supports_action($0, accesskit_action(ACCESSKIT_ACTION_SHOW_CONTEXT_MENU.rawValue)) },
            "a node without the action does not advertise it")

    var request = accesskit_action_request()
    request.action = accesskit_action(ACCESSKIT_ACTION_SHOW_CONTEXT_MENU.rawValue)
    request.target_node = button.id
    let queued = try #require(AccessKitAdapter.queued(from: request), "SHOW_CONTEXT_MENU queues")
    #expect(AccessKitSnapshot.request(for: queued, ids: ids) == .showMenu(nid("button")))
}

/// **S1.2** (`MN-C` item 3). An SDL window declines to present a menu: SDL3
/// has no menu API, so `Window` draws it. Mutation: answer `true`.
@MainActor
@Test func anSDLWindowDeclinesToPresentAMenu() throws {
    #if os(macOS)
    armMainRunLoopExitCheck()
    #endif
    let platform = try SDLPlatform(hiddenWindows: true)
    let window = try platform.openSDLWindow(title: "MetalUI menu test",
                                            size: Size(width: Pixels(200), height: Pixels(100)))
    let menu = PlatformMenu(token: 1, items: [PlatformMenuItem(id: 1, kind: .action, title: "Copy")])
    #expect(!window.presentMenu(menu, at: Point(x: Pixels(10), y: Pixels(10))))
    withExtendedLifetime(platform) {}
}
