import Testing
import Foundation
import Metal
import Observation
import MetalUICore
import MetalUIPlatform
@testable import MetalUILayout
@testable import MetalUI

// Window sizing, lane 1, tests 2.33–2.42 (rulings `SV-L`, `SV-M`; spec
// `docs/superpowers/specs/2026-10-04-platform-services-design.md` §6.2, moved to
// lane 1 by `SV-AC`). `Window.minSize`/`maxSize`/`windowResizability` reach the
// platform through `PlatformWindow.setContentSizeLimits(minimum:maximum:)`,
// recorded by `FakePlatformWindow`; the content's limits are measured through
// a counting `ProposalLayout`, so "asks the content nothing" is a count.

private func size(_ width: Float, _ height: Float) -> Size<Pixels> {
    Size(width: Pixels(width), height: Pixels(height))
}

/// Counts `sizeThatFits` calls across every layout value sharing it.
private final class Calls: @unchecked Sendable {
    var count = 0
}

/// A childless layout answering SwiftUI's
/// `frame(minWidth:maxWidth:minHeight:maxHeight:)` shape: the proposal clamped
/// into `[min, max]` per axis, a `nil` axis answering the minimum — so a zero
/// proposal answers `min` and an infinite one `max` (`W1`, `W2`).
private struct Clamped: ProposalLayout {
    var minWidth: Double, maxWidth: Double, minHeight: Double, maxHeight: Double
    let calls: Calls

    func sizeThatFits(proposal: ProposedSize, subviews: MeasurementSubviews) -> LayoutMeasurement {
        calls.count += 1
        let width = min(max(proposal.width ?? minWidth, minWidth), maxWidth)
        let height = min(max(proposal.height ?? minHeight, minHeight), maxHeight)
        return LayoutMeasurement(size: SizeD(width: width, height: height))
    }

    func placeSubviews(in bounds: LayoutRect, proposal: ProposedSize, subviews: PlacementSubviews) {}
}

/// `Clamped` with one child it measures **twice** at a finite non-zero proposal
/// (the second a cache hit) and not at all at a zero or infinite one — so the
/// real run's work (`measureCalls` 2: this layout and its child, each measured
/// once at the window's proposal) differs from a limit measurement's (1).
private struct MeasuresItsChildAtTheWindowsProposal: ProposalLayout {
    let calls: Calls

    func sizeThatFits(proposal: ProposedSize, subviews: MeasurementSubviews) -> LayoutMeasurement {
        calls.count += 1
        if let width = proposal.width, let height = proposal.height,
           width > 0, height > 0, width.isFinite, height.isFinite {
            _ = subviews[0].sizeThatFits(proposal)
            _ = subviews[0].sizeThatFits(proposal)
        }
        return LayoutMeasurement(size: SizeD(width: 400, height: 300))
    }

    func placeSubviews(in bounds: LayoutRect, proposal: ProposedSize, subviews: PlacementSubviews) {}
}

/// A window over the fake whose root is `Clamped(400…900 × 300…600)`, the
/// probe's `W1`/`W2` content.
@MainActor
private func clampedWindow(calls: Calls, minWidth: Double = 400)
    throws -> (Window, FakePlatformWindow) {
    let device = try #require(MTLCreateSystemDefaultDevice(), "no Metal device; run on macOS hardware")
    return try makeFakeWindow(device: device) {
        ProposalLayoutContainer(Clamped(minWidth: minWidth, maxWidth: 900, minHeight: 300, maxHeight: 600,
                                        calls: calls)) {}
    }
}

/// One limits call as `(minimum, maximum)`, for `==`.
private struct Limits: Equatable {
    var minimum: Size<Pixels>?
    var maximum: Size<Pixels>?
}

@MainActor
private func limits(_ fake: FakePlatformWindow) -> [Limits] {
    fake.contentSizeLimitCalls.map { Limits(minimum: $0.minimum, maximum: $0.maximum) }
}

/// Draws one frame, dirtying the window first so it builds.
@MainActor
private func draw(_ window: Window) {
    window.setNeedsRedraw()
    window.drawFrameIfNeeded()
}

/// **2.33** (`SV-L` item 2, divergence 126). `.automatic` measures nothing: the
/// root's `sizeThatFits` runs once per frame — the real layout at the window's
/// proposal — and the platform is never asked to limit the window.
///
/// Mutation **M2.33**: measure the content regardless of the resizability
/// (the count reads 3).
@MainActor
@Test func automaticResizabilityAsksTheContentNothing() throws {
    let calls = Calls()
    let (window, fake) = try clampedWindow(calls: calls)
    #expect(window.windowResizability == .automatic)
    draw(window)
    draw(window)
    #expect(calls.count == 2, "one real layout per frame, no limit measurement: \(calls.count)")
    #expect(fake.contentSizeLimitCalls.isEmpty, "\(limits(fake))")
}

/// **2.34** (`SV-L` item 4). Explicit limits reach the platform once per
/// distinct effective pair: five frames and two equal assignments add nothing.
///
/// Mutation **M2.34**: reconcile without the change check (every frame calls).
@MainActor
@Test func explicitLimitsReachThePlatformOnlyWhenTheyChange() throws {
    let calls = Calls()
    let (window, fake) = try clampedWindow(calls: calls)
    window.minSize = size(100, 80)
    for _ in 0..<5 { draw(window) }
    window.minSize = size(100, 80)
    window.minSize = size(100, 80)
    draw(window)
    #expect(limits(fake) == [Limits(minimum: size(100, 80), maximum: nil)], "\(limits(fake))")
    window.maxSize = size(500, 400)
    draw(window)
    #expect(limits(fake) == [Limits(minimum: size(100, 80), maximum: nil),
                             Limits(minimum: size(100, 80), maximum: size(500, 400))], "\(limits(fake))")
}

/// **2.35** (`SV-L` item 2, `W1`). `.contentMinSize`: the minimum is the root's
/// answer at a zero proposal, and there is no maximum.
///
/// Mutation **M2.35**: measure at the window's size (the minimum reads the
/// window's 64 clamped up — still 400 × 300 — so the mutation is measured at
/// the window's proposal on a 1000 × 700 fake: it reads 900 × 600).
@MainActor
@Test func contentMinSizeIsTheRootsAnswerAtAZeroProposal() throws {
    let calls = Calls()
    let (window, fake) = try clampedWindow(calls: calls)
    fake.simulateResize(to: size(1000, 700))
    window.windowResizability = .contentMinSize
    draw(window)
    #expect(limits(fake).last == Limits(minimum: size(400, 300), maximum: nil), "\(limits(fake))")
    #expect(calls.count == 2, "the real layout and one zero-proposal measurement: \(calls.count)")
}

/// **2.36** (`SV-L` item 2, `W2`). `.contentSize` adds the maximum, the root's
/// answer at an infinite proposal.
///
/// Mutation **M2.36**: omit the maximum.
@MainActor
@Test func contentSizeAddsTheRootsAnswerAtAnInfiniteProposal() throws {
    let calls = Calls()
    let (window, fake) = try clampedWindow(calls: calls)
    window.windowResizability = .contentSize
    draw(window)
    #expect(limits(fake).last == Limits(minimum: size(400, 300), maximum: size(900, 600)), "\(limits(fake))")
    #expect(calls.count == 3, "the real layout and two measurements: \(calls.count)")
}

/// **2.37** (`SV-L` item 2, `W5`). The minimum follows the content: a content
/// change 400 → 700 makes a new call with 700.
///
/// Mutation **M2.37**: measure once and cache the first answer.
@MainActor
@Test func theContentMinimumFollowsTheContent() throws {
    let device = try #require(MTLCreateSystemDefaultDevice(), "no Metal device; run on macOS hardware")
    final class Model { var minWidth: Double = 400 }
    let model = Model()
    let calls = Calls()
    let (window, fake) = try makeFakeWindow(device: device) {
        ProposalLayoutContainer(Clamped(minWidth: model.minWidth, maxWidth: 900, minHeight: 300, maxHeight: 600,
                                        calls: calls)) {}
    }
    window.windowResizability = .contentMinSize
    draw(window)
    model.minWidth = 700
    draw(window)
    #expect(limits(fake) == [Limits(minimum: size(400, 300), maximum: nil),
                             Limits(minimum: size(700, 300), maximum: nil)], "\(limits(fake))")
}

/// **2.38** (`SV-L` item 4). Explicit and content limits combine per axis:
/// the larger minimum, the smaller maximum, and a maximum below the minimum
/// raised to it.
///
/// Mutation **M2.38**: take the content's limits alone.
@MainActor
@Test func explicitAndContentLimitsCombinePerAxis() throws {
    let calls = Calls()
    let (window, fake) = try clampedWindow(calls: calls)
    window.windowResizability = .contentSize          // content: 400 × 300 … 900 × 600
    window.minSize = size(500, 200)
    window.maxSize = size(800, 1000)
    draw(window)
    #expect(limits(fake).last == Limits(minimum: size(500, 300), maximum: size(800, 600)), "\(limits(fake))")
    window.maxSize = size(300, 1000)                  // below the content's minimum width
    draw(window)
    #expect(limits(fake).last == Limits(minimum: size(500, 300), maximum: size(500, 600)), "\(limits(fake))")
}

/// **2.39** (`SV-L` item 2). The limits are measured **before** the real
/// layout, so `lastNativeLayoutWork` is the real run's: `measureCalls` 2 (the
/// root and its child at the window's proposal), where a zero- or
/// infinite-proposal measurement's is 1.
///
/// Mutation **M2.39**: measure after the real layout (the work reads 1).
@MainActor
@Test func limitsAreMeasuredBeforeTheRealLayout() throws {
    let device = try #require(MTLCreateSystemDefaultDevice(), "no Metal device; run on macOS hardware")
    let calls = Calls(), childCalls = Calls()
    let (window, _) = try makeFakeWindow(device: device) {
        ProposalLayoutContainer(MeasuresItsChildAtTheWindowsProposal(calls: calls)) {
            ProposalLayoutContainer(Clamped(minWidth: 10, maxWidth: 10, minHeight: 10, maxHeight: 10,
                                            calls: childCalls)) {}
        }
    }
    var measureCalls: [Int] = []
    window.onFrameAdopted = { frame in measureCalls.append(frame.tree.lastNativeLayoutWork.measureCalls) }
    window.windowResizability = .contentSize
    draw(window)
    #expect(calls.count == 3, "the root measured three times: \(calls.count)")
    #expect(measureCalls == [2], "the frame's recorded work is the real run's: \(measureCalls)")
}

/// **2.40** (`SV-L` item 4). Limits given to `App.openWindow` reach the
/// platform before the first frame is presented.
///
/// Mutation **M2.40**: apply them after `drawFrameIfNeeded` (the first call
/// follows a present).
@MainActor
@Test func openWindowAppliesLimitsBeforeTheFirstFrame() throws {
    let device = try #require(MTLCreateSystemDefaultDevice(), "no Metal device; run on macOS hardware")
    let platform = FakePlatform(device: device)
    let app = App(platform: platform)
    let window = try app.openWindow(title: "Sized", size: size(64, 64), minSize: size(40, 30),
                                    maxSize: size(500, 400), startsDisplayLink: false) {
        Box().frame(width: Pixels(10), height: Pixels(10)).background(.accent)
    }
    let fake = try #require(platform.openedWindows.first)
    #expect(fake.contentSizeLimitCalls.count == 1, "one pair, not one call per parameter")
    let first = try #require(fake.contentSizeLimitCalls.first)
    #expect(Limits(minimum: first.minimum, maximum: first.maximum)
            == Limits(minimum: size(40, 30), maximum: size(500, 400)))
    #expect(first.presentsBefore == 0, "the limits must precede the first present")
    #expect(window.framesDrawn == 1)
    #expect(window.minSize == size(40, 30) && window.maxSize == size(500, 400))
}

/// **2.41** (`SV-L` item 4). Negative values clamp to 0 and an infinite
/// maximum means none.
///
/// Mutation **M2.41**: pass the values through.
@MainActor
@Test func negativeLimitsClampAndInfiniteMaximumMeansNone() throws {
    let calls = Calls()
    let (window, fake) = try clampedWindow(calls: calls)
    window.minSize = size(-20, 50)
    window.maxSize = size(.infinity, 300)
    draw(window)
    #expect(limits(fake).last == Limits(minimum: size(0, 50), maximum: size(.greatestFiniteMagnitude, 300)),
            "an infinite axis of a finite maximum is unbounded on that axis: \(limits(fake))")
    window.maxSize = size(.infinity, .infinity)
    draw(window)
    #expect(limits(fake).last == Limits(minimum: size(0, 50), maximum: nil), "\(limits(fake))")
}

/// **2.42** (`SV-L` item 4, `SA-J`'s rule). A NaN limit traps.
///
/// Mutation **M2.42**: clamp NaN to 0 (the child exits normally).
@Test func aNaNLimitTraps() async {
    await #expect(processExitsWith: .failure) {
        await MainActor.run {
            guard let device = MTLCreateSystemDefaultDevice(),
                  let (window, _) = try? makeFakeWindow(device: device, content: { Rectangle() })
            else { return }
            window.minSize = Size(width: Pixels(.nan), height: Pixels(10))
        }
    }
    // The maximum's arm (`SV-AG` item 2; mutation **M2.42b**: its precondition
    // removed).
    await #expect(processExitsWith: .failure) {
        await MainActor.run {
            guard let device = MTLCreateSystemDefaultDevice(),
                  let (window, _) = try? makeFakeWindow(device: device, content: { Rectangle() })
            else { return }
            window.maxSize = Size(width: Pixels(10), height: Pixels(.nan))
        }
    }
    await #expect(processExitsWith: .success) {
        await MainActor.run {
            guard let device = MTLCreateSystemDefaultDevice(),
                  let (window, _) = try? makeFakeWindow(device: device, content: { Rectangle() })
            else { exit(1) }
            window.minSize = Size(width: Pixels(10), height: Pixels(10))
        }
    }
}

/// The input test 2.43's `onAppear` writes.
@Observable @MainActor private final class AppearCount { var appeared = 0 }

/// **2.43** (`SV-AG` item 3). A content minimum that resizes the window on a
/// frame whose `onAppear` writes still owes the next frame: the resize arrives
/// inside the first build, and the lifecycle's settle build must not clear the
/// dirt it raised — the presented frame was encoded into a drawable taken
/// before the resize.
///
/// Mutation **M2.43**: the frame's resize no longer re-raises the redraw after
/// the settle build.
@MainActor
@Test func aResizeIntoContentLimitsOnALifecycleFrameOwesTheNextFrame() throws {
    let device = try #require(MTLCreateSystemDefaultDevice(), "no Metal device; run on macOS hardware")
    let model = AppearCount()
    let calls = Calls()
    let (window, fake) = try makeFakeWindow(device: device) {
        VStack {
            // Reads the model, so the `onAppear`'s write dirties the window
            // and the lifecycle's settle build runs.
            ProposalLayoutContainer(Clamped(minWidth: 400, maxWidth: 900 + Double(model.appeared * 0),
                                            minHeight: 300, maxHeight: 600, calls: calls)) {}
                .onAppear { model.appeared += 1 }
        }
    }
    window.windowResizability = .contentMinSize
    window.drawFrameIfNeeded()
    try #require(model.appeared == 1, "the onAppear ran")
    try #require(window.lastDrawBuildCount == 2, "the lifecycle's settle build ran (the separating arm)")
    #expect(fake.contentSize == size(400, 300), "the platform resized into the limits")
    let presents = fake.fakeSurface.presentCalls
    window.drawFrameIfNeeded()
    #expect(fake.fakeSurface.presentCalls == presents + 1,
            "the resize's redraw survived the settle build")
}

/// **2.44** (`SV-AG` item 4). Leaving `.contentSize` drops the content's
/// maximum at once — the switch reaches the platform without the previous
/// mode's maximum, not one frame later.
///
/// Mutation **M2.44**: keep the content maximum when the mode changes.
@MainActor
@Test func leavingContentSizeDropsTheContentMaximumAtOnce() throws {
    let calls = Calls()
    let (window, fake) = try clampedWindow(calls: calls)
    window.windowResizability = .contentSize
    draw(window)
    #expect(limits(fake).last == Limits(minimum: size(400, 300), maximum: size(900, 600)), "\(limits(fake))")
    window.windowResizability = .contentMinSize
    #expect(limits(fake).last == Limits(minimum: size(400, 300), maximum: nil), "\(limits(fake))")
}

// MARK: - SMK port gaps, lane 1: drawn chrome (ruling `SG-F`; spec §5 tests 2.19's strip arms, 2.20)

@Observable @MainActor private final class ChromeModel {
    var showsToolbar = true
}

/// A 400 × 400 fake window whose root declares a toolbar while
/// `model.showsToolbar`; with `drawn` the platform declines it (SDL's answer),
/// so the window draws the 39-point strip (`MD-K`).
@MainActor
private func chromeWindow(_ model: ChromeModel, drawn: Bool) throws -> (Window, FakePlatformWindow) {
    let (window, fake) = try makeFakeWindowOnDefaultDevice(size: 400) {
        Column {
            if model.showsToolbar {
                Text("Body").frame(width: Pixels(100), height: Pixels(50))
                    .toolbar { ToolbarItem { Button("Back") {} } }
            } else {
                Text("Body").frame(width: Pixels(100), height: Pixels(50))
            }
        }
    }
    fake.toolbarIsNative = !drawn
    return (window, fake)
}

/// **2.19**, the toolbar strip's arms (`SG-F` item 1; lane 2 adds the menu
/// bar's 25 and the both-drawn arm). `drawnChromeHeight` is 0 before the
/// first frame, 39 once the strip is drawn, 0 when the toolbar goes, 0 with
/// no toolbar and 0 where the platform shows the toolbar itself. Red before:
/// does not compile. Mutation: report 0 always — reddens.
@MainActor
@Test func drawnChromeHeightIsTheBarPlusTheStrip() throws {
    let model = ChromeModel()
    let (drawn, _) = try chromeWindow(model, drawn: true)
    #expect(drawn.drawnChromeHeight == Pixels(0), "nothing is laid out before the first frame")
    draw(drawn)
    #expect(drawn.drawnChromeHeight == Pixels(39), "the drawn toolbar strip")
    model.showsToolbar = false
    draw(drawn)
    #expect(drawn.drawnChromeHeight == Pixels(0), "no toolbar, no strip")
    model.showsToolbar = true
    let (native, _) = try chromeWindow(model, drawn: false)
    draw(native)
    #expect(native.drawnChromeHeight == Pixels(0), "a toolbar the platform shows is not drawn chrome")

    // The drawn menu bar's arms (lane 2, `SG-A` item 5): an app declaring
    // commands on a platform declining the bar — 25 with the bar alone, 64 with
    // the bar and the strip, 0 with both shown by the platform.
    for (barNative, stripDrawn, expected) in [(false, false, Float(25)), (false, true, 64), (true, false, 0)] {
        let device = try #require(MTLCreateSystemDefaultDevice(), "no Metal device; run on macOS hardware")
        let platform = FakePlatform(device: device)
        platform.menuBarIsNative = barNative
        platform.windowSize = 400
        let app = App(platform: platform)
        app.commands { CommandMenu("Tools") { Button("Go") {} } }
        let window = try app.openWindow(title: "Chrome", size: size(400, 400), startsDisplayLink: false) {
            Column {
                Text("Body").frame(width: Pixels(100), height: Pixels(50))
                    .toolbar { ToolbarItem { Button("Back") {} } }
            }
        }
        let fake = try #require(platform.openedWindows.last)
        fake.toolbarIsNative = !stripDrawn
        draw(window)
        draw(window)
        #expect(window.drawnChromeHeight == Pixels(expected),
                "bar native \(barNative), strip drawn \(stripDrawn): \(window.drawnChromeHeight)")
    }
}

/// **2.20** (`SG-F` items 2–3). An explicit `minSize`/`maxSize` is a size of
/// the content below the drawn chrome, as AppKit's `contentMinSize` excludes
/// its toolbar: with the strip drawn the platform receives 200 × 339 for a
/// 200 × 300 minimum, a finite maximum height grows by 39 and an infinite one
/// stays unbounded; when the toolbar goes the limits are re-sent unadjusted;
/// where the platform shows the toolbar, 200 × 300. Red before: does not
/// adjust (200 × 300 with the strip). Mutation: send the explicit limits
/// unadjusted — reddens.
@MainActor
@Test func anExplicitMinimumIsMeasuredBelowTheDrawnChrome() throws {
    let model = ChromeModel()
    let (drawn, fake) = try chromeWindow(model, drawn: true)
    drawn.minSize = size(200, 300)
    drawn.maxSize = size(500, .infinity)
    draw(drawn)
    #expect(limits(fake).last == Limits(minimum: size(200, 339), maximum: size(500, .greatestFiniteMagnitude)),
            "below the 39-point strip; an infinite maximum stays unbounded: \(limits(fake))")
    drawn.maxSize = size(500, 400)
    #expect(limits(fake).last == Limits(minimum: size(200, 339), maximum: size(500, 439)), "\(limits(fake))")
    let calls = limits(fake).count
    draw(drawn)
    #expect(limits(fake).count == calls, "unchanged chrome sends nothing: \(limits(fake))")
    model.showsToolbar = false
    draw(drawn)
    #expect(limits(fake).last == Limits(minimum: size(200, 300), maximum: size(500, 400)),
            "the strip gone, the limits are re-sent as written: \(limits(fake))")

    model.showsToolbar = true
    let (native, nativeFake) = try chromeWindow(model, drawn: false)
    native.minSize = size(200, 300)
    draw(native)
    #expect(limits(nativeFake).last == Limits(minimum: size(200, 300), maximum: nil),
            "a toolbar the platform shows takes nothing from the limits: \(limits(nativeFake))")
}
