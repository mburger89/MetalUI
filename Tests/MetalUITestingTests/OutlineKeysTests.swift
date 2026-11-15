import MetalUI
import MetalUIScene
import MetalUITesting
import Foundation
import Testing

// Lane 5 of the hierarchical lists: the outline's disclosure keys and its accessibility (rulings `OG-E`, `OG-F`, divergence
// 1086; record 315; probe `docs/probes/swiftui-outline.swift` arms `P-K2`..`P-K5`, `P-C1`, `P-A1`/`P-A2`).
//
// Every key arm runs over BOTH forms: the content form (`List { ForEach { FolderRow } }`, whose rows are recursive
// `DisclosureGroup(isExpanded:)` over an app-owned set) and the data form (`List(_:children:)`, whose expansion is state the
// framework keeps). The probe's tree, A (A/B (A/B/D, A/B/E), A/C), Z, M (M/N), in a 300 x 400 window: row `k` of the
// visible rows is at y `10 + 32 k`, a depth-`d` chevron cell at x `12 + 12 d`.

private struct KNode: Identifiable {
    var id: String
    var kids: [KNode]?
}

private func K(_ id: String, _ kids: [KNode]? = nil) -> KNode { KNode(id: id, kids: kids) }

private func tree() -> [KNode] {
    [K("A", [K("A/B", [K("A/B/D"), K("A/B/E")]), K("A/C")]), K("Z"), K("M", [K("M/N")])]
}

/// A five-deep chain below A (`P-K4d`): A, A/B, A/B/F, A/B/F/G, A/B/F/G/H, and a sibling A/C.
private func chain() -> [KNode] {
    [K("A", [K("A/B", [K("A/B/F", [K("A/B/F/G", [K("A/B/F/G/H")])])]), K("A/C")]), K("Z")]
}

private enum Form: String, CaseIterable { case content, data }

/// What the content form's app owns, and a log of its writes. `layouts` counts rows evaluated: two writes with the same
/// count happened with no build between them, in one turn.
@MainActor private final class Folders {
    var open: Set<String> = []
    var selection: String?
    var selectionWrites: [String?] = []
    var openWrites: [(id: String, value: Bool, layouts: Int)] = []
    var layouts = 0

    var selectionBinding: Binding<String?> {
        Binding(get: { self.selection }, set: { self.selection = $0; self.selectionWrites.append($0) })
    }

    func binding(_ id: String) -> Binding<Bool> {
        Binding(get: { self.open.contains(id) }, set: { value in
            if value { self.open.insert(id) } else { self.open.remove(id) }
            self.openWrites.append((id, value, self.layouts))
        })
    }
}

private struct FolderRow: Component {
    let node: KNode
    let model: Folders
    @ElementBuilder var content: some ElementGroup {
        let _ = bump()
        if let kids = node.kids {
            DisclosureGroup(isExpanded: model.binding(node.id)) {
                ForEach(kids) { FolderRow(node: $0, model: model) }
            } label: { ProposalText(node.id) }
        } else {
            ProposalText(node.id)
        }
    }
    private func bump() { model.layouts += 1 }
}

@MainActor private func listWindow(_ form: Form, _ nodes: [KNode], _ model: Folders, height: Float = 400,
                                   enabled: Bool = true) throws -> TestWindow {
    let window: TestWindow
    switch form {
    case .content:
        window = try harnessWindow(size: sz(300, height)) {
            ProposalScrollView {
                List(selection: model.selectionBinding) { ForEach(nodes) { FolderRow(node: $0, model: model) } }
                    .disabled(!enabled)
            }
        }
    case .data:
        window = try harnessWindow(size: sz(300, height)) {
            ProposalScrollView {
                List(nodes, children: \.kids, selection: model.selectionBinding) { ProposalText($0.id) }
                    .disabled(!enabled)
            }
        }
    }
    settle(window)
    return window
}

@MainActor private func settle(_ window: TestWindow) { for _ in 0..<4 { window.tick() } }

@MainActor private func texts(_ window: TestWindow) -> [String: Bounds<Pixels>] {
    var found: [String: Bounds<Pixels>] = [:]
    for element in (try? window.elements(role: .staticText)) ?? [] {
        if let value = element.value { found[value] = element.frame }
    }
    return found
}

@MainActor private func visible(_ window: TestWindow) -> [String] {
    texts(window).sorted { $0.value.origin.y.value < $1.value.origin.y.value }.map(\.key)
}

private func rowY(_ index: Int) -> Float { 10 + 32 * Float(index) + 16 }

/// The chevron of the visible row holding `name`, clicked with `modifiers`.
@MainActor private func chevron(_ window: TestWindow, _ name: String, modifiers: EventModifiers = []) {
    let rows = visible(window)
    guard let row = rows.firstIndex(of: name) else { Issue.record("\(name) is not visible: \(rows)"); return }
    let depth = name.filter { $0 == "/" }.count
    window.click(at: pt(12 + 12 * Float(depth) + 6, rowY(row)), modifierFlags: modifiers)
    settle(window)
}

/// Selects `name` by a click on its row (which also focuses the list), then forgets the select write.
@MainActor private func select(_ window: TestWindow, _ name: String, _ model: Folders) {
    let rows = visible(window)
    guard let row = rows.firstIndex(of: name) else { Issue.record("\(name) is not visible: \(rows)"); return }
    window.click(at: pt(200, rowY(row)))
    settle(window)
    model.selectionWrites = []
    model.openWrites = []
}

/// Opens `names` (parents first) through the chevrons, the same in both forms.
@MainActor private func open(_ window: TestWindow, _ names: [String], _ model: Folders) {
    for name in names { chevron(window, name) }
    model.selectionWrites = []
    model.openWrites = []
}

@MainActor private func key(_ window: TestWindow, _ key: KeyEquivalent, _ modifiers: EventModifiers = []) {
    window.typeKey(key, modifierFlags: modifiers)
    settle(window)
}

// MARK: - → and ← (P-K2, P-K3)

/// **P-K2.** → on a collapsed group expands it and leaves the selection alone; on an expanded group, on a leaf, and with ⇧
/// it does nothing. Mutations: → moving to the first child of an expanded group; the key reading no modifier test (⇧→
/// expands); → expanding by a write of the selection.
@Test @MainActor func rightArrowExpandsACollapsedGroupAndNothingElse() throws {
    for form in Form.allCases {
        let model = Folders()
        let window = try listWindow(form, tree(), model)
        select(window, "A", model)
        key(window, .rightArrow, .shift)
        #expect(visible(window) == ["A", "Z", "M"], "\(form): ⇧→ declines: \(visible(window))")
        key(window, .rightArrow)
        #expect(visible(window) == ["A", "A/B", "A/C", "Z", "M"], "\(form): K2a: \(visible(window))")
        #expect(model.selection == "A" && model.selectionWrites.isEmpty, "\(form): K2a keeps the selection: \(model.selectionWrites)")
        if form == .content { #expect(model.openWrites.map(\.id) == ["A"], "\(form): one binding write: \(model.openWrites.map(\.id))") }
        key(window, .rightArrow)
        #expect(visible(window) == ["A", "A/B", "A/C", "Z", "M"], "\(form): K2b: an expanded group does nothing")
        #expect(model.selection == "A" && model.selectionWrites.isEmpty, "\(form): K2b does not move to the first child")
        if form == .content { #expect(model.openWrites.count == 1, "\(form): and writes nothing") }
        select(window, "Z", model)
        key(window, .rightArrow)
        #expect(model.selection == "Z" && model.selectionWrites.isEmpty && visible(window).count == 5, "\(form): K2c: a leaf does nothing")
    }
}

/// **P-K3.** ← on an expanded group collapses it, the selection staying; on a collapsed root nothing; on a leaf child or a
/// collapsed child group it selects the parent; on an expanded child group it collapses that group. Mutations: ← on a
/// collapsed root selecting something; ← on an expanded group moving to its parent instead of collapsing; ← on a leaf doing
/// nothing.
@Test @MainActor func leftArrowCollapsesOrMovesToTheParent() throws {
    for form in Form.allCases {
        // K3a: an expanded A collapses, selected stays.
        var model = Folders()
        var window = try listWindow(form, tree(), model)
        open(window, ["A"], model)
        select(window, "A", model)
        key(window, .leftArrow)
        #expect(visible(window) == ["A", "Z", "M"], "\(form): K3a: \(visible(window))")
        #expect(model.selection == "A" && model.selectionWrites.isEmpty, "\(form): K3a keeps the selection")
        // K3b: a collapsed root does nothing.
        key(window, .leftArrow)
        #expect(visible(window) == ["A", "Z", "M"] && model.selection == "A" && model.selectionWrites.isEmpty,
                "\(form): K3b: a collapsed root does nothing")
        // K3c: a leaf child selects its parent.
        model = Folders()
        window = try listWindow(form, tree(), model)
        open(window, ["A"], model)
        select(window, "A/C", model)
        key(window, .leftArrow)
        #expect(model.selection == "A" && model.selectionWrites == ["A"], "\(form): K3c: \(model.selectionWrites)")
        #expect(visible(window) == ["A", "A/B", "A/C", "Z", "M"], "\(form): K3c collapses nothing")
        // K3d: a collapsed child group selects its parent.
        select(window, "A/B", model)
        key(window, .leftArrow)
        #expect(model.selection == "A" && model.selectionWrites == ["A"], "\(form): K3d: \(model.selectionWrites)")
        // K3e: an expanded child group collapses itself.
        open(window, ["A/B"], model)
        select(window, "A/B", model)
        key(window, .leftArrow)
        #expect(visible(window) == ["A", "A/B", "A/C", "Z", "M"], "\(form): K3e: \(visible(window))")
        #expect(model.selection == "A/B" && model.selectionWrites.isEmpty, "\(form): K3e keeps the selection")
    }
}

// MARK: - ⌥→ and ⌥← (P-K4, P-K5)

/// **P-K4.** ⌥→ on a collapsed group expands it and every descendant; on an expanded group it does nothing, even with a
/// collapsed child. In the content form every descendant's `isExpanded` binding is written in ONE turn, the never-built ones
/// included (`layouts` does not move between the writes). Mutations: the cascade expanding one level; ⌥ ignored (a plain
/// expand); the writes spread over builds (the layout count differs).
@Test @MainActor func optionRightExpandsTheGroupAndEveryDescendant() throws {
    for form in Form.allCases {
        let model = Folders()
        let window = try listWindow(form, tree(), model)
        select(window, "A", model)
        key(window, .rightArrow, .option)
        #expect(visible(window) == ["A", "A/B", "A/B/D", "A/B/E", "A/C", "Z", "M"], "\(form): K4a: \(visible(window))")
        #expect(model.selection == "A" && model.selectionWrites.isEmpty, "\(form): the selection stays")
        if form == .content {
            #expect(Set(model.openWrites.map(\.id)) == ["A", "A/B"] && model.openWrites.allSatisfy(\.value),
                    "\(form): both bindings written: \(model.openWrites.map(\.id))")
            #expect(Set(model.openWrites.map(\.layouts)).count == 1, "\(form): in one turn: \(model.openWrites.map(\.layouts))")
        }
        // K4b: an expanded A with a collapsed child does nothing.
        let before = model.openWrites.count
        key(window, .leftArrow, .option)     // collapse everything
        chevron(window, "A")                  // open A alone
        #expect(visible(window) == ["A", "A/B", "A/C", "Z", "M"], "\(form): control: A open, A/B closed: \(visible(window))")
        model.openWrites = []
        key(window, .rightArrow, .option)
        #expect(visible(window) == ["A", "A/B", "A/C", "Z", "M"], "\(form): K4b: nothing: \(visible(window))")
        if form == .content { #expect(model.openWrites.isEmpty, "\(form): K4b writes nothing: \(model.openWrites.count) after \(before)") }
    }
}

/// **P-K4d.** A five-deep chain: one ⌥→ writes the four group bindings in one turn (the recorded SwiftUI count), and the
/// presented frames show the whole chain open. Mutation: one level per build (the writes land in different turns).
@Test @MainActor func optionRightOverAFiveDeepChainWritesFourBindingsInOneTurn() throws {
    for form in Form.allCases {
        let model = Folders()
        let window = try listWindow(form, chain(), model)
        select(window, "A", model)
        window.typeKey(.rightArrow, modifierFlags: .option)   // the key's own frame, nothing settled after it
        #expect(visible(window) == ["A", "A/B", "A/B/F", "A/B/F/G", "A/B/F/G/H", "A/C", "Z"],
                "\(form): the first presented frame shows the whole chain: \(visible(window))")
        settle(window)
        if form == .content {
            #expect(model.open == ["A", "A/B", "A/B/F", "A/B/F/G"], "\(form): \(model.open.sorted())")
            #expect(model.openWrites.count == 4, "\(form): four writes: \(model.openWrites.count)")
            #expect(Set(model.openWrites.map(\.layouts)).count == 1, "\(form): one turn: \(model.openWrites.map(\.layouts))")
        }
    }
}

/// **P-K5.** ⌥← on an expanded group collapses it and every expanded descendant (both bindings in one turn); on A/B it
/// leaves A open. Collapsing A and re-expanding it plainly shows A/B closed. Mutations: ⌥← collapsing the group alone
/// (A/B reopens); ⌥← on a child collapsing the parent too.
@Test @MainActor func optionLeftCollapsesTheGroupAndEveryDescendant() throws {
    for form in Form.allCases {
        let model = Folders()
        let window = try listWindow(form, tree(), model)
        open(window, ["A", "A/B"], model)
        select(window, "A", model)
        key(window, .leftArrow, .option)
        #expect(visible(window) == ["A", "Z", "M"], "\(form): K5: \(visible(window))")
        if form == .content {
            #expect(model.open.isEmpty, "\(form): both bindings cleared: \(model.open.sorted())")
            #expect(Set(model.openWrites.map(\.layouts)).count == 1, "\(form): one turn: \(model.openWrites.map(\.layouts))")
        }
        chevron(window, "A")
        #expect(visible(window) == ["A", "A/B", "A/C", "Z", "M"], "\(form): A/B was collapsed too: \(visible(window))")
        // K5b: on A/B, A stays open.
        open(window, ["A/B"], model)
        select(window, "A/B", model)
        key(window, .leftArrow, .option)
        #expect(visible(window) == ["A", "A/B", "A/C", "Z", "M"], "\(form): K5b: \(visible(window))")
        if form == .content { #expect(model.open == ["A"], "\(form): \(model.open.sorted())") }
    }
}

/// **K5c (`OG-E` deviation (c)).** ⌥← reaches the expanded groups below the group only through expanded ancestors: a group
/// under an already collapsed child keeps its own state. A, A/B, A/B/F opened, then A/B collapsed by a plain click (F stays
/// open inside it); ⌥← on A, A re-opened and A/B re-opened shows F still open. Mutation: the data cascade descending into
/// collapsed children (F is written closed).
@Test @MainActor func optionLeftLeavesAGroupUnderACollapsedChildAlone() throws {
    for form in Form.allCases {
        let model = Folders()
        let window = try listWindow(form, chain(), model)
        open(window, ["A", "A/B", "A/B/F"], model)
        chevron(window, "A/B")
        #expect(visible(window) == ["A", "A/B", "A/C", "Z"], "\(form): control: A/B collapsed: \(visible(window))")
        select(window, "A", model)
        key(window, .leftArrow, .option)
        #expect(visible(window) == ["A", "Z"], "\(form): \(visible(window))")
        chevron(window, "A")
        chevron(window, "A/B")
        #expect(visible(window) == ["A", "A/B", "A/B/F", "A/B/F/G", "A/C", "Z"],
                "\(form): F kept its own state under the collapsed child: \(visible(window))")
        if form == .content { #expect(model.open.contains("A/B/F"), "\(form): F's binding was not written: \(model.open.sorted())") }
    }
}

/// **P-C1.** ⌥-click on the chevron cascades like ⌥→ and ⌥←; a plain click toggles one group. Mutations: the chevron
/// ignoring ⌥; ⌥ cascading a plain click.
@Test @MainActor func optionClickOnTheChevronCascades() throws {
    for form in Form.allCases {
        let model = Folders()
        let window = try listWindow(form, tree(), model)
        chevron(window, "A", modifiers: .option)
        #expect(visible(window) == ["A", "A/B", "A/B/D", "A/B/E", "A/C", "Z", "M"], "\(form): ⌥-click expands all: \(visible(window))")
        if form == .content {
            #expect(Set(model.openWrites.map(\.layouts)).count == 1, "\(form): one turn: \(model.openWrites.map(\.layouts))")
        }
        chevron(window, "A", modifiers: .option)
        #expect(visible(window) == ["A", "Z", "M"], "\(form): ⌥-click collapses all: \(visible(window))")
        if form == .content { #expect(model.open.isEmpty, "\(form): \(model.open.sorted())") }
        chevron(window, "A")
        #expect(visible(window) == ["A", "A/B", "A/C", "Z", "M"], "\(form): a plain click opens one level: \(visible(window))")
    }
}

// MARK: - accessibility (OG-F, P-A1, P-A2)

/// The node of the published row whose content's text is `name` (a leaf row's own text child, or a group row's, which sits
/// under the cell after the triangle).
@MainActor private func rowNode(_ window: TestWindow, _ name: String) throws -> (id: AccessibilityNodeID, node: AccessibilityNode) {
    let tree = try window.accessibilityTree
    func holds(_ id: AccessibilityNodeID) -> Bool {
        guard let node = tree.nodes[id] else { return false }
        if node.role == .staticText, node.value == name { return true }
        return node.children.contains(where: holds)
    }
    for (id, node) in tree.nodes where node.role == .row && holds(id) { return (id, node) }
    throw TestHarnessError.noElement("row \(name)")
}

/// **P-A1/P-A2, OG-F.** The published rows carry the disclosure level, whether a group is open, and the realised row each is
/// disclosed by; the list is an outline. A flat list's rows carry none of it. Mutations: the level off by one; a group's
/// state reading collapsed when open; the disclosed-by taken as the previous row.
@Test @MainActor func anOutlinesRowsPublishTheirLevelStateAndParent() throws {
    for form in Form.allCases {
        let model = Folders()
        let window = try listWindow(form, tree(), model)
        open(window, ["A", "A/B"], model)
        let tree = try window.accessibilityTree
        let list = try #require(tree.nodes.values.first { $0.role == .table })
        #expect(list.isOutline, "\(form): the list is an outline")
        let expected: [(String, Int, Bool?, String?)] = [
            ("A", 0, true, nil), ("A/B", 1, true, "A"), ("A/B/D", 2, nil, "A/B"), ("A/B/E", 2, nil, "A/B"),
            ("A/C", 1, nil, "A"), ("Z", 0, nil, nil), ("M", 0, false, nil),
        ]
        for (name, level, isExpanded, parent) in expected {
            let row = try rowNode(window, name)
            #expect(row.node.outlineLevel == level, "\(form): \(name) level \(String(describing: row.node.outlineLevel))")
            #expect(row.node.isExpanded == isExpanded, "\(form): \(name) expanded \(String(describing: row.node.isExpanded))")
            let disclosedBy = try parent.map { try rowNode(window, $0).id }
            #expect(row.node.disclosedBy == disclosedBy, "\(form): \(name) is disclosed by \(parent ?? "nothing")")
        }
    }
    let flat = try harnessWindow(size: sz(300, 400)) {
        ProposalScrollView { List { ForEach(["one", "two"], id: \.self) { ProposalText($0) } } }
    }
    settle(flat)
    let flatTree = try flat.accessibilityTree
    #expect(flatTree.nodes.values.allSatisfy { !$0.isOutline && $0.outlineLevel == nil && $0.isExpanded == nil },
            "a flat list publishes no outline")
}

/// **OG-F, the nesting carried from lane 4.** A row's element is the parent of its content's text (as the data list's rows
/// are), a group row's text sitting in its cell after the disclosure triangle (`P-A`: the row's one child is an `AXCell`
/// holding an `AXDisclosureTriangle`, value "1" open and "0" closed). Mutations: the adopter dropped (the text is the
/// list's child again); the triangle value inverted.
@Test @MainActor func aRowIsTheParentOfItsTextAndAGroupRowHoldsItsTriangleInACell() throws {
    for form in Form.allCases {
        let model = Folders()
        let window = try listWindow(form, tree(), model)
        open(window, ["A"], model)
        let tree = try window.accessibilityTree
        let z = try rowNode(window, "Z")
        #expect(z.node.children.compactMap { tree.nodes[$0] }.map(\.role) == [.staticText], "\(form): a leaf row's one child is its text")
        let a = try rowNode(window, "A")
        #expect(a.node.children.compactMap { tree.nodes[$0] }.map(\.role) == [.cell], "\(form): a group row's one child is a cell")
        let cell = try #require(tree.nodes[a.node.children[0]])
        let inside = cell.children.compactMap { tree.nodes[$0] }
        #expect(inside.map(\.role) == [.disclosureTriangle, .staticText], "\(form): the triangle, then the text: \(inside.map(\.role))")
        #expect(inside[0].value == "1" && inside[1].value == "A", "\(form): open reads 1: \(String(describing: inside[0].value))")
        let m = try rowNode(window, "M")
        let mCell = try #require(tree.nodes[m.node.children[0]])
        let mTriangle = try #require(tree.nodes[mCell.children[0]])
        #expect(mTriangle.value == "0", "\(form): closed reads 0")
        let list = try #require(tree.nodes.values.first { $0.role == .table })
        #expect(!list.children.contains { tree.nodes[$0]?.role == .staticText }, "\(form): no text hangs from the list itself")
    }
}

/// **OG-F, realised rows only.** When a row's parent is scrolled out of the window the row has no disclosed-by (the parent
/// is not published): a row's parent is the nearest realised row one level up. Mutation: the nearest row above, whatever its
/// level, taken as the parent.
@Test @MainActor func aRowWhoseParentIsNotRealisedIsDisclosedByNothing() throws {
    let big = [K("R", (0..<80).map { K("R/\($0)") })]
    for form in Form.allCases {
        let model = Folders()
        let window = try listWindow(form, big, model, height: 150)
        chevron(window, "R")
        window.scroll(at: pt(150, 75), byDeltaX: 0, deltaY: -2000)
        settle(window)
        let tree = try window.accessibilityTree
        let rows = tree.nodes.filter { $0.value.role == .row }.values
        #expect(rows.count > 2, "\(form): rows are realised: \(rows.count)")
        #expect(rows.allSatisfy { $0.outlineLevel == 1 }, "\(form): every realised row is a child of R")
        #expect(rows.allSatisfy { $0.disclosedBy == nil }, "\(form): R is not realised, so no row is disclosed by it")
    }
}

/// **OG-F, `AXDisclosing` set and the AccessKit EXPAND/COLLAPSE.** An expand request on a collapsed group expands it (the
/// binding, in the content form), a collapse on an expanded one collapses it, and each is refused on a leaf and in the wrong
/// state; a press on the row's triangle toggles it. Mutations: the handler unregistered (nothing happens); the request
/// accepted on a leaf.
@Test @MainActor func expandAndCollapseRequestsToggleAGroupRow() throws {
    for form in Form.allCases {
        let model = Folders()
        let window = try listWindow(form, tree(), model)
        let platform = window.platformWindow
        let a = try rowNode(window, "A")
        #expect(a.node.actions.contains(.expand) && !a.node.actions.contains(.collapse), "\(form): a collapsed group offers expand")
        #expect(!platform.simulateAccessibilityRequest(.collapse(a.id)), "\(form): collapse is refused on a collapsed group")
        #expect(platform.simulateAccessibilityRequest(.expand(a.id)), "\(form): expand is handled")
        settle(window)
        #expect(visible(window) == ["A", "A/B", "A/C", "Z", "M"], "\(form): \(visible(window))")
        if form == .content { #expect(model.open == ["A"], "\(form): the binding was written") }
        #expect(model.selectionWrites.isEmpty, "\(form): and nothing selected")
        let opened = try rowNode(window, "A")
        #expect(opened.node.actions.contains(.collapse) && !opened.node.actions.contains(.expand), "\(form): now it offers collapse")
        #expect(!platform.simulateAccessibilityRequest(.expand(opened.id)), "\(form): expand is refused on an expanded group")
        let z = try rowNode(window, "Z")
        #expect(z.node.actions.intersection([.expand, .collapse]).isEmpty, "\(form): a leaf offers neither")
        #expect(!platform.simulateAccessibilityRequest(.expand(z.id)) && !platform.simulateAccessibilityRequest(.collapse(z.id)),
                "\(form): and refuses both")
        // The triangle: a press toggles, as AXPress does.
        let tree = try window.accessibilityTree
        let cell = try #require(tree.nodes[opened.node.children[0]])
        let triangle = cell.children[0]
        #expect(platform.simulateAccessibilityRequest(.press(triangle)), "\(form): the triangle's press is handled")
        settle(window)
        #expect(visible(window) == ["A", "Z", "M"], "\(form): the press collapsed A: \(visible(window))")
        if form == .content { #expect(model.open.isEmpty, "\(form): \(model.open.sorted())") }
        let again = try rowNode(window, "A")
        let againTree = try window.accessibilityTree
        let againCell = try #require(againTree.nodes[again.node.children[0]])
        let triangleAgain = againCell.children[0]
        #expect(platform.simulateAccessibilityRequest(.press(triangleAgain)), "\(form): and a second press expands")
        settle(window)
        #expect(visible(window) == ["A", "A/B", "A/C", "Z", "M"], "\(form): \(visible(window))")
    }
}

/// **OG-F, the disabled gate.** A disabled list advertises neither action and refuses both requests and the triangle's press,
/// writing nothing. Mutation: the handler registered past the gate.
@Test @MainActor func aDisabledOutlineRefusesExpandAndCollapse() throws {
    for form in Form.allCases {
        let model = Folders()
        let window = try listWindow(form, tree(), model, enabled: false)
        let platform = window.platformWindow
        let a = try rowNode(window, "A")
        #expect(a.node.actions.intersection([.expand, .collapse]).isEmpty, "\(form): no action is offered: \(a.node.actions)")
        #expect(!platform.simulateAccessibilityRequest(.expand(a.id)), "\(form): expand is refused")
        let tree = try window.accessibilityTree
        let cell = try #require(tree.nodes[a.node.children[0]])
        let triangle = try #require(tree.nodes[cell.children[0]])
        #expect(triangle.actions.isEmpty && !triangle.isEnabled, "\(form): the triangle offers no press")
        settle(window)
        #expect(visible(window) == ["A", "Z", "M"], "\(form): nothing expanded")
        #expect(model.openWrites.isEmpty, "\(form): nothing written")
    }
}
