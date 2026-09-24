import Foundation
import Testing
import MetalUICore
@testable import MetalUILayout
import MetalUIText
@testable import MetalUI

// Plan task 7, stage 2, lane 4 (`docs/superpowers/specs/2026-09-17-engine-stage-2-design.md`
// §4.1's `margin` row, §4.2's `border`, `Style.padding` on a `Text` and the declared
// size below the padding sum, and §6's lane-4 table; rulings LR-AH, LR-AI, LR-AZ):
// the **box model** lowered under the proposal layout authority — `Style.border` as
// native padding insets inside the declared size, `Style.padding` on a `Text` as
// native padding around the text leaf, a declared size below the padding sum keeping
// its fixed frame where CSS floors the border box, and `margin` as native padding
// outside the item's wrappers.
//
// **Red before**: every test here was run on lane 3's tree (`51c4628`), where
// `Style.border` reports `box.border`, a padded `Text` reports `text.padding.text`, a
// floored size reports `box.padding.floor` and a margin reports `margin` at the
// child's site — so each reads red by a report, a literal mismatch, or (4.8) a
// production trap. Each compiles against lane-3 API only. 4.6 is a characterization
// pin whose red-before is its report. The mutation each must redden is named in its
// doc comment and in spec §6's lane-4 table; the record names what each reddened.
//
// **Legacy answers were measured before any literal here was written** (record §21,
// lane 4): several of the design's predictions were wrong — the legacy border box
// under 4.3 is **24×24**, not the 34×34 of SwiftUI probe P1, and its child sits at
// (12, 7) in a `Row` and (7, 12) in a `Column` rather than (12, 12) — and the legacy
// **stack** ignores a child's margin entirely, in size and in position (`LR-AZ`).
//
// Geometry is chosen so no centred offset falls on `x.5` (practices, fixture hazard).

private func px(_ v: Float) -> Pixels { Pixels(v) }

private func bounds(_ x: Float, _ y: Float, _ w: Float, _ h: Float) -> Bounds<Pixels> {
    Bounds(origin: Point(x: Pixels(x), y: Pixels(y)), size: Size(width: Pixels(w), height: Pixels(h)))
}

private let rootID = GlobalElementID.child(of: nil, at: 0, name: nil)
private let containerID = GlobalElementID.child(of: rootID, at: 0, name: nil)

private func child(_ parent: GlobalElementID, _ index: Int) -> GlobalElementID {
    GlobalElementID.child(of: parent, at: index, name: nil)
}

private func field(_ site: LoweringSite, _ name: String) -> UnlowerableField {
    UnlowerableField(site: site, field: name)
}

/// A `Style` edited by `edit`, for arms that set engine-side fields.
private func style(_ edit: (inout Style) -> Void) -> Style {
    var s = Style()
    edit(&s)
    return s
}

@MainActor
private func fixed(_ w: Float, _ h: Float) -> Box<EmptyGroup> {
    Box().cssWidth(px(w)).cssHeight(px(h))
}

/// The lane's asymmetric border, one distinct value per edge (practices shape 1), so
/// a transposed or dropped edge moves a literal.
private let borderEdges = Edges<Length>(top: .pixels(px(1)), right: .pixels(px(2)),
                                        bottom: .pixels(px(3)), left: .pixels(px(4)))

/// The lane's asymmetric margin, likewise.
private let marginEdges = Edges<Length>(top: .pixels(px(2)), right: .pixels(px(3)),
                                        bottom: .pixels(px(4)), left: .pixels(px(5)))

/// A `Text` carrying `style`.
@MainActor
private func styled(_ string: String, _ s: Style) -> Text {
    var t = Text(string)
    t.style = s
    return t
}

/// The shaping cache a `Text`'s default font resolves on — 13pt, no family — for the
/// derivations `LR-F` requires wherever a text decides a rect.
@MainActor
private func textShaping(_ string: String, wrappingAt width: Double?) -> ShapedText {
    let cache = ShapingCache()
    return cache.shaped(string, font: cache.resolveFont(family: nil, size: 13), wrappingAt: width)
}

private let longString = "alpha bravo charlie delta echo foxtrot golf"

// MARK: - 4.1 — Style.border

/// **4.1** (`LR-AH`). `Style.border` is CSS's border box: it shrinks the content box
/// exactly as `Style.padding` does, and lowers to the same native padding's insets,
/// **inside** the declared size. Four arms, all agreeing:
///
/// - a 60×50 `Box` with padding (2, 3, 4, 5) and border (1, 2, 3, 4) over a 10×10
///   child: 60×50 on both sides with the child at (5 + 4, 2 + 1) = (9, 3);
/// - an unsized childless `Box` with the border alone: 4 + 2 wide, 1 + 3 tall = 6×4;
/// - the same with padding 2 on every edge as well: 10×8;
/// - a bordered childless `Box` stretched by a 60-tall `Row {…}.alignItems(.stretch)`:
///   20×60, the row 40×60 — the border rides inside the item frame W.
///
/// Every edge differs from every other, so a transposed pair moves a rect.
///
/// Mutation that must redden it: **M4a**, the border insets transposed top ↔ left
/// (the first arm's child reads (6, 6)).
@MainActor
@Test func aStyleBorderLowersAsInsetsInsideTheDeclaredSize() throws {
    let sized = style {
        $0.size = Size(width: .length(.pixels(px(60))), height: .length(.pixels(px(50))))
        $0.padding = Edges(top: .pixels(px(2)), right: .pixels(px(3)),
                           bottom: .pixels(px(4)), left: .pixels(px(5)))
        $0.border = borderEdges
    }
    let container = LayoutDifferential.compare(width: 300, height: 200) {
        Box(style: sized) { fixed(10, 10) }
    }
    try #require(container.elements == 3)
    expectCorpusAgreement(container, "sized container with padding and border")
    #expect(container.loweredBounds[containerID] == bounds(0, 0, 60, 50))
    #expect(container.loweredBounds[child(containerID, 0)] == bounds(9, 3, 10, 10))

    let borderOnly = LayoutDifferential.compare(width: 300, height: 200) {
        Box(style: style { $0.border = borderEdges })
    }
    try #require(borderOnly.elements == 2)
    expectCorpusAgreement(borderOnly, "border alone")
    #expect(borderOnly.loweredBounds[containerID] == bounds(0, 0, 6, 4))

    let withPadding = LayoutDifferential.compare(width: 300, height: 200) {
        Box(style: style {
            $0.border = borderEdges
            $0.padding = Edges(all: .pixels(px(2)))
        })
    }
    try #require(withPadding.elements == 2)
    expectCorpusAgreement(withPadding, "border and padding")
    #expect(withPadding.loweredBounds[containerID] == bounds(0, 0, 10, 8))

    let stretched = LayoutDifferential.compare(width: 300, height: 200) {
        Row {
            Box(style: style { $0.border = borderEdges }).cssWidth(px(20)).background(.accent)
            fixed(20, 10)
        }
        .alignItems(.stretch).cssHeight(px(60))
    }
    try #require(stretched.elements == 4)
    expectCorpusAgreement(stretched, "bordered box stretched")
    #expect(stretched.loweredBounds[containerID] == bounds(0, 0, 40, 60))
    #expect(stretched.loweredBounds[child(containerID, 0)] == bounds(0, 0, 20, 60))
}

// MARK: - 4.2 — Style padding on a Text

/// **4.2 — divergence pin** (`LR-AH` as amended; stage-2 probe P6). `Style.padding` on
/// a `Text` is inert in the legacy engine (a content-sized leaf ignores its box model,
/// CLAUDE.md's inert table) and lowers to native padding around the **text leaf**,
/// SwiftUI's answer: `Text("alpha").padding(10)` is 53×36 with the glyphs at (10, 10).
///
/// Two arms, both with a sibling so the text is not the only child:
///
/// - **plain**, in a `Column {…}.alignItems(.flexStart)`: legacy text 33×16 at the
///   column origin, column 33×26, sibling at (0, 16); lowered text
///   `round(widest + 20)` × 36 = 53×36, column 53×46, sibling at (0, 36). **Every
///   lowered glyph is its legacy twin translated by exactly (10, 10)** — same string,
///   same font, same wrap width, so the sprites are identical and only the origin
///   moves.
/// - **stretched**, in a 140-wide `Column {…}.alignItems(.stretch)`: the text element
///   is 140 wide (its item frame W), but its **leaf** is 120 wide, and the glyphs wrap
///   there: 3 lines from the shaping cache at 120 against 2 at 140, so the lowered
///   text is 20 + 48 = 68 tall, and no glyph reaches past x = 130 (the leaf's trailing
///   edge). Wrapping at the element's aliased width instead would overflow the
///   trailing padding — critic round 1's finding 5.
///
/// Every width here is derived from the shaping cache, never written down (`LR-F`).
///
/// Mutations that must redden it: **M4b**, glyphs painted at the element node's
/// origin (the translation reads (0, 0)); **M4b′**, glyphs wrapped at the element's
/// aliased width (the stretched arm reads 2 lines and a glyph past 130).
@MainActor
@Test func paddingOnALoweredTextPadsItWhereTheLegacyLeafIgnoresIt() throws {
    let padded = style { $0.padding = Edges(all: .pixels(px(10))) }

    // Arm 1 — plain.
    let alphaWidest = textShaping("alpha", wrappingAt: nil).widestLine
    let alphaHeight = Float(textShaping("alpha", wrappingAt: nil).totalHeight)
    let paddedWidth = Float((alphaWidest + 20).rounded())
    let paddedHeight = alphaHeight + 20
    try #require(paddedWidth == 53 && paddedHeight == 36, "\(paddedWidth)x\(paddedHeight)")

    let plain = LayoutDifferential.compare(width: 300, height: 200) {
        Column { styled("alpha", padded); fixed(20, 10) }.alignItems(.flexStart)
    }
    try #require(plain.elements == 4)
    #expect(plain.unlowerable.isEmpty, "\(plain.unlowerable)")
    let text = child(containerID, 0), sibling = child(containerID, 1)
    try #require(plain.legacyBounds[text] != plain.loweredBounds[text])
    #expect(plain.legacyBounds[text] == bounds(0, 0, 33, 16))
    #expect(plain.legacyBounds[containerID] == bounds(0, 0, 33, 26))
    #expect(plain.legacyBounds[sibling] == bounds(0, 16, 20, 10))
    #expect(plain.loweredBounds[text] == bounds(0, 0, paddedWidth, paddedHeight))
    #expect(plain.loweredBounds[containerID] == bounds(0, 0, paddedWidth, paddedHeight + 10))
    #expect(plain.loweredBounds[sibling] == bounds(0, paddedHeight, 20, 10))

    // The glyphs themselves: identical sprites, translated by the leading padding.
    @MainActor func glyphOrigins(_ authority: LayoutAuthority) -> [(Float, Float)] {
        LayoutDifferential.render(authority: authority, width: 300, height: 200) {
            Column { styled("alpha", padded); fixed(20, 10) }.alignItems(.flexStart)
        }.scene.glyphs.map { ($0.bounds.origin.x, $0.bounds.origin.y) }
    }
    let legacyGlyphs = glyphOrigins(.legacy), loweredGlyphs = glyphOrigins(.proposal)
    try #require(legacyGlyphs.count == 5, "\(legacyGlyphs)")
    try #require(loweredGlyphs.count == legacyGlyphs.count, "\(loweredGlyphs)")
    #expect(loweredGlyphs.map { ($0.0 - 10, $0.1 - 10) }.elementsEqual(legacyGlyphs, by: ==),
            "legacy \(legacyGlyphs) lowered \(loweredGlyphs)")

    // Arm 2 — stretched: the leaf, not the element, decides the wrap width.
    let atLeaf = textShaping(longString, wrappingAt: 120)
    let atElement = textShaping(longString, wrappingAt: 140)
    try #require(atLeaf.lines.count == 3 && atElement.lines.count == 2,
                 "leaf \(atLeaf.lines.count) element \(atElement.lines.count)")
    let stretchedHeight = Float(atLeaf.totalHeight) + 20

    let stretched = LayoutDifferential.compare(width: 300, height: 200) {
        Column { styled(longString, padded); fixed(20, 10) }.alignItems(.stretch).cssWidth(px(140))
    }
    try #require(stretched.elements == 4)
    #expect(stretched.unlowerable.isEmpty, "\(stretched.unlowerable)")
    #expect(stretched.legacyBounds[text] == bounds(0, 0, 140, 32))
    #expect(stretched.loweredBounds[text] == bounds(0, 0, 140, stretchedHeight))
    #expect(stretched.loweredBounds[containerID] == bounds(0, 0, 140, stretchedHeight + 10))
    #expect(stretched.loweredBounds[sibling] == bounds(0, stretchedHeight, 20, 10))

    let stretchedGlyphs = LayoutDifferential.render(authority: .proposal, width: 300, height: 200) {
        Column { styled(longString, padded); fixed(20, 10) }.alignItems(.stretch).cssWidth(px(140))
    }.scene.glyphs
    let rightEdge = stretchedGlyphs.map { $0.bounds.origin.x + $0.bounds.size.width }.max() ?? 0
    try #require(rightEdge > 120, "\(rightEdge)")
    #expect(rightEdge <= 130, "widest glyph edge \(rightEdge)")
}

// MARK: - 4.3 — a declared size below the padding sum

/// **4.3 — divergence pin** (`LR-AH` as amended; stage-2 probe P1, P7, P8). CSS floors
/// a border box at its padding + border sum (`BM-4`): a 10×10 box padded 12 is **24×24**
/// with a zero-high content box. SwiftUI's fixed frame wins instead and the padding
/// overflows it, placed by the frame's own alignment (P1 `.topLeading`, P7 `.leading`,
/// P8 `.top`), so the lowered box is 10×10.
///
/// Three arms — a `Box` (`.topLeading`: `alignItems` stretch, `justifyContent` nil), a
/// `Row` (`.leading`: its cross factor ½ centres vertically) and a `Column`
/// (`.top`) — each over a rigid 10×10 child (`.flexShrink(0)`, so the legacy content
/// box does not shrink it to 0 and only the container's own rect is the subject):
///
/// | container | legacy | lowered | child legacy → lowered |
/// |---|---|---|---|
/// | `Box` | 24×24 | 10×10 | (12, 12) → (12, 12) |
/// | `Row` | 24×24 | 10×10 | (12, 7) → (12, 0) |
/// | `Column` | 24×24 | 10×10 | (7, 12) → (0, 12) |
///
/// **The design predicted 34×34 and (12, 12) in all three**: 34×34 is probe P1's
/// SwiftUI *padding* geometry, not the legacy box, and the legacy content box is 0 on
/// the floored axis, so a centring container puts the child half its own size before
/// the padding's inner edge. Measured first, then written (`LR-AZ`).
///
/// Mutations that must redden it: **M4c**, the lowered frame given
/// `max(size, padding sum)` (all three read 24×24); **M4c′**, the frame aligned
/// `.topLeading` whatever the container (the `Row` and `Column` arms).
@MainActor
@Test func aDeclaredSizeBelowThePaddingKeepsTheFrameWhereCSSFloorsTheBox() throws {
    let floored = style {
        $0.size = Size(width: .length(.pixels(px(10))), height: .length(.pixels(px(10))))
        $0.padding = Edges(all: .pixels(px(12)))
    }
    func merged(_ base: Style) -> Style {
        var s = base
        s.size = floored.size
        s.padding = floored.padding
        return s
    }
    enum Kind: String, CaseIterable { case box, row, column }
    let expected: [Kind: (legacyChild: Bounds<Pixels>, loweredChild: Bounds<Pixels>)] = [
        .box: (bounds(12, 12, 10, 10), bounds(12, 12, 10, 10)),
        .row: (bounds(12, 7, 10, 10), bounds(12, 0, 10, 10)),
        .column: (bounds(7, 12, 10, 10), bounds(0, 12, 10, 10)),
    ]
    for kind in Kind.allCases {
        // Built outside the builder closure: a builder `switch` adds an id level
        // (`LR-AX` item 10), which would move every id this test names.
        let element: AnyElement
        switch kind {
        case .box: element = AnyElement(Box(style: floored) { fixed(10, 10).flexShrink(0) })
        case .row:
            var row = MetalUI.Row { fixed(10, 10).flexShrink(0) }
            row.style = merged(row.style)
            element = AnyElement(row)
        case .column:
            var column = Column { fixed(10, 10).flexShrink(0) }
            column.style = merged(column.style)
            element = AnyElement(column)
        }
        let r = LayoutDifferential.compare(width: 300, height: 200) { element }
        try #require(r.elements == 3, "\(kind): \(r.elements)")
        #expect(r.unlowerable.isEmpty, "\(kind): \(r.unlowerable)")
        try #require(r.legacyBounds[containerID] != r.loweredBounds[containerID], "\(kind)")
        #expect(r.legacyBounds[containerID] == bounds(0, 0, 24, 24), "\(kind)")
        #expect(r.loweredBounds[containerID] == bounds(0, 0, 10, 10), "\(kind)")
        #expect(r.legacyBounds[child(containerID, 0)] == expected[kind]!.legacyChild, "\(kind)")
        #expect(r.loweredBounds[child(containerID, 0)] == expected[kind]!.loweredChild, "\(kind)")
    }
}

// MARK: - 4.4 — margin

/// **4.4** (`LR-AH`, `LR-AZ`; stage-2 probe P3). A px or rem `margin` sits **outside**
/// the item's border box in CSS, and lowers to native padding **outside** every
/// wrapper a lowered container registers — outside the item frame W and outside the
/// alignment frame, so it is never aliased and the element's own rect still excludes
/// it, as P3's background does.
///
/// Seven arms, all agreeing:
///
/// - a `Row` and a `Column` over a 20×10 child with margin (2, 3, 4, 5) beside a bare
///   20×10 sibling — the row 48×16 with the child at (5, 2) and the sibling at
///   (28, 3), the column 28×26 with the sibling at (4, 16);
/// - the same row in **rem**, at the frame's root font size 16: margins (4, 8, 12, 16),
///   the row 64×26, the child at (16, 4) and the sibling at (44, 8);
/// - a **`Stack`** and a **`.frame` layer** over a margined child: both **ignore** the
///   margin entirely, in size and in position (measured: the stack is 30×20 — the
///   other child's size — with the margined child centred at (5, 5) by its border box,
///   and the frame layer's child at (30, 25) rather than (31, 24)). The design's table
///   said a stack parent lowers margins "the same"; it does not (`LR-AZ`);
/// - a **stretched** item with cross margins in a 60-tall `Row {…}.alignItems(.stretch)`:
///   W is greedy inside the margin padding, so the box is 60 − 2 − 4 = 54 tall at
///   y 2 (practices shape 9's "stretch × margins" pair);
/// - a **grown** item with main margins in a 200-wide `Row`: the greedy outer padding
///   takes 180 and the box is 180 − 5 − 3 = 172 at x 5.
///
/// Mutations that must redden it: **M4d**, the margin padding aliased as the element's
/// rect (every arm's element grows by its margins); **M4e**, the margin padding
/// registered **inside** W (the stretched and grown arms' boxes fill the line).
@MainActor
@Test func aMarginLowersAsPaddingOutsideTheItem() throws {
    let a = child(containerID, 0), b = child(containerID, 1)

    let row = LayoutDifferential.compare(width: 300, height: 200) {
        MetalUI.Row { fixed(20, 10).margin(marginEdges); fixed(20, 10) }
    }
    try #require(row.elements == 4)
    expectCorpusAgreement(row, "row, px margins")
    #expect([row.loweredBounds[containerID], row.loweredBounds[a], row.loweredBounds[b]]
            == [bounds(0, 0, 48, 16), bounds(5, 2, 20, 10), bounds(28, 3, 20, 10)])

    let column = LayoutDifferential.compare(width: 300, height: 200) {
        Column { fixed(20, 10).margin(marginEdges); fixed(20, 10) }
    }
    try #require(column.elements == 4)
    expectCorpusAgreement(column, "column, px margins")
    #expect([column.loweredBounds[containerID], column.loweredBounds[a], column.loweredBounds[b]]
            == [bounds(0, 0, 28, 26), bounds(5, 2, 20, 10), bounds(4, 16, 20, 10)])

    let rem = Edges<Length>(top: .rems(Rems(0.25)), right: .rems(Rems(0.5)),
                            bottom: .rems(Rems(0.75)), left: .rems(Rems(1)))
    let remRow = LayoutDifferential.compare(width: 300, height: 200) {
        MetalUI.Row { fixed(20, 10).margin(rem); fixed(20, 10) }
    }
    try #require(remRow.elements == 4)
    expectCorpusAgreement(remRow, "row, rem margins")
    #expect([remRow.loweredBounds[containerID], remRow.loweredBounds[a], remRow.loweredBounds[b]]
            == [bounds(0, 0, 64, 26), bounds(16, 4, 20, 10), bounds(44, 8, 20, 10)])

    let stack = LayoutDifferential.compare(width: 300, height: 200) {
        Stack { fixed(20, 10).margin(marginEdges); fixed(30, 20) }
    }
    try #require(stack.elements == 4)
    expectCorpusAgreement(stack, "stack ignores the margin")
    #expect([stack.loweredBounds[containerID], stack.loweredBounds[a]]
            == [bounds(0, 0, 30, 20), bounds(5, 5, 20, 10)])

    let frameLayer = LayoutDifferential.compare(width: 300, height: 200) {
        fixed(20, 10).margin(marginEdges).frame(width: px(80), height: px(60))
    }
    try #require(frameLayer.elements == 3)
    expectCorpusAgreement(frameLayer, "frame layer ignores the margin")
    #expect(frameLayer.loweredBounds[child(containerID, 0)] == bounds(30, 25, 20, 10))

    let stretched = LayoutDifferential.compare(width: 300, height: 200) {
        MetalUI.Row {
            Box().cssWidth(px(20)).margin(marginEdges).background(.accent)
            fixed(20, 10)
        }
        .alignItems(.stretch).cssHeight(px(60))
    }
    try #require(stretched.elements == 4)
    expectCorpusAgreement(stretched, "stretched item with cross margins")
    #expect([stretched.loweredBounds[containerID], stretched.loweredBounds[a], stretched.loweredBounds[b]]
            == [bounds(0, 0, 48, 60), bounds(5, 2, 20, 54), bounds(28, 0, 20, 10)])

    let grown = LayoutDifferential.compare(width: 300, height: 200) {
        MetalUI.Row {
            Box().cssHeight(px(10)).flexGrow(1).margin(marginEdges).background(.accent)
            fixed(20, 10)
        }
        .cssWidth(px(200))
    }
    try #require(grown.elements == 4)
    expectCorpusAgreement(grown, "grown item with main margins")
    #expect([grown.loweredBounds[containerID], grown.loweredBounds[a], grown.loweredBounds[b]]
            == [bounds(0, 0, 200, 16), bounds(5, 2, 172, 10), bounds(180, 3, 20, 10)])
}

/// **4.5** (`LR-AH`; stage-2 probe P4, N1). A negative margin overlaps its sibling on
/// both paths while the margin box stays positive — `Row { 20×20.margin(-8); 20×20 }`
/// is 24×20 with the first box at x −8 and the second at 4, which is P4's SwiftUI
/// reading exactly — and **diverges once the margin box would go negative**: at −15 on
/// a 20 the CSS margin box is −10 and the sibling sits at −10, where the kernel's
/// padding response clamps at 0 per axis (`SA-K` item 3, probe N1) and the sibling
/// sits at 0. N1's placement is the lowered answer: the pad answers 0×0 at (0, 10) and
/// the child at the pad's origin + its (negative) leading inset, (−15, −5).
///
/// Mutation that must redden it: **M4f**, negative margins clamped at registration
/// (the −8 arm's first box reads x 0).
@MainActor
@Test func aNegativeMarginOverlapsItsSibling() throws {
    let a = child(containerID, 0), b = child(containerID, 1)

    let overlapping = LayoutDifferential.compare(width: 300, height: 200) {
        MetalUI.Row { fixed(20, 20).margin(px(-8)); fixed(20, 20) }
    }
    try #require(overlapping.elements == 4)
    expectCorpusAgreement(overlapping, "margin -8")
    #expect([overlapping.loweredBounds[containerID], overlapping.loweredBounds[a],
             overlapping.loweredBounds[b]]
            == [bounds(0, 0, 24, 20), bounds(-8, 0, 20, 20), bounds(4, 0, 20, 20)])

    let clamped = LayoutDifferential.compare(width: 300, height: 200) {
        MetalUI.Row { fixed(20, 20).margin(px(-15)); fixed(20, 20) }
    }
    try #require(clamped.elements == 4)
    #expect(clamped.unlowerable.isEmpty, "\(clamped.unlowerable)")
    try #require(clamped.legacyBounds[b] != clamped.loweredBounds[b])
    #expect([clamped.legacyBounds[containerID], clamped.legacyBounds[a], clamped.legacyBounds[b]]
            == [bounds(0, 0, 10, 20), bounds(-15, 0, 20, 20), bounds(-10, 0, 20, 20)])
    #expect([clamped.loweredBounds[containerID], clamped.loweredBounds[a],
             clamped.loweredBounds[b]]
            == [bounds(0, 0, 20, 20), bounds(-15, -5, 20, 20), bounds(0, 0, 20, 20)])
}

/// **4.6 — characterization** (`LR-AH`; CLAUDE.md's inert table). `margin: .auto`
/// resolves to 0 on both axes in the legacy engine and is unreachable from any
/// modifier, so it lowers to **nothing**: no margin padding, no report. Green on
/// arrival once lane 4 lands; red before, where an `.auto` margin reports `margin` at
/// the child's site.
///
/// **Two arms, and the second is the one a mutation can see.** Inside a lowered `Row`
/// the parent consumes the record, and counting `.auto` as a margin there would
/// register a padding whose insets are all 0 — a node more, the same geometry, no
/// report — so the consumed arm cannot tell the two apart (measured: M4g left the
/// whole suite green until this arm was added). Directly under the harness root
/// nobody consumes the record, and `LR-AQ`'s report is where the difference shows:
/// an `.auto` margin must report **nothing** where a px one reports
/// `margin.unconsumed` (2.3's row).
///
/// Mutation that must redden it: **M4g**, `.auto` counted as a margin.
@MainActor
@Test func anAutoMarginLowersAsZero() throws {
    let autoMargin = style { $0.margin = Edges(all: .auto) }
    let r = LayoutDifferential.compare(width: 300, height: 200) {
        MetalUI.Row { Box(style: autoMargin).cssWidth(px(20)).cssHeight(px(10)); fixed(20, 10) }
    }
    try #require(r.elements == 4)
    expectCorpusAgreement(r, "auto margin")
    #expect([r.loweredBounds[containerID], r.loweredBounds[child(containerID, 0)],
             r.loweredBounds[child(containerID, 1)]]
            == [bounds(0, 0, 40, 10), bounds(0, 0, 20, 10), bounds(20, 0, 20, 10)])

    // Unconsumed, under the harness root: nothing is reported, where a px margin
    // reports `margin.unconsumed`.
    let unconsumed = LayoutDifferential.render(authority: .proposal, width: 300, height: 200) {
        Box(style: autoMargin).cssWidth(px(20)).cssHeight(px(10))
    }.unlowerableFields
    #expect(unconsumed.isEmpty, "auto margin under the root: \(unconsumed)")
    let control = LayoutDifferential.render(authority: .proposal, width: 300, height: 200) {
        Box(style: style { $0.margin = Edges(all: .length(.pixels(px(3)))) })
            .cssWidth(px(20)).cssHeight(px(10))
    }.unlowerableFields
    try #require(control == [field(.box, "margin.unconsumed")], "\(control)")
}

// MARK: - 4.7 — percentages keep reporting, by name

/// **4.7** (`LR-AI`; stage-2 probe C1, C2). Every percentage the box model can carry
/// keeps reporting by its own name with stage 8's recipe as its owner: SwiftUI has no
/// spelling that makes a **child** a fraction of its parent without a greedy
/// `GeometryReader` around it (C2), so each call site needs a respelling decision.
/// Lane 4 renames the two the parent reports — `minSize` and `maxSize` named the
/// percentage case under stage 1's name — and adds the two the box model brings,
/// `border.percent` and `margin.percent`.
///
/// One arm per field, each inside a lowered `Row` so the parent reads the item ones,
/// each reporting exactly one entry.
///
/// Mutation that must redden it: **M4h**, `margin.percent` lowered as 0 (its arm
/// reports nothing).
@MainActor
@Test func percentagesStillReportByNameWithTheirOwner() throws {
    typealias Arm = (name: String, report: [UnlowerableField])
    @MainActor func inRow(_ name: String, _ edit: (inout Style) -> Void) -> Arm {
        let s = style(edit)
        return (name, LayoutDifferential.render(authority: .proposal, width: 300, height: 200) {
            MetalUI.Row { Box(style: s) }
        }.unlowerableFields)
    }
    var arms: [Arm] = [
        inRow("size.percent") { $0.size.width = .length(.percent(0.5)) },
        inRow("padding.percent") { $0.padding.left = .percent(0.1) },
        inRow("border.percent") { $0.border.left = .percent(0.1) },
        inRow("margin.percent") { $0.margin.left = .length(.percent(0.1)) },
        inRow("minSize.percent") { $0.minSize.width = .length(.percent(0.5)) },
        inRow("maxSize.percent") { $0.maxSize.width = .length(.percent(0.5)) },
        inRow("flexBasis") { $0.flexBasis = .length(.percent(0.5)) },
    ]
    var gapRow = MetalUI.Row { fixed(10, 10); fixed(10, 10) }
    gapRow.style.gap = Axes(both: .percent(0.1))
    arms.append(("gap.percent",
                 LayoutDifferential.render(authority: .proposal, width: 300, height: 200) {
                     gapRow
                 }.unlowerableFields))
    try #require(arms.count == 8)
    for arm in arms {
        #expect(arm.report == [field(.box, arm.name)], "\(arm.name): \(arm.report)")
    }
}

// MARK: - 4.8 — the depth guard with four item wrappers per level

/// A chain of `rows` nested `Row`s (spec 4.8; rulings LR-AB as amended, LR-AH, SA-L) —
/// 2.14's chain with a **margin** added per level, so each parent registers **four**
/// wrappers around its first child: `fixedSize` (horizontal, from `flexShrink(0)`),
/// the greedy item frame W (from `flexGrow(1)`), the alignment frame (from
/// `alignSelf(.flexEnd)` against the row's centring ½) and the margin padding,
/// outermost.
///
/// **Native depth, by hand** (`NativeLayoutRun.enter` on every `measureNative` and
/// `placeNative`, one counter): the root's fixed frame is 1 and its stack 2; each of
/// the 13 inner rows adds its parent's four wrappers and its own stack, **5** levels,
/// so the 14th row's stack is at 2 + 13·5 = 67; its first child's four wrappers reach
/// 71, and the child's own nodes **72** (1 level: a bare `Box()` lowers to its 0×0
/// leaf alone) or **73** (2: `.height(10)` adds its fixed frame). 6 + 5·N + own = 72
/// has no whole N for the old two-level innermost, which is why it is one level here
/// (stage 6b's lane 1, `LR-DK`; until then 16 inner rows reached 88 / 89 with a two- or
/// three-level innermost child).
///
/// **Nodes, by hand**: 14 rows × (a stack + the fixed sibling's frame and leaf) = 42;
/// the root's frame 1; 13 inner rows' wrappers 52; the innermost child's wrappers 4 and
/// its own nodes 1 (or 2): **100** (or **101**). (122 / 123 at 16 inner rows.)
@MainActor
private func marginItemChain(deeperInnermost: Bool) -> some Element {
    var element = deeperInnermost
        ? AnyElement(Box().cssHeight(px(10))
            .flexShrink(0).flexGrow(1).alignSelf(.flexEnd).margin(px(1)))
        : AnyElement(Box()
            .flexShrink(0).flexGrow(1).alignSelf(.flexEnd).margin(px(1)))
    for _ in 0..<13 {
        let inner = element
        element = AnyElement(MetalUI.Row { inner; Box().cssWidth(px(10)).cssHeight(px(10)) }
            .flexShrink(0).flexGrow(1).alignSelf(.flexEnd).margin(px(1)))
    }
    let inner = element
    return MetalUI.Row { inner; Box().cssWidth(px(10)).cssHeight(px(10)) }.cssWidth(px(100)).cssHeight(px(100))
}

/// **4.8, limit** (`SA-L`). `marginItemChain(deeperInnermost: false)` — 72 native
/// levels, `NativeLayoutRun.maxDepth` itself, every level of the 13 inner rows carrying
/// **four** item wrappers — lays out as a production frame's root under the proposal
/// authority, in a child process that must exit successfully and print the node count
/// derived by hand (100) and the run's deepest level with the limit (72, 72). With the
/// trap arm this pins the boundary at exactly 72 / 73.
///
/// **Red before**: the chain's `margin` is reported, and a production frame traps on
/// the first report, so the child exits on `SIGTRAP` instead of succeeding.
@Test func aLoweredItemChainWithFourWrappersPerLevelAtTheNativeDepthLimitLaysOut() async {
    let result = await #expect(processExitsWith: .success,
                               observing: [\.standardOutputContent, \.standardErrorContent]) {
        await MainActor.run {
            var root = marginItemChain(deeperInnermost: false)
            let frame = Frame(contentSize: Size(width: Pixels(100), height: Pixels(100)), scaleFactor: 1,
                              layoutAuthority: .proposal)
            frame.render(&root)
            FileHandle.standardOutput.write(Data(("LANE4-4.8 nodes=\(frame.tree.nodeCount)"
                + " deepest=\(frame.tree.lastNativeLayoutDeepestLevel) limit=\(NativeLayoutRun.maxDepth)\n").utf8))
        }
    }
    let out = String(decoding: result?.standardOutputContent ?? [], as: UTF8.self)
    let err = String(decoding: result?.standardErrorContent ?? [], as: UTF8.self)
    #expect(out.contains("LANE4-4.8 nodes=100 deepest=72 limit=72\n"), "stdout:\n\(out)\nstderr:\n\(err)")
}

/// **4.8, one past** (`SA-L`). `marginItemChain(deeperInnermost: true)` — 73 native
/// levels — traps with `SA-L`'s message, as an exit test.
///
/// Mutation that must redden it: **M4i**, `NativeLayoutRun.maxDepth` raised by 8 (the
/// child succeeds).
@Test func aLoweredItemChainWithFourWrappersPerLevelOnePastTheNativeDepthLimitTraps() async {
    let result = await #expect(processExitsWith: .failure, observing: [\.standardErrorContent]) {
        await MainActor.run {
            var root = marginItemChain(deeperInnermost: true)
            Frame(contentSize: Size(width: Pixels(100), height: Pixels(100)), scaleFactor: 1,
                  layoutAuthority: .proposal).render(&root)
        }
    }
    let err = String(decoding: result?.standardErrorContent ?? [], as: UTF8.self)
    #expect(err.contains("native layout recursion exceeded 72 levels"), "stderr:\n\(err)")
}

// MARK: - 4.9 — the animated margin

/// **4.9** (`LR-AS`, `LR-AZ` as amended; added after the lane's verification, which
/// found the read unpinned). `margin` is the one box-model field the lowering reads
/// from the **animated** style through a path of its own — `planLegacyItems`'
/// `plan.marginInsets`, four `marginEdge(a.margin.…)` calls — rather than through the
/// `style` argument `paddedAndSized` receives, which 2.3c already pins for the
/// declared size and which carries `Style.border` too (`LR-AS`'s values half).
///
/// A margin going 0 → 40 under `withAnimation(.linear(duration: 1))` puts the first
/// child at x 0 on the frame that starts the transaction and at x 20 half-way, under
/// the proposal authority exactly as under the legacy one. Without the arm, reading
/// the declared style there passes the whole suite (the verifier's V4n), while a
/// declared read would snap a margin to its target on the frame the change is
/// declared — the failure `LR-AS` exists to prevent.
///
/// Mutation that must redden it: **V4n**, `plan.marginInsets` read from `d.margin`
/// instead of `a.margin` (the half-way frame reads 40 under the proposal authority
/// and 20 under the legacy one, so the two authorities part company).
@MainActor
@Test func aLoweredMarginRegistersItsAnimatedValue() throws {
    let a = child(containerID, 0)
    for authority in [LayoutAuthority.legacy, .proposal] {
        let table = StateTable()
        func xAt(_ margin: Float, timestamp: Double, animating: Bool) -> Pixels? {
            var root = DifferentialRoot(width: 200, height: 100) {
                MetalUI.Row { fixed(20, 10).margin(px(margin)); fixed(20, 10) }
            }
            let frame = Frame(contentSize: Size(width: Pixels(200), height: Pixels(100)), scaleFactor: 1,
                              stateTable: table, timestamp: timestamp,
                              transaction: animating ? .linear(duration: 1) : nil,
                              layoutAuthority: authority,
                              reportsUnlowerableFields: authority == .proposal,
                              recordsElementBounds: true)
            frame.render(&root)
            #expect(frame.unlowerableFields.isEmpty, "\(authority): \(frame.unlowerableFields)")
            return frame.elementBounds[a]?.origin.x
        }
        #expect(xAt(0, timestamp: 0, animating: false) == px(0), "\(authority) baseline")
        #expect(xAt(40, timestamp: 0, animating: true) == px(0), "\(authority) transaction start")
        #expect(xAt(40, timestamp: 0.5, animating: false) == px(20), "\(authority) half-way")
    }
}
