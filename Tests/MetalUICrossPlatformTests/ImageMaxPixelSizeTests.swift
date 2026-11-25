import Testing
import Foundation
@testable import MetalUI

// `ImageBitmap(data:maxPixelSize:)` / `(contentsOfFile:maxPixelSize:)` (ruling `PX-W`). Every
// expected value is hand-computed from the rule it names, not read back from the resampler.
// PNGs come from `makePNG` (ImageTestBytes.swift); colour type 6 is straight RGBA8.

private func rgbaPNG(_ width: Int, _ height: Int, _ pixel: (Int, Int) -> [UInt8]) -> Data {
    var rows: [UInt8] = []
    for y in 0..<height { for x in 0..<width { rows += pixel(x, y) } }
    return Data(makePNG(width: width, height: height, bitDepth: 8, colorType: 6, rows: rows))
}

private func texels(_ bitmap: ImageBitmap) -> [UInt8] { bitmap.texture.pixels }

/// 400×300 in 4×4 blocks of one colour each: the box filter must return the block colours exactly.
/// Mutation: output size `100×75` swapped for a nearest-neighbour or wrong-axis weight reddens it.
@Test func aLargeImageShrinksToTheLongestSideAndKeepsItsBlocks() throws {
    let data = rgbaPNG(400, 300) { x, y in
        [UInt8(x / 4 % 256), UInt8(y / 4 % 256), UInt8((x / 4 + y / 4) % 256), 255]
    }
    let bitmap = try #require(ImageBitmap(data: data, maxPixelSize: 100))
    #expect((bitmap.width, bitmap.height) == (100, 75))
    let t = texels(bitmap)
    for (x, y) in [(0, 0), (99, 74), (37, 11), (50, 60)] {
        let i = (y * 100 + x) * 4
        #expect(Array(t[i..<(i + 4)]) == [UInt8(x), UInt8(y), UInt8(x + y), 255], "at \(x),\(y)")
    }
}

@Test func aPortraitImageKeepsItsAspect() throws {
    let data = rgbaPNG(300, 400) { _, _ in [10, 20, 30, 255] }
    let bitmap = try #require(ImageBitmap(data: data, maxPixelSize: 100))
    #expect((bitmap.width, bitmap.height) == (75, 100))
    #expect(Array(texels(bitmap).prefix(4)) == [10, 20, 30, 255])
}

/// Exact fit and smaller: the same width, height and bytes as `init(data:)`, never upscaled.
/// Alpha varies, so a path that premultiplied twice or not at all would differ.
@Test func anImageThatFitsIsExactlyWhatInitDataGives() throws {
    let data = rgbaPNG(40, 30) { x, y in [UInt8(x * 6), UInt8(y * 8), 200, UInt8(x * 6 + 10)] }
    let plain = try #require(ImageBitmap(data: data))
    for limit in [40, 41, 1000] {
        let bitmap = try #require(ImageBitmap(data: data, maxPixelSize: limit))
        #expect((bitmap.width, bitmap.height) == (40, 30), "limit \(limit)")
        #expect(texels(bitmap) == texels(plain), "limit \(limit)")
    }
}

/// Rule 2's other side: `max(1, Int((other × max / longest).rounded()))`.
@Test func theShorterSideRoundsAndNeverReachesZero() throws {
    let cases: [(w: Int, h: Int, limit: Int, want: (Int, Int))] = [
        (1000, 1, 10, (10, 1)),    // 0.01 -> 0 -> 1
        (1000, 40, 10, (10, 1)),   // 0.4 -> 0 -> 1
        (1000, 60, 10, (10, 1)),   // 0.6 -> 1
        (1000, 300, 10, (10, 3)),  // 3
        (1000, 150, 10, (10, 2)),  // 1.5 rounds away from zero -> 2
        (1, 1000, 10, (1, 10))
    ]
    for c in cases {
        let data = rgbaPNG(c.w, c.h) { _, _ in [1, 2, 3, 255] }
        let bitmap = try #require(ImageBitmap(data: data, maxPixelSize: c.limit))
        #expect((bitmap.width, bitmap.height) == c.want, "\(c.w)x\(c.h)")
    }
}

/// Mean of four opaque texels: R (255+0+0+255)/4 = 127.5 -> 128 on each channel.
@Test func aTwoByTwoShrunkToOnePixelIsTheMean() throws {
    let colours: [[UInt8]] = [[255, 0, 0, 255], [0, 255, 0, 255], [0, 0, 255, 255], [255, 255, 255, 255]]
    let data = rgbaPNG(2, 2) { x, y in colours[y * 2 + x] }
    let bitmap = try #require(ImageBitmap(data: data, maxPixelSize: 1))
    #expect((bitmap.width, bitmap.height) == (1, 1))
    #expect(texels(bitmap) == [128, 128, 128, 255])
}

/// The transparent texel's straight RGB is green; averaged straight it would put 128 in G.
/// Premultiplied, it contributes nothing: (255+0)/2 = 127.5 -> 128 for R and A, 0 for G and B.
@Test func aTransparentNeighbourContributesAlphaButNoColour() throws {
    let data = rgbaPNG(2, 1) { x, _ in x == 0 ? [255, 0, 0, 255] : [0, 255, 0, 0] }
    let bitmap = try #require(ImageBitmap(data: data, maxPixelSize: 1))
    #expect((bitmap.width, bitmap.height) == (1, 1))
    #expect(texels(bitmap) == [128, 0, 0, 128])
}

/// 3 -> 2 is a ratio of 1.5. Output 0 covers [0, 1.5): texel 0 whole, texel 1 half, so
/// (30 + 90/2) / 1.5 = 50. Output 1 covers [1.5, 3): texel 1 half, texel 2 whole, so
/// (90/2 + 240) / 1.5 = 190. Nearest-neighbour or an integer-weight box would give other numbers.
@Test func aNonIntegerRatioWeightsTheSharedTexelByItsCoverage() throws {
    let values: [UInt8] = [30, 90, 240]
    let data = rgbaPNG(3, 1) { x, _ in [values[x], values[x], values[x], 255] }
    let bitmap = try #require(ImageBitmap(data: data, maxPixelSize: 2))
    #expect((bitmap.width, bitmap.height) == (2, 1))
    #expect(texels(bitmap) == [50, 50, 50, 255, 190, 190, 190, 255])
}

/// Coverage is fractional on the vertical axis too (1 x 3 -> 1 x 2).
@Test func theVerticalAxisIsWeightedTheSameWay() throws {
    let values: [UInt8] = [30, 90, 240]
    let data = rgbaPNG(1, 3) { _, y in [values[y], values[y], values[y], 255] }
    let bitmap = try #require(ImageBitmap(data: data, maxPixelSize: 2))
    #expect((bitmap.width, bitmap.height) == (1, 2))
    #expect(texels(bitmap) == [50, 50, 50, 255, 190, 190, 190, 255])
}

@Test func theFileVariantDecodesLikeTheDataVariantAndFailuresAreNil() throws {
    let data = rgbaPNG(40, 30) { x, y in [UInt8(x * 6), UInt8(y * 8), 90, 255] }
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("px-w-\(UUID().uuidString).png")
    try data.write(to: url)
    defer { try? FileManager.default.removeItem(at: url) }
    let fromFile = try #require(ImageBitmap(contentsOfFile: url.path, maxPixelSize: 10))
    let fromData = try #require(ImageBitmap(data: data, maxPixelSize: 10))
    #expect((fromFile.width, fromFile.height) == (10, 8))
    #expect(texels(fromFile) == texels(fromData))

    #expect(ImageBitmap(contentsOfFile: url.path + ".missing", maxPixelSize: 10) == nil)
    #expect(ImageBitmap(data: Data(), maxPixelSize: 10) == nil)
    #expect(ImageBitmap(data: Data(data.prefix(data.count - 5)), maxPixelSize: 10) == nil)
    #expect(ImageBitmap(data: Data("not an image at all".utf8), maxPixelSize: 10) == nil)
}

@Test func aJPEGIsShrunkToo() throws {
    let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .appendingPathComponent("ImageFixtures/q90.jpg")
    let data = try Data(contentsOf: url)
    let full = try #require(ImageBitmap(data: data))
    let small = try #require(ImageBitmap(data: data, maxPixelSize: 4))
    #expect(max(small.width, small.height) == 4)
    #expect(small.width <= full.width && small.height <= full.height)
}

@Test func itRunsOffTheMainThread() async throws {
    let data = rgbaPNG(400, 300) { _, _ in [9, 8, 7, 255] }
    let result = await Task.detached { () -> (Int, Int, [UInt8])? in
        guard let b = ImageBitmap(data: data, maxPixelSize: 100) else { return nil }
        return (b.width, b.height, Array(b.texture.pixels.prefix(4)))
    }.value
    let (w, h, first) = try #require(result)
    #expect((w, h) == (100, 75))
    #expect(first == [9, 8, 7, 255])
}

/// Mutation: removing the precondition lets `maxPixelSize: 0` through (a 0-sized texture would
/// then trap in `ImageTexture`, but not naming `ImageBitmap`'s maxPixelSize).
@Test func aMaxPixelSizeBelowOneTraps() async {
    let zero = await #expect(processExitsWith: .failure, observing: [\.standardErrorContent]) {
        _ = ImageBitmap(data: Data([1, 2, 3]), maxPixelSize: 0)
    }
    let stderr = String(decoding: zero?.standardErrorContent ?? [], as: UTF8.self)
    #expect(stderr.contains("ImageBitmap") && stderr.contains("maxPixelSize"), "\(stderr)")
    let file = await #expect(processExitsWith: .failure, observing: [\.standardErrorContent]) {
        _ = ImageBitmap(contentsOfFile: "/nonexistent", maxPixelSize: -3)
    }
    let fileStderr = String(decoding: file?.standardErrorContent ?? [], as: UTF8.self)
    #expect(fileStderr.contains("ImageBitmap"), "\(fileStderr)")
}
