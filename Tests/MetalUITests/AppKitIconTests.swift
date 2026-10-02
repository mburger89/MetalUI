import Testing
import AppKit
import Metal
import MetalUIScene
@testable import MetalUIAppKit

// App icon, lane 1, tests A1–A5 (rulings `AI-E`, `AI-I`; spec §5). The AppKit
// conversion — an `ImageTexture`'s premultiplied RGBA8 sRGB bytes into a
// `CGImage` and an `NSImage` — pinned pixel for pixel, and
// `AppKitPlatform.setApplicationIcon(_:)` reaching
// `NSApplication.applicationIconImage`.
//
// **`applicationIconImage` is a process global and its getter is a snapshot**
// (`AI-I`, measured): it never returns the assigned object, reads back one
// `NSCGImageSnapshotRep`, and returns the generic icon (never `nil`) after
// `nil` is assigned. So these tests read the platform's own `iconImage` and
// only the getter's `size`; every test that sets it restores `nil` in `defer`.
// Run the suite unfiltered (CLAUDE.md: an AppKit test shares one process).

/// A 3×2 texture: row 0 straight (200, 100, 50, 128) — stored (100, 50, 25,
/// 128) — then an opaque and a clear texel; row 1 opaque red, green, blue.
private func mixedTexture() -> ImageTexture {
    ImageTexture(width: 3, height: 2, straightRGBA: [
        200, 100, 50, 128,   10, 20, 30, 255,   0, 0, 0, 0,
        255, 0, 0, 255,      0, 255, 0, 255,    0, 0, 255, 255,
    ])
}

private func square(_ side: Int) -> ImageTexture {
    ImageTexture(width: side, height: side,
                 premultipliedRGBA: [UInt8](repeating: 255, count: side * side * 4))
}

/// **A1** (`AI-E` items 1–2). One representation per texture, in input order
/// (the platform contract is smallest first), every representation's `size`
/// the image's `size`, which is the largest texture's pixel size — so the
/// representations are resolutions of one picture.
///
/// Mutation **MA1**: only the first texture becomes a representation.
@MainActor
@Test func anIconImageHoldsOneRepresentationPerTextureSmallestFirst() throws {
    let image = try #require(AppKitIcon.image(from: [square(16), square(32), square(64)]))
    #expect(image.representations.map(\.pixelsWide) == [16, 32, 64])
    #expect(image.representations.map(\.pixelsHigh) == [16, 32, 64])
    #expect(image.size == NSSize(width: 64, height: 64))
    #expect(image.representations.allSatisfy { $0.size == NSSize(width: 64, height: 64) },
            "rep sizes: \(image.representations.map(\.size))")
}

/// **A2** (`AI-E` item 1, `AI-I` item 1). The `CGImage` wraps the texture's
/// bytes **as stored** — premultiplied, `premultipliedLast`, sRGB — with no
/// un-premultiply. Reads the `CGImage` the function returns, not a
/// representation's (AppKit may snapshot that).
///
/// Mutation **MA2**: un-premultiply before wrapping (the half-alpha texel's
/// bytes would read (199, 100, 50, 128)).
@MainActor
@Test func anIconCGImageCarriesTheTexturesPremultipliedBytesUnchanged() throws {
    let texture = mixedTexture()
    try #require(Array(texture.pixels[0..<4]) == [100, 50, 25, 128])
    let image = try #require(AppKitIcon.cgImage(from: texture))
    #expect(image.width == 3 && image.height == 2)
    #expect(image.alphaInfo == .premultipliedLast)
    #expect(image.colorSpace?.name == CGColorSpace.sRGB)
    #expect(image.bitsPerComponent == 8 && image.bitsPerPixel == 32 && image.bytesPerRow == 12)
    let data = try #require(image.dataProvider?.data as Data?)
    #expect(Array(data) == texture.pixels)
}

/// **A3** (`AI-E` item 1). Drawn into a premultiplied RGBA8 sRGB context, the
/// representation composites as stored: the half-alpha texel reads
/// (100, 50, 25, 128), not premultiplied a second time.
///
/// Mutation **MA3**: label the bytes `.last` (straight) instead of
/// `.premultipliedLast` — CoreGraphics premultiplies again and the texel reads
/// (50, 25, 13, 128).
@MainActor
@Test func anIconRepresentationDrawsWithoutASecondPremultiply() throws {
    let texture = mixedTexture()
    let image = try #require(AppKitIcon.image(from: [texture]))
    let rep = try #require(image.representations.first)
    let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
    var out = [UInt8](repeating: 0, count: 3 * 2 * 4)
    try out.withUnsafeMutableBytes { buffer in
        let context = try #require(CGContext(
            data: buffer.baseAddress, width: 3, height: 2, bitsPerComponent: 8, bytesPerRow: 12,
            space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue))
        context.interpolationQuality = .none
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        rep.draw(in: NSRect(x: 0, y: 0, width: 3, height: 2))
        NSGraphicsContext.restoreGraphicsState()
    }
    #expect(Array(out[0..<4]) == [100, 50, 25, 128], "drawn: \(out)")
    #expect(out == texture.pixels, "drawn: \(out)")
}

/// **A4** (`AI-E` item 3, `AI-I` item 2). Setting the icon on the AppKit
/// platform assigns `NSApplication.applicationIconImage`: the platform's own
/// `iconImage` holds A1's shape (reps 20², 40², size 40), and the getter's
/// `size` reads 40×40 where it read the pre-test icon's size before (the
/// generic icon, 128×128 measured). `[]` assigns `nil`: `iconImage` is `nil`
/// and the getter's size is back to the pre-test size. Neither the getter's
/// identity nor its reps nor `nil` is asserted — the getter is a snapshot
/// that never returns the assigned object and returns the generic icon after
/// `nil` (`AI-I`, measured).
///
/// Mutations **MA4** (method body empty), **MA5** (`[]` leaves the old image).
@MainActor
@Test func settingTheIconOnTheAppKitPlatformSetsTheApplicationIconImage() throws {
    let device = try #require(MTLCreateSystemDefaultDevice(), "no Metal device; run on macOS hardware")
    let app = NSApplication.shared
    defer { app.applicationIconImage = nil }
    let before = try #require(app.applicationIconImage?.size)
    try #require(before != NSSize(width: 40, height: 40), "the pre-test icon cannot tell 40×40 apart")

    let platform = AppKitPlatform(device: device)
    platform.setApplicationIcon([square(20), square(40)])
    let image = try #require(platform.iconImage)
    #expect(image.representations.map(\.pixelsWide) == [20, 40])
    #expect(image.size == NSSize(width: 40, height: 40))
    #expect(app.applicationIconImage?.size == NSSize(width: 40, height: 40))

    platform.setApplicationIcon([])
    #expect(platform.iconImage == nil)
    #expect(app.applicationIconImage?.size == before)
}

/// **A5** (`AI-E` item 3). An empty list makes no image — the platform assigns
/// `nil`, which restores the bundle's or the generic icon.
///
/// Mutation **MA6**: return an empty `NSImage`.
@MainActor
@Test func anEmptyTextureListMakesNoIconImage() {
    #expect(AppKitIcon.image(from: []) == nil)
}
