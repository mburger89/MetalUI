import Testing
import Foundation
@testable import MetalUI
import MetalUIPortableText
import MetalUISystemFonts
import MetalUITextSystem
#if canImport(CoreText)
import MetalUIText
#endif

// `CodeStyle` faces over real monospaced families (`CV-BY`, record 397): a face may reshape a line, but the families an
// editor uses keep one advance in every face, so the carets of a line with faces are the carets of the same line without.
// The numbers are the fonts' own, so they are relations, never literals.

/// Forty ASCII characters: narrow, wide and punctuation, so a face with another width anywhere shows.
private let probe = "iW.mM0O1l|~#@ abcdefghijklmnopqrstuvwxyz0"

private struct FaceSpec { var italic: Bool; var weight: Font.Weight? }
private let faceSpecs = [FaceSpec(italic: false, weight: nil), FaceSpec(italic: false, weight: .bold),
                         FaceSpec(italic: true, weight: nil), FaceSpec(italic: true, weight: .bold)]

/// Whether the family `name` keeps one advance in its regular, bold, italic and bold italic faces, for `system`, by the
/// system's own caret offsets and by a line built from four runs, one in each face.
@MainActor private func checkOneAdvance(_ system: any TextSystem, family: String?, design: FontDesign = .default) {
    func font(_ spec: FaceSpec) -> FontKey {
        system.resolveFont(FontDescriptor(family: family, size: 14, weight: spec.weight?.value, italic: spec.italic, design: design))
    }
    let regular = font(faceSpecs[0])
    let reference = system.caretOffsets(probe, font: regular)
    #expect(reference.count == probe.count + 1)
    for spec in faceSpecs.dropFirst() {
        let face = font(spec)
        #expect(face != regular, "\(family ?? "system") has a real \(spec.italic ? "italic " : "")\(spec.weight == nil ? "" : "bold ")face")
        let offsets = system.caretOffsets(probe, font: face)
        #expect(offsets.count == reference.count && zip(offsets, reference).allSatisfy { abs($0 - $1) < 0.001 },
                "\(family ?? "system") \(spec): \(offsets.suffix(3)) against \(reference.suffix(3))")
    }
    // Through the line builder: four 10-byte runs, one in each face, put the carets where one face would.
    let bytes = Array(probe.utf8)
    func code(_ spec: FaceSpec) -> UInt8 { CodeDecorations.faceCode(italic: spec.italic, weight: spec.weight) }
    let faced: [(bytes: Int, style: CodeStyleID?, face: UInt8)] = [(10, nil, code(faceSpecs[1])), (10, nil, code(faceSpecs[2])),
                                                                    (10, nil, code(faceSpecs[3])), (10, nil, 0)]
    let flat: [(bytes: Int, style: CodeStyleID?, face: UInt8)] = [(40, nil, 0)]
    let faces = CodeFaces(font: { c in
        font(FaceSpec(italic: CodeDecorations.faceItalic(c), weight: CodeDecorations.faceWeight(c)))
    }, baselinePx: { 0 })
    let a = buildCodeLine(bytes: bytes[...], windowStart: 0, windowX: 0, parts: faced, partOffset: 0, font: regular, scale: 2,
                          tabColumns: 4, spaceAdvance: 8, system: system, faces: faces)
    let b = buildCodeLine(bytes: bytes[...], windowStart: 0, windowX: 0, parts: flat, partOffset: 0, font: regular, scale: 2,
                          tabColumns: 4, spaceAdvance: 8, system: system)
    #expect(a.caretX.count == b.caretX.count && zip(a.caretX, b.caretX).allSatisfy { abs($0 - $1) < 0.01 },
            "\(family ?? "system"): carets of a faced line \(a.caretX.suffix(3)) against \(b.caretX.suffix(3))")
    #expect(abs(a.width - b.width) < 0.01)
}

/// **13** The monospaced families keep one advance in every face, so the carets, hit testing and the column fast paths
/// of a line with faces are those of the line without (the named limit of `CV-BY` is only for a family that does not).
/// On macOS with CoreText: SF Mono (the system's monospaced face) and Menlo, each in regular, bold, italic and bold
/// italic, over 40 ASCII characters. **Mutation:** the per-run caret offsets left unshifted by their run's start
/// (`minX` dropped), which puts every run's carets at the line's start.
#if canImport(CoreText)
@Test @MainActor func monospacedFacesKeepOneAdvance() {
    let system = CoreTextTextSystem()
    checkOneAdvance(system, family: nil, design: .monospaced)
    checkOneAdvance(system, family: "Menlo")
}
#endif

/// The portable arm of **13**: the first of DejaVu Sans Mono, Consolas, Cascadia Mono (and, on macOS, Menlo) installed.
/// Skipped when none is: a CI image without a monospaced family has nothing to measure.
private func installedMonospace() -> String? {
    let installed = Set(SystemFonts.scan(SystemFonts.directories).map(\.names.family))
    return ["DejaVu Sans Mono", "Consolas", "Cascadia Mono", "Menlo"].first { installed.contains($0) }
}
private let portableMonospace = installedMonospace()

@Test(.enabled(if: portableMonospace != nil, "no DejaVu Sans Mono, Consolas, Cascadia Mono or Menlo is installed"))
@MainActor func monospacedFacesKeepOneAdvanceOnThePortableSystem() throws {
    let family = try #require(portableMonospace)
    let system = PortableTextSystem(resolver: try SystemFonts.resolver())
    checkOneAdvance(system, family: family)
}
