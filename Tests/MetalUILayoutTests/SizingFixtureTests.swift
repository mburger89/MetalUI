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
/// **STILL RED after Task 4 implemented BM-4, on the WIDTH only, and that is
/// measured rather than a defect in the fix.** The engine now answers
/// **130 × 140**: the height is BM-4's grown 140, and the width is §4.5's
/// automatic minimum — the item's own min-content, `padding 100 + border 20 +
/// the 10pt child = 130` — which is a *higher* floor than BM-4's 120 and wins.
/// The plan's Ruling G worked the arithmetic as `max(100, 120) = 120` and did
/// not carry the automatic minimum through it; the two floors compose as
/// `max(130, 120)`.
///
/// **Task 6 is what turns it green**, and the differential says so exactly:
/// setting `min-width: 0` on `.box` — which replaces the automatic minimum
/// outright — makes this same tree measure **120 × 140** today, WebKit's
/// answer. What is missing is only §4.5's *specified* size suggestion, whose
/// value under `box-sizing: border-box` is the item's USED size, which BM-4
/// has just made 120: `min(120, 130) = 120`.
///
/// **One forward hazard Ruling G also did not carry, for whoever implements
/// Task 6.** At a box width of 120 the content box is 0, and `.kid` — a flex
/// item with `width: 10px`, `flex-shrink: 1` and an automatic minimum of 0 —
/// shrinks to **0** here, where this golden records WebKit's **10**. Measured:
/// forcing the 120 today (via `min-width: 0`) gives `kid` width 0. So Task 6
/// may turn this fixture green on `box` and red on `kid`; that is a §9.7
/// question, not a BM-4 one.
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
