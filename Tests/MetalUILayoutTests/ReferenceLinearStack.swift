// **A PLAIN import, never `@testable`, and that is the proof.** This file
// reimplements the built-in `linearStack` node kind as a `ProposalLayout`
// using only public API: the proxies' `priority`, `sizeThatFits` and `place`,
// and `ProposalAlignment`'s factors. If it compiled only with `@testable`, the
// protocol would be insufficient for the one algorithm the kernel already
// ships (ruling SA-B, SA-P).
//
// A plain import in one file of a test target is not widened by `@testable`
// imports in the target's other files: measured on a two-file scratch package
// (`error: cannot find 'secret' in scope`; ruling SA-P, evidence 7 of the
// kernel completion design). So `MetalUILayoutTests` being full of `@testable`
// files does not weaken this one.
//
// **Rewritten for ruling CN-B** (plan task 6, lane 1): SwiftUI's distribution
// — priority groups, lower groups' minimums reserved, least flexible first,
// the sum of the answers — and CN-E's second pass at a nil cross proposal. A
// spacer's −∞ `priority` is all its DISTRIBUTION needs, which is also all
// SwiftUI's own proxy offers (contract probe E).
//
// **Lane 2 (ruling CN-C) adds one read of `isSpacer`, and one approximation.**
// A built-in stack marks its spacers at registration so that each answers 0 on
// the stack's cross axis. A `ProposalLayout` cannot mark a node — neither can
// SwiftUI's: a spacer under a custom layout is flexible on both axes (contract
// probe E) — so this reference leaves every `isSpacer` subview out of its own
// cross size instead. The two agree on every rect except a spacer's cross
// extent (the built-in stores 0, this stores the spacer's answer), which the
// equivalence test does not compare. `isSpacer` reaches a spacer bare or under
// `layoutPriority`; the mark's walk also passes `padding`, `frame`,
// `fixedSize`, `aspectRatio` and overlay attachments, which the reference tree
// does not build.
import MetalUICore
import MetalUILayout

/// The built-in linear stack, as an outside module would write it.
/// `aCustomLayoutReimplementingTheLinearStackMatchesTheBuiltInRects`
/// requires it to reproduce every stored rect of the built-in kind.
///
/// It is test-only, so if it and `LayoutTree`'s `linearStack` case drift apart
/// on a tree the equivalence test does not build, a reader of this file is
/// misled and no user is (ruling SA-B's cost).
struct ReferenceLinearStack: ProposalLayout {
    var axis: ProposalStackAxis
    var spacing: Double
    var alignment: ProposalAlignment
    /// Positive-control switches: `PriorityBlindLinearStack` and
    /// `OrderBlindLinearStack` each turn exactly one off.
    var readsPriority = true
    var sortsByFlexibility = true

    init(axis: ProposalStackAxis, spacing: Double = 0, alignment: ProposalAlignment = .center) {
        self.axis = axis
        self.spacing = spacing
        self.alignment = alignment
    }

    func sizeThatFits(proposal: ProposedSize, subviews: MeasurementSubviews) -> LayoutMeasurement {
        LayoutMeasurement(size: solve(proposal: proposal,
                                      priorities: subviews.map { priority($0.priority) },
                                      spacers: subviews.map(\.isSpacer),
                                      measure: { subviews[$0].sizeThatFits($1) }).size)
    }

    func placeSubviews(in bounds: LayoutRect, proposal: ProposedSize,
                       subviews: PlacementSubviews) {
        let priorities = subviews.map { priority($0.priority) }
        let spacers = subviews.map(\.isSpacer)
        let measure: (Int, ProposedSize) -> LayoutMeasurement = { subviews[$0].sizeThatFits($1) }
        var solveProposal = proposal
        switch axis {
        case .horizontal where proposal.height == nil:
            solveProposal.height = solve(proposal: proposal, priorities: priorities, spacers: spacers,
                                         measure: measure).size.height
        case .vertical where proposal.width == nil:
            solveProposal.width = solve(proposal: proposal, priorities: priorities, spacers: spacers,
                                        measure: measure).size.width
        default:
            break
        }
        let solution = solve(proposal: solveProposal, priorities: priorities, spacers: spacers, measure: measure)
        var cursor = axis == .horizontal ? bounds.x : bounds.y
        for index in subviews.indices {
            let answer = solution.answers[index]
            let origin: Point<Double>
            switch axis {
            case .horizontal:
                origin = Point(x: cursor, y: bounds.y + (bounds.height - answer.height) * alignment.verticalFactor)
                cursor += answer.width + spacing
            case .vertical:
                origin = Point(x: bounds.x + (bounds.width - answer.width) * alignment.horizontalFactor, y: cursor)
                cursor += answer.height + spacing
            }
            subviews[index].place(at: origin, anchor: .topLeading, proposal: solution.proposals[index])
        }
    }

    private func priority(_ value: Double) -> Double { readsPriority ? value : 0 }

    private func offer(_ main: Double?, cross: Double?) -> ProposedSize {
        axis == .horizontal ? ProposedSize(width: main, height: cross) : ProposedSize(width: cross, height: main)
    }

    private func mainLength(_ size: SizeD) -> Double { axis == .horizontal ? size.width : size.height }
    private func crossLength(_ size: SizeD) -> Double { axis == .horizontal ? size.height : size.width }

    private func solve(proposal: ProposedSize, priorities: [Double], spacers: [Bool],
                       measure: (Int, ProposedSize) -> LayoutMeasurement)
        -> (answers: [SizeD], proposals: [ProposedSize], size: SizeD) {
        let count = priorities.count
        let main = axis == .horizontal ? proposal.width : proposal.height
        let cross = axis == .horizontal ? proposal.height : proposal.width
        let gaps = Double(max(0, count - 1)) * spacing
        var proposals = Array(repeating: offer(main, cross: cross), count: count)
        var answers = Array(repeating: SizeD(width: 0, height: 0), count: count)

        if let main, main.isFinite, count > 0 {
            var remaining = main - gaps
            for group in Set(priorities).sorted(by: >) {
                let members = priorities.indices.filter { priorities[$0] == group }
                let reserved = priorities.indices.filter { priorities[$0] < group }.reduce(0.0) {
                    $0 + mainLength(measure($1, offer(0, cross: cross)).size)
                }
                var order = members
                if members.count > 1 && sortsByFlexibility {
                    var flexibility: [Int: Double] = [:]
                    for index in members {
                        flexibility[index] = mainLength(measure(index, offer(.infinity, cross: cross)).size)
                            - mainLength(measure(index, offer(0, cross: cross)).size)
                    }
                    order.sort { lhs, rhs in
                        flexibility[lhs]! != flexibility[rhs]! ? flexibility[lhs]! < flexibility[rhs]! : lhs < rhs
                    }
                }
                var groupRemaining = remaining - reserved
                for (served, index) in order.enumerated() {
                    proposals[index] = offer(max(0, groupRemaining / Double(order.count - served)), cross: cross)
                    answers[index] = measure(index, proposals[index]).size
                    groupRemaining -= mainLength(answers[index])
                    remaining -= mainLength(answers[index])
                }
            }
        } else {
            for index in 0..<count { answers[index] = measure(index, proposals[index]).size }
        }

        let mainTotal = answers.reduce(gaps) { $0 + mainLength($1) }
        // A spacer's cross answer is left out: the built-in's is 0 (CN-C).
        let crossMax = answers.indices.filter { !spacers[$0] }.map { crossLength(answers[$0]) }.max() ?? 0
        return (answers, proposals,
                axis == .horizontal ? SizeD(width: mainTotal, height: crossMax)
                                    : SizeD(width: crossMax, height: mainTotal))
    }
}

/// Positive control: the reference stack reading every priority as 0. Exists
/// to prove the equivalence tree's rects depend on priority at all (shape 15).
struct PriorityBlindLinearStack: ProposalLayout {
    var base: ReferenceLinearStack

    init(axis: ProposalStackAxis, spacing: Double = 0, alignment: ProposalAlignment = .center) {
        base = ReferenceLinearStack(axis: axis, spacing: spacing, alignment: alignment)
        base.readsPriority = false
    }

    func sizeThatFits(proposal: ProposedSize, subviews: MeasurementSubviews) -> LayoutMeasurement {
        base.sizeThatFits(proposal: proposal, subviews: subviews)
    }

    func placeSubviews(in bounds: LayoutRect, proposal: ProposedSize, subviews: PlacementSubviews) {
        base.placeSubviews(in: bounds, proposal: proposal, subviews: subviews)
    }
}

/// Positive control: the reference stack serving each group in declaration
/// order, never by flexibility. Exists to prove the equivalence tree's rects
/// depend on the order at all (shape 15).
struct OrderBlindLinearStack: ProposalLayout {
    var base: ReferenceLinearStack

    init(axis: ProposalStackAxis, spacing: Double = 0, alignment: ProposalAlignment = .center) {
        base = ReferenceLinearStack(axis: axis, spacing: spacing, alignment: alignment)
        base.sortsByFlexibility = false
    }

    func sizeThatFits(proposal: ProposedSize, subviews: MeasurementSubviews) -> LayoutMeasurement {
        base.sizeThatFits(proposal: proposal, subviews: subviews)
    }

    func placeSubviews(in bounds: LayoutRect, proposal: ProposedSize, subviews: PlacementSubviews) {
        base.placeSubviews(in: bounds, proposal: proposal, subviews: subviews)
    }
}
