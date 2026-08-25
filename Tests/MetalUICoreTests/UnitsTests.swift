import Testing
@testable import MetalUICore

@Test func pixelsSupportAdditiveArithmeticAndLiterals() {
    let a: Pixels = 10
    let b: Pixels = 2.5
    #expect((a + b).value == 12.5)
    #expect((a - b).value == 7.5)
    #expect(Pixels.zero.value == 0)
}

@Test func pixelsScaleByFloat() {
    let a: Pixels = 10
    #expect((a * 2.0).value == 20.0)
    #expect((a / 4.0).value == 2.5)
}

@Test func pixelsScaleIntoScaledPixels() {
    let a: Pixels = 10
    #expect(a.scaled(by: 2.0) == ScaledPixels(20))
}

@Test func unitsCompare() {
    #expect(Pixels(1) < Pixels(2))
    #expect(ScaledPixels(3) > ScaledPixels(2))
}

@Test func dimensionAndLengthAreDistinct() {
    #expect(Dimension.auto != Dimension.length(.pixels(10)))
    #expect(Length.percent(0.5) != Length.pixels(0.5))
}
