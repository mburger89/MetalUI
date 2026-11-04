import Foundation
import MetalUI
import MetalUIScene
import MetalUITesting
import MetalUITextSystem
import Observation
import Testing

// R4-2 PR B (`DS-E`, record 203): the text edge through the retained channels. A text stack's gap is not a node
// rect of its own: it lives in the layout tree's spacing marks, which a graft must copy, the layout memo's
// signature must carry, and a font change under an unchanged `.equatable()` occurrence must move. Every
// differential draws two windows from one builder, one retaining and grafting and one retaining nothing
// (`testingRetainedSubtrees = false`). Counts and values, never time. Kernel side:
// `MetalUILayoutTests/DefaultSpacingTests.swift` and `GraftKernelTests`.
//
// The fixture: `{ Text(label); DSCard.equatable() }` with spacing 0, the card `{ 20x20 block; Text("Alpha") }`
// at the default spacing. Hand-derived (the portable test system, `harnessTextSystem`, is not CoreText, so these
// are compared against the retention-off twin and against the *kernel's own rule* applied to the same face):
// the card is 20 + g + line, g the rect-above-text gap `d + ceil((a + d) / 10)` of the face.

private struct DSCard: Component, @MainActor Equatable {
    var content: some ElementGroup {
        VStack(alignment: .leading) {
            Color.red.frame(width: Pixels(20), height: Pixels(20))
            Text("Alpha")
        }
    }
    static func == (l: DSCard, r: DSCard) -> Bool { true }
}

/// `side.model.n` is the label above the card, `side.model.tint` the font an ancestor sets (13 at 0, 26 above).
private struct DSRoot: Component {
    let side: RPSide
    var content: some ElementGroup {
        VStack(alignment: .leading, spacing: 0) {
            Text("step \(side.model.n)")
            DSCard().equatable()
        }
        .font(.system(size: side.model.tint == 0 ? 13 : 26))
    }
}

/// The tallest element: the root stack, centred at its own answer (`CN-J`).
@MainActor private func rootHeight(_ window: TestWindow) -> Float {
    window.window.testingElementBounds.values.map(\.size.height.value).max() ?? 0
}

@MainActor private func dsPair() throws -> RPPair<some Element> {
    let pair = try RPPair(size: sz(300, 200), warm: 5) { side in Box { DSRoot(side: side) } }
    pair.on.window.testingRecordsElementBounds = true
    pair.off.window.testingRecordsElementBounds = true
    return pair
}

/// A grafted text stack keeps its gap: the card is unchanged while the label above it changes, so the card is
/// grafted (`retainedGrafts`), and its stack's gap (a spacing mark on a text leaf) must come from the segment.
/// The twin that retains nothing builds it fresh; the two agree on every element's bounds, and the root's height
/// is the kernel's rule for the face: line + 20 + g + line with g = d + ceil((a + d) / 10) of the system's 13 pt
/// font. **Mutation M18**: `LayoutSegment` drops the spacing marks at capture (`rows(spacingMarks)` -> `[]`): the
/// grafted card's gap falls to 8, the bounds differ and `METALUI_VERIFY_RETAINED=1` traps naming the layout digest.
@Test @MainActor func aGraftedTextStackKeepsItsGap() async throws {
    let pair = try dsPair()
    var grafts = 0
    for step in 0..<4 {
        pair.onSide.model.n += 1; pair.offSide.model.n += 1
        await rsSettle()
        pair.redraw(); pair.redraw()
        grafts += pair.frames.suffix(2).map(\.retainedGrafts).reduce(0, +)
        try pair.compare("step \(step)")
        #expect(pair.on.window.testingElementBounds == pair.off.window.testingElementBounds, "step \(step): bounds")
    }
    // METALUI_VERIFY_RETAINED=1 builds a replayed frame twice: the graft counter is not its to read there, the traps are.
    if !rsVerifying { #expect(grafts > 0, "set up: the unchanged card is grafted: \(pair.frames.map { "g\($0.retainedGrafts) gi\($0.retainedGraftIneligible) h\($0.retainedHits)" })") }
    let metrics = harnessTextSystem()
    let key = metrics.resolveFont(FontDescriptor(size: 13))
    let m = metrics.fontMetrics(key)
    let gap = m.descent + ((m.ascent + m.descent) / 10).rounded(.up)
    let expected = Float((m.lineHeight + 20 + gap + m.lineHeight).rounded())
    #expect(rootHeight(pair.on) == expected, "the grafted root: \(rootHeight(pair.on)) vs \(expected) (g = \(gap))")
    #expect(rootHeight(pair.off) == expected)
}

/// A font set by an ancestor moves the gap of an unchanged `.equatable()` occurrence (its whole-environment
/// fingerprint misses), and the retained window agrees with the one that retains nothing at 13 and at 26.
/// **Mutation M19**: `TextLeafKey` drops `font` -- measured, see record 203 section 4: the spacing mark carries the
/// metrics into the signature, so this stays green (the mark is a second guard); with the mark's metrics
/// also dropped from `nodeSignature` (M11) the memo restores the 13 pt gap at 26 and this reddens.
@Test @MainActor func aFontChangeUnderAnEquatableParentMovesTheGap() async throws {
    let pair = try dsPair()
    let before = rootHeight(pair.on)
    for tint in [1, 0, 1] {
        pair.onSide.model.tint = tint; pair.offSide.model.tint = tint
        await rsSettle()
        pair.redraw(); pair.redraw()
        try pair.compare("tint \(tint)")
        #expect(pair.on.window.testingElementBounds == pair.off.window.testingElementBounds, "tint \(tint): bounds")
        if tint == 1 { #expect(rootHeight(pair.on) > before + 20, "26 pt is taller than 13 pt: \(rootHeight(pair.on)) vs \(before)") }
        else { #expect(rootHeight(pair.on) == before, "back at 13: \(rootHeight(pair.on)) vs \(before)") }
    }
}

/// A steady frame of a text stack hits the layout memo's root and measures nothing: three frames, three root
/// hits (the mark is mixed deterministically into the signature) and no leaf measure. Literals derived before
/// the run, from `aColorAndAnEmptyContainerKeepTheirAncestorsMatchable`'s three. **Mutation M20**: the mark
/// mixed with the tree's generation (a different signature every frame): 0 root hits.
@Test(.enabled(if: !rsVerifying, "METALUI_VERIFY_LAYOUT_MEMO=1 / RETAINED recompute hits; the counts are not theirs to read"))
@MainActor func aSteadyTextStackHitsTheMemoAndMeasuresNothing() throws {
    let window = try TestWindow(size: sz(300, 200), textSystem: harnessTextSystem) {
        VStack { Color.clear.frame(width: Pixels(50), height: Pixels(20)); Text("a"); Text("b") }
    }
    for _ in 0..<2 { window.window.setNeedsRedraw(); window.tick() }
    window.resetFrameWork()
    for _ in 0..<3 { window.window.setNeedsRedraw(); window.tick() }
    let work = window.frameWork.dropFirst().reduce(window.frameWork[0], +)
    #expect(work.layoutMemoRootHits == 3, "root hits: \(work.layoutMemoRootHits)")
    #expect(work.layoutMeasureCalls == 0, "a steady text stack measures nothing: \(work.layoutMeasureCalls)")
}
