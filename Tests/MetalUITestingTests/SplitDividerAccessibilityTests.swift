import Foundation
import MetalUI
import MetalUIPlatform
import MetalUIScene
import MetalUITesting
import Testing

// A split view's dividers as accessibility elements (ruling `HS-K`, `docs/superpowers/2026-10-30-split-view-decisions.md`;
// SwiftUI probe `docs/probes/swiftui-split-divider-ax.swift`): one `.splitter` per divider, its value the size in points of
// the pane before it, range 0...(the pair's total), orientation, a settable value that moves the divider as a drag does,
// no increment or decrement, disabled where the panes cannot move.

@MainActor private final class MemoryStore: SplitViewAutosaveStore {
    var saved: [String: [Double]] = [:]
    var writes = 0
    func paneSizes(forName name: String) -> [Double]? { saved[name] }
    func setPaneSizes(_ sizes: [Double], forName name: String) { saved[name] = sizes; writes += 1 }
}

@MainActor private func columns(_ window: TestWindow) -> [Float] {
    window.scene.rects.filter { $0.background.a > 0 && $0.bounds.size.height == 300 && $0.bounds.size.width > 1 }
        .sorted { $0.bounds.origin.x < $1.bounds.origin.x }.map { $0.bounds.size.width }
}

/// A (50...200, ideal 100) | B (no limits) | C (60...240, ideal 120): 398 points of panes at 400 wide.
@MainActor private func threePanes(store: MemoryStore? = nil, name: String? = nil,
                                   identifier: String? = nil) -> some Element {
    var split = HSplitView {
        Color.red.frame(minWidth: 50, idealWidth: 100, maxWidth: 200)
        Color.green
        Color.blue.frame(minWidth: 60, idealWidth: 120, maxWidth: 240)
    }
    if let name { split = split.splitViewAutosaveName(name, store: store) }
    if let identifier { split = split.splitViewDividerIdentifier(identifier) }
    return VStack(spacing: 0) { split }
}

@MainActor private func splitters(_ window: TestWindow) throws -> [TestElement] {
    try window.elements(role: .splitter)
}

@MainActor private func node(_ window: TestWindow, _ element: TestElement) throws -> AccessibilityNode {
    try #require(try window.accessibilityTree.nodes[element.id])
}

/// HS-K -- one splitter per divider, in order, with the orientation of its line, the size of the pane before it as its
/// value (a number in points, the probe's 133), the pair's total as its maximum and a settable value.
/// Mutation: the builder publishes the divider as a group (drop the `.splitter` role mapping), or the value is the pane
/// after the divider.
@Test @MainActor func everyDividerPublishesASplitterWithValueRangeAndOrientation() throws {
    let window = try harnessWindow { threePanes() }
    let found = try splitters(window)
    #expect(found.count == 2, "\(found.count)")
    let nodes = try found.map { try node(window, $0) }
    #expect(nodes.map(\.value) == ["100", "178"], "\(nodes.map(\.value))")
    #expect(nodes.map(\.orientation) == [.vertical, .vertical], "an HSplitView's dividers are vertical lines")
    #expect(nodes.map(\.numericRange) == [0...278, 0...298], "\(nodes.map(\.numericRange))")
    #expect(nodes.allSatisfy { $0.actions.contains(.setValue) && $0.isEnabled })
    #expect(found[0].frame.origin.x.value < found[1].frame.origin.x.value, "published in divider order")
}

/// HS-K -- a VSplitView's dividers are horizontal lines. Mutation: orientation is `.vertical` for both axes.
@Test @MainActor func aVSplitViewsDividerIsHorizontal() throws {
    let window = try harnessWindow {
        VSplitView {
            Color.red.frame(minHeight: 60, idealHeight: 100, maxHeight: .infinity)
            Color.green.frame(minHeight: 60, maxHeight: .infinity)
        }
    }
    let found = try splitters(window)
    #expect(found.count == 1)
    let n = try node(window, found[0])
    #expect(n.orientation == .horizontal)
    #expect(n.value == "169.5", "\(String(describing: n.value))")   // a fraction keeps its decimals; A's ideal 100 plus half the surplus
    #expect(n.numericRange == 0...299, "\(String(describing: n.numericRange))")
}

/// HS-K -- the probe: `NSSplitViewSplitter` has no increment or decrement (calling its inherited one raises), so none is
/// advertised and a request for one is refused. Mutation: the builder adds `.increment`/`.decrement` for a splitter.
@Test @MainActor func aSplitterHasNoIncrementOrDecrement() throws {
    let window = try harnessWindow { threePanes() }
    let first = try #require(try splitters(window).first)
    let n = try node(window, first)
    #expect(!n.actions.contains(.increment) && !n.actions.contains(.decrement) && !n.actions.contains(.press))
    #expect(try window.performAccessibilityAction(.increment, on: first) == false)
    #expect(columns(window) == [100, 178, 120])
}

/// HS-K -- setting the value moves the divider as a drag does: the pair keeps its total, the other pane keeps its size,
/// the value follows. Mutation: the set handler writes the second pane's size instead of the first's.
@Test @MainActor func settingTheValueMovesTheDividerLikeADrag() throws {
    let window = try harnessWindow { threePanes() }
    let first = try #require(try splitters(window).first)
    #expect(try window.setAccessibilityValue(130, on: first))
    #expect(columns(window) == [130, 148, 120], "\(columns(window))")
    let again = try splitters(window)
    #expect(try again.map { try node(window, $0).value } == ["130", "148"])
    // The same result as the drag of the harness test `draggingADividerResizesItsTwoNeighbours`.
    let dragged = try harnessWindow { threePanes() }
    dragged.drag(from: pt(100.5, 150), to: pt(130.5, 150))
    #expect(columns(dragged) == columns(window))
}

/// HS-C / HS-K -- a value below the pane's minimum clamps to it, one past its maximum clamps to it, and a value above
/// the pair's total is ignored (the probe: 1000 left the panes alone). Mutation: the set handler skips `dragged`'s
/// clamp; or it clamps a value above the total instead of ignoring it.
@Test @MainActor func aSetValueRespectsTheMinimaAndMaximaAndIgnoresOneBeyondTheTotal() throws {
    let window = try harnessWindow { threePanes() }
    let first = try #require(try splitters(window).first)
    try window.setAccessibilityValue(0, on: first)
    #expect(columns(window) == [50, 228, 120], "A stops at its minimum: \(columns(window))")
    try window.setAccessibilityValue(250, on: first)
    #expect(columns(window) == [200, 78, 120], "A stops at its maximum: \(columns(window))")
    try window.setAccessibilityValue(1000, on: first)
    #expect(columns(window) == [200, 78, 120], "beyond the total is ignored: \(columns(window))")
    let second = try #require(try splitters(window).last)
    try window.setAccessibilityValue(10, on: second)   // B 78 -> 10 would grow C past its 240 maximum
    #expect(columns(window) == [200, 10, 188], "B has no minimum, C stays under its 240 maximum: \(columns(window))")
}

/// HS-G / HS-K -- a set writes the autosave entry once, a set that changes nothing writes none.
/// Mutation: the set handler never writes the store; or writes it twice (once per pane).
@Test @MainActor func aSetValueWritesTheAutosaveEntryOnce() throws {
    let store = MemoryStore()
    let window = try harnessWindow { threePanes(store: store, name: "main") }
    let first = try #require(try splitters(window).first)
    #expect(store.writes == 0)
    try window.setAccessibilityValue(130, on: first)
    #expect(store.writes == 1, "\(store.writes)")
    #expect(store.saved["main"] == [130, 148, 120], "\(String(describing: store.saved["main"]))")
    try window.setAccessibilityValue(130, on: first)
    #expect(store.writes == 1, "no change, no write")
}

/// HS-K -- a divider whose panes cannot move (both fixed) is disabled, advertises nothing, and refuses a set.
/// Mutation: the builder leaves `isEnabled` as the record's.
@Test @MainActor func aDividerThatCannotMoveIsDisabled() throws {
    let window = try harnessWindow {
        HSplitView {
            Color.red.frame(width: 100)
            Color.green.frame(width: 100)
        }
    }
    let first = try #require(try splitters(window).first)
    let n = try node(window, first)
    #expect(!n.isEnabled && n.actions.isEmpty, "\(n.isEnabled) \(n.actions)")
    #expect(n.value == "100")
    #expect(try window.setAccessibilityValue(150, on: first) == false)
}

/// HS-K -- a disabled split view's dividers are disabled even where the panes could move. Mutation: the query ignores
/// the record's enabled state.
@Test @MainActor func aDisabledSplitViewsDividersAreDisabled() throws {
    let window = try harnessWindow { threePanes().disabled(true) }
    for element in try splitters(window) {
        let n = try node(window, element)
        #expect(!n.isEnabled && !n.actions.contains(.setValue))
    }
}

/// HS-K -- identifiers: none by default (SwiftUI has no way to name a divider, probe arm I); `splitViewDividerIdentifier`
/// gives each `prefix.index`. Mutation: every divider gets the bare prefix.
@Test @MainActor func dividerIdentifiersAreIndexDerivedAndOptIn() throws {
    let plain = try harnessWindow { threePanes() }
    #expect(try splitters(plain).map(\.identifier) == [nil, nil])
    let named = try harnessWindow { threePanes(identifier: "editor") }
    #expect(try splitters(named).map(\.identifier) == ["editor.0", "editor.1"])
    let second = try named.element(identifier: "editor.1")
    try named.setAccessibilityValue(150, on: second)
    #expect(columns(named) == [100, 150, 148], "\(columns(named))")
}

/// HS-K -- nested splits (record 310's depth-5 tree) give one distinct splitter per divider, alternating orientation, and
/// setting one moves only its own split. Mutation: a splitter's handler captures the outermost split's report.
@Test @MainActor func nestedSplitsGiveDistinctSplittersThatMoveOnlyTheirOwnSplit() throws {
    @inline(never) @MainActor func leaf(_ tag: Int) -> some ElementGroup {
        Color.red.opacity(Double(tag) / 100).frame(minWidth: 30, maxWidth: .infinity, minHeight: 30, maxHeight: .infinity)
    }
    @inline(never) @MainActor func tree() -> some ElementGroup {
        HSplitView {
            VSplitView {
                leaf(11)
                HSplitView {
                    leaf(12)
                    leaf(13)
                }
                .frame(minWidth: 30, maxWidth: .infinity, minHeight: 30, maxHeight: .infinity)
            }
            .frame(minWidth: 30, maxWidth: .infinity, minHeight: 30, maxHeight: .infinity)
            leaf(14)
        }
    }
    let window = try harnessWindow(size: sz(640, 480)) { VStack(spacing: 0) { tree() } }
    let found = try splitters(window)
    #expect(found.count == 3, "\(found.count)")
    #expect(Set(found.map(\.id)).count == 3)
    func leaves() -> [Int: Float] {
        var out: [Int: Float] = [:]
        for r in window.scene.rects where r.background.a > 0.1 && r.background.a < 0.3 {
            out[Int((r.background.a * 100).rounded())] = r.bounds.size.width
        }
        return out
    }
    let orientations = try found.map { try node(window, $0).orientation }
    #expect(orientations.filter { $0 == .vertical }.count == 2 && orientations.filter { $0 == .horizontal }.count == 1,
            "\(orientations)")
    let before = leaves()
    // The two vertical lines are the outer divider (full height) and the innermost one (a quarter of it).
    let vertical = try found.filter { try node(window, $0).orientation == .vertical }
    let inner = try #require(vertical.min { $0.frame.size.height.value < $1.frame.size.height.value })
    let text = try #require(try node(window, inner).value)
    let value = try #require(Double(text))
    try window.setAccessibilityValue(value + 20, on: inner)
    let after = leaves()
    #expect(after[12] == before[12]! + 20 && after[13] == before[13]! - 20, "\(before) -> \(after)")
    #expect(after[11] == before[11] && after[14] == before[14], "only the inner split's panes moved: \(before) -> \(after)")
}
