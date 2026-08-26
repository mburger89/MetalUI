import Testing
import Foundation
import MetalUICore
@testable import MetalUILayout

private func px(_ v: Double) -> MetalUICore.Dimension { .length(.pixels(Pixels(Float(v)))) }
private func pxL(_ v: Double) -> Length { .pixels(Pixels(Float(v))) }

private func fixedChild(_ tree: LayoutTree, w: Double, h: Double) -> LayoutNodeID {
    var s = Style()
    s.size = Size(width: px(w), height: px(h))
    return tree.newNode(style: s, children: [])
}

/// A container's padding and border inset its children's origins AND shrink the
/// space offered to them.
///
/// Four different edge values, and padding differs from border: with
/// `padding: 20 8 4 16` and `border: 5 3 2 7` the content box starts at
/// (16 + 7, 20 + 5) = (23, 25) and is
/// 400 - (16 + 7 + 8 + 3) = 366 wide, 100 - (20 + 5 + 4 + 2) = 69 tall.
/// Uniform values would let a transposed axis or a dropped edge pass.
@Test func paddingAndBorderInsetChildrenAndShrinkTheContentBox() {
    let tree = LayoutTree()
    let a = fixedChild(tree, w: 50, h: 30)
    let b = fixedChild(tree, w: 60, h: 30)
    var rootStyle = Style()
    rootStyle.flexDirection = .row
    rootStyle.size = Size(width: px(400), height: px(100))
    rootStyle.padding = Edges(top: pxL(20), right: pxL(8), bottom: pxL(4), left: pxL(16))
    rootStyle.border = Edges(top: pxL(5), right: pxL(3), bottom: pxL(2), left: pxL(7))
    let root = tree.newNode(style: rootStyle, children: [a, b])

    computeLayout(tree, root: root,
                  available: AvailableSpaceSize(width: .definite(800), height: .definite(600)))

    // The root's own border box is untouched — border-box sizing.
    #expect(tree.layout(root) == LayoutRect(x: 0, y: 0, width: 400, height: 100))
    // First child at the content-box origin, not (0, 0).
    #expect(tree.layout(a) == LayoutRect(x: 23, y: 25, width: 50, height: 30))
    // Second child packs after the first, still inside the content box.
    #expect(tree.layout(b) == LayoutRect(x: 73, y: 25, width: 60, height: 30))
}

/// The content box is what a stretched item fills, not the border box.
///
/// Cross-axis stretch must use the reduced extent: 100 tall with 20/4 padding
/// and 5/2 border leaves 69, not 100.
@Test func stretchFillsTheContentBoxNotTheBorderBox() {
    let tree = LayoutTree()
    var kidStyle = Style()
    kidStyle.size = Size(width: px(50), height: .auto)   // auto cross -> stretches
    let kid = tree.newNode(style: kidStyle, children: [])

    var rootStyle = Style()
    rootStyle.flexDirection = .row
    rootStyle.size = Size(width: px(400), height: px(100))
    rootStyle.padding = Edges(top: pxL(20), right: pxL(8), bottom: pxL(4), left: pxL(16))
    rootStyle.border = Edges(top: pxL(5), right: pxL(3), bottom: pxL(2), left: pxL(7))
    let root = tree.newNode(style: rootStyle, children: [kid])

    computeLayout(tree, root: root,
                  available: AvailableSpaceSize(width: .definite(800), height: .definite(600)))

    #expect(tree.layout(kid).height == 69)
    #expect(tree.layout(kid).y == 25)
}

/// A grow item's free space comes from the content box, so padding reduces what
/// it can grow into.
@Test func growDistributesTheContentBoxNotTheBorderBox() {
    let tree = LayoutTree()
    var s = Style()
    s.flexGrow = 1
    s.flexBasis = px(0)
    s.size = Size(width: .auto, height: px(20))
    let kid = tree.newNode(style: s, children: [])

    var rootStyle = Style()
    rootStyle.flexDirection = .row
    rootStyle.size = Size(width: px(400), height: px(100))
    rootStyle.padding = Edges(top: pxL(0), right: pxL(8), bottom: pxL(0), left: pxL(16))
    rootStyle.border = Edges(top: pxL(0), right: pxL(3), bottom: pxL(0), left: pxL(7))
    let root = tree.newNode(style: rootStyle, children: [kid])

    computeLayout(tree, root: root,
                  available: AvailableSpaceSize(width: .definite(800), height: .definite(600)))

    // 400 - (16 + 7 + 8 + 3) = 366
    #expect(tree.layout(kid).width == 366)
    #expect(tree.layout(kid).x == 23)
}
