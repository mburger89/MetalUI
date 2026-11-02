import MetalUI

/// The right-to-left layout section of the looks demo (`METALUI_LOOKS_DEMO=1`; human checks `LD1`-`LD5`, record 191, `LD-A`..`LD-H`): the same card
/// twice, left-to-right and right-to-left, so the mirrored layout can be compared by eye. It asserts nothing; a human looks.
///
/// **Its own `Component` and its own functions** (the 1 MB Windows stack budget, `everyProductionTreeBuildsOnAOneMegabyteThread`; `CI-AI`): the
/// card is `@inline(never)` and the two cards are composed by a generic function that holds only its own children.
struct LooksLayoutDirection: Component {
    var content: some ElementGroup {
        layoutDirectionSection(left: layoutDirectionCard(.leftToRight), right: layoutDirectionCard(.rightToLeft))
    }
}

/// The title and the two cards side by side.
@MainActor
private func layoutDirectionSection(left: some ProposalElementGroup, right: some ProposalElementGroup) -> some ProposalElementGroup {
    VStack(alignment: .leading, spacing: Pixels(8)) {
        Text("Layout direction - human checks LD1-LD5 (left-to-right, then right-to-left)").font(size: 14)
        HStack(alignment: .top, spacing: Pixels(24)) {
            left
            right
        }
    }
}

/// One card under `direction`: a stack, a leading frame, leading padding, an offset badge, a scaled and a rotated chip, a two-line text aligned
/// `.leading`, and a horizontal scroller.
@inline(never) @MainActor
private func layoutDirectionCard(_ direction: LayoutDirection) -> some ProposalElementGroup {
    VStack(alignment: .leading, spacing: Pixels(8)) {
        layoutDirectionChips()
        layoutDirectionAlignments()
        layoutDirectionText()
        layoutDirectionScroller()
    }
    .frame(width: Pixels(220), alignment: .topLeading)
    .environment(\.layoutDirection, direction)
}

@inline(never) @MainActor
private func layoutDirectionChips() -> some ProposalElementGroup {
    VStack(alignment: .leading, spacing: Pixels(6)) {
        HStack(spacing: Pixels(4)) {
            Color.red.frame(width: Pixels(24), height: Pixels(16))
            Color.blue.frame(width: Pixels(40), height: Pixels(16))
            Color.green.frame(width: Pixels(16), height: Pixels(16))
        }
        HStack(spacing: Pixels(12)) {
            Color.orange.frame(width: Pixels(14), height: Pixels(14)).offset(x: Pixels(12))
            Color.purple.frame(width: Pixels(20), height: Pixels(12)).scaleEffect(1.8, anchor: .leading)
            Color.teal.frame(width: Pixels(30), height: Pixels(6)).rotationEffect(.degrees(30), anchor: .leading)
        }
        .frame(height: Pixels(36))
    }
}

@inline(never) @MainActor
private func layoutDirectionAlignments() -> some ProposalElementGroup {
    VStack(alignment: .leading, spacing: Pixels(6)) {
        Color.gray.frame(width: Pixels(20), height: Pixels(12))
            .frame(maxWidth: .infinity, alignment: .leading)
        ProposalText("padded leading").padding(.leading, Pixels(24))
    }
}

@inline(never) @MainActor
private func layoutDirectionText() -> some ProposalElementGroup {
    ProposalText("Hi\nthere, a longer line").frame(maxWidth: .infinity, alignment: .leading)
}

@inline(never) @MainActor
private func layoutDirectionScroller() -> some ProposalElementGroup {
    ProposalScrollView(.horizontal) {
        HStack(spacing: Pixels(2)) {
            ForEach(0..<14) { index in
                ProposalText("\(index)").frame(width: Pixels(26), height: Pixels(20))
            }
        }
    }
    .frame(width: Pixels(180), height: Pixels(24))
}
