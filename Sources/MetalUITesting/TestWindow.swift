import MetalUI
import MetalUIScene

/// A window under test (ruling `HT-C`; gpui's `VisualTestContext`, `HT-B`):
/// the real `Window` an `App.openWindow` returned, over a
/// ``HeadlessPlatformWindow``, with a simulated clock, input injection and
/// layout read-back.
///
/// **Every action delivers its events at ``now`` and then draws one frame**,
/// the frame a display link would draw next (ruling `HT-E`); ``send(_:)``
/// delivers one raw event and draws nothing. The clock starts at 0 and moves
/// only by ``advance(by:)`` and ``advanceFrames(_:)``; nothing reads a wall
/// clock but ``runUntil(timeout:_:)``'s failure bound (`HT-Y`). The window is one `Window` for its life, so every frame after the
/// first is **warm** — state, shaping, rasters and textures persist — and
/// ``lastFrameWork`` counts what each frame did (`HT-I`).
///
/// ```swift
/// let window = try TestWindow(size: Size(width: Pixels(640), height: Pixels(400))) { rootView() }
/// window.click(at: Point(x: Pixels(100), y: Pixels(40)))
/// #expect(try window.frame(ofID: "inspector").size.width == Pixels(248))
/// ```
///
/// MetalUI-only (`HT-B`).
@MainActor
public final class TestWindow {
    /// What ``TestApp`` hands a new window.
    struct Parts {
        let window: Window
        let platformWindow: HeadlessPlatformWindow
        let recorder: FrameWorkRecorder
    }

    /// The app this window belongs to (kept alive by the window).
    public let testApp: TestApp
    /// The real window: `keymap`, `environment`, `preferredColorScheme`,
    /// `onCloseRequest` and the rest are set on it as an app does.
    public let window: Window
    /// The headless platform window under ``window``.
    public let platformWindow: HeadlessPlatformWindow
    let recorder: FrameWorkRecorder

    /// The simulated clock, in seconds; 0 at open.
    public private(set) var now: Double = 0

    /// Where the simulated pointer is, or `nil` before any pointer event and
    /// after ``exitPointer()``.
    var pointer: Point<Pixels>?
    /// The modifier keys held since the last ``pressModifiers(_:)``.
    var heldModifiers: EventModifiers = []
    /// The presentation tokens the harness has answered (lane 2,
    /// `TestWindowPresentations.swift`).
    var answered = AnsweredPresentations()

    init(testApp: TestApp, parts: Parts) {
        self.testApp = testApp
        self.window = parts.window
        self.platformWindow = parts.platformWindow
        self.recorder = parts.recorder
    }

    /// A window in an app of its own: ``TestApp/init(textSystem:)`` then
    /// ``TestApp/openWindow(title:size:minSize:maxSize:windowResizability:windowStyle:colorScheme:scaleFactor:options:recordsLayout:content:)``.
    /// `colorScheme` and `scaleFactor` override those two fields of
    /// `options`. Throws ``TestHarnessError/textSystemRequired`` off Apple
    /// platforms when `textSystem` is `nil`.
    public convenience init<Root: Element>(
        size: Size<Pixels> = Size(width: Pixels(800), height: Pixels(600)),
        colorScheme: ColorScheme = .light, scaleFactor: Float = 1,
        options: HeadlessPlatformWindow.Options = .init(),
        recordsLayout: Bool = true,
        textSystem: (@MainActor () -> any TextSystem)? = nil,
        content: @escaping @MainActor () -> Root
    ) throws {
        let app = try TestApp(textSystem: textSystem)
        var chosen = options
        chosen.appearance = colorScheme
        chosen.scaleFactor = scaleFactor
        let parts = try app.openParts(title: "Test", size: size, minSize: nil, maxSize: nil,
                                      windowResizability: .automatic, windowStyle: .automatic,
                                      colorScheme: colorScheme, scaleFactor: scaleFactor,
                                      options: chosen, recordsLayout: recordsLayout, content: content)
        self.init(testApp: app, parts: parts)
        app.register(self)
    }

    // MARK: Clock and frames (`HT-E`)

    /// How many frames the window has presented (`Window.framesDrawn`).
    public var framesDrawn: Int { window.framesDrawn }

    /// How many times the window asked the platform to move it for a
    /// `WindowDragGesture` (`HeadlessPlatformWindow.windowDrags`, ruling `WD-E`).
    public var windowDrags: Int { platformWindow.windowDrags }

    /// The last drag-region list the window published to the platform (`CW-E`), in window points; empty
    /// before one (``HeadlessPlatformWindow/windowDragRegions``).
    public var windowDragRegions: [Bounds<Pixels>] { platformWindow.windowDragRegions }

    /// Every window action the platform was asked for, in order (`CW-F`).
    public var windowActions: [PlatformWindowAction] { platformWindow.windowActions }

    /// The last presented frame's scene, in device pixels.
    public var scene: Scene { platformWindow.headlessRenderer.lastScene }

    /// Fires one display-link tick at ``now``: the window draws if anything
    /// changed or an animation runs.
    public func tick() {
        window.testingFireDueTimelineWake(atTimestamp: now)
        platformWindow.simulateTick(timestamp: now)
    }

    /// Moves the clock on by `seconds` and fires one tick there — a long
    /// press matures, an animation advances, and a `TimelineView` whose next
    /// entry has come due is re-evaluated, with no `setNeedsRedraw()` first
    /// (`DX-A`): the window's timeline clock is the simulated one from its
    /// first frame (its dates are the window's creation date plus ``now``), and
    /// a periodic timeline's wake is held until a tick finds it due instead of
    /// sleeping on the wall clock.
    public func advance(by seconds: Double) {
        now += seconds
        tick()
    }

    /// Fires `count` ticks 1/60 s apart — the display link's pacing.
    public func advanceFrames(_ count: Int = 1) {
        for _ in 0..<max(0, count) {
            now += 1.0 / 60.0
            tick()
        }
    }

    /// How many consecutive quiet yields ``runUntilIdle()`` waits for
    /// (ruling `HT-S` item 1).
    static let quietYieldsForIdle = 4
    /// The most rounds ``runUntilIdle()`` runs before throwing.
    static let idleRoundLimit = 64

    /// Lets main-actor work — a `.task`'s continuation, an observation hop —
    /// run, drawing a frame whenever the window is dirty, **without moving the
    /// clock** (gpui's `run_until_parked`; ruling `HT-E` item 3, `HT-S`
    /// item 1). It returns once four yields in a row found the window clean (a
    /// running animation does not count: it needs the clock), and throws
    /// ``TestHarnessError/notIdle(rounds:)`` after 64 rounds. A task awaiting
    /// real time (`Task.sleep`) does not finish here: inject a clock.
    ///
    /// **A closed window is clean** (ruling `HT-Y` item 1): it draws nothing
    /// more (`AS-B` item 4), so a dirty flag left on it — by an approved
    /// termination or close that landed mid-settle — is no work to wait for,
    /// and the quiet yields still let what was queued behind the close run.
    ///
    /// It cannot see work off the main actor (a detached task, another
    /// actor): four quiet yields can come before that work hops back. To wait
    /// for such work, wait for its effect with ``runUntil(timeout:_:)``.
    public func runUntilIdle() async throws {
        var quiet = 0
        for _ in 0..<Self.idleRoundLimit {
            await Task.yield()
            if isDirtyAndOpen {
                quiet = 0
                tick()
            } else {
                quiet += 1
                if quiet >= Self.quietYieldsForIdle { return }
            }
        }
        throw TestHarnessError.notIdle(rounds: Self.idleRoundLimit)
    }

    /// Whether a tick would draw something a test waits for: the window is
    /// dirty and still open (`HT-Y` item 1).
    private var isDirtyAndOpen: Bool { window.needsRedraw && !platformWindow.isClosed }

    /// Lets main-actor work run, drawing a frame whenever the window is dirty,
    /// **until `condition` holds** — for work ``runUntilIdle()`` cannot see,
    /// such as a detached task or another actor's that writes back later
    /// (ruling `HT-Y` item 2). Each round draws first (when the window is
    /// dirty and open), then reads `condition`, so a condition about the
    /// window reads the frame its last write drew; then it yields. It never
    /// moves ``now``.
    ///
    /// `timeout` is the only wall-clock read in the harness and only bounds a
    /// failure: past it, ``TestHarnessError/timedOut(after:)`` is thrown. A
    /// slow machine waits longer; it does not fail sooner.
    ///
    /// ```swift
    /// try window.respondToAlert(button: "Save")   // the save runs off the main actor
    /// try await window.runUntil { window.testApp.platform.terminateReplies == [true] }
    /// ```
    public func runUntil(timeout: Duration = .seconds(10), _ condition: () throws -> Bool) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while true {
            if isDirtyAndOpen { tick() }
            if try condition() { return }
            if clock.now >= deadline { throw TestHarnessError.timedOut(after: timeout) }
            await Task.yield()
        }
    }

    /// Delivers one raw event through the platform window and draws nothing;
    /// answers what the window said.
    @discardableResult
    public func send(_ event: InputEvent) -> Bool {
        platformWindow.simulateInput(event)
    }

    // MARK: Platform simulation (`HT-K`)

    /// Resizes the content, then draws.
    public func resize(to size: Size<Pixels>) {
        platformWindow.simulateResize(to: size)
        tick()
    }

    /// Moves the window to a display of scale `scale`, then draws.
    public func setScaleFactor(_ scale: Float) {
        platformWindow.simulateScaleFactorChange(to: scale)
        tick()
    }

    /// Switches the system appearance, then draws.
    public func setAppearance(_ appearance: Appearance) {
        platformWindow.simulateAppearanceChange(to: appearance)
        tick()
    }

    /// Changes the window's key state, then draws.
    public func setControlActiveState(_ state: ControlActiveState) {
        platformWindow.simulateControlActiveStateChange(to: state)
        tick()
    }

    /// Changes Reduce Motion, then draws.
    public func setReduceMotion(_ value: Bool) {
        platformWindow.simulateReduceMotionChange(to: value)
        tick()
    }

    /// Changes Reduce Transparency, then draws (`MT-G`).
    public func setReduceTransparency(_ value: Bool) {
        platformWindow.simulateReduceTransparencyChange(to: value)
        tick()
    }

    /// Closes the window as the platform does, asking nobody: every
    /// `onDisappear` runs once (`LC-J`), and the app ends if it was the last.
    public func close() {
        platformWindow.close()
    }

    /// A user's close request: `Window.onCloseRequest` decides. Answers
    /// whether the window closed.
    @discardableResult
    public func requestClose() -> Bool {
        platformWindow.simulateCloseRequest()
    }

    // MARK: Layout (`HT-G` item 2)

    /// The laid-out rect of the one element named `name` with `.id(name)`, in
    /// window content space (logical points, top-left origin), from the last
    /// build — gpui's `debug_bounds`. Throws ``TestHarnessError/noElement(_:)``
    /// for none, ``TestHarnessError/ambiguous(_:count:)`` for several and
    /// ``TestHarnessError/notRecorded(_:)`` when the window records no layout.
    public func frame(ofID name: String) throws -> Bounds<Pixels> {
        let all = try frames(ofID: name)
        let query = "id \"\(name)\""
        guard let first = all.first else { throw TestHarnessError.noElement(query) }
        guard all.count == 1 else { throw TestHarnessError.ambiguous(query, count: all.count) }
        return first
    }

    /// The rects of every element named `name` with `.id(name)` (under
    /// different parents), top to bottom, then left to right.
    public func frames(ofID name: String) throws -> [Bounds<Pixels>] {
        guard recorder.recordsLayout else { throw TestHarnessError.notRecorded("layout") }
        let component = PathComponent.named(ElementID(name))
        return window.testingElementBounds
            .filter { $0.key.component == component }
            .map(\.value)
            .sorted { a, b in
                (a.origin.y.value, a.origin.x.value, a.size.width.value, a.size.height.value)
                    < (b.origin.y.value, b.origin.x.value, b.size.width.value, b.size.height.value)
            }
    }

    // MARK: Work (`HT-I`)

    /// The work of the last presented frame.
    public var lastFrameWork: FrameWork { recorder.last }

    /// The work of every frame presented since open or ``resetFrameWork()``.
    public var frameWork: [FrameWork] { recorder.history }

    /// Empties ``frameWork``.
    public func resetFrameWork() { recorder.history = [] }
}
