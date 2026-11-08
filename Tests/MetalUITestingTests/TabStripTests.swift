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
