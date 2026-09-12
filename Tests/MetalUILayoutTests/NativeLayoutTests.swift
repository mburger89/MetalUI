import Testing
@testable import MetalUILayout

private final class NativeMeasureCounter: @unchecked Sendable {
    var count = 0
}

@Test func aNativeOverlayForwardsOneProposalMeasuresTheLargestChildAndPlacesAtTheRootOrigin() {
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
    #expect(tree.layout(first) == LayoutRect(x: 13, y: 17, width: 40, height: 20))
    #expect(tree.layout(second) == LayoutRect(x: 13, y: 17, width: 25, height: 50))
    #expect(firstCalls.count == 1)
    #expect(secondCalls.count == 1)
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
