import MetalUI
import MetalUITesting
import Testing

// The greedy-sibling section of `docs/guides/layout.md` (HMK): the mirror of its swift block,
// copied by hand between the markers, and the two pins its prose cites.

// guide: layout #8
/// Two labels and a greedy filler: at priority -1 the filler takes the remainder only.
@MainActor
func layoutGreedyFiller() -> some Element {
    HStack(spacing: Pixels(0)) {
        ProposalText("A fairly long toolbar label").id("label")
        Color.clear.frame(maxWidth: .infinity).layoutPriority(-1).id("filler")
    }
    .frame(width: Pixels(200))
}
// end guide

@MainActor
private func greedyDefaultPriority() -> some Element {
    HStack(spacing: Pixels(0)) {
        ProposalText("A fairly long toolbar label").id("label")
        Color.clear.frame(maxWidth: .infinity).id("filler")
    }
    .frame(width: Pixels(200))
}

/// At the default priority the greedy filler is offered an equal share, so the label is narrower than
/// its ideal width. Mutation: add `.layoutPriority(-1)` to the filler (the label's width reaches ideal).
@Test @MainActor func theLayoutGuideAGreedyChildDilutesItsSiblings() throws {
    let diluted = try harnessWindow { greedyDefaultPriority() }
    let ideal = try harnessWindow { layoutGreedyFiller() }
    let narrow = try diluted.frame(ofID: "label").size.width.value
    let full = try ideal.frame(ofID: "label").size.width.value
    #expect(narrow < full, "diluted \(narrow), ideal \(full)")
}

/// At priority -1 the filler takes what is left: the label keeps its ideal width and the filler fills
/// the rest of the 200 points. Mutation: remove `.layoutPriority(-1)` from the guide's block.
@Test @MainActor func theLayoutGuideALowPriorityGreedyChildTakesOnlyTheRemainder() throws {
    let window = try harnessWindow { layoutGreedyFiller() }
    let label = try window.frame(ofID: "label"), filler = try window.frame(ofID: "filler")
    #expect(label.size.width.value + filler.size.width.value == 200, "read \(label.size.width.value) + \(filler.size.width.value)")
    #expect(filler.size.width.value > 0)
}
