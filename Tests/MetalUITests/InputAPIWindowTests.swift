import Testing
import Metal
import Observation
import MetalUICore
import MetalUIPlatform
@testable import MetalUI

// Input APIs, lane B — the scroll wheel on an element and the pointer style,
// through a real `Window` (rulings `CI-H`, `CI-I`, `CI-L`, `CI-Q`, `CI-S`,
// `CI-AD`, `CI-AH`; spec `docs/superpowers/specs/2026-10-08-input-apis-design.md`
// §1.3, §1.4, §4.3 tests 3.2–3.25 and 3.37's neighbours).
//
// Everything runs on a `FakePlatformWindow` — nothing sleeps. Geometry, unless
// a test says otherwise: a 300 × 300 window whose 200 × 200 root is centred at
// (50, 50)–(250, 250) (`CN-J`), so a window point (x, y) is the root's local
// point (x − 50, y − 50). `FakePlatformWindow.pointerStyles` records every
// `setPointerStyle` call.

// MARK: - Fixtures

@MainActor
private final class BLog {
    var entries: [String] = []
    var events: [ScrollEvent] = []
    var claims = true
    var shown = true
}

@Observable @MainActor
private final class BModel {
    var flag = false
    var shown = false
    var binding: Binding<Bool> { Binding(get: { self.shown }, set: { self.shown = $0 }) }
}

private func px(_ v: Float) -> Pixels { Pixels(v) }
private func pt(_ x: Float, _ y: Float) -> Point<Pixels> { Point(x: px(x), y: px(y)) }

private func wheel(_ x: Float, _ y: Float, dy: Float = -37, dx: Float = 0) -> InputEvent {
    .scrollWheel(ScrollEvent(position: pt(x, y), delta: pt(dx, dy)))
}
private func moved(_ x: Float, _ y: Float) -> InputEvent { .mouseMoved(MouseEvent(position: pt(x, y))) }
private func ldown(_ x: Float, _ y: Float) -> InputEvent { .mouseDown(MouseEvent(position: pt(x, y))) }
private func ldrag(_ x: Float, _ y: Float) -> InputEvent { .mouseDragged(MouseEvent(position: pt(x, y))) }
private func lup(_ x: Float, _ y: Float) -> InputEvent { .mouseUp(MouseEvent(position: pt(x, y))) }
private func rdown(_ x: Float, _ y: Float) -> InputEvent {
    .rightMouseDown(MouseEvent(position: pt(x, y), buttonNumber: 1))
}
private func rup(_ x: Float, _ y: Float) -> InputEvent {
    .rightMouseUp(MouseEvent(position: pt(x, y), buttonNumber: 1))
}
private func odown(_ x: Float, _ y: Float) -> InputEvent {
    .otherMouseDown(MouseEvent(position: pt(x, y), buttonNumber: 2))
}
private func odrag(_ x: Float, _ y: Float) -> InputEvent {
    .otherMouseDragged(MouseEvent(position: pt(x, y), buttonNumber: 2))
}
private func oup(_ x: Float, _ y: Float) -> InputEvent {
    .otherMouseUp(MouseEvent(position: pt(x, y), buttonNumber: 2))
}
private func magnify(_ delta: Double, _ phase: InputPhase, at p: Point<Pixels>) -> InputEvent {
    .magnify(MagnifyEvent(position: p, magnification: delta, phase: phase))
}
private let escapeKey = InputEvent.keyDown(KeyEvent(charactersIgnoringModifiers: "\u{1b}", characters: "\u{1b}",
                                                    modifiers: [], timestamp: 0))

/// A `size` × `size` window over `content`, drawn until clean. **A `Window` is
/// held only weakly by its platform window**, so every test keeps the window
/// to its end (`withExtendedLifetime`).
@MainActor
private func bWindow<Root: Element>(size: Int = 300, native: Bool = true,
                                    _ content: @escaping @MainActor () -> Root) throws
    -> (Window, FakePlatformWindow) {
    let device = try #require(MTLCreateSystemDefaultDevice(), "no Metal device; run on macOS hardware")
    let (window, platform) = try makeFakeWindow(device: device, size: size, content: content)
    platform.presentsMenusNatively = native
    platform.presentsAlertsNatively = false
    window.drawFrameIfNeeded()
    for _ in 0..<6 where window.needsRedraw { window.drawFrameIfNeeded() }
    return (window, platform)
}

@MainActor private func redraw(_ window: Window) {
    window.setNeedsRedraw()
    for _ in 0..<6 where window.needsRedraw { window.drawFrameIfNeeded() }
}

@MainActor private func settle(_ window: Window) {
    for _ in 0..<6 where window.needsRedraw { window.drawFrameIfNeeded() }
}

/// A 200 × 200 legacy box.
@MainActor private func square() -> ModifiedElement<Box<EmptyGroup>> {
    Box().frame(width: px(200), height: px(200))
}

/// A 200 × 200 proposal rectangle.
@MainActor private func proposalSquare() -> some ProposalElementGroup {
    Rectangle().frame(width: px(200), height: px(200))
}

/// A 40-tall, `width`-wide legacy row.
@MainActor private func row(_ width: Float = 100) -> ModifiedElement<Box<EmptyGroup>> {
    Box().frame(width: px(width), height: px(40))
}

/// The scroll region's stored offset (the window's only scroller).
@MainActor
private func scrollOffset(_ window: Window, sourceLocation: SourceLocation = #_sourceLocation) throws -> Double {
    let region = try #require(window.lastHitboxes.first { $0.scroll != nil }, "a scroll region",
                              sourceLocation: sourceLocation)
    var offset = 0.0
    window.stateTable.withState(region.id, initial: ScrollState()) { offset = $0.offset }
    return offset
}

private func close(_ a: Point<Pixels>?, _ b: Point<Pixels>) -> Bool {
    guard let a else { return false }
    return abs(a.x.value - b.x.value) < 0.01 && abs(a.y.value - b.y.value) < 0.01
}

// MARK: - 3.2: the event, local, under StateDispatch

/// A `Component` whose 200 × 200 legacy box accumulates the wheel's `delta.y`
/// in `@State` and logs each event.
private struct WheelingBox: Component {
    let log: BLog
    @State var total = 0.0
    var content: some ElementGroup {
        Box().frame(width: Pixels(200), height: Pixels(200))
            .onScrollWheel { event in
                log.events.append(event)
                total += Double(event.delta.y.value)
                return true
            }
    }
}

/// The same over proposal content.
private struct WheelingRectangle: Component, ProposalElementGroup {
    let log: BLog
    @State var total = 0.0
    var content: some ProposalElementGroup {
        Rectangle().frame(width: Pixels(200), height: Pixels(200))
            .onScrollWheel { event in
                log.events.append(event)
                total += Double(event.delta.y.value)
                return true
            }
    }
}

/// **3.2** (`CI-I` items 1, 2, 4). `.onScrollWheel` receives the event on both
/// vocabularies — `delta`, `phase`, `momentumPhase`, `isPrecise` and
/// `modifiers` passed through, `position` the window point and `location` the
/// element's local point ((60, 80) on the root at (50, 50) → (10, 30)) — its
/// `@State` write landing under `StateDispatch`; the claimed event returns
/// `true`. Mutation: pass `position` as `location`.
@MainActor
@Test func onScrollWheelReceivesTheEventInLocalSpaceUnderStateDispatch() throws {
    let log = BLog()
    let (legacy, legacyPlatform) = try bWindow { Column { WheelingBox(log: log) } }
    let (proposal, proposalPlatform) = try bWindow { VStack { WheelingRectangle(log: log) } }
    let event = ScrollEvent(position: pt(60, 80), delta: pt(3, -7), modifiers: [.command],
                            phase: .changed, momentumPhase: .began, isPrecise: false, timestamp: 0)
    for (window, platform) in [(legacy, legacyPlatform), (proposal, proposalPlatform)] {
        let region = try #require(window.lastHitboxes.first { $0.handlers.pointer?.scrollWheel != nil },
                                  "the wheel region")
        let component = try #require(region.id.parent)
        #expect(platform.simulateInput(.scrollWheel(event)), "claimed")
        // `total` is the second stored property (after `log`): slot 1.
        let total = window.stateTable.peek(GlobalElementID.child(of: component, at: 1, name: ElementID("$state1")),
                                           as: Double.self)
        #expect(total == -7, "the @State write landed: \(String(describing: total))")
    }
    try #require(log.events.count == 2, "both vocabularies ran: \(log.events.count)")
    for got in log.events {
        #expect(close(got.location, pt(10, 30)), "local: \(got.location)")
        #expect(close(got.position, pt(60, 80)), "window: \(got.position)")
        #expect(close(got.delta, pt(3, -7)) && got.modifiers == [.command])
        #expect(got.phase == .changed && got.momentumPhase == .began && !got.isPrecise)
    }
    withExtendedLifetime((legacy, proposal)) {}
}

// MARK: - 3.3–3.6: coexisting with ScrollView (`DD-Y`)

/// A 100 × 100 vertical scroller over four 100 × 40 rows, the first carrying
/// `handler`.
@MainActor
private func scrollerWithHandlerOnFirstRow(_ log: BLog) -> some Element {
    ScrollView(.vertical, elementID: ElementID("list")) {
        Column {
            row().onScrollWheel { _ in log.entries.append("row"); return log.claims }
            row(); row(); row()
        }
    }
}

/// **3.3** (`CI-I` item 4). A wheel handler inside a `ScrollView` that claims
/// stops it: the handler runs, the offset stays 0; off the handler's row the
/// scroller scrolls (the separating arm). Mutation: consult each id's scroll
/// region before its descendants' handlers (outermost first).
@MainActor
@Test func aWheelHandlerThatClaimsStopsAnEnclosingScrollView() throws {
    let log = BLog()
    let (window, platform) = try bWindow(size: 100) { scrollerWithHandlerOnFirstRow(log) }
    #expect(platform.simulateInput(wheel(20, 20)), "claimed")
    #expect(log.entries == ["row"], "\(log.entries)")
    #expect(try scrollOffset(window) == 0, "the claiming handler stopped the scroller")
    platform.simulateInput(wheel(20, 60))
    #expect(try scrollOffset(window) == 37, "off the row the scroller takes it")
    #expect(log.entries == ["row"])
    withExtendedLifetime(window) {}
}

/// **3.4** (`CI-I` items 2, 4). A handler that returns `false` passes the
/// wheel on: it runs, then the enclosing scroller scrolls. Mutation: treat
/// `false` as claimed.
@MainActor
@Test func aWheelHandlerThatDeclinesPassesToTheEnclosingScrollView() throws {
    let log = BLog()
    log.claims = false
    let (window, platform) = try bWindow(size: 100) { scrollerWithHandlerOnFirstRow(log) }
    #expect(platform.simulateInput(wheel(20, 20)), "the scroller claimed it")
    #expect(log.entries == ["row"], "\(log.entries)")
    #expect(try scrollOffset(window) == 37, "declined, so the scroller scrolled")
    withExtendedLifetime(window) {}
}

/// **3.5** (`CI-I` item 4, `CI-V` item 2). A handler outside a `ScrollView`
/// sees only what the scroller left — nothing, since a scroller always claims:
/// a legacy column's handler around a scroller, and a **proposal**
/// `.onScrollWheel` written on a `ProposalScrollView` (its own identity level,
/// the scroller's parent), each run for a wheel over their strip above the
/// scroller (the separating arm) and not for one over the scroller. Mutations:
/// call every handler on the chain (the legacy arm reddens); consult a
/// wrapper's handler before its child's scroll region (the proposal arm).
@MainActor
@Test func aWheelHandlerOutsideAScrollViewSeesNothingTheScrollerClaimed() throws {
    let log = BLog()
    let (legacy, legacyPlatform) = try bWindow(size: 100) {
        Column {
            row()
            ScrollView(.vertical) { Column { row(); row(); row() } }.frame(width: px(100), height: px(60))
        }
        .onScrollWheel { _ in log.entries.append("legacy"); return true }
    }
    let (proposal, proposalPlatform) = try bWindow(size: 100) {
        VStack(spacing: 0) {
            Rectangle().frame(width: px(100), height: px(40))
                .onScrollWheel { _ in log.entries.append("strip"); return true }
            ProposalScrollView(.vertical) {
                VStack(spacing: 0) {
                    Rectangle().frame(width: px(100), height: px(40))
                    Rectangle().frame(width: px(100), height: px(40))
                    Rectangle().frame(width: px(100), height: px(40))
                }
            }
            .frame(width: px(100), height: px(60))
            .onScrollWheel { _ in log.entries.append("proposal"); return true }
        }
    }
    legacyPlatform.simulateInput(wheel(50, 20))
    #expect(log.entries == ["legacy"], "over the strip the column's handler runs: \(log.entries)")
    legacyPlatform.simulateInput(wheel(50, 70))
    #expect(log.entries == ["legacy"], "over the scroller it sees nothing: \(log.entries)")
    #expect(try scrollOffset(legacy) == 37)
    log.entries = []
    proposalPlatform.simulateInput(wheel(50, 20))
    #expect(log.entries == ["strip"], "\(log.entries)")
    proposalPlatform.simulateInput(wheel(50, 70))
    #expect(log.entries == ["strip"], "the proposal wrapper on the scroller sees nothing: \(log.entries)")
    #expect(try scrollOffset(proposal) == 37)
    withExtendedLifetime((legacy, proposal)) {}
}

/// **3.6** (`CI-AH` item 1, amending `CI-I` item 4's "a legacy `.onScrollWheel`
/// on a `ScrollView` itself (same id)": no spelling gives a handler the
/// scroller's own id). A handler on a `ScrollView`'s **content** runs before
/// its scrolling and can veto it (claim: offset 0; decline: 37); a legacy
/// `.onScrollWheel` written on the `ScrollView` (a `ModifiedContent` layer,
/// the scroller's parent) sees nothing. Mutation: consult the chain's scroll
/// regions before any handler.
@MainActor
@Test func aWheelHandlerOnAScrollViewsContentRunsBeforeItsScrollingAndCanVetoIt() throws {
    let log = BLog()
    let (window, platform) = try bWindow(size: 100) {
        ScrollView(.vertical) {
            Column { row(); row(); row(); row() }
                .onScrollWheel { _ in log.entries.append("content"); return log.claims }
        }
        .frame(width: px(100), height: px(100))
        .onScrollWheel { _ in log.entries.append("wrapper"); return true }
    }
    platform.simulateInput(wheel(50, 50))
    #expect(log.entries == ["content"], "\(log.entries)")
    #expect(try scrollOffset(window) == 0, "the content vetoed the scroll")
    log.claims = false
    platform.simulateInput(wheel(50, 50))
    #expect(log.entries == ["content", "content"], "the wrapper sees nothing: \(log.entries)")
    #expect(try scrollOffset(window) == 37, "declined, so it scrolled")
    withExtendedLifetime(window) {}
}

// MARK: - 3.7–3.9: canvases, overlays, gates

/// **3.7** (`CI-I` item 4). A wheel over a click target inside a canvas reaches
/// the canvas's handler (the target's ancestor), claimed. Mutation: stop at the
/// opaque cover.
@MainActor
@Test func aWheelOverAClickTargetInsideACanvasReachesTheCanvasHandler() throws {
    let log = BLog()
    let (window, platform) = try bWindow {
        ZStack {
            Rectangle().frame(width: px(50), height: px(50)).onTapGesture { log.entries.append("tap") }
        }
        .frame(width: px(200), height: px(200))
        .onScrollWheel { _ in log.entries.append("canvas"); return true }
    }
    try #require(window.lastHitboxes.contains { $0.opaque }, "the click target is registered")
    #expect(platform.simulateInput(wheel(150, 150)), "claimed")
    #expect(log.entries == ["canvas"], "\(log.entries)")
    withExtendedLifetime(window) {}
}

/// **3.8** (`CI-I` item 4, `DD-Y`'s ancestry). A click target drawn **above** a
/// canvas as a sibling (not inside it) stops the canvas's wheel — claimed, no
/// handler — while off it the canvas runs (the separating arm). Mutation:
/// drop the ancestry test (any containing region on the layer).
@MainActor
@Test func anOverlaidSiblingClickTargetStopsTheCanvasWheel() throws {
    let log = BLog()
    let (window, platform) = try bWindow {
        ZStack {
            Rectangle().frame(width: px(200), height: px(200))
                .onScrollWheel { _ in log.entries.append("canvas"); return true }
            Rectangle().frame(width: px(50), height: px(50)).onTapGesture { log.entries.append("tap") }
        }
    }
    #expect(platform.simulateInput(wheel(150, 150)), "the overlay claims (opaque)")
    #expect(log.entries.isEmpty, "the canvas beneath sees nothing: \(log.entries)")
    platform.simulateInput(wheel(60, 60))
    #expect(log.entries == ["canvas"], "off the overlay the canvas runs: \(log.entries)")
    withExtendedLifetime(window) {}
}

/// **3.9** (`CI-I` item 3). `.disabled(true)`, `.allowsHitTesting(false)` and
/// `.hidden()` each withdraw the wheel region: no handler, not claimed; the
/// same element without them runs (the control). Mutation: register outside
/// the `allowsHitTesting` gate (that arm reddens).
@MainActor
@Test func aWheelRegionIsWithdrawnByDisabledAllowsHitTestingAndHidden() throws {
    let log = BLog()
    func wheeling(_ name: String) -> ModifiedElement<Box<EmptyGroup>> {
        square().onScrollWheel { _ in log.entries.append(name); return true }
    }
    let (disabled, disabledPlatform) = try bWindow { Column { wheeling("disabled").disabled(true) } }
    let (untestable, untestablePlatform) = try bWindow { Column { wheeling("untestable").allowsHitTesting(false) } }
    let (hidden, hiddenPlatform) = try bWindow { Column { wheeling("hidden").hidden() } }
    let (control, controlPlatform) = try bWindow { Column { wheeling("control") } }
    #expect(!disabledPlatform.simulateInput(wheel(150, 150)))
    #expect(!untestablePlatform.simulateInput(wheel(150, 150)))
    #expect(!hiddenPlatform.simulateInput(wheel(150, 150)))
    #expect(log.entries.isEmpty, "\(log.entries)")
    #expect(controlPlatform.simulateInput(wheel(150, 150)))
    #expect(log.entries == ["control"], "\(log.entries)")
    withExtendedLifetime((disabled, untestable, hidden, control)) {}
}

// MARK: - 3.10–3.11: presentations and viewports (`CI-L`)

/// `anchor` (`width` × `height`) with its top-left corner at (`left`, `top`)
/// in a 400 × 400 root of legacy spacers (no gap).
@MainActor private func at<A: Element>(top: Float, left: Float, width: Float, height: Float,
                                       _ anchor: A) -> some StyledElement {
    Column {
        Box().frame(width: px(1), height: px(top))
        Row {
            Box().frame(width: px(left), height: px(1))
            anchor
            Box().frame(width: px(400 - left - width), height: px(1))
        }
        Box().frame(width: px(1), height: px(400 - top - height))
    }
}

/// **3.10** (`CI-L`, `IX-Q`). A popover above a canvas takes the canvas's
/// wheel, pinch, pointer style and middle drag at the popover's panel: the
/// canvas logs nothing and the style is the arrow; the same events at the same
/// point with the popover closed reach the canvas (the separating window).
/// Mutation: drop the layer clause in the wheel chain (the wheel arm reddens).
@MainActor
@Test func aPopoverAboveACanvasTakesItsWheelPinchStyleAndButtonDrags() throws {
    let log = BLog()
    func canvas(_ shown: Bool) -> some StyledElement {
        let binding = Binding(get: { shown }, set: { _ in })
        return at(top: 100, left: 100, width: 40, height: 20,
                  Box().frame(width: px(40), height: px(20)).popover(isPresented: binding) {
                      Box().frame(width: px(150), height: px(100))
                  })
            .frame(width: px(400), height: px(400))
            .onScrollWheel { _ in log.entries.append("wheel"); return true }
            .pointerStyle(.rectSelection)
            .gesture(MagnifyGesture().onChanged { _ in log.entries.append("magnify") })
            .gesture(DragGesture(minimumDistance: 0, button: .middle).onChanged { _ in log.entries.append("middle") })
    }
    let (open, openPlatform) = try bWindow(size: 400) { canvas(true) }
    let (closed, closedPlatform) = try bWindow(size: 400) { canvas(false) }
    try #require(open.lastOpenPopovers.count == 1, "the popover is open")
    let panel = try #require(open.lastHitboxes.last { $0.opaque && $0.layer > 0 }, "the popover's panel")
    let p = pt(panel.bounds.origin.x.value + 20, panel.bounds.origin.y.value + 20)
    for platform in [openPlatform, closedPlatform] {
        platform.simulateInput(moved(p.x.value, p.y.value))
        platform.simulateInput(.scrollWheel(ScrollEvent(position: p, delta: pt(0, -5))))
        platform.simulateInput(magnify(0, .began, at: p))
        platform.simulateInput(magnify(0.2, .changed, at: p))
        platform.simulateInput(magnify(0, .ended, at: p))
        platform.simulateInput(odown(p.x.value, p.y.value))
        platform.simulateInput(odrag(p.x.value + 15, p.y.value))
        platform.simulateInput(oup(p.x.value + 15, p.y.value))
        if platform === openPlatform {
            #expect(log.entries.isEmpty, "the popover took every event: \(log.entries)")
            #expect(platform.pointerStyles.last == .arrow, "\(platform.pointerStyles)")
            log.entries = []
        }
    }
    #expect(log.entries == ["wheel", "magnify", "middle", "middle"], "closed: \(log.entries)")
    #expect(closedPlatform.pointerStyles.last == .crosshair, "\(closedPlatform.pointerStyles)")
    withExtendedLifetime((open, closed)) {}
}

/// **3.11** (`CI-L`: the viewport case). A `GPUSurface` wrapped in each new
/// modifier receives the wheel (local), a pinch, a middle drag and shows its
/// style — no special case. A coverage pin: it reddens with the 3.2, 3.30 and
/// 3.25 mutations.
@MainActor
@Test func aGPUSurfaceViewportReceivesWheelPinchButtonDragsAndStyle() throws {
    let log = BLog()
    let (window, platform) = try bWindow {
        VStack {
            GPUSurface(redraw: .onDemand) { _ in }
                .frame(width: px(200), height: px(200))
                .onScrollWheel { event in log.events.append(event); log.entries.append("wheel"); return true }
                .gesture(MagnifyGesture().onChanged { _ in log.entries.append("magnify") })
                .gesture(DragGesture(minimumDistance: 0, button: .middle).onChanged { _ in log.entries.append("middle") })
                .pointerStyle(.rectSelection)
        }
    }
    platform.simulateInput(moved(100, 100))
    platform.simulateInput(wheel(100, 100))
    platform.simulateInput(magnify(0, .began, at: pt(100, 100)))
    platform.simulateInput(magnify(0.1, .changed, at: pt(100, 100)))
    platform.simulateInput(magnify(0, .ended, at: pt(100, 100)))
    platform.simulateInput(odown(100, 100))
    platform.simulateInput(oup(100, 100))
    #expect(log.entries == ["wheel", "magnify", "middle"], "\(log.entries)")
    #expect(close(log.events.first?.location, pt(50, 50)), "local: \(String(describing: log.events.first?.location))")
    #expect(platform.pointerStyles == [.crosshair], "\(platform.pointerStyles)")
    withExtendedLifetime(window) {}
}

// MARK: - 3.12–3.14: transforms, claiming, registration

/// **3.12** (`CI-I` item 1, `CI-L`). Through `.scaleEffect(2)` (about the
/// 100 × 100 rectangle's centre (150, 150), drawn (50, 50)–(250, 250)) a wheel
/// at (70, 90) reports the local point (150 + (70 − 150)/2 − 100,
/// 150 + (90 − 150)/2 − 100) = (10, 20) and the raw delta (3, −7). Mutation:
/// transform the delta.
@MainActor
@Test func aWheelThroughAScaleEffectReportsALocalLocationAndARawDelta() throws {
    let log = BLog()
    let (window, platform) = try bWindow {
        VStack {
            Rectangle().frame(width: px(100), height: px(100)).scaleEffect(2)
                .onScrollWheel { event in log.events.append(event); return true }
        }
    }
    #expect(platform.simulateInput(.scrollWheel(ScrollEvent(position: pt(70, 90), delta: pt(3, -7)))),
            "outside the layout rect but inside the drawing: claimed")
    let got = try #require(log.events.first, "the handler ran")
    #expect(close(got.location, pt(10, 20)), "local: \(got.location)")
    #expect(close(got.delta, pt(3, -7)), "raw delta: \(got.delta)")
    withExtendedLifetime(window) {}
}

/// **3.13** (`CI-I` item 4). A wheel whose only target is a non-opaque handler
/// that declines is not claimed and reaches the window's `onInput`; one that
/// claims does not. Mutation: claim whenever a handler ran.
@MainActor
@Test func anUnclaimedWheelOverOnlyANonOpaqueHandlerReachesTheWindowsOnInput() throws {
    let log = BLog()
    log.claims = false
    let (window, platform) = try bWindow {
        square().onScrollWheel { _ in log.entries.append("handler"); return log.claims }
    }
    var raw = 0
    window.onInput = { event in
        if case .scrollWheel = event { raw += 1 }
        return false
    }
    #expect(!platform.simulateInput(wheel(150, 150)), "declined: not claimed")
    #expect(log.entries == ["handler"] && raw == 1, "\(log.entries) raw \(raw)")
    log.claims = true
    #expect(platform.simulateInput(wheel(150, 150)), "claimed")
    #expect(raw == 1, "a claimed wheel never reaches onInput")
    withExtendedLifetime(window) {}
}

/// **3.14** (`CI-H` item 3, `CI-I` item 3). A frame with no wheel handler and
/// no pointer style registers exactly `70ed000`'s hitboxes: a click target
/// (1 opaque), a hover region (1) and a contextual region (1) = **3**. With one
/// `.pointerStyle` and one `.onScrollWheel` on two of them, one region each
/// (5). Mutation: register a pointer region unconditionally.
@MainActor
@Test func aFrameWithNoWheelOrStyleRegionRegistersNoExtraHitbox() throws {
    let (plain, _) = try bWindow {
        Column {
            Box().frame(width: px(50), height: px(50)).onClick {}
            Box().frame(width: px(50), height: px(50)).onHover { _ in }
            Box().frame(width: px(50), height: px(50)).contextMenu { Button("A") {} }
        }
    }
    #expect(plain.lastHitboxes.count == 3, "\(plain.lastHitboxes.map(\.bounds))")
    let (styled, _) = try bWindow {
        Column {
            Box().frame(width: px(50), height: px(50)).onClick {}.pointerStyle(.link)
            Box().frame(width: px(50), height: px(50)).onHover { _ in }.onScrollWheel { _ in true }
            Box().frame(width: px(50), height: px(50)).contextMenu { Button("A") {} }
        }
    }
    #expect(styled.lastHitboxes.count == 5, "\(styled.lastHitboxes.map(\.bounds))")
    withExtendedLifetime((plain, styled)) {}
}

// MARK: - 3.15–3.25: the pointer style

/// **3.15** (`CI-H` item 7). The style reaches the platform only on a change:
/// three moves over a crosshair square send one `.crosshair`, a move off it one
/// `.arrow`, a second move off nothing. Mutation: drop the dedupe.
@MainActor
@Test func pointerStyleReachesThePlatformOnlyOnAChange() throws {
    let (window, platform) = try bWindow { square().pointerStyle(.rectSelection) }
    #expect(platform.pointerStyles.isEmpty, "nothing before a pointer event: \(platform.pointerStyles)")
    platform.simulateInput(moved(60, 60))
    platform.simulateInput(moved(70, 70))
    platform.simulateInput(moved(80, 80))
    #expect(platform.pointerStyles == [.crosshair], "\(platform.pointerStyles)")
    platform.simulateInput(moved(10, 10))
    platform.simulateInput(moved(20, 20))
    #expect(platform.pointerStyles == [.crosshair, .arrow], "\(platform.pointerStyles)")
    withExtendedLifetime(window) {}
}

/// **3.16** (probe `P11`, `P11c`, `P12`; `CI-H` items 2, 4; `CI-AH` item 2).
/// The innermost style wins and `nil` defers, on both vocabularies: in a
/// 200 × 200 column styled `.link` whose top half is styled `.rectSelection`,
/// the top half shows the crosshair (`P11`) and the bottom half the hand
/// (`P11c`); with the top half's style `nil`, the hand there too (`P12`). On
/// one legacy element, `.pointerStyle(.rectSelection).pointerStyle(.link)`
/// shows the crosshair — the first written is the inner. Mutation: take the
/// first (outermost) candidate.
@MainActor
@Test func theInnermostPointerStyleWinsAndNilDefers() throws {
    func check(_ platform: FakePlatformWindow, top: PlatformPointerStyle, bottom: PlatformPointerStyle,
               sourceLocation: SourceLocation = #_sourceLocation) {
        platform.simulateInput(moved(150, 100))
        #expect(platform.pointerStyles.last == top, "top: \(platform.pointerStyles)", sourceLocation: sourceLocation)
        platform.simulateInput(moved(150, 200))
        #expect(platform.pointerStyles.last == bottom, "bottom: \(platform.pointerStyles)",
                sourceLocation: sourceLocation)
    }
    func legacy(_ inner: PointerStyle?) -> some StyledElement {
        Column {
            Box().frame(width: px(200), height: px(100)).pointerStyle(inner)
            Box().frame(width: px(200), height: px(100))
        }
        .pointerStyle(.link)
    }
    func proposal(_ inner: PointerStyle?) -> some ProposalElementGroup {
        VStack(spacing: 0) {
            Rectangle().frame(width: px(200), height: px(100)).pointerStyle(inner)
            Rectangle().frame(width: px(200), height: px(100))
        }
        .pointerStyle(.link)
    }
    let (w1, p1) = try bWindow { legacy(.rectSelection) }
    let (w2, p2) = try bWindow { legacy(nil) }
    let (w3, p3) = try bWindow { VStack { proposal(.rectSelection) } }
    let (w4, p4) = try bWindow { VStack { proposal(nil) } }
    check(p1, top: .crosshair, bottom: .pointingHand)
    check(p2, top: .pointingHand, bottom: .pointingHand)
    check(p3, top: .crosshair, bottom: .pointingHand)
    check(p4, top: .pointingHand, bottom: .pointingHand)
    let (w5, p5) = try bWindow { square().pointerStyle(.rectSelection).pointerStyle(.link) }
    p5.simulateInput(moved(150, 150))
    #expect(p5.pointerStyles == [.crosshair], "the inner (first written) wins: \(p5.pointerStyles)")
    withExtendedLifetime((w1, w2, w3, w4, w5)) {}
}

/// **3.17** (probe `P13`, `P13c`; `CI-H` item 4). An opaque target drawn above
/// a crosshair canvas covers its style (the arrow over it, `P13`); off it the
/// crosshair (`P13c`). Mutation: eligibility without `opaque`.
@MainActor
@Test func anOpaqueTargetAboveCoversAPointerStyleBeneath() throws {
    let (window, platform) = try bWindow {
        ZStack {
            Rectangle().frame(width: px(200), height: px(200)).pointerStyle(.rectSelection)
            Rectangle().frame(width: px(50), height: px(50)).onTapGesture {}
        }
    }
    platform.simulateInput(moved(150, 150))
    #expect(platform.pointerStyles.last == .arrow, "covered (P13): \(platform.pointerStyles)")
    platform.simulateInput(moved(60, 60))
    #expect(platform.pointerStyles.last == .crosshair, "uncovered (P13c): \(platform.pointerStyles)")
    withExtendedLifetime(window) {}
}

/// **3.18** (divergence 141, `CI-H` item 5; probe `P14` measured SwiftUI's
/// paint-only view covering). A shape that only paints, drawn above a
/// crosshair canvas, registers no hitbox and so covers nothing: the crosshair
/// over it. Pins the divergence — a fix reddens it.
@MainActor
@Test func aPaintOnlyOverlayDoesNotCoverAPointerStyle() throws {
    let (window, platform) = try bWindow {
        ZStack {
            Rectangle().frame(width: px(200), height: px(200)).pointerStyle(.rectSelection)
            Rectangle().fill(.accent).frame(width: px(50), height: px(50))
        }
    }
    platform.simulateInput(moved(150, 150))
    #expect(platform.pointerStyles == [.crosshair], "\(platform.pointerStyles)")
    withExtendedLifetime(window) {}
}

/// **3.19** (`CI-H` item 3). `.disabled(true)`, `.allowsHitTesting(false)` and
/// `.hidden()` each withdraw the style region (the arrow); the control shows
/// the crosshair. Mutation: register outside the disabled gate.
@MainActor
@Test func pointerStyleIsWithdrawnByDisabledAllowsHitTestingAndHidden() throws {
    let (disabled, disabledPlatform) = try bWindow { Column { square().pointerStyle(.rectSelection).disabled(true) } }
    let (untestable, untestablePlatform) = try bWindow {
        Column { square().pointerStyle(.rectSelection).allowsHitTesting(false) }
    }
    let (hidden, hiddenPlatform) = try bWindow { Column { square().pointerStyle(.rectSelection).hidden() } }
    let (control, controlPlatform) = try bWindow { Column { square().pointerStyle(.rectSelection) } }
    for platform in [disabledPlatform, untestablePlatform, hiddenPlatform, controlPlatform] {
        platform.simulateInput(moved(150, 150))
    }
    #expect(disabledPlatform.pointerStyles == [.arrow], "disabled: \(disabledPlatform.pointerStyles)")
    #expect(untestablePlatform.pointerStyles == [.arrow], "untestable: \(untestablePlatform.pointerStyles)")
    #expect(hiddenPlatform.pointerStyles == [.arrow], "hidden: \(hiddenPlatform.pointerStyles)")
    #expect(controlPlatform.pointerStyles == [.crosshair], "control: \(controlPlatform.pointerStyles)")
    withExtendedLifetime((disabled, untestable, hidden, control)) {}
}

/// A 200 × 200 legacy box that switches its style to `.grabActive` from a
/// primary drag's `onChanged` and back from its `onEnded`.
private struct GrabbingBox: Component {
    @State var dragging = false
    var content: some ElementGroup {
        Box().frame(width: Pixels(200), height: Pixels(200))
            .pointerStyle(dragging ? .grabActive : .grabIdle)
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { _ in if !dragging { dragging = true } }
                .onEnded { _ in dragging = false })
    }
}

/// **3.20** (`CI-H` item 6). A press holds the pressed target's style while the
/// pointer leaves: the open hand over the box; the drag's `@State` switch shows
/// the closed hand after the frame; a drag to (290, 290), off the box, keeps
/// it; the release resolves under the pointer — the arrow. Mutation: resolve
/// under the pointer during a press.
@MainActor
@Test func aPressHoldsThePressedTargetsStyleWhileThePointerLeaves() throws {
    let (window, platform) = try bWindow { Column { GrabbingBox() } }
    platform.simulateInput(moved(150, 150))
    #expect(platform.pointerStyles == [.openHand], "\(platform.pointerStyles)")
    platform.simulateInput(ldown(150, 150))
    platform.simulateInput(ldrag(160, 160))
    settle(window)
    #expect(platform.pointerStyles.last == .closedHand, "the switch shows after the frame: \(platform.pointerStyles)")
    platform.simulateInput(ldrag(290, 290))
    settle(window)
    #expect(platform.pointerStyles.last == .closedHand, "held off the box: \(platform.pointerStyles)")
    platform.simulateInput(lup(290, 290))
    settle(window)
    #expect(platform.pointerStyles.last == .arrow, "the release resolves under the pointer: \(platform.pointerStyles)")
    withExtendedLifetime(window) {}
}

/// **3.21** (`CI-H` item 7). Content changing under a still pointer changes the
/// style after the frame: the pointer rests over a plain square (the arrow);
/// the model gives the square a crosshair and the next frame sends it with no
/// pointer event. Mutation: recompute only on pointer events.
@MainActor
@Test func contentMovingUnderAStillPointerChangesTheStyleAfterTheFrame() throws {
    let model = BModel()
    let (window, platform) = try bWindow {
        Column {
            square().pointerStyle(model.flag ? .rectSelection : nil).onClick {}
        }
    }
    platform.simulateInput(moved(150, 150))
    #expect(platform.pointerStyles == [.arrow], "\(platform.pointerStyles)")
    model.flag = true
    redraw(window)
    #expect(platform.pointerStyles == [.arrow, .crosshair], "\(platform.pointerStyles)")
    withExtendedLifetime(window) {}
}

/// **3.22** (`CI-H` item 7, `SV-N` item 6's rule). While an in-window menu or
/// a drawn alert is up the style is the arrow, and it comes back when the
/// menu closes. Mutation: ignore `hoverIsSuppressed`.
@MainActor
@Test func anInWindowMenuOrDrawnAlertResetsTheStyleToDefault() throws {
    let (menuWindow, menuPlatform) = try bWindow(native: false) {
        square().pointerStyle(.rectSelection).contextMenu { Button("A") {} }
    }
    menuPlatform.simulateInput(moved(150, 150))
    #expect(menuPlatform.pointerStyles == [.crosshair])
    menuPlatform.simulateInput(rdown(60, 60))
    menuPlatform.simulateInput(rup(60, 60))
    settle(menuWindow)
    try #require(menuWindow.menuSession.map { !$0.isNative } == true, "the drawn menu is open")
    #expect(menuPlatform.pointerStyles.last == .arrow, "menu up: \(menuPlatform.pointerStyles)")
    menuPlatform.simulateInput(escapeKey)
    settle(menuWindow)
    try #require(menuWindow.menuSession == nil, "closed")
    #expect(menuPlatform.pointerStyles.last == .crosshair, "back: \(menuPlatform.pointerStyles)")

    let model = BModel()
    let (alertWindow, alertPlatform) = try bWindow {
        Column {
            square().pointerStyle(.rectSelection)
                .alert("Delete?", isPresented: model.binding) { Button("Delete", role: .destructive) {} }
        }
    }
    alertPlatform.simulateInput(moved(150, 150))
    #expect(alertPlatform.pointerStyles == [.crosshair])
    model.shown = true
    settle(alertWindow)
    redraw(alertWindow)
    try #require(alertWindow.drawnAlert != nil, "the alert is drawn")
    #expect(alertPlatform.pointerStyles.last == .arrow, "alert up: \(alertPlatform.pointerStyles)")
    withExtendedLifetime((menuWindow, alertWindow)) {}
}

/// **3.23** (`CI-S`). A pointer re-entry re-sends the style even when it is the
/// default: over the crosshair half, exit, re-enter over the plain half — the
/// arrow is sent again although the last style sent before the crosshair was
/// the arrow. Mutation: on exit set the last-sent style to `.default`.
@MainActor
@Test func aPointerReEntryResendsTheStyleEvenWhenItIsDefault() throws {
    let (window, platform) = try bWindow {
        Column {
            Box().frame(width: px(200), height: px(100)).pointerStyle(.rectSelection)
            Box().frame(width: px(200), height: px(100)).onClick {}
        }
    }
    platform.simulateInput(moved(150, 200))
    platform.simulateInput(moved(150, 100))
    #expect(platform.pointerStyles == [.arrow, .crosshair], "\(platform.pointerStyles)")
    platform.simulateInput(.pointerExited)
    #expect(platform.pointerStyles == [.arrow, .crosshair], "an exit sends nothing")
    platform.simulateInput(moved(150, 200))
    #expect(platform.pointerStyles == [.arrow, .crosshair, .arrow], "re-sent: \(platform.pointerStyles)")
    platform.simulateInput(.pointerExited)
    platform.simulateInput(moved(150, 200))
    #expect(platform.pointerStyles == [.arrow, .crosshair, .arrow, .arrow],
            "re-sent even when the default was the last sent: \(platform.pointerStyles)")
    withExtendedLifetime(window) {}
}

/// **3.24** (`CI-L`, `GX-I`). A style region under `.rotationEffect(90°)`
/// follows the drawing: a 200 × 40 rectangle centred at (150, 150) turned to
/// 40 × 200 shows the crosshair at (150, 70) (inside the drawing, outside the
/// layout rect) and the arrow at (70, 150) (the reverse). Mutation: test
/// containment with the untransformed rect.
@MainActor
@Test func aPointerStyleThroughARotationFollowsTheDrawing() throws {
    let (window, platform) = try bWindow {
        VStack {
            Rectangle().frame(width: px(200), height: px(40)).rotationEffect(.degrees(90))
                .pointerStyle(.rectSelection)
        }
    }
    platform.simulateInput(moved(150, 70))
    #expect(platform.pointerStyles.last == .crosshair, "inside the drawing: \(platform.pointerStyles)")
    platform.simulateInput(moved(70, 150))
    #expect(platform.pointerStyles.last == .arrow, "outside the drawing: \(platform.pointerStyles)")
    withExtendedLifetime(window) {}
}

/// **3.25** (`CI-H` item 7, `SV-U`'s shape). A frame with no style region does
/// no per-hitbox style work: ten moves over click targets leave
/// `pointerStyleVisits` at 0 (one `.arrow` sent); the same tree with one style
/// region visits (the instrument's separating arm). Mutation: remove the
/// early return.
@MainActor
@Test func aFrameWithNoStyleRegionDoesNoPointerStyleWork() throws {
    let (plain, plainPlatform) = try bWindow {
        Column {
            Box().frame(width: px(200), height: px(100)).onClick {}
            Box().frame(width: px(200), height: px(100)).onClick {}
        }
    }
    for k in 0..<10 { plainPlatform.simulateInput(moved(60 + Float(k) * 10, 150)) }
    #expect(plain.pointerStyleVisits == 0, "\(plain.pointerStyleVisits)")
    #expect(plainPlatform.pointerStyles == [.arrow], "\(plainPlatform.pointerStyles)")
    let (styled, styledPlatform) = try bWindow {
        Column {
            Box().frame(width: px(200), height: px(100)).onClick {}.pointerStyle(.link)
            Box().frame(width: px(200), height: px(100)).onClick {}
        }
    }
    styledPlatform.simulateInput(moved(150, 100))
    #expect(styled.pointerStyleVisits > 0, "the instrument counts")
    withExtendedLifetime((plain, styled)) {}
}
