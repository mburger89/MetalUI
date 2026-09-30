import Testing
import Metal
import MetalUICore
import MetalUIPlatform
@testable import MetalUI

// Plan task 12 part 2, lane 1 (spec `2026-09-29-accessibility-design.md` §7,
// tests 1.10, 1.13, 1.14; rulings `IX-Z` item 1, `IX-AA` item 1): the two
// requests that need no modifier — a press where hit testing is disabled, and
// an accessibility client setting a `List`'s selection. Through a real
// `Window` on a `FakePlatformWindow`; helpers are `ButtonTests.swift`'s
// `control…`. The two renamed pins (1.11, 1.12) stay in
// `AccessibilityTreeTests.swift` and `ListSelectionTests.swift`.

private typealias Request = MetalUIPlatform.AccessibilityRequest

private extension AccessibilityTree {
    /// The one node carrying `label`, or `nil` when none or several do.
    func id(labelled label: String) -> AccessibilityNodeID? {
        let matches = nodes.filter { $0.value.label == label }
        return matches.count == 1 ? matches.first?.key : nil
    }
}

@MainActor private final class Tally {
    var off = 0
    var disabled = 0
}

/// **1.10.** Under `allowsHitTesting(false)` an enabled element with an
/// `onClick` advertises `.press` (SwiftUI arm B6; divergence 28 retires,
/// `IX-Z` item 1), because the frame recorded its handler in
/// `accessibilityPressOnly`; a disabled one advertises nothing (B7); and a
/// window with no client records nothing. Mutations M1j (the press-only record
/// removed) and M1j′ (recorded without a client) must redden it.
@Test @MainActor func aPressIsAdvertisedWhereHitTestingIsDisabled() throws {
    let tally = Tally()
    @MainActor func content() -> some Element {
        Column {
            Box().frame(width: 40, height: 20).onClick { tally.off += 1 }
                .accessibilityLabel("off").allowsHitTesting(false)
            Box().frame(width: 40, height: 20).onClick { tally.disabled += 1 }
                .accessibilityLabel("disabled").allowsHitTesting(false).disabled(true)
        }
    }
    let (window, platform) = try controlWindow(size: 200) { content() }
    #expect(window.lastAccessibilityPressOnly.isEmpty, "no client: nothing is recorded")

    let tree = try controlTree(window, platform)
    let off = try #require(tree.id(labelled: "off"))
    let disabled = try #require(tree.id(labelled: "disabled"))
    #expect(tree.nodes[off]?.actions == [.press], "B6: the press is advertised")
    #expect(tree.nodes[disabled]?.actions == [], "B7: disabled advertises none")
    let offID = try #require(off.base as? GlobalElementID)
    let disabledID = try #require(disabled.base as? GlobalElementID)
    #expect(window.lastAccessibilityPressOnly[offID] != nil, "the frame recorded the press")
    #expect(window.lastAccessibilityPressOnly[disabledID] == nil, "and not the disabled one's")
    #expect(!window.lastHitboxes.contains { $0.id == offID }, "control: still no hitbox for it")
    #expect(tally.off == 0 && tally.disabled == 0)
}

// MARK: - Selection (`IX-AA` item 1)

private struct Item: Identifiable, Hashable { let id: Int }

@MainActor
private final class Selection {
    let items = (0..<5).map(Item.init)
    var single: Int?
    var multi: Set<Int>
    var singleWrites: [Int?] = []
    var multiWrites: [Set<Int>] = []

    init(single: Int? = nil, multi: Set<Int> = []) {
        self.single = single
        self.multi = multi
    }

    var singleBinding: Binding<Int?> {
        Binding(get: { self.single }, set: { self.single = $0; self.singleWrites.append($0) })
    }

    var multiBinding: Binding<Set<Int>> {
        Binding(get: { self.multi }, set: { self.multi = $0; self.multiWrites.append($0) })
    }
}

private func column(width: Float, height: Float? = nil) -> Style {
    var style = Style()
    style.flexDirection = .column
    style.size.width = .length(.pixels(controlPx(width)))
    style.flexShrink = 0
    if let height { style.size.height = .length(.pixels(controlPx(height))) }
    return style
}

/// `list` inside a 100-point vertical `ScrollView`, drawn until the window is
/// bounded (rows publish as `.row`s), a client active.
@MainActor
private func scrolled<C: ElementGroup>(@ElementBuilder _ list: @escaping @MainActor () -> C) throws
    -> (Window, FakePlatformWindow, AccessibilityTree) {
    let (window, platform) = try controlWindow(size: 100) {
        Box(style: column(width: 100, height: 100)) {
            ScrollView {
                Box(style: column(width: 100)) { list() }
            }
            .scrollIndicators(.hidden)
        }
    }
    platform.simulateAccessibilityRequest(.activate)
    var frames = 0
    window.setNeedsRedraw()
    while window.needsRedraw && frames < 6 {
        window.drawFrameIfNeeded()
        frames += 1
    }
    let tree = try #require(platform.publishedAccessibilityTrees.last, "no tree published")
    return (window, platform, tree)
}

/// The table and its rows by their text's index (`Row <i>`).
private func table(_ tree: AccessibilityTree) throws -> (AccessibilityNodeID, [Int: AccessibilityNodeID]) {
    let table = try #require(tree.nodes.first { $0.value.role == .table }?.key, "a table")
    var rows: [Int: AccessibilityNodeID] = [:]
    for row in tree.nodes[table]?.children ?? [] {
        guard tree.nodes[row]?.role == .row,
              let text = tree.nodes[row]?.children.compactMap({ tree.nodes[$0] }).first?.value,
              let index = Int(text.dropFirst(4)) else { continue }
        rows[index] = row
    }
    try #require(rows.count == 5, "five rows: \(rows.keys.sorted())")
    return (table, rows)
}

/// **1.13.** The outline's `.selectRows` sets exactly those rows: a single
/// list takes one (LA3) and ignores two, writing nothing (LA4); a multi list
/// takes both (LB2). Every row of a selectable list is `isSelectable`.
/// Mutation M1m (a single list takes the first of two) must redden it.
@Test @MainActor func settingTheOutlinesSelectedRowsSetsThemAndASingleListIgnoresTwo() throws {
    let singleModel = Selection(single: 2)
    let (singleWindow, singlePlatform, singleTree) = try scrolled {
        List(singleModel.items, selection: singleModel.singleBinding, rowHeight: controlPx(20)) { Text("Row \($0.id)") }
    }
    let (single, singleRows) = try table(singleTree)
    #expect(singleRows.values.allSatisfy { singleTree.nodes[$0]?.isSelectable == true }, "every row is selectable")
    #expect(singlePlatform.simulateAccessibilityRequest(.selectRows(single, [singleRows[1]!])))
    #expect(singleModel.singleWrites == [1], "LA3: one row is set: \(singleModel.singleWrites)")
    controlRedraw(singleWindow)
    _ = singlePlatform.simulateAccessibilityRequest(.selectRows(single, [singleRows[0]!, singleRows[4]!]))
    #expect(singleModel.singleWrites == [1], "LA4: two rows are ignored: \(singleModel.singleWrites)")

    let multiModel = Selection(multi: [1])
    let (multiWindow, multiPlatform, multiTree) = try scrolled {
        List(multiModel.items, selection: multiModel.multiBinding, rowHeight: controlPx(20)) { Text("Row \($0.id)") }
    }
    let (multi, multiRows) = try table(multiTree)
    #expect(multiPlatform.simulateAccessibilityRequest(.selectRows(multi, [multiRows[0]!, multiRows[4]!])))
    #expect(multiModel.multiWrites == [[0, 4]], "LB2: exactly those rows: \(multiModel.multiWrites)")
    #expect(!multiPlatform.simulateAccessibilityRequest(.selectRows(multiRows[0]!, [multiRows[1]!])),
            "a request naming a row as the table is refused")

    // Control: a list without `selection:` publishes rows no client may select.
    let plain = (0..<5).map(Item.init)
    let (plainWindow, plainPlatform, plainTree) = try scrolled {
        List(plain, rowHeight: controlPx(20)) { Text("Row \($0.id)") }
    }
    let (plainTable, plainRows) = try table(plainTree)
    #expect(plainRows.values.allSatisfy { plainTree.nodes[$0]?.isSelectable == false }, "not selectable")
    #expect(!plainPlatform.simulateAccessibilityRequest(.selectRows(plainTable, [plainRows[1]!])))
    #expect(!plainPlatform.simulateAccessibilityRequest(.select(plainRows[1]!)))
    // The platform holds its window weakly: keep every window alive to here,
    // or a request reaches nothing and a refusal passes for the wrong reason.
    withExtendedLifetime((singleWindow, multiWindow, plainWindow)) {}
}

/// **1.14.** A disabled list registers no selection handler, so a client's
/// `.select` is refused and writes nothing; the same list enabled selects
/// (the control). Mutation M1n (the handler registered past the disabled
/// gate) must redden it.
@Test @MainActor func aDisabledListRefusesAnAccessibilitySelection() throws {
    let disabledModel = Selection(multi: [0])
    let (disabledWindow, disabledPlatform, disabledTree) = try scrolled {
        List(disabledModel.items, selection: disabledModel.multiBinding, rowHeight: controlPx(20)) {
            Text("Row \($0.id)")
        }.disabled(true)
    }
    let (_, disabledRows) = try table(disabledTree)
    #expect(!disabledPlatform.simulateAccessibilityRequest(.select(disabledRows[3]!)))
    #expect(disabledModel.multiWrites.isEmpty, "nothing written: \(disabledModel.multiWrites)")
    #expect(disabledRows.values.allSatisfy { disabledTree.nodes[$0]?.isSelectable == false },
            "a disabled list's rows are not offered as selectable")

    let enabledModel = Selection(multi: [0])
    let (enabledWindow, enabledPlatform, enabledTree) = try scrolled {
        List(enabledModel.items, selection: enabledModel.multiBinding, rowHeight: controlPx(20)) {
            Text("Row \($0.id)")
        }.disabled(false)
    }
    let (_, enabledRows) = try table(enabledTree)
    #expect(enabledPlatform.simulateAccessibilityRequest(.select(enabledRows[3]!)))
    #expect(enabledModel.multiWrites == [[3]], "control: the enabled list selects: \(enabledModel.multiWrites)")
    withExtendedLifetime((disabledWindow, enabledWindow)) {}
}
