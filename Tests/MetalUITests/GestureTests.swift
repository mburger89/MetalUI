import Testing
import Metal
import MetalUICore
import MetalUIPlatform
@testable import MetalUI

// Plan task 12, part 1, lane 1 — gestures and the arena (rulings `IX-B`,
// `IX-C`, `IX-D`, and `IX-O`'s `X3`/`X4` rule; spec
// `docs/superpowers/specs/2026-09-29-interaction-design.md` §6, tests 1.1–1.23).
// Every SwiftUI answer here is an arm of `docs/probes/swiftui-interaction.swift`
// (named per test); the numbers the probe only brackets are MetalUI's.
//
// Everything runs through a real `Window` on a `FakePlatformWindow`, with the
// display link driven by `simulateTick(timestamp:)` — nothing sleeps. A pending
// long press or deferred tap is **stamped at the first tick after the event**
// (`IX-C` item 4), so every timed test ticks once at `stamp` right after the
// event and states its later ticks relative to it.
//
// Geometry (every test `#require`s it from the window's own hitboxes first):
// a 300 × 300 window; a 200 × 200 root centred at (50, 50)–(250, 250) (`CN-J`);
// where there is a child, it is 100 × 100 at the root's top-leading corner,
// (50, 50)–(150, 150).

// MARK: - Fixtures

@MainActor
private final class GLog {
    var entries: [String] = []
}

@MainActor
private final class DragValues {
    var all: [DragGesture.Value] = []
}

private func px(_ v: Float) -> Pixels { Pixels(v) }

private func pt(_ x: Float, _ y: Float) -> Point<Pixels> { Point(x: px(x), y: px(y)) }

private func down(_ x: Float, _ y: Float, count: Int = 1) -> InputEvent {
    .mouseDown(MouseEvent(position: pt(x, y), clickCount: count))
}

private func up(_ x: Float, _ y: Float, count: Int = 1) -> InputEvent {
    .mouseUp(MouseEvent(position: pt(x, y), clickCount: count))
}

private func drag(_ x: Float, _ y: Float) -> InputEvent {
    .mouseDragged(MouseEvent(position: pt(x, y)))
}

/// The stamp tick every timed test uses (`IX-C` item 4).
private let stamp = 10.0

@MainActor
private func gestureWindow<Root: Element>(_ content: @escaping @MainActor () -> Root) throws
    -> (Window, FakePlatformWindow) {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let (window, platform) = try makeFakeWindow(device: device, size: 300, startsDisplayLink: true,
                                                content: content)
    window.drawFrameIfNeeded()
    return (window, platform)
}

private let rootRect = Bounds(origin: pt(50, 50), size: Size(width: px(200), height: px(200)))
private let childRect = Bounds(origin: pt(50, 50), size: Size(width: px(100), height: px(100)))

/// Requires that exactly the named rects are registered as pointer hitboxes —
/// the geometry every coordinate in a test below is written against.
@MainActor
private func requireHitboxes(_ window: Window, _ rects: [Bounds<Pixels>],
                             sourceLocation: SourceLocation = #_sourceLocation) throws {
    let got = window.lastHitboxes.filter { $0.scroll == nil }.map(\.bounds)
    try #require(Set(got.map { "\($0)" }) == Set(rects.map { "\($0)" }),
                 "the fixture's hitboxes: \(got)", sourceLocation: sourceLocation)
}

/// A 200 × 200 root with `modify` applied to its outer layer.
@MainActor
private func root<E: StyledElement>(_ modify: @escaping @MainActor (ModifiedElement<Box<EmptyGroup>>) -> E)
    -> @MainActor () -> E {
    { modify(Box().frame(width: Pixels(200), height: Pixels(200))) }
}

/// A 100 × 100 child at the top-leading corner of a 200 × 200 parent;
/// `child` and `parent` configure each one's outer layer.
@MainActor
private func nested<C: StyledElement, P: StyledElement>(
    child: @escaping @MainActor (ModifiedElement<Box<EmptyGroup>>) -> C,
    parent: @escaping @MainActor (ModifiedContent<Column<C>, ModifierLayer>) -> P) -> @MainActor () -> P {
    {
        parent(Column { child(Box().frame(width: Pixels(100), height: Pixels(100))) }
            .frame(width: Pixels(200), height: Pixels(200), alignment: .topLeading))
    }
}

private func fmt(_ v: DragGesture.Value) -> String {
    "(\(Int(v.translation.width.value)),\(Int(v.translation.height.value)))"
}

// MARK: - 1.1–1.6: tap

/// **1.1** (G1: `|down,tap`). A tap ends on the release, never the press.
/// Mutation M1a (end on `mouseDown`) reddens it.
@MainActor
@Test func aTapGestureEndsOnTheReleaseNotThePress() throws {
    let log = GLog()
    let (window, platform) = try gestureWindow(root { $0.onTapGesture { log.entries.append("tap") } })
    try requireHitboxes(window, [rootRect])
    platform.simulateInput(down(150, 150))
    #expect(log.entries == [], "nothing at the press")
    #expect(platform.simulateInput(up(150, 150)), "a release that ran a callback is claimed (IX-D item 6)")
    #expect(log.entries == ["tap"])
}

/// **1.2** (G2g: 4 pt fires; G2b: 5 pt does not). A tap fails once the pointer
/// moves 5 pt or more from the press. M1b (slop 5 → 6) reddens the 5-pt arm;
/// M1b′ (no slop check) reddens it too.
@MainActor
@Test func aTapGestureFailsOnceThePointerMovesFivePoints() throws {
    let log = GLog()
    let (window, platform) = try gestureWindow(root { $0.onTapGesture { log.entries.append("tap") } })
    try requireHitboxes(window, [rootRect])
    platform.simulateInput(down(150, 150))
    platform.simulateInput(drag(154, 150))
    platform.simulateInput(up(154, 150))
    #expect(log.entries == ["tap"], "a 4-pt move still taps (G2g)")
    platform.simulateInput(down(150, 150))
    platform.simulateInput(drag(155, 150))
    platform.simulateInput(up(155, 150))
    #expect(log.entries == ["tap"], "a 5-pt move fails the tap (G2b)")
}

/// **1.3** (G2d vs B1). A press that leaves and returns before its release does
/// not tap, where `onClick` (Button semantics) clicks. M1b′ reddens it.
@MainActor
@Test func aTapReleasedAfterAnExcursionDoesNotFireWhereOnClickDoes() throws {
    let log = GLog()
    let (window, platform) = try gestureWindow {
        Row {
            Box().frame(width: Pixels(100), height: Pixels(100)).onTapGesture { log.entries.append("tap") }
            Box().frame(width: Pixels(100), height: Pixels(100)).onClick { log.entries.append("click") }
        }
    }
    try requireHitboxes(window, [Bounds(origin: pt(50, 100), size: Size(width: px(100), height: px(100))),
                                 Bounds(origin: pt(150, 100), size: Size(width: px(100), height: px(100)))])
    for x: Float in [100, 200] {
        platform.simulateInput(down(x, 150))
        platform.simulateInput(drag(x, 110))
        platform.simulateInput(drag(x, 150))
        platform.simulateInput(up(x, 150))
    }
    #expect(log.entries == ["click"], "the excursion fails the tap and not the click")
}

/// **1.4** (G3a, G3b). A count-2 tap ends on the release whose click count is
/// 2; a single click does not end it. M1c (compare the count with `>= 1`)
/// reddens the single-click arm.
@MainActor
@Test func aCountTwoTapEndsOnTheSecondReleaseByClickCount() throws {
    let log = GLog()
    let (window, platform) = try gestureWindow(root { $0.onTapGesture(count: 2) { log.entries.append("double") } })
    try requireHitboxes(window, [rootRect])
    platform.simulateInput(down(150, 150))
    platform.simulateInput(up(150, 150))
    platform.simulateTick(timestamp: stamp)
    platform.simulateTick(timestamp: stamp + 1)
    #expect(log.entries == [], "a single click ends no count-2 tap (G3a)")
    platform.simulateInput(down(150, 150, count: 1))
    platform.simulateInput(up(150, 150, count: 1))
    #expect(log.entries == [], "the first release of a double")
    platform.simulateInput(down(150, 150, count: 2))
    platform.simulateInput(up(150, 150, count: 2))
    #expect(log.entries == ["double"], "the second release ends it (G3b)")
}

/// **1.5** (G5e). A single tap beside a double waits: nothing at a tick 0.30 s
/// after the release's stamp tick, fired at the first tick at least 0.33 s
/// after it (`IX-C` item 3). M1d (deferral 0.33 → 0) reddens it.
@MainActor
@Test func aSingleTapBesideADoubleWaitsAThirdOfASecondThenFires() throws {
    let log = GLog()
    let (window, platform) = try gestureWindow(root {
        $0.onTapGesture(count: 2) { log.entries.append("double") }
            .onTapGesture { log.entries.append("single") }
    })
    try requireHitboxes(window, [rootRect])
    platform.simulateInput(down(150, 150))
    platform.simulateInput(up(150, 150))
    #expect(log.entries == [], "not at the release")
    platform.simulateTick(timestamp: stamp)
    #expect(log.entries == [], "not at the stamp tick")
    platform.simulateTick(timestamp: stamp + 0.30)
    #expect(log.entries == [], "not 0.30 s after it")
    platform.simulateTick(timestamp: stamp + 0.34)
    #expect(log.entries == ["single"], "at the first tick at least 0.33 s after it")
    platform.simulateTick(timestamp: stamp + 1)
    #expect(log.entries == ["single"], "once")
}

/// **1.6** (G4b, G5b, H15b). A double click runs only the double, whichever of
/// the two taps is attached inner, and inside `exclusively(before:)`. M1e (the
/// single ends at its own release, no count dependency) reddens it.
@MainActor
@Test func aDoubleClickRunsOnlyTheDoubleWhicheverIsInner() throws {
    let log = GLog()
    func doubleClick(_ platform: FakePlatformWindow) {
        platform.simulateInput(down(150, 150, count: 1))
        platform.simulateInput(up(150, 150, count: 1))
        platform.simulateInput(down(150, 150, count: 2))
        platform.simulateInput(up(150, 150, count: 2))
        platform.simulateTick(timestamp: stamp)
        platform.simulateTick(timestamp: stamp + 1)
    }
    do {
        let (window, platform) = try gestureWindow(root {
            $0.onTapGesture(count: 2) { log.entries.append("double") }
                .onTapGesture { log.entries.append("single") }
        })
        try requireHitboxes(window, [rootRect])
        doubleClick(platform)
        #expect(log.entries == ["double"], "double inner (G4b)")
    }
    log.entries = []
    do {
        let (window, platform) = try gestureWindow(root {
            $0.onTapGesture { log.entries.append("single") }
                .onTapGesture(count: 2) { log.entries.append("double") }
        })
        try requireHitboxes(window, [rootRect])
        doubleClick(platform)
        #expect(log.entries == ["double"], "single inner (G5b)")
    }
    log.entries = []
    do {
        let (window, platform) = try gestureWindow(root {
            $0.gesture(TapGesture().onEnded { log.entries.append("single") }
                .exclusively(before: TapGesture(count: 2).onEnded { log.entries.append("double") }))
        })
        try requireHitboxes(window, [rootRect])
        doubleClick(platform)
        #expect(log.entries == ["double"], "exclusively(before:) (H15b)")
    }
}

// MARK: - 1.7–1.9: long press

/// **1.7** (G6a: `long,|held`). A long press ends while still held, at the first
/// tick at least `minimumDuration` after its stamp. M1f (end at the release)
/// reddens it.
@MainActor
@Test func aLongPressEndsWhileHeldAtItsDuration() throws {
    let log = GLog()
    let (window, platform) = try gestureWindow(root {
        $0.onLongPressGesture(minimumDuration: 0.3) { log.entries.append("long") }
    })
    try requireHitboxes(window, [rootRect])
    platform.simulateInput(down(150, 150))
    platform.simulateTick(timestamp: stamp)
    platform.simulateTick(timestamp: stamp + 0.2)
    #expect(log.entries == [], "not before the duration")
    platform.simulateTick(timestamp: stamp + 0.35)
    #expect(log.entries == ["long"], "at the duration, still held")
    platform.simulateInput(up(150, 150))
    #expect(log.entries == ["long"], "the release adds nothing")
}

/// **1.8** (G6b, G6c 30 pt, G6d 5 pt). A quick click ends no long press, a
/// 30-pt move fails it, a 5-pt move does not. M1g (maximum distance unchecked)
/// reddens the 30-pt arm.
@MainActor
@Test func aLongPressFailsOnAQuickClickAndPastItsMaximumDistance() throws {
    let log = GLog()
    let (window, platform) = try gestureWindow(root {
        $0.onLongPressGesture(minimumDuration: 0.3) { log.entries.append("long") }
    })
    try requireHitboxes(window, [rootRect])
    platform.simulateInput(down(150, 150))
    platform.simulateInput(up(150, 150))
    platform.simulateTick(timestamp: stamp)
    platform.simulateTick(timestamp: stamp + 1)
    #expect(log.entries == [], "a quick click (G6b)")

    platform.simulateInput(down(150, 150))
    platform.simulateInput(drag(180, 150))
    platform.simulateTick(timestamp: stamp + 2)
    platform.simulateTick(timestamp: stamp + 3)
    platform.simulateInput(up(180, 150))
    #expect(log.entries == [], "a 30-pt move fails it (G6c)")

    platform.simulateInput(down(150, 150))
    platform.simulateInput(drag(155, 150))
    platform.simulateTick(timestamp: stamp + 4)
    platform.simulateTick(timestamp: stamp + 5)
    #expect(log.entries == ["long"], "a 5-pt move does not (G6d)")
    platform.simulateInput(up(155, 150))
}

/// **1.9** (G6e: `pressing=true,perform,|held,pressing=false`; G6f:
/// `pressing=true,pressing=false`). `onPressingChanged` brackets the press.
/// M1h (no `false` on a failed press) reddens the quick-click arm.
@MainActor
@Test func onLongPressGestureBracketsThePressWithPressingChanges() throws {
    let log = GLog()
    let (window, platform) = try gestureWindow(root {
        $0.onLongPressGesture(minimumDuration: 0.3, perform: { log.entries.append("perform") },
                              onPressingChanged: { log.entries.append("pressing=\($0)") })
    })
    try requireHitboxes(window, [rootRect])
    platform.simulateInput(down(150, 150))
    platform.simulateTick(timestamp: stamp)
    platform.simulateTick(timestamp: stamp + 0.35)
    #expect(log.entries == ["pressing=true", "perform"], "held (G6e)")
    platform.simulateInput(up(150, 150))
    #expect(log.entries == ["pressing=true", "perform", "pressing=false"])

    log.entries = []
    platform.simulateInput(down(150, 150))
    platform.simulateInput(up(150, 150))
    platform.simulateTick(timestamp: stamp + 1)
    platform.simulateTick(timestamp: stamp + 2)
    #expect(log.entries == ["pressing=true", "pressing=false"], "a quick click (G6f)")
}

// MARK: - 1.10–1.12: drag

/// **1.10** (G8a, G8b). A drag changes from exactly its minimum distance, in the
/// element's local, y-down space: a press at the window's (150, 150) is the
/// 200 × 200 element's (100, 100). M1i (`>=` → `>`) reddens the first arm;
/// M1i′ (window coordinates) reddens the location.
@MainActor
@Test func aDragChangesFromExactlyItsMinimumDistanceInLocalYDownSpace() throws {
    let log = GLog()
    let values = DragValues()
    let (window, platform) = try gestureWindow(root {
        $0.gesture(DragGesture().onChanged { values.all.append($0); log.entries.append("chg\(fmt($0))") })
    })
    try requireHitboxes(window, [rootRect])
    platform.simulateInput(down(150, 150))
    platform.simulateInput(drag(155, 150))
    #expect(log.entries == [], "5 pt is short of the 10-pt minimum")
    platform.simulateInput(drag(160, 150))
    #expect(log.entries == ["chg(10,0)"], "exactly the minimum reports (G8a)")
    let first = try #require(values.all.first)
    #expect(first.startLocation == pt(100, 100), "local: the window's (150, 150)")
    #expect(first.location == pt(110, 100))
    platform.simulateInput(up(160, 150))

    log.entries = []
    platform.simulateInput(down(150, 150))
    platform.simulateInput(drag(150, 100))
    #expect(log.entries == ["chg(0,-50)"], "an upward drag reads negative y (G8b)")
    platform.simulateInput(up(150, 100))
}

/// **1.11** (G8c, G8d, G8e). A drag short of its minimum reports nothing, a
/// click reports nothing, and `minimumDistance: 0` reports a change and an end
/// for a click. M1i″ (end a drag that never started) reddens the first two.
@MainActor
@Test func aDragShortOfItsMinimumReportsNothingAndMinimumZeroReportsAClick() throws {
    let log = GLog()
    let (window, platform) = try gestureWindow {
        Row {
            Box().frame(width: Pixels(100), height: Pixels(100))
                .gesture(DragGesture().onChanged { _ in log.entries.append("chg") }
                    .onEnded { _ in log.entries.append("end") })
            Box().frame(width: Pixels(100), height: Pixels(100))
                .gesture(DragGesture(minimumDistance: 0).onChanged { _ in log.entries.append("chg0") }
                    .onEnded { _ in log.entries.append("end0") })
        }
    }
    try requireHitboxes(window, [Bounds(origin: pt(50, 100), size: Size(width: px(100), height: px(100))),
                                 Bounds(origin: pt(150, 100), size: Size(width: px(100), height: px(100)))])
    platform.simulateInput(down(100, 150))
    platform.simulateInput(drag(106, 150))
    platform.simulateInput(up(106, 150))
    #expect(log.entries == [], "6 pt reports nothing (G8c)")
    platform.simulateInput(down(100, 150))
    platform.simulateInput(up(100, 150))
    #expect(log.entries == [], "a click reports nothing (G8d)")
    platform.simulateInput(down(200, 150))
    platform.simulateInput(up(200, 150))
    #expect(log.entries == ["chg0", "end0"], "minimum 0: a change and an end for a click (G8e)")
}

/// **1.12** (G8f). A drag ends wherever it is released — here beyond the
/// window's edge, at local (350, 100). M1j (end only inside the element)
/// reddens it.
@MainActor
@Test func aDragEndsWhereverItIsReleased() throws {
    let log = GLog()
    let (window, platform) = try gestureWindow(root {
        $0.gesture(DragGesture().onEnded { log.entries.append("end(\(Int($0.location.x.value)),\(Int($0.location.y.value)))") })
    })
    try requireHitboxes(window, [rootRect])
    platform.simulateInput(down(150, 150))
    platform.simulateInput(drag(200, 150))
    platform.simulateInput(drag(299, 150))
    platform.simulateInput(up(400, 150))
    #expect(log.entries == ["end(350,100)"])
}

// MARK: - 1.13–1.17: composition

/// **1.13** (H0, H1, H12). An inner gesture beats an outer normal one, across a
/// child and its parent and on one element. M1k (normal members outermost
/// first) reddens it.
@MainActor
@Test func anInnerGestureBeatsAnOuterNormalOneOnAChildOrOneElement() throws {
    let log = GLog()
    do {
        let (window, platform) = try gestureWindow(nested(
            child: { $0.onTapGesture { log.entries.append("c") } },
            parent: { $0.onTapGesture { log.entries.append("p") } }))
        try requireHitboxes(window, [rootRect, childRect])
        platform.simulateInput(down(100, 100))
        platform.simulateInput(up(100, 100))
        platform.simulateInput(down(200, 200))
        platform.simulateInput(up(200, 200))
        #expect(log.entries == ["c", "p"], "the child wins its own press (H0); the parent keeps its own")
    }
    log.entries = []
    do {
        let (window, platform) = try gestureWindow(nested(
            child: { $0.gesture(TapGesture().onEnded { log.entries.append("c") }) },
            parent: { $0.gesture(TapGesture().onEnded { log.entries.append("p") }) }))
        try requireHitboxes(window, [rootRect, childRect])
        platform.simulateInput(down(100, 100))
        platform.simulateInput(up(100, 100))
        #expect(log.entries == ["c"], ".gesture(TapGesture()) on both (H1)")
    }
    log.entries = []
    do {
        let (window, platform) = try gestureWindow(root {
            $0.onTapGesture { log.entries.append("inner") }.onTapGesture { log.entries.append("outer") }
        })
        try requireHitboxes(window, [rootRect])
        platform.simulateInput(down(150, 150))
        platform.simulateInput(up(150, 150))
        #expect(log.entries == ["inner"], "one element: the earlier modifier is inner (H12)")
    }
}

/// **1.14** (H2, H8, H11, H14). An outer high-priority gesture beats the inner
/// one — a child's tap, a child's `onClick` and a child `Button` — and on one
/// element. M1l (high priority treated as normal) reddens it.
@MainActor
@Test func anOuterHighPriorityGestureBeatsTheInnerOneAndAButton() throws {
    let log = GLog()
    do {
        let (window, platform) = try gestureWindow(nested(
            child: { $0.onTapGesture { log.entries.append("c") } },
            parent: { $0.highPriorityGesture(TapGesture().onEnded { log.entries.append("p") }) }))
        try requireHitboxes(window, [rootRect, childRect])
        platform.simulateInput(down(100, 100))
        platform.simulateInput(up(100, 100))
        #expect(log.entries == ["p"], "over a child tap (H2)")
    }
    log.entries = []
    do {
        let (window, platform) = try gestureWindow(nested(
            child: { $0.onClick { log.entries.append("click") } },
            parent: { $0.highPriorityGesture(TapGesture().onEnded { log.entries.append("p") }) }))
        try requireHitboxes(window, [rootRect, childRect])
        platform.simulateInput(down(100, 100))
        platform.simulateInput(up(100, 100))
        #expect(log.entries == ["p"], "over a child onClick (H8)")
    }
    log.entries = []
    do {
        let (window, platform) = try gestureWindow {
            Column { Button("Go") { log.entries.append("button") } }
                .frame(width: Pixels(200), height: Pixels(200), alignment: .topLeading)
                .highPriorityGesture(TapGesture().onEnded { log.entries.append("p") })
        }
        let button = try #require(window.lastHitboxes.first { $0.handlers.onClick != nil }?.bounds)
        let x = button.origin.x.value + button.size.width.value / 2
        let y = button.origin.y.value + button.size.height.value / 2
        platform.simulateInput(down(x, y))
        platform.simulateInput(up(x, y))
        #expect(log.entries == ["p"], "over a child Button (H11)")
    }
    log.entries = []
    do {
        let (window, platform) = try gestureWindow(root {
            $0.onTapGesture { log.entries.append("inner") }
                .highPriorityGesture(TapGesture().onEnded { log.entries.append("outer") })
        })
        try requireHitboxes(window, [rootRect])
        platform.simulateInput(down(150, 150))
        platform.simulateInput(up(150, 150))
        #expect(log.entries == ["outer"], "one element (H14)")
    }
}

/// **1.15** (H3, H7, H10, H13). A simultaneous gesture fires beside the winner,
/// and first. M1m (simultaneous callbacks after the winner's) reddens it.
@MainActor
@Test func aSimultaneousGestureFiresFirstBesideTheWinner() throws {
    let log = GLog()
    do {
        let (window, platform) = try gestureWindow(nested(
            child: { $0.onTapGesture { log.entries.append("c") } },
            parent: { $0.simultaneousGesture(TapGesture().onEnded { log.entries.append("p") }) }))
        try requireHitboxes(window, [rootRect, childRect])
        platform.simulateInput(down(100, 100))
        platform.simulateInput(up(100, 100))
        #expect(log.entries == ["p", "c"], "over a child tap (H3)")
    }
    log.entries = []
    do {
        let (window, platform) = try gestureWindow(nested(
            child: { $0.onClick { log.entries.append("button") } },
            parent: { $0.simultaneousGesture(TapGesture().onEnded { log.entries.append("p") }) }))
        try requireHitboxes(window, [rootRect, childRect])
        platform.simulateInput(down(100, 100))
        platform.simulateInput(up(100, 100))
        #expect(log.entries == ["p", "button"], "over a child onClick (H7)")
    }
    log.entries = []
    do {
        let (window, platform) = try gestureWindow(root {
            $0.onClick { log.entries.append("button") }
                .simultaneousGesture(TapGesture().onEnded { log.entries.append("sim") })
        })
        try requireHitboxes(window, [rootRect])
        platform.simulateInput(down(150, 150))
        platform.simulateInput(up(150, 150))
        #expect(log.entries == ["sim", "button"], "beside an onClick on one element (H10)")
    }
    log.entries = []
    do {
        let (window, platform) = try gestureWindow(root {
            $0.onTapGesture { log.entries.append("inner") }
                .simultaneousGesture(TapGesture().onEnded { log.entries.append("outer") })
        })
        try requireHitboxes(window, [rootRect])
        platform.simulateInput(down(150, 150))
        platform.simulateInput(up(150, 150))
        #expect(log.entries == ["outer", "inner"], "one element (H13)")
    }
}

/// **1.16** (H4a/H4b, H5a/H5b, H6a/H6b, G7a/G7b, G9a/G9b). A member ends only
/// once every member ahead of it has failed, so a failed higher gesture hands
/// the press to the next one. M1n (a member ends without waiting for the
/// members ahead) reddens it.
@MainActor
@Test func aFailedHigherGestureHandsThePressToTheNextOne() throws {
    let log = GLog()
    func click(_ platform: FakePlatformWindow) {
        platform.simulateInput(down(100, 100))
        platform.simulateInput(up(100, 100))
    }
    func drag30(_ platform: FakePlatformWindow) {
        platform.simulateInput(down(80, 100))
        platform.simulateInput(drag(95, 100))
        platform.simulateInput(drag(110, 100))
        platform.simulateInput(up(110, 100))
    }
    // H4: a child drag, a parent tap.
    do {
        let (window, platform) = try gestureWindow(nested(
            child: { $0.gesture(DragGesture().onEnded { _ in log.entries.append("drag") }) },
            parent: { $0.onTapGesture { log.entries.append("p") } }))
        try requireHitboxes(window, [rootRect, childRect])
        click(platform)
        #expect(log.entries == ["p"], "the child drag fails at a click; the parent taps (H4a)")
        log.entries = []
        drag30(platform)
        #expect(log.entries == ["drag"], "the child drag ends and keeps it (H4b)")
    }
    log.entries = []
    // H5: a child tap, a parent drag.
    do {
        let (window, platform) = try gestureWindow(nested(
            child: { $0.onTapGesture { log.entries.append("c") } },
            parent: { $0.gesture(DragGesture().onEnded { _ in log.entries.append("drag") }) }))
        try requireHitboxes(window, [rootRect, childRect])
        click(platform)
        #expect(log.entries == ["c"], "a click is the child's (H5a)")
        log.entries = []
        drag30(platform)
        #expect(log.entries == ["drag"], "the child tap fails by moving; the parent drags (H5b)")
    }
    log.entries = []
    // H6: a parent high-priority drag, a child tap.
    do {
        let (window, platform) = try gestureWindow(nested(
            child: { $0.onTapGesture { log.entries.append("c") } },
            parent: { $0.highPriorityGesture(DragGesture().onEnded { _ in log.entries.append("drag") }) }))
        try requireHitboxes(window, [rootRect, childRect])
        click(platform)
        #expect(log.entries == ["c"], "the high-priority drag fails at the release; the child taps (H6a)")
        log.entries = []
        drag30(platform)
        #expect(log.entries == ["drag"], "a drag is the parent's (H6b)")
    }
    log.entries = []
    // G7: an inner tap, an outer long press, on one element.
    do {
        let (window, platform) = try gestureWindow(root {
            $0.onTapGesture { log.entries.append("tap") }
                .onLongPressGesture(minimumDuration: 0.3) { log.entries.append("long") }
        })
        try requireHitboxes(window, [rootRect])
        platform.simulateInput(down(150, 150))
        platform.simulateInput(drag(157, 150))
        platform.simulateTick(timestamp: stamp)
        platform.simulateTick(timestamp: stamp + 0.5)
        #expect(log.entries == ["long"], "a 7-pt move fails the tap; the long press ends held (G7a)")
        platform.simulateInput(up(157, 150))
        log.entries = []
        platform.simulateInput(down(150, 150))
        platform.simulateTick(timestamp: stamp + 1)
        platform.simulateTick(timestamp: stamp + 1.5)
        #expect(log.entries == [], "held: the tap is still possible and ahead (G7b `|held`)")
        platform.simulateInput(up(150, 150))
        #expect(log.entries == ["tap"], "the release taps (G7b)")
    }
    log.entries = []
    // G9: an inner tap, an outer drag, on one element.
    do {
        let (window, platform) = try gestureWindow(root {
            $0.onTapGesture { log.entries.append("tap") }
                .gesture(DragGesture().onEnded { _ in log.entries.append("drag") })
        })
        try requireHitboxes(window, [rootRect])
        platform.simulateInput(down(150, 150))
        platform.simulateInput(up(150, 150))
        #expect(log.entries == ["tap"], "a click taps (G9a)")
        log.entries = []
        platform.simulateInput(down(150, 150))
        platform.simulateInput(drag(180, 150))
        platform.simulateInput(up(180, 150))
        #expect(log.entries == ["drag"], "a drag drags (G9b)")
    }
}

/// **1.17** (H15a, H16a, H16b). `exclusively(before:)` tries its first member
/// and `simultaneously(with:)` runs both. M1o (`simultaneously` resolved
/// exclusively) reddens the second arm.
@MainActor
@Test func exclusivelyTriesItsFirstMemberAndSimultaneouslyRunsBoth() throws {
    let log = GLog()
    do {
        let (window, platform) = try gestureWindow(root {
            $0.gesture(TapGesture().onEnded { log.entries.append("a") }
                .exclusively(before: TapGesture().onEnded { log.entries.append("b") }))
        })
        try requireHitboxes(window, [rootRect])
        platform.simulateInput(down(150, 150))
        platform.simulateInput(up(150, 150))
        #expect(log.entries == ["a"], "the first member wins (H15a)")
    }
    log.entries = []
    do {
        let (window, platform) = try gestureWindow(root {
            $0.gesture(LongPressGesture(minimumDuration: 0.3).onEnded { _ in log.entries.append("long") }
                .simultaneously(with: TapGesture().onEnded { log.entries.append("tap") }))
        })
        try requireHitboxes(window, [rootRect])
        platform.simulateInput(down(150, 150))
        platform.simulateTick(timestamp: stamp)
        platform.simulateTick(timestamp: stamp + 0.35)
        #expect(log.entries == ["long"], "held (H16b `long,|held`)")
        platform.simulateInput(up(150, 150))
        #expect(log.entries == ["long", "tap"], "both run (H16b)")
    }
}

// MARK: - 1.18–1.23: onClick, gates, identity, the proposal path, time

/// **1.18** (`IX-D` item 2). A parent's `onClick` still never sees a press whose
/// target is a child — here a child whose drag fails at a click. Behaviourally
/// today's rule, written first and kept green; M1p (ancestors' `onClick` join
/// the arena) reddens it.
@MainActor
@Test func aParentsOnClickStillNeverSeesAChildsPress() throws {
    let log = GLog()
    let (window, platform) = try gestureWindow(nested(
        child: { $0.gesture(DragGesture().onEnded { _ in log.entries.append("drag") }) },
        parent: { $0.onClick { log.entries.append("parent") } }))
    try requireHitboxes(window, [rootRect, childRect])
    platform.simulateInput(down(100, 100))
    platform.simulateInput(up(100, 100))
    #expect(log.entries == [], "the child's drag failed; the parent's onClick never joined")
    platform.simulateInput(down(200, 200))
    platform.simulateInput(up(200, 200))
    #expect(log.entries == ["parent"], "control: the parent's own press clicks it")
}

/// **1.19** (H17, N1). A disabled or hit-testing-off gesture leaves the press to
/// its parent. M1q (gestures registered outside the hitbox gate) reddens it.
@MainActor
@Test func aDisabledOrHitTestingOffGestureLeavesThePressToItsParent() throws {
    let log = GLog()
    do {
        let (window, platform) = try gestureWindow {
            Column {
                Box().frame(width: Pixels(100), height: Pixels(100))
                    .onTapGesture { log.entries.append("c") }.disabled(true)
            }
            .frame(width: Pixels(200), height: Pixels(200), alignment: .topLeading)
            .onTapGesture { log.entries.append("p") }
        }
        try requireHitboxes(window, [rootRect])
        platform.simulateInput(down(100, 100))
        platform.simulateInput(up(100, 100))
        #expect(log.entries == ["p"], "disabled (H17)")
    }
    log.entries = []
    do {
        let (window, platform) = try gestureWindow(nested(
            child: { $0.onTapGesture { log.entries.append("c") }.allowsHitTesting(false) },
            parent: { $0.onTapGesture { log.entries.append("p") } }))
        try requireHitboxes(window, [rootRect])
        platform.simulateInput(down(100, 100))
        platform.simulateInput(up(100, 100))
        #expect(log.entries == ["p"], "hit testing off (N1)")
    }
    // The proposal path's `GestureModifier` (`IX-Q` item 3): hit testing off
    // leaves no target; the same tree with it on taps (the control). V2
    // (registered through `insertHitbox`, past the gates) reddens it.
    for enabled in [true, false] {
        log.entries = []
        let (window, platform) = try gestureWindow {
            HStack {
                Rectangle(width: px(200), height: px(200)).onTapGesture { log.entries.append("c") }
                    .allowsHitTesting(enabled)
            }
        }
        try requireHitboxes(window, enabled ? [rootRect] : [])
        platform.simulateInput(down(100, 100))
        platform.simulateInput(up(100, 100))
        #expect(log.entries == (enabled ? ["c"] : []), "proposal, allowsHitTesting(\(enabled))")
    }
}

/// A `Component` whose body is one tappable box writing its `@State`.
private struct TappingComponent: Component {
    @State var n = 0
    var content: some ElementGroup {
        Box().frame(width: Pixels(20), height: Pixels(20)).onTapGesture { n += 1 }
    }
}

/// **1.20** (`ID-F`). A gesture callback writes the occurrence that dispatched
/// it: one component value placed twice, the first occurrence tapped. M1r
/// (callback run without `StateDispatch`) reddens it.
@MainActor
@Test func aGestureCallbackWritesTheOccurrenceThatDispatchedIt() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let (window, platform) = try makeFakeWindow(device: device, size: 200) {
        let component = TappingComponent()
        return Row { component; component }
    }
    window.drawFrameIfNeeded()
    let taps = window.lastHitboxes.filter { !$0.handlers.gestures.isEmpty }
    try #require(taps.count == 2, "each occurrence registers its own hitbox")
    let components = try taps.map { try #require($0.id.parent) }
    try #require(components[0] != components[1])
    func count(_ id: GlobalElementID) -> Int {
        window.stateTable.peek(GlobalElementID.child(of: id, at: 0, name: ElementID("$state0")),
                               as: Int.self) ?? 0
    }
    let centre = Point(x: taps[0].bounds.origin.x + Pixels(10), y: taps[0].bounds.origin.y + Pixels(10))
    platform.simulateInput(.mouseDown(MouseEvent(position: centre)))
    platform.simulateInput(.mouseUp(MouseEvent(position: centre)))
    #expect(components.map(count) == [1, 0], "occurrence 0 was tapped; last-bound dispatch reads [0, 1]")
}

/// **1.21**. The proposal path's `GestureModifier` recognizes as the legacy
/// modifiers do: 1.1's tap, 1.10's local drag and 1.14's high priority, on an
/// `HStack` child. M1s (`GestureModifier` registers no gestures) reddens it.
@MainActor
@Test func aProposalGestureModifierRecognizesAsTheLegacyOneDoes() throws {
    let log = GLog()
    do {
        let (window, platform) = try gestureWindow {
            HStack { Rectangle(width: px(200), height: px(200)).onTapGesture { log.entries.append("tap") } }
        }
        try requireHitboxes(window, [rootRect])
        platform.simulateInput(down(150, 150))
        #expect(log.entries == [])
        platform.simulateInput(up(150, 150))
        #expect(log.entries == ["tap"], "1.1 on the proposal path")
    }
    log.entries = []
    do {
        let (window, platform) = try gestureWindow {
            HStack {
                Rectangle(width: px(200), height: px(200))
                    .gesture(DragGesture().onChanged { log.entries.append("chg\(fmt($0)) at \(Int($0.location.x.value)),\(Int($0.location.y.value))") })
            }
        }
        try requireHitboxes(window, [rootRect])
        platform.simulateInput(down(150, 150))
        platform.simulateInput(drag(160, 150))
        platform.simulateInput(up(160, 150))
        #expect(log.entries == ["chg(10,0) at 110,100"], "1.10 on the proposal path")
    }
    log.entries = []
    do {
        let (window, platform) = try gestureWindow {
            HStack {
                Rectangle(width: px(200), height: px(200))
                    .onTapGesture { log.entries.append("inner") }
                    .highPriorityGesture(TapGesture().onEnded { log.entries.append("outer") })
            }
        }
        try requireHitboxes(window, [rootRect, rootRect])
        platform.simulateInput(down(150, 150))
        platform.simulateInput(up(150, 150))
        #expect(log.entries == ["outer"], "1.14 on the proposal path")
    }
}

/// **1.22** (`IX-C` item 4). A pending gesture keeps frames coming only while it
/// is pending: frames are drawn while a long press is held short of its
/// duration, and none once it has ended though the button is still down.
/// M1t (request frames unconditionally while pressed) reddens it.
@MainActor
@Test func aPendingGestureKeepsFramesComingOnlyWhilePending() throws {
    let log = GLog()
    let (window, platform) = try gestureWindow(root {
        $0.onLongPressGesture(minimumDuration: 0.3) { log.entries.append("long") }
    })
    try requireHitboxes(window, [rootRect])
    platform.simulateTick(timestamp: stamp - 1)
    let idle = window.framesDrawn
    platform.simulateTick(timestamp: stamp - 0.5)
    try #require(window.framesDrawn == idle, "control: an idle window draws nothing")

    platform.simulateInput(down(150, 150))
    var drawn: [Int] = []
    for t in [0.0, 0.1, 0.2, 0.35, 0.4, 0.5, 0.6] {
        let before = window.framesDrawn
        platform.simulateTick(timestamp: stamp + t)
        drawn.append(window.framesDrawn - before)
    }
    #expect(log.entries == ["long"])
    #expect(drawn == [1, 1, 1, 1, 0, 0, 0],
            "a frame per tick while pending (the tick that ends it included); none after, held or not")
    platform.simulateInput(up(150, 150))
}

/// **1.23** (X3, X4; `IX-D` item 3). A child's `onClick` — which never fails on
/// a move — holds a parent's normal drag off for the whole press: a click and a
/// 30-pt drag inside the child both run the child's `onClick`, and the drag
/// reports neither a change nor an end; released outside the child, nothing
/// runs at all (`IX-D` 3's unmeasured corner, MetalUI's choice). M1u (withhold
/// ends only, so a behind member's `onChanged` runs) reddens it.
@MainActor
@Test func aChildsOnClickHoldsOffAParentsDragWhichReportsNothing() throws {
    let log = GLog()
    let (window, platform) = try gestureWindow(nested(
        child: { $0.onClick { log.entries.append("click") } },
        parent: { $0.gesture(DragGesture().onChanged { _ in log.entries.append("chg") }
            .onEnded { _ in log.entries.append("end") }) }))
    try requireHitboxes(window, [rootRect, childRect])
    platform.simulateInput(down(70, 100))
    platform.simulateInput(up(70, 100))
    #expect(log.entries == ["click"], "a click on the child (X3)")

    log.entries = []
    platform.simulateInput(down(70, 100))
    platform.simulateInput(drag(85, 100))
    platform.simulateInput(drag(100, 100))
    platform.simulateInput(up(100, 100))
    #expect(log.entries == ["click"], "a 30-pt drag inside the child: the click, no change (X4)")

    log.entries = []
    platform.simulateInput(down(70, 100))
    platform.simulateInput(drag(120, 100))
    platform.simulateInput(drag(200, 200))
    platform.simulateInput(up(200, 200))
    #expect(log.entries == [], "released outside the child: the drag was withheld and is cancelled")
}

// MARK: - 1.24–1.28: the fix round's pins (IX-Q)

/// **1.24** (`IX-Q`, probe `swiftui-gesture-presentation-arena.swift` S1/S2,
/// V1/V2). A `Deferred` presentation's content does not join its declarer's
/// arena: a root's high-priority tap does not beat a modal's `onClick` hoisted
/// above it, and a root's simultaneous tap does not run beside it. A press on
/// the root outside the modal still runs the root's gesture (the control, so
/// the arena is shown to exist). Mutation V4 (ancestors of any layer join, the
/// lane-1 code) reddens both modal arms.
@MainActor
@Test func aDeferredPresentationsPressDoesNotJoinItsDeclarersArena() throws {
    let log = GLog()
    for simultaneous in [false, true] {
        log.entries = []
        let (window, platform) = try gestureWindow {
            let column = Column {
                Deferred {
                    Box().frame(width: px(40), height: px(40)).onClick { log.entries.append("modal") }
                        .position(.absolute)
                        .inset(Edges(top: .length(.pixels(px(100))), right: .auto,
                                     bottom: .auto, left: .length(.pixels(px(100)))))
                }
            }
            .frame(width: px(200), height: px(200))
            return simultaneous
                ? column.simultaneousGesture(TapGesture().onEnded { log.entries.append("root") })
                : column.highPriorityGesture(TapGesture().onEnded { log.entries.append("root") })
        }
        let modal = Bounds(origin: pt(100, 100), size: Size(width: px(40), height: px(40)))
        try requireHitboxes(window, [rootRect, modal])
        let layers = window.lastHitboxes.filter { $0.scroll == nil }.map(\.layer)
        try #require(Set(layers).count == 2, "the modal is in a layer above the root's: \(layers)")
        platform.simulateInput(down(120, 120))
        platform.simulateInput(up(120, 120))
        #expect(log.entries == ["modal"], "simultaneous=\(simultaneous): the modal's press is its own")
        log.entries = []
        platform.simulateInput(down(200, 200))
        platform.simulateInput(up(200, 200))
        #expect(log.entries == ["root"], "simultaneous=\(simultaneous): control — the root's own press")
    }
}

/// **1.25** (`IX-D` item 1's region clause). A child overflowing its
/// gesture-carrying ancestor, pressed where the ancestor's region does not
/// reach, is not in the ancestor's arena: the ancestor's high-priority drag
/// neither reports nor holds the child's `onClick` off. Pressed inside the
/// ancestor, the drag takes the press (the control). Mutation V3 (ancestors
/// join whether or not they contain the point) reddens the overflow arm.
@MainActor
@Test func anOverflowingChildsPressOutsideItsAncestorLeavesTheAncestorOut() throws {
    let log = GLog()
    let (window, platform) = try gestureWindow {
        Box().frame(width: px(100), height: px(100)).onClick { log.entries.append("click") }
            .frame(width: px(50), height: px(100))
            .highPriorityGesture(DragGesture().onChanged { _ in log.entries.append("drag") })
    }
    let boxes = window.lastHitboxes.filter { $0.scroll == nil }
    let ancestor = try #require(boxes.first { !$0.handlers.gestures.isEmpty })
    let child = try #require(boxes.first { $0.handlers.onClick != nil })
    try #require(ancestor.bounds.size.width == px(50) && child.bounds.size.width == px(100),
                 "the child overflows the 50-wide ancestor: \(boxes.map(\.bounds))")
    let y = child.bounds.origin.y.value + 50
    let outside = child.bounds.origin.x.value + 5
    let inside = ancestor.bounds.origin.x.value + 25
    try #require(!ancestor.contains(pt(outside, y)) && child.contains(pt(outside, y)))
    try #require(ancestor.contains(pt(inside, y)) && child.contains(pt(inside, y)))

    platform.simulateInput(down(outside, y))
    platform.simulateInput(drag(outside + 20, y))
    platform.simulateInput(up(outside + 20, y))
    #expect(log.entries == ["click"], "outside the ancestor: the child's click, no drag")

    log.entries = []
    platform.simulateInput(down(inside, y))
    platform.simulateInput(drag(inside + 20, y))
    platform.simulateInput(up(inside + 20, y))
    #expect(log.entries == ["drag"], "control: inside it, the ancestor's high-priority drag wins")
}

/// **1.26** (`IX-P` item 4). A single tap waiting on a double ends when a press
/// lands on another target within the deferral — at that press, not later and
/// not never. Mutation V6 (the other target's press drops the arena without
/// `abandon()`) reddens it.
@MainActor
@Test func aWaitingSingleTapEndsWhenThePressMovesToAnotherTarget() throws {
    let log = GLog()
    let (window, platform) = try gestureWindow {
        Row {
            Box().frame(width: px(100), height: px(100))
                .onTapGesture(count: 2) { log.entries.append("double") }
                .onTapGesture { log.entries.append("single") }
            Box().frame(width: px(100), height: px(100)).onClick { log.entries.append("click") }
        }
    }
    try requireHitboxes(window, [Bounds(origin: pt(50, 100), size: Size(width: px(100), height: px(100))),
                                 Bounds(origin: pt(150, 100), size: Size(width: px(100), height: px(100)))])
    platform.simulateInput(down(100, 150))
    platform.simulateInput(up(100, 150))
    platform.simulateTick(timestamp: stamp)
    platform.simulateTick(timestamp: stamp + 0.1)
    #expect(log.entries == [], "still inside the deferral")
    platform.simulateInput(down(200, 150))
    #expect(log.entries == ["single"], "the press elsewhere ends the waiting single tap")
    platform.simulateInput(up(200, 150))
    #expect(log.entries == ["single", "click"])
    platform.simulateTick(timestamp: stamp + 1)
    #expect(log.entries == ["single", "click"], "once")
}

/// **1.27** (`IX-P`'s `Hitbox.origin`). A drag's locations are relative to the
/// element's own box, not to its content-shape-inset hit region: a press at the
/// window's (150, 150) on the 200 × 200 root inset by 20 starts at (100, 100).
/// Mutation V5 (the hitbox origin falls back to the inset region's) reddens it.
@MainActor
@Test func aDragOnAContentShapeInsetElementReadsTheElementsOwnSpace() throws {
    let values = DragValues()
    let (window, platform) = try gestureWindow(root {
        $0.contentShape(inset: px(20)).gesture(DragGesture().onChanged { values.all.append($0) })
    })
    try requireHitboxes(window, [Bounds(origin: pt(70, 70), size: Size(width: px(160), height: px(160)))])
    platform.simulateInput(down(150, 150))
    platform.simulateInput(drag(160, 150))
    platform.simulateInput(up(160, 150))
    let first = try #require(values.all.first)
    #expect(first.startLocation == pt(100, 100), "the element's box, not the inset region's (80, 80)")
    #expect(first.location == pt(110, 100))
}

/// **1.28** (`IX-C` item 1). A tap released outside its element fails even when
/// the pointer moved less than the 5-pt slop: pressed 2 pt inside the root's
/// right edge and released 2 pt outside it (4 pt), no tap; the same 3-pt move
/// released inside taps (the control). Mutation V7 (no region check at the
/// release) reddens it.
@MainActor
@Test func aTapReleasedJustOutsideItsElementFailsInsideTheSlop() throws {
    let log = GLog()
    let (window, platform) = try gestureWindow(root { $0.onTapGesture { log.entries.append("tap") } })
    try requireHitboxes(window, [rootRect])
    platform.simulateInput(down(245, 150))
    platform.simulateInput(up(248, 150))
    #expect(log.entries == ["tap"], "control: a 3-pt move released inside taps")
    platform.simulateInput(down(248, 150))
    platform.simulateInput(up(252, 150))
    #expect(log.entries == ["tap"], "a 4-pt move released outside the element does not tap")
}
