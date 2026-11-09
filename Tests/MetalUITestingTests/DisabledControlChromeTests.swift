import MetalUI
import MetalUIPlatform
import MetalUITesting
import Testing

// AS-S (record 251): a disabled control in the title bar band moves nothing, as a native one does not. `EV-E`
// keeps its hitbox out (a click still reaches an enabled ancestor); a chrome-only record of its rect carves
// the SDL drag regions and stops AppKit's unclaimed band press. Plain imports, portable.

private let windowSize = sz(400, 300)
private let appKitBand = HeadlessPlatformWindow.Options(
    hiddenTitleBarInsets: Edges(top: Pixels(32), right: Pixels(0), bottom: Pixels(0), left: Pixels(0)))

@MainActor private func band<Blocker: ProposalElementGroup>(
    @ProposalContentBuilder _ blocker: () -> Blocker
) -> some Element {
    VStack(alignment: .leading, spacing: Pixels(0)) {
        HStack(alignment: .top, spacing: Pixels(0)) {
            Color.clear.frame(width: Pixels(20), height: Pixels(24))
            blocker()
            Color.clear.frame(width: Pixels(300), height: Pixels(24))
        }
        Color.clear.frame(width: Pixels(400), height: Pixels(276))
    }
}

@MainActor private func window<Root: Element>(
    _ options: HeadlessPlatformWindow.Options, _ content: @escaping @MainActor () -> Root
) throws -> TestWindow {
    let app = try TestApp(textSystem: harnessTextSystem)
    let w = try app.openWindow(size: windowSize, windowStyle: .hiddenTitleBar, options: options, content: content)
    w.window.drawsWindowControls = false
    w.tick()
    return w
}

@MainActor @ProposalContentBuilder private func plainButton(disabled: Bool) -> some ProposalElementGroup {
    Button(action: {}) { Color.clear.frame(width: Pixels(80), height: Pixels(24)) }
        .buttonStyle(.plain).disabled(disabled)
}

private let inButton = pt(60, 12)
private let carved = [rect(0, 0, 20, 24), rect(100, 0, 300, 24), rect(0, 24, 400, 8)]

/// A press on a disabled button in the band drags nothing and runs no double-click action (AppKit path).
/// Mutation: drop the `lastInertChromeBlockers` guard in `answerUnclaimedTitleBarPress`.
@Test @MainActor func aPressOnADisabledButtonInTheBandDoesNotDragOnAppKit() throws {
    let w = try window(appKitBand) { band { plainButton(disabled: true) } }
    w.doubleClick(at: inButton)
    #expect(w.platformWindow.titleBarPresses.isEmpty, "\(w.platformWindow.titleBarPresses)")
    w.click(at: pt(10, 12))
    #expect(w.platformWindow.titleBarPresses == [1], "the band around it still drags")
}

/// The same button enabled: the click is its own, nothing drags (unchanged). Mutation: none (control arm).
@Test @MainActor func theSameButtonEnabledStillClaimsThePress() throws {
    var taps = 0
    let w = try window(appKitBand) {
        band {
            Button(action: { taps += 1 }) { Color.clear.frame(width: Pixels(80), height: Pixels(24)) }.buttonStyle(.plain)
        }
    }
    w.click(at: inButton)
    #expect(taps == 1)
    #expect(w.platformWindow.titleBarPresses.isEmpty)
}

/// SDL: the disabled button is carved out of the regions exactly like an enabled one. Mutation: drop the
/// `+ inert` in the band's `carving` in `ChromeRegions.compute`.
@Test @MainActor func aDisabledButtonInTheBandIsCarvedOutOfTheSDLRegions() throws {
    let w = try window(.sdlChrome) { band { plainButton(disabled: true) } }
    #expect(w.windowDragRegions == carved, "\(w.windowDragRegions)")
    let enabled = try window(.sdlChrome) { band { plainButton(disabled: false) } }
    #expect(enabled.windowDragRegions == carved)
}

/// EV-E is kept: a disabled control inside an enabled tappable ancestor still lets the click through to it.
/// Mutation: register an opaque hitbox for the disabled control (the ancestor's tap goes silent).
@Test @MainActor func aDisabledControlInsideAnEnabledAncestorLeavesTheAncestorsClick() throws {
    var taps = 0
    let w = try window(appKitBand) {
        band {
            ZStack {
                Color.clear.frame(width: Pixels(80), height: Pixels(24))
                plainButton(disabled: true)
            }.onTapGesture { taps += 1 }
        }
    }
    w.click(at: inButton)
    #expect(taps == 1)
    #expect(w.platformWindow.titleBarPresses.isEmpty, "the ancestor claimed it")
}

/// A disabled control with no hit testing (`allowsHitTesting(false)`) carves nothing: the press passes through.
@Test @MainActor func aDisabledControlWithHitTestingOffCarvesNothing() throws {
    let w = try window(.sdlChrome) { band { plainButton(disabled: true).allowsHitTesting(false) } }
    #expect(w.windowDragRegions == [rect(0, 0, 400, 32)], "\(w.windowDragRegions)")
}

private struct DisabledChip: Component, @MainActor Equatable {
    var content: some ElementGroup {
        Button(action: {}) { Color.clear.frame(width: Pixels(80), height: Pixels(24)) }.buttonStyle(.plain).disabled(true)
    }
}

/// A replayed `.equatable()` subtree still contributes its blocker. Mutation: drop the `inertBlockers` replay
/// in `replayPrepaintLedger` (the carve vanishes once the prepaint is a hit).
@Test @MainActor func aReplayedSubtreeStillCarves() throws {
    let w = try window(.sdlChrome) { band { DisabledChip().equatable() } }
    var hits = 0
    for _ in 0..<6 {
        w.window.setNeedsRedraw(); w.tick()
        hits += w.lastFrameWork.retainedPrepaintHits
        #expect(w.windowDragRegions == carved, "\(w.windowDragRegions)")
    }
    if !rsVerifying { #expect(hits > 0, "set up: the prepaint was replayed") }
}
