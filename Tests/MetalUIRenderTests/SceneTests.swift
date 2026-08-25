import Testing
import MetalUICore
import MetalUIShaderTypes
@testable import MetalUIRender

private func rect(order: UInt32, x: Float) -> MUIRect {
    MUIRect(bounds: Bounds(origin: Point(x: ScaledPixels(x), y: ScaledPixels(0)),
                           size: Size(width: ScaledPixels(1), height: ScaledPixels(1))),
            contentMask: Bounds(origin: Point(x: ScaledPixels(0), y: ScaledPixels(0)),
                                size: Size(width: ScaledPixels(100), height: ScaledPixels(100))),
            background: .white, borderColor: .black,
            cornerRadii: Corners(all: ScaledPixels(0)),
            borderWidths: Edges(all: ScaledPixels(0)),
            order: order)
}

@Test func sceneStartsEmptyAndClears() {
    var s = Scene()
    #expect(s.isEmpty)
    s.insert(rect(order: 0, x: 0))
    #expect(!s.isEmpty)
    s.clear()
    #expect(s.isEmpty)
}

@Test func finalizeSortsByOrder() {
    var s = Scene()
    s.insert(rect(order: 2, x: 20))
    s.insert(rect(order: 0, x: 0))
    s.insert(rect(order: 1, x: 10))
    s.finalize()
    #expect(s.rects.map(\.order) == [0, 1, 2])
}

@Test func finalizeIsStableForEqualOrders() {
    // A regression tripwire, not a test of the current comparator: Swift's sort
    // is stable at every size measured (checked up to 5000 elements, with and
    // without a tiebreaker), so no element count can make this fail today. It
    // exists to fail loudly if the sort is ever swapped for a non-stable one.
    let count = 40
    var s = Scene()
    for i in 0..<count {
        s.insert(rect(order: 1, x: Float(i)))
    }
    s.finalize()
    // Insertion order must survive: painters at the same order layer in sequence.
    #expect(s.rects.map(\.bounds.origin.x) == (0..<count).map { Float($0) })
}
