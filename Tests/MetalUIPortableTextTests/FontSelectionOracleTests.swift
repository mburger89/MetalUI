import CoreText
import Foundation
import MetalUIFreeType
import MetalUITextSystem
import Testing
@testable import MetalUIPortableText
@testable import MetalUIText

// Plan task 11 part 1, lane 2 (spec rows 1.1 and 1.2; rulings TE-C item 1,
// TE-W): the portable resolver picks the face CoreText picks for a weight and
// a slope. CoreText's answer is SwiftUI's (`docs/probes/swiftui-font-selection.swift`
// W/N: 151/151 rows), and `FontDescriptorResolutionTests` pins it on the
// CoreText side; this compares the portable answer with it, face for face,
// over the installed static multi-weight families below.
//
// The families' faces are registered the way `SystemFonts.resolver` registers
// a system's (ruling SF-B/SF-C): lazily, by the names and traits FreeType
// reads from the file (`FreeTypeFaceNames.read(path:)`), outside the cascade,
// regular styles first — so a lazy face is selected without its bytes, and a
// family name resolves to its regular face.

/// Static families with at least four faces on a stock macOS 27 install. A
/// family that is missing is skipped; at least two must be found.
private let oracleFamilies = [
    "Helvetica Neue", "Avenir Next", "Avenir Next Condensed", "Avenir", "Futura", "Gill Sans",
    "American Typewriter", "Optima", "Baskerville", "Menlo", "Palatino", "Didot", "Hoefler Text", "Cochin",
    "Seravek", "Sukhumvit Set", "Charter", "Iowan Old Style", "Superclarendon", "Athelas", "Big Caslon",
    "Copperplate", "Marion", "Rockwell", "Georgia", "Verdana", "Trebuchet MS", "Arial", "Times New Roman",
    "Courier New", "Kohinoor Bangla", "Kohinoor Telugu", "Kohinoor Gujarati", "Galvji", "Charter",
]

private let requestWeights: [Double?] = [nil, -0.8, -0.6, -0.4, 0, 0.23, 0.3, 0.4, 0.56, 0.62]

/// The files CoreText lists for `family`, and how many faces it has.
private func coreTextFaces(of family: String) -> (paths: Set<String>, count: Int) {
    let descriptor = CTFontDescriptorCreateWithAttributes([kCTFontFamilyNameAttribute: family] as CFDictionary)
    let matches = (CTFontDescriptorCreateMatchingFontDescriptors(descriptor, nil) as? [CTFontDescriptor]) ?? []
    let paths = matches.compactMap { (CTFontDescriptorCopyAttribute($0, kCTFontURLAttribute) as? URL)?.path }
    return (Set(paths), matches.count)
}

/// One request CoreText and the portable resolver answer differently: the
/// family, the weight (`nil`: none asked), the slope, and both faces.
struct SelectionDifference: Hashable, CustomStringConvertible {
    let family: String
    let weight: Double?
    let italic: Bool
    let coreText: String
    let portable: String
    var description: String {
        "(\(family.debugDescription), \(weight.map { "\($0)" } ?? "nil"), \(italic)) CoreText \(coreText) portable \(portable)"
    }
}

/// The differences ruling TE-W names (item 4), each with its reason there;
/// nothing else may differ. Three classes: a face whose CoreText weight
/// follows neither its style word nor its OS/2 class (Hoefler Text Black is
/// CoreText's 0.4, Futura Condensed ExtraBold its 0.62), a slant CoreText
/// declines for a nearer italic face (Futura bold italic stays upright Bold,
/// where Gill Sans ultra-bold italic takes BoldItalic), and one exact face
/// CoreText passes over (Sukhumvit Set thin, −0.6, is Light).
let pinnedSelectionDifferences: Set<SelectionDifference> = [
    SelectionDifference(family: "Futura", weight: 0.4, italic: true, coreText: "Futura-Bold", portable: "Futura-MediumItalic"),
    SelectionDifference(family: "Futura", weight: 0.56, italic: true, coreText: "Futura-Bold", portable: "Futura-MediumItalic"),
    SelectionDifference(family: "Futura", weight: 0.62, italic: false, coreText: "Futura-CondensedExtraBold",
                        portable: "Futura-Bold"),
    SelectionDifference(family: "Futura", weight: 0.62, italic: true, coreText: "Futura-CondensedExtraBold",
                        portable: "Futura-MediumItalic"),
    SelectionDifference(family: "Hoefler Text", weight: 0.23, italic: false, coreText: "HoeflerText-Black",
                        portable: "HoeflerText-Regular"),
    SelectionDifference(family: "Hoefler Text", weight: 0.23, italic: true, coreText: "HoeflerText-BlackItalic",
                        portable: "HoeflerText-Italic"),
    SelectionDifference(family: "Hoefler Text", weight: 0.3, italic: false, coreText: "HoeflerText-Black",
                        portable: "HoeflerText-Regular"),
    SelectionDifference(family: "Hoefler Text", weight: 0.3, italic: true, coreText: "HoeflerText-BlackItalic",
                        portable: "HoeflerText-Italic"),
    SelectionDifference(family: "Sukhumvit Set", weight: -0.6, italic: false, coreText: "SukhumvitSet-Light",
                        portable: "SukhumvitSet-Thin"),
    SelectionDifference(family: "Sukhumvit Set", weight: -0.6, italic: true, coreText: "SukhumvitSet-Light",
                        portable: "SukhumvitSet-Thin"),
]

/// **1.1.** Every (family, weight, slope) over the installed families: the
/// portable face's PostScript name equals CoreText's, except exactly the rows
/// `TE-W` pins.
@Test func thePortableResolverPicksCoreTextsFaceForEveryWeightAndItalic() throws {
    let resolver = try PortableFontResolver(defaultFont: fontBytes("NotoSans-Regular.ttf"))
    var found: [String] = []
    var registeredPaths: Set<String> = []
    var names: [FreeTypeFaceNames] = []
    var pathOf: [String: String] = [:]
    for family in oracleFamilies where !found.contains(family) {
        let faces = coreTextFaces(of: family)
        guard faces.count >= 4, !faces.paths.isEmpty else { continue }
        found.append(family)
        for path in faces.paths.sorted() where registeredPaths.insert(path).inserted {
            for face in FreeTypeFaceNames.read(path: path) {
                names.append(face)
                pathOf[face.postScript] = path
            }
        }
    }
    try #require(found.count >= 2, "at least two multi-weight families must be installed: \(found)")
    let isRegular = { (face: FreeTypeFaceNames) in
        ["regular", "book", "normal", "roman", ""].contains(face.style.lowercased())
    }
    var loads = 0
    for face in names.filter(isRegular) + names.filter({ !isRegular($0) }) {
        let path = pathOf[face.postScript]!
        resolver.register(face, inCascade: false) {
            loads += 1
            return [UInt8](try Data(contentsOf: URL(fileURLWithPath: path)))
        }
    }
    // Laziness (SF-B): registering reads no face's bytes, and a selection
    // reads traits, not bytes — the first request opens only its answer.
    #expect(loads == 0, "registration loaded \(loads) faces")
    _ = try resolver.resolve(FontDescriptor(family: "Helvetica Neue", size: 15, weight: 0.4, italic: true))
    #expect(loads == 1, "one bold italic request loaded \(loads) faces")
    var differences: Set<SelectionDifference> = []
    var compared = 0
    for family in found {
        for weight in requestWeights {
            for italic in [false, true] {
                let descriptor = FontDescriptor(family: family, size: 15, weight: weight, italic: italic)
                let apple = FontResolver.resolve(descriptor).key.postScriptName
                let portable = try resolver.resolve(descriptor).key.postScriptName
                compared += 1
                if apple != portable {
                    differences.insert(SelectionDifference(family: family, weight: weight, italic: italic,
                                                           coreText: apple, portable: portable))
                }
            }
        }
    }
    print("TE-W font selection: \(found.count) families, \(names.count) faces, \(compared) requests, "
          + "\(differences.count) differences, \(loads) faces loaded")
    for difference in differences.sorted(by: { $0.description < $1.description }) { print("  \(difference)") }
    let pinned = pinnedSelectionDifferences.filter { found.contains($0.family) }
    let unpinned = differences.subtracting(pinned).sorted { $0.description < $1.description }
    let unmatched = pinned.subtracting(differences).sorted { $0.description < $1.description }
    #expect(differences == pinned, "unpinned: \(unpinned); pinned but matching: \(unmatched)")
    // The corpus is not dominated by the pinned rows.
    #expect(compared >= 300 && differences.count * 20 < compared, "\(differences.count) of \(compared)")
}

/// **1.2.** A weight or slope the family lacks draws the registered face
/// unchanged, on both systems (F2h, F4b): with only Noto Sans Regular (and
/// two other families' regular faces) registered, bold, black, light and
/// italic requests all give `NotoSans-Regular` — never another family's face
/// and never a synthesised one.
@Test func aWeightOrItalicTheFamilyLacksDrawsTheRegisteredFaceUnchanged() throws {
    try withBundledFacesRegistered {
        for defaultFace in bundledFaces {
            let resolver = try bundledResolver(default: defaultFace)
            for (family, expected) in [("Noto Sans", "NotoSans-Regular"), ("Source Sans 3", "SourceSans3-Regular")] {
                for weight in requestWeights {
                    for italic in [false, true] {
                        let descriptor = FontDescriptor(family: family, size: 15, weight: weight, italic: italic)
                        #expect(FontResolver.resolve(descriptor).key.postScriptName == expected, "\(descriptor)")
                        #expect(try resolver.resolve(descriptor).key.postScriptName == expected,
                                "\(descriptor), default \(defaultFace)")
                    }
                }
            }
            // A design names a registered family for a request with no
            // family (`register(design:family:)`); an unregistered design is
            // the default face, as an unmatched name is.
            let defaultName = try resolver.resolve(family: nil, size: 15).key.postScriptName
            resolver.register(design: .serif, family: "Source Sans 3")
            #expect(try resolver.resolve(FontDescriptor(size: 15, design: .serif)).key.postScriptName
                    == "SourceSans3-Regular")
            #expect(try resolver.resolve(FontDescriptor(size: 15, design: .rounded)).key.postScriptName == defaultName)
            #expect(try resolver.resolve(FontDescriptor(family: "Noto Sans", size: 15, design: .serif)).key
                .postScriptName == "NotoSans-Regular", "a family wins over a design")
        }
    }
}
