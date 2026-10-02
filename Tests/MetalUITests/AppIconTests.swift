import Testing
import Metal
import MetalUICore
import MetalUIPlatform
import MetalUIDemoContent
@testable import MetalUI

// App icon, lane 1, tests 1.1–1.7 (rulings `AI-A`, `AI-C`, `AI-G`, `AI-J`;
// spec §5). `App.icon`'s contract with the platform, pinned against
// `FakePlatform`, which records every `setApplicationIcon` call; and the demo's
// generated icon (spec §3).

/// A bitmap of one opaque colour, `width × height`.
private func solid(_ width: Int, _ height: Int, _ value: UInt8 = 200) -> ImageBitmap {
    ImageBitmap(width: width, height: height,
                rgba: [UInt8](repeating: value, count: width * height * 4))
}

/// The identities of a list of textures, for an `==` that cannot be fooled by
/// equal bytes in a copy (mutation M1c).
private func ids(_ textures: [ImageTexture]) -> [ObjectIdentifier] {
    textures.map(ObjectIdentifier.init)
}

private func ids(_ bitmaps: [ImageBitmap]) -> [ObjectIdentifier] {
    bitmaps.map { ObjectIdentifier($0.texture) }
}

@MainActor
private func makeApp() throws -> (App, FakePlatform) {
    let device = try #require(MTLCreateSystemDefaultDevice(), "no Metal device; run on macOS hardware")
    let platform = FakePlatform(device: device)
    return (App(platform: platform), platform)
}

@MainActor
private func openWindow(_ app: App) throws {
    try app.openWindow(title: "Icon", size: Size(width: Pixels(64), height: Pixels(64)),
                       startsDisplayLink: false) {
        Box().frame(width: Pixels(10), height: Pixels(10)).background(.accent)
    }
}

/// **1.1** (`AI-C` item 1). An `App` that never assigns `icon` never calls the
/// platform — not at construction, not when a window opens — so a bundled
/// app's own icon is never overwritten by an empty list at launch.
///
/// Mutation **M1a**: `App.init` calls `setApplicationIcon([])`.
@MainActor
@Test func anAppThatNeverSetsAnIconNeverCallsThePlatform() throws {
    let (app, platform) = try makeApp()
    try openWindow(app)
    try #require(platform.openedWindows.count == 1)
    #expect(platform.iconCalls.isEmpty, "calls: \(platform.iconCalls.map(ids))")
}

/// **1.2** (`AI-C` items 2–3, `AI-J`). One assignment is one call, carrying the
/// bitmaps' own textures (identical objects, no copy). A window opened after
/// the assignment adds no second call: applying the icon to windows opened
/// later is the platform's job (`AI-J`), not `App`'s.
///
/// Mutations **M1b** (`didSet` removed), **M1c** (passes copies built from the
/// same pixels), **M1m** (`App.openWindow` re-sends `icon`).
@MainActor
@Test func settingTheAppIconReachesThePlatformOnceWithTheBitmapsOwnTextures() throws {
    let (app, platform) = try makeApp()
    let bitmaps = [solid(16, 16), solid(32, 32)]
    app.icon = bitmaps
    try openWindow(app)
    try #require(platform.openedWindows.count == 1)
    try #require(platform.iconCalls.count == 1, "calls: \(platform.iconCalls.map(ids))")
    #expect(ids(platform.iconCalls[0]) == ids(bitmaps))
}

/// **1.3** (`AI-C` item 3). The platform receives the list sorted by area,
/// smallest first and stable, with a later bitmap repeating an earlier
/// `width × height` dropped — the first written wins. Assigned
/// [32², 16², 32²′, 8×64] (areas 1024, 256, 1024, 512), the call holds
/// 16², 8×64, 32² — the first 32², not 32²′.
///
/// Mutations **M1d** (no sort), **M1e** (no dedupe), **M1f** (dedupe keeps the
/// last).
@MainActor
@Test func theAppIconReachesThePlatformSmallestFirstWithoutRepeatedSizes() throws {
    let (app, platform) = try makeApp()
    let first32 = solid(32, 32, 10)
    let small = solid(16, 16)
    let second32 = solid(32, 32, 20)
    let tall = solid(8, 64)
    app.icon = [first32, small, second32, tall]
    try #require(platform.iconCalls.count == 1)
    #expect(ids(platform.iconCalls[0]) == ids([small, tall, first32]),
            "sizes: \(platform.iconCalls[0].map { "\($0.width)×\($0.height)" })")
}

/// **1.4** (`AI-C` item 4). `icon` reads back exactly what was assigned —
/// unsorted, the repeated size kept — the normalization is the platform's
/// contract, not the property's value.
///
/// Mutation **M1g**: store the normalized list.
@MainActor
@Test func theAppIconReadsBackExactlyAsAssigned() throws {
    let (app, _) = try makeApp()
    let assigned = [solid(32, 32, 10), solid(16, 16), solid(32, 32, 20), solid(8, 64)]
    app.icon = assigned
    #expect(ids(app.icon) == ids(assigned))
}

/// **1.5** (`AI-C` item 2). Every assignment is a call — no equality or count
/// short-circuit — and `[]` is passed on as `[]` (the platform restores its own
/// icon as far as it can).
///
/// Mutations **M1h** (short-circuit on an equal count: `[a]` then `[b]`),
/// **M1i** (skip the call for `[]`).
@MainActor
@Test func settingTheAppIconAgainReplacesItAndClearingPassesAnEmptyList() throws {
    let (app, platform) = try makeApp()
    let a = solid(16, 16, 10)
    let b = solid(16, 16, 20)
    app.icon = [a]
    app.icon = [b]
    app.icon = []
    try #require(platform.iconCalls.count == 3, "calls: \(platform.iconCalls.map(ids))")
    #expect(ids(platform.iconCalls[0]) == ids([a]))
    #expect(ids(platform.iconCalls[1]) == ids([b]))
    #expect(platform.iconCalls[2].isEmpty)
}

/// **1.6** (`AI-G`). The demo's icon is six square bitmaps, 16 to 512 px, in
/// that order.
///
/// Mutation **M1j**: drop the 512.
@MainActor
@Test func theDemoIconIsSixSquareBitmapsFrom16To512() {
    let icon = demoIcon()
    #expect(icon.map(\.width) == [16, 32, 64, 128, 256, 512])
    #expect(icon.map(\.height) == [16, 32, 64, 128, 256, 512])
}

/// **1.7** (`AI-G`, spec §3). Each pixel is classified by its centre
/// `(x + 0.5, y + 0.5)`: outside the rounded square `[0, s]²` (corner radius
/// `0.22 s`) clear; inside the disc about `(s/2, s/2)` of radius `0.28 s`
/// white; else `#2F6FEB`. At `s = 16` (disc radius 4.48 about (8, 8); corner
/// radius 3.52 about (3.52, 3.52)):
///
/// - `(0,0)`, `(15,15)` clear; `(8,8)` white; `(1,8)` accent;
/// - `(3,8)` accent — centre distance √(4.5² + 0.5²) = 4.528 > 4.48; at radius
///   0.30 s = 4.8 it would be white (**M1k**);
/// - `(4,8)` white (3.536);
/// - `(0,1)` clear — distance to the corner centre √(3.02² + 2.02²) = 3.63 >
///   3.52; at corner radius 0.18 s = 2.88 the distance to (2.88, 2.88) is
///   √(2.38² + 1.38²) = 2.75 < 2.88, so it would be accent (**M1l**);
/// - `(1,1)` accent (2.857).
///
/// And at 512: the centre white, `(0,0)` clear. The bitmaps' alpha is 0 or 255,
/// so their stored (premultiplied) bytes equal the written ones.
@MainActor
@Test func theDemoIconsPixelsAreTheSpecifiedShape() throws {
    let icon = demoIcon()
    let s16 = try #require(icon.first { $0.width == 16 })
    let s512 = try #require(icon.first { $0.width == 512 })
    func pixel(_ bitmap: ImageBitmap, _ x: Int, _ y: Int) -> [UInt8] {
        let i = (y * bitmap.width + x) * 4
        return Array(bitmap.texture.pixels[i..<(i + 4)])
    }
    let clear: [UInt8] = [0, 0, 0, 0]
    let white: [UInt8] = [255, 255, 255, 255]
    let accent: [UInt8] = [47, 111, 235, 255]
    #expect(pixel(s16, 0, 0) == clear)
    #expect(pixel(s16, 15, 15) == clear)
    #expect(pixel(s16, 8, 8) == white)
    #expect(pixel(s16, 1, 8) == accent)
    #expect(pixel(s16, 3, 8) == accent)
    #expect(pixel(s16, 4, 8) == white)
    #expect(pixel(s16, 0, 1) == clear)
    #expect(pixel(s16, 1, 1) == accent)
    #expect(pixel(s512, 256, 256) == white)
    #expect(pixel(s512, 0, 0) == clear)
}
