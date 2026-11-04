import Testing
import MetalUICore
@testable import MetalUILayout

// R4-2 PR B (`DS-E`..`DS-H`, record 203): the default spacing at a text edge, in the kernel. Pure, so these run
// on Linux and Windows. **Every literal is SwiftUI's, read by `docs/probes/swiftui-default-spacing.swift`
// (macOS 27.2, output in `swiftui-default-spacing-run.txt`) and derived by hand from its printed metrics, never
// computed by the code under test.** A "face" is a font's CoreText ascent a, descent d, cap height c and
// leading l at one size; the rule (vertical only, horizontal is always 8):
//
//   rect above text   d + ceil((a + d) / 10)
//   text above rect   that + (a - c)            (the upper text's metrics)
//   text above text   ceil(l)                   (the lower text's leading)
//
// Gaps are read unrounded, as the stack's measured length minus its children's own.

private typealias Build = @Sendable (LayoutTree) -> LayoutNodeID

private struct Face: Sendable, CustomStringConvertible {
    let name: String
    let ascent: Double, descent: Double, leading: Double, cap: Double?
    /// The probe's `rect|text`, `text|rect` and `text|text` for this face (DS1, DS2).
    let rectText: Double, textRect: Double, textText: Double
    var description: String { name }
    var metrics: TextSpacingMetrics {
        TextSpacingMetrics(ascent: ascent, descent: descent, leading: leading, capHeight: cap)
    }
}

// DS1 and DS2 lines, verbatim: "DS2 SF s=13 asc=12.568 desc=-2.742 lead=0 cap=9.16" with
// "rect|text 4.742" and "text|rect 8.151" (the probe prints cap to three decimals, hence 0.002 slack).
private let sf13 = Face(name: "SF 13", ascent: 12.568, descent: 2.742, leading: 0, cap: 9.16,
                        rectText: 4.742, textRect: 8.151, textText: 0)
private let sf26 = Face(name: "SF 26", ascent: 25.137, descent: 5.484, leading: 0, cap: 18.319,
                        rectText: 9.484, textRect: 16.302, textText: 0)
private let sf48 = Face(name: "SF 48", ascent: 46.406, descent: 10.125, leading: 0, cap: 33.82,
                        rectText: 16.125, textRect: 28.711, textText: 0)
private let noto13 = Face(name: "Noto Sans 13", ascent: 13.897, descent: 3.809, leading: 0, cap: 9.282,
                          rectText: 5.809, textRect: 10.424, textText: 0)
private let noto26 = Face(name: "Noto Sans 26", ascent: 27.794, descent: 7.618, leading: 0, cap: 18.564,
                          rectText: 11.618, textRect: 20.848, textText: 0)
private let source13 = Face(name: "Source Sans 3 13", ascent: 13, descent: 4.238, leading: 0, cap: 8.58,
                            rectText: 6.238, textRect: 10.658, textText: 0)
private let geneva13 = Face(name: "Geneva 13", ascent: 13, descent: 3.25, leading: 1.085, cap: 9.852,
                            rectText: 5.25, textRect: 8.398, textText: 2)
/// Cap height equal to the ascent: the cap term vanishes (DS2 "DINCondensed-Bold s=13").
private let din13 = Face(name: "DIN Condensed 13", ascent: 9.256, descent: 3.744, leading: 2.6, cap: 9.256,
                         rectText: 5.744, textRect: 5.744, textText: 3)
private let faces = [sf13, sf26, sf48, noto13, noto26, source13, geneva13, din13]

private let rect: Build = { tree in
    tree.newNativeLeaf { _ in LayoutMeasurement(size: SizeD(width: 10, height: 10)) }
}

private func text(_ face: Face) -> Build {
    { tree in
        let id = tree.newNativeLeaf { _ in LayoutMeasurement(size: SizeD(width: 10, height: 10)) }
        tree.markTextSpacing(id, .text(face.metrics))
        return id
    }
}

private let emptyText: Build = { tree in
    let id = tree.newNativeLeaf { _ in LayoutMeasurement(size: SizeD(width: 10, height: 10)) }
    tree.markTextSpacing(id, .zero)
    return id
}

private let zeroSpacer: Build = { tree in tree.newNativeSpacer(minLength: 0) }

private func padded(_ build: @escaping Build, top: Double = 0, right: Double = 0, bottom: Double = 0,
                    left: Double = 0) -> Build {
    { tree in
        tree.newNativePadding(child: build(tree), insets: Edges(top: top, right: right, bottom: bottom, left: left))
    }
}

private func stack(_ axis: ProposalStackAxis, spacing: Double? = nil, _ children: [Build]) -> Build {
    { tree in tree.newNativeLinearStack(children: children.map { $0(tree) }, axis: axis, spacing: spacing) }
}

private func overlay(_ children: [Build]) -> Build {
    { tree in tree.newNativeOverlay(children: children.map { $0(tree) }) }
}

private func along(_ build: Build, _ axis: ProposalStackAxis) -> Double {
    let tree = LayoutTree(generation: 1)
    let size = tree.measureNativeLayout(root: build(tree), proposal: ProposedSize(width: nil, height: nil)).size
    return axis == .vertical ? size.height : size.width
}

/// The default gap between `upper` and `lower` in a stack along `axis` (`spacing` nil: the default): the
/// stack's length minus the two children's own.
private func gap(_ upper: @escaping Build, _ lower: @escaping Build, axis: ProposalStackAxis = .vertical,
                 spacing: Double? = nil) -> Double {
    along(stack(axis, spacing: spacing, [upper, lower]), axis) - along(upper, axis) - along(lower, axis)
}

private func near(_ a: Double, _ b: Double) -> Bool { abs(a - b) < 0.002 }

// MARK: - the rule

/// **The separating arm: the gap is a function of the font's metrics.** Eight faces (SF at 13, 26 and 48,
/// Noto Sans at 13 and 26, Source Sans 3, and two with a non-zero leading, one with the cap height equal to the
/// ascent), each against the probe's own three figures, and rect|rect keeping 8.
///
/// Mutations: **M1** `defaultGap` returns the 13 pt figures (4.742, 8.151, 0, a constant per kind) — red on
/// every face but `SF 13`, which stays green, so the test separates a metric function from a hard-coded 13 pt
/// table; **M1b** the cap term dropped (`text above rect` reads `rect above text`) — red on every face with
/// a cap height below its ascent and green on `DIN Condensed 13`; **M2** text|text always 0 — red on the two
/// faces with a leading.
@Test(arguments: faces) @MainActor private func aTextEdgeGapIsTheProbesFigureAtEverySize(face: Face) {
    let rectText = gap(rect, text(face)), textRect = gap(text(face), rect), textText = gap(text(face), text(face))
    #expect(near(rectText, face.rectText), "\(face): rect above text \(rectText) vs \(face.rectText)")
    #expect(near(textRect, face.textRect), "\(face): text above rect \(textRect) vs \(face.textRect)")
    #expect(near(textText, face.textText), "\(face): text above text \(textText) vs \(face.textText)")
    #expect(gap(rect, rect) == 8, "\(face): rect above rect")
}

/// DS5: text|text is the LOWER text's `ceil(leading)`; equal metrics are 0 only because their leading is 0.
/// SF 13 over SF 26 and back: 0. Geneva (l 1.085) over SF: 0, SF over Geneva: 2; DIN (l 2.6) over Geneva: 2,
/// Geneva over DIN: 3. Mutation **M2** (text|text always 0): the last four.
@Test @MainActor func unequalFontsTakeTheLowerTextsLeading() {
    #expect(gap(text(sf13), text(sf26)) == 0, "SF 13 over SF 26")
    #expect(gap(text(sf26), text(sf13)) == 0, "SF 26 over SF 13")
    #expect(gap(text(geneva13), text(sf13)) == 0, "Geneva over SF: the lower leading is 0")
    #expect(gap(text(sf13), text(geneva13)) == 2, "SF over Geneva: ceil(1.085)")
    #expect(gap(text(din13), text(geneva13)) == 2, "DIN over Geneva")
    #expect(gap(text(geneva13), text(din13)) == 3, "Geneva over DIN: ceil(2.6)")
}

/// The horizontal gap is 8 beside every neighbour at every font (DS1: stop condition 6 did not fire), an empty
/// text's too. Mutation **M7** (the text edge applied on both axes): red.
@Test(arguments: faces) @MainActor private func theHorizontalGapIsEightBesideText(face: Face) {
    #expect(gap(text(face), text(face), axis: .horizontal) == 8, "\(face) | \(face)")
    #expect(gap(text(face), rect, axis: .horizontal) == 8, "\(face) | rect")
    #expect(gap(rect, text(face), axis: .horizontal) == 8, "rect | \(face)")
    #expect(gap(emptyText, text(face), axis: .horizontal) == 8, "empty | \(face)")
}

/// An explicit spacing is verbatim (the S control, SP4): every kind of pair reads 3. Mutation **M8**
/// (`stackGaps` consults the edges first).
@Test @MainActor func anExplicitSpacingIgnoresTextEdges() {
    #expect(gap(text(sf13), rect, spacing: 3) == 3)
    #expect(gap(rect, text(sf13), spacing: 3) == 3)
    #expect(gap(text(sf13), text(geneva13), spacing: 3) == 3)
    #expect(gap(text(sf26), text(sf13), spacing: 0) == 0)
}

// MARK: - zero, spacer, empty

/// A spacer beside text takes no default spacing (DS11: b = c = 0 for text|Spacer, Spacer|text), at any font:
/// `{text; Spacer(0); rect}` is 20 tall. Mutation **M3**: `.zero` not checked before the text kinds (a text
/// above a zero edge falls to the 8 or the font's gap).
@Test(arguments: [sf13, sf48, geneva13]) @MainActor private func aSpacerBesideTextStillTakesNoDefaultSpacing(face: Face) {
    #expect(along(stack(.vertical, [text(face), zeroSpacer, rect]), .vertical) == 20, "\(face) | spacer | rect")
    #expect(along(stack(.vertical, [rect, zeroSpacer, text(face)]), .vertical) == 20, "rect | spacer | \(face)")
    #expect(along(stack(.vertical, [text(face), zeroSpacer, text(face)]), .vertical) == 20, "text | spacer | text")
}

/// `Spacer()`'s nil minimum is a constant 8 even between texts of any size (K1, K1c, DS11: `VStack{T; Spacer(); T}`
/// at 9, 13 and 48 pt is two lines + 8). Mutation **M9**: the minimum read from `defaultGap` of a text neighbour.
@Test(arguments: [sf13, sf48, geneva13]) @MainActor private func aSpacersNilMinimumIsConstantBesideText(face: Face) {
    let tree = LayoutTree(generation: 1)
    let spacer = tree.newNativeSpacer()
    let size = tree.measureNativeLayout(root: spacer, proposal: ProposedSize(width: nil, height: nil)).size
    #expect(size.height == 8 && size.width == 8, "\(face): the bare spacer's minimum is the constant 8: \(size)")
    #expect(along(stack(.vertical, [text(face), { $0.newNativeSpacer() }, text(face)]), .vertical) == 28,
            "\(face): 10 + 8 + 10")
}

/// An empty `Text` has no vertical edge (DS6 `empty`: rect|X, X|rect, X|X all 0; 8 horizontally). Mutation
/// **M24** (an empty text marked as text, or not marked): rect above it reads the font's gap or 8.
@Test @MainActor func anEmptyTextHasNoVerticalEdge() {
    #expect(gap(rect, emptyText) == 0 && gap(emptyText, rect) == 0, "empty beside a rect")
    #expect(gap(emptyText, text(sf13)) == 0 && gap(text(sf13), emptyText) == 0, "empty beside a text")
    #expect(gap(emptyText, emptyText) == 0, "empty beside itself")
}

// MARK: - wrappers (DS8)

/// DS8, a 13 pt SF text: `.padding(0)` and horizontal padding keep its edges (rect|W 4.742, W|rect 8.151); a
/// non-zero inset gives that edge standard: `.padding(4)` reads W|W 8, W|rect 8, rect|W 8, W|text 4.742,
/// text|W 8.151; `.padding(.top, 4)` W|W 8.151, W|rect 8.151, rect|W 8, W|text 0, text|W 8.151;
/// `.padding(.bottom, 4)` W|W 4.742, W|rect 8, rect|W 4.742, W|text 4.742, text|W 0 (the probe's paddingTop4
/// and paddingBottom4 lines). Mutation **M4**: padding passes the text edge through at any inset.
@Test @MainActor func aPaddedTextHasAStandardEdge() {
    func inset(_ top: Double, _ bottom: Double, _ sides: Double = 0) -> Build {
        padded(text(sf13), top: top, right: sides, bottom: bottom, left: sides)
    }
    let all = inset(4, 4, 4), top = inset(4, 0), bottom = inset(0, 4)
    #expect(near(gap(all, all), 8) && near(gap(all, rect), 8) && near(gap(rect, all), 8), "padding 4: standard")
    #expect(near(gap(all, text(sf13)), 4.742) && near(gap(text(sf13), all), 8.151), "padding 4 beside text")
    #expect(near(gap(top, top), 8.151) && near(gap(top, rect), 8.151) && near(gap(rect, top), 8), "padding top")
    #expect(near(gap(top, text(sf13)), 0) && near(gap(text(sf13), top), 8.151), "padding top beside text")
    #expect(near(gap(bottom, bottom), 4.742) && near(gap(bottom, rect), 8) && near(gap(rect, bottom), 4.742),
            "padding bottom")
    #expect(near(gap(bottom, text(sf13)), 4.742) && near(gap(text(sf13), bottom), 0), "padding bottom beside text")
}

/// DS8: zero padding and horizontal-only padding keep the text edges. Mutation **M4b**: padding makes the edge
/// standard whatever its inset (W|rect reads 8, not 8.151).
@Test @MainActor func aZeroPaddingKeepsTheTextEdge() {
    let zero = padded(text(sf13)), sides = padded(text(sf13), right: 4, left: 4)
    #expect(near(gap(zero, rect), 8.151) && near(gap(rect, zero), 4.742), "padding 0")
    #expect(near(gap(sides, rect), 8.151) && near(gap(rect, sides), 4.742), "horizontal padding 4")
    #expect(near(gap(zero, zero), 0) && near(gap(sides, sides), 0), "text over text")
}

/// DS8: a fixed `.frame(width: 40, height: 30)` gives standard (W|W 8, W|rect 8, rect|W 8, W|text 4.742,
/// text|W 8.151); a flexible frame (`maxWidth: .infinity`) keeps the text edges (8.151 / 4.742 / 0).
/// Mutation **M23**: a frame passes the text edge whatever its height.
@Test @MainActor func aFixedHeightFrameTurnsATextEdgeStandard() {
    let fixed: Build = { tree in tree.newNativeFrame(child: text(sf13)(tree), width: 40, height: 30) }
    let flexible: Build = { tree in tree.newNativeFrame(child: text(sf13)(tree), maxWidth: .infinity) }
    #expect(near(gap(fixed, fixed), 8) && near(gap(fixed, rect), 8) && near(gap(rect, fixed), 8), "fixed frame")
    #expect(near(gap(fixed, text(sf13)), 4.742) && near(gap(text(sf13), fixed), 8.151), "fixed frame beside text")
    #expect(near(gap(flexible, rect), 8.151) && near(gap(rect, flexible), 4.742) && near(gap(flexible, flexible), 0),
            "flexible frame")
}

// MARK: - unions (DS9)

/// A row's text edge wins over its control (FM0: `{Text; Slider}` above `{Toggle; Spacer; Button}` is 8.151,
/// not the larger of the two edges' distances), the larger font's edge wins between two text edges, and a
/// `ZStack` behaves the same. `{rect; text 13}`: rect above it 4.742 (**not** the 8 the standard pair would
/// take: the separating arm for M5), it above a rect 8.151; `{text 13; text 26}` is the 26's either way
/// (9.484 / 16.302). Mutation **M5**: a standard edge beats a text edge in the union.
@Test @MainActor func aRowsTextEdgeWinsOverItsControl() {
    let fm0Upper = stack(.horizontal, [text(sf13), rect]), fm0Lower = stack(.horizontal, [rect, zeroSpacer, rect])
    #expect(near(gap(fm0Upper, fm0Lower), 8.151), "FM0: text over a control row")
    let row = stack(.horizontal, [rect, text(sf13)])
    #expect(near(gap(rect, row), 4.742) && near(gap(row, rect), 8.151), "{rect; text} beside a rect")
    let mixed = stack(.horizontal, [text(sf13), text(sf26)]), reversed = stack(.horizontal, [text(sf26), text(sf13)])
    #expect(near(gap(rect, mixed), 9.484) && near(gap(mixed, rect), 16.302), "{13; 26}: the larger font")
    #expect(near(gap(rect, reversed), 9.484) && near(gap(reversed, rect), 16.302), "{26; 13}: either order")
    #expect(gap(mixed, text(sf13)) == 0 && gap(text(sf26), mixed) == 0, "text over text stays leading-only")
    let layered = overlay([rect, text(sf13)])
    #expect(near(gap(rect, layered), 4.742) && near(gap(layered, rect), 8.151), "ZStack{rect; text}")
}

/// A nested stack along the axis passes its first child's edge (leading) and its last child's (trailing)
/// (DS9 `vstackRectText`: M|rect 8.151, rect|M 8; `vstackTextRect`: M|rect 8, rect|M 4.742). Mutation **M6**:
/// the first child's edge used for both.
@Test @MainActor func aNestedStackTakesItsFirstAndLastChildsTextEdge() {
    let rectText = stack(.vertical, [rect, text(sf13)]), textRect = stack(.vertical, [text(sf13), rect])
    #expect(near(gap(rectText, rect), 8.151) && near(gap(rect, rectText), 8), "{rect; text}")
    #expect(near(gap(textRect, rect), 8) && near(gap(rect, textRect), 4.742), "{text; rect}")
}

/// **Not SwiftUI's, pinned as the ruling's behaviour** (`DS-G`; divergence 213 widened): a composite of a rect
/// and a text across the axis (`HStack{rect; text}`, a `ZStack`) presents the text edge to a rect neighbour (the
/// arms above agree with the probe) but SwiftUI's reads like a standard edge beside a TEXT neighbour (DS9
/// `hstackRectText`: M|text13 **4.742**, text13|M **8.151**, M|text26 **9.484**, text26|M **16.302**), where
/// the three-kind union reads text over text: 0, 0, and the leading of the 26 (0). Wrong on purpose; a fix
/// would add a fourth, mixed edge kind (stop condition 8's category question, not taken).
@Test @MainActor func aMixedCompositeBesideTextIsPinnedAsTheRulingReadsIt() {
    let row = stack(.horizontal, [rect, text(sf13)])
    #expect(gap(row, text(sf13)) == 0 && gap(text(sf13), row) == 0, "SwiftUI reads 4.742 and 8.151")
    #expect(gap(row, text(sf26)) == 0 && gap(text(sf26), row) == 0, "SwiftUI reads 9.484 and 16.302")
}

// MARK: - the grid (DS12)

/// A grid's row gap is the stack rule, the largest pair over the cells meeting in a column (GS1/GS4;
/// DS12 s=13: text/text rows dy 0, rect/text 4.742, text/rect 8.151, mixed `{text,rect}/{rect,text}`
/// 48.151 tall = 20 + 8.151 + 20, `{rect,rect}/{text,text}` 40.742); the column gap is 8. Mutation **M10**:
/// `pair` ignores the metrics (8 for all, or 0).
@Test @MainActor func aGridsRowGapIsTheLargestPairOverTextCells() {
    func height(_ rows: [[Build]]) -> Double {
        let tree = LayoutTree(generation: 1)
        var children: [LayoutNodeID] = []
        for row in rows {
            let cells = row.map { $0(tree) }
            tree.markNativeGridRow(cells)
            children += cells
        }
        return tree.measureNativeLayout(root: tree.newNativeGrid(children: children),
                                        proposal: ProposedSize(width: nil, height: nil)).size.height
    }
    #expect(height([[text(sf13)], [text(sf13)]]) == 20, "text/text: 10 + 0 + 10")
    #expect(near(height([[rect], [text(sf13)]]), 24.742), "rect/text: 10 + 4.742 + 10")
    #expect(near(height([[text(sf13)], [rect]]), 28.151), "text/rect: 10 + 8.151 + 10")
    #expect(near(height([[text(sf13), rect], [rect, text(sf13)]]), 28.151), "mixed: the larger pair")
    #expect(near(height([[rect, rect], [text(sf13), text(sf13)]]), 24.742), "rect row over text row")
    #expect(near(height([[text(sf26)], [rect]]), 36.302), "text/rect at 26")
    #expect(height([[rect], [rect]]) == 28, "rect/rect keeps 8")
    // A grid as a stack child passes its first and last rows' edges (DS12 "Grid{rect;text} as a stack child":
    // grid|rect 8.151, rect|grid 8).
    func grid(_ rows: [[Build]]) -> Build {
        { tree in
            var children: [LayoutNodeID] = []
            for row in rows {
                let cells = row.map { $0(tree) }
                tree.markNativeGridRow(cells)
                children += cells
            }
            return tree.newNativeGrid(children: children)
        }
    }
    let rectText = grid([[rect], [text(sf13)]]), textRect = grid([[text(sf13)], [rect]])
    #expect(near(gap(rectText, rect), 8.151) && near(gap(rect, rectText), 8), "Grid{rect; text} as a child")
    #expect(near(gap(textRect, rect), 8) && near(gap(rect, textRect), 4.742), "Grid{text; rect} as a child")
}

// MARK: - work (SA-M)

/// **A text stack costs the work of a rect stack.** The edge walk reads the spacing marks and measures nothing: the
/// same branching tree (a row of three columns of three leaves, measured and placed at a nil proposal, which no gap
/// can change a leaf's proposal under) registered once with plain leaves and once with the leaves alternately
/// marked as text, reads the same `lastNativeLayoutWork`, and not zero. Practice:
/// work counted on a branching tree (`SA-M`), never wall clock. Mutation **M21**: the walk measures a marked leaf
/// (`spacingEdges` calling the leaf's measure closure): the leaves' call count moves.
@Test @MainActor func aTextStacksLayoutWorkEqualsARectStacks() {
    final class Calls: @unchecked Sendable { var count = 0 }
    func work(marked: Bool) -> (NativeLayoutWork, leafCalls: Int) {
        let calls = Calls()
        let tree = LayoutTree(generation: 1)
        var columns: [LayoutNodeID] = []
        for column in 0..<3 {
            var leaves: [LayoutNodeID] = []
            for row in 0..<3 {
                let leaf = tree.newNativeLeaf { _ in
                    calls.count += 1
                    return LayoutMeasurement(size: SizeD(width: 10, height: 10))
                }
                if marked && (row + column) % 2 == 0 { tree.markTextSpacing(leaf, .text(sf13.metrics)) }
                leaves.append(leaf)
            }
            columns.append(tree.newNativeLinearStack(children: leaves, axis: .vertical, spacing: nil))
        }
        let root = tree.newNativeLinearStack(children: columns, axis: .horizontal, spacing: nil)
        let size = tree.measureNativeLayout(root: root, proposal: ProposedSize(width: nil, height: nil)).size
        tree.computeNativeLayout(root: root, proposal: ProposedSize(width: nil, height: nil),
                                 in: LayoutRect(x: 0, y: 0, width: size.width, height: size.height))
        return (tree.lastNativeLayoutWork, calls.count)
    }
    let plain = work(marked: false), marked = work(marked: true)
    // The counts themselves are the rect tree's (the unmarked path is untouched); the claim is the equality, on the
    // kernel's counters and on the leaves' own closures (a walk that measured would call them).
    #expect(plain.leafCalls >= 9 && plain.0.cacheMisses > 0, "the instrument sees work: \(plain)")
    #expect(marked.0 == plain.0, "marked \(marked.0) vs plain \(plain.0)")
    #expect(marked.leafCalls == plain.leafCalls, "leaf closures called: \(marked.leafCalls) vs \(plain.leafCalls)")
}
