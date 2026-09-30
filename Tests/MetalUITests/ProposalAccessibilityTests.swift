import Testing
import MetalUICore
import MetalUIPlatform
@testable import MetalUI

// Plan task 12 part 2, lane 2 (spec `2026-09-29-accessibility-design.md` §7,
// tests 2.15–2.18; ruling `IX-AB`): the proposal path — `ProposalText`'s
// record, `AccessibilityModifier`, and images. Built with
// `AccessibilityModifierTests.swift`'s `accessibilityBuild`.

/// **2.15.** A `ProposalText` publishes its string as a static text: two texts
/// and a spacer publish the texts only (P1), a 2×2 grid its four texts row by
/// row (P2), a disabled scope `isEnabled == false`, and a hidden one nothing.
/// Mutation M2o (`ProposalText.prepaint` records nothing) must redden it.
@Test @MainActor func aProposalTextPublishesItsStringAsAStaticText() throws {
    let (_, p1) = try accessibilityBuild(HStack { ProposalText("A"); Spacer(); ProposalText("B") })
    #expect(p1.tree.readings == ["A", "B"] && p1.tree.nodes.count == 2, "P1: \(p1.tree.readings)")
    #expect(try p1.tree.one("A").node.role == .staticText && p1.tree.one("A").node.value == "A", "P1")

    let (_, p2) = try accessibilityBuild(Grid {
        GridRow { ProposalText("A"); ProposalText("B") }
        GridRow { ProposalText("C"); ProposalText("D") }
    })
    #expect(p2.tree.readings == ["A", "B", "C", "D"] && p2.tree.roots.count == 4, "P2: \(p2.tree.readings)")

    let (_, disabled) = try accessibilityBuild(HStack { ProposalText("A").disabled(true); ProposalText("B") })
    #expect(try !disabled.tree.one("A").node.isEnabled && disabled.tree.one("B").node.isEnabled, "disabled")

    let (_, hidden) = try accessibilityBuild(controlRoot {
        Box { HStack { ProposalText("H") } }.frame(width: 40, height: 20).hidden()
        Box { HStack { ProposalText("V") } }.frame(width: 40, height: 20)
    })
    #expect(hidden.tree.readings == ["V"], "a hidden one publishes nothing: \(hidden.tree.readings)")
}

/// **2.16.** A proposal accessibility modifier labels and distributes (P3: a
/// label on an `HStack` becomes each text's), labels a `Rectangle` as a group
/// (P5), and is ONE identity level: the content's id is `.child(of: wrapper,
/// at: 0)`. Over two nodes it traps naming the count (an exit test). Mutations
/// M2p (the wrapper records nothing) and M2p′ (content numbered at the
/// wrapper's own id) must redden it.
@Test @MainActor func aProposalAccessibilityModifierLabelsDistributesAndIsOneIdentityLevel() async throws {
    let (_, p3) = try accessibilityBuild(HStack { ProposalText("A"); ProposalText("B") }.accessibilityLabel("L"))
    #expect(p3.tree.readings == ["L", "L"] && p3.tree.roots.count == 2, "P3: \(p3.tree.readings)")
    let wrapper = GlobalElementID.child(of: nil, at: 0, name: nil)
    let stack = GlobalElementID.child(of: wrapper, at: 0, name: nil)
    let first = GlobalElementID.child(of: stack, at: 0, name: nil)
    #expect(p3.tree.roots.first == AccessibilityNodeID(first),
            "the content numbers from 0 under the wrapper: \(p3.tree.roots.map(\.base))")

    let (_, p5) = try accessibilityBuild(HStack {
        Rectangle().frame(width: 20, height: 20).accessibilityLabel("Swatch")
    })
    let swatch = try p5.tree.one("Swatch").node
    #expect(swatch.role == .group && swatch.label == "Swatch" && swatch.children.isEmpty, "P5: \(swatch)")

    let result = await #expect(processExitsWith: .failure, observing: [\.standardErrorContent]) {
        await MainActor.run {
            _ = try? accessibilityBuild(HStack { ForEach(0..<2) { i in ProposalText("\(i)") }.accessibilityLabel("x") })
        }
    }
    let stderr = String(decoding: result?.standardErrorContent ?? [], as: UTF8.self)
    #expect(stderr.contains("an accessibility modifier requires exactly one native child, got 2"),
            "aborted, but not at the wrapper's count check:\n\(stderr)")
}

/// **2.17.** The proposal modifiers mirror the styled ones on an `HStack`:
/// `.combine` joins (2.2's E3), `.accessibilityHidden(true)` removes (2.5's H1),
/// `.isHeader` distributes headings (2.7's T9), `.accessibilityAction {}`
/// distributes a press (2.11's A5). Mutation M2q (the wrapper drops its child
/// behaviour) must redden it.
@Test @MainActor func theProposalModifiersMirrorTheStyledOnes() throws {
    let (_, combined) = try accessibilityBuild(HStack { ProposalText("A"); ProposalText("B") }
        .accessibilityElement(children: .combine))
    try #require(combined.tree.nodes.count == 1, "combine: \(combined.tree.readings)")
    let a = try #require(combined.tree.nodes[combined.tree.roots[0]])
    #expect(a.role == .staticText && a.value == "A, B", "combine: \(a)")

    let (_, hidden) = try accessibilityBuild(VStack {
        HStack { ProposalText("A") }.accessibilityHidden(true)
        ProposalText("C")
    })
    #expect(hidden.tree.readings == ["C"], "hidden: \(hidden.tree.readings)")

    let (_, header) = try accessibilityBuild(HStack { ProposalText("A"); ProposalText("B") }
        .accessibilityAddTraits(.isHeader))
    #expect(try header.tree.one("A").node.role == .heading && header.tree.one("B").node.role == .heading,
            "header: \(header.tree.readings)")

    let (_, action) = try accessibilityBuild(HStack { ProposalText("A") }.accessibilityAction {})
    let pressed = try action.tree.one("A").node
    #expect(pressed.role == .button && pressed.actions == [.press], "action: \(pressed)")
}

/// **2.18.** `Image(_:scale:label:)` publishes an image labelled by its text
/// (I1, I3); a decorative image publishes nothing — plain (I2), labelled (I4)
/// or tapped (I5). Mutation M2r (the decorative init records too) must redden it.
@Test @MainActor func aLabelledImagePublishesAnImageAndADecorativeOneNothing() throws {
    let bitmap = ImageBitmap(width: 2, height: 2, rgba: [UInt8](repeating: 255, count: 16))
    let (_, i3) = try accessibilityBuild(HStack { Image(bitmap, scale: 1, label: Text("Logo")); ProposalText("V") })
    let logo = try i3.tree.one("Logo").node
    #expect(logo.role == .image && logo.label == "Logo", "I3: \(logo)")

    let decorative: [(String, @MainActor () throws -> AccessibilityBuild)] = [
        ("I2", { try accessibilityBuild(HStack { Image(decorative: bitmap, scale: 1); ProposalText("V") }).1 }),
        ("I4", { try accessibilityBuild(HStack { Image(decorative: bitmap, scale: 1).accessibilityLabel("Logo"); ProposalText("V") }).1 }),
        ("I5", { try accessibilityBuild(HStack { Image(decorative: bitmap, scale: 1).onTapGesture {}; ProposalText("V") }).1 }),
    ]
    for (arm, make) in decorative {
        let build = try make()
        #expect(build.tree.readings == ["V"] && build.tree.nodes.count == 1,
                "\(arm): nothing but the control text: \(build.tree.readings)")
    }
}
