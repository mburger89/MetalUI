import Testing
@testable import MetalUICore

private func close(_ a: Float, _ b: Float, _ tol: Float = 0.001) -> Bool { abs(a - b) < tol }

@Test func hslaToRgbaPrimaries() {
    let red = Hsla(h: 0, s: 1, l: 0.5, a: 1).toRgba()
    #expect(close(red.r, 1) && close(red.g, 0) && close(red.b, 0))

    let green = Hsla(h: 1.0 / 3.0, s: 1, l: 0.5, a: 1).toRgba()
    #expect(close(green.r, 0) && close(green.g, 1) && close(green.b, 0))

    let blue = Hsla(h: 2.0 / 3.0, s: 1, l: 0.5, a: 1).toRgba()
    #expect(close(blue.r, 0) && close(blue.g, 0) && close(blue.b, 1))
}

@Test func hslaGreyscaleHasNoHue() {
    let grey = Hsla(h: 0.25, s: 0, l: 0.5, a: 1).toRgba()
    #expect(close(grey.r, 0.5) && close(grey.g, 0.5) && close(grey.b, 0.5))
}

@Test func hexRoundTripsThroughHsla() {
    let c = Hsla.rgb(0x3366CC).toRgba()
    #expect(close(c.r, 0x33 / 255.0))
    #expect(close(c.g, 0x66 / 255.0))
    #expect(close(c.b, 0xCC / 255.0))
}

@Test func rgbaToHslaRoundTrips() {
    let original = Rgba(r: 0.2, g: 0.6, b: 0.9, a: 1)
    let back = original.toHsla().toRgba()
    #expect(close(back.r, original.r) && close(back.g, original.g) && close(back.b, original.b))
}
