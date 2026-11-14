import MetalUI
import MetalUIScene
import MetalUIPlatform
import MetalUITesting
import Testing

// Alloy gap G46 (record 294; rulings `BY-L`, `BY-M`, `SD-E`, `TBS-M`; probe `swiftui-button-border-shape.swift` BO0):
// `.buttonBorderShape(_:)` on bordered, prominent and glass buttons, `Menu` and the menu `Picker`; the segmented picker's
// own `.segmentedPickerShape(_:)`; `TabStrip.selectedTabShape(_:)`. Plain imports and the portable harness text system,
// so the file runs on Linux and Windows as it does on macOS (state writes dirty asynchronously there: `redraw`).

private let size = Size(width: Pixels(320), height: Pixels(200))

@MainActor private func window<Root: Element>(scheme: ColorScheme = .light,
                                              @ElementBuilder _ content: @escaping @MainActor () -> Root) throws -> TestWindow {
    let w = try TestWindow(size: size, colorScheme: scheme, textSystem: harnessTextSystem, content: content)
    redraw(w)
    return w
}

@MainActor private func redraw(_ w: TestWindow) {
    w.window.setNeedsRedraw()
    w.tick()
}

/// A line per drawn rect and backdrop: bounds, radius, border width, background. Equal strings are equal drawings.
@MainActor private func signature(_ w: TestWindow) -> String {
    w.scene.rects.map { "\($0.bounds) r=\($0.cornerRadii.topLeft)/\($0.cornerRadii.bottomRight) bw=\($0.borderWidths.top) bg=\($0.background) bc=\($0.borderColor)" }
        .joined(separator: "\n")
        + "\nglass: " + w.scene.backdrops.map { "\($0.bounds) \($0.cornerRadii.topLeft)" }.joined(separator: ",")
}

/// The visible rects at least 20 tall and 8 wide: a control's chrome, its border and its ring.
@MainActor private func chromeRects(_ w: TestWindow) -> [MUIRect] {
    w.scene.rects.filter { $0.bounds.size.height >= 20 && $0.bounds.size.width >= 8 && ($0.background.a > 0 || $0.borderWidths.top > 0) }
}

@MainActor private func radii(_ w: TestWindow) -> Set<Float> {
    Set(chromeRects(w).map { $0.cornerRadii.topLeft })
}

private let blue = Color(red: 0, green: 0, blue: 1)

/// BO0: a bordered button under `.capsule` fills and borders at half its height: 12 for the 24-point chrome, 20 for a 40-point
/// label. Mutation: a radius fixed at 12 (not from the bounds) reddens the tall arm; dropping the paint-time write reddens both.
@Test @MainActor func aCapsuleBorderedButtonHasHalfHeightCornerRadii() throws {
    let w = try window { Button("Go") {}.buttonBorderShape(.capsule) }
    let rects = chromeRects(w)
    #expect(rects.count >= 2, "the fill and the border: \(rects.count)")
    for rect in rects { #expect(rect.cornerRadii.topLeft == rect.bounds.size.height / 2, "\(rect.bounds) r=\(rect.cornerRadii.topLeft)") }
    #expect(radii(w) == [12])
    let tall = try window { Button(action: {}) { Color.clear.frame(width: Pixels(60), height: Pixels(40)) }.buttonBorderShape(.capsule) }
    #expect(radii(tall) == [20], "half of a 40-point button: \(radii(tall))")
    let circle = try window { Button(action: {}) { Color.clear.frame(width: Pixels(30), height: Pixels(30)) }.buttonBorderShape(.circle) }
    #expect(radii(circle).count == 1 && radii(circle).first! >= 15, "a square button under .circle: \(radii(circle))")
}

/// BY-L: `.roundedRectangle` is the chrome's 5, `.roundedRectangle(radius:)` the radius, clamped to half the shorter side.
@Test @MainActor func aRoundedRectangleShapeUsesItsRadiusAndClampsToHalfTheHeight() throws {
    #expect(radii(try window { Button("Go") {}.buttonBorderShape(.roundedRectangle) }) == [5])
    #expect(radii(try window { Button("Go") {}.buttonBorderShape(.roundedRectangle(radius: 9)) }) == [9])
    #expect(radii(try window { Button("Go") {}.buttonBorderShape(.roundedRectangle(radius: 100)) }) == [12], "clamped")
    #expect(radii(try window { Button("Go") {}.buttonBorderShape(.roundedRectangle(radius: -4)) }) == [0], "a negative radius is 0")
}

/// BY-L: `.automatic` is today's drawing, byte for byte, in every control that reads it.
/// Mutation: treating `.automatic` as `.capsule` reddens every arm.
@Test @MainActor func anAutomaticBorderShapeDrawsTheSameSceneAsNoModifier() throws {
    @MainActor func pairs() -> [(String, () throws -> (TestWindow, TestWindow))] {
        func both<A: Element, B: Element>(_ a: @escaping @MainActor () -> A, _ b: @escaping @MainActor () -> B) -> () throws -> (TestWindow, TestWindow) {
            { (try window(a), try window(b)) }
        }
        return [
            ("bordered", both({ Button("Go") {} }, { Button("Go") {}.buttonBorderShape(.automatic) })),
            ("prominent", both({ Button("Go") {}.buttonStyle(.borderedProminent) },
                               { Button("Go") {}.buttonStyle(.borderedProminent).buttonBorderShape(.automatic) })),
            ("glass", both({ Button("Go") {}.buttonStyle(.glass) }, { Button("Go") {}.buttonStyle(.glass).buttonBorderShape(.automatic) })),
            ("glassProminent", both({ Button("Go") {}.buttonStyle(.glassProminent) },
                                    { Button("Go") {}.buttonStyle(.glassProminent).buttonBorderShape(.automatic) })),
            ("menu", both({ Menu("M") { Button("x") {} } }, { Menu("M") { Button("x") {} }.buttonBorderShape(.automatic) })),
            ("menu picker", both({ Picker("P", selection: .constant(1)) { Text("A").tag(0); Text("B").tag(1) } },
                                 { Picker("P", selection: .constant(1)) { Text("A").tag(0); Text("B").tag(1) }.buttonBorderShape(.automatic) })),
            ("segmented", both({ Picker("P", selection: .constant(1)) { Text("A").tag(0); Text("B").tag(1) }.pickerStyle(.segmented) },
                               { Picker("P", selection: .constant(1)) { Text("A").tag(0); Text("B").tag(1) }.pickerStyle(.segmented)
                                   .buttonBorderShape(.capsule).segmentedPickerShape(.automatic) })),
        ]
    }
    for (name, make) in pairs() {
        let (plain, automatic) = try make()
        #expect(signature(plain) == signature(automatic), "\(name)")
        #expect(!plain.scene.rects.isEmpty || !plain.scene.backdrops.isEmpty, "\(name) draws something")
    }
    #expect(radii(try window { Button("Go") {} }) == [5], "the bordered chrome's radius is unchanged")
}

/// BY-L: an environment write above a container reaches every button below it; the nearest writer wins.
/// Mutation: reading the shape from the button's own value (not the environment) reddens it.
@Test @MainActor func theShapeReachesButtonsThroughTheEnvironmentAndTheNearestWriterWins() throws {
    let w = try window {
        VStack(spacing: Pixels(10)) {
            Button("One") {}
            VStack { Button("Two") {} }.buttonBorderShape(.roundedRectangle(radius: 3))
        }.buttonBorderShape(.capsule)
    }
    #expect(radii(w) == [12, 3], "the outer capsule and the inner 3: \(radii(w))")
    let outer = chromeRects(w).filter { $0.cornerRadii.topLeft == 12 }
    let inner = chromeRects(w).filter { $0.cornerRadii.topLeft == 3 }
    try #require(!outer.isEmpty && !inner.isEmpty)
    #expect(outer[0].bounds.origin.y < inner[0].bounds.origin.y, "One (capsule) is above Two")
}

/// BY-L: `.plain`, `.borderless`, `.link` and a custom style draw no border of the button's own and ignore the shape.
/// Mutation: applying the shape before the look is checked reddens the plain arms (a radius appears on the label's box).
@Test @MainActor func stylesWithoutABorderIgnoreTheShape() throws {
    struct Custom: ButtonStyle {
        func makeBody(configuration: Configuration) -> some ElementGroup { configuration.label.padding(6).background(blue) }
    }
    @MainActor func check<S: PrimitiveButtonStyle>(_ name: String, _ style: S) throws {
        let none = try window { Button("Go") {}.buttonStyle(style) }
        let shaped = try window { Button("Go") {}.buttonStyle(style).buttonBorderShape(.capsule) }
        let scoped = try window { VStack { Button("Go") {} }.buttonStyle(style).buttonBorderShape(.capsule) }
        #expect(signature(none) == signature(shaped), "\(name)")
        #expect(!signature(scoped).contains("r=12.0/12.0"), "\(name)")
    }
    try check("plain", PlainButtonStyle())
    try check("borderless", BorderlessButtonStyle())
    try check("link", LinkButtonStyle())
    let none = try window { Button("Go") {}.buttonStyle(Custom()) }
    let shaped = try window { Button("Go") {}.buttonStyle(Custom()).buttonBorderShape(.capsule) }
    #expect(signature(none) == signature(shaped), "a custom style")
}

/// BY-L: the prominent chrome is filled with the accent and takes the shape; a caller's `.cornerRadius` outranks it.
@Test @MainActor func aProminentButtonFollowsTheShapeAndACallersRadiusOutranksIt() throws {
    let prominent = try window { Button("Go") {}.buttonStyle(.borderedProminent).buttonBorderShape(.capsule) }
    #expect(radii(prominent) == [12], "\(radii(prominent))")
    let own = try window { Button("Go") {}.cornerRadius(Pixels(3)).buttonBorderShape(.capsule) }
    #expect(radii(own) == [3], "the caller's 3 wins: \(radii(own))")
}

/// BY-L: a glass button is a capsule under `.automatic` and `.capsule` (the same record), a rounded rectangle under `.roundedRectangle`.
/// Mutation: ignoring the shape for glass reddens the rounded arms.
@Test @MainActor func aGlassButtonFollowsTheShape() throws {
    @MainActor func glassRadius(_ shape: ButtonBorderShape?, _ style: GlassButtonStyle = .glass) throws -> Float? {
        let w: TestWindow
        if let shape { w = try window { Button("Go") {}.buttonStyle(style).buttonBorderShape(shape) } }
        else { w = try window { Button("Go") {}.buttonStyle(style) } }
        return w.scene.backdrops.first?.cornerRadii.topLeft
    }
    #expect(try glassRadius(nil) == 12, "the default capsule")
    #expect(try glassRadius(.capsule) == 12)
    #expect(try glassRadius(.roundedRectangle) == 5)
    #expect(try glassRadius(.roundedRectangle(radius: 8)) == 8)
    let prominent = try window { Button("Go") {}.buttonStyle(.glassProminent).buttonBorderShape(.roundedRectangle(radius: 7)) }
    #expect(prominent.scene.backdrops.first?.cornerRadii.topLeft == 7)
}

/// BY-M: `Menu` and the menu `Picker` are bordered buttons and take the shape; the radio group ignores it.
@Test @MainActor func aMenuAndAMenuPickerFollowTheShape() throws {
    let menu = try window { Menu("More") { Button("x") {} }.buttonBorderShape(.capsule) }
    #expect(radii(menu) == [12], "Menu: \(radii(menu))")
    let picker = try window {
        Picker("P", selection: .constant(1)) { Text("A").tag(0); Text("B").tag(1) }.pickerStyle(.menu).buttonBorderShape(.capsule)
    }
    #expect(radii(picker) == [12], "menu Picker: \(radii(picker))")
    let radio = try window {
        Picker("P", selection: .constant(1)) { Text("A").tag(0); Text("B").tag(1) }.pickerStyle(.radioGroup).buttonBorderShape(.capsule)
    }
    let plainRadio = try window {
        Picker("P", selection: .constant(1)) { Text("A").tag(0); Text("B").tag(1) }.pickerStyle(.radioGroup)
    }
    #expect(signature(radio) == signature(plainRadio), "the radio group ignores it")
}

/// BY-L: the focus ring follows the shape (and the pressed wash, which shares the radius).
/// Mutation: setting the radius after the ring is resolved leaves the ring at 5.
@Test @MainActor func theFocusRingFollowsTheShape() throws {
    let w = try window { Button("Go") {}.buttonBorderShape(.capsule) }
    w.typeKey(.tab)
    redraw(w)
    let rings = w.scene.rects.filter { $0.borderWidths.top == 2 && $0.borderWidths.left == 2 }
    try #require(rings.count == 1, "one focus ring: \(rings.count)")
    #expect(rings[0].cornerRadii.topLeft == rings[0].bounds.size.height / 2, "\(rings[0].cornerRadii.topLeft)")
}

/// SD-E: a segmented picker ignores `.buttonBorderShape` and takes `.segmentedPickerShape`: 6 and 5 by default, 12 and 12 as a
/// capsule, 8 and 7 for a radius of 8; the selected segment keeps its hairline edge.
/// Mutation: reading `buttonBorderShape` for the segmented track reddens the first arm.
@Test @MainActor func aSegmentedPickerTakesItsOwnShapeAndIgnoresTheButtonBorderShape() throws {
    typealias Three = Picker<Int, Pair<Pair<TaggedElement<Text>, TaggedElement<Text>>, TaggedElement<Text>>>
    @MainActor func segmented<R: Element>(_ configure: @escaping @MainActor (Three) -> R) throws -> TestWindow {
        try window {
            configure(Picker("P", selection: .constant(1)) { Text("A").tag(0); Text("B").tag(1); Text("C").tag(2) }.pickerStyle(.segmented))
        }
    }
    let plain = try segmented { $0 }
    #expect(radii(plain) == [6, 5], "today's: \(radii(plain))")
    let ignoring = try segmented { $0.buttonBorderShape(.capsule) }
    #expect(signature(ignoring) == signature(plain), "buttonBorderShape does not reshape it")
    let capsule = try segmented { $0.segmentedPickerShape(.capsule) }
    #expect(radii(capsule) == [12], "\(radii(capsule))")
    let rounded = try segmented { $0.segmentedPickerShape(.roundedRectangle(radius: 8)) }
    #expect(radii(rounded) == [8, 7], "\(radii(rounded))")
    let edges = capsule.scene.rects.filter { $0.borderWidths.top == 1 && $0.cornerRadii.topLeft == 12 }
    #expect(edges.count == 1, "the selected segment keeps its 1-pixel edge: \(edges.count)")
    let scoped = try window {
        VStack {
            Picker("A", selection: .constant(1)) { Text("A").tag(0); Text("B").tag(1) }.pickerStyle(.segmented)
            Picker("B", selection: .constant(1)) { Text("A").tag(0); Text("B").tag(1) }.pickerStyle(.segmented)
                .segmentedPickerShape(.automatic)
        }.segmentedPickerShape(.capsule)
    }
    #expect(radii(scoped) == [12, 6, 5], "the inner writer wins: \(radii(scoped))")
}

@MainActor private func tabs() -> [TabStripItem<String>] {
    [TabStripItem(id: "a", title: "main.swift"), TabStripItem(id: "b", title: "other.swift")]
}

/// TBS-M: `.rectangle` is today's strip; a capsule or rounded shape draws the selected fill inset in its cell and no hairlines.
/// Mutation: ignoring the shape reddens every arm but the first.
@Test @MainActor func aTabStripDrawsItsSelectedTabInTheShape() throws {
    let plain = try window { VStack(spacing: Pixels(0)) { TabStrip(selection: .constant("a"), tabs: tabs()) } }
    let rectangle = try window { VStack(spacing: Pixels(0)) { TabStrip(selection: .constant("a"), tabs: tabs()).selectedTabShape(.rectangle) } }
    #expect(signature(plain) == signature(rectangle), "the default is unchanged")
    let theme = plain.window.theme
    func fills(_ w: TestWindow) -> [MUIRect] { w.scene.rects.filter { $0.bounds.size.height > 10 && $0.background.a > 0 && $0.bounds.size.width < 300 } }
    let flat = fills(plain)
    #expect(flat.contains { $0.bounds.size.height == 31 && $0.cornerRadii.topLeft == 0 }, "the default selected cell is a square 31 tall")
    let capsule = try window { VStack(spacing: Pixels(0)) { TabStrip(selection: .constant("a"), tabs: tabs()).selectedTabShape(.capsule) } }
    let pill = fills(capsule).filter { $0.cornerRadii.topLeft > 0 }
    let described = fills(capsule).map { "\($0.bounds) \($0.cornerRadii.topLeft)" }
    try #require(pill.count == 1, "one pill: \(described)")
    #expect(pill[0].bounds.size.height == 23 && pill[0].cornerRadii.topLeft == 11.5, "inset 4, half height: \(pill[0].bounds) \(pill[0].cornerRadii.topLeft)")
    let cell = flat.first { $0.bounds.size.height == 31 }
    #expect(pill[0].bounds.origin.x == (cell?.bounds.origin.x ?? -1) + 3, "inset 3 at the sides")
    #expect(capsule.scene.rects.filter { $0.bounds.size.width == 1 && $0.bounds.size.height == 31 }.isEmpty, "no tab hairlines")
    #expect(plain.scene.rects.contains { $0.bounds.size.width == 1 && $0.bounds.size.height == 31 }, "the default has them")
    let rounded = try window { VStack(spacing: Pixels(0)) { TabStrip(selection: .constant("a"), tabs: tabs()).selectedTabShape(.roundedRectangle(radius: 6)) } }
    #expect(fills(rounded).contains { $0.cornerRadii.topLeft == 6 }, "a 6-point rounded fill")
    _ = theme
}
