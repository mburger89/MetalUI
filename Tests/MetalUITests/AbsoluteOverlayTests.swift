import Testing
import MetalUICore
import MetalUILayout
import MetalUIText
@testable import MetalUI

private func px(_ v: Float) -> Pixels { Pixels(v) }
private func dim(_ v: Float) -> MetalUICore.Dimension { .length(.pixels(Pixels(v))) }

private func sized(_ w: Float, _ h: Float) -> Style {
    var s = Style()
    s.size = Size(width: dim(w), height: dim(h))
    return s
}

/// The seam between the two halves of this milestone, pinned as behaviour:
/// **an absolute box positioned against the window is still clipped and
/// translated by an ancestor `ScrollView`, so it renders nothing.**
///
/// Layout places the box against its *containing block* — the root here, since
/// no ancestor is positioned — while paint applies every *ancestor's*
/// `clipped(to:offsetBy:)`, because a clip and a translation are properties of
/// the emission's position in the tree and know nothing about containing
/// blocks. The two mechanisms answer different questions and this composition
/// is where the answers disagree: the rect lands in window space and the mask
/// it carries is the viewport, so it is masked out entirely. CSS clips neither
/// — an absolutely-positioned descendant whose containing block sits outside
/// an `overflow` clipper escapes that clipper — and design spec §2 rejects
/// reproducing that coupling on purpose, because it would entangle layer
/// resolution with containing-block resolution. Recorded as CLAUDE.md's
/// divergence 11, whose other direction is divergence 10.
///
/// **`Deferred` is the escape, and the second half of this test is the
/// differential that says so.** The identical tree with the box wrapped in
/// `Deferred` carries the whole surface as its mask and does not move under
/// scroll — which is also what makes the first half meaningful, since "the
/// rect is masked out" would be equally true of a tree that never emitted it.
///
/// **A `ScrollView` genuinely narrower than the frame, with real overflow.**
/// The 41×60 viewport holds 80pt of content inside a 200×200 frame; a viewport
/// the size of the surface would make "the viewport's mask" and "the whole
/// surface" the same rect and a broken clip would read as correct.
///
/// If someone implements CSS's coupling, this test fails — which is the point.
/// It is a decision, not an accident, and the record (`Box.position(_:)`'s doc
/// comment and divergence 11) has to move with the behaviour.
@Test @MainActor func anAbsoluteBoxInsideAScrollViewIsStillClippedAndScrolledByIt() throws {
    var rootStyle = Style()
    rootStyle.flexDirection = .column
    rootStyle.padding = Edges(top: .pixels(px(30)), right: .pixels(px(0)),
                              bottom: .pixels(px(0)), left: .pixels(px(60)))

    // A row with an explicit height and cross-axis stretch is what bounds the
    // viewport's height at 60 against 80pt of content; `minSize.height = 0`
    // removes §4.5's automatic minimum, which would otherwise floor this
    // wrapper back up to its content's height and leave nothing to scroll.
    var wrapper = Style()
    wrapper.flexDirection = .row
    wrapper.alignItems = .stretch
    wrapper.size = Size(width: dim(60), height: dim(60))
    wrapper.minSize = Size(width: .auto, height: dim(0))

    var overlay = sized(22, 20)
    overlay.position = .absolute
    overlay.inset = Edges(top: dim(5), right: .auto, bottom: .auto, left: dim(5))

    func makeTree(deferring: Bool) -> some Element {
        Box(style: rootStyle) {
            Box(style: wrapper) {
                ScrollView(.vertical, elementID: ElementID("list")) {
                    Box(style: sized(40, 40)).background(.accent)
                    Box(style: sized(41, 40)).background(.accent)
                    if deferring {
                        Deferred { Box(style: overlay).background(.accent) }
                    } else {
                        Box(style: overlay).background(.accent)
                    }
                }
            }
        }
    }

    func render(_ tree: inout some Element, in table: StateTable) -> Frame {
        let frame = Frame(contentSize: Size(width: px(200), height: px(200)), scaleFactor: 1,
                          stateTable: table, theme: Theme.forAppearance(.light))
        frame.render(&tree)
        return frame
    }
    // The 22x20 declared size appears nowhere else in this tree, so it
    // identifies the overlay's rect without depending on emission order — the
    // scroll indicator is also in this scene.
    func overlayRect(_ scene: Scene) throws -> MUIRect {
        try #require(scene.rects.first { $0.bounds.size.width == 22 && $0.bounds.size.height == 20 })
    }

    let plainTable = StateTable()
    var plain = makeTree(deferring: false)
    let firstFrame = render(&plain, in: plainTable)
    let unscrolled = try overlayRect(firstFrame.finalizedScene())

    #expect(unscrolled.bounds.origin.x == 5 && unscrolled.bounds.origin.y == 5,
            "layout placed it against the ROOT — its containing block — at the window-space (5, 5)")
    #expect(unscrolled.contentMask.origin.x == 60 && unscrolled.contentMask.origin.y == 30,
            "paint masked it to the VIEWPORT, which starts at (60, 30) — not to the whole surface")
    #expect(unscrolled.contentMask.size.width == 41 && unscrolled.contentMask.size.height == 60,
            "and the viewport is genuinely smaller than the 200x200 surface")
    #expect(unscrolled.bounds.origin.x + unscrolled.bounds.size.width <= unscrolled.contentMask.origin.x,
            "the rect lies entirely left of its own mask, so it draws nothing at all")

    // Scroll the list. The overlay's own layout is unchanged — it was never in
    // flow — but the emission is translated with everything else under the
    // viewport's stack entry, so it leaves the window entirely.
    // 12, not a rounder number: 80pt of content in a 60pt viewport leaves 20pt
    // of travel, and `ScrollChrome.resolvedOffset` clamps anything past it — an
    // offset of 40 would silently become 20 and the assertion below would be
    // measuring the clamp rather than the translation.
    let listID = try #require(firstFrame.scrollRegions.first).id
    plainTable.withState(listID, initial: ScrollState()) { $0.offset = 12 }
    var scrolled = makeTree(deferring: false)
    let scrolledScene = render(&scrolled, in: plainTable).finalizedScene()
    let firstRow = try #require(scrolledScene.rects.first { $0.bounds.size.width == 40 })
    #expect(firstRow.bounds.origin.y == 18,
            "30 - 12: an in-flow sibling moved, which is what says the offset reached paint at all")
    let afterScroll = try overlayRect(scrolledScene)
    #expect(afterScroll.bounds.origin.y == -7,
            "5 - 12: the box positioned against the WINDOW scrolled with the list anyway, off the top of it")

    // The escape, on the identical tree.
    let portalTable = StateTable()
    var portal = makeTree(deferring: true)
    let portalRect = try overlayRect(render(&portal, in: portalTable).finalizedScene())
    #expect(portalRect.bounds.origin.x == 5 && portalRect.bounds.origin.y == 5)
    #expect(portalRect.contentMask.origin.x == 0 && portalRect.contentMask.origin.y == 0
                && portalRect.contentMask.size.width == 200 && portalRect.contentMask.size.height == 200,
            "Deferred resets the mask to the whole surface, so the same box is visible")
}
