import Testing
import Foundation
import Metal
import MetalUICore
import MetalUIPath
import MetalUIScene
import MetalUIShaderTypes
@testable import MetalUIRender

// Liquid Glass, lane A, render tests 2, 5b, 7-10 and 12 (rulings `LG-B`, `LG-D`, `LG-G`, `LG-S`;
// spec `docs/superpowers/specs/2026-10-23-liquid-glass-design.md` §5). The Metal renderer draws a
// glass record through `backdrop_fragment`'s glass branch; every expected pixel is computed from
// the scene (the backdrop pixels are known by construction), `BackdropBlurReference` and
// `GlassReference`, never from the renderer's own output. macOS hardware.

private func maxOff(_ pixels: [UInt8], width: Int, expected: [SIMD4<Float>]) -> Float {
    var worst: Float = 0
    for (i, e) in expected.enumerated() {
        let got = glassPixel(pixels, i % width, i / width, width: width)
        for c in 0..<4 { worst = max(worst, abs(got[c] - e[c] * 255)) }
    }
    return worst
}

/// `base64` of the 40x16 BGRA readback of `materialScene()` taken on `f1c422e5`, before the glass
/// tail existed: four hue bars and one rounded, tinted, half-opaque material over them.
private let materialBaseline = """
AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wD/f/8A/4D/AP+A/wD/gP8A/4D/AP+A/wD/gP8A/4D/AP+A
/wD/gP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD//wB///8AgP//AID//wCA//8AgP//AID//wCA//8A
gP//AID//wCA/wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8A/3//AP+A/wD/gP8A/4D/AP+A/wD/gP8A
/4D/AP+A/wD/gP8A/4D///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A//8Af///AID//wCA//8AgP//AID/
/wCA//8AgP//AID//wCA//8AgP8AAP//AAD//wAA//8AAP//AAD//wcO9P8aNtf/JlHE/ylbvf8sYrj/L5ya/zOilf83qY//PK6K
/0K0hP9IuH//Trx6/1S/df9bwXH/YsJt/53CUP+kwU3/q79K/7G8Sf+3uEf/vbRH/8OuRv/IqUf/zKJI/9CcSf/TYmX/1ltn/9lR
av/lNnL/+A58//8AgP//AID//wCA//8AgP//AID/AAD//wAA//8AAP//AAD//wcO9f8iRcz/JU7G/ydUwv8pW73/LGK4/y+cmv8z
opX/N6mP/zyuiv9CtIT/SLh//068ev9Vv3X/W8Fx/2PCbf+cwlD/o8FN/6q/Sv+xvEn/t7hH/720R//Drkf/yKlH/8yiSP/QnEn/
02Jl/9ZbZ//YVGn/2k5r/91Fbv/4Dn3//wCA//8AgP//AID//wCA/wAA//8AAP//AAD//wAA//8YMNv/I0jK/yVOxv8nVML/KVu9
/yxiuP8vnJr/M6KV/zepj/88ror/QrSE/0i4f/9OvHr/Vb91/1vBcf9jwm3/nMJQ/6PBTf+qv0r/sbxJ/7e4R/+9tEf/w65H/8ip
R//Mokj/0JxJ/9NiZf/WW2f/2FRp/9pOa//cSG7/5zB0//8AgP//AID//wCA//8AgP8AAP//AAD//wAA//8AAP//IULO/yNIyv8l
Tsb/J1TC/ylbvf8sYrj/L5ya/zOilf83qY//PK6K/0K0hP9IuH//Trx6/1W/df9bwXH/Y8Jt/5zCUP+jwU3/qr9K/7G8Sf+3uEf/
vbRH/8OuR//IqUf/zKJI/9CcSf/TYmX/1ltn/9hUaf/aTmv/3Ehu/95CcP//AID//wCA//8AgP//AID/AAD//wAA//8AAP//AAD/
/yNFzP8jSMr/JU7G/ydUwv8pW73/LGK4/y+cmv8zopX/N6mP/zyuiv9CtIT/SLh//068ev9Vv3X/W8Fx/2PCbf+cwlD/o8FN/6q/
Sv+xvEn/t7hH/720R//Drkf/yKlH/8yiSP/QnEn/02Jl/9ZbZ//YVGn/2k5r/9xIbv/cRW///wCA//8AgP//AID//wCA/wAA//8A
AP//AAD//wAA//8jRcz/I0jK/yVOxv8nVML/KVu9/yxiuP8vnJr/M6KV/zepj/88ror/QrSE/0i4f/9OvHr/Vb91/1vBcf9jwm3/
nMJQ/6PBTf+qv0r/sbxJ/7e4R/+9tEf/w65H/8ipR//Mokj/0JxJ/9NiZf/WW2f/2FRp/9pOa//cSG7/3EVv//8AgP//AID//wCA
//8AgP8AAP//AAD//wAA//8AAP//I0XM/yNIyv8lTsb/J1TC/ylbvf8sYrj/L5ya/zOilf83qY//PK6K/0K0hP9IuH//Trx6/1W/
df9bwXH/Y8Jt/5zCUP+jwU3/qr9K/7G8Sf+3uEf/vbRH/8OuR//IqUf/zKJI/9CcSf/TYmX/1ltn/9hUaf/aTmv/3Ehu/9xFb///
AID//wCA//8AgP//AID/AAD//wAA//8AAP//AAD//yNFzP8jSMr/JU7G/ydUwv8pW73/LGK4/y+cmv8zopX/N6mP/zyuiv9CtIT/
SLh//068ev9Vv3X/W8Fx/2PCbf+cwlD/o8FN/6q/Sv+xvEn/t7hH/720R//Drkf/yKlH/8yiSP/QnEn/02Jl/9ZbZ//YVGn/2k5r
/9xIbv/cRW///wCA//8AgP//AID//wCA/wAA//8AAP//AAD//wAA//8hQs7/I0jK/yVOxv8nVML/KVu9/yxiuP8vnJr/M6KV/zep
j/88ror/QrSE/0i4f/9OvHr/Vb91/1vBcf9jwm3/nMJQ/6PBTf+qv0r/sbxJ/7e4R/+9tEf/w65H/8ipR//Mokj/0JxJ/9NiZf/W
W2f/2FRp/9pOa//cSG7/3kJw//8AgP//AID//wCA//8AgP8AAP//AAD//wAA//8AAP//GDDb/yNIyv8lTsb/J1TC/ylbvf8sYrj/
L5ya/zOilf83qY//PK6K/0K0hP9IuH//Trx6/1W/df9bwXH/Y8Jt/5zCUP+jwU3/qr9K/7G8Sf+3uEf/vbRH/8OuR//IqUf/zKJI
/9CcSf/TYmX/1ltn/9hUaf/aTmv/3Ehu/+cwdP//AID//wCA//8AgP//AID/AAD//wAA//8AAP//AAD//wcO9f8iRcz/JU7G/ydU
wv8pW73/LGK4/y+cmv8zopX/N6mP/zyuiv9CtIT/SLh//068ev9Vv3X/W8Fx/2PCbf+cwlD/o8FN/6q/Sv+xvEn/t7hH/720R//D
rkf/yKlH/8yiSP/QnEn/02Jl/9ZbZ//YVGn/2k5r/91Fbv/4Dn3//wCA//8AgP//AID//wCA/wAA//8AAP//AAD//wAA//8AAP//
Bw70/xo21/8mUcT/KVu9/yxiuP8vnJr/M6KV/zepj/88ror/QrSE/0i4f/9OvHr/Vb91/1vBcf9jwm3/nMJQ/6PBTf+qv0r/sbxJ
/7e4R/+9tEf/w65H/8ipR//Mokj/0JxJ/9NiZf/WW2f/2VFq/+U2cv/4Dnz//wCA//8AgP//AID//wCA//8AgP8AAP//AAD//wAA
//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AP9//wD/gP8A/4D/AP+A/wD/gP8A/4D/AP+A/wD/gP8A/4D/AP+A////AP//
/wD///8A////AP///wD///8A////AP///wD///8A////AP//AH///wCA//8AgP//AID//wCA//8AgP//AID//wCA//8AgP//AID/
AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wD/f/8A/4D/AP+A/wD/gP8A/4D/AP+A/wD/gP8A/4D/AP+A
/wD/gP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD//wB///8AgP//AID//wCA//8AgP//AID//wCA//8A
gP//AID//wCA/w==
"""

private func materialScene() -> Scene {
    var scene = Scene()
    for (i, x) in [0, 10, 20, 30].enumerated() {
        scene.insert(glassSolid(glassBounds(Float(x), 0, 10, 16), MUIHsla(h: Float(i) / 4, s: 1, l: 0.5, a: 1)))
    }
    scene.insert(MUIBackdrop(bounds: glassBounds(4, 2, 32, 12), contentMask: glassWide, maskCornerRadii: glassSquare,
                             cornerRadii: MUICorners(topLeft: 4, topRight: 4, bottomRight: 4, bottomLeft: 4),
                             tint: MUIHsla(h: 0, s: 0, l: 0.5, a: 0.3), order: 0, shape: 0, sigma: 8, opacity: 0.8))
    scene.finalize()
    return scene
}

/// **2** (`LG-B`). A material record — the nine-argument spelling, a zero tail — renders today's
/// bytes: the readback equals the one stored before the tail existed, within one level (the
/// bytes are a GPU's). Mutation: take the glass branch when `glassFlags == 0` (the test
/// `b.glassFlags == 0u` for `(b.glassFlags & 1u) != 0u`), which draws a material through the glass arithmetic.
@Test @MainActor func aMaterialRecordWithAZeroTailRendersTodaysBytes() throws {
    let renderer = try glassRenderer()
    let pixels = try renderer.renderOffscreen(materialScene(), size: glassTargetSize(40, 16))
    let stored = [UInt8](try #require(Data(base64Encoded: materialBaseline.replacingOccurrences(of: "\n", with: ""))))
    try #require(stored.count == pixels.count)
    var worst = 0
    for i in 0..<pixels.count { worst = max(worst, abs(Int(pixels[i]) - Int(stored[i]))) }
    #expect(worst <= 1, "a material's pixels moved by \(worst) levels")
    #expect(renderer.lastGlassRecords == 0, "a material is not a glass")
}

private let fieldWidth = 60, fieldHeight = 40

/// **5b** (`LG-D`, `TE-AD`). The shader's glass branch equals `GlassReference` on a field that varies
/// on both axes, with the lens, the rim and a half opacity: a 60x40 rounded glass over 6-pixel
/// blocks of eight colours, σ = 8, band 10, depth 5. Mutations: weight `(1−t)` for `(1−t)²`; the
/// rim's light flipped; the sharp read taken at `p + n·d`.
@Test @MainActor func theGlassShaderMatchesTheReferenceOnATwoAxisField() throws {
    let renderer = try glassRenderer()
    let (w, h) = (fieldWidth, fieldHeight)
    let field = glassField(width: w, height: h)
    var scene = Scene()
    for r in field.rects { scene.insert(r) }
    let record = glassRecord(glassBounds(0, 0, Float(w), Float(h)), tint: glassHSLA(0.2, 0.4, 0.9, 0.35), radius: 14, sigma: 8,
                             opacity: 0.8, lensRim: true, lensDepth: 5, band: 10, rim: 0.5, press: 1, pressLift: 0.1,
                             members: [])
    scene.insert(record)
    scene.finalize()
    let pixels = try renderer.renderOffscreen(scene, size: glassTargetSize(w, h))
    let blurred = BackdropBlurReference.blur(field.pixels, width: w, height: h, sigma: 8)
    let ref = referenceRecord(record, tint: SIMD4(0.2, 0.4, 0.9, 0.35))
    var expected: [SIMD4<Float>] = []
    var effect: Float = 0
    for y in 0..<h { for x in 0..<w {
        let i = (y * w + x) * 4
        let b = SIMD4(blurred[i], blurred[i + 1], blurred[i + 2], blurred[i + 3])
        let g = GlassReference.shade(ref, x: Float(x) + 0.5, y: Float(y) + 0.5, blurred: b,
                                     sharp: { glassBilinear(field.pixels, width: w, height: h, x: $0, y: $1) })
        let dest = SIMD4(field.pixels[i], field.pixels[i + 1], field.pixels[i + 2], field.pixels[i + 3])
        expected.append(g + dest * (1 - g.w))
        var noLens = ref
        noLens.flags &= ~GlassReference.lensRimBit
        let plain = GlassReference.shade(noLens, x: Float(x) + 0.5, y: Float(y) + 0.5, blurred: b, sharp: { _, _ in b })
        effect = max(effect, (0..<3).map { abs(g[$0] - plain[$0]) }.max() ?? 0)
    } }
    let off = maxOff(pixels, width: w, expected: expected)
    print("LG theGlassShaderMatchesTheReference: worst \(off) levels, lens and rim effect \(effect * 255) levels")
    #expect(effect * 255 > 25, "the field makes the lens and rim visible (\(effect * 255) levels), or this test cannot fail")
    #expect(off <= 3, "worst channel \(off) levels off the reference")
}

/// **7** (`LG-C`). A tint composites source-over the blurred backdrop: red at alpha 0.3 over a
/// gray 0.5 field reads `0.3·red + 0.7·gray` within one level. Mutation: the tint under the base
/// (`base = B + (1 − B.a)·T`), which leaves the opaque gray alone.
@Test @MainActor func aTintCompositesSourceOverTheBase() throws {
    let renderer = try glassRenderer()
    var scene = Scene()
    scene.insert(glassSolid(glassBounds(0, 0, 40, 40), glassGray(0.5)))
    scene.insert(glassRecord(glassBounds(0, 0, 40, 40), tint: glassHSLA(1, 0, 0, 0.3), sigma: 8))
    scene.finalize()
    let pixels = try renderer.renderOffscreen(scene, size: glassTargetSize(40, 40))
    let got = glassPixel(pixels, 20, 20, width: 40)
    let expected: [Float] = [0.3 + 0.7 * 0.5, 0.7 * 0.5, 0.7 * 0.5, 1].map { $0 * 255 }
    for c in 0..<4 { #expect(abs(got[c] - expected[c]) <= 1.5, "channel \(c): \(got[c]) against \(expected[c])") }
}

/// **8** (`LG-G`). A single-member glass has a material's edge: with the lens and rim off, the same
/// rounded shape as a glass and as a material reads the same pixels over a field, edge
/// included. Mutation: read the fold (`members` slots) for a count of one.
@Test @MainActor func aSingleMemberGlassHasAMaterialsEdge() throws {
    let renderer = try glassRenderer()
    let (w, h) = (fieldWidth, fieldHeight)
    let field = glassField(width: w, height: h)
    let tint = glassHSLA(0.9, 0.9, 0.9, 0.4)
    func render(_ record: MUIBackdrop) throws -> [UInt8] {
        var scene = Scene()
        for r in field.rects { scene.insert(r) }
        scene.insert(record)
        scene.finalize()
        return try renderer.renderOffscreen(scene, size: glassTargetSize(w, h))
    }
    let box = glassBounds(5.3, 4.6, 48.4, 30.2)
    for (radius, ellipse) in [(Float(11.5), false), (0, false), (0, true)] {
        let glass = try render(glassRecord(box, tint: tint, radius: radius, ellipse: ellipse))
        let corners = MUICorners(topLeft: radius, topRight: radius, bottomRight: radius, bottomLeft: radius)
        let material = try render(MUIBackdrop(bounds: box, contentMask: glassWide, maskCornerRadii: glassSquare,
                                              cornerRadii: corners, tint: tint, order: 0, shape: ellipse ? 1 : 0,
                                              sigma: 8, opacity: 1))
        var worst = 0
        for i in 0..<glass.count { worst = max(worst, abs(Int(glass[i]) - Int(material[i]))) }
        #expect(worst <= 1, "radius \(radius) ellipse \(ellipse): a glass edge is \(worst) levels from a material's")
    }
}

/// **9** (`BB-A`, `LG-B`). A glass with an opacity is a half-weight composite of the whole layer over
/// the SHARP backdrop: `o·glass` over the destination, lens and rim included, not an opacity on the
/// tint alone. Mutation: apply the opacity to the tint only (`T · o + (1 − T.a·o)·B`).
@Test @MainActor func aGlassWithAnOpacityIsAHalfWeightCompositeOverTheSharpBackdrop() throws {
    let renderer = try glassRenderer()
    let (w, h) = (fieldWidth, fieldHeight)
    let field = glassField(width: w, height: h)
    func render(opacity: Float) throws -> [UInt8] {
        var scene = Scene()
        for r in field.rects { scene.insert(r) }
        scene.insert(glassRecord(glassBounds(0, 0, Float(w), Float(h)), tint: glassHSLA(1, 1, 1, 0.5), radius: 14, sigma: 8,
                                 opacity: opacity, lensRim: true, lensDepth: 5, band: 10, rim: 0.5))
        scene.finalize()
        return try renderer.renderOffscreen(scene, size: glassTargetSize(w, h))
    }
    let full = try render(opacity: 1), half = try render(opacity: 0.5)
    var worst: Float = 0
    for y in 0..<h { for x in 0..<w {
        let i = (y * w + x) * 4
        let d = (0..<3).map { field.pixels[i + $0] * 255 }
        let f = glassPixel(full, x, y, width: w)
        let hv = glassPixel(half, x, y, width: w)
        // The opaque destination: half weight is the mean of the full glass and the sharp backdrop.
        // (The full glass is opaque inside, so `o·G + (1 − o·G.a)·D` is `(G + D) / 2`.)
        if f[3] == 255 { for c in 0..<3 { worst = max(worst, abs(hv[c] - (f[c] + d[c]) / 2)) } }
    } }
    #expect(worst <= 2.5, "half opacity is not the mean of the glass and the sharp backdrop: \(worst) levels")
}

/// **10** (`LG-B`). Members are normalised to the record's bounds, so a transform moves them with
/// it: two circles of diameter 20 at local x 0 and 60 of an 80x20 blob, turned 90 degrees
/// (`x' = 60 − y, y' = x − 50`), cover screen (40, 20) and (40, 80) and not the gap between them
/// (40, 50) nor where the untransformed blob's second circle would be. Mutation: read the members
/// as absolute pixels (skip the `· whole` scale in `glass_member_sdf`).
@Test @MainActor func aGlassUnderATransformKeepsItsMembers() throws {
    let renderer = try glassRenderer()
    let (w, h) = (100, 140)
    var scene = Scene()
    scene.insert(glassSolid(glassBounds(0, 0, Float(w), Float(h)), glassRedHSLA))
    let turn = MUITransform(a: 0, b: 1, c: -1, d: 0, tx: 60, ty: -50, pixelScale: 1, _reserved: 0,
                            outerMask: glassBounds(0, 0, Float(w), Float(h)), outerMaskRadii: glassSquare)
    scene.insert(glassRecord(glassBounds(70, 10, 80, 20), tint: glassGray(1), sigma: 8, blendK: 0,
                             members: [(glassBounds(0, 0, 0.25, 1), glassSquare), (glassBounds(0.75, 0, 0.25, 1), glassSquare)],
                             ellipses: [true, true]),
                 transform: turn)
    scene.finalize()
    let pixels = try renderer.renderOffscreen(scene, size: glassTargetSize(w, h))
    // Local centres (80, 20) and (140, 20) land at (60 - 20, 80 - 50) = (40, 30) and (40, 90).
    let first = glassPixel(pixels, 40, 30, width: w), second = glassPixel(pixels, 40, 90, width: w)
    let gap = glassPixel(pixels, 40, 60, width: w), elsewhere = glassPixel(pixels, 70, 30, width: w)
    #expect(first == [255, 255, 255, 255] && second == [255, 255, 255, 255], "both circles follow the turn: \(first) \(second)")
    #expect(gap == [255, 0, 0, 255], "the gap between them stays the backdrop: \(gap)")
    #expect(elsewhere == [255, 0, 0, 255], "nothing where the untransformed blob would be: \(elsewhere)")
}

/// **12** (`LG-B`, `BB-E`). A scene holding only a glass is not empty and draws: it counts `L + 2`
/// passes (`L` the blur's downsample levels), one blur, one glass record and (the lens being on)
/// one sharp copy; a material beside it adds passes but no glass record. Mutation: skip the
/// `lastGlassRecords` count.
@Test @MainActor func aSceneHoldingOnlyAGlassIsNotEmptyAndCountsLPlusTwoPasses() throws {
    let renderer = try glassRenderer()
    var scene = Scene()
    scene.insert(glassRecord(glassBounds(0, 0, 64, 32), tint: glassGray(1, alpha: 0.5), radius: 8, sigma: 52,
                             lensRim: true, lensDepth: 4, band: 8, rim: 0.4))
    #expect(!scene.isEmpty)
    scene.finalize()
    let pixels = try renderer.renderOffscreen(scene, size: glassTargetSize(64, 32))
    let levels = BackdropBlurReference.levels(sigma: 52, maxLevel: Int(MUIBackdropBlurMaxLevel))
    #expect(renderer.lastBackdropPasses == levels + 2, "passes \(renderer.lastBackdropPasses), levels \(levels)")
    #expect(renderer.lastGlassRecords == 1 && renderer.lastBackdropBlurs == 1 && renderer.lastGlassSharpCopies == 1)
    #expect(glassPixel(pixels, 32, 16, width: 64)[3] > 100, "the glass draws its tint over a transparent frame")
    // A second frame resets the counter.
    var other = Scene()
    other.insert(glassSolid(glassBounds(0, 0, 8, 8), glassGray(1)))
    other.finalize()
    _ = try renderer.renderOffscreen(other, size: glassTargetSize(64, 32))
    #expect(renderer.lastGlassRecords == 0 && renderer.lastGlassSharpCopies == 0)
}

/// **4b** (`LG-G`, `TE-AD`). The shader's blob fold equals `GlassReference`'s: three members (a
/// circle, a rounded rect, a circle) at a blend radius of 18 over the two-axis field, no lens, no
/// rim, an opaque white tint over everything so the readback is the coverage `c`. Mutation:
/// `h·h·k·0.25` → `h·h·k·0.5` in `glass_smin`.
@Test @MainActor func theShaderFoldMatchesTheReference() throws {
    let renderer = try glassRenderer()
    let (w, h) = (96, 40)
    var scene = Scene()
    scene.insert(glassSolid(glassBounds(0, 0, Float(w), Float(h)), glassRedHSLA))
    let record = glassRecord(glassBounds(4, 6, 88, 28), tint: glassGray(1), sigma: 8, blendK: 18,
                             members: [(glassBounds(0, 0, 0.3, 1), glassSquare),
                                       (glassBounds(0.33, 0.2, 0.3, 0.6), MUICorners(topLeft: 0.2, topRight: 0.2, bottomRight: 0.2, bottomLeft: 0.2)),
                                       (glassBounds(0.7, 0, 0.3, 1), glassSquare)],
                             ellipses: [true, false, true])
    scene.insert(record)
    scene.finalize()
    let pixels = try renderer.renderOffscreen(scene, size: glassTargetSize(w, h))
    let ref = referenceRecord(record, tint: SIMD4(1, 1, 1, 1))
    var expected: [SIMD4<Float>] = []
    var partial = 0
    for y in 0..<h { for x in 0..<w {
        let red = SIMD4<Float>(1, 0, 0, 1)
        let g = GlassReference.shade(ref, x: Float(x) + 0.5, y: Float(y) + 0.5, blurred: red, sharp: { _, _ in red })
        expected.append(g + red * (1 - g.w))
        if g.w > 0.05 && g.w < 0.95 { partial += 1 }
    } }
    #expect(partial > 40, "the blob's edge and necks are antialiased (\(partial) partial pixels), or the fold is not exercised")
    let off = maxOff(pixels, width: w, expected: expected)
    #expect(off <= 3, "worst channel \(off) levels off the reference")
}

/// **11b** (`LG-L`, `BB-I`). A blob whose blur cannot be allocated draws its flat arm, one rect per
/// member: two square members at local x 0...20 and 60...80 of an 80x20 blob over red, white tint:
/// each member's middle is white and the gap between them is the sharp backdrop. Mutation: drop the
/// per-member branch in `encodeBackdrop` (the union's bounds are filled).
@Test @MainActor func aBlobThatCannotBlurDrawsOneFlatRectPerMember() throws {
    let renderer = try glassRenderer()
    var scene = Scene()
    scene.insert(glassSolid(glassBounds(0, 0, 100, 40), glassRedHSLA))
    scene.insert(glassRecord(glassBounds(10, 10, 80, 20), tint: glassGray(1), sigma: 8, blendK: 0,
                             members: [(glassBounds(0, 0, 0.25, 1), glassSquare), (glassBounds(0.75, 0, 0.25, 1), glassSquare)]))
    scene.finalize()
    renderer.backdropPoolFailsAllocation = true
    defer { renderer.backdropPoolFailsAllocation = false }
    let pixels = try renderer.renderOffscreen(scene, size: glassTargetSize(100, 40))
    #expect(renderer.lastBackdropBlurs == 0, "the blur was refused")
    #expect(glassPixel(pixels, 20, 20, width: 100) == [255, 255, 255, 255], "first member")
    #expect(glassPixel(pixels, 80, 20, width: 100) == [255, 255, 255, 255], "second member")
    #expect(glassPixel(pixels, 50, 20, width: 100) == [255, 0, 0, 255], "the gap is the sharp backdrop: \(glassPixel(pixels, 50, 20, width: 100))")
}

/// **15** (`LG-W`). A glass whose lens cannot get its sharp copy (the blur succeeded) draws the plain
/// material look: bit 1 of its flags is cleared, so its pixels equal the same record without the lens
/// and rim, not a lens reading the downsampled blurred texture at the wrong scale. The control run
/// (the copy succeeds) differs from it, so the lens is on in the arm that fails. Mutation: bind
/// `sharp ?? blurred` with the flags untouched (drop `Renderer.glassFlags`'s clearing).
@Test @MainActor func aGlassWhoseSharpCopyFailsDrawsWithoutItsLens() throws {
    let renderer = try glassRenderer()
    let (w, h) = (fieldWidth, fieldHeight)
    let field = glassField(width: w, height: h)
    func render(lens: Bool, sharpFails: Bool) throws -> [UInt8] {
        var scene = Scene()
        for r in field.rects { scene.insert(r) }
        scene.insert(glassRecord(glassBounds(0, 0, Float(w), Float(h)), tint: glassHSLA(0.2, 0.4, 0.9, 0.35), radius: 14, sigma: 52,
                                 lensRim: lens, lensDepth: 6, band: 12, rim: 0.6))
        scene.finalize()
        renderer.glassSharpCopyFailsAllocation = sharpFails
        defer { renderer.glassSharpCopyFailsAllocation = false }
        return try renderer.renderOffscreen(scene, size: glassTargetSize(w, h))
    }
    let failed = try render(lens: true, sharpFails: true)
    #expect(renderer.lastGlassSharpCopies == 0 && renderer.lastBackdropBlurs == 1, "only the sharp copy failed")
    let plain = try render(lens: false, sharpFails: false)
    let lensed = try render(lens: true, sharpFails: false)
    #expect(renderer.lastGlassSharpCopies == 1)
    var toPlain = 0, toLensed = 0
    for i in 0..<failed.count {
        toPlain = max(toPlain, abs(Int(failed[i]) - Int(plain[i])))
        toLensed = max(toLensed, abs(Int(failed[i]) - Int(lensed[i])))
    }
    #expect(toPlain <= 1, "a failed sharp copy is \(toPlain) levels from the plain look")
    #expect(toLensed > 8, "the lens is on in the control run (\(toLensed))")
    #expect(Renderer.glassFlags(3, haveSharpCopy: false) == 1 && Renderer.glassFlags(3, haveSharpCopy: true) == 3
            && Renderer.glassFlags(2, haveSharpCopy: false) == 2, "a material's flags are untouched")
}

/// **16** (`LG-W`). The glass coverage is taken in device pixels: under a uniform scale of 2 a box whose
/// local left edge is 5.1 lies at screen 10.2, so the pixel at 10 (centre 10.5) is 80 % covered
/// (`saturate(0.5 - d * s)`, d = -0.15 local, s = 2), not 65 % (the unscaled `saturate(0.5 - d)`). The
/// readback over red under an opaque white tint is `255 * c` in green; the same box as a material
/// agrees. Mutation: `d * s` for `d` in `glass_shade`'s coverage (shaders.metal).
@Test @MainActor func aGlassEdgeUnderAScaleIsCoveredInDevicePixels() throws {
    let renderer = try glassRenderer()
    let (w, h) = (80, 60)
    func render(glass: Bool) throws -> [UInt8] {
        var scene = Scene()
        scene.insert(glassSolid(glassBounds(0, 0, Float(w), Float(h)), glassRedHSLA))
        let scale = MUITransform(a: 2, b: 0, c: 0, d: 2, tx: 0, ty: 0, pixelScale: 2, _reserved: 0,
                                 outerMask: glassBounds(0, 0, Float(w), Float(h)), outerMaskRadii: glassSquare)
        let box = glassBounds(5.1, 5.1, 20, 12)
        if glass {
            scene.insert(glassRecord(box, tint: glassGray(1), sigma: 8), transform: scale)
        } else {
            scene.insert(MUIBackdrop(bounds: box, contentMask: glassWide, maskCornerRadii: glassSquare,
                                     cornerRadii: MUICorners(topLeft: 0, topRight: 0, bottomRight: 0, bottomLeft: 0),
                                     tint: glassGray(1), order: 0, shape: 0, sigma: 8, opacity: 1),
                         transform: scale)
        }
        scene.finalize()
        return try renderer.renderOffscreen(scene, size: glassTargetSize(w, h))
    }
    let glass = try render(glass: true), material = try render(glass: false)
    // Row 20 is inside the box (screen 10.2...34.2 vertically); the left edge is at 10.2, the right at 50.2.
    for (x, expected) in [(10, Float(0.8 * 255)), (50, Float(0.2 * 255))] {
        let g = glassPixel(glass, x, 20, width: w), m = glassPixel(material, x, 20, width: w)
        #expect(abs(g[1] - expected) <= 3, "column \(x): glass green \(g[1]), expected \(expected)")
        #expect(abs(g[1] - m[1]) <= 1, "column \(x): glass \(g[1]) against its material \(m[1])")
    }
}
