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

@Test func edgesMemberwiseInitAssignsEachFieldToItsOwnSlot() {
    let e = Edges(top: 1.0, right: 2.0, bottom: 3.0, left: 4.0)
    #expect(e.top == 1.0)
    #expect(e.right == 2.0)
    #expect(e.bottom == 3.0)
    #expect(e.left == 4.0)
    // A transposition would still be field-wise equal to *some* permutation, so
    // pin the ordering down explicitly.
    #expect(e != Edges(top: 4.0, right: 3.0, bottom: 2.0, left: 1.0))
    #expect(e != Edges(top: 2.0, right: 1.0, bottom: 4.0, left: 3.0))
}

@Test func edgesUniformInitFillsEveryField() {
    let e = Edges(all: 7.0)
    #expect(e.top == 7.0)
    #expect(e.right == 7.0)
    #expect(e.bottom == 7.0)
    #expect(e.left == 7.0)
}

@Test func cornersMemberwiseInitAssignsEachFieldToItsOwnSlot() {
    let c = Corners(topLeft: 1.0, topRight: 2.0, bottomRight: 3.0, bottomLeft: 4.0)
    #expect(c.topLeft == 1.0)
    #expect(c.topRight == 2.0)
    #expect(c.bottomRight == 3.0)
    #expect(c.bottomLeft == 4.0)
    #expect(c != Corners(topLeft: 4.0, topRight: 3.0, bottomRight: 2.0, bottomLeft: 1.0))
    #expect(c != Corners(topLeft: 2.0, topRight: 1.0, bottomRight: 4.0, bottomLeft: 3.0))
}

@Test func cornersUniformInitFillsEveryField() {
    let c = Corners(all: 9.0)
    #expect(c.topLeft == 9.0)
    #expect(c.topRight == 9.0)
    #expect(c.bottomRight == 9.0)
    #expect(c.bottomLeft == 9.0)
}
