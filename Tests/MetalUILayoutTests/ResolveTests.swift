import Testing
import MetalUICore
@testable import MetalUILayout

@Test func lengthsResolveByKind() {
    #expect(resolveLength(.pixels(Pixels(12)), against: 400, rootFontSize: 16) == 12)
    #expect(resolveLength(.rems(Rems(2)), against: 400, rootFontSize: 16) == 32)
    #expect(resolveLength(.percent(0.25), against: 400, rootFontSize: 16) == 100)
}

@Test func percentagesAgainstAnIndefiniteParentAreUnresolvable() {
    // CSS treats a percentage against an indefinite containing block as auto.
    #expect(resolveLength(.percent(0.5), against: nil, rootFontSize: 16) == nil)
    // Absolute units do not care about the parent.
    #expect(resolveLength(.pixels(Pixels(10)), against: nil, rootFontSize: 16) == 10)
    #expect(resolveLength(.rems(Rems(1)), against: nil, rootFontSize: 16) == 16)
}

@Test func autoDimensionIsUnresolvable() {
    #expect(resolveDimension(.auto, against: 400, rootFontSize: 16) == nil)
    #expect(resolveDimension(.length(.percent(0.5)), against: 400, rootFontSize: 16) == 200)
}

@Test func edgesResolveAndSumPerAxis() {
    let e = Edges<Length>(top: .pixels(Pixels(1)), right: .pixels(Pixels(2)),
                          bottom: .pixels(Pixels(3)), left: .pixels(Pixels(4)))
    let r = resolveEdges(e, against: 100, rootFontSize: 16)
    #expect(r.top == 1 && r.right == 2 && r.bottom == 3 && r.left == 4)
    #expect(r.horizontal == 6)   // left + right
    #expect(r.vertical == 4)     // top + bottom
}

@Test func edgePercentagesResolveAgainstTheInlineAxisOnly() {
    // CSS resolves ALL padding/margin percentages against the containing
    // block's WIDTH, including the vertical ones. This surprises people.
    let e = Edges<Length>(all: .percent(0.1))
    let r = resolveEdges(e, against: 200, rootFontSize: 16)
    #expect(r.top == 20 && r.bottom == 20)
}

@Test func clampRespectsBothBounds() {
    #expect(clamp(50, min: 10, max: 100) == 50)
    #expect(clamp(5,  min: 10, max: 100) == 10)
    #expect(clamp(500, min: 10, max: 100) == 100)
    #expect(clamp(50, min: nil, max: nil) == 50)
    // min wins when the bounds conflict, per CSS.
    #expect(clamp(50, min: 200, max: 100) == 200)
}
