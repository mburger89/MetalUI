import Foundation
import MetalUI
import MetalUIScene
import MetalUITesting
import Testing

// Alloy gap G18 (`VT-D`, record 253): a vertical `TextField` reads its edit state in prepaint and paint with `readState` (a read,
// not a write) and writes its caret reveal compared, so an unfocused one retains like the one-line field (`RW-`), and a focused
// one that scrolls equals a retention-off window frame for frame.

private struct VTCard: Component, @MainActor Equatable {
    let value: Int
    static func == (l: VTCard, r: VTCard) -> Bool { l.value == r.value }
    var content: some ElementGroup {
        VStack(alignment: .leading, spacing: 4) {
            Text("Card = \(value)")
            TextField("name", text: (1...12).map { "line \($0)" }.joined(separator: "\n"), axis: .vertical, onChange: { _ in })
                .lineLimit(1...4)
            TextField("other", text: "", onChange: { _ in })
        }.frame(width: Pixels(200))
    }
}

/// **20** (`VT-D`): an unfocused vertical field's card replays its prepaint; a click, ⌘↓ (the caret reveal and its compared write),
/// a typed character, a wheel step and a click elsewhere each leave the retaining window equal to the retention-off one.
///
/// Mutation M20: `paintVerticalText` reading the edit state with `stateTable.peek` (a read nothing journals) traps
/// `unrecordedRead` under `METALUI_VERIFY_RETAINED=1`; the replay count of the quiet frame reddens it without that variable.
@Test @MainActor func anUnfocusedVerticalFieldReplaysAndAFocusedOneEqualsARetentionOffWindow() throws {
    let options = HeadlessPlatformWindow.Options(scaleFactor: 2, accessibilityClientActive: true)
    func make() throws -> TestWindow {
        try TestWindow(size: Size(width: Pixels(320), height: Pixels(300)), scaleFactor: 2, options: options,
                       textSystem: { harnessTextSystem() }) { VStack(spacing: 0) { VTCard(value: 1).equatable() } }
    }
    let on = try make(), off = try make()
    on.window.testingTimelineClockOffset = 0; off.window.testingTimelineClockOffset = 0
    off.window.testingRetainedSubtrees = false
    on.window.testingRetainedGraft = true
    func redraw() { for w in [on, off] { w.window.setNeedsRedraw(); w.tick() } }
    func compare(_ step: String) throws {
        let differences = try RPSnapshot(on).differences(from: RPSnapshot(off))
        #expect(differences.isEmpty, "after \(step): \(differences)")
    }
    for _ in 0..<16 { redraw() }
    try compare("warm")
    redraw()
    if !rsVerifying {
        let quiet = on.lastFrameWork
        #expect(quiet.retainedPrepaintHits > 0, "an unfocused vertical field's card replays: \(quiet.retainedPrepaintHits) of \(quiet.retainedHits)")
    }
    for w in [on, off] { try w.click(w.element(label: "name")) }
    try compare("focused")
    for w in [on, off] { w.typeKey(.downArrow, modifierFlags: .command) }
    try compare("at the end")
    for w in [on, off] { w.typeText("x") }
    try compare("typed")
    let frame = try on.element(label: "name").frame
    let center = Point(x: Pixels(frame.origin.x.value + frame.size.width.value / 2),
                       y: Pixels(frame.origin.y.value + frame.size.height.value / 2))
    for w in [on, off] { w.scroll(at: center, byDeltaX: 0, deltaY: 16) }
    try compare("a wheel step")
    for w in [on, off] { try w.click(w.element(label: "other")) }
    try compare("blurred")
    for _ in 0..<3 { redraw(); try compare("quiet after the blur") }
}
