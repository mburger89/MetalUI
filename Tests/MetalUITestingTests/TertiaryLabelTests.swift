import MetalUI
import MetalUIScene
import MetalUITesting
import Testing

// Sift gap G13 (record 393, ruling `CR-AE`): there is no `Color.tertiary` (SwiftUI has none); the third and fourth label levels are
// the hierarchical `.tertiary` and `.quaternary`, which already exist. A grid cell's NULL marker (italic, sized text) painted
// with `foregroundStyle(.tertiary)` takes SwiftUI's ratios of the theme text colour, 0.306 light and 0.292 dark for
// tertiary and 0.116 for quaternary, in both appearances.

@Test(arguments: [ColorScheme.light, .dark]) @MainActor
func aCellMarkerInTheTertiaryAndQuaternaryLevelsResolvesInBothAppearances(scheme: ColorScheme) throws {
    let w = try harnessWindow(colorScheme: scheme) {
        VStack(spacing: 0) {
            Text(verbatim: "NULL").font(size: 13).italic().foregroundStyle(.tertiary)
            Text(verbatim: "NULL").font(size: 13).italic().foregroundStyle(.quaternary)
        }
    }
    try w.tick()
    let text = scheme == .dark ? Theme.dark.textPrimary : Theme.light.textPrimary
    let colours = w.scene.glyphs.map(\.color)
    func has(_ factor: Float) -> Bool {
        colours.contains { abs($0.a - text.a * factor) < 1e-4 && abs($0.l - text.l) < 1e-4 }
    }
    let tertiary: Float = scheme == .dark ? 0.292 : 0.306
    #expect(has(tertiary), "a tertiary glyph at \(tertiary) of the text colour in \(scheme): \(colours.map(\.a))")
    #expect(has(0.116), "a quaternary glyph at 0.116: \(colours.map(\.a))")
    #expect(Color.secondary != Color.primary)   // the two Color statics SwiftUI has
}
