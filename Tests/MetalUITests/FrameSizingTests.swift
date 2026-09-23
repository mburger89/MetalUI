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
// 5.7) and `CN-O`'s (5.2, fractional sizing) are in this file too.
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
/// **A Dual fixture since stage 6a** (record §30, spec §5 lane 3): under the
/// proposal authority it is `declaredSizeNativeLeaf` (`ElementLayoutTests`), and
/// its one R test passes `.proposal`; under the legacy one it registers through
/// `Frame`'s internal legacy registrar, and its fourteen P tests pass `.legacy`.
/// The file's three helpers take the authority as a **required** argument, so
/// every call names its own.
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

/// A chain's outer width as a flex item, read as the **x of a 5pt sibling**
/// placed after it in a `Row` — the instrument scratch arm `L10` used, and the
/// only one that can see a layer's own width without reaching into the tree.
@MainActor
private func widthInRow<Chain: Element>(authority: LayoutAuthority, rowWidth: Float = 300,
                                        siblingWidth: Float = 5,
                                        _ make: (SizeLog) -> Chain) throws -> Float {
    let log = SizeLog()
    var row = Row {
        make(log)
        Mark("sibling", log: log, width: siblingWidth, height: 5)
    }.alignItems(.flexStart)
    Frame(contentSize: Size(width: px(rowWidth), height: px(200)), scaleFactor: 1,
          layoutAuthority: authority).render(&row)
    return try #require(log.bounds["sibling"], "the sibling never prepainted").origin.x.value
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
/// Pinned to the legacy authority by stage 6a (CE+RP, record §30 §4).
@Test @MainActor func aLegacyFramePlacesItsChildAtEachOfTheNineAlignments() throws {
    func origin(_ alignment: ProposalAlignment) throws -> Origin {
        let log = try render(authority: .legacy) { log in
            Mark("leaf", log: log, width: 20, height: 20)
                .frame(width: px(60), height: px(40), alignment: alignment)
        }
        return Origin(try #require(log.bounds["leaf"]))
    }

    let topLeading = try origin(.topLeading)
    let centre = try origin(.center)
    try #require(topLeading != centre,
                 "the instrument cannot see alignment: topLeading \(topLeading), center \(centre)")

    #expect(topLeading == Origin(0, 0), "topLeading \(topLeading)")
    #expect(try origin(.top) == Origin(20, 0))
    #expect(try origin(.topTrailing) == Origin(40, 0))
    #expect(try origin(.leading) == Origin(0, 10))
    #expect(centre == Origin(20, 10), "center \(centre)")
    #expect(try origin(.trailing) == Origin(40, 10))
    #expect(try origin(.bottomLeading) == Origin(0, 20))
    #expect(try origin(.bottom) == Origin(20, 20))
    #expect(try origin(.bottomTrailing) == Origin(40, 20))
}

// MARK: - 2.2 a fixed frame does not shrink (ruling FR-P)

/// **A fixed legacy frame keeps its declared size in an over-constrained
/// parent** — SwiftUI has no shrinking, and `FR-P` pins each declared axis with
/// an axis-named `minSize`.
///
/// Two 200pt frames in a 300pt `Row`: 400 of content in 300 of space. Each
/// layer keeps 200 and overflows, so the 20pt marks sit at 90 and 290. Without
/// the pin both layers shrink to 150 and the marks read 65 and 215 (scratch
/// `N10`).
///
/// Mutation: drop `minSize` from the fixed-axis rows of `FrameSpec.style()`.
///
/// Pinned to the legacy authority by stage 6a (CSS-frame, record §30 §4).
@Test @MainActor func aLegacyFixedFrameDoesNotShrinkAsAFlexItem() throws {
    let log = try render(authority: .legacy) { log in
        Row {
            Mark("a", log: log, width: 20, height: 20).frame(width: px(200), height: px(20))
            Mark("b", log: log, width: 20, height: 20).frame(width: px(200), height: px(20))
        }
    }
    // The positive control: the same two declared widths WITHOUT a frame do
    // shrink in this row, so the fixture is genuinely over-constrained and the
    // instrument can see shrinking when it happens.
    let unpinned = try render(authority: .legacy) { log in
        Row {
            Mark("a", log: log, width: 200, height: 20)
            Mark("b", log: log, width: 200, height: 20)
        }
    }
    let unpinnedB = Origin(try #require(unpinned.bounds["b"])).x
    try #require(unpinnedB < 200,
                 "the row is not over-constrained, so nothing could shrink: \(unpinnedB)")

    #expect(Origin(try #require(log.bounds["a"])).x == 90)
    #expect(Origin(try #require(log.bounds["b"])).x == 290)
}

// MARK: - 2.3 min/max clamp, and the divergence (ruling FR-E)

/// **A legacy `maxWidth` clamps but never grows into the proposal** — ruling
/// `FR-E`, with the third arm **pinned wrong on purpose**.
///
/// Three layers in a 300pt `Row`, each layer's width read from a 5pt sibling:
///
/// - `minWidth: 40` over a 20pt child → **40**, which is SwiftUI's `D7`;
/// - `maxWidth: 80` over a 200pt child → **80**, which is SwiftUI's `D14`;
/// - `maxWidth: 80` over a 20pt child → **20**, where **SwiftUI's `D4` reads
///   80**: SwiftUI's flexible frame answers its proposal clamped into the
///   bounds, and a CSS layer cannot see a proposal for one named axis
///   (`FR-E`'s M2/M4). Fixing it needs the parent's main axis — plan task 6.
///
/// Mutations: drop `minSize` from the minimum row (arm 1); drop `maxSize` from
/// the maximum row (arm 2).
///
/// Pinned to the legacy authority by stage 6a (CSS-frame, record §30 §4).
@Test @MainActor func aLegacyFrameClampsToItsMinimumAndMaximumWithoutGrowingIntoTheProposal() throws {
    let minimum = try widthInRow(authority: .legacy) { log in
        Mark("child", log: log, width: 20, height: 20).frame(minWidth: px(40))
    }
    let maximumOverALargeChild = try widthInRow(authority: .legacy) { log in
        Mark("child", log: log, width: 200, height: 20).frame(maxWidth: px(80))
    }
    let maximumOverASmallChild = try widthInRow(authority: .legacy) { log in
        Mark("child", log: log, width: 20, height: 20).frame(maxWidth: px(80))
    }
    try #require(minimum != maximumOverASmallChild,
                 "the instrument cannot see the bounds: \(minimum) and \(maximumOverASmallChild)")

    #expect(minimum == 40, "minWidth 40 over a 20pt child (SwiftUI D7 = 40): \(minimum)")
    #expect(maximumOverALargeChild == 80,
            "maxWidth 80 over a 200pt child (SwiftUI D14 = 80): \(maximumOverALargeChild)")
    #expect(maximumOverASmallChild == 20,
            "maxWidth 80 over a 20pt child — SwiftUI's D4 reads 80, FR-E: \(maximumOverASmallChild)")
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
/// Pinned to the legacy authority by stage 6a (CE+RP, record §30 §4).
@Test @MainActor func chainedLegacyFramesAgreeWithSwiftUIsOrderingRules() throws {
    let innerWide = try render(authority: .legacy) { log in
        Row {
            Mark("leaf", log: log, width: 20, height: 20).frame(width: px(100)).frame(width: px(50))
            Mark("sibling", log: log, width: 5, height: 5)
        }.alignItems(.flexStart)
    }
    let outerWide = try render(authority: .legacy) { log in
        Row {
            Mark("leaf", log: log, width: 20, height: 20).frame(width: px(50)).frame(width: px(100))
            Mark("sibling", log: log, width: 5, height: 5)
        }.alignItems(.flexStart)
    }
    let innerLeafX = Origin(try #require(innerWide.bounds["leaf"])).x
    let outerLeafX = Origin(try #require(outerWide.bounds["leaf"])).x
    try #require(innerLeafX != outerLeafX,
                 "the instrument cannot see chain order: \(innerLeafX) and \(outerLeafX)")

    #expect(Origin(try #require(innerWide.bounds["sibling"])).x == 50, "E1's outer width")
    #expect(innerLeafX == 15, "E1's leaf")
    #expect(Origin(try #require(outerWide.bounds["sibling"])).x == 100, "E2's outer width")
    #expect(outerLeafX == 40, "E2's leaf")

    let aligned = try render(authority: .legacy) { log in
        Row {
            Mark("leaf", log: log, width: 20, height: 20)
                .frame(width: px(60), height: px(40))
                .frame(width: px(120), height: px(100), alignment: .topLeading)
            Mark("sibling", log: log, width: 5, height: 5)
        }.alignItems(.flexStart)
    }
    #expect(Origin(try #require(aligned.bounds["sibling"])).x == 120, "E6's outer width")
    #expect(Origin(try #require(aligned.bounds["leaf"])) == Origin(20, 10), "E6's leaf")
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
/// Pinned to the legacy authority by stage 6a (CE+RP, record §30 §4).
@Test @MainActor func aLegacyFrameProposesItsWidthToAMeasuredLeaf() throws {
    let framed = try render(authority: .legacy) { log in
        Column {
            Text("alpha bravo charlie delta").font(size: 12).frame(width: px(60))
            Mark("marker", log: log, width: 5, height: 5)
        }
    }
    let bare = try render(authority: .legacy) { log in
        Column {
            Text("alpha bravo charlie delta").font(size: 12)
            Mark("marker", log: log, width: 5, height: 5)
        }
    }
    let framedY = Origin(try #require(framed.bounds["marker"])).y
    let bareY = Origin(try #require(bare.bounds["marker"])).y
    try #require(framedY != bareY, "the frame's width never reached the leaf: \(framedY), \(bareY)")

    #expect(framedY == 60, "four wrapped 15pt lines: \(framedY)")
    #expect(bareY == 15, "one unwrapped line: \(bareY)")
}

// MARK: - 2.7 a frame around a `List` still builds every row

/// **A legacy frame around a `List` builds exactly the rows the unframed list
/// builds** — the "it broke list virtualization" half of the same reverted
/// conversion, refuted (scratch `L12`).
///
/// **Forty 40pt rows in a 600pt viewport**, so the window is genuinely
/// windowing — 1600pt of content against 600pt of viewport — and the
/// observable is the SET of row indices built, not a count that every arm
/// would reach anyway. The framed spelling must build the same set as the
/// unframed one and as `.width(200)`, which writes the element's own box
/// instead of wrapping it.
///
/// **No mutation of `FrameSpec.style()` can move the row SET, and that is a
/// measured property of the engine rather than a weak test.** The designed
/// mutation (critic finding 16) — a fixed `size.height` of 40 on the frame
/// layer — was run over the whole suite and left this test green even against a
/// real window: `List` computes its window against the enclosing **scroller's**
/// origin and viewport, ignoring where the list itself sits (CLAUDE.md
/// divergence 14), so geometry the layer imposes cannot reach the window at
/// all. The two frames below are still required — frame 0 has no measured
/// viewport and builds every row (MP-I) — but the window is insensitive to the
/// wrapper by construction.
///
/// So the test also pins the rows' WIDTH, and measuring it turned up something
/// worth keeping: **`.frame(width: 200)` around a `List` does NOT narrow its
/// rows, where `.width(200)` does.** With 400pt rows the three arms read 400
/// (unframed), **200** (`.width(200)`, which writes the list's own box) and
/// **400** (framed). The frame layer is 200 wide and the list overflows it:
/// flex §4.5's automatic minimum floors the list at its rows' own min-content
/// width, and a wrapper cannot reach into its child to cancel that — the same
/// mechanism ruling `FR-G` measured for `.minHeight(0)`, seen from the other
/// side. It is the sharpest available statement of "these two sizing
/// vocabularies are not the same operation" (`FR-F`).
///
/// **This test's only mutation is therefore a non-localized one** — dropping
/// the layer's child list in `ModifiedElement.requestLayout`, which reddens
/// most of the suite. It is recorded in the lane's mutation table rather than
/// claimed as this test's own, and the honest summary is that the test is a
/// characterization the lowering cannot move.
///
/// Pinned to the legacy authority by stage 6a (CSS-frame, record §30 §4).
@Test @MainActor func aLegacyFrameAroundAListStillBuildsEveryRow() throws {
    struct Datum: Identifiable { let id: String }
    let data = (0..<40).map { Datum(id: "row-\($0)") }

    // TWO frames, sharing one `StateTable`. Frame 0 has no measured viewport
    // and builds every row (MP-I), so only the second frame is windowed and
    // only the second frame's rows are the observable.
    // `-1` for "row 0 was never built": a `#require` inside a nested function
    // expands without a throwing call and costs a `warning:` against the hard
    // 0-warning gate, and every assertion below names a real width, so the
    // sentinel cannot pass for one.
    func rowsBuilt<Wrapped: Element>(_ wrap: @escaping (List<[Datum], Mark>) -> Wrapped)
        -> (rows: [Int], width: Float) {
        let log = SizeLog()
        var root = ScrollView {
            wrap(List(data, rowHeight: px(40)) { Mark($0.id, log: log, width: 400, height: 20) })
        }
        let size = Size(width: px(400), height: px(600))
        let table = StateTable()
        Frame(contentSize: size, scaleFactor: 1, stateTable: table, layoutAuthority: .legacy).render(&root)
        log.bounds.removeAll()
        Frame(contentSize: size, scaleFactor: 1, stateTable: table, layoutAuthority: .legacy).render(&root)
        let rows = log.bounds.keys
            .compactMap { $0.hasPrefix("row-") ? Int($0.dropFirst(4)) : nil }
            .sorted()
        return (rows, log.bounds["row-0"]?.size.width.value ?? -1)
    }

    let bare = rowsBuilt { $0 }
    let styled = rowsBuilt { $0.width(px(200)) }
    let framed = rowsBuilt { $0.frame(width: px(200)) }
    try #require(bare.rows.isEmpty == false, "the unframed list built no rows at all")
    try #require(bare.width != styled.width,
                 "the instrument cannot see a row's width: \(bare.width), \(styled.width)")

    #expect(styled.rows == bare.rows, "`.width(200)` built \(styled.rows) against \(bare.rows)")
    #expect(framed.rows == bare.rows, "`.frame(width: 200)` built \(framed.rows) against \(bare.rows)")
    #expect(bare.width == 400 && styled.width == 200 && framed.width == 400,
            """
            a framed list keeps its rows' own width where `.width(200)` narrows them: \
            bare \(bare.width), styled \(styled.width), framed \(framed.width)
            """)
}

// MARK: - 5.1 a single-child frame overflows (ruling CN-N, closing FR-N)

/// Two legacy marks as ONE component, so a frame around it wraps two nodes —
/// the case `CN-N` keeps on `FR-C`'s flex-row lowering.
private struct TwoMarks: Component {
    let log: SizeLog
    var content: some ElementGroup {
        Mark("child", log: log, width: 200, height: 160)
        Mark("second", log: log, width: 10, height: 10)
    }
}

/// **A child bigger than its single-child legacy frame keeps its size and
/// overflows BOTH axes, placed by the frame's alignment** — ruling `CN-N`,
/// which closes `FR-N` (this test replaces
/// `aLegacyFrameSqueezesAnOversizedChildWhereSwiftUIOverflows`).
///
/// SwiftUI, `docs/probes/swiftui-frame-semantics.swift` (re-run 2026-09-16,
/// output identical on these arms): `A5`, a 200×160 child in
/// `.frame(width: 60, height: 40)`, is placed at **(−70, −60) 200×160** relative
/// to the frame; `B9`, the same with `.topLeading`, at **(0, 0) 200×160**.
///
/// Here the frame is a flex item of a 300×200 `Row`, so it sits at (0, 80) and
/// the expected rects are the probe's plus that origin: centred (−70, 20),
/// top-leading (0, 80). The second arm puts `flexShrink(0)` on the LAYER and
/// must read the same (the old test's separation of "the layer shrank" from
/// "the child was shrunk").
///
/// **The control is the other half of the ruling**: the same oversized mark
/// framed together with a 10×10 sibling inside one component — two nodes —
/// keeps the flex row and is still squeezed (to 57, CSS shrink by base size), as
/// `FR-N` read. It is `#require`d to disagree with the single-child arm.
///
/// **The frame as an inner layer** — the lowering is made per layer, so a
/// frame under a `.padding(4)` (child at (−66, 20): the frame sits at (4, 80))
/// and under a second 80×60 frame (child at (−60, 20): the inner frame sits at
/// (10, 80)) overflow the same way. These two arms were added after the lane:
/// the mutation "lower only the outermost layer" left the suite green.
///
/// **The flexible overload lowers too** (`CN-N` covers both `.frame` overloads):
/// the probe's `D13`, `.frame(minWidth: 40, maxWidth: 80)`, and `D14`,
/// `.frame(maxWidth: 80)`, each around a 200×160 child (re-run 2026-09-16,
/// output identical), answer 80×160 and place the child at **(−60, 0)**. In the
/// `Row` each frame sits at (0, 20), so the child reads (−60, 20) 200×160.
/// Before the lane these two arms read the child squeezed to the frame's 80.
/// These arms were added in lane 5's fix round: making the flexible overload
/// pass `isFrame: false` (verifier mutation V1; spelled `frameSpec: nil` since
/// plan task 7's lane 4 made `isFrame` computed) left the suite green.
///
/// Before the lane the single-child arm reads (0, 20) 60×160 (`FR-N`).
/// Mutations, measured (record §17, lane 5): lower single-child frames as a
/// flex row again (the single-child arms redden, and
/// `aFrameLayersClipAndBorderBoundTheChildTheFrameCannotShrink`); lower every
/// frame layer as a stack (the control's `#require` fails, and three
/// component-frame tests redden); lower only the outermost layer (the two
/// inner-layer arms redden).
///
/// Pinned to the legacy authority by stage 6a (CSS-frame, record §30 §4).
@Test @MainActor func aSingleChildLegacyFrameOverflowsAnOversizedChildOnBothAxes() throws {
    let plain = try render(authority: .legacy) { log in
        Row {
            Mark("child", log: log, width: 200, height: 160).frame(width: px(60), height: px(40))
        }
    }
    let pinned = try render(authority: .legacy) { log in
        Row {
            Mark("child", log: log, width: 200, height: 160)
                .frame(width: px(60), height: px(40))
                .flexShrink(0)
        }
    }
    let topLeading = try render(authority: .legacy) { log in
        Row {
            Mark("child", log: log, width: 200, height: 160)
                .frame(width: px(60), height: px(40), alignment: .topLeading)
        }
    }
    // The frame as an INNER layer: under a padding, and under a second frame.
    let padded = try render(authority: .legacy) { log in
        Row {
            Mark("child", log: log, width: 200, height: 160)
                .frame(width: px(60), height: px(40))
                .padding(4)
        }
    }
    let framedTwice = try render(authority: .legacy) { log in
        Row {
            Mark("child", log: log, width: 200, height: 160)
                .frame(width: px(60), height: px(40))
                .frame(width: px(80), height: px(60))
        }
    }
    let twoNodes = try render(authority: .legacy) { log in
        Row {
            TwoMarks(log: log).frame(width: px(60), height: px(40))
        }
    }
    // The FLEXIBLE overload, probe arms D13 and D14.
    let minMax = try render(authority: .legacy) { log in
        Row {
            Mark("child", log: log, width: 200, height: 160).frame(minWidth: px(40), maxWidth: px(80))
        }
    }
    let maxOnly = try render(authority: .legacy) { log in
        Row {
            Mark("child", log: log, width: 200, height: 160).frame(maxWidth: px(80))
        }
    }

    let single = Rect(try #require(plain.bounds["child"]))
    let squeezed = Rect(try #require(twoNodes.bounds["child"]))
    try #require(single != squeezed,
                 "the single-child and two-node frames placed the child alike: \(single), \(squeezed)")

    #expect(single == Rect(-70, 20, 200, 160), "A5 (-70, -60) from the frame at (0, 80): \(single)")
    #expect(Rect(try #require(pinned.bounds["child"])) == Rect(-70, 20, 200, 160),
            "flexShrink(0) on the layer changes nothing")
    #expect(Rect(try #require(topLeading.bounds["child"])) == Rect(0, 80, 200, 160),
            "B9 (0, 0) from the frame at (0, 80)")
    #expect(Rect(try #require(padded.bounds["child"])) == Rect(-66, 20, 200, 160),
            "an inner frame layer lowers too: the frame at (4, 80) under a 4pt padding")
    #expect(Rect(try #require(framedTwice.bounds["child"])) == Rect(-60, 20, 200, 160),
            "an inner frame under an outer 80x60 frame: the inner frame at (10, 80)")
    #expect(Rect(try #require(minMax.bounds["child"])) == Rect(-60, 20, 200, 160),
            "D13 (-60, 0) from the flexible frame at (0, 20)")
    #expect(Rect(try #require(maxOnly.bounds["child"])) == Rect(-60, 20, 200, 160),
            "D14 (-60, 0) from the flexible frame at (0, 20)")
    #expect(squeezed.width == 57 && squeezed.height == 160,
            "a frame over two nodes keeps FR-C's flex row and squeezes the child: \(squeezed)")
}

// MARK: - 5.8 a single-child frame ignores its child's flex item fields (ruling CN-N)

/// A growing mark and a stretching mark, each beside a 10×10 mark, as ONE
/// component: a frame around it wraps two nodes and keeps `FR-C`'s flex row —
/// the control for test 5.8.
private struct GrowingPair: Component {
    let log: SizeLog
    var content: some ElementGroup {
        Mark("grow", log: log, height: 20).flexGrow(1)
        Mark("second", log: log, width: 10, height: 10)
    }
}

private struct StretchingPair: Component {
    let log: SizeLog
    var content: some ElementGroup {
        Mark("stretch", log: log, width: 20).alignSelf(.stretch)
        Mark("second", log: log, width: 10, height: 10)
    }
}

/// **The only child of a legacy `.frame` loses its `.flexGrow` and
/// `.alignSelf`** — ruling `CN-N`'s cost, pinned as it stands (lane 5 fix
/// round; no SwiftUI claim: neither field has a SwiftUI spelling). A frame over
/// exactly one node is a one-cell `display: .stack`, and a stack reads neither
/// item field, so both compile and do nothing — including the fill idiom
/// `.flexGrow(1).frame(maxWidth: .infinity, maxHeight: .infinity)`.
///
/// Arms, in a 300×200 `Frame`:
///
/// - **grow**: `Row { mark(h 20).flexGrow(1).frame(width: 100, height: 40) }` —
///   the frame sits at (0, 80), and the width-less mark centred in it at
///   (50, 90) 0×20 (before the lane (0, 90) 100×20);
/// - **fill** at the root: `mark(h 20).flexGrow(1).frame(maxWidth: .infinity,
///   maxHeight: .infinity)` — (150, 90) 0×20 (before, (0, 90) 300×20);
/// - **stretch**: `mark(w 20).alignSelf(.stretch).frame(width: 100, height:
///   40)` — (40, 100) 20×0 (before, (40, 80) 20×40).
///
/// **Controls** (`#require`d to disagree with the pins): the same marks framed
/// together with a 10×10 sibling in one component — two nodes, the flex row —
/// still grow to 90 wide and stretch to 40 high.
///
/// **The workaround is `width(fraction: 1)`** (and `height(fraction: 1)`): the
/// stack offers its content box as the containing block, so the grow arm
/// respelled reads (0, 90) 100×20 and the fill arm (0, 90) 300×20.
///
/// Mutations, measured (record §17, lane 5 fix round): the fixed overload
/// passes `isFrame: false` (the stretch control's `#require` fails — the
/// restored row stretches both — so the test stops there; 5.1's six fixed arms
/// redden too); the flexible overload passes `isFrame: false` (the fill pin
/// reddens, with 5.1's `D13`/`D14` arms; the fill workaround does not, since the
/// row fills a `width(fraction: 1)` child too). `isFrame: false` is spelled
/// `frameSpec: nil` since plan task 7's lane 4 (`isFrame` is computed from it).
///
/// Pinned to the legacy authority by stage 6a (CSS-frame, record §30 §4).
@Test @MainActor func aSingleChildLegacyFrameIgnoresItsChildsFlexGrowAndAlignSelf() throws {
    let grow = try render(authority: .legacy) { log in
        Row { Mark("grow", log: log, height: 20).flexGrow(1).frame(width: px(100), height: px(40)) }
    }
    let fill = try render(authority: .legacy) { log in
        Mark("grow", log: log, height: 20).flexGrow(1)
            .frame(maxWidth: px(.infinity), maxHeight: px(.infinity))
    }
    let stretch = try render(authority: .legacy) { log in
        Row { Mark("stretch", log: log, width: 20).alignSelf(.stretch).frame(width: px(100), height: px(40)) }
    }
    let growPair = try render(authority: .legacy) { log in
        Row { GrowingPair(log: log).frame(width: px(100), height: px(40)) }
    }
    let stretchPair = try render(authority: .legacy) { log in
        Row { StretchingPair(log: log).frame(width: px(100), height: px(40)) }
    }
    let growWorkaround = try render(authority: .legacy) { log in
        Row { Mark("grow", log: log, height: 20).width(fraction: 1).frame(width: px(100), height: px(40)) }
    }
    let fillWorkaround = try render(authority: .legacy) { log in
        Mark("grow", log: log, height: 20).width(fraction: 1)
            .frame(maxWidth: px(.infinity), maxHeight: px(.infinity))
    }

    let grown = Rect(try #require(growPair.bounds["grow"]))
    let stretched = Rect(try #require(stretchPair.bounds["stretch"]))
    let pinnedGrow = Rect(try #require(grow.bounds["grow"]))
    let pinnedStretch = Rect(try #require(stretch.bounds["stretch"]))
    try #require(grown.width != pinnedGrow.width,
                 "the two-node control and the single-child pin agree on width: \(grown), \(pinnedGrow)")
    try #require(stretched.height != pinnedStretch.height,
                 "the two-node control and the single-child pin agree on height: \(stretched), \(pinnedStretch)")

    #expect(grown.width == 90, "control: flexGrow in a two-node frame's row takes the rest: \(grown)")
    #expect(stretched.height == 40, "control: alignSelf(.stretch) in a two-node frame's row: \(stretched)")
    #expect(pinnedGrow == Rect(50, 90, 0, 20), "flexGrow on a single-child frame's child is inert: \(pinnedGrow)")
    #expect(Rect(try #require(fill.bounds["grow"])) == Rect(150, 90, 0, 20),
            "the fill idiom's flexGrow is inert under a single-child flexible frame")
    #expect(pinnedStretch == Rect(40, 100, 20, 0),
            "alignSelf(.stretch) on a single-child frame's child is inert: \(pinnedStretch)")
    #expect(Rect(try #require(growWorkaround.bounds["grow"])) == Rect(0, 90, 100, 20),
            "the workaround, width(fraction: 1), fills the frame")
    #expect(Rect(try #require(fillWorkaround.bounds["grow"])) == Rect(0, 90, 300, 20),
            "the workaround fills the root flexible frame")
}

// MARK: - 5.9 `hidden()` after a single-child frame still hides (ruling CN-N, closeout)

/// **`hidden()` written after a one-node legacy frame hides the element** —
/// the regression the branch checker found in `CN-N`'s lowering (record §17,
/// "Branch checker"; fixed in its "Closeout"). `ModifierLayer.lowered(_:childCount:)`
/// wrote `display = .stack` over whatever the frame layer held, so the
/// `display: .none` that `hidden()` — a `Self`-returning modifier, which
/// configures the layer it follows — had written was overwritten and the
/// element took its frame's space again. No SwiftUI claim: this is MetalUI's own
/// `hidden()` keeping the meaning it had at `9e439cb`.
///
/// Instrument: `widthInRow`, the x of a 5pt sibling after a 20×20 mark's chain
/// in a 300pt `Row` (the checker's scratch instrument). Each row read at
/// `9e439cb` (a `git archive` build: rows 1–5 by the checker, 6–7 by the
/// closeout), at `b442c9e` (red run, before the fix) and required now:
///
/// | chain on the mark | `9e439cb` | `b442c9e` | now |
/// |---|---|---|---|
/// | 1 `.hidden()` (control) | 0 | 0 | 0 |
/// | 2 `.frame(width: 40, height: 40)` (control) | 40 | 40 | 40 |
/// | 3 `.frame(width: 40, height: 40).hidden()` | 0 | **40** | 0 |
/// | 4 `.frame(width: 40, height: 40).padding(4).hidden()` (control) | 0 | 0 | 0 |
/// | 5 `.frame(minWidth: 40, maxWidth: 80).hidden()` | 0 | **40** | 0 |
/// | 6 `.frame(width: 40, height: 40).hidden().padding(4)` | 8 | **48** | 8 |
/// | 7 `.frame(minWidth: 40, maxWidth: 80).hidden().padding(4)` | 8 | **48** | 8 |
///
/// Row 4 was never broken: its hidden layer is the padding, not a frame. Rows 6
/// and 7 hide the frame as an INNER layer, which `requestLayout` lowers too; 8 is
/// the padding's two insets around a filtered frame. Controls 1 and 2 are
/// `#require`d to disagree.
///
/// Red at `b442c9e`: rows 3, 5, 6, 7 (4 issues). Mutation, after the fix
/// (`lowered` ignoring `.none` again): this test's same 4 issues and
/// `aHiddenOneNodeFrameLayerPublishesNothingToAnAccessibilityClient` (record §17,
/// "Closeout").
///
/// Pinned to the legacy authority by stage 6a (CE+RP, record §30 §4).
@Test @MainActor func hiddenAfterASingleChildLegacyFrameStillHidesTheElement() throws {
    let rows: [(chain: String, expected: Float, measure: () throws -> Float)] = [
        ("hidden()", 0, {
            try widthInRow(authority: .legacy) { Mark("mark", log: $0, width: 20, height: 20).hidden() }
        }),
        ("frame(width: 40, height: 40)", 40, {
            try widthInRow(authority: .legacy) { Mark("mark", log: $0, width: 20, height: 20).frame(width: px(40), height: px(40)) }
        }),
        ("frame(width: 40, height: 40).hidden()", 0, {
            try widthInRow(authority: .legacy) {
                Mark("mark", log: $0, width: 20, height: 20).frame(width: px(40), height: px(40)).hidden()
            }
        }),
        ("frame(width: 40, height: 40).padding(4).hidden()", 0, {
            try widthInRow(authority: .legacy) {
                Mark("mark", log: $0, width: 20, height: 20).frame(width: px(40), height: px(40))
                    .padding(4).hidden()
            }
        }),
        ("frame(minWidth: 40, maxWidth: 80).hidden()", 0, {
            try widthInRow(authority: .legacy) {
                Mark("mark", log: $0, width: 20, height: 20).frame(minWidth: px(40), maxWidth: px(80)).hidden()
            }
        }),
        ("frame(width: 40, height: 40).hidden().padding(4)", 8, {
            try widthInRow(authority: .legacy) {
                Mark("mark", log: $0, width: 20, height: 20).frame(width: px(40), height: px(40))
                    .hidden().padding(4)
            }
        }),
        ("frame(minWidth: 40, maxWidth: 80).hidden().padding(4)", 8, {
            try widthInRow(authority: .legacy) {
                Mark("mark", log: $0, width: 20, height: 20).frame(minWidth: px(40), maxWidth: px(80))
                    .hidden().padding(4)
            }
        }),
    ]
    let measured = try rows.map { try $0.measure() }
    try #require(measured.count == 7)
    try #require(measured[0] != measured[1],
                 "the hidden control and the visible frame control agree: \(measured[0]), \(measured[1])")
    for (row, x) in zip(rows, measured) {
        #expect(x == row.expected, "mark.\(row.chain): the sibling sits at \(x), expected \(row.expected)")
    }
}

// MARK: - 2.9 an infinite maximum (ruling FR-O)

/// **An infinite maximum fills only when BOTH axes are infinite** (ruling
/// `FR-O`).
///
/// `flexGrow = 1` fills the parent's **main** axis and `alignSelf = .stretch`
/// fills its **cross** axis, so setting both is correct whichever way the
/// parent runs — the centred arm reads (140, 90) in a `Row` and in a `Column`
/// alike (scratch `N14`). A **single** infinite maximum lowers to nothing: the
/// same lowering applied to one axis consumes a whole axis nobody asked for
/// (scratch `N15`: a `Column` sibling pushed from y = 20 to y = 195), and the
/// layer a caller gets instead is **present and inert** — one more node,
/// identical geometry. That is a declared-but-inert row CLAUDE.md owes at
/// integration, and the fix needs the parent's axis (plan task 6).
///
/// **The two `.topLeading` arms are here because a centred mark cannot see the
/// cross axis, and a mutation proved it**: dropping `alignSelf = .stretch` left
/// the whole suite green, because a mark centred in a 20pt-tall layer at y = 90
/// and a mark centred in a 200pt-tall layer at y = 0 sit at the same y. Pinned
/// to the layer's leading corner the two disagree — (0, 0) filled, (0, 90) in a
/// `Row` with no stretch and (140, 0) in a `Column` with no stretch.
///
/// Mutations: drop `alignSelf = .stretch` (both `.topLeading` arms redden);
/// drop `flexGrow = 1` (the two centred arms redden, at the opening
/// `#require`); extend the fill lowering to a single infinite maximum (the
/// inert arm reddens, at the same `#require`).
///
/// Pinned to the legacy authority by stage 6a (CSS-frame, record §30 §4).
@Test @MainActor func anInfiniteMaximumFillsOnlyWhenBothAxesAreInfinite() throws {
    func mark(_ parentIsRow: Bool, _ alignment: ProposalAlignment) throws -> Origin {
        let log = parentIsRow
            ? try render(authority: .legacy) { log in
                Row {
                    Mark("mark", log: log, width: 20, height: 20)
                        .frame(maxWidth: px(.infinity), maxHeight: px(.infinity),
                               alignment: alignment)
                }
              }
            : try render(authority: .legacy) { log in
                Column {
                    Mark("mark", log: log, width: 20, height: 20)
                        .frame(maxWidth: px(.infinity), maxHeight: px(.infinity),
                               alignment: alignment)
                }
              }
        return Origin(try #require(log.bounds["mark"]))
    }

    let inert = try render(authority: .legacy) { log in
        Row {
            Mark("mark", log: log, width: 20, height: 20).frame(maxWidth: px(.infinity))
        }
    }
    let bare = try render(authority: .legacy) { log in
        Row { Mark("mark", log: log, width: 20, height: 20) }
    }

    let filledOrigin = try mark(true, .center)
    let inertOrigin = Origin(try #require(inert.bounds["mark"]))
    try #require(filledOrigin != inertOrigin,
                 "both spellings placed the mark alike: \(filledOrigin), \(inertOrigin)")

    #expect(filledOrigin == Origin(140, 90), "a Row parent, centred: \(filledOrigin)")
    #expect(try mark(false, .center) == Origin(140, 90), "a Column parent fills the same way")
    #expect(try mark(true, .topLeading) == Origin(0, 0),
            "a Row parent: the layer must fill the CROSS axis too")
    #expect(try mark(false, .topLeading) == Origin(0, 0),
            "a Column parent: the layer must fill the CROSS axis too")
    #expect(inertOrigin == Origin(try #require(bare.bounds["mark"])),
            "a single infinite maximum must place the mark where no frame does")

    let inertNodes = try nodeCount(authority: .legacy) { log in
        Row { Mark("mark", log: log, width: 20, height: 20).frame(maxWidth: px(.infinity)) }
    }
    let bareNodes = try nodeCount(authority: .legacy) { log in
        Row { Mark("mark", log: log, width: 20, height: 20) }
    }
    #expect(inertNodes == bareNodes + 1,
            "the inert layer must still cost its node: \(inertNodes) against \(bareNodes)")
}

/// The tree's node count after one rendered frame — how test 2.9 shows that an
/// inert layer is present rather than absent.
@MainActor
private func nodeCount<Root: Element>(authority: LayoutAuthority, _ make: (SizeLog) -> Root) throws -> Int {
    let log = SizeLog()
    var root = make(log)
    let frame = Frame(contentSize: Size(width: px(300), height: px(200)), scaleFactor: 1,
                      layoutAuthority: authority)
    frame.render(&root)
    return frame.tree.nodeCount
}

// MARK: - 2.10 a single fixed axis pins only itself (ruling FR-P)

/// **A single-axis fixed frame does not pin the axis it did not declare** —
/// ruling `FR-P`, the reason the lowering is an axis-named `minSize` rather
/// than `flexShrink = 0`.
///
/// `Style.flexShrink` is one scalar governing the parent's **main** axis, so
/// `.frame(height: 40)` inside a `Row` would pin the layer's WIDTH — a
/// dimension the caller never declared. Here a `.frame(height: 40)` around a
/// wrapping `Text`, in an over-constrained 300pt `Row` with a 200pt sibling
/// whose x reads the layer's width, must read exactly what the unframed
/// spelling reads; under `flexShrink = 0` it reads the text's full unwrapped
/// width instead (scratch `N11` read 154 against 210 on its own string).
///
/// Mutation: replace the axis-named pin with `flexShrink = 0` on any fixed
/// axis. This test reddens where 2.2 does not, which is the whole finding.
///
/// Pinned to the legacy authority by stage 6a (CSS-frame, record §30 §4).
/// `FR-P` is a choice inside the legacy `FrameSpec.style()`, which the
/// proposal authority never reads: run under `.proposal` (as lane 3 first
/// spelled it) the mutation above left the whole suite green (record §30
/// §10.7, VA). It is green under the flipped default, so it is the one lane-3
/// P test that M3g cannot see; the mutation is its pin.
@Test @MainActor func aSingleAxisFixedFrameDoesNotPinTheAxisItDidNotDeclare() throws {
    let framed = try widthInRow(authority: .legacy, siblingWidth: 200) { _ in
        Text("alpha bravo charlie delta").font(size: 12).frame(height: px(40))
    }
    let bare = try widthInRow(authority: .legacy, siblingWidth: 200) { _ in
        Text("alpha bravo charlie delta").font(size: 12)
    }
    let unconstrained = try widthInRow(authority: .legacy, rowWidth: 1000, siblingWidth: 200) { _ in
        Text("alpha bravo charlie delta").font(size: 12)
    }
    try #require(framed < unconstrained,
                 "the row is not over-constrained, so no pin could matter: \(framed), \(unconstrained)")

    #expect(framed == bare,
            "a declared height must not pin the width: framed \(framed), unframed \(bare)")
}

// MARK: - Lane 3, the sizing inventory (rulings FR-F, FR-G, FR-H, FR-T)
//
// Lane 3 is a documentation lane: its source change is `Box.swift`'s
// `MARK: Size` comments. These two tests are what make that documentation
// falsifiable — every sentence added there names one of them.
//
// (3.1 was replaced by plan task 6's 5.2, when ruling `CN-O` renamed the
// `percent:` modifiers `fraction:`.)
//
// Both are **characterizations**: they were green the moment they compiled,
// because they describe shipped behaviour rather than new behaviour. Their
// proof is therefore entirely in their mutations, which are named in each doc
// comment and measured in `docs/record/14-frame-and-sizing.md`.

/// Calls the deprecated `percent:` spellings without a deprecation warning at
/// the call site (the suite's 0-warning gate): a deprecated witness reached
/// through a generic requirement is not diagnosed.
@MainActor
private protocol DeprecatedPercentSpellings {
    func viaWidthPercent(_ value: Float) -> Self
    func viaHeightPercent(_ value: Float) -> Self
    func viaFlexBasisPercent(_ value: Float) -> Self
}

extension Mark: DeprecatedPercentSpellings {
    @available(*, deprecated)
    func viaWidthPercent(_ value: Float) -> Mark { width(percent: value) }
    @available(*, deprecated)
    func viaHeightPercent(_ value: Float) -> Mark { height(percent: value) }
    @available(*, deprecated)
    func viaFlexBasisPercent(_ value: Float) -> Mark { flexBasis(percent: value) }
}

@MainActor private func widthPercent<T: DeprecatedPercentSpellings>(_ t: T, _ v: Float) -> T { t.viaWidthPercent(v) }
@MainActor private func heightPercent<T: DeprecatedPercentSpellings>(_ t: T, _ v: Float) -> T { t.viaHeightPercent(v) }
@MainActor private func flexBasisPercent<T: DeprecatedPercentSpellings>(_ t: T, _ v: Float) -> T { t.viaFlexBasisPercent(v) }

// MARK: - 5.2 fractional sizing (rulings FR-H, FR-T, CN-O)

/// **`width(fraction:)`, `height(fraction:)` and `flexBasis(fraction:)` take a
/// fraction of the containing block, as their names now say** — ruling `CN-O`,
/// which renames `FR-T`'s misnamed `percent:` modifiers (still present,
/// deprecated, meaning unchanged; guard G4 counts their deprecations). This
/// test replaces `aPercentageSizeTakesAFractionAndResolvesAgainstItsContainingBlock`.
/// No SwiftUI claim: SwiftUI has no fractional sizing (`FR-H` keeps it as a
/// MetalUI divergence; its nearest, `containerRelativeFrame`, resolves against
/// a named container rather than a containing block).
///
/// `FR-T`'s arms, respelled:
///
/// - **A**, 0.5 in a 300pt `Row`, read as the x of a 5pt sibling: 150;
/// - **B**, the same element as the ROOT: (0, 0) 150×20 (`SZ-A`);
/// - **C**, 0.5 centred on a 300pt `Column`'s cross axis: x 75;
/// - **D**, `height(fraction: 0.5)` against the `Column`'s 200pt height: 100;
/// - **E**, `flexBasis(fraction: 0.5)` in the 300pt `Row`: 150.
///
/// - **F**, the deprecated `width`/`height`/`flexBasis(percent: 0.5)`, reached
///   through a generic shim so the call sites raise no deprecation warning,
///   must equal A, D and E (lane 5 fix round: making `width(percent:)` forward
///   `fraction: percent * 100`, verifier mutation V8, left the suite green).
///
/// The control is 0.25 in the same `Row` (75), `#require`d to disagree with A.
///
/// Before the lane the API is missing. Mutation: make `fraction:` write
/// `.percent(fraction * 100)` (A, B, C, D, E move to 15000-scale widths).
///
/// Pinned to the legacy authority by stage 6a (CSS-frame, record §30 §4).
@Test @MainActor func aFractionSizeResolvesAgainstItsContainingBlock() throws {
    let half = try widthInRow(authority: .legacy) { log in
        Mark("a", log: log, height: 20).width(fraction: 0.5)
    }
    let quarter = try widthInRow(authority: .legacy) { log in
        Mark("a", log: log, height: 20).width(fraction: 0.25)
    }
    try #require(half != quarter, "0.5 and 0.25 agreed, so nothing here can see the fraction: \(half)")

    let atRoot = try render(authority: .legacy) { log in
        Mark("a", log: log, height: 20).width(fraction: 0.5)
    }
    let halfInColumn = try render(authority: .legacy) { log in
        Column { Mark("a", log: log, height: 20).width(fraction: 0.5) }
    }
    let halfHigh = try render(authority: .legacy) { log in
        Column { Mark("a", log: log, width: 20).height(fraction: 0.5) }
    }
    let basis = try widthInRow(authority: .legacy) { log in
        Mark("a", log: log, height: 20).flexBasis(fraction: 0.5)
    }

    #expect(half == 150, "A: 0.5 of a 300pt containing block: \(half)")
    #expect(quarter == 75, "the control: 0.25 of it: \(quarter)")
    #expect(Rect(try #require(atRoot.bounds["a"])) == Rect(0, 0, 150, 20),
            "B: the ROOT resolves its fraction against the offered extent too (SZ-A)")
    #expect(Rect(try #require(halfInColumn.bounds["a"])) == Rect(75, 0, 150, 20),
            "C: the same fraction, centred on a Column's cross axis")
    #expect(Rect(try #require(halfHigh.bounds["a"])) == Rect(140, 0, 20, 100),
            "D: `height(fraction:)` resolves against the containing block's HEIGHT")
    #expect(basis == 150, "E: `flexBasis(fraction:)` against the Row's main axis: \(basis)")

    // F: the deprecated `percent:` spellings keep their meaning (CN-O): each
    // resolves exactly as its `fraction:` rename does at 0.5.
    let percentWidth = try widthInRow(authority: .legacy) { log in widthPercent(Mark("a", log: log, height: 20), 0.5) }
    let percentHigh = try render(authority: .legacy) { log in
        Column { heightPercent(Mark("a", log: log, width: 20), 0.5) }
    }
    let percentBasis = try widthInRow(authority: .legacy) { log in flexBasisPercent(Mark("a", log: log, height: 20), 0.5) }
    #expect(percentWidth == half, "F: width(percent: 0.5) must equal width(fraction: 0.5): \(percentWidth)")
    #expect(Rect(try #require(percentHigh.bounds["a"])) == Rect(try #require(halfHigh.bounds["a"])),
            "F: height(percent: 0.5) must equal height(fraction: 0.5)")
    #expect(percentBasis == basis, "F: flexBasis(percent: 0.5) must equal flexBasis(fraction: 0.5): \(percentBasis)")
}

// MARK: - 3.2 the sizing modifiers write their own box (rulings FR-F, FR-G)

/// **The eight CSS sizing modifiers write THIS element's own box; `.frame(...)`
/// wraps it in a new one** — rulings `FR-F` and `FR-G`, the measurements that
/// keep both refusals honest rather than asserted (practices shape 14).
///
/// **Half one, the node count.** `.width`, `.height`, `.minWidth`, `.maxWidth`,
/// `.minHeight` and `.maxHeight` each leave `tree.nodeCount` exactly where the
/// unmodified element leaves it; `.frame(width:)` adds one. Two vocabularies,
/// two different operations, one observable that cannot be argued with.
///
/// Half one's mutation for the six is `FR-F`'s refusal made executable, and it
/// is a **compile** result rather than a red test: a modifier that returns
/// `Self` cannot add a node, so routing `width(_:)`/`height(_:)` through
/// `frame(width:)`/`frame(height:)` must change their return type, and the
/// package then stops building. Measured this lane: `swift build
/// --build-tests` halts in `MetalUIDemo` at **2** errors (`main.swift:266`'s
/// `-> Box<Text>` helper and `:290`'s `typealias Chrome`), and building
/// `MetalUITests` alone — which skips the demo — reports **70** distinct error
/// sites across six files (`AccessibilityTreeTests` 60,
/// `AccessibilityEndToEndTests` 4, `ModifierTests` 2, `EnvironmentTests` 2,
/// `ProposalNodeIDTests` 1, `AnimationTests` 1). That is why the conversion is
/// deferred to plan task 7 rather than done here.
///
/// The frame arm of half one has an ordinary mutation: make the legacy
/// `frame(width:height:alignment:)` `_wrap` twice, and `framed == bare + 1`
/// reddens (along with seven other tests).
///
/// **Half two, the automatic minimum**, on the demo's own shape
/// (`main.swift:878-881`): a `flexGrow(1)`, `flexBasis(0)` box holding 400pt of
/// content in a 200pt `Column` under an 80pt header. `.minHeight(px(0))` — the
/// demo's own spelling, whose comment says it "replaces the automatic
/// (content-based) minimum" — lets the content shrink into the 120pt left. No
/// `minHeight` keeps flex §4.5's automatic minimum and the content stays 400.
/// **`.frame(minHeight: 0)` reads 400 as well**, with `flexGrow`/`flexBasis` on
/// the layer and on the inner box alike: the layer's `minSize` is the LAYER's
/// minimum, and the element inside keeps its own automatic one. There is no
/// frame spelling of `.minHeight(0)`, which is why `FR-G` keeps the four
/// clamps.
///
/// The two framed arms are pinned **wrong on purpose** in the sense that a
/// reader may wish they read 120; their mutation is the fix (make a frame
/// layer's `minSize` reach into its child), and it is owed to plan task 6, not
/// to a one-line change here. The `.minHeight(px(0))` arm has an ordinary
/// mutation: make `minHeight(_:)` write nothing, and the opening `#require`
/// reddens.
///
/// Pinned to the legacy authority by stage 6a (CSS-frame, record §30 §4).
@Test @MainActor func theSizingModifiersWriteTheirOwnElementsBoxRatherThanWrappingIt() throws {
    let bare = try nodeCount(authority: .legacy) { log in Row { Mark("a", log: log, width: 20, height: 20) } }
    let framed = try nodeCount(authority: .legacy) { log in
        Row { Mark("a", log: log, width: 20, height: 20).frame(width: px(40)) }
    }
    try #require(bare != framed,
                 "`.frame(width:)` added no node, so the instrument cannot see a layer: \(bare)")
    #expect(framed == bare + 1, "a frame is a layer: \(framed) against \(bare)")

    let counts: [(String, Int)] = [
        ("width(_:)",     try nodeCount(authority: .legacy) { log in
            Row { Mark("a", log: log, width: 20, height: 20).width(px(40)) } }),
        ("height(_:)",    try nodeCount(authority: .legacy) { log in
            Row { Mark("a", log: log, width: 20, height: 20).height(px(40)) } }),
        ("minWidth(_:)",  try nodeCount(authority: .legacy) { log in
            Row { Mark("a", log: log, width: 20, height: 20).minWidth(px(40)) } }),
        ("maxWidth(_:)",  try nodeCount(authority: .legacy) { log in
            Row { Mark("a", log: log, width: 20, height: 20).maxWidth(px(40)) } }),
        ("minHeight(_:)", try nodeCount(authority: .legacy) { log in
            Row { Mark("a", log: log, width: 20, height: 20).minHeight(px(40)) } }),
        ("maxHeight(_:)", try nodeCount(authority: .legacy) { log in
            Row { Mark("a", log: log, width: 20, height: 20).maxHeight(px(40)) } }),
    ]
    for (name, count) in counts {
        #expect(count == bare,
                "`\(name)` must write its own box and add no node: \(count) against \(bare)")
    }

    // The demo's shape. `-1` for "the content never prepainted": a `#require`
    // inside a nested function expands without a throwing call and costs a
    // `warning:` against the hard 0-warning gate, and every number asserted
    // below is a real height, so the sentinel cannot pass for one (the same
    // reasoning as test 2.7's).
    func contentHeight<Growing: Element>(_ box: (SizeLog) -> Growing) -> Float {
        let log = SizeLog()
        var root = Column {
            Mark("header", log: log, width: 100, height: 80)
            box(log)
        }
        Frame(contentSize: Size(width: px(300), height: px(200)), scaleFactor: 1, layoutAuthority: .legacy).render(&root)
        return log.bounds["content"]?.size.height.value ?? -1
    }

    let demoSpelling = contentHeight { log in
        Column { Mark("content", log: log, width: 100, height: 400) }
            .flexGrow(1).flexBasis(px(0)).minHeight(px(0))
    }
    let noMinimum = contentHeight { log in
        Column { Mark("content", log: log, width: 100, height: 400) }
            .flexGrow(1).flexBasis(px(0))
    }
    let framedOnLayer = contentHeight { log in
        Column { Mark("content", log: log, width: 100, height: 400) }
            .frame(minHeight: px(0)).flexGrow(1).flexBasis(px(0))
    }
    let framedOnInner = contentHeight { log in
        Column { Mark("content", log: log, width: 100, height: 400) }
            .flexGrow(1).flexBasis(px(0)).frame(minHeight: px(0))
    }

    try #require(demoSpelling != noMinimum,
                 """
                 `.minHeight(0)` changed nothing, so this half cannot see the automatic \
                 minimum at all: \(demoSpelling), \(noMinimum)
                 """)

    #expect(demoSpelling == 120, "`.minHeight(0)` cancels the automatic minimum: \(demoSpelling)")
    #expect(noMinimum == 400, "the automatic minimum floors the content: \(noMinimum)")
    #expect(framedOnLayer == 400,
            "a frame layer's minSize is the LAYER's, with flexGrow on the layer: \(framedOnLayer)")
    #expect(framedOnInner == 400,
            "and with flexGrow on the inner box: \(framedOnInner)")
}


// MARK: - Plan task 6, lane 5: what a single-child legacy frame must keep (ruling CN-N)
//
// `CN-N` lowers a legacy frame layer over exactly one node to a one-cell
// `display: .stack` instead of `FR-C`'s flex row. Its prototype never put an
// absolutely positioned child or a `ScrollView` inside such a frame, so these
// two tests take **today's answers, measured at `8e1dfa7` before the lowering
// changed**, and a moved rect afterwards is a finding (the spec's 5.6 and 5.7).
// Neither makes a SwiftUI claim: SwiftUI has no absolute positioning, and a
// legacy `ScrollView`'s viewport is `CN-P`'s divergence 3.

/// Four `inset` edges in points, `nil` for `.auto`.
private func insets(top: Float?, right: Float?, bottom: Float?, left: Float?) -> Edges<MetalUICore.Dimension> {
    func edge(_ value: Float?) -> MetalUICore.Dimension { value.map { .length(.pixels(px($0))) } ?? .auto }
    return Edges(top: edge(top), right: edge(right), bottom: edge(bottom), left: edge(left))
}

/// **An absolutely positioned child of a single-child legacy frame is placed
/// against its containing block exactly as before the lowering** (5.6).
///
/// Each arm is a 300×200 `Row` of a 30×30 `pad`, the framed 20×20 `abs` and a
/// 10×10 `after` whose rect reads the frame's own size. Taken at `8e1dfa7`:
///
/// - **A**, fixed 60×40 frame made `.relative`, insets top 10 left 15: abs
///   (45, 90) — the frame at (30, 80) plus the insets; after (90, 95);
/// - **B**, the same frame left `.static`: abs (15, 10), against the root;
/// - **C**, `.relative`, every inset `.auto`: abs (30, 80), the containing
///   block's origin (divergence 9, `AP-F`);
/// - **D**, as C with `.bottomTrailing`: still (30, 80) — alignment does not
///   place an absolute child, on either lowering;
/// - **E**, a flexible `.frame(minWidth: 50, minHeight: 30)` made `.relative`,
///   insets right 5 bottom 5: abs (55, 90), after (80, 95) — the frame is
///   50×30 because an absolute child contributes no size;
/// - **F**, `.relative`, insets all 0 on a 20×20 child: abs (30, 80).
///
/// The control: A and B must disagree (the relative frame IS the containing
/// block). Green before and after the lowering, as intended. Mutation,
/// measured: lower through `display: .stack` without carrying `position`'s
/// containing block (make the frame layer `.static` when it lowers) — the
/// `#require` fails, A reading B's (15, 10).
///
/// Pinned to the legacy authority by stage 6a (CSS-frame, record §30 §4).
@Test @MainActor func anAbsolutelyPositionedChildInsideASingleChildLegacyFrameKeepsItsPlacement() throws {
    func arm(relative: Bool, _ edges: Edges<MetalUICore.Dimension>, alignment: ProposalAlignment = .center,
             flexible: Bool = false) throws -> (abs: Rect, after: Rect) {
        let log = try render(authority: .legacy) { log in
            Row {
                Mark("pad", log: log, width: 30, height: 30)
                if flexible {
                    Mark("abs", log: log, width: 20, height: 20).position(.absolute).inset(edges)
                        .frame(minWidth: px(50), minHeight: px(30), alignment: alignment)
                        .position(relative ? .relative : .static)
                } else {
                    Mark("abs", log: log, width: 20, height: 20).position(.absolute).inset(edges)
                        .frame(width: px(60), height: px(40), alignment: alignment)
                        .position(relative ? .relative : .static)
                }
                Mark("after", log: log, width: 10, height: 10)
            }
        }
        return (Rect(try #require(log.bounds["abs"])), Rect(try #require(log.bounds["after"])))
    }

    let a = try arm(relative: true, insets(top: 10, right: nil, bottom: nil, left: 15))
    let b = try arm(relative: false, insets(top: 10, right: nil, bottom: nil, left: 15))
    try #require(a.abs != b.abs, "a relative and a static frame placed the child alike: \(a.abs)")

    #expect(a.abs == Rect(45, 90, 20, 20), "A: \(a.abs)")
    #expect(a.after == Rect(90, 95, 10, 10), "A: the frame keeps its 60pt width: \(a.after)")
    #expect(b.abs == Rect(15, 10, 20, 20), "B: \(b.abs)")
    let c = try arm(relative: true, insets(top: nil, right: nil, bottom: nil, left: nil))
    #expect(c.abs == Rect(30, 80, 20, 20), "C: \(c.abs)")
    let d = try arm(relative: true, insets(top: nil, right: nil, bottom: nil, left: nil),
                    alignment: .bottomTrailing)
    #expect(d.abs == Rect(30, 80, 20, 20), "D: \(d.abs)")
    let e = try arm(relative: true, insets(top: nil, right: 5, bottom: 5, left: nil), flexible: true)
    #expect(e.abs == Rect(55, 90, 20, 20), "E: \(e.abs)")
    #expect(e.after == Rect(80, 95, 10, 10), "E: the flexible frame is 50x30: \(e.after)")
    let f = try arm(relative: true, insets(top: 0, right: 0, bottom: 0, left: 0))
    #expect(f.abs == Rect(30, 80, 20, 20), "F: \(f.abs)")
}

/// **A `ScrollView` inside a single-child legacy frame keeps its viewport, its
/// content's rect and its wheel exactly as before the lowering** (5.7).
///
/// Through a real `Window` over `FakePlatformWindow`, 200×200. Each arm is a
/// `Row` of a 30×30 pad and the frame; one wheel event of −37 at a point inside
/// the region. Taken at `8e1dfa7` (region bounds are clipped to the window, as
/// every hitbox is):
///
/// - **A**, `ScrollView(.vertical) { c 80×400 }` in a 120×100 frame: the
///   viewport is the content's 400 tall — a legacy frame never imposes its
///   size — so the region is (50, 0) 80×200, c (50, −100), and nothing scrolls
///   (offset 0);
/// - **F**, the same scroll view in a `Box` declared 100 tall: region (50, 50)
///   80×100, c (50, 50), offset **37**;
/// - **H**, F's box in a 60×60 `.topLeading` frame: region (30, 70) 80×100, c
///   (30, 70), offset 37;
/// - **G**, `ScrollView(.horizontal) { c 400×40 }` in a `Box` declared 100
///   wide in a 120×100 frame: the viewport overflows at the content's width,
///   region (40, 80) 160×40, c (40, 80), offset 0.
///
/// The control: A and F must disagree on the offset (the instrument can see a
/// scroll). Green before and after the lowering, as intended. Mutations,
/// measured: the lowered stack stretches its one child
/// (`justifyItems`/`alignItems` `.stretch`) — the `#require` fails, A's viewport
/// stretched to the frame's 100 and scrolling 37; `FrameSpec.style()` writes no
/// `justifyItems` (a stack's default is stretch) — A, F and G move (A's region
/// (30, 0) 120×200).
///
/// Pinned to the legacy authority by stage 6a (CSS-frame, record §30 §4).
@Test @MainActor func aScrollViewInsideASingleChildLegacyFrameKeepsItsViewportAndWheel() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    func arm<Content: Element>(at x: Float, _ y: Float, horizontal: Bool = false,
                               _ make: @escaping @MainActor (SizeLog) -> Content) throws
        -> (region: Rect, content: Rect, offset: Double) {
        let log = SizeLog()
        let (window, platform) = try makeFakeWindow(device: device, size: 200, layoutAuthority: .legacy) { make(log) }
        window.drawFrameIfNeeded()
        let region = try #require(window.lastScrollRegions.first, "no scroll region registered")
        let delta = horizontal ? Point(x: px(-37), y: px(0)) : Point(x: px(0), y: px(-37))
        platform.simulateInput(.scrollWheel(ScrollEvent(position: Point(x: px(x), y: px(y)), delta: delta)))
        window.drawFrameIfNeeded()
        let offset = try #require(window.stateTable.peek(region.id, as: ScrollState.self)).offset
        return (Rect(region.bounds), Rect(try #require(log.bounds["c"])), offset)
    }

    let a = try arm(at: 90, 100) { log in
        Row {
            Mark("pad", log: log, width: 30, height: 30)
            ScrollView(.vertical) { Mark("c", log: log, width: 80, height: 400) }
                .frame(width: px(120), height: px(100))
        }
    }
    let f = try arm(at: 90, 100) { log in
        Row {
            Mark("pad", log: log, width: 30, height: 30)
            Box { ScrollView(.vertical) { Mark("c", log: log, width: 80, height: 400) } }
                .height(px(100))
                .frame(width: px(120), height: px(100))
        }
    }
    try #require(a.offset != f.offset, "neither arm scrolled, so the wheel is unobserved: \(a.offset)")

    #expect(a.region == Rect(50, 0, 80, 200) && a.content == Rect(50, -100, 80, 400) && a.offset == 0,
            "A: \(a)")
    #expect(f.region == Rect(50, 50, 80, 100) && f.content == Rect(50, 50, 80, 400) && f.offset == 37,
            "F: \(f)")
    let h = try arm(at: 50, 90) { log in
        Row {
            Mark("pad", log: log, width: 30, height: 30)
            Box { ScrollView(.vertical) { Mark("c", log: log, width: 80, height: 400) } }
                .height(px(100))
                .frame(width: px(60), height: px(60), alignment: .topLeading)
        }
    }
    #expect(h.region == Rect(30, 70, 80, 100) && h.content == Rect(30, 70, 80, 400) && h.offset == 37,
            "H: \(h)")
    let g = try arm(at: 90, 100, horizontal: true) { log in
        Row {
            Mark("pad", log: log, width: 30, height: 30)
            Box { ScrollView(.horizontal) { Mark("c", log: log, width: 400, height: 40) } }
                .width(px(100))
                .frame(width: px(120), height: px(100))
        }
    }
    #expect(g.region == Rect(40, 80, 160, 40) && g.content == Rect(40, 80, 400, 40) && g.offset == 0,
            "G: \(g)")
}
