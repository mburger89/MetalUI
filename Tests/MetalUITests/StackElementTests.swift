import Testing
import MetalUICore
import MetalUILayout
@testable import MetalUI

/// Runs `element.requestLayout` in a throwaway 200x200 frame and hands back
/// the `Style` the engine received for the root node, plus that node's id.
///
/// **Reads the `Style` straight off `LayoutTree`, not through any production
/// API** — nothing outside `MetalUI` can do this, and nothing needs to: a real
/// caller never sees a `Style` back out, it only sees the geometry the engine
/// produced from it. `LayoutPass.frame` and `Frame.tree` are both internal,
/// reachable here only because this file is `@testable import MetalUI`. This
/// mirrors `ScrollViewTests.laidOut` and `TextMeasureTests.laidOut` (build a
/// `Frame`, drive `requestLayout` directly, skip `Frame.render`) rather than
/// inventing a new idiom, generalised to read `Style` back instead of a
/// resolved rect — `computeRootLayout` is deliberately not called, since the
/// point is the `Style` `Stack.init` built, not what the engine did with it.
@MainActor
private func styleOfRoot<E: Element>(_ element: inout E) throws -> (Style, LayoutNodeID) {
    let frame = Frame(contentSize: Size(width: Pixels(200), height: Pixels(200)),
                      scaleFactor: 1)
    var pass = LayoutPass(frame: frame)
    let (root, _) = element.requestLayout(GlobalElementID.child(of: nil, at: 0, name: nil),
                                          pass: &pass)
    return (frame.tree.style(root), root)
}

/// `Stack.init` writes the substrate; `Style`'s defaults do not move.
///
/// The same division `Column.init` uses (ruling EP-8): the element translates
/// SwiftUI's single `Alignment` into `alignItems` + `justifyItems`, and a
/// hand-built `Style` still defaults to `nil` on both.
@Test @MainActor func stackWritesDisplayAndBothAlignmentFields() throws {
    var element = Stack(alignment: .topLeading) { Box() }
    let (style, _) = try styleOfRoot(&element)
    #expect(style.display == .stack)
    #expect(style.alignItems == .flexStart)
    #expect(style.justifyItems == .start)
    // The default has not moved.
    #expect(Style().display == .flex)
    #expect(Style().justifyItems == nil)
}

/// All nine `Alignment` cases map to a distinct (alignItems, justifyItems) pair.
/// A mapping where two cases collided would silently make one unreachable.
@Test @MainActor func allNineAlignmentsMapToDistinctPairs() throws {
    let all: [Alignment] = [.topLeading, .top, .topTrailing,
                            .leading, .center, .trailing,
                            .bottomLeading, .bottom, .bottomTrailing]
    var seen: Set<String> = []
    for a in all {
        var element = Stack(alignment: a) { Box() }
        let (style, _) = try styleOfRoot(&element)
        seen.insert("\(String(describing: style.alignItems)),\(String(describing: style.justifyItems))")
    }
    try #require(seen.count == 9, "nine alignments must give nine pairs, got \(seen.count)")
}

/// The default is `.center` — SwiftUI's answer, not CSS's `stretch`.
@Test @MainActor func stackDefaultsToCentreNotStretch() throws {
    var element = Stack { Box() }
    let (style, _) = try styleOfRoot(&element)
    #expect(style.alignItems == .center)
    #expect(style.justifyItems == .center)
}
