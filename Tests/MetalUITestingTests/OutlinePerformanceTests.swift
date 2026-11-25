import MetalUI
import MetalUIScene
import MetalUITesting
import Foundation
import Observation
import Testing

// Lane 8 of the hierarchical lists: the content form's flatten cache (ruling `OG-O`, `OG-I`; record 318; Alloy's binding
// requirement, design section 9a item 1). Alloy's shape, over `@Observable` model classes:
//
//     List(selection: $sel) { ForEach(model.roots) { NodeRow(node: $0) } }
//     NodeRow.content: if node.isFolder { DisclosureGroup(isExpanded: $node.isExpanded) { ForEach(node.children) { NodeRow } } label: {...} }
//                      else { leaf }
//
// A frame in which nothing changed (no scroll, no observed model change, no bound state change) evaluates no row body and
// walks no tree; a scroll frame evaluates nothing either, whatever the tree's size; a model change walks once and shows next
// frame. Counts, never time. A 300 x 400 window: a row is 32 high, the first 10 below the top.

@Observable @MainActor private final class PNode: Identifiable {
    nonisolated let id: String
    var name: String
    var isFolder: Bool
    var isExpanded: Bool
    var children: [PNode]

    init(_ id: String, name: String? = nil, expanded: Bool = false, children: [PNode]? = nil) {
        self.id = id
        self.name = name ?? id
        self.isFolder = children != nil
        self.isExpanded = expanded
        self.children = children ?? []
    }
}

@Observable @MainActor private final class PModel {
    var roots: [PNode]
    var selection: String?
    @ObservationIgnored var proxy: ScrollViewProxy?
    init(_ roots: [PNode]) { self.roots = roots }
}

/// How many `NodeRow` bodies ran: the steady-frame guard's number.
@MainActor private enum Bodies {
    static var count = 0
    /// The `@State` serial each row's body saw, by node id; a row whose state was lost reads a new one.
    static var seen: [String: Int] = [:]
    static var minted = 0
    static func mint() -> Int { minted += 1; return minted }
}

private struct NodeRow: Component {
    @Bindable var node: PNode
    @State private var serial = Bodies.mint()
    @ElementBuilder var content: some ElementGroup {
        let _: Void = Bodies.count += 1
        let _: Void = Bodies.seen[node.id] = serial
        if node.isFolder {
            DisclosureGroup(isExpanded: $node.isExpanded) {
                ForEach(node.children) { NodeRow(node: $0) }
            } label: { ProposalText(node.name) }
        } else {
            ProposalText(node.name)
        }
    }
}

@MainActor private func leaves(_ prefix: String, _ count: Int) -> [PNode] { (0..<count).map { PNode("\(prefix)\($0)") } }

@MainActor private func listWindow(_ model: PModel, height: Float = 400) throws -> TestWindow {
    let selection = Binding<String?>(get: { model.selection }, set: { model.selection = $0 })
    let window = try harnessWindow(size: sz(300, height)) {
        VStack(spacing: Pixels(0)) {
            ScrollViewReader { proxy in
                let _: Void = model.proxy = proxy
                ProposalScrollView {
                    List(selection: selection) { ForEach(model.roots) { NodeRow(node: $0) } }
                }
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

/// A frame the window draws though nothing changed.
@MainActor private func idleFrame(_ window: TestWindow) {
    window.window.setNeedsRedraw()
    window.tick()
}

@MainActor private func chevron(_ window: TestWindow, _ name: String, modifiers: EventModifiers = []) {
    let rows = visible(window)
    guard let row = rows.firstIndex(of: name) else { Issue.record("\(name) is not visible: \(rows)"); return }
    let depth = name.filter { $0 == "/" }.count
    window.click(at: pt(12 + 12 * Float(depth) + 6, rowY(row)), modifierFlags: modifiers)
    settle(window)
}

private func evaluations(_ work: [FrameWork]) -> Int { work.reduce(0) { $0 + $1.outlineContentEvaluations } }
private func rebuilds(_ work: [FrameWork]) -> Int { work.reduce(0) { $0 + $1.outlineContentRebuilds } }
private func hits(_ work: [FrameWork]) -> Int { work.reduce(0) { $0 + $1.outlineContentHits } }

/// Three roots, each an expanded folder of six leaves.
@MainActor private func smallTree() -> [PNode] {
    (0..<3).map { r in PNode("r\(r)", expanded: true, children: leaves("r\(r)/l", 6)) }
}

// A model write dirties the window through the observation `onChange`. On Apple the handler runs on the writer's (main) thread
// and marks the window at once; off Apple the Swift Testing main actor is a pool thread, so the mark hops (`ContentMemoHandle`
// record 123) and a bare `tick()` right after the write draws nothing. The flag the cache reads is set synchronously either
// way, so the cache is never stale; the tests wait with `runUntilIdle()` after a model write.

// MARK: - the idle frame

/// **Alloy's requirement: an idle frame does zero outline evaluation.** Three expanded folders of six leaves: after the tree
/// settles, five frames in which nothing changed run no `NodeRow` body (the steady-frame guard's number), evaluate no content
/// (`outlineContentEvaluations` 0), rebuild nothing (0 walks, 0 index rebuilds) and take the cache (one hit a frame); the top
/// level is compared, 3 `ForEach` closures a frame. Control: the settling frames did evaluate (the cache was made then).
/// Mutation: the cache off (`cachesOutlineContent`) puts 45 evaluations in every frame (21 `ForEach` closures, 21 bodies, 3 group contents); replaying nothing on a hit
/// (the journal not applied) fails `aHitKeepsTheStatesItsRowsHold`.
@Test @MainActor func anIdleFrameEvaluatesNothingAndWalksNothing() throws {
    let model = PModel(smallTree())
    let window = try listWindow(model)
    #expect(evaluations(window.frameWork) > 0 && rebuilds(window.frameWork) >= 1, "control: the first frames walked")
    let bodies = Bodies.count
    window.resetFrameWork()
    for _ in 0..<5 { idleFrame(window) }
    #expect(window.frameWork.count == 5 && window.frameWork.allSatisfy { $0.builds >= 1 }, "five built frames: \(window.frameWork.count)")
    #expect(evaluations(window.frameWork) == 0, "evaluations \(window.frameWork.map(\.outlineContentEvaluations))")
    #expect(rebuilds(window.frameWork) == 0 && window.frameWork.allSatisfy { $0.outlineIndexRebuilds == 0 },
            "rebuilds \(window.frameWork.map(\.outlineContentRebuilds))")
    #expect(hits(window.frameWork) == 5, "hits \(window.frameWork.map(\.outlineContentHits))")
    #expect(window.frameWork.allSatisfy { $0.outlineContentChecks == 3 }, "checks \(window.frameWork.map(\.outlineContentChecks))")
    #expect(Bodies.count == bodies, "no NodeRow body ran: \(Bodies.count - bodies)")
    #expect(visible(window).prefix(3) == ["r0", "r0/l0", "r0/l1"], "\(visible(window).prefix(3))")
}

/// **The same frames with the cache off evaluate every row** (the control that makes the zero above mean something, and the
/// mutation "disable the cache", live): 45 evaluations and a walk in each frame, the same rows.
@Test @MainActor func withTheCacheOffEveryFrameWalksTheTree() throws {
    let model = PModel(smallTree())
    let window = try listWindow(model)
    window.window.testingContentMemos.cachesOutlineContent = false
    window.resetFrameWork()
    for _ in 0..<3 { idleFrame(window) }
    #expect(window.frameWork.map(\.outlineContentEvaluations) == [45, 45, 45], "\(window.frameWork.map(\.outlineContentEvaluations))")
    #expect(rebuilds(window.frameWork) == 3 && hits(window.frameWork) == 0)
    #expect(visible(window).prefix(3) == ["r0", "r0/l0", "r0/l1"], "\(visible(window).prefix(3))")
}

// MARK: - the scroll frame

/// **A scroll frame's work does not depend on the tree's size.** One expanded folder of 500 and of 5 000 leaves, scrolled the
/// same: each frame evaluates 0, walks 0 times, hits once, and realises the same units; no body runs. Mutation: the cache off
/// (each frame evaluates 502 and 5 002).
@Test @MainActor func aContentListScrollFrameEvaluatesNothingWhateverTheTreesSize() throws {
    var perSize: [[[Int]]] = []
    for count in [500, 5_000] {
        let model = PModel([PNode("R", expanded: true, children: leaves("k", count))])
        let window = try listWindow(model)
        let bodies = Bodies.count
        window.resetFrameWork()
        window.scroll(at: pt(100, 100), byDeltaX: 0, deltaY: -200)
        settle(window)
        window.scroll(at: pt(100, 100), byDeltaX: 0, deltaY: -640)
        settle(window)
        #expect(Bodies.count == bodies, "\(count): scrolling ran \(Bodies.count - bodies) bodies")
        #expect(evaluations(window.frameWork) == 0 && rebuilds(window.frameWork) == 0, "\(count): \(window.frameWork.map(\.outlineContentEvaluations))")
        #expect(hits(window.frameWork) >= 2, "\(count): hits \(window.frameWork.map(\.outlineContentHits))")
        perSize.append(window.frameWork.map {
            [$0.outlineContentEvaluations, $0.outlineContentRebuilds, $0.outlineContentHits, $0.outlineContentChecks,
             $0.lazyUnitsRealized, $0.outlineIndexRebuilds]
        })
    }
    #expect(perSize[0] == perSize[1], "500: \(perSize[0])\n5000: \(perSize[1])")
}

// MARK: - a model change

/// **Renaming a visible node shows the next frame**, with one walk (the session fired), and nothing is evaluated the frame
/// after it. Mutation: the session not run (`entry.buildSession.run` replaced by the bare walk): the label stays.
@Test @MainActor func renamingAVisibleNodeShowsNextFrame() async throws {
    let model = PModel(smallTree())
    let window = try listWindow(model)
    let leaf = model.roots[1].children[2]
    window.resetFrameWork()
    leaf.name = "renamed"
    try await window.runUntilIdle()
    #expect(texts(window)["renamed"] != nil && texts(window)["r1/l2"] == nil, "\(visible(window))")
    #expect(rebuilds(window.frameWork) == 1 && hits(window.frameWork) == 0, "rebuilds \(window.frameWork.map(\.outlineContentRebuilds))")
    window.resetFrameWork()
    for _ in 0..<2 { idleFrame(window) }
    #expect(evaluations(window.frameWork) == 0 && hits(window.frameWork) == 2, "after: \(window.frameWork.map(\.outlineContentEvaluations))")
}

/// **Renaming an offscreen node is right when scrolled to**, and costs one walk at the change, not at the scroll. 500 leaves,
/// leaf 300 renamed; scrolling to it evaluates nothing and shows the new name.
@Test @MainActor func renamingAnOffscreenNodeIsRightWhenScrolledTo() async throws {
    let model = PModel([PNode("R", expanded: true, children: leaves("k", 500))])
    let window = try listWindow(model)
    window.resetFrameWork()
    model.roots[0].children[300].name = "renamed300"
    try await window.runUntilIdle()
    #expect(rebuilds(window.frameWork) == 1, "one walk at the change: \(window.frameWork.map(\.outlineContentRebuilds))")
    window.resetFrameWork()
    window.scroll(at: pt(100, 100), byDeltaX: 0, deltaY: -9_650)
    settle(window)
    #expect(evaluations(window.frameWork) == 0, "scrolling evaluated \(evaluations(window.frameWork))")
    #expect(texts(window)["renamed300"] != nil, "\(visible(window))")
}

/// **Adding and removing a child of an expanded folder changes the row count the next frame.** The rows are the folder, its
/// children and the other roots'; one walk each.
@Test @MainActor func addingAndRemovingAChildChangesTheRowsNextFrame() async throws {
    let model = PModel([PNode("A", expanded: true, children: leaves("A/a", 2)), PNode("Z", children: nil)])
    let window = try listWindow(model)
    #expect(visible(window) == ["A", "A/a0", "A/a1", "Z"], "\(visible(window))")
    window.resetFrameWork()
    model.roots[0].children.append(PNode("A/new"))
    try await window.runUntilIdle()
    #expect(visible(window) == ["A", "A/a0", "A/a1", "A/new", "Z"], "\(visible(window))")
    #expect(rebuilds(window.frameWork) == 1, "\(window.frameWork.map(\.outlineContentRebuilds))")
    model.roots[0].children.removeFirst()
    try await window.runUntilIdle()
    #expect(visible(window) == ["A", "A/a1", "A/new", "Z"], "\(visible(window))")
    model.roots.append(PNode("Y"))
    try await window.runUntilIdle()
    #expect(visible(window) == ["A", "A/a1", "A/new", "Z", "Y"], "\(visible(window))")
}

/// **Expanding by the model, the chevron and the keys all re-walk once and show the rows.**
@Test @MainActor func expandingByTheModelTheChevronAndTheKeysShowsTheRows() async throws {
    let tree = [PNode("A", children: [PNode("A/B", children: leaves("A/B/", 2)), PNode("A/C")]), PNode("Z")]
    let model = PModel(tree)
    let window = try listWindow(model)
    #expect(visible(window) == ["A", "Z"], "\(visible(window))")
    model.roots[0].isExpanded = true                           // the model
    try await window.runUntilIdle()
    #expect(visible(window) == ["A", "A/B", "A/C", "Z"], "model: \(visible(window))")
    window.resetFrameWork()
    chevron(window, "A/B")                                       // the chevron
    #expect(visible(window) == ["A", "A/B", "A/B/0", "A/B/1", "A/C", "Z"], "chevron: \(visible(window))")
    #expect(rebuilds(window.frameWork) == 1, "one walk: \(window.frameWork.map(\.outlineContentRebuilds))")
    chevron(window, "A/B")
    #expect(visible(window) == ["A", "A/B", "A/C", "Z"], "chevron closes: \(visible(window))")
    window.click(at: pt(200, rowY(0)))                           // select A, then ← and →
    settle(window)
    window.typeKey(.leftArrow, modifierFlags: [])
    settle(window)
    #expect(visible(window) == ["A", "Z"], "left: \(visible(window))")
    window.typeKey(.rightArrow, modifierFlags: [])
    settle(window)
    #expect(visible(window) == ["A", "A/B", "A/C", "Z"], "right: \(visible(window))")
    window.typeKey(.leftArrow, modifierFlags: [])
    settle(window)
    window.typeKey(.rightArrow, modifierFlags: .option)           // the cascade never reads or makes the cache
    settle(window)
    #expect(model.roots[0].children[0].isExpanded, "the cascade wrote A/B's binding")
    #expect(visible(window) == ["A", "A/B", "A/B/0", "A/B/1", "A/C", "Z"], "cascade: \(visible(window))")
    window.resetFrameWork()
    for _ in 0..<2 { idleFrame(window) }
    #expect(evaluations(window.frameWork) == 0 && hits(window.frameWork) == 2, "settled again: \(window.frameWork.map(\.outlineContentHits))")
}

/// **A hit keeps the states its rows hold.** 400 expanded leaves, each row with a `@State`: the table is past its reaping
/// threshold (256), so an entry nothing marks for three frames is dropped. Twelve idle frames of hits, then a rename (a
/// walk): every row reads the serial it had, because a hit replays the walk's marks. Mutation: a hit that applies no journal
/// (`frame.reapply` removed): the rows' states are reaped and the walk reads new serials.
@Test @MainActor func aHitKeepsTheStatesItsRowsHold() async throws {
    Bodies.seen = [:]
    let model = PModel([PNode("R", expanded: true, children: leaves("k", 400))])
    let window = try listWindow(model)
    let before = Bodies.seen
    #expect(before.count == 401, "\(before.count)")
    window.resetFrameWork()
    for _ in 0..<12 { idleFrame(window) }
    #expect(hits(window.frameWork) == 12 && evaluations(window.frameWork) == 0, "\(hits(window.frameWork))")
    model.roots[0].children[5].name = "renamed"
    try await window.runUntilIdle()
    #expect(rebuilds(window.frameWork) == 1)
    #expect(Bodies.seen == before, "serials moved: \(Bodies.seen.filter { before[$0.key] != $0.value }.count) rows")
}

// MARK: - the reveal (divergence 1085) over the cache

/// **The reveal still lands the row the same frame.** Expanding two groups by the model, selecting a row and `scrollTo` it in
/// ONE transaction: the observation fires, the walk runs once, and the row is in view after two frames.
@Test @MainActor func theRevealLandsTheRowOverTheCache() async throws {
    let tree = (0..<3).map { r in PNode("R\(r)", children: [PNode("R\(r)/S", children: leaves("R\(r)/S/L", 20))]) }
    let model = PModel(tree)
    let window = try listWindow(model)
    #expect(visible(window) == ["R0", "R1", "R2"], "\(visible(window))")
    model.roots[2].isExpanded = true
    model.roots[2].children[0].isExpanded = true
    model.selection = "R2/S/L15"
    model.proxy?.scrollTo("R2/S/L15")
    try await window.runUntilIdle()
    
    let rows = ((try? window.elements(role: .row)) ?? []).filter(\.isSelected)
    let target = try #require(rows.first, "the selected row is realised")
    let top = target.frame.origin.y.value, bottom = top + target.frame.size.height.value
    #expect(top >= 0 && bottom <= 400, "inside the viewport: \(top)..\(bottom)")
    #expect(texts(window)["R2/S/L15"] != nil)
}

// MARK: - bound state

private struct UncontrolledRow: Component {
    @Bindable var node: PNode
    @ElementBuilder var content: some ElementGroup {
        if node.isFolder {
            DisclosureGroup {
                ForEach(node.children) { UncontrolledRow(node: $0) }
            } label: { ProposalText(node.name) }
        } else {
            ProposalText(node.name)
        }
    }
}

/// **A bound `@State` the walk read changes the cache.** An uncontrolled `DisclosureGroup` keeps its expansion in a state
/// slot: after settling the frames hit, a click on the chevron writes the slot (a new version) and the next frame walks and
/// shows the children; the frames after it hit again. Mutation: `outlineDependenciesHold` ignoring `stateReads`: the click
/// shows nothing.
@Test @MainActor func aBoundStateTheWalkReadChangesTheCache() throws {
    let roots = [PNode("A", children: leaves("A/", 2)), PNode("Z")]
    let window = try harnessWindow(size: sz(300, 400)) {
        ProposalScrollView { List { ForEach(roots) { UncontrolledRow(node: $0) } } }
    }
    settle(window)
    window.resetFrameWork()
    idleFrame(window)
    #expect(hits(window.frameWork) == 1 && rebuilds(window.frameWork) == 0, "settled: \(window.frameWork.map(\.outlineContentHits))")
    #expect(visible(window) == ["A", "Z"], "\(visible(window))")
    window.resetFrameWork()
    chevron(window, "A")
    #expect(visible(window) == ["A", "A/0", "A/1", "Z"], "\(visible(window))")
    #expect(rebuilds(window.frameWork) == 1, "\(window.frameWork.map(\.outlineContentRebuilds))")
    window.resetFrameWork()
    idleFrame(window)
    #expect(hits(window.frameWork) == 1 && evaluations(window.frameWork) == 0, "\(window.frameWork.map(\.outlineContentHits))")
}

// MARK: - what the cache refuses

/// A plain class (not `Observable`) a row holds.
@MainActor private final class Plain {
    var names: [String: String] = [:]
}

private struct PlainRow: Component {
    let node: PNode
    let plain: Plain
    @ElementBuilder var content: some ElementGroup {
        ProposalText(plain.names[node.id] ?? node.name)
    }
}

private struct PlainFolder: Component {
    @Bindable var node: PNode
    let plain: Plain
    @ElementBuilder var content: some ElementGroup {
        if node.isFolder {
            DisclosureGroup(isExpanded: $node.isExpanded) {
                ForEach(node.children) { PlainFolder(node: $0, plain: plain) }
            } label: { ProposalText(plain.names[node.id] ?? node.name) }
        } else {
            ProposalText(plain.names[node.id] ?? node.name)
        }
    }
}

/// **A row that reads a plain class is walked every frame, and so stays right.** A component holding a class that is not
/// `Observable` is what observation cannot see: the cache refuses (no hit, a walk a frame) and a change to the plain class
/// shows on the next drawn frame, as before lane 8. Mutation: the `Observable` check dropped (`OutlineWalk.note`): the cache
/// serves the old label.
@Test @MainActor func aListOverAPlainClassIsWalkedEveryFrameAndStaysRight() throws {
    let plain = Plain()
    let roots = [PNode("A", expanded: true, children: leaves("A/", 2))]
    let window = try harnessWindow(size: sz(300, 400)) {
        ProposalScrollView { List { ForEach(roots) { PlainFolder(node: $0, plain: plain) } } }
    }
    settle(window)
    window.resetFrameWork()
    for _ in 0..<3 { idleFrame(window) }
    #expect(hits(window.frameWork) == 0 && rebuilds(window.frameWork) == 3, "walked: \(window.frameWork.map(\.outlineContentRebuilds))")
    plain.names["A/0"] = "plain-renamed"
    idleFrame(window)
    #expect(texts(window)["plain-renamed"] != nil, "\(visible(window))")
}

/// **A top level that changes by value is seen.** The list reads a value from outside the model (a `@State`-style
/// capture): the closure's component differs, the stamp differs, the walk runs and the label changes. Mutation: the stamp
/// compared by element ids only.
@Test @MainActor func aValueTheTopLevelClosureCapturesIsNotMissed() throws {
    let roots = [PNode("A", expanded: true, children: leaves("A/", 2))]
    let box = Prefix()
    let window = try harnessWindow(size: sz(300, 400)) {
        ProposalScrollView {
            List { ForEach(roots) { PrefixedRow(node: $0, prefix: box.value) } }
        }
    }
    settle(window)
    #expect(texts(window)["x A"] != nil || texts(window)["A"] != nil, "\(visible(window))")
    window.resetFrameWork()
    box.value = "y "
    idleFrame(window)
    #expect(texts(window)["y A"] != nil, "\(visible(window))")
    #expect(rebuilds(window.frameWork) == 1, "\(window.frameWork.map(\.outlineContentRebuilds))")
}

@MainActor private final class Prefix { var value = "x " }

private struct PrefixedRow: Component {
    @Bindable var node: PNode
    let prefix: String
    @ElementBuilder var content: some ElementGroup {
        if node.isFolder {
            DisclosureGroup(isExpanded: $node.isExpanded) {
                ForEach(node.children) { PrefixedRow(node: $0, prefix: prefix) }
            } label: { ProposalText(prefix + node.name) }
        } else {
            ProposalText(prefix + node.name)
        }
    }
}

// MARK: - 100 000 paths (gated)

/// A tree of `count` paths: root `r0` holds `count / 50` folders of 50 files, the first three expanded; `r1` is expanded over
/// two files; `r2`..`r4` are files. The top level and the expanded groups are the same whatever `count` is.
@MainActor private func pathTree(_ count: Int) -> [PNode] {
    let folders = (0..<(count / 50)).map { f in
        PNode("r0/d\(f)", expanded: f < 3, children: leaves("r0/d\(f)/f", 50))
    }
    return [PNode("r0", expanded: true, children: folders),
            PNode("r1", expanded: true, children: leaves("r1/f", 2)),
            PNode("r2"), PNode("r3"), PNode("r4")]
}

/// **100 000 paths do the same work per idle and scroll frame as 500.** (Gated: `METALUI_RUN_100K_OUTLINE_TEST=1 swift test
/// --filter anOutlinesWorkIsTheSameFor100kPathsAsFor500`.) The tree above at 500 and at 100 000 paths: the settled idle frames
/// and the scroll frames each evaluate 0, walk 0 times, hit once and realise equal units - the same literals at both sizes.
/// The numbers (a walk at 100 000, an idle frame, a scroll frame) are printed for the record.
@Test(.enabled(if: ProcessInfo.processInfo.environment["METALUI_RUN_100K_OUTLINE_TEST"] == "1"))
@MainActor func anOutlinesWorkIsTheSameFor100kPathsAsFor500() throws {
    var perSize: [[[Int]]] = []
    for count in [500, 100_000] {
        let model = PModel(pathTree(count))
        let clock = ContinuousClock()
        let started = clock.now
        let window = try listWindow(model, height: 400)
        let build = clock.now - started
        let walks = window.frameWork.map { [$0.outlineContentEvaluations, $0.outlineContentRebuilds, $0.outlineContentHits] }
        window.resetFrameWork()
        let idleStarted = clock.now
        for _ in 0..<3 { idleFrame(window) }
        let idle = (clock.now - idleStarted) / 3
        let idleWork = window.frameWork.map {
            [$0.outlineContentEvaluations, $0.outlineContentRebuilds, $0.outlineContentHits, $0.outlineContentChecks, $0.lazyUnitsRealized]
        }
        window.resetFrameWork()
        let scrollStarted = clock.now
        window.scroll(at: pt(100, 100), byDeltaX: 0, deltaY: -400)
        settle(window)
        window.scroll(at: pt(100, 100), byDeltaX: 0, deltaY: -1_000)
        settle(window)
        let scroll = (clock.now - scrollStarted) / 8
        let scrollWork = window.frameWork.map {
            [$0.outlineContentEvaluations, $0.outlineContentRebuilds, $0.outlineContentHits, $0.outlineContentChecks, $0.lazyUnitsRealized]
        }
        print("OUTLINE \(count) paths: first frames (evaluations, rebuilds, hits) \(walks), build+settle \(build), idle frame \(idle), scroll frame \(scroll)")
        print("OUTLINE \(count) paths: idle \(idleWork), scroll \(scrollWork)")
        #expect(idleWork.allSatisfy { $0[0] == 0 && $0[1] == 0 && $0[2] == 1 }, "\(count) idle: \(idleWork)")
        #expect(scrollWork.allSatisfy { $0[0] == 0 && $0[1] == 0 && $0[2] == 1 }, "\(count) scroll: \(scrollWork)")
        perSize.append(idleWork + scrollWork)
    }
    #expect(perSize[0] == perSize[1], "500: \(perSize[0])\n100k: \(perSize[1])")
}
