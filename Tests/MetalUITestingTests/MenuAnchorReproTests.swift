import MetalUI
import MetalUITesting
import Testing

// XP-G29 repro (MA-A): a pull-down `Menu` under `.offset` presents at its
// layout position, not its drawn one. PLAIN imports.

/// The View menu of MetalCreator's `cubeControls`, shaped down: a `Menu` in a
/// `VStack` carrying `.offset`, in a pane that does not start at the window
/// origin.
@MainActor private func offsetMenuTree() -> some Element {
    HStack(spacing: 0) {
        Color.clear.frame(width: Pixels(120))
        VStack(alignment: .leading, spacing: 4) {
            Button("Home") {}
            Menu("View") {
                Button("Perspective") {}
                Button("Orthographic") {}
            }
        }
        .offset(x: Pixels(60), y: Pixels(40))
    }
}

@Test @MainActor func aMenuUnderOffsetPresentsAtItsDrawnLabel() throws {
    let window = try harnessWindow { offsetMenuTree() }
    let label = try window.element(label: "View")
    try window.click(label)
    let shown = try #require(window.platformWindow.presentedMenus.last)
    #expect(shown.at.x.value == label.frame.origin.x.value, "x is the drawn label's, offset included")
    #expect(shown.at.y.value == label.frame.origin.y.value + label.frame.size.height.value,
            "y is the drawn label's bottom, offset included")
}
