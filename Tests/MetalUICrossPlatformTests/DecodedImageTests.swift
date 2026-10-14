import Testing
import Foundation
@testable import MetalUI

// Lane 1 tests 1-5, 12, 13 (rulings IB-A, IB-B, IB-C, IB-I; spec 2026-10-13-image-decode-api §5).
// Bytes are generated (`ImageTestBytes.swift`); the real JPEG is the `q90.jpg` fixture.

private let fixtureDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    .appendingPathComponent("ImageFixtures")

private func fixtureData(_ name: String) throws -> Data {
    try Data(contentsOf: fixtureDirectory.appendingPathComponent(name))
}

/// **1** `rgbaPixelsAreTheSamePixelsAnImageBitmapDraws`. Straight in `DecodedImage`, premultiplied
/// in the bitmap's texture (hand-derived with `(c * a + 127) / 255`). Mutation: store premultiplied
/// bytes in `DecodedImage`.
@Test func rgbaPixelsAreTheSamePixelsAnImageBitmapDraws() throws {
    let straight: [UInt8] = [255, 0, 0, 128, 0, 255, 0, 255, 10, 20, 30, 0, 200, 100, 50, 128]
    let png = makePNG(width: 2, height: 2, bitDepth: 8, colorType: 6, rows: straight)
    let decoded = try #require(DecodedImage(data: Data(png)))
    #expect(decoded.format == .rgba)
    #expect(decoded.pixels == straight)
    #expect(decoded.orientation == .up)
    let bitmap = ImageBitmap(decoded)
    #expect(bitmap.texture.pixels == [128, 0, 0, 128, 0, 255, 0, 255, 0, 0, 0, 0, 100, 50, 25, 128])
    #expect(ImageBitmap(data: Data(png))?.texture.pixels == bitmap.texture.pixels, "the same decoder")
}

/// **1b** A grey `DecodedImage` becomes an `ImageBitmap` with R=G=B=v, A=255.
@Test func aGreyDecodedImageBecomesAnOpaqueGreyBitmap() throws {
    let png = makePNG(width: 3, height: 1, bitDepth: 8, colorType: 0, rows: [0, 77, 255])
    let decoded = try #require(DecodedImage(data: Data(png), format: .grey))
    #expect(decoded.pixels == [0, 77, 255])
    #expect(ImageBitmap(decoded).texture.pixels == [0, 0, 0, 255, 77, 77, 77, 255, 255, 255, 255, 255])
    #expect(ImageBitmap(decoded).width == 3)
}

/// **2** `greyFromAGreySourceIsTheSourceSample`. Mutations: `v >> 8` for 16-bit (the 16-bit arm);
/// compositing the alpha over black (the alpha-0 arm).
@Test func greyFromAGreySourceIsTheSourceSample() throws {
    let eight = makePNG(width: 4, height: 1, bitDepth: 8, colorType: 0, rows: [0, 1, 200, 255])
    #expect(DecodedImage(data: Data(eight), format: .grey)?.pixels == [0, 1, 200, 255])
    // 16-bit: 0x0000, 0x00FF, 0x01FF, 0xFFFF. (v * 255 + 32767) / 65535 = 0, 1, 2, 255; v >> 8 = 0, 0, 1, 255.
    let sixteen = makePNG(width: 4, height: 1, bitDepth: 16, colorType: 0,
                          rows: [0, 0, 0, 0xFF, 0x01, 0xFF, 0xFF, 0xFF])
    #expect(DecodedImage(data: Data(sixteen), format: .grey)?.pixels == [0, 1, 2, 255])
    // Grey + alpha: the alpha is dropped, not composited (alpha 0 keeps its grey).
    let greyAlpha = makePNG(width: 2, height: 1, bitDepth: 8, colorType: 4, rows: [200, 0, 90, 255])
    #expect(DecodedImage(data: Data(greyAlpha), format: .grey)?.pixels == [200, 90])
    // The rgba route of the same file is unchanged.
    #expect(DecodedImage(data: Data(greyAlpha), format: .rgba)?.pixels == [200, 200, 200, 0, 90, 90, 90, 255])
}

/// **3** `greyFromRGBIsStbLuma`: `(77r + 150g + 29b) >> 8` by hand, 76, 149, 28, 18. Mutation:
/// Rec. 709 weights (all four differ).
@Test func greyFromRGBIsStbLuma() throws {
    let rgb: [UInt8] = [255, 0, 0, 0, 255, 0, 0, 0, 255, 10, 20, 30]
    let png = makePNG(width: 4, height: 1, bitDepth: 8, colorType: 2, rows: rgb)
    #expect(DecodedImage(data: Data(png), format: .grey)?.pixels == [76, 149, 28, 18])
    let rgba = makePNG(width: 2, height: 1, bitDepth: 8, colorType: 6, rows: [255, 0, 0, 0, 0, 0, 255, 255])
    #expect(DecodedImage(data: Data(rgba), format: .grey)?.pixels == [76, 28], "alpha is dropped, not composited")
}

/// **4** `strideIsTheRowWidthWithNoPadding`. Mutation: round grey rows up to 4.
@Test func strideIsTheRowWidthWithNoPadding() throws {
    let png = makePNG(width: 3, height: 2, bitDepth: 8, colorType: 2, rows: Array(repeating: 9, count: 18))
    let rgba = try #require(DecodedImage(data: Data(png)))
    let grey = try #require(DecodedImage(data: Data(png), format: .grey))
    #expect(rgba.bytesPerRow == 12 && rgba.pixels.count == 24)
    #expect(grey.bytesPerRow == 3 && grey.pixels.count == 6)
    #expect(rgba.width == 3 && rgba.height == 2 && grey.width == 3 && grey.height == 2)
}

/// **5** `aCorruptOrOversizeFileIsNilInEveryFormat` (`PX-D` unmoved, `IB-I`). Mutation: skip
/// `pngStructureIsIntact` on the grey path.
@Test func aCorruptOrOversizeFileIsNilInEveryFormat() throws {
    let good = try fixtureData("rgba8.png")
    for format in [DecodedImage.Format.rgba, .grey] {
        try #require(DecodedImage(data: good, format: format) != nil, "the control decodes")
        for name in ["corrupt-idat.png", "corrupt-ihdr.png", "corrupt-truncated.png",
                     "wide-16385x1.png", "thumb-truncated.jpg"] {
            #expect(DecodedImage(data: try fixtureData(name), format: format) == nil, "\(name) \(format)")
            #expect(ImageBitmap(data: try fixtureData(name)) == nil, "\(name) as a bitmap")
        }
        #expect(DecodedImage(data: Data(), format: format) == nil)
        #expect(DecodedImage(data: Data([1, 2, 3, 4, 5, 6, 7, 8, 9]), format: format) == nil, "not an image")
        #expect(DecodedImage(data: try fixtureData("rgb8.tiff"), format: format) == nil, "IB-J: no ImageIO fallback")
    }
    #expect(DecodedImage(contentsOfFile: "/nonexistent/none.png") == nil)
    #expect(DecodedImage(contentsOfFile: fixtureDirectory.appendingPathComponent("rgba8.png").path) != nil)
    // A bad CRC the grey path must also refuse: flip a bit in a good 8-bit file's IDAT CRC.
    var flipped = [UInt8](good)
    flipped[flipped.count - 17] ^= 1
    #expect(DecodedImage(data: Data(flipped), format: .grey) == nil)
}

/// **12** `decodeReportsOrientationAndDoesNotApplyIt`. Mutation: permute in `init`.
@Test func decodeReportsOrientationAndDoesNotApplyIt() throws {
    let rows: [UInt8] = [1, 2, 3, 4, 5, 6]
    let tag = pngChunk("eXIf", orientationTIFF(6, bigEndian: false))
    let png = makePNG(width: 3, height: 2, bitDepth: 8, colorType: 0, rows: rows, before: [tag])
    let grey = try #require(DecodedImage(data: Data(png), format: .grey))
    #expect(grey.width == 3 && grey.height == 2 && grey.pixels == rows)
    #expect(grey.orientation == .right)
    #expect(grey.orientedSize.width == 2 && grey.orientedSize.height == 3)
    let rgba = try #require(DecodedImage(data: Data(png)))
    #expect(rgba.orientation == .right && rgba.width == 3 && rgba.height == 2)
    #expect(rgba.pixels.prefix(8) == [1, 1, 1, 255, 2, 2, 2, 255])
    let bitmap = try #require(ImageBitmap(data: Data(png)))
    #expect(bitmap.width == 3 && bitmap.height == 2, "the default draw is unchanged (IB-G)")
    #expect(ImageBitmap(rgba).width == 3, "ImageBitmap(_:) ignores the orientation")
    // A JPEG: the fixture with an APP1 inserted after SOI.
    let q90 = [UInt8](try fixtureData("q90.jpg"))
    let tagged = [UInt8](q90[..<2]) + exifAPP1(orientationTIFF(8, bigEndian: true)) + [UInt8](q90[2...])
    let jpeg = try #require(DecodedImage(data: Data(tagged)))
    let plain = try #require(DecodedImage(data: Data(q90)))
    #expect(plain.orientation == .up)
    #expect(jpeg.orientation == .left && jpeg.width == 4 && jpeg.height == 3)
    #expect(jpeg.pixels == plain.pixels, "the tag adds nothing to the stored pixels")
    #expect(jpeg.orientedSize.width == 3 && jpeg.orientedSize.height == 4)
    // A damaged tag is .up, not a failure.
    let damaged = [UInt8](q90[..<2]) + exifAPP1(orientationTIFF(9, bigEndian: true)) + [UInt8](q90[2...])
    #expect(DecodedImage(data: Data(damaged))?.orientation == .up)
}

/// The probe's 2x2 table (`docs/probes/swiftui-image-orientation.swift`): stored `R B / G W`.
private let probeTable: [(Image.Orientation, String)] = [
    (.up, "RBGW"), (.upMirrored, "BRWG"), (.down, "WGBR"), (.downMirrored, "GWRB"),
    (.leftMirrored, "RGBW"), (.right, "GRWB"), (.rightMirrored, "WBGR"), (.left, "BWRG"),
]

private let letterRGBA: [Character: [UInt8]] = [
    "R": [255, 0, 0, 255], "B": [0, 0, 255, 255], "G": [0, 255, 0, 255], "W": [255, 255, 255, 255],
]
private let letterGrey: [Character: UInt8] = ["R": 10, "B": 20, "G": 30, "W": 40]

/// **13** `applyingOrientationPermutesEveryOneOfTheEightLikeSwiftUI`: the probe's 8 arms in rgba and
/// grey, a 3x2 for the axis swap. Mutations: swap the `left` and `right` tables; transpose instead
/// of rotate (`rightMirrored`/`leftMirrored` against `right`/`left`).
@Test func applyingOrientationPermutesEveryOneOfTheEightLikeSwiftUI() throws {
    for (orientation, expected) in probeTable {
        let rgba = DecodedImage(format: .rgba, width: 2, height: 2,
                                pixels: "RBGW".flatMap { letterRGBA[$0]! }, orientation: orientation)
        let turned = rgba.applyingOrientation()
        #expect(turned.pixels == expected.flatMap { letterRGBA[$0]! }, "rgba \(orientation)")
        #expect(turned.orientation == .up && turned.width == 2 && turned.height == 2 && turned.bytesPerRow == 8)
        let grey = DecodedImage(format: .grey, width: 2, height: 2,
                                pixels: "RBGW".map { letterGrey[$0]! }, orientation: orientation)
        #expect(grey.applyingOrientation().pixels == expected.map { letterGrey[$0]! }, "grey \(orientation)")
    }
    // 3x2: stored a b c / d e f = 1...6.
    let wide: [(Image.Orientation, [UInt8], Int, Int)] = [
        (.up, [1, 2, 3, 4, 5, 6], 3, 2), (.upMirrored, [3, 2, 1, 6, 5, 4], 3, 2),
        (.down, [6, 5, 4, 3, 2, 1], 3, 2), (.downMirrored, [4, 5, 6, 1, 2, 3], 3, 2),
        (.leftMirrored, [1, 4, 2, 5, 3, 6], 2, 3), (.right, [4, 1, 5, 2, 6, 3], 2, 3),
        (.rightMirrored, [6, 3, 5, 2, 4, 1], 2, 3), (.left, [3, 6, 2, 5, 1, 4], 2, 3),
    ]
    for (orientation, expected, width, height) in wide {
        let image = DecodedImage(format: .grey, width: 3, height: 2, pixels: [1, 2, 3, 4, 5, 6], orientation: orientation)
        let turned = image.applyingOrientation()
        #expect(turned.pixels == expected, "3x2 \(orientation)")
        #expect(turned.width == width && turned.height == height && turned.bytesPerRow == width, "3x2 size \(orientation)")
        #expect(image.orientedSize.width == width && image.orientedSize.height == height)
        #expect(image.width == 3 && image.height == 2, "the original is a value")
    }
}
