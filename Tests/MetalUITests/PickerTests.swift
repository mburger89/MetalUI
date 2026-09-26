import Testing
import Metal
import MetalUICore
import MetalUIPlatform
@testable import MetalUI

// Plan task 10, part 2, lane 1: `Picker(selection:)`, `.tag(_:)` and the closed
// `PickerStyle` (ruling `DD-V`; spec tests 1.14–1.20, 1.24). Helpers are
// `ButtonTests.swift`'s `control…`.
//
// **Options are found by their hitboxes**, not by a hand-spelled internal id:
// every option is a click target, so the frame's `onClick` hitboxes sorted by
// position are the options in order, whatever the picker's internal nesting.

private enum Flavor: Hashable { case alpha, beta, gamma }

private let labels = ["A", "Medium", "The longest one"]

@MainActor
private final class Choice<V: Hashable> {
    var value: V
    var writes: [V] = []
    init(_ value: V) { self.value = value }
    var binding: Binding<V> {
        Binding(get: { self.value }, set: { self.value = $0; self.writes.append($0) })
    }
}

@MainActor
private func flavorPicker(_ model: Choice<Flavor>, style: PickerStyle = .automatic)
    -> Picker<Flavor, some ElementGroup> {
    Picker("Flavor", selection: model.binding) {
        Text(labels[0]).tag(Flavor.alpha)
        Text(labels[1]).tag(Flavor.beta)
        Text(labels[2]).tag(Flavor.gamma)
    }
    .pickerStyle(style)
}

/// The option hitboxes, sorted by x then y.
private func options(_ hitboxes: [Hitbox]) -> [Hitbox] {
    hitboxes.filter { $0.handlers.onClick != nil }.sorted {
        ($0.bounds.origin.x.value, $0.bounds.origin.y.value) < ($1.bounds.origin.x.value, $1.bounds.origin.y.value)
    }
}

@MainActor
private func pickerWindow(_ model: Choice<Flavor>, style: PickerStyle = .automatic,
                          disabled: Bool = false) throws -> (Window, FakePlatformWindow) {
    try controlWindow {
        controlRoot { flavorPicker(model, style: style).disabled(disabled) }
    }
}

/// **1.14.** Segmented: every segment as wide as the widest (`textW + 24`
/// before equalising), the row three times that, the whole `titleW + 8 + row`
/// (PK1, PA1). Segments sit at fractional x after the widest's width, so each
/// is within one rounding of the width, and the row within three (the widest's
/// raw width is rounded once and multiplied); a segment at its own width
/// misses by tens of points. M1l (`EqualWidthRow` places each at
/// its own ideal width) must redden it.
@Test @MainActor func aSegmentedPickerMakesEverySegmentAsWideAsTheWidest() throws {
    let widths = try labels.map { try controlTextSize($0).width.value }
    let title = try controlTextSize("Flavor").width.value
    let widest = try #require(widths.max()) + 24
    // 600 wide, so the whole picker (≈ 411) is not compressed.
    let frame = try controlRender(controlRoot(width: 600) { flavorPicker(Choice(.alpha)) }, width: 600)
    let segments = options(frame.hitboxes)
    try #require(segments.count == 3, "three segment click targets, read \(segments.count)")
    for (index, segment) in segments.enumerated() {
        #expect(abs(segment.bounds.size.width.value - widest) <= 1,
                "segment \(index) is the widest's width \(widest), read \(segment.bounds.size.width.value)")
    }
    let row = segments[2].bounds.origin.x.value + segments[2].bounds.size.width.value
        - segments[0].bounds.origin.x.value
    // Three times a width rounded once: within 3 × ½ plus an edge's rounding.
    #expect(abs(row - 3 * widest) <= 3, "the row is 3 × the widest: \(row) vs \(3 * widest)")
    let picker = try controlBounds(frame, controlID([0, 0]))
    #expect(abs(picker.size.width.value - (title + 8 + 3 * widest)) <= 3,
            "title, 8, the row: \(picker.size.width.value) vs \(title + 8 + 3 * widest)")
    #expect(abs(segments[0].bounds.origin.x.value - (title + 8)) <= 1, "the row starts 8 after the title")
}

/// **1.15.** A press writes the option's **tag**, not its position: a click on
/// the third segment writes `.gamma`, an accessibility press on the first
/// writes `.alpha` (PA1, PA2). M1m (the option writes its position, as an
/// `Int`) reddens all three arms: an `Int` is no `Flavor`, so the enum arms
/// write nothing, and the `Int`-tagged arm (tags 10/20/30) reads 0.
@Test @MainActor func pressingAnOptionWritesItsTag() throws {
    let model = Choice(Flavor.beta)
    let (window, platform) = try pickerWindow(model)
    let segments = options(window.lastHitboxes)
    try #require(segments.count == 3)
    controlClick(platform, at: controlCentre(segments[2].bounds))
    #expect(model.writes == [.gamma], "the third segment's tag")
    let tree = try controlTree(window, platform)
    let radios = tree.nodes.filter { $0.value.role == .radioButton }
        .sorted { (tree.geometry[$0.key]?.order ?? 0) < (tree.geometry[$1.key]?.order ?? 0) }
    try #require(radios.count == 3, "three radio buttons")
    #expect(platform.simulateAccessibilityRequest(.press(radios[0].key)))
    #expect(model.writes == [.gamma, .alpha], "the first option's tag")

    // Tags that are not positions: 10, 20, 30.
    let numbers = Choice(20)
    let (numbersWindow, numbersPlatform) = try controlWindow {
        controlRoot {
            Picker("N", selection: numbers.binding) {
                Text("ten").tag(10)
                Text("twenty").tag(20)
                Text("thirty").tag(30)
            }
        }
    }
    let numberSegments = options(numbersWindow.lastHitboxes)
    try #require(numberSegments.count == 3)
    controlClick(numbersPlatform, at: controlCentre(numberSegments[0].bounds))
    #expect(numbers.writes == [10], "the first option's tag is 10, not 0")
}

/// **1.16.** A selection matching no tag selects nothing and writes nothing
/// over two frames (PA3). M1n′ (an unmatched selection writes the first tag)
/// must redden it.
@Test @MainActor func aSelectionMatchingNoTagSelectsNothingAndWritesNothing() throws {
    let model = Choice(99)
    let (window, platform) = try controlWindow {
        controlRoot {
            Picker("N", selection: model.binding) {
                Text("one").tag(1)
                Text("two").tag(2)
                Text("three").tag(3)
            }
        }
    }
    let tree = try controlTree(window, platform)
    controlRedraw(window)
    let radios = tree.nodes.values.filter { $0.role == .radioButton }
    try #require(radios.count == 3, "three radio buttons, read \(radios.count)")
    #expect(radios.allSatisfy { !$0.isSelected && $0.value == "0" }, "nothing selected")
    #expect(model.writes.isEmpty, "nothing written: \(model.writes)")
}

/// **1.17.** A radio group labelled by its title, three radio buttons
/// labelled by their options, `"1"` and `.selected` on the chosen one only
/// (PA1, PA2; divergence 82 — SwiftUI publishes the title as a sibling text).
/// M1n (the partial fold removed) must redden it.
@Test @MainActor func aPickerPublishesARadioGroupTitledByItsTitle() throws {
    for style in [PickerStyle.segmented, .radioGroup] {
        let model = Choice(Flavor.beta)
        let (window, platform) = try pickerWindow(model, style: style)
        let tree = try controlTree(window, platform)
        let group = try #require(tree.nodes.first { $0.value.role == .radioGroup },
                                 "\(style): no radio group: \(tree.nodes.values.map(\.role))")
        #expect(group.value.label == "Flavor", "\(style): titled by its title")
        let children = group.value.children.compactMap { tree.nodes[$0] }
        try #require(children.count == 3, "\(style): three children, read \(children.map(\.role))")
        #expect(children.map(\.role) == [.radioButton, .radioButton, .radioButton])
        #expect(children.map(\.label) == labels.map(Optional.some), "\(style): labelled by option")
        #expect(children.map(\.value) == ["0", "1", "0"], "\(style): the chosen one reads 1")
        #expect(children.map(\.isSelected) == [false, true, false], "\(style): selected on the chosen one")
        #expect(tree.nodes.count == 4, "\(style): the title is the group's label, not a node")
    }
}

/// **1.18.** Radio group: a leading-aligned column of rows `14 + 7 + textW_i`,
/// 6 apart (PK1, PK2/PK3; `DD-AC` item 8). Read within each row, so the
/// arithmetic is exact after rounding. M1o (gap 6 → 8) and M1o′ (the row's
/// indicator gap 7 → 6) must redden it.
@Test @MainActor func aRadioGroupPickerStacksItsOptionsSixPointsApart() throws {
    let widths = try labels.map { try controlTextSize($0).width.value }
    let frame = try controlRender(controlRoot { flavorPicker(Choice(.alpha), style: .radioGroup) })
    let rows = options(frame.hitboxes)
    try #require(rows.count == 3, "three option rows, read \(rows.count)")
    for (index, row) in rows.enumerated() {
        let indicator = try controlBounds(frame, GlobalElementID.child(of: row.id, at: 0, name: nil))
        let label = try controlBounds(frame, GlobalElementID.child(of: row.id, at: 1, name: nil))
        #expect(indicator.size.width.value == 14 && indicator.size.height.value == 14, "row \(index): 14-pt circle")
        #expect(indicator.origin.x.value == row.bounds.origin.x.value, "row \(index): the circle leads")
        #expect(label.origin.x.value - indicator.origin.x.value == 21, "row \(index): 14 + 7 before the label")
        #expect(abs(label.size.width.value - widths[index]) <= 1, "row \(index): the label's width")
        #expect(row.bounds.origin.x.value + row.bounds.size.width.value
                    == label.origin.x.value + label.size.width.value, "row \(index): the row ends at its label")
        #expect(row.bounds.origin.x.value == rows[0].bounds.origin.x.value, "row \(index): leading-aligned")
    }
    for index in 1..<rows.count {
        let gap = rows[index].bounds.origin.y.value
            - (rows[index - 1].bounds.origin.y.value + rows[index - 1].bounds.size.height.value)
        #expect(gap == 6, "rows \(index - 1)–\(index) are 6 apart, read \(gap)")
    }
}

/// **1.19.** A focused picker moves its selection with the arrows and does not
/// wrap: → from the last writes nothing, ← from the first writes nothing, →
/// from the first writes the second; with nothing selected → writes the first
/// tag and ← the last. M1p (wrap-around) and V14 (forward from no selection
/// writes index 1) must redden it.
@Test @MainActor func aFocusedPickerMovesItsSelectionWithTheArrowsAndDoesNotWrap() throws {
    let model = Choice(Flavor.gamma)
    let (window, platform) = try pickerWindow(model)
    let id = controlID([0, 0])
    window.focus(id)
    window.drawFrameIfNeeded()
    try #require(window.focusedElement == id, "a picker takes focus")
    platform.simulateInput(controlKey(TextEditing.rightArrow))
    platform.simulateInput(controlKey(TextEditing.downArrow))
    #expect(model.writes.isEmpty, "past the last: nothing, read \(model.writes)")
    model.value = .alpha
    controlRedraw(window)
    platform.simulateInput(controlKey(TextEditing.leftArrow))
    platform.simulateInput(controlKey(TextEditing.upArrow))
    #expect(model.writes.isEmpty, "before the first: nothing, read \(model.writes)")
    platform.simulateInput(controlKey(TextEditing.rightArrow))
    #expect(model.writes == [.beta], "→ from the first writes the second")

    // With nothing selected, → selects the first option and ← the last
    // (`PickerScope.move`).
    let numbers = Choice(99)
    let (numbersWindow, numbersPlatform) = try controlWindow {
        controlRoot {
            Picker("N", selection: numbers.binding) {
                Text("one").tag(1)
                Text("two").tag(2)
                Text("three").tag(3)
            }
        }
    }
    numbersWindow.focus(id)
    numbersWindow.drawFrameIfNeeded()
    try #require(numbersWindow.focusedElement == id)
    numbersPlatform.simulateInput(controlKey(TextEditing.rightArrow))
    #expect(numbers.writes == [1], "→ from no selection writes the first tag, read \(numbers.writes)")
    numbers.value = 99
    controlRedraw(numbersWindow)
    numbersPlatform.simulateInput(controlKey(TextEditing.leftArrow))
    #expect(numbers.writes == [1, 3], "← from no selection writes the last tag, read \(numbers.writes)")
}

/// **1.19b.** A caller's `onKey` runs before the picker's arrows (spec §4, as
/// 1.6 for `Button`): one that claims → suppresses the move; one that declines
/// lets it run. V15 (the picker's key replaces the caller's `onKey`) must
/// redden it (`DD-AE` item 1).
@Test @MainActor func aCallersOnKeyRunsBeforeThePickersArrows() throws {
    for claims in [true, false] {
        let model = Choice(Flavor.alpha)
        let seen = ControlModel()
        let (window, platform) = try controlWindow {
            controlRoot {
                flavorPicker(model).onKey { event in
                    seen.keys.append(event.charactersIgnoringModifiers)
                    return claims
                }
            }
        }
        let id = controlID([0, 0])
        window.focus(id)
        window.drawFrameIfNeeded()
        try #require(window.focusedElement == id)
        platform.simulateInput(controlKey(TextEditing.rightArrow))
        #expect(seen.keys == [TextEditing.rightArrow], "claims \(claims): the caller saw the key first")
        #expect(model.writes == (claims ? [] : [.beta]), "claims \(claims): the move ran only if declined")
    }
}

/// A counter whose width shows its own `@State`, for 1.20's retention arm.
private struct Counter: Element {
    @State var taps = 0
    var elementID: ElementID? { nil }
    mutating func requestLayout(_ id: GlobalElementID, pass: inout LayoutPass) -> (LayoutNodeID, Box<EmptyGroup>.Layout) {
        var box = Box().cssWidth(controlPx(Float(10 + taps))).cssHeight(controlPx(10))
        return box.requestLayout(id, pass: &pass)
    }
    mutating func prepaint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Box<EmptyGroup>.Layout,
                           pass: inout PrepaintPass) {
        let state = $taps
        var box = Box().cssWidth(controlPx(Float(10 + taps))).cssHeight(controlPx(10))
            .onClick { state.wrappedValue += 1 }
        box.prepaint(id, bounds: bounds, layout: &layout, pass: &pass)
    }
    mutating func paint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Box<EmptyGroup>.Layout,
                        prepaint: inout Void, pass: inout PaintPass) {}
}

/// **1.20.** A tag outside a picker changes nothing (`DD-V` item 6, record §05's
/// row): `Text("A").tag(1)` in a `Row` gives the scene, bounds and `StateTable`
/// ids of `Text("A")`; a grown `Box().flexGrow(1).tag(1)` keeps its grown width
/// beside a fixed sibling (`DD-AC` item 5, the container arm); an `.id` on the
/// tagged content still names it; and a tagged element's `@State` is bound.
/// Measured (`DD-AD` item 2): M1q (`TaggedElement` builds its segment chrome
/// with no scope) reddens the leaf arm's bounds and ids and the `@State` arm;
/// M1q′ (it forwards only the three phases, the Element defaults taking the
/// group entry and `elementID`) reddens the `.id` and `@State` arms. **The
/// container arm reddens under neither** — a lowered record passes through
/// any wrapper that registers the content's node, and a greedy child makes a
/// wrapping chrome greedy too — so it is a regression pin for the record's
/// passage, not the discriminator `DD-AC` item 5 took it for.
@Test @MainActor func aTagOutsideAPickerChangesNothing() throws {
    func leaf<C: ElementGroup>(@ElementBuilder _ content: () -> C) throws
        -> (bounds: [GlobalElementID: Bounds<Pixels>], ids: Set<GlobalElementID>, rects: Int, glyphs: Int) {
        let table = StateTable()
        var root = controlRoot { content() }
        let frame = Frame(contentSize: Size(width: controlPx(400), height: controlPx(200)), scaleFactor: 1,
                          stateTable: table, reportsUnlowerableFields: true, recordsElementBounds: true)
        frame.render(&root)
        try #require(frame.unlowerableFields.isEmpty)
        return (frame.elementBounds, table.ids, frame.scene.rects.count, frame.scene.glyphs.count)
    }
    let plain = try leaf { Text("A") }, tagged = try leaf { Text("A").tag(1) }
    try #require(!plain.bounds.isEmpty, "set up: bounds recorded")
    #expect(plain.bounds == tagged.bounds, "the same ids and bounds")
    #expect(plain.ids == tagged.ids, "the same StateTable ids")
    #expect(plain.rects == tagged.rects && plain.glyphs == tagged.glyphs, "the same scene")

    // The container arm: a grown box keeps its grown width through `.tag`.
    let grown = try controlRender(controlRoot {
        Box().flexGrow(1).cssHeight(controlPx(10)).tag(1)
        Box().cssWidth(controlPx(100)).cssHeight(controlPx(10))
    })
    #expect(try controlBounds(grown, controlID([0, 0])).size.width.value == 300,
            "the tagged grower takes the free 300")

    // An `.id` on the tagged content names it, as it does untagged.
    let named = try controlRender(controlRoot { Text("A").id("a").tag(1) })
    let namedID = GlobalElementID.child(of: controlID([0]), at: 0, name: ElementID("a"))
    #expect(named.elementBounds[namedID] != nil, "the content's `.id` survives the tag")

    // A tagged element's `@State` is bound: a click grows the counter by one.
    let (window, platform) = try controlWindow { controlRoot { Counter().tag(1) } }
    let counter = try controlBounds(window.lastFrameBounds(), controlID([0, 0]))
    try #require(counter.size.width.value == 10)
    controlClick(platform, at: controlCentre(counter))
    controlRedraw(window)
    #expect(try controlBounds(window.lastFrameBounds(), controlID([0, 0])).size.width.value == 11,
            "the tagged element's @State survives the click")
}

/// A `Counter` named `"c"`, for 1.20b's retention arm inside a picker.
private struct NamedCounter: Element {
    @State var taps = 0
    var elementID: ElementID? { ElementID("c") }
    mutating func requestLayout(_ id: GlobalElementID, pass: inout LayoutPass) -> (LayoutNodeID, Box<EmptyGroup>.Layout) {
        var box = Box().cssWidth(controlPx(Float(10 + taps))).cssHeight(controlPx(10))
        return box.requestLayout(id, pass: &pass)
    }
    mutating func prepaint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Box<EmptyGroup>.Layout,
                           pass: inout PrepaintPass) {
        let state = $taps
        var box = Box().cssWidth(controlPx(Float(10 + taps))).cssHeight(controlPx(10))
            .onClick { state.wrappedValue += 1 }
        box.prepaint(id, bounds: bounds, layout: &layout, pass: &pass)
    }
    mutating func paint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Box<EmptyGroup>.Layout,
                        prepaint: inout Void, pass: inout PaintPass) {}
}

/// **1.20b.** Inside a `Picker` an option's chrome takes the content's `.id`
/// as its own (`TaggedElement.makeChrome`): `Text("A").id("a").tag(1)`'s
/// option records its bounds at the **named** id under the options `Box`, not
/// at `positional(0)`; and a named option's content keeps its `@State` under
/// that name across a selection change. V18 (the chrome takes no
/// `elementID`) must redden it (`DD-AE` item 2).
@Test @MainActor func anOptionInsideAPickerTakesItsContentsIDAndKeepsItsState() throws {
    let model = Choice(3)
    let (window, platform) = try controlWindow {
        controlRoot {
            Picker("N", selection: model.binding) {
                Text("A").id("a").tag(1)
                NamedCounter().tag(2)
                Text("C").tag(3)
            }
        }
    }
    let options = controlID([0, 0, 1])
    let named = GlobalElementID.child(of: options, at: 0, name: ElementID("a"))
    let namedCounter = GlobalElementID.child(of: options, at: 1, name: ElementID("c"))
    let bounds = window.lastElementBounds
    #expect(bounds[named] != nil, "the first option's chrome is named \"a\"")
    #expect(bounds[GlobalElementID.child(of: options, at: 0, name: nil)] == nil,
            "no option sits at positional(0)")
    #expect(bounds[namedCounter] != nil, "the second option's chrome is named \"c\"")

    func counter() throws -> (GlobalElementID, Bounds<Pixels>) {
        try #require(window.lastElementBounds.first {
            $0.value.size.height.value == 10 && $0.value.size.width.value >= 10 && $0.value.size.width.value <= 12
        }, "no counter bounds")
    }
    let (counterID, before) = try counter()
    #expect(counterID.parent == namedCounter, "the counter numbers under its named option")
    try #require(before.size.width.value == 10)
    controlClick(platform, at: controlCentre(before))
    controlRedraw(window)
    try #require(try counter().1.size.width.value == 11, "set up: the counter's click landed")
    model.value = 2
    controlRedraw(window)
    model.value = 1
    controlRedraw(window)
    let (afterID, after) = try counter()
    #expect(afterID == counterID && after.size.width.value == 11,
            "the counter's @State survives two selection changes under its named option")
}

/// **1.20c.** A tag nested inside an option is transparent (the barrier
/// `TaggedElement` pushes around its content): a picker over
/// `Row { Text("x").tag(2) }.tag(1)` and `Text("y").tag(3)` publishes two
/// radio buttons, and → from the first option goes to 3, not to 2. V10 (no
/// barrier) must redden it (`DD-AE` item 2).
@Test @MainActor func aTagNestedInsideAnOptionIsNotASecondOption() throws {
    let model = Choice(1)
    let (window, platform) = try controlWindow {
        controlRoot {
            Picker("N", selection: model.binding) {
                Row { Text("x").tag(2) }.tag(1)
                Text("y").tag(3)
            }
        }
    }
    let id = controlID([0, 0])
    window.focus(id)
    window.drawFrameIfNeeded()
    try #require(window.focusedElement == id)
    platform.simulateInput(controlKey(TextEditing.rightArrow))
    #expect(model.writes == [3], "→ from the first goes to the next top-level option, read \(model.writes)")
    model.value = 1
    let tree = try controlTree(window, platform)
    let radios = tree.nodes.values.filter { $0.role == .radioButton }
    #expect(radios.count == 2, "two options, read \(radios.count): \(tree.nodes.values.map(\.role))")
}

/// **1.24.** Disabled: a segment click, focused arrows and a `.press` write
/// nothing; the group and every radio button publish disabled (PA4; `DD-AC`
/// item 7). M1g, re-run on this arm, reddens it; so does M1t (the partial
/// fold keeping only interactive descendants, which folds a disabled
/// picker's options into its label — `DD-AD` item 1).
@Test @MainActor func aDisabledPickerWritesNothingAndPublishesDisabled() throws {
    let model = Choice(Flavor.alpha)
    let (window, platform) = try pickerWindow(model, disabled: true)
    // Disabled: no hitbox, so the segment is found by its element bounds.
    let tree = try controlTree(window, platform)
    let radios = tree.nodes.filter { $0.value.role == .radioButton }
    try #require(radios.count == 3, "three radio buttons")
    let third = try #require(radios.max { (tree.geometry[$0.key]?.frame.origin.x.value ?? 0)
        < (tree.geometry[$1.key]?.frame.origin.x.value ?? 0) })
    let frame = try #require(tree.geometry[third.key]?.frame)
    controlClick(platform, at: controlCentre(frame))
    let id = controlID([0, 0])
    window.focus(id)
    window.drawFrameIfNeeded()
    platform.simulateInput(controlKey(TextEditing.rightArrow))
    for radio in radios { platform.simulateAccessibilityRequest(.press(radio.key)) }
    #expect(model.writes.isEmpty, "nothing written while disabled: \(model.writes)")
    let group = try #require(tree.nodes.values.first { $0.role == .radioGroup })
    #expect(group.isEnabled == false, "the group publishes disabled")
    #expect(radios.values.allSatisfy { !$0.isEnabled }, "every option publishes disabled")
}
