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
