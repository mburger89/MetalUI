import MetalUI
import MetalUIScene
import MetalUITesting
import Foundation
import Testing

// Lane 4 of the hierarchical lists: the content `List` and the outline `List` inits (rulings `OG-A`, `OG-B`, `OG-E`, `OG-J`,
// divergence 1085; record 314; probe `docs/probes/swiftui-outline.swift` arms `P-L1`..`P-L4`, `P-K1`, `P-K7`, `P-C1`, `P-R1`).
// The probe's tree, A (A/B (A/B/D, A/B/E), A/C), Z, M (M/N), in a 300 x 400 window: a row is 32 high, the first 10 below the
// top, so row `k` (counted over the visible rows) is at y `10 + 32 k`, a depth-`d` chevron cell at x `12 + 12 d` (13 wide),
// its label at x `25 + 12 d`. Labels are `ProposalText`, 18 high in Noto Sans, centred in the row (y + 7).

private struct Node: Identifiable {
    var id: String
    var kids: [Node]?
}

private func N(_ id: String, _ kids: [Node]? = nil) -> Node { Node(id: id, kids: kids) }

private func probeTree() -> [Node] {
    [N("A", [N("A/B", [N("A/B/D"), N("A/B/E")]), N("A/C")]), N("Z"), N("M", [N("M/N")])]
}

@MainActor private final class Model {
    var selection: String?
    var writes: [String?] = []
    var binding: Binding<String?> {
        Binding(get: { self.selection }, set: { self.selection = $0; self.writes.append($0) })
    }
}

@MainActor private func label(_ node: Node) -> ProposalText { ProposalText(node.id) }

@MainActor private func outlineWindow(_ tree: [Node], model: Model, height: Float = 400) throws -> TestWindow {
    try harnessWindow(size: sz(300, height)) {
        ProposalScrollView {
            List(tree, children: \.kids, selection: model.binding) { node in label(node) }
        }
    }
}

@MainActor private func settle(_ window: TestWindow) { for _ in 0..<4 { window.tick() } }

/// The static texts by value, with their frames.
@MainActor private func texts(_ window: TestWindow) -> [String: Bounds<Pixels>] {
    var found: [String: Bounds<Pixels>] = [:]
    for element in (try? window.elements(role: .staticText)) ?? [] {
        if let value = element.value { found[value] = element.frame }
    }
    return found
}

/// The visible rows' accessibility elements, top to bottom.
@MainActor private func rows(_ window: TestWindow) -> [TestElement] {
    ((try? window.elements(role: .row)) ?? []).sorted { $0.frame.origin.y.value < $1.frame.origin.y.value }
}

/// The labels of the visible rows, top to bottom.
@MainActor private func visible(_ window: TestWindow) -> [String] {
    texts(window).sorted { $0.value.origin.y.value < $1.value.origin.y.value }.map(\.key)
}

/// Row `index`'s centre y, and a click at `x` on it.
private func rowY(_ index: Int) -> Float { 10 + 32 * Float(index) + 16 }

@MainActor private func chevron(_ window: TestWindow, row: Int, depth: Int) {
    window.click(at: pt(12 + 12 * Float(depth) + 6, rowY(row)))
    settle(window)
}

@MainActor private func body(_ window: TestWindow, row: Int, x: Float = 150, modifiers: EventModifiers = []) {
    window.click(at: pt(x, rowY(row)), modifierFlags: modifiers)
    settle(window)
}

private func f(_ value: Pixels) -> Float { value.value }

// MARK: - the `.sidebar` look (OG-J, P-L1, P-L2)

/// **P-L1, P-L2.** The probe's tree fully expanded: 8 rows of 32 starting 10 below the top, each full width; labels at x 25 /
/// 37 / 49 for depths 0 / 1 / 2, **a leaf at the same x as its sibling group** (Z at 25 like A and M, A/C at 37 like A/B,
/// A/B/D at 49: it reserves the chevron slot), each label vertically centred in its row. Mutations: the row height 32 -> 24;
/// the first row's top inset 10 -> 0; the indent 12 -> 13 (the 49 becomes 51); a leaf not reserving the slot (Z at 16).
@Test @MainActor func theSidebarRowsAre32HighWith12PerLevelIndentAndLeavesReserveTheChevronSlot() throws {
    let model = Model()
    let window = try outlineWindow(probeTree(), model: model)
    settle(window)
    chevron(window, row: 0, depth: 0)   // A
    chevron(window, row: 1, depth: 1)   // A/B
    chevron(window, row: 6, depth: 0)   // M
    #expect(visible(window) == ["A", "A/B", "A/B/D", "A/B/E", "A/C", "Z", "M", "M/N"], "\(visible(window))")
    let labels = texts(window)
    let expectedX: [String: Float] = ["A": 25, "A/B": 37, "A/B/D": 49, "A/B/E": 49, "A/C": 37, "Z": 25, "M": 25, "M/N": 37]
    for (index, name) in ["A", "A/B", "A/B/D", "A/B/E", "A/C", "Z", "M", "M/N"].enumerated() {
        let frame = try #require(labels[name])
        #expect(f(frame.origin.x) == expectedX[name], "\(name) label x \(f(frame.origin.x))")
        #expect(abs(f(frame.origin.y) + f(frame.size.height) / 2 - (10 + 32 * Float(index) + 16)) <= 0.5,
                "\(name) centred in its 32 point row: y \(f(frame.origin.y))")
    }
    let found = rows(window)
    #expect(found.count == 8, "eight rows: \(found.count)")
    for (index, row) in found.enumerated() {
        #expect(f(row.frame.origin.y) == 10 + 32 * Float(index) && f(row.frame.size.height) == 32
                    && f(row.frame.origin.x) == 0 && f(row.frame.size.width) == 300,
                "row \(index): \(row.frame)")
    }
}

/// **P-L1's flat control.** A content list with no hierarchy has its labels at x 16 and 32 point rows from 10 down.
/// Mutation: the flat leading 16 -> 25 (every row reserves a chevron slot it has no use for).
@Test @MainActor func aListWithNoHierarchyHasItsLabelsAtX16() throws {
    let names = ["one", "two", "three"]
    let window = try harnessWindow(size: sz(300, 400)) {
        ProposalScrollView {
            List {
                ForEach(names, id: \.self) { ProposalText($0) }
            }
        }
    }
    settle(window)
    #expect(visible(window) == names)
    for (index, name) in names.enumerated() {
        let frame = try #require(texts(window)[name])
        #expect(f(frame.origin.x) == 16, "\(name): \(f(frame.origin.x))")
        #expect(abs(f(frame.origin.y) + f(frame.size.height) / 2 - (10 + 32 * Float(index) + 16)) <= 0.5)
    }
}

/// **P-L4.** A selected row's highlight is inset 10 from each side (x 10, width 280 of 300), the row's full 32 points, with
/// 8 point corners. The colour is MetalUI's existing list selection colour (the tint, else the accent): the probe did not
/// measure SwiftUI's (human check OG). Mutations: the inset 10 -> 0; the radius 8 -> 0.
@Test @MainActor func theSelectionHighlightIsInsetTenAndRoundedEight() throws {
    let model = Model()
    model.selection = "Z"
    let window = try outlineWindow(probeTree(), model: model)
    settle(window)
    let highlights = window.allRects.filter { $0.bounds.size.height == 32 && $0.bounds.size.width == 280 }
    let one = try #require(highlights.first, "a 280 x 32 highlight: \(window.allRects.map { xywh($0) })")
    #expect(highlights.count == 1)
    #expect(xywh(one) == [10, 10 + 32, 280, 32], "Z is the second row: \(xywh(one))")
    #expect(one.cornerRadii.topLeft == 8 && one.cornerRadii.bottomRight == 8, "radius 8: \(one.cornerRadii)")
    #expect(try #require(rows(window).first { $0.isSelected }).frame.origin.y.value == 42, "its row reads as selected")
}

// MARK: - clicks (P-C1)

/// **P-C1.** The chevron toggles and does not select; a click on the row body selects and does not toggle. The chevron
/// cell is 13 wide at x 12 (depth 0) and x 24 (depth 1): a click at x 13 or 24 toggles, at x 26 on a depth-0 row (the
/// label) selects. Mutations: the chevron's tap also selecting (a write of A); the row body's click also toggling.
@Test @MainActor func theChevronTogglesWithoutSelectingAndTheRowSelectsWithoutToggling() throws {
    let model = Model()
    model.selection = "Z"
    let window = try outlineWindow(probeTree(), model: model)
    settle(window)
    chevron(window, row: 0, depth: 0)
    #expect(visible(window) == ["A", "A/B", "A/C", "Z", "M"], "the chevron expanded A: \(visible(window))")
    #expect(model.selection == "Z" && model.writes.isEmpty, "and selected nothing: \(model.writes)")
    body(window, row: 0, x: 26)
    #expect(model.selection == "A" && model.writes == ["A"], "a click on the label selects A: \(model.writes)")
    #expect(visible(window) == ["A", "A/B", "A/C", "Z", "M"], "and does not collapse it")
    body(window, row: 3, x: 200)
    #expect(model.selection == "Z" && visible(window).count == 5, "a click on a leaf selects it: \(String(describing: model.selection))")
    window.click(at: pt(24 + 3, rowY(1)))   // A/B's chevron cell is at x 24
    settle(window)
    #expect(visible(window) == ["A", "A/B", "A/B/D", "A/B/E", "A/C", "Z", "M"], "a depth-1 chevron at x 24: \(visible(window))")
    window.click(at: pt(12 + 3, rowY(1)))   // x 15 on a depth-1 row is the indent, not a chevron or a label
    settle(window)
    #expect(model.selection == "A/B", "a click left of the depth-1 chevron is the row's: \(String(describing: model.selection))")
}

// MARK: - keys (P-K1, P-K7)

/// **P-K1.** ↓ and ↑ move the selection one visible row per key, through the children of an expanded group and past a
/// collapsed one, writing the binding once per key; at the ends the lead stays. Mutations: the walk over every node, not the
/// visible ones (a collapsed group's children are visited); a write per key repeated.
@Test @MainActor func theArrowKeysMoveOneVisibleRowPerKey() throws {
    let model = Model()
    let window = try outlineWindow(probeTree(), model: model)
    settle(window)
    chevron(window, row: 0, depth: 0)
    chevron(window, row: 1, depth: 1)
    body(window, row: 0, x: 150)   // select A, focusing the list
    var walked: [String?] = []
    for _ in 0..<7 {
        window.typeKey(.downArrow)
        settle(window)
        walked.append(model.selection)
    }
    #expect(walked == ["A/B", "A/B/D", "A/B/E", "A/C", "Z", "M", "M"], "M is collapsed, its child never visited: \(walked)")
    #expect(model.writes == ["A", "A/B", "A/B/D", "A/B/E", "A/C", "Z", "M"], "one write per key, none at the end: \(model.writes)")
    window.typeKey(.upArrow)
    settle(window)
    #expect(model.selection == "Z")
    let highlighted = rows(window).filter(\.isSelected)
    #expect(highlighted.count == 1 && f(highlighted[0].frame.origin.y) == 10 + 32 * 5, "row 5 is selected: \(highlighted.map(\.frame))")
}

/// **P-K7.** Collapsing an ancestor of the selection keeps the hidden id in the binding with no write, and no row shows
/// selected; the next ↓ selects the FIRST row and, after the same collapse, ↑ the LAST. Mutations: the collapse clearing the
/// binding; ↓ from a hidden selection starting at the row after the hidden one's position.
@Test @MainActor func aHiddenSelectionStaysInTheBindingAndTheNextKeyStartsFromTheEnds() throws {
    func hidden() throws -> (Model, TestWindow) {
        let model = Model()
        let window = try outlineWindow(probeTree(), model: model)
        settle(window)
        chevron(window, row: 0, depth: 0)
        chevron(window, row: 1, depth: 1)
        body(window, row: 2, x: 150)   // A/B/D
        #expect(model.selection == "A/B/D")
        let before = model.writes.count
        chevron(window, row: 0, depth: 0)   // collapse A
        #expect(visible(window) == ["A", "Z", "M"], "\(visible(window))")
        #expect(model.selection == "A/B/D" && model.writes.count == before, "the binding keeps the hidden id, no write")
        #expect(rows(window).allSatisfy { !$0.isSelected }, "and no row shows selected")
        return (model, window)
    }
    let (down, downWindow) = try hidden()
    downWindow.typeKey(.downArrow)
    settle(downWindow)
    #expect(down.selection == "A", "↓ selects the first row: \(String(describing: down.selection))")
    let (up, upWindow) = try hidden()
    upWindow.typeKey(.upArrow)
    settle(upWindow)
    #expect(up.selection == "M", "↑ selects the last row: \(String(describing: up.selection))")
}

// MARK: - selection values (OG-E)

/// **A row's selection value is its `.tag(_:)` first, else its `ForEach` element id.** Ids 0...2 and tags 100...102 over one
/// `Int` selection: the tagged rows select their tags, an untagged list its ids. Mutations: the id read before the tag.
@Test @MainActor func aTagBeatsTheElementIDAndTheIDIsUsedWithoutOne() throws {
    var picked: Int?
    let binding = Binding<Int?>(get: { picked }, set: { picked = $0 })
    let tagged = try harnessWindow(size: sz(300, 400)) {
        ProposalScrollView {
            List(selection: binding) {
                ForEach(0..<3, id: \.self) { ProposalText("row \($0)").tag($0 + 100) }
            }
        }
    }
    settle(tagged)
    tagged.click(at: pt(150, rowY(1)))
    settle(tagged)
    #expect(picked == 101, "the tag: \(String(describing: picked))")
    picked = nil
    let plain = try harnessWindow(size: sz(300, 400)) {
        ProposalScrollView {
            List(selection: binding) {
                ForEach(0..<3, id: \.self) { ProposalText("row \($0)") }
            }
        }
    }
    settle(plain)
    plain.click(at: pt(150, rowY(2)))
    settle(plain)
    #expect(picked == 2, "the element id: \(String(describing: picked))")
    #expect(rows(plain).filter(\.isSelected).map { f($0.frame.origin.y) } == [10 + 64], "its row reads selected")
}

/// **A `Set` selection by click**: a click selects exactly the row, ⇧ selects the range from the anchor (`DD-Z`), through the
/// shared controller. Mutation: the range read over the data order instead of the visible rows.
@Test @MainActor func aSetSelectionTakesAClickAndAShiftRange() throws {
    var picked: Set<String> = []
    let tree = probeTree()
    let window = try harnessWindow(size: sz(300, 400)) {
        ProposalScrollView {
            List(tree, children: \.kids, selection: Binding(get: { picked }, set: { picked = $0 })) { label($0) }
        }
    }
    settle(window)
    chevron(window, row: 0, depth: 0)
    body(window, row: 1)   // A/B
    #expect(picked == ["A/B"], "\(picked)")
    body(window, row: 3, modifiers: [.shift])   // Z
    #expect(picked == ["A/B", "A/C", "Z"], "the visible rows from A/B to Z: \(picked)")
    #expect(rows(window).filter(\.isSelected).count == 3)
}

/// **A programmatic selection highlights its row**, and one the visible rows do not hold highlights none.
@Test @MainActor func aProgrammaticSelectionHighlightsItsRow() throws {
    let model = Model()
    let window = try outlineWindow(probeTree(), model: model)
    settle(window)
    chevron(window, row: 0, depth: 0)
    model.selection = "A/C"
    window.window.setNeedsRedraw()
    settle(window)
    #expect(rows(window).filter(\.isSelected).map { f($0.frame.origin.y) } == [10 + 64], "A/C is the third row")
    #expect(model.writes.isEmpty, "a programmatic selection is not written back")
    model.selection = "no such row"
    window.window.setNeedsRedraw()
    settle(window)
    #expect(rows(window).allSatisfy { !$0.isSelected }, "a value no row holds selects none")
}

// MARK: - the outline inits (OG-A)

/// **Each outline init is literally `List(selection:) { OutlineGroup(...) }`**: the same tree through the Set, optional,
/// non-optional, no-selection and `id:` forms and through the literal content form has the same accessibility ids (the
/// element ids). Mutation: an init building `OutlineGroup` inside an extra container (every id moves).
@Test @MainActor func theOutlineInitsMakeTheSameElementIDsAsAListOfAnOutlineGroup() throws {
    let tree = probeTree()
    var optional: String?
    var many: Set<String> = []
    var plain = ""
    func ids<Root: Element>(_ root: @escaping @MainActor () -> Root) throws -> Set<AccessibilityNodeID> {
        let window = try harnessWindow(size: sz(300, 400)) { ProposalScrollView { root() } }
        settle(window)
        #expect(visible(window) == ["A", "Z", "M"], "every form shows the same labels: \(visible(window))")
        return Set(try window.elements(where: { _ in true }).map(\.id))
    }
    let literal = try ids {
        List(selection: Binding<String?>(get: { optional }, set: { optional = $0 })) {
            OutlineGroup(tree, children: \.kids) { label($0) }
        }
    }
    #expect(literal.count == 1 + 3 + 3 + 2 + 2,
            "the table, one row and one label per root, and (lane 5) a cell and a triangle for each of the two groups: \(literal.count)")
    let viaOptional = try ids { List(tree, children: \.kids, selection: Binding<String?>(get: { optional }, set: { optional = $0 })) { label($0) } }
    let viaSet = try ids { List(tree, children: \.kids, selection: Binding(get: { many }, set: { many = $0 })) { label($0) } }
    let viaPlain = try ids { List(tree, children: \.kids, selection: Binding(get: { plain }, set: { plain = $0 })) { label($0) } }
    let viaPath = try ids { List(tree, id: \.id, children: \.kids, selection: Binding<String?>(get: { optional }, set: { optional = $0 })) { label($0) } }
    #expect(viaOptional == literal, "optional: \(viaOptional.symmetricDifference(literal).count) ids differ")
    #expect(viaPath == literal, "id: \(viaPath.symmetricDifference(literal).count) ids differ")
    // The Set and non-optional forms select their own rows (the row ids equal as the rows are the same); no-selection
    // lists publish no selectable rows, so only the labels are compared there.
    #expect(viaSet == literal, "set: \(viaSet.symmetricDifference(literal).count) ids differ")
    #expect(viaPlain == literal, "non-optional: \(viaPlain.symmetricDifference(literal).count) ids differ")
    let none = try ids { List(tree, children: \.kids) { label($0) } }
    #expect(none.count >= 3, "the no-selection form builds the same tree: \(none.count)")
}

// MARK: - reveal (OG-D, divergence 1085, P-R1)

@MainActor private final class Folders {
    var open: Set<String> = []
    var selection: String?
    var proxy: ScrollViewProxy?
    func binding(_ id: String) -> Binding<Bool> {
        Binding(get: { self.open.contains(id) }, set: { if $0 { self.open.insert(id) } else { self.open.remove(id) } })
    }
}

private struct FolderRow: Component {
    let node: Node
    let model: Folders
    @ElementBuilder var content: some ElementGroup {
        if let kids = node.kids {
            DisclosureGroup(isExpanded: model.binding(node.id)) {
                ForEach(kids) { FolderRow(node: $0, model: model) }
            } label: { ProposalText(node.id) }
        } else {
            ProposalText(node.id)
        }
    }
}

/// R0, R1, R2, each holding S, which holds 20 leaves.
private func bigTree() -> [Node] {
    (0..<3).map { r in N("R\(r)", [N("R\(r)/S", (0..<20).map { N("R\(r)/S/L\($0)") })]) }
}

@MainActor private func revealWindow(_ model: Folders) throws -> TestWindow {
    let tree = bigTree()
    let selection = Binding<String?>(get: { model.selection }, set: { model.selection = $0 })
    return try harnessWindow(size: sz(300, 400)) {
        VStack(spacing: Pixels(0)) {
            ScrollViewReader { proxy in
                let _ = model.proxy = proxy
                ProposalScrollView {
                    List(selection: selection) {
                        ForEach(tree) { FolderRow(node: $0, model: model) }
                    }
                }
            }
        }
    }
}

/// **Same-transaction reveal (Alloy request a, divergence 1085; SwiftUI does not, probe `P-R1`).** Expanding R2 and R2/S,
/// selecting R2/S/L15 (row 20 of 26, y 650 of a 400 high list) and `scrollTo` it in ONE transaction: the frame that
/// flattens the new expansion also resolves the scroll against it, so with no frame in between the row (all 32 points of it)
/// is inside the viewport after that frame and the one it asks for, and it reads as selected. Control (the same without the
/// expansion's help): the row is far outside the viewport before. Mutation: scroll requests resolved only against the
/// realised units (`unitCount: plan.window.upperBound` in `LazyStackEngine.prepaint`): the row never lands.
@Test @MainActor func anExpansionASelectionAndAScrollToInOneTransactionLandTheRowInView() throws {
    let model = Folders()
    let window = try revealWindow(model)
    settle(window)
    #expect(visible(window) == ["R0", "R1", "R2"], "\(visible(window))")
    model.open = ["R2", "R2/S"]
    model.selection = "R2/S/L15"
    model.proxy?.scrollTo("R2/S/L15")
    window.tick()   // the frame that flattens the expansion, and resolves the scroll
    window.tick()   // the frame the resolution asks for
    let target = try #require(rows(window).first { $0.isSelected }, "the selected row is realised: \(rows(window).count) rows")
    let top = f(target.frame.origin.y), bottom = top + f(target.frame.size.height)
    #expect(top >= 0 && bottom <= 400, "row R2/S/L15 is inside the 400 high viewport: \(top)..\(bottom)")
    #expect(texts(window)["R2/S/L15"] != nil, "its label is on screen")
}

/// **Control for the reveal**: the row is NOT in view when nothing scrolls (the same writes without the `scrollTo`), so the
/// assertion above is the scroll's, not the layout's.
@Test @MainActor func withoutTheScrollToTheExpandedRowIsBelowTheViewport() throws {
    let model = Folders()
    let window = try revealWindow(model)
    settle(window)
    model.open = ["R2", "R2/S"]
    model.selection = "R2/S/L15"
    window.window.setNeedsRedraw()
    settle(window)
    #expect(texts(window)["R2/S/L15"] == nil, "L15 is 20 rows down: not realised, not in view")
    #expect(!rows(window).contains { $0.isSelected }, "so no realised row reads selected")
}

// MARK: - performance (OG-I)

/// **A content list over 100 000 roots, a few expanded: the realised units are the window.** The outline form (data-driven
/// index) over 100 000 top-level paths with three expanded: the frame realises the viewport's rows plus overscan, however many
/// rows there are. Mutation: the list realising every unit (100 000).
@Test @MainActor func aHundredThousandRowOutlineRealisesOnlyItsWindow() throws {
    let roots = (0..<100_000).map { i in i % 25_000 == 0 ? N("p\(i)", [N("p\(i)/a"), N("p\(i)/b")]) : N("p\(i)") }
    let window = try harnessWindow(size: sz(300, 400)) {
        ProposalScrollView {
            List(roots, children: \.kids) { label($0) }
        }
    }
    settle(window)
    chevron(window, row: 0, depth: 0)
    let work = window.lastFrameWork
    #expect(work.lazyUnitsRealized <= 20 && work.lazyUnitsRealized >= 12, "the window: \(work.lazyUnitsRealized) of 100 000+ rows")
    #expect(visible(window).prefix(3) == ["p0", "p0/a", "p0/b"], "\(visible(window).prefix(3))")
}
