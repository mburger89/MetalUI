import Testing
import MetalUICore
@testable import MetalUILayout

/// A container asked for min-content must ask its children for min-content.
/// Before this task the leaf received `.maxContent` under both queries.
@Test func aContainersIntrinsicQueryReachesItsChildren() {
    let tree = LayoutTree(generation: 0)
    let leaf = tree.newLeaf(style: Style()) { _, available in
        if case .minContent = available.width { return SizeD(width: 30, height: 40) }
        return SizeD(width: 90, height: 20)
    }
    var row = Style()
    row.flexDirection = .row
    let container = tree.newNode(style: row, children: [leaf])

    let ctx = LayoutContext(rootFontSize: 16)
    let narrow = measureNode(ctx, tree, container, known: .unspecified,
                             available: AvailableSpaceSize(width: .minContent, height: .maxContent),
                             containingBlockWidth: nil)
    let wide = measureNode(LayoutContext(rootFontSize: 16), tree, container, known: .unspecified,
                           available: AvailableSpaceSize(width: .maxContent, height: .maxContent),
                           containingBlockWidth: nil)
    #expect(narrow.width == 30)
    #expect(wide.width == 90)
}

/// §9.9.1.1: under min-content the line budget is zero, so each item lines
/// alone. This is a WRAPPING fact, not a base-size fact — no amount of
/// `flexBaseSize` work reaches it, which is why `collectLines` is in scope here.
@Test func aWrapContainerUnderMinContentPutsEachItemOnItsOwnLine() {
    let tree = LayoutTree(generation: 0)
    var kid = Style()
    kid.size = Size(width: .length(.pixels(Pixels(40))),
                    height: .length(.pixels(Pixels(20))))
    let kids = (0..<3).map { _ in tree.newNode(style: kid, children: []) }
    var wrap = Style()
    wrap.flexDirection = .row
    wrap.flexWrap = .wrap
    let container = tree.newNode(style: wrap, children: kids)

    let narrow = measureNode(LayoutContext(rootFontSize: 16), tree, container,
                             known: .unspecified,
                             available: AvailableSpaceSize(width: .minContent, height: .maxContent),
                             containingBlockWidth: nil)
    let wide = measureNode(LayoutContext(rootFontSize: 16), tree, container,
                           known: .unspecified,
                           available: AvailableSpaceSize(width: .maxContent, height: .maxContent),
                           containingBlockWidth: nil)
    #expect(narrow == SizeD(width: 40, height: 60))
    #expect(wide == SizeD(width: 120, height: 20))
}

/// The CROSS axis of the query reaches the child too, and it is a **column**
/// that shows it: a column's cross axis is width, so the container's
/// `.minContent` width question has to survive as the *cross* available space
/// `flexBaseSize` offers the item.
///
/// This test exists because the fix's third edit was unguarded — reverting
/// `flexBaseSize`'s cross-axis fallback to its pre-task `?? .maxContent`
/// reddened **0 of 330**, while the doc comment on `measureNode` claimed the
/// two committed tests covered every site the query reaches. They cover the
/// main axis twice and the cross axis not at all.
///
/// **`min-height: 0` is load-bearing, not tidiness.** Without it, CSS Sizing
/// §4.5's automatic minimum probes the same leaf at `width: .maxContent`, gets
/// 77 back, and clamps the 33 up to 77 — hiding the effect completely. That
/// confounded the first probe written for this. The probe is max-content here
/// because this column has no definite width: with one, `collectItems` offers
/// the item's used width instead (`sizing_column_content_suggestion`), but the
/// fallback for an indefinite cross extent is still max-content.
@Test func theCrossAxisOfTheQueryReachesTheChildToo() {
    let tree = LayoutTree(generation: 0)
    var kid = Style()
    // Disable §4.5's automatic minimum, whose own probe is max-content in the
    // cross axis when the column has no width, and would clamp the
    // min-content answer back up.
    kid.minSize = Size(width: .auto, height: .length(.pixels(Pixels(0))))
    let leaf = tree.newLeaf(style: kid) { _, available in
        if case .minContent = available.width { return SizeD(width: 10, height: 33) }
        return SizeD(width: 10, height: 77)
    }
    var column = Style()
    column.flexDirection = .column
    let container = tree.newNode(style: column, children: [leaf])

    // Main axis (height) is max-content in both calls; only the CROSS axis
    // question changes, so nothing but the cross fallback can move the answer.
    let narrowCross = measureNode(LayoutContext(rootFontSize: 16), tree, container,
                                  known: .unspecified,
                                  available: AvailableSpaceSize(width: .minContent, height: .maxContent),
                                  containingBlockWidth: nil)
    let wideCross = measureNode(LayoutContext(rootFontSize: 16), tree, container,
                                known: .unspecified,
                                available: AvailableSpaceSize(width: .maxContent, height: .maxContent),
                                containingBlockWidth: nil)
    #expect(narrowCross.height == 33)
    #expect(wideCross.height == 77)
}

/// The **fourth** propagation site, and the one divergence 6's fix added:
/// `collectItems`' `ownCross`.
///
/// A column's own min-content width is the max over its items' min-content
/// widths, and an item with an `auto` cross size contributes through `ownCross`.
/// That probe's cross axis was hardcoded to `.maxContent` — deliberately, and
/// harmlessly, while `ownCross` *was* max-content — so a column reported the
/// same number for both of its intrinsic widths. Shrink-to-fit made that a wrong
/// answer: an auto-width column nested in a narrower one takes 200 where WebKit
/// gives 120 (`flex_column_fit_content_nested_auto`).
///
/// The width is what moves here; `theCrossAxisOfTheQueryReachesTheChildToo`
/// above covers `flexBaseSize`'s cross fallback and reads a **height**, so
/// neither test can stand in for the other.
///
/// **The oracle is the closure, not the engine**: 40 and 90 are written into the
/// measure function and the assertions read them back out through a container
/// that never sees them directly.
@Test func theCrossAxisQueryReachesAnAutoCrossItem() {
    let tree = LayoutTree(generation: 0)
    let leaf = tree.newLeaf(style: Style()) { _, available in
        if case .minContent = available.width { return SizeD(width: 40, height: 25) }
        return SizeD(width: 90, height: 25)
    }
    var column = Style()
    column.flexDirection = .column
    let container = tree.newNode(style: column, children: [leaf])

    // Neither call gives the column a width, so `containerCross` is indefinite
    // in both and only the QUESTION distinguishes them.
    let narrow = measureNode(LayoutContext(rootFontSize: 16), tree, container,
                             known: .unspecified,
                             available: AvailableSpaceSize(width: .minContent, height: .maxContent),
                             containingBlockWidth: nil)
    let wide = measureNode(LayoutContext(rootFontSize: 16), tree, container,
                           known: .unspecified,
                           available: AvailableSpaceSize(width: .maxContent, height: .maxContent),
                           containingBlockWidth: nil)
    #expect(narrow.width == 40)
    #expect(wide.width == 90)
}
