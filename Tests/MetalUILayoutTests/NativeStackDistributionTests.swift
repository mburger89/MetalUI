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
/// - **T7, pinned wrong on purpose** (`GR-O` item 8; moved here from the grids
///   track's test 2.11 by its lane 3, second critic round finding 9): when two
///   children's answers at main ∞ are **both infinite** their flexibilities tie,
///   and this stack serves them in declaration order. `VStack{z flexible;
///   b height ≥ 58}` at 200×100 gives z 46 and b 58, the stack 112 tall; SwiftUI
///   serves the one larger at main 0 first and reads z **34**, the stack 100
///   (probe `docs/probes/swiftui-grid-stack-ties.swift`). **No grid is
///   involved** — the grids track's GE10 and GE19 arms merely expose it — and
///   the owner is plan task 6, the stacks task.
///
/// Mutations: sort by flexibility descending (G1 a 60…); no sort (G1r's b
/// served first at 50 → 60 is the same, but G1's a is served at 50). T7's own:
/// break an infinite-flexibility tie by the answer at main 0, larger first (T7
/// then reads SwiftUI's z 34 and stack 100).
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
    do { // T7: an infinite-flexibility tie, at the stack's default spacing
        let arm = Arm()
        let z = arm.leaf("z", minW: 0, idealW: 10, maxW: .infinity, minH: 0, idealH: 10, maxH: .infinity)
        let b = arm.leaf("b", minW: 0, idealW: 10, maxW: .infinity, minH: 58, idealH: 10, maxH: .infinity)
        let root = arm.name(arm.tree.newNativeLinearStack(children: [z, b], axis: .vertical, spacing: nil), "s")
        #expect(arm.run(root, 200, 100) == size(200, 112), "T7 size (pinned wrong on purpose: SwiftUI 200×100)")
        #expect(arm["z"] == rect(0, 0, 200, 46), "T7 z (pinned wrong on purpose: SwiftUI 34)")
        #expect(arm["b"] == rect(0, 54, 200, 58), "T7 b")
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

// MARK: - Lane 2: spacer cross axis and minimum, infinite answers, aspect ratio

// Lane 2 of the same spec: the rest of CN-C (a nil minimum is 8; a spacer
// answers 0 on the cross axis of the linear stack that marks it, the mark
// reaching through `layoutPriority`, `padding`, `frame`, `fixedSize`,
// `aspectRatio` and both children of an overlay attachment), the rest of CN-F
// (a frame and a scroll viewport answer ∞ at ∞) and CN-G (`aspectRatio`
// answers its child's answer to the ratio-shaped proposal, ∞ a concrete axis).
// Spacers below use the nil default unless an arm names a minimum.

extension Arm {
    func defaultSpacer(_ name: String) -> LayoutNodeID {
        self.name(tree.newNativeSpacer(), name)
    }

    func frame(_ name: String, _ child: LayoutNodeID, width: Double? = nil,
               maxWidth: Double? = nil) -> LayoutNodeID {
        self.name(tree.newNativeFrame(child: child, width: width, maxWidth: maxWidth), name)
    }

    func padding(_ name: String, _ child: LayoutNodeID, _ inset: Double) -> LayoutNodeID {
        self.name(tree.newNativePadding(child: child,
                                        insets: Edges(top: inset, right: inset, bottom: inset, left: inset)), name)
    }

    func fixedSize(_ name: String, _ child: LayoutNodeID) -> LayoutNodeID {
        self.name(tree.newNativeFixedSize(child: child), name)
    }

    func aspectRatio(_ name: String, _ child: LayoutNodeID, _ ratio: Double,
                     _ mode: AspectRatioContentMode = .fit) -> LayoutNodeID {
        self.name(tree.newNativeAspectRatio(child: child, ratio: ratio, contentMode: mode), name)
    }

    func overlay(_ name: String, _ primary: LayoutNodeID, _ content: LayoutNodeID) -> LayoutNodeID {
        self.name(tree.newNativeOverlayAttachment(child: primary, overlay: content), name)
    }

    func zstack(_ name: String, _ children: [LayoutNodeID]) -> LayoutNodeID {
        self.name(tree.newNativeOverlay(children: children), name)
    }

    /// The probe's `Leaf(minW: 0, idealW: 10, maxW: .infinity, …)` on both axes.
    func flexible(_ name: String) -> LayoutNodeID {
        leaf(name, minW: 0, idealW: 10, maxW: .infinity, minH: 0, idealH: 10, maxH: .infinity)
    }
}

// MARK: 2.1 default minimum and cross axis

/// CN-C: `Spacer()`'s nil minimum is 8, and inside a linear stack a spacer
/// answers 0 on that stack's cross axis; outside one it is flexible on both.
///
/// - SP1 `HStack(0){a20; Spacer(); b20}` at nil: 48×20, b at 28. SP6 the
///   same vertically: 20×48, b at y 28. K1: `VStack{text; Spacer(); text}` is
///   40 (two 16pt leaves stand in for the texts, spacing 0 as K1c).
/// - SPB1 `HStack(0){Spacer()}` at 100×50: 100×0; SPB2 at nil: 8×0; SPB5
///   `VStack(0){Spacer()}` at 100×50: 0×50.
/// - SP13 `HStack(0){Spacer(); a}` at 100×50: 100×20 (not 50), a offered 92
///   at x 80; SP14 vertically: 20×50, a offered 100×42 at y 30.
/// - SP18b `HStack(0){VStack{Spacer()}; a20}` at 100×50: 20×50 — the inner
///   stack's mark stands, so the VStack is 0 wide and 50 tall; a at y 15.
///   SP21 `VStack(0){HStack(0){Spacer()}; a20}`: 100×20, a at x 40.
/// - SP22 `HStack(0){a20; Spacer()}` at 100×nil: 100×20, a offered 92×nil
///   then placed at 92×20.
/// - SPB3/SPB4, outside a stack: `Spacer()` at 100×50 answers 100×50, at nil
///   8×8.
///
/// Before the lane: the default is 0 (SP1 40) and a spacer claims its cross
/// proposal (SP13 100×50). Mutations: nil → 0 in `newNativeSpacer`; delete the
/// marking.
@Test func aSpacerDefaultsToEightAndAnswersZeroOnItsStacksCrossAxis() {
    do { // SP1
        let arm = Arm()
        let root = arm.hstack("s", [arm.fixed("a", 20, 20), arm.defaultSpacer("sp"), arm.fixed("b", 20, 20)])
        #expect(arm.run(root, nil, nil) == size(48, 20), "SP1 size")
        #expect(arm["b"] == rect(28, 0, 20, 20), "SP1 b")
    }
    do { // SP6
        let arm = Arm()
        let root = arm.vstack("s", [arm.fixed("a", 20, 20), arm.defaultSpacer("sp"), arm.fixed("b", 20, 20)])
        #expect(arm.run(root, nil, nil) == size(20, 48), "SP6 size")
        #expect(arm["b"] == rect(0, 28, 20, 20), "SP6 b")
    }
    do { // K1
        let arm = Arm()
        let root = arm.vstack("s", [arm.fixed("a", 13, 16), arm.defaultSpacer("sp"), arm.fixed("b", 13, 16)])
        #expect(arm.run(root, nil, nil) == size(13, 40), "K1 size")
    }
    do { // SPB1, SPB2
        let arm = Arm()
        let root = arm.hstack("s", [arm.defaultSpacer("sp")])
        #expect(arm.measure(root, 100, 50) == size(100, 0), "SPB1")
        #expect(arm.measure(root, nil, nil) == size(8, 0), "SPB2")
    }
    do { // SPB5
        let arm = Arm()
        let root = arm.vstack("s", [arm.defaultSpacer("sp")])
        #expect(arm.measure(root, 100, 50) == size(0, 50), "SPB5")
    }
    do { // SP13
        let arm = Arm()
        let root = arm.hstack("s", [arm.defaultSpacer("sp"), arm.fixed("a", 20, 20)])
        #expect(arm.run(root, 100, 50) == size(100, 20), "SP13 size")
        #expect(arm.proposals("a") == [p(92, 50)], "SP13 a")
        #expect(arm["a"] == rect(80, 0, 20, 20), "SP13 a rect")
    }
    do { // SP14
        let arm = Arm()
        let root = arm.vstack("s", [arm.defaultSpacer("sp"), arm.fixed("a", 20, 20)])
        #expect(arm.run(root, 100, 50) == size(20, 50), "SP14 size")
        #expect(arm.proposals("a") == [p(100, 42)], "SP14 a")
        #expect(arm["a"] == rect(0, 30, 20, 20), "SP14 a rect")
    }
    do { // SP18b
        let arm = Arm()
        let inner = arm.vstack("v", [arm.defaultSpacer("sp")])
        let root = arm.hstack("s", [inner, arm.fixed("a", 20, 20)])
        #expect(arm.run(root, 100, 50) == size(20, 50), "SP18b size")
        #expect(arm.proposals("a") == [p(100, 50)], "SP18b a")
        #expect(arm["a"] == rect(0, 15, 20, 20), "SP18b a rect")
    }
    do { // SP21
        let arm = Arm()
        let inner = arm.hstack("h", [arm.defaultSpacer("sp")])
        let root = arm.vstack("s", [inner, arm.fixed("a", 20, 20)])
        #expect(arm.run(root, 100, 50) == size(100, 20), "SP21 size")
        #expect(arm.proposals("a") == [p(100, 50)], "SP21 a")
        #expect(arm["a"] == rect(40, 0, 20, 20), "SP21 a rect")
    }
    do { // SP22
        let arm = Arm()
        let root = arm.hstack("s", [arm.fixed("a", 20, 20), arm.defaultSpacer("sp")])
        #expect(arm.run(root, 100, nil) == size(100, 20), "SP22 size")
        #expect(arm.proposals("a") == [p(92, nil), p(92, 20)], "SP22 a")
        #expect(arm["a"] == rect(0, 0, 20, 20), "SP22 a rect")
    }
    do { // SPB3, SPB4
        let arm = Arm()
        let spacer = arm.defaultSpacer("sp")
        #expect(arm.measure(spacer, 100, 50) == size(100, 50), "SPB3")
        #expect(arm.measure(spacer, nil, nil) == size(8, 8), "SPB4")
    }
}

// MARK: 2.2 the marking walk

/// CN-C's walk: `newNativeLinearStack` marks a spacer reached through
/// `layoutPriority`, `padding`, `frame`, `fixedSize`, `aspectRatio` and both
/// children of an overlay attachment; it stops at anything else.
///
/// - K2b `HStack(0){a20; Spacer().aspectRatio(1, .fit); b20}` at 200×50:
///   90×20, b offered 90 last and placed at 70 (the spacer is 50×0).
/// - K2c `Spacer().fixedSize()`: 48×20, b at 28. K2c does NOT show the mark
///   (the siblings set the height either way); probe revision 6 does: K2g
///   `HStack(0){Spacer().fixedSize()}` at nil is 8×0 (its ZStack control K2f
///   is 8×8), and K2i `{a20; Spacer(minLength: 30).fixedSize(); b20}` at nil
///   is 70×20 (its ZStack control K2j is 70×30).
/// - K2d `Spacer().frame(maxWidth: .infinity)`: 200×20, b at 180.
/// - K2e `{a20; p 10×10 .overlay{Spacer()}; b20}`: 50×20, the overlay-side
///   spacer 10×0 on p's 10×10 (its background reads (25, 10), its centre).
/// - SP19 `Spacer().frame(width: 10)`: 50×20, b at 30. SP20
///   `Spacer().padding(5)`: 200×20, b at 180.
/// - X8 `HStack(0){Spacer().overlay{o 20x20}; a20}`: 200×20, o offered
///   180×0 and placed at (80, 0); a offered 192 at 180.
/// - Stops: K2a `{a20; ZStack{Spacer()}; b20}` is 200×50 with a and b at y 15
///   (the ZStack's spacer is unmarked and claims 50); SP18b is 2.1's.
///
/// Before the lane K2b's stack is 50 tall. Mutations: stop the walk at `frame`
/// (K2d, SP19 move); skip the overlay's content side (K2e moves); walk into an
/// `overlay` node (K2a moves); stop the walk at `fixedSize` (K2g, K2i move;
/// K2c does not).
@Test func theCrossAxisMarkReachesASpacerThroughEveryWrapperButAStack() {
    do { // K2b
        let arm = Arm()
        let root = arm.hstack("s", [arm.fixed("a", 20, 20),
                                    arm.aspectRatio("ar", arm.defaultSpacer("sp"), 1),
                                    arm.fixed("b", 20, 20)])
        #expect(arm.run(root, 200, 50) == size(90, 20), "K2b size")
        #expect(arm.proposals("a").last == p(200.0 / 3, 50), "K2b a")
        #expect(arm.proposals("b").last == p(90, 50), "K2b b")
        #expect(arm["b"] == rect(70, 0, 20, 20), "K2b b rect")
    }
    do { // K2c
        let arm = Arm()
        let root = arm.hstack("s", [arm.fixed("a", 20, 20),
                                    arm.fixedSize("fs", arm.defaultSpacer("sp")),
                                    arm.fixed("b", 20, 20)])
        #expect(arm.run(root, 200, 50) == size(48, 20), "K2c size")
        #expect(arm.proposals("b").last == p(172, 50), "K2c b")
        #expect(arm["b"] == rect(28, 0, 20, 20), "K2c b rect")
    }
    do { // K2g: a lone fixed-size spacer answers 0 on the stack's cross axis
        let arm = Arm()
        let root = arm.hstack("s", [arm.fixedSize("fs", arm.defaultSpacer("sp"))])
        #expect(arm.measure(root, nil, nil) == size(8, 0), "K2g size")
    }
    do { // K2i: a 30pt fixed-size spacer does not set the stack's height
        let arm = Arm()
        let root = arm.hstack("s", [arm.fixed("a", 20, 20),
                                    arm.fixedSize("fs", arm.spacer("sp", minLength: 30)),
                                    arm.fixed("b", 20, 20)])
        #expect(arm.run(root, nil, nil) == size(70, 20), "K2i size")
        #expect(arm["b"] == rect(50, 0, 20, 20), "K2i b rect")
    }
    do { // K2d
        let arm = Arm()
        let root = arm.hstack("s", [arm.fixed("a", 20, 20),
                                    arm.frame("f", arm.defaultSpacer("sp"), maxWidth: .infinity),
                                    arm.fixed("b", 20, 20)])
        #expect(arm.run(root, 200, 50) == size(200, 20), "K2d size")
        #expect(arm["b"] == rect(180, 0, 20, 20), "K2d b rect")
    }
    do { // K2e
        let arm = Arm()
        let root = arm.hstack("s", [arm.fixed("a", 20, 20),
                                    arm.overlay("ov", arm.fixed("p", 10, 10), arm.defaultSpacer("sp")),
                                    arm.fixed("b", 20, 20)])
        #expect(arm.run(root, 200, 50) == size(50, 20), "K2e size")
        #expect(arm["p"] == rect(20, 5, 10, 10), "K2e p")
        #expect(arm["sp"] == rect(20, 10, 10, 0), "K2e overlay-side spacer")
        #expect(arm["b"] == rect(30, 0, 20, 20), "K2e b rect")
    }
    do { // SP19
        let arm = Arm()
        let root = arm.hstack("s", [arm.fixed("a", 20, 20),
                                    arm.frame("f", arm.defaultSpacer("sp"), width: 10),
                                    arm.fixed("b", 20, 20)])
        #expect(arm.run(root, 200, 50) == size(50, 20), "SP19 size")
        #expect(arm["b"] == rect(30, 0, 20, 20), "SP19 b rect")
    }
    do { // SP20
        let arm = Arm()
        let root = arm.hstack("s", [arm.fixed("a", 20, 20),
                                    arm.padding("pad", arm.defaultSpacer("sp"), 5),
                                    arm.fixed("b", 20, 20)])
        #expect(arm.run(root, 200, 50) == size(200, 20), "SP20 size")
        #expect(arm.proposals("b").last == p(90, 50), "SP20 b")
        #expect(arm["b"] == rect(180, 0, 20, 20), "SP20 b rect")
    }
    do { // X8
        let arm = Arm()
        let root = arm.hstack("s", [arm.overlay("ov", arm.defaultSpacer("sp"), arm.fixed("o", 20, 20)),
                                    arm.fixed("a", 20, 20)])
        #expect(arm.run(root, 200, 50) == size(200, 20), "X8 size")
        #expect(arm.proposals("a").last == p(192, 50), "X8 a")
        #expect(arm.proposals("o").last == p(180, 0), "X8 o")
        #expect(arm["o"] == rect(80, 0, 20, 20), "X8 o rect")
        #expect(arm["a"] == rect(180, 0, 20, 20), "X8 a rect")
    }
    do { // K2a: the walk stops at a ZStack
        let arm = Arm()
        let root = arm.hstack("s", [arm.fixed("a", 20, 20),
                                    arm.zstack("z", [arm.defaultSpacer("sp")]),
                                    arm.fixed("b", 20, 20)])
        #expect(arm.run(root, 200, 50) == size(200, 50), "K2a size")
        #expect(arm.proposals("a").last == p(96, 50), "K2a a")
        #expect(arm["a"] == rect(0, 15, 20, 20), "K2a a rect")
        #expect(arm["b"] == rect(180, 15, 20, 20), "K2a b rect")
    }
}

// MARK: 2.3 infinite answers

/// CN-F, reversing FR-B: a frame with a maximum and a scroll viewport answer
/// ∞ at an ∞ proposal, so a greedy frame over a fixed child reports its
/// flexibility to a stack.
///
/// - D12 (`swiftui-frame-semantics.swift`) `.frame(maxWidth: .infinity)` over
///   a 20pt child at ∞×∞: inf×20.
/// - SC1 at ∞×∞, a `ScrollView` of a flexible ideal-50×300 child: inf×inf on
///   the vertical and on the horizontal axis.
/// - G4 `HStack(0){a fixed 20; b fixed 20 .frame(maxWidth: .infinity)}` at
///   200×50: the frame takes 180, b at 100. Revision 5: G4r, the frame
///   declared first, still takes 180 (b at 80, a at 180); G4f, beside a
///   bounded 0..80 sibling, is served after it (a 80 at 120, b at 50).
///
/// Before the lane the frame answers its child at ∞ (FR-B): D12 reads 20, and
/// G4r's frame is served first at 100. Mutations: restore `isFinite` in
/// `framedSize` (D12, G4r, G4f move); restore it in
/// `resolvedViewportDimension` (SC1 moves).
@Test func anInfiniteProposalIsAnsweredWithInfinity() {
    do { // D12
        let arm = Arm()
        let root = arm.frame("f", arm.fixed("c", 20, 20), maxWidth: .infinity)
        #expect(arm.measure(root, .infinity, .infinity) == size(.infinity, 20), "D12")
    }
    do { // SC1, vertical and horizontal
        for axis in [ProposalStackAxis.vertical, .horizontal] {
            let arm = Arm()
            let content = arm.leaf("c", minW: 0, idealW: 50, maxW: .infinity, minH: 0, idealH: 300, maxH: .infinity)
            let viewport = arm.tree.newNativeScrollViewport(child: content, axis: axis)
            #expect(arm.measure(viewport, .infinity, .infinity) == size(.infinity, .infinity), "SC1 \(axis)")
        }
    }
    do { // G4
        let arm = Arm()
        let root = arm.hstack("s", [arm.fixed("a", 20, 20),
                                    arm.frame("f", arm.fixed("b", 20, 20), maxWidth: .infinity)])
        #expect(arm.run(root, 200, 50) == size(200, 20), "G4 size")
        #expect(arm["f"] == rect(20, 0, 180, 20), "G4 frame")
        #expect(arm["b"] == rect(100, 0, 20, 20), "G4 b")
    }
    do { // G4r
        let arm = Arm()
        let root = arm.hstack("s", [arm.frame("f", arm.fixed("b", 20, 20), maxWidth: .infinity),
                                    arm.fixed("a", 20, 20)])
        #expect(arm.run(root, 200, 50) == size(200, 20), "G4r size")
        #expect(arm["b"] == rect(80, 0, 20, 20), "G4r b")
        #expect(arm["a"] == rect(180, 0, 20, 20), "G4r a")
        #expect(arm.proposals("a").last == p(100, 50), "G4r a is served first")
    }
    do { // G4f
        let arm = Arm()
        let root = arm.hstack("s", [arm.frame("f", arm.fixed("b", 20, 20), maxWidth: .infinity),
                                    arm.flexW("a", 0, 80, 80)])
        #expect(arm.run(root, 200, 50) == size(200, 20), "G4f size")
        #expect(arm["b"] == rect(50, 0, 20, 20), "G4f b")
        #expect(arm["a"] == rect(120, 0, 80, 20), "G4f a")
    }
}

// MARK: 2.5 aspect ratio answers its child

/// CN-G: `aspectRatio` proposes the ratio-shaped size and answers its child's
/// answer to it.
///
/// - AR1 fixed 168×95 `.aspectRatio(16/9, .fit)` at 500×300: proposes
///   500×281.25, answers 168×95. AR2 at nil: proposes nil×nil, 168×95. AR3 a
///   child that takes the offer: 500×281.25.
/// - AR4 `HStack(12){a 168×64; that; b 168×64}` at 856×300: 528×95; the
///   child is asked 533.33×300, 0×0 and 332×186.75, and sits at x 180; b at
///   360.
/// - K4 500×nil proposes 500×281.25 (168×95); K4b nil×300 proposes
///   533.33×300 (168×95); K4c a flexible child at 500×nil answers 500×281.25.
/// - K4i/K4j ratio −1 at 100×100 proposes 100×−100: a clamping child answers
///   100×0, a fixed 30×30 one 30×30.
///
/// Before the lane AR1 answers 500×281.25. Mutation: answer the ratio size.
@Test func anAspectRatioAnswersItsChildsAnswerToTheRatioProposal() {
    let ratio = 16.0 / 9.0
    do { // AR1
        let arm = Arm()
        let root = arm.aspectRatio("ar", arm.fixed("c", 168, 95), ratio)
        #expect(arm.run(root, 500, 300) == size(168, 95), "AR1 size")
        #expect(arm.proposals("c") == [p(500, 500 / ratio)], "AR1 c")
        #expect(arm["c"] == rect(0, 0, 168, 95), "AR1 c rect")
    }
    do { // AR2
        let arm = Arm()
        let root = arm.aspectRatio("ar", arm.fixed("c", 168, 95), ratio)
        #expect(arm.run(root, nil, nil) == size(168, 95), "AR2 size")
        #expect(arm.proposals("c") == [p(nil, nil)], "AR2 c")
    }
    do { // AR3
        let arm = Arm()
        let root = arm.aspectRatio("ar", arm.flexible("c"), ratio)
        #expect(arm.measure(root, 500, 300) == size(500, 500 / ratio), "AR3 size")
    }
    do { // AR4
        let arm = Arm()
        let root = arm.hstack("s", spacing: 12, [arm.fixed("a", 168, 64),
                                                 arm.aspectRatio("ar", arm.fixed("c", 168, 95), ratio),
                                                 arm.fixed("b", 168, 64)])
        #expect(arm.run(root, 856, 300) == size(528, 95), "AR4 size")
        #expect(arm.proposals("c") == [p(300 * ratio, 300), p(0, 0), p(332, 332 / ratio)], "AR4 c")
        #expect(arm["c"] == rect(180, 0, 168, 95), "AR4 c rect")
        #expect(arm.x("b") == 360, "AR4 b")
    }
    do { // K4, K4b
        let arm = Arm()
        let root = arm.aspectRatio("ar", arm.fixed("c", 168, 95), ratio)
        #expect(arm.measure(root, 500, nil) == size(168, 95), "K4 size")
        #expect(arm.measure(root, nil, 300) == size(168, 95), "K4b size")
        #expect(arm.proposals("c") == [p(500, 500 / ratio), p(300 * ratio, 300)], "K4, K4b c")
    }
    do { // K4c
        let arm = Arm()
        let root = arm.aspectRatio("ar", arm.flexible("c"), ratio)
        #expect(arm.measure(root, 500, nil) == size(500, 500 / ratio), "K4c size")
    }
    do { // K4i, K4j
        let flexible = Arm()
        let k4i = flexible.aspectRatio("ar", flexible.flexible("c"), -1)
        #expect(flexible.run(k4i, 100, 100) == size(100, 0), "K4i size")
        #expect(flexible.proposals("c") == [p(100, -100)], "K4i c")
        let fixed = Arm()
        let k4j = fixed.aspectRatio("ar", fixed.fixed("c", 30, 30), -1)
        #expect(fixed.run(k4j, 100, 100) == size(30, 30), "K4j size")
        #expect(fixed.proposals("c") == [p(100, -100)], "K4j c")
    }
}

// MARK: 2.6 infinity is a concrete axis

/// CN-G: ∞ is a concrete proposal axis to `aspectRatio`, not nil — the
/// two-axis `width / ratio <= height` (`>=` for `.fill`) comparison with ∞ in
/// it. Measured only, as the probe's `runMeasured` arms are (placing an
/// infinite answer traps in both).
///
/// - K4d fixed 168×95 `.fit` at ∞×∞: proposes ∞×∞, answers 168×95.
/// - K4e fixed at 500×∞: proposes 500×281.25. K4g a flexible child there:
///   500×281.25.
/// - K4f a flexible child at ∞×∞: proposes and answers ∞×∞.
/// - K4h fixed `.fill` at 500×∞: proposes ∞×∞, answers 168×95.
///
/// Before the lane K4d proposes the intrinsic-shaped size. Mutation: filter ∞
/// to nil in the ratio proposal.
@Test func anAspectRatioTreatsInfinityAsAConcreteAxis() {
    let ratio = 16.0 / 9.0
    do { // K4d
        let arm = Arm()
        let root = arm.aspectRatio("ar", arm.fixed("c", 168, 95), ratio)
        #expect(arm.measure(root, .infinity, .infinity) == size(168, 95), "K4d size")
        #expect(arm.proposals("c") == [p(.infinity, .infinity)], "K4d c")
    }
    do { // K4e
        let arm = Arm()
        let root = arm.aspectRatio("ar", arm.fixed("c", 168, 95), ratio)
        #expect(arm.measure(root, 500, .infinity) == size(168, 95), "K4e size")
        #expect(arm.proposals("c") == [p(500, 500 / ratio)], "K4e c")
    }
    do { // K4f
        let arm = Arm()
        let root = arm.aspectRatio("ar", arm.flexible("c"), ratio)
        #expect(arm.measure(root, .infinity, .infinity) == size(.infinity, .infinity), "K4f size")
        #expect(arm.proposals("c") == [p(.infinity, .infinity)], "K4f c")
    }
    do { // K4g
        let arm = Arm()
        let root = arm.aspectRatio("ar", arm.flexible("c"), ratio)
        #expect(arm.measure(root, 500, .infinity) == size(500, 500 / ratio), "K4g size")
        #expect(arm.proposals("c") == [p(500, 500 / ratio)], "K4g c")
    }
    do { // K4h
        let arm = Arm()
        let root = arm.aspectRatio("ar", arm.fixed("c", 168, 95), ratio, .fill)
        #expect(arm.measure(root, 500, .infinity) == size(168, 95), "K4h size")
        #expect(arm.proposals("c") == [p(.infinity, .infinity)], "K4h c")
    }
}

// MARK: - Lane 3: default spacing beside a spacer (CN-H)

// Lane 3 of the same spec: CN-H. A stack registered with `spacing: nil` puts
// `ProposalSpacing.platformDefault` (8) between each adjacent pair unless the
// earlier child's trailing edge or the later child's leading edge is a
// zero-spacing edge. Spacers below are `minLength: 0`, as the probe's K3 arms
// are, so the only thing between `a` and `b` is the spacing.

extension Arm {
    /// A default-spacing stack: the element API's `HStack { … }`.
    func defaultHStack(_ name: String, _ children: [LayoutNodeID]) -> LayoutNodeID {
        self.name(tree.newNativeLinearStack(children: children, axis: .horizontal, spacing: nil), name)
    }

    func defaultVStack(_ name: String, _ children: [LayoutNodeID]) -> LayoutNodeID {
        self.name(tree.newNativeLinearStack(children: children, axis: .vertical, spacing: nil), name)
    }

    /// `.padding` with one inset per edge.
    func padding(_ name: String, _ child: LayoutNodeID, top: Double = 0, right: Double = 0,
                 bottom: Double = 0, left: Double = 0) -> LayoutNodeID {
        self.name(tree.newNativePadding(child: child,
                                        insets: Edges(top: top, right: right, bottom: bottom, left: left)), name)
    }
}

// MARK: 3.2 the per-edge walk

/// CN-H's walk, arm by arm against the probe's K3 group (every arm at nil×nil,
/// `a` and `b` fixed 20×20, a `Spacer(minLength: 0)` between them, default
/// spacing). A node's zero-spacing edges along the stack's axis: both for a
/// spacer; the child's through `padding` only where that edge's inset is 0, and
/// through `frame`, `fixedSize`, `aspectRatio`, `layoutPriority` and an overlay
/// attachment's PRIMARY; the AND of every child's for a `ZStack`; none for
/// anything else.
///
/// - K3 control `{a; b}`: 48×20, b at 28.
/// - Zero spacing survives: K3a `.padding(0)`, K3b `.frame(width: 0)`, K3c
///   `.overlay{c 0×0}` (c at (20, 10)), K3d `.layoutPriority(1)`, K3e
///   `.fixedSize()`, K3g `ZStack{spacer}`, K3l `ZStack{spacer; spacer}`, K3o
///   `.padding(.top, 4)` (a cross-axis edge): each 40×20, b at 20. K3f
///   `.aspectRatio(1, .fit)` reports 40×20; SwiftUI places b at 40 there
///   (the spacer is proposed a width at the placement pass), so only its size
///   is pinned. K3q `.frame(width: 10).padding(0)`: 50×20, b at 30.
/// - Default spacing: K3h `VStack{spacer}` (a nested stack), K3i `c 0×0
///   .overlay{spacer}` (the spacer on the content side; c at (28, 10)), K3j
///   `ZStack{spacer; c}` and K3k `ZStack{c; spacer}`: each 56×20, b at 36.
///   K3m `.padding(4)`: 64×20 (20+8+8+8+20), b at 44. K3n `.padding(.leading,
///   4)`: 52×20 (20+8+4+0+20), b at 32, and the padding wrapper at (28, 10)
///   4×0 (probe revision 8's V6: its background reads that rect); V6c
///   `.padding(.trailing, 4)`: 52×20, the wrapper at (20, 10). K3p vertically,
///   `.padding(.top, 4)`: 20×52, b at y 32.
///
/// Before the lane every default gap is an explicit 8: K3a reads 56.
/// Mutations: read `isNativeSpacer` instead of the walk (K3a, K3b, K3c, K3e,
/// K3f, K3g move); treat padding as transparent whatever its inset (K3m, K3n
/// move); walk into an overlay's content (K3i moves); OR instead of AND over a
/// `ZStack`'s children (K3j moves); swap padding's leading and trailing insets
/// (V6 and V6c exchange rects, sizes and b unmoved).
@Test func defaultSpacingBesideASpacerIsDecidedPerEdgeThroughItsWrappers() {
    typealias Wrap = (Arm, LayoutNodeID) -> LayoutNodeID
    /// `defaultHStack{a; wrap(spacer); b}` at nil×nil: its size and b's rect.
    func wrapped(_ wrap: Wrap) -> (Arm, SizeD) {
        let arm = Arm()
        let a = arm.fixed("a", 20, 20)
        let middle = wrap(arm, arm.spacer("sp", minLength: 0))
        let root = arm.defaultHStack("s", [a, middle, arm.fixed("b", 20, 20)])
        return (arm, arm.run(root, nil, nil))
    }
    do { // K3 control
        let arm = Arm()
        let root = arm.defaultHStack("s", [arm.fixed("a", 20, 20), arm.fixed("b", 20, 20)])
        #expect(arm.run(root, nil, nil) == size(48, 20), "K3 control size")
        #expect(arm["b"] == rect(28, 0, 20, 20), "K3 control b")
    }
    let zero: [(String, Wrap)] = [
        ("K3a", { $0.padding("w", $1, 0) }),
        ("K3b", { $0.frame("w", $1, width: 0) }),
        ("K3d", { $0.priority($1, 1) }),
        ("K3e", { $0.fixedSize("w", $1) }),
        ("K3g", { $0.zstack("w", [$1]) }),
        ("K3l", { arm, spacer in arm.zstack("w", [spacer, arm.spacer("sp2", minLength: 0)]) }),
        ("K3o", { $0.padding("w", $1, top: 4) }),
    ]
    for (label, wrap) in zero {
        let (arm, answer) = wrapped(wrap)
        #expect(answer == size(40, 20), "\(label) size")
        #expect(arm["b"] == rect(20, 0, 20, 20), "\(label) b")
    }
    do { // K3c
        let (arm, answer) = wrapped { arm, spacer in arm.overlay("w", spacer, arm.fixed("c", 0, 0)) }
        #expect(answer == size(40, 20), "K3c size")
        #expect(arm["c"] == rect(20, 10, 0, 0), "K3c c")
        #expect(arm["b"] == rect(20, 0, 20, 20), "K3c b")
    }
    do { // K3f
        let (_, answer) = wrapped { $0.aspectRatio("w", $1, 1) }
        #expect(answer == size(40, 20), "K3f size")
    }
    do { // K3q
        let (arm, answer) = wrapped { arm, spacer in arm.padding("p", arm.frame("w", spacer, width: 10), 0) }
        #expect(answer == size(50, 20), "K3q size")
        #expect(arm["b"] == rect(30, 0, 20, 20), "K3q b")
    }
    let eight: [(String, Wrap)] = [
        ("K3h", { $0.defaultVStack("w", [$1]) }),
        ("K3j", { arm, spacer in arm.zstack("w", [spacer, arm.fixed("c", 0, 0)]) }),
        ("K3k", { arm, spacer in arm.zstack("w", [arm.fixed("c", 0, 0), spacer]) }),
    ]
    for (label, wrap) in eight {
        let (arm, answer) = wrapped(wrap)
        #expect(answer == size(56, 20), "\(label) size")
        #expect(arm["b"] == rect(36, 0, 20, 20), "\(label) b")
    }
    do { // K3i
        let (arm, answer) = wrapped { arm, spacer in arm.overlay("w", arm.fixed("c", 0, 0), spacer) }
        #expect(answer == size(56, 20), "K3i size")
        #expect(arm["c"] == rect(28, 10, 0, 0), "K3i c")
        #expect(arm["b"] == rect(36, 0, 20, 20), "K3i b")
    }
    do { // K3m
        let (arm, answer) = wrapped { $0.padding("w", $1, 4) }
        #expect(answer == size(64, 20), "K3m size")
        #expect(arm["b"] == rect(44, 0, 20, 20), "K3m b")
    }
    do { // K3n, and V6 (probe revision 8): the padded spacer sits at x 28
        let (arm, answer) = wrapped { $0.padding("w", $1, left: 4) }
        #expect(answer == size(52, 20), "K3n size")
        #expect(arm["b"] == rect(32, 0, 20, 20), "K3n b")
        #expect(arm["w"] == rect(28, 10, 4, 0), "V6 the leading-padded spacer")
    }
    do { // V6c: the trailing-padded spacer sits at x 20, and must disagree with V6
        let (arm, answer) = wrapped { $0.padding("w", $1, right: 4) }
        #expect(answer == size(52, 20), "V6c size")
        #expect(arm["w"] == rect(20, 10, 4, 0), "V6c the trailing-padded spacer")
        #expect(arm["b"] == rect(32, 0, 20, 20), "V6c b")
    }
    do { // K3p
        let arm = Arm()
        let root = arm.defaultVStack("s", [arm.fixed("a", 20, 20),
                                           arm.padding("w", arm.spacer("sp", minLength: 0), top: 4),
                                           arm.fixed("b", 20, 20)])
        #expect(arm.run(root, nil, nil) == size(20, 52), "K3p size")
        #expect(arm["b"] == rect(0, 32, 20, 20), "K3p b")
    }
}

// MARK: 3.6 nested stacks, custom layouts, empty containers

/// A custom layout that overrides nothing about spacing: the probe's `Pass`,
/// answering the largest child answer per axis and placing every child at its
/// origin.
private struct Pass: ProposalLayout {
    func sizeThatFits(proposal: ProposedSize, subviews: MeasurementSubviews) -> LayoutMeasurement {
        LayoutMeasurement(size: subviews.reduce(SizeD(width: 0, height: 0)) { size, subview in
            let answer = subview.sizeThatFits(proposal).size
            return SizeD(width: Swift.max(size.width, answer.width), height: Swift.max(size.height, answer.height))
        })
    }

    func placeSubviews(in bounds: LayoutRect, proposal: ProposedSize, subviews: PlacementSubviews) {
        for subview in subviews {
            subview.place(at: Point(x: bounds.x, y: bounds.y), anchor: .topLeading, proposal: proposal)
        }
    }
}

/// CN-H as amended (probe revisions 8 and 10, the V group; every arm at nil×nil
/// between `a` and `b` fixed 20×20 in a default-spacing `HStack`, `sp` a
/// `Spacer(minLength: 0)`, `c`/`d` fixed 0×0). Controls: K3 (48, test 3.2) and
/// the non-spacer arms V1j, V3c, V3g, V4c (56), which must disagree with the
/// zero arms (40).
///
/// - A spacer is a zero edge only along the axis of the stack that orients it,
///   or both ways when none does: V1d `VStack{sp; c}` and V1h `VStack{sp; sp}`
///   56, V3h `Pass{VStack{sp}}` 56, V7h `ZStack{VStack{sp}}` 56; V3 `Pass{sp}`
///   40.
/// - A same-axis stack: first child's leading, last child's trailing, its own
///   spacing ignored. V1 `HStack{sp}` 40; V1b `HStack{sp; c}` 48 (c at 20, b at
///   28); V1c `HStack{c; sp}` 48 (c at 28, b at 28); V1i `HStack(spacing:
///   4){sp; c}` 52 (c at 24, b at 32); V1k `HStack{sp.padding(.leading, 4); c}`
///   60 (c at 32, b at 40); V1e vertically `VStack{a; VStack{sp}; b}` 20×40.
///   The trailing edge is the last child's TRAILING edge (probe revision 10, V1k
///   mirrored): V1l `HStack{c; sp.padding(.trailing, 4)}` 60 and V1m
///   `HStack{c; sp.padding(.leading, 4)}` 60, each c at 28 and b at 40 — the only
///   arms whose last child's two edges disagree.
/// - A cross-axis stack or a custom layout: an edge is zero when ANY child's
///   is. V3b `Pass{sp; c}`, V3e `Pass{c; sp}`, V7 `VStack{ZStack{sp}}`, V7b
///   `VStack{ZStack{sp}; c}`, V7c `VStack{HStack{sp}}`, V7d `VStack{c;
///   HStack{sp}}`, V7e, V7i `Pass{VStack{sp}; ZStack{sp}}`: each 40. Per edge:
///   V3f `Pass{sp.padding(.leading, 4); c}` 52, b at 32; V7f
///   `VStack{ZStack{sp}.padding(.leading, 4); HStack{sp}}` 44, b at 24.
/// - A ZStack: EVERY child's, per edge. V7g `ZStack{HStack{sp}}` 40, V7j
///   `ZStack{sp; HStack{sp}}` 40, V7k `ZStack{sp.padding(.leading, 4); sp}` 52,
///   b at 32.
/// - Empty: zero. V1f `HStack{}`, V1g `VStack{}`, V3d `Pass{}`, V4 `ZStack{}`:
///   each 40.
///
/// Before the amendment the walk answered no zero edge for any stack or custom
/// layout: V1, V1b, V3, V3d, V4 read 56 and V1e 20×56. Mutations: an empty
/// `ZStack` has no zero edge (V4); a nested stack has none (V1…); a spacer's
/// edges ignore its orientation (V1d, V1h, V3h, V7h read 40); a custom layout
/// combines with AND (V3b, V3e, V7i); a cross-axis stack combines with AND (V7b,
/// V7d); a same-axis stack reads its last child's LEADING edge for its trailing
/// one (mutation F: V1l and V1m only, 4 issues — V1l 52 with b at 32, V1m 68
/// with b at 48; record §17, "Closeout"). Before V1l/V1m that mutation reddened
/// nothing (record §17, lane 3's record pass and the branch checker's M3): V1b's
/// last child is a leaf and V1c's a bare spacer, whose two edges agree.
@Test func defaultSpacingBesideANestedContainerFollowsItsChildrensEdges() {
    typealias Middle = (Arm) -> LayoutNodeID
    /// `defaultHStack{a; middle; b}` at nil×nil: the arm and its answer.
    func between(_ middle: Middle) -> (Arm, SizeD) {
        let arm = Arm()
        let a = arm.fixed("a", 20, 20)
        let m = middle(arm)
        let root = arm.defaultHStack("s", [a, m, arm.fixed("b", 20, 20)])
        return (arm, arm.run(root, nil, nil))
    }
    func sp(_ arm: Arm) -> LayoutNodeID { arm.tree.newNativeSpacer(minLength: 0) }
    func c(_ arm: Arm, _ name: String = "c") -> LayoutNodeID { arm.fixed(name, 0, 0) }
    func pass(_ arm: Arm, _ children: [LayoutNodeID]) -> LayoutNodeID {
        arm.tree.newNativeLayout(Pass(), children: children)
    }
    func leftPadded(_ arm: Arm, _ child: LayoutNodeID) -> LayoutNodeID {
        arm.tree.newNativePadding(child: child, insets: Edges(top: 0, right: 0, bottom: 0, left: 4))
    }
    func rightPadded(_ arm: Arm, _ child: LayoutNodeID) -> LayoutNodeID {
        arm.tree.newNativePadding(child: child, insets: Edges(top: 0, right: 4, bottom: 0, left: 0))
    }

    let controls: [(String, Middle)] = [
        ("V1j", { arm in arm.defaultHStack("w", [c(arm)]) }),
        ("V3c", { arm in pass(arm, [c(arm)]) }),
        ("V3g", { arm in pass(arm, [c(arm), c(arm, "d")]) }),
        ("V4c", { arm in arm.zstack("w", [c(arm)]) }),
        ("V1d", { arm in arm.defaultVStack("w", [sp(arm), c(arm)]) }),
        ("V1h", { arm in arm.defaultVStack("w", [sp(arm), sp(arm)]) }),
        ("V3h", { arm in pass(arm, [arm.defaultVStack("v", [sp(arm)])]) }),
        ("V7h", { arm in arm.zstack("w", [arm.defaultVStack("v", [sp(arm)])]) }),
    ]
    for (label, middle) in controls {
        let (arm, answer) = between(middle)
        #expect(answer == size(56, 20), "\(label) size")
        #expect(arm["b"] == rect(36, 0, 20, 20), "\(label) b")
    }
    let zero: [(String, Middle)] = [
        ("V1", { arm in arm.defaultHStack("w", [sp(arm)]) }),
        ("V1f", { arm in arm.defaultHStack("w", []) }),
        ("V1g", { arm in arm.defaultVStack("w", []) }),
        ("V3", { arm in pass(arm, [sp(arm)]) }),
        ("V3b", { arm in pass(arm, [sp(arm), c(arm)]) }),
        ("V3e", { arm in pass(arm, [c(arm), sp(arm)]) }),
        ("V3d", { arm in pass(arm, []) }),
        ("V4", { arm in arm.zstack("w", []) }),
        ("V7", { arm in arm.defaultVStack("w", [arm.zstack("z", [sp(arm)])]) }),
        ("V7b", { arm in arm.defaultVStack("w", [arm.zstack("z", [sp(arm)]), c(arm)]) }),
        ("V7c", { arm in arm.defaultVStack("w", [arm.defaultHStack("h", [sp(arm)])]) }),
        ("V7d", { arm in arm.defaultVStack("w", [c(arm), arm.defaultHStack("h", [sp(arm)])]) }),
        ("V7e", { arm in arm.defaultVStack("w", [arm.defaultHStack("h", [sp(arm)]),
                                                 arm.defaultHStack("h2", [sp(arm)])]) }),
        ("V7g", { arm in arm.zstack("w", [arm.defaultHStack("h", [sp(arm)])]) }),
        ("V7i", { arm in pass(arm, [arm.defaultVStack("v", [sp(arm)]), arm.zstack("z", [sp(arm)])]) }),
        ("V7j", { arm in arm.zstack("w", [sp(arm), arm.defaultHStack("h", [sp(arm)])]) }),
    ]
    for (label, middle) in zero {
        let (arm, answer) = between(middle)
        #expect(answer == size(40, 20), "\(label) size")
        #expect(arm["b"] == rect(20, 0, 20, 20), "\(label) b")
    }
    do { // V1b
        let (arm, answer) = between { arm in arm.defaultHStack("w", [sp(arm), c(arm)]) }
        #expect(answer == size(48, 20), "V1b size")
        #expect(arm.x("c") == 20, "V1b c")
        #expect(arm["b"] == rect(28, 0, 20, 20), "V1b b")
    }
    do { // V1c
        let (arm, answer) = between { arm in arm.defaultHStack("w", [c(arm), sp(arm)]) }
        #expect(answer == size(48, 20), "V1c size")
        #expect(arm.x("c") == 28, "V1c c")
        #expect(arm["b"] == rect(28, 0, 20, 20), "V1c b")
    }
    do { // V1i
        let (arm, answer) = between { arm in
            arm.name(arm.tree.newNativeLinearStack(children: [sp(arm), c(arm)], axis: .horizontal, spacing: 4), "w")
        }
        #expect(answer == size(52, 20), "V1i size")
        #expect(arm.x("c") == 24, "V1i c")
        #expect(arm["b"] == rect(32, 0, 20, 20), "V1i b")
    }
    do { // V1k
        let (arm, answer) = between { arm in arm.defaultHStack("w", [leftPadded(arm, sp(arm)), c(arm)]) }
        #expect(answer == size(60, 20), "V1k size")
        #expect(arm.x("c") == 32, "V1k c")
        #expect(arm["b"] == rect(40, 0, 20, 20), "V1k b")
    }
    do { // V1l (probe revision 10, V1k mirrored): the last child's padded TRAILING edge is default
        let (arm, answer) = between { arm in arm.defaultHStack("w", [c(arm), rightPadded(arm, sp(arm))]) }
        #expect(answer == size(60, 20), "V1l size")
        #expect(arm.x("c") == 28, "V1l c")
        #expect(arm["b"] == rect(40, 0, 20, 20), "V1l b")
    }
    do { // V1m (probe revision 10): the last child's padded LEADING edge does not reach the trailing edge
        let (arm, answer) = between { arm in arm.defaultHStack("w", [c(arm), leftPadded(arm, sp(arm))]) }
        #expect(answer == size(60, 20), "V1m size")
        #expect(arm.x("c") == 28, "V1m c")
        #expect(arm["b"] == rect(40, 0, 20, 20), "V1m b")
    }
    do { // V3f
        let (arm, answer) = between { arm in pass(arm, [leftPadded(arm, sp(arm)), c(arm)]) }
        #expect(answer == size(52, 20), "V3f size")
        #expect(arm["b"] == rect(32, 0, 20, 20), "V3f b")
    }
    do { // V7f
        let (arm, answer) = between { arm in
            arm.defaultVStack("w", [leftPadded(arm, arm.zstack("z", [sp(arm)])),
                                    arm.defaultHStack("h", [sp(arm)])])
        }
        #expect(answer == size(44, 20), "V7f size")
        #expect(arm["b"] == rect(24, 0, 20, 20), "V7f b")
    }
    do { // V7k
        let (arm, answer) = between { arm in arm.zstack("w", [leftPadded(arm, sp(arm)), sp(arm)]) }
        #expect(answer == size(52, 20), "V7k size")
        #expect(arm["b"] == rect(32, 0, 20, 20), "V7k b")
    }
    do { // V1e, vertically
        let arm = Arm()
        let root = arm.defaultVStack("s", [arm.fixed("a", 20, 20),
                                           arm.defaultVStack("w", [sp(arm)]),
                                           arm.fixed("b", 20, 20)])
        #expect(arm.run(root, nil, nil) == size(20, 40), "V1e size")
        #expect(arm["b"] == rect(0, 20, 20, 20), "V1e b")
    }
}

// MARK: - Lane 4: ZStack placement (CN-E's ZStack clause)

extension Arm {
    /// The probe's `half` leaf: width half its proposal (half of 40 at nil),
    /// height 10.
    func half(_ name: String) -> LayoutNodeID {
        let log = ProposalLog()
        let id = tree.newNativeLeaf { proposal in
            log.record(proposal)
            return LayoutMeasurement(size: SizeD(width: (proposal.width ?? 40) / 2, height: 10))
        }
        nodes[name] = id
        logs[name] = log
        return id
    }

    func zstack(_ name: String, alignment: ProposalAlignment, _ children: [LayoutNodeID]) -> LayoutNodeID {
        self.name(tree.newNativeOverlay(children: children, alignment: alignment), name)
    }
}

/// Kernel half of test 4.4 (CN-E, amended in critic round 1): a `ZStack`
/// measures every child at its proposal, then PLACES every child at a proposal
/// equal to its own size B (the stored bounds), and aligns each child's answer
/// there within the UNION U of those answers, U at the `ZStack`'s origin.
///
/// Each arm is laid out at its proposal in bounds of its own answer at the
/// origin (`Arm.run`), as the probe's `Probe` layout places it.
///
/// - Z1 `ZStack{half h; o 20x20}` at 60×40: 30×20; h proposed [60×40, 30×20],
///   placed 15×10 at SwiftUI's (2.5, 5) — stored rounded, (3, 5) 15×10
///   (`roundLayout`: 2.5 → 3, 17.5 → 18); o at (0, 0).
/// - Z2 `.topLeading`: h and o at (0, 0).
/// - Z3 at nil: 20×20; h proposed [nil×nil, 20×20] at (5, 5) 10×10.
/// - Z4 `{half h; o 60x40}` at 100×100: 60×40; h proposed [100×100, 60×40] at
///   (15, 15) 30×10.
/// - Q2 `{a area 600 ideal 10; b 30x20}` at nil: 30×60; a proposed [nil×nil,
///   30×60] at (0, 0) 30×20; b at (0, 0).
/// - A5 `{a 0..inf ideal 10; b 20x20}` at 100×80: a (0, 0) 100×80, b (40, 30).
///   A5n at nil: 20×20, a proposed [nil×nil, 20×20], both at (0, 0).
/// - X12 at 100×nil: 100×20; a proposed [100×nil, 100×20] (0, 0) 100×20; b
///   (40, 0).
///
/// Before the lane each child is placed at the `ZStack`'s PARENT proposal and
/// centred in the bounds: Z1's h reads (0, 5) 30×10. Mutations: place at the
/// parent's proposal (Z4 moves); centre in the bounds instead of the union
/// (Z1 moves).
@Test func aZStackPlacesItsChildrenAtItsOwnSizeWithinTheirUnion() {
    do { // Z1
        let arm = Arm()
        let root = arm.zstack("z", [arm.half("h"), arm.fixed("o", 20, 20)])
        #expect(arm.run(root, 60, 40) == size(30, 20), "Z1 size")
        #expect(arm.proposals("h") == [p(60, 40), p(30, 20)], "Z1 h proposals")
        #expect(arm["h"] == rect(3, 5, 15, 10), "Z1 h (SwiftUI 2.5, 5)")
        #expect(arm["o"] == rect(0, 0, 20, 20), "Z1 o")
    }
    do { // Z2
        let arm = Arm()
        let root = arm.zstack("z", alignment: .topLeading, [arm.half("h"), arm.fixed("o", 20, 20)])
        #expect(arm.run(root, 60, 40) == size(30, 20), "Z2 size")
        #expect(arm["h"] == rect(0, 0, 15, 10), "Z2 h")
        #expect(arm["o"] == rect(0, 0, 20, 20), "Z2 o")
    }
    do { // Z3
        let arm = Arm()
        let root = arm.zstack("z", [arm.half("h"), arm.fixed("o", 20, 20)])
        #expect(arm.run(root, nil, nil) == size(20, 20), "Z3 size")
        #expect(arm.proposals("h") == [p(nil, nil), p(20, 20)], "Z3 h proposals")
        #expect(arm["h"] == rect(5, 5, 10, 10), "Z3 h")
        #expect(arm["o"] == rect(0, 0, 20, 20), "Z3 o")
    }
    do { // Z4
        let arm = Arm()
        let root = arm.zstack("z", [arm.half("h"), arm.fixed("o", 60, 40)])
        #expect(arm.run(root, 100, 100) == size(60, 40), "Z4 size")
        #expect(arm.proposals("h") == [p(100, 100), p(60, 40)], "Z4 h proposals")
        #expect(arm["h"] == rect(15, 15, 30, 10), "Z4 h")
        #expect(arm["o"] == rect(0, 0, 60, 40), "Z4 o")
    }
    do { // Q2
        let arm = Arm()
        let root = arm.zstack("z", [arm.area("a", 600, ideal: 10), arm.fixed("b", 30, 20)])
        #expect(arm.run(root, nil, nil) == size(30, 60), "Q2 size")
        #expect(arm.proposals("a") == [p(nil, nil), p(30, 60)], "Q2 a proposals")
        #expect(arm["a"] == rect(0, 0, 30, 20), "Q2 a")
        #expect(arm["b"] == rect(0, 0, 30, 20), "Q2 b")
    }
    do { // A5
        let arm = Arm()
        let root = arm.zstack("z", [arm.flexible("a"), arm.fixed("b", 20, 20)])
        #expect(arm.run(root, 100, 80) == size(100, 80), "A5 size")
        #expect(arm["a"] == rect(0, 0, 100, 80), "A5 a")
        #expect(arm["b"] == rect(40, 30, 20, 20), "A5 b")
    }
    do { // A5n
        let arm = Arm()
        let root = arm.zstack("z", [arm.flexible("a"), arm.fixed("b", 20, 20)])
        #expect(arm.run(root, nil, nil) == size(20, 20), "A5n size")
        #expect(arm.proposals("a") == [p(nil, nil), p(20, 20)], "A5n a proposals")
        #expect(arm["a"] == rect(0, 0, 20, 20), "A5n a")
        #expect(arm["b"] == rect(0, 0, 20, 20), "A5n b")
    }
    do { // X12
        let arm = Arm()
        let root = arm.zstack("z", [arm.flexible("a"), arm.fixed("b", 20, 20)])
        #expect(arm.run(root, 100, nil) == size(100, 20), "X12 size")
        #expect(arm.proposals("a") == [p(100, nil), p(100, 20)], "X12 a proposals")
        #expect(arm["a"] == rect(0, 0, 100, 20), "X12 a")
        #expect(arm["b"] == rect(40, 0, 20, 20), "X12 b")
    }
}

/// Records the proposal each `placeSubviews` call receives.
private final class PlacementLog: @unchecked Sendable {
    var placements: [ProposedSize] = []
}

/// The probe's `half` leaf as a childless custom layout, so the proposal it is
/// PLACED at is observable: a kernel leaf never sees its placement proposal.
private struct PlacementRecordingHalf: ProposalLayout {
    let log: PlacementLog

    func sizeThatFits(proposal: ProposedSize, subviews: MeasurementSubviews) -> LayoutMeasurement {
        LayoutMeasurement(size: SizeD(width: (proposal.width ?? 40) / 2, height: 10))
    }

    func placeSubviews(in bounds: LayoutRect, proposal: ProposedSize, subviews: PlacementSubviews) {
        log.placements.append(proposal)
    }
}

/// CN-E's placement-proposal clause, which the rects of
/// `aZStackPlacesItsChildrenAtItsOwnSizeWithinTheirUnion` cannot see: a
/// `ZStack` places each child with its OWN size B as the child's placement
/// proposal. Probe `swiftui-stack-algorithms.swift`'s placement logs read the
/// displayed (last) placement of the half-width child h at 30×20 in Z1 (a
/// `ZStack` answering 30×20 at 60×40) and at 60×40 in Z4 (answering 60×40 at
/// 100×100).
///
/// The kernel places once, so each log holds exactly one entry.
///
/// Mutation (verifier V3): pass the `ZStack`'s parent proposal instead of B to
/// each child's `placeNative` — Z1 reads [60×40], Z4 [100×100].
@Test func aZStackPlacesEachChildWithItsOwnSizeAsTheProposal() {
    do { // Z1
        let arm = Arm()
        let log = PlacementLog()
        let h = arm.tree.newNativeLayout(PlacementRecordingHalf(log: log), children: [])
        let root = arm.zstack("z", [h, arm.fixed("o", 20, 20)])
        #expect(arm.run(root, 60, 40) == size(30, 20), "Z1 size")
        #expect(log.placements == [p(30, 20)], "Z1 h placement proposal")
        #expect(arm.tree.layout(h) == rect(3, 5, 15, 10), "Z1 h (SwiftUI 2.5, 5)")
    }
    do { // Z4
        let arm = Arm()
        let log = PlacementLog()
        let h = arm.tree.newNativeLayout(PlacementRecordingHalf(log: log), children: [])
        let root = arm.zstack("z", [h, arm.fixed("o", 60, 40)])
        #expect(arm.run(root, 100, 100) == size(60, 40), "Z4 size")
        #expect(log.placements == [p(60, 40)], "Z4 h placement proposal")
        #expect(arm.tree.layout(h) == rect(15, 15, 30, 10), "Z4 h")
    }
}
