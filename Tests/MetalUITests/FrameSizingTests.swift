import Testing
import Metal
import MetalUICore
import MetalUILayout
import MetalUIPlatform
@testable import MetalUI

// Lane 2 of plan task 4, "the legacy frame's SwiftUI surface"
// (`docs/superpowers/specs/2026-09-15-frame-sizing-design.md`; rulings `FR-C`,
// `FR-D`, `FR-E`, `FR-K`, `FR-N`, `FR-O`, `FR-P`, `FR-S` in
// `docs/superpowers/2026-09-15-frame-sizing-decisions.md`).
//
// **What these tests are against.** SwiftUI's own answers, measured by
// `docs/probes/swiftui-frame-semantics.swift` (54 arms, arm names `A1`, `B1`,
// `D4`, `E1`…) and `docs/probes/swiftui-frame-negative-sizes.swift` (17 arms,
// `H…`). Where MetalUI's CSS lowering cannot reach SwiftUI's answer the test
// pins MetalUI's number **wrong on purpose** and carries SwiftUI's in its doc
// comment: `FR-E` (a finite maximum clamps but never grows) and `FR-O` (a
// single-axis infinite maximum is inert). `FR-N` (an oversized child squeezed on
// one axis) was closed by plan task 6's ruling `CN-N`, whose tests (5.1, 5.6,
// 5.7) and `CN-O`'s (5.2, fractional sizing) were in this file too.
//
// **Stage 7b retired every legacy-pinned test here** (record §49 §4 rows
// 195–206): the `FR-E`/`FR-O` pins, `CN-N`'s and `CN-O`'s tests and the
// sizing inventory each read the CSS engine's answer, and each row names the
// proposal-authority test that pins what the lowering does instead. N2.3 and
// N2.4 carry the two facts no lowering suite pinned.
//
// Every measurement here is a rendered `Frame` — no golden moves, nothing
// sleeps. Red runs and the mutation that reddens each test are recorded in the
// test's doc comment and in `docs/record/14-frame-and-sizing.md`.

private func px(_ v: Float) -> Pixels { Pixels(v) }

/// What the probes below write down, by reference, so it survives the content
/// closure rebuilding every element each frame.
@MainActor
private final class SizeLog {
    var bounds: [String: Bounds<Pixels>] = [:]
    var names: [String] = []
}

/// A childless legacy `StyledElement` recording the bounds its `prepaint`
/// receives. Optionally declares its own size, which is what makes it either a
/// content-sized child (no declared axis) or an oversized one.
///
/// **A Dual fixture since stage 6a** (record §38, spec §5 lane 3): under the
/// proposal authority it is `declaredSizeNativeLeaf` (`ElementLayoutTests`), and
/// its one R test passes `.proposal`; under the legacy one it registers through
/// `Frame`'s internal legacy registrar, and its fourteen P tests pass `.legacy`.
/// The file's `render` helper takes the authority as a **required** argument,
/// so every call names its own.
///
/// **Stage 7b** (record §49 §6.2) the file's twelve legacy-pinned tests and
/// added N2.3 and N2.4 on the proposal side; the legacy branch stays for the
/// kept loop over both authorities (`chainedLegacyFramesAgreeWithSwiftUIsOrderingRules`).
private struct Mark: StyledElement {
    var name: String
    var log: SizeLog
    var style: Style
    var decoration = Decoration()
    var elementID: ElementID?
    var handlers = Handlers()

    init(_ name: String, log: SizeLog, width: Float? = nil, height: Float? = nil) {
        self.name = name
        self.log = log
        var style = Style()
        if let width { style.size.width = .length(.pixels(px(width))) }
        if let height { style.size.height = .length(.pixels(px(height))) }
        self.style = style
    }

    mutating func requestLayout(_ id: GlobalElementID, pass: inout LayoutPass) -> (LayoutNodeID, Void) {
        (pass.lowersToProposal
            ? declaredSizeNativeLeaf(style, pass)
            : pass.frame.requestNode(style: style, children: []), ())
    }

    mutating func prepaint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Void,
                           pass: inout PrepaintPass) {
        log.bounds[name] = bounds
        log.names.append(name)
    }

    mutating func paint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Void,
                        prepaint: inout Void, pass: inout PaintPass) {}
}

private struct Origin: Equatable, CustomStringConvertible {
    var x: Float, y: Float
    init(_ bounds: Bounds<Pixels>) {
        x = bounds.origin.x.value
        y = bounds.origin.y.value
    }
    init(_ x: Float, _ y: Float) {
        self.x = x
        self.y = y
    }
    var description: String { "(\(x), \(y))" }
}

private struct Rect: Equatable, CustomStringConvertible {
    var x: Float, y: Float, width: Float, height: Float
    init(_ bounds: Bounds<Pixels>) {
        x = bounds.origin.x.value
        y = bounds.origin.y.value
        width = bounds.size.width.value
        height = bounds.size.height.value
    }
    init(_ x: Float, _ y: Float, _ width: Float, _ height: Float) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
    var description: String { "(\(x), \(y)) \(width)x\(height)" }
}

/// The bounds a `Mark` named `name` received, from one rendered frame whose
/// root is `make`'s element.
@MainActor
private func render<Root: Element>(authority: LayoutAuthority, width: Float = 300, height: Float = 200,
                                   _ make: (SizeLog) -> Root) throws -> SizeLog {
    let log = SizeLog()
    var root = make(log)
    Frame(contentSize: Size(width: px(width), height: px(height)), scaleFactor: 1,
          layoutAuthority: authority).render(&root)
    return log
}

// MARK: - 2.1 alignment (ruling FR-C)

/// **The legacy frame places its child at each of SwiftUI's nine alignments**
/// (ruling `FR-C`, critic finding 15: the lowering switches over
/// `ProposalAlignment`'s nine CASES, never over its `Double` factors).
///
/// A 20×20 child in `.frame(width: 60, height: 40, alignment:)`. The nine
/// origins are the probe's `B1`–`B8` offsets plus the centred control, and
/// scratch `L6` read all nine from the CSS engine before the API existed.
///
/// Mutations: dropping `justifyContent` from `FrameSpec.style()` reddens the
/// six arms whose x is not 20; dropping `alignItems` reddens the six whose y is
/// not 10; swapping the two axes reddens the four corners.
///
/// Pinned to the legacy authority by stage 6a (CE+RP, record §38 §4); stage 6b
/// (`LR-DG`, R-centre — the root is the frame layer) moves it to `.proposal`:
/// the 60×40 layer is centred in the 300×200 frame at ((300 − 60) / 2,
/// (200 − 40) / 2) = (120, 80) (`CN-J`), so every origin below is the probe's
/// offset plus (120, 80).
@Test @MainActor func aLegacyFramePlacesItsChildAtEachOfTheNineAlignments() throws {
    func origin(_ alignment: ProposalAlignment) throws -> Origin {
        let log = try render(authority: .proposal) { log in
            Mark("leaf", log: log, width: 20, height: 20)
                .frame(width: px(60), height: px(40), alignment: alignment)
        }
        return Origin(try #require(log.bounds["leaf"]))
    }

    let topLeading = try origin(.topLeading)
    let centre = try origin(.center)
    try #require(topLeading != centre,
                 "the instrument cannot see alignment: topLeading \(topLeading), center \(centre)")

    #expect(topLeading == Origin(120, 80), "topLeading \(topLeading)")
    #expect(try origin(.top) == Origin(140, 80))
    #expect(try origin(.topTrailing) == Origin(160, 80))
    #expect(try origin(.leading) == Origin(120, 90))
    #expect(centre == Origin(140, 90), "center \(centre)")
    #expect(try origin(.trailing) == Origin(160, 90))
    #expect(try origin(.bottomLeading) == Origin(120, 100))
    #expect(try origin(.bottom) == Origin(140, 100))
    #expect(try origin(.bottomTrailing) == Origin(160, 100))
}

// MARK: - 2.4 an ideal dimension traps (ruling FR-D)

/// **`idealWidth`/`idealHeight` TRAP on the legacy path** (ruling `FR-D`): the
/// CSS engine has no unspecified proposal for an ideal to answer, and `Style`
/// has no field that carries a caller's preferred size. An accepted-and-ignored
/// parameter is the declared-but-inert shape CLAUDE.md keeps a table of, so the
/// parameters stay in the signature — a port between paths is a type change and
/// nothing else — and laying the frame out traps with a message naming the
/// proposal path.
///
/// **Amended by plan task 7, stage 1, lane 4 (ruling `LR-H`)**: the trap moved
/// from the overload (construction) to the frame layer's **legacy registration**,
/// because under the proposal layout authority the same layer lowers onto the
/// kernel frame, whose ideal is SwiftUI's (spec 4.6). So each closure below
/// **renders** its value under the legacy authority; the message check is
/// unchanged. The old construction-only spelling exits successfully since lane 4,
/// which is the amendment's evidence (record §18, lane 4).
///
/// **Two positive controls**, and the second is the overload split's
/// (critic finding 5): the same flexible overload with min/max only must render
/// successfully, and `.frame(idealWidth:)` on a **proposal** element must render
/// successfully too — if the legacy overload ever won there, a working SwiftUI
/// idiom would become this trap.
///
/// Mutations: delete the legacy registration's check (both failure arms redden);
/// make the legacy overload win on a proposal element (the proposal control
/// reddens).
@Test func anIdealDimensionOnTheLegacyFrameTraps() async throws {
    let width = await #expect(processExitsWith: .failure,
                              observing: [\.standardErrorContent]) {
        await MainActor.run {
            _ = LayoutDifferential.render(authority: .legacy, width: 200, height: 200) {
                Text("ideal").frame(idealWidth: Pixels(80))
            }
        }
    }
    let widthError = String(decoding: width?.standardErrorContent ?? [], as: UTF8.self)
    #expect(widthError.contains("idealWidth"),
            "the trap must name the parameter that caused it: \(widthError)")

    await #expect(processExitsWith: .failure) {
        await MainActor.run {
            _ = LayoutDifferential.render(authority: .legacy, width: 200, height: 200) {
                Text("ideal").frame(idealHeight: Pixels(80))
            }
        }
    }

    await #expect(processExitsWith: .success) {
        await MainActor.run {
            _ = LayoutDifferential.render(authority: .legacy, width: 200, height: 200) {
                Text("bounded").frame(minWidth: Pixels(40), maxWidth: Pixels(80))
            }
        }
    }

    await #expect(processExitsWith: .success) {
        await MainActor.run {
            // A proposal root, not the harness root: a legacy `Stack` over a native
            // node is `SA-G`'s trap, whatever the frame does.
            var root = Rectangle().frame(idealWidth: Pixels(80))
            Frame(contentSize: Size(width: Pixels(200), height: Pixels(200)), scaleFactor: 1,
                  layoutAuthority: .legacy).render(&root)
        }
    }
}

// MARK: - 2.5 chained frames (the probe's E arms)

/// **Chained legacy frames agree with SwiftUI's ordering rules**: the OUTER
/// frame's size is what the parent sees, and the inner keeps its own and
/// overflows (probe `E1`, `E2`, `E6`).
///
/// - `.frame(width: 100).frame(width: 50)` reports **50**, the 20pt leaf at
///   x = 15 — the inner 100pt layer overflowing the 50pt outer one;
/// - reversed, it reports **100** with the leaf at x = 40;
/// - `.frame(width: 60, height: 40).frame(width: 120, height: 100, alignment:
///   .topLeading)` reports 120×100 with the leaf at **(20, 10)**.
///
/// **Arms 1 and 2 do not discriminate on their own** (scratch `N13`): a 100pt
/// inner overflowing a 50pt outer and one shrunk to 50 both centre the leaf at
/// x = 15. Arm 3 is what separates them, because only an aligned outer frame
/// puts the inner layer where its own size is observable.
///
/// Mutation: mint the layer nodes outermost-first (arms 1 and 2 swap); drop
/// `justifyContent` (arm 3).
///
/// Pinned to the legacy authority by stage 6a (CE+RP, record §38 §4); unpinned
/// by stage 6b (`LR-DG`, R-fill): every root declares the 300×200 frame's
/// extent on its two auto axes — what `CS-I` gave the legacy root, now spelled
/// — so the literals hold on both authorities, and the test reads both
/// (`render`'s authority is a required argument, record §38 §17).
@Test @MainActor func chainedLegacyFramesAgreeWithSwiftUIsOrderingRules() throws {
    for authority in [LayoutAuthority.legacy, .proposal] {
        let innerWide = try render(authority: authority) { log in
            Row {
                Mark("leaf", log: log, width: 20, height: 20).frame(width: px(100)).frame(width: px(50))
                Mark("sibling", log: log, width: 5, height: 5)
            }.alignItems(.flexStart).width(px(300)).height(px(200))
        }
        let outerWide = try render(authority: authority) { log in
            Row {
                Mark("leaf", log: log, width: 20, height: 20).frame(width: px(50)).frame(width: px(100))
                Mark("sibling", log: log, width: 5, height: 5)
            }.alignItems(.flexStart).width(px(300)).height(px(200))
        }
        let innerLeafX = Origin(try #require(innerWide.bounds["leaf"])).x
        let outerLeafX = Origin(try #require(outerWide.bounds["leaf"])).x
        try #require(innerLeafX != outerLeafX,
                     "the instrument cannot see chain order: \(innerLeafX) and \(outerLeafX)")

        #expect(Origin(try #require(innerWide.bounds["sibling"])).x == 50, "E1's outer width, \(authority)")
        #expect(innerLeafX == 15, "E1's leaf, \(authority)")
        #expect(Origin(try #require(outerWide.bounds["sibling"])).x == 100, "E2's outer width, \(authority)")
        #expect(outerLeafX == 40, "E2's leaf, \(authority)")

        let aligned = try render(authority: authority) { log in
            Row {
                Mark("leaf", log: log, width: 20, height: 20)
                    .frame(width: px(60), height: px(40))
                    .frame(width: px(120), height: px(100), alignment: .topLeading)
                Mark("sibling", log: log, width: 5, height: 5)
            }.alignItems(.flexStart).width(px(300)).height(px(200))
        }
        #expect(Origin(try #require(aligned.bounds["sibling"])).x == 120, "E6's outer width, \(authority)")
        #expect(Origin(try #require(aligned.bounds["leaf"])) == Origin(20, 10), "E6's leaf, \(authority)")
    }
}

// MARK: - 2.6 a frame's width reaches a measured leaf

/// **A legacy frame proposes its width to a measured leaf**, which re-wraps —
/// the "it broke text measurement" half of the reverted 2026-09-12 conversion
/// (`4aaca40`, reverted by `d0a04d3`), refuted by measurement (`FR-F`).
///
/// `Text("alpha bravo charlie delta").font(size: 12)` in a `Column`: framed at
/// 60pt it wraps to four 15pt lines, so the marker after it sits at y = 60;
/// unframed the text is one line and the marker sits at y = 15. SwiftUI's own
/// numbers for the same string are the probe's `F1` (60×60) and `F control`
/// (139×15).
///
/// Mutation: drop `size.width` from `FrameSpec.style()`.
///
/// Pinned to the legacy authority by stage 6a (CE+RP, record §38 §4); unpinned
/// by stage 6b (`LR-DG`, R-fill): every root declares the 300×200 frame's
/// extent on its two auto axes — what `CS-I` gave the legacy root, now spelled
/// — so the literals hold on both authorities, and the test reads both
/// (`render`'s authority is a required argument, record §38 §17).
@Test @MainActor func aLegacyFrameProposesItsWidthToAMeasuredLeaf() throws {
    for authority in [LayoutAuthority.legacy, .proposal] {
        let framed = try render(authority: authority) { log in
            Column {
                Text("alpha bravo charlie delta").font(size: 12).frame(width: px(60))
                Mark("marker", log: log, width: 5, height: 5)
            }.width(px(300)).height(px(200))
        }
        let bare = try render(authority: authority) { log in
            Column {
                Text("alpha bravo charlie delta").font(size: 12)
                Mark("marker", log: log, width: 5, height: 5)
            }.width(px(300)).height(px(200))
        }
        let framedY = Origin(try #require(framed.bounds["marker"])).y
        let bareY = Origin(try #require(bare.bounds["marker"])).y
        try #require(framedY != bareY, "the frame's width never reached the leaf: \(framedY), \(bareY)")

        #expect(framedY == 60, "four wrapped 15pt lines: \(framedY), \(authority)")
        #expect(bareY == 15, "one unwrapped line: \(bareY), \(authority)")
    }
}

// MARK: - 2.7 a frame around a `List` (stage 7b's N2.3, record §49 §4 row 197)

/// **A frame around a `List` builds exactly the rows the unframed `List`
/// builds, under the proposal authority** — N2.3 of stage 7b (record §49 §4
/// row 197, spec §6 lane 2), the non-CSS half of the retired
/// `aLegacyFrameAroundAListStillBuildsEveryRow` (no `ListLoweringTests` arm
/// frames a `List`: grep). The CSS half — the framed rows keeping their 400pt
/// width by the automatic minimum — dies with the CSS engine.
///
/// Forty 40pt rows in a `ScrollView` in a 400×600 window, sharing one
/// `StateTable` across two frames. **The literal is derived from
/// `List.visibleRange` before the run**: the lowered viewport fills its
/// proposal on the scrolling axis (600, `LR-BC`), the offset is 0, so the
/// window is `floor(0 / 40) − 2 … ceil(600 / 40) + 2`, clamped into `0..<40`:
/// rows **0 through 16**, seventeen of the forty. The cold frame builds every
/// row (`MP-I`: no measured viewport yet), which is the disagreeing control —
/// `try #require`d to read all forty, unlike the warm frame.
///
/// Red-before (record §49 §6.2, M2.3): `visibleRange` returning `0..<count`
/// (windowing off) — both warm arms read forty rows against the literal.
@Test @MainActor func aFramedListBuildsTheRowsTheUnframedListBuildsUnderTheProposalAuthority() throws {
    struct Datum: Identifiable { let id: String }
    let data = (0..<40).map { Datum(id: "row-\($0)") }

    func rowsBuilt<Wrapped: Element>(_ wrap: @escaping (List<[Datum], Mark>) -> Wrapped)
        -> (cold: [Int], warm: [Int]) {
        let log = SizeLog()
        var root = ScrollView {
            wrap(List(data, rowHeight: px(40)) { Mark($0.id, log: log, width: 400, height: 20) })
        }
        let size = Size(width: px(400), height: px(600))
        let table = StateTable()
        func built() -> [Int] {
            log.bounds.keys
                .compactMap { $0.hasPrefix("row-") ? Int($0.dropFirst(4)) : nil }
                .sorted()
        }
        Frame(contentSize: size, scaleFactor: 1, stateTable: table, layoutAuthority: .proposal).render(&root)
        let cold = built()
        log.bounds.removeAll()
        Frame(contentSize: size, scaleFactor: 1, stateTable: table, layoutAuthority: .proposal).render(&root)
        return (cold, built())
    }

    let window = Array(0..<17)
    let bare = rowsBuilt { $0 }
    let framed = rowsBuilt { $0.frame(width: px(200)) }
    try #require(bare.cold == Array(0..<40) && framed.cold == Array(0..<40),
                 "the cold frame builds every row (MP-I): bare \(bare.cold.count), framed \(framed.cold.count)")
    try #require(bare.cold != window, "the control must disagree with the windowed literal")

    #expect(bare.warm == window, "the unframed list built \(bare.warm)")
    #expect(framed.warm == window, "`.frame(width: 200)` built \(framed.warm)")
    #expect(framed.warm == bare.warm, "framed \(framed.warm) against unframed \(bare.warm)")
}

// MARK: - Stage 7b: a `ScrollView` inside a frame (N2.4, record §49 §4 row 206)

/// **A `ScrollView` inside a frame keeps its viewport and wheel, through a
/// real `Window` at the default (proposal) authority** — N2.4 of stage 7b
/// (record §49 §4 row 206, spec §6 lane 2), the retired
/// `aScrollViewInsideASingleChildLegacyFrameKeepsItsViewportAndWheel`'s four
/// arms re-derived for the proposal engine (no `LoweringScrollTests` arm
/// frames a `ScrollView`: grep). Each arm pre-flights the same tree in a
/// 200×200 `Frame` with diagnostics on and `try #require`s an empty report
/// before its `Window` opens (CLAUDE.md "a window test in a mode that traps
/// pre-flights in a mode that reports").
///
/// **Literals, derived by hand before the run.** The `Row` (gap 0, cross
/// axis centred) is the root and is centred at its own answer (`CN-J`). The
/// lowered viewport answers its proposal on the scrolling axis and its
/// content's answer on the other (`LR-BC`); a frame centres it unless told
/// otherwise; content rects are layout rects, unscrolled.
///
/// - **A**, `ScrollView(.vertical) { c 80×400 }` in a 120×100 frame: the row
///   is 150×100 at (25, 50), the frame at (55, 50), the viewport 80×100
///   centred in it at (75, 50); c at (75, 50) 80×400; the wheel scrolls
///   **37** (the CSS engine's viewport hugged its 400pt content and scrolled
///   0).
/// - **F**, A's scroll view in a `Box` declared 100 tall: the box hugs the
///   viewport's 80 and stretches it to 100, so the same (75, 50) 80×100, c
///   (75, 50), offset 37.
/// - **H**, F's box in a 60×60 `.topLeading` frame: the row is 90×60 at (55,
///   70), the frame at (85, 70), the 80×100 box at its top-leading corner:
///   region (85, 70) 80×100, c (85, 70), offset 37.
/// - **G**, `ScrollView(.horizontal) { c 400×40 }` in a `Box` declared 100
///   wide in a 120×100 frame: the viewport takes the box's 100 on the
///   scrolling axis and its content's 40 on the other; the 100×40 box centred
///   in the frame at (65, 80): region (65, 80) 100×40, c (65, 80) 400×40,
///   offset 37.
///
/// **The control**: A's scroll view over a 50pt-tall c, which fits its 100pt
/// viewport and cannot scroll, `try #require`d to read an offset unlike A's
/// (the instrument can see a scroll).
///
/// Red-before (record §49 §6.2, M2.4): `ScrollChrome.clamp(offset:content:viewport:)`
/// returning 0.
@Test @MainActor func aScrollViewInsideAFrameKeepsItsViewportAndWheelUnderTheProposalAuthority() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    func arm<Content: Element>(at x: Float, _ y: Float, horizontal: Bool = false,
                               _ make: @escaping @MainActor (SizeLog) -> Content) throws
        -> (region: Rect, content: Rect, offset: Double) {
        var preflight = make(SizeLog())
        let diagnostics = Frame(contentSize: Size(width: px(200), height: px(200)), scaleFactor: 1,
                                layoutAuthority: .proposal, reportsUnlowerableFields: true)
        diagnostics.render(&preflight)
        try #require(diagnostics.unlowerableFields.isEmpty,
                     "the pre-flight reported \(diagnostics.unlowerableFields.map(\.description))")
        let log = SizeLog()
        let (window, platform) = try makeFakeWindow(device: device, size: 200) { make(log) }
        window.drawFrameIfNeeded()
        let region = try #require(window.lastScrollRegions.first, "no scroll region registered")
        let delta = horizontal ? Point(x: px(-37), y: px(0)) : Point(x: px(0), y: px(-37))
        platform.simulateInput(.scrollWheel(ScrollEvent(position: Point(x: px(x), y: px(y)), delta: delta)))
        window.drawFrameIfNeeded()
        let offset = try #require(window.stateTable.peek(region.id, as: ScrollState.self)).offset
        return (Rect(region.bounds), Rect(try #require(log.bounds["c"])), offset)
    }

    let a = try arm(at: 115, 100) { log in
        Row {
            Mark("pad", log: log, width: 30, height: 30)
            ScrollView(.vertical) { Mark("c", log: log, width: 80, height: 400) }
                .frame(width: px(120), height: px(100))
        }
    }
    let fits = try arm(at: 115, 100) { log in
        Row {
            Mark("pad", log: log, width: 30, height: 30)
            ScrollView(.vertical) { Mark("c", log: log, width: 80, height: 50) }
                .frame(width: px(120), height: px(100))
        }
    }
    try #require(a.offset != fits.offset, "neither arm's offset moved, so the wheel is unobserved: \(a.offset)")

    #expect(a.region == Rect(75, 50, 80, 100) && a.content == Rect(75, 50, 80, 400) && a.offset == 37,
            "A: \(a)")
    let f = try arm(at: 115, 100) { log in
        Row {
            Mark("pad", log: log, width: 30, height: 30)
            Box { ScrollView(.vertical) { Mark("c", log: log, width: 80, height: 400) } }
                .height(px(100))
                .frame(width: px(120), height: px(100))
        }
    }
    #expect(f.region == Rect(75, 50, 80, 100) && f.content == Rect(75, 50, 80, 400) && f.offset == 37,
            "F: \(f)")
    let h = try arm(at: 120, 100) { log in
        Row {
            Mark("pad", log: log, width: 30, height: 30)
            Box { ScrollView(.vertical) { Mark("c", log: log, width: 80, height: 400) } }
                .height(px(100))
                .frame(width: px(60), height: px(60), alignment: .topLeading)
        }
    }
    #expect(h.region == Rect(85, 70, 80, 100) && h.content == Rect(85, 70, 80, 400) && h.offset == 37,
            "H: \(h)")
    let g = try arm(at: 115, 100, horizontal: true) { log in
        Row {
            Mark("pad", log: log, width: 30, height: 30)
            Box { ScrollView(.horizontal) { Mark("c", log: log, width: 400, height: 40) } }
                .width(px(100))
                .frame(width: px(120), height: px(100))
        }
    }
    #expect(g.region == Rect(65, 80, 100, 40) && g.content == Rect(65, 80, 400, 40) && g.offset == 37,
            "G: \(g)")
}
