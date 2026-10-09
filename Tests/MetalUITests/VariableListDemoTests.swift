import Testing
import MetalUICore
import MetalUIPlatform
@testable import MetalUIDemoContent
@testable import MetalUI

// Variable-height `List`, lane 3 — the demo (ruling `VL-K`; spec
// `docs/superpowers/specs/2026-10-08-variable-height-list-design.md` §5 test
// 3.2, `VL-R` items 4–5). `METALUI_LIST_DEMO=1` opens
// `variableListDemoContent()` in both demos; this pins what human checks
// VL1–VL5 then look at: the demo is windowed (it builds fewer rows than its
// data) and it settles without input.
//
// **Red-before** (record §82 §6): the demo first landed without its
// `ScrollView` — every row built, the built-row assertion fails.

/// **3.2 (`VL-K`, `VL-R` items 4–5).** The demo in a 600 × 600 fake window,
/// an accessibility client active, element bounds recorded (each built row is
/// a named element, which is how the built rows are counted), drawn until it
/// asks for nothing; then the
/// scroller's stored offset is moved by 4000 and the window drawn until it
/// asks for nothing again.
///
/// Derived before the run. **Opening: 2 frames.** Frame 1 is the cold frame
/// (`MP-I`, `VL-L`): the list has no stored origin, so it builds and measures
/// all 300 rows at the list's width, stores its origin and index in
/// `prepaint`, finds its window stale and asks for one frame (`DD-F` item 3);
/// frame 2 windows against a fully measured index, so `D = 0` and the window
/// is not stale — it asks for nothing. **After the scroll: 1 frame.** Every
/// row is measured, so the frame at the new offset computes its anchor and
/// window from exact prefix offsets, records heights equal to the stored ones
/// (`D = 0`, no adjustment) and is not stale: it asks for nothing. Built rows
/// at rest: the rows in the ~500pt viewport plus overscan (2 above, 3 below,
/// `VL-F`) — fewer than 300, whatever the text system's line heights; the
/// table's `rowCount` is 300 and the published row indices are the built rows
/// (AB-L/AB-X). Mutation: remove the demo's `ScrollView` (every
/// row is built: the built-row assertion reddens).
@Test @MainActor
func theVariableListDemoSettlesHeadless() throws {
    // Pre-flight in a mode that reports (`PE-Z`): nothing unlowerable.
    let preflight = LayoutDifferential.report(width: 600, height: 600) { variableListDemoContent() }
    try #require(preflight.unlowerable.isEmpty, "\(preflight.unlowerable.map(\.description))")

    let (window, platform) = try makeFakeWindowOnDefaultDevice(size: 600) { variableListDemoContent() }
    platform.simulateAccessibilityRequest(.activate)
    window.recordsElementBounds = true
    var opening = 0
    while window.needsRedraw && opening < 12 {
        window.drawFrameIfNeeded()
        opening += 1
    }
    #expect(opening == 2, "frames to settle on opening: \(opening)")
    let atRest = builtRows(window)
    #expect(!atRest.isEmpty, "rows were built")
    #expect(atRest.count < variableListDemoItems.count, "windowed: \(atRest.count) rows built of 300")

    let scroller = try #require(window.lastScrollRegions.first, "the demo's scroller").id
    let before = window.stateTable.peek(scroller, as: ScrollState.self)?.offset ?? 0
    window.stateTable.withState(scroller, initial: ScrollState()) { $0.offset = before + 4000 }
    window.setNeedsRedraw()
    var scrolled = 0
    while window.needsRedraw && scrolled < 12 {
        window.drawFrameIfNeeded()
        scrolled += 1
    }
    #expect(scrolled == 1, "frames to settle after scrolling by 4000: \(scrolled)")
    let stored = window.stateTable.peek(scroller, as: ScrollState.self)?.offset ?? 0
    #expect(stored == before + 4000, "no adjustment and no clamp: \(stored)")

    let scrolledRows = builtRows(window)
    #expect(scrolledRows.count < variableListDemoItems.count, "windowed: \(scrolledRows.count) rows built of 300")
    #expect(scrolledRows.first.map { $0 > 0 } == true, "the window moved off row 0: \(scrolledRows)")
    // The published tree agrees: the table's logical count is the data's, and
    // the realised rows' indices are the built rows (AB-L, AB-X).
    let tree = try #require(platform.publishedAccessibilityTrees.last, "a published tree")
    #expect(tree.nodes.values.compactMap(\.rowCount) == [variableListDemoItems.count], "the table's logical count")
    #expect(tree.nodes.values.compactMap(\.rowIndex).sorted() == scrolledRows, "AX rows = built rows")
    withExtendedLifetime(window) {}
}

/// The row ids built this frame, sorted: each row is the named element
/// `child(of: list, at: 0, name: "<id>")` (`VL-J`), so its bounds are recorded
/// under a `.named` component holding a row id. Read from element bounds, not
/// the published tree, because an unbounded list publishes no rows (AB-X).
@MainActor
private func builtRows(_ window: Window) -> [Int] {
    window.lastElementBounds.keys.compactMap { id -> Int? in
        guard case .named(let name) = id.component, let row = Int(name.name),
              variableListDemoItems.indices.contains(row) else { return nil }
        return row
    }.sorted()
}
