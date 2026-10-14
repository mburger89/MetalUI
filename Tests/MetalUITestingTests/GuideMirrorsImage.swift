import Foundation
import MetalUI
import Testing

// Item S2 (rulings `IB-F`, `IB-G`; record 113): the mirror of the image-decoding block of
// `docs/guides/cross-platform.md`, copied by hand between the markers (`DG-C`, `DG-D`).

// guide: cross-platform #3
/// Decodes once: grey pixels to analyse, and an upright bitmap to draw.
func crossDecode(_ data: Data) -> (grey: DecodedImage, upright: ImageBitmap)? {
    guard let grey = DecodedImage(data: data, format: .grey),
          let colour = DecodedImage(data: data) else { return nil }
    return (grey, ImageBitmap(colour.applyingOrientation()))
}
// end guide

/// A 1x1 PNG decodes to one grey byte and a 1x1 bitmap; garbage is `nil`.
/// Mutation: return `nil` for the grey decode, or drop the `guard`'s second clause.
@Test func theCrossPlatformGuideDecodesOnceAndRejectsGarbage() throws {
    let png = try #require(Data(base64Encoded:
        "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg=="))
    let result = try #require(crossDecode(png))
    #expect(result.grey.format == .grey && result.grey.pixels.count == 1)
    #expect(result.upright.width == 1 && result.upright.height == 1)
    #expect(crossDecode(Data([1, 2, 3, 4])) == nil)
}

// Item S9 (rulings `IH-J`, `IH-O`; record 117): the mirror of the bounded-decode block of
// `docs/guides/cross-platform.md`, copied by hand between the markers (`DG-C`, `DG-D`).

// guide: cross-platform #4
/// Decodes only what fits: 16 MB of input, 8192 pixels a side, 24 million pixels.
func crossDecodeBounded(_ data: Data) -> (info: ImageInfo, image: DecodedImage)? {
    let limits = DecodedImage.Limits(maxInputBytes: 16 << 20, maxSide: 8192, maxPixels: 24_000_000)
    guard let info = ImageInfo(data: data),
          let image = DecodedImage(data: data, limits: limits) else { return nil }
    return (info, image)
}
// end guide

/// A 1x1 PNG reports 1x1 and decodes inside the limits; a zero-pixel limit refuses it; garbage is `nil`.
/// Mutation: drop the `guard`'s second clause, or build the limits without `maxPixels`.
@Test func theCrossPlatformGuideBoundsADecodeFromTheHeader() throws {
    let png = try #require(Data(base64Encoded:
        "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg=="))
    let result = try #require(crossDecodeBounded(png))
    #expect(result.info.width == 1 && result.info.height == 1 && result.image.width == 1)
    #expect(DecodedImage(data: png, limits: DecodedImage.Limits(maxPixels: 0)) == nil)
    #expect(crossDecodeBounded(Data([1, 2, 3, 4])) == nil)
}
