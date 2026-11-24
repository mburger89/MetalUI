import Testing
import MetalUICore
import MetalUIPlatform
@testable import MetalUI

// Ruling `AB-AH` (Sift gap G18): `accessibilityLabel(_:)` and
// `accessibilityValue(_:)` on a `Component`. Built with
// `AccessibilityModifierTests.swift`'s `accessibilityBuild`.

/// A body that draws one of two texts, as Sift's filter chip does.
private struct ChipText: Component {
    var rejected: Bool
    var content: some ElementGroup {
        if rejected { Text("bad") } else { Text("ok") }
    }
}

private struct TwoTexts: Component {
    var content: some ElementGroup {
        Text("A")
        Text("B")
    }
}

/// **G18.** A value declared on a component reaches the text whichever branch drew, and the text's own string stays
/// its label (the `Text("vol").accessibilityValue("5")` reading, AB-F R1). Mutation: `accessibilityValue` declares the
/// label instead (the node reads `L`, not the text) must redden it.
@Test @MainActor func aComponentsAccessibilityValueReachesTheTextOfEitherBranch() throws {
    for (rejected, text) in [(true, "bad"), (false, "ok")] {
        let (_, build) = try accessibilityBuild(HStack { ChipText(rejected: rejected).accessibilityValue("V") })
        try #require(build.tree.nodes.count == 1, "\(build.tree.readings)")
        let node = try #require(build.tree.nodes.values.first)
        #expect(node.role == .staticText && node.label == text && node.value == "V", "\(text): \(node)")
    }
}

/// A label and a value chain on one component: the label is the text's name, the value its value (Sift's
/// `Text(chip).accessibilityLabel(chip).accessibilityValue(error)`, on the component instead). Mutation: the
/// component label drops its declaration must redden it.
@Test @MainActor func aComponentsLabelAndValueChain() throws {
    let (_, build) = try accessibilityBuild(HStack {
        ChipText(rejected: true).accessibilityLabel("Filter").accessibilityValue("syntax error")
    })
    let node = try #require(build.tree.nodes.values.first)
    #expect(build.tree.nodes.count == 1 && node.label == "Filter" && node.value == "syntax error", "\(node)")
    let (_, labelled) = try accessibilityBuild(HStack { ChipText(rejected: true).accessibilityLabel("L") })
    #expect(try labelled.tree.one("L").node.role == .staticText, "a label alone is the text's reading: \(labelled.tree.readings)")
}

/// As SwiftUI's modifier on a stack distributes to each text (P3), one declaration on a two-text component reaches
/// both. Mutation: the layer registers no declaration (`declaring` no-ops) must redden it.
@Test @MainActor func aComponentsDeclarationDistributesToEachOfItsTexts() throws {
    let (_, build) = try accessibilityBuild(HStack { TwoTexts().accessibilityValue("V") })
    let values = build.tree.nodes.values.map { "\($0.label ?? "-")=\($0.value ?? "-")" }.sorted()
    #expect(values == ["A=V", "B=V"], "\(values)")
}

/// `AB-AH` item 2: over one member the wrapper is the member's own size, so the text sits where it did.
/// Mutation: the wrapper takes a padding (`Style()` becomes a padded one) must redden it.
@Test @MainActor func aComponentsAccessibilityWrapperLeavesAOneTextBodyWhereItWas() throws {
    let (_, plain) = try accessibilityBuild(HStack { Text("lead"); ChipText(rejected: true) })
    let (_, wrapped) = try accessibilityBuild(HStack { Text("lead"); ChipText(rejected: true).accessibilityValue("V") })
    func frame(_ build: AccessibilityBuild, _ text: String) throws -> Bounds<Pixels> {
        let id = try build.tree.one(text).id
        return try #require(build.tree.geometry[id]?.frame)
    }
    // The row is centred, so padding moves the text it holds and its neighbour in opposite senses: compare both.
    #expect(try frame(plain, "bad") == frame(wrapped, "bad") && frame(plain, "lead") == frame(wrapped, "lead"))
}
