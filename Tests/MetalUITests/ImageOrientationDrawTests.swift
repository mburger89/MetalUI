import Testing
import MetalUICore
import MetalUILayout
import MetalUIScene
import MetalUIRender
@testable import MetalUI

// Item S2, lane 2 (rulings IB-F, IB-G, IB-K; record 113): drawing with an orientation.
// The 2x2 table is probe `swiftui-image-orientation.swift`'s (stored `R B / G W`).

@MainActor
private func painted<E: Element>(_ width: Float, _ height: Float, _ root: E) -> Scene {
    var root = root
    let frame = Frame(contentSize: Size(width: Pixels(width), height: Pixels(height)), scaleFactor: 1)
    frame.render(&root)
    return frame.finalizedScene()
}

private let red: [UInt8] = [255, 0, 0, 255], blue: [UInt8] = [0, 0, 255, 255]
private let green: [UInt8] = [0, 255, 0, 255], white: [UInt8] = [255, 255, 255, 255]

private func letters(_ pixels: [UInt8]) -> String {
    var out = ""
    for i in stride(from: 0, to: pixels.count, by: 4) {
        switch Array(pixels[i..<i + 4]) {
        case red: out += "R"
        case blue: out += "B"
        case green: out += "G"
        case white: out += "W"
        default: out += "?"
        }
    }
    return out
}

private func rbgw() -> ImageBitmap {
    ImageBitmap(width: 2, height: 2, rgba: red + blue + green + white)
}

private func wide(_ width: Int, _ height: Int) -> ImageBitmap {
    ImageBitmap(width: width, height: height,
                rgba: [UInt8](repeating: 200, count: width * height * 4))
}

/// **16 — an oriented image lays out at the oriented size** (probe: a rotated orientation swaps
/// the drawn width and height). Mutation: ignore the argument (the quad stays 4x2).
@Test @MainActor func anOrientedImageLaysOutAtTheOrientedSize() throws {
    let right = painted(40, 40, Image(decorative: wide(4, 2), scale: 1, orientation: .right))
    let up = painted(40, 40, Image(decorative: wide(4, 2), scale: 1, orientation: .up))
    let labelled = painted(40, 40, Image(wide(4, 2), scale: 1, orientation: .left, label: Text("x")))
    try #require(right.images.count == 1 && up.images.count == 1 && labelled.images.count == 1)
    #expect([right.images[0].bounds.size.width, right.images[0].bounds.size.height] == [2, 4])
    #expect([up.images[0].bounds.size.width, up.images[0].bounds.size.height] == [4, 2])
    #expect([labelled.images[0].bounds.size.width, labelled.images[0].bounds.size.height] == [2, 4])
}

/// **17 — an oriented bitmap keeps one texture identity across calls and builds** (`TE-AF`).
/// Mutation: build the variant per call.
@Test @MainActor func anOrientedBitmapKeepsOneTextureIdentityAcrossBuilds() throws {
    let bitmap = rbgw()
    let first = bitmap.oriented(.right), second = bitmap.oriented(.right)
    #expect(first.texture === second.texture)
    #expect(bitmap.oriented(.left).texture !== first.texture, "separate orientations are separate textures")
    let a = painted(40, 40, Image(decorative: bitmap, scale: 1, orientation: .right))
    let b = painted(40, 40, Image(decorative: bitmap, scale: 1, orientation: .right))
    try #require(a.textures.count == 1 && b.textures.count == 1)
    #expect(a.textures[0] === b.textures[0], "two frames name one texture")
    #expect(a.textures[0] === first.texture)
    // A copy of the bitmap shares the box.
    let copy = bitmap
    #expect(copy.oriented(.right).texture === first.texture)
}

/// **18 — the eight orientations give SwiftUI's 2x2 table (probe O9)** through the scene's textures
/// (premultiplied bytes permuted, none changed). Mutation: swap `left` and `right`.
@Test @MainActor func orientedPixelsEqualSwiftUIsForAllEight() throws {
    let expected: [(Image.Orientation, String)] = [
        (.up, "RBGW"), (.upMirrored, "BRWG"), (.down, "WGBR"), (.downMirrored, "GWRB"),
        (.leftMirrored, "RGBW"), (.right, "GRWB"), (.rightMirrored, "WBGR"), (.left, "BWRG")]
    for (orientation, table) in expected {
        let scene = painted(20, 20, Image(decorative: rbgw(), scale: 1, orientation: orientation))
        try #require(scene.textures.count == 1)
        #expect(letters(scene.textures[0].pixels) == table, "\(orientation)")
    }
    // A half-alpha pixel is permuted, never recomputed.
    let half = ImageBitmap(width: 2, height: 1, rgba: [200, 100, 50, 128, 10, 20, 30, 255])
    let flipped = half.oriented(.upMirrored)
    #expect(flipped.texture.pixels == Array(half.texture.pixels[4..<8]) + Array(half.texture.pixels[0..<4]))
    // A 3x2 swaps its axes.
    let tall = wide(3, 2).oriented(.rightMirrored)
    #expect(tall.width == 2 && tall.height == 3)
}

/// **19 — `.up` is the same bitmap and costs no work.** Mutation: always copy.
@Test @MainActor func upOrientedIsTheSameBitmapAndZeroWork() throws {
    let bitmap = rbgw()
    #expect(bitmap.oriented(.up).texture === bitmap.texture)
    let scene = painted(20, 20, Image(decorative: bitmap, scale: 1, orientation: .up))
    try #require(scene.textures.count == 1)
    #expect(scene.textures[0] === bitmap.texture)
}
