import Testing
import MetalUICore
import MetalUILayout
@testable import MetalUI

// Plan task 10, part 1, lane 3 (rulings `DD-G`, `DD-K`): `ScrollViewReader`
// and `scrollTo(_:anchor:)`. Every expected offset is a probe arm's
// (`docs/probes/swiftui-data-and-scrolling.swift` T*, and
// `docs/probes/swiftui-scrollviewreader-scope.swift` S*), re-derived for these
// fixtures: rows 30pt tall in a 100pt viewport, so row 10's top is 300 and
// `minY − anchor.y × (viewport − height)` gives `.top` 300, `.center` 265,
// `.bottom` 230 and `y: 0.25` 282.5 (T1–T3, T9).
//
// A request is resolved by the frame after `scrollTo` and shows on the frame
// after that (`DD-G` item 3), so every scenario draws until the window is
// clean (`settle`) and reads the scroller's stored `ScrollState.offset` — the
// value the last frame painted.

private func px(_ v: Float) -> Pixels { Pixels(v) }

private func sized(width: Float? = nil, height: Float? = nil,
                   column: Bool = false, row: Bool = false) -> Style {
    var s = Style()
    if column { s.flexDirection = .column }
    if row { s.flexDirection = .row }
    if let width { s.size.width = .length(.pixels(px(width))); s.flexShrink = 0 }
    if let height { s.size.height = .length(.pixels(px(height))); s.flexShrink = 0 }
    return s
}

/// Where a reader's content hands its proxy out, so a test can call
/// `scrollTo` from outside a frame — where a handler would.
@MainActor
private final class Proxies {
    var byName: [String: ScrollViewProxy] = [:]
    func keep(_ proxy: ScrollViewProxy, as name: String = "main") -> Bool {
        byName[name] = proxy
        return true
    }
    subscript(_ name: String) -> ScrollViewProxy {
        guard let proxy = byName[name] else { preconditionFailure("no proxy named \(name)") }
        return proxy
    }
    var main: ScrollViewProxy { self["main"] }
}

/// Draws until the window asks for nothing more (at most six frames).
@MainActor
private func settle(_ window: Window) {
    var frames = 0
    while window.needsRedraw && frames < 6 {
        window.drawFrameIfNeeded()
        frames += 1
    }
}

/// The stored offset of the scroller whose own id is named `name`, or of the
/// first scroller when `name` is nil.
@MainActor
private func offset(_ window: Window, _ name: String? = nil) throws -> Double {
    let region = try #require(window.lastScrollRegions.first { region in
        guard let name else { return true }
        return region.id.component == .named(ElementID(name))
    }, "no scroller named \(name ?? "(first)")")
    return window.stateTable.peek(region.id, as: ScrollState.self)?.offset ?? 0
}

@MainActor
private func requireViewport(_ window: Window, height: Float? = nil, width: Float? = nil,
                             _ name: String? = nil) throws {
    let region = try #require(window.lastScrollRegions.first { region in
        guard let name else { return true }
        return region.id.component == .named(ElementID(name))
    })
    if let height {
        try #require(region.bounds.size.height.value == height,
                     "control: the viewport is \(height)pt tall, got \(region.bounds.size.height.value)")
    }
    if let width {
        try #require(region.bounds.size.width.value == width,
                     "control: the viewport is \(width)pt wide, got \(region.bounds.size.width.value)")
    }
}

/// A 100 × 100 reader over a vertical `ScrollView` of `count` rows 30pt tall,
/// each `.id("r<i>")` — or, for the rows in `plainKeys`, `.id("<i>")`.
@MainActor
private func namedRows(_ proxies: Proxies, count: Int = 20, plainKeys: Bool = false) -> some Element {
    Box(style: sized(width: 100, height: 100, column: true)) {
        ScrollViewReader { proxy in
            let _ = proxies.keep(proxy)
            ScrollView {
                Box(style: sized(width: 100, column: true)) {
                    for i in 0..<count {
                        Box(style: sized(width: 100, height: 30)).id(plainKeys ? "\(i)" : "r\(i)")
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
    }
}

/// `namedRows` in a fresh window, drawn once; the viewport required at 100.
@MainActor
private func namedRowsWindow(_ proxies: Proxies, count: Int = 20,
                             plainKeys: Bool = false) throws -> Window {
    let (window, _) = try makeFakeWindowOnDefaultDevice(size: 100) {
        namedRows(proxies, count: count, plainKeys: plainKeys)
    }
    window.drawFrameIfNeeded()
    try requireViewport(window, height: 100)
    return window
}

/// **3.6 (T1–T3, T9).** With an anchor, the target's anchor point lands at the
/// viewport's: `.top` 300, `.center` 265, `.bottom` 230, `y: 0.25` 282.5 — and
/// `scrollTo` dirties the window. **M3f**: the formula uses the target's
/// `maxY` (reads 330, 295, 260, 312.5).
@Test @MainActor
func scrollToAnAnchorLandsTheTargetAtTheAnchor() throws {
    let cases: [(UnitPoint, Double)] = [(.top, 300), (.center, 265), (.bottom, 230),
                                         (UnitPoint(x: 0, y: 0.25), 282.5)]
    for (anchor, expected) in cases {
        let proxies = Proxies()
        let window = try namedRowsWindow(proxies)
        try #require(!window.needsRedraw, "control: a settled window")
        proxies.main.scrollTo("r10", anchor: anchor)
        #expect(window.needsRedraw, "scrollTo dirties the window")
        settle(window)
        #expect(try offset(window) == expected, "anchor \(anchor): row 10 lands at \(expected)")
    }
}

/// **3.7 (T4–T6).** With no anchor, the least distance that shows the target:
/// below → bottom-aligned (230), already visible → unmoved (0), above →
/// top-aligned (60, from 300). **M3g**: a nil anchor treated as `.top` (reads
/// 300, 30, 60 — the first two arms redden).
@Test @MainActor
func scrollToWithNoAnchorScrollsTheLeastDistance() throws {
    do {
        let proxies = Proxies()
        let window = try namedRowsWindow(proxies)
        proxies.main.scrollTo("r10")
        settle(window)
        #expect(try offset(window) == 230, "row 10 is below the viewport: bottom-aligned")
    }
    do {
        let proxies = Proxies()
        let window = try namedRowsWindow(proxies)
        proxies.main.scrollTo("r1")
        settle(window)
        #expect(try offset(window) == 0, "row 1 is already visible: unmoved")
    }
    do {
        let proxies = Proxies()
        let window = try namedRowsWindow(proxies)
        proxies.main.scrollTo("r10", anchor: .top)
        settle(window)
        try #require(try offset(window) == 300, "control: scrolled to row 10's top")
        proxies.main.scrollTo("r2")
        settle(window)
        #expect(try offset(window) == 60, "row 2 is above the viewport: top-aligned")
    }
}

/// A model the window's content closure reads each frame.
@MainActor
private final class RowCount { var count = 20 }

/// **3.8 (T7, T8).** Row 19 `.top` clamps to the content's end, 500; an
/// unknown id does nothing, and an element that appears with that id a frame
/// later is **not** scrolled to — the request was dropped. **M3h**: unresolved
/// requests kept pending (the second arm reads 450). The clamp itself is also
/// re-applied by `ScrollChrome.resolvedOffset`'s write-back (measured, see
/// the lane's mutation table).
@Test @MainActor
func scrollToClampsToTheContentAndIgnoresAnUnknownID() throws {
    do {
        let proxies = Proxies()
        let window = try namedRowsWindow(proxies)
        proxies.main.scrollTo("r19", anchor: .top)
        settle(window)
        #expect(try offset(window) == 500, "clamped to 20 × 30 − 100")
    }
    do {
        let proxies = Proxies()
        let model = RowCount()
        let (window, _) = try makeFakeWindowOnDefaultDevice(size: 100) {
            namedRows(proxies, count: model.count)
        }
        window.drawFrameIfNeeded()
        try requireViewport(window, height: 100)
        proxies.main.scrollTo("r15", anchor: .top)
        settle(window)
        try #require(try offset(window) == 450, "control: a known id in the same fixture moves")
        proxies.main.scrollTo("r0", anchor: .top)
        settle(window)
        try #require(try offset(window) == 0, "control: back at the top")

        proxies.main.scrollTo("r25", anchor: .top)
        settle(window)
        #expect(try offset(window) == 0, "an unknown id does nothing")
        model.count = 30
        window.setNeedsRedraw()
        settle(window)
        #expect(try offset(window) == 0, "and a request is not kept for an element that appears later")
    }
}

private struct Datum: Identifiable { let id: Int }

/// Logs each row index a `List` builds.
@MainActor
private final class Built { var indices: [Int] = [] }

private struct LoggingCell: Element {
    let index: Int
    let log: Built
    var elementID: ElementID? { nil }

    mutating func requestLayout(_ id: GlobalElementID, pass: inout LayoutPass)
        -> (LayoutNodeID, Void) {
        log.indices.append(index)
        return (pass.lowerLegacyNode(Style(), declared: Style(), children: [], site: .box), ())
    }
    mutating func prepaint(_ id: GlobalElementID, bounds: Bounds<Pixels>,
                           layout: inout Void, pass: inout PrepaintPass) {}
    mutating func paint(_ id: GlobalElementID, bounds: Bounds<Pixels>,
                        layout: inout Void, prepaint: inout Void, pass: inout PaintPass) {}
}

/// A 100 × 100 reader over a `ScrollView { List }` of `count` rows at 30,
/// ids `0..<count`.
@MainActor
private func listWindow(_ proxies: Proxies, count: Int, log: Built) throws
    -> (Window, FakePlatformWindow) {
    let (window, platform) = try makeFakeWindowOnDefaultDevice(size: 100) {
        Box(style: sized(width: 100, height: 100, column: true)) {
            ScrollViewReader { proxy in
                let _ = proxies.keep(proxy)
                ScrollView {
                    Box(style: sized(width: 100, column: true)) {
                        List((0..<count).map(Datum.init), rowHeight: px(30)) {
                            LoggingCell(index: $0.id, log: log)
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }
        }
    }
    window.drawFrameIfNeeded()
    try requireViewport(window, height: 100)
    // The first frame is unbounded (every row built); a one-point wheel draws
    // a bounded one, so the rows far down are unrealised when `scrollTo` runs.
    platform.simulateInput(.scrollWheel(ScrollEvent(position: Point(x: px(50), y: px(50)),
                                                    delta: Point(x: px(0), y: px(-1)))))
    settle(window)
    return (window, platform)
}

/// **3.9 (T15 for reachability; T10's rule at a uniform `rowHeight`).** A
/// `List` of 200 at 30: row 150, not realised when the request resolves,
/// `.top` → 4500 (SwiftUI's own `List` reads 3610 in T15 — its rows are not 30
/// tall). **M3i**: `List`'s pending-request scan removed (reads 1).
@Test @MainActor
func scrollToReachesAnUnrealisedListRow() throws {
    let proxies = Proxies()
    let log = Built()
    let (window, _) = try listWindow(proxies, count: 200, log: log)
    try #require(try offset(window) == 1, "control: the one-point wheel landed")
    log.indices = []
    proxies.main.scrollTo(150, anchor: .top)
    window.drawFrameIfNeeded()
    try #require(!log.indices.contains(150), "control: row 150 is unrealised on the frame that resolves the request: \(log.indices)")
    settle(window)
    #expect(try offset(window) == 4500, "row 150's top, from its index at the uniform rowHeight")
    #expect(log.indices.contains(150), "and the list windows onto it: \(log.indices)")
}

/// **3.10 (T12, T12b).** A `ForEach` element of two members (30 and 10) is
/// targeted by its FIRST member: `.top` 400, `.bottom` 330 — not the whole
/// element's 340. **M3j**: the target is the union of the element's members
/// (`.bottom` reads 340).
@Test @MainActor
func scrollToTargetsTheFirstMemberOfAForEachElement() throws {
    for (anchor, expected) in [(UnitPoint.top, 400.0), (.bottom, 330)] {
        let proxies = Proxies()
        let (window, _) = try makeFakeWindowOnDefaultDevice(size: 100) {
            Box(style: sized(width: 100, height: 100, column: true)) {
                ScrollViewReader { proxy in
                    let _ = proxies.keep(proxy)
                    ScrollView {
                        Box(style: sized(width: 100, column: true)) {
                            ForEach(0..<20) { _ in
                                Box(style: sized(width: 100, height: 30))
                                Box(style: sized(width: 100, height: 10))
                            }
                        }
                    }
                    .scrollIndicators(.hidden)
                }
            }
        }
        window.drawFrameIfNeeded()
        try requireViewport(window, height: 100)
        proxies.main.scrollTo(10, anchor: anchor)
        settle(window)
        #expect(try offset(window) == expected, "element 10's first member, anchor \(anchor)")
    }
}

/// **3.11 (T14).** A target inside an inner scroller inside an outer one moves
/// only the inner: outer 0, inner 300. **M3k**: resolved against the outermost
/// scroller frame (outer 200, clamped; inner 0).
@Test @MainActor
func scrollToMovesOnlyTheNearestScroller() throws {
    let proxies = Proxies()
    let (window, _) = try makeFakeWindowOnDefaultDevice(size: 100) {
        Box(style: sized(width: 100, height: 100, column: true)) {
            ScrollViewReader { proxy in
                let _ = proxies.keep(proxy)
                ScrollView(.vertical, elementID: ElementID("outer")) {
                    Box(style: sized(width: 100, column: true)) {
                        Box(style: sized(width: 100, height: 100, column: true)) {
                            ScrollView(.vertical, elementID: ElementID("inner")) {
                                Box(style: sized(width: 100, column: true)) {
                                    for i in 0..<20 {
                                        Box(style: sized(width: 100, height: 30)).id("r\(i)")
                                    }
                                }
                            }
                            .scrollIndicators(.hidden)
                        }
                        Box(style: sized(width: 100, height: 200))
                    }
                }
                .scrollIndicators(.hidden)
            }
        }
    }
    window.drawFrameIfNeeded()
    try requireViewport(window, height: 100, "outer")
    try requireViewport(window, height: 100, "inner")
    proxies.main.scrollTo("r10", anchor: .top)
    settle(window)
    #expect(try offset(window, "inner") == 300, "the nearest scroller moves")
    #expect(try offset(window, "outer") == 0, "and the one around it does not")
}

/// **3.12 (T11; `DD-I` item 1).** Horizontally, `.leading` lands column 10 at
/// 300; and a `ProposalScrollView` is a scroller `scrollTo` resolves against,
/// `.top` 300. **M3l**: `ProposalScrollView` pushes no scroller frame (the
/// second arm reads 0).
@Test @MainActor
func scrollToWorksHorizontallyAndInAProposalScrollView() throws {
    do {
        let proxies = Proxies()
        let (window, _) = try makeFakeWindowOnDefaultDevice(size: 100) {
            Box(style: sized(width: 100, height: 30, row: true)) {
                ScrollViewReader { proxy in
                    let _ = proxies.keep(proxy)
                    ScrollView(.horizontal) {
                        Box(style: sized(height: 30, row: true)) {
                            for i in 0..<20 {
                                Box(style: sized(width: 30, height: 30)).id("c\(i)")
                            }
                        }
                    }
                    .scrollIndicators(.hidden)
                }
            }
        }
        window.drawFrameIfNeeded()
        try requireViewport(window, width: 100)
        proxies.main.scrollTo("c10", anchor: .leading)
        settle(window)
        #expect(try offset(window) == 300, "column 10's leading edge at the viewport's")
    }
    do {
        let proxies = Proxies()
        let (window, _) = try makeFakeWindowOnDefaultDevice(size: 100) {
            Box(style: sized(width: 100, height: 100, column: true)) {
                ScrollViewReader { proxy in
                    let _ = proxies.keep(proxy)
                    ProposalScrollView {
                        VStack(spacing: 0) {
                            ForEach(0..<20) { _ in Rectangle().frame(width: 100, height: 30) }
                        }
                    }
                    .scrollIndicators(.hidden)
                }
            }
        }
        window.drawFrameIfNeeded()
        try requireViewport(window, height: 100)
        proxies.main.scrollTo(10, anchor: .top)
        settle(window)
        #expect(try offset(window) == 300, "a ProposalScrollView is resolved against as a ScrollView is")
    }
}

/// Two 100 × 100 readers side by side, `"a"` and `"b"`, each over a scroller
/// (named `"a"`/`"b"`) of 20 rows at 30; row 10 is `.id("x")` under the
/// readers in `withX`, `.id("<name>10")` elsewhere.
@MainActor
private func twoReaders(_ proxies: Proxies, withX: Set<String>) -> some Element {
    func reader(_ name: String) -> some ElementGroup {
        ScrollViewReader { proxy in
            let _ = proxies.keep(proxy, as: name)
            ScrollView(.vertical, elementID: ElementID(name)) {
                Box(style: sized(width: 100, column: true)) {
                    for i in 0..<20 {
                        Box(style: sized(width: 100, height: 30))
                            .id(i == 10 && withX.contains(name) ? "x" : "\(name)\(i)")
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
    }
    return Box(style: sized(width: 200, height: 100, row: true)) {
        Box(style: sized(width: 100, height: 100, column: true)) { reader("a") }
        Box(style: sized(width: 100, height: 100, column: true)) { reader("b") }
    }
}

/// **3.13 (S1, S2).** A proxy reaches only its own reader's subtree. S1: both
/// readers hold `.id("x")`; reader A's proxy moves only A's scroller. **S2,
/// the separating arm**: the key only under reader B; A's proxy moves
/// **neither** (SwiftUI moves nothing, S2). **M3m**: the scope check dropped
/// from the match — reddens the S2 arm (B moves to 300); the S1 arm alone
/// cannot see it, since A's key is matched first.
@Test @MainActor
func scrollToIsScopedToItsReader() throws {
    do {
        let proxies = Proxies()
        let (window, _) = try makeFakeWindowOnDefaultDevice(size: 200) {
            twoReaders(proxies, withX: ["a", "b"])
        }
        window.drawFrameIfNeeded()
        try requireViewport(window, height: 100, "a")
        try requireViewport(window, height: 100, "b")
        proxies["a"].scrollTo("x", anchor: .top)
        settle(window)
        #expect(try offset(window, "a") == 300, "S1: reader A's scroller moves")
        #expect(try offset(window, "b") == 0, "S1: reader B's does not")
    }
    do {
        let proxies = Proxies()
        let (window, _) = try makeFakeWindowOnDefaultDevice(size: 200) {
            twoReaders(proxies, withX: ["b"])
        }
        window.drawFrameIfNeeded()
        proxies["b"].scrollTo("x", anchor: .top)
        settle(window)
        try #require(try offset(window, "b") == 300, "control: B's own proxy reaches B's key")
        proxies["b"].scrollTo("b0", anchor: .top)
        settle(window)
        try #require(try offset(window, "b") == 0, "control: B back at the top")

        proxies["a"].scrollTo("x", anchor: .top)
        settle(window)
        #expect(try offset(window, "a") == 0, "S2: A's proxy finds no key in A's subtree")
        #expect(try offset(window, "b") == 0, "S2: and does not reach into B's")
    }
}

/// Logs each id and state value it is built with.
@MainActor
private final class Seen {
    var ids: [GlobalElementID] = []
    var counts: [Int] = []
}

private struct Tally: Component {
    @State var n = 0
    let seen: Seen
    var content: some ElementGroup {
        let _ = seen.counts.append(n)
        Box(style: sized(width: 50, height: 50)).onClick { n += 1 }
    }
}

private struct IDLogger: Element {
    let seen: Seen
    var elementID: ElementID? { nil }
    mutating func requestLayout(_ id: GlobalElementID, pass: inout LayoutPass)
        -> (LayoutNodeID, Void) {
        seen.ids.append(id)
        return (pass.lowerLegacyNode(sized(width: 10, height: 10), declared: sized(width: 10, height: 10),
                                     children: [], site: .box), ())
    }
    mutating func prepaint(_ id: GlobalElementID, bounds: Bounds<Pixels>,
                           layout: inout Void, pass: inout PrepaintPass) {}
    mutating func paint(_ id: GlobalElementID, bounds: Bounds<Pixels>,
                        layout: inout Void, prepaint: inout Void, pass: inout PaintPass) {}
}

/// **3.14 (`DD-G` item 1).** A reader takes ONE slot with an identity level of
/// its own: the element inside it is `positional(0)` under the reader's slot
/// `positional(0)`, the sibling after the reader keeps index 1, both are
/// stable across frames, and the reader's content keeps its `@State` (a click
/// writes 1, read on the next two frames). **M3n**: the reader consumes no
/// slot (its content numbers in its parent's cursor space).
@Test @MainActor
func aScrollViewReaderIsOneSlotWithItsOwnIdentityLevel() throws {
    let seen = Seen()
    let (window, platform) = try makeFakeWindowOnDefaultDevice(size: 100) {
        Box(style: sized(width: 100, height: 100, column: true)) {
            ScrollViewReader { _ in
                IDLogger(seen: seen)
                Tally(seen: seen)
            }
            IDLogger(seen: seen)
        }
    }
    window.drawFrameIfNeeded()
    try #require(seen.ids.count == 2, "control: two loggers built once each")
    let inside = seen.ids[0], after = seen.ids[1]
    let box = try #require(after.parent, "the sibling hangs under the box")
    #expect(after.component == .positional(1), "the sibling after the reader keeps index 1")
    #expect(inside.component == .positional(0), "the reader's content numbers from 0")
    #expect(inside.parent?.component == .positional(0) && inside.parent?.parent == box,
            "under the reader's own slot, index 0 of the box")

    let tally = try #require(window.lastHitboxes.first { $0.handlers.onClick != nil })
    let point = Point(x: tally.bounds.origin.x + px(5), y: tally.bounds.origin.y + px(5))
    platform.simulateInput(.mouseDown(MouseEvent(position: point)))
    platform.simulateInput(.mouseUp(MouseEvent(position: point)))
    seen.ids = []
    seen.counts = []
    window.drawFrameIfNeeded()
    window.setNeedsRedraw()
    window.drawFrameIfNeeded()
    #expect(seen.counts == [1, 1], "the reader's content keeps its state across frames: \(seen.counts)")
    #expect(seen.ids == [inside, after, inside, after], "and both ids are stable")
}

/// **3.16 (`DD-K`, S3–S5).** Keys compare by value: `.id("10")` is reached by
/// `"10"` (300) and not by `10` (0) (S3); a `ForEach(0..<20)` key is reached
/// by `10` and not by `"10"` (S5); a realised `List` row is reached by its
/// `datum.id`'s value (`2` → 60) and not by its description (`"2"` → 0). And
/// with **no** request pending, a frame of a 1000-element `ForEach` notes no
/// typed key (literal 0; 1000 with one pending, the positive control).
/// **M3p**: match by `String(describing:)` (the negative arms redden); **M3q**:
/// typed keys noted unconditionally (the counter arm reddens).
@Test @MainActor
func scrollToComparesKeysByValue() throws {
    // S3: a String `.id`.
    for (key, expected) in [(AnyHashable("10"), 300.0), (AnyHashable(10), 0)] {
        let proxies = Proxies()
        let window = try namedRowsWindow(proxies, plainKeys: true)
        proxies.main.scrollTo(key, anchor: .top)
        settle(window)
        #expect(try offset(window) == expected, ".id(\"10\") by \(key.base) (\(type(of: key.base)))")
    }
    // S5: a `ForEach` key.
    for (key, expected) in [(AnyHashable(10), 300.0), (AnyHashable("10"), 0)] {
        let proxies = Proxies()
        let (window, _) = try makeFakeWindowOnDefaultDevice(size: 100) {
            Box(style: sized(width: 100, height: 100, column: true)) {
                ScrollViewReader { proxy in
                    let _ = proxies.keep(proxy)
                    ScrollView {
                        Box(style: sized(width: 100, column: true)) {
                            ForEach(0..<20) { _ in Box(style: sized(width: 100, height: 30)) }
                        }
                    }
                    .scrollIndicators(.hidden)
                }
            }
        }
        window.drawFrameIfNeeded()
        proxies.main.scrollTo(key, anchor: .top)
        settle(window)
        #expect(try offset(window) == expected, "ForEach key 10 by \(key.base) (\(type(of: key.base)))")
    }
    // A realised `List` row, by `datum.id`'s value.
    for (key, expected) in [(AnyHashable(2), 60.0), (AnyHashable("2"), 0)] {
        let proxies = Proxies()
        let log = Built()
        let (window, platform) = try listWindow(proxies, count: 40, log: log)
        platform.simulateInput(.scrollWheel(ScrollEvent(position: Point(x: px(50), y: px(50)),
                                                        delta: Point(x: px(0), y: px(1)))))
        settle(window)
        try #require(try offset(window) == 0, "control: back at the top")
        log.indices = []
        proxies.main.scrollTo(key, anchor: .top)
        window.drawFrameIfNeeded()
        try #require(log.indices.contains(2), "control: row 2 is realised when the request resolves: \(log.indices)")
        settle(window)
        #expect(try offset(window) == expected, "List row 2 by \(key.base) (\(type(of: key.base)))")
    }
    // The counter: typed keys are noted only while a request is pending.
    func notedKeys(pending: Bool) -> Int {
        let frame = Frame(contentSize: Size(width: px(100), height: px(100)), scaleFactor: 1)
        if pending {
            let scope = GlobalElementID.child(of: nil, at: 0, name: nil)
            frame.scrollRequestQueue.enqueue(ScrollRequest(scope: scope, key: AnyHashable(-1), anchor: nil))
        }
        var tree = Box(style: sized(width: 100, column: true)) {
            ForEach(0..<1000) { _ in Box(style: sized(width: 10, height: 1)) }
        }
        frame.render(&tree)
        return frame.scrollKeyCount
    }
    try #require(notedKeys(pending: true) == 1000, "control: with a request pending, every element's key is noted")
    #expect(notedKeys(pending: false) == 0, "with none pending, a steady frame notes nothing")
}
