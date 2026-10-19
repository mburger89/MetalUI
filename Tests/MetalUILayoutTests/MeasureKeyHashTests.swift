import Testing
import MetalUICore
@testable import MetalUILayout

// P2 lane 1, L5 (`PA-K`): the folded measure-key hashes agree with the keys' (synthesized, complete) `==`.

private let axes: [Double?] = [nil, 0, -0.0, 1, 1.5, -1, 100, .infinity, 1e300]

/// Mutation: drop the `axis == 0 ? 0` normalisation in `ProposedSize.foldedHashWord` (`-0.0` and `0.0` are `==`).
@Test func equalMeasureKeysHashEqualAndNilIsNotZero() throws {
    var proposals: [ProposedSize] = []
    for w in axes { for h in axes { proposals.append(ProposedSize(width: w, height: h)) } }
    try #require(proposals.count == 81)
    let signature = LayoutSignature(a: 0x1234_5678_9ABC_DEF0, b: 0x0FED_CBA9_8765_4321)
    var distinct = Set<Int>()
    for p in proposals {
        for q in proposals where p == q {
            #expect(NativeMeasurementKey(id: LayoutNodeID(generation: 3, index: 9), proposal: p).hashValue
                    == NativeMeasurementKey(id: LayoutNodeID(generation: 3, index: 9), proposal: q).hashValue, "\(p) \(q)")
            #expect(LayoutMemo.MeasureKey(signature: signature, proposal: p).hashValue
                    == LayoutMemo.MeasureKey(signature: signature, proposal: q).hashValue, "\(p) \(q)")
        }
        distinct.insert(LayoutMemo.MeasureKey(signature: signature, proposal: p).hashValue)
    }
    // 81 proposals, of which -0.0 == 0 merges 81 - 64 = 17: 64 distinct values; a fold that drops an axis or a nil
    // collapses far below that.
    #expect(distinct.count == 64, "distinct hashes \(distinct.count) of 64 distinct proposals")
    // The id and the signature each move the hash.
    let p = ProposedSize(width: 10, height: 20)
    #expect(NativeMeasurementKey(id: LayoutNodeID(generation: 3, index: 9), proposal: p).hashValue
            != NativeMeasurementKey(id: LayoutNodeID(generation: 3, index: 10), proposal: p).hashValue)
    #expect(LayoutMemo.MeasureKey(signature: signature, proposal: p).hashValue
            != LayoutMemo.MeasureKey(signature: LayoutSignature(a: signature.b, b: signature.a), proposal: p).hashValue)
}
