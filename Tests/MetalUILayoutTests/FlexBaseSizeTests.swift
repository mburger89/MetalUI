import Testing
import MetalUICore
@testable import MetalUILayout

private func px(_ v: Double) -> MetalUICore.Dimension { .length(.pixels(Pixels(Float(v)))) }

@Test func definiteFlexBasisWins() {
    let tree = LayoutTree()
    var s = Style()
    s.flexBasis = px(120)
    s.size = Size(width: px(50), height: px(10))   // must be ignored
    let item = tree.newNode(style: s, children: [])
    #expect(flexBaseSize(tree, item: item, isRow: true,
                         containerMain: 700, containerCross: 100, rootFontSize: 16) == 120)
}

@Test func autoBasisFallsBackToTheDefiniteMainSize() {
    let tree = LayoutTree()
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

@Test func autoBasisWithNoDefiniteSizeMeasuresContent() {
    let tree = LayoutTree()
    var s = Style()
    s.flexBasis = .auto                              // size stays .auto
    let item = tree.newLeaf(style: s) { known, available in
        // A leaf that reports 137 wide at max-content.
        if case .maxContent = available.width { return SizeD(width: 137, height: 20) }
        return SizeD(width: 40, height: 20)
    }
    #expect(flexBaseSize(tree, item: item, isRow: true,
                         containerMain: 700, containerCross: 100, rootFontSize: 16) == 137)
}

@Test func autoBasisWithNoMeasureFunctionIsZero() {
    let tree = LayoutTree()
    let item = tree.newNode(style: Style(), children: [])
    #expect(flexBaseSize(tree, item: item, isRow: true,
                         containerMain: 700, containerCross: 100, rootFontSize: 16) == 0)
}

@Test func percentageBasisResolvesAgainstTheContainerMainAxis() {
    let tree = LayoutTree()
    var s = Style()
    s.flexBasis = .length(.percent(0.25))
    let item = tree.newNode(style: s, children: [])
    #expect(abs(flexBaseSize(tree, item: item, isRow: true,
                             containerMain: 800, containerCross: 100, rootFontSize: 16) - 200) < 1e-4)
}
