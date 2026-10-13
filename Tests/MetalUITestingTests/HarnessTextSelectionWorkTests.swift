import MetalUIPlatform
import MetalUITesting
import Testing
@testable import MetalUI

// Spec §4 tests 4.15 and 4.19 (rulings SL-B, SL-J): the work the selection
// binding costs, counted through `TextSelection.conversionCount` (internal, so
// `@testable`). They count work, never time. Helpers are `HarnessTextSelectionTests`'.

/// 4.15 — a published value is not applied back and the field writes once per
/// input. One key writes the binding once; the frame it draws and three idle
/// frames after it write nothing and convert nothing (a re-applied echo would
/// convert once). Mutation: do not store `seenBinding` after publishing.
@available(macOS 15, *)
@Test @MainActor func aPublishedValueIsNotAppliedBackAndWritesOnce() throws {
    let model = SelModel("hello")
    let window = try fieldWindow(model)
    try focusField(window)
    let before = TextSelection.conversionCount
    window.typeText("X")
    #expect(model.published.count == 1, "one input, one write")
    let afterInput = TextSelection.conversionCount
    #expect(afterInput == before, "publishing builds a TextSelection and converts no index to an offset")
    for _ in 0..<3 { window.tick() }
    #expect(model.published.count == 1, "idle frames write nothing")
    #expect(TextSelection.conversionCount == afterInput, "and the echo is not converted back")
    window.click(at: pt(380, 150))
    #expect(model.published.count == 2, "a click is one more write")
}

/// 4.19 — a steady frame with a binding converts nothing, and a field with no
/// binding never converts or publishes at all. Mutation: compare converted ranges
/// each frame instead of `TextSelection` values.
@available(macOS 15, *)
@Test @MainActor func aSteadyFrameWithABindingConvertsNothing() throws {
    let model = SelModel("hello", selection: span(1, 3, in: "hello"))
    let window = try fieldWindow(model)
    try focusField(window)
    let settled = TextSelection.conversionCount
    #expect(settled > 0, "the first frame applied the binding: the counter is wired")
    for _ in 0..<5 {
        window.window.setNeedsRedraw()
        window.tick()
    }
    #expect(TextSelection.conversionCount == settled, "five rebuilt frames convert nothing")

    var plain = "hello"
    let unbound = try harnessWindow {
        TextField("Title", text: Binding(get: { plain }, set: { plain = $0 }))
    }
    try unbound.focus(unbound.element(label: "Title"))
    let start = TextSelection.conversionCount
    unbound.typeText("abc")
    unbound.click(at: pt(200, 150))
    unbound.typeKey("a", modifierFlags: .primary)
    #expect(plain == "abchello")
    #expect(TextSelection.conversionCount == start, "no binding, no conversion")
}
