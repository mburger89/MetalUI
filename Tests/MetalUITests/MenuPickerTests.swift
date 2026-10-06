import Testing
import Foundation
import Metal
import MetalUICore
import MetalUIPlatform
import MetalUITextSystem
import MetalUIText
@testable import MetalUILayout
@testable import MetalUI

// Platform services, lane 3 — `.pickerStyle(.menu)` (rulings `SV-P`, `SV-AA`,
// `SV-S`; spec §6.3 tests 5.1–5.11, 5.17). SwiftUI's answers are the probe's
// `P` arms (`docs/probes/swiftui-platform-services.swift`): a pull-down button
// showing the selected option's title, as wide as the widest option (`P1` 86
// vs `P3` 102), opening a menu of every option with the selected one checked
// (`P1` `state=on`), choosing writes the tag (`P1` pick=1), a selection
// matching no tag shows an empty label (`P5`), published as `AXPopUpButton`
// (`P0`–`P3`). Red before: `PickerStyle.menu` does not exist at `be806c5`, so
// every test here fails by not compiling.
//
// The picker sits in `controlRoot` (a `Row` at the window's top-left): the
// picker is `[0, 0]`, its title `[0, 0, 0]`, its pull-down button `[0, 0, 1]`.

private let titles = ["A", "Medium", "The longest one"]
private let buttonID = controlID([0, 0, 1])

@MainActor private final class MPChoice {
    var value: Int
    var writes: [Int] = []
    init(_ value: Int) { self.value = value }
    var binding: Binding<Int> {
        Binding(get: { self.value }, set: { self.value = $0; self.writes.append($0) })
    }
}

@MainActor private func menuPicker(_ model: MPChoice, _ options: [String] = titles)
    -> Picker<Int, some ElementGroup> {
    Picker("Flavor", selection: model.binding) {
        for (index, title) in options.enumerated() { Text(title).tag(index) }
    }
    .pickerStyle(.menu)
}

/// A window over a menu picker, menus presented natively unless `native` is
/// false, one frame drawn.
@MainActor private func mpWindow(_ model: MPChoice, _ options: [String] = titles, native: Bool = true,
                                 disabled: Bool = false) throws -> (Window, FakePlatformWindow) {
    let (window, platform) = try controlWindow {
        controlRoot(width: 400, height: 400) { menuPicker(model, options).disabled(disabled) }
    }
    platform.presentsMenusNatively = native
    controlRedraw(window)
    return (window, platform)
}

/// The published `.popUpButton`, required.
@MainActor private func popUp(_ window: Window, _ platform: FakePlatformWindow,
                              sourceLocation: SourceLocation = #_sourceLocation)
    throws -> (id: AccessibilityNodeID, node: AccessibilityNode, frame: Bounds<Pixels>) {
    let tree = try controlTree(window, platform)
    let found = tree.nodes.filter { $0.value.role == .popUpButton }
    try #require(found.count == 1, "one pop-up button: \(tree.nodes.values.map(\.role))",
                 sourceLocation: sourceLocation)
    let (id, node) = found.first!
    let frame = try #require(tree.geometry[id]?.frame, sourceLocation: sourceLocation)
    return (id, node, frame)
}

// MARK: - 5.1–5.2: structure and width

/// **5.1** (`SV-P` item 2, `P1`). A menu picker is its title, 8, then a
/// 24-pt pull-down button whose label is the **selected** option's title
/// (beta selected → "Medium", not the first option's "A"). Mutation: label
/// from the first option.
@MainActor
@Test func aMenuPickerIsATitleAndAPullDownShowingTheSelection() throws {
    let model = MPChoice(1)
    let (window, platform) = try mpWindow(model)
    let title = try #require(window.lastElementBounds[controlID([0, 0, 0])], "the title")
    let button = try #require(window.lastElementBounds[buttonID], "the pull-down button")
    let titleWidth = try controlTextSize("Flavor").width.value
    #expect(abs(title.size.width.value - titleWidth) <= 1, "the title's own width")
    #expect(abs(button.origin.x.value - (title.origin.x.value + title.size.width.value + 8)) <= 1,
            "8 after the title: \(title) \(button)")
    #expect(button.size.height.value == Button<Text>.metrics(.regular).height, "Button's strut height")
    let (_, node, _) = try popUp(window, platform)
    #expect(node.value == "Medium", "the selected option's title: \(String(describing: node.value))")
    withExtendedLifetime(window) {}
}

/// **5.2** (`SV-P` item 2, `SV-AA`; `P1`, `P3`). The button is as wide as its
/// **widest** option's title plus `Button`'s chrome (padding on both sides)
/// and the ` ⌄` indicator — whichever option is selected. Mutation: the
/// selected title's width.
@MainActor
@Test func aMenuPickersButtonIsAsWideAsItsWidestOption() throws {
    let widest = try titles.map { try controlTextSize($0).width.value }.max()!
    let indicator = try controlTextSize(" \u{2304}").width.value
    let padding = Button<Text>.metrics(.regular).padding
    let expected = widest + indicator + 2 * padding
    for selection in [0, 2] {
        let (window, _) = try mpWindow(MPChoice(selection))
        let button = try #require(window.lastElementBounds[buttonID])
        #expect(abs(button.size.width.value - expected) <= 2,
                "selection \(selection): \(button.size.width.value) vs \(expected)")
        withExtendedLifetime(window) {}
    }
}

// MARK: - 5.3–5.5: the menu

/// **5.3** (`SV-P` item 4, `P1` `state=on`). A click presents every option,
/// in order, as items whose `isOn` is set only on the selected one, below the
/// button. Mutation: mark none.
@MainActor
@Test func openingAMenuPickerPresentsEveryOptionWithTheSelectionOn() throws {
    let model = MPChoice(2)
    let (window, platform) = try mpWindow(model)
    let button = try #require(window.lastElementBounds[buttonID])
    controlClick(platform, at: controlCentre(button))
    let presented = try #require(platform.presentedMenus.last, "the click presents a menu")
    #expect(presented.menu.items.map(\.title) == titles)
    #expect(presented.menu.items.map(\.isOn) == [false, false, true])
    #expect(presented.menu.items.allSatisfy { $0.kind == .action && $0.isEnabled })
    #expect(presented.at == Point(x: button.origin.x,
                                  y: Pixels(button.origin.y.value + button.size.height.value)),
            "below the button")
    withExtendedLifetime(window) {}
}

/// **5.4** (`P1` pick=1). Choosing an option writes its tag — once, the
/// chosen one's. Mutation: run the previous option.
@MainActor
@Test func choosingAMenuPickerOptionWritesItsTag() throws {
    let model = MPChoice(0)
    let (window, platform) = try mpWindow(model)
    controlClick(platform, at: controlCentre(try #require(window.lastElementBounds[buttonID])))
    let presented = try #require(platform.presentedMenus.last)
    platform.simulateInput(.menuAction(MenuActionEvent(menu: presented.menu.token, item: presented.menu.items[2].id)))
    #expect(model.writes == [2], "\(model.writes)")
    controlRedraw(window)
    let (_, node, _) = try popUp(window, platform)
    #expect(node.value == titles[2])
    withExtendedLifetime(window) {}
}

/// **5.5** (`P5`). A selection matching no tag shows an empty label and
/// checks nothing. Mutation: fall back to the first option.
@MainActor
@Test func aSelectionMatchingNoTagShowsAnEmptyLabel() throws {
    let model = MPChoice(99)
    let (window, platform) = try mpWindow(model)
    let (_, node, frame) = try popUp(window, platform)
    #expect(node.value == "", "an empty label: \(String(describing: node.value))")
    controlClick(platform, at: controlCentre(frame))
    let presented = try #require(platform.presentedMenus.last)
    #expect(presented.menu.items.allSatisfy { !$0.isOn })
    withExtendedLifetime(window) {}
}

// MARK: - 5.6: options lay out nothing (counted)

/// **5.6** (`SV-P` item 3, `SV-U`). A 300-option menu picker registers no
/// node per option: its tree has the 3-option picker's node count and its
/// layout run does the same work (both widest titles the same, so every
/// measured size agrees). Mutation: lay the option out.
@MainActor
@Test func menuPickerOptionsLayOutNothing() throws {
    func run(_ count: Int) throws -> (nodes: Int, work: [Int]) {
        let options = (0..<count).map { $0 == 1 ? "The longest one" : "Option" }
        var root = controlRoot(width: 400, height: 400) { menuPicker(MPChoice(0), options) }
        let frame = Frame(contentSize: Size(width: controlPx(400), height: controlPx(400)), scaleFactor: 1,
                          reportsUnlowerableFields: true, recordsElementBounds: true)
        frame.render(&root)
        try #require(frame.unlowerableFields.isEmpty, "\(frame.unlowerableFields.map(\.description))")
        let work = frame.tree.lastNativeLayoutWork
        return (frame.tree.nodeCount, [work.measureCalls, work.cacheHits, work.cacheMisses])
    }
    let small = try run(3)
    let large = try run(300)
    #expect(large.nodes == small.nodes, "nodes: 300 options \(large.nodes), 3 options \(small.nodes)")
    #expect(large.work == small.work, "work: 300 options \(large.work), 3 options \(small.work)")
}

// MARK: - 5.7–5.8: accessibility and openers

/// **5.7** (`SV-S`, `SV-P` item 5; `P0`–`P3` `AXPopUpButton`). The button
/// publishes as `.popUpButton`, value the selected title, labelled by the
/// picker's title, pressable; no option publishes. Mutation: `.menuButton`.
@MainActor
@Test func aMenuPickerPublishesAPopUpButtonWithTheSelectedValue() throws {
    let model = MPChoice(1)
    let (window, platform) = try mpWindow(model)
    let (_, node, _) = try popUp(window, platform)
    #expect(node.label == "Flavor", "labelled by the picker's title: \(String(describing: node.label))")
    #expect(node.value == "Medium")
    #expect(node.actions.contains(.press))
    let tree = try #require(platform.publishedAccessibilityTrees.last)
    #expect(!tree.nodes.values.contains { $0.role == .radioButton || $0.role == .menuButton },
            "no option and no menu button publish")
    withExtendedLifetime(window) {}
}

/// **5.8** (`SV-P` items 4 and 6, `MN-AF`). A click, Space when focused (and
/// Return only where it presses a `Button`, off Apple) and an accessibility
/// press each open the menu; disabled, none does. Mutation: open regardless
/// of the gate.
@MainActor
@Test func aMenuPickerOpensFromSpaceReturnAndAPressButNotWhenDisabled() throws {
    let model = MPChoice(0)
    let (window, platform) = try mpWindow(model)
    let (id, _, frame) = try popUp(window, platform)
    controlClick(platform, at: controlCentre(frame))
    #expect(platform.presentedMenus.count == 1, "a click")
    window.focus(buttonID)
    controlRedraw(window)
    try #require(window.focusedElement == buttonID, "the button takes focus")
    platform.simulateInput(controlKey(" "))
    #expect(platform.presentedMenus.count == 2, "Space")
    platform.simulateInput(controlKey("\r"))
    let afterReturn = TextEditing.platform == .mac ? 2 : 3
    #expect(platform.presentedMenus.count == afterReturn, "Return only off Apple")
    #expect(platform.simulateAccessibilityRequest(.press(id)))
    #expect(platform.presentedMenus.count == afterReturn + 1, "an accessibility press")

    let (disabled, disabledPlatform) = try mpWindow(MPChoice(0), disabled: true)
    let (disabledID, disabledNode, disabledFrame) = try popUp(disabled, disabledPlatform)
    #expect(!disabledNode.isEnabled)
    controlClick(disabledPlatform, at: controlCentre(disabledFrame))
    disabledPlatform.simulateInput(controlKey("\t"))
    controlRedraw(disabled)
    disabledPlatform.simulateInput(controlKey(" "))
    #expect(!disabledPlatform.simulateAccessibilityRequest(.press(disabledID)))
    #expect(disabledPlatform.presentedMenus.isEmpty, "nothing opens a disabled menu picker")
    withExtendedLifetime(window) {}
    withExtendedLifetime(disabled) {}
}

// MARK: - 5.9–5.11

/// A wrapper reaching its content through the **single-element** entry, as a
/// modifier layer written after `.tag` does (`SV-P` item 3).
private struct SingleEntry<Content: Element>: Element {
    var content: Content
    struct LayoutState { var inner: Content.LayoutState; var node: LayoutNodeID }
    mutating func requestLayout(_ id: GlobalElementID, pass: inout LayoutPass) -> (LayoutNodeID, LayoutState) {
        let (node, inner) = content.requestLayout(GlobalElementID.child(of: id, at: 0, name: nil), pass: &pass)
        return (node, LayoutState(inner: inner, node: node))
    }
    mutating func prepaint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout LayoutState,
                           pass: inout PrepaintPass) -> Content.PrepaintState {
        content.prepaint(GlobalElementID.child(of: id, at: 0, name: nil), bounds: bounds, layout: &layout.inner,
                         pass: &pass)
    }
    mutating func paint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout LayoutState,
                        prepaint: inout Content.PrepaintState, pass: inout PaintPass) {
        content.paint(GlobalElementID.child(of: id, at: 0, name: nil), bounds: bounds, layout: &layout.inner,
                      prepaint: &prepaint, pass: &pass)
    }
}

/// **5.9** (`SV-P` item 3). An option reached through the single-element
/// entry is still recorded (it is in the menu) and registers exactly one
/// zero-size node. Mutation: trap on the single entry (or record nothing).
@MainActor
@Test func aModifierAfterTagStillYieldsAMenuOption() throws {
    let model = MPChoice(1)
    let (window, platform) = try controlWindow {
        controlRoot(width: 400, height: 400) {
            Picker("Flavor", selection: model.binding) {
                Text("A").tag(0)
                SingleEntry(content: Text("B").tag(1))
            }
            .pickerStyle(.menu)
        }
    }
    platform.presentsMenusNatively = true
    controlRedraw(window)
    let button = try #require(window.lastElementBounds[buttonID])
    controlClick(platform, at: controlCentre(button))
    let presented = try #require(platform.presentedMenus.last)
    #expect(presented.menu.items.map(\.title) == ["A", "B"])
    #expect(presented.menu.items.map(\.isOn) == [false, true])
    func descends(_ id: GlobalElementID) -> Bool {
        var cursor = id.parent
        while let c = cursor { if c == buttonID { return true }; cursor = c.parent }
        return false
    }
    let leaves = window.lastElementBounds.filter {
        descends($0.key) && $0.value.size.width.value == 0 && $0.value.size.height.value == 0
    }
    #expect(leaves.count == 1, "one zero-size node, for the single entry: \(leaves)")
    withExtendedLifetime(window) {}
}

/// **5.10** (divergence 128). An option whose content is not a `Text` is
/// titled by its tag's description in the menu. Mutation: an empty title.
@MainActor
@Test func aNonTextMenuOptionIsTitledByItsTag() throws {
    let model = MPChoice(0)
    let (window, platform) = try controlWindow {
        controlRoot(width: 400, height: 400) {
            Picker("Flavor", selection: model.binding) {
                Text("Plain").tag(0)
                Rectangle().frame(width: controlPx(10), height: controlPx(10)).tag(42)
            }
            .pickerStyle(.menu)
        }
    }
    platform.presentsMenusNatively = true
    controlRedraw(window)
    controlClick(platform, at: controlCentre(try #require(window.lastElementBounds[buttonID])))
    let presented = try #require(platform.presentedMenus.last)
    #expect(presented.menu.items.map(\.title) == ["Plain", "42"])
    withExtendedLifetime(window) {}
}

/// **5.11** (`SV-P` item 1, divergence 81). `.automatic` stays segmented: its
/// options are click targets side by side and no pop-up button publishes.
@MainActor
@Test func theAutomaticPickerStaysSegmented() throws {
    let model = MPChoice(0)
    let (window, platform) = try controlWindow {
        controlRoot(width: 400, height: 400) {
            Picker("Flavor", selection: model.binding) {
                for (index, title) in titles.enumerated() { Text(title).tag(index) }
            }
        }
    }
    let targets = window.lastHitboxes.filter { $0.handlers.onClick != nil }
    #expect(targets.count == 3, "three segments")
    #expect(Set(targets.map(\.bounds.origin.y)).count == 1, "side by side")
    let tree = try controlTree(window, platform)
    #expect(!tree.nodes.values.contains { $0.role == .popUpButton })
    withExtendedLifetime(window) {}
}

// MARK: - 5.17: the width cache (counted)

/// A `TextSystem` counting `measure` calls whose string is one of `watched`.
private final class CountingTextSystem: TextSystem, @unchecked Sendable {
    let base = CoreTextTextSystem()
    var watched: Set<String> = []
    var count = 0
    func resolveFont(_ descriptor: FontDescriptor) -> FontKey { base.resolveFont(descriptor) }
    func fontMetrics(_ font: FontKey) -> TextFontMetrics { base.fontMetrics(font) }
    func measure(_ string: String, font: FontKey, wrappingAt width: Double?,
                 options: TextLayoutOptions) -> TextMeasurement {
        if watched.contains(string) { count += 1 }
        return base.measure(string, font: font, wrappingAt: width, options: options)
    }
    func placeGlyphs(_ string: String, font: FontKey, wrappingAt width: Double?, options: TextLayoutOptions,
                     origin: (x: Double, y: Double), scaleFactor: Float) -> [TextGlyph] {
        base.placeGlyphs(string, font: font, wrappingAt: width, options: options, origin: origin,
                         scaleFactor: scaleFactor)
    }
    func caretOffsets(_ string: String, font: FontKey) -> [Double] { base.caretOffsets(string, font: font) }
    func lineRanges(_ string: String, font: FontKey, wrappingAt width: Double?,
                    options: TextLayoutOptions) -> [Range<Int>] {
        base.lineRanges(string, font: font, wrappingAt: width, options: options)
    }
    func rasterize(_ key: GlyphKey) -> GlyphImage { base.rasterize(key) }
    func beginFrame() { base.beginFrame() }
    func endFrame() { base.endFrame() }
}

@MainActor private final class MPTitles {
    var titles = (0..<300).map { "Option \($0)" }
}

/// **5.17** (`SV-AA`). The button's width measures every option title on the
/// first frame (300), none on the next warm frame, and all 300 again after one
/// title changes. Literals: the options are `"Option 0"`…`"Option 299"`, each
/// measured once per uncached frame by the width cache; the label measures
/// only the selected title (`"Option 0"`, through `Text`'s own measure, so
/// the watched set excludes it). Mutation: drop the cache-key comparison.
@MainActor
@Test func aWarmMenuPickerFrameMeasuresNoOptionTitle() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let system = CountingTextSystem()
    let model = MPChoice(0)
    let source = MPTitles()
    system.watched = Set(source.titles.dropFirst())
    let platformWindow = try FakePlatformWindow(device: device, size: 400)
    let window = Window(platformWindow: platformWindow, startsDisplayLink: false, textSystem: system) {
        controlRoot(width: 400, height: 400) {
            Picker("Flavor", selection: model.binding) {
                for (index, title) in source.titles.enumerated() { Text(title).tag(index) }
            }
            .pickerStyle(.menu)
        }
    }
    window.drawFrameIfNeeded()
    #expect(system.count == 299, "the first frame measures every title but the selected: \(system.count)")
    system.count = 0
    controlRedraw(window)
    #expect(system.count == 0, "a warm frame measures none: \(system.count)")
    source.titles[5] = "Option five"
    system.watched.insert("Option five")
    system.count = 0
    controlRedraw(window)
    #expect(system.count == 299, "a changed title re-measures them all: \(system.count)")
    withExtendedLifetime(window) {}
}
