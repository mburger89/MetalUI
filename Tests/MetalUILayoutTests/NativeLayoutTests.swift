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
