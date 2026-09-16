import Testing
import MetalUICore
@testable import MetalUILayout

// Lane 1 ("distribution") of `docs/superpowers/specs/2026-09-16-containers-design.md`:
// rulings CN-B (flexibility-ordered, priority-grouped distribution answering the
// sum of its children's answers), CN-D (single-child pass-through), CN-E's
// second-pass clause, and the parts of CN-C (a spacer's priority is −∞) and
// CN-F (a spacer answers ∞ at ∞) the distribution cannot be pinned without, in
// `docs/superpowers/2026-09-16-containers-decisions.md`.
//
// Every arm name and number below is SwiftUI's, read by
// `docs/probes/swiftui-stack-algorithms.swift` (revision 4) or, for E, E2 and
// L3, `docs/probes/swiftui-layout-protocol-contract.swift`; both headers hold
// the recorded output. The leaves mirror the probe's `Leaf`: a leaf answers
// `clamp(proposal ?? ideal, min, max)` per axis and logs each DISTINCT
// proposal it is asked, in order. Every probe `Spacer()` is written
// `newNativeSpacer(minLength: 8)` here, because the nil default of 8 is lane
// 2's (CN-C), and spacer arms assert the MAIN axis only, because a spacer's
// zero on its stack's cross axis is lane 2's too.
//
// A root is measured at the arm's proposal and then laid out at that proposal
// in bounds of its own answer at the origin, which is where the probe's `Probe`
// layout puts the view under test.

/// A leaf's distinct proposals, in the order first asked.
private final class ProposalLog: @unchecked Sendable {
    var proposals: [ProposedSize] = []
    var calls = 0
    func record(_ proposal: ProposedSize) {
        calls += 1
        if !proposals.contains(proposal) { proposals.append(proposal) }
    }
}

/// One probe arm: a tree, its named nodes and their logs.
private final class Arm {
    let tree = LayoutTree(generation: 0)
    private var nodes: [String: LayoutNodeID] = [:]
    private var logs: [String: ProposalLog] = [:]

    @discardableResult
    func leaf(_ name: String, minW: Double, idealW: Double, maxW: Double,
              minH: Double, idealH: Double, maxH: Double) -> LayoutNodeID {
        let log = ProposalLog()
        let id = tree.newNativeLeaf { proposal in
            log.record(proposal)
            return LayoutMeasurement(size: SizeD(
                width: Swift.min(Swift.max(proposal.width ?? idealW, minW), maxW),
                height: Swift.min(Swift.max(proposal.height ?? idealH, minH), maxH)))
        }
        nodes[name] = id
        logs[name] = log
        return id
    }

    /// The probe's `fixed(n, w, h)`.
    func fixed(_ name: String, _ width: Double, _ height: Double) -> LayoutNodeID {
        leaf(name, minW: width, idealW: width, maxW: width, minH: height, idealH: height, maxH: height)
    }

    /// The probe's `flexW(n, min, ideal, max, h)`.
    func flexW(_ name: String, _ min: Double, _ ideal: Double, _ max: Double, _ height: Double = 20) -> LayoutNodeID {
        leaf(name, minW: min, idealW: ideal, maxW: max, minH: height, idealH: height, maxH: height)
    }

    /// The probe's `flexH(n, min, ideal, max, w)`.
    func flexH(_ name: String, _ min: Double, _ ideal: Double, _ max: Double, _ width: Double = 20) -> LayoutNodeID {
        leaf(name, minW: width, idealW: width, maxW: width, minH: min, idealH: ideal, maxH: max)
    }

    /// The probe's `AreaLeaf`: width `max(1, min(proposal ?? ideal, 1000))`,
    /// height `area / width`.
    func area(_ name: String, _ area: Double, ideal: Double) -> LayoutNodeID {
        let log = ProposalLog()
        let id = tree.newNativeLeaf { proposal in
            log.record(proposal)
            let width = Swift.max(1, Swift.min(proposal.width ?? ideal, 1000))
            return LayoutMeasurement(size: SizeD(width: width, height: area / width))
        }
        nodes[name] = id
        logs[name] = log
        return id
    }

    func spacer(_ name: String, minLength: Double = 8) -> LayoutNodeID {
        self.name(tree.newNativeSpacer(minLength: minLength), name)
    }

    func hstack(_ name: String, spacing: Double = 0, _ children: [LayoutNodeID]) -> LayoutNodeID {
        self.name(tree.newNativeLinearStack(children: children, axis: .horizontal, spacing: spacing), name)
    }

    func vstack(_ name: String, spacing: Double = 0, _ children: [LayoutNodeID]) -> LayoutNodeID {
        self.name(tree.newNativeLinearStack(children: children, axis: .vertical, spacing: spacing), name)
    }

    func priority(_ child: LayoutNodeID, _ value: Double) -> LayoutNodeID {
        tree.newNativeLayoutPriority(child: child, priority: value)
    }

    @discardableResult
    func name(_ id: LayoutNodeID, _ name: String) -> LayoutNodeID {
        nodes[name] = id
        return id
    }

    /// Measures `root` at `proposal`, then lays it out at `proposal` in bounds
    /// of its answer at the origin, and returns the answer.
    @discardableResult
    func run(_ root: LayoutNodeID, _ width: Double?, _ height: Double?) -> SizeD {
        let proposal = ProposedSize(width: width, height: height)
        let answer = tree.measureNativeLayout(root: root, proposal: proposal).size
        tree.computeNativeLayout(root: root, proposal: proposal,
                                 in: LayoutRect(x: 0, y: 0, width: answer.width, height: answer.height))
        return answer
    }

    /// Measures only, for an arm whose answer may be infinite (the probe's
    /// `runMeasured`; placing an infinite answer traps in both).
    func measure(_ root: LayoutNodeID, _ width: Double?, _ height: Double?) -> SizeD {
        tree.measureNativeLayout(root: root, proposal: ProposedSize(width: width, height: height)).size
    }

    subscript(_ name: String) -> LayoutRect { tree.layout(nodes[name]!) }
    func x(_ name: String) -> Double { self[name].x }
    func width(_ name: String) -> Double { self[name].width }
    func proposals(_ name: String) -> [ProposedSize] { logs[name]!.proposals }
}

private func rect(_ x: Double, _ y: Double, _ width: Double, _ height: Double) -> LayoutRect {
    LayoutRect(x: x, y: y, width: width, height: height)
}

private func size(_ width: Double, _ height: Double) -> SizeD { SizeD(width: width, height: height) }

private func p(_ width: Double?, _ height: Double?) -> ProposedSize { ProposedSize(width: width, height: height) }

// MARK: - 1.1 flexibility order

/// CN-B step 4: inside a priority group, children are served least flexible
/// first (flexibility = answer at main ∞ minus answer at main 0), ties in
/// declaration order, each proposed `remaining / children left`.
///
/// - G1 `{a 20..100; b 60..100}` at 100×50: b (flexibility 40) is served
///   first at 50 and answers its 60; a gets the 40 left. Before the lane,
///   equal shares: a 50, b 60, and the stack overflows to 110.
/// - G1r, the same two swapped: a still gets 40, so order is by flexibility,
///   not declaration.
/// - X1 `{a 0..80; b fixed 80}`: b (0) first at 50 → 80; a at 20.
/// - X3 `{a 0..80; b fixed 30; c fixed 30}`: b at 33.3 → 30, c at 35 → 30,
///   a at 40.
/// - X4 `{a 0..100 ideal 50; b 40..60 ideal 50}` at 70: b (20) at 35 → 40, a
///   at 30.
///
/// Mutations: sort by flexibility descending (G1 a 60…); no sort (G1r's b
/// served first at 50 → 60 is the same, but G1's a is served at 50).
@Test func aStackServesItsLeastFlexibleChildFirst() {
    do { // G1
        let arm = Arm()
        let root = arm.hstack("s", [arm.flexW("a", 20, 100, 100), arm.flexW("b", 60, 100, 100)])
        #expect(arm.run(root, 100, 50) == size(100, 20), "G1 size")
        #expect(arm["a"] == rect(0, 0, 40, 20), "G1 a")
        #expect(arm["b"] == rect(40, 0, 60, 20), "G1 b")
    }
    do { // G1r
        let arm = Arm()
        let root = arm.hstack("s", [arm.flexW("b", 60, 100, 100), arm.flexW("a", 20, 100, 100)])
        #expect(arm.run(root, 100, 50) == size(100, 20), "G1r size")
        #expect(arm["b"] == rect(0, 0, 60, 20), "G1r b")
        #expect(arm["a"] == rect(60, 0, 40, 20), "G1r a")
    }
    do { // X1
        let arm = Arm()
        let root = arm.hstack("s", [arm.flexW("a", 0, 80, 80), arm.fixed("b", 80, 20)])
        #expect(arm.run(root, 100, 50) == size(100, 20), "X1 size")
        #expect(arm["a"] == rect(0, 0, 20, 20), "X1 a")
        #expect(arm["b"] == rect(20, 0, 80, 20), "X1 b")
    }
    do { // X3
        let arm = Arm()
        let root = arm.hstack("s", [arm.flexW("a", 0, 80, 80), arm.fixed("b", 30, 20), arm.fixed("c", 30, 20)])
        #expect(arm.run(root, 100, 50) == size(100, 20), "X3 size")
        #expect(arm["a"] == rect(0, 0, 40, 20), "X3 a")
        #expect(arm["b"] == rect(40, 0, 30, 20), "X3 b")
        #expect(arm["c"] == rect(70, 0, 30, 20), "X3 c")
        #expect(arm.proposals("c").last == p(35, 50), "X3 c is served second, at 70 / 2")
    }
    do { // X4
        let arm = Arm()
        let root = arm.hstack("s", [arm.flexW("a", 0, 50, 100), arm.flexW("b", 40, 50, 60)])
        #expect(arm.run(root, 70, 50) == size(70, 20), "X4 size")
        #expect(arm["a"] == rect(0, 0, 30, 20), "X4 a")
        #expect(arm["b"] == rect(30, 0, 40, 20), "X4 b")
    }
}

// MARK: - 1.2 lower groups' minimums

/// CN-B step 3: each priority group is offered the remaining length minus the
/// minimum (the answer at main 0) of every lower-priority child.
///
/// - G2 `{a 0..80 prio 1; b 30..80}` at 100: a is offered 100 − 30 = 70; b 30.
///   Before the lane a took its ideal 80, which fit.
/// - G2c, b's minimum 0: a 80, b 20 — the control that G2's 70 is the
///   reservation and not something else.
/// - G14 `{a prio −1; b; c prio 1}`, all 0..80: c 80, b 20, a 0.
/// - X5 `{a 0..80 prio 1; Spacer(); b 0..80}`: a is offered 100 − 8 = 92 and
///   answers 80; b is offered 20 − 8 = 12; the spacer (−∞) gets 8.
///
/// Mutation: drop the lower-group minimum subtraction (G2 a 80).
@Test func aLowerPriorityGroupKeepsItsMinimumsReserved() {
    do { // G2
        let arm = Arm()
        let root = arm.hstack("s", [arm.priority(arm.flexW("a", 0, 80, 80), 1), arm.flexW("b", 30, 80, 80)])
        #expect(arm.run(root, 100, 50) == size(100, 20), "G2 size")
        #expect(arm["a"] == rect(0, 0, 70, 20), "G2 a")
        #expect(arm["b"] == rect(70, 0, 30, 20), "G2 b")
        #expect(arm.proposals("a") == [p(70, 50)], "G2 a is asked once, at 70")
    }
    do { // G2c
        let arm = Arm()
        let root = arm.hstack("s", [arm.priority(arm.flexW("a", 0, 80, 80), 1), arm.flexW("b", 0, 80, 80)])
        #expect(arm.run(root, 100, 50) == size(100, 20), "G2c size")
        #expect(arm["a"] == rect(0, 0, 80, 20), "G2c a")
        #expect(arm["b"] == rect(80, 0, 20, 20), "G2c b")
    }
    do { // G14
        let arm = Arm()
        let root = arm.hstack("s", [arm.priority(arm.flexW("a", 0, 80, 80), -1),
                                    arm.flexW("b", 0, 80, 80),
                                    arm.priority(arm.flexW("c", 0, 80, 80), 1)])
        #expect(arm.run(root, 100, 50) == size(100, 20), "G14 size")
        #expect(arm["a"] == rect(0, 0, 0, 20), "G14 a")
        #expect(arm["b"] == rect(0, 0, 20, 20), "G14 b")
        #expect(arm["c"] == rect(20, 0, 80, 20), "G14 c")
    }
    do { // X5
        let arm = Arm()
        let root = arm.hstack("s", [arm.priority(arm.flexW("a", 0, 80, 80), 1), arm.spacer("sp"),
                                    arm.flexW("b", 0, 80, 80)])
        #expect(arm.run(root, 100, 50).width == 100, "X5 width")
        #expect(arm.proposals("a") == [p(92, 50)], "X5 a is offered 100 − the spacer's 8")
        #expect(arm.x("a") == 0 && arm.width("a") == 80, "X5 a")
        #expect(arm.x("sp") == 80 && arm.width("sp") == 8, "X5 spacer")
        #expect(arm.x("b") == 88 && arm.width("b") == 12, "X5 b")
    }
}

// MARK: - 1.3 a greedy child before a spacer

/// A non-spacer child takes surplus, and does so ahead of a spacer, whose −∞
/// priority serves it last (CN-B, CN-C).
///
/// - G3 `{a fixed 20; b 0..∞ ideal 10}` at 200: a 20, b 180. Before the lane a
///   non-spacer never expanded: b 10.
/// - G5 `{a 20; Spacer(); b 0..∞}`: group 0 is offered 192; a 20, b 172; the
///   spacer 8. G5b swapped: the same widths in the other order.
/// - G25 `{a 0..∞; Spacer(); b 0..∞}`: 96 / 8 / 96.
///
/// Mutation: give a bare spacer priority 0 (G5's spacer takes 90).
@Test func aGreedyChildTakesTheSurplusAheadOfASpacer() {
    do { // G3
        let arm = Arm()
        let root = arm.hstack("s", [arm.fixed("a", 20, 20), arm.flexW("b", 0, 10, .infinity)])
        #expect(arm.run(root, 200, 50) == size(200, 20), "G3 size")
        #expect(arm["a"] == rect(0, 0, 20, 20), "G3 a")
        #expect(arm["b"] == rect(20, 0, 180, 20), "G3 b")
    }
    do { // G5
        let arm = Arm()
        let root = arm.hstack("s", [arm.fixed("a", 20, 20), arm.spacer("sp"), arm.flexW("b", 0, 10, .infinity)])
        #expect(arm.run(root, 200, 50).width == 200, "G5 width")
        #expect(arm.x("sp") == 20 && arm.width("sp") == 8, "G5 spacer")
        #expect(arm.x("b") == 28 && arm.width("b") == 172, "G5 b")
    }
    do { // G5b
        let arm = Arm()
        let root = arm.hstack("s", [arm.flexW("b", 0, 10, .infinity), arm.spacer("sp"), arm.fixed("a", 20, 20)])
        #expect(arm.run(root, 200, 50).width == 200, "G5b width")
        #expect(arm.x("b") == 0 && arm.width("b") == 172, "G5b b")
        #expect(arm.x("sp") == 172 && arm.width("sp") == 8, "G5b spacer")
        #expect(arm.x("a") == 180 && arm.width("a") == 20, "G5b a")
    }
    do { // G25
        let arm = Arm()
        let root = arm.hstack("s", [arm.flexW("a", 0, 10, .infinity), arm.spacer("sp"),
                                    arm.flexW("b", 0, 10, .infinity)])
        #expect(arm.run(root, 200, 50).width == 200, "G25 width")
        #expect(arm.x("a") == 0 && arm.width("a") == 96, "G25 a")
        #expect(arm.x("sp") == 96 && arm.width("sp") == 8, "G25 spacer")
        #expect(arm.x("b") == 104 && arm.width("b") == 96, "G25 b")
    }
}

// MARK: - 1.4 compression with a spacer

/// A stack holding a spacer still compresses its other children (CN-B).
///
/// - G6 `{a fixed 80; Spacer(); b 0..80}` at 100: group 0 is offered 92; a
///   (flexibility 0) at 46 → 80; b at 12; the spacer 8. Before the lane a stack
///   with a spacer never compressed: 80 + 8 + 80.
/// - G6c, no spacer: a 80, b 20 — the control.
///
/// Mutation: skip distribution when a spacer is present.
@Test func aStackWithASpacerStillCompressesItsOtherChildren() {
    do { // G6
        let arm = Arm()
        let root = arm.hstack("s", [arm.fixed("a", 80, 20), arm.spacer("sp"), arm.flexW("b", 0, 80, 80)])
        #expect(arm.run(root, 100, 50).width == 100, "G6 width")
        #expect(arm.x("a") == 0 && arm.width("a") == 80, "G6 a")
        #expect(arm.x("sp") == 80 && arm.width("sp") == 8, "G6 spacer")
        #expect(arm.x("b") == 88 && arm.width("b") == 12, "G6 b")
    }
    do { // G6c
        let arm = Arm()
        let root = arm.hstack("s", [arm.fixed("a", 80, 20), arm.flexW("b", 0, 80, 80)])
        #expect(arm.run(root, 100, 50) == size(100, 20), "G6c size")
        #expect(arm["b"] == rect(80, 0, 20, 20), "G6c b")
    }
}

// MARK: - 1.5 the sum of the answers

/// A stack answers the sum of its children's answers plus spacing: overflow
/// and shrink-wrap included (CN-B step 6).
///
/// - G9 `{a fixed 80; b fixed 80}` at 100: 160, b at 80. Before the lane
///   `min(natural, proposal)`: 100.
/// - G10 `{a 20; b 20}` at 300: 40.
/// - G12 spacing 10, three 0..80 at 100: 80 / 3 each, 100 total. Stored rects
///   are rounded from cumulative edges (`roundLayout`): a 0…26.67 → (0, 27),
///   b 36.67…63.33 → (37, 26), c 73.33…100 → (73, 27); the pre-rounding widths
///   are 80 / 3.
/// - G13 `{a 30..40; b 0..100 ideal 50; c fixed 45}` at 60: served c (0), a
///   (10), b (100): c at 20 → 45, a at 7.5 → 30, b at max(0, −15) → 0. 75, with
///   b at 30 and c at 30.
/// - X13 `{a fixed 80; b fixed 80}` at nil×50: 160.
///
/// Mutation: clamp the total to the proposal (G9 100).
@Test func aStackAnswersTheSumOfItsChildrensAnswers() {
    do { // G9
        let arm = Arm()
        let root = arm.hstack("s", [arm.fixed("a", 80, 20), arm.fixed("b", 80, 20)])
        #expect(arm.run(root, 100, 50) == size(160, 20), "G9 size")
        #expect(arm["a"] == rect(0, 0, 80, 20), "G9 a")
        #expect(arm["b"] == rect(80, 0, 80, 20), "G9 b")
        #expect(arm.proposals("b").last == p(20, 50), "G9 b is offered the 20 left")
    }
    do { // G10
        let arm = Arm()
        let root = arm.hstack("s", [arm.fixed("a", 20, 20), arm.fixed("b", 20, 20)])
        #expect(arm.run(root, 300, 50) == size(40, 20), "G10 size")
        #expect(arm["b"] == rect(20, 0, 20, 20), "G10 b")
    }
    do { // G12
        let arm = Arm()
        let root = arm.hstack("s", spacing: 10, [arm.flexW("a", 0, 80, 80), arm.flexW("b", 0, 80, 80),
                                                 arm.flexW("c", 0, 80, 80)])
        #expect(arm.run(root, 100, 50) == size(100, 20), "G12 size")
        #expect(arm["a"] == rect(0, 0, 27, 20), "G12 a")
        #expect(arm["b"] == rect(37, 0, 26, 20), "G12 b")
        #expect(arm["c"] == rect(73, 0, 27, 20), "G12 c")
    }
    do { // G13
        let arm = Arm()
        let root = arm.hstack("s", [arm.flexW("a", 30, 40, 40), arm.flexW("b", 0, 50, 100), arm.fixed("c", 45, 20)])
        #expect(arm.run(root, 60, 50) == size(75, 20), "G13 size")
        #expect(arm["a"] == rect(0, 0, 30, 20), "G13 a")
        #expect(arm["b"] == rect(30, 0, 0, 20), "G13 b")
        #expect(arm["c"] == rect(30, 0, 45, 20), "G13 c")
        #expect(arm.proposals("a").last == p(7.5, 50), "G13 a is offered 15 / 2")
        #expect(arm.proposals("b").last == p(0, 50), "G13 b is offered max(0, −15)")
    }
    do { // X13
        let arm = Arm()
        let root = arm.hstack("s", [arm.fixed("a", 80, 20), arm.fixed("b", 80, 20)])
        #expect(arm.run(root, nil, 50) == size(160, 20), "X13 size")
        #expect(arm["b"] == rect(80, 0, 80, 20), "X13 b")
    }
}

// MARK: - 1.6 nil and infinite main proposals

/// At a nil or infinite main proposal every child is offered that value, and
/// nothing is distributed (CN-B).
///
/// - G7 `{a 0..80; Spacer(); b 20}` at nil: 80 + 8 + 20 = 108; a is asked only
///   nil×nil (measurement) and nil×20 (placement's second pass, CN-E).
/// - G8 `{a 0..∞ ideal 10; b 20}` at ∞×∞: ∞ wide, each child asked ∞×∞ only
///   (measured, not placed).
/// - G19 `{a 20; Spacer(); b 20}` at nil×50: 48, each leaf asked nil×50 only.
///
/// Mutation: treat nil as 0 in the distribution (G7 a 0).
@Test func aStackAtANilOrInfiniteMainProposalOffersItToEveryChild() {
    do { // G7
        let arm = Arm()
        let root = arm.hstack("s", [arm.flexW("a", 0, 80, 80), arm.spacer("sp"), arm.fixed("b", 20, 20)])
        #expect(arm.run(root, nil, nil) == size(108, 20), "G7 size")
        #expect(arm["a"] == rect(0, 0, 80, 20), "G7 a")
        #expect(arm.x("sp") == 80 && arm.width("sp") == 8, "G7 spacer")
        #expect(arm["b"] == rect(88, 0, 20, 20), "G7 b")
        #expect(arm.proposals("a") == [p(nil, nil), p(nil, 20)], "G7 a")
    }
    do { // G8
        let arm = Arm()
        let root = arm.hstack("s", [arm.flexW("a", 0, 10, .infinity), arm.fixed("b", 20, 20)])
        #expect(arm.measure(root, .infinity, .infinity) == size(.infinity, 20), "G8 size")
        #expect(arm.proposals("a") == [p(.infinity, .infinity)], "G8 a")
        #expect(arm.proposals("b") == [p(.infinity, .infinity)], "G8 b")
    }
    do { // G19
        let arm = Arm()
        let root = arm.hstack("s", [arm.fixed("a", 20, 20), arm.spacer("sp"), arm.fixed("b", 20, 20)])
        #expect(arm.run(root, nil, 50).width == 48, "G19 width")
        #expect(arm.x("b") == 28, "G19 b")
        #expect(arm.proposals("a") == [p(nil, 50)], "G19 a")
        #expect(arm.proposals("b") == [p(nil, 50)], "G19 b")
    }
}

// MARK: - 1.7 the spacer's priority and infinite answer

/// A reader that records what a custom layout sees through its proxies.
private final class ProxyLog: @unchecked Sendable {
    var priorities: [Double] = []
    var answers: [[SizeD]] = []
}

private struct ProxyReader: ProposalLayout {
    let log: ProxyLog
    func sizeThatFits(proposal: ProposedSize, subviews: MeasurementSubviews) -> LayoutMeasurement {
        log.priorities = subviews.map(\.priority)
        log.answers = subviews.map { subview in
            [ProposedSize(width: 0, height: 0), .unspecified,
             ProposedSize(width: .infinity, height: .infinity)].map { subview.sizeThatFits($0).size }
        }
        return LayoutMeasurement(size: SizeD(width: 10, height: 10))
    }
    func placeSubviews(in bounds: LayoutRect, proposal: ProposedSize, subviews: PlacementSubviews) {}
}

/// A spacer has priority −∞ and answers ∞ at ∞ (CN-C's priority, CN-F's
/// spacer clause).
///
/// - SP8 `{a 20; Spacer(); b 20}` at 200: a is offered (200 − 8) / 2 = 96 — a
///   spacer at priority 0 would share a group and offer a 200 / 3; the rects
///   alone cannot tell (the spacer is served last either way).
/// - SP9 `{Spacer(); a 20; Spacer(); Spacer()}` at 200: 60 each, a at 60.
/// - SP10 `{Spacer(min 50); a 20; Spacer()}`: 90 / 20 / 90, a at 90.
/// - X6 `{a 0..80; Spacer().layoutPriority(1); b 0..80}`: the spacer takes all
///   100, a and b 0, b at 100.
/// - X8 `{Spacer().overlay{o 20×20}; a 20}`: a at 180 (the overlaid spacer
///   keeps −∞ and is served last). Main axis only.
/// - Contract probe E through a proxy: a `Spacer(minLength: 12)` reads −∞ and
///   answers 12×12 at zero and unspecified and ∞×∞ at ∞; E2: any node under
///   `.layoutPriority(-.infinity)` reads −∞ too.
///
/// Mutations: restore `spacerLength`'s `isFinite` (E's ∞ reads 12); return 0
/// for a spacer in the stack's priority reader (SP8's 96 reads 66.67).
@Test func aSpacerHasTheLowestPriorityAndAnswersInfinityAtInfinity() {
    do { // SP8
        let arm = Arm()
        let root = arm.hstack("s", [arm.fixed("a", 20, 20), arm.spacer("sp"), arm.fixed("b", 20, 20)])
        #expect(arm.run(root, 200, 50).width == 200, "SP8 width")
        #expect(arm.proposals("a").last == p(96, 50), "SP8 a is offered (200 − 8) / 2")
        #expect(arm.x("sp") == 20 && arm.width("sp") == 160, "SP8 spacer")
        #expect(arm.x("b") == 180, "SP8 b")
    }
    do { // SP9
        let arm = Arm()
        let root = arm.hstack("s", [arm.spacer("s1"), arm.fixed("a", 20, 20), arm.spacer("s2"), arm.spacer("s3")])
        #expect(arm.run(root, 200, 50).width == 200, "SP9 width")
        #expect(arm.proposals("a") == [p(176, 50)], "SP9 a")
        #expect(arm.x("a") == 60, "SP9 a")
        #expect(arm.width("s1") == 60 && arm.width("s2") == 60 && arm.width("s3") == 60, "SP9 spacers")
    }
    do { // SP10
        let arm = Arm()
        let root = arm.hstack("s", [arm.spacer("s1", minLength: 50), arm.fixed("a", 20, 20), arm.spacer("s2")])
        #expect(arm.run(root, 200, 50).width == 200, "SP10 width")
        #expect(arm.proposals("a") == [p(142, 50)], "SP10 a")
        #expect(arm.x("a") == 90, "SP10 a")
        #expect(arm.width("s1") == 90 && arm.x("s2") == 110 && arm.width("s2") == 90, "SP10 spacers")
    }
    do { // X6
        let arm = Arm()
        let spacer = arm.priority(arm.spacer("sp"), 1)
        let root = arm.hstack("s", [arm.flexW("a", 0, 80, 80), spacer, arm.flexW("b", 0, 80, 80)])
        #expect(arm.run(root, 100, 50).width == 100, "X6 width")
        #expect(arm.width("a") == 0, "X6 a")
        #expect(arm.x("sp") == 0 && arm.width("sp") == 100, "X6 spacer")
        #expect(arm.x("b") == 100 && arm.width("b") == 0, "X6 b")
    }
    do { // X8
        let arm = Arm()
        let attached = arm.tree.newNativeOverlayAttachment(child: arm.spacer("sp"), overlay: arm.fixed("o", 20, 20))
        let root = arm.hstack("s", [attached, arm.fixed("a", 20, 20)])
        #expect(arm.run(root, 200, 50).width == 200, "X8 width")
        #expect(arm.proposals("a") == [p(192, 50)], "X8 a")
        #expect(arm.x("sp") == 0 && arm.width("sp") == 180, "X8 spacer")
        #expect(arm.x("a") == 180, "X8 a")
    }
    do { // contract probe E, E2
        let tree = LayoutTree(generation: 0)
        let log = ProxyLog()
        let echo = tree.newNativeLeaf { proposal in
            LayoutMeasurement(size: SizeD(width: proposal.width ?? 10, height: proposal.height ?? 10))
        }
        let root = tree.newNativeLayout(ProxyReader(log: log), children: [
            tree.newNativeSpacer(minLength: 12),
            tree.newNativeLayoutPriority(child: echo, priority: -.infinity),
        ])
        tree.computeNativeLayout(root: root, proposal: ProposedSize(width: 100, height: 100),
                                 in: LayoutRect(x: 0, y: 0, width: 10, height: 10))
        #expect(log.priorities == [-.infinity, -.infinity], "E / E2 priorities")
        #expect(log.answers.first == [size(12, 12), size(12, 12), size(.infinity, .infinity)], "E spacer answers")
    }
}

// MARK: - 1.8 single-child pass-through

/// A single-child linear stack or `ZStack` passes its child's priority through;
/// a two-child one and a custom layout read 0 (CN-D).
///
/// - G11 `{HStack{a 0..80 prio 1}; b 0..80}` at 100: the inner stack reads 1,
///   is offered 100 and answers 80; b 20. Before the lane it read 0: 50 / 50.
/// - G11c, the inner stack with a second, 0×0 child: 0, and 50 / 50.
/// - K2a `{a 20; ZStack{Spacer()}; b 20}` at 200: the `ZStack` reads −∞, so a
///   is offered (200 − 8) / 2 = 96, not 200 / 3 (priority half only).
/// - Contract probe L3 through a proxy: `HStack{p2}` 2, `VStack{p2}` 2,
///   `ZStack{p2}` 2, `HStack{p2; p0}` 0, a single-child custom layout 0.
///
/// Mutations: delete the pass-through (G11); pass through at any child count
/// (G11c).
@Test func aSingleChildStackPassesItsChildsPriorityThrough() {
    do { // G11
        let arm = Arm()
        let inner = arm.hstack("inner", [arm.priority(arm.flexW("a", 0, 80, 80), 1)])
        let root = arm.hstack("s", [inner, arm.flexW("b", 0, 80, 80)])
        #expect(arm.run(root, 100, 50) == size(100, 20), "G11 size")
        #expect(arm["a"] == rect(0, 0, 80, 20), "G11 a")
        #expect(arm["b"] == rect(80, 0, 20, 20), "G11 b")
    }
    do { // G11c
        let arm = Arm()
        let inner = arm.hstack("inner", [arm.priority(arm.flexW("a", 0, 80, 80), 1), arm.fixed("c", 0, 0)])
        let root = arm.hstack("s", [inner, arm.flexW("b", 0, 80, 80)])
        #expect(arm.run(root, 100, 50) == size(100, 20), "G11c size")
        #expect(arm["a"] == rect(0, 0, 50, 20), "G11c a")
        #expect(arm["c"] == rect(50, 10, 0, 0), "G11c c")
        #expect(arm["b"] == rect(50, 0, 50, 20), "G11c b")
    }
    do { // K2a
        let arm = Arm()
        let zstack = arm.tree.newNativeOverlay(children: [arm.spacer("sp")])
        let root = arm.hstack("s", [arm.fixed("a", 20, 20), zstack, arm.fixed("b", 20, 20)])
        #expect(arm.run(root, 200, 50).width == 200, "K2a width")
        #expect(arm.proposals("a").last == p(96, 50), "K2a a is offered (200 − 8) / 2")
        #expect(arm.x("b") == 180, "K2a b")
    }
    do { // L3
        let tree = LayoutTree(generation: 0)
        let log = ProxyLog()
        func p2() -> LayoutNodeID {
            tree.newNativeLayoutPriority(child: tree.newNativeLeaf { _ in LayoutMeasurement(size: SizeD(width: 1, height: 1)) },
                                         priority: 2)
        }
        let p0 = tree.newNativeLeaf { _ in LayoutMeasurement(size: SizeD(width: 1, height: 1)) }
        let root = tree.newNativeLayout(ProxyReader(log: log), children: [
            tree.newNativeLinearStack(children: [p2()], axis: .horizontal),
            tree.newNativeLinearStack(children: [p2()], axis: .vertical),
            tree.newNativeOverlay(children: [p2()]),
            tree.newNativeLinearStack(children: [p2(), p0], axis: .horizontal),
            tree.newNativeLayout(ProxyReader(log: ProxyLog()), children: [p2()]),
        ])
        tree.computeNativeLayout(root: root, proposal: ProposedSize(width: 100, height: 100),
                                 in: LayoutRect(x: 0, y: 0, width: 10, height: 10))
        #expect(log.priorities == [2, 2, 2, 0, 0], "L3 priorities")
    }
}

// MARK: - 1.9 the second pass

/// At a nil cross proposal a stack REPORTS its first-pass answers and PLACES
/// after re-running the distribution at its own cross size (CN-E).
///
/// - Q1 `VStack{a area 600 ideal 10; b 30×20}` at nil: reports 30×80 (a is
///   10×60 at nil), places a at 30×20 and b at y 20.
/// - Q1c, the same at 30×nil: 30×40, the same rects — the control that the
///   placement is Q1c's.
/// - X10 `HStack{a height 0..∞ ideal 10; b 20×30}` at nil: 40×30, a placed
///   20×30.
/// - X11 `VStack{a 0..∞ ideal 10 wide; b 30}` at nil×100: 30×40, a placed 30
///   wide.
/// - G17 `VStack{a 0..∞ ideal 10 wide; b fixed 30}` at nil: 30×40, a 30 wide.
/// - G21 `HStack{a height 0..∞ ideal 10; b 20×30}` at 100×nil: 40×30, a 20×30.
///
/// Mutation: place with the first-pass answers (Q1's a is 10 wide).
@Test func aStackPlacesAfterASecondPassAtItsOwnCrossSize() {
    do { // Q1
        let arm = Arm()
        let root = arm.vstack("s", [arm.area("a", 600, ideal: 10), arm.fixed("b", 30, 20)])
        #expect(arm.run(root, nil, nil) == size(30, 80), "Q1 size")
        #expect(arm["a"] == rect(0, 0, 30, 20), "Q1 a")
        #expect(arm["b"] == rect(0, 20, 30, 20), "Q1 b")
    }
    do { // Q1c
        let arm = Arm()
        let root = arm.vstack("s", [arm.area("a", 600, ideal: 10), arm.fixed("b", 30, 20)])
        #expect(arm.run(root, 30, nil) == size(30, 40), "Q1c size")
        #expect(arm["a"] == rect(0, 0, 30, 20), "Q1c a")
        #expect(arm["b"] == rect(0, 20, 30, 20), "Q1c b")
    }
    do { // X10
        let arm = Arm()
        let root = arm.hstack("s", [arm.flexH("a", 0, 10, .infinity), arm.fixed("b", 20, 30)])
        #expect(arm.run(root, nil, nil) == size(40, 30), "X10 size")
        #expect(arm["a"] == rect(0, 0, 20, 30), "X10 a")
        #expect(arm["b"] == rect(20, 0, 20, 30), "X10 b")
    }
    do { // X11
        let arm = Arm()
        let root = arm.vstack("s", [arm.flexW("a", 0, 10, .infinity), arm.fixed("b", 30, 20)])
        #expect(arm.run(root, nil, 100) == size(30, 40), "X11 size")
        #expect(arm["a"] == rect(0, 0, 30, 20), "X11 a")
        #expect(arm["b"] == rect(0, 20, 30, 20), "X11 b")
    }
    do { // G17
        let arm = Arm()
        let root = arm.vstack("s", [arm.flexW("a", 0, 10, .infinity), arm.fixed("b", 30, 20)])
        #expect(arm.run(root, nil, nil) == size(30, 40), "G17 size")
        #expect(arm["a"] == rect(0, 0, 30, 20), "G17 a")
        #expect(arm["b"] == rect(0, 20, 30, 20), "G17 b")
    }
    do { // G21
        let arm = Arm()
        let root = arm.hstack("s", [arm.flexH("a", 0, 10, .infinity), arm.fixed("b", 20, 30)])
        #expect(arm.run(root, 100, nil) == size(40, 30), "G21 size")
        #expect(arm["a"] == rect(0, 0, 20, 30), "G21 a")
        #expect(arm["b"] == rect(20, 0, 20, 30), "G21 b")
    }
}

// MARK: - 1.10 cross size at the allocations

/// The main axis is measured at the allocations, so the reported cross size
/// is the children's answers at their allocations (CN-B).
///
/// Q3 `HStack{a area 600 ideal 10; b 20×30}` at 100×50: b (flexibility 0) at
/// 50 → 20; a at 80 → 80×7.5. The stack is 100×30, not the 60 an unallocated
/// measurement (a at nil, 10×60) gives. a sits at y (30 − 7.5) / 2 = 11.25,
/// stored rounded: top 11, bottom round(18.75) = 19, so (0, 11, 80, 8).
///
/// Mutation: report the cross size from the flexibility probes' answers
/// (a at 0 is 1×600).
@Test func aStackMeasuresItsCrossSizeAtItsAllocations() {
    let arm = Arm()
    let root = arm.hstack("s", [arm.area("a", 600, ideal: 10), arm.fixed("b", 20, 30)])
    #expect(arm.run(root, 100, 50) == size(100, 30), "Q3 size")
    #expect(arm["a"] == rect(0, 11, 80, 8), "Q3 a")
    #expect(arm["b"] == rect(80, 0, 20, 30), "Q3 b")
}

// MARK: - 1.12 work

/// Level k (k ≥ 1) of the nested tree: a stack, spacing 4, over a flexible
/// leaf L_k, a fixed 20×20 leaf F_k, a spacer of minimum 8 and level k − 1;
/// level 0 is a flexible leaf L_0. Level 3 is horizontal, 2 vertical, 1
/// horizontal. Every flexible leaf answers `clamp(proposal ?? 10, 10, 80)` on
/// both axes.
private func nestedStacks(_ tree: LayoutTree) -> LayoutNodeID {
    func flexible() -> LayoutNodeID {
        tree.newNativeLeaf { proposal in
            LayoutMeasurement(size: SizeD(width: Swift.min(Swift.max(proposal.width ?? 10, 10), 80),
                                          height: Swift.min(Swift.max(proposal.height ?? 10, 10), 80)))
        }
    }
    func fixed() -> LayoutNodeID {
        tree.newNativeLeaf { _ in LayoutMeasurement(size: SizeD(width: 20, height: 20)) }
    }
    var level = flexible()
    for axis in [ProposalStackAxis.horizontal, .vertical, .horizontal] {
        level = tree.newNativeLinearStack(children: [flexible(), fixed(), tree.newNativeSpacer(minLength: 8), level],
                                          axis: axis, spacing: 4)
    }
    return level
}

/// Eager flexibility probing and the second pass cost a bounded, hand-derived
/// number of leaf calls on a nested tree (CN-B's measured cost; SA-M). Every
/// leaf closure runs once per distinct proposal per call, so "calls" is the
/// count of distinct (leaf, proposal) pairs. Derived by hand before the run;
/// the staged prototype read the same two numbers (CN-B's table, depth 3).
///
/// Notation: a stack at (W, H) offers its children (main, cross); "probes" are
/// a group's members at main ∞ and main 0; a spacer is never a call.
///
/// **Finite root**, level 3 (H) at 400×300 (cross finite, no second pass).
/// Group 0 {L3, F3, level 2} is offered 400 − 12 − 8 = 380 and probed at
/// (∞, 300), (0, 300); level 2's probes answer ∞ and 60 wide, so the order is
/// F3, L3, level 2: F3 at 126.67 → 20, L3 at 180 → 80, level 2 at 280.
/// - L3, F3: (∞, 300), (0, 300), their offer → **3 + 3**.
/// - Level 2 (V) is evaluated at (∞, 300), (0, 300), (280, 300). At each,
///   group {L2, F2, level 1} is offered 300 − 12 − 8 = 280, probed at (c, ∞)
///   and (c, 0) with c the cross, and served F2 at 93.33, L2 at 130, level 1
///   at 180. L2 and F2 each see 3 proposals per evaluation → **9 + 9**.
/// - Level 1 (H) is evaluated at (∞, ∞), (∞, 0), (∞, 180) — main ∞, no
///   probes, children at those — and at (0, ∞), (0, 0), (0, 180) — probes add
///   (∞, c) (already seen) and (0, c), every offer is 0 — and at (280, ∞),
///   (280, 0), (280, 180) — offers F1 86.67, L1 120, L0 160. So L1, L0 and F1
///   each see (∞, c), (0, c) and (offer, c) for c ∈ {∞, 0, 180} → **9 + 9 + 9**.
/// Placement re-asks the same keys. Total **51**.
///
/// **In a vertical scroll viewport** at 400×300: level 3 is measured at
/// (400, nil) and placed after a second pass at its measured height 70.
/// - Measurement: every leaf sees (∞, nil), (0, nil) and one offer (F3
///   126.67, L3 180; level 2 at (∞, nil), (0, nil), (280, nil) has main nil,
///   so L2 and F2 see those three; level 1's evaluations add (∞, nil), (0, nil)
///   and offers 86.67 / 120 / 160) → 7 × 3 = **21**.
/// - Placement at (400, 70): the finite-root derivation with cross 70 for
///   level 3 (L3, F3: 3 + 3), level 2 offered 70 − 20 = 50 → F2 at 16.67, L2
///   at 15, level 1 at 15 (L2, F2: 9 + 9), level 1 evaluated at c ∈ {∞, 0, 15}
///   (L1, L0, F1: 9 + 9 + 9) → **51**, none a nil key.
/// Total **72**.
///
/// Today (before the lane) each is 7: one call per leaf. Mutations: disable
/// the measurement cache; probe every group, including groups of one.
@Test func nestedStacksUnderAnUnspecifiedCrossProposalDoBoundedWork() {
    let finite = LayoutTree(generation: 0)
    let finiteRoot = nestedStacks(finite)
    finite.computeNativeLayout(root: finiteRoot, proposal: ProposedSize(width: 400, height: 300),
                               in: LayoutRect(x: 0, y: 0, width: 400, height: 300))
    #expect(finite.lastNativeLayoutWork.measureCalls == 51, "finite root")

    let scrolled = LayoutTree(generation: 0)
    let viewport = scrolled.newNativeScrollViewport(child: nestedStacks(scrolled), axis: .vertical)
    scrolled.computeNativeLayout(root: viewport, proposal: ProposedSize(width: 400, height: 300),
                                 in: LayoutRect(x: 0, y: 0, width: 400, height: 300))
    #expect(scrolled.lastNativeLayoutWork.measureCalls == 72, "inside a vertical scroll viewport")
}
