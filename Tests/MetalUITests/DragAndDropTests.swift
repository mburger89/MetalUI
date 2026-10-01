import Testing
import Foundation
import Metal
import MetalUICore
import MetalUIPlatform
@testable import MetalUI

// Drag and drop, lane 1, tests 1.5–1.19 and 1.22–1.29 (rulings `DN-C`…`DN-I`,
// `DN-K`, `DN-O`, `DN-P`, `DN-S`, `DN-U`; spec
// `docs/superpowers/specs/2026-10-01-drag-and-drop-design.md` §6.2). Every
// SwiftUI answer is an arm of `docs/probes/swiftui-drag-and-drop.swift`
// (named per test); the rest is MetalUI's own, ruled.
//
// Everything runs through a real `Window` on a `FakePlatformWindow` resized to
// 400 × 200, with the display link driven by `simulateTick(timestamp:)` —
// nothing sleeps. The fixture is the probe's `pair`: a 200 × 200 source at the
// left, (0, 0)–(200, 200), and a 200 × 200 destination at the right,
// (200, 0)–(400, 200), side by side in a `Row` (spacing 0, `CN-A`) whose
// 400 × 200 answer fills the window from its origin (`CN-J`). Every test
// `#require`s its geometry from the window's own hitboxes first.

// MARK: - Fixtures

@MainActor
private final class DLog {
    var entries: [String] = []
}

private func px(_ v: Float) -> Pixels { Pixels(v) }
private func pt(_ x: Float, _ y: Float) -> Point<Pixels> { Point(x: px(x), y: px(y)) }
private func rect(_ x: Float, _ y: Float, _ w: Float, _ h: Float) -> Bounds<Pixels> {
    Bounds(origin: pt(x, y), size: Size(width: px(w), height: px(h)))
}
private func down(_ x: Float, _ y: Float, count: Int = 1) -> InputEvent {
    .mouseDown(MouseEvent(position: pt(x, y), clickCount: count))
}
private func up(_ x: Float, _ y: Float, count: Int = 1) -> InputEvent {
    .mouseUp(MouseEvent(position: pt(x, y), clickCount: count))
}
private func drag(_ x: Float, _ y: Float) -> InputEvent {
    .mouseDragged(MouseEvent(position: pt(x, y)))
}
private func escape() -> InputEvent {
    .keyDown(KeyEvent(charactersIgnoringModifiers: "\u{1b}", characters: "\u{1b}", timestamp: 0))
}
private func centre(_ b: Bounds<Pixels>) -> Point<Pixels> {
    Point(x: px(b.origin.x.value + b.size.width.value / 2), y: px(b.origin.y.value + b.size.height.value / 2))
}

private let stamp = 10.0
private let left = rect(0, 0, 200, 200)
private let right = rect(200, 0, 200, 200)

/// A 400 × 200 window over `content`, one frame drawn. **A `Window` is held
/// only weakly by its platform window** (`onInput` captures `[weak self]`), so a
/// caller that keeps only the fake extends the window's lifetime to its scope
/// (`defer { withExtendedLifetime(…) }`) — else every event is answered
/// `false` by nobody. Never in a global: a live dirty window is what
/// `withAnimation` asks about (`Window.redrawRequestCount`), so a leaked one
/// changes other tests' answers (measured: `aDisablingTransactionReachesExactlyOneBuildAndRollsBack`).
@MainActor
private func dndWindow<Root: Element>(_ content: @escaping @MainActor () -> Root) throws
    -> (Window, FakePlatformWindow) {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let (window, platform) = try makeFakeWindow(device: device, size: 400, startsDisplayLink: true,
                                                content: content)
    platform.simulateResize(to: Size(width: px(400), height: px(200)))
    window.drawFrameIfNeeded()
    return (window, platform)
}

/// A 200 × 200 box.
@MainActor
private func square() -> ModifiedElement<Box<EmptyGroup>> {
    Box().frame(width: px(200), height: px(200))
}

/// The probe's `pair`'s destination: a 200 × 200 `String` destination logging
/// `T=<bool>` and `drop(<items>)` into `log`.
@MainActor
private func stringWell(_ log: DLog, name: String = "") -> ModifiedElement<Box<EmptyGroup>> {
    square().dropDestination(for: String.self, action: { items, _ in
        log.entries.append("\(name)drop(\(items))"); return true
    }, isTargeted: { log.entries.append("\(name)T=\($0)") })
}

/// The non-opaque regions carrying a drop destination (an opaque hitbox of the
/// same element carries its whole `Handlers`, the destination included, and is
/// not one).
@MainActor
private func destinationRegions(_ window: Window) -> [Hitbox] {
    window.lastHitboxes.filter { !$0.opaque && $0.handlers.dropDestination != nil }
}

/// The non-opaque hitboxes carrying a draggable.
@MainActor
private func draggableRegions(_ window: Window) -> [Hitbox] {
    window.lastHitboxes.filter { !$0.opaque && $0.handlers.gestures.contains { $0.isDraggable } }
}

/// Requires the fixture's two regions: a draggable at the left and a
/// destination at the right.
@MainActor
private func requirePair(_ window: Window, sourceOpaque: Bool = false,
                         sourceLocation: SourceLocation = #_sourceLocation) throws {
    try #require(destinationRegions(window).map(\.bounds) == [right],
                 "the destination region: \(destinationRegions(window).map(\.bounds))",
                 sourceLocation: sourceLocation)
    if !sourceOpaque {
        try #require(draggableRegions(window).map(\.bounds) == [left],
                     "the draggable region: \(draggableRegions(window).map(\.bounds))",
                     sourceLocation: sourceLocation)
    }
}

/// Presses at `from`, drags through `path` and releases at its last point.
@MainActor
private func dragAndDrop(_ platform: FakePlatformWindow, from: Point<Pixels>, through path: [Point<Pixels>]) {
    platform.simulateInput(.mouseDown(MouseEvent(position: from)))
    for p in path { platform.simulateInput(.mouseDragged(MouseEvent(position: p))) }
    platform.simulateInput(.mouseUp(MouseEvent(position: path.last ?? from)))
}

// MARK: - 1.5–1.6: when a drag begins

/// **1.5** (`P0`, `P17`). A press on a draggable and a 1-pt move open a
/// session; moving over a destination targets it; the release untargets it,
/// then drops — `T=true, T=false, drop`.
/// Mutation **M1e** (the draggable leaf waits for `tapSlop`).
@MainActor
@Test func aDraggableBeginsOnTheFirstMoveAndDropsOnADestination() throws {
    let log = DLog()
    let (window, platform) = try dndWindow { Row { square().draggable("s"); stringWell(log) } }
    try requirePair(window)
    platform.simulateInput(down(100, 100))
    #expect(window.dragSession == nil, "a press alone begins nothing")
    platform.simulateInput(drag(101, 100))
    #expect(window.dragSession != nil, "P17: a 1-pt move begins the session")
    #expect(log.entries == [], "nothing is targeted over the source")
    platform.simulateInput(drag(300, 100))
    #expect(log.entries == ["T=true"], "P0: entering the destination targets it")
    let claimed = platform.simulateInput(up(300, 100))
    #expect(claimed, "a release ending a session is claimed")
    #expect(log.entries == ["T=true", "T=false", "drop([\"s\"])"], "P0, R1b: false before the action")
    #expect(window.dragSession == nil, "the drop ends the session")
}

/// **1.6** (`P17z`, `P1a`). A dragged event at the press point is no move: the
/// tap runs at the release and no session opens.
/// Mutation **M1f** (begin on any dragged event, `>= 0`).
@MainActor
@Test func aZeroDistanceDragIsAClickNotADrag() throws {
    let log = DLog()
    let (window, platform) = try dndWindow {
        Row { square().draggable("s").onTapGesture { log.entries.append("tap") }; stringWell(log) }
    }
    try requirePair(window, sourceOpaque: true)
    platform.simulateInput(down(100, 100))
    platform.simulateInput(drag(100, 100))
    #expect(window.dragSession == nil, "P17z: a zero-distance dragged event is no drag")
    platform.simulateInput(up(100, 100))
    #expect(log.entries == ["tap"], "P1a: the tap runs")
}

// MARK: - 1.7–1.9: precedence (`DN-D`)

/// **1.7** (`P1`, `P2f`, `P3`, `P21`, `P22a`–`c`; `DN-U` items 1 and 5). A
/// draggable outranks a tap, a click and an undecided long press on its own
/// element and on its children: each drag drops and runs none of them, and
/// each click (no move) still runs the tap or click. A long press that has
/// already ENDED holds the drag off (`DN-U` item 1, MetalUI's choice).
/// Mutations **M1g** (delete the `isBlocked` exception) and **M1g′** (let a
/// draggable pass an ended member — reddens the sixth arm).
@MainActor
@Test func aDraggableBeatsATapAClickAndALongPressOnItsElementAndItsChildren() throws {
    // Each arm: the source and the point a press on it should land at.
    struct Arm {
        let name: String
        let clickRuns: String?
        let source: @MainActor (DLog) -> AnyElement
        let press: @MainActor (Window) -> Point<Pixels>
    }
    let opaqueCentre: @MainActor (Window) -> Point<Pixels> = { window in
        centre(window.lastHitboxes.last { $0.opaque && $0.bounds.origin.x.value < 200 }?.bounds ?? left)
    }
    let arms: [Arm] = [
        Arm(name: "draggable then tap", clickRuns: "tap",
            source: { log in AnyElement(square().draggable("s").onTapGesture { log.entries.append("tap") }) },
            press: { _ in pt(100, 100) }),
        Arm(name: "tap then draggable", clickRuns: "tap",
            source: { log in AnyElement(square().onTapGesture { log.entries.append("tap") }.draggable("s")) },
            press: { _ in pt(100, 100) }),
        Arm(name: "a Button's own draggable", clickRuns: "click",
            source: { log in
                AnyElement(Box { Button("B") { log.entries.append("click") }.draggable("s") }
                    .frame(width: px(200), height: px(200)))
            },
            press: opaqueCentre),
        Arm(name: "a draggable parent over a Button", clickRuns: "click",
            source: { log in
                AnyElement(Box { Button("B") { log.entries.append("click") } }
                    .frame(width: px(200), height: px(200)).draggable("s"))
            },
            press: opaqueCentre),
        Arm(name: "a draggable parent over a tapped child", clickRuns: "tap",
            source: { log in
                AnyElement(Column { Box().frame(width: px(100), height: px(100))
                        .onTapGesture { log.entries.append("tap") } }
                    .frame(width: px(200), height: px(200), alignment: .topLeading).draggable("s"))
            },
            press: { _ in pt(50, 50) }),
        Arm(name: "an undecided long press", clickRuns: nil,
            source: { log in
                AnyElement(square().onLongPressGesture(minimumDuration: 0.5) { log.entries.append("long") }
                    .draggable("s"))
            },
            press: { _ in pt(100, 100) }),
    ]
    for arm in arms {
        let log = DLog()
        let (window, platform) = try dndWindow { Row { arm.source(log); stringWell(log) } }
        try #require(destinationRegions(window).map(\.bounds) == [right], "\(arm.name): the destination")
        let p = arm.press(window)
        dragAndDrop(platform, from: p, through: [pt(p.x.value + 10, p.y.value), pt(300, 100)])
        #expect(log.entries == ["T=true", "T=false", "drop([\"s\"])"], "\(arm.name): the drag drops and runs nothing else")
        log.entries = []
        if let clickRuns = arm.clickRuns {
            platform.simulateTick(timestamp: stamp)
            platform.simulateInput(.mouseDown(MouseEvent(position: p)))
            platform.simulateInput(.mouseUp(MouseEvent(position: p)))
            platform.simulateTick(timestamp: stamp + 1)
            #expect(log.entries == [clickRuns], "\(arm.name): a click with no move runs the \(clickRuns)")
        }
    }

    // Sixth arm (`DN-U` item 1): a long press held past its duration has
    // ended before the move, and an ended member ahead holds the drag off.
    do {
        let log = DLog()
        let (keptWindow, platform) = try dndWindow {
            Row {
                square().onLongPressGesture(minimumDuration: 0.3) { log.entries.append("long") }.draggable("s")
                stringWell(log)
            }
        }
        defer { withExtendedLifetime(keptWindow) {} }   // a Window is held only weakly by its platform
        platform.simulateInput(down(100, 100))
        platform.simulateTick(timestamp: stamp)
        platform.simulateTick(timestamp: stamp + 0.35)
        #expect(log.entries == ["long"], "the long press ends while held")
        platform.simulateInput(drag(110, 100))
        platform.simulateInput(drag(300, 100))
        platform.simulateInput(up(300, 100))
        #expect(log.entries == ["long"], "DN-U item 1: the move after it begins no drag")
    }

    // Seventh arm (`P21`, `DN-U` item 5): a double tap beside a draggable — a
    // double click runs the double tap, a drag drops.
    do {
        let log = DLog()
        let (window, platform) = try dndWindow {
            Row { square().draggable("s").onTapGesture(count: 2) { log.entries.append("double") }; stringWell(log) }
        }
        try requirePair(window, sourceOpaque: true)
        dragAndDrop(platform, from: pt(100, 100), through: [pt(110, 100), pt(300, 100)])
        #expect(log.entries == ["T=true", "T=false", "drop([\"s\"])"], "P21: a drag drops")
        log.entries = []
        platform.simulateTick(timestamp: stamp)
        platform.simulateInput(down(100, 100, count: 1))
        platform.simulateInput(up(100, 100, count: 1))
        platform.simulateInput(down(100, 100, count: 2))
        platform.simulateInput(up(100, 100, count: 2))
        #expect(log.entries == ["double"], "P21: a double click runs the double tap")
    }

    // Eighth arm (`DN-V` item 6, pinned by `DN-W` item 2): the other order —
    // the draggable written BEFORE the long press, so inner and ahead. The
    // undecided draggable holds the long press off past its duration; the
    // draggable fails at the release, and the long press ends there.
    do {
        let log = DLog()
        let (keptWindow, platform) = try dndWindow {
            Row {
                square().draggable("s").onLongPressGesture(minimumDuration: 0.3) { log.entries.append("long") }
                stringWell(log)
            }
        }
        defer { withExtendedLifetime(keptWindow) {} }   // a Window is held only weakly by its platform
        platform.simulateInput(down(100, 100))
        platform.simulateTick(timestamp: stamp)
        platform.simulateTick(timestamp: stamp + 0.35)
        platform.simulateTick(timestamp: stamp + 1)
        #expect(log.entries == [], "DN-V item 6: held past its duration, the long press waits on the draggable")
        platform.simulateInput(up(100, 100))
        platform.simulateTick(timestamp: stamp + 1.1)
        #expect(log.entries == ["long"], "DN-V item 6: the long press ends at the release")
    }
}

/// **1.8** (`P2a`–`d`, `P22d`). A `DragGesture` that outranks the draggable —
/// declared before it (inner), on a child, or high priority — wins: it changes
/// and ends, and nothing drops. An outer normal one, or a parent's, loses.
/// Mutation **M1h** (the draggable at `.high` priority).
@MainActor
@Test func aDragGestureThatOutranksADraggableWinsAndAnOuterOneLoses() throws {
    func gesture(_ log: DLog) -> DragGesture {
        DragGesture().onChanged { _ in
            if log.entries.last != "chg" { log.entries.append("chg") }
        }.onEnded { _ in log.entries.append("end") }
    }
    let winners: [(String, @MainActor (DLog) -> AnyElement)] = [
        ("inner (declared before)", { log in AnyElement(square().gesture(gesture(log)).draggable("s")) }),
        ("a child's", { log in
            AnyElement(Column { Box().frame(width: px(200), height: px(200)).gesture(gesture(log)) }
                .frame(width: px(200), height: px(200)).draggable("s"))
        }),
        ("high priority", { log in AnyElement(square().draggable("s").highPriorityGesture(gesture(log))) }),
    ]
    for (name, source) in winners {
        let log = DLog()
        let (keptWindow, platform) = try dndWindow { Row { source(log); stringWell(log) } }
        defer { withExtendedLifetime(keptWindow) {} }   // a Window is held only weakly by its platform
        dragAndDrop(platform, from: pt(100, 100), through: [pt(120, 100), pt(300, 100)])
        #expect(log.entries == ["chg", "end"], "\(name): the drag gesture wins, nothing drops")
    }
    let losers: [(String, @MainActor (DLog) -> AnyElement)] = [
        ("outer normal", { log in AnyElement(square().draggable("s").gesture(gesture(log))) }),
        ("a parent's", { log in
            AnyElement(Column { Box().frame(width: px(200), height: px(200)).draggable("s") }
                .frame(width: px(200), height: px(200)).gesture(gesture(log)))
        }),
    ]
    for (name, source) in losers {
        let log = DLog()
        let (keptWindow, platform) = try dndWindow { Row { source(log); stringWell(log) } }
        defer { withExtendedLifetime(keptWindow) {} }   // a Window is held only weakly by its platform
        dragAndDrop(platform, from: pt(100, 100), through: [pt(120, 100), pt(300, 100)])
        #expect(log.entries == ["T=true", "T=false", "drop([\"s\"])"], "\(name): the draggable wins")
    }
}

/// **1.9** (`P2e`). A simultaneous `DragGesture` changes for the move that
/// begins the drag, then stops with no end; the drop follows.
/// Mutation **M1i** (simultaneous members keep receiving after the drag begins).
@MainActor
@Test func aSimultaneousDragGestureChangesForTheStartingMoveAndNeverEnds() throws {
    let log = DLog()
    let (keptWindow, platform) = try dndWindow {
        Row {
            square().simultaneousGesture(DragGesture(minimumDistance: 1)
                .onChanged { _ in log.entries.append("chg") }
                .onEnded { _ in log.entries.append("end") }).draggable("s")
            stringWell(log)
        }
    }
    defer { withExtendedLifetime(keptWindow) {} }   // a Window is held only weakly by its platform
    dragAndDrop(platform, from: pt(100, 100), through: [pt(105, 100), pt(150, 100), pt(300, 100)])
    #expect(log.entries == ["chg", "T=true", "T=false", "drop([\"s\"])"], "P2e: one change, the drop, no end")
}

// MARK: - 1.10–1.11: what a drag leaves alone

private struct RowItem: Identifiable, Hashable { let id: Int }

/// **1.10** (`P4a`, `P4b`). A selectable `List` row whose content is
/// draggable: a click selects; a drag from another row drops and selects
/// nothing — the draggable adds no opaque target (`DN-E` item 1), and the
/// drag's begin abandons the row's click (`DN-D` item 7).
/// Mutation **M1j** (count a draggable in `isPointerTarget`, opaque).
@MainActor
@Test func aDraggableRowsClickStillSelectsAndItsDragDoesNot() throws {
    final class Model { var selection: Int? }
    let model = Model()
    let log = DLog()
    let items = (0..<5).map(RowItem.init)
    let (window, platform) = try dndWindow {
        Row {
            Column {
                List(items, selection: Binding(get: { model.selection }, set: { model.selection = $0 }),
                     rowHeight: px(20)) { item in
                    Text("Row \(item.id)").draggable("row\(item.id)")
                }
            }.frame(width: px(200), height: px(200), alignment: .topLeading)
            stringWell(log)
        }
    }
    window.setNeedsRedraw()
    window.drawFrameIfNeeded()
    let texts = draggableRegions(window).sorted { $0.bounds.origin.y.value < $1.bounds.origin.y.value }
    try #require(texts.count == 5, "one draggable region per row's text: \(texts.map(\.bounds))")
    let row1 = centre(texts[1].bounds), row2 = centre(texts[2].bounds)
    platform.simulateInput(.mouseDown(MouseEvent(position: row1)))
    platform.simulateInput(.mouseUp(MouseEvent(position: row1)))
    #expect(model.selection == 1, "P4a: a click on a draggable row's content selects it")
    window.drawFrameIfNeeded()
    dragAndDrop(platform, from: row2, through: [pt(row2.x.value + 10, row2.y.value), pt(300, 100)])
    #expect(log.entries == ["T=true", "T=false", "drop([\"row2\"])"], "P4b: the row drags")
    #expect(model.selection == 1, "P4b: and the drag selects nothing")
}

/// **1.11** (`P20`, `P20b`, `DN-D` item 6). A draggable `TextField`'s drag
/// selects text and a draggable `Slider`'s writes values; neither begins a
/// session — both run ahead of the arena in `Window.onInput`.
/// Mutation **M1k** (run the arena ahead of `dispatchTextInput`).
@MainActor
@Test func aTextFieldAndASliderKeepTheirPressUnderADraggable() throws {
    do {
        let log = DLog()
        let (window, platform) = try dndWindow {
            Row {
                TextField("p", text: "hello world", onChange: { _ in }).draggable("s")
                    .frame(width: px(200), height: px(200))
                stringWell(log)
            }
        }
        let field = try #require(window.lastHitboxes.first { $0.handlers.textInput != nil }, "the field's hitbox")
        let start = Point(x: px(field.bounds.origin.x.value + 2), y: centre(field.bounds).y)
        dragAndDrop(platform, from: start, through: [pt(start.x.value + 40, start.y.value), pt(300, 100)])
        #expect(window.dragSession == nil && log.entries == [], "P20: a draggable field never drags")
        let state = try #require(window.stateTable.peek(field.id, as: TextEditState.self), "the field's edit state")
        #expect(state.anchor != state.head, "P20: the drag selected text")
    }
    do {
        final class Value { var v = 0.0; var writes = 0 }
        let value = Value()
        let log = DLog()
        let (window, platform) = try dndWindow {
            Row {
                Slider(value: Binding(get: { value.v }, set: { value.v = $0; value.writes += 1 }))
                    .draggable("s").frame(width: px(200), height: px(200))
                stringWell(log)
            }
        }
        let track = try #require(window.lastHitboxes.first { $0.handlers.valueTrack != nil }, "the slider's track")
        let start = centre(track.bounds)
        dragAndDrop(platform, from: start, through: [pt(start.x.value + 20, start.y.value), pt(300, 100)])
        #expect(window.dragSession == nil && log.entries == [], "P20b: a draggable slider never drags")
        #expect(value.writes >= 2, "P20b: the press and the drag write values")
    }
}

// MARK: - 1.12–1.15: the target (`DN-F`, `DN-H`)

/// **1.12** (`P13a`, `P13b`, `P15a`–`d`). The deepest destination takes the
/// drop, the outer turning `false` as the pointer enters the inner; a plain
/// box, an `onClick` box and a `Button` covering a destination do not block it.
/// Mutation **M1l** (resolve with `topmostOpaqueHitbox`).
@MainActor
@Test func theDeepestDestinationTakesTheDropAndCoversDoNotBlockIt() throws {
    do {
        let log = DLog()
        let (window, platform) = try dndWindow {
            Row {
                square().draggable("s")
                Column {
                    Box().frame(width: px(100), height: px(100)).dropDestination(for: String.self, action: { items, _ in
                        log.entries.append("inner(\(items))"); return true
                    }, isTargeted: { log.entries.append("iT=\($0)") })
                }
                .frame(width: px(200), height: px(200), alignment: .topLeading)
                .dropDestination(for: String.self, action: { items, _ in
                    log.entries.append("outer(\(items))"); return true
                }, isTargeted: { log.entries.append("oT=\($0)") })
            }
        }
        try #require(Set(destinationRegions(window).map { "\($0.bounds)" })
                        == Set([right, rect(200, 0, 100, 100)].map { "\($0)" }), "the two destinations")
        dragAndDrop(platform, from: pt(100, 100), through: [pt(110, 100), pt(350, 150), pt(250, 50)])
        #expect(log.entries == ["oT=true", "oT=false", "iT=true", "iT=false", "inner([\"s\"])"],
                "P13a: the inner takes the drop; the outer un-targets on entry")
        log.entries = []
        dragAndDrop(platform, from: pt(100, 100), through: [pt(110, 100), pt(350, 150)])
        #expect(log.entries == ["oT=true", "oT=false", "outer([\"s\"])"], "P13b: outside the inner, the outer")
    }
    let covers: [(String, @MainActor (DLog) -> AnyElement)] = [
        ("a plain box", { _ in AnyElement(square().background(.accent)) }),
        ("an onClick box", { log in AnyElement(square().onClick { log.entries.append("click") }) }),
        ("a Button", { log in AnyElement(Box { Button("B") { log.entries.append("click") } }
                                            .frame(width: px(200), height: px(200))) }),
    ]
    for (name, cover) in covers {
        let log = DLog()
        let (keptWindow, platform) = try dndWindow { Row { square().draggable("s"); Stack { stringWell(log); cover(log) } } }
        defer { withExtendedLifetime(keptWindow) {} }   // a Window is held only weakly by its platform
        dragAndDrop(platform, from: pt(100, 100), through: [pt(110, 100), pt(300, 100)])
        #expect(log.entries == ["T=true", "T=false", "drop([\"s\"])"], "P15: \(name) over a destination does not block it")
    }
}

/// **1.13** (`P13c`, `P16`; `DN-U` item 2). Over an inner `URL` destination a
/// `String` drag un-targets the outer `String` destination, never targets the
/// inner and drops nowhere; a `URL` dragged onto a `String` destination calls
/// nothing at all.
/// Mutation **M1m** (fall through to the nearest accepting ancestor destination).
@MainActor
@Test func aDestinationThatRefusesTheTypeTargetsNothing() throws {
    do {
        let log = DLog()
        let (keptWindow, platform) = try dndWindow {
            Row {
                square().draggable("s")
                Column {
                    Box().frame(width: px(100), height: px(100)).dropDestination(for: URL.self, action: { _, _ in
                        log.entries.append("inner"); return true
                    }, isTargeted: { log.entries.append("iT=\($0)") })
                }
                .frame(width: px(200), height: px(200), alignment: .topLeading)
                .dropDestination(for: String.self, action: { _, _ in
                    log.entries.append("outer"); return true
                }, isTargeted: { log.entries.append("oT=\($0)") })
            }
        }
        defer { withExtendedLifetime(keptWindow) {} }   // a Window is held only weakly by its platform
        dragAndDrop(platform, from: pt(100, 100), through: [pt(110, 100), pt(350, 150), pt(250, 50)])
        #expect(log.entries == ["oT=true", "oT=false"], "P13c: the refusing inner targets nothing and drops nowhere")
    }
    do {
        let log = DLog()
        let (keptWindow, platform) = try dndWindow {
            Row { square().draggable(URL(string: "https://example.com")!); stringWell(log) }
        }
        defer { withExtendedLifetime(keptWindow) {} }   // a Window is held only weakly by its platform
        dragAndDrop(platform, from: pt(100, 100), through: [pt(110, 100), pt(300, 100)])
        #expect(log.entries == [], "P16: a URL never targets a String destination")
    }
}

/// **1.14** (`P14`, `P10`, `P19`). `isTargeted(false)` comes before the next
/// destination's `true` and before the action; leaving and re-entering targets
/// again; holding still sends nothing more.
/// Mutation **M1n** (call the new target's `true` before the old one's `false`).
@MainActor
@Test func isTargetedTurnsFalseBeforeTheNextTrueAndBeforeTheAction() throws {
    do {
        let log = DLog()
        let (keptWindow, platform) = try dndWindow {
            Row {
                square().draggable("s")
                Column {
                    Box().frame(width: px(200), height: px(100)).dropDestination(for: String.self, action: { _, _ in
                        log.entries.append("A"); return true
                    }, isTargeted: { log.entries.append("AT=\($0)") })
                    Box().frame(width: px(200), height: px(100)).dropDestination(for: String.self, action: { items, _ in
                        log.entries.append("B(\(items))"); return true
                    }, isTargeted: { log.entries.append("BT=\($0)") })
                }
            }
        }
        defer { withExtendedLifetime(keptWindow) {} }   // a Window is held only weakly by its platform
        dragAndDrop(platform, from: pt(100, 100), through: [pt(110, 100), pt(300, 50), pt(300, 150)])
        #expect(log.entries == ["AT=true", "AT=false", "BT=true", "BT=false", "B([\"s\"])"], "P14")
    }
    do {
        let log = DLog()
        let (keptWindow, platform) = try dndWindow { Row { square().draggable("s"); stringWell(log) } }
        defer { withExtendedLifetime(keptWindow) {} }   // a Window is held only weakly by its platform
        dragAndDrop(platform, from: pt(100, 100),
                    through: [pt(110, 100), pt(300, 100), pt(100, 100), pt(300, 100), pt(300, 100), pt(301, 100)])
        #expect(log.entries == ["T=true", "T=false", "T=true", "T=false", "drop([\"s\"])"],
                "P10: re-entering targets again; P19: holding still adds nothing")
    }
}

/// **1.15** (`P12a`). The action's location is local to the destination:
/// window (330, 140) on a destination at x = 200 reads (130, 140).
/// Mutation **M1o** (pass the window point).
@MainActor
@Test func theDropLocationIsLocalToTheDestination() throws {
    final class Where { var location: Point<Pixels>? }
    let got = Where()
    let (window, platform) = try dndWindow {
        Row {
            square().draggable("s")
            square().dropDestination(for: String.self) { _, location in got.location = location; return true }
        }
    }
    try requirePair(window)
    dragAndDrop(platform, from: pt(100, 100), through: [pt(110, 100), pt(330, 140)])
    #expect(got.location == pt(130, 140), "P12a: \(String(describing: got.location))")
}

// MARK: - 1.16–1.19: refusing and cancelling (`DN-I`, `DN-G`, `DN-F`)

private struct EscapeFixture: Action {}

/// **1.16** (`P7`, `DN-I`). Escape over the destination cancels: `T=true,
/// T=false`, no drop; the release clicks nothing; a keymap binding for Escape
/// does not run — the session claims it first.
/// Mutation **M1p** (let Escape reach the keymap first).
@MainActor
@Test func escapeCancelsADragWithNoDropAndNoClick() throws {
    let log = DLog()
    let (window, platform) = try dndWindow {
        Row {
            square().draggable("s").onClick { log.entries.append("click") }
            stringWell(log)
        }
    }
    window.keymap = Keymap { KeyBinding("escape", EscapeFixture()) }
    window.onAction = { action in
        guard action is EscapeFixture else { return false }
        log.entries.append("keymap"); return true
    }
    platform.simulateInput(down(100, 100))
    platform.simulateInput(drag(110, 100))
    platform.simulateInput(drag(300, 100))
    let claimed = platform.simulateInput(escape())
    #expect(claimed, "the session claims Escape")
    #expect(window.dragSession == nil, "Escape ends the session")
    platform.simulateInput(up(300, 100))
    #expect(log.entries == ["T=true", "T=false"], "P7: no drop, no click, no keymap action")
    platform.simulateInput(escape())
    #expect(log.entries == ["T=true", "T=false", "keymap"], "with no session, the keymap's Escape runs")
}

/// **1.17** (divergence 100, `DN-G`). A disabled source does not drag and a
/// disabled destination is never targeted and takes no drop — SwiftUI's do
/// both (`P9`, `P8`).
/// Mutation **M1q** (register the destination region outside the disabled gate).
@MainActor
@Test func aDisabledSourceDoesNotDragAndADisabledDestinationRefuses() throws {
    do {
        let log = DLog()
        let (window, platform) = try dndWindow { Row { square().draggable("s").disabled(true); stringWell(log) } }
        #expect(draggableRegions(window).isEmpty, "a disabled source registers no draggable region")
        dragAndDrop(platform, from: pt(100, 100), through: [pt(110, 100), pt(300, 100)])
        #expect(window.dragSession == nil && log.entries == [], "a disabled source does not drag")
    }
    do {
        let log = DLog()
        let (window, platform) = try dndWindow { Row { square().draggable("s"); stringWell(log).disabled(true) } }
        #expect(destinationRegions(window).isEmpty, "a disabled destination registers no region")
        dragAndDrop(platform, from: pt(100, 100), through: [pt(110, 100), pt(300, 100)])
        #expect(log.entries == [], "a disabled destination is never targeted and takes no drop")
    }
}

/// **1.18** (`P15e`, `DN-F` item 3). A destination under
/// `allowsHitTesting(false)` still receives — its region is registered outside
/// that gate, as a scroll region is.
/// Mutation **M1r** (register the destination region inside the `allowsHitTesting` gate).
@MainActor
@Test func aDestinationUnderAllowsHitTestingFalseStillReceives() throws {
    let log = DLog()
    let (window, platform) = try dndWindow { Row { square().draggable("s"); stringWell(log).allowsHitTesting(false) } }
    try requirePair(window)
    dragAndDrop(platform, from: pt(100, 100), through: [pt(110, 100), pt(300, 100)])
    #expect(log.entries == ["T=true", "T=false", "drop([\"s\"])"], "P15e")
}

/// **1.19** (`DN-F` item 4, MetalUI's choice). A `Deferred` scrim with an
/// `onClick` over the destination — a presentation, on a higher layer — blocks
/// it; the same scrim on the destination's own layer does not.
/// Mutation **M1s** (drop the layer comparison).
@MainActor
@Test func aPresentationAboveADestinationBlocksADropBeneathIt() throws {
    do {
        let log = DLog()
        let (window, platform) = try dndWindow {
            Row {
                square().draggable("s")
                Stack { stringWell(log); Deferred { square().onClick { log.entries.append("scrim") } } }
            }
        }
        let scrim = try #require(window.lastHitboxes.first { $0.opaque && $0.bounds == right }, "the scrim")
        let well = try #require(destinationRegions(window).first, "the destination")
        try #require(scrim.layer > well.layer, "the scrim is a presentation, above the destination's layer")
        dragAndDrop(platform, from: pt(100, 100), through: [pt(110, 100), pt(300, 100)])
        #expect(log.entries == [], "a presentation blocks the drop beneath it")
    }
    do {
        let log = DLog()
        let (keptWindow, platform) = try dndWindow {
            Row {
                square().draggable("s")
                Stack { stringWell(log); square().onClick { log.entries.append("scrim") } }
            }
        }
        defer { withExtendedLifetime(keptWindow) {} }   // a Window is held only weakly by its platform
        dragAndDrop(platform, from: pt(100, 100), through: [pt(110, 100), pt(300, 100)])
        #expect(log.entries == ["T=true", "T=false", "drop([\"s\"])"], "a cover on the same layer does not")
    }
}

// MARK: - 1.22–1.24: the platform (`DN-K`, `DN-C`, `DN-L`, `DN-M`)

/// **1.22** (`DN-K`). The first move outside the window offers the drag to the
/// platform once, with the payload's representations at that point. When the
/// platform takes it the in-window session ends and the release does nothing;
/// when it refuses the session continues and a release outside cancels.
/// Mutations **M1w** (offer on every outside move) and **M1x** (never offer).
@MainActor
@Test func leavingTheWindowHandsTheDragToThePlatformWhenItCan() throws {
    do {
        let log = DLog()
        let (window, platform) = try dndWindow { Row { square().draggable("s"); stringWell(log) } }
        platform.externalDragResult = true
        platform.simulateInput(down(100, 100))
        platform.simulateInput(drag(110, 100))
        platform.simulateInput(drag(300, 100))
        platform.simulateInput(drag(300, 250))
        try #require(platform.externalDrags.count == 1, "offered once: \(platform.externalDrags.count)")
        let (representations, position) = platform.externalDrags[0]
        #expect(representations == [DragRepresentation(
            type: PasteboardType(identifier: "public.utf8-plain-text",
                                 conformsTo: ["public.data", "public.item", "public.plain-text", "public.text"]),
            bytes: Array("s".utf8))], "the payload's one representation")
        #expect(position == pt(300, 250), "at the first point outside")
        #expect(window.dragSession == nil && window.active == nil, "the platform's session replaces ours")
        #expect(log.entries == ["T=true", "T=false"], "the destination it left is un-targeted")
        platform.simulateInput(drag(300, 260))
        let claimed = platform.simulateInput(up(300, 100))
        #expect(!claimed && log.entries == ["T=true", "T=false"], "the release does nothing")
        #expect(platform.externalDrags.count == 1)
    }
    do {
        let log = DLog()
        let (window, platform) = try dndWindow { Row { square().draggable("s"); stringWell(log) } }
        platform.simulateInput(down(100, 100))
        platform.simulateInput(drag(110, 100))
        platform.simulateInput(drag(100, 250))
        platform.simulateInput(drag(100, 260))
        #expect(platform.externalDrags.count == 1, "a refusing platform is asked once")
        #expect(window.dragSession != nil, "and the drag stays in the window")
        platform.simulateInput(up(100, 260))
        #expect(window.dragSession == nil && log.entries == [], "a release outside cancels")
    }
}

/// A dragged item offered as `types`, counting what is loaded.
@MainActor
private final class LoadLog { var loaded: [String] = [] }

private let png = PasteboardType(identifier: "public.png", conformsTo: ["public.image", "public.data", "public.item"])
private let utf8 = PasteboardType(identifier: "public.utf8-plain-text",
                                  conformsTo: ["public.plain-text", "public.text", "public.data", "public.item"])

@MainActor
private func item(_ types: [PasteboardType], bytes: [String: [UInt8]], log: LoadLog) -> DropItem {
    DropItem(types: types) { identifier in
        log.loaded.append(identifier)
        return bytes[identifier]
    }
}

/// **1.23** (`DN-C`, `DN-L`). An external drop finds the destination by the
/// same resolver: `.entered` over it answers `true` and targets it, `.moved`
/// outside answers `false` and un-targets it, `.performed` over it delivers —
/// loading only the type the destination imports.
/// Mutation **M1y** (load every offered type).
@MainActor
@Test func anExternalDropFindsTheSameDestinationAndLoadsOnlyWhatItImports() throws {
    let log = DLog()
    let loads = LoadLog()
    let (window, platform) = try dndWindow { Row { square(); stringWell(log) } }
    try #require(destinationRegions(window).map(\.bounds) == [right])
    let x = item([png, utf8], bytes: ["public.png": [9, 9], "public.utf8-plain-text": Array("x".utf8)], log: loads)
    #expect(platform.simulateDrop(.entered(position: pt(300, 100), items: [x])), "an accepting destination answers true")
    #expect(log.entries == ["T=true"])
    #expect(!platform.simulateDrop(.moved(position: pt(100, 100))), "outside it, false")
    #expect(log.entries == ["T=true", "T=false"])
    #expect(platform.simulateDrop(.moved(position: pt(300, 100))))
    #expect(platform.simulateDrop(.performed(position: pt(300, 100), items: [x])), "it took the drop")
    #expect(log.entries == ["T=true", "T=false", "T=true", "T=false", "drop([\"x\"])"])
    #expect(loads.loaded == ["public.utf8-plain-text"], "only the imported type is read: \(loads.loaded)")
}

/// **1.23b** (`DN-C`, `DN-H`; the review round's mutations B2 and F2). What
/// `Window` does with an external `.exited` — un-targets, `isTargeted(false)`,
/// no action — and where an external `.performed` delivers: at the
/// destination-local point of its own position, window (330, 140) on a
/// destination at x = 200 reading (130, 140), as 1.15 reads it for the
/// in-window session.
@MainActor
@Test func anExternalExitUnTargetsAndAnExternalDropDeliversItsLocalLocation() throws {
    final class Where { var locations: [Point<Pixels>] = [] }
    let log = DLog()
    let got = Where()
    let loads = LoadLog()
    let (window, platform) = try dndWindow {
        Row {
            square()
            square().dropDestination(for: String.self, action: { items, location in
                got.locations.append(location); log.entries.append("drop(\(items))"); return true
            }, isTargeted: { log.entries.append("T=\($0)") })
        }
    }
    try #require(destinationRegions(window).map(\.bounds) == [right])
    let x = item([utf8], bytes: ["public.utf8-plain-text": Array("x".utf8)], log: loads)
    #expect(platform.simulateDrop(.entered(position: pt(300, 100), items: [x])))
    #expect(!platform.simulateDrop(.exited), "a drag that left answers false")
    #expect(log.entries == ["T=true", "T=false"], "B2: `.exited` un-targets with isTargeted(false)")
    #expect(got.locations.isEmpty, "and runs no action")

    #expect(platform.simulateDrop(.entered(position: pt(250, 60), items: [x])))
    #expect(platform.simulateDrop(.performed(position: pt(330, 140), items: [x])))
    #expect(got.locations == [pt(130, 140)], "F2: the drop is local to the destination: \(got.locations)")
    #expect(log.entries == ["T=true", "T=false", "T=true", "T=false", "drop([\"x\"])"])
}

/// **1.24** (divergence 102's MetalUI half, `DN-M` item 2). With the items
/// unknown until the drop (SDL), the destination is targeted optimistically;
/// at the drop a payload it does not import un-targets it and runs nothing.
/// Mutation **M1z** (treat unknown types as refusing).
@MainActor
@Test func anExternalDropWithUnknownTypesTargetsOptimistically() throws {
    let log = DLog()
    let loads = LoadLog()
    let (keptWindow, platform) = try dndWindow {
        Row {
            square()
            square().dropDestination(for: URL.self, action: { _, _ in log.entries.append("drop"); return true },
                                     isTargeted: { log.entries.append("T=\($0)") })
        }
    }
    defer { withExtendedLifetime(keptWindow) {} }   // a Window is held only weakly by its platform
    #expect(platform.simulateDrop(.entered(position: pt(300, 100), items: nil)), "unknown items: optimistic")
    #expect(log.entries == ["T=true"])
    let text = item([utf8], bytes: ["public.utf8-plain-text": Array("https://example.com".utf8)], log: loads)
    #expect(!platform.simulateDrop(.performed(position: pt(300, 100), items: [text])), "nothing took it")
    #expect(log.entries == ["T=true", "T=false"], "un-targeted, no action")
    #expect(loads.loaded == [], "nothing imports, nothing is read")
}

// MARK: - 1.25–1.29: what must not move (`DN-O`, `DN-P`, `DN-H`, `DN-S`)

/// **1.25** (`DN-O`, `DN-H` item 6). A drag neither focuses its source nor its
/// destination, and adds no `StateTable` entry frame over frame.
/// Mutation **M1aa** (focus the source at drag begin).
@MainActor
@Test func aDragNeitherFocusesNorAddsAStateEntry() throws {
    let log = DLog()
    let (window, platform) = try dndWindow {
        Row { square().draggable("s").focusable(); stringWell(log).focusable() }
    }
    window.setNeedsRedraw()
    window.drawFrameIfNeeded()
    let entries = window.stateTable.count
    try #require(window.focusedElement == nil)
    platform.simulateInput(down(100, 100))
    platform.simulateInput(drag(110, 100))
    window.drawFrameIfNeeded()
    platform.simulateInput(drag(300, 100))
    window.drawFrameIfNeeded()
    #expect(window.stateTable.count == entries, "mid-drag: no entry added")
    platform.simulateInput(up(300, 100))
    window.drawFrameIfNeeded()
    #expect(log.entries == ["T=true", "T=false", "drop([\"s\"])"])
    #expect(window.focusedElement == nil, "no focus moved")
    #expect(window.stateTable.count == entries, "after the drop: no entry added")
}

/// **1.26** (`DN-P`). The `StyledElement` spellings return `Self`, so a `Box`
/// registers its hitbox under the same id with or without them; the proposal
/// spelling wraps once, its content one level below the wrapper.
/// Mutation **M1ab** (wrap `StyledElement` in a modifier element).
@MainActor
@Test func theStyledSpellingsMoveNoIDAndTheProposalOnesWrapOnce() throws {
    let (plain, _) = try dndWindow { square().onClick {} }
    let (dressed, _) = try dndWindow {
        square().onClick {}.draggable("s").dropDestination(for: String.self) { _, _ in true }
    }
    let plainID = try #require(plain.lastHitboxes.first { $0.opaque }?.id)
    let dressedID = try #require(dressed.lastHitboxes.first { $0.opaque }?.id)
    #expect(plainID == dressedID, "the draggable box's hitbox keeps its id")
    #expect(destinationRegions(dressed).map(\.id) == [plainID], "the destination region rides the same id")

    let (proposal, _) = try dndWindow { Rectangle().onTapGesture {}.draggable("s") }
    let tap = try #require(proposal.lastHitboxes.first { $0.opaque }, "the tap wrapper's hitbox")
    let wrapper = try #require(draggableRegions(proposal).first, "the draggable wrapper's region")
    #expect(tap.id.parent == wrapper.id, "the proposal spelling wraps once: content one level below")
}

/// **1.27** (`DN-H` item 4). A source that vanishes mid-drag still delivers:
/// the payload was exported when the drag began.
/// Mutation **M1ac** (end the session when the source is not produced).
@MainActor
@Test func aSourceThatVanishesMidDragStillDelivers() throws {
    final class Model { var showsSource = true }
    let model = Model()
    let log = DLog()
    let (window, platform) = try dndWindow {
        Row {
            if model.showsSource { square().draggable("s") } else { square() }
            stringWell(log)
        }
    }
    platform.simulateInput(down(100, 100))
    platform.simulateInput(drag(110, 100))
    model.showsSource = false
    window.setNeedsRedraw()
    window.drawFrameIfNeeded()
    try #require(draggableRegions(window).isEmpty, "the source is gone")
    platform.simulateInput(drag(300, 100))
    window.drawFrameIfNeeded()
    platform.simulateInput(up(300, 100))
    #expect(log.entries == ["T=true", "T=false", "drop([\"s\"])"], "the vanished source still delivers")
}

/// **1.28** (`DN-E`, `DN-F`; work counted, not timed). A tree with no draggable
/// or destination registers exactly what it did; a destination adds one
/// non-opaque hitbox; a draggable with no other pointer ask adds one; a
/// draggable on a click target adds none (it rides the opaque hitbox).
/// Mutation **M1ad** (register the destination region for every element).
@MainActor
@Test func aFrameWithoutADragOrDestinationAddsNoHitbox() throws {
    let (base, _) = try dndWindow { Row { square().onClick {}; square() } }
    #expect(base.lastHitboxes.count == 1, "the baseline: one click target")
    let (withDestination, _) = try dndWindow {
        Row { square().onClick {}; square().dropDestination(for: String.self) { _, _ in true } }
    }
    #expect(withDestination.lastHitboxes.count == 2)
    #expect(withDestination.lastHitboxes.filter { !$0.opaque }.count == 1, "one non-opaque destination region")
    let (withDraggable, _) = try dndWindow { Row { square().onClick {}; square().draggable("s") } }
    #expect(withDraggable.lastHitboxes.count == 2)
    #expect(draggableRegions(withDraggable).count == 1, "one non-opaque draggable region")
    let (onClickDraggable, _) = try dndWindow { Row { square().onClick {}.draggable("s"); square() } }
    #expect(onClickDraggable.lastHitboxes.count == 1, "a draggable click target rides its opaque hitbox")
}

/// Records what `init(importing:contentType:)` is told.
private struct Spy: Transferable {
    nonisolated(unsafe) static var told: [String] = []
    let bytes: Int
    func exportedContentTypes() -> [ContentType] { [.data] }
    static func importedContentTypes() -> [ContentType] { [.data] }
    func exported(as contentType: ContentType) -> Data? { nil }
    init?(importing data: Data, contentType: ContentType) {
        Spy.told.append(contentType.identifier)
        bytes = data.count
    }
}

/// **1.29** (`R3g`, `P16b`, `DN-S` item 2). A `Data` destination takes a
/// `String` — matched by conformance and told its own type, `.data` — and an
/// external `public.png` likewise; the importer is told `.data` both times.
/// Mutation **M1ae** (hand `init(importing:)` the offered type — `Data`
/// refuses, `T7e`).
@MainActor
@Test func aDataDestinationTakesAStringThroughItsOwnImportedType() throws {
    final class Got { var sizes: [Int] = [] }
    let got = Got()
    let loads = LoadLog()
    let (keptWindow, platform) = try dndWindow {
        Row {
            square().draggable("hello")
            square().dropDestination(for: Data.self) { items, _ in got.sizes += items.map(\.count); return true }
        }
    }
    defer { withExtendedLifetime(keptWindow) {} }   // a Window is held only weakly by its platform
    dragAndDrop(platform, from: pt(100, 100), through: [pt(110, 100), pt(300, 100)])
    #expect(got.sizes == [5], "R3g, P16b: the String arrives as its 5 bytes")
    let image = item([png], bytes: ["public.png": [1, 2]], log: loads)
    #expect(platform.simulateDrop(.performed(position: pt(300, 100), items: [image])))
    #expect(got.sizes == [5, 2], "an external png reaches it as 2 bytes")

    Spy.told = []
    let (keptSpyPlatform, spyPlatform) = try dndWindow {
        Row {
            square().draggable("hello")
            square().dropDestination(for: Spy.self) { _, _ in true }
        }
    }
    defer { withExtendedLifetime(keptSpyPlatform) {} }   // a Window is held only weakly by its platform
    dragAndDrop(spyPlatform, from: pt(100, 100), through: [pt(110, 100), pt(300, 100)])
    spyPlatform.simulateDrop(.performed(position: pt(300, 100), items: [image]))
    #expect(Spy.told == ["public.data", "public.data"], "DN-S item 2: told the destination's type: \(Spy.told)")
}
