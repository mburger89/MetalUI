import MetalUICore
import MetalUIPlatform

// SDL custom chrome, lane 1 (rulings `CW-C`…`CW-F`, `CW-J`, `CW-M`; spec
// `docs/superpowers/specs/2026-10-13-sdl-chrome-design.md`). The window half: the three verbs an app-drawn
// control calls, the drawn buttons' spec, and the region publication — after each build, only for a
// platform that said it uses regions, `Window` hands the platform the rects where a press may move the
// window. **A region function over the last frame's hitbox list, not a point lookup** (`CW-J`): the one
// ranking, `topmostHitbox(in:at:where:)`, is not duplicated; this reads the list's rects.

/// `Window`'s chrome state, one stored value (`Window.shell` holds it).
struct WindowChromeState {
    /// ``Window/drawsWindowControls``.
    var drawsWindowControls = true
    /// The platform's answer to its first `setWindowDragRegions`; `nil` until asked (once, with `[]`).
    var platformUsesDragRegions: Bool?
    /// The list the platform last got; `nil` before the ask (`CW-E`: published only on change).
    var publishedDragRegions: [Bounds<Pixels>]?
    /// How many region computations ran (tests; `testingChromeCarveCount`).
    var carveCount = 0
    /// ``Window/backgroundDragBehavior`` (`BG-G`).
    var backgroundDragBehavior = WindowInteractionBehavior.automatic
}

extension Window {
    /// Whether the window draws its own close, minimise and zoom buttons under `.hiddenTitleBar` where the
    /// platform has none (SDL: ruling `CW-C`, MetalUI-only — SwiftUI has no window-control API, probe
    /// `swiftui-window-chrome.swift`). Default `true`. Set it to `false` to draw your own, calling
    /// ``performClose()``, ``minimize()`` and ``toggleZoom()``: the cluster's inset in
    /// `EnvironmentValues.titleBarInsets` then reads zero, the band's stays. No effect on AppKit (the
    /// traffic lights stay) or under the standard style.
    public var drawsWindowControls: Bool {
        get { shell.chrome.drawsWindowControls }
        set {
            guard newValue != shell.chrome.drawsWindowControls else { return }
            shell.chrome.drawsWindowControls = newValue
            setNeedsRedraw()
        }
    }

    /// Minimises the window (ruling `CW-C`, MetalUI-only): AppKit's miniaturise, SDL's minimise. A platform
    /// that cannot do nothing; the answer is ignored.
    public func minimize() {
        _ = platformWindow.performWindowAction(.minimize)
    }

    /// Maximises the window, or restores it when it is zoomed (ruling `CW-C`, MetalUI-only): AppKit's
    /// `zoom(_:)`, SDL's maximise and restore.
    public func toggleZoom() {
        _ = platformWindow.performWindowAction(.toggleZoom)
        setNeedsRedraw()
    }

    /// Whether the window is zoomed (maximised) now (ruling `CW-C`): the platform's answer, read fresh.
    public var isZoomed: Bool { platformWindow.isZoomed }

    /// The drawn buttons for a build, or `nil` — the window's button-less path (`CW-C`): the hidden style is
    /// applied, the platform has no native window buttons, `drawsWindowControls` is on, and the band has a
    /// height (fullscreen has none).
    func windowControlsSpec() -> WindowControlsSpec? {
        guard shell.titleBarStyleApplied, shell.chrome.drawsWindowControls,
              !platformWindow.hasNativeWindowControls else { return nil }
        let insets = platformWindow.titleBarInsets
        guard insets.top.value > 0 else { return nil }
        let onRight = !(insets.left.value > 0 && insets.right.value <= 0)
        return WindowControlsSpec(
            onRight: onRight, bandHeight: insets.top.value, isZoomed: platformWindow.isZoomed,
            minimize: { [weak self] in self?.minimize() },
            toggleZoom: { [weak self] in self?.toggleZoom() },
            close: { [weak self] in self?.performClose() })
    }

    // MARK: - Drag regions (`CW-E`, `CW-F`, `CW-J`)

    /// How many times the window computed its regions (tests; `CW-J`).
    var chromeCarveCount: Int { shell.chrome.carveCount }

    /// Publishes the drag regions after a build (`CW-E`): the platform is asked once, with `[]`; one that
    /// answered `false` is never computed for again; one that answered `true` gets the carved list when it
    /// differs from the last. A press in progress holds the list still.
    func publishChromeRegions() {
        if shell.chrome.platformUsesDragRegions == nil {
            let uses = platformWindow.setWindowDragRegions([])
            shell.chrome.platformUsesDragRegions = uses
            shell.chrome.publishedDragRegions = uses ? [] : nil
        }
        guard shell.chrome.platformUsesDragRegions == true, active == nil else { return }
        let regions = chromeRegions()
        guard regions != shell.chrome.publishedDragRegions else { return }
        shell.chrome.publishedDragRegions = regions
        _ = platformWindow.setWindowDragRegions(regions)
    }

    /// The regions now: empty while a presentation is open (a press outside must reach `Window` and
    /// dismiss), while the band is gone (fullscreen) and when there is no band and no handle; else the
    /// band and the handles minus every blocker (`ChromeRegions`).
    ///
    /// With ``backgroundDragBehavior`` `.enabled` the content rect is one more candidate, carved by every
    /// blocker and dropped whole when it would not fit the cap (`BG-I`); it is not offered while the
    /// window is zoomed. Without a band (fullscreen under the hidden style) there is still no region.
    private func chromeRegions() -> [Bounds<Pixels>] {
        if drawnAlert != nil || menuSession != nil || !lastOpenPopovers.isEmpty { return [] }
        let hidden = shell.titleBarStyleApplied
        let band = hidden ? platformWindow.titleBarInsets.top.value : 0
        if hidden && band <= 0 { return [] }
        let handles = lastHitboxes.filter(ChromeRegions.isHandle)
        let size = platformWindow.contentSize
        let background = shell.chrome.backgroundDragBehavior.dragsFromBackground && !platformWindow.isZoomed
            ? Bounds(origin: Point(x: Pixels(0), y: Pixels(0)), size: size) : nil
        guard band > 0 || !handles.isEmpty || background != nil else { return [] }
        shell.chrome.carveCount += 1
        return ChromeRegions.compute(hitboxes: lastHitboxes, bandHeight: band, windowWidth: size.width.value,
                                     background: background)
    }
}
