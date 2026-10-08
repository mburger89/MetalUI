// RED-BEFORE STUB (lane 1): every query answers 0 and `record` does nothing,
// so each `RowExtentIndexTests` case fails on its first `#expect`. Replaced by
// the implementation in the next commit.

/// A variable-height `List`'s row heights (ruling `VL-D`) — stub.
final class RowExtentIndex<ID: Hashable> {
    private(set) var count: Int
    let declaredEstimate: Double?
    private(set) var width: Double?
    private(set) var nodeVisits = 0
    private(set) var rebuilds = 0

    init(count: Int, declaredEstimate: Double?) {
        self.count = count
        self.declaredEstimate = declaredEstimate
    }

    var estimate: Double { 0 }
    var totalExtent: Double { 0 }
    func offset(of index: Int) -> Double { 0 }
    func extent(at index: Int) -> Double { 0 }
    func index(containing y: Double) -> Int { 0 }
    func isMeasured(_ index: Int) -> Bool { false }
    func id(at index: Int) -> ID? { nil }
    func record(_ height: Double, at index: Int, id: ID) {}
    func forgetMeasurements(width: Double) {}
    @discardableResult
    func rebuild<C: Collection>(ids: C) -> [ID: Int] where C.Element == ID { [:] }
}
