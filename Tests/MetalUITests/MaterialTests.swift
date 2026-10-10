import Testing
import MetalUICore
import MetalUILayout
import MetalUIScene
@testable import MetalUI

// C10 lane 3 — materials (rulings `LK-L`, `LK-O` item 2; divergence 166; spec
// `docs/superpowers/specs/2026-10-08-controls-looks-design.md` §4.3). SwiftUI's
// side is `docs/probes/swiftui-controls-looks.swift`, arms M5 (each material
// over uniform white and black, ImageRenderer, both schemes).

private func px(_ v: Float) -> Pixels { Pixels(v) }

private let materials: [(String, Material)] = [
    ("ultraThin", .ultraThinMaterial), ("thin", .thinMaterial), ("regular", .regularMaterial),
    ("thick", .thickMaterial), ("ultraThick", .ultraThickMaterial), ("bar", .bar),
]

/// `color` (straight, gamma, 0…1) at `alpha` over the grey `backdrop`
/// (0…255), as the renderer blends: in gamma space, rounded.
private func over(_ c: Float, _ alpha: Float, _ backdrop: Float) -> Int {
    Int((c * 255 * alpha + backdrop * (1 - alpha)).rounded())
}

private func rgba(_ c: MUIHsla) -> Rgba { Hsla(h: c.h, s: c.s, l: c.l, a: c.a).toRgba() }

// MARK: - 3.28 (M5)

/// **3.28** (M5, `LK-L` item 3). Every material's flat tint, composited over
/// uniform white and black, matches SwiftUI's material (ImageRenderer) within
/// one level, in both schemes — 12 × 2 composites, and a `Rectangle().fill`
/// of each draws that colour. Mutation: swap thin and thick.
@Test @MainActor func everyMaterialMatchesSwiftUIOverWhiteAndBlackM5() throws {
    let m5: [ColorScheme: [String: (white: Int, black: Int)]] = [
        .light: ["ultraThin": (246, 111), "thin": (242, 139), "regular": (239, 166), "thick": (235, 191),
                 "ultraThick": (231, 215), "bar": (255, 204)],
        .dark: ["ultraThin": (155, 29), "thin": (135, 32), "regular": (115, 36), "thick": (96, 40),
                "ultraThick": (79, 44), "bar": (84, 37)],
    ]
    for scheme in [ColorScheme.light, .dark] {
        var environment = EnvironmentValues()
        environment.colorScheme = scheme
        for (name, material) in materials {
            let tint = material.color.resolve(in: environment)
            let want = try #require(m5[scheme]?[name])
            #expect(abs(tint.red - tint.green) < 1e-6 && abs(tint.green - tint.blue) < 1e-6, "\(name): a grey")
            let white = over(tint.red, tint.opacity, 255), black = over(tint.red, tint.opacity, 0)
            #expect(abs(white - want.white) <= 1 && abs(black - want.black) <= 1,
                    "\(scheme) \(name): over white \(white) vs \(want.white), over black \(black) vs \(want.black)")
        }
    }
    // The fill site draws the colour site's rect with that colour (`LK-L` item 3).
    let scene = lkScene(Rectangle().fill(.thickMaterial).frame(width: px(20), height: px(20)), side: 100)
    try #require(scene.rects.count == 1, "one rect, no new primitive: \(scene.rects.count)")
    let drawn = rgba(scene.rects[0].background)
    #expect(abs(over(drawn.r, drawn.a, 255) - 235) <= 1 && abs(over(drawn.r, drawn.a, 0) - 191) <= 1,
            "thick over white 235, black 191: \(drawn)")
}

// MARK: - 3.29 (LK-L item 3)

/// **3.29** (`LK-L` item 3). A material follows the colour scheme on every
/// site: the proposal `.background(.regularMaterial)`, the legacy one and
/// `.background(_:in:)` paint the light tint in a light scope and the dark
/// tint in a dark one. Mutation: the light table in dark.
@Test @MainActor func aMaterialFollowsTheColourScheme() throws {
    func tree() -> some Element {
        Column {
            Color.clear.frame(width: px(40), height: px(10)).background(.regularMaterial)
            Box().frame(width: px(40), height: px(10)).background(.regularMaterial)
            Color.clear.frame(width: px(40), height: px(10)).background(.regularMaterial, in: Rectangle())
        }
    }
    func whites(_ scheme: ColorScheme) -> [Int] {
        let scene = lkScene(Column { tree().environment(\.colorScheme, scheme) }, side: 100)
        return scene.rects.filter { $0.background.a > 0 }.map {
            let c = rgba($0.background)
            return over(c.r, c.a, 255)
        }
    }
    let light = whites(.light), dark = whites(.dark)
    try #require(light.count == 3 && dark.count == 3, "three tinted rects each: \(light) \(dark)")
    #expect(light.allSatisfy { abs($0 - 239) <= 1 }, "light regular over white 239: \(light)")
    #expect(dark.allSatisfy { abs($0 - 115) <= 1 }, "dark regular over white 115: \(dark)")
}
