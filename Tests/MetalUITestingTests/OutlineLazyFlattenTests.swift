import MetalUI
import MetalUIScene
import MetalUITesting
import Foundation
import Testing

// Lane 2 of the hierarchical lists: a `LazyVStack` of recursive `Component` rows holding a `DisclosureGroup`
// stays lazy (rulings `OG-B`, `OG-C`, extending `LZ-B`; record 312). The shape is Alloy's project tree:
//
//     LazyVStack(spacing: 0) { ForEach(roots) { NodeRow(node: $0) } }
//     NodeRow.content: if folder { DisclosureGroup(isExpanded:) { ForEach(kids) { NodeRow } } label: { Text(name) } }
//                      else { leaf }
//
// A folder's label row is 24 points, a leaf 20, spacing 0, in a 200 x 200 window: the viewport holds 10 leaf rows and the
// window is the row holding the bottom edge + 1 + 2 overscan (`LZ-E`). Counts, never time.

/// A tree node. Its counters say what the framework evaluated.
@MainActor private final class Node: Identifiable {
    let name: String
    var expanded: Bool
    var kids: [Node]
    var isFolder: Bool
    /// How many times a row for this node built its body, and how many times its group's content closure ran.
    var bodies = 0
    var contentCalls = 0

    init(_ name: String, folder: Bool = false, expanded: Bool = false, kids: [Node] = []) {
        self.name = name
        self.isFolder = folder || !kids.isEmpty
        self.expanded = expanded
        self.kids = kids
    }

    nonisolated var id: String { name }
    var binding: Binding<Bool> { Binding(get: { self.expanded }, set: { self.expanded = $0 }) }
    func walk(_ visit: (Node) -> Void) { visit(self); kids.forEach { $0.walk(visit) } }
}

/// What the leaves minted: a leaf's `@State` is seeded once, at its identity.
@MainActor private final class Serials {
    var next = 0
    var seen: [String: Int] = [:]
    func mint() -> Int { next += 1; return next }
}

private struct LeafRow: Component {
    let name: String
    let serials: Serials
    @State private var serial: Int

    init(name: String, serials: Serials) {
        self.name = name
        self.serials = serials
        _serial = State(wrappedValue: serials.mint())
    }

    var content: some ProposalElementGroup {
        // swiftlint:disable:next redundant_discardable_let - inside a result builder `let _ =` is a declaration; `_ =` would be a stray statement
        let _ = serials.seen[name] = serial
        ProposalText(name).frame(height: Pixels(20))
    }
}

private struct NodeRow: Component {
    let node: Node
    let serials: Serials

    @ElementBuilder var content: some ElementGroup {
        // swiftlint:disable:next redundant_discardable_let - inside a result builder `let _ =` is a declaration; `_ =` would be a stray statement
        let _ = node.bodies += 1
        if node.isFolder {
            DisclosureGroup(isExpanded: node.binding) {
                // swiftlint:disable:next redundant_discardable_let - inside a result builder `let _ =` is a declaration; `_ =` would be a stray statement
                let _ = node.contentCalls += 1
                ForEach(node.kids) { NodeRow(node: $0, serials: serials) }
            } label: { ProposalText(node.name) }
        } else {
            LeafRow(name: node.name, serials: serials)
        }
    }
}

@MainActor private func outline(_ roots: [Node], serials: Serials = Serials(), height: Float = 200) throws -> TestWindow {
    try harnessWindow(size: sz(200, height)) {
        ProposalScrollView {
            LazyVStack(alignment: .leading, spacing: Pixels(0)) {
                ForEach(roots) { NodeRow(node: $0, serials: serials) }
            }
        }
    }
}

@MainActor private func labels(_ window: TestWindow) throws -> [String] {
    // A leaf is a static text; a folder's label row is a disclosure triangle named by its label.
    try window.elements { $0.role == .staticText || $0.role == .disclosureTriangle }
        .compactMap { $0.role == .staticText ? $0.value : $0.label }
}

/// `labels` for use inside `#expect`'s autoclosure.
@MainActor private func shown(_ window: TestWindow) -> [String] { (try? labels(window)) ?? ["<no tree>"] }

@MainActor private func settle(_ window: TestWindow) {
    for _ in 0..<4 { window.tick() }
}

/// A small tree: A (open: A1, A2 (open: A2a, A2b)), B (closed: B1), C.
@MainActor private func smallTree() -> [Node] {
    [Node("A", expanded: true, kids: [
        Node("A1"),
        Node("A2", expanded: true, kids: [Node("A2a"), Node("A2b")]),
    ]),
     Node("B", kids: [Node("B1")]),
     Node("C")]
}

/// **Units are the label plus the expanded content, recursively; the container stays lazy.** The tree above reads as
/// A, A1, A2, A2a, A2b, B, C = 7 units (B's content is a collapsed group's: none), all realised (7 < the window), in
/// that order, and `lazyUnbounded` is 0: the container did not go eager through the `Component`, the `if`/`else` or the
/// `DisclosureGroup`. Mutations: `lazyFlattenRoot` always taking the plain `lazyFlatten` (the `if` makes the
/// container eager: `lazyUnbounded` 1 and, with a 500-row tail in the next test, every row built); the
/// disclosure's content slot not flattened (A1, A2... missing).
@Test @MainActor func aRecursiveComponentTreeIsLabelPlusExpandedContentAndStaysLazy() throws {
    let window = try outline(smallTree())
    settle(window)
    #expect(shown(window) == ["A", "A1", "A2", "A2a", "A2b", "B", "C"], "\(shown(window))")
    let work = window.lastFrameWork
    #expect(work.lazyUnitsRealized == 7 && work.lazyUnbounded == 0, "\(work.lazyUnitsRealized) units, \(work.lazyUnbounded) unbounded")
}

/// **Clicking a header toggles it and the units update on the next frame.** Rows: A 0-24, A1 24-44, A2 44-68,
/// A2a 68-88, A2b 88-108, B 108-132, C 132-152. Click A2's header (y 56): its two children go, 5 units. Click A
/// (y 12): 3 units (A, B, C). Click B (then at y 24 + 24): expanded, B1 appears, 4 units. Mutation: the lazy path
/// realising a bare header (its `Button` not realised under the stack's level): the click lands nowhere and
/// the counts never move.
@Test @MainActor func clickingAHeaderInsideALazyStackTogglesItAndTheUnitsFollow() throws {
    let window = try outline(smallTree())
    settle(window)
    window.click(at: pt(100, 56)); settle(window)
    #expect(shown(window) == ["A", "A1", "A2", "B", "C"], "\(shown(window))")
    #expect(window.lastFrameWork.lazyUnitsRealized == 5 && window.lastFrameWork.lazyUnbounded == 0)
    window.click(at: pt(100, 12)); settle(window)
    #expect(shown(window) == ["A", "B", "C"], "\(shown(window))")
    #expect(window.lastFrameWork.lazyUnitsRealized == 3)
    window.click(at: pt(100, 36)); settle(window)   // B is now at 24 .. 48
    #expect(shown(window) == ["A", "B", "B1", "C"], "\(shown(window))")
    #expect(window.lastFrameWork.lazyUnitsRealized == 4)
}

/// **A folder of 10 000 expanded children realises only the window.** R (24) then 10 000 leaves of 20: after the cold
/// frame the viewport's bottom edge 200 is in unit 9 (R is unit 0, ending at 24; unit 9 spans 184 .. 204), so the
/// window is 0 ..< 9 + 1 + 2 = **12** units. Mutation: the tree source realising every element (10 001).
@Test @MainActor func aFolderOfTenThousandExpandedChildrenRealizesOnlyTheWindow() throws {
    let kids = (0..<10_000).map { Node("k\($0)") }
    let window = try outline([Node("R", expanded: true, kids: kids)])
    settle(window)
    let work = window.lastFrameWork
    #expect(work.lazyUnitsRealized == 12 && work.lazyUnbounded == 0, "\(work.lazyUnitsRealized) units, \(work.lazyUnbounded) unbounded")
    #expect(shown(window).count == 12, "\(shown(window).count)")
}

/// **A collapsed subtree costs nothing.** Root R is open over two folders: F (collapsed, with a chain of nested open
/// folders and leaves below it) and a leaf. F's content closure is never called, and none of the nodes below F
/// builds a body or a content closure, over four frames; the open root's are (the control: the closure runs, once per
/// frame). Mutation: the group evaluating its content while collapsed (F's `contentCalls` > 0).
@Test @MainActor func aCollapsedSubtreeEvaluatesNothingBelowIt() throws {
    let deep = Node("d0", expanded: true, kids: [Node("d1", expanded: true, kids: [Node("d2", expanded: true,
                    kids: [Node("d3", expanded: true, kids: [Node("leaf")])])])])
    let folder = Node("F", expanded: false, kids: [deep])
    let root = Node("R", expanded: true, kids: [folder, Node("x")])
    let window = try outline([root])
    settle(window)
    var below: [Node] = []
    folder.kids.forEach { $0.walk { below.append($0) } }
    #expect(folder.contentCalls == 0, "F is collapsed: \(folder.contentCalls) content calls")
    #expect(below.allSatisfy { $0.bodies == 0 && $0.contentCalls == 0 }, "below F: \(below.map { ($0.name, $0.bodies, $0.contentCalls) })")
    #expect(root.contentCalls >= 1 && folder.bodies >= 1, "control: the open root evaluates (\(root.contentCalls), \(folder.bodies))")
    #expect(shown(window) == ["R", "F", "x"], "\(shown(window))")
    // Expanding F (its header is at 24 .. 48) evaluates its content on the next frame, and only then.
    window.click(at: pt(100, 36)); settle(window)
    #expect(folder.expanded && folder.contentCalls >= 1, "F expanded: \(folder.contentCalls) content calls")
    #expect(shown(window).starts(with: ["R", "F", "d0", "d1", "d2", "d3"]), "\(shown(window))")
}

/// **A leaf realised in the window keeps its `@State` through a scroll out and back.** 300 leaves under an open folder;
/// the first leaf's serial is minted at its first realisation, the window moves to leaf ~100 and back, and the
/// serial read at the end is the first one (`LZ-H`, `TB-AH`). Mutation: the disclosure's content slot noted absent
/// before it is noted produced (the slot is reset every frame: the leaf returns with a new serial). (`noteLoop` on
/// the tree source's slot is inert: its element scopes are never noted under a windowed parent.)
@Test @MainActor func aLeafScrolledOutAndBackKeepsItsState() throws {
    let serials = Serials()
    let kids = (0..<300).map { Node("k\($0)") }
    let window = try outline([Node("R", expanded: true, kids: kids)], serials: serials)
    settle(window)
    let first = try #require(serials.seen["k0"])
    window.scroll(at: pt(100, 100), byDeltaX: 0, deltaY: -2000)
    settle(window)
    #expect(shown(window).contains("k95") || shown(window).contains("k100"), "\(shown(window))")
    window.scroll(at: pt(100, 100), byDeltaX: 0, deltaY: 4000)
    settle(window)
    #expect(shown(window).contains("k0"))
    #expect(serials.seen["k0"] == first, "serial \(String(describing: serials.seen["k0"])) vs \(first)")
}

/// A row whose body is a bare `if` (no `else`): a folder is a disclosure, a leaf contributes nothing.
private struct FolderOnlyRow: Component {
    let node: Node

    @ElementBuilder var content: some ElementGroup {
        if node.isFolder {
            DisclosureGroup(isExpanded: node.binding) {
                ForEach(node.kids) { FolderOnlyRow(node: $0) }
            } label: { ProposalText(node.name) }
        }
    }
}

/// **A bare `if` inside a `Component` flattens too (`OG-C`).** R (open) holds F (open, with a leaf x), G (collapsed) and a
/// leaf y; the leaves' rows are `if` with nothing: 0 units. So R, F, G = 3 units and the container is not unbounded.
/// Mutation: `OptionalGroup` not tree-capable (the row is then one opaque unit, so one unit realised for R alone).
@Test @MainActor func aBareIfInsideAComponentFlattensToItsContentOrNothing() throws {
    let root = Node("R", expanded: true, kids: [Node("F", expanded: true, kids: [Node("x")]), Node("G", kids: [Node("g1")]), Node("y")])
    let window = try harnessWindow(size: sz(200, 200)) {
        ProposalScrollView {
            LazyVStack(alignment: .leading, spacing: Pixels(0)) { ForEach([root]) { FolderOnlyRow(node: $0) } }
        }
    }
    settle(window)
    #expect(shown(window) == ["R", "F", "G"], "\(shown(window))")
    #expect(window.lastFrameWork.lazyUnitsRealized == 3 && window.lastFrameWork.lazyUnbounded == 0)
}
