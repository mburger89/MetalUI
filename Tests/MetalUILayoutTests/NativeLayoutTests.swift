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

/// An ideal frame dimension is the proposal used only when its parent leaves
/// that axis unspecified. It does not force the frame's response: the child
/// still answers the proposal and the frame then applies its min/max limits.
@Test func aNativeFrameUsesIdealDimensionsOnlyForUnspecifiedAxes() {
    let tree = LayoutTree(generation: 0)
    let child = tree.newNativeLeaf { proposal in
        #expect(proposal == ProposedSize(width: 80, height: 60))
        return LayoutMeasurement(size: SizeD(width: 30, height: 10))
    }
    let frame = tree.newNativeFrame(child: child,
                                    minWidth: 40, idealWidth: 90, maxWidth: 80,
                                    minHeight: 20, idealHeight: 70, maxHeight: 70)

    let measurement = tree.computeNativeLayout(
        root: frame,
        proposal: ProposedSize(width: nil, height: 60),
        in: LayoutRect(x: 5, y: 9, width: 40, height: 20)
    )

    #expect(measurement.size == SizeD(width: 40, height: 20))
    #expect(tree.layout(child) == LayoutRect(x: 10, y: 14, width: 30, height: 10))
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
