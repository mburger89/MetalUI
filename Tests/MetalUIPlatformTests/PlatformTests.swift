import Testing
import Foundation
import Metal
import AppKit
import MetalUICore
@testable import MetalUIPlatform

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

    let frame = try window.surface.nextFrame()
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
