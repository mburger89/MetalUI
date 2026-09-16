import Testing
import MetalUICore
@testable import MetalUILayout

private final class NativeMeasureCounter: @unchecked Sendable {
    var count = 0
}

@Test func aNativeOverlayForwardsOneProposalMeasuresTheLargestChildAndCentresEachChild() {
    let tree = LayoutTree(generation: 0)
    let firstCalls = NativeMeasureCounter()
    let secondCalls = NativeMeasureCounter()
    let first = tree.newNativeLeaf { proposal in
        firstCalls.count += 1
        #expect(proposal == ProposedSize(width: 120, height: 80))
        return LayoutMeasurement(size: SizeD(width: 40, height: 20))
    }
    let second = tree.newNativeLeaf { proposal in
        secondCalls.count += 1
        #expect(proposal == ProposedSize(width: 120, height: 80))
        return LayoutMeasurement(size: SizeD(width: 25, height: 50))
    }
    let overlay = tree.newNativeOverlay(children: [first, second])

    let measurement = tree.computeNativeLayout(
        root: overlay,
        proposal: ProposedSize(width: 120, height: 80),
        in: LayoutRect(x: 13, y: 17, width: 120, height: 80)
    )

    #expect(measurement.size == SizeD(width: 40, height: 50))
    #expect(tree.layout(overlay) == LayoutRect(x: 13, y: 17, width: 120, height: 80))
    #expect(tree.layout(first) == LayoutRect(x: 53, y: 47, width: 40, height: 20))
    #expect(tree.layout(second) == LayoutRect(x: 61, y: 32, width: 25, height: 50))
    #expect(firstCalls.count == 1)
    #expect(secondCalls.count == 1)
}

@Test func aNativeOverlayPlacesEveryChildAtTheRequestedAlignment() {
    let tree = LayoutTree(generation: 0)
    let first = tree.newNativeLeaf { _ in
        LayoutMeasurement(size: SizeD(width: 30, height: 10))
    }
    let second = tree.newNativeLeaf { _ in
        LayoutMeasurement(size: SizeD(width: 50, height: 40))
    }
    let overlay = tree.newNativeOverlay(children: [first, second], alignment: .bottomTrailing)

    _ = tree.computeNativeLayout(
        root: overlay,
        proposal: ProposedSize(width: 120, height: 80),
        in: LayoutRect(x: 13, y: 17, width: 120, height: 80)
    )

    #expect(tree.layout(first) == LayoutRect(x: 103, y: 87, width: 30, height: 10))
    #expect(tree.layout(second) == LayoutRect(x: 83, y: 57, width: 50, height: 40))
}

/// Every public proposal alignment must map to a distinct placement in a
/// larger overlay. This is intentionally a nine-arm table: testing only the
/// factors independently would let one enum case be routed to the wrong pair.
@Test func everyProposalAlignmentPlacesAnOverlayChildAtItsNamedPosition() {
    let cases: [(ProposalAlignment, LayoutRect)] = [
        (.topLeading, LayoutRect(x: 13, y: 17, width: 20, height: 10)),
        (.top, LayoutRect(x: 53, y: 17, width: 20, height: 10)),
        (.topTrailing, LayoutRect(x: 93, y: 17, width: 20, height: 10)),
        (.leading, LayoutRect(x: 13, y: 52, width: 20, height: 10)),
        (.center, LayoutRect(x: 53, y: 52, width: 20, height: 10)),
        (.trailing, LayoutRect(x: 93, y: 52, width: 20, height: 10)),
        (.bottomLeading, LayoutRect(x: 13, y: 87, width: 20, height: 10)),
        (.bottom, LayoutRect(x: 53, y: 87, width: 20, height: 10)),
        (.bottomTrailing, LayoutRect(x: 93, y: 87, width: 20, height: 10)),
    ]

    for (alignment, expected) in cases {
        let tree = LayoutTree(generation: 0)
        let child = tree.newNativeLeaf { _ in LayoutMeasurement(size: SizeD(width: 20, height: 10)) }
        let overlay = tree.newNativeOverlay(children: [child], alignment: alignment)
        _ = tree.computeNativeLayout(root: overlay, proposal: ProposedSize(width: 100, height: 80),
                                     in: LayoutRect(x: 13, y: 17, width: 100, height: 80))
        #expect(tree.layout(child) == expected, "alignment: \(alignment)")
    }
}

/// A fixed frame changes the proposal seen by its child; it is not a CSS size
/// declaration applied after that child has already measured. The child returns
/// a deliberately smaller response so the centred placement tests both axes.
@Test func aNativeFrameProposesItsFixedAxesAndCentresTheChildResponse() {
    let tree = LayoutTree(generation: 0)
    let child = tree.newNativeLeaf { proposal in
        #expect(proposal == ProposedSize(width: 100, height: 50))
        return LayoutMeasurement(size: SizeD(width: 30, height: 10), firstBaseline: 7)
    }
    let frame = tree.newNativeFrame(child: child, width: 100, height: 50)

    let measurement = tree.computeNativeLayout(
        root: frame,
        proposal: ProposedSize(width: 180, height: 90),
        in: LayoutRect(x: 13, y: 17, width: 100, height: 50)
    )

    #expect(measurement == LayoutMeasurement(size: SizeD(width: 100, height: 50),
                                              firstBaseline: 27, lastBaseline: nil))
    #expect(tree.layout(frame) == LayoutRect(x: 13, y: 17, width: 100, height: 50))
    #expect(tree.layout(child) == LayoutRect(x: 48, y: 37, width: 30, height: 10))
}

@Test func aNativeFrameForwardsAnOptionalAxisAndAdoptsThatChildResponse() {
    let tree = LayoutTree(generation: 0)
    let child = tree.newNativeLeaf { proposal in
        #expect(proposal == ProposedSize(width: 100, height: 70))
        return LayoutMeasurement(size: SizeD(width: 30, height: 12))
    }
    let frame = tree.newNativeFrame(child: child, width: 100)

    let measurement = tree.computeNativeLayout(
        root: frame,
        proposal: ProposedSize(width: 180, height: 70),
        in: LayoutRect(x: 5, y: 9, width: 100, height: 12)
    )

    #expect(measurement.size == SizeD(width: 100, height: 12))
    #expect(tree.layout(child) == LayoutRect(x: 40, y: 9, width: 30, height: 12))
}

@Test func aNativeFramePlacesItsChildAtTheRequestedAlignment() {
    let tree = LayoutTree(generation: 0)
    let child = tree.newNativeLeaf { proposal in
        #expect(proposal == ProposedSize(width: 100, height: 50))
        return LayoutMeasurement(size: SizeD(width: 30, height: 10), firstBaseline: 7)
    }
    let frame = tree.newNativeFrame(child: child, width: 100, height: 50,
                                    alignment: .bottomTrailing)

    let measurement = tree.computeNativeLayout(
        root: frame,
        proposal: ProposedSize(width: 180, height: 90),
        in: LayoutRect(x: 13, y: 17, width: 100, height: 50)
    )

    #expect(measurement.firstBaseline == 47)
    #expect(tree.layout(child) == LayoutRect(x: 83, y: 57, width: 30, height: 10))
}

/// A frame with a maximum is **greedy**: it answers its parent's proposal
/// clamped into `[min, max]`, not its child's own answer clamped (ruling FR-A;
/// probe `D control`, `D1`, `D2`, `D13`).
///
/// **Re-fixtured by the frame-sizing track's lane 1.** It pinned 40×70, which
/// is `SA-N` item 1's wrong-on-purpose answer — the old kernel grew only at an
/// infinite maximum. By hand, with both axes carrying a declared minimum so
/// `FR-M` is not in play: the width's base is the proposal 100, clamped into
/// 40…80 = **80**; the height's base is the proposal 60, already inside
/// 30…70 = **60**. The child's proposal (80, 60) and the child's stored rect
/// do not move — placement uses the rect the caller passed, not the
/// measurement.
@Test func aNativeFrameClampsItsProposalAndResponseToMinimumAndMaximum() {
    let tree = LayoutTree(generation: 0)
    let child = tree.newNativeLeaf { proposal in
        #expect(proposal == ProposedSize(width: 80, height: 60))
        return LayoutMeasurement(size: SizeD(width: 20, height: 90))
    }
    let frame = tree.newNativeFrame(child: child,
                                    minWidth: 40, maxWidth: 80,
                                    minHeight: 30, maxHeight: 70)

    let measurement = tree.computeNativeLayout(
        root: frame,
        proposal: ProposedSize(width: 100, height: 60),
        in: LayoutRect(x: 5, y: 9, width: 40, height: 70)
    )

    #expect(measurement.size == SizeD(width: 80, height: 60))
    #expect(tree.layout(child) == LayoutRect(x: 15, y: -1, width: 20, height: 90))
}

/// When a parent leaves an axis unspecified, SwiftUI's ideal frame dimension
/// both becomes the child's proposal and the frame's outer response, subject
/// to the frame's min/max limits. A concrete parent proposal still wins.
///
/// **Re-fixtured twice.** By the kernel completion's lane 3 (ruling SA-K item
/// 5), because it declared `idealWidth: 90` over `maxWidth: 80`, which SwiftUI
/// diagnoses as contradictory (P4c) and ruling `SA-J` now rejects at
/// registration; and by the frame-sizing track's lane 1, because its height
/// sentence stated the rule `FR-A` deletes.
///
/// By hand, at ideal 70 under `FR-A`: the width axis has **no** proposal, so
/// the ideal is used — it becomes the child's proposal, clamp(70, 40…80) = 70,
/// and the frame's own answer, 70. The height axis **does** have a concrete
/// proposal (60) and a maximum (70), and a minimum (20) is declared, so the
/// greedy rule applies to it: the base is the proposal 60, clamp(60, 20…70) =
/// **60**. The previous fixture read 20 here — the child's 10 clamped up to the
/// minimum — which is what the kernel answered before the greedy rule landed.
/// The child sees (70, 60) and its stored rect does not move.
///
/// The first re-fixture lost the "ideal clamped by max" case, which validated
/// ordering makes unreachable.
@Test func aNativeFrameUsesIdealDimensionsOnlyForUnspecifiedAxes() {
    let tree = LayoutTree(generation: 0)
    let child = tree.newNativeLeaf { proposal in
        #expect(proposal == ProposedSize(width: 70, height: 60))
        return LayoutMeasurement(size: SizeD(width: 30, height: 10))
    }
    let frame = tree.newNativeFrame(child: child,
                                    minWidth: 40, idealWidth: 70, maxWidth: 80,
                                    minHeight: 20, idealHeight: 70, maxHeight: 70)

    let measurement = tree.computeNativeLayout(
        root: frame,
        proposal: ProposedSize(width: nil, height: 60),
        in: LayoutRect(x: 5, y: 9, width: 40, height: 20)
    )

    #expect(measurement.size == SizeD(width: 70, height: 60))
    #expect(tree.layout(child) == LayoutRect(x: 10, y: 14, width: 30, height: 10))
}

@Test func aNativeFrameWithInfiniteMaximumExpandsToItsFiniteProposal() {
    let tree = LayoutTree(generation: 0)
    let child = tree.newNativeLeaf { proposal in
        #expect(proposal == ProposedSize(width: 120, height: 80))
        return LayoutMeasurement(size: SizeD(width: 30, height: 10))
    }
    let frame = tree.newNativeFrame(child: child, maxWidth: .infinity, maxHeight: .infinity)

    let measurement = tree.computeNativeLayout(
        root: frame, proposal: ProposedSize(width: 120, height: 80),
        in: LayoutRect(x: 0, y: 0, width: 120, height: 80)
    )

    #expect(measurement.size == SizeD(width: 120, height: 80))
    #expect(tree.layout(child) == LayoutRect(x: 45, y: 35, width: 30, height: 10))
}

// MARK: - The flexible frame's response rule (rulings FR-A, FR-B, FR-L, FR-M)
//
// The arm names below (`D control`, `C5`, `H14`, …) are the two committed
// SwiftUI probes': `docs/probes/swiftui-frame-semantics.swift` (54 arms, the
// `A`…`F` names) and `docs/probes/swiftui-frame-negative-sizes.swift` (17 arms,
// the `H` names). Every expected number in this section is one SwiftUI printed,
// except where a test's own doc comment says MetalUI diverges and carries
// SwiftUI's answer beside it.
//
// The rule, from both probes together:
//
//     lo = max(0, min)   hi = max(0, max)         // DECLARED bounds only
//     childProposal = fixed ?? clamp(parentProposal ?? ideal,
//                                   min == nil ? -inf : lo, hi)
//     response      = fixed ?? clamp(base, lo, hi)
//       base = parentProposal            a maximum, a concrete proposal, a DECLARED minimum
//            = max(parentProposal, child) a maximum, a concrete proposal, NO minimum
//            = ideal                     no proposal on this axis
//            = child's answer            otherwise

/// What one width arm of the flexible-frame table answered, and what its child
/// was proposed. The height axis is left entirely unconstrained so the width's
/// rule is the only thing under test.
private struct FrameWidthArm {
    var answer: Double
    var childProposals: [Double?]
}

private func widthArm(_ tree: LayoutTree, childWidth: Double, proposal: Double?,
                      minWidth: Double? = nil, idealWidth: Double? = nil,
                      maxWidth: Double? = nil) -> FrameWidthArm {
    let recorder = NativeProposalRecorder()
    let child = tree.newNativeLeaf { proposal in
        recorder.proposals.append(proposal)
        return LayoutMeasurement(size: SizeD(width: childWidth, height: 20))
    }
    let frame = tree.newNativeFrame(child: child, minWidth: minWidth,
                                    idealWidth: idealWidth, maxWidth: maxWidth)
    let measurement = tree.measureNativeLayout(
        root: frame, proposal: ProposedSize(width: proposal, height: nil))
    return FrameWidthArm(answer: measurement.size.width,
                         childProposals: recorder.proposals.map(\.width))
}

private final class NativeProposalRecorder: @unchecked Sendable {
    var proposals: [ProposedSize] = []
}

/// **A frame with a minimum AND a maximum grows toward its proposal** (ruling
/// FR-A). SwiftUI's flexible frame is greedy at ANY maximum, not only an
/// infinite one, and the kernel answered its child instead.
///
/// Four probe arms, all with a minimum declared so `FR-M` is not in play:
/// `D control` (min 40/max 80 at 100) → 80, `D1` (at 60) → 60, `D2` (at 30) →
/// 40, `D13` (a 200pt child at 100) → 80. `D2` and `D13` are the test's
/// internal controls: they read the same number under the old rule and the new
/// one, so a mutation that reddens all four is a broken instrument rather than
/// this finding.
@Test func aFrameWithAMinimumAndAMaximumGrowsTowardItsProposal() {
    let tree = LayoutTree(generation: 0)

    let dControl = widthArm(tree, childWidth: 20, proposal: 100, minWidth: 40, maxWidth: 80)
    #expect(dControl.answer == 80, "D control: min 40, max 80, proposal 100, child 20")
    #expect(dControl.childProposals == [80])

    let d1 = widthArm(tree, childWidth: 20, proposal: 60, minWidth: 40, maxWidth: 80)
    #expect(d1.answer == 60, "D1: min 40, max 80, proposal 60, child 20")
    #expect(d1.childProposals == [60])

    let d2 = widthArm(tree, childWidth: 20, proposal: 30, minWidth: 40, maxWidth: 80)
    #expect(d2.answer == 40, "D2 (control): min 40, max 80, proposal 30, child 20")
    #expect(d2.childProposals == [40])

    let d13 = widthArm(tree, childWidth: 200, proposal: 100, minWidth: 40, maxWidth: 80)
    #expect(d13.answer == 80, "D13 (control): min 40, max 80, proposal 100, child 200")
    #expect(d13.childProposals == [80])
}

/// **Without a maximum the frame answers its child, not its proposal** (ruling
/// FR-A). This is the half that rules out "greedy whenever the proposal is
/// concrete": probe `D7`/`D8`/`D9` (a minimum alone) report 40 over a 20pt
/// child at 100, 30 and no proposal alike, `D15` reports its 400pt minimum, and
/// `C control` reports the child's 20 even though an ideal is declared.
@Test func aFrameWithNoMaximumAnswersItsChildRatherThanItsProposal() {
    let tree = LayoutTree(generation: 0)

    #expect(widthArm(tree, childWidth: 20, proposal: 100, minWidth: 40).answer == 40, "D7")
    #expect(widthArm(tree, childWidth: 20, proposal: 30, minWidth: 40).answer == 40, "D8")
    #expect(widthArm(tree, childWidth: 20, proposal: nil, minWidth: 40).answer == 40, "D9")
    #expect(widthArm(tree, childWidth: 20, proposal: 100, minWidth: 400).answer == 400, "D15")
    #expect(widthArm(tree, childWidth: 20, proposal: 300, idealWidth: 80).answer == 20, "C control")
}

// `aFrameAtAnInfiniteProposalAnswersItsChildRatherThanInfinity` (ruling FR-B)
// was replaced by `anInfiniteProposalIsAnsweredWithInfinity` in
// `NativeStackDistributionTests.swift` when ruling CN-F reversed FR-B (plan
// task 6, lane 2).

/// **An ideal dimension is used only on an axis with no proposal** (ruling
/// FR-A's second base). `C1` (ideal 80, no proposal) answers 80 and proposes 80
/// to its child; `C control` (the same frame at a concrete 300) answers the
/// child's 20 and proposes 300; `C3` shows the ideal beating a LARGER child;
/// `C4`/`C5` show the ideal branch and the greedy branch of the same frame.
@Test func anIdealDimensionIsUsedOnlyWhenThatAxisHasNoProposal() {
    let tree = LayoutTree(generation: 0)

    let c1 = widthArm(tree, childWidth: 20, proposal: nil, idealWidth: 80)
    #expect(c1.answer == 80, "C1: ideal 80 at no proposal")
    #expect(c1.childProposals == [80])

    let cControl = widthArm(tree, childWidth: 20, proposal: 300, idealWidth: 80)
    #expect(cControl.answer == 20, "C control: a concrete proposal beats the ideal")
    #expect(cControl.childProposals == [300])

    #expect(widthArm(tree, childWidth: 200, proposal: nil, idealWidth: 80).answer == 80,
            "C3: the ideal beats a larger child")
    #expect(widthArm(tree, childWidth: 20, proposal: nil,
                     minWidth: 40, idealWidth: 80, maxWidth: 120).answer == 80, "C4")
    #expect(widthArm(tree, childWidth: 20, proposal: 300,
                     minWidth: 40, idealWidth: 80, maxWidth: 120).answer == 120, "C5")
}

/// **An absent minimum is not `minWidth: 0`** (ruling FR-M). With a maximum and
/// a concrete proposal the base is the proposal when a minimum is DECLARED, and
/// `max(proposal, child)` when none is. The 54-arm probe could not see this:
/// every arm of it that declares a maximum proposes MORE than its child
/// answers, so the two rules agree on all of them.
///
/// `H8` and `H14` are the decisive pair — identical numbers, differing only in
/// whether a zero minimum is written — so they open the test with a `#require`
/// that they disagree (practices shape 15). `H16` is the live bug the finding
/// exposed: the shipped kernel's `max == .infinity` branch answered the
/// proposal, 100, where SwiftUI answers the 200pt child.
@Test func aFrameWithoutAMinimumNeverAnswersLessThanItsChild() throws {
    let tree = LayoutTree(generation: 0)

    let h8 = widthArm(tree, childWidth: 20, proposal: 10, maxWidth: 80)
    let h14 = widthArm(tree, childWidth: 20, proposal: 10, minWidth: 0, maxWidth: 80)
    try #require(h8.answer != h14.answer,
                 "H8 and H14 are the same numbers with and without a zero minimum: they must disagree")

    #expect(h8.answer == 20, "H8: max 80, NO minimum, proposal 10, child 20")
    #expect(h8.childProposals == [10])
    #expect(h14.answer == 10, "H14: minWidth 0 changes the answer")
    #expect(h14.childProposals == [10])

    #expect(widthArm(tree, childWidth: 20, proposal: 0, maxWidth: 80).answer == 20, "H7")
    #expect(widthArm(tree, childWidth: 20, proposal: 10,
                     minWidth: 5, maxWidth: 80).answer == 10, "H11")
    #expect(widthArm(tree, childWidth: 200, proposal: 10,
                     minWidth: 5, maxWidth: 80).answer == 10, "H13")
    #expect(widthArm(tree, childWidth: 200, proposal: 10, maxWidth: 80).answer == 80, "H15")
    #expect(widthArm(tree, childWidth: 200, proposal: 100,
                     maxWidth: .infinity).answer == 200, "H16")
}

/// **A frame never answers a negative size, and a DECLARED minimum is floored
/// at 0 before use** (ruling FR-L). The floor is on the declared bound, not on
/// the proposal: `H2` (no minimum) forwards a −30 proposal to its child
/// unchanged, where `H4` (`minWidth: −50`) forwards 0 — which is why the two
/// child proposals open the test with a `#require` that they disagree.
///
/// `ProposedSize` is publicly constructible and `ProposalLayout` is a public
/// protocol, so an outside layout can propose a negative width; ruling `SA-J`
/// accepts a negative minimum (`negativeAndNegativeInfiniteFrameMinimumsAndAnInfiniteMaximumAreAccepted`).
///
/// **SwiftUI's negative MAXIMUM and negative FIXED size are unreachable here**
/// (ruling FR-R): SwiftUI floors both at 0 (probe `H6`, `H10`), MetalUI traps at
/// registration instead — `aNegativeFrameMaximumTraps` and
/// `aNegativeFixedFrameDimensionTraps` pin the rejection — so those two probe
/// arms have no MetalUI spelling and are not arms of this test.
@Test func aFrameNeverAnswersANegativeSize() throws {
    let tree = LayoutTree(generation: 0)

    let h2 = widthArm(tree, childWidth: 20, proposal: -30, maxWidth: 80)
    let h4 = widthArm(tree, childWidth: 20, proposal: -30, minWidth: -50, maxWidth: 80)
    try #require(h2.childProposals != h4.childProposals,
                 "an absent minimum forwards a negative proposal; a declared one floors it")

    #expect(h2.answer == 20, "H2: max 80, no minimum, proposal −30, child 20")
    #expect(h2.childProposals == [-30])
    #expect(h4.answer == 0, "H4: minWidth −50 floors to 0, so the base is the −30 proposal clamped up")
    #expect(h4.childProposals == [0])

    #expect(widthArm(tree, childWidth: 20, proposal: 100, minWidth: -50).answer == 20, "H3")
    #expect(widthArm(tree, childWidth: 20, proposal: nil, minWidth: -50).answer == 20, "H9")
}

@Test func aNativePaddingInsetsConcreteProposalsExpandsMeasurementsAndOffsetsBaselines() {
    let tree = LayoutTree(generation: 0)
    let child = tree.newNativeLeaf { proposal in
        #expect(proposal == ProposedSize(width: 82, height: 64))
        return LayoutMeasurement(size: SizeD(width: 30, height: 10), firstBaseline: 5)
    }
    let padding = tree.newNativePadding(child: child,
                                        insets: Edges(top: 3, right: 7, bottom: 13, left: 11))

    let measurement = tree.computeNativeLayout(
        root: padding,
        proposal: ProposedSize(width: 100, height: 80),
        in: LayoutRect(x: 5, y: 9, width: 48, height: 26)
    )

    #expect(measurement == LayoutMeasurement(size: SizeD(width: 48, height: 26), firstBaseline: 8))
    #expect(tree.layout(child) == LayoutRect(x: 16, y: 12, width: 30, height: 10))
}

@Test func aNativeFixedSizeWithholdsOnlyItsSelectedAxesFromTheChildProposal() {
    let tree = LayoutTree(generation: 0)
    let child = tree.newNativeLeaf { proposal in
        #expect(proposal == ProposedSize(width: nil, height: 80))
        return LayoutMeasurement(size: SizeD(width: 30, height: 10), firstBaseline: 6)
    }
    let fixed = tree.newNativeFixedSize(child: child, horizontal: true, vertical: false)

    let measurement = tree.computeNativeLayout(
        root: fixed,
        proposal: ProposedSize(width: 100, height: 80),
        in: LayoutRect(x: 5, y: 9, width: 30, height: 10)
    )

    #expect(measurement == LayoutMeasurement(size: SizeD(width: 30, height: 10), firstBaseline: 6))
    #expect(tree.layout(child) == LayoutRect(x: 5, y: 9, width: 30, height: 10))
}

@Test func aNativeScrollViewportLeavesItsScrollingAxisUnspecifiedForContent() {
    let tree = LayoutTree(generation: 0)
    let contentCalls = NativeMeasureCounter()
    let content = tree.newNativeLeaf { proposal in
        contentCalls.count += 1
        #expect(proposal == ProposedSize(width: 90, height: nil))
        return LayoutMeasurement(size: SizeD(width: proposal.width ?? 80,
                                             height: proposal.height ?? 160))
    }
    let viewport = tree.newNativeScrollViewport(child: content, axis: .vertical)

    let measurement = tree.computeNativeLayout(
        root: viewport,
        proposal: ProposedSize(width: 90, height: 50),
        in: LayoutRect(x: 0, y: 0, width: 90, height: 50)
    )

    #expect(contentCalls.count == 1)
    #expect(measurement.size == SizeD(width: 90, height: 50))
    #expect(tree.layout(viewport) == LayoutRect(x: 0, y: 0, width: 90, height: 50))
    #expect(tree.layout(content) == LayoutRect(x: 0, y: 0, width: 90, height: 160))
}

@Test func aNativeHorizontalScrollViewportLeavesItsWidthUnspecifiedForContent() {
    let tree = LayoutTree(generation: 0)
    let contentCalls = NativeMeasureCounter()
    let content = tree.newNativeLeaf { proposal in
        contentCalls.count += 1
        #expect(proposal == ProposedSize(width: nil, height: 50))
        return LayoutMeasurement(size: SizeD(width: proposal.width ?? 160,
                                             height: proposal.height ?? 40))
    }
    let viewport = tree.newNativeScrollViewport(child: content, axis: .horizontal)

    let measurement = tree.computeNativeLayout(
        root: viewport,
        proposal: ProposedSize(width: 90, height: 50),
        in: LayoutRect(x: 0, y: 0, width: 90, height: 50)
    )

    #expect(contentCalls.count == 1)
    #expect(measurement.size == SizeD(width: 90, height: 50))
    #expect(tree.layout(content) == LayoutRect(x: 0, y: 0, width: 160, height: 50))
}

/// A spacer takes the surplus its siblings leave, because its −∞ priority
/// serves it last (ruling CN-B, CN-C; probe SP8).
///
/// Re-derived by hand for CN-B (plan task 6, lane 1). Leaves 30×10 and 20×10
/// around a min-10 spacer, spacing 5, offered 100×40: 90 remain after the
/// gaps. The priority-0 group reserves the spacer's minimum 10 and is offered
/// 80; both leaves have flexibility 0 (probed at (∞, 40) and (0, 40)), so the
/// first is offered 40 and answers 30, the second 50 and answers 20. The spacer
/// is offered the 40 left and answers 40 wide — and, re-derived for lane 2's
/// CN-C, 0 tall, because the stack marks it: the stack answers 100×10, not
/// 100×40. Placed in bounds 100×40, rects: (0, 15, 30, 10), (35, 20, 40, 0),
/// (80, 15, 20, 10); every proposal carries the 40pt cross.
@Test func aNativeLinearStackDividesConcreteSurplusBetweenSpacers() {
    let tree = LayoutTree(generation: 0)
    let leadingLog = NativeProposalLog()
    let trailingLog = NativeProposalLog()
    let leading = tree.newNativeLeaf { proposal in
        leadingLog.proposals.append(proposal)
        return LayoutMeasurement(size: SizeD(width: 30, height: 10))
    }
    let spacer = tree.newNativeSpacer(minLength: 10)
    let trailing = tree.newNativeLeaf { proposal in
        trailingLog.proposals.append(proposal)
        return LayoutMeasurement(size: SizeD(width: 20, height: 10))
    }
    let stack = tree.newNativeLinearStack(children: [leading, spacer, trailing], axis: .horizontal,
                                           spacing: 5)

    let measurement = tree.computeNativeLayout(
        root: stack,
        proposal: ProposedSize(width: 100, height: 40),
        in: LayoutRect(x: 0, y: 0, width: 100, height: 40)
    )

    #expect(measurement.size == SizeD(width: 100, height: 10))
    #expect(leadingLog.proposals.allSatisfy { $0.height == 40 } && trailingLog.proposals.allSatisfy { $0.height == 40 })
    #expect(leadingLog.proposals.last == ProposedSize(width: 40, height: 40))
    #expect(trailingLog.proposals.last == ProposedSize(width: 50, height: 40))
    #expect(tree.layout(leading) == LayoutRect(x: 0, y: 15, width: 30, height: 10))
    #expect(tree.layout(spacer) == LayoutRect(x: 35, y: 20, width: 40, height: 0))
    #expect(tree.layout(trailing) == LayoutRect(x: 80, y: 15, width: 20, height: 10))
}

/// A horizontal stack forwards the parent's cross-axis proposal to every child,
/// distributes its main axis (ruling CN-B), answers the sum of its children's
/// widths plus gaps, and centres each unequal child vertically.
///
/// Re-derived by hand for CN-B: 30×10 and 50×40, spacing 7, offered 120×80.
/// Both have flexibility 0, so the first is offered (120 − 7) / 2 = 56.5 and the
/// second the 83 left. Answer 87×40; rects (13, 52, 30, 10), (50, 37, 50, 40).
@Test func aNativeHorizontalStackForwardsItsCrossProposalMeasuresAndPlacesInOrder() {
    let tree = LayoutTree(generation: 0)
    let firstLog = NativeProposalLog()
    let secondLog = NativeProposalLog()
    let first = tree.newNativeLeaf { proposal in
        firstLog.proposals.append(proposal)
        return LayoutMeasurement(size: SizeD(width: 30, height: 10))
    }
    let second = tree.newNativeLeaf { proposal in
        secondLog.proposals.append(proposal)
        return LayoutMeasurement(size: SizeD(width: 50, height: 40))
    }
    let stack = tree.newNativeLinearStack(children: [first, second], axis: .horizontal,
                                           spacing: 7)

    let measurement = tree.computeNativeLayout(
        root: stack,
        proposal: ProposedSize(width: 120, height: 80),
        in: LayoutRect(x: 13, y: 17, width: 120, height: 80)
    )

    #expect(measurement.size == SizeD(width: 87, height: 40))
    #expect(firstLog.proposals.allSatisfy { $0.height == 80 } && secondLog.proposals.allSatisfy { $0.height == 80 })
    #expect(firstLog.proposals.last == ProposedSize(width: 56.5, height: 80))
    #expect(secondLog.proposals.last == ProposedSize(width: 83, height: 80))
    #expect(tree.layout(first) == LayoutRect(x: 13, y: 52, width: 30, height: 10))
    #expect(tree.layout(second) == LayoutRect(x: 50, y: 37, width: 50, height: 40))
}

/// The vertical counterpart. Re-derived by hand for CN-B: 30×10 and 50×40,
/// spacing 5, offered 120×80: the first is offered (80 − 5) / 2 = 37.5, the
/// second the 65 left. Answer 50×55; rects (58, 17, 30, 10), (48, 32, 50, 40).
@Test func aNativeVerticalStackForwardsItsCrossProposalMeasuresAndPlacesInOrder() {
    let tree = LayoutTree(generation: 0)
    let firstLog = NativeProposalLog()
    let secondLog = NativeProposalLog()
    let first = tree.newNativeLeaf { proposal in
        firstLog.proposals.append(proposal)
        return LayoutMeasurement(size: SizeD(width: 30, height: 10))
    }
    let second = tree.newNativeLeaf { proposal in
        secondLog.proposals.append(proposal)
        return LayoutMeasurement(size: SizeD(width: 50, height: 40))
    }
    let stack = tree.newNativeLinearStack(children: [first, second], axis: .vertical,
                                           spacing: 5)

    let measurement = tree.computeNativeLayout(
        root: stack,
        proposal: ProposedSize(width: 120, height: 80),
        in: LayoutRect(x: 13, y: 17, width: 120, height: 80)
    )

    #expect(measurement.size == SizeD(width: 50, height: 55))
    #expect(firstLog.proposals.allSatisfy { $0.width == 120 } && secondLog.proposals.allSatisfy { $0.width == 120 })
    #expect(firstLog.proposals.last == ProposedSize(width: 120, height: 37.5))
    #expect(secondLog.proposals.last == ProposedSize(width: 120, height: 65))
    #expect(tree.layout(first) == LayoutRect(x: 58, y: 17, width: 30, height: 10))
    #expect(tree.layout(second) == LayoutRect(x: 48, y: 32, width: 50, height: 40))
}

@Test func aNativeLinearStackUsesItsAlignmentOnTheCrossAxisOnly() {
    let tree = LayoutTree(generation: 0)
    let horizontalChild = tree.newNativeLeaf { _ in
        LayoutMeasurement(size: SizeD(width: 30, height: 10))
    }
    let horizontal = tree.newNativeLinearStack(children: [horizontalChild], axis: .horizontal,
                                                alignment: .bottomTrailing)
    let verticalChild = tree.newNativeLeaf { _ in
        LayoutMeasurement(size: SizeD(width: 30, height: 10))
    }
    let vertical = tree.newNativeLinearStack(children: [verticalChild], axis: .vertical,
                                              alignment: .bottomTrailing)

    _ = tree.computeNativeLayout(
        root: horizontal,
        proposal: ProposedSize(width: 120, height: 80),
        in: LayoutRect(x: 13, y: 17, width: 120, height: 80)
    )
    _ = tree.computeNativeLayout(
        root: vertical,
        proposal: ProposedSize(width: 120, height: 80),
        in: LayoutRect(x: 13, y: 17, width: 120, height: 80)
    )

    #expect(tree.layout(horizontalChild) == LayoutRect(x: 13, y: 87, width: 30, height: 10))
    #expect(tree.layout(verticalChild) == LayoutRect(x: 103, y: 17, width: 30, height: 10))
}

@Test func nativeLayoutRoundsStoredRectanglesAfterFractionalPlacement() {
    let tree = LayoutTree(generation: 0)
    let first = tree.newNativeLeaf { _ in
        LayoutMeasurement(size: SizeD(width: 30.4, height: 10.2))
    }
    let second = tree.newNativeLeaf { _ in
        LayoutMeasurement(size: SizeD(width: 50.2, height: 39.8))
    }
    let stack = tree.newNativeLinearStack(children: [first, second], axis: .horizontal,
                                           spacing: 7.5)

    _ = tree.computeNativeLayout(
        root: stack,
        proposal: ProposedSize(width: 120.5, height: 80.3),
        in: LayoutRect(x: 13.25, y: 17.5, width: 120.5, height: 80.3)
    )

    #expect(tree.layout(first) == LayoutRect(x: 13, y: 53, width: 31, height: 10))
    #expect(tree.layout(second) == LayoutRect(x: 51, y: 38, width: 50, height: 40))
}

private final class NativeProposalLog: @unchecked Sendable {
    var proposals: [ProposedSize] = []
}

/// A `layoutPriority` survives an `.overlay` attachment wrapped around it, as
/// SwiftUI's does (probe L2, `docs/probes/swiftui-layout-protocol-contract.swift`;
/// ruling SA-D). Before lane 1 of the kernel completion the built-in rule read
/// only a `layoutPriority` node that IS the child, so the attachment hid it.
///
/// Hand-derived before the run. A horizontal stack, spacing 0, offered 100×30
/// at bounds (13, 17, 100, 30), holds two leaves that answer
/// `min(80, proposal.width ?? 80)` × 10. The first is under `layoutPriority(1)`
/// and then an overlay attachment (a fixed 6×4 badge).
/// - Re-derived for ruling CN-B (plan task 6, lane 1): reading priority 1
///   through the attachment, the first is the higher group, offered 100 minus
///   the second's minimum 0 = 100, and answers 80; the second is offered the
///   remaining 20. Reading 0 for both: one group, 50 and 50.
/// - Cross axis centred: y = 17 + (30 − 10) / 2 = 27.
/// - The badge is measured at the primary's 80×10 and centred in it:
///   x = 13 + (80 − 6) / 2 = 50, y = 27 + (10 − 4) / 2 = 30.
@Test func aLinearStackReadsPriorityThroughAnOverlayAttachment() {
    let tree = LayoutTree(generation: 0)
    let firstLog = NativeProposalLog()
    let secondLog = NativeProposalLog()
    let first = tree.newNativeLeaf { proposal in
        firstLog.proposals.append(proposal)
        return LayoutMeasurement(size: SizeD(width: Swift.min(80, proposal.width ?? 80), height: 10))
    }
    let prioritized = tree.newNativeLayoutPriority(child: first, priority: 1)
    let badge = tree.newNativeLeaf { _ in LayoutMeasurement(size: SizeD(width: 6, height: 4)) }
    let attached = tree.newNativeOverlayAttachment(child: prioritized, overlay: badge)
    let second = tree.newNativeLeaf { proposal in
        secondLog.proposals.append(proposal)
        return LayoutMeasurement(size: SizeD(width: Swift.min(80, proposal.width ?? 80), height: 10))
    }
    let stack = tree.newNativeLinearStack(children: [attached, second], axis: .horizontal)

    let measurement = tree.computeNativeLayout(
        root: stack,
        proposal: ProposedSize(width: 100, height: 30),
        in: LayoutRect(x: 13, y: 17, width: 100, height: 30)
    )

    #expect(measurement.size == SizeD(width: 100, height: 10))
    #expect(firstLog.proposals.last == ProposedSize(width: 100, height: 30))
    #expect(secondLog.proposals.contains(ProposedSize(width: 20, height: 30)))
    #expect(tree.layout(attached) == LayoutRect(x: 13, y: 27, width: 80, height: 10))
    #expect(tree.layout(first) == LayoutRect(x: 13, y: 27, width: 80, height: 10))
    #expect(tree.layout(badge) == LayoutRect(x: 50, y: 30, width: 6, height: 4))
    #expect(tree.layout(second) == LayoutRect(x: 93, y: 27, width: 20, height: 10))
}
