import Testing
import MetalUICore
@testable import MetalUILayout

// C14 lane 1 (`IV-E`, `IV-N`): the layout memo at the kernel. Window-level pins
// are `MetalUITestingTests/LayoutMemoWindowTests.swift`. Counts, never time.

private final class Calls: @unchecked Sendable { var count = 0 }

private func keyed(_ tree: LayoutTree, _ key: String, width: Double = 20, height: Double = 10,
                              calls: Calls = Calls()) -> LayoutNodeID {
    tree.newNativeLeaf(key: key) { proposal in
        calls.count += 1
        return LayoutMeasurement(size: SizeD(width: Swift.min(width, proposal.width ?? width), height: height))
    }
}

private func unkeyed(_ tree: LayoutTree, calls: Calls) -> LayoutNodeID {
    tree.newNativeLeaf { _ in calls.count += 1; return LayoutMeasurement(size: SizeD(width: 5, height: 5)) }
}

private let big = ProposedSize(width: 200, height: 200)
private let bounds = LayoutRect(x: 0, y: 0, width: 200, height: 200)

/// 1.4 — an unkeyed leaf makes exactly its ancestors unmatchable. Mutation: a
/// `nil` leaf key hashed as a constant (`leafKeys[index]` missing → `h.mix(0)`)
/// makes the unkeyed `d` match, so `d` is never measured on the second run.
@Test @MainActor func anUnkeyedLeafTaintsOnlyItsAncestors() throws {
    let memo = LayoutMemo()
    let d = Calls(), c = Calls(), a = Calls()
    func build(_ generation: UInt64) -> (LayoutTree, left: LayoutNodeID, right: LayoutNodeID, root: LayoutNodeID) {
        let tree = LayoutTree(generation: generation)
        tree.memo = memo
        let left = tree.newNativeLinearStack(children: [keyed(tree, "a", calls: a), keyed(tree, "b")], axis: .vertical)
        let right = tree.newNativeLinearStack(children: [keyed(tree, "c", calls: c), unkeyed(tree, calls: d)], axis: .vertical)
        let root = tree.newNativeLinearStack(children: [left, right], axis: .horizontal)
        return (tree, left, right, root)
    }
    let first = build(1)
    first.0.computeNativeLayout(root: first.root, proposal: big, in: bounds)
    memo.endFrame()
    let (tree, left, right, root) = build(2)
    a.count = 0; c.count = 0; d.count = 0
    tree.computeNativeLayout(root: root, proposal: big, in: bounds)
    #expect(tree.structuralSignature(of: left) != nil)
    #expect(tree.structuralSignature(of: right) == nil)
    #expect(tree.structuralSignature(of: root) == nil)
    #expect(a.count == 0, "the keyed left subtree is answered by the memo")
    #expect(d.count > 0, "the unkeyed leaf is measured again")
    #expect(tree.lastNativeLayoutWork.memoHits >= 1)
}

private struct GapLayout: ProposalLayout, Hashable {
    var gap: Double
    func sizeThatFits(proposal: ProposedSize, subviews: MeasurementSubviews) -> LayoutMeasurement {
        LayoutMeasurement(size: SizeD(width: gap, height: gap))
    }
    func placeSubviews(in bounds: LayoutRect, proposal: ProposedSize, subviews: PlacementSubviews) {}
}

private struct OpaqueLayout: ProposalLayout {
    func sizeThatFits(proposal: ProposedSize, subviews: MeasurementSubviews) -> LayoutMeasurement {
        LayoutMeasurement(size: SizeD(width: 1, height: 1))
    }
    func placeSubviews(in bounds: LayoutRect, proposal: ProposedSize, subviews: PlacementSubviews) {}
}

/// One registrar parameter: two values and the tree each builds.
private struct ParameterArm {
    let name: String
    let build: @MainActor (LayoutTree, Int) -> LayoutNodeID
}

private let parameterArms: [ParameterArm] = {
    func arm(_ name: String, _ build: @escaping @MainActor (LayoutTree, Int) -> LayoutNodeID) -> ParameterArm {
        ParameterArm(name: name, build: build)
    }
    func leaf(_ t: LayoutTree) -> LayoutNodeID { keyed(t, "k") }
    func frame(_ t: LayoutTree, _ v: Int, _ set: (inout [Double?]) -> Void) -> LayoutNodeID {
        var p = [Double?](repeating: nil, count: 8)
        set(&p)
        _ = v
        return t.newNativeFrame(child: leaf(t), width: p[0], height: p[1], minWidth: p[2], idealWidth: p[3],
                                maxWidth: p[4], minHeight: p[5], idealHeight: p[6], maxHeight: p[7])
    }
    var arms: [ParameterArm] = []
    let alignments: [ProposalAlignment] = [.center, .topLeading]
    arms.append(arm("overlay.alignment") { t, v in t.newNativeOverlay(children: [leaf(t)], alignment: alignments[v]) })
    arms.append(arm("overlayAttachment.alignment") { t, v in
        t.newNativeOverlayAttachment(child: leaf(t), overlay: keyed(t, "o"), alignment: alignments[v]) })
    for index in 0..<8 {
        let names = ["width", "height", "minWidth", "idealWidth", "maxWidth", "minHeight", "idealHeight", "maxHeight"]
        arms.append(arm("frame.\(names[index])") { t, v in
            frame(t, v) { $0[index] = v == 0 ? 10 : 20 } })
    }
    arms.append(arm("frame.alignment") { t, v in
        t.newNativeFrame(child: leaf(t), width: 50, alignment: alignments[v]) })
    for edge in 0..<4 {
        arms.append(arm("padding.edge\(edge)") { t, v in
            var e = [1.0, 1, 1, 1]; e[edge] = v == 0 ? 2 : 3
            return t.newNativePadding(child: leaf(t), insets: Edges(top: e[0], right: e[1], bottom: e[2], left: e[3]))
        })
    }
    arms.append(arm("fixedSize.horizontal") { t, v in t.newNativeFixedSize(child: leaf(t), horizontal: v == 0, vertical: true) })
    arms.append(arm("fixedSize.vertical") { t, v in t.newNativeFixedSize(child: leaf(t), horizontal: true, vertical: v == 0) })
    arms.append(arm("aspectRatio.ratio") { t, v in t.newNativeAspectRatio(child: leaf(t), ratio: v == 0 ? 1 : 2) })
    arms.append(arm("aspectRatio.contentMode") { t, v in
        t.newNativeAspectRatio(child: leaf(t), ratio: 1, contentMode: v == 0 ? .fit : .fill) })
    arms.append(arm("layoutPriority") { t, v in t.newNativeLayoutPriority(child: leaf(t), priority: Double(v)) })
    arms.append(arm("spacer.minLength") { t, v in t.newNativeSpacer(minLength: Double(v + 1)) })
    arms.append(arm("scrollViewport.axis") { t, v in
        t.newNativeScrollViewport(child: leaf(t), axis: v == 0 ? .vertical : .horizontal) })
    arms.append(arm("linearStack.axis") { t, v in
        t.newNativeLinearStack(children: [leaf(t)], axis: v == 0 ? .vertical : .horizontal) })
    arms.append(arm("linearStack.spacing") { t, v in
        t.newNativeLinearStack(children: [leaf(t)], axis: .vertical, spacing: v == 0 ? 1 : 2) })
    arms.append(arm("linearStack.spacingNil") { t, v in
        t.newNativeLinearStack(children: [leaf(t)], axis: .vertical, spacing: v == 0 ? nil : 0) })
    arms.append(arm("linearStack.alignment") { t, v in
        t.newNativeLinearStack(children: [leaf(t)], axis: .vertical, alignment: alignments[v]) })
    arms.append(arm("linearStack.baseline") { t, v in
        t.newNativeLinearStack(children: [leaf(t)], axis: .horizontal, baseline: v == 0 ? .first : .last) })
    arms.append(arm("linearStack.childOrder") { t, v in
        let a = keyed(t, "a"), b = keyed(t, "b")
        return t.newNativeLinearStack(children: v == 0 ? [a, b] : [b, a], axis: .vertical) })
    arms.append(arm("custom.value") { t, v in t.newNativeLayout(GapLayout(gap: Double(v)), children: [leaf(t)]) })
    arms.append(arm("grid.alignment") { t, v in
        t.newNativeGrid(children: [leaf(t)], alignment: alignments[v]) })
    // Spacing is a gap between cells: a one-cell grid has none, so these arms use
    // two columns / two rows (the plan holds `columnCount − 1` / `rowCount − 1` gaps).
    arms.append(arm("grid.horizontalSpacing") { t, v in
        let row = [leaf(t), keyed(t, "k2")]
        t.markNativeGridRow(row)
        return t.newNativeGrid(children: row, horizontalSpacing: Double(v)) })
    arms.append(arm("grid.verticalSpacing") { t, v in
        let first = [leaf(t)], second = [keyed(t, "k2")]
        t.markNativeGridRow(first); t.markNativeGridRow(second)
        return t.newNativeGrid(children: first + second, verticalSpacing: Double(v)) })
    arms.append(arm("leaf.key") { t, v in keyed(t, v == 0 ? "x" : "y") })
    return arms
}()

/// 1.5 — every registrar parameter is in its node's signature. Each arm builds
/// the node twice with one parameter at two values and reads the signature of the
/// result; they must differ, and two builds at one value must agree (so the arm
/// separates). Mutation: `frame.maxHeight` dropped from the `.frame` case of
/// `nodeSignature` reddens `frame.maxHeight` only.
@Test @MainActor func everyRegistrarParameterIsInItsSignature() throws {
    var failures: [String] = []
    for arm in parameterArms {
        func signature(_ value: Int) -> LayoutSignature? {
            let tree = LayoutTree(generation: 1)
            return tree.structuralSignature(of: arm.build(tree, value))
        }
        guard let zero = signature(0), let one = signature(1), let again = signature(0) else {
            failures.append("\(arm.name): nil signature"); continue
        }
        if zero == one { failures.append("\(arm.name): parameter not in the signature") }
        if zero != again { failures.append("\(arm.name): not deterministic") }
    }
    #expect(failures.isEmpty, "\(failures)")
    #expect(parameterArms.count == 33)
}

/// 1.5b — a non-`Hashable` custom layout is unmatchable; a `Hashable` one is not.
@Test @MainActor func aCustomLayoutIsKeyedOnlyWhenHashable() throws {
    let tree = LayoutTree(generation: 1)
    let plain = tree.newNativeLayout(OpaqueLayout(), children: [keyed(tree, "k")])
    let hashable = tree.newNativeLayout(GapLayout(gap: 1), children: [keyed(tree, "k")])
    #expect(tree.structuralSignature(of: plain) == nil)
    #expect(tree.structuralSignature(of: hashable) != nil)
}

/// 1.6 — a spacer's signature carries its stack's axis (CN-C): the same spacer
/// under a vertical then a horizontal stack. Mutation: hash only the spacer's own
/// case (drop `spacerAxes[index]`).
@Test @MainActor func aSpacersSignatureCarriesItsStacksAxis() throws {
    func spacerSignature(_ axis: ProposalStackAxis) -> LayoutSignature? {
        let tree = LayoutTree(generation: 1)
        let spacer = tree.newNativeSpacer()
        _ = tree.newNativeLinearStack(children: [spacer], axis: axis)
        return tree.structuralSignature(of: spacer)
    }
    let vertical = spacerSignature(.vertical), horizontal = spacerSignature(.horizontal)
    #expect(vertical != nil && horizontal != nil)
    #expect(vertical != horizontal)
    // The mark is written after the spacer registers, so a signature taken at
    // registration would read the unmarked one.
    let tree = LayoutTree(generation: 1)
    let spacer = tree.newNativeSpacer()
    let before = tree.structuralSignature(of: spacer)
    _ = tree.newNativeLinearStack(children: [spacer], axis: .vertical)
    #expect(tree.structuralSignature(of: spacer) != before)
}

/// 1.7 — a grid row's token is fresh per mark and never hashed (GR-A): two
/// identical grids built in one tree (tokens differ) have equal signatures, and
/// moving one cell to another row changes it. Mutation: hash the raw token.
@Test @MainActor func aGridRowMarkIsNormalisedNotHashedAsAToken() throws {
    func grid(_ tree: LayoutTree, rows: [[String]]) -> LayoutNodeID {
        var cells: [LayoutNodeID] = []
        for row in rows {
            let nodes = row.map { keyed(tree, $0) }
            tree.markNativeGridRow(nodes)
            cells += nodes
        }
        return tree.newNativeGrid(children: cells)
    }
    let tree = LayoutTree(generation: 1)
    let first = grid(tree, rows: [["a", "b"], ["c"]])
    let second = grid(tree, rows: [["a", "b"], ["c"]])
    let other = grid(tree, rows: [["a"], ["b", "c"]])
    #expect(tree.structuralSignature(of: first) != nil)
    #expect(tree.structuralSignature(of: first) == tree.structuralSignature(of: second))
    #expect(tree.structuralSignature(of: first) != tree.structuralSignature(of: other))
}

/// 1.8 — the memo holds values, never a node id: a `Mirror` walk finds no
/// `LayoutNodeID`, and a memo outlives its tree (C-3). Mutation: add a
/// `[LayoutNodeID: LayoutMeasurement]` member to `LayoutMemo`.
@Test @MainActor func theMemoHoldsNoNodeID() throws {
    let memo = LayoutMemo()
    let tree = LayoutTree(generation: 1)
    tree.memo = memo
    let root = tree.newNativeLinearStack(children: [keyed(tree, "a")], axis: .vertical)
    tree.computeNativeLayout(root: root, proposal: big, in: bounds)
    try #require(memo.entryCount > 0)

    func containsNodeID(_ value: Any, depth: Int = 0) -> Bool {
        if value is LayoutNodeID { return true }
        if depth > 6 { return false }
        let mirror = Mirror(reflecting: value)
        if mirror.displayStyle == .dictionary || mirror.displayStyle == .collection || mirror.displayStyle == .set {
            return mirror.children.contains { containsNodeID($0.value, depth: depth + 1) }
        }
        return mirror.children.contains { containsNodeID($0.value, depth: depth + 1) }
    }
    #expect(!containsNodeID(memo))
    let types = Mirror(reflecting: memo).children.map { String(describing: type(of: $0.value)) }
    #expect(!types.contains { $0.contains("LayoutNodeID") }, "\(types)")

    // Outlives the tree: a later tree of another generation reads it without a trap.
    let later = LayoutTree(generation: 9)
    later.memo = memo
    let again = later.newNativeLinearStack(children: [keyed(later, "a")], axis: .vertical)
    later.computeNativeLayout(root: again, proposal: big, in: bounds)
    #expect(later.lastNativeLayoutWork.memoHits >= 1)
}

/// 1.14 — (P): an equal tree at an equal proposal and bounds restores the whole
/// placement; the rects equal a fresh run's, one lookup measures. Mutation:
/// `placeFromMemo` writes `rects[offset]` of the wrong node (reverse the order).
@Test @MainActor func aRootPlacementHitEqualsAFreshRun() throws {
    let memo = LayoutMemo()
    func laidOut(_ generation: UInt64, memo: LayoutMemo?) -> (LayoutTree, [LayoutNodeID]) {
        let tree = LayoutTree(generation: generation)
        tree.memo = memo
        let a = keyed(tree, "a", width: 30), b = keyed(tree, "b", width: 17.5), c = keyed(tree, "c", width: 40)
        let stack = tree.newNativeLinearStack(children: [a, b, c], axis: .vertical, spacing: 3.25)
        let root = tree.newNativeFrame(child: stack, width: 100, height: 100)
        tree.computeNativeLayout(root: root, proposal: big, centredIn: bounds)
        return (tree, [a, b, c, stack, root])
    }
    _ = laidOut(1, memo: memo)
    memo.endFrame()
    let (hit, ids) = laidOut(2, memo: memo)
    let (fresh, freshIds) = laidOut(3, memo: nil)
    #expect(hit.lastNativeLayoutWork.memoRootHits == 1)
    #expect(hit.lastNativeLayoutWork.measureCalls == 0)
    #expect(hit.lastNativeLayoutWork.cacheMisses == 0)
    for (id, freshId) in zip(ids, freshIds) {
        #expect(hit.layout(id) == fresh.layout(freshId))
        #expect(hit.measuredWidth(id) == fresh.measuredWidth(freshId))
    }
}

/// 1.15 — `verifies` traps nothing on a hit and counts nothing extra: the same
/// work as the unverified run.
@Test @MainActor func verifyModeDoesNotChangeTheCounters() throws {
    func run(verifies: Bool) -> NativeLayoutWork {
        let memo = LayoutMemo(verifies: verifies)
        var work = NativeLayoutWork()
        for generation in 1...2 as ClosedRange<UInt64> {
            let tree = LayoutTree(generation: generation)
            tree.memo = memo
            let stack = tree.newNativeLinearStack(children: [keyed(tree, "a"), keyed(tree, "b")], axis: .vertical)
            tree.computeNativeLayout(root: stack, proposal: big, centredIn: bounds)
            work = tree.lastNativeLayoutWork
            memo.endFrame()
        }
        return work
    }
    #expect(run(verifies: true) == run(verifies: false))
}
