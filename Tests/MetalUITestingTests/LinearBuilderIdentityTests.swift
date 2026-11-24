import MetalUI
import MetalUITesting
import Testing

// Ruling `PE-AB`: a block of eleven children is one `TupleGroup`, not a chain of `Pair`s, and the focus order, the
// accessibility ids and the tab walk of its children are what the chain gave (this test passes unchanged at `595c474a`, the
// `buildPartialBlock` build, whose paths it asserts).

@MainActor private func elevenButtons() -> some Element {
    HStack(spacing: Pixels(4)) {
        Button("0") { }.accessibilityIdentifier("b0")
        Button("1") { }.accessibilityIdentifier("b1")
        Button("2") { }.accessibilityIdentifier("b2")
        Button("3") { }.accessibilityIdentifier("b3")
        Button("4") { }.accessibilityIdentifier("b4")
        Button("5") { }.accessibilityIdentifier("b5")
        Button("6") { }.accessibilityIdentifier("b6")
        Button("7") { }.accessibilityIdentifier("b7")
        Button("8") { }.accessibilityIdentifier("b8")
        Button("9") { }.accessibilityIdentifier("b9")
        Button("10") { }.accessibilityIdentifier("b10")
    }
}

@Test @MainActor func elevenChildrenKeepTheirAccessibilityIdsAndTheirTabOrder() throws {
    let window = try harnessWindow(size: Size(width: Pixels(800), height: Pixels(100))) { elevenButtons() }
    let buttons = try window.elements(role: .button)
    let names = (0..<11).map { "b\($0)" }
    func path(_ id: GlobalElementID?) -> String {
        guard let id else { return "" }
        return path(id.parent) + "/\(id.component)"
    }
    let paths = buttons.map { path($0.id.base.base as? GlobalElementID) }
    #expect(paths == (0..<11).map { "/positional(0)/positional(\($0))" },
            "one flat index space under the stack, as the `Pair` chain gave: \(paths)")
    #expect(buttons.compactMap(\.identifier) == names, "the accessibility tree lists the children in source order")
    #expect(Set(buttons.map(\.id)).count == 11, "eleven distinct node ids")
    var walked: [String] = []
    for _ in 0..<11 {
        window.typeKey(.tab)
        walked.append(try window.focusedElement?.identifier ?? "-")
    }
    #expect(walked == names, "Tab walks the focus order b0 to b10, got \(walked)")
}
