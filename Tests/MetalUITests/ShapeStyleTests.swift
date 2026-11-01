import Testing
import MetalUICore
import MetalUIPlatform
@testable import MetalUI

// Round 3 item R3-9 (`SS-A`…): `ShapeStyle` as a protocol, `AnyShapeStyle`, `TintShapeStyle` and `.tint(_:)`.
// Colours are read from the scene's rects and compared to the colour resolved through the one function paint
// uses, never to a literal copy of the expected answer.

private let ssTint = Color(red: 0.8, green: 0.2, blue: 0.6)
private let ssTintB = Color(red: 0.1, green: 0.7, blue: 0.3)

private func ssSame(_ a: MUIHsla, _ b: Hsla) -> Bool { rtSame(a, b) }

/// The number of rects in `frame`'s scene whose fill is `color` as the frame resolves it.
@MainActor
private func ssFills(_ frame: Frame, _ color: Color) -> Int {
    let want = frame.resolve(color)
    return frame.finalizedScene().rects.filter { ssSame($0.background, want) }.count
}

// MARK: - The tint reaches every control (SS-D)

/// A control in a state that paints its accent, with an optional tint written outside it.
@MainActor
private enum TintControl: CaseIterable {
    case borderedProminent, checkbox, switchToggle, slider, progressBar, radioPicker

    func root(tint: Color?) -> any Element {
        switch self {
        case .borderedProminent: scoped(Button("Go") {}.buttonStyle(.borderedProminent), tint)
        case .checkbox: scoped(Toggle("T", isOn: .constant(true)).toggleStyle(.checkbox), tint)
        case .switchToggle: scoped(Toggle("T", isOn: .constant(true)).toggleStyle(.switch), tint)
        case .slider: scoped(Slider(value: .constant(0.5)), tint)
        case .progressBar: scoped(ProgressView(value: 0.5), tint)
        case .radioPicker:
            scoped(Picker("S", selection: .constant(1)) { Text("A").tag(0); Text("B").tag(1) }.pickerStyle(.radioGroup), tint)
        }
    }

    private func scoped<G: ElementGroup>(_ group: G, _ tint: Color?) -> any Element {
        tint.map { color in controlRoot { group.tint(color) } } ?? controlRoot { group }
    }
}

/// `.tint(_:)` above a built-in control paints its accent in the tint; with no tint the theme's accent token
/// paints exactly as before. Mutations: `controlAccent` ignoring `environment.tint` (reddens every arm that reads
/// it: borderedProminent, checkbox, switch, slider, progress bar, radio picker).
@Test @MainActor func aTintReachesEveryControlsAccent() throws {
    for control in TintControl.allCases {
        let tinted = try controlRender(control.root(tint: ssTint))
        let plain = try controlRender(control.root(tint: nil))
        #expect(ssFills(tinted, ssTint) >= 1, "\(control): the tint is painted")
        #expect(ssFills(tinted, Color(.accent)) == 0, "\(control): no accent left under a tint")
        #expect(ssFills(plain, Color(.accent)) >= 1, "\(control): untinted keeps the theme accent")
        #expect(ssFills(plain, ssTint) == 0, "\(control): untinted paints no tint")
    }
}

/// The nearest `.tint(_:)` wins, and `.tint(nil)` removes an outer one. Mutation: `tint(_:)` writing only when
/// the new value is non-nil (reddens the nil arm).
@Test @MainActor func theNearestTintWinsAndNilRemovesAnOuterOne() throws {
    let inner = try controlRender(controlRoot { Column { Slider(value: .constant(0.5)).tint(ssTintB) }.tint(ssTint) })
    #expect(ssFills(inner, ssTintB) >= 1 && ssFills(inner, ssTint) == 0, "the inner tint wins")
    let cleared = try controlRender(controlRoot { Column { Slider(value: .constant(0.5)).tint(nil) }.tint(ssTint) })
    #expect(ssFills(cleared, Color(.accent)) >= 1 && ssFills(cleared, ssTint) == 0, "nil removes the outer tint")
}

/// An inactive window paints `.separator`, not the tint (`IX-H`'s rule survives). Mutation: `controlAccent`
/// testing the tint before the active state.
@Test @MainActor func aTintDoesNotRevealAnInactiveWindowsAccent() throws {
    var env = EnvironmentValues()
    env.tint = ssTint
    env.controlActiveState = .inactive
    #expect(controlAccent(env) == Color(.separator))
    env.controlActiveState = .key
    #expect(controlAccent(env) == ssTint)
    env.tint = nil
    #expect(controlAccent(env) == Color(.accent), "no tint: the token itself, so every pixel stays")
}

// MARK: - Color.accentColor and the tint style

/// `Color.accentColor` resolves to the tint in the scope; `Color.accent` (the token) never does; `.tint(.accentColor)`
/// is the theme accent. Mutation: `.accentColor` provider resolving `theme[.accent]` only.
@Test @MainActor func accentColorFollowsTheTintButTheAccentTokenDoesNot() throws {
    var env = EnvironmentValues()
    let accent = Theme.light[.accent].toRgba()
    func same(_ r: Color.Resolved, _ r2: Rgba) -> Bool {
        abs(r.red - r2.r) < 1e-4 && abs(r.green - r2.g) < 1e-4 && abs(r.blue - r2.b) < 1e-4
    }
    #expect(same(Color.accentColor.resolve(in: env), accent), "no tint: the theme accent")
    env.tint = ssTint
    let tinted = ssTint.resolve(in: EnvironmentValues())
    #expect(Color.accentColor.resolve(in: env) == tinted, "tint set: the tint")
    #expect(same(Color.accent.resolve(in: env), accent), "the token ignores the tint")
    env.tint = .accentColor
    #expect(same(Color.accentColor.resolve(in: env), accent), "a tint of accentColor is the theme accent, no loop")
}

/// `fill(.tint)`, `foregroundStyle(.tint)` and `background(.tint)` paint the tint of the scope they sit in.
/// Mutation: `TintShapeStyle.storage` a fixed colour.
@Test @MainActor func theTintStyleFillsAndColoursTextInTheScopesTint() throws {
    let fill = rtFrame(rtTopLeft(Row {
        Rectangle().fill(.tint).frame(width: Pixels(40), height: Pixels(20))
    }.tint(ssTint)))
    #expect(ssFills(fill, ssTint) == 1, "fill(.tint)")
    let back = rtFrame(rtTopLeft(Row { Rectangle().fill(.clear).frame(width: Pixels(40), height: Pixels(20)) }
        .background(TintShapeStyle()).tint(ssTint)))
    #expect(ssFills(back, ssTint) >= 1, "background(.tint)")
    let scoped = rtFrame(rtTopLeft(Column { Text("ab") }.foregroundStyle(.tint).tint(ssTint)))
    let glyphs = scoped.scene.glyphs
    try #require(glyphs.count == 2)
    #expect(glyphs.allSatisfy { ssSame($0.color, scoped.resolve(ssTint)) }, "text takes the tint through the environment")
}

/// A link run draws in the tint, not the theme accent. Mutation: `.accentColor` back to the token.
@Test @MainActor func aLinkRunDrawsInTheTint() throws {
    let text = Text(content: .runs([TextRunRequest(string: "ab", link: "https://example.com")]))
    let frame = rtFrame(rtTopLeft(Row { text }.tint(ssTint)))
    let glyphs = frame.scene.glyphs
    try #require(!glyphs.isEmpty)
    #expect(glyphs.allSatisfy { ssSame($0.color, frame.resolve(ssTint)) }, "the link takes the tint")
}

// MARK: - Styles through some ShapeStyle (SS-A, SS-C)

@MainActor private func ssFilled(_ style: some ShapeStyle) -> some Element {
    Row { Rectangle().fill(style).frame(width: Pixels(60), height: Pixels(30)) }
}

private struct SSBrand: ShapeStyle {
    func resolve(in environment: EnvironmentValues) -> some ShapeStyle {
        environment.colorScheme == .dark ? Color(red: 0.9, green: 0.9, blue: 0.1) : Color(red: 0.1, green: 0.1, blue: 0.9)
    }
}

private struct SSNested: ShapeStyle {
    func resolve(in environment: EnvironmentValues) -> some ShapeStyle { SSBrand() }
}

private struct SSLoop: ShapeStyle {
    func resolve(in environment: EnvironmentValues) -> SSLoop { self }
}

/// A colour, gradient and material through `some ShapeStyle` paint the same scene as the concrete overload.
/// Mutations: the generic `fill` ignoring the style's storage case (reddens gradient and material arms); `LinearGradient`
/// resolving to a `.color` storage.
@Test @MainActor func aColourGradientAndMaterialPaintThroughSomeShapeStyleAsTheConcreteOverloadsDo() throws {
    let gradient = LinearGradient(colors: [.red, .blue], startPoint: .leading, endPoint: .trailing)
    let radial = RadialGradient(colors: [.red, .blue], center: .center, startRadius: Pixels(0), endRadius: Pixels(20))
    @MainActor func kinds(_ element: some Element) -> [PrimitiveKind] { rtFrame(element).finalizedScene().drawList.map(\.kind) }
    @MainActor func shape(_ fill: (Rectangle) -> ShapeView<Rectangle>) -> some Element {
        rtTopLeft(Row { fill(Rectangle()).frame(width: Pixels(60), height: Pixels(30)) })
    }
    let colourGeneric = kinds(rtTopLeft(ssFilled(Color.red)))
    #expect(colourGeneric == kinds(shape { $0.fill(Color.red) }) && !colourGeneric.isEmpty)
    let gradientGeneric = kinds(rtTopLeft(ssFilled(gradient)))
    #expect(gradientGeneric == kinds(shape { $0.fill(gradient) }) && gradientGeneric.contains(.image), "\(gradientGeneric)")
    let radialGeneric = kinds(rtTopLeft(ssFilled(radial)))
    #expect(radialGeneric == kinds(shape { $0.fill(radial) }) && radialGeneric.contains(.image), "\(radialGeneric)")
    let materialGeneric = kinds(rtTopLeft(ssFilled(Material.regularMaterial)))
    #expect(materialGeneric == kinds(shape { $0.fill(Material.regularMaterial) }), "\(materialGeneric)")
    #expect(materialGeneric.contains(.backdrop), "\(materialGeneric)")
    // A colour through the generic arm is the same pixels as the concrete one.
    let a = rtFrame(rtTopLeft(ssFilled(Color.red))), b = rtFrame(shape { $0.fill(Color.red) })
    #expect(ssFills(a, .red) == 1 && ssFills(b, .red) == 1)
}

/// Strokes, inside strokes and `background(_:in:)` take any style; a gradient strokes as an image, a colour as a
/// band, a material in its flat tint. Mutation: `paintStyleStroke`'s `.gradient` arm drawing nothing.
@Test @MainActor func strokesAndBackgroundsTakeAnyShapeStyle() throws {
    let gradient = LinearGradient(colors: [.red, .blue], startPoint: .leading, endPoint: .trailing)
    func frame(_ build: () -> some Element) -> Frame { rtFrame(rtTopLeft(Row { build() })) }
    let colour = frame { Rectangle().stroke(AnyShapeStyle(Color.green), lineWidth: Pixels(3)).frame(width: Pixels(40), height: Pixels(20)) }
    #expect(colour.finalizedScene().rects.contains { ssSame($0.borderColor, colour.resolve(.green)) }, "a colour strokes as a band")
    let inside = frame { Rectangle().strokeBorder(AnyShapeStyle(Color.green), lineWidth: Pixels(3)).frame(width: Pixels(40), height: Pixels(20)) }
    #expect(inside.finalizedScene().rects.contains { ssSame($0.borderColor, inside.resolve(.green)) }, "inside stroke")
    let gradientStroke = frame { Rectangle().stroke(AnyShapeStyle(gradient), lineWidth: Pixels(3)).frame(width: Pixels(40), height: Pixels(20)) }
    #expect(gradientStroke.finalizedScene().drawList.contains { $0.kind == .image }, "a gradient strokes as an image")
    let gradientInside = frame { Rectangle().strokeBorder(AnyShapeStyle(gradient), lineWidth: Pixels(3)).frame(width: Pixels(40), height: Pixels(20)) }
    #expect(gradientInside.finalizedScene().drawList.contains { $0.kind == .image }, "an inside gradient stroke")
    let material = frame { Rectangle().stroke(AnyShapeStyle(Material.thinMaterial), lineWidth: Pixels(3)).frame(width: Pixels(40), height: Pixels(20)) }
    #expect(material.finalizedScene().rects.contains { ssSame($0.borderColor, material.resolve(Material.thinMaterial.color)) },
            "a material strokes in its flat tint")
    let behind = frame { Row { Rectangle().fill(.clear).frame(width: Pixels(10), height: Pixels(10)) }
        .background(AnyShapeStyle(Color.orange), in: Rectangle()) }
    #expect(ssFills(behind, .orange) >= 1, "background(_:in:) takes a style")
}

/// `AnyShapeStyle` round trips: wrapping is idempotent, equal built-ins are equal, a custom style resolves at paint, an
/// `Equatable` custom value equals itself and a non-`Equatable` one equals nothing. Mutations: `init` wrapping an
/// `AnyShapeStyle` in a custom box (reddens the idempotence arm); `CustomBox.equals` always true (reddens the last).
@Test @MainActor func anAnyShapeStyleRoundTripsAndComparesByWhatItWraps() throws {
    #expect(AnyShapeStyle(Color.red) == AnyShapeStyle(Color.red))
    #expect(AnyShapeStyle(Color.red) != AnyShapeStyle(Color.blue))
    #expect(AnyShapeStyle(AnyShapeStyle(Color.red)) == AnyShapeStyle(Color.red), "wrapping twice is wrapping once")
    #expect(AnyShapeStyle(Material.thinMaterial) != AnyShapeStyle(Material.thickMaterial))
    let g = LinearGradient(colors: [.red, .blue], startPoint: .top, endPoint: .bottom)
    #expect(AnyShapeStyle(g) == AnyShapeStyle(g) && AnyShapeStyle(g) != AnyShapeStyle(Color.red))
    let env = EnvironmentValues()
    let resolved = AnyShapeStyle(Color.red).resolve(in: env)
    #expect(resolved == ResolvedShapeStyle(.color(.red)), "the built-in's storage survives erasure")
    // Custom: a composition erased keeps resolving against the environment.
    var dark = EnvironmentValues(); dark.colorScheme = .dark
    #expect(AnyShapeStyle(SSBrand()).resolve(in: env) != AnyShapeStyle(SSBrand()).resolve(in: dark), "resolves per scheme")
    #expect(AnyShapeStyle(SSNested()).resolve(in: env) == AnyShapeStyle(SSBrand()).resolve(in: env), "compositions nest")
    struct Same: ShapeStyle, Equatable { func resolve(in environment: EnvironmentValues) -> some ShapeStyle { Color.red } }
    #expect(AnyShapeStyle(Same()) == AnyShapeStyle(Same()), "an Equatable custom value equals its twin")
    #expect(AnyShapeStyle(SSBrand()) != AnyShapeStyle(SSBrand()), "a non-Equatable custom style equals nothing but itself")
    let one = AnyShapeStyle(SSBrand())
    #expect(one == one, "the same box equals itself")
}

/// A custom composition paints against the environment where it sits: dark scope, dark colour. Mutation:
/// `shapeStyleStorage` resolving in a bare environment.
@Test @MainActor func aCustomStyleResolvesAgainstTheEnvironmentItIsPaintedIn() throws {
    let light = rtFrame(rtTopLeft(ssFilled(SSBrand())))
    let dark = rtFrame(rtTopLeft(ssFilled(SSBrand()).environment(\.colorScheme, .dark)))
    #expect(ssFills(light, Color(red: 0.1, green: 0.1, blue: 0.9)) == 1, "light")
    #expect(ssFills(dark, Color(red: 0.9, green: 0.9, blue: 0.1)) == 1, "dark")
    let foreground = rtFrame(rtTopLeft(Column { Text("ab") }.foregroundStyle(SSBrand()).environment(\.colorScheme, .dark)))
    #expect(foreground.scene.glyphs.allSatisfy { ssSame($0.color, foreground.resolve(Color(red: 0.9, green: 0.9, blue: 0.1))) },
            "foregroundStyle(custom) resolves in the scope it is written in")
}

/// `foregroundStyle` of a gradient paints its first stop (divergence 975); a style that never reaches a primitive traps
/// rather than loops (not asserted: an exit test is not offered here), so only the first-stop rule is pinned.
@Test @MainActor func aGradientForegroundStylePaintsItsFirstStop() throws {
    let g = LinearGradient(colors: [.green, .blue], startPoint: .top, endPoint: .bottom)
    let frame = rtFrame(rtTopLeft(Column { Text("ab") }.foregroundStyle(g)))
    #expect(frame.scene.glyphs.allSatisfy { ssSame($0.color, frame.resolve(.green)) })
    #expect(AnyShapeStyle(g).resolve(in: EnvironmentValues()) == ResolvedShapeStyle(.gradient(.linear(g))))
    #expect(ShapeStyleStorage.gradient(.linear(g)).representativeColor == .green)
}

/// A box border and a box background take a style. Mutation: `StyledElement.background<S>` dropping the gradient case.
@Test @MainActor func aBoxTakesAStyleForItsBackgroundAndBorder() throws {
    let tinted = rtFrame(rtTopLeft(Row {
        Box(decoration: Decoration(), content: EmptyGroup()).background(.tint).border(TintShapeStyle(), width: Pixels(2))
            .cssWidth(Pixels(30)).cssHeight(Pixels(30))
    }.tint(ssTint)))
    let scene = tinted.finalizedScene()
    #expect(scene.rects.contains { ssSame($0.background, tinted.resolve(ssTint)) }, "background(.tint)")
    #expect(scene.rects.contains { ssSame($0.borderColor, tinted.resolve(ssTint)) }, "border(.tint)")
    let g = LinearGradient(colors: [.red, .blue], startPoint: .top, endPoint: .bottom)
    let gradient = rtFrame(rtTopLeft(Row { Box(decoration: Decoration(), content: EmptyGroup()).background(AnyShapeStyle(g)).cssWidth(Pixels(30)).cssHeight(Pixels(30)) }))
    #expect(gradient.finalizedScene().drawList.contains { $0.kind == .image }, "a gradient through AnyShapeStyle")
}

// MARK: - The environment field

/// `tint` is an environment field: it is written by `.tint(_:)`, read by `controlAccent`, and named in the
/// retained fingerprint. Mutation: `retainedFingerprint` dropping `tint` (reddens
/// `RetainedShapeStyleTests`' tint arms and the fingerprint-field test).
@Test @MainActor func theTintIsPartOfTheEnvironmentFingerprint() {
    var a = EnvironmentValues(), b = EnvironmentValues()
    #expect(a.retainedFingerprint == b.retainedFingerprint)
    b.tint = ssTint
    #expect(a.retainedFingerprint != b.retainedFingerprint)
    #expect(b.retainedFingerprint.differences(from: a.retainedFingerprint) == ["tint"])
    a.tint = ssTint
    #expect(a.retainedFingerprint == b.retainedFingerprint, "an equal tint is an equal fingerprint")
}
