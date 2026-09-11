import Testing
import MetalUICore
@testable import MetalUILayout

// `measureNode` answers a node with no children and no measure function in
// closed form — `known` where known, `borderBoxFloor` otherwise — instead of
// building a cache key, running `layOutChildren` over zero children and storing
// the result. Two properties, one test each:
//
// 1. **The work is gone** (`aChildlessNodeWithNoMeasureFunctionIsNeverACacheMiss`),
//    counted in `LayoutContext.misses` against an oracle the engine does not
//    compute.
// 2. **No number moved** (`theLeafShortcutMovesNoRectOnSeededRandomTrees`), bit
//    for bit, against a reference tree that cannot take the shortcut.

private func pxL(_ v: Float) -> Length { .pixels(Pixels(v)) }
private func pxD(_ v: Float) -> MetalUICore.Dimension { .length(.pixels(Pixels(v))) }

/// Counts calls from inside a `@Sendable` measure function. The engine calls
/// measure functions on the thread that called it, and these tests are
/// single-threaded.
private final class CallCounter: @unchecked Sendable {
    var calls = 0
}

/// A **branching** tree, 4 columns x 5 rows x 3 leaves — never a chain, which
/// collapses every probe onto a few cache keys. The columns are `flexStart` so
/// each row's cross size is measured rather than stretched; the leaves are
/// whatever `leaf` builds.
private func branchingTree(_ tree: LayoutTree, leaf: () -> LayoutNodeID) -> LayoutNodeID {
    var column = Style()
    column.flexDirection = .column
    column.alignItems = .flexStart
    var row = Style()
    row.flexDirection = .row
    let columns = (0..<4).map { _ in
        tree.newNode(style: column, children: (0..<5).map { _ in
            tree.newNode(style: row, children: (0..<3).map { _ in leaf() })
        })
    }
    return tree.newNode(style: row, children: columns)
}

/// **A childless node with no measure function is never a cache miss.**
///
/// Two copies of `branchingTree`, measured with the same three queries in a
/// fresh `LayoutContext` each. In one the 60 leaves are empty nodes. In the
/// other they are `newLeaf`s whose measure function returns exactly what an
/// empty node measures (`known` on a known axis, 0 on the other; the leaves
/// have no padding or border), so every container is asked exactly the same
/// questions in both trees. The `#require` on the three root sizes checks that
/// rather than assuming it.
///
/// **Where the expected count comes from:** the measure function's own call
/// counter, which the test keeps. A measured leaf is called exactly once per
/// cache miss, so `measured.misses - leafCalls` is the number of misses the
/// *containers* made. An empty-leaf tree must make exactly that many. Before
/// the shortcut every empty leaf missed too and the two counts were equal:
/// 707 and 707, of which 540 were the leaves' own.
///
/// The measured half is also what keeps a `Text` leaf off the shortcut. A
/// shortcut that skipped the `tree.measure(node) == nil` check would never call
/// the measure function, and the first `#require` fails.
@Test func aChildlessNodeWithNoMeasureFunctionIsNeverACacheMiss() throws {
    let queries: [(known: OptionalSizeD, available: AvailableSpaceSize)] = [
        (.unspecified, AvailableSpaceSize(width: .maxContent, height: .maxContent)),
        (.unspecified, AvailableSpaceSize(width: .minContent, height: .maxContent)),
        (OptionalSizeD(width: 300, height: nil),
         AvailableSpaceSize(width: .definite(300), height: .maxContent)),
    ]
    func run(_ tree: LayoutTree, _ root: LayoutNodeID) -> (sizes: [SizeD], misses: Int) {
        let ctx = LayoutContext(rootFontSize: 16)
        let sizes = queries.map {
            measureNode(ctx, tree, root, known: $0.known, available: $0.available,
                        containingBlockWidth: nil)
        }
        return (sizes, ctx.misses)
    }

    let emptyTree = LayoutTree(generation: 1)
    let emptyRoot = branchingTree(emptyTree) { emptyTree.newNode(style: Style(), children: []) }
    let empty = run(emptyTree, emptyRoot)

    let counter = CallCounter()
    let measuredTree = LayoutTree(generation: 2)
    let measuredRoot = branchingTree(measuredTree) {
        measuredTree.newLeaf(style: Style()) { known, _ in
            counter.calls += 1
            return SizeD(width: known.width ?? 0, height: known.height ?? 0)
        }
    }
    let measured = run(measuredTree, measuredRoot)

    try #require(counter.calls >= 60,
                 "the 60 measured leaves were called \(counter.calls) times: the probe never reached them")
    try #require(empty.sizes.count == measured.sizes.count)
    for (e, m) in zip(empty.sizes, measured.sizes) {
        try #require(e.width.bitPattern == m.width.bitPattern
                        && e.height.bitPattern == m.height.bitPattern,
                     "the two trees are not the same layout (\(e) vs \(m)), so their containers were asked different questions")
    }

    let containerMisses = measured.misses - counter.calls
    #expect(empty.misses == containerMisses,
            "empty leaves: \(empty.misses) misses; measured leaves: \(measured.misses), of which \(counter.calls) were the leaves' own")
}

// MARK: - Equivalence

private struct TreeRandom {
    var state: UInt64
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
    mutating func pick<T>(_ xs: [T]) -> T { xs[Int(next() % UInt64(xs.count))] }
    mutating func chance(_ percent: UInt64) -> Bool { next() % 100 < percent }

    mutating func length() -> Length {
        switch next() % 10 {
        case 0..<6: return pxL(pick([0, 0, -0.0, 3, 7.5, 12, 25]))
        case 6..<8: return .rems(Rems(pick([0.25, 0.5, 1.25])))
        default: return .percent(pick([0.02, 0.05, 0.1]))
        }
    }
    mutating func size() -> MetalUICore.Dimension {
        switch next() % 10 {
        case 0..<5: return .auto
        case 5..<8: return pxD(pick([0, 10, 25, 40, 60, 120, 333.5]))
        case 8: return .length(.rems(Rems(pick([2, 5]))))
        default: return .length(.percent(pick([0.25, 0.5, 1])))
        }
    }
    mutating func bound(_ values: [Float]) -> MetalUICore.Dimension {
        chance(70) ? .auto : (chance(80) ? pxD(pick(values)) : .length(.percent(pick([0.3, 0.6]))))
    }
}

/// What a random tree is made of, and where to read it back.
private struct RandomTree {
    let tree: LayoutTree
    let root: LayoutNodeID
    /// Every node the seed describes, in creation order — **not** the hidden
    /// children `hidingLeaves` adds, so the two arms index the same boxes.
    var nodes: [LayoutNodeID] = []
    /// Indices into `nodes` of the nodes with no children and no measure
    /// function in the plain arm.
    var childlessLeaves: [Int] = []
    /// How many of those have every padding and border edge at `-0.0`.
    var negativeZeroLeaves = 0
}

/// One seeded random tree. Both arms draw the same numbers in the same order;
/// the only difference is that `hidingLeaves` gives every node the seed leaves
/// childless one `display: .none` child. That child takes no part in layout
/// (`collectItems`, `layOutStack` and the absolute loop in `placeNode` all
/// filter it out), but the node is no longer childless, so it takes the full
/// path.
private func randomTree(seed: UInt64, generation: UInt64, hidingLeaves: Bool) -> RandomTree {
    var random = TreeRandom(state: seed)
    let tree = LayoutTree(generation: generation)
    var hidden = Style()
    hidden.display = .none
    var nodes: [LayoutNodeID] = []
    var childlessLeaves: [Int] = []
    var negativeZeroLeaves = 0

    func build(depth: Int, isRoot: Bool) -> LayoutNodeID {
        var s = Style()
        s.display = random.chance(20) ? .stack : .flex
        if !isRoot && random.chance(8) {
            s.position = .absolute
            s.inset = Edges(top: random.chance(50) ? .auto : pxD(random.pick([0, 5, 20])),
                            right: random.chance(60) ? .auto : pxD(random.pick([0, 10])),
                            bottom: random.chance(60) ? .auto : .length(.percent(0.1)),
                            left: random.chance(50) ? .auto : pxD(random.pick([0, 15])))
        }
        s.flexDirection = random.pick([.row, .rowReverse, .column, .columnReverse])
        s.flexWrap = random.pick([.noWrap, .noWrap, .wrap, .wrapReverse])
        s.size = Size(width: random.size(), height: random.size())
        s.minSize = Size(width: random.bound([0, 15, 50]), height: random.bound([0, 15, 50]))
        s.maxSize = Size(width: random.bound([20, 45, 80, 200]), height: random.bound([20, 45, 80, 200]))
        s.padding = Edges(top: random.length(), right: random.length(),
                          bottom: random.length(), left: random.length())
        if random.chance(40) {
            s.border = Edges(top: random.length(), right: random.length(),
                             bottom: random.length(), left: random.length())
        }
        // Every edge `-0.0`: the one box whose edge totals are `-0.0` rather
        // than `+0.0`, which the full path's `0 + edges` turns positive.
        let negativeZero = random.chance(10)
        if negativeZero {
            s.padding = Edges(all: pxL(-0.0))
            s.border = Edges(all: pxL(-0.0))
        }
        if random.chance(30) {
            s.margin = Edges(top: pxD(random.pick([0, 2, 5])), right: .length(.percent(0.05)),
                             bottom: random.chance(10) ? .auto : pxD(3), left: pxD(random.pick([0, 4])))
        }
        s.gap = Axes(horizontal: random.length(), vertical: random.length())
        s.alignItems = random.chance(40) ? nil : random.pick([.flexStart, .flexEnd, .center, .baseline, .stretch])
        s.justifyItems = random.chance(50) ? nil : random.pick([.start, .center, .end, .stretch])
        s.justifyContent = random.chance(60) ? nil : random.pick([.flexStart, .flexEnd, .center, .spaceBetween])
        s.alignContent = random.chance(60) ? nil : random.pick([.flexStart, .center, .stretch, .spaceAround])
        s.alignSelf = random.chance(70) ? nil : random.pick([.flexStart, .center, .stretch])
        s.flexGrow = random.pick([0, 0, 0.5, 1, 2])
        s.flexShrink = random.pick([1, 1, 0, 0.5, 3])
        s.flexBasis = random.chance(60) ? .auto : (random.chance(70) ? pxD(random.pick([0, 20, 80])) : .length(.percent(0.3)))

        let kind = depth >= 4 ? 0 : random.next() % 10
        let id: LayoutNodeID
        if kind == 9 && !isRoot {
            // A text-like leaf: it has a measure function, so neither arm
            // may take the shortcut for it.
            let narrow = Double(random.pick([20, 30])), wide = Double(random.pick([70, 90]))
            id = tree.newLeaf(style: s) { known, available in
                let width: Double
                switch available.width {
                case .minContent: width = narrow
                case .maxContent: width = wide
                case .definite(let w): width = Swift.min(wide, Swift.max(narrow, w))
                }
                let used = known.width ?? width
                return SizeD(width: used, height: known.height ?? (used < wide ? 40 : 20))
            }
        } else {
            let count = kind < 3 && !isRoot ? 0 : Int(1 + random.next() % 4)
            var children = (0..<count).map { _ in build(depth: depth + 1, isRoot: false) }
            let childless = children.isEmpty
            if childless && hidingLeaves { children = [tree.newNode(style: hidden, children: [])] }
            id = tree.newNode(style: s, children: children)
            if childless {
                childlessLeaves.append(nodes.count)
                if negativeZero { negativeZeroLeaves += 1 }
            }
        }
        nodes.append(id)
        return id
    }

    let root = build(depth: 0, isRoot: true)
    var result = RandomTree(tree: tree, root: root)
    result.nodes = nodes
    result.childlessLeaves = childlessLeaves
    result.negativeZeroLeaves = negativeZeroLeaves
    return result
}

/// **The shortcut changes no stored rect, no pre-rounding width and no measured
/// size, bit for bit,** on 150 seeded random trees. Each tree is laid out at
/// three offered sizes and two root font sizes. Its root is measured at four
/// queries, and every childless leaf is measured directly at four more, each
/// against three containing-block widths.
///
/// **The reference arm is structural, not a switch in `Sources/`.** It is the
/// same tree with a `display: .none` child under every childless node (see
/// `randomTree`). That child is laid out by nothing, so the node's answer
/// cannot change, but it is no longer childless and takes the full path.
///
/// **The random values are chosen to make the shortcut's inputs matter.**
/// Percentage padding and border resolve against the containing-block width,
/// and that width is `nil` in some queries. `rem` edges resolve against the
/// root font size, which varies. Some boxes have every edge at `-0.0`.
///
/// **The direct leaf queries are not redundant with the layouts.** Measured by
/// mutation. A shortcut that ignored `known` moved nothing, bit for bit, in any
/// `computeLayout` the whole suite runs, this test's own layouts included. Only
/// a leaf measured directly with a known axis sees it. A shortcut that dropped
/// its `0 +` moves no rect either. It does change a stored pre-rounding width to
/// `-0.0` on a box whose every edge is `-0.0`. This test's first version drew
/// no such box, and the whole suite stayed green under that mutant. Resolving
/// the edges against a `nil` containing
/// block, or against a fixed root font size, shows in the layouts too.
///
/// **What makes agreement mean something** is the `#require`s at the end.
/// The plain arm must have skipped work the reference arm did; without that, a
/// shortcut that never fires would agree with the reference trivially. Before
/// the shortcut the two miss counts were equal.
@Test func theLeafShortcutMovesNoRectOnSeededRandomTrees() throws {
    let offers = [
        AvailableSpaceSize(width: .definite(800), height: .definite(600)),
        AvailableSpaceSize(width: .definite(240), height: .maxContent),
        AvailableSpaceSize(width: .maxContent, height: .maxContent),
    ]
    let rootQueries: [(known: OptionalSizeD, available: AvailableSpaceSize)] = [
        (.unspecified, AvailableSpaceSize(width: .maxContent, height: .maxContent)),
        (.unspecified, AvailableSpaceSize(width: .minContent, height: .maxContent)),
        (.unspecified, AvailableSpaceSize(width: .definite(240), height: .definite(90))),
        (OptionalSizeD(width: 150, height: nil), AvailableSpaceSize(width: .definite(150), height: .maxContent)),
    ]
    let leafQueries: [(known: OptionalSizeD, available: AvailableSpaceSize)] = [
        (.unspecified, AvailableSpaceSize(width: .maxContent, height: .maxContent)),
        (.unspecified, AvailableSpaceSize(width: .minContent, height: .definite(90))),
        (OptionalSizeD(width: 37.5, height: nil), AvailableSpaceSize(width: .definite(37.5), height: .maxContent)),
        (OptionalSizeD(width: nil, height: 12), AvailableSpaceSize(width: .maxContent, height: .definite(12))),
    ]

    var disagreements: [String] = []
    var plainMisses = 0, referenceMisses = 0, comparedRects = 0
    var childlessLeaves = 0, negativeZeroLeaves = 0, leafMeasures = 0

    func note(_ s: @autoclosure () -> String) {
        if disagreements.count < 10 { disagreements.append(s()) }
    }
    func same(_ a: Double, _ b: Double) -> Bool { a.bitPattern == b.bitPattern }

    for t in 0..<150 {
        let seed = 0x1EAF_0000 &+ UInt64(t) &* 7919
        let plain = randomTree(seed: seed, generation: UInt64(2 * t + 10), hidingLeaves: false)
        let reference = randomTree(seed: seed, generation: UInt64(2 * t + 11), hidingLeaves: true)
        try #require(plain.nodes.count == reference.nodes.count)
        try #require(plain.childlessLeaves == reference.childlessLeaves)
        childlessLeaves += plain.childlessLeaves.count
        negativeZeroLeaves += plain.negativeZeroLeaves

        for rootFontSize in [16.0, 10.0] {
            for (o, offer) in offers.enumerated() {
                computeLayout(plain.tree, root: plain.root, available: offer, rootFontSize: rootFontSize)
                computeLayout(reference.tree, root: reference.root, available: offer, rootFontSize: rootFontSize)
                for (p, r) in zip(plain.nodes, reference.nodes) {
                    let a = plain.tree.layout(p), b = reference.tree.layout(r)
                    comparedRects += 1
                    if !(same(a.x, b.x) && same(a.y, b.y) && same(a.width, b.width) && same(a.height, b.height)
                         && same(plain.tree.measuredWidth(p), reference.tree.measuredWidth(r))) {
                        note("tree \(t) offer \(o) font \(rootFontSize) node \(p.index): \(a) vs \(b)")
                    }
                }
            }

            for containingBlockWidth in [nil, 500.0, 333.5] as [Double?] {
                let plainCtx = LayoutContext(rootFontSize: rootFontSize)
                let referenceCtx = LayoutContext(rootFontSize: rootFontSize)
                func compare(_ label: String, _ p: LayoutNodeID, _ r: LayoutNodeID,
                             _ query: (known: OptionalSizeD, available: AvailableSpaceSize)) {
                    let a = measureNode(plainCtx, plain.tree, p, known: query.known,
                                        available: query.available, containingBlockWidth: containingBlockWidth)
                    let b = measureNode(referenceCtx, reference.tree, r, known: query.known,
                                        available: query.available, containingBlockWidth: containingBlockWidth)
                    if !(same(a.width, b.width) && same(a.height, b.height)) {
                        note("tree \(t) \(label) font \(rootFontSize) cb \(String(describing: containingBlockWidth)): \(a) vs \(b)")
                    }
                }
                for (q, query) in rootQueries.enumerated() {
                    compare("root query \(q)", plain.root, reference.root, query)
                }
                for i in plain.childlessLeaves {
                    for (q, query) in leafQueries.enumerated() {
                        compare("leaf \(i) query \(q)", plain.nodes[i], reference.nodes[i], query)
                        leafMeasures += 1
                    }
                }
                plainMisses += plainCtx.misses
                referenceMisses += referenceCtx.misses
            }
        }
    }

    try #require(childlessLeaves >= 250, "childless leaves across the trees: \(childlessLeaves)")
    try #require(negativeZeroLeaves >= 15, "leaves with every edge at -0.0: \(negativeZeroLeaves)")
    try #require(comparedRects >= 10_000, "rects compared: \(comparedRects)")
    try #require(leafMeasures >= 6_000, "direct leaf measurements: \(leafMeasures)")
    try #require(plainMisses < referenceMisses,
                 "the shortcut never fired: \(plainMisses) misses with it, \(referenceMisses) without")

    #expect(disagreements.isEmpty, "\(disagreements.joined(separator: "\n"))")
}
