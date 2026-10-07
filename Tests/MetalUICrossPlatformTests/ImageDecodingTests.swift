import Testing
import Foundation
import CStbImage
@testable import MetalUI

// Portable images, lane 2, tests 2.1–2.10 and 2.13 (rulings `PX-B`…`PX-E`,
// `PX-O`; spec `docs/superpowers/specs/2026-10-07-portable-app-design.md`
// §4.2). Portable: Linux and Windows CI run this file, so every literal below
// is the same decode on every platform (`PX-C` item 1).
//
// The fixtures are written by `docs/probes/image-decoder-parity/gen-fixtures.py
// --tests`, a pure-Python PNG encoder, so every PNG literal is the generator's
// straight pixels premultiplied with `ImageTexture`'s rule ((c × a + 127) /
// 255; 16-bit samples first rounded (v × 255 + 32767) / 65535) — printed by
// the generator, not read back from a decoder. The JPEG literal is stb's
// output (scalar paths everywhere, `STBI_NO_SIMD`, `PX-O` item 4), checked
// against the generator's source within 3. Loaded by `#filePath` (`FT-G`).

private let fixtureDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    .appendingPathComponent("ImageFixtures")

private func fixturePath(_ name: String) -> String {
    fixtureDirectory.appendingPathComponent(name).path
}

private func fixtureBytes(_ name: String) throws -> [UInt8] {
    [UInt8](try Data(contentsOf: fixtureDirectory.appendingPathComponent(name)))
}

private func decoded(_ name: String) -> [UInt8]? {
    ImageBitmap(contentsOfFile: fixturePath(name))?.texture.pixels
}

private func bitmap(_ bytes: some Collection<UInt8>) -> ImageBitmap? {
    ImageBitmap(data: Data(bytes))
}

/// Byte offsets of each chunk's end (after its CRC) in a PNG, by chunk type.
private func pngChunkEnds(_ bytes: [UInt8]) -> [(type: String, end: Int)] {
    var ends: [(String, Int)] = []
    var offset = 8
    while offset + 8 <= bytes.count {
        let length = Int(bytes[offset]) << 24 | Int(bytes[offset + 1]) << 16
            | Int(bytes[offset + 2]) << 8 | Int(bytes[offset + 3])
        let type = String(decoding: bytes[(offset + 4)..<(offset + 8)], as: UTF8.self)
        offset += 12 + length
        ends.append((type, offset))
    }
    return ends
}

/// The 4×3 PNG fixtures and their premultiplied bytes (the generator's
/// output). `rgba8-adam7.png` is `rgba8.png` interlaced (passes 2 and 3 are
/// empty at 4×3); `rgb8-srgb.png` and `rgb8-p3.png` are `rgb8.png` with an
/// `sRGB` chunk and a Display P3 `iCCP` chunk — profiles are ignored
/// (`PX-C` item 4), so all three decode to the same bytes.
private let rgb8Expected: [UInt8] = [
    255, 0, 0, 255, 0, 255, 0, 255, 0, 0, 255, 255, 200, 100, 50, 255,
    10, 20, 30, 255, 255, 255, 255, 255, 17, 34, 51, 255, 128, 128, 128, 255,
    0, 0, 0, 255, 250, 5, 99, 255, 77, 155, 233, 255, 1, 2, 3, 255,
]
private let rgba8Expected: [UInt8] = [
    255, 0, 0, 255, 0, 255, 0, 255, 0, 0, 255, 255, 100, 50, 25, 128,
    0, 0, 0, 0, 64, 64, 64, 64, 13, 27, 40, 200, 128, 128, 128, 255,
    0, 0, 0, 255, 1, 0, 0, 1, 39, 78, 117, 128, 1, 2, 3, 254,
]
private let pngFixtures: [(name: String, pixels: [UInt8])] = [
    ("gray1.png", [0, 0, 0, 255, 255, 255, 255, 255, 0, 0, 0, 255, 255, 255, 255, 255,
                   255, 255, 255, 255, 0, 0, 0, 255, 255, 255, 255, 255, 0, 0, 0, 255,
                   0, 0, 0, 255, 255, 255, 255, 255, 0, 0, 0, 255, 255, 255, 255, 255]),
    ("gray4.png", [0, 0, 0, 255, 17, 17, 17, 255, 34, 34, 34, 255, 51, 51, 51, 255,
                   51, 51, 51, 255, 68, 68, 68, 255, 85, 85, 85, 255, 102, 102, 102, 255,
                   102, 102, 102, 255, 119, 119, 119, 255, 136, 136, 136, 255, 153, 153, 153, 255]),
    ("gray8.png", [255, 255, 255, 255, 0, 0, 0, 255, 0, 0, 0, 255, 200, 200, 200, 255,
                   10, 10, 10, 255, 255, 255, 255, 255, 17, 17, 17, 255, 128, 128, 128, 255,
                   0, 0, 0, 255, 250, 250, 250, 255, 77, 77, 77, 255, 1, 1, 1, 255]),
    ("graya8.png", [255, 255, 255, 255, 0, 0, 0, 255, 0, 0, 0, 255, 100, 100, 100, 128,
                    0, 0, 0, 0, 64, 64, 64, 64, 13, 13, 13, 200, 128, 128, 128, 255,
                    0, 0, 0, 255, 1, 1, 1, 1, 39, 39, 39, 128, 1, 1, 1, 254]),
    ("palette2-trns.png", [255, 0, 0, 255, 0, 128, 0, 128, 0, 0, 0, 0, 50, 25, 13, 64,
                           0, 128, 0, 128, 0, 0, 0, 0, 50, 25, 13, 64, 255, 0, 0, 255,
                           0, 0, 0, 0, 50, 25, 13, 64, 255, 0, 0, 255, 0, 128, 0, 128]),
    ("rgb8.png", rgb8Expected),
    ("rgba8.png", rgba8Expected),
    ("rgba8-adam7.png", rgba8Expected),
    ("rgba16.png", [0, 1, 2, 255, 128, 254, 255, 255, 255, 0, 1, 255, 2, 128, 254, 255,
                    4, 8, 12, 255, 128, 128, 128, 128, 48, 91, 135, 255, 0, 0, 0, 0,
                    1, 2, 3, 255, 254, 254, 254, 255, 0, 0, 1, 255, 156, 195, 233, 255]),
    ("rgb8-srgb.png", rgb8Expected),
    ("rgb8-p3.png", rgb8Expected),
]

/// `q90.jpg`: stb's decode (4×3, 4:4:4, quality 90, Pillow 12.3.0), and the
/// generator's smooth source it was encoded from.
private let q90Expected: [UInt8] = [
    121, 80, 60, 255, 127, 80, 62, 255, 135, 79, 64, 255, 138, 80, 66, 255,
    121, 86, 64, 255, 127, 86, 66, 255, 134, 85, 68, 255, 138, 87, 70, 255,
    119, 91, 67, 255, 126, 91, 69, 255, 133, 92, 72, 255, 138, 93, 74, 255,
]
private let q90Source: [UInt8] = [
    120, 80, 60, 126, 80, 63, 132, 80, 66, 138, 80, 69,
    120, 86, 63, 126, 86, 66, 132, 86, 69, 138, 86, 72,
    120, 92, 66, 126, 92, 69, 132, 92, 72, 138, 92, 75,
]

/// **2.1 — every fixture PNG decodes to its literal pixels**, on every
/// platform: gray 1/4/8, gray + alpha, palette + `tRNS`, RGB, RGBA, Adam7,
/// 16-bit RGBA and the two colour-tagged copies of `rgb8.png`.
///
/// Mutation: R and B swapped in the copy out of stb.
@Test func everyFixturePNGDecodesToItsLiteralPixels() throws {
    for fixture in pngFixtures {
        let image = try #require(ImageBitmap(contentsOfFile: fixturePath(fixture.name)),
                                 "\(fixture.name) decodes")
        #expect(image.width == 4 && image.height == 3, "\(fixture.name): \(image.width)×\(image.height)")
        #expect(image.texture.pixels == fixture.pixels, "\(fixture.name): \(image.texture.pixels)")
    }
}

/// **2.2 — 16-bit samples round to 8 bits** (`PX-C` item 2): `rgba16.png`'s
/// first pixel holds samples 0, 255, 386 (opaque) → 0, 1, 2, and its second
/// 32896, 65280, 65535 → 128, 254, 255. stb's own 8-bit path truncates
/// (`v >> 8`): 0, 0, 1 and 128, 255, 255.
///
/// Mutation: `v >> 8` in place of the rounding.
@Test func sixteenBitSamplesRoundToEightBits() throws {
    let pixels = try #require(decoded("rgba16.png"))
    #expect(Array(pixels[0..<4]) == [0, 1, 2, 255], "255 → 1, 386 → 2: \(Array(pixels[0..<4]))")
    #expect(Array(pixels[4..<8]) == [128, 254, 255, 255], "65280 → 254: \(Array(pixels[4..<8]))")
}

/// **2.3 — straight samples are premultiplied once** (`TE-AR`, the `AI-E`
/// alpha rule): the alpha-128 pixels equal `(c × 128 + 127) / 255` of the
/// generator's straight values — straight (200, 100, 50, 128) → (100, 50,
/// 25, 128), (77, 155, 233, 128) → (39, 78, 117, 128), gray 200 → 100.
///
/// Mutations: the straight samples stored as they are; premultiplied twice.
@Test func straightSamplesArePremultipliedOnce() throws {
    func premultiplied(_ c: Int, _ a: Int) -> UInt8 { UInt8((c * a + 127) / 255) }
    let rgba = try #require(decoded("rgba8.png"))
    #expect(Array(rgba[12..<16]) == [premultiplied(200, 128), premultiplied(100, 128),
                                     premultiplied(50, 128), 128])
    #expect(Array(rgba[12..<16]) == [100, 50, 25, 128], "\(Array(rgba[12..<16]))")
    #expect(Array(rgba[40..<44]) == [39, 78, 117, 128], "\(Array(rgba[40..<44]))")
    let graya = try #require(decoded("graya8.png"))
    #expect(Array(graya[12..<16]) == [100, 100, 100, 128], "\(Array(graya[12..<16]))")
}

/// **2.4 — an Adam7 file decodes like its plain twin**: 9×7 interlaced equals
/// 9×7 plain byte for byte, and the 4×3 interlaced file (two empty passes)
/// equals its literal.
///
/// Mutation: the pre-check refuses `interlace == 1` → both arms red.
@Test func anAdam7FileDecodesLikeItsPlainTwin() throws {
    let plain = try #require(ImageBitmap(contentsOfFile: fixturePath("rgba8-9x7.png")))
    let adam7 = try #require(ImageBitmap(contentsOfFile: fixturePath("rgba8-adam7-9x7.png")))
    #expect(plain.width == 9 && plain.height == 7 && adam7.width == 9 && adam7.height == 7)
    #expect(adam7.texture.pixels == plain.texture.pixels)
    #expect(decoded("rgba8-adam7.png") == rgba8Expected)
}

/// **2.5 — a JPEG decodes to the pinned pixels**: `q90.jpg`'s 48 bytes (stb's
/// scalar output, the same on every CI platform) and each within 3 of the
/// generator's source pixel.
///
/// Mutation: the sniff recognises only PNG → the JPEG is `nil` (on macOS it
/// then reaches ImageIO, whose pixels differ by up to 2 — red either way).
@Test func aJPEGDecodesToThePinnedPixels() throws {
    let image = try #require(ImageBitmap(contentsOfFile: fixturePath("q90.jpg")), "q90.jpg decodes")
    #expect(image.width == 4 && image.height == 3)
    #expect(image.texture.pixels == q90Expected, "\(image.texture.pixels)")
    for pixel in 0..<12 {
        #expect(image.texture.pixels[pixel * 4 + 3] == 255)
        for channel in 0..<3 {
            let got = Int(image.texture.pixels[pixel * 4 + channel])
            let source = Int(q90Source[pixel * 3 + channel])
            #expect(abs(got - source) <= 3, "pixel \(pixel) channel \(channel): \(got) vs \(source)")
        }
    }
}

/// **2.6 — every truncation is `nil` and never traps** (`PX-D`): every prefix
/// `0..<count` of `rgba8.png` and of `q90.jpg`.
///
/// Mutations: the chunk-length bound skipped (the prefixes ending inside
/// `IEND`'s CRC then decode — stb checks no CRC); the JPEG's EOI requirement
/// skipped (stb pads a truncated scan with zeros).
@Test func everyTruncationIsNilAndNeverTraps() throws {
    for name in ["rgba8.png", "q90.jpg"] {
        let bytes = try fixtureBytes(name)
        try #require(bitmap(bytes) != nil, "\(name) whole decodes")
        var decodedPrefixes: [Int] = []
        for length in 0..<bytes.count where bitmap(bytes[0..<length]) != nil {
            decodedPrefixes.append(length)
        }
        #expect(decodedPrefixes.isEmpty, "\(name): prefixes that decoded: \(decodedPrefixes)")
    }
}

/// **2.6b — the PNG pre-check requires `IEND`** (`PX-O` item 1): of
/// `rgba8.png`, the prefix ending right after IDAT's CRC is refused by
/// `pngStructureIsIntact` (stb refuses it too, on its own, so only this
/// direct arm can see the requirement); the whole file passes.
///
/// Mutation: the `IEND` requirement skipped (a walk that runs out after a
/// whole chunk passes).
@Test func thePNGPreCheckRequiresIEND() throws {
    let bytes = try fixtureBytes("rgba8.png")
    let idatEnd = try #require(pngChunkEnds(bytes).first { $0.type == "IDAT" }?.end)
    try #require(idatEnd == bytes.count - 12, "IEND (12 bytes) follows IDAT")
    #expect(Array(bytes[0..<idatEnd]).withUnsafeBytes { pngStructureIsIntact($0) } == false)
    #expect(bytes.withUnsafeBytes { pngStructureIsIntact($0) } == true)
}

/// **2.7 — a corrupt PNG is `nil`**: the three corrupt fixtures (a flipped
/// bit in IDAT's data, the first half of the file, a flipped bit in IHDR's
/// width), and every single-bit flip of every byte of IDAT's data in
/// `rgba8.png` and `rgba8-9x7.png`.
///
/// Mutation: the CRC check skipped (stb alone decodes many of the flips —
/// measured on the 9×7 file, 1 186 of 2 096; `PX-O` item 1).
@Test func aCorruptPNGIsNil() throws {
    for name in ["corrupt-idat.png", "corrupt-truncated.png", "corrupt-ihdr.png"] {
        #expect(ImageBitmap(contentsOfFile: fixturePath(name)) == nil, "\(name)")
    }
    for name in ["rgba8.png", "rgba8-9x7.png"] {
        let bytes = try fixtureBytes(name)
        let chunks = pngChunkEnds(bytes)
        let idat = try #require(chunks.firstIndex { $0.type == "IDAT" })
        let dataStart = chunks[idat - 1].end + 8
        let dataEnd = chunks[idat].end - 4
        try #require(dataEnd > dataStart)
        var decodedFlips = 0
        for index in dataStart..<dataEnd {
            for bit in 0..<8 {
                var flipped = bytes
                flipped[index] ^= UInt8(1 << bit)
                if bitmap(flipped) != nil { decodedFlips += 1 }
            }
        }
        #expect(decodedFlips == 0, "\(name): \(decodedFlips) of \((dataEnd - dataStart) * 8) flips decoded")
    }
}

/// **2.8 — the dimension cap is 16384** (`PX-D` item 3): a valid 16385×1 PNG
/// is `nil`, a 16384×1 one decodes (the separating arm). **2.8b**: stb alone,
/// called directly, refuses the 16385-wide file (`STBI_MAX_DIMENSIONS`) and
/// accepts the 16384-wide one. **2.8c**: the Swift bound,
/// `decodedSizeIsAccepted`, on its own (`PX-O` item 3: either guard alone
/// keeps the first arm green).
///
/// Mutations: `STBI_MAX_DIMENSIONS` 16385 → 2.8b red; the Swift bound 16385 →
/// 2.8c red.
@Test func theDimensionCapIsSixteenThousandThreeHundredEightyFour() throws {
    #expect(ImageBitmap(contentsOfFile: fixturePath("wide-16385x1.png")) == nil)
    let wide = try #require(ImageBitmap(contentsOfFile: fixturePath("wide-16384x1.png")))
    #expect(wide.width == 16384 && wide.height == 1)
    #expect(Array(wide.texture.pixels.suffix(4)) == [10, 20, 30, 255])

    // 2.8b
    for (name, accepted) in [("wide-16385x1.png", false), ("wide-16384x1.png", true)] {
        let bytes = try fixtureBytes(name)
        var width: Int32 = 0, height: Int32 = 0, channels: Int32 = 0
        let pixels = bytes.withUnsafeBufferPointer {
            stbi_load_from_memory($0.baseAddress, Int32($0.count), &width, &height, &channels, 4)
        }
        #expect((pixels != nil) == accepted, "2.8b stb alone, \(name)")
        stbi_image_free(pixels)
    }

    // 2.8c
    #expect(decodedSizeIsAccepted(width: 16385, height: 1) == false)
    #expect(decodedSizeIsAccepted(width: 1, height: 16385) == false)
    #expect(decodedSizeIsAccepted(width: 16384, height: 1) == true)
    #expect(decodedSizeIsAccepted(width: 16384, height: 16384) == true)
    #expect(decodedSizeIsAccepted(width: 0, height: 1) == false)
}

/// **2.9 — a file and its bytes decode identically**: `init?(contentsOfFile:)`
/// and `init?(data:)` give the same bytes for every fixture; a missing path,
/// a directory and empty data are `nil`; and the `rgba8.png` prefix ending
/// inside `IEND`'s CRC is `nil` through `data:` although stb alone decodes it
/// (`PX-O` item 6 — the separating arm, measured here).
///
/// Mutation: `data:` skips the pre-check.
@Test func fileAndDataDecodeIdentically() throws {
    for name in pngFixtures.map(\.name) + ["rgba8-9x7.png", "rgba8-adam7-9x7.png", "q90.jpg", "thumb.jpg"] {
        let fromFile = try #require(ImageBitmap(contentsOfFile: fixturePath(name)), "\(name) from the file")
        let fromData = try #require(bitmap(try fixtureBytes(name)), "\(name) from data")
        #expect(fromFile.texture.pixels == fromData.texture.pixels
                && fromFile.width == fromData.width && fromFile.height == fromData.height, "\(name)")
    }
    #expect(ImageBitmap(contentsOfFile: fixturePath("no-such-file.png")) == nil, "a missing path")
    #expect(ImageBitmap(contentsOfFile: fixtureDirectory.path) == nil, "a directory")
    #expect(ImageBitmap(data: Data()) == nil, "empty data")

    let bytes = try fixtureBytes("rgba8.png")
    let insideIENDCRC = Array(bytes[0..<(bytes.count - 2)])
    var width: Int32 = 0, height: Int32 = 0, channels: Int32 = 0
    let stbAlone = insideIENDCRC.withUnsafeBufferPointer {
        stbi_load_from_memory($0.baseAddress, Int32($0.count), &width, &height, &channels, 4)
    }
    #expect(stbAlone != nil, "stb alone decodes the prefix (no CRC check)")
    stbi_image_free(stbAlone)
    #expect(bitmap(insideIENDCRC) == nil, "through data: the pre-check refuses it")
}

/// **2.10 — a bundle resource decodes once and shares its texture**
/// (`PX-E` item 3): in a scratch flat bundle directory (`Bundle(path:)`),
/// two calls return the same `ImageTexture` (`===`), a subdirectory
/// resolves, and a missing name is `nil`. A resource that does not decode is
/// `nil` and stays `nil` after its file is replaced by a valid PNG — the
/// second answer came from the cache; likewise a decoded resource keeps its
/// pixels after its file is replaced by another image.
///
/// Mutation: the cache bypassed → the identity differs (and the replaced
/// files are read again).
@Test func aBundleResourceDecodesOnceAndSharesItsTexture() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("metalui-bundle-\(UUID().uuidString).bundle")
    defer { try? FileManager.default.removeItem(at: root) }
    let nested = root.appendingPathComponent("Icons/dark")
    try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
    let rgba8 = Data(try fixtureBytes("rgba8.png"))
    let gray8 = Data(try fixtureBytes("gray8.png"))
    try rgba8.write(to: root.appendingPathComponent("icon.png"))
    try gray8.write(to: nested.appendingPathComponent("key.png"))
    try Data([0x89, 0x50, 0x4E, 0x47]).write(to: root.appendingPathComponent("broken.png"))
    let bundle = try #require(Bundle(path: root.path), "a flat bundle directory")

    let first = try #require(ImageBitmap(resource: "icon", bundle: bundle), "icon.png resolves")
    let second = try #require(ImageBitmap(resource: "icon", withExtension: "png", bundle: bundle))
    #expect(first.texture === second.texture, "one decode, one texture identity")
    #expect(first.texture.pixels == rgba8Expected)

    let key = try #require(ImageBitmap(resource: "key", subdirectory: "Icons/dark", bundle: bundle),
                           "the subdirectory resolves")
    #expect(key.texture.pixels == pngFixtures.first { $0.name == "gray8.png" }?.pixels)

    #expect(ImageBitmap(resource: "missing", bundle: bundle) == nil)
    #expect(ImageBitmap(resource: "missing", bundle: bundle) == nil, "missing, asked twice")

    #expect(ImageBitmap(resource: "broken", bundle: bundle) == nil, "an undecodable resource")
    try rgba8.write(to: root.appendingPathComponent("broken.png"))
    #expect(ImageBitmap(resource: "broken", bundle: bundle) == nil, "the cached nil, not the new file")

    try gray8.write(to: root.appendingPathComponent("icon.png"))
    let third = try #require(ImageBitmap(resource: "icon", bundle: bundle))
    #expect(third.texture === first.texture && third.texture.pixels == rgba8Expected,
            "the cached decode, not the replaced file")
}

/// **2.13 — a truncated JPEG with a thumbnail is `nil`** (`PX-O` item 2):
/// `thumb-truncated.jpg` (an `APP1` holding `FF D8 FF DA 00 02 00 FF D9`, the
/// main scan cut in half) is refused by `jpegScanIsTerminated` and so by
/// `ImageBitmap`, although stb alone decodes it (zero-padded — the
/// separating arm); the same file untruncated decodes to `q90.jpg`'s pixels.
///
/// Mutation: the design's raw byte scan for `FF DA … FF D9`.
@Test func aTruncatedJPEGWithAThumbnailIsNil() throws {
    let truncated = try fixtureBytes("thumb-truncated.jpg")
    let whole = try fixtureBytes("thumb.jpg")
    var width: Int32 = 0, height: Int32 = 0, channels: Int32 = 0
    let stbAlone = truncated.withUnsafeBufferPointer {
        stbi_load_from_memory($0.baseAddress, Int32($0.count), &width, &height, &channels, 4)
    }
    #expect(stbAlone != nil, "stb alone decodes the truncated file")
    stbi_image_free(stbAlone)

    #expect(truncated.withUnsafeBytes { jpegScanIsTerminated($0) } == false)
    #expect(whole.withUnsafeBytes { jpegScanIsTerminated($0) } == true)
    #expect(bitmap(truncated) == nil)
    #expect(ImageBitmap(contentsOfFile: fixturePath("thumb-truncated.jpg")) == nil)
    #expect(bitmap(whole)?.texture.pixels == q90Expected)
}

#if !canImport(ImageIO)
/// **2.12, off Apple — a TIFF is `nil`** (`PX-C` item 5: other formats only
/// through ImageIO, which exists only on Apple; `PC-B`'s per-declaration
/// gate). The macOS arm is `aTIFFStillDecodesThroughImageIOOnApple`.
@Test func aTIFFIsNilOffApple() throws {
    #expect(ImageBitmap(contentsOfFile: fixturePath("rgb8.tiff")) == nil)
    #expect(bitmap(try fixtureBytes("rgb8.tiff")) == nil)
}
#endif
