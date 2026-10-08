import Testing
import Foundation
import Metal
import AppKit
import MetalUICore
@testable import MetalUIPlatform
@testable import MetalUIAppKit
import MetalUIRender

@MainActor
@Test func openWindowProducesASurfaceSizedToItsContent() throws {
    let device = try #require(MTLCreateSystemDefaultDevice(),
                              "no Metal device; run on macOS hardware")
    let platform = AppKitPlatform(device: device)
    let window = try platform.openWindow(title: "Test",
                                         size: Size(width: Pixels(400), height: Pixels(300)))

    #expect(window.contentSize.width.value == 400)
    #expect(window.contentSize.height.value == 300)
    #expect(window.scaleFactor >= 1.0)

    // The AppKit window draws through a Metal `WindowRenderer` over its own
    // layer surface (ruling RS-C); the surface itself is read here directly.
    let appKitWindow = try #require(window as? AppKitWindow)
    let metal = try #require(window.renderer as? MetalWindowRenderer)
    #expect(metal.surface === appKitWindow.surface)
    let frame = try appKitWindow.surface.nextFrame()
    #expect(frame.views.count == 1)
    // Surface is sized in device pixels, so it tracks the scale factor.
    #expect(frame.views[0].colorTexture.width == Int(400 * window.scaleFactor))
    #expect(frame.scaleFactor == window.scaleFactor)
}

@MainActor
@Test func windowTitleRoundTrips() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let platform = AppKitPlatform(device: device)
    let window = try platform.openWindow(title: "Initial",
                                         size: Size(width: Pixels(200), height: Pixels(200)))
    #expect(window.title == "Initial")
    window.title = "Changed"
    #expect(window.title == "Changed")
}

/// Spec §7.9: "`NSApp.effectiveAppearance` … swap[s] the active theme."
///
/// **This was very nearly written off as untestable.** Four comments on this
/// branch said, in one form or another, that no test can see
/// `viewDidChangeEffectiveAppearance` fire because AppKit calls it in response
/// to a system-wide setting a test may not change. Measured: setting
/// `NSApplication.shared.appearance` drives `effectiveAppearance` for every view
/// under it, and the override fires **synchronously** — no run-loop spin, and so
/// no re-entrancy into other main-actor tests. The claim was a prediction about
/// measurement, dressed as a fact (practices doc, shape 10).
///
/// Both directions are asserted. One would pass against a getter hard-coded to
/// the answer it happens to expect, and against a callback that passes a
/// constant.
@MainActor
@Test func theWindowFollowsTheApplicationsEffectiveAppearance() throws {
    let device = try #require(MTLCreateSystemDefaultDevice(),
                              "no Metal device; run on macOS hardware")
    let platform = AppKitPlatform(device: device)
    let window = try platform.openWindow(title: "Appearance",
                                         size: Size(width: Pixels(200), height: Pixels(200)))

    let saved = NSApplication.shared.appearance
    defer { NSApplication.shared.appearance = saved }

    // Force a known starting point, before the callback is attached, so the
    // machine's own appearance cannot decide how many events this test sees.
    NSApplication.shared.appearance = NSAppearance(named: .aqua)
    #expect(window.appearance == .light)

    var fired: [Appearance] = []
    window.onAppearanceChange = { fired.append($0) }

    NSApplication.shared.appearance = NSAppearance(named: .darkAqua)
    #expect(window.appearance == .dark)
    #expect(fired == [.dark], "the callback must carry the new value, not merely say something changed")

    NSApplication.shared.appearance = NSAppearance(named: .aqua)
    #expect(window.appearance == .light)
    #expect(fired == [.dark, .light])
}

/// The resize path, through a **real** `AppKitPlatform` window.
///
/// **This was written off as untestable and is not.** `Fakes.swift` grouped
/// resize with the failure and idle paths as "unreachable through
/// `App.openWindow`, because the AppKit surface only produces a drawable for a
/// window that is actually on screen". Resize needs no drawable and no surface
/// at all: `NSWindow.setContentSize` resizes the content view, `setFrameSize`
/// runs `syncSurfaceGeometry`, and `onResize` fires **synchronously**. Deleting
/// the `onResize?(…)` call left the whole suite green before this existed.
///
/// The size is non-square and neither extent matches the original, so a
/// callback that transposed the axes or passed a stale `contentSize` reddens
/// rather than passing on a coincidence.
@MainActor
@Test func theWindowReportsAContentSizeChangeThroughOnResize() throws {
    let device = try #require(MTLCreateSystemDefaultDevice(),
                              "no Metal device; run on macOS hardware")
    let platform = AppKitPlatform(device: device)
    let title = "Resize \(UUID().uuidString)"
    let window = try platform.openWindow(title: title,
                                         size: Size(width: Pixels(400), height: Pixels(300)))
    let nsWindow = try #require(NSApplication.shared.windows.first { $0.title == title })
    defer { nsWindow.close() }

    // Attached after `openWindow`, whose own init already synced geometry once.
    var fired: [Size<Pixels>] = []
    window.onResize = { size, _ in fired.append(size) }
    #expect(fired.isEmpty)

    nsWindow.setContentSize(NSSize(width: 320, height: 140))

    #expect(fired.count == 1, "onResize did not fire, or fired more than once")
    #expect(fired.first?.width == Pixels(320))
    #expect(fired.first?.height == Pixels(140))
    // The getter agrees with the payload — a callback carrying the *previous*
    // size would satisfy neither, and one carrying a constant only this.
    #expect(window.contentSize.width == Pixels(320))
    #expect(window.contentSize.height == Pixels(140))
}

/// Why `appearance` uses `bestMatch(from:)` and not `effectiveAppearance.name
/// == .darkAqua`.
///
/// **The comment at that property named the wrong appearance for four commits.**
/// It blamed the accessibility high-contrast ones; probed,
/// `.accessibilityHighContrastDarkAqua` resolves to plain
/// `NSAppearanceNameDarkAqua`, which equality handles fine. The name that
/// actually diverges is the **vibrant** one — it resolves to
/// `NSAppearanceNameVibrantDark`, so an equality test would report a dark window
/// as **light** and paint a light theme over it.
///
/// Needs no system setting: the appearance is set on the `NSWindow`, which is
/// what makes this a guard rather than a second untestable assertion.
@MainActor
@Test func aVibrantDarkAppearanceIsReportedAsDark() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let platform = AppKitPlatform(device: device)
    let title = "Vibrant \(UUID().uuidString)"
    let window = try platform.openWindow(title: title,
                                         size: Size(width: Pixels(200), height: Pixels(200)))
    let nsWindow = try #require(NSApplication.shared.windows.first { $0.title == title })
    defer { nsWindow.close() }

    nsWindow.appearance = NSAppearance(named: .vibrantDark)
    let effective = try #require(nsWindow.contentView?.effectiveAppearance)

    // The premise, asserted rather than assumed: this appearance really is one
    // an equality test would get wrong. Without this line the expectation below
    // would pass just as well against a `.darkAqua` window.
    #expect(effective.name != .darkAqua,
            "vibrantDark no longer resolves to a distinct name, so this test has stopped testing bestMatch")
    #expect(window.appearance == .dark)

    // Both directions, so the getter is not simply hard-coded to `.dark`.
    nsWindow.appearance = NSAppearance(named: .aqua)
    #expect(window.appearance == .light)
}

/// ARC owns the `NSWindow`, so AppKit must not release it a second time on
/// `close()`.
///
/// **This is the guard for a crash the suite could not report.** Two tests above
/// end in `defer { nsWindow.close() }`, which is the ordinary correct habit and
/// stayed correct. `NSWindow(contentRect:…)` defaults `isReleasedWhenClosed` to
/// **true**, so the close over-released a window `AppKitWindow` holds strongly;
/// AppKit defers the window's close animation into an autorelease pool that
/// CoreAnimation pops from a run-loop observer, so the dangling release fired
/// later, in `-[_NSWindowTransformAnimation dealloc]`, the next time the main
/// run loop spun a CA commit. Nothing in `MetalUIPlatformTests` awaits, so alone
/// these tests exit before that happens; the WebKit layout-oracle tests in
/// `MetalUILayoutTests` await for seconds, and the whole `swift test` process
/// died with **SIGSEGV, 297 of 303 tests reported and no summary line** —
/// practices doc, shape 11.
///
/// **Asserted as a property rather than as behaviour on purpose.** The
/// behavioural failure is a process crash, and a crash is a truncated run, not a
/// red test — reporting it is exactly what the bug prevents. This spelling
/// reddens cleanly: delete the `isReleasedWhenClosed = false` line in
/// `AppKitWindow.init` and this is the test that says so.
@MainActor
@Test func closingAWindowDoesNotOverReleaseTheOneARCAlreadyOwns() throws {
    let device = try #require(MTLCreateSystemDefaultDevice(),
                              "no Metal device; run on macOS hardware")
    let platform = AppKitPlatform(device: device)
    let title = "Ownership \(UUID().uuidString)"
    _ = try platform.openWindow(title: title,
                                size: Size(width: Pixels(200), height: Pixels(200)))
    let nsWindow = try #require(NSApplication.shared.windows.first { $0.title == title })
    defer { nsWindow.close() }

    #expect(nsWindow.isReleasedWhenClosed == false,
            "AppKit will release a window ARC already owns; closing it crashes the process later")
}

/// A non-precise scroll device (a wheel mouse) reports LINES in
/// `scrollingDeltaX/Y`; a precise one (trackpad, Magic Mouse) reports points.
///
/// **Both arms carry the same raw numbers and must come back different.** Before
/// the fix the seam copied the raw value in either case, so the line arm read
/// `3, -2` points where `NSScrollView` would have moved `30, -20`. The oracle is
/// AppKit's own `NSScrollView.verticalLineScroll`/`horizontalLineScroll` read at
/// test time, not the constant under test. The x and y magnitudes differ and
/// carry opposite signs, so a transposed or sign-dropping conversion reddens
/// too (practices doc, shape 1).
@MainActor
@Test func aNonPreciseScrollDeltaIsScaledFromLinesToPointsAndAPreciseOneIsNot() throws {
    let precise = MetalHostView.scrollDelta(x: 3, y: -2, precise: true)
    let lines = MetalHostView.scrollDelta(x: 3, y: -2, precise: false)

    // The arms must disagree; agreement is the bug.
    #expect(precise.x != lines.x, "a wheel mouse's line count was applied as points")
    #expect(precise.y != lines.y, "a wheel mouse's line count was applied as points")

    // The precise arm is exactly the raw value: trackpads were already right.
    #expect(precise.x == Pixels(3))
    #expect(precise.y == Pixels(-2))

    let reference = NSScrollView(frame: .zero)
    #expect(lines.x == Pixels(Float(3 * reference.horizontalLineScroll)))
    #expect(lines.y == Pixels(Float(-2 * reference.verticalLineScroll)))
}

/// The same conversion, through the override AppKit actually calls, with real
/// `NSEvent`s. The pure-function test above cannot see a `scrollWheel(with:)`
/// that stops calling it; this one can.
///
/// `CGEvent(scrollWheelEvent2Source:units:.line …)` is what a wheel mouse's
/// event looks like after `NSEvent(cgEvent:)`: `hasPreciseScrollingDeltas` is
/// false and `scrollingDeltaY` holds the raw line count. `.pixel` gives the
/// precise shape. Both premises are required, not assumed, so an SDK that
/// changes either stops this test loudly instead of letting it pass on
/// identical inputs. No window is opened.
@MainActor
@Test func aWheelMouseEventReachesOnInputInPointsAndATrackpadEventIsUnchanged() throws {
    let device = try #require(MTLCreateSystemDefaultDevice(),
                              "no Metal device; run on macOS hardware")
    let view = MetalHostView(surface: MetalLayerSurface(device: device))
    var deltas: [Point<Pixels>] = []
    view.onInput = { event in
        if case .scrollWheel(let scroll) = event { deltas.append(scroll.delta) }
        return true
    }

    func wheelEvent(_ units: CGScrollEventUnit) throws -> NSEvent {
        let cg = try #require(CGEvent(scrollWheelEvent2Source: nil, units: units,
                                      wheelCount: 2, wheel1: -2, wheel2: 3, wheel3: 0))
        return try #require(NSEvent(cgEvent: cg))
    }
    let line = try wheelEvent(.line)
    let pixel = try wheelEvent(.pixel)
    try #require(line.hasPreciseScrollingDeltas == false)
    try #require(pixel.hasPreciseScrollingDeltas == true)
    try #require(line.scrollingDeltaX == 3 && line.scrollingDeltaY == -2)
    try #require(pixel.scrollingDeltaX == 3 && pixel.scrollingDeltaY == -2)

    view.scrollWheel(with: line)
    view.scrollWheel(with: pixel)
    try #require(deltas.count == 2)

    let reference = NSScrollView(frame: .zero)
    #expect(deltas[0].x == Pixels(Float(3 * reference.horizontalLineScroll)))
    #expect(deltas[0].y == Pixels(Float(-2 * reference.verticalLineScroll)))
    #expect(deltas[1].x == Pixels(3))
    #expect(deltas[1].y == Pixels(-2))
}

/// **2.20** (colour and colour scheme, ruling `CR-M`). A preferred colour
/// scheme sets the `NSWindow`'s own appearance — so its title bar and native
/// menus follow — and the change comes back through `onAppearanceChange` as
/// the forced scheme; `nil` clears the override and the application's
/// appearance is reported again (probe `swiftui-colour.swift` `P8b`).
///
/// Mutation: map `.dark` to `.aqua` (the first two expectations redden).
@MainActor
@Test func settingAPreferredColorSchemeSetsTheNSWindowsAppearanceAndReportsIt() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let platform = AppKitPlatform(device: device)
    let saved = NSApplication.shared.appearance
    defer { NSApplication.shared.appearance = saved }
    NSApplication.shared.appearance = NSAppearance(named: .aqua)

    let title = "Preferred \(UUID().uuidString)"
    let window = try platform.openWindow(title: title,
                                         size: Size(width: Pixels(200), height: Pixels(200)))
    let nsWindow = try #require(NSApplication.shared.windows.first { $0.title == title })
    defer { nsWindow.close() }
    try #require(window.appearance == .light, "the premise: an aqua application")

    var fired: [Appearance] = []
    window.onAppearanceChange = { fired.append($0) }

    window.setPreferredColorScheme(.dark)
    #expect(nsWindow.appearance?.name == .darkAqua)
    #expect(window.appearance == .dark)
    #expect(fired.last == .dark, "the forced appearance must be reported: \(fired)")

    window.setPreferredColorScheme(nil)
    #expect(nsWindow.appearance == nil, "nil follows the application")
    #expect(window.appearance == .light)
    #expect(fired.last == .light, "clearing must report the application's appearance: \(fired)")

    window.setPreferredColorScheme(.light)
    #expect(nsWindow.appearance?.name == .aqua)
}

// MARK: - Input APIs, lane 1: the scroll event's phases (spec
// `docs/superpowers/specs/2026-10-08-input-apis-design.md` §4.1, tests 1.3 and
// 1.4; rulings `CI-I` items 1 and 6, `CI-V` item 1)

/// **1.3** (`CI-I` item 1, `CI-V` item 1). The old initialiser keeps its
/// spelling and meaning: `isMomentum: true` is a momentum phase of `.changed`
/// with no gesture phase, a precise delta, and `location` equal to `position`
/// (the seam's answer, before any element makes it local). `isMomentum` keeps
/// a setter: `true` marks a `.none` momentum phase `.changed` and leaves a
/// phase already under way alone; `false` clears it.
///
/// Mutations: the old init leaves `momentumPhase` `.none` (the first block
/// reddens); the setter ignores `false` (the setter arm reddens).
@Test func theOldScrollEventInitialiserKeepsItsMeaning() {
    let position = Point(x: Pixels(12), y: Pixels(34))
    let delta = Point(x: Pixels(3), y: Pixels(-5))
    let momentum = ScrollEvent(position: position, delta: delta, isMomentum: true)
    #expect(momentum.momentumPhase == .changed)
    #expect(momentum.isMomentum)
    #expect(momentum.phase == .none)
    #expect(momentum.isPrecise)
    #expect(momentum.location == position)

    let plain = ScrollEvent(position: position, delta: delta)
    #expect(plain.momentumPhase == .none)
    #expect(!plain.isMomentum)
    #expect(plain.location == position)

    var assigned = plain
    assigned.isMomentum = true
    #expect(assigned.momentumPhase == .changed, "setting isMomentum marks the momentum phase")
    assigned.isMomentum = false
    #expect(assigned.momentumPhase == .none, "clearing isMomentum clears the momentum phase")

    var underWay = ScrollEvent(position: position, delta: delta, phase: .none, momentumPhase: .began,
                               isPrecise: true, timestamp: 0)
    underWay.isMomentum = true
    #expect(underWay.momentumPhase == .began, "a momentum phase already under way is kept")
    #expect(underWay.location == position)
}

/// **1.4** (`CI-I` item 6). Real scroll `CGEvent`s through
/// `MetalHostView.scrollWheel(with:)`: the gesture phase comes from
/// `NSEvent.phase`, the momentum phase from `NSEvent.momentumPhase` (each set
/// through its own CG field, `scrollWheelEventScrollPhase` and
/// `scrollWheelEventMomentumPhase`), and `isPrecise` from
/// `hasPreciseScrollingDeltas` (a `.pixel` event is precise, a `.line` one is
/// not). The three events carry **different** phases on the two axes, so a
/// seam that reads one field for both reddens. Every premise on the converted
/// `NSEvent` is required, not assumed.
///
/// Mutation: map `momentumPhase` from `phase` (the second and third events
/// redden).
@MainActor
@Test func appKitScrollWheelCarriesPhaseMomentumAndPrecision() throws {
    let device = try #require(MTLCreateSystemDefaultDevice(), "no Metal device; run on macOS hardware")
    let view = MetalHostView(surface: MetalLayerSurface(device: device))
    var events: [ScrollEvent] = []
    view.onInput = { event in
        if case .scrollWheel(let scroll) = event { events.append(scroll) }
        return true
    }
    func wheel(_ units: CGScrollEventUnit, scrollPhase: Int64, momentumPhase: Int64) throws -> NSEvent {
        let cg = try #require(CGEvent(scrollWheelEvent2Source: nil, units: units,
                                      wheelCount: 1, wheel1: -2, wheel2: 0, wheel3: 0))
        cg.setIntegerValueField(.scrollWheelEventScrollPhase, value: scrollPhase)
        cg.setIntegerValueField(.scrollWheelEventMomentumPhase, value: momentumPhase)
        return try #require(NSEvent(cgEvent: cg))
    }
    // CGScrollPhase: began 1, changed 2; CGMomentumScrollPhase: begin 1, continue 2.
    let began = try wheel(.pixel, scrollPhase: 1, momentumPhase: 0)
    let coasting = try wheel(.line, scrollPhase: 0, momentumPhase: 2)
    let startCoast = try wheel(.pixel, scrollPhase: 0, momentumPhase: 1)
    try #require(began.phase == .began && began.momentumPhase == [] && began.hasPreciseScrollingDeltas,
                 "premise: \(began.phase) \(began.momentumPhase) \(began.hasPreciseScrollingDeltas)")
    try #require(coasting.phase == [] && coasting.momentumPhase == .changed && !coasting.hasPreciseScrollingDeltas,
                 "premise: \(coasting.phase) \(coasting.momentumPhase) \(coasting.hasPreciseScrollingDeltas)")
    try #require(startCoast.phase == [] && startCoast.momentumPhase == .began,
                 "premise: \(startCoast.phase) \(startCoast.momentumPhase)")

    view.scrollWheel(with: began)
    view.scrollWheel(with: coasting)
    view.scrollWheel(with: startCoast)
    try #require(events.count == 3)
    #expect(events[0].phase == .began)
    #expect(events[0].momentumPhase == .none)
    #expect(events[0].isPrecise)
    #expect(!events[0].isMomentum)
    #expect(events[1].phase == .none)
    #expect(events[1].momentumPhase == .changed)
    #expect(!events[1].isPrecise)
    #expect(events[1].isMomentum)
    #expect(events[2].phase == .none)
    #expect(events[2].momentumPhase == .began)
    #expect(events[2].isPrecise)
    for event in events { #expect(event.location == event.position, "location is the seam's position") }
}
