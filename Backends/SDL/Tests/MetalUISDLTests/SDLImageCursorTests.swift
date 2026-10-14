import Testing
import MetalUICore
import MetalUIPlatform
import MetalUIScene
@testable import MetalUISDL
import SDLBridge

// Image cursors on SDL, tests 11-17 (rulings `IC-E`, `IC-H`, `IC-O`, `AI-F`; spec
// `docs/superpowers/specs/2026-10-14-cursors-headless-design.md` §5). A test cannot see the pointer, so
// the bridge's C recorders (`mui_cursor_*`, written in the production path) are read. They are
// process-global, so every test that reads one lives in one serialized suite and compares deltas.
// The bounded table is pure Swift (`IC-O`): tests 13-15's table arms use a counting fake. **No test is gated on
// the video driver**: the offscreen driver of CI's Linux image creates colour cursors (measured, `IC-R`).
// Every test that creates an `SDLPlatform` arms `armMainRunLoopExitCheck()` on macOS (record §61 §9).

@MainActor
private func armed() {
    #if os(macOS)
    armMainRunLoopExitCheck()
    #endif
}

@MainActor
private func cursorPlatform() throws -> SDLPlatform {
    armed()
    return try SDLPlatform(hiddenWindows: true)
}

@MainActor
private func openWindow(_ platform: SDLPlatform, _ title: String) throws -> SDLWindow {
    let window = try platform.openSDLWindow(title: title, size: Size(width: Pixels(64), height: Pixels(48)))
    platform.pumpEvents()
    return window
}

/// A `side` x `side` texture of premultiplied (100, 50, 25, 128); texel 0 carries `seed`.
private func texture(side: Int, seed: UInt8 = 100) -> ImageTexture {
    var bytes: [UInt8] = []
    for i in 0..<(side * side) { bytes += i == 0 ? [seed, 50, 25, 128] : [100, 50, 25, 128] }
    return ImageTexture(width: side, height: side, premultipliedRGBA: bytes)
}

private func cursorImage(side: Int, scale: Float = 1, seed: UInt8 = 100,
                         hotSpot: (x: Float, y: Float) = (0, 0)) -> PlatformCursorImage {
    PlatformCursorImage(texture: texture(side: side, seed: seed), scale: scale, hotSpot: hotSpot)
}

@Suite(.serialized) @MainActor
struct SDLImageCursorTests {
    /// **11** (`AI-F`). The surface handed to `SDL_CreateColorCursor` is straight alpha:
    /// premultiplied (100, 50, 25, 128) reads (199, 100, 50, 128), packed as the recorder returns it.
    /// Mutation: pass the premultiplied bytes.
    @Test func anSDLImageCursorIsCreatedFromStraightAlphaPixels() throws {
        let platform = try cursorPlatform()
        let window = try openWindow(platform, "IC11")
        defer { window.close() }
        let attempts = mui_cursor_attempt_count()
        window.setPointerStyle(.image(cursorImage(side: 4)))
        #expect(mui_cursor_attempt_count() == attempts + 1)
        #expect(mui_cursor_last_pixel(0) == (199 << 24 | 100 << 16 | 50 << 8 | 128),
                "\(String(mui_cursor_last_pixel(0), radix: 16))")
    }

    /// **12** (`IC-E` 1, 2). The hot spot is in surface pixels: `.center` on a 16 pt, scale 1 image is
    /// (8, 8); at scale 2 (a 32 px bitmap) the primary is the 16 px point-size image with hot spot
    /// (8, 8) and the bitmap rides as one alternate.
    /// Mutations: hot spot in bitmap pixels for the primary; drop the alternate.
    @Test func anSDLImageCursorGetsItsHotSpotInSurfacePixels() throws {
        let platform = try cursorPlatform()
        let window = try openWindow(platform, "IC12")
        defer { window.close() }
        window.setPointerStyle(.image(cursorImage(side: 16, seed: 1, hotSpot: (8, 8))))
        #expect(mui_cursor_last_width() == 16 && mui_cursor_last_height() == 16)
        #expect(mui_cursor_last_hot_x() == 8 && mui_cursor_last_hot_y() == 8)
        #expect(mui_cursor_last_alternate_count() == 0)
        window.setPointerStyle(.image(cursorImage(side: 32, scale: 2, seed: 2, hotSpot: (8, 8))))
        #expect(mui_cursor_last_width() == 16 && mui_cursor_last_height() == 16, "the primary is the point size")
        #expect(mui_cursor_last_hot_x() == 8 && mui_cursor_last_hot_y() == 8)
        #expect(mui_cursor_last_alternate_count() == 1)
    }

    /// **16** (`CI-H` item 8, `IC-H`). The old styles stay on system cursors: the table is unchanged
    /// and no colour cursor is attempted for a grab or a zoom.
    /// Mutation: map `.zoomIn` through the image path.
    @Test func grabAndZoomStayOnSystemCursors() throws {
        let platform = try cursorPlatform()
        let window = try openWindow(platform, "IC16")
        defer { window.close() }
        #expect(SDLCursorTable.systemCursor(for: .openHand) == .move)
        #expect(SDLCursorTable.systemCursor(for: .closedHand) == .move)
        #expect(SDLCursorTable.systemCursor(for: .zoomIn) == .default)
        #expect(SDLCursorTable.systemCursor(for: .zoomOut) == .default)
        let attempts = mui_cursor_attempt_count()
        for style: PlatformPointerStyle in [.openHand, .closedHand, .zoomIn, .zoomOut, .pointingHand] {
            window.setPointerStyle(style)
        }
        #expect(mui_cursor_attempt_count() == attempts)
    }

    /// **17** (`IC-E` 4). The platform does not `SDL_SetCursor` the cursor it already shows: the same
    /// image twice sets once.     /// Mutation: drop the skip.
    @Test func anImageCursorIsNotSetTwiceForTheSameStyle() throws {
        let platform = try cursorPlatform()
        let window = try openWindow(platform, "IC17")
        defer { window.close() }
        let image = cursorImage(side: 8, seed: 17)
        let sets = mui_cursor_set_count()
        window.setPointerStyle(.image(image))
        window.setPointerStyle(.image(image))
        #expect(mui_cursor_set_count() == sets + 1, "\(mui_cursor_set_count() - sets)")
    }

    /// **15, platform arm** (`IC-E` 3). Closing the last window destroys every image cursor; a second
    /// open window keeps them until it closes too.     /// Mutation: destroy on any window close; never destroy.
    @Test func closingTheLastWindowDestroysEveryImageCursor() throws {
        let platform = try cursorPlatform()
        let first = try openWindow(platform, "IC15a")
        let second = try openWindow(platform, "IC15b")
        let live = mui_cursor_live_count()
        first.setPointerStyle(.image(cursorImage(side: 8, seed: 31)))
        first.setPointerStyle(.image(cursorImage(side: 8, seed: 32)))
        try #require(mui_cursor_live_count() == live + 2, "premise: two cursors live")
        first.close()
        #expect(mui_cursor_live_count() == live + 2, "a window is still open")
        second.close()
        #expect(mui_cursor_live_count() == live, "the last close destroys them")
    }
}

/// A counting fake for the pure table: handles are ints.
@MainActor
private final class Counter {
    var created: [Int] = [], destroyed: [Int] = []
    var next = 100
    func table(capacity: Int = 8) -> SDLImageCursorTable<Int, Int> {
        SDLImageCursorTable(capacity: capacity,
                            create: { _ in self.next += 1; self.created.append(self.next); return self.next },
                            destroy: { self.destroyed.append($0) })
    }
}

/// **13** (`IC-E` 3, `IC-O`). A returned image reuses its cursor: A, B, A creates two. Ungated.
/// Mutation: no table (create every time).
@MainActor @Test func aReturnedImageReusesItsCursor() {
    let counter = Counter()
    var table = counter.table()
    let a1 = table.handle(for: 1, current: nil)
    _ = table.handle(for: 2, current: nil)
    let a2 = table.handle(for: 1, current: nil)
    #expect(a1 == a2 && a1 != nil)
    #expect(counter.created.count == 2)
    #expect(counter.destroyed.isEmpty)
}

/// **14** (`IC-E` 3, `IC-O`). The ninth image evicts the least recently used cursor and never the one
/// SDL shows: a current one is parked and destroyed at its next replacement. Ungated.
/// Mutations: no bound; evict the current.
@MainActor @Test func theNinthImageEvictsTheLeastRecentlyUsedAndNeverTheCurrent() {
    let counter = Counter()
    var table = counter.table()
    var handles: [Int] = []
    for key in 1...8 { handles.append(table.handle(for: key, current: nil)!) }
    _ = table.handle(for: 9, current: nil)
    #expect(counter.destroyed == [handles[0]], "the least recently used (key 1)")
    #expect(table.count == 8)

    // Key 2 is now the least recently used, and SDL shows it: parked, not destroyed.
    _ = table.handle(for: 10, current: handles[1])
    #expect(!counter.destroyed.contains(handles[1]), "the current cursor is never destroyed")
    #expect(counter.destroyed.count == 1, "\(counter.destroyed)")
    #expect(table.count == 8)
    #expect(table.parkedCount == 1)
    // Replaced by another cursor: the parked one goes.
    table.sweepParked(current: nil)
    #expect(counter.destroyed.contains(handles[1]))
    #expect(table.parkedCount == 0)
}

/// **15, table arm** (`IC-E` 3, `IC-O`). `removeAll()` destroys every cursor, parked ones included. Ungated.
/// Mutation: `removeAll()` skips the parked ones.
@MainActor @Test func removingEveryCursorDestroysTheParkedOnesToo() throws {
    let counter = Counter()
    var table = counter.table(capacity: 2)
    let first = table.handle(for: 1, current: nil)!
    _ = table.handle(for: 2, current: nil)
    _ = table.handle(for: 3, current: first)   // evicts 1, which is shown: parked
    try #require(table.parkedCount == 1, "premise: one parked")
    table.removeAll()
    #expect(counter.destroyed.sorted() == counter.created.sorted(), "\(counter.destroyed) vs \(counter.created)")
    #expect(table.count == 0 && table.parkedCount == 0)
}
