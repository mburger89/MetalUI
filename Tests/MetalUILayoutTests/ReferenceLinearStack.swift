// **A PLAIN import, never `@testable`, and that is the proof.** This file
// reimplements the built-in `linearStack` node kind as a `ProposalLayout`
// using only public API: the proxies' `priority`, `isSpacer`, `sizeThatFits`
// and `place`, and `ProposalAlignment`'s factors. If it compiled only with
// `@testable`, the protocol would be insufficient for the one algorithm the
// kernel already ships (ruling SA-B, SA-P).
//
// A plain import in one file of a test target is not widened by `@testable`
// imports in the target's other files: measured on a two-file scratch package
// (`error: cannot find 'secret' in scope`; ruling SA-P, evidence 7 of the
// kernel completion design). So `MetalUILayoutTests` being full of `@testable`
// files does not weaken this one.
import MetalUICore
import MetalUILayout

/// The built-in linear stack, line for line, as an outside module would write
/// it. `aCustomLayoutReimplementingTheLinearStackMatchesTheBuiltInRects`
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
    /// `SpacerBlindLinearStack` each turn exactly one off.
    var readsPriority = true
    var readsSpacers = true

    init(axis: ProposalStackAxis, spacing: Double = 0, alignment: ProposalAlignment = .center) {
        self.axis = axis
        self.spacing = spacing
        self.alignment = alignment
    }

    func sizeThatFits(proposal: ProposedSize, subviews: MeasurementSubviews) -> LayoutMeasurement {
        let childProposal = stackChildProposal(parent: proposal)
        let childMeasurements = subviews.map { $0.sizeThatFits(childProposal) }
        let gaps = Double(max(0, childMeasurements.count - 1)) * spacing
        let hasSpacer = subviews.contains { spacer($0.isSpacer) }
        switch axis {
        case .horizontal:
            let naturalWidth = childMeasurements.reduce(gaps) { $0 + $1.size.width }
            return LayoutMeasurement(
                size: SizeD(width: resolvedStackMainSize(naturalWidth, proposal: proposal.width,
                                                         hasSpacer: hasSpacer),
                            height: childMeasurements.map(\.size.height).max() ?? 0)
            )
        case .vertical:
            let naturalHeight = childMeasurements.reduce(gaps) { $0 + $1.size.height }
            return LayoutMeasurement(
                size: SizeD(width: childMeasurements.map(\.size.width).max() ?? 0,
                            height: resolvedStackMainSize(naturalHeight, proposal: proposal.height,
                                                          hasSpacer: hasSpacer))
            )
        }
    }

    func placeSubviews(in bounds: LayoutRect, proposal: ProposedSize,
                       subviews: PlacementSubviews) {
        let childProposal = stackChildProposal(parent: proposal)
        let childMeasurements = subviews.map { $0.sizeThatFits(childProposal) }
        let naturalMain = stackMainSize(childMeasurements)
        let spacers = subviews.map { spacer($0.isSpacer) }
        let spacerCount = spacers.filter { $0 }.count
        let availableMain = axis == .horizontal ? bounds.width : bounds.height
        let extraPerSpacer = spacerCount == 0 ? 0 : max(0, availableMain - naturalMain) / Double(spacerCount)
        let allocations = stackMainAllocations(priorities: subviews.map { priority($0.priority) },
                                               measurements: childMeasurements,
                                               available: availableMain,
                                               hasSpacer: spacerCount > 0)
        var cursor = axis == .horizontal ? bounds.x : bounds.y
        for index in subviews.indices {
            let subview = subviews[index]
            let baseMeasurement = childMeasurements[index]
            var placementProposal = childProposal
            if spacers[index] {
                switch axis {
                case .horizontal:
                    placementProposal = ProposedSize(width: baseMeasurement.size.width + extraPerSpacer,
                                                     height: childProposal.height)
                case .vertical:
                    placementProposal = ProposedSize(width: childProposal.width,
                                                     height: baseMeasurement.size.height + extraPerSpacer)
                }
            }
            var constrainedProposal = placementProposal
            if let allocated = allocations[index] {
                switch axis {
                case .horizontal:
                    constrainedProposal = ProposedSize(width: allocated, height: placementProposal.height)
                case .vertical:
                    constrainedProposal = ProposedSize(width: placementProposal.width, height: allocated)
                }
            }
            let measurement = subview.sizeThatFits(constrainedProposal)
            let origin: Point<Double>
            switch axis {
            case .horizontal:
                origin = Point(x: cursor,
                               y: bounds.y + (bounds.height - measurement.size.height) * alignment.verticalFactor)
                cursor += measurement.size.width + spacing
            case .vertical:
                origin = Point(x: bounds.x + (bounds.width - measurement.size.width) * alignment.horizontalFactor,
                               y: cursor)
                cursor += measurement.size.height + spacing
            }
            subview.place(at: origin, anchor: .topLeading, proposal: constrainedProposal)
        }
    }

    private func priority(_ value: Double) -> Double { readsPriority ? value : 0 }
    private func spacer(_ value: Bool) -> Bool { readsSpacers ? value : false }

    private func stackChildProposal(parent: ProposedSize) -> ProposedSize {
        switch axis {
        case .horizontal: ProposedSize(width: nil, height: parent.height)
        case .vertical: ProposedSize(width: parent.width, height: nil)
        }
    }

    private func resolvedStackMainSize(_ natural: Double, proposal: Double?, hasSpacer: Bool) -> Double {
        guard let proposal, proposal.isFinite else { return natural }
        return hasSpacer ? max(natural, proposal) : min(natural, proposal)
    }

    private func stackMain(_ measurement: LayoutMeasurement) -> Double {
        switch axis {
        case .horizontal: measurement.size.width
        case .vertical: measurement.size.height
        }
    }

    private func stackMainSize(_ measurements: [LayoutMeasurement]) -> Double {
        let gaps = Double(max(0, measurements.count - 1)) * spacing
        return measurements.reduce(gaps) { $0 + stackMain($1) }
    }

    private func stackMainAllocations(priorities: [Double], measurements: [LayoutMeasurement],
                                      available: Double, hasSpacer: Bool) -> [Double?] {
        let natural = stackMainSize(measurements)
        guard !hasSpacer, available < natural else { return Array(repeating: nil, count: priorities.count) }
        var allocations = [Double?](repeating: nil, count: priorities.count)
        var remaining = max(0, available - Double(max(0, priorities.count - 1)) * spacing)
        for priority in Set(priorities).sorted(by: >) {
            let indices = priorities.indices.filter { priorities[$0] == priority }
            let ideal = indices.reduce(0) { $0 + stackMain(measurements[$1]) }
            if remaining >= ideal {
                for index in indices { allocations[index] = stackMain(measurements[index]) }
                remaining -= ideal
            } else {
                let share = remaining / Double(indices.count)
                for index in indices { allocations[index] = share }
                remaining = 0
            }
        }
        return allocations
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

/// Positive control: the reference stack reading every `isSpacer` as false.
struct SpacerBlindLinearStack: ProposalLayout {
    var base: ReferenceLinearStack

    init(axis: ProposalStackAxis, spacing: Double = 0, alignment: ProposalAlignment = .center) {
        base = ReferenceLinearStack(axis: axis, spacing: spacing, alignment: alignment)
        base.readsSpacers = false
    }

    func sizeThatFits(proposal: ProposedSize, subviews: MeasurementSubviews) -> LayoutMeasurement {
        base.sizeThatFits(proposal: proposal, subviews: subviews)
    }

    func placeSubviews(in bounds: LayoutRect, proposal: ProposedSize, subviews: PlacementSubviews) {
        base.placeSubviews(in: bounds, proposal: proposal, subviews: subviews)
    }
}
