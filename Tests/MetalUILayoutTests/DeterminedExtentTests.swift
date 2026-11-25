import Testing
import MetalUICore
@testable import MetalUILayout

// `HS-M` (record 413): a frame answers some axes without its child, and a stack's flexibility probes and a split view's pane limits
// read only one axis, so they need not measure the subtree. `determinedExtent` is the one place that says which; these tests
// pin it to the full measurement over every combination of bounds, children and proposals, then pin what the stack does with it.
// Probe: `docs/probes/swiftui-flex-frame-determined.swift` (the same grid, run in SwiftUI).

/// A leaf of a fixed width and height 20, whatever it is proposed.
private func fixedLeaf(_ tree: LayoutTree, _ width: Double) -> LayoutNodeID {
    tree.newNativeLeaf { _ in LayoutMeasurement(size: SizeD(width: width, height: 20)) }
}

private struct Bounds1: CustomStringConvertible {
    var width: Double?, minimum: Double?, ideal: Double?, maximum: Double?
    var description: String {
        "w=\(width.map { "\($0)" } ?? "-") min=\(minimum.map { "\($0)" } ?? "-") ideal=\(ideal.map { "\($0)" } ?? "-") max=\(maximum.map { "\($0)" } ?? "-")"
    }
}

private let allBounds: [Bounds1] = {
    var out: [Bounds1] = [Bounds1(width: 150)]
    let minimums: [Double?] = [nil, 0, 240, 320]
    let ideals: [Double?] = [nil, 250]
    let maximums: [Double?] = [nil, 380, 800, .infinity]
    for minimum in minimums {
        for ideal in ideals {
            for maximum in maximums {
                if let minimum, let ideal, minimum > ideal { continue }
                if let ideal, let maximum, ideal > maximum { continue }
                if let minimum, let maximum, minimum > maximum { continue }
                out.append(Bounds1(minimum: minimum, ideal: ideal, maximum: maximum))
            }
        }
    }
    return out
}()

private let proposals: [Double?] = [nil, 0, 1, 100, 240, 250, 320, 380, 500, 800, 900, .infinity]
private let childWidths: [Double] = [10, 500, 1500, 5000]

/// **1** `determinedExtent(frame, p)` is the width `measureNative` answers, whenever it answers at all; and it answers exactly
/// when no child width changes the measured answer (over four widths from 10 to 5000, which straddle every bound above).
/// Mutations: `framedDetermined` always `nil` (the second half reddens); the `min != nil` arm answering `proposal` unclamped; the
/// `proposal >= hi` arm without `min == nil`'s guard (a minimum alone is not determined); the ideal arm unclamped.
@Test func aFramesDeterminedExtentIsTheMeasuredWidthAndExistsExactlyWhenNoChildChangesIt() {
    var determined = 0
    var undetermined = 0
    for bounds in allBounds {
        for proposal in proposals {
            var answers: [Double] = []
            var claimed: [Double?] = []
            for child in childWidths {
                let tree = LayoutTree(generation: 0)
                let frame = tree.newNativeFrame(child: fixedLeaf(tree, child), width: bounds.width,
                                                minWidth: bounds.minimum, idealWidth: bounds.ideal, maxWidth: bounds.maximum)
                let size = tree.measureNativeLayout(root: frame, proposal: ProposedSize(width: proposal, height: 100)).size
                answers.append(size.width)
                claimed.append(tree.determinedExtent(frame, proposal: ProposedSize(width: proposal, height: 100), horizontal: true))
            }
            let independent = answers.allSatisfy { $0 == answers[0] }
            if let first = claimed[0] {
                determined += 1
                #expect(claimed.allSatisfy { $0 == first }, "\(bounds) at \(String(describing: proposal)): \(claimed)")
                #expect(answers.allSatisfy { $0 == first }, "\(bounds) at \(String(describing: proposal)): claimed \(first), measured \(answers)")
            } else {
                undetermined += 1
                #expect(!independent, "\(bounds) at \(String(describing: proposal)): the child never shows through (\(answers)) but nothing was claimed")
            }
        }
    }
    #expect(determined > 100 && undetermined > 100, "the grid reaches both kinds: \(determined), \(undetermined)")
}

/// **2** The height axis is the same function over the height bounds: `horizontal: false` reads the frame's height arms.
/// Mutation: `determinedExtent` reading the width arms for `horizontal: false`.
@Test func theHeightAxisReadsTheHeightBounds() {
    let tree = LayoutTree(generation: 0)
    let frame = tree.newNativeFrame(child: fixedLeaf(tree, 10), minWidth: 100, maxWidth: 200,
                                    minHeight: 30, idealHeight: 40, maxHeight: 50)
    #expect(tree.determinedExtent(frame, proposal: ProposedSize(width: 150, height: 45), horizontal: false) == 45)
    #expect(tree.determinedExtent(frame, proposal: ProposedSize(width: 150, height: nil), horizontal: false) == 40)
    #expect(tree.determinedExtent(frame, proposal: ProposedSize(width: 150, height: 0), horizontal: false) == 30)
    #expect(tree.determinedExtent(frame, proposal: ProposedSize(width: 150, height: 99), horizontal: false) == 50)
    #expect(tree.determinedExtent(frame, proposal: ProposedSize(width: nil, height: 45), horizontal: true) == nil,
            "no proposal and no ideal: the width is the child's")
}

/// **3** Only a frame is determined: padding, a leaf and a stack over the same bounds are measured. Mutation: `determinedExtent`
/// answering for a `padding` node.
@Test func onlyAFrameAnswersWithoutItsChild() {
    let tree = LayoutTree(generation: 0)
    let leaf = fixedLeaf(tree, 10)
    let padded = tree.newNativePadding(child: tree.newNativeFrame(child: leaf, width: 40),
                                       insets: Edges(top: 0, right: 0, bottom: 0, left: 0))
    let stack = tree.newNativeLinearStack(children: [tree.newNativeFrame(child: fixedLeaf(tree, 3), width: 40)], axis: .horizontal)
    for node in [leaf, padded, stack] {
        #expect(tree.determinedExtent(node, proposal: ProposedSize(width: 100, height: 100), horizontal: true) == nil)
    }
}

// MARK: - The stack

private final class Log: @unchecked Sendable { var widths: [Double?] = [] }

/// **4** A stack's flexibility probe at main infinity does not measure a greedy frame's subtree. `HStack { frame(width: 4);
/// frame(maxWidth: .infinity) { leaf } }` at 100 offers the leaf 0 (the minimum probe, a frame with no minimum reads its child
/// there) and 96 (its share), and not infinity. Mutation: `mainExtent` measuring (the leaf sees infinity).
@Test func aGreedyFramesInfiniteProbeDoesNotMeasureItsChild() {
    let tree = LayoutTree(generation: 0)
    let log = Log()
    let probed = tree.newNativeLeaf { proposal in
        log.widths.append(proposal.width)
        return LayoutMeasurement(size: SizeD(width: Swift.min(60, proposal.width ?? 60), height: 20))
    }
    let root = tree.newNativeLinearStack(children: [
        tree.newNativeFrame(child: fixedLeaf(tree, 1), width: 4),
        tree.newNativeFrame(child: probed, maxWidth: .infinity)
    ], axis: .horizontal)
    tree.computeNativeLayout(root: root, proposal: ProposedSize(width: 100, height: 50), in: LayoutRect(x: 0, y: 0, width: 100, height: 50))
    #expect(Set(log.widths.compactMap { $0 }) == [0, 96], "\(log.widths)")
    #expect(!log.widths.contains(.infinity) && !log.widths.contains(nil), "\(log.widths)")
}

/// A stack over `members`, each a frame spelled by `spec` over a leaf, optionally with every frame wrapped in zero padding (the
/// wrapper is not a frame, so the stack measures the old way). Returns the root and the frames' nodes (the wrappers when wrapped).
private func stack(_ tree: LayoutTree, axis: ProposalStackAxis, specs: [Bounds1], wrapped: Bool) -> (root: LayoutNodeID, members: [LayoutNodeID]) {
    let members = specs.enumerated().map { index, spec -> LayoutNodeID in
        let leaf = tree.newNativeLeaf { proposal in
            let ideal = 30.0 + Double(index) * 25
            let main = axis == .horizontal ? proposal.width : proposal.height
            let extent = Swift.min(ideal, main ?? ideal)
            return LayoutMeasurement(size: axis == .horizontal ? SizeD(width: extent, height: 20) : SizeD(width: 20, height: extent))
        }
        let frame = axis == .horizontal
            ? tree.newNativeFrame(child: leaf, width: spec.width, minWidth: spec.minimum, idealWidth: spec.ideal, maxWidth: spec.maximum)
            : tree.newNativeFrame(child: leaf, height: spec.width, minHeight: spec.minimum, idealHeight: spec.ideal, maxHeight: spec.maximum)
        return wrapped ? tree.newNativePadding(child: frame, insets: Edges(top: 0, right: 0, bottom: 0, left: 0)) : frame
    }
    return (tree.newNativeLinearStack(children: members, axis: axis, spacing: 3), members)
}

/// **5** A stack of frames lays out exactly as the same stack with every frame behind a wrapper that is not a frame: the same answer
/// and every child's rect, over both axes, every pair of bounds and eight main proposals. Mutations: the stack taking
/// `determinedExtent` for a `max(proposal, child)` answer at a finite proposal under the maximum (the `proposal >= hi` guard dropped).
@Test func aStackOfFramesLaysOutAsItDidBeforeItAskedAFrameForOneAxis() {
    let picks: [Bounds1] = [Bounds1(width: 4), Bounds1(maximum: .infinity), Bounds1(minimum: 50, maximum: 200),
                            Bounds1(maximum: 120), Bounds1(minimum: 40), Bounds1(ideal: 70), Bounds1(minimum: 20, ideal: 70, maximum: 90),
                            Bounds1(minimum: 0, maximum: .infinity)]
    let mains: [Double?] = [nil, 0, 30, 100, 160, 300, 700, 2000]
    var checked = 0
    for axis in [ProposalStackAxis.horizontal, .vertical] {
        for first in picks.indices {
            for second in picks.indices {
                for third in [0, 3, 6] {
                    let specs = [picks[first], picks[second], picks[third]]
                    for main in mains {
                        let proposal = axis == .horizontal ? ProposedSize(width: main, height: 80) : ProposedSize(width: 80, height: main)
                        let bounds = axis == .horizontal
                            ? LayoutRect(x: 0, y: 0, width: main.flatMap { $0.isFinite ? $0 : nil } ?? 400, height: 80)
                            : LayoutRect(x: 0, y: 0, width: 80, height: main.flatMap { $0.isFinite ? $0 : nil } ?? 400)
                        let (a, b) = (LayoutTree(generation: 0), LayoutTree(generation: 0))
                        let plain = stack(a, axis: axis, specs: specs, wrapped: false)
                        let wrapped = stack(b, axis: axis, specs: specs, wrapped: true)
                        let answerA = a.computeNativeLayout(root: plain.root, proposal: proposal, in: bounds)
                        let answerB = b.computeNativeLayout(root: wrapped.root, proposal: proposal, in: bounds)
                        let label = "\(axis) \(specs) at \(String(describing: main))"
                        #expect(answerA.size == answerB.size, "\(label): \(answerA.size) vs \(answerB.size)")
                        for (x, y) in zip(plain.members, wrapped.members) {
                            #expect(a.layout(x) == b.layout(y), "\(label): \(a.layout(x)) vs \(b.layout(y))")
                        }
                        checked += 1
                    }
                }
            }
        }
    }
    #expect(checked > 1000, "\(checked)")
}

/// **6** The rows `docs/probes/swiftui-flex-frame-determined.swift` recorded from SwiftUI, as literals: over a child 10 wide, the
/// answer at proposals 0, nil, 100, 500, 900 and infinity, and whether SwiftUI's answer was the same over children of 500 and 1500
/// (`=`: determined here too). The measured answer is SwiftUI's; `determinedExtent` is that answer exactly where SwiftUI's did not
/// move with the child, and `nil` where it did. Mutations: any arm of `framedDetermined` answering a different number (the min+max
/// arm unclamped, the ideal arm answering the child, the maximum-alone arm answering at a proposal below the maximum).
@Test func theRecordedSwiftUIRowsHoldMeasuredAndDetermined() {
    let inf = Double.infinity
    let proposals: [Double?] = [0, nil, 100, 500, 900, inf]
    typealias Row = (name: String, bounds: Bounds1, answers: [(Double, Bool)])
    let rows: [Row] = [
        ("min320 max inf", Bounds1(minimum: 320, maximum: inf),
         [(320, true), (320, false), (320, true), (500, true), (900, true), (inf, true)]),
        ("min200 ideal250 max380", Bounds1(minimum: 200, ideal: 250, maximum: 380),
         [(200, true), (250, true), (200, true), (380, true), (380, true), (380, true)]),
        ("min240 max800", Bounds1(minimum: 240, maximum: 800),
         [(240, true), (240, false), (240, true), (500, true), (800, true), (800, true)]),
        ("max380 only", Bounds1(maximum: 380),
         [(10, false), (10, false), (100, false), (380, true), (380, true), (380, true)]),
        ("max inf only", Bounds1(maximum: inf),
         [(10, false), (10, false), (100, false), (500, false), (900, false), (inf, true)]),
        ("fixed 150", Bounds1(width: 150),
         [(150, true), (150, true), (150, true), (150, true), (150, true), (150, true)])
    ]
    for row in rows {
        for (proposal, expected) in zip(proposals, row.answers) {
            let tree = LayoutTree(generation: 0)
            let frame = tree.newNativeFrame(child: fixedLeaf(tree, 10), width: row.bounds.width, minWidth: row.bounds.minimum,
                                            idealWidth: row.bounds.ideal, maxWidth: row.bounds.maximum)
            let offer = ProposedSize(width: proposal, height: 100)
            #expect(tree.measureNativeLayout(root: frame, proposal: offer).size.width == expected.0,
                    "\(row.name) at \(String(describing: proposal)): measured")
            let known = tree.determinedExtent(frame, proposal: offer, horizontal: true)
            #expect(known == (expected.1 ? expected.0 : nil), "\(row.name) at \(String(describing: proposal)): determined \(String(describing: known))")
        }
    }
}
