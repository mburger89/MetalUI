import AppKit
import CoreText
import Foundation
import MetalUITextSystem
import Testing
@testable import MetalUIText

// Plan task 11 part 1, lane 2 (spec rows 1.3 and 1.4; rulings TE-C item 1,
// TE-W): `FontResolver.resolve(_ descriptor:)` — the CoreText half of font
// selection — answers the face SwiftUI draws. SwiftUI's answers come from
// probes: `docs/probes/swiftui-text-semantics.swift` F2/F3/F4 (the system
// font is `NSFont.systemFont(ofSize:weight:)`, its designs
// `NSFontDescriptor.withDesign`, its italic the italic face) and X2/X2b/X2d,
// and `docs/probes/swiftui-font-selection.swift` W/N/S (a custom family's
// weight and italic by CoreText's descriptor matching, 144/144 rows; the
// system font's weight × design × italic, 32/32).
//
// Each arm resolves twice: through `FontResolver` directly, and through one
// `CoreTextTextSystem` (its `ShapingCache` memo) asked every descriptor in
// turn, so a memo keyed on the family and size alone serves the first
// weight's face for every later one and reddens here.

private let nineWeights: [(label: String, value: Double, ns: NSFont.Weight)] = [
    ("ultraLight", -0.8, .ultraLight), ("thin", -0.6, .thin), ("light", -0.4, .light), ("regular", 0, .regular),
    ("medium", 0.23, .medium), ("semibold", 0.3, .semibold), ("bold", 0.4, .bold), ("heavy", 0.56, .heavy),
    ("black", 0.62, .black),
]

private let threeDesigns: [(design: FontDesign, ns: NSFontDescriptor.SystemDesign)] = [
    (.serif, .serif), (.rounded, .rounded), (.monospaced, .monospaced),
]

/// **1.3.** The system descriptor is `NSFont.systemFont(ofSize:weight:)` at all
/// nine weights (F2), `withDesign` at the three designs and at every weight
/// under each (F3, S), and the italic face (F4) — whole `FontKey`s, so the
/// variation coordinates count, not only the PostScript name. The unweighted,
/// upright, default-design request is the face `resolve(family: nil, size:)`
/// always gave (0 px for every existing caller).
@MainActor
@Test func theSystemDescriptorIsNSFontsSystemFontAtEveryWeightAndDesign() throws {
    let system = CoreTextTextSystem()
    #expect(FontResolver.resolve(FontDescriptor(size: 13)).key == FontResolver.resolve(family: nil, size: 13).key)
    var names: Set<String> = []
    for size in [13.0, 26.0] {
        for weight in nineWeights {
            let expected = FontKey(resolved: NSFont.systemFont(ofSize: size, weight: weight.ns) as CTFont)
            let descriptor = FontDescriptor(size: size, weight: weight.value)
            #expect(FontResolver.resolve(descriptor).key == expected, "\(weight.label) \(size)")
            #expect(system.resolveFont(descriptor) == expected, "\(weight.label) \(size), through the seam")
            names.insert(expected.postScriptName)
            for design in threeDesigns {
                let ns = NSFont.systemFont(ofSize: size, weight: weight.ns).fontDescriptor.withDesign(design.ns)!
                let designed = FontKey(resolved: NSFont(descriptor: ns, size: size)! as CTFont)
                let request = FontDescriptor(size: size, weight: weight.value, design: design.design)
                #expect(FontResolver.resolve(request).key == designed, "\(weight.label) \(design.design) \(size)")
                #expect(system.resolveFont(request) == designed, "\(weight.label) \(design.design) \(size), seam")
                names.insert(designed.postScriptName)
            }
        }
        for design in threeDesigns {
            let ns = NSFont.systemFont(ofSize: size).fontDescriptor.withDesign(design.ns)!
            let designed = FontKey(resolved: NSFont(descriptor: ns, size: size)! as CTFont)
            #expect(FontResolver.resolve(FontDescriptor(size: size, design: design.design)).key == designed)
            #expect(system.resolveFont(FontDescriptor(size: size, design: design.design)) == designed)
        }
    }
    // F4: the italic face of the system font; F3's serif italic (probe S).
    #expect(FontResolver.resolve(FontDescriptor(size: 13, italic: true)).key.postScriptName == ".SFNS-RegularItalic")
    #expect(system.resolveFont(FontDescriptor(size: 13, italic: true)).postScriptName == ".SFNS-RegularItalic")
    #expect(FontResolver.resolve(FontDescriptor(size: 13, weight: 0.3, italic: true)).key.postScriptName
            == ".SFNS-SemiboldItalic")
    #expect(FontResolver.resolve(FontDescriptor(size: 13, italic: true, design: .serif)).key.postScriptName
            == ".NewYork-RegularItalic")
    // The instrument separates: nine weights and every design are different faces.
    try #require(names.count >= 9 + 3, "the arms must name distinct faces: \(names.sorted())")
}

/// **1.4.** A custom family's weight selects its nearest face by CoreText's
/// descriptor matching (X2: semibold → Medium, heavy → Bold, black →
/// CondensedBlack — `swiftui-font-selection.swift` W, which lists every face
/// the family has), from a PostScript name too (X2d: `HelveticaNeue-Bold` +
/// light → Light); italic is the family's italic face (X2b, N), at the
/// weight asked for (W: Avenir Next light italic → UltraLightItalic, not the
/// upright Regular's Italic), and nothing when the family has none (N:
/// American Typewriter).
@MainActor
@Test func aCustomFamilysWeightSelectsItsNearestFace() throws {
    let system = CoreTextTextSystem()
    let helveticaNeue = [
        "HelveticaNeue-UltraLight", "HelveticaNeue-Thin", "HelveticaNeue-Light", "HelveticaNeue",
        "HelveticaNeue-Medium", "HelveticaNeue-Medium", "HelveticaNeue-Bold", "HelveticaNeue-Bold",
        "HelveticaNeue-CondensedBlack",
    ]
    for (weight, expected) in zip(nineWeights, helveticaNeue) {
        let descriptor = FontDescriptor(family: "Helvetica Neue", size: 15, weight: weight.value)
        #expect(FontResolver.resolve(descriptor).key.postScriptName == expected, "\(weight.label)")
        #expect(system.resolveFont(descriptor).postScriptName == expected, "\(weight.label), through the seam")
    }
    let rows: [(FontDescriptor, String)] = [
        (FontDescriptor(family: "Helvetica Neue", size: 15), "HelveticaNeue"),
        (FontDescriptor(family: "HelveticaNeue-Bold", size: 15), "HelveticaNeue-Bold"),
        (FontDescriptor(family: "HelveticaNeue-Bold", size: 15, weight: -0.4), "HelveticaNeue-Light"),
        (FontDescriptor(family: "Helvetica Neue", size: 15, italic: true), "HelveticaNeue-Italic"),
        (FontDescriptor(family: "HelveticaNeue-Bold", size: 15, italic: true), "HelveticaNeue-BoldItalic"),
        (FontDescriptor(family: "Helvetica Neue", size: 15, weight: 0.4, italic: true), "HelveticaNeue-BoldItalic"),
        (FontDescriptor(family: "Helvetica Neue", size: 15, weight: 0.62, italic: true), "HelveticaNeue-CondensedBlack"),
        (FontDescriptor(family: "Avenir Next", size: 15, weight: -0.4), "AvenirNext-Regular"),
        (FontDescriptor(family: "Avenir Next", size: 15, weight: -0.4, italic: true), "AvenirNext-UltraLightItalic"),
        (FontDescriptor(family: "American Typewriter", size: 15, italic: true), "AmericanTypewriter"),
        (FontDescriptor(family: "American Typewriter", size: 15, weight: 0.4, italic: true), "AmericanTypewriter-Bold"),
    ]
    for (descriptor, expected) in rows {
        #expect(FontResolver.resolve(descriptor).key.postScriptName == expected, "\(descriptor)")
        #expect(system.resolveFont(descriptor).postScriptName == expected, "\(descriptor), through the seam")
    }
}
