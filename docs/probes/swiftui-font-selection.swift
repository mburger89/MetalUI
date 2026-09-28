// SwiftUI probe: font selection by weight, italic and design (plan task 11,
// part 1, lane 2) — which face `Font.custom(_:size:).weight(_:)`,
// `.italic()` and `.system(size:weight:design:).italic()` draw, and whether
// CoreText's descriptor matching (the rule `FontResolver.resolve(_:)` uses)
// picks the same face.
//
// Evidence for ruling TE-W in
// docs/superpowers/2026-09-28-text-semantics-decisions.md, cited by arm id.
//
// HOW TO RUN (ruling SA-O's two forms), from the repository root:
//
//   xcrun swiftc docs/probes/swiftui-font-selection.swift -o /tmp/font-probe && /tmp/font-probe
//   /usr/bin/swift docs/probes/swiftui-font-selection.swift
//
// INSTRUMENT. RENDER only (`ImageRenderer` at scale 2 on white, headless — a
// locked screen measures the same): a SwiftUI font "draws" a face when
// `Text(s).font(f)` and `Text(s).font(Font(ctFace))` render identically
// (0 px), the candidates being every face of the family as CoreText lists it
// (`CTFontDescriptorCreateMatchingFontDescriptors` on the family name). The
// CoreText prediction ("ct") is: a descriptor of the family name plus the
// weight trait (`kCTFontFamilyNameAttribute` + `kCTFontTraitsAttribute`
// {`kCTFontWeightTrait`}), created at the size, then the italic symbolic
// trait (`CTFontCreateCopyWithSymbolicTraits`, kept upright when that answers
// nil); the system path uses the system UI font's descriptor plus the weight
// and design traits, then the italic trait.
//
// SEPARATING ARMS AND POSITIVE CONTROLS.
// - P0: two faces of one family differ (HelveticaNeue vs HelveticaNeue-Bold,
//   and upright vs italic) — so a 0-px match names one face.
// - W: nine weights × two slopes over eight families, each row naming the
//   face SwiftUI drew and the face CoreText predicts; a row whose drawn face
//   is "none" matched no listed face.
// - S: the system font at four weights × two slopes × four designs.
//
// RECORDED OUTPUT (2026-09-28, macOS 27.0, screen locked; compiled five times
// and interpreted once, byte-identical):
//
//     P0 HelveticaNeue vs HelveticaNeue-Bold: 4924px; vs HelveticaNeue-Italic: 3081px
//     W Helvetica Neue ultraLight: drawn=HelveticaNeue-UltraLight ct=HelveticaNeue-UltraLight
//     W Helvetica Neue thin: drawn=HelveticaNeue-Thin ct=HelveticaNeue-Thin
//     W Helvetica Neue light: drawn=HelveticaNeue-Light ct=HelveticaNeue-Light
//     W Helvetica Neue regular: drawn=HelveticaNeue ct=HelveticaNeue
//     W Helvetica Neue medium: drawn=HelveticaNeue-Medium ct=HelveticaNeue-Medium
//     W Helvetica Neue semibold: drawn=HelveticaNeue-Medium ct=HelveticaNeue-Medium
//     W Helvetica Neue bold: drawn=HelveticaNeue-Bold ct=HelveticaNeue-Bold
//     W Helvetica Neue heavy: drawn=HelveticaNeue-Bold ct=HelveticaNeue-Bold
//     W Helvetica Neue black: drawn=HelveticaNeue-CondensedBlack ct=HelveticaNeue-CondensedBlack
//     W Helvetica Neue ultraLight italic: drawn=HelveticaNeue-UltraLightItalic ct=HelveticaNeue-UltraLightItalic
//     W Helvetica Neue thin italic: drawn=HelveticaNeue-ThinItalic ct=HelveticaNeue-ThinItalic
//     W Helvetica Neue light italic: drawn=HelveticaNeue-LightItalic ct=HelveticaNeue-LightItalic
//     W Helvetica Neue regular italic: drawn=HelveticaNeue-Italic ct=HelveticaNeue-Italic
//     W Helvetica Neue medium italic: drawn=HelveticaNeue-MediumItalic ct=HelveticaNeue-MediumItalic
//     W Helvetica Neue semibold italic: drawn=HelveticaNeue-MediumItalic ct=HelveticaNeue-MediumItalic
//     W Helvetica Neue bold italic: drawn=HelveticaNeue-BoldItalic ct=HelveticaNeue-BoldItalic
//     W Helvetica Neue heavy italic: drawn=HelveticaNeue-BoldItalic ct=HelveticaNeue-BoldItalic
//     W Helvetica Neue black italic: drawn=HelveticaNeue-CondensedBlack ct=HelveticaNeue-CondensedBlack
//     W Avenir Next ultraLight: drawn=AvenirNext-UltraLight ct=AvenirNext-UltraLight
//     W Avenir Next thin: drawn=AvenirNext-UltraLight ct=AvenirNext-UltraLight
//     W Avenir Next light: drawn=AvenirNext-Regular ct=AvenirNext-Regular
//     W Avenir Next regular: drawn=AvenirNext-Regular ct=AvenirNext-Regular
//     W Avenir Next medium: drawn=AvenirNext-Medium ct=AvenirNext-Medium
//     W Avenir Next semibold: drawn=AvenirNext-DemiBold ct=AvenirNext-DemiBold
//     W Avenir Next bold: drawn=AvenirNext-Bold ct=AvenirNext-Bold
//     W Avenir Next heavy: drawn=AvenirNext-Heavy ct=AvenirNext-Heavy
//     W Avenir Next black: drawn=AvenirNext-Heavy ct=AvenirNext-Heavy
//     W Avenir Next ultraLight italic: drawn=AvenirNext-UltraLightItalic ct=AvenirNext-UltraLightItalic
//     W Avenir Next thin italic: drawn=AvenirNext-UltraLightItalic ct=AvenirNext-UltraLightItalic
//     W Avenir Next light italic: drawn=AvenirNext-UltraLightItalic ct=AvenirNext-UltraLightItalic
//     W Avenir Next regular italic: drawn=AvenirNext-Italic ct=AvenirNext-Italic
//     W Avenir Next medium italic: drawn=AvenirNext-MediumItalic ct=AvenirNext-MediumItalic
//     W Avenir Next semibold italic: drawn=AvenirNext-DemiBoldItalic ct=AvenirNext-DemiBoldItalic
//     W Avenir Next bold italic: drawn=AvenirNext-BoldItalic ct=AvenirNext-BoldItalic
//     W Avenir Next heavy italic: drawn=AvenirNext-HeavyItalic ct=AvenirNext-HeavyItalic
//     W Avenir Next black italic: drawn=AvenirNext-HeavyItalic ct=AvenirNext-HeavyItalic
//     W Avenir ultraLight: drawn=Avenir-Light ct=Avenir-Light
//     W Avenir thin: drawn=Avenir-Light ct=Avenir-Light
//     W Avenir light: drawn=Avenir-Light ct=Avenir-Light
//     W Avenir regular: drawn=Avenir-Book ct=Avenir-Book
//     W Avenir medium: drawn=Avenir-Medium ct=Avenir-Medium
//     W Avenir semibold: drawn=Avenir-Medium ct=Avenir-Medium
//     W Avenir bold: drawn=Avenir-Heavy ct=Avenir-Heavy
//     W Avenir heavy: drawn=Avenir-Heavy ct=Avenir-Heavy
//     W Avenir black: drawn=Avenir-Black ct=Avenir-Black
//     W Avenir ultraLight italic: drawn=Avenir-LightOblique ct=Avenir-LightOblique
//     W Avenir thin italic: drawn=Avenir-LightOblique ct=Avenir-LightOblique
//     W Avenir light italic: drawn=Avenir-LightOblique ct=Avenir-LightOblique
//     W Avenir regular italic: drawn=Avenir-BookOblique ct=Avenir-BookOblique
//     W Avenir medium italic: drawn=Avenir-MediumOblique ct=Avenir-MediumOblique
//     W Avenir semibold italic: drawn=Avenir-MediumOblique ct=Avenir-MediumOblique
//     W Avenir bold italic: drawn=Avenir-HeavyOblique ct=Avenir-HeavyOblique
//     W Avenir heavy italic: drawn=Avenir-HeavyOblique ct=Avenir-HeavyOblique
//     W Avenir black italic: drawn=Avenir-BlackOblique ct=Avenir-BlackOblique
//     W Futura ultraLight: drawn=Futura-Medium ct=Futura-Medium
//     W Futura thin: drawn=Futura-Medium ct=Futura-Medium
//     W Futura light: drawn=Futura-Medium ct=Futura-Medium
//     W Futura regular: drawn=Futura-Medium ct=Futura-Medium
//     W Futura medium: drawn=Futura-Medium ct=Futura-Medium
//     W Futura semibold: drawn=Futura-Medium ct=Futura-Medium
//     W Futura bold: drawn=Futura-Bold ct=Futura-Bold
//     W Futura heavy: drawn=Futura-Bold ct=Futura-Bold
//     W Futura black: drawn=Futura-CondensedExtraBold ct=Futura-CondensedExtraBold
//     W Futura ultraLight italic: drawn=Futura-MediumItalic ct=Futura-MediumItalic
//     W Futura thin italic: drawn=Futura-MediumItalic ct=Futura-MediumItalic
//     W Futura light italic: drawn=Futura-MediumItalic ct=Futura-MediumItalic
//     W Futura regular italic: drawn=Futura-MediumItalic ct=Futura-MediumItalic
//     W Futura medium italic: drawn=Futura-MediumItalic ct=Futura-MediumItalic
//     W Futura semibold italic: drawn=Futura-MediumItalic ct=Futura-MediumItalic
//     W Futura bold italic: drawn=Futura-Bold ct=Futura-Bold
//     W Futura heavy italic: drawn=Futura-Bold ct=Futura-Bold
//     W Futura black italic: drawn=Futura-CondensedExtraBold ct=Futura-CondensedExtraBold
//     W Gill Sans ultraLight: drawn=GillSans-Light ct=GillSans-Light
//     W Gill Sans thin: drawn=GillSans-Light ct=GillSans-Light
//     W Gill Sans light: drawn=GillSans-Light ct=GillSans-Light
//     W Gill Sans regular: drawn=GillSans ct=GillSans
//     W Gill Sans medium: drawn=GillSans-SemiBold ct=GillSans-SemiBold
//     W Gill Sans semibold: drawn=GillSans-SemiBold ct=GillSans-SemiBold
//     W Gill Sans bold: drawn=GillSans-Bold ct=GillSans-Bold
//     W Gill Sans heavy: drawn=GillSans-UltraBold ct=GillSans-UltraBold
//     W Gill Sans black: drawn=GillSans-UltraBold ct=GillSans-UltraBold
//     W Gill Sans ultraLight italic: drawn=GillSans-LightItalic ct=GillSans-LightItalic
//     W Gill Sans thin italic: drawn=GillSans-LightItalic ct=GillSans-LightItalic
//     W Gill Sans light italic: drawn=GillSans-LightItalic ct=GillSans-LightItalic
//     W Gill Sans regular italic: drawn=GillSans-Italic ct=GillSans-Italic
//     W Gill Sans medium italic: drawn=GillSans-SemiBoldItalic ct=GillSans-SemiBoldItalic
//     W Gill Sans semibold italic: drawn=GillSans-SemiBoldItalic ct=GillSans-SemiBoldItalic
//     W Gill Sans bold italic: drawn=GillSans-BoldItalic ct=GillSans-BoldItalic
//     W Gill Sans heavy italic: drawn=GillSans-BoldItalic ct=GillSans-BoldItalic
//     W Gill Sans black italic: drawn=GillSans-BoldItalic ct=GillSans-BoldItalic
//     W American Typewriter ultraLight: drawn=AmericanTypewriter-Light ct=AmericanTypewriter-Light
//     W American Typewriter thin: drawn=AmericanTypewriter-Light ct=AmericanTypewriter-Light
//     W American Typewriter light: drawn=AmericanTypewriter-Light ct=AmericanTypewriter-Light
//     W American Typewriter regular: drawn=AmericanTypewriter ct=AmericanTypewriter
//     W American Typewriter medium: drawn=AmericanTypewriter-Semibold ct=AmericanTypewriter-Semibold
//     W American Typewriter semibold: drawn=AmericanTypewriter-Semibold ct=AmericanTypewriter-Semibold
//     W American Typewriter bold: drawn=AmericanTypewriter-Bold ct=AmericanTypewriter-Bold
//     W American Typewriter heavy: drawn=AmericanTypewriter-Bold ct=AmericanTypewriter-Bold
//     W American Typewriter black: drawn=AmericanTypewriter-Bold ct=AmericanTypewriter-Bold
//     W American Typewriter ultraLight italic: drawn=AmericanTypewriter-Light ct=AmericanTypewriter-Light
//     W American Typewriter thin italic: drawn=AmericanTypewriter-Light ct=AmericanTypewriter-Light
//     W American Typewriter light italic: drawn=AmericanTypewriter-Light ct=AmericanTypewriter-Light
//     W American Typewriter regular italic: drawn=AmericanTypewriter ct=AmericanTypewriter
//     W American Typewriter medium italic: drawn=AmericanTypewriter-Semibold ct=AmericanTypewriter-Semibold
//     W American Typewriter semibold italic: drawn=AmericanTypewriter-Semibold ct=AmericanTypewriter-Semibold
//     W American Typewriter bold italic: drawn=AmericanTypewriter-Bold ct=AmericanTypewriter-Bold
//     W American Typewriter heavy italic: drawn=AmericanTypewriter-Bold ct=AmericanTypewriter-Bold
//     W American Typewriter black italic: drawn=AmericanTypewriter-Bold ct=AmericanTypewriter-Bold
//     W Optima ultraLight: drawn=Optima-Regular ct=Optima-Regular
//     W Optima thin: drawn=Optima-Regular ct=Optima-Regular
//     W Optima light: drawn=Optima-Regular ct=Optima-Regular
//     W Optima regular: drawn=Optima-Regular ct=Optima-Regular
//     W Optima medium: drawn=Optima-Bold ct=Optima-Bold
//     W Optima semibold: drawn=Optima-Bold ct=Optima-Bold
//     W Optima bold: drawn=Optima-Bold ct=Optima-Bold
//     W Optima heavy: drawn=Optima-ExtraBlack ct=Optima-ExtraBlack
//     W Optima black: drawn=Optima-ExtraBlack ct=Optima-ExtraBlack
//     W Optima ultraLight italic: drawn=Optima-Italic ct=Optima-Italic
//     W Optima thin italic: drawn=Optima-Italic ct=Optima-Italic
//     W Optima light italic: drawn=Optima-Italic ct=Optima-Italic
//     W Optima regular italic: drawn=Optima-Italic ct=Optima-Italic
//     W Optima medium italic: drawn=Optima-BoldItalic ct=Optima-BoldItalic
//     W Optima semibold italic: drawn=Optima-BoldItalic ct=Optima-BoldItalic
//     W Optima bold italic: drawn=Optima-BoldItalic ct=Optima-BoldItalic
//     W Optima heavy italic: drawn=Optima-BoldItalic ct=Optima-BoldItalic
//     W Optima black italic: drawn=Optima-BoldItalic ct=Optima-BoldItalic
//     W Baskerville ultraLight: drawn=Baskerville ct=Baskerville
//     W Baskerville thin: drawn=Baskerville ct=Baskerville
//     W Baskerville light: drawn=Baskerville ct=Baskerville
//     W Baskerville regular: drawn=Baskerville ct=Baskerville
//     W Baskerville medium: drawn=Baskerville-SemiBold ct=Baskerville-SemiBold
//     W Baskerville semibold: drawn=Baskerville-SemiBold ct=Baskerville-SemiBold
//     W Baskerville bold: drawn=Baskerville-Bold ct=Baskerville-Bold
//     W Baskerville heavy: drawn=Baskerville-Bold ct=Baskerville-Bold
//     W Baskerville black: drawn=Baskerville-Bold ct=Baskerville-Bold
//     W Baskerville ultraLight italic: drawn=Baskerville-Italic ct=Baskerville-Italic
//     W Baskerville thin italic: drawn=Baskerville-Italic ct=Baskerville-Italic
//     W Baskerville light italic: drawn=Baskerville-Italic ct=Baskerville-Italic
//     W Baskerville regular italic: drawn=Baskerville-Italic ct=Baskerville-Italic
//     W Baskerville medium italic: drawn=Baskerville-SemiBoldItalic ct=Baskerville-SemiBoldItalic
//     W Baskerville semibold italic: drawn=Baskerville-SemiBoldItalic ct=Baskerville-SemiBoldItalic
//     W Baskerville bold italic: drawn=Baskerville-BoldItalic ct=Baskerville-BoldItalic
//     W Baskerville heavy italic: drawn=Baskerville-BoldItalic ct=Baskerville-BoldItalic
//     W Baskerville black italic: drawn=Baskerville-BoldItalic ct=Baskerville-BoldItalic
//     W rows=144 agree=144
//     N Helvetica Neue italic: drawn=HelveticaNeue-Italic ct=HelveticaNeue-Italic
//     N HelveticaNeue-Bold italic: drawn=HelveticaNeue-BoldItalic ct=HelveticaNeue-BoldItalic
//     N Avenir Next italic: drawn=AvenirNext-Italic ct=AvenirNext-Italic
//     N Gill Sans italic: drawn=GillSans-Italic ct=GillSans-Italic
//     N Optima italic: drawn=Optima-Italic ct=Optima-Italic
//     N American Typewriter italic: drawn=AmericanTypewriter ct=AmericanTypewriter
//     N Futura italic: drawn=Futura-MediumItalic ct=Futura-MediumItalic
//     S default ultraLight: ct=.SFNS-Ultralight differsFromSwiftUI=0px
//     S default ultraLight italic: ct=.SFNS-UltralightItalic differsFromSwiftUI=0px
//     S default regular: ct=.SFNS-Regular differsFromSwiftUI=0px
//     S default regular italic: ct=.SFNS-RegularItalic differsFromSwiftUI=0px
//     S default semibold: ct=.SFNS-Semibold differsFromSwiftUI=0px
//     S default semibold italic: ct=.SFNS-SemiboldItalic differsFromSwiftUI=0px
//     S default black: ct=.SFNS-Black differsFromSwiftUI=0px
//     S default black italic: ct=.SFNS-BlackItalic differsFromSwiftUI=0px
//     S serif ultraLight: ct=.NewYork-Regular differsFromSwiftUI=0px
//     S serif ultraLight italic: ct=.NewYork-RegularItalic differsFromSwiftUI=0px
//     S serif regular: ct=.NewYork-Regular differsFromSwiftUI=0px
//     S serif regular italic: ct=.NewYork-RegularItalic differsFromSwiftUI=0px
//     S serif semibold: ct=.NewYork-Semibold differsFromSwiftUI=0px
//     S serif semibold italic: ct=.NewYork-SemiboldItalic differsFromSwiftUI=0px
//     S serif black: ct=.NewYork-Black differsFromSwiftUI=0px
//     S serif black italic: ct=.NewYork-BlackItalic differsFromSwiftUI=0px
//     S rounded ultraLight: ct=.AppleSystemUIFontRounded-Ultralight differsFromSwiftUI=0px
//     S rounded ultraLight italic: ct=.AppleSystemUIFontRounded-Ultralight differsFromSwiftUI=0px
//     S rounded regular: ct=.AppleSystemUIFontRounded-Regular differsFromSwiftUI=0px
//     S rounded regular italic: ct=.AppleSystemUIFontRounded-Regular differsFromSwiftUI=0px
//     S rounded semibold: ct=.AppleSystemUIFontRounded-Semibold differsFromSwiftUI=0px
//     S rounded semibold italic: ct=.AppleSystemUIFontRounded-Semibold differsFromSwiftUI=0px
//     S rounded black: ct=.AppleSystemUIFontRounded-Black differsFromSwiftUI=0px
//     S rounded black italic: ct=.AppleSystemUIFontRounded-Black differsFromSwiftUI=0px
//     S monospaced ultraLight: ct=.AppleSystemUIFontMonospaced-Light differsFromSwiftUI=0px
//     S monospaced ultraLight italic: ct=.AppleSystemUIFontMonospaced-LightItalic differsFromSwiftUI=0px
//     S monospaced regular: ct=.AppleSystemUIFontMonospaced-Regular differsFromSwiftUI=0px
//     S monospaced regular italic: ct=.AppleSystemUIFontMonospaced-RegularItalic differsFromSwiftUI=0px
//     S monospaced semibold: ct=.AppleSystemUIFontMonospaced-Semibold differsFromSwiftUI=0px
//     S monospaced semibold italic: ct=.AppleSystemUIFontMonospaced-SemiboldItalic differsFromSwiftUI=0px
//     S monospaced black: ct=.AppleSystemUIFontMonospaced-Heavy differsFromSwiftUI=0px
//     S monospaced black italic: ct=.AppleSystemUIFontMonospaced-HeavyItalic differsFromSwiftUI=0px
//     S rows=32 agree=32
//
// READING.
// - W 144/144, N 7/7, S 32/32: SwiftUI draws exactly the face CoreText's
//   descriptor matching predicts. A custom font's weight is a family-name +
//   weight-trait descriptor (not the named face's descriptor with a weight:
//   that keeps the named face), its italic the descriptor's symbolic trait
//   (Avenir Next light italic draws UltraLightItalic where slanting the
//   upright Regular would draw Italic — the one row the first draft of this
//   probe, which slanted the created font, got wrong). The system font slants
//   the created font instead (slanting its descriptor drew another face in
//   15 of S's 32 rows).
// - No synthesis: American Typewriter (no italic face) stays upright; a
//   width the family lacks is not faked (Helvetica Neue black draws
//   CondensedBlack, its only 0.62 face; heavy draws Bold, not CondensedBlack).
// - CoreText's "nearest" is its own: Helvetica Neue heavy (0.56) draws Bold
//   (0.4) over CondensedBlack (0.62), Avenir Next light (-0.4) Regular (0)
//   over UltraLight (-0.8).

import AppKit
import CoreText
import SwiftUI

let sample = "Hamburgefonstiv 0123"

@MainActor
func bitmap(_ view: some View) -> (bytes: [UInt8], w: Int, h: Int) {
    let r = ImageRenderer(content: view.frame(width: 300, height: 40, alignment: .topLeading).background(Color.white))
    r.scale = 2
    guard let cg = r.cgImage else { return ([], 0, 0) }
    let w = cg.width, h = cg.height
    var bytes = [UInt8](repeating: 0, count: w * h * 4)
    let ctx = CGContext(data: &bytes, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                        space: CGColorSpaceCreateDeviceRGB(),
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
    return (bytes, w, h)
}

func differing(_ a: (bytes: [UInt8], w: Int, h: Int), _ b: (bytes: [UInt8], w: Int, h: Int)) -> Int {
    guard a.w == b.w, a.h == b.h else { return Int.max }
    var n = 0
    for i in stride(from: 0, to: a.bytes.count, by: 4) where a.bytes[i] != b.bytes[i]
        || a.bytes[i + 1] != b.bytes[i + 1] || a.bytes[i + 2] != b.bytes[i + 2] { n += 1 }
    return n
}

func ps(_ f: CTFont) -> String { CTFontCopyPostScriptName(f) as String }

func faces(of family: String) -> [String] {
    let d = CTFontDescriptorCreateWithAttributes([kCTFontFamilyNameAttribute: family] as CFDictionary)
    let ms = (CTFontDescriptorCreateMatchingFontDescriptors(d, nil) as? [CTFontDescriptor]) ?? []
    return ms.map { CTFontDescriptorCopyAttribute($0, kCTFontNameAttribute) as! String }
}

func predictedCustom(_ family: String, size: CGFloat, weight: Double?, italic: Bool) -> CTFont {
    let named = CTFontCreateWithName(family as CFString, size, nil)
    var descriptor = CTFontCopyFontDescriptor(named)
    if let weight {
        descriptor = CTFontDescriptorCreateWithAttributes([
            kCTFontFamilyNameAttribute: CTFontCopyFamilyName(named),
            kCTFontTraitsAttribute: [kCTFontWeightTrait: weight],
        ] as CFDictionary)
    }
    if italic, let slanted = CTFontDescriptorCreateCopyWithSymbolicTraits(descriptor, .traitItalic, .traitItalic) {
        descriptor = slanted
    }
    return CTFontCreateWithFontDescriptor(descriptor, size, nil)
}

func predictedSystem(size: CGFloat, weight: Double?, design: String?, italic: Bool) -> CTFont {
    let sys = CTFontCreateUIFontForLanguage(.system, size, nil)!
    var traits: [CFString: Any] = [:]
    if let weight { traits[kCTFontWeightTrait] = weight }
    if let design { traits["NSCTFontUIFontDesignTrait" as CFString] = design }
    var descriptor = CTFontCopyFontDescriptor(sys)
    if !traits.isEmpty {
        descriptor = CTFontDescriptorCreateCopyWithAttributes(descriptor, [kCTFontTraitsAttribute: traits] as CFDictionary)
    }
    let font = CTFontCreateWithFontDescriptor(descriptor, size, nil)
    // The system path slants the created font (arm S; slanting the
    // descriptor instead, as the custom path does, drew another face in 15
    // of S's 32 rows when this probe was written).
    return italic ? CTFontCreateCopyWithSymbolicTraits(font, 0, nil, .traitItalic, .traitItalic) ?? font : font
}

let weights: [(String, Font.Weight, Double)] = [
    ("ultraLight", .ultraLight, -0.8), ("thin", .thin, -0.6), ("light", .light, -0.4), ("regular", .regular, 0),
    ("medium", .medium, 0.23), ("semibold", .semibold, 0.3), ("bold", .bold, 0.4), ("heavy", .heavy, 0.56),
    ("black", .black, 0.62),
]

@MainActor func run() {
    // A warm-up render: the process's first `ImageRenderer` render of the
    // italic face occasionally differed by 2 px from every later one.
    for name in ["HelveticaNeue", "HelveticaNeue-Bold", "HelveticaNeue-Italic"] {
        _ = bitmap(Text(sample).font(Font(CTFontCreateWithName(name as CFString, 15, nil))))
    }
    // P0 controls
    let hn = bitmap(Text(sample).font(Font(CTFontCreateWithName("HelveticaNeue" as CFString, 15, nil))))
    let hb = bitmap(Text(sample).font(Font(CTFontCreateWithName("HelveticaNeue-Bold" as CFString, 15, nil))))
    let hi = bitmap(Text(sample).font(Font(CTFontCreateWithName("HelveticaNeue-Italic" as CFString, 15, nil))))
    print("P0 HelveticaNeue vs HelveticaNeue-Bold: \(differing(hn, hb))px; vs HelveticaNeue-Italic: \(differing(hn, hi))px")

    var agree = 0, rows = 0
    for family in ["Helvetica Neue", "Avenir Next", "Avenir", "Futura", "Gill Sans", "American Typewriter",
                   "Optima", "Baskerville"] {
        let candidates = faces(of: family)
        let rendered = candidates.map { ($0, bitmap(Text(sample).font(Font(CTFontCreateWithName($0 as CFString, 15, nil))))) }
        for italic in [false, true] {
            for (label, w, value) in weights {
                var font = Font.custom(family, size: 15).weight(w)
                if italic { font = font.italic() }
                let t = bitmap(Text(sample).font(font))
                let drawn = rendered.first { differing(t, $0.1) == 0 }?.0 ?? "none"
                let ct = ps(predictedCustom(family, size: 15, weight: value, italic: italic))
                rows += 1
                if drawn == ct { agree += 1 }
                print("W \(family) \(label)\(italic ? " italic" : ""): drawn=\(drawn) ct=\(ct)\(drawn == ct ? "" : " DIFF")")
            }
        }
    }
    print("W rows=\(rows) agree=\(agree)")

    // N: no weight, italic only — the named face slanted.
    for name in ["Helvetica Neue", "HelveticaNeue-Bold", "Avenir Next", "Gill Sans", "Optima", "American Typewriter", "Futura"] {
        let family = CTFontCopyFamilyName(CTFontCreateWithName(name as CFString, 15, nil)) as String
        let candidates = faces(of: family)
        let t = bitmap(Text(sample).font(Font.custom(name, size: 15).italic()))
        let drawn = candidates.first { differing(t, bitmap(Text(sample).font(Font(CTFontCreateWithName($0 as CFString, 15, nil))))) == 0 } ?? "none"
        let ct = ps(predictedCustom(name, size: 15, weight: nil, italic: true))
        print("N \(name) italic: drawn=\(drawn) ct=\(ct)\(drawn == ct ? "" : " DIFF")")
    }

    var sAgree = 0, sRows = 0
    let designs: [(String, Font.Design, String?)] = [("default", .default, nil), ("serif", .serif, "NSCTFontUIFontDesignSerif"),
                                                     ("rounded", .rounded, "NSCTFontUIFontDesignRounded"),
                                                     ("monospaced", .monospaced, "NSCTFontUIFontDesignMonospaced")]
    for (dl, d, key) in designs {
        for (label, w, value) in weights where ["ultraLight", "regular", "semibold", "black"].contains(label) {
            for italic in [false, true] {
                var font = Font.system(size: 13, weight: w, design: d)
                if italic { font = font.italic() }
                let t = bitmap(Text(sample).font(font))
                let ct = predictedSystem(size: 13, weight: value, design: key, italic: italic)
                let diff = differing(t, bitmap(Text(sample).font(Font(ct))))
                sRows += 1
                if diff == 0 { sAgree += 1 }
                print("S \(dl) \(label)\(italic ? " italic" : ""): ct=\(ps(ct)) differsFromSwiftUI=\(diff)px")
            }
        }
    }
    print("S rows=\(sRows) agree=\(sAgree)")
}

MainActor.assumeIsolated { run() }
