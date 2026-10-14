import MetalUI
import MetalUIScene
import MetalUITesting
import Observation
import Testing

// SDL custom chrome, lane 1 (rulings `CW-B`…`CW-G`, `CW-J`, `CW-M`; spec
// `docs/superpowers/specs/2026-10-13-sdl-chrome-design.md` "Tests"). `Options.sdlChrome` makes the
// headless platform answer as SDL does under `.hiddenTitleBar`: drag regions used, no native window
// buttons, the band 32 and a 138-point cluster. The real `Window` computes and publishes the regions
// and draws the strip. Plain imports, portable: runs on macOS, Linux and Windows.

private let windowSize = sz(400, 300)

/// A 400 x 300 `.hiddenTitleBar` window over `content`, in `options`. `controls: false` turns the drawn
/// buttons off (so the band tests see the whole band) and redraws.
@MainActor private func chromeWindow<Root: Element>(
    options: HeadlessPlatformWindow.Options = .sdlChrome, style: WindowStyle = .hiddenTitleBar,
    controls: Bool = true, scale: Float = 1, _ content: @escaping @MainActor () -> Root
) throws -> TestWindow {
    let app = try TestApp(textSystem: harnessTextSystem)
    let window = try app.openWindow(size: windowSize, windowStyle: style, scaleFactor: scale,
                                    options: options, content: content)
    if !controls {
        window.window.drawsWindowControls = false
        window.tick()
    }
    return window
}

/// The page every band test uses: a 32-point band row (`band`, top aligned) over a 268-point body that
/// registers nothing, 400 wide, so every literal below is the band's.
@MainActor private func bandPage<Band: ProposalElementGroup, Body: ProposalElementGroup>(
    @ProposalContentBuilder band: () -> Band, @ProposalContentBuilder body: () -> Body
) -> some Element {
    VStack(alignment: .leading, spacing: Pixels(0)) {
        HStack(alignment: .top, spacing: Pixels(0)) { band() }
        body()
    }
}

/// A 20-point gap, a `blocker` 80 wide, and a gap filling to 400.
@MainActor private func blockerBand<Blocker: ProposalElementGroup>(
    height: Float, @ProposalContentBuilder _ blocker: () -> Blocker
) -> some Element {
    bandPage {
        Color.clear.frame(width: Pixels(20), height: Pixels(32))
        blocker()
        Color.clear.frame(width: Pixels(300), height: Pixels(32))
    } body: {
        Color.clear.frame(width: Pixels(400), height: Pixels(268))
    }
}

private let wholeBand = [rect(0, 0, 400, 32)]

// MARK: - Insets (CW-D)

/// Reads the insets the root is stamped with.
@MainActor private final class InsetsLog { var last: Edges<Pixels>? }

private struct InsetsReader: Component {
    @Environment(\.titleBarInsets) var insets
    let log: InsetsLog
    var content: some ElementGroup {
        let _ = log.noteInsets(insets)
        Color.clear.frame(width: Pixels(400), height: Pixels(300))
    }
}

extension InsetsLog {
    fileprivate func noteInsets(_ insets: Edges<Pixels>) -> Int { last = insets; return 0 }
}

/// **2.1** (`CW-D`). Under the hidden style an SDL-like platform's insets reach the root: the band 32 and
/// the 138-point cluster on the right; `drawsWindowControls = false` zeroes the cluster side only.
/// Mutation: `effectiveTitleBarInsets` ignores `drawsWindowControls` (the second expectation reddens).
@Test @MainActor func aHiddenStyleOnAnSDLLikePlatformStampsBandAndClusterInsets() throws {
    let log = InsetsLog()
    let window = try chromeWindow(controls: true) { VStack(spacing: Pixels(0)) { InsetsReader(log: log) } }
    let withControls = try #require(log.last)
    #expect(withControls.top == Pixels(32) && withControls.right == Pixels(138))
    #expect(withControls.left == Pixels(0) && withControls.bottom == Pixels(0))
    window.window.drawsWindowControls = false
    window.tick()
    let without = try #require(log.last)
    #expect(without.top == Pixels(32), "the band stays: the app still has a hidden bar")
    #expect(without.right == Pixels(0), "the cluster is the app's now")
}

/// **2.2** (`CW-B`, `CW-J`). A standard-style window reads zero insets, whatever the platform could answer.
@Test @MainActor func aStandardStyleWindowReadsZeroInsets() throws {
    let log = InsetsLog()
    _ = try chromeWindow(style: .automatic) { VStack(spacing: Pixels(0)) { InsetsReader(log: log) } }
    let insets = try #require(log.last)
    #expect(insets.top == Pixels(0) && insets.right == Pixels(0))
}

// MARK: - Regions (CW-E)

/// **2.3** (`CW-E`). With nothing in the band it is one region, published to the platform.
/// Mutation: publish `[]`, or drop the band candidate.
@Test @MainActor func theBandIsOneRegionWhenNothingIsInIt() throws {
    let window = try chromeWindow(controls: false) {
        bandPage { Color.clear.frame(width: Pixels(400), height: Pixels(32)) } body: {
            Color.clear.frame(width: Pixels(400), height: Pixels(268))
        }
    }
    #expect(window.windowDragRegions == wholeBand)
}

/// **2.4** (`CW-E`). A `Button` in the band is carved out: the regions are the band around its hitbox.
/// Mutation: drop `onClick` from the blocker predicate.
@Test @MainActor func aButtonInTheBandIsCarvedOut() throws {
    let window = try chromeWindow(controls: false) {
        blockerBand(height: 24) {
            Button(action: {}) { Color.clear.frame(width: Pixels(80), height: Pixels(24)) }.buttonStyle(.plain)
        }
    }
    #expect(window.windowDragRegions == [rect(0, 0, 20, 24), rect(100, 0, 300, 24), rect(0, 24, 400, 8)])
}

/// **2.5** (`CW-E`). A tap gesture is a blocker (it needs the press). Mutation: drop gesture members from
/// the blocker predicate.
@Test @MainActor func aTapGestureInTheBandIsCarvedOut() throws {
    let window = try chromeWindow(controls: false) {
        blockerBand(height: 32) {
            Color.clear.frame(width: Pixels(80), height: Pixels(32)).onTapGesture {}
        }
    }
    #expect(window.windowDragRegions == [rect(0, 0, 20, 32), rect(100, 0, 300, 32)])
}

/// **2.6** (`CW-E`). A text field is a blocker (`textInput`). Mutation: drop `textInput` from the predicate.
@Test @MainActor func aTextFieldInTheBandIsCarvedOut() throws {
    let window = try chromeWindow(controls: false) {
        blockerBand(height: 24) {
            TextField("Name", text: .constant("")).frame(width: Pixels(80), height: Pixels(24))
        }
    }
    // The field's own box is 25 tall inside its 24-point frame (its chrome, measured): the carve follows the
    // hitbox, not the frame.
    #expect(window.windowDragRegions == [rect(0, 0, 20, 25), rect(100, 0, 300, 25), rect(0, 25, 400, 7)])
}

/// **2.7** (`CW-E`). A hover region is **not** a blocker (a root-level hover would forbid all drag) — the
/// band stays whole and loses its pointer events inside the region (divergence 425). Mutation: count a
/// hover region as a blocker.
@Test @MainActor func aHoverRegionInTheBandIsNotABlocker() throws {
    let window = try chromeWindow(controls: false) {
        blockerBand(height: 32) {
            Color.clear.frame(width: Pixels(80), height: Pixels(32)).onHover { _ in }
        }
    }
    #expect(window.windowDragRegions == wholeBand)
}

/// **2.8** (`CW-E`, `WD-C`). A `WindowDragGesture` handle outside the band is a region of its own, after the
/// band in reading order. Mutation: ignore handles.
@Test @MainActor func aWindowDragHandleOutsideTheBandIsARegion() throws {
    let window = try chromeWindow(controls: false) {
        bandPage { Color.clear.frame(width: Pixels(400), height: Pixels(32)) } body: {
            HStack(spacing: Pixels(0)) {
                Color.clear.frame(width: Pixels(50), height: Pixels(100))
                Color.clear.frame(width: Pixels(100), height: Pixels(100)).gesture(WindowDragGesture())
                Color.clear.frame(width: Pixels(250), height: Pixels(100))
            }
            Color.clear.frame(width: Pixels(400), height: Pixels(168))
        }
    }
    #expect(window.windowDragRegions == [rect(0, 0, 400, 32), rect(50, 32, 100, 100)])
}

/// **2.9** (`CW-E`, divergence 426). A handle with a button inside is draggable only around it.
/// Mutation: treat the handle's own gesture as a blocker (no handle region at all), or skip the carve.
@Test @MainActor func aHandleWithAButtonInsideIsRegionsAroundIt() throws {
    let window = try chromeWindow(controls: false) {
        bandPage { Color.clear.frame(width: Pixels(400), height: Pixels(32)) } body: {
            ZStack(alignment: .topLeading) {
                Color.clear.frame(width: Pixels(200), height: Pixels(40)).gesture(WindowDragGesture())
                Button(action: {}) { Color.clear.frame(width: Pixels(60), height: Pixels(40)) }.buttonStyle(.plain)
            }
            Color.clear.frame(width: Pixels(400), height: Pixels(228))
        }
    }
    #expect(window.windowDragRegions == [rect(0, 0, 400, 32), rect(60, 32, 140, 40)])
}

/// **2.10** (`CW-E`). An open presentation publishes an empty list so a press outside reaches `Window` and
/// dismisses: a drawn alert here. Mutation: ignore presentations.
@Test @MainActor func anOpenAlertPublishesNoRegions() throws {
    let model = ChromeAlertModel()
    var options = HeadlessPlatformWindow.Options.sdlChrome
    options.presentsAlertsNatively = false
    let window = try chromeWindow(options: options, controls: false) {
        VStack(spacing: Pixels(0)) { ChromeAlertPage(model: model) }
    }
    #expect(window.windowDragRegions == wholeBand)
    model.isPresented = true
    window.window.setNeedsRedraw()
    window.tick()
    window.tick()
    #expect(window.windowDragRegions.isEmpty, "the drawn alert is open")
    model.isPresented = false
    window.window.setNeedsRedraw()
    window.tick()
    window.tick()
    #expect(window.windowDragRegions == wholeBand, "and the band returns when it closes")
}

@MainActor @Observable final class ChromeAlertModel { var isPresented = false }

private struct ChromeAlertPage: Component {
    let model: ChromeAlertModel
    var content: some ElementGroup {
        Color.clear.frame(width: Pixels(400), height: Pixels(300))
            .alert("Sure?", isPresented: Binding(get: { model.isPresented }, set: { model.isPresented = $0 })) {
                Button("OK") {}
            }
    }
}

/// **2.11** (`CW-M` 3). The `$windowcontrols` strip is not an open presentation: with it drawn the band is
/// published minus the cluster, never emptied. Mutation: count the strip as a presentation.
@Test @MainActor func theStripDoesNotEmptyTheRegions() throws {
    let window = try chromeWindow(controls: true) {
        bandPage { Color.clear.frame(width: Pixels(400), height: Pixels(32)) } body: {
            Color.clear.frame(width: Pixels(400), height: Pixels(268))
        }
    }
    #expect(window.windowDragRegions == [rect(0, 0, 262, 32)], "the three 46 x 32 buttons are carved out")
}

/// **2.12** (`CW-E`). Regions reach the platform only on change: further frames publish nothing, a real
/// change publishes once. Mutation: publish every frame.
@Test @MainActor func regionsArePublishedOnlyOnChange() throws {
    let window = try chromeWindow(controls: true) {
        bandPage { Color.clear.frame(width: Pixels(400), height: Pixels(32)) } body: {
            Color.clear.frame(width: Pixels(400), height: Pixels(268))
        }
    }
    let first = window.platformWindow.windowDragRegionPublishes
    try #require(first >= 1)
    window.window.setNeedsRedraw(); window.tick()
    window.window.setNeedsRedraw(); window.tick()
    window.window.setNeedsRedraw(); window.tick()
    #expect(window.platformWindow.windowDragRegionPublishes == first, "three more frames, no publish")
    window.window.drawsWindowControls = false
    window.tick()
    #expect(window.platformWindow.windowDragRegionPublishes == first + 1, "the cluster left: one publish")
    #expect(window.windowDragRegions == wholeBand)
}

/// **2.12b** (`CW-E`, `CW-Q` 6). A press in progress holds the published list still: with a button in the
/// body pressed, a change that would republish waits for the release. Mutation: drop the `active == nil`
/// guard (the first expectation reddens).
@Test @MainActor func aPressInProgressHoldsTheRegionsStill() throws {
    let window = try chromeWindow(controls: true) {
        bandPage { Color.clear.frame(width: Pixels(400), height: Pixels(32)) } body: {
            Button(action: {}) { Color.clear.frame(width: Pixels(400), height: Pixels(268)) }.buttonStyle(.plain)
        }
    }
    #expect(window.windowDragRegions == [rect(0, 0, 262, 32)])
    _ = window.send(.mouseDown(MouseEvent(position: pt(200, 150))))
    window.window.drawsWindowControls = false
    window.tick()
    #expect(window.windowDragRegions == [rect(0, 0, 262, 32)], "the press holds the list")
    _ = window.send(.mouseUp(MouseEvent(position: pt(200, 150))))
    window.tick()
    #expect(window.windowDragRegions == wholeBand, "and the release lets the change through")
}

/// **2.13** (`CW-F`, `CW-J`). A platform answering `false` is asked once and never computed for: AppKit's
/// answers, the hidden style applied, several frames — one call, no region work.
/// Mutation: ignore the answer and compute anyway (the carve counter reddens).
@Test @MainActor func aPlatformDecliningRegionsIsNeverAskedAgain() throws {
    let window = try chromeWindow(options: .init(), controls: true) {
        bandPage { Color.clear.frame(width: Pixels(400), height: Pixels(32)) } body: {
            Color.clear.frame(width: Pixels(400), height: Pixels(268))
        }
    }
    for _ in 0..<3 { window.window.setNeedsRedraw(); window.tick() }
    #expect(window.platformWindow.windowDragRegionPublishes == 1, "asked once, with an empty list")
    #expect(window.window.testingChromeCarveCount == 0)
}

/// **2.14** (`CW-J`). A standard-style window is untouched: no strip, no actions, no regions, no carve.
@Test @MainActor func aStandardStyleWindowIsUntouched() throws {
    let window = try chromeWindow(style: .automatic) {
        bandPage { Color.clear.frame(width: Pixels(400), height: Pixels(32)) } body: {
            Color.clear.frame(width: Pixels(400), height: Pixels(268))
        }
    }
    window.window.setNeedsRedraw(); window.tick()
    #expect(window.windowDragRegions.isEmpty)
    #expect(window.platformWindow.windowActions.isEmpty)
    #expect(window.window.testingChromeCarveCount == 0, "no hidden style and no handle: no carve")
    #expect((try? window.element(label: "Close")) == nil)
    #expect(window.platformWindow.titleBarStyles.isEmpty)
}

/// **2.15** (`CW-M` 1). Regions are in the unit every platform position uses — window points — so on a 2x
/// window a blocker's region is its point rect, not doubled. Mutation: multiply by the scale.
@Test @MainActor func regionsAreInWindowPointsOnA2xWindow() throws {
    let window = try chromeWindow(controls: false, scale: 2) {
        blockerBand(height: 32) {
            Color.clear.frame(width: Pixels(80), height: Pixels(32)).onTapGesture {}
        }
    }
    #expect(window.windowDragRegions == [rect(0, 0, 20, 32), rect(100, 0, 300, 32)])
}

// MARK: - The drawn strip (CW-C, CW-M)

/// **2.16** (`CW-C`). Where the platform has no native buttons the hidden style draws three, with their
/// accessibility labels, right-aligned in the cluster. Mutation: draw nothing.
@Test @MainActor func theStripDrawsThreeButtonsWhereThePlatformHasNone() throws {
    let window = try chromeWindow(controls: true) { Color.clear.frame(width: Pixels(400), height: Pixels(300)) }
    let minimise = try window.element(label: "Minimise")
    let zoom = try window.element(label: "Zoom")
    let close = try window.element(label: "Close")
    #expect([minimise, zoom, close].allSatisfy { $0.role == .button })
    #expect(minimise.frame == rect(262, 0, 46, 32))
    #expect(zoom.frame == rect(308, 0, 46, 32))
    #expect(close.frame == rect(354, 0, 46, 32))
}

/// **2.17** (`CW-C`). A platform with native window buttons (AppKit's traffic lights) draws no strip.
@Test @MainActor func aNativeControlsPlatformDrawsNoStrip() throws {
    var options = HeadlessPlatformWindow.Options.sdlChrome
    options.hasNativeWindowControls = true
    let window = try chromeWindow(options: options, controls: true) {
        Color.clear.frame(width: Pixels(400), height: Pixels(300))
    }
    #expect((try? window.element(label: "Close")) == nil)
}

/// **2.18** (`CW-C`, `CW-D`). `drawsWindowControls = false` draws no strip and zeroes the cluster inset;
/// turning it back on restores both.
@Test @MainActor func drawsWindowControlsFalseDrawsNoStripAndZeroesTheCluster() throws {
    let log = InsetsLog()
    let window = try chromeWindow(controls: false) { VStack(spacing: Pixels(0)) { InsetsReader(log: log) } }
    #expect((try? window.element(label: "Close")) == nil)
    #expect(try #require(log.last).right == Pixels(0))
    window.window.drawsWindowControls = true
    window.tick()
    #expect((try? window.element(label: "Close")) != nil)
    #expect(try #require(log.last).right == Pixels(138))
}

/// **2.19** (`CW-C`, `AS-B`). The close button goes through the close veto, as the system button does:
/// `.cancel` keeps the window, `.now` closes it. Mutation: the button calls `close()` (the first
/// expectation reddens).
@Test @MainActor func theCloseButtonGoesThroughTheCloseVeto() throws {
    let window = try chromeWindow(controls: true) { Color.clear.frame(width: Pixels(400), height: Pixels(300)) }
    let script = CloseScript()
    window.window.onCloseRequest = { script.asked += 1; return script.reply }
    try window.click(try window.element(label: "Close"))
    #expect(script.asked == 1)
    #expect(!window.platformWindow.isClosed, "the veto kept the window")
    script.reply = .now
    try window.click(try window.element(label: "Close"))
    #expect(script.asked == 2)
    #expect(window.platformWindow.isClosed)
}

@MainActor private final class CloseScript {
    var asked = 0
    var reply = CloseRequestReply.cancel
}

/// **2.20** (`CW-C`). Minimise and zoom send their actions to the platform, in order, once each.
/// Mutation: swap the two actions.
@Test @MainActor func theMinimiseAndZoomButtonsSendTheirActions() throws {
    let window = try chromeWindow(controls: true) { Color.clear.frame(width: Pixels(400), height: Pixels(300)) }
    try window.click(try window.element(label: "Minimise"))
    #expect(window.platformWindow.windowActions == [.minimize])
    try window.click(try window.element(label: "Zoom"))
    #expect(window.platformWindow.windowActions == [.minimize, .toggleZoom])
}

/// **2.21** (`CW-C`). The zoom button reads "Restore" while the window is zoomed, and `Window.isZoomed`
/// reads the platform's. Mutation: a constant label.
@Test @MainActor func zoomShowsRestoreAfterIsZoomed() throws {
    let window = try chromeWindow(controls: true) { Color.clear.frame(width: Pixels(400), height: Pixels(300)) }
    #expect(!window.window.isZoomed)
    try window.click(try window.element(label: "Zoom"))
    #expect(window.platformWindow.isZoomed, "the headless window flips like a platform that honoured it")
    #expect(window.window.isZoomed)
    window.tick()
    #expect((try? window.element(label: "Restore")) != nil)
    #expect((try? window.element(label: "Zoom")) == nil)
}

/// **2.22** (`CW-C`). The verbs on `Window` reach the platform: `minimize()` and `toggleZoom()`.
@Test @MainActor func theWindowVerbsReachThePlatform() throws {
    let window = try chromeWindow(controls: false) { Color.clear.frame(width: Pixels(400), height: Pixels(300)) }
    window.window.minimize()
    window.window.toggleZoom()
    #expect(window.platformWindow.windowActions == [.minimize, .toggleZoom])
}

/// **2.23** (`CW-D`). Fullscreen has no band: with the platform's insets zero the window draws no strip and
/// publishes no regions, even with a handle in it. Mutation: draw the strip whenever the style is hidden.
@Test @MainActor func fullscreenPublishesNoRegionsAndNoStrip() throws {
    let window = try chromeWindow(controls: true) {
        bandPage { Color.clear.frame(width: Pixels(400), height: Pixels(32)) } body: {
            Color.clear.frame(width: Pixels(400), height: Pixels(100)).gesture(WindowDragGesture())
            Color.clear.frame(width: Pixels(400), height: Pixels(168))
        }
    }
    try #require(!window.windowDragRegions.isEmpty)
    window.platformWindow.titleBarInsets = Edges(all: Pixels(0))
    window.resize(to: windowSize)
    window.tick()
    #expect(window.windowDragRegions.isEmpty)
    #expect((try? window.element(label: "Close")) == nil)
}

/// **2.24** (`CW-M` 4). The strip's buttons are focusable and **last** in Tab order: content first, then
/// Minimise, Zoom, Close. Mutation: prepaint the strip before the root.
@Test @MainActor func theStripIsLastInTabOrder() throws {
    let window = try chromeWindow(controls: true) {
        VStack(spacing: Pixels(0)) {
            Button("Content") {}
            Color.clear.frame(width: Pixels(400), height: Pixels(200))
        }
    }
    var labels: [String?] = []
    for _ in 0..<4 {
        window.typeKey(.tab)
        labels.append(try window.focusedElement?.label)
    }
    #expect(labels == ["Content", "Minimise", "Zoom", "Close"])
}

// MARK: - Headless honesty (HT-X 1)

/// **2.25** (`CW-F`). `Options.sdlChrome` is SDL's answers; the defaults are AppKit's. Mutation: flip any
/// field of the preset.
@Test @MainActor func theSDLChromePresetAnswersAsSDLDoes() {
    let sdl = HeadlessPlatformWindow.Options.sdlChrome
    #expect(sdl.usesWindowDragRegions && !sdl.hasNativeWindowControls && sdl.appliesTitleBarStyle)
    #expect(sdl.hiddenTitleBarInsets?.top == Pixels(32) && sdl.hiddenTitleBarInsets?.right == Pixels(138))
    #expect(sdl.hiddenTitleBarInsets?.left == Pixels(0) && sdl.hiddenTitleBarInsets?.bottom == Pixels(0))
    let appKit = HeadlessPlatformWindow.Options()
    #expect(!appKit.usesWindowDragRegions && appKit.hasNativeWindowControls && !appKit.isZoomed)
    #expect(appKit.hiddenTitleBarInsets == nil)
}
