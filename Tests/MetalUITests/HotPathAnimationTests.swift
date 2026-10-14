import Testing
import MetalUICore
import MetalUILayout
@testable import MetalUI

// Hot paths lane 2 (`HP-C`, spec tests 11-13 and 15): animation early-outs and the plain-loop
// `hasPercentEdge`. Every pin counts work or compares values; nothing reads a clock.

private let linear1 = Animation.linear(duration: 1)

@MainActor private func borderBox(_ width: Float) -> some Element {
    Box().cssWidth(Pixels(40)).cssHeight(Pixels(40)).background(.surface).border(.separator, width: Pixels(width))
}

@MainActor private func borderedRect(_ frame: Frame) -> MUIRect? {
    frame.scene.rects.first { $0.borderColor.a > 0 }
}

/// **HP.11 (spec test 11).** A settled tree builds no border-width track key: with nothing in flight and
/// a border that did not change, `AnimatedStyle.borderWidths` returns the declared border before it
/// builds any `"border.top"` string, and an element with no border builds none either. Red before:
/// the function built four strings per border per element per frame (counter 4 per call, 1 per edge).
/// Mutation 1: remove the `inFlight.isEmpty && d == p` early return (the counter reddens); mutation 2:
/// return `declared` while a width is in flight (`aChangedBorderWidthStillAnimatesAfterTheEarlyOut`).
@Test @MainActor func aSettledBorderlessTreeBuildsNoBorderWidthKeys() throws {
    let h = WrapperHarness()
    func tree(_ bordered: Bool) -> some Element {
        Column {
            Box().cssWidth(Pixels(40)).cssHeight(Pixels(40)).background(.surface)
            if bordered { borderBox(2) }
        }
    }
    h.frame(0, nil, tree(true))
    h.frame(0.1, nil, tree(true))
    let before = h.store.borderKeyBuilds
    h.frame(0.2, nil, tree(true))
    h.frame(0.3, nil, tree(true))
    #expect(h.store.borderKeyBuilds == before,
            "a settled tree, bordered or not, builds no border key: \(h.store.borderKeyBuilds - before) built")
    // The control: a change in flight does build keys, so the counter can move.
    h.frame(0.4, linear1, tree(false))
    h.frame(0.5, linear1, tree(true))
    #expect(h.store.borderKeyBuilds > before, "the counter moves when a border appears and disappears")
}

/// **HP.11b.** The values the early return must keep: a width change under a transaction interpolates
/// half-way at 0.5 s, lands exactly on the declared width, and the same change with no transaction snaps.
/// Mutation: return `declared` unconditionally when the keys are absent.
@Test @MainActor func aChangedBorderWidthStillAnimatesAfterTheEarlyOut() throws {
    let h = WrapperHarness()
    h.frame(0, nil, borderBox(2))
    h.frame(0.1, nil, borderBox(2))
    h.frame(0.2, linear1, borderBox(10))
    let mid = try #require(borderedRect(h.frame(0.7, nil, borderBox(10))), "the bordered rect")
    #expect(abs(mid.borderWidths.top - 6) < 0.01, "half-way 2 -> 10 is 6, got \(mid.borderWidths.top)")
    h.frame(1.3, nil, borderBox(10))
    let landed = try #require(borderedRect(h.frame(1.4, nil, borderBox(10))), "the bordered rect")
    #expect(landed.borderWidths.top == 10, "landed on 10, got \(landed.borderWidths.top)")
    let snap = try #require(borderedRect(h.frame(1.5, nil, borderBox(3))), "the bordered rect")
    #expect(snap.borderWidths.top == 3, "no transaction: snaps to 3, got \(snap.borderWidths.top)")
}

/// **HP.12 (spec test 12).** A settled proposal tree rebuilds no numeric track: every layer whose declared
/// numbers equal its baseline bit for bit takes the early return of `animatedNumbers` (no dictionary
/// copy, no state rebuilt, no comparison). `aSettledProposalTreeInterpolatesNothing` is unmoved. Red
/// before: the slow path ran for every layer every frame. Mutation: delete the early return.
@Test @MainActor func aSettledProposalTreeAllocatesNoTracks() throws {
    let h = WrapperHarness()
    func tree(_ w: Float) -> some Element {
        HStack(spacing: Pixels(0)) {
            Rectangle(width: Pixels(10), height: Pixels(10)).frame(width: Pixels(w), height: Pixels(40))
            Rectangle(width: Pixels(10), height: Pixels(10)).frame(width: Pixels(w), height: Pixels(41)).opacity(0.5)
        }
    }
    h.frame(0, nil, tree(50))
    h.frame(0.1, nil, tree(50))
    let before = h.store.numberTrackRebuilds
    h.frame(0.2, nil, tree(50))
    h.frame(0.3, nil, tree(50))
    #expect(h.store.numberTrackRebuilds == before,
            "a settled tree rebuilds no track: \(h.store.numberTrackRebuilds - before) rebuilt")
    #expect(h.store.lastFrameInterpolations == 0)
    h.frame(0.4, linear1, tree(80))
    #expect(h.store.numberTrackRebuilds > before, "a changed value takes the slow path (the counter can move)")
}

/// **HP.13 (spec test 13).** After the early return a changed value still animates: the width is half-way
/// at 0.5 s, an overshooting spring on an opacity is clamped to 1 while in flight, the declared value is
/// never clamped (a landed layer reads exactly what was declared), and the interpolation count equals the
/// pre-change literal (2 layers move: 2). Mutations: the early return ignoring a changed baseline (width
/// stays 100); removing the in-flight clamp (opacity above 1).
@Test @MainActor func aChangedValueStillAnimatesAndClampsAfterTheEarlyOut() throws {
    let h = WrapperHarness()
    func tree(_ w: Float, _ o: Float) -> some Element {
        HStack(spacing: Pixels(0)) {
            Rectangle(width: Pixels(10), height: Pixels(10)).frame(width: Pixels(w), height: Pixels(40))
                .background(.accent)
            Rectangle(width: Pixels(10), height: Pixels(10)).frame(width: Pixels(20), height: Pixels(41))
                .background(.accent).opacity(o)
        }
    }
    func width(_ f: Frame) -> Float? { f.scene.rects.first { $0.bounds.size.height == 40 }?.bounds.size.width }
    func alpha(_ f: Frame) -> Float? { f.scene.rects.first { $0.bounds.size.height == 41 }?.background.a }
    h.frame(0, nil, tree(100, 0.2))
    h.frame(0.1, nil, tree(100, 0.2))
    h.frame(0.2, linear1, tree(300, 1))
    #expect(h.store.lastFrameInterpolations == 2, "two layers move, got \(h.store.lastFrameInterpolations)")
    let mid = h.frame(0.7, nil, tree(300, 1))
    #expect(width(mid) == 200, "half-way width 200, got \(String(describing: width(mid)))")
    var peak: Float = 0
    let spring = Animation.spring(duration: 0.5, bounce: 0.7)
    let s = WrapperHarness()
    s.frame(0, nil, tree(100, 0.2))
    s.frame(0.1, nil, tree(100, 0.2))
    s.frame(0.2, spring, tree(100, 1))
    for i in 1...40 { peak = max(peak, alpha(s.frame(0.2 + Double(i) * 0.025, nil, tree(100, 1))) ?? 0) }
    #expect(peak <= 1 && peak > 0.9, "an overshooting spring is clamped to 1 in flight, peak \(peak)")
    let landed = h.frame(1.4, nil, tree(300, 1))
    h.frame(1.5, nil, tree(300, 1))
    #expect(width(landed) == 300 && alpha(landed) == 1, "landed on the declared values exactly")
    let before = h.store.numberTrackRebuilds
    h.frame(1.6, nil, tree(300, 1))
    #expect(h.store.numberTrackRebuilds == before, "and settled again: the early return resumes")
}

/// **HP.15 (spec test 15).** The plain-loop `edgesHavePercent` agrees with the closure form it replaced
/// for all 2^4 percent/point patterns of the four edges, so an edge cannot be omitted. Mutation: omit
/// `.left`.
@Test func edgesHavePercentAgreesWithItsClosureFormForEverySubset() {
    func reference(_ e: Edges<Length>) -> Bool {
        [e.top, e.right, e.bottom, e.left].contains { if case .percent = $0 { true } else { false } }
    }
    for mask in 0..<16 {
        func edge(_ bit: Int) -> Length { mask & (1 << bit) != 0 ? .percent(0.5) : .pixels(Pixels(4)) }
        let edges = Edges(top: edge(0), right: edge(1), bottom: edge(2), left: edge(3))
        #expect(edgesHavePercent(edges) == reference(edges), "mask \(mask)")
        #expect(edgesHavePercent(edges) == (mask != 0), "mask \(mask) has a percent edge exactly when nonzero")
    }
    #expect(!edgesHavePercent(Edges(all: Length.rems(Rems(1)))), "rems is not a percentage")
}
