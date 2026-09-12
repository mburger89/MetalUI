import Testing
@testable import MetalUILayout

@Test func anUnspecifiedProposalUsesFallbackOnlyForItsUnspecifiedAxis() {
    let proposal = ProposedSize(width: nil, height: 24)
    let result = proposal.replacingUnspecifiedDimensions(by: SizeD(width: 80, height: 60))

    #expect(result.width == 80)
    #expect(result.height == 24)
}

@Test func zeroAndInfinityRemainConcreteProposalsRatherThanFallbackRequests() {
    let fallback = SizeD(width: 80, height: 60)

    #expect(ProposedSize.zero.replacingUnspecifiedDimensions(by: fallback) ==
            SizeD(width: 0, height: 0))
    #expect(ProposedSize.infinity.replacingUnspecifiedDimensions(by: fallback) ==
            SizeD(width: .infinity, height: .infinity))
    #expect(ProposedSize.unspecified.replacingUnspecifiedDimensions(by: fallback) == fallback)
}

@Test func aMeasurementPreservesItsSizeAndOptionalBaselineMetadata() {
    let measurement = LayoutMeasurement(size: SizeD(width: 44, height: 20),
                                        firstBaseline: 15, lastBaseline: 18)
    let box = LayoutMeasurement(size: SizeD(width: 10, height: 8))

    #expect(measurement.size == SizeD(width: 44, height: 20))
    #expect(measurement.firstBaseline == 15)
    #expect(measurement.lastBaseline == 18)
    #expect(box.firstBaseline == nil)
    #expect(box.lastBaseline == nil)
}
