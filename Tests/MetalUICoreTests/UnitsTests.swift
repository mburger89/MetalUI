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

@Test func devicePixelsRoundTripTheirIntegralValue() {
    #expect(DevicePixels(0).value == 0)
    #expect(DevicePixels(1920).value == 1920)
    #expect(DevicePixels(-3).value == -3)
    #expect(DevicePixels(Int32.max).value == Int32.max)
}

@Test func devicePixelsAreEquatable() {
    #expect(DevicePixels(1080) == DevicePixels(1080))
    #expect(DevicePixels(1080) != DevicePixels(1081))
}

@Test func devicePixelsAreOrdered() {
    #expect(DevicePixels(1) < DevicePixels(2))
    #expect(DevicePixels(2) > DevicePixels(1))
    #expect(DevicePixels(-1) < DevicePixels(0))
    #expect(DevicePixels(5) <= DevicePixels(5))
    #expect(DevicePixels(5) >= DevicePixels(5))
}

@Test func devicePixelsAreHashableByValue() {
    let set: Set<DevicePixels> = [DevicePixels(1), DevicePixels(1), DevicePixels(2)]
    #expect(set.count == 2)
    #expect(set.contains(DevicePixels(2)))
}
