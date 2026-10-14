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
