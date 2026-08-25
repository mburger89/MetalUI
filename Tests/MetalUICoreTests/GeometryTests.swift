import Testing
@testable import MetalUICore

@Test func boundsExposesEdges() {
    let b = Bounds(origin: Point(x: 10.0, y: 20.0), size: Size(width: 30.0, height: 40.0))
    #expect(b.minX == 10.0)
    #expect(b.minY == 20.0)
    #expect(b.maxX == 40.0)
    #expect(b.maxY == 60.0)
}

@Test func boundsContainsIsHalfOpen() {
    let b = Bounds(origin: Point(x: 0.0, y: 0.0), size: Size(width: 10.0, height: 10.0))
    #expect(b.contains(Point(x: 0.0, y: 0.0)))
    #expect(b.contains(Point(x: 9.99, y: 9.99)))
    #expect(!b.contains(Point(x: 10.0, y: 5.0)))   // max edge excluded
    #expect(!b.contains(Point(x: -0.01, y: 5.0)))
}

@Test func edgesAndCornersAreUniformConstructible() {
    #expect(Edges(all: 4.0) == Edges(top: 4.0, right: 4.0, bottom: 4.0, left: 4.0))
    #expect(Corners(all: 6.0) == Corners(topLeft: 6.0, topRight: 6.0, bottomRight: 6.0, bottomLeft: 6.0))
}
