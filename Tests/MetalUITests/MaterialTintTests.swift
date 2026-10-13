import Testing
import MetalUICore
@testable import MetalUI

// C27 lane A — the public read of a material's tint (ruling `MT-B`; spec
// `docs/superpowers/specs/2026-10-12-material-followups-design.md`, tests 1-2).
// SwiftUI has no such read (probe `swiftui-material-followups.swift`, arm A2),
// so the method is MetalUI-only (class M).

private let table: [(String, Material, ColorScheme, Float, Float)] = [
    ("ultraThin", .ultraThinMaterial, .light, 0.9250, 0.4706),
    ("thin", .thinMaterial, .light, 0.9145, 0.5961),
    ("regular", .regularMaterial, .light, 0.9121, 0.7137),
    ("thick", .thickMaterial, .light, 0.9052, 0.8275),
    ("ultraThick", .ultraThickMaterial, .light, 0.8996, 0.9373),
    ("bar", .bar, .light, 1.0000, 0.8000),
    ("ultraThin", .ultraThinMaterial, .dark, 0.2248, 0.5059),
    ("thin", .thinMaterial, .dark, 0.2105, 0.5961),
    ("regular", .regularMaterial, .dark, 0.2045, 0.6902),
    ("thick", .thickMaterial, .dark, 0.2010, 0.7804),
    ("ultraThick", .ultraThickMaterial, .dark, 0.2000, 0.8627),
    ("bar", .bar, .dark, 0.1779, 0.8157),
]

/// **MT-B test 1.** `tint(in:)` is `LK-L` item 3's table for every kind and scheme.
/// Mutations: change one alpha in `fill(for:)`; make `tint(in:)` ignore `scheme`.
@Test func materialTintMatchesTheFillTableForEveryKindAndScheme() throws {
    try #require(table.count == 12)
    for (name, material, scheme, grey, alpha) in table {
        let r = material.tint(in: scheme).resolve(in: EnvironmentValues())
        #expect(abs(r.opacity - alpha) < 1e-4, "\(name) \(scheme) opacity \(r.opacity) != \(alpha)")
        #expect(abs(r.red - grey) < 1e-4, "\(name) \(scheme) grey \(r.red) != \(grey)")
        #expect(r.red == r.green && r.green == r.blue, "\(name) \(scheme) is a grey")
    }
}

/// **MT-B test 2.** The glass identity `(1 - t)(1 - m) = 1 - g` holds for the panel
/// opacity `t` solved from the public read.
/// Mutation: `tint(in:)` returns `opacity(1)`.
@Test func theGlassIdentityHoldsForTheSolvedTint() throws {
    for material: Material in [.ultraThinMaterial, .regularMaterial, .bar] {
        for scheme in [ColorScheme.light, .dark] {
            let m = Double(material.tint(in: scheme).resolve(in: EnvironmentValues()).opacity)
            try #require(m > 0 && m < 1)
            for g in [0.9, 0.97] {
                let t = 1 - (1 - g) / (1 - m)
                #expect(abs((1 - t) * (1 - m) - (1 - g)) < 1e-6)
                #expect(t > 0 && t < 1, "g \(g) is above m \(m), so t is a real opacity")
            }
        }
    }
}
