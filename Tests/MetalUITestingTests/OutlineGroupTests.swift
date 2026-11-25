import MetalUI
import MetalUIScene
import MetalUITesting
import Foundation
import Testing

// Lane 3 of the hierarchical lists: `OutlineGroup` and its `OutlineIndex` (rulings `OG-B`, `OG-D`, `OG-K`; record 313;
// probe `docs/probes/swiftui-outline.swift` arms `P-E5` and `P-I1`). The tree is a value type whose `children` read is
// logged by id, so what the framework read is ground truth independent of the work counters. A group's label row is 24
// points, a leaf's 20, in a 200 x 200 window (the viewport holds 10 leaf rows; the window is the row holding the bottom edge
// + 1 + 2 overscan, `LZ-E`). Counts, never time.

/// Reads of a node's `children`, by node id: the key path's own getter logs.
nonisolated(unsafe) private var kidReads: [String: Int] = [:]

private struct VNode: Identifiable {
    var id: String
    var stored: [VNode]?
    var kids: [VNode]? { kidReads[id, default: 0] += 1; return stored }
}

private func N(_ id: String, _ kids: [VNode]? = nil) -> VNode { VNode(id: id, stored: kids) }

/// `count` leaves named `prefix0 ..< prefixN`.
private func leaves(_ prefix: String, _ count: Int) -> [VNode] { (0..<count).map { N("\(prefix)\($0)") } }

@MainActor private final class Tree {
    var roots: [VNode]
    init(_ roots: [VNode]) { self.roots = roots }
}

@MainActor private func row(_ node: VNode) -> some ProposalElementGroup {
    ProposalText(node.id).frame(height: Pixels(20))
}

@MainActor private func lazyOutline(_ tree: Tree, height: Float = 200) throws -> TestWindow {
    kidReads = [:]
    return try harnessWindow(size: sz(200, height)) {
        ProposalScrollView {
            LazyVStack(alignment: .leading, spacing: Pixels(0)) {
                OutlineGroup(tree.roots, children: \.kids) { row($0) }
            }
        }
    }
}

@MainActor private func eagerOutline(_ tree: Tree) throws -> TestWindow {
    kidReads = [:]
    return try harnessWindow(size: sz(200, 400)) {
        ProposalScrollView {
            VStack(alignment: .leading, spacing: Pixels(0)) {
                OutlineGroup(tree.roots, children: \.kids) { row($0) }
            }
        }
    }
}

@MainActor private func labels(_ window: TestWindow) -> [String] {
    ((try? window.elements { $0.role == .staticText || $0.role == .disclosureTriangle }) ?? [])
        .compactMap { $0.role == .staticText ? $0.value : $0.label }
}

/// Whether the row labelled `label` is where `frame` says, to a quarter of a point (the lazy index's extents are measured
/// means until a row is realised, so an anchor can sit a fraction off).
@MainActor private func isAt(_ window: TestWindow, _ label: String, _ frame: Bounds<Pixels>) -> Bool {
    guard let now = try? window.element(label: label).frame else { return false }
    return abs(now.origin.y.value - frame.origin.y.value) < 0.25 && now.size == frame.size
}

@MainActor private func settle(_ window: TestWindow) { for _ in 0..<4 { window.tick() } }

@MainActor private func toggle(_ window: TestWindow, _ label: String) throws {
    try window.click(window.element(label: label))
    settle(window)
}

@MainActor private func sum(_ work: [FrameWork], _ field: KeyPath<FrameWork, Int>) -> Int {
    work.reduce(0) { $0 + $1[keyPath: field] }
}

/// R (open after a click): a, B (b1, b2), c. Then Z, and M (n).
@MainActor private func smallTree() -> Tree {
    Tree([N("R", [N("a"), N("B", [N("b1"), N("b2")]), N("c")]), N("Z"), N("M", [N("n")])])
}

/// **A collapsed group's contents are never read, and the work counter is the ground truth.** A (open) holds a1 and B
/// (open), which holds b1 and C (collapsed); under C is a chain of groups and leaves. The visible rows are A, a1, B, b1, C;
/// the nodes under C (c1, D, d1, E, e1) are never read, while C's own `children` is (to tell group from leaf).
/// `childrenReads` summed over every frame equals the reads the data saw, to the unit. Mutations: the rebuild descending
/// into a collapsed group (c1 etc. read); a read not counted (the totals differ).
@Test @MainActor func aCollapsedGroupsContentsAreNeverRead() throws {
    let tree = Tree([N("A", [N("a1"), N("B", [N("b1"), N("C", [N("c1"), N("D", [N("d1"), N("E", [N("e1")])])])])])])
    let window = try lazyOutline(tree)
    settle(window)
    try toggle(window, "A")
    try toggle(window, "B")
    #expect(labels(window) == ["A", "a1", "B", "b1", "C"], "\(labels(window))")
    for hidden in ["c1", "D", "d1", "E", "e1"] {
        #expect(kidReads[hidden] == nil, "\(hidden) is below a collapsed group but was read \(kidReads[hidden] ?? 0) times")
    }
    #expect((kidReads["C"] ?? 0) >= 1 && (kidReads["b1"] ?? 0) >= 1, "the visible rows are read: C \(kidReads["C"] ?? 0), b1 \(kidReads["b1"] ?? 0)")
    #expect(sum(window.frameWork, \.outlineChildrenReads) == kidReads.values.reduce(0, +),
            "counted \(sum(window.frameWork, \.outlineChildrenReads)), read \(kidReads.values.reduce(0, +))")
}

/// **A scroll frame rebuilds nothing, and checks the root, each expanded group and last frame's window.** One open group of
/// 300 leaves: after it is open and settled, every scrolled frame has 0 rebuilds and `1 + 1 + (the previous frame's
/// realised rows)` validations, and reads `children` once per expanded group and once per validated row plus once per row
/// that entered. Mutations: validation skipped entirely (0 validations); the index rebuilt every frame (rebuilds 1).
@Test @MainActor func aScrollFrameRebuildsNothingAndValidatesTheGroupsAndTheWindow() throws {
    let tree = Tree([N("R", leaves("k", 300))])
    let window = try lazyOutline(tree)
    settle(window)
    try toggle(window, "R")
    var previous = window.lastFrameWork.lazyUnitsRealized
    #expect(previous == 12, "window of R + 9 leaves + 2 overscan: \(previous)")
    window.resetFrameWork()
    for _ in 0..<5 {
        window.scroll(at: pt(100, 100), byDeltaX: 0, deltaY: -150)
        settle(window)
    }
    let history = window.frameWork
    #expect(history.count >= 5, "\(history.count) frames drawn")
    for (index, work) in history.enumerated() {
        #expect(work.outlineIndexRebuilds == 0, "frame \(index): \(work.outlineIndexRebuilds) rebuilds")
        #expect(work.outlineIndexValidations == 2 + previous, "frame \(index): \(work.outlineIndexValidations) validations, window \(previous)")
        #expect(work.outlineChildrenReads >= 1 + previous && work.outlineChildrenReads <= 1 + previous + work.lazyUnitsRealized,
                "frame \(index): \(work.outlineChildrenReads) reads")
        previous = work.lazyUnitsRealized
    }
    #expect(!labels(window).contains("k0") && labels(window).contains("k40"), "scrolled: \(labels(window))")
}

/// **The frame after an expansion rebuilds once, and the frames after that do not.** R (300 leaves) and S (one child):
/// the first frame builds the index (1), R's click is the generation bump (1 rebuild), and the idle ticks after it draw
/// nothing. Collapsing R is one more. Mutation: the toggle not bumping the generation (the realised row's own check still
/// finds the mismatch, but a frame later: the click's own frame does not rebuild).
@Test @MainActor func theFrameAfterAnExpansionRebuildsOnceAndTheNextDoesNot() throws {
    let tree = Tree([N("R", leaves("k", 300)), N("S", [N("s1")])])
    let window = try lazyOutline(tree)
    settle(window)
    #expect(sum(window.frameWork, \.outlineIndexRebuilds) == 1, "the first build: \(sum(window.frameWork, \.outlineIndexRebuilds))")
    window.resetFrameWork()
    try toggle(window, "R")
    #expect(labels(window).starts(with: ["R", "k0", "k1"]), "\(labels(window))")
    #expect(sum(window.frameWork, \.outlineIndexRebuilds) == 1, "expand: \(sum(window.frameWork, \.outlineIndexRebuilds)) rebuilds")
    #expect(window.frameWork.first?.outlineIndexRebuilds == 1, "the click's own frame rebuilds (the generation, not the row's safety net a frame later): \(window.frameWork.map(\.outlineIndexRebuilds))")
    window.resetFrameWork()
    window.tick(); window.tick()
    #expect(sum(window.frameWork, \.outlineIndexRebuilds) == 0 && window.frameWork.allSatisfy { $0.outlineIndexRebuilds == 0 })
    try toggle(window, "R")
    #expect(labels(window) == ["R", "S"], "\(labels(window))")
    #expect(sum(window.frameWork, \.outlineIndexRebuilds) == 1, "collapse: \(sum(window.frameWork, \.outlineIndexRebuilds)) rebuilds")
}

/// **A rename inside the window rebuilds at once and keeps the anchor.** 300 leaves open, scrolled to about k20: renaming a
/// visible leaf (the same count, the same position) is found by the window validation in the same frame (one rebuild), the new
/// name shows, and the row that was on top is exactly where it was (`VL-G`). Mutation: the window validation skipped (the old
/// name still shows, no rebuild).
@Test @MainActor func aRenameInsideTheWindowRebuildsOnceAndKeepsTheAnchor() throws {
    let tree = Tree([N("R", leaves("k", 300))])
    let window = try lazyOutline(tree)
    settle(window)
    try toggle(window, "R")
    window.scroll(at: pt(100, 100), byDeltaX: 0, deltaY: -400)
    settle(window)
    let shown = labels(window)
    let victim = try #require(shown.dropFirst(3).first { $0.hasPrefix("k") })
    let neighbour = try #require(shown.first { $0.hasPrefix("k") && $0 != victim })
    let before = try window.element(label: neighbour).frame
    let at = try #require(Int(victim.dropFirst()))
    _ = try #require(tree.roots[0].stored)
    tree.roots[0].stored?[at].id = "renamed"
    window.resetFrameWork()
    window.window.setNeedsRedraw()
    settle(window)
    #expect(sum(window.frameWork, \.outlineIndexRebuilds) == 1, "\(sum(window.frameWork, \.outlineIndexRebuilds)) rebuilds")
    #expect(labels(window).contains("renamed") && !labels(window).contains(victim), "\(labels(window))")
    #expect(isAt(window, neighbour, before), "the anchor moved")
}

/// **A count change in an expanded group rebuilds, and rows above the window do not move the rows in it.** Inserting a leaf
/// before the window and removing one after it each change the group's `children.count`: a rebuild each, the visible rows
/// keep their screen position. Mutation: the group's count not validated (no rebuild, the data change unseen).
@Test @MainActor func aCountChangeInAnExpandedGroupRebuildsAndTheRowsStayPut() throws {
    let tree = Tree([N("R", leaves("k", 300))])
    let window = try lazyOutline(tree)
    settle(window)
    try toggle(window, "R")
    window.scroll(at: pt(100, 100), byDeltaX: 0, deltaY: -1000)
    settle(window)
    let probe = try #require(labels(window).dropFirst(3).first { $0.hasPrefix("k") })
    let before = try window.element(label: probe).frame
    _ = try #require(tree.roots[0].stored)
    tree.roots[0].stored?.insert(N("inserted"), at: 5)
    window.resetFrameWork()
    window.window.setNeedsRedraw()
    settle(window)
    #expect(sum(window.frameWork, \.outlineIndexRebuilds) == 1, "insert: \(sum(window.frameWork, \.outlineIndexRebuilds)) rebuilds")
    #expect(isAt(window, probe, before), "the row moved when a row was inserted above the window: \(probe) \(before) -> \((try? window.element(label: probe).frame) as Any)")
    tree.roots[0].stored?.removeLast()
    window.resetFrameWork()
    window.window.setNeedsRedraw()
    settle(window)
    #expect(sum(window.frameWork, \.outlineIndexRebuilds) == 1, "remove: \(sum(window.frameWork, \.outlineIndexRebuilds)) rebuilds")
    #expect(isAt(window, probe, before), "the row moved when a row was removed below the window")
}

/// **Collapsing an ancestor keeps its descendants' expansion (probe `P-E5`).** Expand R, expand B (inside R), collapse R,
/// expand R: B is still expanded (b1, b2 shown). Mutations: the disclosure's content slot noted absent while collapsed (B
/// resets: the eager form fails), the hidden expansions not kept alive (the lazy form fails once the state table reaps), the
/// expansion keyed by position instead of the element.
@Test @MainActor func collapsingAnAncestorKeepsTheDescendantsExpansionInBothForms() throws {
    for lazy in [true, false] {
        let tree = smallTree()
        let window = try lazy ? lazyOutline(tree) : eagerOutline(tree)
        settle(window)
        try toggle(window, "R")
        try toggle(window, "B")
        #expect(labels(window) == ["R", "a", "B", "b1", "b2", "c", "Z", "M"], "lazy \(lazy): \(labels(window))")
        try toggle(window, "R")
        #expect(labels(window) == ["R", "Z", "M"], "lazy \(lazy): \(labels(window))")
        try toggle(window, "R")
        #expect(labels(window) == ["R", "a", "B", "b1", "b2", "c", "Z", "M"], "lazy \(lazy), re-expanded: \(labels(window))")
    }
}

/// **An element the data drops loses its expansion; it returns collapsed.** R and B open; B is removed from R and (after a
/// frame) put back: B shows collapsed. A leaf under it comes back under the same id (b1). Mutation: no reset of the removed
/// group's subtree (B returns open).
@Test @MainActor func aRemovedNodesExpansionResetsInBothForms() throws {
    for lazy in [true, false] {
        let tree = smallTree()
        let window = try lazy ? lazyOutline(tree) : eagerOutline(tree)
        settle(window)
        try toggle(window, "R")
        try toggle(window, "B")
        let b = try #require(tree.roots[0].stored)[1]
        tree.roots[0].stored?.remove(at: 1)
        window.window.setNeedsRedraw(); settle(window)
        #expect(labels(window) == ["R", "a", "c", "Z", "M"], "lazy \(lazy), removed: \(labels(window))")
        tree.roots[0].stored?.insert(b, at: 1)
        window.window.setNeedsRedraw(); settle(window)
        #expect(labels(window) == ["R", "a", "B", "c", "Z", "M"], "lazy \(lazy), back: B must be collapsed: \(labels(window))")
    }
}

/// A node that is not `Identifiable`: its id is a key path.
private struct PathNode {
    var path: String
    var stored: [PathNode]?
    var kids: [PathNode]? { stored }
}

/// **The four initialisers.** The `id:` forms over a collection and over a root element, and the `Identifiable` forms over a
/// collection and over a root element, read the same tree the same way: a non-nil `children` (even `[]`) is a group,
/// `nil` a leaf. Each is also a `LazyVStack` and a `VStack` outline.
@Test @MainActor func theKeyPathAndIdentifiableFormsOverARootAndACollectionAllBuildTheTree() throws {
    let tree = [PathNode(path: "a", stored: [PathNode(path: "a/x"), PathNode(path: "a/empty", stored: [])]), PathNode(path: "b")]
    let identifiable = [N("a", [N("a/x"), N("a/empty", [])]), N("b")]
    func window<G: ElementGroup>(@ElementBuilder _ outline: @escaping @MainActor () -> G) throws -> TestWindow {
        try harnessWindow(size: sz(200, 200)) {
            ProposalScrollView { LazyVStack(alignment: .leading, spacing: Pixels(0)) { outline() } }
        }
    }
    let byPath = try window { OutlineGroup(tree, id: \.path, children: \.kids) { n in ProposalText(n.path).frame(height: Pixels(20)) } }
    let rootByPath = try window { OutlineGroup(tree[0], id: \.path, children: \.kids) { n in ProposalText(n.path).frame(height: Pixels(20)) } }
    let byID = try window { OutlineGroup(identifiable, children: \.kids) { n in ProposalText(n.id).frame(height: Pixels(20)) } }
    let rootByID = try window { OutlineGroup(identifiable[0], children: \.kids) { n in ProposalText(n.id).frame(height: Pixels(20)) } }
    for each in [byPath, rootByPath, byID, rootByID] { settle(each) }
    #expect(labels(byPath) == ["a", "b"] && labels(byID) == ["a", "b"], "\(labels(byPath)) \(labels(byID))")
    #expect(labels(rootByPath) == ["a"] && labels(rootByID) == ["a"], "\(labels(rootByPath)) \(labels(rootByID))")
    for each in [(byPath, "a"), (byID, "a"), (rootByPath, "a"), (rootByID, "a")] { try toggle(each.0, each.1) }
    // The empty group a/empty is a GROUP (a disclosure triangle), the leaf a/x a static text.
    let roles = try byID.elements { $0.role == .disclosureTriangle || $0.role == .staticText }.map { "\($0.role) \($0.label ?? $0.value ?? "")" }
    #expect(roles.count == 4, "\(roles)")
    #expect(try byID.elements(role: .disclosureTriangle).map(\.label) == ["a", "a/empty"], "an empty children array is a group")
    #expect(labels(byPath) == ["a", "a/x", "a/empty", "b"] && labels(rootByPath) == ["a", "a/x", "a/empty"], "\(labels(byPath)) \(labels(rootByPath))")
    #expect(labels(byID) == labels(byPath) && labels(rootByID) == labels(rootByPath))
}

/// **Expanding a folder of 10 000 children rebuilds once and realises only the window.** R (24) then 10 000 leaves of 20:
/// the window is 12 rows (as lane 2's), the click's frame rebuilds once (reading `children` once per visible row: R and its
/// 10 000 children, to the unit), the next frames rebuild nothing and validate `1 + 1 + window`. Mutation: the rebuild on
/// every frame (the zero fails), the window not honoured (10 001 realised).
@Test @MainActor func expandingATenThousandChildFolderRebuildsOnceAndRealizesTheWindow() throws {
    let tree = Tree([N("R", leaves("k", 10_000))])
    let window = try lazyOutline(tree)
    settle(window)
    kidReads = [:]
    window.resetFrameWork()
    try toggle(window, "R")
    #expect(sum(window.frameWork, \.outlineIndexRebuilds) == 1, "\(sum(window.frameWork, \.outlineIndexRebuilds)) rebuilds")
    #expect(window.lastFrameWork.lazyUnitsRealized == 12 && window.lastFrameWork.lazyUnbounded == 0, "\(window.lastFrameWork.lazyUnitsRealized) realised")
    let reads = sum(window.frameWork, \.outlineChildrenReads)
    #expect(reads == kidReads.values.reduce(0, +), "counted \(reads), read \(kidReads.values.reduce(0, +))")
    #expect(kidReads.count == 10_001 && (kidReads["R"] ?? 0) >= 1, "every visible row is read for group-or-leaf: \(kidReads.count) ids")
    window.resetFrameWork()
    window.scroll(at: pt(100, 100), byDeltaX: 0, deltaY: -300)
    settle(window)
    #expect(sum(window.frameWork, \.outlineIndexRebuilds) == 0, "scrolling: \(sum(window.frameWork, \.outlineIndexRebuilds)) rebuilds")
    #expect(window.frameWork.allSatisfy { $0.outlineChildrenReads < 100 }, "scroll reads: \(window.frameWork.map(\.outlineChildrenReads))")
}

/// **The outline works in a `VStack`, every expanded row built.** The eager form is the nested `DisclosureGroup`s: the same
/// small tree reads the same rows, and clicking a chevron toggles.
@Test @MainActor func anOutlineInAVStackShowsTheSameRows() throws {
    let tree = smallTree()
    let window = try eagerOutline(tree)
    settle(window)
    #expect(labels(window) == ["R", "Z", "M"], "\(labels(window))")
    try toggle(window, "M")
    #expect(labels(window) == ["R", "Z", "M", "n"], "\(labels(window))")
    try toggle(window, "R")
    #expect(labels(window) == ["R", "a", "B", "c", "Z", "M", "n"], "\(labels(window))")
    #expect(window.lastFrameWork.lazyUnitsRealized == 0, "an eager stack counts no lazy work")
}

/// **The window's work is the same for 500 and 5 000 siblings.** The same expanded group of 500 and of 5 000 leaves,
/// scrolled the same: equal realised rows, validations and reads per scrolled frame (rebuilds 0).
@Test @MainActor func aScrollFramesWorkDoesNotDependOnTheSizeOfTheTree() throws {
    var perSize: [[[Int]]] = []
    for count in [500, 5_000] {
        let tree = Tree([N("R", leaves("k", count))])
        let window = try lazyOutline(tree)
        settle(window)
        try toggle(window, "R")
        window.resetFrameWork()
        window.scroll(at: pt(100, 100), byDeltaX: 0, deltaY: -200)
        settle(window)
        perSize.append(window.frameWork.map { [$0.lazyUnitsRealized, $0.outlineIndexValidations, $0.outlineChildrenReads, $0.outlineIndexRebuilds] })
    }
    #expect(perSize[0] == perSize[1], "500: \(perSize[0]) 5000: \(perSize[1])")
    #expect(perSize[0].allSatisfy { $0[3] == 0 })
}

// MARK: identity

private struct HandRoot: Component {
    let roots: [VNode]
    var content: some ElementGroup { ForEach(roots) { HandNode(node: $0) } }
}

/// The recursive hand-written form (`OG-B`): a component level, an `if`/`else`, a disclosure over a `ForEach` of the same.
private struct HandNode: Component {
    let node: VNode
    @ElementBuilder var content: some ElementGroup {
        if let kids = node.stored {
            DisclosureGroup { ForEach(kids) { HandNode(node: $0) } } label: { row(node) }
        } else {
            row(node)
        }
    }
}

/// **`OutlineGroup` and the recursive `DisclosureGroup` form agree on identity.** The same tree, the same clicks, one in each:
/// every accessibility element has the same id (which is the element's structural identity), group and leaf, at every depth.
/// Mutations: the group's content slot numbered 0 instead of 1 in `OutlineScopes`; the leaf branch numbered as the group's;
/// the node's component level dropped.
@Test @MainActor func anOutlineGroupAndTheHandWrittenRecursiveFormHaveTheSameIdentity() throws {
    let roots = smallTree().roots
    let outline = try lazyOutline(Tree(roots))
    let hand = try harnessWindow(size: sz(200, 200)) {
        ProposalScrollView { LazyVStack(alignment: .leading, spacing: Pixels(0)) { HandRoot(roots: roots) } }
    }
    for window in [outline, hand] {
        settle(window)
        try toggle(window, "R")
        try toggle(window, "B")
        try toggle(window, "M")
    }
    #expect(labels(outline) == ["R", "a", "B", "b1", "b2", "c", "Z", "M", "n"] && labels(hand) == labels(outline), "\(labels(outline)) \(labels(hand))")
    let ids = { (window: TestWindow) throws -> Set<AccessibilityNodeID> in
        Set(try window.elements { $0.role == .staticText || $0.role == .disclosureTriangle }.map(\.id))
    }
    let outlineIDs = try ids(outline), handIDs = try ids(hand)
    #expect(outlineIDs.count == 9 && outlineIDs == handIDs, "only in outline \(outlineIDs.subtracting(handIDs).count), only in hand \(handIDs.subtracting(outlineIDs).count)")
}

/// A leaf whose `@State` is seeded once per identity: the serial it minted.
@MainActor private final class Serials {
    var next = 0
    var seen: [String: Int] = [:]
}

private struct StatefulLeaf: Component {
    let name: String
    let serials: Serials
    @State private var serial: Int

    init(name: String, serials: Serials) {
        self.name = name
        self.serials = serials
        serials.next += 1
        _serial = State(wrappedValue: serials.next)
    }

    var content: some ElementGroup {
        // swiftlint:disable:next redundant_discardable_let - inside a result builder `let _ =` is a declaration; `_ =` would be a stray statement
        let _ = serials.seen[name] = serial
        ProposalText(name).frame(height: Pixels(20))
    }
}

/// **A leaf realised by the index keeps its `@State` through a scroll away and back (`TB-AH`, `LZ-H`).** 300 leaves under an
/// open group: leaf k0 mints a serial when first realised, the window moves a long way and returns, and k0 reads the first
/// serial. Mutation (shown red): `OutlineScopes.children` numbered 0 (the group's content slot collides with its label row).
@Test @MainActor func aLeafKeepsItsStateThroughAScrollOutAndBack() throws {
    let serials = Serials()
    let tree = Tree([N("R", leaves("k", 300))])
    kidReads = [:]
    let window = try harnessWindow(size: sz(200, 200)) {
        ProposalScrollView {
            LazyVStack(alignment: .leading, spacing: Pixels(0)) {
                OutlineGroup(tree.roots, children: \.kids) { StatefulLeaf(name: $0.id, serials: serials) }
            }
        }
    }
    settle(window)
    try toggle(window, "R")
    let first = try #require(serials.seen["k0"])
    window.scroll(at: pt(100, 100), byDeltaX: 0, deltaY: -2000)
    settle(window)
    #expect(!labels(window).contains("k0"))
    window.scroll(at: pt(100, 100), byDeltaX: 0, deltaY: 4000)
    settle(window)
    #expect(labels(window).contains("k0") && serials.seen["k0"] == first, "serial \(String(describing: serials.seen["k0"])) vs \(first)")
}

/// A bar of 300 stateful rows: enough `@State` entries that the state table reaps (`sweepThreshold` 256) an entry nothing
/// marks for three frames (`TB-AH`).
private struct Ballast: Component {
    @State private var count = 0
    var content: some ElementGroup { ProposalText("x").frame(height: Pixels(1)) }
}

/// **A hidden group's expansion survives the state table's reaping.** R and B open, R collapsed: B's expansion slot is
/// under a collapsed ancestor, so nothing builds it; with the table over its reaping threshold and several frames drawn, an
/// unmarked slot would be reaped. Re-expanding R shows B still open. Mutation: the index not marking its hidden expanded
/// groups (B comes back collapsed).
@Test @MainActor func aHiddenGroupsExpansionSurvivesTheStateTablesReaping() throws {
    let tree = smallTree()
    kidReads = [:]
    let window = try harnessWindow(size: sz(200, 200)) {
        ProposalScrollView {
            VStack(alignment: .leading, spacing: Pixels(0)) {
                LazyVStack(alignment: .leading, spacing: Pixels(0)) {
                    OutlineGroup(tree.roots, children: \.kids) { row($0) }
                }
                VStack(spacing: Pixels(0)) { ForEach(0..<300, id: \.self) { _ in Ballast() } }
            }
        }
    }
    settle(window)
    try toggle(window, "R")
    try toggle(window, "B")
    try toggle(window, "R")
    for _ in 0..<12 { window.window.setNeedsRedraw(); window.tick() }
    try toggle(window, "R")
    #expect(Array(labels(window).prefix(8)) == ["R", "a", "B", "b1", "b2", "c", "Z", "M"], "\(labels(window))")
}

/// **The lazy outline's ids are the eager outline's.** The same tree and clicks in a `LazyVStack` and a `VStack`: every row
/// (label rows and leaves, at every depth) has the same accessibility id, the element's structural identity, so a tree moved
/// between the two keeps its `@State`. Mutation: `OutlineScopes.leafBranch` numbered 0.
@Test @MainActor func anOutlineInALazyAndInAnEagerStackHasTheSameIdentity() throws {
    let lazy = try lazyOutline(smallTree()), eager = try eagerOutline(smallTree())
    for window in [lazy, eager] {
        settle(window)
        try toggle(window, "R")
        try toggle(window, "B")
        try toggle(window, "M")
    }
    #expect(labels(lazy) == labels(eager) && labels(lazy).count == 9, "\(labels(lazy)) \(labels(eager))")
    let ids = { (window: TestWindow) throws -> Set<AccessibilityNodeID> in
        Set(try window.elements { $0.role == .staticText || $0.role == .disclosureTriangle }.map(\.id))
    }
    let lazyIDs = try ids(lazy), eagerIDs = try ids(eager)
    #expect(lazyIDs.count == 9 && lazyIDs == eagerIDs, "lazy only \(lazyIDs.subtracting(eagerIDs).count), eager only \(eagerIDs.subtracting(lazyIDs).count)")
}
