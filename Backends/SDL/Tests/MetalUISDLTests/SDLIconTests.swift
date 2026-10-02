import Testing
import MetalUICore
import MetalUIScene
@testable import MetalUISDL
import SDLBridge

// The application icon on SDL, lane 2, tests S1–S6 (rulings `AI-F`, `AI-J`;
// spec `docs/superpowers/specs/2026-10-01-app-icon-design.md` §5). The pixel
// format is compared against the C-exported `MUI_PIXELFORMAT_RGBA32`, never
// `SDL_PIXELFORMAT_RGBA32.rawValue` (Int32 on Windows, UInt32 on Apple).
// Every test arms `armMainRunLoopExitCheck()` on macOS (record §61 §9).

@MainActor
private func armed() {
    #if os(macOS)
    armMainRunLoopExitCheck()
    #endif
}

@MainActor
private func iconPlatform() throws -> SDLPlatform {
    armed()
    return try SDLPlatform(hiddenWindows: true)
}

@MainActor
private func openWindow(_ platform: SDLPlatform, _ title: String) throws -> SDLWindow {
    let window = try platform.openSDLWindow(title: title, size: Size(width: Pixels(64), height: Pixels(48)))
    platform.pumpEvents()
    return window
}

/// A solid `side` × `side` texture, opaque, its colour varying with `side` so
/// no two sizes share bytes.
private func square(_ side: Int) -> ImageTexture {
    ImageTexture(width: side, height: side,
                 premultipliedRGBA: Array(repeating: [UInt8(side % 256), 40, 200, 255], count: side * side).flatMap { $0 })
}

private func ids(_ textures: [ImageTexture]) -> [ObjectIdentifier] { textures.map(ObjectIdentifier.init) }

/// S1 — `straightRGBA` un-premultiplies: `c → min(255, (c × 255 + a / 2) / a)`,
/// and `a == 0` gives (0, 0, 0, 0). (100, 50, 25, 128) is what
/// `ImageBitmap` stores for straight (200, 100, 50, 128) and comes back one
/// level short on red, (199, 100, 50, 128); (200, 0, 0, 100) — a colour above
/// its alpha, spellable only through `ImageTexture(premultipliedRGBA:)` —
/// clamps to 255 (510 without the clamp, which traps in `UInt8(_:)`).
/// Mutations MS1 (identity), MS2 (no clamp: traps), MS3 (`a == 0` keeps colours).
@MainActor
@Test func unpremultiplyingRestoresStraightAlpha() {
    armed()
    let texture = ImageTexture(width: 5, height: 1, premultipliedRGBA: [
        100, 50, 25, 128,
        255, 0, 0, 255,
        0, 0, 0, 0,
        10, 20, 30, 0,
        200, 0, 0, 100,
    ])
    #expect(SDLIcon.straightRGBA(texture) == [
        199, 100, 50, 128,
        255, 0, 0, 255,
        0, 0, 0, 0,
        0, 0, 0, 0,
        255, 0, 0, 100,
    ])
}

/// S2 — the primary surface is RGBA32, the texture's size (3 wide, 2 high),
/// and holds the STRAIGHT bytes row by row. The fourth texel (10, 20, 30, 40)
/// un-premultiplies to (64, 128, 191, 40). Mutations MS4 (`w`/`h` swapped at
/// create: reads 2 × 3) and MS5 (created from the premultiplied bytes).
@MainActor
@Test func anIconSurfaceIsRGBA32HoldingTheStraightBytesRowByRow() throws {
    armed()
    let texture = ImageTexture(width: 3, height: 2, premultipliedRGBA: [
        100, 50, 25, 128,   255, 0, 0, 255,   0, 0, 0, 0,
        10, 20, 30, 40,     0, 0, 255, 255,   1, 2, 3, 4,
    ])
    let surface = try #require(SDLIcon.makeSurface([texture]))
    defer { mui_surface_destroy(surface) }
    #expect(mui_surface_format(surface) == MUI_PIXELFORMAT_RGBA32)
    var w: Int32 = 0, h: Int32 = 0
    mui_surface_size(surface, &w, &h)
    #expect(w == 3 && h == 2, "size \(w)×\(h)")
    var bytes = [UInt8](repeating: 0xAB, count: 3 * 2 * 4)
    #expect(mui_surface_read_rgba(surface, &bytes, Int32(bytes.count)))
    let expected: [UInt8] = [
        199, 100, 50, 128,  255, 0, 0, 255,   0, 0, 0, 0,
        64, 128, 191, 40,   0, 0, 255, 255,   64, 128, 191, 4,
    ]
    #expect(bytes == expected)
    #expect(bytes == SDLIcon.straightRGBA(texture))
}

/// S3 — the first (smallest) texture is the primary, every other an
/// alternate: `SDL_GetSurfaceImages` lists three images, ascending. Mutation
/// MS6 (`add_alternate` skipped: one image).
@MainActor
@Test func anIconSurfaceCarriesEveryLargerTextureAsAnAlternate() throws {
    armed()
    let surface = try #require(SDLIcon.makeSurface([square(16), square(32), square(64)]))
    defer { mui_surface_destroy(surface) }
    var w: Int32 = 0, h: Int32 = 0
    mui_surface_size(surface, &w, &h)
    #expect(w == 16 && h == 16, "primary \(w)×\(h)")
    let count = mui_surface_image_count(surface)
    try #require(count == 3, "image count \(count)")
    var sizes: [Int32] = []
    for index in 0..<count {
        mui_surface_image_size(surface, index, &w, &h)
        #expect(w == h)
        sizes.append(w)
    }
    #expect(sizes == [16, 32, 64])
}

/// S4 — setting the icon applies it to every open window. `applied` is
/// `SDL_SetWindowIcon`'s answer: true on macOS (measured); a backend that
/// answers false (Wayland without `xdg-toplevel-icon-v1`) still records the
/// textures. Mutation MS7 (the first window only).
@MainActor
@Test func settingTheIconAppliesItToEveryOpenWindow() throws {
    let platform = try iconPlatform()
    let first = try openWindow(platform, "icon S4 a")
    let second = try openWindow(platform, "icon S4 b")
    let icon = [square(16), square(32)]
    platform.setApplicationIcon(icon)
    for window in [first, second] {
        let result = try #require(window.iconResult, "window \(window.id) has no icon result")
        #expect(result.textures == ids(icon))
        #if os(macOS)
        #expect(result.applied)
        #endif
    }
}

/// S5 — a window opened after the icon is set gets it: `openSDLWindow`
/// applies the stored icon (`AI-J`; `App` sends nothing on `openWindow`).
/// Mutation MS8 (`openSDLWindow` skips the stored icon).
@MainActor
@Test func aWindowOpenedAfterTheIconIsSetGetsIt() throws {
    let platform = try iconPlatform()
    let icon = [square(16), square(32), square(64)]
    platform.setApplicationIcon(icon)
    let window = try openWindow(platform, "icon S5")
    let result = try #require(window.iconResult, "the later window has no icon result")
    #expect(result.textures == ids(icon))
    #if os(macOS)
    #expect(result.applied)
    #endif
}

/// S6 — `[]` cannot clear on SDL (`AI-F` item 5): an open window keeps the
/// icon it had, a window opened afterwards gets none, and
/// `mui_window_set_icon` is never handed `NULL`. Mutation MS9 (a new window
/// gets the last non-empty icon).
@MainActor
@Test func clearingTheIconLeavesOpenWindowsAndGivesNewOnesNone() throws {
    let platform = try iconPlatform()
    let nullCalls = mui_window_set_icon_null_calls()
    let open = try openWindow(platform, "icon S6 open")
    let icon = [square(16)]
    platform.setApplicationIcon(icon)
    let before = try #require(open.iconResult, "the icon never reached the open window")
    #expect(before.textures == ids(icon))
    platform.setApplicationIcon([])
    let after = try #require(open.iconResult)
    #expect(after.textures == before.textures && after.applied == before.applied)
    let later = try openWindow(platform, "icon S6 later")
    #expect(later.iconResult == nil, "a window opened after [] got \(String(describing: later.iconResult))")
    #expect(mui_window_set_icon_null_calls() == nullCalls)
}

#if os(macOS)
import AppKit

/// S7 — SDL received the icon, observed from outside the wrapper: SDL's
/// Cocoa backend turns `SDL_SetWindowIcon`'s surface into
/// `NSApplication.applicationIconImage`, whose size is the primary
/// texture's (`AI-I`: the getter's size is the one fact that discriminates).
/// The getter is first reset to a 7 × 7 image, so the reading cannot be a
/// previous test's icon. Both paths: an open window (`setApplicationIcon`)
/// and a window opened later (`openSDLWindow`'s stored icon). S4/S5's
/// `applied` is only the wrapper's own return value; mutation V7 (the
/// wrapper returns `true` without calling `SDL_SetWindowIcon`) leaves them
/// green and reddens this.
@MainActor
@Test func sdlsCocoaBackendReceivesTheIconAsTheApplicationIcon() throws {
    let platform = try iconPlatform()
    let sentinel = NSSize(width: 7, height: 7)
    NSApplication.shared.applicationIconImage = NSImage(size: sentinel)
    _ = try openWindow(platform, "icon S7 open")
    #expect(NSApplication.shared.applicationIconImage?.size == sentinel)
    platform.setApplicationIcon([square(20), square(40)])
    #expect(NSApplication.shared.applicationIconImage?.size == NSSize(width: 20, height: 20),
            "after setApplicationIcon: \(String(describing: NSApplication.shared.applicationIconImage?.size))")
    NSApplication.shared.applicationIconImage = NSImage(size: sentinel)
    _ = try openWindow(platform, "icon S7 later")
    #expect(NSApplication.shared.applicationIconImage?.size == NSSize(width: 20, height: 20),
            "after a later window opened: \(String(describing: NSApplication.shared.applicationIconImage?.size))")
}
#endif
