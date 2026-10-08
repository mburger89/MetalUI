import Testing
import Metal
import MetalUICore
import MetalUIPlatform
@testable import MetalUI

// C10 lane 1: `ColorPicker<Label>` — its geometry, its well, opening the
// drawn panel and its accessibility (rulings `LK-C`, `LK-P`; spec
// `2026-10-08-controls-looks-design.md` §3.1, §4.1). SwiftUI's numbers are
// probe `C0`/`V12` (`docs/probes/swiftui-controls-looks.swift`): the label,
// 8 points, a 48×24 well (`79 = 23 + 8 + 48` for "Tint"); `C1` the well's
// `rgb R G B A` value. Literals are derived from MetalUI's own measured
// `Text` sizes (`controlTextSize`), never SwiftUI's points. Helpers are
// `ButtonTests.swift`'s `control…` and the `picker…` ones below (internal:
// `ColorPickerPanelTests` reads them).

@MainActor
final class PickerModel {
    var color: Color
    var writes: [Color] = []
    init(_ color: Color) { self.color = color }
    var binding: Binding<Color> {
        Binding(get: { self.color }, set: { self.color = $0; self.writes.append($0) })
    }
}

/// The bounds of every recorded element of `width × height`, top to bottom.
@MainActor
func pickerBounds(_ window: Window, width: Float, height: Float)
    -> [(id: GlobalElementID, bounds: Bounds<Pixels>)] {
    window.lastElementBounds
        .filter { $0.value.size.width.value == width && $0.value.size.height.value == height }
        .map { ($0.key, $0.value) }
        .sorted { $0.bounds.origin.y.value < $1.bounds.origin.y.value }
}

/// The one 48×24 well.
@MainActor
func pickerWell(_ window: Window) throws -> (id: GlobalElementID, bounds: Bounds<Pixels>) {
    let wells = pickerBounds(window, width: 48, height: 24)
    try #require(wells.count == 1, "one 48×24 well, found \(wells.count)")
    return wells[0]
}

/// The panel's 200×150 square, or `nil` while the panel is closed.
@MainActor
func pickerSquare(_ window: Window) -> (id: GlobalElementID, bounds: Bounds<Pixels>)? {
    pickerBounds(window, width: 200, height: 150).first
}

/// A 400-point window over `content` at the top-left of a `Row` root, bounds
/// recorded, one frame drawn.
@MainActor
func pickerWindow<C: ElementGroup>(appearance: Appearance = .light, @ElementBuilder _ content: @escaping @MainActor () -> C)
    throws -> (Window, FakePlatformWindow) {
    let device = try #require(MTLCreateSystemDefaultDevice(), "no Metal device; run on macOS hardware")
    let (window, platform) = try makeFakeWindow(device: device, size: 400, appearance: appearance) {
        controlRoot(width: 400, height: 400) { content() }
    }
    window.recordsElementBounds = true
    window.drawFrameIfNeeded()
    return (window, platform)
}

/// Clicks the well and draws until the panel's square is laid out (a popover
/// appears on the frame after its anchor is recorded, `MN-M` item 2).
@MainActor
func pickerOpen(_ window: Window, _ platform: FakePlatformWindow,
                sourceLocation: SourceLocation = #_sourceLocation) throws -> Bounds<Pixels> {
    controlClick(platform, at: controlCentre(try pickerWell(window).bounds))
    for _ in 0..<3 where pickerSquare(window) == nil { controlRedraw(window) }
    return try #require(pickerSquare(window), "the panel opened", sourceLocation: sourceLocation).bounds
}

// MARK: - Geometry (C0, V12, LK-P)

/// **1.16.** `ColorPicker("Tint", …)` is the label, 8 points, then a 48×24
/// well: own width `textW + 56`, height 24 (C0: 79 = 23 + 8 + 48). Mutation:
/// spacing 6.
@Test @MainActor func aColorPickerIsItsLabelEightPointsAndAFortyEightByTwentyFourWell() throws {
    let text = try controlTextSize("Tint")
    try #require(text.height.value <= 24, "set up: the label is shorter than the well (\(text))")
    let frame = try controlRender(controlRoot { ColorPicker("Tint", selection: .constant(.red)) })
    let picker = try controlBounds(frame, controlID([0, 0]))
    #expect(picker.size.width.value == text.width.value + 56 && picker.size.height.value == 24,
            "\(text.width.value) + 8 + 48 by 24: \(picker.size)")
}

/// **1.17.** An empty title draws the well alone, 48×24 — no label and no gap
/// (`labelsHidden()`'s answer, `LK-C` item 2). Mutation: keep the spacing with
/// no label.
@Test @MainActor func aColorPickerWithAnEmptyTitleIsTheWellAlone() throws {
    let frame = try controlRender(controlRoot { ColorPicker("", selection: .constant(.red)) })
    let picker = try controlBounds(frame, controlID([0, 0]))
    #expect(picker.size.width.value == 48 && picker.size.height.value == 24, "\(picker.size)")
}

/// The label's and the well's bounds inside `root`, both recorded.
@MainActor
private func labelAndWell<E: Element>(_ root: E) throws -> (label: Bounds<Pixels>, well: Bounds<Pixels>) {
    let frame = try controlRender(root)
    let text = try controlTextSize("Tint")
    let well = try #require(frame.elementBounds.values.first { $0.size.width.value == 48 && $0.size.height.value == 24 },
                            "no 48×24 well")
    let label = try #require(frame.elementBounds.values.first { $0.size == text }, "no label of \(text)")
    return (label, well)
}

/// **1.18** (`LK-P`). In a `VStack` the picker stays one node: the well sits
/// beside its label, `textW + 8` to its right, on the same row — not stacked
/// under it. Mutation: make the body a `Component` of two top-level nodes.
@Test @MainActor func aColorPickerInAVStackKeepsItsLabelBesideTheWell() throws {
    let text = try controlTextSize("Tint")
    let (label, well) = try labelAndWell(controlRoot { VStack { ColorPicker("Tint", selection: .constant(.red)) } })
    #expect(well.origin.x.value - label.origin.x.value == text.width.value + 8, "label \(label), well \(well)")
    #expect(well.origin.y.value <= label.origin.y.value
                && well.origin.y.value + 24 >= label.origin.y.value + text.height.value,
            "the label is beside the well, inside its height: label \(label), well \(well)")
}

/// **1.19** (`LK-P`). In an `HStack(spacing: 20)` the picker keeps its own
/// 8-point gap. Mutation: the same `Component` body (the stack's 20 would
/// separate them).
@Test @MainActor func aColorPickerInAnHStackKeepsItsOwnEightPointGap() throws {
    let text = try controlTextSize("Tint")
    let (label, well) = try labelAndWell(controlRoot {
        HStack(spacing: 20) { ColorPicker("Tint", selection: .constant(.red)) }
    })
    #expect(well.origin.x.value - label.origin.x.value == text.width.value + 8, "label \(label), well \(well)")
}

// MARK: - The well (LK-C items 3, 7)

/// **1.20.** A press on the well opens the panel (its 200×150 square is laid
/// out) and does not focus (divergence 94's rule). Mutation: focus on press.
@Test @MainActor func pressingTheWellOpensThePanelAndDoesNotFocus() throws {
    let model = PickerModel(.red)
    let (window, platform) = try pickerWindow { ColorPicker("Tint", selection: model.binding) }
    #expect(pickerSquare(window) == nil, "closed at first")
    _ = try pickerOpen(window, platform)
    #expect(window.focusedElement == nil, "a press does not focus the well")
    #expect(model.writes.isEmpty, "opening writes nothing")
}

/// **1.21.** Space on a focused well opens the panel. Mutation: drop the key.
@Test @MainActor func spaceOnAFocusedWellOpensThePanel() throws {
    let model = PickerModel(.red)
    let (window, platform) = try pickerWindow { ColorPicker("Tint", selection: model.binding) }
    let well = try pickerWell(window).id
    window.focus(well)
    window.drawFrameIfNeeded()
    try #require(window.focusedElement == well, "the well takes focus")
    platform.simulateInput(controlKey(" "))
    for _ in 0..<3 where pickerSquare(window) == nil { controlRedraw(window) }
    #expect(pickerSquare(window) != nil, "Space opened the panel")
}

/// **1.22.** The well publishes as `.colorWell`, no label (the label is its own
/// static text, `C1`), its value `rgb R G B A` printed as AppKit prints it —
/// `rgb 1 0 0 1`, `rgb 0.2 0.4 0.6 0.5` — and a press action. Mutation: print
/// `%.3f`.
@Test @MainActor func theWellPublishesAColorWellWithAppKitsValueFormat() throws {
    for (color, expected) in [(Color(.sRGB, red: 1, green: 0, blue: 0), "rgb 1 0 0 1"),
                              (Color(.sRGB, red: 0.2, green: 0.4, blue: 0.6, opacity: 0.5), "rgb 0.2 0.4 0.6 0.5")] {
        let model = PickerModel(color)
        let (window, platform) = try pickerWindow { ColorPicker("Tint", selection: model.binding) }
        let tree = try controlTree(window, platform)
        let wells = tree.nodes.filter { $0.value.role == .colorWell }
        try #require(wells.count == 1, "one colour well: \(tree.nodes.values.map(\.role))")
        let well = wells.first!.value
        #expect(well.value == expected, "value \(well.value ?? "nil")")
        #expect(well.label == nil, "no label on the well (C1)")
        #expect(well.actions.contains(.press) && well.isFocusable, "pressable and focusable")
        #expect(tree.nodes.values.contains { $0.role == .staticText && $0.value == "Tint" }, "the label is its own text")
    }
}

/// **1.23.** An accessibility press on the well opens the panel (`LK-C` item
/// 7). Mutation: register the well's open as a keyboard-only action.
@Test @MainActor func anAccessibilityPressOnTheWellOpensThePanel() throws {
    let model = PickerModel(.red)
    let (window, platform) = try pickerWindow { ColorPicker("Tint", selection: model.binding) }
    let tree = try controlTree(window, platform)
    let well = try #require(tree.nodes.first { $0.value.role == .colorWell }, "no colour well")
    #expect(platform.simulateAccessibilityRequest(.press(well.key)))
    for _ in 0..<3 where pickerSquare(window) == nil { controlRedraw(window) }
    #expect(pickerSquare(window) != nil, "the press opened the panel")
}
