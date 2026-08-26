import Testing
import MetalUICore
@testable import MetalUILayout

private func px(_ v: Double) -> MetalUICore.Dimension { .length(.pixels(Pixels(Float(v)))) }

@Test func definiteFlexBasisWins() {
    let tree = LayoutTree(generation: 0)
    var s = Style()
    s.flexBasis = px(120)
    s.size = Size(width: px(50), height: px(10))   // must be ignored
    let item = tree.newNode(style: s, children: [])
    #expect(flexBaseSize(tree, item: item, isRow: true,
                         containerMain: 700, containerCross: 100, rootFontSize: 16) == 120)
}

@Test func autoBasisFallsBackToTheDefiniteMainSize() {
    let tree = LayoutTree(generation: 0)
    var s = Style()
    s.flexBasis = .auto
    s.size = Size(width: px(80), height: px(10))
    let item = tree.newNode(style: s, children: [])
    #expect(flexBaseSize(tree, item: item, isRow: true,
                         containerMain: 700, containerCross: 100, rootFontSize: 16) == 80)
    // In a column the main axis is height, so the same style yields 10.
    #expect(flexBaseSize(tree, item: item, isRow: false,
                         containerMain: 700, containerCross: 100, rootFontSize: 16) == 10)
}

/// Step 2's main-size percentage must resolve against `containerMain`, never
/// `containerCross`. A pixel fixture can't catch a swapped axis argument —
/// pixels ignore both — so this uses a percentage main size with a container
/// whose main and cross extents are deliberately unequal: resolving against
/// the wrong one is arithmetically visible (300 vs 100), not just wrong by a
/// rounding hair.
@Test func autoBasisPercentageMainSizeResolvesAgainstContainerMainNotCross() {
    let tree = LayoutTree(generation: 0)
    var s = Style()
    s.flexBasis = .auto
    s.size = Size(width: .length(.percent(0.5)), height: px(10))
    let item = tree.newNode(style: s, children: [])
    // containerMain: 600, containerCross: 200 -> correct answer is 300 (50%
    // of 600). If the implementation resolved against containerCross
    // instead, it would report 100 (50% of 200).
    #expect(abs(flexBaseSize(tree, item: item, isRow: true,
                             containerMain: 600, containerCross: 200, rootFontSize: 16) - 300) < 1e-4)
}

/// Row-direction content sizing: the main axis (width) must reach the
/// measure function as *unknown* and offered at max-content, while the cross
/// axis (height) must reach it as *known* and offered as the definite
/// container-cross extent. The row-side mirror of
/// `columnContentSizeOffersKnownCrossAndMaxContentMain` — needed separately
/// because `available`'s cross-axis half lives on a different struct field
/// per direction (`height:` here, `width:` there), so hardcoding either
/// field to max-content is only visible from the direction that actually
/// routes its cross axis through that field.
@Test func autoBasisWithNoDefiniteSizeMeasuresContent() {
    let tree = LayoutTree(generation: 0)
    var s = Style()
    s.flexBasis = .auto                               // size stays .auto
    s.size = Size(width: .auto, height: px(20))        // cross (height) known; main (width) unknown
    let item = tree.newLeaf(style: s) { known, available in
        #expect(known.width == nil)
        #expect(known.height == 20)
        #expect(available.width == .maxContent)
        #expect(available.height == .definite(100))
        // Distinct width/height in the return, so an axis mix-up in the
        // final `isRow ? measured.width : measured.height` selection would
        // also show up in the assertion below.
        return SizeD(width: 137, height: 999)
    }
    #expect(flexBaseSize(tree, item: item, isRow: true,
                         containerMain: 700, containerCross: 100, rootFontSize: 16) == 137)
}

@Test func autoBasisWithNoMeasureFunctionIsZero() {
    let tree = LayoutTree(generation: 0)
    let item = tree.newNode(style: Style(), children: [])
    #expect(flexBaseSize(tree, item: item, isRow: true,
                         containerMain: 700, containerCross: 100, rootFontSize: 16) == 0)
}

/// Column-direction content sizing: the main axis (height) must reach the
/// measure function as *unknown* and offered at max-content, while the cross
/// axis (width) must reach it as *known* (from the item's own style) and
/// offered as the definite container-cross extent. Catches three mutations
/// that a row-only fixture cannot: `known` collapsing to all-nil, `known`'s
/// width/height branches swapping, and `available`'s cross-axis half being
/// hardcoded to max-content instead of the offered definite extent.
@Test func columnContentSizeOffersKnownCrossAndMaxContentMain() {
    let tree = LayoutTree(generation: 0)
    var s = Style()
    s.flexBasis = .auto
    s.size = Size(width: px(50), height: .auto)   // cross (width) known; main (height) unknown
    let item = tree.newLeaf(style: s) { known, available in
        #expect(known.width == 50)
        #expect(known.height == nil)
        #expect(available.width == .definite(300))
        #expect(available.height == .maxContent)
        // Distinct width/height in the return, so an axis mix-up in the
        // final `isRow ? measured.width : measured.height` selection would
        // also show up in the assertion below.
        return SizeD(width: 999, height: 77)
    }
    #expect(flexBaseSize(tree, item: item, isRow: false,
                         containerMain: 700, containerCross: 300, rootFontSize: 16) == 77)
}

@Test func percentageBasisResolvesAgainstTheContainerMainAxis() {
    let tree = LayoutTree(generation: 0)
    var s = Style()
    s.flexBasis = .length(.percent(0.25))
    let item = tree.newNode(style: s, children: [])
    #expect(abs(flexBaseSize(tree, item: item, isRow: true,
                             containerMain: 800, containerCross: 100, rootFontSize: 16) - 200) < 1e-4)
}
