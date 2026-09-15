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

    #expect(measurement.size == SizeD(width: 40, height: 70))
    #expect(tree.layout(child) == LayoutRect(x: 15, y: -1, width: 20, height: 90))
}

/// When a parent leaves an axis unspecified, SwiftUI's ideal frame dimension
/// both becomes the child's proposal and the frame's outer response, subject
/// to the frame's min/max limits. A concrete parent proposal still wins.
///
/// **Re-fixtured by the kernel completion's lane 3** (ruling SA-K item 5): this
/// declared `idealWidth: 90` over `maxWidth: 80`, which SwiftUI diagnoses as
/// contradictory (P4c) and ruling SA-J now rejects at registration. At ideal 70,
/// by hand: the unspecified width proposes the ideal, clamp(70, 40…80) = 70,
/// so the child sees (70, 60) and the frame answers 70; the concrete height 60
/// is not the ideal's, so the height is the child's 10 clamped to 20…70 = 20.
/// The child rect is unchanged. The re-fixture loses the "ideal clamped by
/// max" case, which validated ordering makes unreachable.
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

    #expect(measurement.size == SizeD(width: 70, height: 20))
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

@Test func aNativeLinearStackDividesConcreteSurplusBetweenSpacers() {
    let tree = LayoutTree(generation: 0)
    let leading = tree.newNativeLeaf { proposal in
        #expect(proposal == ProposedSize(width: nil, height: 40))
        return LayoutMeasurement(size: SizeD(width: 30, height: 10))
    }
    let spacer = tree.newNativeSpacer(minLength: 10)
    let trailing = tree.newNativeLeaf { proposal in
        #expect(proposal == ProposedSize(width: nil, height: 40))
        return LayoutMeasurement(size: SizeD(width: 20, height: 10))
    }
    let stack = tree.newNativeLinearStack(children: [leading, spacer, trailing], axis: .horizontal,
                                           spacing: 5)

    let measurement = tree.computeNativeLayout(
        root: stack,
        proposal: ProposedSize(width: 100, height: 40),
        in: LayoutRect(x: 0, y: 0, width: 100, height: 40)
    )

    #expect(measurement.size == SizeD(width: 100, height: 40))
    #expect(tree.layout(leading) == LayoutRect(x: 0, y: 15, width: 30, height: 10))
    #expect(tree.layout(spacer) == LayoutRect(x: 35, y: 0, width: 40, height: 40))
    #expect(tree.layout(trailing) == LayoutRect(x: 80, y: 15, width: 20, height: 10))
}

/// A horizontal stack leaves its main axis unspecified for each child, forwards
/// the parent's cross-axis proposal, sums widths plus gaps, and centres each
/// unequal child vertically in the placement rectangle.
@Test func aNativeHorizontalStackForwardsItsCrossProposalMeasuresAndPlacesInOrder() {
    let tree = LayoutTree(generation: 0)
    let first = tree.newNativeLeaf { proposal in
        #expect(proposal == ProposedSize(width: nil, height: 80))
        return LayoutMeasurement(size: SizeD(width: 30, height: 10))
    }
    let second = tree.newNativeLeaf { proposal in
        #expect(proposal == ProposedSize(width: nil, height: 80))
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
    #expect(tree.layout(first) == LayoutRect(x: 13, y: 52, width: 30, height: 10))
    #expect(tree.layout(second) == LayoutRect(x: 50, y: 37, width: 50, height: 40))
}

@Test func aNativeVerticalStackForwardsItsCrossProposalMeasuresAndPlacesInOrder() {
    let tree = LayoutTree(generation: 0)
    let first = tree.newNativeLeaf { proposal in
        #expect(proposal == ProposedSize(width: 120, height: nil))
        return LayoutMeasurement(size: SizeD(width: 30, height: 10))
    }
    let second = tree.newNativeLeaf { proposal in
        #expect(proposal == ProposedSize(width: 120, height: nil))
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
/// - Natural widths 80 + 80 = 160 > 100, so the stack divides 100 by priority.
/// - Reading priority 1 through the attachment: the first gets its ideal 80,
///   the second the remaining 20. Reading 0 for both: 50 and 50.
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
    #expect(firstLog.proposals.contains(ProposedSize(width: 80, height: 30)))
    #expect(secondLog.proposals.contains(ProposedSize(width: 20, height: 30)))
    #expect(tree.layout(attached) == LayoutRect(x: 13, y: 27, width: 80, height: 10))
    #expect(tree.layout(first) == LayoutRect(x: 13, y: 27, width: 80, height: 10))
    #expect(tree.layout(badge) == LayoutRect(x: 50, y: 30, width: 6, height: 4))
    #expect(tree.layout(second) == LayoutRect(x: 93, y: 27, width: 20, height: 10))
}
