import Testing
import AppKit
import Metal
import MetalUICore
import MetalUIPlatform
@testable import MetalUIAppKit
@testable import MetalUI
import MetalUIDemoContent

// Plan task 10, part 2, lane 3: `List(selection:)` (ruling `DD-Z`, amended by
// `DD-AC` items 1, 2, 4 and 6) and the controls demo. Spec
// `2026-09-26-controls-and-selection-design.md` §7 and tests 3.1–3.16,
// 3.19–3.21. Helpers are `ButtonTests.swift`'s `control…`.
//
// **Two fixtures.** An unbounded list (no scroller: every row realised, rows
// publish as buttons, `DD-AC` item 6) at `rowHeight` 20 in a 400 × 400 column,
// and a bounded one inside a 100-point vertical `ScrollView` (rows publish as
// `.row`s after the scroller's first frame). Ids are computed, not searched:
// the root `Box` is `[0]`, an unbounded list `[0, 0]`; a scrolled list sits
// under the scroller's content `Box` (`[0, 0, 0, i]`, the scroller numbering
// its content directly, as `FocusTests.rowID` does). A row is named by its
// datum's id directly under the list (`ListRows` adds no level).

private typealias Request = MetalUIPlatform.AccessibilityRequest

private struct Item: Identifiable, Hashable {
    let id: Int
}

private struct Named: Identifiable, Hashable {
    let id: String
}

@MainActor
private final class Selection {
    var items: [Item]
    var single: Int?
    var multi: Set<Int>
    var singleWrites: [Int?] = []
    var multiWrites: [Set<Int>] = []

    init(count: Int = 5, single: Int? = nil, multi: Set<Int> = []) {
        self.items = (0..<count).map(Item.init)
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

private func column(width: Float? = nil, height: Float? = nil) -> Style {
    var style = Style()
    style.flexDirection = .column
    if let width { style.size.width = .length(.pixels(controlPx(width))); style.flexShrink = 0 }
    if let height { style.size.height = .length(.pixels(controlPx(height))); style.flexShrink = 0 }
    return style
}

private let unboundedListID = controlID([0, 0])

private func rowID(_ list: GlobalElementID, _ id: some CustomStringConvertible) -> GlobalElementID {
    GlobalElementID.child(of: list, at: 0, name: ElementID(id.description))
}

@MainActor
private func singleList(_ model: Selection, rowHeight: Float = 20) -> some Element {
    List(model.items, selection: model.singleBinding, rowHeight: controlPx(rowHeight)) { item in
        Text("Row \(item.id)")
    }
}

@MainActor
private func multiList(_ model: Selection, rowHeight: Float = 20) -> some Element {
    List(model.items, selection: model.multiBinding, rowHeight: controlPx(rowHeight)) { item in
        Text("Row \(item.id)")
    }
}

/// An unbounded list: a 400 × 400 column over `list`, one frame drawn.
@MainActor
private func unboundedWindow<L: ElementGroup>(@ElementBuilder _ list: @escaping @MainActor () -> L) throws
    -> (Window, FakePlatformWindow) {
    try controlWindow { Box(style: column(width: 400, height: 400)) { list() } }
}

/// A bounded list: a 100 × 100 vertical `ScrollView` over `list`, drawn until
/// the viewport is measured and the window is bounded.
@MainActor
private func scrolledWindow<C: ElementGroup>(@ElementBuilder _ content: @escaping @MainActor () -> C) throws
    -> (Window, FakePlatformWindow) {
    let (window, platform) = try controlWindow(size: 100) {
        Box(style: column(width: 100, height: 100)) {
            ScrollView {
                Box(style: column(width: 100)) { content() }
            }
            .scrollIndicators(.hidden)
        }
    }
    settle(window)
    return (window, platform)
}

private let scrolledContentID = controlID([0, 0, 0])

/// Draws until the window asks for nothing more (at most six frames).
@MainActor
private func settle(_ window: Window) {
    var frames = 0
    window.setNeedsRedraw()
    while window.needsRedraw && frames < 6 {
        window.drawFrameIfNeeded()
        frames += 1
    }
}

@MainActor
private func scrollOffset(_ window: Window) throws -> Double {
    let region = try #require(window.lastScrollRegions.first, "no scroller")
    return window.stateTable.peek(region.id, as: ScrollState.self)?.offset ?? 0
}

/// Clicks the centre of row `id`'s hitbox, with `modifiers` on both halves.
@MainActor
private func clickRow(_ window: Window, _ platform: FakePlatformWindow, _ row: GlobalElementID,
                      _ modifiers: Modifiers = []) throws {
    let hitbox = try #require(window.lastHitboxes.first { $0.id == row && $0.handlers.onClick != nil },
                              "row \(row) registered no click target")
    let point = controlCentre(hitbox.bounds)
    platform.simulateInput(.mouseDown(MouseEvent(position: point, modifiers: modifiers)))
    platform.simulateInput(.mouseUp(MouseEvent(position: point, modifiers: modifiers)))
    controlRedraw(window)
}

@MainActor
private func key(_ window: Window, _ platform: FakePlatformWindow, _ name: String,
                 _ modifiers: Modifiers = []) {
    platform.simulateInput(controlKey(name, modifiers))
    controlRedraw(window)
}

@MainActor
private func focusList(_ window: Window, _ list: GlobalElementID) throws {
    window.focus(list)
    controlRedraw(window)
    try #require(window.focusedElement == list, "control: the list takes focus")
}

private func kids(_ tree: AccessibilityTree, _ id: AccessibilityNodeID) -> [AccessibilityNode] {
    (tree.nodes[id]?.children ?? []).compactMap { tree.nodes[$0] }
}

/// The published nodes labelled `Row <i>`, by `i` — a row's own node (a
/// `.button` or a `.row`), or, for a `.row`, the node whose child is the text.
private func rowNodes(_ tree: AccessibilityTree) -> [Int: AccessibilityNode] {
    var result: [Int: AccessibilityNode] = [:]
    for (id, node) in tree.nodes {
        if node.role == .button, let label = node.label, label.hasPrefix("Row ") {
            result[Int(label.dropFirst(4))!] = node
        }
        if node.role == .row {
            let texts = kids(tree, id).compactMap(\.value)
            if let text = texts.first, text.hasPrefix("Row ") { result[Int(text.dropFirst(4))!] = node }
        }
    }
    return result
}

// MARK: - Pointer (`DD-Z` item 4)

/// **3.1.** A plain click selects exactly the clicked row: single `nil` → `2`;
/// multi `[1, 3]` → `[2]` (LB3's replace). M3a (a multi click inserts) must
/// redden it.
@Test @MainActor func aPlainClickSelectsExactlyTheClickedRow() throws {
    let single = Selection()
    let (singleWindow, singlePlatform) = try unboundedWindow { singleList(single) }
    try clickRow(singleWindow, singlePlatform, rowID(unboundedListID, 2))
    #expect(single.singleWrites == [2], "single: \(single.singleWrites)")

    let multi = Selection(multi: [1, 3])
    let (multiWindow, multiPlatform) = try unboundedWindow { multiList(multi) }
    try clickRow(multiWindow, multiPlatform, rowID(unboundedListID, 2))
    #expect(multi.multiWrites == [[2]], "multi: a plain click replaces the set: \(multi.multiWrites)")

    // 3.1b (`DD-Z` item 4, `DD-AH` item 3): a plain click on the sole selected
    // row of a multi list changes nothing, so writes nothing. V5 (a multi
    // click always writes) must redden it.
    let sole = Selection(multi: [2])
    let (soleWindow, solePlatform) = try unboundedWindow { multiList(sole) }
    try clickRow(soleWindow, solePlatform, rowID(unboundedListID, 2))
    try #require(sole.multi == [2], "control: row 2 stays selected")
    #expect(sole.multiWrites.isEmpty, "3.1b: no write when nothing changes: \(sole.multiWrites)")
}

/// **3.2.** The platform's shortcut modifier (⌘ on Apple, ctrl elsewhere,
/// `ControlKeys.selectionToggleModifier`) toggles a row in and out of a
/// multi-selection. M3b (the toggle replaces) must redden it.
@Test @MainActor func aShortcutClickTogglesARowInAMultiSelectionList() throws {
    let toggle = ControlKeys.selectionToggleModifier()
    #expect(ControlKeys.selectionToggleModifier(platform: .mac) == .command)
    #expect(ControlKeys.selectionToggleModifier(platform: .other) == .control)
    let model = Selection(multi: [1])
    let (window, platform) = try unboundedWindow { multiList(model) }
    try clickRow(window, platform, rowID(unboundedListID, 3), toggle)
    #expect(model.multi == [1, 3], "toggled in: \(model.multi)")
    try clickRow(window, platform, rowID(unboundedListID, 1), toggle)
    #expect(model.multi == [3], "toggled out: \(model.multi)")
    #expect(model.multiWrites == [[1, 3], [3]], "one write per click: \(model.multiWrites)")
}

/// **3.3.** ⇧-click selects the range from the anchor (the last plain click)
/// to the row. M3c (the range excludes the anchor) must redden it.
@Test @MainActor func aShiftClickSelectsTheRangeFromTheAnchor() throws {
    let model = Selection()
    let (window, platform) = try unboundedWindow { multiList(model) }
    try clickRow(window, platform, rowID(unboundedListID, 1))
    try #require(model.multi == [1], "control: the plain click anchors row 1")
    try clickRow(window, platform, rowID(unboundedListID, 3), .shift)
    #expect(model.multi == [1, 2, 3], "the anchor to the row, inclusive: \(model.multi)")
    // Backwards from the same anchor.
    try clickRow(window, platform, rowID(unboundedListID, 0), .shift)
    #expect(model.multi == [0, 1], "the anchor stays: \(model.multi)")

    // 3.3b (`DD-Z` item 7, `DD-AH` item 1): inside a scroller, where the
    // list's origin is written every frame into the same `ListOrigin` entry,
    // an anchor that is NOT the first selected row in data order survives
    // that write. Click 3, ⇧-click 1 → [1, 2, 3] (anchor 3), ⇧-click 4 →
    // [3, 4]. V3 (the origin write resets the entry) re-derives the anchor as
    // the first selected row and reads [1, 2, 3, 4].
    let scrolled = Selection(count: 10)
    let (scrolledWin, scrolledPlatform) = try scrolledWindow { multiList(scrolled) }
    let list = GlobalElementID.child(of: scrolledContentID, at: 0, name: nil)
    try clickRow(scrolledWin, scrolledPlatform, rowID(list, 3))
    try clickRow(scrolledWin, scrolledPlatform, rowID(list, 1), .shift)
    try #require(scrolled.multi == [1, 2, 3], "control: anchor 3 to row 1: \(scrolled.multi)")
    try clickRow(scrolledWin, scrolledPlatform, rowID(list, 4), .shift)
    #expect(scrolled.multi == [3, 4], "3.3b: the anchor survives the origin write: \(scrolled.multi)")
}

/// **3.4.** A single-selection list selects the clicked row whatever the
/// modifiers, and a shortcut click on the selected row keeps it. M3d (⌘
/// deselects in single mode) must redden it.
@Test @MainActor func aSingleSelectionListSelectsTheClickedRowWhateverTheModifiers() throws {
    let model = Selection(single: 1)
    let (window, platform) = try unboundedWindow { singleList(model) }
    try clickRow(window, platform, rowID(unboundedListID, 3), ControlKeys.selectionToggleModifier())
    #expect(model.single == 3, "a shortcut click selects: \(String(describing: model.single))")
    try clickRow(window, platform, rowID(unboundedListID, 0), .shift)
    #expect(model.single == 0, "a shift click selects: \(String(describing: model.single))")
    try clickRow(window, platform, rowID(unboundedListID, 0), ControlKeys.selectionToggleModifier())
    #expect(model.single == 0, "a shortcut click on the selected row keeps it: \(String(describing: model.single))")
    #expect(model.singleWrites == [3, 0], "a write only when the selection changes: \(model.singleWrites)")
}

/// **3.5.** A press on a row focuses its list (`DD-Z` item 5, through
/// `ClickDispatch.focusRequest`). M3e (no `focusRequest`) must redden it.
@Test @MainActor func aPressOnARowFocusesItsList() throws {
    let model = Selection()
    let (window, platform) = try unboundedWindow { singleList(model) }
    try #require(window.focusedElement == nil, "control: nothing is focused")
    try clickRow(window, platform, rowID(unboundedListID, 2))
    #expect(window.focusedElement == unboundedListID,
            "the list is focused: \(String(describing: window.focusedElement))")
}

// MARK: - Keyboard (`DD-Z` item 6; KY6, KY8)

/// **3.6 (KY6–KY6f).** ↓/↑ move a single selection; with nothing selected ↓
/// selects the first row and ↑ the last; at the ends nothing is written. M3f
/// (wrap at the ends) must redden it.
@Test @MainActor func theArrowsMoveASingleSelectionAndStopAtTheEnds() throws {
    let model = Selection(single: 1)
    let (window, platform) = try unboundedWindow { singleList(model) }
    try focusList(window, unboundedListID)
    key(window, platform, TextEditing.downArrow)
    #expect(model.singleWrites == [2], "KY6: \(model.singleWrites)")
    key(window, platform, TextEditing.upArrow)
    #expect(model.singleWrites == [2, 1], "KY6b: \(model.singleWrites)")

    func reset(_ value: Int?) { model.single = value; model.singleWrites = []; controlRedraw(window) }
    reset(nil)
    key(window, platform, TextEditing.downArrow)
    #expect(model.singleWrites == [0], "KY6c: nothing selected, ↓ selects the first: \(model.singleWrites)")
    reset(4)
    key(window, platform, TextEditing.downArrow)
    #expect(model.singleWrites.isEmpty && model.single == 4, "KY6d: ↓ at the last writes nothing: \(model.singleWrites)")
    reset(nil)
    key(window, platform, TextEditing.upArrow)
    #expect(model.singleWrites == [4], "KY6e: nothing selected, ↑ selects the last: \(model.singleWrites)")
    reset(0)
    key(window, platform, TextEditing.upArrow)
    #expect(model.singleWrites.isEmpty && model.single == 0, "KY6f: ↑ at the first writes nothing: \(model.singleWrites)")
}

/// **3.7 (KY8, KY8b, KY8e, KY8f, KY8g).** A plain arrow collapses a
/// multi-selection to one row; ⇧+arrow extends or shrinks from the anchor; a
/// plain arrow at the end collapses to the lead alone, a write. M3g (⇧ extends
/// from the lead, not the anchor) must redden it.
@Test @MainActor func aPlainArrowCollapsesAMultiSelectionAndShiftExtendsFromTheAnchor() throws {
    let model = Selection(multi: [1])
    let (window, platform) = try unboundedWindow { multiList(model) }
    try focusList(window, unboundedListID)
    key(window, platform, TextEditing.downArrow)
    #expect(model.multiWrites == [[2]], "KY8: \(model.multiWrites)")
    key(window, platform, TextEditing.downArrow, .shift)
    #expect(model.multiWrites.last == [2, 3] && model.multiWrites.count == 2, "KY8b: \(model.multiWrites)")
    key(window, platform, TextEditing.upArrow, .shift)
    #expect(model.multiWrites.last == [2] && model.multiWrites.count == 3, "KY8e: \(model.multiWrites)")
    key(window, platform, TextEditing.downArrow, .shift)
    key(window, platform, TextEditing.downArrow, .shift)
    #expect(Array(model.multiWrites.suffix(2)) == [[2, 3], [2, 3, 4]] && model.multiWrites.count == 5,
            "KY8f: \(model.multiWrites)")
    key(window, platform, TextEditing.downArrow)
    #expect(model.multiWrites.last == [4] && model.multiWrites.count == 6,
            "KY8g: ↓ at the end collapses to the lead, a write: \(model.multiWrites)")
    // 3.7c (`DD-Z` item 6, `DD-AH` item 3): with only the lead selected, a
    // plain ↓ at the end changes nothing, so writes nothing (`DD-Z`'s general
    // rule; the probe measured only KY8g). V6 (a multi arrow always writes)
    // must redden it.
    key(window, platform, TextEditing.downArrow)
    try #require(model.multi == [4], "control: still the lead alone: \(model.multi)")
    #expect(model.multiWrites.count == 6, "3.7c: no write when nothing changes: \(model.multiWrites)")

    // 3.7b (`DD-Z` item 7, `DD-AH` item 1): inside a scroller, the lead and
    // anchor survive the per-frame origin write. Click 3, ⇧↑ ⇧↑ → [1, 2, 3]
    // (anchor 3, lead 1), ⇧↓ → [2, 3]. V3 (the origin write resets the entry)
    // re-derives lead and anchor as row 1 and reads [1, 2].
    let scrolled = Selection(count: 10)
    let (scrolledWin, scrolledPlatform) = try scrolledWindow { multiList(scrolled) }
    let list = GlobalElementID.child(of: scrolledContentID, at: 0, name: nil)
    try clickRow(scrolledWin, scrolledPlatform, rowID(list, 3))
    try focusList(scrolledWin, list)
    key(scrolledWin, scrolledPlatform, TextEditing.upArrow, .shift)
    key(scrolledWin, scrolledPlatform, TextEditing.upArrow, .shift)
    try #require(scrolled.multi == [1, 2, 3], "control: anchor 3, lead 1: \(scrolled.multi)")
    key(scrolledWin, scrolledPlatform, TextEditing.downArrow, .shift)
    #expect(scrolled.multi == [2, 3], "3.7b: lead and anchor survive the origin write: \(scrolled.multi)")
}

/// **3.8 (KY8c, KY8d).** Neither ⌘A nor Space changes a selection. M3h (⌘A
/// selects all) must redden it.
@Test @MainActor func neitherCommandANorSpaceChangesASelection() throws {
    let model = Selection(multi: [2, 3])
    let (window, platform) = try unboundedWindow { multiList(model) }
    try focusList(window, unboundedListID)
    key(window, platform, "a", .command)
    key(window, platform, ControlKeys.space)
    #expect(model.multiWrites.isEmpty && model.multi == [2, 3], "KY8c, KY8d: \(model.multiWrites)")
    // Control: the list does take its arrows.
    key(window, platform, TextEditing.downArrow)
    #expect(!model.multiWrites.isEmpty, "control: an arrow writes")

    // A caller's `onKey` runs first (spec §4): claiming ↓ suppresses the move,
    // declining ↑ lets it run. M3v (the list's arrows before the caller's
    // `onKey`) must redden this arm.
    let claimed = Selection(single: 1)
    let (claimedWindow, claimedPlatform) = try unboundedWindow {
        List(claimed.items, selection: claimed.singleBinding, rowHeight: controlPx(20)) { Text("Row \($0.id)") }
            .onKey { $0.charactersIgnoringModifiers == TextEditing.downArrow }
    }
    try focusList(claimedWindow, unboundedListID)
    key(claimedWindow, claimedPlatform, TextEditing.downArrow)
    #expect(claimed.singleWrites.isEmpty, "the caller claimed ↓: \(claimed.singleWrites)")
    key(claimedWindow, claimedPlatform, TextEditing.upArrow)
    #expect(claimed.singleWrites == [0], "the caller declined ↑: \(claimed.singleWrites)")
}

// MARK: - What a row shows (`DD-Z` item 3)

/// **3.9 (LA1, LB1).** A selected row publishes `isSelected`; an unselected
/// one does not — single and multi, set by the model. M3i (the hint never set)
/// must redden it.
@Test @MainActor func aSelectedRowPublishesSelectedAndAnUnselectedOneDoesNot() throws {
    let single = Selection(single: 2)
    let (singleWindow, singlePlatform) = try scrolledWindow { singleList(single) }
    let singleRows = rowNodes(try controlTree(singleWindow, singlePlatform))
    try #require(singleRows.count == 5, "control: five rows publish, read \(singleRows.keys.sorted())")
    #expect(singleRows.filter { $0.value.isSelected }.map(\.key) == [2], "LA1")

    let multi = Selection(multi: [1, 3])
    let (multiWindow, multiPlatform) = try scrolledWindow { multiList(multi) }
    let multiRows = rowNodes(try controlTree(multiWindow, multiPlatform))
    try #require(multiRows.count == 5)
    #expect(multiRows.filter { $0.value.isSelected }.map(\.key).sorted() == [1, 3], "LB1")
}

/// **3.10 (LA5).** A selection naming a removed row is kept — nothing written —
/// and the row is selected again when it returns. M3j (stale ids pruned) must
/// redden it.
@Test @MainActor func aSelectionNamingARemovedRowIsKeptAndReselectsItOnReturn() throws {
    let model = Selection(single: 4)
    let (window, platform) = try scrolledWindow { singleList(model) }
    _ = try controlTree(window, platform)
    model.items.removeLast()
    controlRedraw(window)
    controlRedraw(window)
    #expect(model.singleWrites.isEmpty && model.single == 4, "no write: \(model.singleWrites)")
    model.items.append(Item(id: 4))
    controlRedraw(window)
    controlRedraw(window)
    let tree = try #require(platform.publishedAccessibilityTrees.last)
    #expect(rowNodes(tree)[4]?.isSelected == true, "row 4 is selected again")
}

/// **3.11 (LD0).** A disabled list shows its selection and changes nothing:
/// clicks register no target, the list takes no focus, so arrows write
/// nothing. M1g (the central gate's `enabled` conjunct removed) must redden it.
@Test @MainActor func aDisabledListShowsItsSelectionAndChangesNothing() throws {
    let model = Selection(single: 4)
    let (window, platform) = try unboundedWindow { singleList(model).disabled(true) }
    let tree = try controlTree(window, platform)
    let rows = rowNodes(tree)
    try #require(rows.count == 5, "control: five rows publish, read \(rows.keys.sorted())")
    #expect(rows[4]?.isSelected == true, "LD0: the selection shows")
    #expect(rows.values.allSatisfy { !$0.isEnabled }, "every row publishes disabled")
    #expect(!window.lastHitboxes.contains { $0.id == rowID(unboundedListID, 2) },
            "a disabled row registers no click target")
    // The row's own rect, from the enabled twin's geometry: row 2 at y 40.
    controlClick(platform, at: Point(x: controlPx(50), y: controlPx(50)))
    window.focus(unboundedListID)
    controlRedraw(window)
    #expect(window.focusedElement == nil, "a disabled list takes no focus")
    key(window, platform, TextEditing.downArrow)
    #expect(model.singleWrites.isEmpty && model.single == 4, "nothing written: \(model.singleWrites)")
    let bg = window.lastScene.rects.first { $0.bounds.origin.y == 80 && $0.bounds.size.height == 20 }
    #expect(bg != nil, "the selected row still paints its background")
}

/// **3.12.** 100 rows at 20 in a 100-point viewport, the lead at the last
/// visible row: ↓ selects row 5 and scrolls it just into view (offset 20),
/// realising it. **3.12b** (`DD-AC` item 2): a sibling above the list whose
/// `.id` equals the lead's datum id does not take the scroll. M3k (no reveal
/// request) reddens both; M3k′ (the request keyed by the bare `datum.id`)
/// reddens 3.12b.
@Test @MainActor func anArrowPastTheWindowScrollsTheNewLeadIntoView() throws {
    let model = Selection(count: 100, single: 4)
    let (window, platform) = try scrolledWindow { singleList(model) }
    let list = GlobalElementID.child(of: scrolledContentID, at: 0, name: nil)
    try #require(try scrollOffset(window) == 0, "control: unscrolled")
    try focusList(window, list)
    key(window, platform, TextEditing.downArrow)
    settle(window)
    #expect(model.single == 5, "↓ selects row 5")
    let revealed = try scrollOffset(window)
    #expect(revealed == 20, "row 5 (100…120) scrolled just into view: \(revealed)")
    #expect(window.lastHitboxes.contains { $0.id == rowID(list, 5) }, "row 5 is realised")

    // 3.12b: string ids, and a zero-height sibling named "r5" above the list.
    let named = (0..<100).map { Named(id: "r\($0)") }
    final class Holder { var selection: String? = "r4" }
    let holder = Holder()
    let (siblingWindow, siblingPlatform) = try scrolledWindow {
        Box().id("r5")
        List(named, selection: Binding(get: { holder.selection }, set: { holder.selection = $0 }),
             rowHeight: controlPx(20)) { item in Text(item.id) }
    }
    let siblingList = GlobalElementID.child(of: scrolledContentID, at: 1, name: nil)
    try focusList(siblingWindow, siblingList)
    key(siblingWindow, siblingPlatform, TextEditing.downArrow)
    settle(siblingWindow)
    try #require(holder.selection == "r5", "control: ↓ selects r5")
    let siblingOffset = try scrollOffset(siblingWindow)
    #expect(siblingOffset == 20, "3.12b: the list's own reveal scrolls, not the sibling named r5: \(siblingOffset)")

    // 3.12c (`DD-AC` item 2, `DD-AH` item 2): a second selectable list with
    // the same datum ids, placed BEFORE the focused one in the same scroller,
    // does not take the reveal. The upper list's 10 rows fill 0…200; the
    // lower's row 5 is 300…320, so the offset reads 220. V4 (the
    // `reveal.list == id` conjunct dropped) lets the upper list resolve it
    // first, at its own row 5 (100…120), and reads 20.
    let upper = Selection(count: 10)
    let lower = Selection(count: 100, single: 4)
    let (twoWindow, twoPlatform) = try scrolledWindow {
        singleList(upper)
        singleList(lower)
    }
    let lowerList = GlobalElementID.child(of: scrolledContentID, at: 1, name: nil)
    try focusList(twoWindow, lowerList)
    key(twoWindow, twoPlatform, TextEditing.downArrow)
    settle(twoWindow)
    try #require(lower.single == 5 && upper.singleWrites.isEmpty, "control: ↓ selects the lower list's row 5")
    let twoOffset = try scrollOffset(twoWindow)
    #expect(twoOffset == 220, "3.12c: only the list the reveal names takes it: \(twoOffset)")
}

/// **3.13.** The joint test with `DD-Y`: a selectable list's rows are click
/// targets, and the wheel over one still scrolls its scroller. Lane 2's M2q
/// (the rule reverted), re-run on this lane's head, must redden it.
@Test @MainActor func aSelectableListScrollsUnderTheWheelOverARow() throws {
    let model = Selection(count: 40)
    let (window, platform) = try scrolledWindow { singleList(model) }
    let list = GlobalElementID.child(of: scrolledContentID, at: 0, name: nil)
    try #require(window.lastHitboxes.contains { $0.id == rowID(list, 1) && $0.handlers.onClick != nil },
                 "control: row 1 is a click target")
    platform.simulateInput(.scrollWheel(ScrollEvent(position: Point(x: controlPx(50), y: controlPx(30)),
                                                    delta: Point(x: controlPx(0), y: controlPx(-37)))))
    settle(window)
    let wheeled = try scrollOffset(window)
    #expect(wheeled == 37, "the wheel over a row scrolls: \(wheeled)")
}

/// **3.14.** A selected row paints the `.accent` background; an unselected
/// row paints none. M3l (no background) must redden it.
@Test @MainActor func aSelectedRowPaintsTheAccentBackground() throws {
    let model = Selection(single: 2)
    let (window, _) = try unboundedWindow { singleList(model) }
    let theme = window.theme
    let rowRects = window.lastScene.rects.filter {
        $0.bounds.size.width == 400 && $0.bounds.size.height == 20
    }
    try #require(rowRects.count == 1, "one row-sized fill, read \(rowRects.count)")
    #expect(rowRects[0].bounds.origin.y == 40, "row 2's fill")
    let accent = theme[.accent]
    let fill = rowRects[0].background
    #expect(abs(fill.h - accent.h) < 1e-4 && abs(fill.s - accent.s) < 1e-4
            && abs(fill.l - accent.l) < 1e-4 && abs(fill.a - accent.a) < 1e-4, "the fill is .accent: \(fill)")
}

/// **3.15** (renamed by `DD-AC` item 1). Over two frames: a selectable list with
/// nothing selected adds no `StateTable` entry over the same list without
/// `selection:`; `s` selected realised rows add exactly `s`, each an
/// `$anim-color` slot, and no `$ax` id. M3m (the hint declared as a
/// `.selected` trait, which writes `$ax`) must redden it.
@Test @MainActor func aSelectableListAddsOneColourSlotPerSelectedRowAndNoAXSlot() throws {
    func ids<E: Element>(_ root: E) -> Set<GlobalElementID> {
        let table = StateTable()
        for _ in 0..<2 {
            var root = root
            let frame = Frame(contentSize: Size(width: controlPx(400), height: controlPx(400)), scaleFactor: 1,
                              stateTable: table, collectsAccessibility: true)
            frame.render(&root)
        }
        return table.ids
    }
    let items = (0..<5).map(Item.init)
    let plain = ids(Box(style: column(width: 400, height: 400)) {
        List(items, rowHeight: controlPx(20)) { Text("Row \($0.id)") }
    })
    let none = Selection()
    let unselected = ids(Box(style: column(width: 400, height: 400)) { multiList(none) })
    #expect(unselected == plain, "nothing selected: no entry added, \(unselected.subtracting(plain))")
    let two = Selection(multi: [1, 3])
    let selected = ids(Box(style: column(width: 400, height: 400)) { multiList(two) })
    let added = selected.subtracting(plain)
    #expect(added.count == 2, "two selected rows add two entries: \(added)")
    #expect(added == Set([1, 3].map {
        GlobalElementID.child(of: rowID(unboundedListID, $0), at: 0, name: ElementID("$anim-color"))
    }), "each is the row's $anim-color slot: \(added)")
    #expect(!added.contains { $0.component == .named(ElementID("$ax")) }, "no $ax slot added")
}

/// **3.16.** An accessibility client selects a row by pressing it (the press
/// replaces the selection), and setting `AXSelected` on the AppKit element
/// changes nothing (divergence 83). M3n (the rows' press not wired) must
/// redden it.
@Test @MainActor func anAccessibilityClientSelectsARowByPressingItAndCannotSetSelectedDirectly() throws {
    let model = Selection(count: 5, multi: [0, 1])
    let (window, platform) = try scrolledWindow { multiList(model) }
    let tree = try controlTree(window, platform)
    let rows = tree.nodes.filter { $0.value.role == .row }
    let row3 = try #require(rows.first { kids(tree, $0.key).first?.value == "Row 3" },
                            "row 3 publishes a row")
    #expect(row3.value.actions.contains(.press), "a row publishes .press")
    #expect(platform.simulateAccessibilityRequest(.press(row3.key)))
    #expect(model.multiWrites == [[3]], "the press replaces the selection: \(model.multiWrites)")
    controlRedraw(window)

    // The AppKit bridge: `setAccessibilitySelected(true)` on row 4's element.
    let published = try #require(platform.publishedAccessibilityTrees.last)
    let row4 = try #require(published.nodes.first {
        $0.value.role == .row && kids(published, $0.key).first?.value == "Row 4"
    }?.key)
    let host = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 100, height: 100),
                        styleMask: [.titled], backing: .buffered, defer: true)
    host.isReleasedWhenClosed = false
    let view = NSView(frame: NSRect(x: 0, y: 0, width: 100, height: 100))
    host.contentView = view
    let bridge = AppKitAccessibilityBridge(signal: SelectionRunning(), poster: SelectionNoPoster())
    var requests: [Request] = []
    bridge.onRequest = { requests.append($0); return platform.simulateAccessibilityRequest($0) }
    bridge.hostView = view
    bridge.publish(published)
    requests = []
    let element = bridge.element(for: row4)
    #expect(!element.isAccessibilitySelected(), "control: row 4 is not selected")
    element.setAccessibilitySelected(true)
    #expect(requests.isEmpty, "no request reaches the window: \(requests)")
    #expect(model.multiWrites == [[3]], "nothing written: \(model.multiWrites)")
}

@MainActor private final class SelectionRunning: AccessibilityClientSignal {
    func observe(_ handler: @escaping @MainActor (Bool) -> Void) { handler(true) }
}

@MainActor private final class SelectionNoPoster: AccessibilityNotificationPosting {
    func post(_ notification: NSAccessibility.Notification, for element: Any) {}
}

// MARK: - The controls demo, the row roles, the per-frame work

/// **3.19.** `controlsDemoContent()` through a real `Window`, a client active,
/// publishes a button, a check box, a slider, an incrementor, a radio group and
/// a table with exactly one selected row; its deepest native level is recorded
/// (at most 40, `DD-AC` item 10). M3q (the demo's list built without
/// `selection:`) must redden it.
@Test @MainActor func theControlsDemoPublishesEveryControlsRole() throws {
    let (window, platform) = try controlWindow(size: 900) { controlsDemoContent() }
    let tree = try controlTree(window, platform)
    let roles = Set(tree.nodes.values.map(\.role))
    for role in [AccessibilityRole.button, .checkBox, .slider, .incrementor, .radioGroup, .table] {
        #expect(roles.contains(role), "the demo publishes a \(role)")
    }
    let table = try #require(tree.nodes.first { $0.value.role == .table }, "a table")
    let rows = table.value.children.compactMap { tree.nodes[$0] }
    #expect(!rows.isEmpty, "the table publishes rows: \(rows.map { ($0.role, $0.rowIndex, $0.isSelected) })")
    #expect(rows.filter(\.isSelected).count == 1,
            "exactly one selected row: \(rows.map { ($0.role, $0.rowIndex, $0.isSelected, $0.label) })")
    let deepest = window.lastNativeLayoutDeepestLevel
    print("CONTROLS DEMO deepest native level: \(deepest)")
    #expect(deepest > 0 && deepest <= 40, "the controls demo's deepest native level \(deepest) is at most 40")

    // Each control alone, in the controls' own root, through a real window
    // (`DD-AC` item 10's record; the default demo's own root reads 30).
    let flag = Binding.constant(true), level = Binding.constant(0.5), count = Binding.constant(1)
    let choice = Binding.constant(1), picked = Binding<Int?>.constant(2)
    func depth<E: Element>(_ name: String, _ make: @escaping @MainActor () -> E) throws -> Int {
        let (window, _) = try controlWindow(size: 400) { make() }
        controlRedraw(window)
        let level = window.lastNativeLayoutDeepestLevel
        print("CONTROL DEPTH \(name): \(level)")
        return level
    }
    let levels = [
        try depth("Button") { controlRoot { Button("Go") {} } },
        try depth("Toggle") { controlRoot { Toggle("Wi-Fi", isOn: flag) } },
        try depth("Slider") { controlRoot { Slider(value: level, in: 0...1) } },
        try depth("Stepper") { controlRoot { Stepper("Qty", value: count, in: 0...9) } },
        try depth("Picker segmented") {
            controlRoot { Picker("P", selection: choice) { Text("A").tag(0); Text("B").tag(1) } }
        },
        try depth("Picker radioGroup") {
            controlRoot {
                Picker("P", selection: choice) { Text("A").tag(0); Text("B").tag(1) }.pickerStyle(.radioGroup)
            }
        },
        try depth("List(selection:) in a ScrollView") {
            Box(style: column(width: 100, height: 100)) {
                ScrollView {
                    List((0..<20).map(Item.init), selection: picked, rowHeight: controlPx(20)) { Text("Row \($0.id)") }
                }
            }
        },
    ]
    #expect(levels.allSatisfy { $0 > 0 && $0 <= 40 }, "every control's deepest level is at most 40: \(levels)")
}

/// **3.20** (`DD-AC` item 6). With no scroller (an unbounded window) each
/// selectable row publishes as a `.button` labelled by its text, with `.press`,
/// the selected one `isSelected`; inside a scroller after its first frame, as a
/// `.row` with its index, `.press` and `isSelected`. M3s (`logicalIndex` set on
/// unbounded rows too) must redden the first arm.
@Test @MainActor func anUnboundedSelectableListPublishesButtonRowsAndABoundedOneTableRows() throws {
    let unbounded = Selection(single: 2)
    let (window, platform) = try unboundedWindow { singleList(unbounded) }
    let tree = try controlTree(window, platform)
    let buttons = tree.nodes.values.filter { $0.role == .button && ($0.label ?? "").hasPrefix("Row ") }
    #expect(buttons.count == 5, "five button rows: \(buttons.map(\.label))")
    #expect(buttons.allSatisfy { $0.actions.contains(.press) }, "each with .press")
    #expect(buttons.filter(\.isSelected).map { $0.label ?? "" } == ["Row 2"], "the selected one isSelected")
    #expect(!tree.nodes.values.contains { $0.role == .row }, "no .row while unbounded")

    let bounded = Selection(single: 2)
    let (boundedWindow, boundedPlatform) = try scrolledWindow { singleList(bounded) }
    let boundedTree = try controlTree(boundedWindow, boundedPlatform)
    let rows = boundedTree.nodes.filter { $0.value.role == .row }
    #expect(rows.count == 5, "five .rows once bounded: \(rows.count)")
    #expect(rows.allSatisfy { $0.value.actions.contains(.press) }, "each with .press")
    let selected = rows.filter { $0.value.isSelected }
    #expect(selected.count == 1 && selected.first?.value.rowIndex == 2, "row index 2 is selected")
    #expect(Set(rows.compactMap(\.value.rowIndex)) == Set(0..<5), "each carries its index")

    // 3.20b (`DD-AG` item 1): the scroller's FIRST frame, a client active
    // before it, is unbounded only until the viewport is measured, so a
    // selectable list keeps AB-X rule 1 there — the table, no rows and no
    // button rows — rather than publishing every row as a button for one frame.
    // M3t (the `windowAwaitsViewport` clause dropped) must redden this arm.
    let first = Selection(single: 2)
    let device = try #require(MTLCreateSystemDefaultDevice())
    let (firstWindow, firstPlatform) = try makeFakeWindow(device: device, size: 100) {
        Box(style: column(width: 100, height: 100)) {
            ScrollView {
                Box(style: column(width: 100)) { singleList(first) }
            }
            .scrollIndicators(.hidden)
        }
    }
    #expect(firstPlatform.simulateAccessibilityRequest(.activate))
    firstWindow.drawFrameIfNeeded()
    try #require(firstWindow.framesDrawn == 1)
    let frame0 = try #require(firstPlatform.publishedAccessibilityTrees.last, "frame 0 publishes")
    let table0 = try #require(frame0.nodes.values.first { $0.role == .table }, "the table on frame 0")
    #expect(table0.children.isEmpty, "3.20b: no rows on the scroller's first frame")
    #expect(!frame0.nodes.values.contains { $0.role == .button && ($0.label ?? "").hasPrefix("Row ") },
            "3.20b: no button rows on the scroller's first frame")
}

/// A collection counting its element accesses.
private final class AccessCount: @unchecked Sendable {
    var reads = 0
}

private struct CountingItems: RandomAccessCollection {
    let count: Int
    let counter: AccessCount
    var startIndex: Int { 0 }
    var endIndex: Int { count }
    subscript(position: Int) -> Item {
        counter.reads += 1
        return Item(id: position)
    }
}

/// **3.21** (`DD-AC` item 4). A selectable list's warm frame touches only its
/// realised rows: through a counting collection, the element accesses of a
/// warm frame are equal at 500 and 5 000 rows, with a selection whose lead is
/// not stored (never interacted with) and whose one id is the last row. M3r
/// (the lead re-derived by a data scan in `requestLayout`) must redden it.
@Test @MainActor func aSelectableListsWarmFrameTouchesOnlyItsRealisedRows() throws {
    func warmReads(_ n: Int) throws -> Int {
        let counter = AccessCount()
        let data = CountingItems(count: n, counter: counter)
        final class Holder { var selection: Set<Int> = [] }
        let holder = Holder()
        holder.selection = [n - 1]
        let (window, _) = try scrolledWindow {
            List(data, selection: Binding(get: { holder.selection }, set: { holder.selection = $0 }),
                 rowHeight: controlPx(20)) { item in Text("Row \(item.id)") }
        }
        try #require(window.lastScrollRegions.first.map {
            window.stateTable.peek($0.id, as: ScrollState.self)?.viewportExtent == 100 } == true,
                     "control: the viewport is measured, so the window is bounded")
        counter.reads = 0
        controlRedraw(window)
        return counter.reads
    }
    let small = try warmReads(500)
    let large = try warmReads(5_000)
    try #require(small > 0, "control: a warm frame reads its realised rows")
    #expect(small == large, "a warm frame's accesses do not grow with the data: \(small) vs \(large)")
}
