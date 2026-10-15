import Testing
@testable import MetalUILayout

// P2 lane 1, test 1 (`PA-B`): the scalar `roundedRect(_:)` is the array `roundLayout`'s element, bit for bit.

private let roundedRectCorpus: [LayoutRect] = {
    var out: [LayoutRect] = []
    let values: [Double] = [0, 0.4, 0.5, 0.6, 1.5, 2.5, 33.3333, 66.6666, -0.5, -1.4, -2.5, 100.5, 1e6 + 0.5, 0.0000001]
    for x in values { for w in values.map({ abs($0) }) { out.append(LayoutRect(x: x, y: x / 3, width: w, height: w * 1.7)) } }
    out.append(LayoutRect(x: 0, y: 0, width: 0, height: 0))
    return out
}()

/// Mutation: `.rounded()` -> `.rounded(.down)` on `x0` in `roundedRect` reddens this, `nativeLayoutRoundsStoredRectanglesAfterFractionalPlacement`
/// and `theDemoFrameMatchesTheValuesRecordedOnMacOS`.
@Test func aRoundedRectEqualsTheArrayRoundingOfItself() throws {
    try #require(roundedRectCorpus.count > 100)
    for rect in roundedRectCorpus {
        let scalar = roundedRect(rect)
        let viaArray = roundLayout([rect])[0]
        #expect(scalar == viaArray, "\(rect): scalar \(scalar), array \(viaArray)")
    }
    #expect(roundLayout(roundedRectCorpus) == roundedRectCorpus.map(roundedRect))
}
