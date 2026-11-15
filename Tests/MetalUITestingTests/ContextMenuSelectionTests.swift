@testable import MetalUI
import MetalUIScene
import MetalUITesting
import Foundation
import Testing

// Lane 6 of the hierarchical lists: `.contextMenu(forSelectionType:menu:primaryAction:)` and the click count (ruling
// `OG-N`, record 317; probe `docs/probes/swiftui-outline.swift` arms `P-M1`..`P-M4`, `P-C1`).
//
// Every arm runs over the three list forms: the content form (`List { ForEach { DisclosureGroup } }`), the outline data form
// (`List(_:children:selection:)`) and the flat data form (`List(_:selection:rowHeight:)`). The tree is A (A/B, A/C), Z, M (M/N)
// with every group collapsed, so the rows are A, Z, M.

private struct CNode: Identifiable {
    var id: String
    var kids: [CNode]?
}

private func C(_ id: String, _ kids: [CNode]? = nil) -> CNode { CNode(id: id, kids: kids) }
private func cTree() -> [CNode] { [C("A", [C("A/B"), C("A/C")]), C("Z"), C("M", [C("M/N")])] }

private enum CForm: String, CaseIterable { case content, outline, flat }

@MainActor private final class CModel {
    var open: Set<String> = []
    var selection: String?
    var multi: Set<String> = []
    var selectionWrites = 0
    var menus: [[String]] = []
    var primary: [[String]] = []

    var selectionBinding: Binding<String?> {
        Binding(get: { self.selection }, set: { self.selection = $0; self.selectionWrites += 1 })
    }
    var multiBinding: Binding<Set<String>> {
        Binding(get: { self.multi }, set: { self.multi = $0; self.selectionWrites += 1 })
    }
    func binding(_ id: String) -> Binding<Bool> {
        Binding(get: { self.open.contains(id) }, set: { value in
            if value { self.open.insert(id) } else { self.open.remove(id) }
        })
    }
}

private struct CRow: Component {
    let node: CNode
    let model: CModel
    @ElementBuilder var content: some ElementGroup {
        if let kids = node.kids {
            DisclosureGroup(isExpanded: model.binding(node.id)) {
                ForEach(kids) { CRow(node: $0, model: model) }
            } label: { ProposalText(node.id) }
        } else {
            ProposalText(node.id)
        }
    }
}

private struct FlatItem: Identifiable { let id: String }

/// What the modifier is given: the action, or none, and the identifier type.
private enum CWith { case menuAndAction, menuOnly, mismatched, noSelection }

@MainActor private func cWindow(_ form: CForm, _ model: CModel, multi: Bool = false, with: CWith = .menuAndAction,
                                over: Bool = false) throws -> TestWindow {
    @MainActor func menu(_ ids: Set<String>) -> some MenuContent {
        let _ = model.menus.append(ids.sorted())
        return Button("Act") {}
    }
    @MainActor func menuInt(_ ids: Set<Int>) -> some MenuContent {
        let _ = model.menus.append(ids.map(String.init).sorted())
        return Button("Act") {}
    }
    var action: (@MainActor (Set<String>) -> Void)?
    if with != .menuOnly { action = { (ids: Set<String>) in model.primary.append(ids.sorted()) } }
    let nodes = cTree()
    let window: TestWindow
    switch (form, multi) {
    case (.content, false):
        window = try harnessWindow(size: sz(300, 400)) {
            ProposalScrollView {
                if with == .mismatched {
                    List(selection: model.selectionBinding) { ForEach(nodes) { CRow(node: $0, model: model) } }
                        .contextMenu(forSelectionType: Int.self, menu: menuInt, primaryAction: { _ in model.primary.append(["int"]) })
                } else {
                    List(selection: model.selectionBinding) { ForEach(nodes) { CRow(node: $0, model: model) } }
                        .contextMenu(forSelectionType: String.self, menu: menu, primaryAction: action)
                }
            }
        }
    case (.content, true):
        window = try harnessWindow(size: sz(300, 400)) {
            ProposalScrollView {
                List(selection: model.multiBinding) { ForEach(nodes) { CRow(node: $0, model: model) } }
                    .contextMenu(forSelectionType: String.self, menu: menu, primaryAction: action)
            }
        }
    case (.outline, false):
        window = try harnessWindow(size: sz(300, 400)) {
            ProposalScrollView {
                if with == .mismatched {
                    List(nodes, children: \.kids, selection: model.selectionBinding) { ProposalText($0.id) }
                        .contextMenu(forSelectionType: Int.self, menu: menuInt, primaryAction: { _ in model.primary.append(["int"]) })
                } else {
                    List(nodes, children: \.kids, selection: model.selectionBinding) { ProposalText($0.id) }
                        .contextMenu(forSelectionType: String.self, menu: menu, primaryAction: action)
                }
            }
        }
    case (.outline, true):
        window = try harnessWindow(size: sz(300, 400)) {
            ProposalScrollView {
                List(nodes, children: \.kids, selection: model.multiBinding) { ProposalText($0.id) }
                    .contextMenu(forSelectionType: String.self, menu: menu, primaryAction: action)
            }
        }
    case (.flat, false):
        let items = ["A", "Z", "M"].map(FlatItem.init)
        window = try harnessWindow(size: sz(300, 400)) {
            ScrollView(.vertical) {
                if with == .mismatched {
                    List(items, selection: model.selectionBinding, rowHeight: Pixels(32)) { ProposalText($0.id) }
                        .contextMenu(forSelectionType: Int.self, menu: menuInt, primaryAction: { _ in model.primary.append(["int"]) })
                } else if with == .noSelection {
                    List(items, rowHeight: Pixels(32)) { ProposalText($0.id) }
                        .contextMenu(forSelectionType: String.self, menu: menu, primaryAction: action)
                } else {
                    List(items, selection: model.selectionBinding, rowHeight: Pixels(32)) { ProposalText($0.id) }
                        .contextMenu(forSelectionType: String.self, menu: menu, primaryAction: action)
                }
            }.frame(width: Pixels(300), height: Pixels(400))
        }
    case (.flat, true):
        let items = ["A", "Z", "M"].map(FlatItem.init)
        window = try harnessWindow(size: sz(300, 400)) {
            ScrollView(.vertical) {
                List(items, selection: model.multiBinding, rowHeight: Pixels(32)) { ProposalText($0.id) }
                    .contextMenu(forSelectionType: String.self, menu: menu, primaryAction: action)
            }.frame(width: Pixels(300), height: Pixels(400))
        }
    }
    for _ in 0..<4 { window.tick() }
    return window
}

@MainActor private func rowPoint(_ window: TestWindow, _ name: String) -> Point<Pixels> {
    guard let element = (try? window.elements(role: .staticText))?.first(where: { $0.value == name }) else {
        Issue.record("no row \(name)")
        return pt(0, 0)
    }
    return pt(200, (element.frame.origin.y.value + element.frame.size.height.value / 2))
}

@MainActor private func settle(_ window: TestWindow) { for _ in 0..<3 { window.tick() } }

@MainActor private func visibleRows(_ window: TestWindow) -> [String] {
    ((try? window.elements(role: .staticText)) ?? [])
        .sorted { $0.frame.origin.y.value < $1.frame.origin.y.value }.compactMap(\.value)
}

@MainActor private func selectByClick(_ window: TestWindow, _ name: String, _ model: CModel) {
    window.click(at: rowPoint(window, name))
    settle(window)
    model.selectionWrites = 0
}

@MainActor private func presented(_ window: TestWindow) -> Int { window.platformWindow.presentedMenus.count }

// MARK: - the menu (P-M1, P-M2)

/// **P-M1.** A secondary press on a row outside the selection builds the menu with `{row}` and does not change the
/// selection; on the selected row, with the selection (`P-M1b`). Mutations: the row set always the selection; the set always
/// `{row}` (the selected-row half fails in the multi tests below); a press that selects the row.
@Test @MainActor func aSecondaryPressOnARowOpensItsMenuWithoutChangingTheSelection() throws {
    for form in CForm.allCases {
        let model = CModel()
        let window = try cWindow(form, model)
        selectByClick(window, "Z", model)
        model.menus = []
        window.rightClick(at: rowPoint(window, "A"))
        #expect(model.menus == [["A"]], "\(form): M1: an unselected row gets itself: \(model.menus)")
        #expect(presented(window) == 1, "\(form): M1: the menu opened")
        #expect(model.selection == "Z" && model.selectionWrites == 0, "\(form): M1: the selection is untouched")
        try window.dismissMenu()
        model.menus = []
        window.rightClick(at: rowPoint(window, "Z"))
        #expect(model.menus == [["Z"]], "\(form): M1b: the selected row gets the selection: \(model.menus)")
        #expect(model.selection == "Z" && model.selectionWrites == 0, "\(form): M1b")
        withExtendedLifetime(window) {}
    }
}

/// A multi list: a row inside the selection gets the whole selection, one outside gets itself.
@Test @MainActor func aSecondaryPressInsideAMultiSelectionGetsTheWholeSelection() throws {
    for form in CForm.allCases {
        let model = CModel()
        let window = try cWindow(form, model, multi: true)
        model.multi = ["A", "Z"]
        settle(window)
        window.rightClick(at: rowPoint(window, "Z"))
        #expect(model.menus == [["A", "Z"]], "\(form): inside: \(model.menus)")
        try window.dismissMenu()
        model.menus = []
        window.rightClick(at: rowPoint(window, "M"))
        #expect(model.menus == [["M"]], "\(form): outside: \(model.menus)")
        #expect(model.multi == ["A", "Z"] && model.selectionWrites == 0, "\(form): the selection is untouched")
        withExtendedLifetime(window) {}
    }
}

/// **P-M2.** On the list's empty space the closure gets `{}` and the menu still opens. The content forms have such space
/// (their first row's 10 point inset); a flat data list is sized to its rows, so it has none to press (record 317).
/// Mutation: the list's own region carrying no menu.
@Test @MainActor func aSecondaryPressOnEmptySpaceBuildsTheMenuWithAnEmptySet() throws {
    for form in [CForm.content, .outline] {
        let model = CModel()
        let window = try cWindow(form, model)
        selectByClick(window, "Z", model)
        model.menus = []
        window.rightClick(at: pt(200, 4))
        #expect(model.menus == [[]], "\(form): M2: \(model.menus)")
        #expect(presented(window) == 1, "\(form): M2: a menu opened")
        #expect(model.selection == "Z" && model.selectionWrites == 0, "\(form): M2: the selection is untouched")
        withExtendedLifetime(window) {}
    }
}

/// A modifier over a list's proposal content reaches the list through the environment.
@Test @MainActor func theProposalReceiverReachesAListBelowIt() throws {
    let model = CModel()
    let nodes = cTree()
    let window = try harnessWindow(size: sz(300, 400)) {
        ProposalScrollView {
            List(selection: model.selectionBinding) { ForEach(nodes) { CRow(node: $0, model: model) } }
        }
        .contextMenu(forSelectionType: String.self, menu: { (ids: Set<String>) in
            let _ = model.menus.append(ids.sorted())
            return Button("Act") {}
        }, primaryAction: { model.primary.append($0.sorted()) })
    }
    for _ in 0..<4 { window.tick() }
    window.rightClick(at: rowPoint(window, "A"))
    #expect(model.menus == [["A"]])
    window.doubleClick(at: rowPoint(window, "Z"))
    #expect(model.primary == [["Z"]])
    withExtendedLifetime(window) {}
}

// MARK: - the primary action (P-M3, P-M4, P-C1)

/// **P-M3, P-M3b.** A double-click selects on the first click and runs the action once with `{row}` on the second; a group row
/// does not toggle. Mutations: the action on every click (the single click test); the action with the selection instead of
/// `{row}`; the action firing on the first click of a double-click.
@Test @MainActor func aDoubleClickSelectsTheRowAndRunsThePrimaryActionOnce() throws {
    for form in CForm.allCases {
        let model = CModel()
        let window = try cWindow(form, model)
        window.doubleClick(at: rowPoint(window, "Z"))
        settle(window)
        #expect(model.selection == "Z" && model.primary == [["Z"]], "\(form): M3: \(String(describing: model.selection)) \(model.primary)")
        window.doubleClick(at: rowPoint(window, "A"))
        settle(window)
        #expect(model.selection == "A" && model.primary == [["Z"], ["A"]], "\(form): M3b: \(model.primary)")
        #expect(visibleRows(window) == ["A", "Z", "M"], "\(form): M3b: the group did not toggle: \(visibleRows(window))")
        withExtendedLifetime(window) {}
    }
}

/// A single click selects and runs no action; a second, separate single click neither.
@Test @MainActor func aSingleClickNeverRunsThePrimaryAction() throws {
    for form in CForm.allCases {
        let model = CModel()
        let window = try cWindow(form, model)
        window.click(at: rowPoint(window, "Z"))
        window.click(at: rowPoint(window, "A"))
        settle(window)
        #expect(model.selection == "A" && model.primary.isEmpty, "\(form): \(model.primary)")
        withExtendedLifetime(window) {}
    }
}

/// **P-C1.** With no `primaryAction`, a double-click on a group selects it and toggles nothing.
@Test @MainActor func withoutAPrimaryActionADoubleClickDoesNothingMore() throws {
    for form in CForm.allCases {
        let model = CModel()
        let window = try cWindow(form, model, with: .menuOnly)
        window.doubleClick(at: rowPoint(window, "A"))
        settle(window)
        #expect(model.selection == "A" && model.primary.isEmpty, "\(form)")
        #expect(visibleRows(window) == ["A", "Z", "M"], "\(form): no toggle: \(visibleRows(window))")
        window.rightClick(at: rowPoint(window, "Z"))
        #expect(model.menus == [["Z"]], "\(form): the menu still works")
        withExtendedLifetime(window) {}
    }
}

/// **P-M4, P-M4b.** Return on the focused list runs the action with the selection, a group's too, without toggling; with
/// nothing selected it runs nothing. Mutations: Return running with `{}`; Return toggling the group; Return with a modifier.
@Test @MainActor func returnRunsThePrimaryActionWithTheSelection() throws {
    for form in CForm.allCases {
        let model = CModel()
        let window = try cWindow(form, model)
        selectByClick(window, "Z", model)
        window.typeKey(.return)
        settle(window)
        #expect(model.primary == [["Z"]], "\(form): M4: \(model.primary)")
        window.typeKey(.return, modifierFlags: .shift)
        #expect(model.primary == [["Z"]], "\(form): a modified Return is not the key")
        selectByClick(window, "A", model)
        window.typeKey(.return)
        settle(window)
        #expect(model.primary == [["Z"], ["A"]], "\(form): M4b: \(model.primary)")
        #expect(visibleRows(window) == ["A", "Z", "M"], "\(form): M4b: no toggle")
        withExtendedLifetime(window) {}
    }
    // Nothing selected (the list still focused): nothing to act on. Mutation: Return running with `{}`.
    for form in CForm.allCases {
        let model = CModel()
        let window = try cWindow(form, model)
        selectByClick(window, "Z", model)
        model.selection = nil
        settle(window)
        window.typeKey(.return)
        #expect(model.primary.isEmpty, "\(form): \(model.primary)")
        withExtendedLifetime(window) {}
    }
}

/// A multi list's Return runs the action with the whole selection.
@Test @MainActor func returnInAMultiListRunsTheActionWithTheWholeSelection() throws {
    for form in CForm.allCases {
        let model = CModel()
        let window = try cWindow(form, model, multi: true)
        selectByClick(window, "A", model)
        // The platform's toggle modifier (`DD-Z` item 4): ⌘ on Apple, ctrl elsewhere.
        let toggle: EventModifiers = ControlKeys.selectionToggleModifier() == .command ? .command : .control
        window.click(at: rowPoint(window, "Z"), modifierFlags: toggle)
        settle(window)
        window.typeKey(.return)
        #expect(model.primary == [["A", "Z"]], "\(form): \(model.primary)")
        withExtendedLifetime(window) {}
    }
}

/// A list with no selection binding still gets its menu and its double-click action (its rows are its data's ids).
@Test @MainActor func aFlatListWithNoSelectionTakesTheMenuAndTheDoubleClick() throws {
    let model = CModel()
    let window = try cWindow(.flat, model, with: .noSelection)
    window.rightClick(at: rowPoint(window, "Z"))
    #expect(model.menus == [["Z"]], "\(model.menus)")
    try window.dismissMenu()
    window.click(at: rowPoint(window, "A"))
    #expect(model.primary.isEmpty)
    window.doubleClick(at: rowPoint(window, "A"))
    #expect(model.primary == [["A"]], "\(model.primary)")
    withExtendedLifetime(window) {}
}

/// A modifier written over another identifier type is inert, as is a modifier on a list with its own `.contextMenu`'s type.
@Test @MainActor func aModifierOfAnotherIdentifierTypeIsInert() throws {
    for form in [CForm.content, .outline, .flat] {
        let model = CModel()
        let window = try cWindow(form, model, with: .mismatched)
        window.rightClick(at: rowPoint(window, "A"))
        window.rightClick(at: pt(200, 380))
        #expect(presented(window) == 0 && model.menus.isEmpty, "\(form): no menu: \(presented(window))")
        window.doubleClick(at: rowPoint(window, "Z"))
        selectByClick(window, "Z", model)
        window.typeKey(.return)
        #expect(model.primary.isEmpty, "\(form): no action: \(model.primary)")
        withExtendedLifetime(window) {}
    }
}

// MARK: - the click count

@MainActor private final class CountLog { var counts: [Int] = []; var modifiers: [Modifiers] = [] }

/// `ClickDispatch.clickCount` is the completing event's click count while a click handler runs, 1 for an accessibility
/// press and after the handler. Mutation: the count not passed on from the event (reads 1).
@Test @MainActor func theClickCountReachesAClickHandler() throws {
    let log = CountLog()
    let window = try harnessWindow(size: sz(200, 100)) {
        Box().frame(width: Pixels(100), height: Pixels(100))
            .onClick { log.counts.append(ClickDispatch.clickCount) }
    }
    for _ in 0..<2 { window.tick() }
    window.click(at: pt(50, 50))
    window.doubleClick(at: pt(50, 50))
    #expect(log.counts == [1, 1, 2], "\(log.counts)")
    #expect(ClickDispatch.clickCount == 1, "reset after the handler")
}
