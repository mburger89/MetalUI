import MetalUIPlatform

// The test harness's menu read-back (ruling `HT-H` item 4; spec §3.2 item 5):
// one `package` member, in a file of its own, that `MetalUITesting`'s
// `MenuEvaluation` reads and an app cannot spell. It numbers content through
// **`MenuSession.number`** — the window's own numbering, so an id here is the
// id a presented menu gives the same item (a copy would drift). Nothing here
// changes behaviour. Merge debt (spec §9 item 2a): a change to
// `MenuSession.number`'s signature or `MenuContent`'s SPI is re-pointed here.

extension MenuContent {
    /// This content evaluated as a window evaluates a menu at its open — every
    /// item disabled when `isEnabled` is false — into items numbered
    /// depth-first from 1, and each enabled command item's action by id. A
    /// disabled item has no entry in `actions`.
    @MainActor
    package func testingEvaluateMenu(isEnabled: Bool) -> (items: [PlatformMenuItem],
                                                          actions: [Int: @MainActor () -> Void]) {
        var next = 1
        var recorded: [Int: MenuItemAction] = [:]
        var toggles = Set<Int>()
        let items = MenuSession.number(menuNodes(isEnabled: isEnabled), declaringID: testingMenuRoot,
                                       enabled: isEnabled, next: &next, actions: &recorded, toggles: &toggles)
        var actions: [Int: @MainActor () -> Void] = [:]
        for (id, action) in recorded where action.isEnabled { actions[id] = action.run }
        return (items, actions)
    }
}

/// The synthetic declaring element of a menu evaluated outside any window.
private let testingMenuRoot = GlobalElementID(component: .named(ElementID("$menu-evaluation")), parent: nil)
