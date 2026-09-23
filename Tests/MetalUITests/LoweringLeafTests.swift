import Foundation
import Testing
import MetalUICore
import MetalUILayout
import MetalUIText
@testable import MetalUI

// Plan task 7, stage 1, lane 2 (`docs/superpowers/specs/2026-09-17-engine-replacement-design.md`
// §5.4 and §6 lane 2; rulings LR-E, LR-F, LR-X): the lowering table's leaf half —
// a childless `Box` and a `Text` registered as kernel nodes under the proposal
// layout authority, compared with the legacy engine through the differential
// harness (`LayoutDifferential.swift`).
//
// **Red before**: every test here except 2.7 (a characterization pin) read red on
// lane 1's tree, where `Box` and `Text` report `noLowering` at site level
// (record §18, lane 2). The mutation each must redden is named in its doc comment
// and in spec §6's lane-2 table; the record names what each actually reddened.

private func px(_ v: Float) -> Pixels { Pixels(v) }

private func bounds(_ x: Float, _ y: Float, _ w: Float, _ h: Float) -> Bounds<Pixels> {
    Bounds(origin: Point(x: Pixels(x), y: Pixels(y)), size: Size(width: Pixels(w), height: Pixels(h)))
}

private let rootID = GlobalElementID.child(of: nil, at: 0, name: nil)
private let leafID = GlobalElementID.child(of: rootID, at: 0, name: nil)

private func field(_ site: LoweringSite, _ name: String) -> UnlowerableField {
    UnlowerableField(site: site, field: name)
}

/// A long run whose widest word is far narrower than the whole line (probe T's string).
private let longString = "alpha bravo charlie delta echo foxtrot golf"

/// A `Style` edited by `edit`, for arms that set one field.
private func style(_ edit: (inout Style) -> Void) -> Style {
    var s = Style()
    edit(&s)
    return s
}

/// A `Text` whose style is edited by `edit`.
@MainActor
private func text(_ string: String, _ edit: (inout Style) -> Void) -> Text {
    var t = Text(string)
    edit(&t.style)
    return t
}

/// Every whole-frame observation agrees, the one leaf agrees, and nothing was reported.
@MainActor
private func expectFullAgreement(_ r: LayoutDifferential.Report, _ arm: String,
                                 sourceLocation: SourceLocation = #_sourceLocation) {
    #expect(r.unlowerable.isEmpty, "\(arm): \(r.unlowerable)", sourceLocation: sourceLocation)
    #expect(r.disagreeing.isEmpty, "\(arm): \(r.disagreeing)", sourceLocation: sourceLocation)
    #expect(r.legacyOnly.isEmpty && r.loweredOnly.isEmpty,
            "\(arm): legacyOnly \(r.legacyOnly) loweredOnly \(r.loweredOnly)", sourceLocation: sourceLocation)
    #expect(r.scenesEqual, "\(arm): scenes", sourceLocation: sourceLocation)
    #expect(r.hitboxesEqual, "\(arm): hitboxes", sourceLocation: sourceLocation)
    #expect(r.accessibilityEqual, "\(arm): accessibility", sourceLocation: sourceLocation)
    #expect(r.stateSlotsEqual, "\(arm): state slots", sourceLocation: sourceLocation)
}

// MARK: - 2.1, 2.2 — a childless Box

/// **2.1.** A fixed-size childless `Box`, declared in px and in rem, decorated
/// (background, corner radius) and clickable with an accessibility label, agrees
/// with its legacy twin in bounds, scene, hitboxes, accessibility and state slots,
/// at literal rects derived by hand: 30×20 px; 2.5rem × 1.25rem at the frame's
/// root font size 16 = 40×20.
///
/// Mutation that must redden it: **M2a**, rem lowered as px (× 1: 2.5×1.25, which
/// rounds to 3×1).
@MainActor
@Test func aLoweredFixedSizeBoxAgreesWithTheLegacyBoxInEveryObservation() throws {
    let pxReport = LayoutDifferential.compare(width: 100, height: 60) {
        Box().width(px(30)).height(px(20)).background(.accent).cornerRadius(px(4))
            .onClick {}.accessibilityLabel("px box")
    }
    try #require(pxReport.elements == 2)
    expectFullAgreement(pxReport, "px")
    #expect(pxReport.loweredBounds[leafID] == bounds(0, 0, 30, 20))

    let remStyle = style {
        $0.size = Size(width: .length(.rems(Rems(2.5))), height: .length(.rems(Rems(1.25))))
    }
    let remReport = LayoutDifferential.compare(width: 100, height: 60) {
        Box(style: remStyle).background(.accent).cornerRadius(px(4))
            .onClick {}.accessibilityLabel("rem box")
    }
    try #require(remReport.elements == 2)
    expectFullAgreement(remReport, "rem")
    #expect(remReport.loweredBounds[leafID] == bounds(0, 0, 40, 20))
}

/// **2.2.** `Style.padding` on a childless `Box` sits **inside** its declared
/// size (CSS border-box; stage-1 probe B1): a 60×60 box padded (12, 4, 8, 12) is
/// 60×60 on both sides; an unsized box padded (top 3, right 5, bottom 7, left 11)
/// is 16×10 on both sides (the padding sums); a 10×10 box padded 8 on every edge
/// (a declared size below the padding sum, `BM-4`) reports nothing **since stage 2's
/// lane 4** and keeps its fixed 10×10 frame where CSS floors the border box at 16×16
/// — the divergence spec 4.3 pins (`LR-AH` as amended); this arm only holds that the
/// report is gone and the frame is the declared size.
///
/// Mutation that must redden it: **M2b**, padding placed outside the size frame
/// (the first arm's lowered box reads 76×80).
@MainActor
@Test func aLoweredBoxPaddingSitsInsideItsDeclaredSize() throws {
    let sized = LayoutDifferential.compare(width: 100, height: 100) {
        Box(style: style {
            $0.size = Size(width: .length(.pixels(px(60))), height: .length(.pixels(px(60))))
            $0.padding = Edges(top: .pixels(px(12)), right: .pixels(px(4)),
                               bottom: .pixels(px(8)), left: .pixels(px(12)))
        }).background(.accent)
    }
    try #require(sized.elements == 2)
    expectFullAgreement(sized, "padded sized")
    #expect(sized.loweredBounds[leafID] == bounds(0, 0, 60, 60))

    let unsized = LayoutDifferential.compare(width: 100, height: 100) {
        Box(style: style {
            $0.padding = Edges(top: .pixels(px(3)), right: .pixels(px(5)),
                               bottom: .pixels(px(7)), left: .pixels(px(11)))
        }).background(.accent)
    }
    try #require(unsized.elements == 2)
    expectFullAgreement(unsized, "padded unsized")
    #expect(unsized.loweredBounds[leafID] == bounds(0, 0, 16, 10))

    let floor = LayoutDifferential.compare(width: 100, height: 100) {
        Box(style: style {
            $0.size = Size(width: .length(.pixels(px(10))), height: .length(.pixels(px(10))))
            $0.padding = Edges(all: .pixels(px(8)))
        })
    }
    #expect(floor.unlowerable.isEmpty, "\(floor.unlowerable)")
    #expect(floor.legacyBounds[leafID] == bounds(0, 0, 16, 16))
    #expect(floor.loweredBounds[leafID] == bounds(0, 0, 10, 10))
}

// MARK: - 2.3, 2.4 — which fields a leaf reports

/// **2.3.** Every "otherwise" row of spec §5.4's **every node** table is reported
/// by its field name on a leaf — on a childless `Box` and on a `Text`. One arm
/// per row, each setting only that field; each report is exactly one entry. Three
/// combined rows follow on both sites: a percentage padding and a percentage border
/// together, in the table's order; `display: none` with a margin, reported alone
/// (`LR-J`); `margin` with `flexGrow`, both in the table's order.
///
/// **Stage 2, lane 4 (rulings LR-AH, LR-AI).** The box-model rows are gone or
/// renamed: `padding.floor` lowers (the fixed frame wins, spec 4.3), `padding.text`
/// lowers (native padding around the leaf, spec 4.2), and a px/rem `border` lowers
/// into the padding's insets — only `border.percent` still reports.
///
/// **Stage 2, lane 1 (rulings LR-AB, LR-AQ).** The item rows — `minSize`, `maxSize`,
/// `margin`, `flexGrow`, `flexShrink`, `flexBasis`, `alignSelf` — are the parent's
/// to read. Directly under the harness root (a proposal overlay) no lowered
/// container consumes the leaf's record, so each reports `<field>.unconsumed` after
/// the root returns, in `LR-AQ`'s order (`flexGrow` before `margin` in the combined
/// row). Inside a lowered `Row` the parent consumes the record and reports what
/// stage 2 cannot lower, at the leaf's site: seven more arms per site
/// (`minSize.percent`, `maxSize` on the row's unstretched cross axis, a negative
/// `flexGrow` and `flexShrink` — lane 2 lowers a positive grow, a zero shrink and a
/// px minimum — `flexBasis` a length, `margin.percent` — lane 4 lowers a px/rem
/// margin — and `alignSelf` as `.baseline`, which reports `alignSelf.baseline`: a
/// `.center` `alignSelf` lowers since lane 1). 46 arms.
///
/// **`display.none` is no longer a row** (stage 6b, lane 1, `LR-DH`): a hidden leaf
/// lowers as if shown, so the table's `display.none` row went and the combined arms
/// below carry a hidden leaf that reports nothing alone and, with a margin, reports
/// only the margin.
///
/// Mutations that must redden it: **M2c**, the `margin` check deleted; stage 1's
/// **V4** (`display: none` no longer returned alone) is **retired** with the row;
/// **V5**, only the last of several fields
/// recorded; **M4h**, `margin.percent` no longer reported (2 issues); **V4q**, the
/// `border.percent` entry removed (4). Stage 1's **V3** (the height half of the floor
/// check deleted) is **retired**: lane 4 deleted the `padding.floor` branch outright,
/// so the mutation has no target left (record §21's verification section).
@MainActor
@Test func everyStageOneUnlowerableNodeFieldIsReportedByNameOnALeaf() throws {
    typealias Row = (name: String, edit: (inout Style) -> Void, onBox: Bool)
    let rows: [Row] = [
        ("size.percent", { $0.size.width = .length(.percent(0.5)) }, true),
        ("padding.percent", { $0.padding.left = .percent(0.1) }, true),
        ("minSize.unconsumed", { $0.minSize.width = .length(.pixels(px(5))) }, true),
        ("maxSize.unconsumed", { $0.maxSize.height = .length(.pixels(px(50))) }, true),
        ("margin.unconsumed", { $0.margin.top = .length(.pixels(px(3))) }, true),
        ("border.percent", { $0.border.right = .percent(0.1) }, true),
        ("position", { $0.position = .relative }, true),
        ("inset", { $0.inset.left = .length(.pixels(px(4))) }, true),
        ("flexGrow.unconsumed", { $0.flexGrow = 1 }, true),
        ("flexShrink.unconsumed", { $0.flexShrink = 0 }, true),
        ("flexBasis.unconsumed", { $0.flexBasis = .length(.pixels(px(10))) }, true),
        ("alignSelf.unconsumed", { $0.alignSelf = .center }, true),
    ]
    typealias Arm = (name: String, entries: [UnlowerableField], expected: [UnlowerableField])
    var arms: [Arm] = []
    for row in rows {
        if row.onBox {
            let s = style(row.edit)
            arms.append(("Box \(row.name)",
                         LayoutDifferential.render(authority: .proposal, width: 100, height: 100) {
                             Box(style: s)
                         }.unlowerableFields,
                         [field(.box, row.name)]))
        }
        let t = text("ab", row.edit)
        arms.append(("Text \(row.name)",
                     LayoutDifferential.render(authority: .proposal, width: 100, height: 100) {
                         t
                     }.unlowerableFields,
                     [field(.text, row.name)]))
    }
    // Arms whose report is not a single entry named by the row (verifier round 1,
    // lane 2): each half of `padding.floor` on its own axis (the 10×10 row above
    // always takes the width branch first); a hidden leaf reports nothing of its own
    // and, declaring an unlowerable field too, only that field — it lowers as if
    // shown since stage 6b (`LR-DH`), where it reported `display.none` ALONE
    // (`LR-J`); a leaf with two
    // unlowerable fields reports both, in the table's order.
    let combined: [(name: String, edit: (inout Style) -> Void, expected: [String])] = [
        ("padding and border percent together", {
            $0.padding.left = .percent(0.1)
            $0.border.right = .percent(0.1)
        }, ["padding.percent", "border.percent"]),
        ("display.none alone", { $0.display = .none }, []),
        ("display.none with margin", {
            $0.display = .none
            $0.margin.top = .length(.pixels(px(3)))
        }, ["margin.unconsumed"]),
        ("margin and flexGrow", {
            $0.flexGrow = 1
            $0.margin.top = .length(.pixels(px(3)))
        }, ["flexGrow.unconsumed", "margin.unconsumed"]),
    ]
    for row in combined {
        let s = style(row.edit)
        arms.append(("Box \(row.name)",
                     LayoutDifferential.render(authority: .proposal, width: 100, height: 100) {
                         Box(style: s)
                     }.unlowerableFields,
                     row.expected.map { field(.box, $0) }))
        let t = text("ab", row.edit)
        arms.append(("Text \(row.name)",
                     LayoutDifferential.render(authority: .proposal, width: 100, height: 100) {
                         t
                     }.unlowerableFields,
                     row.expected.map { field(.text, $0) }))
    }
    // Consumed by a lowered `Row` (stage 2, lane 1): the parent reports at the leaf's
    // site, under the stage-1 name, what stage 2 does not lower. Re-spelled in lane 2,
    // which lowers a px `minSize`, a positive `flexGrow` and `flexShrink: 0`: the
    // `minSize` arm is a percentage, and the grow and shrink arms are negative.
    let consumed: [(name: String, edit: (inout Style) -> Void)] = [
        ("minSize.percent", { $0.minSize.width = .length(.percent(0.5)) }),
        ("maxSize", { $0.maxSize.height = .length(.pixels(px(50))) }),
        ("margin.percent", { $0.margin.top = .length(.percent(0.1)) }),
        ("flexGrow", { $0.flexGrow = -1 }),
        ("flexShrink", { $0.flexShrink = -1 }),
        ("flexBasis", { $0.flexBasis = .length(.pixels(px(10))) }),
        ("alignSelf.baseline", { $0.alignSelf = .baseline }),
    ]
    for row in consumed {
        let s = style(row.edit)
        arms.append(("Box in a Row \(row.name)",
                     LayoutDifferential.render(authority: .proposal, width: 100, height: 100) {
                         MetalUI.Row { Box(style: s) }
                     }.unlowerableFields,
                     [field(.box, row.name)]))
        let t = text("ab", row.edit)
        arms.append(("Text in a Row \(row.name)",
                     LayoutDifferential.render(authority: .proposal, width: 100, height: 100) {
                         MetalUI.Row { t }
                     }.unlowerableFields,
                     [field(.text, row.name)]))
    }
    try #require(arms.count == 46)
    for arm in arms {
        #expect(arm.entries == arm.expected, "\(arm.name): \(arm.entries)")
    }
}

/// **2.3b** (exit test). In production — diagnostics off — a leaf declaring two
/// unlowerable fields traps naming the **first** in the table's order
/// (`box.size.percent`), not the last (`box.inset`).
///
/// **Re-spelled in stage 2, lane 1** from `margin` + `flexGrow`: both are item
/// fields now, reported `…unconsumed` after the root returns (ruling LR-AQ), so the
/// pair no longer exercised the leaf table's order. `size.percent` and `inset` are
/// every-node rows the leaf still reports itself (spec §6 lane 2's amendment, taken
/// in lane 1, where the change lands).
///
/// Mutation that must redden it: **V5**, the loop recording every field but the
/// last deleted (the trap then names `inset`).
@Test func aLeafWithTwoUnlowerableFieldsTrapsNamingTheFirstInProduction() async {
    let result = await #expect(processExitsWith: .failure, observing: [\.standardErrorContent]) {
        await MainActor.run {
            var s = Style()
            s.size.width = .length(.percent(0.5))
            s.inset.left = .length(.pixels(Pixels(4)))
            let box = Box(style: s)
            var root = DifferentialRoot(width: 100, height: 100) { box }
            Frame(contentSize: Size(width: Pixels(100), height: Pixels(100)), scaleFactor: 1,
                  layoutAuthority: .proposal).render(&root)
        }
    }
    let stderr = String(decoding: result?.standardErrorContent ?? [], as: UTF8.self)
    #expect(stderr.contains("box.size.percent has no proposal lowering"),
            "aborted, but not at the first unlowerable field:\n\(stderr)")
    #expect(!stderr.contains("box.inset"), "the trap must name the first field:\n\(stderr)")
}

/// **2.3c.** A lowered `Box` registers its **animated** style, not its declared
/// one: a width going 20 → 100 under `withAnimation(.linear(duration: 1))` reads
/// 20 on the frame that starts the transaction and 60 half-way, under the proposal
/// authority exactly as under the legacy one. (Spec §6's 5.6 is the stage's
/// animation pin; this is lane 2's own.)
///
/// Mutation that must redden it: **V7**, `Box` lowers its declared style (the
/// half-way frame reads 100).
@MainActor
@Test func aLoweredBoxRegistersItsAnimatedWidth() throws {
    for authority in [LayoutAuthority.legacy, .proposal] {
        let table = StateTable()
        func widthAt(_ width: Float, timestamp: Double, animating: Bool) -> Pixels? {
            let box = Box().width(px(width)).height(px(10))
            var root = DifferentialRoot(width: 200, height: 100) { box }
            let frame = Frame(contentSize: Size(width: Pixels(200), height: Pixels(100)), scaleFactor: 1,
                              stateTable: table, timestamp: timestamp,
                              transaction: animating ? .linear(duration: 1) : nil,
                              layoutAuthority: authority,
                              reportsUnlowerableFields: authority == .proposal,
                              recordsElementBounds: true)
            frame.render(&root)
            #expect(frame.unlowerableFields.isEmpty, "\(authority): \(frame.unlowerableFields)")
            return frame.elementBounds[leafID]?.size.width
        }
        #expect(widthAt(20, timestamp: 0, animating: false) == px(20), "\(authority) baseline")
        #expect(widthAt(100, timestamp: 0, animating: true) == px(20), "\(authority) transaction start")
        #expect(widthAt(100, timestamp: 0.5, animating: false) == px(60), "\(authority) half-way")
    }
}

/// **2.4.** Every **container** field is ignored on a leaf, whatever its value
/// (spec §5.4's leaves paragraph; `LR-E`, critic round 1 finding 6): the legacy
/// engine lays out no children for a leaf. One arm per field with its most
/// "unlowerable" value, plus `aspectRatio` and `overflow` (inert on legacy), each
/// on a 30×20 childless `Box` and on `Text("ab")`: nothing is reported and every
/// observation agrees.
///
/// Mutation that must redden it: **M2d**, `.rowReverse` reported on a leaf.
@MainActor
@Test func everyContainerFieldIsIgnoredOnALoweredLeaf() throws {
    let rows: [(name: String, edit: (inout Style) -> Void)] = [
        ("flexDirection.rowReverse", { $0.flexDirection = .rowReverse }),
        ("flexDirection.columnReverse", { $0.flexDirection = .columnReverse }),
        ("gap.percent", { $0.gap = Axes(both: .percent(0.5)) }),
        ("alignItems.baseline", { $0.alignItems = .baseline }),
        ("alignItems.stretch", { $0.alignItems = .stretch }),
        ("justifyContent.spaceBetween", { $0.justifyContent = .spaceBetween }),
        ("justifyItems.stretch", { $0.justifyItems = .stretch }),
        ("flexWrap.wrap", { $0.flexWrap = .wrap }),
        ("alignContent.spaceAround", { $0.alignContent = .spaceAround }),
        ("display.stack", { $0.display = .stack }),
        ("aspectRatio", { $0.aspectRatio = 2 }),
        ("overflow.hidden", { $0.overflow = Axes(both: .hidden) }),
    ]
    var count = 0
    for row in rows {
        let s = style {
            $0.size = Size(width: .length(.pixels(px(30))), height: .length(.pixels(px(20))))
            row.edit(&$0)
        }
        let boxReport = LayoutDifferential.compare(width: 100, height: 100) {
            Box(style: s).background(.accent)
        }
        try #require(boxReport.elements == 2)
        expectFullAgreement(boxReport, "Box \(row.name)")
        #expect(boxReport.loweredBounds[leafID] == bounds(0, 0, 30, 20), "Box \(row.name)")
        count += 1

        let t = text("ab", row.edit)
        let textReport = LayoutDifferential.compare(width: 100, height: 100) { t }
        try #require(textReport.elements == 2)
        expectFullAgreement(textReport, "Text \(row.name)")
        count += 1
    }
    try #require(count == 24)
}

// MARK: - 2.5–2.8 — Text

/// **2.5.** A `Text` at its natural width (a 1000-wide root, wider than every
/// arm's line) agrees with its legacy twin in bounds, glyph scene, hitboxes,
/// accessibility (its string) and state: a short and a long string × 13 and 22pt ×
/// with and without `.foregroundColor(.accent)`. Each legacy frame is required to
/// emit glyphs, so scene equality is not vacuous.
///
/// Mutation that must redden it: **M2e**, the lowered leaf ignores `fontSize`
/// (measures at 13pt).
@MainActor
@Test func aLoweredTextAgreesWithTheLegacyTextAtItsNaturalWidth() throws {
    var count = 0
    for string in ["Count 3", longString] {
        for size in [13.0, 22.0] {
            for tinted in [false, true] {
                let arm = "\(string) @\(size) tinted \(tinted)"
                var t = Text(string).font(size: size)
                if tinted { t = t.foregroundColor(.accent) }
                let element = t
                let legacy = LayoutDifferential.render(authority: .legacy, width: 1000, height: 100) { element }
                try #require(legacy.scene.glyphs.count >= string.filter { $0 != " " }.count, "\(arm)")
                let report = LayoutDifferential.compare(width: 1000, height: 100) { element }
                try #require(report.elements == 2)
                expectFullAgreement(report, arm)
                count += 1
            }
        }
    }
    try #require(count == 8)
}

/// **2.6.** A lowered `Text` **hugs its widest line** where the legacy text fills
/// the width it is offered (`LR-F`; stage-1 probe T2: SwiftUI answers 45 at 60).
/// `Text(long)` directly in a 60-wide harness root: the legacy root `Stack` gives
/// its child fit-content — `min(max-content, max(min-content, 60))` = 60, the rule
/// a `Column` item's cross size follows too (ST-H, TX-H) — and the lowered leaf
/// answers the shaper's widest line wrapped at 60 (44 on the design machine),
/// computed here from a fresh `ShapingCache`. Directly under the root rather than
/// in a `Column` because containers lower in lane 3 (ruling `LR-X`).
///
/// Mutation that must redden it: **M2f**, the lowered answer is the proposed width.
@MainActor
@Test func aLoweredTextHugsItsWidestLineWhereTheLegacyTextFillsItsContainingBlock() throws {
    let report = LayoutDifferential.compare(width: 60, height: 300) { Text(longString) }
    try #require(report.elements == 2)
    #expect(report.unlowerable.isEmpty)
    let legacy = try #require(report.legacyBounds[leafID])
    let lowered = try #require(report.loweredBounds[leafID])
    let cache = ShapingCache()
    let widest = cache.shaped(longString, font: cache.resolveFont(family: nil, size: 13),
                              wrappingAt: 60).widestLine
    #expect(legacy.size.width == px(60))
    #expect(lowered.size.width == Pixels(Float(widest.rounded())))
    #expect(lowered.origin == legacy.origin)
    try #require(legacy.size.width != lowered.size.width)
}

/// **3.3** (stage 1's 2.7, re-derived and renamed; ruling `LR-AU`). Below the
/// width of its widest broken line, `proposalTextMeasurement` — which a lowered
/// `Text` shares with `ProposalText`, one measurement for both (`LR-F`,
/// `LR-AM`) — now answers **the proposal**, as SwiftUI does (stage-1 probe T3:
/// 0×592, T4: 5×592).
///
/// Until this lane it answered its widest **character**: it wraps at
/// `smallestWrapWidth`, and the typesetter breaks inside a word it cannot fit, so
/// every line is one character — 11.18 here, a character with the trailing space
/// the typesetter hangs on its line (7.91 without it), against a tokenizer
/// min-content of 40.44 (`textMeasure`'s doc comment records the same split).
/// That answer was pinned wrong on purpose and is now the clamp's subject: the
/// `try #require` below keeps it as the discriminator, so an arm whose widest
/// broken line already fits the proposal cannot stand in for one that does not.
/// The height is unchanged and is SwiftUI's too (592, one 16pt line per
/// non-space character); only the width moves.
///
/// Mutation that must redden it: **M3b**, the clamp removed.
@MainActor
@Test func aProposalTextBelowItsWidestBrokenLineAnswersTheProposal() throws {
    let cache = ShapingCache()
    let font = cache.resolveFont(family: nil, size: 13)
    // One line per character; a word's last character keeps its trailing space
    // (the typesetter hangs it on that line), so those lines are shaped with it.
    let words = longString.split(separator: " ")
    var lines: [String] = []
    for (w, word) in words.enumerated() {
        for (c, character) in word.enumerated() {
            let endsAWordBeforeASpace = c == word.count - 1 && w < words.count - 1
            lines.append(String(character) + (endsAWordBeforeASpace ? " " : ""))
        }
    }
    try #require(lines.count == 37)
    let widestCharacter = lines
        .map { cache.shaped($0, font: font, wrappingAt: nil).widestLine }
        .max() ?? 0
    let minContent = cache.minContentWidth(longString, font: font)
    // The discriminator: both proposals are BELOW the widest broken line, so an
    // unclamped answer is wider than the proposal at both.
    try #require(widestCharacter > 5 && widestCharacter < minContent)
    for width in [0.0, 5.0] {
        let answer = proposalTextMeasurement(longString, font: font, cache: cache,
                                             proposal: ProposedSize(width: width, height: nil))
        #expect(answer.size.width == width, "at \(width): \(answer.size)")
        #expect(answer.size.height == Double(lines.count) * 16, "at \(width): \(answer.size)")
    }
}

/// **3.4** (ruling `LR-AU`). The measurement breaks **inside** a word that does
/// not fit and answers its widest resulting line, **up to the proposal** — probe
/// group Y, whose ten arms this test replays at the same strings and widths.
///
/// Two halves, each able to fail alone:
/// - **the line count** is probe Y's, as a literal per arm (1, 2, 2, 4, 5, 2, 2,
///   12, 7 for Y1–Y9, and 1 for the nil control Y0), read off the answer's
///   height at 16pt per line. This is what "breaks inside a word" means: "alpha"
///   holds no space at all, and at 25 it is two lines (Y2) rather than one
///   32.84-wide line overflowing its proposal; at 5 it is five (Y5), one per
///   character. `longString` at 30 is twelve (Y8) although its widest word
///   ("charlie", the tokenizer's 40.44 min-content) fits on no line there.
/// - **the width** is `min(w, cache.shaped(s, wrappingAt: w).widestLine)`, derived
///   from the shaping cache rather than written as a literal (`LR-F`). Y5 (5
///   against 7.86) and Y8 (30 against 33.31) are the two arms the clamp decides;
///   the other seven are below their proposal and must NOT move.
///
/// **SwiftUI ceils and MetalUI does not** — Y2 reads 19 against our 18.17, Y9 45
/// against 44.02 — so the widths come from the cache, not from the probe's
/// printed integers. The `try #require` on the clamped arms is what keeps this
/// test honest: without it every arm could pass by hugging.
///
/// Mutations that must redden it: **M3b**, the clamp removed (Y5 and Y8 answer
/// wider than the proposal); **M3c**, the clamp applied as the proposal whenever
/// a line breaks (Y2's 18.17 would read 25).
@MainActor
@Test func aProposalTextBreaksInsideAWordAndAnswersItsWidestLineUpToTheProposal() throws {
    let cache = ShapingCache()
    let font = cache.resolveFont(family: nil, size: 13)
    // Probe Y's three strings: a single word, a shorter one, and the sentence.
    let word = "alpha"
    let short = "Short"

    // Y0, the control: no proposal, one line at its own unwrapped width.
    let unwrapped = cache.shaped(word, font: font, wrappingAt: nil)
    let control = proposalTextMeasurement(word, font: font, cache: cache,
                                          proposal: .unspecified)
    #expect(control.size.height == 16, "Y0: \(control.size)")
    #expect(abs(control.size.width - unwrapped.widestLine) < 0.001, "Y0: \(control.size)")

    // Y1–Y9: (arm, string, proposed width, probe Y's line count).
    let arms: [(String, String, Double, Int)] = [
        ("Y1", word, 33, 1), ("Y2", word, 25, 2), ("Y3", word, 20, 2),
        ("Y4", word, 12, 4), ("Y5", word, 5, 5),
        ("Y6", short, 21, 2), ("Y7", short, 18, 2),
        ("Y8", longString, 30, 12), ("Y9", longString, 45, 7),
    ]
    try #require(arms.count == 9)
    var clamped = 0
    for (arm, string, width, expectedLines) in arms {
        let widest = cache.shaped(string, font: font, wrappingAt: width).widestLine
        if widest > width { clamped += 1 }
        let answer = proposalTextMeasurement(string, font: font, cache: cache,
                                             proposal: ProposedSize(width: width, height: nil))
        #expect(answer.size.height == Double(expectedLines) * 16,
                "\(arm): \(answer.size), probe Y reads \(expectedLines) lines")
        #expect(abs(answer.size.width - Swift.min(width, widest)) < 0.001,
                "\(arm): \(answer.size), widest line \(widest) at proposal \(width)")
    }
    // Y5 and Y8 are the only arms whose widest line exceeds their proposal; the
    // other seven cannot see the clamp at all.
    try #require(clamped == 2)
}

/// **2.8.** A `Text` with a declared width or height keeps its legacy bounds and
/// glyphs when lowered: its node is a fixed frame aligned `.topLeading` around the
/// measured leaf, and glyphs wrap at **the element node's** measured width — the
/// frame's, which is the width the leaf was proposed (ruling `LR-X`). Arms:
/// `Text(long).width(100)` (wraps), `.width(30)` and `.width(5)` (narrower than
/// the text's widest word, so the leaf answers wider than its frame, 2.7), and
/// `.height(40)` (one line in a 1000-wide root, 40 tall).
///
/// **The arms run in a child process** that must exit successfully and print one
/// line per agreeing arm: a lowering that registers the text leaf both inside its
/// frame and as the element's node traps on the kernel's one-parent precondition
/// (`CN-L`), and in-process that ended the whole run with no summary line
/// (mutation M2h, lane 2; practices shape 13).
///
/// Mutations that must redden it: **M2h**, the element's node returned as the
/// leaf, not the frame; **M2i**, glyphs wrapped at the leaf's answer to the
/// frame's proposal (the design's `Text.Layout.measuredNode`), which draws the
/// `.width(30)` and `.width(5)` arms in fewer, wider lines than the legacy text.
@Test func aLoweredTextWithADeclaredWidthKeepsItsBoundsAndGlyphOrigin() async {
    let child = await #expect(processExitsWith: .success,
                              observing: [\.standardOutputContent, \.standardErrorContent]) {
        await MainActor.run {
            let arms: [(name: String, text: Text, width: Float?, height: Float?)] = [
                ("width(100)", Text(longString).width(px(100)), 100, nil),
                ("width(30)", Text(longString).width(px(30)), 30, nil),
                ("width(5)", Text(longString).width(px(5)), 5, nil),
                ("height(40)", Text(longString).height(px(40)), nil, 40),
            ]
            for arm in arms {
                let element = arm.text
                let r = LayoutDifferential.compare(width: 1000, height: 900) { element }
                let lowered = r.loweredBounds[leafID]
                let agrees = r.elements == 2 && r.unlowerable.isEmpty && r.disagreeing.isEmpty
                    && r.legacyOnly.isEmpty && r.loweredOnly.isEmpty && r.scenesEqual
                    && r.hitboxesEqual && r.accessibilityEqual && r.stateSlotsEqual
                    && (arm.width.map { lowered?.size.width == Pixels($0) } ?? true)
                    && (arm.height.map { lowered?.size.height == Pixels($0) } ?? true)
                let line = "LANE2-2.8 \(arm.name) agrees=\(agrees) scenes=\(r.scenesEqual) "
                    + "disagreeing=\(r.disagreeing) unlowerable=\(r.unlowerable) lowered=\(String(describing: lowered))\n"
                FileHandle.standardOutput.write(Data(line.utf8))
            }
        }
    }
    let out = String(decoding: child?.standardOutputContent ?? [], as: UTF8.self)
    let err = String(decoding: child?.standardErrorContent ?? [], as: UTF8.self)
    for name in ["width(100)", "width(30)", "width(5)", "height(40)"] {
        #expect(out.contains("LANE2-2.8 \(name) agrees=true "), "\(name):\n\(out)\nstderr \(err)")
    }
}
