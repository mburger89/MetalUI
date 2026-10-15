import Testing
import MetalUICore
@testable import MetalUILayout

// P2 lane 1, test 6 (`PA-F`): `solveLinearStack` after the single-priority fast path against a test-local copy of
// the algorithm as it was at 6273e3a4. Same sizes, same order of leaf measurements, same four counters.

private struct ChildSpec {
    var lo: Double, hi: Double, ideal: Double
    var height: Double = 10
    var priority: Double? = nil
}

private final class CallLog: @unchecked Sendable { var calls: [String] = [] }

private struct Case {
    var name: String
    var axis: ProposalStackAxis
    var spacing: Double?
    var main: Double?
    var cross: Double?
    var children: [ChildSpec]
}

private func answer(_ spec: ChildSpec, _ axis: ProposalStackAxis, _ proposal: ProposedSize) -> LayoutMeasurement {
    let main = axis == .horizontal ? proposal.width : proposal.height
    let length = Swift.min(Swift.max(main ?? spec.ideal, spec.lo), spec.hi)
    return LayoutMeasurement(size: axis == .horizontal ? SizeD(width: length, height: spec.height)
                                                       : SizeD(width: spec.height, height: length))
}

private struct Reference {
    var cacheKeys: Set<String> = []
    var cache: [String: LayoutMeasurement] = [:]
    var measureCalls = 0, hits = 0, misses = 0
    var calls: [String] = []
    let axis: ProposalStackAxis
    let specs: [ChildSpec]

    /// measureNative of child `i` (a leaf, under a layoutPriority node when `priority` is set).
    mutating func measure(_ i: Int, _ proposal: ProposedSize) -> LayoutMeasurement {
        let wrapped = specs[i].priority != nil
        let key = "\(i)|\(String(describing: proposal.width))|\(String(describing: proposal.height))"
        if wrapped {
            if let cached = cache["w" + key] { hits += 1; return cached }
            misses += 1
        }
        let result: LayoutMeasurement
        if let cached = cache["l" + key] { hits += 1; result = cached } else {
            misses += 1
            measureCalls += 1
            calls.append("\(i)@\(String(describing: proposal.width)),\(String(describing: proposal.height))")
            result = answer(specs[i], axis, proposal)
            cache["l" + key] = result
        }
        if wrapped { cache["w" + key] = result }
        return result
    }

    /// The algorithm of 6273e3a4, over this reference's measure.
    mutating func solve(spacing: Double?, proposal: ProposedSize)
        -> (answers: [LayoutMeasurement], size: SizeD) {
        let count = specs.count
        let cross = axis == .horizontal ? proposal.height : proposal.width
        let main = axis == .horizontal ? proposal.width : proposal.height
        func offer(_ length: Double?) -> ProposedSize {
            axis == .horizontal ? ProposedSize(width: length, height: cross) : ProposedSize(width: cross, height: length)
        }
        func mainLength(_ m: LayoutMeasurement) -> Double { axis == .horizontal ? m.size.width : m.size.height }
        let gapList: [Double] = count > 1
            ? Array(repeating: spacing ?? ProposalSpacing.platformDefault, count: count - 1) : []
        let gaps = gapList.reduce(0, +)
        var answers: [LayoutMeasurement]
        if let main, main.isFinite, count > 0 {
            answers = Array(repeating: LayoutMeasurement(size: .zero), count: count)
            let priorities = specs.map { $0.priority ?? 0 }
            var remaining = main - gaps
            for priority in Set(priorities).sorted(by: >) {
                let members = (0..<count).filter { priorities[$0] == priority }
                let reserved = (0..<count).filter { priorities[$0] < priority }.reduce(0.0) { total, index in
                    total + mainLength(measure(index, offer(0)))
                }
                var order = members
                if members.count > 1 {
                    var flexibility: [Int: Double] = [:]
                    for index in members {
                        flexibility[index] = mainLength(measure(index, offer(.infinity))) - mainLength(measure(index, offer(0)))
                    }
                    order.sort { lhs, rhs in
                        let (l, r) = (flexibility[lhs]!, flexibility[rhs]!)
                        return l != r ? l < r : lhs < rhs
                    }
                }
                var groupRemaining = remaining - reserved
                for (served, index) in order.enumerated() {
                    let p = offer(Swift.max(0, groupRemaining / Double(order.count - served)))
                    answers[index] = measure(index, p)
                    groupRemaining -= mainLength(answers[index])
                    remaining -= mainLength(answers[index])
                }
            }
        } else {
            answers = (0..<count).map { measure($0, offer(main)) }
        }
        let mainTotal = answers.reduce(gaps) { $0 + mainLength($1) }
        let crossMax = answers.map { axis == .horizontal ? $0.size.height : $0.size.width }.max() ?? 0
        return (answers, axis == .horizontal ? SizeD(width: mainTotal, height: crossMax) : SizeD(width: crossMax, height: mainTotal))
    }
}

private func corpus() -> [Case] {
    let flex = ChildSpec(lo: 0, hi: .infinity, ideal: 20)
    let rigid = ChildSpec(lo: 30, hi: 30, ideal: 30)
    let capped = ChildSpec(lo: 5, hi: 40, ideal: 15)
    func spaced(_ n: Int, _ spec: ChildSpec = flex) -> [ChildSpec] { Array(repeating: spec, count: n) }
    var out: [Case] = []
    for axis in [ProposalStackAxis.horizontal, .vertical] {
        for spacing in [nil, 0, 4.5, 0.1] as [Double?] {
            for main in [nil, 0, 100, 37.3, Double.infinity] as [Double?] {
                for n in [1, 2, 7] {
                    out.append(Case(name: "equal \(n)", axis: axis, spacing: spacing, main: main, cross: 50, children: spaced(n)))
                    out.append(Case(name: "mixed \(n)", axis: axis, spacing: spacing, main: main, cross: nil,
                                    children: (0..<n).map { [flex, rigid, capped][$0 % 3] }))
                }
                var two = spaced(4); two[1].priority = 1; two[3].priority = 1
                out.append(Case(name: "two levels", axis: axis, spacing: spacing, main: main, cross: 50, children: two))
                var three = [flex, capped, rigid, flex, capped]
                three[2].priority = 2; three[0].priority = 1; three[4].priority = 1
                out.append(Case(name: "three levels one reserved", axis: axis, spacing: spacing, main: main, cross: 50, children: three))
                var allWrapped = spaced(3, capped); for i in 0..<3 { allWrapped[i].priority = 0 }
                out.append(Case(name: "all wrapped at one level", axis: axis, spacing: spacing, main: main, cross: 50, children: allWrapped))
            }
        }
    }
    return out
}

@Test @MainActor func aStackWithEqualPrioritiesSolvesLikeTheReference() throws {
    let cases = corpus()
    try #require(cases.count > 300)
    for c in cases {
        let log = CallLog()
        let tree = LayoutTree(generation: 1)
        var nodes: [LayoutNodeID] = []
        for (i, spec) in c.children.enumerated() {
            let axis = c.axis
            let leaf = tree.newNativeLeaf { proposal in
                log.calls.append("\(i)@\(String(describing: proposal.width)),\(String(describing: proposal.height))")
                return answer(spec, axis, proposal)
            }
            nodes.append(spec.priority.map { tree.newNativeLayoutPriority(child: leaf, priority: $0) } ?? leaf)
        }
        let root = tree.newNativeLinearStack(children: nodes, axis: c.axis, spacing: c.spacing)
        let proposal = c.axis == .horizontal ? ProposedSize(width: c.main, height: c.cross)
                                             : ProposedSize(width: c.cross, height: c.main)
        let measured = tree.measureNativeLayout(root: root, proposal: proposal)
        let work = tree.lastNativeLayoutWork

        var reference = Reference(axis: c.axis, specs: c.children)
        let expected = reference.solve(spacing: c.spacing, proposal: proposal)
        let label = "\(c.name) \(c.axis) spacing \(String(describing: c.spacing)) main \(String(describing: c.main))"
        #expect(measured.size == expected.size, "\(label): size \(measured.size) against \(expected.size)")
        #expect(log.calls == reference.calls, "\(label): the order of leaf measurements")
        #expect(work.measureCalls == reference.measureCalls, "\(label): measureCalls")
        #expect(work.cacheHits == reference.hits, "\(label): cacheHits \(work.cacheHits) against \(reference.hits)")
        #expect(work.cacheMisses == reference.misses + 1, "\(label): cacheMisses (the root is one) \(work.cacheMisses) against \(reference.misses + 1)")
        #expect(work.memoHits == 0, "\(label): memoHits")
    }
}
