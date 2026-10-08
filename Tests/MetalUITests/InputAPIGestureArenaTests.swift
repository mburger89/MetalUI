import Testing
import MetalUICore
import MetalUIPlatform
@testable import MetalUI

// Input APIs, lane 2 — the gesture arena's new modes, tested pure (rulings
// `CI-B`, `CI-C`, `CI-D`, `CI-F`, `CI-G`; spec
// `docs/superpowers/specs/2026-10-08-input-apis-design.md` §4.2, tests
// 2.3–2.20). `GestureArena` knows only hitboxes and points (`CI-N`), so every
// test builds its hitboxes by hand and feeds the arena directly — no `Window`.
// SwiftUI's answers are arms of `docs/probes/swiftui-input-apis.swift` (named
// per test); the rest is MetalUI's own, ruled.
//
// Geometry: the target region is 100 × 100 with its top-leading corner at
// (40, 30) unless a test says otherwise, so a window point (x, y) is the local
// point (x − 40, y − 30).

// MARK: - Fixtures

@MainActor
private final class ALog {
    var entries: [String] = []
    var points: [Point<Pixels>] = []
    var drags: [DragGesture.Value] = []
    var dragEnds: [DragGesture.Value] = []
    var magnifies: [MagnifyGesture.Value] = []
    var magnifyEnds: [MagnifyGesture.Value] = []
    var rotations: [RotateGesture.Value] = []
    var rotationEnds: [RotateGesture.Value] = []
}

private func px(_ v: Float) -> Pixels { Pixels(v) }
private func pt(_ x: Float, _ y: Float) -> Point<Pixels> { Point(x: px(x), y: px(y)) }

private let rootID = GlobalElementID(component: .positional(0), parent: nil)
private let childID = GlobalElementID.child(of: rootID, at: 0, name: nil)

/// An opaque pointer hitbox for `id` with `gestures` (and an `onClick`).
@MainActor
private func region(_ id: GlobalElementID, x: Float = 40, y: Float = 30, w: Float = 100, h: Float = 100,
                    _ gestures: [GestureAttachment] = [], onClick: (@MainActor () -> Void)? = nil,
                    transform: HitboxTransform? = nil) -> Hitbox {
    var handlers = Handlers()
    handlers.gestures = gestures
    handlers.onClick = onClick
    return Hitbox(bounds: Bounds(origin: pt(x, y), size: Size(width: px(w), height: px(h))), id: id, layer: 0,
                  opaque: true, scroll: nil, handlers: handlers, origin: pt(x, y), shape: nil,
                  transform: transform)
}

@MainActor private func normal<G: Gesture>(_ g: G) -> GestureAttachment { GestureAttachment(g, priority: .normal) }
@MainActor private func high<G: Gesture>(_ g: G) -> GestureAttachment { GestureAttachment(g, priority: .high) }

/// Runs what the arena decided, in order.
@MainActor
private func run(_ callbacks: [GestureCallback], _ log: ALog) {
    for callback in callbacks {
        switch callback {
        case .gesture(_, let run): run()
        case .click(_, let handler, _): handler()
        case .beginDrag: log.entries.append("beginDrag")
        }
    }
}

private func mag(_ delta: Double, _ phase: InputPhase, at p: Point<Pixels> = pt(60, 50)) -> MagnifyEvent {
    MagnifyEvent(position: p, magnification: delta, phase: phase)
}

private func rot(_ degrees: Double, _ phase: InputPhase, at p: Point<Pixels> = pt(60, 50)) -> RotateEvent {
    RotateEvent(position: p, rotation: degrees, phase: phase)
}

private func close(_ a: Point<Pixels>, _ b: Point<Pixels>) -> Bool {
    abs(a.x.value - b.x.value) < 0.01 && abs(a.y.value - b.y.value) < 0.01
}

private func close(_ a: [Double], _ b: [Double]) -> Bool {
    a.count == b.count && zip(a, b).allSatisfy { abs($0 - $1) < 1e-9 }
}

// MARK: - 2.3–2.6: spatial tap

/// **2.3** (probe `T1`, `CI-B` item 1). A spatial tap reports the release that
/// ends it, in the gesture element's local space: region origin (40, 30),
/// press (50, 60), release (52, 61) → (12, 31). Mutation: report the press
/// point → (10, 30).
@MainActor
@Test func aSpatialTapReportsItsReleasePointInLocalSpace() throws {
    let log = ALog()
    let target = region(rootID, [normal(SpatialTapGesture().onEnded { log.points.append($0.location) })])
    var arena = try #require(GestureArena(target: target, ancestors: []))
    run(arena.press(at: pt(50, 60), clickCount: 1, continuing: false), log)
    #expect(log.points.isEmpty, "nothing at the press")
    run(arena.release(at: pt(52, 61), clickCount: 1, click: nil), log)
    #expect(log.points == [pt(12, 31)])
}

/// **2.4** (probe `T2`, `CI-B` item 3; divergence 139). `.global` is the
/// window's content space: the same tap reports (52, 61). Mutation: ignore
/// `coordinateSpace`.
@MainActor
@Test func aSpatialTapInGlobalSpaceReportsTheWindowPoint() throws {
    let log = ALog()
    let target = region(rootID, [normal(SpatialTapGesture(coordinateSpace: .global)
                                            .onEnded { log.points.append($0.location) })])
    var arena = try #require(GestureArena(target: target, ancestors: []))
    run(arena.press(at: pt(50, 60), clickCount: 1, continuing: false), log)
    run(arena.release(at: pt(52, 61), clickCount: 1, click: nil), log)
    #expect(log.points == [pt(52, 61)])
}

/// **2.5** (probe `T4`). A spatial double tap reports its second release.
/// Mutation: record the first release → (11, 30).
@MainActor
@Test func aSpatialDoubleTapReportsTheSecondRelease() throws {
    let log = ALog()
    let target = region(rootID, [normal(SpatialTapGesture(count: 2).onEnded { log.points.append($0.location) })])
    var arena = try #require(GestureArena(target: target, ancestors: []))
    run(arena.press(at: pt(50, 60), clickCount: 1, continuing: false), log)
    run(arena.release(at: pt(51, 60), clickCount: 1, click: nil), log)
    #expect(log.points.isEmpty, "one click does not end a double tap")
    run(arena.press(at: pt(50, 60), clickCount: 2, continuing: true), log)
    run(arena.release(at: pt(53, 62), clickCount: 2, click: nil), log)
    #expect(log.points == [pt(13, 32)])
}

/// **2.6** (`CI-L`, `GX-P`). A spatial tap through a rotation reports where on
/// itself the element was tapped: the region (40, 30)–(140, 130) turned 90°
/// clockwise about its centre (90, 80) draws its local (10, 10) at window
/// (130, 40). Mutation: skip `Hitbox.localPoint` → (90, 10).
@MainActor
@Test func aSpatialTapThroughARotationReportsWhereOnItselfItWasTapped() throws {
    let log = ALog()
    let forward = Affine2D.rotation(radians: Double.pi / 2, about: 90, 80)
    let clip = Bounds(origin: pt(-1000, -1000), size: Size(width: px(3000), height: px(3000)))
    let target = region(rootID, [normal(SpatialTapGesture().onEnded { log.points.append($0.location) })],
                        transform: HitboxTransform(inverse: forward.inverted, outerClip: clip))
    try #require(target.contains(pt(130, 40)), "set up: the drawn point is inside the rotated region")
    var arena = try #require(GestureArena(target: target, ancestors: []))
    run(arena.press(at: pt(130, 40), clickCount: 1, continuing: false), log)
    run(arena.release(at: pt(130, 40), clickCount: 1, click: nil), log)
    try #require(log.points.count == 1)
    #expect(close(log.points[0], pt(10, 10)), "local (10, 10): \(log.points)")
}

// MARK: - 2.7–2.11: drags — modifiers, space, buttons

/// **2.7** (`CI-G`; divergence 140). A drag value carries the modifiers of the
/// event that produced it: press `[]` (a `minimumDistance: 0` first change),
/// move `[.option]`, release `[.shift]`. Mutation: always the press's.
@MainActor
@Test func aDragValueCarriesTheModifiersOfItsEvent() throws {
    let log = ALog()
    let target = region(rootID, [normal(DragGesture(minimumDistance: 0)
                                            .onChanged { log.drags.append($0) }
                                            .onEnded { log.dragEnds.append($0) })])
    var arena = try #require(GestureArena(target: target, ancestors: []))
    run(arena.press(at: pt(50, 60), clickCount: 1, continuing: false, modifiers: []), log)
    run(arena.move(to: pt(70, 60), modifiers: [.option]), log)
    run(arena.release(at: pt(80, 60), clickCount: 1, modifiers: [.shift], click: nil), log)
    #expect(log.drags.map(\.modifiers) == [[], [.option]])
    #expect(log.dragEnds.map(\.modifiers) == [[.shift]])
    #expect(DragGesture.Value(startLocation: pt(0, 0), location: pt(1, 1)).modifiers == [],
            "the old initialiser keeps its spelling, modifiers []")
}

/// **2.8** (`CI-B` item 3, `CI-F` item 5). A `.global` drag reports window
/// points. Mutation: ignore `coordinateSpace`.
@MainActor
@Test func aGlobalDragReportsWindowPoints() throws {
    let log = ALog()
    let target = region(rootID, [normal(DragGesture(minimumDistance: 0, coordinateSpace: .global)
                                            .onChanged { log.drags.append($0) })])
    var arena = try #require(GestureArena(target: target, ancestors: []))
    run(arena.press(at: pt(50, 60), clickCount: 1, continuing: false), log)
    run(arena.move(to: pt(70, 65)), log)
    try #require(log.drags.count == 2)
    #expect(log.drags[1].startLocation == pt(50, 60))
    #expect(log.drags[1].location == pt(70, 65))
    #expect(log.drags[1].translation == Size(width: px(20), height: px(5)))
}

/// **2.9** (`CI-D` item 2, `CI-F` item 3). A press arena fails pinch leaves
/// and non-primary drags at formation: `MagnifyGesture().exclusively(before:
/// DragGesture(minimumDistance: 0))` drags on a press, and a secondary drag
/// declared FIRST — which, live, would report at the press and hold the
/// composition off — reports nothing. Mutation: do not fail pinch leaves at
/// formation → the drag never reports.
@MainActor
@Test func aPressArenaFailsPinchLeavesAndNonPrimaryDrags() throws {
    let log = ALog()
    let target = region(rootID, [
        normal(DragGesture(minimumDistance: 0, button: .secondary).onChanged { _ in log.entries.append("secondary") }),
        normal(MagnifyGesture().onChanged { _ in log.entries.append("magnify") }
            .exclusively(before: DragGesture(minimumDistance: 0).onChanged { _ in log.entries.append("drag") })),
    ])
    var arena = try #require(GestureArena(target: target, ancestors: [], mode: .press))
    run(arena.press(at: pt(50, 60), clickCount: 1, continuing: false), log)
    run(arena.move(to: pt(60, 60)), log)
    #expect(log.entries == ["drag", "drag"], "\(log.entries)")
}

/// **2.10** (`CI-F` item 3). A button arena for button N has only button N's
/// drag leaves: in `.button(1)` the secondary drag is live while a primary
/// `DragGesture()` ahead of it, a tap and the target's `onClick` are dead (the
/// release even hands a click); `.button(2)` with no middle leaf is no arena.
/// Mutation: add the click member in button mode.
@MainActor
@Test func aButtonArenaHasOnlyItsButtonsDragLeaves() throws {
    let log = ALog()
    let target = region(rootID, [
        normal(DragGesture(minimumDistance: 0).onChanged { _ in log.entries.append("primary") }),
        normal(TapGesture().onEnded { log.entries.append("tap") }),
        normal(DragGesture(minimumDistance: 0, button: .secondary)
            .onChanged { _ in log.entries.append("secondary") }
            .onEnded { _ in log.entries.append("secondary end") }),
    ], onClick: { log.entries.append("click") })
    #expect(GestureArena(target: target, ancestors: [], mode: .button(2)) == nil, "no middle leaf, no arena")
    var arena = try #require(GestureArena(target: target, ancestors: [], mode: .button(1)))
    run(arena.press(at: pt(50, 60), clickCount: 1, continuing: false), log)
    run(arena.release(at: pt(50, 60), clickCount: 1, click: ({ log.entries.append("click") }, [])), log)
    #expect(log.entries == ["secondary", "secondary end"], "\(log.entries)")
    #expect(!arena.isAlive, "the release of button N ends it")
}

/// **2.11** (`IX-C` item 5, `CI-F` item 4). A secondary drag activates at its
/// minimum distance (default 10): 9 pt nothing, 10 pt `onChanged`, the
/// release `onEnded`; `activatedAnyDrag` false, then true. Mutation: `>` for
/// `>=`.
@MainActor
@Test func aSecondaryDragActivatesAtItsMinimumDistance() throws {
    let log = ALog()
    let target = region(rootID, [normal(DragGesture(button: .secondary)
                                            .onChanged { log.drags.append($0) }
                                            .onEnded { log.dragEnds.append($0) })])
    var arena = try #require(GestureArena(target: target, ancestors: [], mode: .button(1)))
    run(arena.press(at: pt(50, 60), clickCount: 1, continuing: false), log)
    run(arena.move(to: pt(59, 60)), log)
    #expect(log.drags.isEmpty && !arena.activatedAnyDrag, "9 pt: nothing")
    run(arena.move(to: pt(60, 60)), log)
    #expect(log.drags.map(\.translation) == [Size(width: px(10), height: px(0))], "10 pt: the first change")
    #expect(arena.activatedAnyDrag)
    run(arena.release(at: pt(60, 60), clickCount: 1, click: nil), log)
    #expect(log.dragEnds.map(\.translation) == [Size(width: px(10), height: px(0))])
}

// MARK: - 2.12–2.16: magnify and rotate values

/// **2.12** (probe `M1`, `CI-C` item 1). `magnification` is cumulative and
/// additive from 1: began, +0.1, +0.1, ended → 1.1, 1.2, end 1.2; the arena
/// dies with the gesture. Mutation: multiply → 1.21.
@MainActor
@Test func magnificationIsCumulativeAndAdditiveFromOne() throws {
    let log = ALog()
    let target = region(rootID, [normal(MagnifyGesture()
                                            .onChanged { log.magnifies.append($0) }
                                            .onEnded { log.magnifyEnds.append($0) })])
    var arena = try #require(GestureArena(target: target, ancestors: [], mode: .pinch))
    run(arena.magnify(mag(0, .began)), log)
    run(arena.magnify(mag(0.1, .changed)), log)
    run(arena.magnify(mag(0.1, .changed)), log)
    #expect(arena.isAlive, "alive while the magnify has not ended")
    run(arena.magnify(mag(0, .ended)), log)
    #expect(close(log.magnifies.map(\.magnification), [1.1, 1.2]), "\(log.magnifies.map(\.magnification))")
    #expect(close(log.magnifyEnds.map(\.magnification), [1.2]))
    #expect(!arena.isAlive, "every begun kind ended")
}

/// **2.13** (`CI-C` item 4). A magnify activates only once |magnification − 1|
/// reaches `minimumScaleDelta` (0.05: +0.03 nothing, +0.03 → 1.06), then
/// reports every event. Mutation: activate on the first event.
@MainActor
@Test func aMagnifyActivatesOnlyAtItsMinimumScaleDelta() throws {
    let log = ALog()
    let target = region(rootID, [normal(MagnifyGesture(minimumScaleDelta: 0.05)
                                            .onChanged { log.magnifies.append($0) })])
    var arena = try #require(GestureArena(target: target, ancestors: [], mode: .pinch))
    run(arena.magnify(mag(0, .began)), log)
    run(arena.magnify(mag(0.03, .changed)), log)
    #expect(log.magnifies.isEmpty, "1.03: below the minimum")
    run(arena.magnify(mag(0.03, .changed)), log)
    #expect(close(log.magnifies.map(\.magnification), [1.06]), "\(log.magnifies.map(\.magnification))")
}

/// **2.14** (`CI-C` item 4). A magnify that never activated ends with no
/// callback. Mutation: always run `onEnded`.
@MainActor
@Test func aMagnifyThatNeverActivatedEndsWithNoCallback() throws {
    let log = ALog()
    let target = region(rootID, [normal(MagnifyGesture(minimumScaleDelta: 0.5)
                                            .onChanged { log.magnifies.append($0) }
                                            .onEnded { log.magnifyEnds.append($0) })])
    var arena = try #require(GestureArena(target: target, ancestors: [], mode: .pinch))
    run(arena.magnify(mag(0, .began)), log)
    run(arena.magnify(mag(0.1, .changed)), log)
    run(arena.magnify(mag(0, .ended)), log)
    #expect(log.magnifies.isEmpty && log.magnifyEnds.isEmpty)
    #expect(!arena.isAlive)
}

/// **2.15** (probe `Q1`, `CI-C` item 2). `rotation` is cumulative from the
/// seam's clockwise-positive deltas: 10, 10 → 10°, 20°. Mutation: subtract.
@MainActor
@Test func rotationIsCumulativeFromTheSeamsClockwiseDeltas() throws {
    let log = ALog()
    let target = region(rootID, [normal(RotateGesture()
                                            .onChanged { log.rotations.append($0) }
                                            .onEnded { log.rotationEnds.append($0) })])
    var arena = try #require(GestureArena(target: target, ancestors: [], mode: .pinch))
    run(arena.rotate(rot(0, .began)), log)
    run(arena.rotate(rot(10, .changed)), log)
    run(arena.rotate(rot(10, .changed)), log)
    run(arena.rotate(rot(0, .ended)), log)
    #expect(close(log.rotations.map(\.rotation.degrees), [10, 20]), "\(log.rotations.map(\.rotation.degrees))")
    #expect(close(log.rotationEnds.map(\.rotation.degrees), [20]))
}

/// **2.16** (probe `M1`, `CI-C` item 3). `startLocation` and `startAnchor` are
/// the first event's local point and its fraction of the hit region: region
/// 100 × 100 at (40, 30), began at (60, 50) → (20, 20), (0.2, 0.2); a later
/// event elsewhere does not move them. Mutation: recompute per event.
@MainActor
@Test func startLocationAndAnchorAreTheFirstEventsLocalPoint() throws {
    let log = ALog()
    let target = region(rootID, [normal(MagnifyGesture().onChanged { log.magnifies.append($0) }),
                                 normal(RotateGesture().onChanged { log.rotations.append($0) })])
    var arena = try #require(GestureArena(target: target, ancestors: [], mode: .pinch))
    run(arena.magnify(mag(0, .began, at: pt(60, 50))), log)
    run(arena.magnify(mag(0.1, .changed, at: pt(90, 90))), log)
    run(arena.rotate(rot(0, .began, at: pt(60, 50))), log)
    run(arena.rotate(rot(10, .changed, at: pt(90, 90))), log)
    try #require(log.magnifies.count == 1 && log.rotations.count == 1)
    #expect(log.magnifies[0].startLocation == pt(20, 20))
    #expect(log.magnifies[0].startAnchor == UnitPoint(x: 0.2, y: 0.2))
    #expect(log.rotations[0].startLocation == pt(20, 20))
    #expect(log.rotations[0].startAnchor == UnitPoint(x: 0.2, y: 0.2))
}

// MARK: - 2.17–2.20: the pinch arena's order

/// **2.17** (`CI-D` item 3). A magnify and a rotate never block each other: an
/// inner `MagnifyGesture` (ahead, innermost first) that is live and then
/// ended does not hold off or cancel an outer `RotateGesture`. Mutation: let
/// any live leaf ahead block → the outer rotate never reports.
@MainActor
@Test func aMagnifyAndARotateOnNestedElementsDoNotBlockEachOther() throws {
    let log = ALog()
    let inner = region(childID, [normal(MagnifyGesture().onChanged { _ in log.entries.append("magnify") })])
    let outer = region(rootID, x: 0, y: 0, w: 300, h: 300,
                       [normal(RotateGesture().onChanged { log.entries.append("rotate \(Int($0.rotation.degrees))") })])
    var arena = try #require(GestureArena(target: inner, ancestors: [(outer, 1)], mode: .pinch))
    run(arena.magnify(mag(0, .began)), log)
    run(arena.magnify(mag(0.1, .changed)), log)
    run(arena.rotate(rot(0, .began)), log)
    run(arena.rotate(rot(10, .changed)), log)
    #expect(log.entries == ["magnify", "rotate 10"], "\(log.entries)")
    run(arena.magnify(mag(0, .ended)), log)
    run(arena.rotate(rot(10, .changed)), log)
    #expect(log.entries == ["magnify", "rotate 10", "rotate 20"], "an ended magnify cancels no rotate: \(log.entries)")
    #expect(arena.isAlive, "the rotate has not ended")
}

/// **2.18** (`CI-D` item 3, `IX-D` item 3). Among magnifies the exclusive
/// order holds: the innermost wins; an outer high-priority one wins instead.
/// Mutation: outermost first for normal members.
@MainActor
@Test func theInnermostMagnifyWinsUnlessAnOuterOneIsHighPriority() throws {
    let log = ALog()
    func pinch(outer priority: (MagnifyGesture) -> GestureAttachment) throws {
        let inner = region(childID, [normal(MagnifyGesture().onChanged { _ in log.entries.append("inner") })])
        let outer = region(rootID, x: 0, y: 0, w: 300, h: 300,
                           [priority(MagnifyGesture().onChanged { _ in log.entries.append("outer") })])
        var arena = try #require(GestureArena(target: inner, ancestors: [(outer, 1)], mode: .pinch))
        run(arena.magnify(mag(0, .began)), log)
        run(arena.magnify(mag(0.1, .changed)), log)
        run(arena.magnify(mag(0.1, .changed)), log)
        run(arena.magnify(mag(0, .ended)), log)
    }
    try pinch(outer: { normal($0) })
    #expect(log.entries == ["inner", "inner"], "\(log.entries)")
    log.entries = []
    try pinch(outer: { high($0) })
    #expect(log.entries == ["outer", "outer"], "\(log.entries)")
}

/// **2.19** (`CI-D` item 3, `IX-D` item 4). A simultaneous composition reports
/// both members: a magnify with a rotate, and — the arm that separates
/// "simultaneous" from "exclusive" — a magnify with another magnify.
/// Mutation: treat `.simultaneous` as exclusive in pinch mode.
@MainActor
@Test func aSimultaneousMagnifyAndRotateCompositionReportsBoth() throws {
    let log = ALog()
    let target = region(rootID, [
        normal(MagnifyGesture().onChanged { _ in log.entries.append("m") }
            .simultaneously(with: RotateGesture().onChanged { _ in log.entries.append("r") })),
    ])
    var arena = try #require(GestureArena(target: target, ancestors: [], mode: .pinch))
    run(arena.magnify(mag(0, .began)), log)
    run(arena.magnify(mag(0.1, .changed)), log)
    run(arena.rotate(rot(0, .began)), log)
    run(arena.rotate(rot(10, .changed)), log)
    #expect(log.entries == ["m", "r"], "\(log.entries)")

    log.entries = []
    let twice = region(rootID, [
        normal(MagnifyGesture().onChanged { _ in log.entries.append("a") }
            .simultaneously(with: MagnifyGesture().onChanged { _ in log.entries.append("b") })),
    ])
    var both = try #require(GestureArena(target: twice, ancestors: [], mode: .pinch))
    run(both.magnify(mag(0, .began)), log)
    run(both.magnify(mag(0.1, .changed)), log)
    #expect(Set(log.entries) == ["a", "b"] && log.entries.count == 2, "\(log.entries)")
}

/// **2.20** (`CI-D` item 1). A pinch arena runs no tap, drag, long press or
/// click: they are failed at formation (a press and a release handing a click
/// reach none of them); a target with no pinch leaf forms no pinch arena.
/// Mutation: keep the click member in pinch mode.
@MainActor
@Test func aPinchArenaRunsNoTapDragOrClick() throws {
    let log = ALog()
    let target = region(rootID, [
        normal(TapGesture().onEnded { log.entries.append("tap") }),
        normal(DragGesture(minimumDistance: 0).onChanged { _ in log.entries.append("drag") }),
        normal(DragGesture(minimumDistance: 0, button: .secondary).onChanged { _ in log.entries.append("secondary") }),
        normal(LongPressGesture(minimumDuration: 0).onEnded { _ in log.entries.append("long") }),
        normal(MagnifyGesture().onChanged { _ in log.entries.append("magnify") }),
    ], onClick: { log.entries.append("click") })
    #expect(GestureArena(target: region(rootID, [normal(TapGesture())], onClick: {}), ancestors: [],
                         mode: .pinch) == nil, "no pinch leaf, no pinch arena")
    var arena = try #require(GestureArena(target: target, ancestors: [], mode: .pinch))
    run(arena.magnify(mag(0, .began)), log)
    run(arena.press(at: pt(50, 60), clickCount: 1, continuing: false), log)
    run(arena.move(to: pt(51, 60)), log)
    run(arena.release(at: pt(51, 60), clickCount: 1, click: ({ log.entries.append("click") }, [])), log)
    run(arena.tick(100), log)
    run(arena.magnify(mag(0.1, .changed)), log)
    #expect(log.entries == ["magnify"], "\(log.entries)")
}
