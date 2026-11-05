import Testing
import MetalUICore
import MetalUILayout
import MetalUIScene
@testable import MetalUI

// Round 4 item R4-4 PR A (`HY-`, divergence 119 retired): a hierarchical level is a factor of the style a view
// inherits. Every alpha literal is a probe reading (`docs/probes/swiftui-hierarchical-paint.swift`, arm ids in
// each name), never a value computed by the code under test. A typecheck guard sees only that a spelling
// compiles (`HierarchicalStyleCompileGuards`); WHICH overload bound is pinned here, because `.secondary` binds
// the grey `Color.secondary` (alpha .588 of the theme's text) if the `@_disfavoredOverload` on the `Color`
// statics is dropped, and the level (alpha .5 of a red parent) otherwise.

private func px(_ v: Float) -> Pixels { Pixels(v) }

/// `Color.red`'s halves, `FF383C` light and `FF4245` dark.
private let redLight = (r: Float(1), g: Float(56) / 255, b: Float(60) / 255)
private let redDark = (r: Float(1), g: Float(0x42) / 255, b: Float(0x45) / 255)

/// The probe's factors over a parent, `RL2`...`RL5` and `RD2`...`RD5`.
private let overParent: [Float] = [1, 0.5, 0.25, 0.18, 0.18]

@MainActor private func painted<E: Element>(_ element: E, dark: Bool = false) -> Scene {
    var root = element
    let frame = Frame(contentSize: Size(width: px(200), height: px(200)), scaleFactor: 1,
                      theme: dark ? .dark : .light, timestamp: 0, mousePosition: nil, focusedElement: nil)
    frame.render(&root)
    return frame.finalizedScene()
}

private func rgba(_ c: MUIHsla) -> Rgba { Hsla(h: c.h, s: c.s, l: c.l, a: c.a).toRgba() }

private enum Landing { case fill, border, glyph }

/// Every colour the scene lands at `landing` (the first glyph's, for text).
private func landed(_ scene: Scene, _ landing: Landing) -> [Rgba] {
    switch landing {
    case .fill: return scene.rects.map { rgba($0.background) }.filter { $0.a > 0 }
    case .border: return scene.rects.map { rgba($0.borderColor) }.filter { $0.a > 0 }
    case .glyph: return scene.glyphs.map { rgba($0.color) }
    }
}

private func has(_ scene: Scene, _ landing: Landing, _ rgb: (r: Float, g: Float, b: Float), alpha: Float) -> Bool {
    landed(scene, landing).contains {
        abs($0.r - rgb.r) <= 2.0 / 255 && abs($0.g - rgb.g) <= 2.0 / 255 && abs($0.b - rgb.b) <= 2.0 / 255
            && abs($0.a - alpha) <= 1.5 / 255
    }
}

private func describe(_ scene: Scene, _ landing: Landing) -> String { "\(landed(scene, landing))" }

@MainActor private func leaf() -> ModifiedContent<Rectangle, LayoutModifier> {
    Rectangle(width: px(10), height: px(10)).frame(width: px(40), height: px(40))
}

/// Every sink under a red parent at one level. `build` lays `site` out below `HStack { ... }.foregroundStyle(.red)`.
@MainActor private func eachSink(_ expect: (String, Landing, Scene) -> Void,
                                 level: HierarchicalShapeStyle, dark: Bool) {
    func scene<E: ElementGroup>(_ e: E) -> Scene {
        painted(HStack { e }.foregroundStyle(.red).environment(\.colorScheme, dark ? .dark : .light), dark: dark)
    }
    expect("Shape.fill", .fill, scene(Circle().fill(level).frame(width: px(40), height: px(40))))
    expect("ShapeView.fill", .fill, scene(Circle().fill(.blue).fill(level).frame(width: px(40), height: px(40))))
    expect("Shape.stroke", .border, scene(Circle().stroke(level, lineWidth: px(4)).frame(width: px(40), height: px(40))))
    expect("Shape.strokeBorder", .border,
           scene(Circle().strokeBorder(level, lineWidth: px(4)).frame(width: px(40), height: px(40))))
    expect("ProposalBase.background", .fill, scene(leaf().background(level)))
    expect("ProposalBase.border", .border, scene(leaf().border(level, width: px(2))))
    expect("background(_:in:)", .fill, scene(leaf().background(level, in: Circle())))
    expect("Box.background", .fill, scene(Box().cssWidth(px(40)).cssHeight(px(40)).background(level)))
    expect("Box.border", .border, scene(Box().cssWidth(px(40)).cssHeight(px(40)).border(level, width: px(2))))
    expect("bare shape (foregroundStyle)", .fill,
           scene(Circle().foregroundStyle(level).frame(width: px(40), height: px(40))))
    expect("ElementGroup.foregroundStyle over ProposalText", .glyph,
           scene(HStack { ProposalText("Hi") }.foregroundStyle(level)))
    expect("Text.foregroundStyle", .glyph, scene(Text("Hi").foregroundStyle(level)))
    expect("ProposalText.foregroundStyle", .glyph, scene(ProposalText("Hi").foregroundStyle(level)))
    expect("AnyShapeStyle fill", .fill,
           scene(Circle().fill(AnyShapeStyle(level)).frame(width: px(40), height: px(40))))
}

/// **RL2 (RL1…RL5), RD2 (RD1…RD5), S1…S6, T2, T3, T6** — each level of a red parent at 1, .5, .25, .18, .18 of its alpha,
/// in both schemes, at every sink. Mutations: `Color.secondary`/`primary` lose `@_disfavoredOverload` (the
/// level binds the grey: alpha .588 of the text colour, no red); a factor changed (mutation 4/5);
/// `Color.resolved`'s `.hierarchical` case ignoring `inherited` (mutations 1/3/6).
@Test @MainActor func aLevelIsAFactorOfTheParentAtEverySink() {
    let levels: [HierarchicalShapeStyle] = [.primary, .secondary, .tertiary, .quaternary, .quinary]
    for dark in [false, true] {
        let red = dark ? redDark : redLight
        for (i, level) in levels.enumerated() {
            eachSink({ site, landing, scene in
                #expect(has(scene, landing, red, alpha: overParent[i]),
                        "\(site), level \(i + 1), \(dark ? "dark" : "light"): wanted red at \(overParent[i]), got \(describe(scene, landing))")
            }, level: level, dark: dark)
        }
    }
}

/// **NL1…NL5, ND1…ND5, T3n** — with no parent a level is the theme's text colour at SwiftUI's label alphas
/// divided by the primary's .847. The factors are the probe's: .588/.306/.116/.0555 light, .648/.292/.116/.0555
/// dark. Primary equals the theme's text colour bit for bit.
@Test @MainActor func withNoParentALevelIsTheThemesTextAtTheLabelAlphas() {
    let light: [Float] = [1, 0.588, 0.306, 0.116, 0.0555]
    let darkFactors: [Float] = [1, 0.648, 0.292, 0.116, 0.0555]
    let levels: [HierarchicalShapeStyle] = [.primary, .secondary, .tertiary, .quaternary, .quinary]
    for dark in [false, true] {
        let text = (dark ? Theme.dark : Theme.light).textPrimary.toRgba()
        let factors = dark ? darkFactors : light
        for (i, level) in levels.enumerated() {
            let own = painted(Text("Hi").foregroundStyle(level).environment(\.colorScheme, dark ? .dark : .light), dark: dark)
            let fill = painted(Circle().fill(level).frame(width: px(40), height: px(40))
                .environment(\.colorScheme, dark ? .dark : .light), dark: dark)
            for (name, scene, landing) in [("Text", own, Landing.glyph), ("fill", fill, .fill)] {
                #expect(has(scene, landing, (text.r, text.g, text.b), alpha: text.a * factors[i]),
                        "\(name) level \(i + 1) \(dark ? "dark" : "light"): wanted text × \(factors[i]), got \(describe(scene, landing))")
            }
        }
    }
}

/// **P6, P6d** — the separating arm: `Color.secondary` is not a level, so under a red parent it stays the
/// grey (the text colour at .588 / .648), and `foregroundColor(.secondary)` too.
@Test @MainActor func aColorSecondaryStaysGreyUnderAParent() {
    for dark in [false, true] {
        let text = (dark ? Theme.dark : Theme.light).textPrimary.toRgba()
        let want = text.a * (dark ? 0.648 : 0.588)
        let scheme: ColorScheme = dark ? .dark : .light
        let explicit = painted(HStack { ProposalText("Hi").foregroundStyle(Color.secondary) }.foregroundStyle(.red)
            .environment(\.colorScheme, scheme), dark: dark)
        let colourVariable = Color.secondary
        let variable = painted(HStack { Circle().fill(colourVariable).frame(width: px(40), height: px(40)) }
            .foregroundStyle(.red).environment(\.colorScheme, scheme), dark: dark)
        let legacy = painted(HStack { ProposalText("Hi").foregroundColor(.secondary) }.foregroundStyle(.red)
            .environment(\.colorScheme, scheme), dark: dark)
        for (name, scene, landing) in [("foregroundStyle(Color.secondary)", explicit, Landing.glyph),
                                       ("fill(Color value)", variable, .fill), ("foregroundColor(.secondary)", legacy, .glyph)] {
            #expect(has(scene, landing, (text.r, text.g, text.b), alpha: want),
                    "\(name) \(dark ? "dark" : "light"): wanted the grey at \(want), got \(describe(scene, landing))")
            #expect(!has(scene, landing, dark ? redDark : redLight, alpha: 0.5), "\(name): became a red level")
        }
    }
}

/// **P7, P8, P9, P10, S9, S9r** — levels do not compound; a plain child inherits the level; a parent's opacity
/// multiplies; the later modifier is the parent.
@Test @MainActor func levelsDoNotCompoundAndTheLaterModifierIsTheParent() {
    func fill<E: Element>(_ e: E) -> Scene { painted(e) }
    let size = (width: px(40), height: px(40))
    let text = Theme.light.textPrimary.toRgba()
    // P7: .secondary under .secondary, no parent -> one level, text × .588.
    let p7 = fill(HStack { Circle().foregroundStyle(.secondary).frame(width: size.width, height: size.height) }
        .foregroundStyle(.secondary))
    #expect(has(p7, .fill, (text.r, text.g, text.b), alpha: text.a * 0.588), "P7: \(describe(p7, .fill))")
    // P8: red -> .secondary -> .secondary -> .5.
    let p8 = fill(HStack { HStack { Circle().foregroundStyle(.secondary).frame(width: size.width, height: size.height) }
        .foregroundStyle(.secondary) }.foregroundStyle(.red))
    #expect(has(p8, .fill, redLight, alpha: 0.5), "P8: \(describe(p8, .fill))")
    #expect(!has(p8, .fill, redLight, alpha: 0.25), "P8 compounded")
    // P9: a plain child under red -> .secondary inherits the level.
    let p9 = fill(HStack { HStack { Circle().frame(width: size.width, height: size.height) }.foregroundStyle(.secondary) }
        .foregroundStyle(.red))
    #expect(has(p9, .fill, redLight, alpha: 0.5), "P9: \(describe(p9, .fill))")
    // P10: red.opacity(0.5) -> .secondary multiplies to .25.
    let p10 = fill(HStack { Circle().foregroundStyle(.secondary).frame(width: size.width, height: size.height) }
        .foregroundStyle(Color.red.opacity(0.5)))
    #expect(has(p10, .fill, redLight, alpha: 0.25), "P10: \(describe(p10, .fill))")
    // S9: .secondary then blue -> blue × .5; S9r: blue then .secondary -> plain blue (nothing over it).
    let blue = (r: Float(0), g: Float(0x88) / 255, b: Float(1))
    let s9 = fill(HStack { Circle().foregroundStyle(.secondary).frame(width: size.width, height: size.height) }
        .foregroundStyle(.blue))
    #expect(has(s9, .fill, blue, alpha: 0.5), "S9: \(describe(s9, .fill))")
    let s9r = fill(HStack { Circle().foregroundStyle(.blue).frame(width: size.width, height: size.height) }
        .foregroundStyle(.secondary))
    #expect(has(s9r, .fill, blue, alpha: 1), "S9r: \(describe(s9r, .fill))")
}

/// **P14, P15 (divergence 975)** — a gradient parent is lowered to its first stop, a `.tint` parent is the tint.
@Test @MainActor func aGradientParentLowersToItsFirstStopAndATintParentIsTheTint() {
    let size = (width: px(40), height: px(40))
    let gradient = LinearGradient(colors: [.red, .blue], startPoint: .leading, endPoint: .trailing)
    let p14 = painted(HStack { Circle().foregroundStyle(.secondary).frame(width: size.width, height: size.height) }
        .foregroundStyle(gradient))
    #expect(has(p14, .fill, redLight, alpha: 0.5), "P14 (first stop × .5): \(describe(p14, .fill))")
    let green = (r: Float(0x34) / 255, g: Float(0xC7) / 255, b: Float(0x59) / 255)
    let p15 = painted(HStack { Circle().foregroundStyle(.secondary).frame(width: size.width, height: size.height) }
        .foregroundStyle(.tint).tint(.green))
    #expect(has(p15, .fill, green, alpha: 0.5), "P15: \(describe(p15, .fill))")
}

/// **T9-adjacent, ternaries** — spellings whose binding differs: a ternary of two levels is a level, of two
/// colours a `Color`, `flag ? .red : .secondary` the grey `Color.secondary`.
@Test @MainActor func ternariesBindLikeTheirArms() {
    let text = Theme.light.textPrimary.toRgba()
    func fill(_ style: some ShapeStyle) -> Scene {
        painted(HStack { Circle().fill(style).frame(width: px(40), height: px(40)) }.foregroundStyle(.red))
    }
    let flag = ProcessInfoFlag.yes
    let levels = painted(HStack { Circle().fill(flag ? .secondary : .primary).frame(width: px(40), height: px(40)) }
        .foregroundStyle(.red))
    #expect(has(levels, .fill, redLight, alpha: 0.5), "level ternary: \(describe(levels, .fill))")
    let colours = painted(HStack { Circle().fill(flag ? .blue : .green).frame(width: px(40), height: px(40)) }
        .foregroundStyle(.red))
    #expect(has(colours, .fill, (r: 0, g: Float(0x88) / 255, b: 1), alpha: 1), "colour ternary: \(describe(colours, .fill))")
    let mixed = painted(HStack { Circle().fill(flag ? .red : .secondary).frame(width: px(40), height: px(40)) }
        .foregroundStyle(.blue))
    #expect(has(mixed, .fill, redLight, alpha: 1), "mixed ternary, red arm: \(describe(mixed, .fill))")
    let mixedGrey = painted(HStack { Circle().fill(!flag ? .red : .secondary).frame(width: px(40), height: px(40)) }
        .foregroundStyle(.blue))
    #expect(has(mixedGrey, .fill, (text.r, text.g, text.b), alpha: text.a * 0.588), "mixed ternary, grey arm: \(describe(mixedGrey, .fill))")
    _ = fill(HierarchicalShapeStyle.primary)
}

/// A value the optimiser cannot fold, so a ternary keeps both arms in the type checker's view.
private enum ProcessInfoFlag { static var yes: Bool { CommandLine.arguments.count >= 0 } }
