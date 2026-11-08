import Foundation
import MetalUI
import MetalUIPlatform
import MetalUIScene
import MetalUITesting
import Testing

// `TabStrip` (ruling prefix `TBS-`, record 238): PLAIN imports, headless `TestWindow`, Noto Sans on every platform.
// Layout: the bar is 32 tall (31 of tabs and a 1-point rule); a tab is 96..220 wide; the close slot is the tab's last 18
// points less 0 padding, so its centre is 9 points inside the tab's trailing edge.

@MainActor private final class StripModel {
    var selected: String
    var tabs: [TabStripItem<String>]
    var closed: [String] = []
    var moves: [String] = []
    init(selected: String = "a", tabs: [TabStripItem<String>]) {
        self.selected = selected
        self.tabs = tabs
    }
    var binding: Binding<String> { Binding(get: { self.selected }, set: { self.selected = $0 }) }
}

@MainActor private var plainTabs: [TabStripItem<String>] {
    [TabStripItem(id: "a", title: "main.swift"), TabStripItem(id: "b", title: "b.swift"), TabStripItem(id: "c", title: "c.swift")]
}

@MainActor private func stripWindow(_ m: StripModel, width: Float = 500, retained: Bool = false) throws -> TestWindow {
    let window = try harnessWindow(size: sz(width, 100)) {
        VStack(spacing: 0) {
            TabStrip(selection: m.binding, tabs: m.tabs)
                .onCloseTab { m.closed.append($0) }
                .onMoveTab { m.moves.append("\($0)>\($1)") }
            Spacer()
        }
    }
    window.tick()
    window.tick()
    return window
}

/// The frame of the tab button labelled `title`.
@MainActor private func tabFrame(_ window: TestWindow, _ title: String) throws -> Bounds<Pixels> {
    try window.element(label: title).frame
}

/// The point in a tab's title area, and at its close slot (a button's frame is the title area; the 18-point slot follows).
@MainActor private func body(_ window: TestWindow, _ title: String) throws -> Point<Pixels> {
    let f = try tabFrame(window, title)
    return pt(f.origin.x.value + 30, 16)
}
@MainActor private func slot(_ window: TestWindow, _ title: String) throws -> Point<Pixels> {
    let f = try tabFrame(window, title)
    return pt(f.origin.x.value + f.size.width.value + 9, 16)
}

/// 1 - a click selects, by writing the binding from input. Mutation: drop the tab's `onTapGesture` write.
@Test @MainActor func aClickOnATabSelectsIt() throws {
    let m = StripModel(tabs: plainTabs)
    let window = try stripWindow(m)
    window.click(at: try body(window, "b.swift")); window.tick()
    #expect(m.selected == "b")
    #expect(try window.element(label: "b.swift").isSelected && !window.element(label: "main.swift").isSelected)
    #expect(m.closed.isEmpty && m.moves.isEmpty)
}

/// 2 - the close button reports the id and leaves the selection to the app. Mutation: let the slot's tap also select, or
/// report the wrong id.
@Test @MainActor func theCloseButtonReportsTheIdAndDoesNotSelect() throws {
    let m = StripModel(tabs: plainTabs)
    let window = try stripWindow(m)
    let point = try slot(window, "c.swift")
    window.hover(at: point); window.tick()
    window.click(at: point); window.tick()
    #expect(m.closed == ["c"])
    #expect(m.selected == "a", "closing selects nothing")
}

/// 3 - a middle click closes the tab under it, and only a closable one. Mutation: the middle gesture on the primary button,
/// or no `isClosable` check.
@Test @MainActor func aMiddleClickClosesAClosableTab() throws {
    var items = plainTabs
    items[1].isClosable = false
    let m = StripModel(tabs: items)
    let window = try stripWindow(m)
    window.otherClick(at: try body(window, "c.swift")); window.tick()
    window.otherClick(at: try body(window, "b.swift")); window.tick()
    #expect(m.closed == ["c"], "b is not closable")
    #expect(m.selected == "a")
}

/// 4 - a non-closable tab has no close button; a closable one has. Mutation: show the slot regardless of `isClosable`.
@Test @MainActor func aNonClosableTabHasNoCloseButton() throws {
    var items = plainTabs
    items[1].isClosable = false
    let m = StripModel(tabs: items)
    let window = try stripWindow(m)
    let closeLabels = try window.elements { $0.label?.hasPrefix("Close ") == true }.compactMap(\.label).sorted()
    #expect(closeLabels == ["Close c.swift", "Close main.swift"])
    // Hover and click where the slot would be: nothing is reported.
    let point = try slot(window, "b.swift")
    window.hover(at: point); window.tick()
    window.click(at: point); window.tick()
    #expect(m.closed.isEmpty)
}

/// 4b - a tab with no slot is 18 points narrower than the same title with one: the next tab starts 18 points sooner.
/// Mutation: build the slot regardless of `isClosable`/`isDirty` (its accessibility button is hidden, its click does nothing,
/// so only the width shows it).
@Test @MainActor func aTabWithNoSlotIsEighteenPointsNarrower() throws {
    let title = "a-fairly-long-file-name.swift"
    let items = [TabStripItem(id: "a", title: title), TabStripItem(id: "b", title: title + "2", isClosable: false),
                 TabStripItem(id: "c", title: title + "3")]
    let window = try stripWindow(StripModel(tabs: items), width: 800)
    let a = try tabFrame(window, title), b = try tabFrame(window, title + "2"), c = try tabFrame(window, title + "3")
    #expect(b.origin.x.value - a.origin.x.value == a.size.width.value + 18, "a has a slot: \(a) \(b)")
    #expect(c.origin.x.value - b.origin.x.value == b.size.width.value, "b has none: \(b) \(c)")
}

/// The 16 x 16 close buttons drawn (a hover wash rect, clear or not, sits behind each).
@MainActor private func closeButtons(_ window: TestWindow) -> Int {
    window.scene.rects.filter { $0.bounds.size.width == 16 && $0.bounds.size.height == 16 }.count
}

/// 4c - the close button shows on the selected tab and on a hovered one, and nowhere else. Mutation: never show it, or
/// always.
@Test @MainActor func theCloseButtonShowsOnTheSelectedAndTheHoveredTab() throws {
    let m = StripModel(tabs: plainTabs)
    let window = try stripWindow(m)
    #expect(closeButtons(window) == 1, "only the selected tab's")
    window.hover(at: try body(window, "c.swift")); window.tick()
    #expect(closeButtons(window) == 2, "and the hovered tab's")
    window.exitPointer(); window.tick()
    #expect(closeButtons(window) == 1)
}

/// The dot a dirty tab shows: an 8 x 8 rect.
@MainActor private func dots(_ window: TestWindow) -> Int {
    window.scene.rects.filter { $0.bounds.size.width == 8 && $0.bounds.size.height == 8 }.count
}

/// 5 - a dirty tab shows its dot in the close slot until the pointer is over it, then the close button; a dirty tab that
/// cannot close keeps the dot. Mutation: show the dot whenever dirty.
@Test @MainActor func theDirtyDotGivesWayToTheCloseButtonOnHover() throws {
    var items = plainTabs
    items[1].isDirty = true
    items[2].isDirty = true
    items[2].isClosable = false
    let m = StripModel(tabs: items)
    let window = try stripWindow(m)
    #expect(dots(window) == 2, "b and c show a dot")
    window.hover(at: try body(window, "b.swift")); window.tick()
    #expect(dots(window) == 1, "the hovered closable tab shows the close button, c keeps its dot")
    window.hover(at: try body(window, "c.swift")); window.tick()
    #expect(dots(window) == 2, "a hovered non-closable tab keeps its dot")
    #expect(try window.element(label: "b.swift").value == "edited")
    #expect(try window.element(label: "main.swift").value == nil)
}

/// 6 - the accent is a 3 x 14 bar in the colour given, once per accented tab. Mutation: ignore `accent`.
@Test @MainActor func theAccentIsDrawnInItsColour() throws {
    var items = plainTabs
    items[1].accent = .red
    let m = StripModel(tabs: items)
    let window = try stripWindow(m)
    let bars = window.scene.rects.filter { $0.bounds.size.width == 3 && $0.bounds.size.height == 14 }
    try #require(bars.count == 1)
    #expect(bars[0].background.a == 1 && bars[0].background.h > 0.95 && bars[0].background.s > 0.9, "red: \(bars[0].background)")
    let plain = try stripWindow(StripModel(tabs: plainTabs))
    #expect(plain.scene.rects.filter { $0.bounds.size.width == 3 && $0.bounds.size.height == 14 }.isEmpty)
}

/// 7 - a drag reports (from, to) at the release, with the index the tab has afterwards; a tiny drag and a drag that ends where
/// it began report nothing. Mutation: `to` counts the dragged tab's own middle, or the report is made on every change.
@Test @MainActor func aDragReordersAndATinyDragDoesNot() throws {
    let m = StripModel(tabs: plainTabs)
    let window = try stripWindow(m)
    let a = try body(window, "main.swift"), c = try body(window, "c.swift")
    window.drag(from: a, to: pt(c.x.value + 20, 16)); window.tick()
    #expect(m.moves == ["0>2"])
    window.drag(from: c, to: try body(window, "main.swift")); window.tick()
    #expect(m.moves == ["0>2", "2>0"])
    window.drag(from: try body(window, "b.swift"), to: pt(try body(window, "b.swift").x.value + 3, 16)); window.tick()
    window.drag(from: try body(window, "b.swift"), to: pt(try body(window, "b.swift").x.value + 40, 18)); window.tick()
    #expect(m.moves == ["0>2", "2>0"], "a tiny drag and a drag within its own tab report nothing")
    #expect(m.selected == "b", "the tiny drag was a click")
}

/// 8 - tabs wider than the strip scroll it, and a selection made off screen is brought into view. Mutation: drop the
/// `scrollTo` in `onChange`.
@Test @MainActor func aSelectionOffScreenScrollsIntoView() throws {
    let items = (0..<8).map { TabStripItem(id: "t\($0)", title: "file\($0).swift") }
    let m = StripModel(selected: "t0", tabs: items)
    let window = try stripWindow(m, width: 300)
    let last = try tabFrame(window, "file7.swift")
    #expect(last.origin.x.value >= 300, "the last tab starts past the strip's end: \(last)")
    m.selected = "t7"
    window.window.setNeedsRedraw(); window.tick(); window.tick(); window.tick()
    let moved = try tabFrame(window, "file7.swift")
    #expect(moved.origin.x.value + moved.size.width.value <= 300.5 && moved.origin.x.value >= 0, "in view: \(moved)")
    #expect(try tabFrame(window, "file0.swift").origin.x.value < 0, "the strip scrolled")
}

/// 9 - a tab is as wide as its title up to 220 and no less than 96, and a long title truncates (its text ends inside the
/// tab). Mutation: the clamp's maximum.
@Test @MainActor func tabsClampTheirWidth() throws {
    let long = String(repeating: "very-long-name-", count: 8) + ".swift"
    let m = StripModel(tabs: [TabStripItem(id: "a", title: "x.swift"), TabStripItem(id: "b", title: long, isDirty: true)])
    let window = try stripWindow(m, width: 600)
    #expect(try tabFrame(window, "x.swift").size.width.value == 96 - 18)
    var b = try tabFrame(window, long)
    #expect(b.size.width.value == 220 - 18)
    b = Bounds(origin: b.origin, size: sz(220, b.size.height.value))
    // The dot sits in the slot at the tab's trailing edge, not past it: the title did not push it out.
    let dot = try #require(window.scene.rects.first { $0.bounds.size.width == 8 && $0.bounds.size.height == 8 })
    #expect(dot.bounds.origin.x < b.origin.x.value + 220 && dot.bounds.origin.x > b.origin.x.value + 190, "dot at \(dot.bounds.origin.x)")
}

/// 10 - the accessibility tree: a "Tabs" group over buttons, the selected one selected, a close button per closable tab.
/// Mutation: drop the group label, or the `isSelected` trait.
@Test @MainActor func theAccessibilityTreeHasTheStripsShape() throws {
    var items = plainTabs
    items[1].isDirty = true
    items[2].isClosable = false
    let m = StripModel(selected: "b", tabs: items)
    let window = try stripWindow(m)
    let group = try window.element(label: "Tabs")
    #expect(group.role == .group)
    let titles = ["main.swift", "b.swift", "c.swift"]
    for title in titles {
        let tab = try window.element(label: title)
        #expect(tab.role == .button && group.children.contains(tab.id), "\(title)")
        #expect(tab.isSelected == (title == "b.swift"))
    }
    #expect(try window.element(label: "b.swift").value == "edited")
    for title in ["main.swift", "b.swift"] {
        let close = try window.element(label: "Close \(title)")
        #expect(close.role == .button && group.children.contains(close.id))
    }
    #expect((try? window.element(label: "Close c.swift")) == nil)
    let pressedClose = try window.performAccessibilityAction(.press, on: window.element(label: "Close main.swift"))
    try #require(pressedClose)
    #expect(m.closed == ["a"])
    let pressedTab = try window.performAccessibilityAction(.press, on: window.element(label: "c.swift"))
    try #require(pressedTab)
    #expect(m.selected == "c")
}

/// 11 - an unchanged `.equatable()` strip replays while its parent redraws, and a change to a tab's data rebuilds it.
/// Run again under `METALUI_VERIFY_RETAINED=1`, which compares every replay with a fresh build. Mutation: `==` always true
/// (the title change is not drawn), or `isSame` ignoring `isDirty`.
@Test @MainActor func anUnchangedStripReplaysAndAChangedOneRebuilds() throws {
    let m = StripModel(tabs: plainTabs)
    let window = try harnessWindow(size: sz(500, 100)) {
        VStack(spacing: 0) {
            Text("tick \(m.moves.count)")
            TabStrip(selection: m.binding, tabs: m.tabs).equatable()
            Spacer()
        }
    }
    window.window.testingRetainedGraft = true
    window.window.testingRetainedSubtrees = true
    for _ in 0..<4 { window.window.setNeedsRedraw(); window.tick() }
    let before = window.scene.rects.count
    m.moves.append("x")
    window.window.setNeedsRedraw(); window.tick()
    if !rsVerifying { #expect(window.lastFrameWork.retainedHits > 0 || window.lastFrameWork.retainedGrafts > 0, "replayed: \(window.lastFrameWork.retainedHits) hits") }
    #expect(window.scene.rects.count == before)
    m.tabs[1].isDirty = true
    window.window.setNeedsRedraw(); window.tick(); window.tick()
    #expect(try window.element(label: "b.swift").value == "edited", "the changed strip rebuilt")
    #expect(window.scene.rects.filter { $0.bounds.size.width == 8 && $0.bounds.size.height == 8 }.count == 1)
}

/// 12 - while a tab is dragged it dims and a 2-point accent bar marks the edge it would land on: the destination's leading
/// edge going left, its trailing edge going right, none while it stays. The scene is read in `onMoveTab`, which runs at the
/// release before the next frame. Mutation: swap the two edges in `dropEdge`, or never draw the bar.
@Test @MainActor func aDraggedTabDimsAndMarksWhereItWouldLand() throws {
    let m = StripModel(tabs: plainTabs)
    var seen: [MUIRect] = []
    var window: TestWindow!
    window = try harnessWindow(size: sz(500, 100)) {
        VStack(spacing: 0) {
            TabStrip(selection: m.binding, tabs: m.tabs).onMoveTab { _, _ in seen = window.scene.rects }
            Spacer()
        }
    }
    window.tick(); window.tick()
    let bar: (MUIRect) -> Bool = { $0.bounds.size.width == 2 && $0.bounds.size.height == 31 }
    window.drag(from: try body(window, "main.swift"), to: pt(try body(window, "c.swift").x.value + 20, 16)); window.tick()
    let right = try #require(seen.first(where: bar))
    #expect(right.bounds.origin.x == 286, "trailing edge of c (96 x 3 = 288, less the bar): \(right.bounds)")
    window.drag(from: try body(window, "c.swift"), to: pt(10, 16)); window.tick()
    let left = try #require(seen.first(where: bar))
    #expect(left.bounds.origin.x == 0, "leading edge of a: \(left.bounds)")
    #expect(!window.scene.rects.contains(where: bar), "the marker goes with the drag")
}

/// 13 - an icon takes 14 points and the 6 between it and the title, and the strip's equality sees a changed icon.
/// Mutation: drop the icon from `TabStripLabel`, or `isSame` treating any two icons as equal.
@Test @MainActor func anIconWidensTheTabAndCountsInEquality() throws {
    let title = "a-fairly-long-file-name.swift"
    let items = [TabStripItem(id: "a", title: title), TabStripItem(id: "b", title: title + "2", icon: Image(systemName: "doc"))]
    let window = try stripWindow(StripModel(tabs: items), width: 800)
    let a = try tabFrame(window, title), b = try tabFrame(window, title + "2")
    #expect(b.size.width.value - a.size.width.value > 19.5 && b.size.width.value - a.size.width.value < 20.5 + 10,
            "the icon and its gap (plus the longer title): \(a.size.width) \(b.size.width)")
    let m = StripModel(tabs: items)
    func strip(_ icon: Image?) -> TabStrip<String> {
        TabStrip(selection: m.binding, tabs: [TabStripItem(id: "a", title: "x", icon: icon)])
    }
    #expect(strip(Image(systemName: "doc")) == strip(Image(systemName: "doc")))
    #expect(strip(Image(systemName: "doc")) != strip(Image(systemName: "star")))
    #expect(strip(nil) != strip(Image(systemName: "doc")))
}

/// 13 - `TBS-J`: a tab's identifier is on its button and its close identifier on its close button (found by identifier, with
/// the label, role and press unchanged); a nil identifier leaves the node's identifier nil. Mutation: drop the
/// `.accessibilityIdentifier` write in `TabStripLabel` or in `TabStripCloseSlot`.
@Test @MainActor func aTabAndItsCloseButtonCarryTheirOwnIdentifiers() throws {
    var items = plainTabs
    items[0] = TabStripItem(id: "a", title: "main.swift", accessibilityIdentifier: "tab-a", closeAccessibilityIdentifier: "tab-close-a")
    items[1] = TabStripItem(id: "b", title: "b.swift", isDirty: true, accessibilityIdentifier: "tab-b", closeAccessibilityIdentifier: "tab-close-b")
    items[2] = TabStripItem(id: "c", title: "c.swift", closeAccessibilityIdentifier: "tab-close-c")
    let m = StripModel(tabs: items)
    let window = try stripWindow(m)
    for (id, title) in [("a", "main.swift"), ("b", "b.swift")] {
        let tab = try window.element(identifier: "tab-\(id)")
        #expect(tab.label == title && tab.role == .button)
        let close = try window.element(identifier: "tab-close-\(id)")
        #expect(close.label == "Close \(title)" && close.role == .button)
    }
    #expect(try window.element(identifier: "tab-b").value == "edited", "the dirty value survives the identifier")
    #expect(try window.element(label: "c.swift").identifier == nil, "no identifier is derived from the id")
    #expect(try window.element(identifier: "tab-close-c").label == "Close c.swift", "either identifier is independent")
    #expect((try? window.element(identifier: "tab-c")) == nil)
    let pressed = try window.performAccessibilityAction(.press, on: window.element(identifier: "tab-close-a"))
    try #require(pressed)
    #expect(m.closed == ["a"])
}

/// 14 - nil identifiers leave the tree as before: no node of a plain strip has one. Mutation: write `""` for nil.
@Test @MainActor func aStripWithoutIdentifiersHasNoneInItsTree() throws {
    let window = try stripWindow(StripModel(tabs: plainTabs))
    for title in ["Tabs", "main.swift", "b.swift", "c.swift", "Close main.swift", "Close b.swift", "Close c.swift"] {
        #expect(try window.element(label: title).identifier == nil, "\(title)")
    }
}

/// 15 - an identifier belongs to its item: after another tab is reordered or removed it is still on its own tab, and a
/// changed identifier rebuilds an `.equatable()` strip. Mutation: `isSame` ignoring the identifiers (the last arm), or
/// identifiers assigned by position.
@Test @MainActor func anIdentifierStaysWithItsItem() throws {
    func item(_ id: String) -> TabStripItem<String> {
        TabStripItem(id: id, title: "\(id).swift", accessibilityIdentifier: "tab-\(id)", closeAccessibilityIdentifier: "tab-close-\(id)")
    }
    let m = StripModel(tabs: ["a", "b", "c"].map(item))
    let window = try harnessWindow(size: sz(500, 100)) {
        VStack(spacing: 0) {
            TabStrip(selection: m.binding, tabs: m.tabs).equatable()
            Spacer()
        }
    }
    window.tick(); window.tick()
    func check(_ ids: [String]) throws {
        for id in ids {
            #expect(try window.element(identifier: "tab-\(id)").label == "\(id).swift", "tab-\(id)")
            #expect(try window.element(identifier: "tab-close-\(id)").label == "Close \(id).swift", "tab-close-\(id)")
        }
    }
    try check(["a", "b", "c"])
    m.tabs.append(m.tabs.removeFirst())
    window.window.setNeedsRedraw(); window.tick(); window.tick()
    try check(["b", "c", "a"])
    m.tabs.remove(at: 0)
    window.window.setNeedsRedraw(); window.tick(); window.tick()
    try check(["c", "a"])
    #expect((try? window.element(identifier: "tab-b")) == nil)
    m.tabs[0].accessibilityIdentifier = "renamed"
    window.window.setNeedsRedraw(); window.tick(); window.tick()
    #expect(try window.element(identifier: "renamed").label == "c.swift")
}
