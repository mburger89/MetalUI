import Foundation
import MetalUI
import MetalUIPlatform
import MetalUIScene
import MetalUITesting
import Testing

// `TabStrip.stripBackground(_:)` and `.selectedTabFill(_:)` (`TBS-N`, record 299). Plain imports, headless `TestWindow`, the portable
// harness text system. The bar is a 500 x 32 rect; the selected tab's cell a 31-point-tall one; subtrees live in Components.

private struct PaintTabs {
    static func items() -> [TabStripItem<String>] {
        [TabStripItem(id: "a", title: "main.swift"), TabStripItem(id: "b", title: "other.swift")]
    }
}

private struct DefaultStrip: Component {
    var content: some ElementGroup { VStack(spacing: Pixels(0)) { TabStrip(selection: .constant("a"), tabs: PaintTabs.items()) } }
}
private struct AutomaticStrip: Component {
    var content: some ElementGroup {
        VStack(spacing: Pixels(0)) { TabStrip(selection: .constant("a"), tabs: PaintTabs.items()).stripBackground(.automatic).selectedTabFill(.automatic) }
    }
}
private struct ClearBarStrip: Component {
    var content: some ElementGroup { VStack(spacing: Pixels(0)) { TabStrip(selection: .constant("a"), tabs: PaintTabs.items()).stripBackground(.clear) } }
}
private struct RedBarStrip: Component {
    var content: some ElementGroup {
        VStack(spacing: Pixels(0)) { TabStrip(selection: .constant("a"), tabs: PaintTabs.items()).stripBackground(.color(Color(red: 1, green: 0, blue: 0))) }
    }
}
private struct MaterialBarStrip: Component {
    var content: some ElementGroup {
        VStack(spacing: Pixels(0)) { TabStrip(selection: .constant("a"), tabs: PaintTabs.items()).stripBackground(.material(.regularMaterial)) }
    }
}
private struct GreenFillStrip: Component {
    let shape: TabStripSelectionShape
    var content: some ElementGroup {
        VStack(spacing: Pixels(0)) {
            TabStrip(selection: .constant("a"), tabs: PaintTabs.items()).selectedTabShape(shape).selectedTabFill(.color(Color(red: 0, green: 1, blue: 0)))
        }
    }
}
private struct ClearFillStrip: Component {
    var content: some ElementGroup {
        VStack(spacing: Pixels(0)) { TabStrip(selection: .constant("a"), tabs: PaintTabs.items()).selectedTabFill(.clear) }
    }
}
private struct MaterialFillStrip: Component {
    let shape: TabStripSelectionShape
    var content: some ElementGroup {
        VStack(spacing: Pixels(0)) { TabStrip(selection: .constant("a"), tabs: PaintTabs.items()).selectedTabShape(shape).selectedTabFill(.material(.thickMaterial)) }
    }
}

@MainActor private func paintWindow<C: Component>(_ scheme: ColorScheme = .light, _ make: @escaping @MainActor () -> C) throws -> TestWindow {
    let w = try TestWindow(size: sz(500, 100), colorScheme: scheme, textSystem: harnessTextSystem) { VStack(spacing: Pixels(0)) { make() } }
    w.window.setNeedsRedraw()
    w.tick()
    return w
}

@MainActor private func signature(_ w: TestWindow) -> String {
    w.scene.rects.map { "\($0.bounds) r=\($0.cornerRadii.topLeft) bw=\($0.borderWidths.top) bg=\($0.background) bc=\($0.borderColor)" }
        .joined(separator: "\n") + "\nbackdrops: \(w.scene.backdrops.count)"
}
/// The bar's band: the 500-wide, 32-tall rect.
@MainActor private func band(_ w: TestWindow) -> [MUIRect] {
    w.scene.rects.filter { $0.bounds.size.width == 500 && $0.bounds.size.height == 32 }
}
/// The selected tab's fill: a visible rect 31 tall (the full-bleed cell) or 23 tall (the inset pill) narrower than the bar.
@MainActor private func selectedFills(_ w: TestWindow) -> [MUIRect] {
    w.scene.rects.filter { ($0.bounds.size.height == 31 || $0.bounds.size.height == 23) && $0.bounds.size.width > 30
        && $0.bounds.size.width < 300 && $0.background.a > 0 }
}
private func near(_ c: MUIHsla, _ other: Hsla) -> Bool {
    abs(c.h - other.h) < 0.005 && abs(c.s - other.s) < 0.005 && abs(c.l - other.l) < 0.005 && abs(c.a - other.a) < 0.005
}
private let red = Hsla(h: 0, s: 1, l: 0.5, a: 1)
private let green = Hsla(h: 1.0 / 3, s: 1, l: 0.5, a: 1)

/// 1 - the defaults: the bar is the theme's `surfaceSecondary` (one 500 x 32 rect), the selected cell its `background`, and
/// spelling `.automatic` twice changes nothing. Mutation: **M1** `.automatic` mapped to `.clear` (or the fill to a colour) reddens it.
@Test @MainActor func theDefaultsAreTodaysLook() throws {
    let plain = try paintWindow { DefaultStrip() }
    let explicit = try paintWindow { AutomaticStrip() }
    #expect(signature(plain) == signature(explicit), "`.automatic` is the default")
    let bar = band(plain)
    try #require(bar.count == 1, "one band: \(bar.count)")
    #expect(near(bar[0].background, plain.window.theme.surfaceSecondary), "\(bar[0].background)")
    let fills = selectedFills(plain)
    try #require(fills.count == 1, "one selected cell: \(fills.count)")
    #expect(near(fills[0].background, plain.window.theme.background), "\(fills[0].background)")
}

/// 2 - `.clear` draws no band at all while the selected cell keeps its fill. Mutation: **M2** `.clear` painting a transparent
/// `Color` still emits nothing visible but a band of `surfaceSecondary` returns when the case falls to `.automatic`.
@Test @MainActor func aClearBarDrawsNoBand() throws {
    let clear = try paintWindow { ClearBarStrip() }
    #expect(band(clear).isEmpty, "no 500 x 32 rect: \(band(clear).count)")
    #expect(!clear.scene.rects.contains { $0.bounds.size.width == 500 && $0.bounds.size.height >= 31 && $0.background.a > 0 }, "nothing wide and visible")
    #expect(selectedFills(clear).count == 1, "the selected tab still fills")
    #expect(clear.scene.backdrops.isEmpty, "and no backdrop")
}

/// 3 - a colour bar paints that colour, a material bar the material's rect and its backdrop. Mutation: **M3** the colour ignored.
@Test @MainActor func aColourOrMaterialBarPaintsThatStyle() throws {
    let coloured = try paintWindow { RedBarStrip() }
    let bar = band(coloured)
    try #require(bar.count == 1, "one band: \(bar.count)")
    #expect(near(bar[0].background, red), "\(bar[0].background)")
    let material = try paintWindow { MaterialBarStrip() }
    #expect(!material.scene.backdrops.isEmpty, "a material records its backdrop")
    #expect(material.scene.backdrops.contains { $0.bounds.size.width == 500 && $0.bounds.size.height == 32 }, "over the bar")
    let plain = try paintWindow { DefaultStrip() }
    #expect(plain.scene.backdrops.isEmpty)
}

/// 4 - a selected fill paints in the cell, the capsule and the rounded rectangle; the shape is kept. Mutation: **M4** the fill read
/// only on the rectangle path reddens the capsule and rounded arms.
@Test @MainActor func aSelectedFillColoursEveryShape() throws {
    let flat = try paintWindow { GreenFillStrip(shape: .rectangle) }
    let cell = selectedFills(flat)
    try #require(cell.count == 1, "\(cell.count)")
    #expect(near(cell[0].background, green) && cell[0].bounds.size.height == 31 && cell[0].cornerRadii.topLeft == 0, "\(cell[0].background)")
    let capsule = try paintWindow { GreenFillStrip(shape: .capsule) }
    let pill = selectedFills(capsule)
    try #require(pill.count == 1, "\(pill.count)")
    #expect(near(pill[0].background, green) && pill[0].bounds.size.height == 23 && pill[0].cornerRadii.topLeft == 11.5, "\(pill[0].bounds) \(pill[0].background)")
    let rounded = try paintWindow { GreenFillStrip(shape: .roundedRectangle(radius: 6)) }
    let box = selectedFills(rounded)
    try #require(box.count == 1, "\(box.count)")
    #expect(near(box[0].background, green) && box[0].cornerRadii.topLeft == 6, "\(box[0].cornerRadii.topLeft)")
    #expect(band(capsule).count == 1, "the bar is untouched")
}

/// 5 - a clear selected fill draws no fill; a material fill draws a backdrop in the cell and the pill. Mutation: **M5** `.clear`
/// falling to `.automatic` leaves a fill and reddens the first arm.
@Test @MainActor func aClearOrMaterialSelectedFill() throws {
    let clear = try paintWindow { ClearFillStrip() }
    #expect(selectedFills(clear).isEmpty, "no selected fill: \(selectedFills(clear).count)")
    #expect(clear.scene.rects.contains { $0.bounds.size.width == 1 && $0.bounds.size.height == 31 }, "the hairlines stay")
    for shape in [TabStripSelectionShape.rectangle, .capsule] {
        let w = try paintWindow { MaterialFillStrip(shape: shape) }
        #expect(w.scene.backdrops.count == 1, "\(shape): \(w.scene.backdrops.count) backdrops")
        let height: Float = shape == .rectangle ? 31 : 23
        #expect(w.scene.backdrops.contains { $0.bounds.size.height == height }, "\(shape) at \(height)")
    }
}

/// 6 - theme switch: the automatic bar and cell follow a runtime theme assignment, a custom colour does not. Mutation: **M6**
/// resolving the automatic bar once (a fixed colour) reddens the first arm.
@Test @MainActor func aThemeSwitchRepaintsTheAutomaticPaint() throws {
    let w = try paintWindow { DefaultStrip() }
    var themed = Theme.light
    themed.surfaceSecondary = Hsla(h: 0.6, s: 0.5, l: 0.3, a: 1)
    themed.background = Hsla(h: 0.1, s: 0.5, l: 0.7, a: 1)
    w.window.lightTheme = themed
    w.window.setNeedsRedraw()
    w.tick()
    #expect(near(band(w)[0].background, themed.surfaceSecondary), "bar \(band(w)[0].background)")
    #expect(near(selectedFills(w)[0].background, themed.background), "cell")
    let fixed = try paintWindow { RedBarStrip() }
    fixed.window.lightTheme = themed
    fixed.window.setNeedsRedraw()
    fixed.tick()
    #expect(near(band(fixed)[0].background, red), "a custom colour stays")
}

/// 7 - the paints take part in `==`: a strip with another bar or fill is not equal. Mutation: **M7** leaving them out of `==` reddens it.
@Test @MainActor func thePaintsTakePartInEquality() {
    let a = TabStrip(selection: .constant("a"), tabs: PaintTabs.items())
    #expect(a == a.stripBackground(.automatic).selectedTabFill(.automatic))
    #expect(a != a.stripBackground(.clear))
    #expect(a != a.selectedTabFill(.clear))
    #expect(a.stripBackground(.color(Color(red: 1, green: 0, blue: 0))) != a.stripBackground(.color(Color(red: 0, green: 1, blue: 0))))
}
