import Testing
import Foundation
import MetalUICore
@testable import MetalUILayout

/// Browser evidence for the four sizing rules this milestone implements.
///
/// Every fixture here was RED against the engine that preceded its fix — that
/// is the file's entry condition, and it is what separates these from a corpus
/// that records the engine's own answer as correct.
private func px(_ v: Double) -> MetalUICore.Dimension { .length(.pixels(Pixels(Float(v)))) }

/// A percentage size on the root resolves against the offered extent, per axis.
///
/// The engine answered the offered 800x600 before this milestone: its root
/// resolved percentages against `nil` and fell through to the fallback. The two
/// percentages differ so that a width-basis bug (150 vs 200 on the height) is
/// visible as well as a no-basis one.
@Test func rootPercentageMatchesWebKit() throws {
    let golden = try loadGolden("sizing_root_percent")
    let tree = LayoutTree(generation: 0)

    var kidStyle = Style()
    kidStyle.size = Size(width: px(100), height: px(40))
    let kid = tree.newNode(style: kidStyle, children: [])

    var rootStyle = Style()
    rootStyle.display = .flex
    rootStyle.size = Size(width: .length(.percent(0.5)), height: .length(.percent(0.25)))
    let root = tree.newNode(style: rootStyle, children: [kid])

    computeLayout(tree, root: root,
                  available: AvailableSpaceSize(width: .definite(800), height: .definite(600)))

    assertMatchesGolden(tree, ids: [root: "root", kid: "kid"], golden: golden, tolerance: 0.5)
}

/// Ruling BM-4 — an over-constrained box grows its border box to fit its
/// padding and border, rather than clamping its content box to zero.
///
/// The two axes overflow by different amounts (20 horizontally, 60 vertically)
/// so an engine that grows one axis only, or grows by the wrong edge, cannot
/// pass by coincidence.
///
/// **`.box` IS GREEN as of Task 6 and `.kid` IS RED, and the red one is not a
/// defect in the engine — it is a defect in this fixture's HTML. Read this
/// before touching either side.**
///
/// The width history, because it took two tasks: Task 4 implemented BM-4 and
/// left the box at **130 × 140** — the height BM-4's grown 140, the width
/// §4.5's automatic minimum, the item's own min-content of `padding 100 +
/// border 20 + the 10pt child = 130`, a *higher* floor than BM-4's 120, and a
/// floor can only raise. Task 6 completed §4.5 to
/// `min(specified size suggestion, content size suggestion)` where the
/// specified suggestion is the item's USED preferred size — BM-4's 120, not
/// the declared 100 — so `min(120, 130) = 120` and the box now matches WebKit
/// exactly.
///
/// **`.kid` then reddened at 0 against this golden's 10, and the cause is that
/// the HTML and the Swift tree below are NOT the same tree.** `.box` in
/// `sizing_over_constrained_grows.html` declares no `display`, so it is a
/// **block** container and `.kid` is a block-level box that simply keeps its
/// declared 10 and overflows. `Style.display` defaults to `.flex` in this
/// engine, so the `boxStyle` built below is a **flex container** and `.kid` is
/// a flex item with `flex-shrink: 1` and an automatic minimum of
/// `min(10, 0) = 0`, which §9.7 shrinks to 0 in a content box that is now 0
/// wide. This engine has no block layout at all, so it cannot produce the
/// golden's 10 for any spelling of this tree.
///
/// **Measured through the oracle rather than argued** (throwaway probe, Task
/// 6, deleted): the identical HTML with `display: flex` added to `.box` gives
/// WebKit `box` 120×140 and **`kid` 0×10 at (60, 70)** — the engine's answer,
/// to the pixel. Adding `min-width: 0` to that flex `.box` changes nothing.
/// So the engine is right for the tree it is given and this golden records a
/// block-layout answer.
///
/// **The fix is one line of HTML plus a regeneration of this one golden**: add
/// `display: flex` to `.box` so the fixture says what the Swift tree says, and
/// regenerate — `kid.width` moves 10 → 0 and nothing else moves. That is a
/// correction of the fixture against the browser, not a regeneration to match
/// the engine, and Task 6 deliberately did **not** perform it: its brief
/// forbade adjusting a golden, and a golden moving is a finding to report
/// rather than a step to take. Whoever picks it up should re-run the probe
/// above rather than trusting this paragraph.
@Test func overConstrainedBoxGrowsLikeWebKit() throws {
    let golden = try loadGolden("sizing_over_constrained_grows")
    let tree = LayoutTree(generation: 0)

    var kidStyle = Style()
    kidStyle.size = Size(width: px(10), height: px(10))
    let kid = tree.newNode(style: kidStyle, children: [])

    var boxStyle = Style()
    boxStyle.size = Size(width: px(100), height: px(80))
    boxStyle.padding = Edges(top: .pixels(Pixels(60)), right: .pixels(Pixels(50)),
                             bottom: .pixels(Pixels(60)), left: .pixels(Pixels(50)))
    boxStyle.border = Edges(all: .pixels(Pixels(10)))
    let box = tree.newNode(style: boxStyle, children: [kid])

    var rootStyle = Style()
    rootStyle.display = .flex
    rootStyle.flexDirection = .row
    rootStyle.size = Size(width: px(400), height: px(300))
    let root = tree.newNode(style: rootStyle, children: [box])

    computeLayout(tree, root: root,
                  available: AvailableSpaceSize(width: .definite(800), height: .definite(600)))

    assertMatchesGolden(tree, ids: [root: "root", box: "box", kid: "kid"],
                        golden: golden, tolerance: 0.5)
}

/// Ruling FS-3 — §4.5's automatic minimum is
/// `min(specified size suggestion, content size suggestion)`, and this engine
/// implemented the content half only.
///
/// 130 is the discriminating declared width: flooring at the content 200 gives
/// 200/0, not flooring at all lets `.a` shrink to 75, and only the `min` gives
/// WebKit's 130/20. `.b` is empty and must NOT be floored — its content
/// suggestion is 0.
@Test func specifiedSizeSuggestionMatchesWebKit() throws {
    let golden = try loadGolden("sizing_specified_suggestion")
    let tree = LayoutTree(generation: 0)

    var gStyle = Style()
    gStyle.size = Size(width: px(200), height: px(20))
    let g1 = tree.newNode(style: gStyle, children: [])

    var aStyle = Style()
    aStyle.display = .flex
    aStyle.flexDirection = .row
    aStyle.size = Size(width: px(130), height: .auto)
    let a = tree.newNode(style: aStyle, children: [g1])

    var bStyle = Style()
    bStyle.size = Size(width: px(100), height: px(20))
    let b = tree.newNode(style: bStyle, children: [])

    var rootStyle = Style()
    rootStyle.display = .flex
    rootStyle.flexDirection = .row
    rootStyle.size = Size(width: px(150), height: px(60))
    let root = tree.newNode(style: rootStyle, children: [a, b])

    computeLayout(tree, root: root,
                  available: AvailableSpaceSize(width: .definite(800), height: .definite(600)))

    assertMatchesGolden(tree, ids: [root: "root", a: "a", b: "b", g1: "g1"],
                        golden: golden, tolerance: 0.5)
}

/// Ruling FS-3, second fixture — the specified size suggestion is the box's
/// **used** preferred size, not the number in the stylesheet.
///
/// `.a` declares 100 with 50+50 padding and 10+10 border, so ruling BM-4 makes
/// its used size 120; its 200-wide child makes its content suggestion 320. The
/// two readings of §4.5 therefore differ — `min(120, 320) = 120` against
/// `min(100, 320) = 100` — and `.b` absorbs the difference, 30 against 50.
///
/// **This exists because the milestone's other over-constrained fixture cannot
/// see the distinction, which was measured rather than assumed.** That one has
/// no shrinking sibling, so nothing forces `.a` below its base size; BM-4 has
/// already floored that base at 120 and an automatic minimum can only RAISE, so
/// both readings give 120 there. The declared-value mutant leaves it green.
/// A sibling that forces shrinking is what makes the floor bind and the two
/// readings separate.
@Test func theSpecifiedSizeSuggestionIsTheUsedSizeMatchesWebKit() throws {
    let golden = try loadGolden("sizing_specified_suggestion_is_used_value")
    let tree = LayoutTree(generation: 0)

    var gStyle = Style()
    gStyle.size = Size(width: px(200), height: px(20))
    let g1 = tree.newNode(style: gStyle, children: [])

    var aStyle = Style()
    aStyle.display = .flex
    aStyle.flexDirection = .row
    aStyle.size = Size(width: px(100), height: .auto)
    aStyle.padding = Edges(top: .pixels(Pixels(0)), right: .pixels(Pixels(50)),
                           bottom: .pixels(Pixels(0)), left: .pixels(Pixels(50)))
    aStyle.border = Edges(all: .pixels(Pixels(10)))
    let a = tree.newNode(style: aStyle, children: [g1])

    var bStyle = Style()
    bStyle.size = Size(width: px(100), height: px(20))
    let b = tree.newNode(style: bStyle, children: [])

    var rootStyle = Style()
    rootStyle.display = .flex
    rootStyle.flexDirection = .row
    rootStyle.size = Size(width: px(150), height: px(60))
    let root = tree.newNode(style: rootStyle, children: [a, b])

    computeLayout(tree, root: root,
                  available: AvailableSpaceSize(width: .definite(800), height: .definite(600)))

    assertMatchesGolden(tree, ids: [root: "root", a: "a", b: "b", g1: "g1"],
                        golden: golden, tolerance: 0.5)
}

/// Ruling TX-H — §9.4 step 7 measures an item's cross size from its USED main
/// size, after §9.7 has flexed it.
///
/// `.a` is a wrapping container of four 50x20 items, so its height depends on
/// the width it is laid out at: 200 wide is one line (20 tall), 120 wide is two
/// (40 tall). `align-items: flex-start` is load-bearing — under `stretch` an
/// item takes its cross size from the line and the two engines already agree.
@Test func crossSizeAfterFlexingMatchesWebKit() throws {
    let golden = try loadGolden("sizing_cross_after_flex")
    let tree = LayoutTree(generation: 0)

    let items = (0..<4).map { _ -> LayoutNodeID in
        var s = Style()
        s.size = Size(width: px(50), height: px(20))
        return tree.newNode(style: s, children: [])
    }

    var aStyle = Style()
    aStyle.display = .flex
    aStyle.flexDirection = .row
    aStyle.flexWrap = .wrap
    let a = tree.newNode(style: aStyle, children: items)

    var rootStyle = Style()
    rootStyle.display = .flex
    rootStyle.flexDirection = .row
    rootStyle.alignItems = .flexStart
    rootStyle.size = Size(width: px(120), height: px(600))
    let root = tree.newNode(style: rootStyle, children: [a])

    computeLayout(tree, root: root,
                  available: AvailableSpaceSize(width: .definite(800), height: .definite(600)))

    var ids: [LayoutNodeID: String] = [root: "root", a: "a"]
    for (n, node) in items.enumerated() { ids[node] = "i\(n + 1)" }
    assertMatchesGolden(tree, ids: ids, golden: golden, tolerance: 0.5)
}

/// Ruling FS-3's **second** guard clause — a percentage main size against an
/// indefinite container contributes no specified size suggestion.
///
/// **This fixture was added by the milestone's fix wave rather than by a task,
/// and it is the only one here that was GREEN on arrival.** The other four
/// were red against the engine that preceded their fix, which is this file's
/// stated entry condition; this one pins a clause that was already correct,
/// already browser-verified and reachable — and that no test in the 752 could
/// see. Mutating the guard from resolvability to the declaration
/// (`if case .auto = mainDim { return nil }`, the reading its own comment
/// forbids) moved `mid` 160→100, `p` 60→50 and `q` 100→50 and reddened
/// **nothing**. So the entry condition here is the mutation rather than the
/// engine's history: it must redden this test and it does.
///
/// The fixture's HTML carries why the shape needs all three of an indefinite
/// container, a `flex-basis: 0` and a content-bearing child; the short version
/// is that `own` maps an unresolvable axis to 0, so reading the declaration
/// gives a specified suggestion of 0 and floors the item at nothing.
@Test func percentageMainAgainstAnIndefiniteContainerMatchesWebKit() throws {
    let golden = try loadGolden("sizing_percent_main_against_indefinite")
    let tree = LayoutTree(generation: 0)

    var gStyle = Style()
    gStyle.size = Size(width: px(60), height: px(10))
    let g1 = tree.newNode(style: gStyle, children: [])

    var pStyle = Style()
    pStyle.display = .flex
    pStyle.flexDirection = .row
    pStyle.size = Size(width: .length(.percent(0.5)), height: .auto)
    pStyle.flexBasis = px(0)
    pStyle.flexGrow = 0
    let p = tree.newNode(style: pStyle, children: [g1])

    var qStyle = Style()
    qStyle.size = Size(width: px(100), height: px(10))
    let q = tree.newNode(style: qStyle, children: [])

    // No declared width: `mid` is sized at its own max-content, which is what
    // leaves `.p`'s `50%` with nothing to resolve against.
    var midStyle = Style()
    midStyle.display = .flex
    midStyle.flexDirection = .row
    let mid = tree.newNode(style: midStyle, children: [p, q])

    var rootStyle = Style()
    rootStyle.display = .flex
    rootStyle.flexDirection = .row
    rootStyle.alignItems = .flexStart
    rootStyle.size = Size(width: px(400), height: px(200))
    let root = tree.newNode(style: rootStyle, children: [mid])

    computeLayout(tree, root: root,
                  available: AvailableSpaceSize(width: .definite(800), height: .definite(600)))

    assertMatchesGolden(tree, ids: [root: "root", mid: "mid", p: "p", g1: "g1", q: "q"],
                        golden: golden, tolerance: 0.5)
}
