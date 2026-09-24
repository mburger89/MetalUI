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

/// The max clamp on §4.5's automatic minimum never takes an item below its own
/// padding and border: clamp first, ruling BM-4's floor last.
///
/// `.p` (no width, 80 of padding, a 200-wide child, `max-width: 50px`) is 80 in
/// WebKit; it was 280 before the clamp and is 50 with a clamp that skips the
/// floor. `.c` (`width: 100px; max-width: 40px`, 120 of padding and border) is
/// 120 in WebKit and was already 120 here — **because** the automatic minimum
/// was unclamped. Clamping the content suggestion alone, the obvious fix, gives
/// `.c` a floor of 40 and a width of 40, and without this fixture nothing in
/// the suite noticed.
///
/// The last three expectations are not WebKit's. They pin `borderBoxFloor`'s
/// documented composition 1, `.c` with `min-width: 0`: WebKit 120, this engine
/// 40. It goes through the explicit-`min-width` branch, not the automatic
/// minimum, so the clamp must leave it where it was. Pinned wrong on purpose,
/// so that closing it is a deliberate edit to this test rather than a side
/// effect nobody sees.
@Test func theClampedAutomaticMinimumIsStillFlooredByPaddingAndBorderMatchesWebKit() throws {
    func build(cMinZero: Bool) -> (tree: LayoutTree, root: LayoutNodeID, p: LayoutNodeID,
                                   pg: LayoutNodeID, c: LayoutNodeID, b: LayoutNodeID) {
        let tree = LayoutTree(generation: 0)

        var pgStyle = Style()
        pgStyle.size = Size(width: px(200), height: px(20))
        pgStyle.flexGrow = 0
        pgStyle.flexShrink = 0
        let pg = tree.newNode(style: pgStyle, children: [])

        var pStyle = Style()
        pStyle.display = .flex
        pStyle.flexDirection = .row
        pStyle.maxSize = Size(width: px(50), height: .auto)
        pStyle.padding = Edges(top: .pixels(Pixels(0)), right: .pixels(Pixels(40)),
                               bottom: .pixels(Pixels(0)), left: .pixels(Pixels(40)))
        let p = tree.newNode(style: pStyle, children: [pg])

        var cStyle = Style()
        cStyle.size = Size(width: px(100), height: px(20))
        cStyle.maxSize = Size(width: px(40), height: .auto)
        if cMinZero { cStyle.minSize = Size(width: px(0), height: .auto) }
        cStyle.padding = Edges(top: .pixels(Pixels(0)), right: .pixels(Pixels(50)),
                               bottom: .pixels(Pixels(0)), left: .pixels(Pixels(50)))
        cStyle.border = Edges(top: .pixels(Pixels(0)), right: .pixels(Pixels(10)),
                              bottom: .pixels(Pixels(0)), left: .pixels(Pixels(10)))
        let c = tree.newNode(style: cStyle, children: [])

        var bStyle = Style()
        bStyle.size = Size(width: px(50), height: px(20))
        let b = tree.newNode(style: bStyle, children: [])

        var rootStyle = Style()
        rootStyle.display = .flex
        rootStyle.flexDirection = .row
        rootStyle.size = Size(width: px(500), height: px(60))
        let root = tree.newNode(style: rootStyle, children: [p, c, b])

        computeLayout(tree, root: root,
                      available: AvailableSpaceSize(width: .definite(800), height: .definite(600)))
        return (tree, root, p, pg, c, b)
    }

    let auto = build(cMinZero: false)
    #expect(auto.tree.layout(auto.p).width == 80)
    #expect(auto.tree.layout(auto.c).width == 120)
    #expect(auto.tree.layout(auto.b).x == 200)

    // Composition 1 — WebKit 120, this engine 40. Not this change's site.
    let minZero = build(cMinZero: true)
    #expect(minZero.tree.layout(minZero.c).x == 80)
    #expect(minZero.tree.layout(minZero.c).width == 40)
    #expect(minZero.tree.layout(minZero.b).x == 120)
}
