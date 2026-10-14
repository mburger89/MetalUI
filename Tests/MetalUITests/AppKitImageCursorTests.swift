import Testing
import Foundation
import Metal
import AppKit
import MetalUICore
import MetalUIScene
import MetalUIRender
@testable import MetalUIPlatform
@testable import MetalUIAppKit

// Image cursors on AppKit (rulings `IC-D`, `AI-E`; spec
// `docs/superpowers/specs/2026-10-14-cursors-headless-design.md` §5 tests 7-8). A real
// `AppKitPlatform` window; the cursor is read back from the host view's `pointerCursor`. Nothing sleeps.

@MainActor private final class Signal: AccessibilityClientSignal {
    func observe(_ handler: @escaping @MainActor (Bool) -> Void) { handler(false) }
}

@MainActor private func hostWindow() throws -> (AppKitWindow, NSWindow) {
    let device = try #require(MTLCreateSystemDefaultDevice(), "no Metal device; run on macOS hardware")
    let platform = AppKitPlatform(device: device, accessibilitySignal: { Signal() })
    let platformWindow = try platform.openWindow(title: "Image cursors \(UUID().uuidString)",
                                                 size: Size(width: Pixels(200), height: Pixels(100)))
    let appKit = try #require(platformWindow as? AppKitWindow)
    return (appKit, try #require(appKit.hostView.window))
}

/// A `side` x `side` texture, premultiplied (100, 50, 25, 128) throughout but its first texel, which
/// carries `seed`.
private func texture(side: Int, seed: UInt8 = 0) -> ImageTexture {
    var bytes: [UInt8] = []
    for i in 0..<(side * side) { bytes += i == 0 ? [seed, 50, 25, 128] : [100, 50, 25, 128] }
    return ImageTexture(width: side, height: side, premultipliedRGBA: bytes)
}

/// **7** (`IC-D`, `AI-E`). The cursor's image is the point size (32 px at scale 2 is 16 pt), its hot
/// spot is AppKit's top-left one — (4, 2), not (4, 14) — and its one bitmap representation holds the
/// texture's premultiplied bytes as stored.
///
/// Mutations: flip the hot spot's y; un-premultiply the bytes.
@MainActor
@Test func appKitImageCursorHasTheImagesPointSizeHotSpotAndStoredPixels() throws {
    let (appKit, nsWindow) = try hostWindow()
    defer { nsWindow.close(); NSCursor.arrow.set() }
    let source = texture(side: 32)
    appKit.setPointerStyle(.image(PlatformCursorImage(texture: source, scale: 2, hotSpot: (x: 4, y: 2))))
    let cursor = appKit.hostView.pointerCursor
    #expect(cursor.image.size == NSSize(width: 16, height: 16))
    #expect(cursor.hotSpot == NSPoint(x: 4, y: 2))
    let rep = try #require(cursor.image.representations.first as? NSBitmapImageRep)
    #expect(rep.pixelsWide == 32 && rep.pixelsHigh == 32)
    let data = try #require(rep.bitmapData)
    try #require(rep.bytesPerRow == 32 * 4, "premise: tightly packed rows")
    #expect(Array(UnsafeBufferPointer(start: data, count: 32 * 32 * 4)) == source.pixels)
}

/// **8** (`IC-D`). The same image twice gives the same `NSCursor`; seventeen distinct images keep
/// sixteen, least recently used out, and the first is the one gone.
///
/// Mutations: remove the cache; remove the bound.
@MainActor
@Test func appKitCachesAnImageCursorPerImageAndBoundsTheCache() throws {
    let (appKit, nsWindow) = try hostWindow()
    defer { nsWindow.close(); NSCursor.arrow.set() }
    let first = PlatformCursorImage(texture: texture(side: 8, seed: 1), scale: 1, hotSpot: (x: 0, y: 0))
    appKit.setPointerStyle(.image(first))
    let cursor = appKit.hostView.pointerCursor
    appKit.setPointerStyle(.arrow)
    appKit.setPointerStyle(.image(first))
    #expect(appKit.hostView.pointerCursor === cursor, "the same image is the same cursor")
    #expect(appKit.imageCursorCacheCount == 1)
    for seed in 2...17 {
        appKit.setPointerStyle(.image(PlatformCursorImage(texture: texture(side: 8, seed: UInt8(seed)),
                                                          scale: 1, hotSpot: (x: 0, y: 0))))
    }
    #expect(appKit.imageCursorCacheCount == 16, "\(appKit.imageCursorCacheCount)")
    appKit.setPointerStyle(.arrow)
    appKit.setPointerStyle(.image(first))
    #expect(appKit.hostView.pointerCursor !== cursor, "the least recently used one was evicted and is rebuilt")
}
