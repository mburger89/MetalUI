import Foundation
import Testing
import MetalUICore
import MetalUIPlatform
@testable import MetalUISDL
import SDLBridge

// SDL custom window chrome, lane 2 (item S1; rulings `CW-B`, `CW-D`, `CW-E`, `CW-G`, `CW-H`, `CW-I`, `CW-O`,
// `CW-S`; spec `docs/superpowers/specs/2026-10-13-sdl-chrome-design.md`). A real hidden `SDLPlatform`
// window. No test needs a presented frame; the ones that read the window manager's maximise or minimise
// flags are gated on a driver that implements them (the offscreen driver does not). A real drag or resize
// is human check group CW; what is pinned here is the hit-test callback's answer, called through the same
// locked-copy function SDL's callback calls (`mui_window_chrome_hit`), and the C function against the Swift
// specification (`ChromeHitSnapshot.hit(at:)`) over a table. Red before: the file does not compile at
// `0c61b352` (no `mui_window_set_bordered`, no snapshot, no chrome members on `SDLWindow`).

@MainActor
private func chromePlatform(size: Size<Pixels> = Size(width: Pixels(400), height: Pixels(300)))
    throws -> (SDLPlatform, SDLWindow) {
    #if os(macOS)
    armMainRunLoopExitCheck()
    #endif
    let platform = try SDLPlatform(hiddenWindows: true)
    let window = try platform.openSDLWindow(title: "MetalUI chrome test", size: size)
    platform.pumpEvents()
    return (platform, window)
}

private func bounds(_ x: Float, _ y: Float, _ w: Float, _ h: Float) -> Bounds<Pixels> {
    Bounds(origin: Point(x: Pixels(x), y: Pixels(y)), size: Size(width: Pixels(w), height: Pixels(h)))
}

private func point(_ x: Float, _ y: Float) -> Point<Pixels> { Point(x: Pixels(x), y: Pixels(y)) }

@MainActor private func pushResize(_ window: SDLWindow) {
    var event = MUIEvent(); event.kind = UInt32(MUI_EVENT_RESIZE); event.window_id = window.id
    #expect(mui_push_event(&event))
}

/// The video drivers whose windows implement minimise, maximise and the flags that report them. The
/// offscreen driver (CI's Linux image) has no window manager.
private let windowManagerDriver = ProcessInfo.processInfo.environment["SDL_VIDEO_DRIVER"] != "offscreen"

// MARK: Style

/// **2.1** (`CW-B`). `.hidden` makes the window borderless (`SDL_WINDOW_BORDERLESS`, read through the bridge) and
/// answers `true`; every request is recorded.
/// Mutation: the bridge passes `true` to `SDL_SetWindowBordered` for `.hidden` -> red.
@MainActor
@Test func hiddenStyleMakesTheWindowBorderlessAndAnswersTrue() throws {
    let (_, window) = try chromePlatform()
    #expect(window.isBorderless == false)
    #expect(window.setTitleBarStyle(.hidden) == true)
    #expect(window.isBorderless == true)
    #expect(window.titleBarStyles == [.hidden])
}

/// **2.2** (`CW-B`). `.standard` restores the border and answers `true`.
/// Mutation: `.standard` does nothing -> red.
@MainActor
@Test func standardStyleRestoresTheBorder() throws {
    let (_, window) = try chromePlatform()
    _ = window.setTitleBarStyle(.hidden)
    #expect(window.setTitleBarStyle(.standard) == true)
    #expect(window.isBorderless == false)
    #expect(window.titleBarStyles == [.hidden, .standard])
}

/// **2.3** (`CW-S`). A style requested while the window is fullscreen is recorded, answered `true`, and applied
/// on leaving fullscreen — the last request wins, and a later leave re-applies nothing twice.
/// Mutation: the leave handler does not re-apply -> red.
@MainActor
@Test func leavingFullscreenAppliesTheLastRequestedStyle() throws {
    let (platform, window) = try chromePlatform()
    window.fullscreenOverride = true
    #expect(window.setTitleBarStyle(.hidden) == true, "recorded for the leave")
    #expect(window.isBorderless == false, "SDL cannot change a fullscreen window's border")
    #expect(window.titleBarInsets == Edges(all: Pixels(0)))
    window.fullscreenOverride = false
    pushResize(window)
    platform.pumpEvents()
    #expect(window.isBorderless == true, "applied on leaving fullscreen")
    window.fullscreenOverride = true
    #expect(window.setTitleBarStyle(.standard) == true)
    window.fullscreenOverride = false
    pushResize(window)
    platform.pumpEvents()
    #expect(window.isBorderless == false, "the last request wins")
}

// MARK: Insets

/// **2.4** (`CW-D`). The hidden style reads the band (32) and the cluster edge — 138 on the right on Linux and
/// Windows, 70 on the left through macOS — zero before the style, after `.standard` and in fullscreen.
/// Mutation: the cluster on the wrong side, or the band 30 -> red.
@MainActor
@Test func insetsAreBandPlusClusterPerPlatformAndZeroInFullscreen() throws {
    let (_, window) = try chromePlatform()
    #expect(window.titleBarInsets == Edges(all: Pixels(0)))
    _ = window.setTitleBarStyle(.hidden)
    let expected: Edges<Pixels>
    #if os(macOS)
    expected = Edges(top: Pixels(32), right: Pixels(0), bottom: Pixels(0), left: Pixels(70))
    #else
    expected = Edges(top: Pixels(32), right: Pixels(138), bottom: Pixels(0), left: Pixels(0))
    #endif
    #expect(window.titleBarInsets == expected)
    window.fullscreenOverride = true
    #expect(window.titleBarInsets == Edges(all: Pixels(0)), "fullscreen has no band")
    window.fullscreenOverride = false
    _ = window.setTitleBarStyle(.standard)
    #expect(window.titleBarInsets == Edges(all: Pixels(0)))
}

/// **2.5** (`CW-S`). The platform has no native window buttons (`Window` draws them).
@MainActor
@Test func theWindowHasNoNativeControls() throws {
    let (_, window) = try chromePlatform()
    #expect(window.hasNativeWindowControls == false)
}

// MARK: The hit test

private struct Row { let snapshot: ChromeHitSnapshot; let name: String }

private func table() -> [Row] {
    let regions = [bounds(0, 0, 262, 32), bounds(300, 0, 100, 10), bounds(50, 100, 80, 40)]
    return [
        Row(snapshot: ChromeHitSnapshot(size: Size(width: Pixels(400), height: Pixels(300)), dragRegions: regions,
                                        borderless: true), name: "borderless, regions"),
        Row(snapshot: ChromeHitSnapshot(size: Size(width: Pixels(400), height: Pixels(300)), dragRegions: regions,
                                        borderless: false), name: "bordered, regions"),
        Row(snapshot: ChromeHitSnapshot(size: Size(width: Pixels(400), height: Pixels(300)), dragRegions: regions,
                                        borderless: true, zoomedOrFullscreen: true), name: "zoomed"),
        Row(snapshot: ChromeHitSnapshot(size: Size(width: Pixels(400), height: Pixels(300)), dragRegions: regions,
                                        borderless: true, resizableHorizontally: false), name: "fixed width"),
        Row(snapshot: ChromeHitSnapshot(size: Size(width: Pixels(400), height: Pixels(300)), dragRegions: regions,
                                        borderless: true, resizableVertically: false), name: "fixed height"),
        Row(snapshot: ChromeHitSnapshot(size: Size(width: Pixels(640), height: Pixels(480)), dragRegions: regions,
                                        borderless: true), name: "resized to 640x480"),
        Row(snapshot: ChromeHitSnapshot(size: Size(width: Pixels(20), height: Pixels(20)), borderless: true),
            name: "smaller than two corners")
    ]
}

private func bridged(_ snapshot: ChromeHitSnapshot) -> MUIChromeSnapshot {
    var c = MUIChromeSnapshot()
    mui_chrome_snapshot_init(&c, snapshot.size.width.value, snapshot.size.height.value, snapshot.borderless,
                             snapshot.zoomedOrFullscreen, snapshot.resizableHorizontally,
                             snapshot.resizableVertically)
    for r in snapshot.dragRegions {
        #expect(mui_chrome_snapshot_add_rect(&c, r.origin.x.value, r.origin.y.value, r.size.width.value,
                                             r.size.height.value))
    }
    return c
}

private func sample(_ low: Float, _ high: Float, steps: Int = 36) -> [Float] {
    // Whole and half points, the boundaries of every rect, border and corner (6, 12, 262, ...) included.
    var values: Set<Float> = [low - 1, low, low + 0.5, high - 0.5, high - 1, high, high + 1]
    for edge: Float in [0, 5, 6, 11, 12, 32, 50, 100, 130, 140, 262, 300, 400, 640, 20, 10, 480, 300] {
        for d: Float in [-1, 0, 1] { values.insert(edge + d) }
    }
    for i in 0..<steps { values.insert(low + (high - low) * Float(i) / Float(steps)) }
    return values.sorted()
}

/// **2.6** (`CW-H`). The C function (`mui_chrome_hit`) agrees with the Swift specification
/// (`ChromeHitSnapshot.hit(at:)`) over a table of snapshots (borderless, bordered, zoomed, a fixed axis, a
/// resized window, a window smaller than two corners) and a grid of points that includes every rect, border
/// and corner boundary and a point outside the window.
/// Mutation: one C comparison `<` to `<=` (the right edge, the drag rect's max) -> red.
@MainActor
@Test func theBridgeCallbackAgreesWithTheSwiftReferenceOverATable() throws {
    var checked = 0
    for row in table() {
        var c = bridged(row.snapshot)
        for x in sample(-2, row.snapshot.size.width.value + 2) {
            for y in sample(-2, row.snapshot.size.height.value + 2) {
                let swift = row.snapshot.hit(at: point(x, y))
                let raw = mui_chrome_hit(&c, x, y)
                #expect(SDLChrome.hit(fromBridge: raw) == swift, "\(row.name) at (\(x), \(y)): C \(raw), Swift \(swift)")
                checked += 1
            }
        }
    }
    #expect(checked > 10_000, "the table is not empty: \(checked)")
}

/// **2.7** (`CW-G`, `CW-E`). The C copy has the Swift constants: the 6-point border and the 64-rect cap; a
/// 65th rect is refused.
/// Mutation: C border 6 -> 7, or a cap of 65 -> red.
@MainActor
@Test func theConstantsAreTheSwiftSpecifications() throws {
    #expect(mui_chrome_resize_border() == ChromeHitSnapshot.resizeBorder)
    #expect(Int(mui_chrome_max_rects()) == ChromeHitSnapshot.maximumRegions)
    var c = MUIChromeSnapshot()
    mui_chrome_snapshot_init(&c, 100, 100, true, false, true, true)
    for _ in 0..<ChromeHitSnapshot.maximumRegions { #expect(mui_chrome_snapshot_add_rect(&c, 0, 0, 1, 1)) }
    #expect(mui_chrome_snapshot_add_rect(&c, 0, 0, 1, 1) == false, "a 65th rect is refused")
}

/// **2.8** (`CW-E`, `CW-G`, `CW-J`). Through a real window: the regions `Window` published answer through the
/// installed callback's locked-copy path; a point outside them is normal; the border resizes only while the
/// window is borderless.
/// Mutation: the callback ignores `borderless` -> red.
@MainActor
@Test func theInstalledCallbackAnswersFromThePublishedRegions() throws {
    let (_, window) = try chromePlatform()
    #expect(window.setTitleBarStyle(.hidden))
    #expect(window.setWindowDragRegions([bounds(0, 0, 262, 32)]) == true)
    #expect(window.hitTestInstalled)
    #expect(window.chromeHit(at: point(100, 20)) == .draggable)
    #expect(window.chromeHit(at: point(300, 20)) == .normal)
    #expect(window.chromeHit(at: point(2, 2)) == .resizeTopLeft)
    #expect(window.chromeHit(at: point(399, 150)) == .resizeRight)
    #expect(window.chromeHit(at: point(200, 150)) == .normal)
    _ = window.setTitleBarStyle(.standard)
    #expect(window.chromeHit(at: point(399, 150)) == .normal, "a bordered window resizes by its system frame")
    #expect(window.chromeHit(at: point(100, 20)) == .draggable, "the regions stay")
}

/// **2.9** (`CW-M` 2). A resize event refreshes the snapshot's size under the lock, so the edges follow the
/// new size before `Window` rebuilds.
/// Mutation: no refresh on a resize event -> red.
@MainActor
@Test func aResizeRefreshesTheSnapshotSize() throws {
    let (platform, window) = try chromePlatform()
    _ = window.setTitleBarStyle(.hidden)
    _ = window.setWindowDragRegions([])
    #expect(window.chromeHit(at: point(399, 150)) == .resizeRight)
    mui_window_set_size(window.rawHandle, 640, 480)
    pushResize(window)
    platform.pumpEvents()
    var w: Int32 = 0, h: Int32 = 0
    mui_window_size(window.rawHandle, &w, &h)
    try #require(w > 400 && h > 300, "the window grew: \(w)x\(h)")
    #expect(window.chromeHit(at: point(399, 150)) == .normal, "the old edge is now inside")
    #expect(window.chromeHit(at: point(Float(w) - 1, 150)) == .resizeRight)
}

/// **2.10** (`CW-J`). A window that never asked for chrome never installs a callback: a standard window with no
/// regions, and one asked once with `[]` (`Window`'s first ask), which still answers `true` (the platform
/// uses regions; none are needed yet).
/// Mutation: install on every publish -> red.
@MainActor
@Test func aPlainWindowNeverInstallsOne() throws {
    let (_, window) = try chromePlatform()
    #expect(window.hitTestInstalled == false)
    #expect(window.setWindowDragRegions([]) == true)
    #expect(window.hitTestInstalled == false)
    #expect(window.windowDragRegions.isEmpty)
    var publishes: UInt32 = 0, copies: UInt32 = 0, locks: UInt32 = 0
    mui_window_chrome_counters(window.rawHandle, &publishes, &copies, &locks)
    #expect(publishes == 0 && locks == 0, "no publish reached the bridge: \(publishes), \(locks)")
}

/// **2.11** (`CW-J`). A window whose edges and regions both end clears the callback: `.standard` with an empty
/// list clears it; regions on a standard window (a `WindowDragGesture` handle) install it again.
/// Mutation: never clear -> red.
@MainActor
@Test func clearingTheRegionsAndEdgesRemovesTheCallback() throws {
    let (_, window) = try chromePlatform()
    _ = window.setTitleBarStyle(.hidden)
    #expect(window.hitTestInstalled, "a borderless window has edges")
    _ = window.setWindowDragRegions([bounds(0, 0, 10, 10)])
    _ = window.setTitleBarStyle(.standard)
    #expect(window.hitTestInstalled, "regions still ask for it")
    #expect(window.chromeHit(at: point(5, 5)) == .draggable)
    _ = window.setWindowDragRegions([])
    #expect(window.hitTestInstalled == false, "no edges and no regions: cleared")
    #expect(window.chromeHit(at: point(5, 5)) == .normal)
    _ = window.setWindowDragRegions([bounds(0, 0, 10, 10)])
    #expect(window.hitTestInstalled, "installed again")
}

/// **2.12** (`CW-E`). More than 64 regions are cut at 64 by the platform too (a platform never trusts its caller
/// with a fixed array).
/// Mutation: copy without the cap -> red (a trap or an overrun).
@MainActor
@Test func moreThanSixtyFourRegionsAreCutAtSixtyFour() throws {
    let (_, window) = try chromePlatform()
    _ = window.setTitleBarStyle(.hidden)
    let many = (0..<70).map { bounds(Float($0) * 5, 100, 4, 4) }
    #expect(window.setWindowDragRegions(many) == true)
    #expect(window.chromeHit(at: point(63 * 5 + 1, 101)) == .draggable)
    #expect(window.chromeHit(at: point(64 * 5 + 1, 101)) == .normal, "the 65th is not draggable")
}

// MARK: Threads and the lock

/// **2.13** (`CW-O`). The lock is held across the publish's copy and across the callback's: a bridge counter
/// of lock/unlock pairs moves once per publish and once per callback call. Deterministic; the two-thread test
/// below is a smoke run.
/// Mutation: remove the lock calls from publish or from the callback's copy -> red.
@MainActor
@Test func thePublishAndTheCallbackEachHoldTheLockOnce() throws {
    let (_, window) = try chromePlatform()
    _ = window.setTitleBarStyle(.hidden)
    _ = window.setWindowDragRegions([bounds(0, 0, 100, 32)])
    let raw = window.rawHandle
    var publishes: UInt32 = 0, copies: UInt32 = 0, locks: UInt32 = 0
    mui_window_chrome_counters(raw, &publishes, &copies, &locks)
    let (p0, c0, l0) = (publishes, copies, locks)
    _ = window.setWindowDragRegions([bounds(0, 0, 100, 32), bounds(200, 0, 50, 32)])
    mui_window_chrome_counters(raw, &publishes, &copies, &locks)
    #expect(publishes == p0 + 1 && copies == c0 && locks == l0 + 1, "one publish: \(publishes), \(copies), \(locks)")
    for _ in 0..<5 { _ = window.chromeHit(at: point(10, 10)) }
    mui_window_chrome_counters(raw, &publishes, &copies, &locks)
    #expect(copies == c0 + 5 && locks == l0 + 6, "five callbacks, five locked copies: \(copies), \(locks)")
}

/// **2.14** (`CW-H`, smoke; not a mutation killer, `CW-O`). Two threads: one publishes alternating snapshots,
/// the other calls the callback's path 10^5 times; every answer is one of the two snapshots' known answers
/// at a probe point, never a torn mix.
@MainActor
@Test func aConcurrentPublishNeverTearsAnAnswer() async throws {
    let (_, window) = try chromePlatform()
    _ = window.setTitleBarStyle(.hidden)
    let a = [bounds(0, 0, 200, 32)], b = [bounds(300, 200, 50, 50)]
    _ = window.setWindowDragRegions(a)
    let raw = UInt(bitPattern: window.rawHandle)
    let stop = ManagedAtomicFlag()
    let reader = Task.detached { () -> Int in
        var bad = 0
        let handle = UnsafeMutableRawPointer(bitPattern: raw)
        for _ in 0..<100_000 {
            // Probe 1 is draggable only under `a`, probe 2 only under `b`; both are never draggable at once.
            let p1 = mui_window_chrome_hit(handle, 100, 10), p2 = mui_window_chrome_hit(handle, 320, 220)
            let d1 = p1 == Int32(MUI_CHROME_HIT_DRAGGABLE), d2 = p2 == Int32(MUI_CHROME_HIT_DRAGGABLE)
            if d1 && d2 { bad += 1 }
        }
        stop.set()
        return bad
    }
    var flip = false
    while !stop.isSet {
        _ = window.setWindowDragRegions(flip ? a : b)
        flip.toggle()
        await Task.yield()
    }
    #expect(await reader.value == 0)
}

private final class ManagedAtomicFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false
    func set() { lock.lock(); value = true; lock.unlock() }
    var isSet: Bool { lock.lock(); defer { lock.unlock() }; return value }
}

// MARK: Actions

/// **2.15** (`CW-F`). `performWindowAction` sends minimise, and maximise then restore, to the window manager
/// and `isZoomed` reads the flag. Gated: the offscreen driver has no window manager. SDL answers true when it
/// accepted the call.
/// Mutation: `.toggleZoom` always maximises, or `.minimize` calls maximise -> red.
@MainActor
@Test(.enabled(if: windowManagerDriver, "the offscreen video driver has no window manager"))
func performWindowActionSendsMinimizeAndZoomRestore() throws {
    let (platform, window) = try chromePlatform()
    #expect(window.isZoomed == false)
    #expect(window.performWindowAction(.toggleZoom) == true)
    for _ in 0..<20 where !window.isZoomed { platform.pumpEvents(); Thread.sleep(forTimeInterval: 0.01) }
    #expect(window.windowActions == [.toggleZoom])
    #expect(window.isZoomed == true)
    #expect(window.performWindowAction(.toggleZoom) == true)
    for _ in 0..<20 where window.isZoomed { platform.pumpEvents(); Thread.sleep(forTimeInterval: 0.01) }
    #expect(window.isZoomed == false)
    #expect(window.performWindowAction(.minimize) == true)
    #expect(window.windowActions == [.toggleZoom, .toggleZoom, .minimize])
}

/// **2.16** (`CW-I`). A press with a click count of two toggles zoom and answers `true`; a count of one answers
/// `false` and does nothing (the hit test dragged). Needs no window manager: the action is recorded and its
/// answer is the platform's.
/// Mutation: ignore the count, or answer `true` for one -> red.
@MainActor
@Test func aDoubleClickPressTogglesZoom() throws {
    let (_, window) = try chromePlatform()
    #expect(window.performTitleBarPress(clickCount: 1) == false)
    #expect(window.windowActions.isEmpty)
    let answer = window.performTitleBarPress(clickCount: 2)
    #expect(window.windowActions == [.toggleZoom])
    #expect(answer == window.lastWindowActionAnswer)
    #expect(window.titleBarPresses == [1, 2])
}

/// **2.17** (`WD-F`, divergence 276 amended). `performWindowDrag()` still records and answers `false`: a handle
/// moves the window through a region, not through the gesture.
/// Mutation: answer `true` -> red.
@MainActor
@Test func performWindowDragStillRecordsAndAnswersFalse() throws {
    let (_, window) = try chromePlatform()
    #expect(window.performWindowDrag() == false)
    #expect(window.windowDragRequests == 1)
}

/// **2.18** (`CW-E`). Zoomed or fullscreen: no edges, but the regions stay (the band drags a maximised window
/// on Windows, which restores it).
/// Mutation: the zoomed flag ignored by the publish -> red.
@MainActor
@Test func aFullscreenWindowHasNoEdges() throws {
    let (platform, window) = try chromePlatform()
    _ = window.setTitleBarStyle(.hidden)
    _ = window.setWindowDragRegions([bounds(0, 0, 262, 32)])
    #expect(window.chromeHit(at: point(399, 150)) == .resizeRight)
    window.fullscreenOverride = true
    pushResize(window)
    platform.pumpEvents()
    #expect(window.chromeHit(at: point(399, 150)) == .normal)
    #expect(window.chromeHit(at: point(100, 20)) == .draggable)
}

/// **2.19** (`SV-B`, `CW-G`). A window whose limits make an axis fixed has no edge on it.
/// Mutation: limits ignored by the publish -> red.
@MainActor
@Test func aFixedAxisHasNoEdge() throws {
    let (_, window) = try chromePlatform()
    _ = window.setTitleBarStyle(.hidden)
    _ = window.setWindowDragRegions([])
    window.setContentSizeLimits(minimum: Size(width: Pixels(400), height: Pixels(100)),
                                maximum: Size(width: Pixels(400), height: Pixels(600)))
    #expect(window.chromeHit(at: point(399, 150)) == .normal, "the width is fixed")
    #expect(window.chromeHit(at: point(200, 299)) == .resizeBottom, "the height is not")
    window.setContentSizeLimits(minimum: nil, maximum: nil)
    #expect(window.chromeHit(at: point(399, 150)) == .resizeRight)
}
