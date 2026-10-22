import MetalUI
import MetalUIPlatform
import MetalUITesting
import Observation
import Testing

// Presentation extras, lane 2: `Window.backgroundDragBehavior` (rulings `BG-G`...`BG-J`; spec
// `docs/superpowers/specs/2026-10-22-presentation-extras-design.md` tests 15-24). The headless platform answers as
// AppKit (`performTitleBarPress` recorded, no regions) or as SDL (`usesWindowDragRegions`: the real `Window`
// computes and publishes the regions the platform hit-tests). Plain imports, portable. Red before:
// `WindowInteractionBehavior` and `backgroundDragBehavior` do not exist, so the file does not compile.

private let windowSize = sz(400, 300)

/// An AppKit-like options value (no regions) whose hidden style applies with a 32-point band.
private let appKitBand = HeadlessPlatformWindow.Options(
    hiddenTitleBarInsets: Edges(top: Pixels(32), right: Pixels(0), bottom: Pixels(0), left: Pixels(0)))
/// An SDL-like options value without the hidden style's band: regions used, no chrome.
private let sdlRegions = HeadlessPlatformWindow.Options(usesWindowDragRegions: true)

/// A 400 x 300 window over `content` with `behavior` set and drawn.
@MainActor private func dragWindow<Root: Element>(
    options: HeadlessPlatformWindow.Options = .init(), style: WindowStyle = .automatic,
    behavior: WindowInteractionBehavior = .enabled, controls: Bool = true,
    _ content: @escaping @MainActor () -> Root
) throws -> TestWindow {
    let app = try TestApp(textSystem: harnessTextSystem)
    let window = try app.openWindow(size: windowSize, windowStyle: style, options: options, content: content)
    window.window.backgroundDragBehavior = behavior
    if !controls { window.window.drawsWindowControls = false }
    window.tick()
    return window
}

/// An empty 400 x 300 page: every point is background.
@MainActor private func emptyPage() -> some Element {
    VStack(spacing: Pixels(0)) { Color.clear.frame(width: Pixels(400), height: Pixels(300)) }
}

/// A 20-wide gap, a `blocker` 80 x 24, a gap to 400, over a 276-point body.
@MainActor private func blockerPage<Blocker: ProposalElementGroup>(
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

private let backgroundPoint = pt(200, 200)

/// 15 (`BG-G`, `BG-H`) - an unclaimed primary press on the background asks the platform for a title-bar drag
/// when enabled. Mutation: drop the behavior check (16 reddens too).
@Test @MainActor func anUnclaimedPrimaryPressOnTheBackgroundDragsWhenEnabled() throws {
    let window = try dragWindow { emptyPage() }
    window.click(at: backgroundPoint)
    #expect(window.platformWindow.titleBarPresses == [1], "\(window.platformWindow.titleBarPresses)")
}

/// 16 (`BG-G`) - `.automatic` and `.disabled` never drag, and neither does a window that never set it.
/// Mutation: treat `.automatic` as `.enabled`.
@Test @MainActor func automaticAndDisabledNeverDragFromTheBackground() throws {
    for behavior in [WindowInteractionBehavior.automatic, .disabled] {
        let window = try dragWindow(behavior: behavior) { emptyPage() }
        window.click(at: backgroundPoint)
        #expect(window.platformWindow.titleBarPresses.isEmpty, "\(behavior)")
    }
    let untouched = try TestApp(textSystem: harnessTextSystem).openWindow(size: windowSize) { emptyPage() }
    untouched.click(at: backgroundPoint)
    #expect(untouched.platformWindow.titleBarPresses.isEmpty, "the default is no background drag")
    #expect(untouched.window.backgroundDragBehavior == .automatic)
}

/// 17 (`BG-G`) - a press an opaque target, a gesture arena or a `WindowDragGesture` handle owns never drags
/// from the background (the handle keeps its own `performWindowDrag` path). Mutation: skip `active == nil`
/// (the `onClick` arm), skip the arena check (the gesture arms).
@Test @MainActor func aPressOnAnOpaqueTargetANestedGestureOrAHandleNeverDragsFromTheBackground() throws {
    let tap = try dragWindow {
        Color.clear.frame(width: Pixels(400), height: Pixels(300)).onClick {}
    }
    tap.click(at: backgroundPoint)
    #expect(tap.platformWindow.titleBarPresses.isEmpty, "an onClick target owns the press")

    let drag = try dragWindow {
        Color.clear.frame(width: Pixels(400), height: Pixels(300)).gesture(DragGesture())
    }
    drag.click(at: backgroundPoint)
    #expect(drag.platformWindow.titleBarPresses.isEmpty, "a DragGesture owns the press")

    let draggable = try dragWindow {
        Color.clear.frame(width: Pixels(400), height: Pixels(300)).draggable("payload")
    }
    draggable.click(at: backgroundPoint)
    #expect(draggable.platformWindow.titleBarPresses.isEmpty, "a draggable's arena owns the press")

    let handle = try dragWindow {
        Color.clear.frame(width: Pixels(400), height: Pixels(300)).gesture(WindowDragGesture())
    }
    handle.drag(from: backgroundPoint, to: pt(260, 240))
    #expect(handle.platformWindow.titleBarPresses.isEmpty, "a handle is not the background")
    #expect(handle.windowDrags == 1, "the handle runs its own performWindowDrag path: \(handle.windowDrags)")
}

/// 18 (`BG-H`) - a secondary press and the second press of a double click on the background do not drag; the
/// double-click action belongs to the title bar. Mutation: pass `mouse.clickCount` through (the double
/// click records `[2]`).
@Test @MainActor func aSecondaryPressAndADoubleClickOnTheBackgroundDoNotDrag() throws {
    let window = try dragWindow { emptyPage() }
    window.rightClick(at: backgroundPoint)
    #expect(window.platformWindow.titleBarPresses.isEmpty, "a secondary press")
    _ = window.send(.mouseDown(MouseEvent(position: backgroundPoint, clickCount: 2)))
    #expect(window.platformWindow.titleBarPresses.isEmpty, "a double click is not a background drag")
    _ = window.send(.mouseUp(MouseEvent(position: backgroundPoint, clickCount: 2)))
    _ = window.send(.mouseDown(MouseEvent(position: backgroundPoint, clickCount: 1)))
    #expect(window.platformWindow.titleBarPresses == [1], "a single press still drags")
}

/// 19 (`BG-J`) - the title band keeps `AS-J`'s drag and double click whatever the behavior. Mutation: gate
/// the band on `.enabled`.
@Test @MainActor func theTitleBandKeepsItsDragWhateverTheBehavior() throws {
    for behavior in [WindowInteractionBehavior.automatic, .enabled, .disabled] {
        let window = try dragWindow(options: appKitBand, style: .hiddenTitleBar, behavior: behavior) { emptyPage() }
        window.click(at: pt(200, 10))
        _ = window.send(.mouseDown(MouseEvent(position: pt(200, 10), clickCount: 2)))
        #expect(window.platformWindow.titleBarPresses == [1, 2], "\(behavior): \(window.platformWindow.titleBarPresses)")
    }
}

// MARK: - SDL regions (BG-I)

/// 20 (`BG-I`) - the background region is the window carved by every blocker, literal rects: a button leaves
/// the strips around it. Mutation: carve by handles only.
@Test @MainActor func theBackgroundRegionIsTheWindowCarvedByEveryBlocker() throws {
    let plain = try dragWindow(options: sdlRegions) { emptyPage() }
    #expect(plain.windowDragRegions == [rect(0, 0, 400, 300)])
    let window = try dragWindow(options: sdlRegions) {
        blockerPage { Button(action: {}) { Color.clear.frame(width: Pixels(80), height: Pixels(24)) }.buttonStyle(.plain) }
    }
    #expect(window.windowDragRegions == [rect(0, 0, 20, 24), rect(100, 0, 300, 24), rect(0, 24, 400, 276)],
            "\(window.windowDragRegions)")
    let hover = try dragWindow(options: sdlRegions) {
        blockerPage { Color.clear.frame(width: Pixels(80), height: Pixels(24)).onHover { _ in } }
    }
    #expect(hover.windowDragRegions == [rect(0, 0, 400, 300)],
            "a hover region is not a blocker: it loses its events inside the region (divergence 737)")
    let disabled = try dragWindow(options: sdlRegions, behavior: .disabled) { emptyPage() }
    #expect(disabled.windowDragRegions.isEmpty, "only .enabled publishes a background region")
}

/// 21 (`BG-I`, `CW-V`) - a window-wide opaque backdrop leaves no background region, though the band's
/// exemption still keeps the band (the separating arm). Mutation: reuse `isBackdrop` for the background.
@Test @MainActor func aWindowWideOpaqueBackdropLeavesNoBackgroundRegion() throws {
    let backdrop = try dragWindow(options: sdlRegions) {
        Color.clear.frame(width: Pixels(400), height: Pixels(300)).onTapGesture {}
    }
    #expect(backdrop.windowDragRegions.isEmpty, "\(backdrop.windowDragRegions)")
    let band = try dragWindow(options: .sdlChrome, style: .hiddenTitleBar, controls: false) {
        Color.clear.frame(width: Pixels(400), height: Pixels(300)).onTapGesture {}
    }
    #expect(band.windowDragRegions == [rect(0, 0, 400, 32)], "the band floats over it, the background does not")
}

@MainActor @Observable private final class ShownModel { var shown = false }

private struct ShownPage: Component {
    let model: ShownModel
    let alert: Bool
    var content: some ElementGroup {
        VStack(alignment: .leading, spacing: Pixels(0)) {
            if alert {
                Button("Open") { model.shown = true }
                    .alert("Sure?", isPresented: Binding(get: { model.shown }, set: { model.shown = $0 })) {
                        Button("OK") {}
                    }
            } else {
                Button("Open") { model.shown = true }
                    .popover(isPresented: Binding(get: { model.shown }, set: { model.shown = $0 })) {
                        Text("Popover").frame(width: Pixels(60), height: Pixels(20))
                    }
            }
            Color.clear.frame(width: Pixels(400), height: Pixels(260))
        }
    }
}

/// 22 (`BG-I`) - no background region while a popover or a drawn alert is open, and none while the window is
/// zoomed; the band keeps its rule when zoomed. Mutation: drop the zoomed arm.
@Test @MainActor func theBackgroundRegionIsEmptyWhileAPopoverADrawnAlertOrAMenuIsOpenAndWhileZoomed() throws {
    for alert in [false, true] {
        let model = ShownModel()
        var options = sdlRegions
        options.presentsAlertsNatively = false
        let window = try dragWindow(options: options) { VStack(spacing: Pixels(0)) { ShownPage(model: model, alert: alert) } }
        #expect(!window.windowDragRegions.isEmpty, "closed: a region (alert \(alert))")
        try window.click(window.element(label: "Open"))
        window.tick()
        #expect(window.windowDragRegions.isEmpty, "open: none (alert \(alert)): \(window.windowDragRegions)")
    }
    var zoomed = sdlRegions
    zoomed.isZoomed = true
    let plain = try dragWindow(options: zoomed) { emptyPage() }
    #expect(plain.windowDragRegions.isEmpty, "zoomed: no background drag: \(plain.windowDragRegions)")
    var zoomedBand = HeadlessPlatformWindow.Options.sdlChrome
    zoomedBand.isZoomed = true
    let band = try dragWindow(options: zoomedBand, style: .hiddenTitleBar, controls: false) { emptyPage() }
    #expect(band.windowDragRegions == [rect(0, 0, 400, 32)], "the band keeps its rule when zoomed")
    var menuOptions = sdlRegions
    menuOptions.presentsMenusNatively = false
    let menu = try dragWindow(options: menuOptions) {
        VStack(alignment: .leading, spacing: Pixels(0)) {
            Button("Target") {}.frame(width: Pixels(80), height: Pixels(24))
                .contextMenu { Button("Copy") {} }
            Color.clear.frame(width: Pixels(400), height: Pixels(276))
        }
    }
    #expect(!menu.windowDragRegions.isEmpty)
    try menu.rightClick(menu.element(label: "Target"))
    menu.tick()
    #expect(menu.windowDragRegions.isEmpty, "a drawn menu is open: \(menu.windowDragRegions)")
}

/// 23 (`BG-I`) - a background too fragmented to publish is dropped whole, never cut short: 40 staggered
/// buttons carve it into over 64 pieces; the band and the handle stay published. Mutation: keep the cut
/// list (a partial background appears).
@Test @MainActor func aTooFragmentedBackgroundIsDroppedWholeNotCutShort() throws {
    let window = try dragWindow(options: .sdlChrome, style: .hiddenTitleBar, controls: false) {
        VStack(alignment: .leading, spacing: Pixels(0)) {
            Color.clear.frame(width: Pixels(400), height: Pixels(32))
            HStack(alignment: .top, spacing: Pixels(0)) {
                Color.clear.frame(width: Pixels(100), height: Pixels(100)).gesture(WindowDragGesture())
                VStack(alignment: .leading, spacing: Pixels(2)) {
                    ForEach(0..<40, id: \.self) { index in
                        HStack(spacing: Pixels(0)) {
                            Color.clear.frame(width: Pixels(Float(120 + (index % 7) * 20)), height: Pixels(4))
                            Button(action: {}) { Color.clear.frame(width: Pixels(10), height: Pixels(4)) }
                                .buttonStyle(.plain)
                        }
                    }
                }
            }
            Color.clear.frame(width: Pixels(400), height: Pixels(30))   // 32 + 238 + 30: the column fills the window
        }
    }
    let regions = window.windowDragRegions
    #expect(regions.count <= 64)
    #expect(regions.first == rect(0, 0, 400, 32), "the band is still published")
    #expect(regions.contains(rect(0, 32, 100, 100)), "so is the handle: \(regions)")
    #expect(regions.count == 2, "and nothing of the background: \(regions)")
}

/// 24 (`BG-I`) - a change of behavior republishes the regions once, and an equal frame or an equal write
/// publishes nothing. Mutation: publish every frame, or let an equal write dirty the window.
@Test @MainActor func aChangeOfBehaviorRepublishesTheRegionsOnceAndNeverOnAnEqualFrame() throws {
    let window = try dragWindow(options: sdlRegions, behavior: .automatic) { emptyPage() }
    let first = window.platformWindow.windowDragRegionPublishes
    #expect(window.windowDragRegions.isEmpty)
    window.window.backgroundDragBehavior = .enabled
    window.tick()
    #expect(window.platformWindow.windowDragRegionPublishes == first + 1, "one publish for the change")
    #expect(window.windowDragRegions == [rect(0, 0, 400, 300)])
    window.window.backgroundDragBehavior = .enabled
    window.window.setNeedsRedraw(); window.tick()
    window.window.setNeedsRedraw(); window.tick()
    #expect(window.platformWindow.windowDragRegionPublishes == first + 1, "equal frames publish nothing")
    window.window.backgroundDragBehavior = .disabled
    window.tick()
    #expect(window.platformWindow.windowDragRegionPublishes == first + 2)
    #expect(window.windowDragRegions.isEmpty)
    // On an SDL-like platform the platform moves the window before `Window` sees the press: no title-bar press.
    window.window.backgroundDragBehavior = .enabled
    window.tick()
    window.click(at: backgroundPoint)
    #expect(window.platformWindow.titleBarPresses.isEmpty, "regions, not performTitleBarPress, on a region platform")
}
