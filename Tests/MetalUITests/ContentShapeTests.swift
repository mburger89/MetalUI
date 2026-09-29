import Testing
import Metal
import MetalUICore
import MetalUIPlatform
@testable import MetalUI

// Plan task 12, part 1, lane 2 — content shapes and what a clip does to a hit
// (ruling `IX-L`; spec §6, tests 2.14–2.18, moved from lane 3 by `IX-O`). Every
// SwiftUI answer is an arm of `docs/probes/swiftui-interaction.swift` (C0–C13,
// H18): a 200 × 200 view clicked at its centre and at its corner (12, 12).
//
// Geometry (each test `#require`s it from the window's hitboxes): a 300 × 300
// window with a 200 × 200 root centred at (50, 50)–(250, 250) (`CN-J`), so the
// probe's corner is (62, 62) and its centre (150, 150).

private func px(_ v: Float) -> Pixels { Pixels(v) }
private func pt(_ x: Float, _ y: Float) -> Point<Pixels> { Point(x: px(x), y: px(y)) }

private let corner = pt(62, 62)
private let centre = pt(150, 150)
private let rootRect = Bounds(origin: pt(50, 50), size: Size(width: px(200), height: px(200)))

@MainActor
private final class HitLog {
    var hits: [String] = []
}

@MainActor
private func shapeWindow<Root: Element>(_ content: @escaping @MainActor () -> Root) throws
    -> (Window, FakePlatformWindow) {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let (window, platform) = try makeFakeWindow(device: device, size: 300, content: content)
    window.drawFrameIfNeeded()
    return (window, platform)
}

@MainActor
private func click(_ platform: FakePlatformWindow, _ point: Point<Pixels>) {
    platform.simulateInput(.mouseDown(MouseEvent(position: point)))
    platform.simulateInput(.mouseUp(MouseEvent(position: point)))
}

/// Clicks the corner, then the centre, and returns what each click logged.
@MainActor
private func cornerAndCentre<Root: Element>(_ log: HitLog, requiring rect: Bounds<Pixels> = rootRect,
                                            _ content: @escaping @MainActor () -> Root,
                                            sourceLocation: SourceLocation = #_sourceLocation) throws
    -> (corner: [String], centre: [String]) {
    let (window, platform) = try shapeWindow(content)
    let targets = window.lastHitboxes.filter { $0.scroll == nil }.map(\.bounds)
    try #require(targets.contains(rect), "the fixture's hitboxes: \(targets)", sourceLocation: sourceLocation)
    log.hits = []
    click(platform, corner)
    let atCorner = log.hits
    log.hits = []
    click(platform, centre)
    return (atCorner, log.hits)
}

@MainActor
private func tappable(_ log: HitLog) -> ModifiedElement<Box<EmptyGroup>> {
    Box().frame(width: px(200), height: px(200))
}

// MARK: - 2.14 legacy

/// **2.14** (C1: `.contentShape(Circle())` refuses the corner and takes the
/// centre; C11: a 60-pt `RoundedRectangle` refuses the corner too; C13: the
/// same inside a padding — MetalUI's spelling is the shape inside
/// `contentShape(inset:)`'s rect; C0 the unshaped control). On a legacy
/// `onClick`. M3i (`Hitbox.contains` ignores the shape) reddens it.
@Test @MainActor func aCircularContentShapeRefusesTheCornerAndTakesTheCentre() throws {
    let log = HitLog()
    let control = try cornerAndCentre(log) { tappable(log).onClick { log.hits.append("hit") } }
    #expect(control.corner == ["hit"] && control.centre == ["hit"], "C0: unshaped, both hit")

    let circle = try cornerAndCentre(log) {
        tappable(log).contentShape(Circle()).onClick { log.hits.append("hit") }
    }
    #expect(circle.corner == [], "C1: the circle refuses the corner")
    #expect(circle.centre == ["hit"], "C1: and takes the centre")

    let rounded = try cornerAndCentre(log) {
        tappable(log).contentShape(RoundedRectangle(cornerRadius: px(60))).onClick { log.hits.append("hit") }
    }
    #expect(rounded.corner == [] && rounded.centre == ["hit"], "C11: a 60-pt rounded rect refuses the corner")

    // C13: the circle inside a 20-pt inset rect (160 × 160 at (70, 70)). Its
    // corner (75, 75) is inside the inset rect and outside the circle.
    let inset = Bounds(origin: pt(70, 70), size: Size(width: px(160), height: px(160)))
    let (window, platform) = try shapeWindow {
        tappable(log).contentShape(inset: px(20)).contentShape(Circle()).onClick { log.hits.append("hit") }
    }
    try #require(window.lastHitboxes.map(\.bounds).contains(inset), "the inset hit rect")
    log.hits = []
    click(platform, pt(75, 75))
    #expect(log.hits == [], "C13: the inset rect's corner is outside the circle")
    click(platform, centre)
    #expect(log.hits == ["hit"], "C13: the centre hits")
}

// MARK: - 2.15 proposal and Button

/// **2.15** (C2: `.onTapGesture.contentShape(Circle())` — the shape written
/// AFTER the gesture — refuses the corner, as C1 does; C10: a `.plain` button
/// whose label is circle-shaped refuses it). On the proposal `onTap`, the
/// proposal `onTapGesture` and a `.plain` `Button` carrying the shape. M3i
/// reddens it.
@Test @MainActor func aContentShapeWrittenAfterAProposalTapShapesItsHit() throws {
    let log = HitLog()
    let tap = try cornerAndCentre(log) {
        Rectangle().frame(width: px(200), height: px(200)).onTap { log.hits.append("tap") }
            .contentShape(Circle())
    }
    #expect(tap.corner == [] && tap.centre == ["tap"], "C2: the proposal tap follows its shape")

    let gesture = try cornerAndCentre(log) {
        Rectangle().frame(width: px(200), height: px(200)).onTapGesture { log.hits.append("gesture") }
            .contentShape(Circle())
    }
    #expect(gesture.corner == [] && gesture.centre == ["gesture"], "C2: a proposal gesture follows its shape")

    let button = try cornerAndCentre(log) {
        Button(action: { log.hits.append("button") }) { Box().frame(width: px(200), height: px(200)) }
            .buttonStyle(.plain).contentShape(Circle())
    }
    #expect(button.corner == [] && button.centre == ["button"], "C10: a plain button follows its shape")
}

// MARK: - 2.16 every consumer

/// **2.16** (`IX-L` item 1: every pointer consumer reads the one region test).
/// The corner outside a circular content shape neither hovers (no hover
/// fill), presses (`active` stays nil) nor starts a drag gesture, and a wheel
/// over it reaches the scroller beneath — the centre does all four the other
/// way. M3j (the shape tested in click dispatch only, a second copy) reddens
/// it.
@Test @MainActor func hoverActiveAndTheGestureArenaFollowTheContentShape() throws {
    let log = HitLog()
    let (window, platform) = try shapeWindow {
        tappable(log).contentShape(Circle()).hoverBackground(.accent)
            .gesture(DragGesture().onChanged { _ in log.hits.append("drag") })
    }
    window.theme = .light
    try #require(window.lastHitboxes.map(\.bounds).contains(rootRect), "the shaped target registers")
    func hoverFills() -> Int {
        window.lastScene.rects.filter { ixSame(ixHsla($0.background), window.theme[.accent]) }.count
    }
    func step(_ event: InputEvent) {
        platform.simulateInput(event)
        window.setNeedsRedraw()
        window.drawFrameIfNeeded()
    }
    step(.mouseMoved(MouseEvent(position: corner)))
    #expect(hoverFills() == 0, "the corner does not hover")
    step(.mouseMoved(MouseEvent(position: centre)))
    #expect(hoverFills() == 1, "the centre hovers")

    step(.mouseDown(MouseEvent(position: corner)))
    #expect(window.active == nil, "a press at the corner presses nothing")
    step(.mouseDragged(MouseEvent(position: pt(92, 62))))
    step(.mouseUp(MouseEvent(position: pt(92, 62))))
    #expect(log.hits == [], "a drag from the corner starts no gesture")
    step(.mouseDown(MouseEvent(position: centre)))
    #expect(window.active == hitboxID(window, rootRect), "a press at the centre is active")
    step(.mouseDragged(MouseEvent(position: pt(180, 150))))
    step(.mouseUp(MouseEvent(position: pt(180, 150))))
    #expect(log.hits == ["drag"], "a drag from the centre changes")

    // The wheel: a shaped click target overlaid on a scroller (a `Stack`
    // sibling, not its ancestor) swallows the wheel over its shape and passes
    // it over the corner (`DD-Y`'s ancestry clause keeps the centre claimed).
    let listID = ElementID("list")
    let (scrollWindow, scrollPlatform) = try shapeWindow {
        Stack {
            ScrollView(.vertical, elementID: listID) {
                Column { for _ in 0..<10 { Box().frame(width: px(200), height: px(80)) } }
            }.frame(width: px(200), height: px(200))
            tappable(log).contentShape(Circle()).onClick {}
        }
    }
    let region = try #require(scrollWindow.lastScrollRegions.first, "the scroller registers a region")
    func offset() -> Double { scrollWindow.stateTable.peek(region.id, as: ScrollState.self)?.offset ?? 0 }
    func wheel(_ at: Point<Pixels>) {
        scrollPlatform.simulateInput(.scrollWheel(ScrollEvent(position: at, delta: Point(x: px(0), y: px(-37)))))
    }
    try #require(region.bounds.contains(corner) && region.bounds.contains(centre), "the scroller is under both")
    wheel(centre)
    #expect(offset() == 0, "the shape over the scroller swallows the wheel at the centre")
    wheel(corner)
    #expect(offset() == 37, "the corner outside the shape passes the wheel to the scroller beneath")
}

/// The id of the window's pointer hitbox with exactly `bounds`.
@MainActor
private func hitboxID(_ window: Window, _ bounds: Bounds<Pixels>) -> GlobalElementID? {
    window.lastHitboxes.first { $0.bounds == bounds && $0.scroll == nil }?.id
}

// MARK: - 2.17 clip

/// **2.17** (C3, C4: a `clipShape(Circle())` on the tapped view does not
/// restrict its hit — the corner still hits, either order; C9: nor does a
/// 60-pt `cornerRadius`; divergence 43 amended: MetalUI intersects a hitbox
/// with an ancestor clip's RECT, so at a same-sized clip's corners the two
/// agree, and a smaller clip cuts where SwiftUI's would not). Green before this
/// lane; written first. M3k (the hit intersected with the clip's rounded
/// geometry) reddens it.
@Test @MainActor func aClipShapesCornersStayHittableAndItsRectBoundsTheHit() throws {
    let log = HitLog()
    let before = try cornerAndCentre(log) { tappable(log).clipShape(Circle()).onClick { log.hits.append("hit") } }
    #expect(before.corner == ["hit"] && before.centre == ["hit"], "C3: a clip shape does not restrict the hit")
    let after = try cornerAndCentre(log) { tappable(log).onClick { log.hits.append("hit") }.clipShape(Circle()) }
    #expect(after.corner == ["hit"] && after.centre == ["hit"], "C4: in either order")
    let radius = try cornerAndCentre(log) { tappable(log).cornerRadius(px(60)).onClick { log.hits.append("hit") } }
    #expect(radius.corner == ["hit"] && radius.centre == ["hit"], "C9: a corner radius does not restrict it")

    // An ANCESTOR's same-sized circular clip: the child's hit is intersected
    // with the clip's rect, so the corner still hits (agreeing with SwiftUI).
    let ancestor = try cornerAndCentre(log) {
        Box { tappable(log).onClick { log.hits.append("child") } }
            .frame(width: px(200), height: px(200)).clipShape(Circle())
    }
    #expect(ancestor.corner == ["child"] && ancestor.centre == ["child"],
            "a same-sized ancestor clip's corners stay hittable")

    // A smaller clip cuts (divergence 43): a 200 × 200 child inside a 100 × 100
    // clipped parent at (100, 100)–(200, 200) is hit only inside the clip.
    let (window, platform) = try shapeWindow {
        Box { Box().frame(width: px(200), height: px(200)).onClick { log.hits.append("cut") } }
            .frame(width: px(100), height: px(100), alignment: .topLeading).clipped()
    }
    let clip = Bounds(origin: pt(100, 100), size: Size(width: px(100), height: px(100)))
    try #require(window.lastHitboxes.map(\.bounds).contains(clip), "the child's hitbox is cut to the clip")
    log.hits = []
    click(platform, pt(210, 150))
    #expect(log.hits == [], "outside the smaller clip: no hit (divergence 43)")
    click(platform, centre)
    #expect(log.hits == ["cut"], "inside it: the child")
}

// MARK: - 2.18 divergence 57

/// **2.18** (H18, C12: SwiftUI's gesture-less drawn circle over a tappable
/// swallows the centre and passes the corner). **Divergence 57, pinned wrong
/// on purpose**: MetalUI's drawn element with no pointer target registers no
/// hitbox, so a click anywhere on it reaches the tappable beneath. Green
/// before this lane; written first. M3l (a hitbox registered for every
/// painted element) reddens it.
@Test @MainActor func aDrawnElementWithoutAPointerTargetDoesNotBlockAClickBeneathIt() throws {
    let log = HitLog()
    let proposal = try cornerAndCentre(log) {
        ZStack {
            Rectangle().frame(width: px(200), height: px(200)).onTap { log.hits.append("under") }
            Circle().frame(width: px(200), height: px(200))
        }
    }
    #expect(proposal.corner == ["under"], "C12: the corner reaches the tappable (SwiftUI agrees)")
    #expect(proposal.centre == ["under"], "divergence 57: the drawn circle does not block the centre (SwiftUI's does)")

    let legacy = try cornerAndCentre(log) {
        Stack {
            tappable(log).onClick { log.hits.append("under") }
            Box().frame(width: px(200), height: px(200)).background(.accent)
        }
    }
    #expect(legacy.corner == ["under"] && legacy.centre == ["under"],
            "divergence 57: a painted legacy box over a tappable does not block it (H18)")
}
