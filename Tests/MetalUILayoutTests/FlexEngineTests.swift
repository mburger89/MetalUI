import Testing
import Foundation
import MetalUICore
@testable import MetalUILayout

/// Build a tree from a fixture's shape by hand, run layout, and compare every
/// node against the browser's answer for the same fixture.
/// Qualified: this file imports Foundation, whose Measurement API also exports a
/// `Dimension` type, so the bare name is ambiguous here.
private func px(_ v: Double) -> MetalUICore.Dimension { .length(.pixels(Pixels(Float(v)))) }

private func fixedChild(_ tree: LayoutTree, w: Double, h: Double) -> LayoutNodeID {
    var s = Style()
    s.size = Size(width: px(w), height: px(h))
    return tree.newNode(style: s, children: [])
}

/// Compare every named node's computed rect against the browser's rounded box.
///
/// `sourceLocation` defaults to the call site so a disagreement is reported at
/// the test that failed, not inside this helper.
func assertMatchesGolden(
    _ tree: LayoutTree,
    root: LayoutNodeID,
    ids: [LayoutNodeID: String],
    golden: GoldenFile,
    tolerance: Double,
    sourceLocation: SourceLocation = #_sourceLocation
) {
    let byID = Dictionary(uniqueKeysWithValues: golden.rounded.map { ($0.id, $0) })
    for (node, id) in ids {
        let ours = tree.layout(node)
        guard let theirs = byID[id] else {
            Issue.record("golden '\(golden.fixture)' has no node '\(id)'",
                         sourceLocation: sourceLocation)
            continue
        }
        #expect(abs(ours.x - theirs.x) <= tolerance,
                "\(id).x: ours \(ours.x) vs WebKit \(theirs.x)", sourceLocation: sourceLocation)
        #expect(abs(ours.y - theirs.y) <= tolerance,
                "\(id).y: ours \(ours.y) vs WebKit \(theirs.y)", sourceLocation: sourceLocation)
        #expect(abs(ours.width - theirs.width) <= tolerance,
                "\(id).w: ours \(ours.width) vs WebKit \(theirs.width)", sourceLocation: sourceLocation)
        #expect(abs(ours.height - theirs.height) <= tolerance,
                "\(id).h: ours \(ours.height) vs WebKit \(theirs.height)", sourceLocation: sourceLocation)
    }
}

@Test func rowPacksFixedChildrenLeftToRight() {
    let tree = LayoutTree()
    let x = fixedChild(tree, w: 60, h: 20)
    let y = fixedChild(tree, w: 90, h: 30)
    let z = fixedChild(tree, w: 40, h: 50)
    var rootStyle = Style()
    rootStyle.flexDirection = .row
    rootStyle.size = Size(width: px(300), height: px(50))
    let root = tree.newNode(style: rootStyle, children: [x, y, z])

    computeLayout(tree, root: root,
                  available: AvailableSpaceSize(width: .definite(800), height: .definite(600)))

    #expect(tree.layout(root) == LayoutRect(x: 0, y: 0, width: 300, height: 50))
    #expect(tree.layout(x) == LayoutRect(x: 0,   y: 0, width: 60, height: 20))
    #expect(tree.layout(y) == LayoutRect(x: 60,  y: 0, width: 90, height: 30))
    #expect(tree.layout(z) == LayoutRect(x: 150, y: 0, width: 40, height: 50))
}

@Test func columnPacksFixedChildrenTopToBottom() {
    let tree = LayoutTree()
    let x = fixedChild(tree, w: 60, h: 20)
    let y = fixedChild(tree, w: 90, h: 30)
    let z = fixedChild(tree, w: 40, h: 50)
    var rootStyle = Style()
    rootStyle.flexDirection = .column
    rootStyle.size = Size(width: px(120), height: px(400))
    let root = tree.newNode(style: rootStyle, children: [x, y, z])

    computeLayout(tree, root: root,
                  available: AvailableSpaceSize(width: .definite(800), height: .definite(600)))

    #expect(tree.layout(x) == LayoutRect(x: 0, y: 0,  width: 60, height: 20))
    #expect(tree.layout(y) == LayoutRect(x: 0, y: 20, width: 90, height: 30))
    #expect(tree.layout(z) == LayoutRect(x: 0, y: 50, width: 40, height: 50))
}

/// Stored rects are absolute to the root, never relative to the parent.
///
/// `roundLayout` carries no cross-rect state: its whole no-drift guarantee rests
/// on callers handing it absolute coordinates. A flex engine naturally computes
/// parent-relative positions, so switching to them would look harmless here and
/// silently reintroduce the accumulation `roundLayout` exists to prevent. The
/// grandchildren below sit at a non-zero offset in BOTH axes, so this test fails
/// the moment anyone stores a parent-relative rect.
@Test func nestedContainersStoreAbsoluteNotRelativeCoordinates() {
    let tree = LayoutTree()
    let spacer = fixedChild(tree, w: 30, h: 40)

    let g1 = fixedChild(tree, w: 20, h: 25)
    let g2 = fixedChild(tree, w: 20, h: 35)
    var midStyle = Style()
    midStyle.flexDirection = .column
    midStyle.size = Size(width: px(100), height: px(150))
    let mid = tree.newNode(style: midStyle, children: [g1, g2])

    var rootStyle = Style()
    rootStyle.flexDirection = .row
    rootStyle.size = Size(width: px(300), height: px(200))
    let root = tree.newNode(style: rootStyle, children: [spacer, mid])

    computeLayout(tree, root: root,
                  available: AvailableSpaceSize(width: .definite(800), height: .definite(600)))

    #expect(tree.layout(mid) == LayoutRect(x: 30, y: 0, width: 100, height: 150))
    // Relative coordinates would put g1 at x = 0 and g2 at (0, 25).
    #expect(tree.layout(g1) == LayoutRect(x: 30, y: 0,  width: 20, height: 25))
    #expect(tree.layout(g2) == LayoutRect(x: 30, y: 25, width: 20, height: 35))
}

@MainActor
@Test func rowOfFixedChildrenMatchesWebKit() async throws {
    let golden = try await generateGolden(fixture: "flex_row_three_fixed",
                                          viewport: CGSize(width: 800, height: 600))
    let byID = Dictionary(uniqueKeysWithValues: golden.rounded.map { ($0.id, $0) })

    let tree = LayoutTree()
    let x = fixedChild(tree, w: 60, h: 20)
    let y = fixedChild(tree, w: 90, h: 30)
    let z = fixedChild(tree, w: 40, h: 50)
    var rootStyle = Style()
    rootStyle.flexDirection = .row
    rootStyle.size = Size(width: px(300), height: px(50))
    let root = tree.newNode(style: rootStyle, children: [x, y, z])
    computeLayout(tree, root: root,
                  available: AvailableSpaceSize(width: .definite(800), height: .definite(600)))

    for (node, id) in [(root, "root"), (x, "x"), (y, "y"), (z, "z")] {
        let ours = tree.layout(node)
        let theirs = try #require(byID[id])
        #expect(abs(ours.x - theirs.x) <= 0.1, "\(id).x: ours \(ours.x) vs WebKit \(theirs.x)")
        #expect(abs(ours.y - theirs.y) <= 0.1, "\(id).y: ours \(ours.y) vs WebKit \(theirs.y)")
        #expect(abs(ours.width - theirs.width) <= 0.1, "\(id).w: ours \(ours.width) vs WebKit \(theirs.width)")
        #expect(abs(ours.height - theirs.height) <= 0.1, "\(id).h: ours \(ours.height) vs WebKit \(theirs.height)")
    }
}

@MainActor
@Test func columnOfFixedChildrenMatchesWebKit() async throws {
    let golden = try await generateGolden(fixture: "flex_column_three_fixed",
                                          viewport: CGSize(width: 800, height: 600))

    let tree = LayoutTree()
    let x = fixedChild(tree, w: 60, h: 20)
    let y = fixedChild(tree, w: 90, h: 30)
    let z = fixedChild(tree, w: 40, h: 50)
    var rootStyle = Style()
    rootStyle.flexDirection = .column
    rootStyle.size = Size(width: px(120), height: px(400))
    let root = tree.newNode(style: rootStyle, children: [x, y, z])
    computeLayout(tree, root: root,
                  available: AvailableSpaceSize(width: .definite(800), height: .definite(600)))

    assertMatchesGolden(tree, root: root,
                        ids: [root: "root", x: "x", y: "y", z: "z"],
                        golden: golden, tolerance: 0.1)
}
