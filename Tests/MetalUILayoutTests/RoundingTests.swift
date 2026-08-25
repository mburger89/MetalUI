import Testing
@testable import MetalUILayout

@Test func roundingUsesCumulativeCoordinatesSoWidthsDoNotDrift() {
    // Three children of 33.333… in a 100 row. Naive per-width rounding gives
    // 33+33+33 = 99. Cumulative rounding must recover the missing pixel.
    let input = [
        LayoutRect(x: 0,       y: 0, width: 33.3333, height: 10),
        LayoutRect(x: 33.3333, y: 0, width: 33.3333, height: 10),
        LayoutRect(x: 66.6666, y: 0, width: 33.3333, height: 10),
    ]
    let out = roundLayout(input)
    #expect(out.map(\.x) == [0, 33, 67])
    #expect(out.map(\.width) == [33, 34, 33])
    #expect(out[2].x + out[2].width == 100)   // right edge is exact
}

@Test func roundingIsIdentityOnIntegers() {
    let input = [
        LayoutRect(x: 0,   y: 0,  width: 200, height: 50),
        LayoutRect(x: 200, y: 0,  width: 400, height: 50),
    ]
    #expect(roundLayout(input) == input)
}

@Test func roundingHandlesTheMeasuredWebKitCase() {
    // 7 x flex:1 in 100px, as WebKit actually reports it (1/64 quantised).
    let w = 14.28125
    let input = (0..<7).map { LayoutRect(x: Double($0) * w, y: 0, width: w, height: 10) }
    let out = roundLayout(input)
    // Every child lands on an integer boundary and the row closes at 100.
    #expect(out.allSatisfy { $0.x == $0.x.rounded() && $0.width == $0.width.rounded() })
    #expect(out[6].x + out[6].width == 100)
    #expect(out.map(\.width).reduce(0, +) == 100)
}

@Test func roundingRoundsYIndependentlyOfX() {
    let input = [LayoutRect(x: 0.4, y: 10.6, width: 5.2, height: 3.3)]
    let out = roundLayout(input)
    #expect(out[0].x == 0)
    #expect(out[0].y == 11)
}
