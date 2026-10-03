import Testing
import Metal
import MetalUICore
import MetalUILayout
import MetalUIScene
import MetalUIShaderTypes
@testable import MetalUI

// Colour and colour scheme, lane 1 — paint (spec
// `docs/superpowers/specs/2026-10-03-colour-design.md` §6.1, tests
// 1.15–1.20 and `CR-R`'s settle test; rulings `CR-E`, `CR-G`, `CR-H`,
// `CR-N`, `CR-U`). Headless: `Frame` + `render`, reading the finalized
// scene's rects, glyphs and raster texels.

private func px(_ v: Float) -> Pixels { Pixels(v) }

/// `Color.red`'s light half, `FF383C`, as sRGB components.
private let redLight = Rgba(r: 1, g: 56.0 / 255, b: 60.0 / 255, a: 1)

@MainActor private func gid(_ name: String) -> GlobalElementID {
    GlobalElementID.child(of: nil, at: 0, name: ElementID(name))
}

/// Renders `element` once into a fresh 200 × 200 frame.
@MainActor private func painted<E: Element>(_ element: E, theme: Theme = .light,
                                            mouse: Point<Pixels>? = nil,
                                            focused: GlobalElementID? = nil) -> Scene {
    var root = element
    let frame = Frame(contentSize: Size(width: px(200), height: px(200)), scaleFactor: 1,
                      theme: theme, timestamp: 0, mousePosition: mouse, focusedElement: focused)
    frame.render(&root)
    return frame.finalizedScene()
}

private func rgba(_ c: MUIHsla) -> Rgba { Hsla(h: c.h, s: c.s, l: c.l, a: c.a).toRgba() }

private func close(_ a: Rgba, _ b: Rgba, tolerance: Float = 1.0 / 255) -> Bool {
    abs(a.r - b.r) <= tolerance && abs(a.g - b.g) <= tolerance && abs(a.b - b.b) <= tolerance
        && abs(a.a - b.a) <= tolerance
}

/// Where an arm's colour lands in the scene.
private enum Landing { case fill, border, glyph, raster }

/// Whether `scene` carries `want` at `landing`: a rect's background, a rect's
/// border colour, a glyph's tint, or a fully covered texel of a raster image
/// (a path or a shadow; premultiplied RGBA, so an opaque texel is the colour).
private func carries(_ scene: Scene, _ want: Rgba, at landing: Landing) -> Bool {
    switch landing {
    case .fill: return scene.rects.contains { close(rgba($0.background), want) }
    case .border: return scene.rects.contains { $0.borderColor.a > 0 && close(rgba($0.borderColor), want) }
    case .glyph: return scene.glyphs.contains { close(rgba($0.color), want) }
    case .raster:
        for image in scene.images {
            let texture = scene.textures[Int(image.texture)]
            for i in stride(from: 0, to: texture.pixels.count, by: 4) where texture.pixels[i + 3] == 255 {
                let texel = Rgba(r: Float(texture.pixels[i]) / 255, g: Float(texture.pixels[i + 1]) / 255,
                                 b: Float(texture.pixels[i + 2]) / 255, a: 1)
                if close(texel, want, tolerance: 1.5 / 255) { return true }
            }
        }
        return false
    }
}

private func describe(_ scene: Scene) -> String {
    "rects=\(scene.rects.map { "bg\(rgba($0.background)) border\(rgba($0.borderColor))" }) "
        + "glyphs=\(scene.glyphs.prefix(2).map { rgba($0.color) }) images=\(scene.images.count)"
}

/// A 40 × 40 legacy box.
@MainActor private func legacyBox() -> Box<EmptyGroup> {
    Box().cssWidth(px(40)).cssHeight(px(40))
}

/// A 40 × 40 proposal leaf.
@MainActor private func leaf() -> ModifiedContent<Rectangle, LayoutModifier> {
    Rectangle(width: px(10), height: px(10)).frame(width: px(40), height: px(40))
}

private let centre = Point(x: px(100), y: px(100))
private let roundJoin = StrokeStyle(lineWidth: px(6), lineJoin: .round)

/// **1.15.** A literal colour reaches every colour-taking site, on both
/// vocabularies: each arm renders with `.red` (light) and reads `FF383C` where
/// that site emits its colour. Mutations, one at a time: in
/// `StyledElement.background(_ color:)`, `Text.foregroundColor(_ color:)` and
/// `Shape.fill(_ color:)` replace the forwarded colour with `.surface` —
/// exactly that arm reddens. **`CR-U`'s tinted-parent arm**: a `Text` under
/// `.foregroundStyle(.red)` with its own `.foregroundStyle(.secondary)` paints
/// `Color.secondary`'s resolved value, not a red (divergence 119).
@Test @MainActor func aLiteralColourReachesEveryColourTakingSite() {
    func arm<E: Element>(_ site: String, _ landing: Landing, mouse: Point<Pixels>? = nil,
                         focused: GlobalElementID? = nil, _ element: E,
                         sourceLocation: SourceLocation = #_sourceLocation) {
        let scene = painted(element, mouse: mouse, focused: focused)
        #expect(carries(scene, redLight, at: landing), "\(site): no FF383C at \(landing): \(describe(scene))",
                sourceLocation: sourceLocation)
    }
    func named<E: StyledElement>(_ e: E) -> E { var c = e; c.elementID = ElementID("site"); return c }

    // Box.swift — StyledElement, Decoration, BorderStyle.
    arm("StyledElement.background", .fill, legacyBox().background(.red))
    arm("StyledElement.hoverBackground", .fill, mouse: centre,
        named(legacyBox().background(.surface).hoverBackground(.red).onClick {}))
    arm("StyledElement.focusBackground", .fill, focused: gid("site"),
        named(legacyBox().background(.surface).focusBackground(.red).focusable()))
    arm("StyledElement.border(_:width:)", .border, legacyBox().border(.red, width: px(2)))
    arm("StyledElement.border(_:widths:)", .border, legacyBox().border(.red, widths: Edges(all: px(2))))
    arm("StyledElement.hoverBorder(_:width:)", .border, mouse: centre,
        named(legacyBox().hoverBorder(.red, width: px(2)).onClick {}))
    arm("StyledElement.hoverBorder(_:widths:)", .border, mouse: centre,
        named(legacyBox().hoverBorder(.red, widths: Edges(all: px(2))).onClick {}))
    arm("StyledElement.focusBorder(_:width:)", .border, focused: gid("site"),
        named(legacyBox().focusBorder(.red, width: px(2)).focusable()))
    arm("StyledElement.focusBorder(_:widths:)", .border, focused: gid("site"),
        named(legacyBox().focusBorder(.red, widths: Edges(all: px(2))).focusable()))
    arm("Decoration.init(background:)", .fill,
        Box(style: Style(), decoration: Decoration(background: .red)).cssWidth(px(40)).cssHeight(px(40)))
    arm("BorderStyle.init(_:width:)", .border,
        Box(style: Style(), decoration: Decoration(border: BorderStyle(.red, width: px(2))))
            .cssWidth(px(40)).cssHeight(px(40)))
    arm("BorderStyle.init(_:widths:)", .border,
        Box(style: Style(), decoration: Decoration(border: BorderStyle(.red, widths: Edges(all: px(2)))))
            .cssWidth(px(40)).cssHeight(px(40)))

    // NativeModifiedContent.swift, ClipShape.swift — the proposal vocabulary.
    arm("ProposalBase.background", .fill, leaf().background(.red))
    arm("ProposalBase.border", .border, leaf().border(.red, width: px(2)))
    arm("background(_:in:)", .fill, leaf().background(.red, in: Circle()))

    // Shadow.swift — both vocabularies.
    arm("shadow(color:) proposal", .raster,
        leaf().background(.surface).shadow(color: .red, radius: px(0), x: px(4), y: px(4)))
    arm("shadow(color:) legacy", .raster,
        Box().frame(width: px(40), height: px(40)).background(.surface)
            .shadow(color: .red, radius: px(0), x: px(4), y: px(4)))

    // ShapeView.swift — on Shape and on ShapeView.
    arm("Shape.fill", .fill, Circle().fill(.red).frame(width: px(40), height: px(40)))
    arm("Shape.fill(_:style:)", .raster,
        Circle().fill(.red, style: FillStyle(antialiased: false)).frame(width: px(40), height: px(40)))
    arm("Shape.stroke(_:lineWidth:)", .border, Circle().stroke(.red, lineWidth: px(4)).frame(width: px(40), height: px(40)))
    arm("Shape.stroke(_:style:)", .raster, Rectangle().stroke(.red, style: roundJoin).frame(width: px(40), height: px(40)))
    arm("Shape.strokeBorder(_:lineWidth:)", .border,
        Circle().strokeBorder(.red, lineWidth: px(4)).frame(width: px(40), height: px(40)))
    arm("Shape.strokeBorder(_:style:)", .raster,
        Rectangle().strokeBorder(.red, style: roundJoin).frame(width: px(40), height: px(40)))
    arm("ShapeView.fill", .fill, Circle().fill(.blue).fill(.red).frame(width: px(40), height: px(40)))
    arm("ShapeView.fill(_:style:)", .raster,
        Circle().fill(.blue).fill(.red, style: FillStyle(antialiased: false)).frame(width: px(40), height: px(40)))
    arm("ShapeView.stroke(_:lineWidth:)", .border,
        Circle().fill(.blue).stroke(.red, lineWidth: px(4)).frame(width: px(40), height: px(40)))
    arm("ShapeView.stroke(_:style:)", .raster,
        Rectangle().fill(.blue).stroke(.red, style: roundJoin).frame(width: px(40), height: px(40)))
    arm("ShapeView.strokeBorder(_:lineWidth:)", .border,
        Circle().fill(.blue).strokeBorder(.red, lineWidth: px(4)).frame(width: px(40), height: px(40)))
    arm("ShapeView.strokeBorder(_:style:)", .raster,
        Rectangle().fill(.blue).strokeBorder(.red, style: roundJoin).frame(width: px(40), height: px(40)))

    // TextModifiers.swift, Text.swift, ProposalText.swift, TextField.swift, TextEditor.swift.
    arm("ElementGroup.foregroundStyle", .glyph, HStack { HStack { ProposalText("Hi") }.foregroundStyle(.red) })
    arm("ElementGroup.foregroundColor", .glyph, HStack { HStack { ProposalText("Hi") }.foregroundColor(.red) })
    arm("ElementGroup.foregroundStyle over a legacy Text", .glyph, Box { Box { Text("Hi") }.foregroundStyle(.red) })
    arm("ElementGroup.foregroundStyle over a bare shape", .fill,
        HStack { HStack { Circle().frame(width: px(40), height: px(40)) }.foregroundStyle(.red) })
    arm("Text.foregroundColor", .glyph, Text("Hi").foregroundColor(.red))
    arm("Text.foregroundStyle", .glyph, Text("Hi").foregroundStyle(.red))
    arm("ProposalText.foregroundColor", .glyph, ProposalText("Hi").foregroundColor(.red))
    arm("ProposalText.foregroundStyle", .glyph, ProposalText("Hi").foregroundStyle(.red))
    arm("TextField.foregroundColor", .glyph,
        TextField("", text: .constant("Hi")).foregroundColor(.red).frame(width: px(120), height: px(30)))
    arm("TextEditor.foregroundColor", .glyph,
        TextEditor(text: .constant("Hi")).foregroundColor(.red).frame(width: px(120), height: px(60)))

    // NativeElements.swift, NativeTappable.swift.
    arm("Background.init", .fill, Background(.red) { Rectangle(width: px(40), height: px(40), color: .surface) })
    arm("Rectangle.init(width:height:color:)", .fill, Rectangle(width: px(40), height: px(40), color: .red))
    let tapScene = painted(Rectangle(width: px(40), height: px(40), color: .surface).onTap(hoverColor: .red) {},
                           mouse: centre)
    #expect(tapScene.rects.contains { close(rgba($0.background), Rgba(r: redLight.r, g: redLight.g, b: redLight.b, a: 0.22)) },
            "onTap(hoverColor:): no FF383C wash at 0.22: \(describe(tapScene))")

    // CR-U: the text's own `.secondary` wins over a red parent and is Color.secondary's value.
    let tinted = painted(HStack { HStack { ProposalText("Hi").foregroundStyle(.secondary) }.foregroundStyle(.red) })
    let text = Theme.light.textPrimary.toRgba()
    let secondary = Rgba(r: text.r, g: text.g, b: text.b, a: text.a * 0.588)
    #expect(carries(tinted, secondary, at: .glyph) && !carries(tinted, redLight, at: .glyph),
            "CR-U: .foregroundStyle(.secondary) under a red parent paints Color.secondary: \(describe(tinted))")
}

/// **1.16** (`CR-G`). `Color.red` as a view is one `FF383C` rect;
/// `Color.red.opacity(0.5)` is the VALUE method — one rect at alpha 0.5 and no
/// opacity layer, so the frame records as many element ids as a bare
/// `Color.red`. Mutation: `Color.opacity` `@_disfavoredOverload` (the view
/// modifier wins and adds a layer).
@Test @MainActor func aColorViewFillsWithItsColourAndOpacityIsTheValueMethod() throws {
    func recorded<E: Element>(_ element: E) -> (Scene, Int) {
        var root = element
        let frame = Frame(contentSize: Size(width: px(200), height: px(200)), scaleFactor: 1,
                          recordsElementBounds: true)
        frame.render(&root)
        return (frame.finalizedScene(), frame.elementBounds.count)
    }
    let (bare, bareIDs) = recorded(HStack { Color.red })
    try #require(bare.rects.count == 1, "one rect: \(describe(bare))")
    #expect(close(rgba(bare.rects[0].background), redLight), "FF383C: \(describe(bare))")
    let (half, halfIDs) = recorded(HStack { Color.red.opacity(0.5) })
    try #require(half.rects.count == 1, "one rect: \(describe(half))")
    #expect(close(rgba(half.rects[0].background), Rgba(r: redLight.r, g: redLight.g, b: redLight.b, a: 0.5)),
            "FF383C at 0.5: \(describe(half))")
    #expect(halfIDs == bareIDs, "no opacity layer: \(halfIDs) element ids against \(bareIDs)")
}

/// A leaf that records what `PaintPass.resolve(_:)` answers at its position.
@MainActor private final class ResolveLog { var surface: Hsla?; var red: Hsla? }

private struct ResolveProbe: ProposalElement {
    let log: ResolveLog

    mutating func requestProposalLayout(_ id: GlobalElementID,
                                        pass: inout LayoutPass) -> (ProposalNodeID, Void) {
        (pass.requestNativeLeaf { _ in LayoutMeasurement(size: SizeD(width: 10, height: 10)) }, ())
    }

    func prepaint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Void,
                  pass: inout PrepaintPass) {}

    func paint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Void,
               prepaint: inout Void, pass: inout PaintPass) {
        log.surface = pass.resolve(.surface)
        log.red = pass.resolve(.red)
    }
}

/// **1.17** (`CR-H` item 2). `PaintPass.resolve(_:)` resolves against the
/// element's scoped theme and scheme: `.surface` follows a `.theme(.dark)`
/// scope, `.red` an `.environment(\.colorScheme, .dark)` scope. Mutation:
/// `PaintPass.resolve` uses the root theme.
@Test @MainActor func paintPassResolveUsesTheElementsScopedThemeAndScheme() {
    let root = ResolveLog(), themed = ResolveLog(), schemed = ResolveLog()
    _ = painted(HStack {
        ResolveProbe(log: root)
        ResolveProbe(log: themed).theme(.dark)
        ResolveProbe(log: schemed).environment(\.colorScheme, .dark)
    })
    let darkRed = Rgba(r: 1, g: 0x42 / 255.0, b: 0x45 / 255.0, a: 1)
    #expect(root.surface == Theme.light.surface && root.red.map { close($0.toRgba(), redLight) } == true,
            "the root: light surface, light red; got \(String(describing: root.surface)), \(String(describing: root.red))")
    #expect(themed.surface == Theme.dark.surface, "a .theme(.dark) scope: dark surface, got \(String(describing: themed.surface))")
    #expect(schemed.red.map { close($0.toRgba(), darkRed) } == true,
            "a dark colorScheme scope: dark red, got \(String(describing: schemed.red))")
}

/// **1.18** (`CR-H` item 3). A scheme change moves what an unchanged dynamic
/// colour resolves to without moving the declared `Color`, so it never starts
/// a fade: under a transaction the next frame reads the dark half at once and
/// nothing is live. Mutation: key the baseline on the resolved colour.
@Test @MainActor func aSchemeChangeNeverStartsAFadeOnADynamicColour() throws {
    let a = Color(red: 0.1, green: 0.2, blue: 0.3), b = Color(red: 0.9, green: 0.8, blue: 0.7)
    let table = StateTable()
    func frame(_ scheme: ColorScheme, _ t: Double, _ animation: Animation?) -> Frame {
        var root = Box { legacyBox().background(Color(light: a, dark: b)).environment(\.colorScheme, scheme) }
        let f = Frame(contentSize: Size(width: px(200), height: px(200)), scaleFactor: 1, stateTable: table,
                      timestamp: t, transaction: animation)
        f.render(&root)
        return f
    }
    let first = frame(.light, 0, nil)
    try #require(first.scene.rects.first.map { close(rgba($0.background), Rgba(r: 0.1, g: 0.2, b: 0.3)) } == true,
                 "set up: the light half")
    let second = frame(.dark, 0.1, .linear(duration: 1))
    #expect(second.scene.rects.first.map { close(rgba($0.background), Rgba(r: 0.9, g: 0.8, b: 0.7)) } == true,
            "the dark half at once: \(String(describing: second.scene.rects.first.map { rgba($0.background) }))")
    #expect(!second.hasActiveAnimations, "a scheme change starts no fade")
}

/// **1.19** (`CR-H` item 3). A fade from a token to a literal re-resolves the
/// token end every frame: swapping `Theme.light` → `Theme.dark` half-way moves
/// the midpoint by the token end only. Mutation: `ColorEnd.declared` resolved
/// once at start (frozen).
@Test @MainActor func aFadeFromATokenToALiteralReResolvesTheTokenEnd() throws {
    let table = StateTable()
    func frame(_ color: Color, _ t: Double, _ theme: Theme, _ animation: Animation?) -> Rgba? {
        var root = legacyBox().background(color)
        let f = Frame(contentSize: Size(width: px(200), height: px(200)), scaleFactor: 1, stateTable: table,
                      theme: theme, timestamp: t, transaction: animation)
        f.render(&root)
        return f.scene.rects.first.map { rgba($0.background) }
    }
    _ = frame(.surface, 0, .light, nil)
    _ = frame(.red, 0, .light, .linear(duration: 1))
    func lerp(_ x: Rgba, _ y: Rgba) -> Rgba {
        Rgba(r: (x.r + y.r) / 2, g: (x.g + y.g) / 2, b: (x.b + y.b) / 2, a: (x.a + y.a) / 2)
    }
    let lightMid = try #require(frame(.red, 0.5, .light, nil))
    #expect(close(lightMid, lerp(Theme.light.surface.toRgba(), redLight), tolerance: 2.0 / 255),
            "half-way under Theme.light: \(lightMid)")
    let darkMid = try #require(frame(.red, 0.5, .dark, nil))
    #expect(close(darkMid, lerp(Theme.dark.surface.toRgba(), redLight), tolerance: 2.0 / 255),
            "half-way under Theme.dark the token end moved, the literal end did not: \(darkMid)")
}

/// A key whose override reaches itself.
private struct CycleKey: ThemeColorKey { static let defaultValue = Color.red }

/// **1.20** (`CR-N` item 5; exit test). A palette colour that reaches itself
/// again traps naming the key. The control: the same resolution with no
/// cycle exits normally. Mutation: return `.clear` instead of trapping.
@Test func aPaletteCycleTrapsNamingTheKey() async {
    let trapped = await #expect(processExitsWith: .failure, observing: [\.standardErrorContent]) {
        var theme = Theme.light
        theme[CycleKey.self] = Color(CycleKey.self)
        _ = Color(CycleKey.self).resolved(theme: theme, scheme: .light)
    }
    let message = String(decoding: trapped?.standardErrorContent ?? [], as: UTF8.self)
    #expect(message.contains("ThemeColorKey cycle through") && message.contains("CycleKey"),
            "aborted, but not naming the key:\n\(message)")
    await #expect(processExitsWith: .success) {
        var theme = Theme.light
        theme[CycleKey.self] = Color.blue
        _ = Color(CycleKey.self).resolved(theme: theme, scheme: .light)
    }
}

@MainActor @Observable private final class NaNModel { var flips = 0 }

/// **`CR-R` item 2.** A NaN literal is stored as 0, so the declared colour
/// equals itself frame to frame: a box painting it, rebuilt once under a
/// transaction, settles and lets the display link pause. Mutation: drop the
/// canonicalisation.
@Test @MainActor func aNaNColourSettlesAndLetsTheDisplayLinkPause() throws {
    let model = NaNModel()
    let (window, platform) = try makeFakeWindowOnDefaultDevice(size: 200, startsDisplayLink: true) {
        let flips = model.flips
        return legacyBox().background(flips >= 0 ? Color(red: .nan, green: 0, blue: 0) : .surface)
    }
    platform.simulateTick(timestamp: 100)
    platform.simulateTick(timestamp: 100.1)
    try #require(platform.pauseCalls.last == true, "set up: a settled window pauses")
    withAnimation(.linear(duration: 1)) { model.flips += 1 }
    platform.simulateTick(timestamp: 100.2)
    platform.simulateTick(timestamp: 100.3)
    platform.simulateTick(timestamp: 100.4)
    #expect(platform.pauseCalls.last == true, "the NaN colour settled and the display link paused")
    #expect(!window.hasActiveAnimations, "nothing live")
}
