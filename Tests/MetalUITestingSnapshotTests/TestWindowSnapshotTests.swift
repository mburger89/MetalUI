import CoreGraphics
import Foundation
import Metal
import MetalUI
import MetalUIScene
import MetalUITesting
@testable import MetalUITestingSnapshot
import Testing

// `TestWindow.snapshot()` (ruling HT-AB). Needs a Metal device.

private let hasMetal = MTLCreateSystemDefaultDevice() != nil

/// A white window with a red 40 x 40 square at the top left and a line of black text below it.
@MainActor private func fixture(scale: Float) throws -> TestWindow {
    let window = try TestWindow(size: Size(width: Pixels(120), height: Pixels(100)), scaleFactor: scale) {
        VStack(alignment: .leading, spacing: Pixels(0)) {
            Color(red: 1, green: 0, blue: 0).frame(width: Pixels(40), height: Pixels(40))
            Text("Hello Wide World").foregroundColor(Color(red: 0, green: 0, blue: 0))
        }
        .frame(width: Pixels(120), height: Pixels(100), alignment: .topLeading)
        .background(Color(red: 1, green: 1, blue: 1))
    }
    window.tick()
    return window
}

/// RGBA bytes of `image`, row-major.
private func rgba(_ image: CGImage) -> [UInt8] {
    var out = [UInt8](repeating: 0, count: image.width * image.height * 4)
    let context = CGContext(data: &out, width: image.width, height: image.height, bitsPerComponent: 8,
                            bytesPerRow: image.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    return out
}

/// Whether any pixel in rows `rows` is not white.
private func hasInk(_ bytes: [UInt8], width: Int, rows: Range<Int>) -> Bool {
    for y in rows { for x in 0..<width {
        let i = (y * width + x) * 4
        if bytes[i] < 200 || bytes[i + 1] < 200 || bytes[i + 2] < 200 { return true }
    } }
    return false
}

@Test(.enabled(if: hasMetal, "no Metal device")) @MainActor
func aSnapshotIsPointsTimesScaleWithTheRectangleAndTheText() throws {
    for scale: Float in [1, 2] {
        let window = try fixture(scale: scale)
        let image = try window.snapshot()
        let s = Int(scale)
        #expect(image.width == 120 * s)
        #expect(image.height == 100 * s)
        let bytes = rgba(image)
        let inside = ((20 * s) * image.width + 20 * s) * 4
        #expect(bytes[inside] > 240 && bytes[inside + 1] < 15 && bytes[inside + 2] < 15, "red inside the rectangle")
        let corner = ((95 * s) * image.width + 115 * s) * 4
        #expect(bytes[corner] > 240 && bytes[corner + 1] > 240, "white background")
        #expect(hasInk(bytes, width: image.width, rows: (45 * s)..<(70 * s)), "glyphs drawn")
    }
}

/// The glyph check must fail without the atlas: the same scene with an empty atlas draws blank text.
@Test(.enabled(if: hasMetal, "no Metal device")) @MainActor
func theSameSceneWithAnEmptyAtlasDrawsNoGlyphs() throws {
    let window = try fixture(scale: 1)
    let image = try TestWindow.render(scene: window.scene, atlas: GlyphAtlas(width: 1024, height: 1024), size: window.platformWindow.contentSize, scale: 1)
    #expect(!hasInk(rgba(image), width: image.width, rows: 45..<70))
}

@Test(.enabled(if: hasMetal, "no Metal device")) @MainActor
func aPNGHasTheSignatureAndTheWindowExposesItsAtlas() throws {
    let window = try fixture(scale: 1)
    let png = try window.snapshotPNG()
    #expect(Array(png.prefix(4)) == [0x89, 0x50, 0x4E, 0x47])
    #expect(window.glyphAtlas != nil)
}
