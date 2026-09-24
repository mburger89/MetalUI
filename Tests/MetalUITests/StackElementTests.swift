import Testing
import MetalUICore
import MetalUILayout
@testable import MetalUI

/// Hands back the `Style` (and `Decoration`) `element` stores — for a `Stack`,
/// the `Style` `Stack.init` built.
///
/// **Reads the element's own `StyledElement.style`, with no `Frame` and no
/// layout authority** (stage 7b, record §49 rows 238–240). Until stage 7b this
/// registered the element on a `.legacy` `Frame` and read the `Style` back off
/// the CSS tree (`LayoutTree.style`); a lowered `Stack` is a native node, whose
/// tree carries no `Style` at all, and the question these three tests ask was
/// never about the engine — it is what `Stack.init` writes, which is exactly
/// the stored `style` the engine is later handed. The observable twin (a
/// `Stack`'s alignment placing its children, under the proposal authority) is
/// `aLoweredStackPlacesFixedChildrenAtAllNineAlignmentsAsTheLegacyStackDoes`.
/// `throws` and `inout` are kept so the three callers' bodies are unchanged.
@MainActor
private func styleOfRoot<E: StyledElement>(_ element: inout E) throws -> (Style, Decoration) {
    (element.style, element.decoration)
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

/// Every one of the nine `Alignment` cases maps to the RIGHT
/// (`alignItems`, `justifyItems`) pair — and the nine pairs are distinct.
///
/// **The two assertions catch different bugs and neither subsumes the other.**
/// The per-case pair assertions catch a *permutation*: a mapping that sends
/// `.leading` to the trailing edge. The distinctness `#require` catches a
/// *collision*: two cases landing on one pair, which makes one of them
/// unreachable and would leave the pair assertions failing for two cases
/// without saying why.
///
/// **This test asserted distinctness ALONE until the milestone's final review,
/// and that left seven of the nine cases unguarded.** Only `.topLeading`
/// (`stackWritesDisplayAndBothAlignmentFields`) and `.center`
/// (`stackDefaultsToCentreNotStretch`) were pinned to values anywhere, and any
/// permutation of the other seven that fixes those two is still a bijection —
/// so distinctness is preserved and the suite stays green. Both of these
/// mutations of `Alignment.blockAxis`/`inlineAxis` passed all 529 tests:
///
/// ```swift
/// // in `inlineAxis`
/// case .topLeading, .trailing, .bottomLeading:  return .start    // was .leading
/// case .topTrailing, .leading, .bottomTrailing: return .end      // was .trailing
/// // in `blockAxis`, .top and .bottom swapped
/// ```
///
/// The first ships `Stack(alignment: .leading) { Badge() }` drawing the badge
/// on the *right*. Both redden this test now, and the second halves of the
/// `expected` rows below are what does it — the axis assignment
/// (`alignItems` = block, `justifyItems` = inline) is separately load-bearing
/// and is why the two mutations redden different rows rather than all nine.
@Test @MainActor func allNineAlignmentsMapToTheirPairAndTheNineAreDistinct() throws {
    // Read as a 3x3 grid: rows are the block (vertical) axis, columns the
    // inline (horizontal) one. Hand-derived from SwiftUI's own meaning of the
    // names, not from `Alignment`'s implementation.
    let expected: [(Alignment, AlignItems, JustifyItems)] = [
        (.topLeading,     .flexStart, .start),
        (.top,            .flexStart, .center),
        (.topTrailing,    .flexStart, .end),
        (.leading,        .center,    .start),
        (.center,         .center,    .center),
        (.trailing,       .center,    .end),
        (.bottomLeading,  .flexEnd,   .start),
        (.bottom,         .flexEnd,   .center),
        (.bottomTrailing, .flexEnd,   .end),
    ]
    var seen: Set<String> = []
    for (alignment, block, inline) in expected {
        var element = Stack(alignment: alignment) { Box() }
        let (style, _) = try styleOfRoot(&element)
        #expect(style.alignItems == block,
                "\(alignment) must map to alignItems \(block), got \(String(describing: style.alignItems))")
        #expect(style.justifyItems == inline,
                "\(alignment) must map to justifyItems \(inline), got \(String(describing: style.justifyItems))")
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
