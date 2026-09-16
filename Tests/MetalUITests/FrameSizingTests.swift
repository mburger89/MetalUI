import Testing
import MetalUICore
import MetalUILayout
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
// comment: `FR-E` (a finite maximum clamps but never grows), `FR-N` (an
// oversized child is squeezed on one axis) and `FR-O` (a single-axis infinite
// maximum is inert).
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
        (pass.requestNode(style: style, children: []), ())
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
private func render<Root: Element>(width: Float = 300, height: Float = 200,
                                   _ make: (SizeLog) -> Root) throws -> SizeLog {
    let log = SizeLog()
    var root = make(log)
    Frame(contentSize: Size(width: px(width), height: px(height)), scaleFactor: 1).render(&root)
    return log
}

/// A chain's outer width as a flex item, read as the **x of a 5pt sibling**
/// placed after it in a `Row` — the instrument scratch arm `L10` used, and the
/// only one that can see a layer's own width without reaching into the tree.
@MainActor
private func widthInRow<Chain: Element>(rowWidth: Float = 300, siblingWidth: Float = 5,
                                        _ make: (SizeLog) -> Chain) throws -> Float {
    let log = SizeLog()
    var row = Row {
        make(log)
        Mark("sibling", log: log, width: siblingWidth, height: 5)
    }.alignItems(.flexStart)
    Frame(contentSize: Size(width: px(rowWidth), height: px(200)), scaleFactor: 1).render(&row)
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
@Test @MainActor func aLegacyFramePlacesItsChildAtEachOfTheNineAlignments() throws {
    func origin(_ alignment: ProposalAlignment) throws -> Origin {
        let log = try render { log in
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
@Test @MainActor func aLegacyFixedFrameDoesNotShrinkAsAFlexItem() throws {
    let log = try render { log in
        Row {
            Mark("a", log: log, width: 20, height: 20).frame(width: px(200), height: px(20))
            Mark("b", log: log, width: 20, height: 20).frame(width: px(200), height: px(20))
        }
    }
    // The positive control: the same two declared widths WITHOUT a frame do
    // shrink in this row, so the fixture is genuinely over-constrained and the
    // instrument can see shrinking when it happens.
    let unpinned = try render { log in
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
@Test @MainActor func aLegacyFrameClampsToItsMinimumAndMaximumWithoutGrowingIntoTheProposal() throws {
    let minimum = try widthInRow { log in
        Mark("child", log: log, width: 20, height: 20).frame(minWidth: px(40))
    }
    let maximumOverALargeChild = try widthInRow { log in
        Mark("child", log: log, width: 200, height: 20).frame(maxWidth: px(80))
    }
    let maximumOverASmallChild = try widthInRow { log in
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
/// nothing else — and the call traps with a message naming the proposal path.
///
/// **Two positive controls**, and the second is the overload split's
/// (critic finding 5): the same flexible overload with min/max only must exit
/// successfully, and `.frame(idealWidth:)` on a **proposal** element must exit
/// successfully too — if the legacy overload ever won there, a working SwiftUI
/// idiom would become this trap.
///
/// Mutations: delete the precondition (both failure arms redden); make the
/// legacy overload win on a proposal element (the proposal control reddens).
@Test func anIdealDimensionOnTheLegacyFrameTraps() async throws {
    let width = await #expect(processExitsWith: .failure,
                              observing: [\.standardErrorContent]) {
        await MainActor.run { _ = Text("ideal").frame(idealWidth: Pixels(80)) }
    }
    let widthError = String(decoding: width?.standardErrorContent ?? [], as: UTF8.self)
    #expect(widthError.contains("idealWidth"),
            "the trap must name the parameter that caused it: \(widthError)")

    await #expect(processExitsWith: .failure) {
        await MainActor.run { _ = Text("ideal").frame(idealHeight: Pixels(80)) }
    }

    await #expect(processExitsWith: .success) {
        await MainActor.run { _ = Text("bounded").frame(minWidth: Pixels(40), maxWidth: Pixels(80)) }
    }

    await #expect(processExitsWith: .success) {
        await MainActor.run { _ = Rectangle().frame(idealWidth: Pixels(80)) }
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
@Test @MainActor func chainedLegacyFramesAgreeWithSwiftUIsOrderingRules() throws {
    let innerWide = try render { log in
        Row {
            Mark("leaf", log: log, width: 20, height: 20).frame(width: px(100)).frame(width: px(50))
            Mark("sibling", log: log, width: 5, height: 5)
        }.alignItems(.flexStart)
    }
    let outerWide = try render { log in
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

    let aligned = try render { log in
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
@Test @MainActor func aLegacyFrameProposesItsWidthToAMeasuredLeaf() throws {
    let framed = try render { log in
        Column {
            Text("alpha bravo charlie delta").font(size: 12).frame(width: px(60))
            Mark("marker", log: log, width: 5, height: 5)
        }
    }
    let bare = try render { log in
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

/// **A legacy frame around a `List` still builds every row** — the "it broke
/// list virtualization" half of the same reverted conversion, refuted
/// (scratch `L12`).
///
/// Forty 14pt rows in a 600pt viewport, so every row is inside the window.
/// The framed spelling builds the same rows as the unframed one and as
/// `.width(200)`, which writes the element's own box instead of wrapping it.
///
/// Mutation (critic finding 16 — **localized**, so that it separates
/// virtualization from painting): give the frame layer itself a fixed
/// `size.height` of 40 in `FrameSpec.style()`. The framed arm's row count then
/// collapses while the other two hold. The previous candidate — dropping the
/// layer's child list — reddened every framed element in the suite and proved
/// nothing about this test.
@Test @MainActor func aLegacyFrameAroundAListStillBuildsEveryRow() throws {
    struct Datum: Identifiable { let id: String }
    let data = (0..<40).map { Datum(id: "row-\($0)") }

    func rowCount<Wrapped: Element>(_ wrap: @escaping (List<[Datum], Mark>) -> Wrapped) throws -> Int {
        let log = SizeLog()
        var root = ScrollView {
            wrap(List(data, rowHeight: px(14)) { Mark($0.id, log: log) })
        }
        Frame(contentSize: Size(width: px(400), height: px(600)), scaleFactor: 1).render(&root)
        return log.bounds.keys.filter { $0.hasPrefix("row-") }.count
    }

    let bare = try rowCount { $0 }
    let styled = try rowCount { $0.width(px(200)) }
    let framed = try rowCount { $0.frame(width: px(200)) }
    try #require(bare == 40, "the instrument never built every row unframed: \(bare)")

    #expect(styled == 40, "`.width(200)` built \(styled) rows")
    #expect(framed == 40, "`.frame(width: 200)` built \(framed) rows")
}

// MARK: - 2.8 an oversized child is squeezed (ruling FR-N)

/// **A child bigger than its legacy frame is SQUEEZED on the layer's main axis**
/// where SwiftUI overflows both — ruling `FR-N`, **pinned wrong on purpose**.
///
/// A child declaring 200×160 inside `.frame(width: 60, height: 40)` lands at
/// **(0, 20) 60×160**: its width shrunk to the frame, its height overflowing.
/// **SwiftUI's `A5` keeps 200×160 at (−70, −60)** — a frame never resizes its
/// child.
///
/// The frame layer is a flex container: on its main axis an over-large item
/// shrinks (`flexShrink` defaults to 1, and the layer cannot reach into its
/// child's `Style`), on its cross axis it overflows. The second arm puts
/// `flexShrink(0)` on the LAYER and reads the same numbers, which separates
/// "the layer shrank" from "the child was shrunk as its flex item" (scratch
/// `N5`/`N6`). Owner of the fix: plan task 6.
///
/// Mutation: set the layer's `flexDirection` to `.column` — the squeeze moves
/// to the height and both arms redden, which is the evidence that one flex node
/// cannot overflow both axes.
@Test @MainActor func aLegacyFrameSqueezesAnOversizedChildWhereSwiftUIOverflows() throws {
    let plain = try render { log in
        Row {
            Mark("child", log: log, width: 200, height: 160).frame(width: px(60), height: px(40))
        }
    }
    let pinned = try render { log in
        Row {
            Mark("child", log: log, width: 200, height: 160)
                .frame(width: px(60), height: px(40))
                .flexShrink(0)
        }
    }
    #expect(Rect(try #require(plain.bounds["child"])) == Rect(0, 20, 60, 160),
            "SwiftUI's A5 is 200x160 at (-70, -60)")
    #expect(Rect(try #require(pinned.bounds["child"])) == Rect(0, 20, 60, 160),
            "the layer did not shrink; the child was shrunk as its flex item")
}

// MARK: - 2.9 an infinite maximum (ruling FR-O)

/// **An infinite maximum fills only when BOTH axes are infinite** (ruling
/// `FR-O`).
///
/// `flexGrow = 1` fills the parent's **main** axis and `alignSelf = .stretch`
/// fills its **cross** axis, so setting both is correct whichever way the
/// parent runs — the fill arm reads (140, 90) in a `Row` and in a `Column`
/// alike (scratch `N14`). A **single** infinite maximum lowers to nothing: the
/// same lowering applied to one axis consumes a whole axis nobody asked for
/// (scratch `N15`: a `Column` sibling pushed from y = 20 to y = 195), and the
/// layer a caller gets instead is **present and inert** — one more node,
/// identical geometry. That is a declared-but-inert row CLAUDE.md owes at
/// integration, and the fix needs the parent's axis (plan task 6).
///
/// Mutations: drop `alignSelf = .stretch` (the `Row` arm's y and the `Column`
/// arm's x redden); drop `flexGrow = 1` (the other halves); extend the fill
/// lowering to a single infinite maximum (the inert arm reddens).
@Test @MainActor func anInfiniteMaximumFillsOnlyWhenBothAxesAreInfinite() throws {
    let filledRow = try render { log in
        Row {
            Mark("mark", log: log, width: 20, height: 20)
                .frame(maxWidth: px(.infinity), maxHeight: px(.infinity))
        }
    }
    let filledColumn = try render { log in
        Column {
            Mark("mark", log: log, width: 20, height: 20)
                .frame(maxWidth: px(.infinity), maxHeight: px(.infinity))
        }
    }
    let inert = try render { log in
        Row {
            Mark("mark", log: log, width: 20, height: 20).frame(maxWidth: px(.infinity))
        }
    }
    let bare = try render { log in
        Row { Mark("mark", log: log, width: 20, height: 20) }
    }

    let filledOrigin = Origin(try #require(filledRow.bounds["mark"]))
    let inertOrigin = Origin(try #require(inert.bounds["mark"]))
    try #require(filledOrigin != inertOrigin,
                 "both spellings placed the mark alike: \(filledOrigin), \(inertOrigin)")

    #expect(filledOrigin == Origin(140, 90), "a Row parent: \(filledOrigin)")
    #expect(Origin(try #require(filledColumn.bounds["mark"])) == Origin(140, 90),
            "a Column parent fills the same way")
    #expect(inertOrigin == Origin(try #require(bare.bounds["mark"])),
            "a single infinite maximum must place the mark where no frame does")

    let inertNodes = try nodeCount { log in
        Row { Mark("mark", log: log, width: 20, height: 20).frame(maxWidth: px(.infinity)) }
    }
    let bareNodes = try nodeCount { log in
        Row { Mark("mark", log: log, width: 20, height: 20) }
    }
    #expect(inertNodes == bareNodes + 1,
            "the inert layer must still cost its node: \(inertNodes) against \(bareNodes)")
}

/// The tree's node count after one rendered frame — how test 2.9 shows that an
/// inert layer is present rather than absent.
@MainActor
private func nodeCount<Root: Element>(_ make: (SizeLog) -> Root) throws -> Int {
    let log = SizeLog()
    var root = make(log)
    let frame = Frame(contentSize: Size(width: px(300), height: px(200)), scaleFactor: 1)
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
@Test @MainActor func aSingleAxisFixedFrameDoesNotPinTheAxisItDidNotDeclare() throws {
    let framed = try widthInRow(siblingWidth: 200) { _ in
        Text("alpha bravo charlie delta").font(size: 12).frame(height: px(40))
    }
    let bare = try widthInRow(siblingWidth: 200) { _ in
        Text("alpha bravo charlie delta").font(size: 12)
    }
    let unconstrained = try widthInRow(rowWidth: 1000, siblingWidth: 200) { _ in
        Text("alpha bravo charlie delta").font(size: 12)
    }
    try #require(framed < unconstrained,
                 "the row is not over-constrained, so no pin could matter: \(framed), \(unconstrained)")

    #expect(framed == bare,
            "a declared height must not pin the width: framed \(framed), unframed \(bare)")
}
