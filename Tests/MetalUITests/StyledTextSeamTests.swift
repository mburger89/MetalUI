import CoreText
import Foundation
import Metal
import Testing
import MetalUIDemoContent
import MetalUITextSystem
@testable import MetalUIPortableText
@testable import MetalUI
@testable import MetalUIText

// Rich text, lane 1 — the styled seam (rulings `RT-F`…`RT-J`, spec §4.1).
// Test 1.19 is the must-not-move pin for the plain path's work (`RT-M` item
// 1, moved to lane 1 by `RT-O` item 11).

/// A CoreText system over a cache the test can read, inside a window over the
/// main demo tree (the 1024-point square the fourteen offscreen images use).
@MainActor
private func demoWindow(_ system: CoreTextTextSystem) throws -> Window {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let platformWindow = try FakePlatformWindow(device: device, size: 1024)
    return Window(platformWindow: platformWindow, startsDisplayLink: false, textSystem: system) {
        demoContent()
    }
}

/// **1.19** (`RT-M` item 1, `RT-O` item 11). The main demo's first and warm
/// frames do the same shaping work as before rich text: `ShapingCache` misses
/// and lookups equal literals **recorded on `70ed000`'s code** (the merge of
/// PR #51, `feat/rich-text`'s base) before lane 1's first source change — so a
/// lane-1 regression in plain work cannot be baked into the pin. Green on
/// arrival by design. Mutation (lane 1): key the plain cache by `(string,
/// font, width)` without the options — the literals move; (lane 2, re-run):
/// route every `Text` through the styled path.
///
/// Recorded 2026-10-08 with `METALUI_RT_119_MEASURE=1` on `4a47f27` (its
/// `Sources/` byte-identical to `70ed000`'s), three runs alike: first frame
/// 1020 misses, 1544 lookups; warm frame 0 misses, 110 lookups.
@MainActor
@Test func theDemoDoesTheSameTextWorkAsBefore() throws {
    let system = CoreTextTextSystem()
    let window = try demoWindow(system)
    window.drawFrameIfNeeded()
    let firstMisses = system.cache.misses, firstLookups = system.cache.lookups
    try #require(firstMisses > 0, "set up: the demo shaped text")
    window.setNeedsRedraw()
    window.drawFrameIfNeeded()
    let warmMisses = system.cache.misses - firstMisses
    let warmLookups = system.cache.lookups - firstLookups
    if ProcessInfo.processInfo.environment["METALUI_RT_119_MEASURE"] == "1" {
        print("RT 1.19 first misses=\(firstMisses) lookups=\(firstLookups) warm misses=\(warmMisses) lookups=\(warmLookups)")
    }
    #expect(firstMisses == 1020, "first frame misses")
    #expect(firstLookups == 1544, "first frame lookups")
    #expect(warmMisses == 0, "warm frame misses")
    #expect(warmLookups == 110, "warm frame lookups")
    withExtendedLifetime(window) {}
}

// MARK: - Both systems over the three test faces

private let rtFontsDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    .deletingLastPathComponent().appendingPathComponent("Fonts")
private let rtFaceFiles = ["NotoSans-Regular.ttf", "NotoSansArabic-Regular.ttf", "SourceSans3-Regular.otf"]

/// One text system under test, by name.
private struct RTSystem {
    let name: String
    let system: any TextSystem
}

/// Runs `body` over the CoreText system and the portable one, the three test
/// faces registered with CoreText for the process (and unregistered after)
/// and with the portable resolver (Noto Sans its default, the other two in
/// its cascade).
@MainActor
private func withBothSystems(_ body: @MainActor (RTSystem) throws -> Void) throws {
    let urls = rtFaceFiles.map { rtFontsDirectory.appendingPathComponent($0) }
    for url in urls { CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil) }
    defer { for url in urls { CTFontManagerUnregisterFontsForURL(url as CFURL, .process, nil) } }
    let resolver = try PortableFontResolver(defaultFont: [UInt8](Data(contentsOf: urls[0])))
    try resolver.register([UInt8](Data(contentsOf: urls[1])))
    try resolver.register([UInt8](Data(contentsOf: urls[2])))
    try body(RTSystem(name: "CoreText", system: CoreTextTextSystem()))
    try body(RTSystem(name: "portable", system: PortableTextSystem(resolver: resolver)))
}

@MainActor
private func noto(_ system: any TextSystem, _ size: Double = 13) -> FontKey {
    system.resolveFont(FontDescriptor(family: "Noto Sans", size: size))
}

private func rtNote(_ message: String) -> Comment { Comment(rawValue: message) }

/// A styled text from `(string, style)` pieces.
private func styled(_ pieces: [(String, TextRunStyle)]) -> StyledText {
    StyledText(pieces.map(\.0).joined(),
               runs: pieces.map { StyledTextRun(length: $0.0.utf16.count, style: $0.1) })
}

/// The pair-kerned corpus string (`RT-O` item 7): Noto Sans kerns A–V and T–y.
private let kernedString = "AVAVAV To Ty"

/// Test 1.1/1.2's corpus: Latin, the pair-kerned string, Arabic, a hard
/// break, an emoji that falls back.
private let seamCorpus = [
    "The quick brown fox jumps over the lazy dog.",
    kernedString,
    "مرحبا بالعالم",
    "Ready\nSet\nGo",
    "a 😀 b",
]
private let seamWidths: [Double?] = [nil, 40, 0.5]
private let seamOptions = [
    TextLayoutOptions(),
    TextLayoutOptions(maxLines: 2, truncation: .tail),
    TextLayoutOptions(maxLines: 2, truncation: .head),
    TextLayoutOptions(maxLines: 2, truncation: .middle),
    TextLayoutOptions(alignment: .center),
]

/// **1.1** (`RT-F` item 3, `RT-O` item 7). A one-run styled text measures as
/// the plain calls do on both systems: widest line, total height, line
/// ranges, and every line `fontMetrics.lineHeight` tall — over the corpus ×
/// widths nil/40/0.5 × options. The pair-kerned string's plain width is below
/// the sum of its glyphs' lone advances (so its arm sees pair kerning).
/// Mutations: (a) CoreText line height from `CTLineGetTypographicBounds` —
/// the emoji arm; (b) CoreText always sets `kCTKernAttributeName` — the kern
/// arm (`K2`).
@MainActor
@Test func aOneRunStyledTextMeasuresAsThePlainCallsOnBothSystems() throws {
    try withBothSystems { rt in
        let system = rt.system
        let font = noto(system)
        let lone = kernedString.reduce(0.0) { $0 + system.measure(String($1), font: font, wrappingAt: nil).widestLine }
        try #require(system.measure(kernedString, font: font, wrappingAt: nil).widestLine < lone - 0.5,
                     rtNote("\(rt.name): the kerned string must be pair-kerned"))
        let lineHeight = system.fontMetrics(font).lineHeight
        for string in seamCorpus {
            let text = StyledText(string, style: TextRunStyle(font: font))
            for width in seamWidths {
                for options in seamOptions {
                    let plain = system.measure(string, font: font, wrappingAt: width, options: options)
                    let ranges = system.lineRanges(string, font: font, wrappingAt: width, options: options)
                    let measured = system.measure(text, wrappingAt: width, options: options)
                    let label = "\(rt.name) \(string.debugDescription) w=\(String(describing: width)) \(options)"
                    #expect(measured.widestLine == plain.widestLine, rtNote(label + " widest"))
                    #expect(measured.totalHeight == plain.totalHeight, rtNote(label + " total"))
                    #expect(measured.lines.map(\.range) == ranges, rtNote(label + " ranges"))
                    #expect(measured.lines.allSatisfy { $0.height == lineHeight }, rtNote(label + " heights"))
                }
            }
        }
    }
}

/// **1.2** (`RT-F` item 3). A one-run styled text places the plain glyphs on
/// both systems, every glyph in run 0, at scale 1 and 2 and a fractional
/// origin. Mutation: portable styled placement rounds the baseline before
/// scaling.
@MainActor
@Test func aOneRunStyledTextPlacesThePlainGlyphsOnBothSystems() throws {
    try withBothSystems { rt in
        let system = rt.system
        let font = noto(system)
        for string in seamCorpus {
            let text = StyledText(string, style: TextRunStyle(font: font))
            for width in seamWidths {
                for options in seamOptions {
                    for scale: Float in [1, 2] {
                        let origin = (x: 3.3, y: 7.6)
                        let plain = system.placeGlyphs(string, font: font, wrappingAt: width, options: options,
                                                       origin: origin, scaleFactor: scale)
                        let layout = system.layOut(text, wrappingAt: width, options: options, origin: origin,
                                                   scaleFactor: scale)
                        let label = "\(rt.name) \(string.debugDescription) w=\(String(describing: width)) x\(scale)"
                        #expect(!plain.isEmpty, rtNote(label + " set up"))
                        #expect(layout.glyphs.map(\.glyph) == plain, rtNote(label))
                        #expect(layout.glyphs.allSatisfy { $0.run == 0 }, rtNote(label + " runs"))
                    }
                }
            }
        }
    }
}

/// **1.3** (`RT-H` item 1; `C4`, `C4c`). A run boundary is not a break
/// opportunity: `"foo"` + `"bar"` (the second run raised 2 points, so the
/// advances are the plain ones) at `width("foobar") − 3` breaks where the plain
/// `"foobar"` breaks, on both systems. Mutation: portable marks `.allowed` at
/// each run boundary.
@MainActor
@Test func aRunBoundaryIsNotABreakOpportunity() throws {
    try withBothSystems { rt in
        let system = rt.system
        let font = noto(system)
        let width = system.measure("foobar", font: font, wrappingAt: nil).widestLine - 3
        let plain = system.lineRanges("foobar", font: font, wrappingAt: width)
        try #require(plain.count == 2, rtNote("\(rt.name): plain foobar breaks once at \(width): \(plain)"))
        try #require(plain[0] != 0..<3, rtNote("\(rt.name): the plain break is not at the run boundary"))
        let text = styled([("foo", TextRunStyle(font: font)), ("bar", TextRunStyle(font: font, baselineOffset: 2))])
        let measured = system.measure(text, wrappingAt: width, options: TextLayoutOptions())
        #expect(measured.lines.map(\.range) == plain, rtNote("\(rt.name): \(measured.lines.map(\.range))"))
    }
}

/// **1.4** (`RT-H` item 1; `C4d`). `"word "` + `"next"` (Source Sans 3) +
/// `" more"` at 40 breaks into UTF-16 ranges 0..<5, 5..<10, 10..<14 on both
/// systems — the breaks between runs fall at the spaces, as CoreText's
/// typesetter puts them. Mutation: portable re-shapes each line start in run
/// 0's face.
@MainActor
@Test func breaksBetweenRunsFallWhereCoreTextPutsThem() throws {
    try withBothSystems { rt in
        let system = rt.system
        let font = noto(system)
        let source = system.resolveFont(FontDescriptor(family: "Source Sans 3", size: 13))
        try #require(source != font)
        let text = styled([("word ", TextRunStyle(font: font)), ("next", TextRunStyle(font: source)),
                           (" more", TextRunStyle(font: font))])
        let measured = system.measure(text, wrappingAt: 40, options: TextLayoutOptions())
        #expect(measured.lines.map(\.range) == [0..<5, 5..<10, 10..<14],
                rtNote("\(rt.name): \(measured.lines.map(\.range))"))
    }
}

/// **1.5** (`RT-G` items 1–2; `C5`, `C6`). A 10-point and a 30-point run on
/// one line: the line is the 30-point line height, its baseline the 30-point
/// ascent. Wrapped (at `width("BBBB") + 1`) so line 1 holds only the 10-point run: heights
/// `[lh10, lh30]`, line 2's top `lh10`. Mutation: sum ascents instead of
/// taking the largest.
@MainActor
@Test func aMixedLineTakesTheLargestAscentAndDescent() throws {
    try withBothSystems { rt in
        let system = rt.system
        let small = noto(system, 10), large = noto(system, 30)
        let m10 = system.fontMetrics(small), m30 = system.fontMetrics(large)
        let mixed = system.measure(styled([("a ", TextRunStyle(font: small)), ("B", TextRunStyle(font: large))]),
                                   wrappingAt: nil, options: TextLayoutOptions())
        try #require(mixed.lines.count == 1)
        #expect(mixed.lines[0].height == m30.lineHeight, rtNote("\(rt.name) mixed height"))
        #expect(mixed.lines[0].baseline == m30.ascent, rtNote("\(rt.name) mixed baseline"))
        let width = system.measure("BBBB", font: large, wrappingAt: nil).widestLine + 1
        let wrapped = system.measure(styled([("aaaa ", TextRunStyle(font: small)), ("BBBB", TextRunStyle(font: large))]),
                                     wrappingAt: width, options: TextLayoutOptions())
        try #require(wrapped.lines.map(\.range) == [0..<5, 5..<9], rtNote("\(rt.name): \(wrapped.lines.map(\.range))"))
        #expect(wrapped.lines.map(\.height) == [m10.lineHeight, m30.lineHeight], rtNote(rt.name))
        #expect(wrapped.lines[1].top == m10.lineHeight, rtNote(rt.name))
        #expect(wrapped.lines[1].baseline == m10.lineHeight + m30.ascent, rtNote(rt.name))
        #expect(wrapped.totalHeight == m10.lineHeight + m30.lineHeight, rtNote(rt.name))
    }
}

/// **1.6** (`RT-G` item 1, `RT-H` item 4; `C7`, `C7d`). A run raised 5 points
/// and one lowered 5 both make the 16-point line `lineHeight + 5`; the raised
/// run's glyphs sit `5 × scale` device rows above the line's baseline, the
/// lowered run's below. Mutations: shrink the descent for a positive offset
/// (`descent − offset`) — the +5 arm; flip the glyph sign — the glyph arm.
@MainActor
@Test func aBaselineOffsetGrowsTheLineAndMovesItsGlyphs() throws {
    try withBothSystems { rt in
        let system = rt.system
        let font = noto(system, 16)
        let lineHeight = system.fontMetrics(font).lineHeight
        for offset in [5.0, -5.0] {
            let text = styled([("a", TextRunStyle(font: font)), ("b", TextRunStyle(font: font, baselineOffset: offset))])
            for scale: Float in [1, 2] {
                let layout = system.layOut(text, wrappingAt: nil, options: TextLayoutOptions(), origin: (x: 2, y: 3.4),
                                           scaleFactor: scale)
                let box = try #require(layout.measurement.lines.first)
                #expect(box.height == lineHeight + 5, rtNote("\(rt.name) offset \(offset) height"))
                let lineRow = Int(((3.4 + box.baseline) * Double(scale)).rounded())
                let glyphs = layout.glyphs
                try #require(glyphs.count == 2)
                #expect(glyphs[0].run == 0 && glyphs[1].run == 1)
                #expect(glyphs[0].glyph.baselineY == lineRow, rtNote("\(rt.name) plain run row"))
                #expect(glyphs[1].glyph.baselineY == lineRow - Int(offset * Double(scale)),
                        rtNote("\(rt.name) offset \(offset) x\(scale) row"))
                #expect(layout.segments.last?.baseline == 3.4 + box.baseline - offset,
                        rtNote("\(rt.name) segment baseline"))
            }
        }
    }
}

/// **1.7** (`RT-H` item 3; `C8`, `C8e`, `F1`). Kerning 4 adds 4 after every
/// glyph, the last included — the width is the plain one plus 4 × the glyph
/// count — and keeps a ligature (Noto Sans ligates "office": fewer glyphs than
/// letters). Mutation: skip the last glyph's kern.
@MainActor
@Test func kerningAddsAfterEveryGlyphAndKeepsLigatures() throws {
    try withBothSystems { rt in
        let system = rt.system
        let font = noto(system)
        for string in ["office", "abc", kernedString] {
            let plainGlyphs = system.placeGlyphs(string, font: font, wrappingAt: nil, origin: (0, 0), scaleFactor: 1)
            let plain = system.measure(string, font: font, wrappingAt: nil).widestLine
            let text = StyledText(string, style: TextRunStyle(font: font, kerning: 4))
            let measured = system.measure(text, wrappingAt: nil, options: TextLayoutOptions())
            #expect(abs(measured.widestLine - (plain + 4 * Double(plainGlyphs.count))) < 1e-9,
                    rtNote("\(rt.name) \(string): \(measured.widestLine) vs \(plain) + 4 × \(plainGlyphs.count)"))
            let kerned = system.layOut(text, wrappingAt: nil, options: TextLayoutOptions(), origin: (0, 0), scaleFactor: 1)
            #expect(kerned.glyphs.count == plainGlyphs.count, rtNote("\(rt.name) \(string) glyph count"))
        }
        let office = system.placeGlyphs("office", font: font, wrappingAt: nil, origin: (0, 0), scaleFactor: 1)
        try #require(office.count < 6, rtNote("\(rt.name): Noto Sans ligates office"))
    }
}

/// The glyph count of `string` drawn one character at a time — its unligated
/// count.
@MainActor
private func unligatedCount(_ string: String, _ font: FontKey, _ system: any TextSystem) -> Int {
    string.reduce(0) { $0 + system.placeGlyphs(String($1), font: font, wrappingAt: nil, origin: (0, 0),
                                               scaleFactor: 1).count }
}

/// **1.8** (`RT-H` item 3; `C8e`). Tracking 4 breaks ligatures on both
/// systems — "office" draws its unligated glyph count — and the two systems'
/// widths agree to 1e-3. Mutation: `HarfBuzzShaper.shape` ignores `features`.
@MainActor
@Test func trackingBreaksLigaturesOnBothSystems() throws {
    var widths: [String: Double] = [:]
    try withBothSystems { rt in
        let system = rt.system
        let font = noto(system)
        let text = StyledText("office", style: TextRunStyle(font: font, tracking: 4))
        let layout = system.layOut(text, wrappingAt: nil, options: TextLayoutOptions(), origin: (0, 0), scaleFactor: 1)
        let unligated = unligatedCount("office", font, system)
        try #require(unligated == 6)
        #expect(layout.glyphs.count == unligated, rtNote("\(rt.name): \(layout.glyphs.count) glyphs"))
        widths[rt.name] = layout.measurement.widestLine
    }
    let apple = try #require(widths["CoreText"]), portable = try #require(widths["portable"])
    #expect(abs(apple - portable) < 1e-3, rtNote("CoreText \(apple) vs portable \(portable)"))
}

/// The run of the ellipsis glyph in `layout`, and how many glyphs precede it.
@MainActor
private func ellipsis(in layout: StyledTextLayout, system: any TextSystem, fonts: [FontKey])
    -> (run: Int, before: Int)? {
    let ids = Set(fonts.compactMap { system.placeGlyphs("\u{2026}", font: $0, wrappingAt: nil, origin: (0, 0),
                                                         scaleFactor: 1).first?.key })
    guard let index = layout.glyphs.firstIndex(where: { glyph in
        ids.contains { $0.glyph == glyph.glyph.key.glyph && $0.font == glyph.glyph.key.font }
    }) else { return nil }
    return (layout.glyphs[index].run, index)
}

/// **1.9** (`RT-I`; `C13`, `C13b`, `C13d`, `C19`). The ellipsis takes the
/// run of the first character the truncation removes: tail cut inside the
/// second run → run 1; cut inside the first → run 0; head truncation → the
/// first character's run 0; middle → the run of the unit after the kept
/// prefix (one glyph per letter here, so the glyphs before the token count
/// it). A removed 30-point run makes the truncated 10-point line `lh30` tall
/// (`C19`: "aa aa" 10 pt + " BB" 30 pt under `lineLimit(1)` at 40).
/// Mutation: attribute the token with the last **kept** character's run —
/// the head arm and the `C19` arm redden.
@MainActor
@Test func theEllipsisTakesTheFirstRemovedCharactersRun() throws {
    try withBothSystems { rt in
        let system = rt.system
        let a = TextRunStyle(font: noto(system)), b = TextRunStyle(font: noto(system), baselineOffset: 1)
        @MainActor func truncate(_ pieces: [(String, TextRunStyle)], _ mode: TextTruncation, width: Double = 70)
            -> StyledTextLayout {
            system.layOut(styled(pieces), wrappingAt: width, options: TextLayoutOptions(maxLines: 1, truncation: mode),
                          origin: (0, 0), scaleFactor: 1)
        }
        let fonts = [noto(system)]
        let tailInB = ellipsis(in: truncate([("aa ", a), ("bbbb bbbb bbbb", b)], .tail), system: system, fonts: fonts)
        #expect(tailInB?.run == 1, rtNote("\(rt.name) tail in run 1: \(String(describing: tailInB))"))
        let tailInA = ellipsis(in: truncate([("aaaa aaaa aaaa aaaa", a), (" bbbb", b)], .tail), system: system,
                               fonts: fonts)
        #expect(tailInA?.run == 0, rtNote("\(rt.name) tail in run 0: \(String(describing: tailInA))"))
        let head = ellipsis(in: truncate([("aaaa ", a), ("bbbb bbbb bbbb bbbb", b)], .head), system: system,
                            fonts: fonts)
        #expect(head?.run == 0, rtNote("\(rt.name) head: \(String(describing: head))"))
        let middlePieces: [(String, TextRunStyle)] = [("aaaaaa", a), ("bbbbbbbbbbbb", b), ("cccccc", a)]
        let middle = ellipsis(in: truncate(middlePieces, .middle), system: system, fonts: fonts)
        let runOfUnit = styled(middlePieces).runOfUnit
        if let middle {
            #expect(middle.run == runOfUnit[middle.before], rtNote("\(rt.name) middle: \(middle)"))
        } else {
            Issue.record(rtNote("\(rt.name): the middle arm drew no ellipsis"))
        }
        let small = noto(system, 10), large = noto(system, 30)
        let c19 = system.measure(styled([("aa aa", TextRunStyle(font: small)), (" BB", TextRunStyle(font: large))]),
                                 wrappingAt: 40, options: TextLayoutOptions(maxLines: 1))
        #expect(c19.lines.map(\.height) == [system.fontMetrics(large).lineHeight],
                rtNote("\(rt.name) C19: \(c19.lines.map(\.height))"))
    }
}

/// **1.11** (`RT-J` item 2). The decoration metrics agree on both systems for
/// the three faces × five sizes, to 1e-4: underline position and thickness
/// from the `post` table, strikethrough at half the x-height — CoreText's
/// `CTFontGetUnderlinePosition`/`Thickness`/`XHeight` the reference.
/// Mutation: FreeType takes the strikethrough from OS/2 `yStrikeoutPosition`.
@MainActor
@Test func theDecorationMetricsAgreeOnBothSystems() throws {
    var answers: [String: [TextDecorationMetrics]] = [:]
    try withBothSystems { rt in
        var list: [TextDecorationMetrics] = []
        for family in ["Noto Sans", "Noto Sans Arabic", "Source Sans 3"] {
            for size in [9.0, 13, 17, 26, 31.5] {
                list.append(rt.system.decorationMetrics(rt.system.resolveFont(FontDescriptor(family: family, size: size))))
            }
        }
        answers[rt.name] = list
    }
    let apple = try #require(answers["CoreText"]), portable = try #require(answers["portable"])
    try #require(apple.count == 15 && portable.count == 15)
    var index = 0
    for family in ["Noto Sans", "Noto Sans Arabic", "Source Sans 3"] {
        let url = rtFontsDirectory.appendingPathComponent(rtFaceFiles[["Noto Sans", "Noto Sans Arabic", "Source Sans 3"].firstIndex(of: family)!])
        let descriptor = try #require((CTFontManagerCreateFontDescriptorsFromData(try Data(contentsOf: url) as CFData)
            as? [CTFontDescriptor])?.first)
        for size in [9.0, 13, 17, 26, 31.5] {
            let ct = CTFontCreateWithFontDescriptor(descriptor, CGFloat(size), nil)
            let expected = TextDecorationMetrics(underlinePosition: Double(CTFontGetUnderlinePosition(ct)),
                                                 underlineThickness: Double(CTFontGetUnderlineThickness(ct)),
                                                 strikethroughPosition: Double(CTFontGetXHeight(ct)) / 2)
            try #require(expected.underlinePosition < 0 && expected.underlineThickness > 0)
            for (name, got) in [("CoreText", apple[index]), ("portable", portable[index])] {
                let label = "\(name) \(family) \(size)"
                #expect(abs(got.underlinePosition - expected.underlinePosition) < 1e-4, rtNote(label + " position"))
                #expect(abs(got.underlineThickness - expected.underlineThickness) < 1e-4, rtNote(label + " thickness"))
                #expect(abs(got.strikethroughPosition - expected.strikethroughPosition) < 1e-4, rtNote(label + " strike"))
            }
            index += 1
        }
    }
}

/// **1.12** (`RT-J` item 3; `C9k`, `C9w`, `F4`). Segments span their advance,
/// kerning included; a line's visible extent leaves out its leading and
/// trailing whitespace and keeps interior whitespace, on both systems.
/// `"x   "`, `"   x"` and `"x"` + `"   "` + `"x"`, kerning 2 (3 on the middle
/// run). Mutation: include trailing whitespace in `visibleMaxX`.
@MainActor
@Test func segmentsSpanTheirAdvanceAndLinesKnowTheirVisibleExtent() throws {
    try withBothSystems { rt in
        let system = rt.system
        let font = noto(system)
        let k2 = TextRunStyle(font: font, kerning: 2), k3 = TextRunStyle(font: font, kerning: 3)
        let x = system.measure("x", font: font, wrappingAt: nil).widestLine
        let space = system.measure(" ", font: font, wrappingAt: nil).widestLine
        let origin = (x: 5.0, y: 1.0)
        @MainActor func lay(_ text: StyledText) -> StyledTextLayout {
            system.layOut(text, wrappingAt: nil, options: TextLayoutOptions(), origin: origin, scaleFactor: 2)
        }
        let trailing = lay(StyledText("x   ", style: k2))
        let t = try #require(trailing.measurement.lines.first)
        #expect(abs(t.width - (x + 3 * space + 8)) < 1e-9, rtNote("\(rt.name) trailing width"))
        #expect(t.visibleMinX == 0, rtNote("\(rt.name) trailing min"))
        #expect(abs(t.visibleMaxX - (x + 2)) < 1e-9, rtNote("\(rt.name) trailing max \(t.visibleMaxX)"))
        #expect(trailing.segments.count == 1)
        #expect(abs((trailing.segments.first?.minX ?? -1) - origin.x) < 1e-9)
        #expect(abs((trailing.segments.first?.maxX ?? -1) - (origin.x + t.width)) < 1e-9,
                rtNote("\(rt.name) the segment spans the trailing spaces"))
        let leading = lay(StyledText("   x", style: k2))
        let l = try #require(leading.measurement.lines.first)
        #expect(abs(l.visibleMinX - 3 * (space + 2)) < 1e-9, rtNote("\(rt.name) leading min \(l.visibleMinX)"))
        #expect(abs(l.visibleMaxX - l.width) < 1e-9, rtNote("\(rt.name) leading max"))
        let interior = lay(styled([("x", k2), ("   ", k3), ("x", k2)]))
        let i = try #require(interior.measurement.lines.first)
        #expect(abs(i.width - (2 * x + 3 * space + 4 + 9)) < 1e-9, rtNote("\(rt.name) interior width"))
        #expect(i.visibleMinX == 0 && abs(i.visibleMaxX - i.width) < 1e-9, rtNote("\(rt.name) interior extent"))
        #expect(interior.segments.map(\.run) == [0, 1, 2], rtNote("\(rt.name) \(interior.segments)"))
        if interior.segments.count == 3 {
            let s = interior.segments
            #expect(abs(s[0].maxX - (origin.x + x + 2)) < 1e-9 && abs(s[1].minX - s[0].maxX) < 1e-9
                    && abs(s[1].maxX - (s[1].minX + 3 * space + 9)) < 1e-9 && abs(s[2].minX - s[1].maxX) < 1e-9,
                    rtNote("\(rt.name) \(s)"))
        }
    }
}

/// **1.13**. Latin–Arabic–Latin with a run spanning the direction switch (the
/// Noto Sans Arabic run holds Arabic letters and European digits, which UAX #9
/// gives their own level): one segment per visual piece, in visual order, the
/// same count, order and extents (1e-3) on both systems. Mutation: emit
/// segments in logical order.
@MainActor
@Test func bidiRunsSplitIntoOneSegmentPerVisualPiece() throws {
    var answers: [String: [TextRunSegment]] = [:]
    try withBothSystems { rt in
        let system = rt.system
        let latin = TextRunStyle(font: noto(system))
        let arabic = TextRunStyle(font: system.resolveFont(FontDescriptor(family: "Noto Sans Arabic", size: 13)))
        let text = styled([("abc ", latin), ("مرحبا 123 بالعالم", arabic), (" def", latin)])
        let layout = system.layOut(text, wrappingAt: nil, options: TextLayoutOptions(), origin: (0, 0), scaleFactor: 1)
        answers[rt.name] = layout.segments
    }
    let apple = try #require(answers["CoreText"]), portable = try #require(answers["portable"])
    try #require(apple.count > 3, rtNote("the Arabic run splits into visual pieces: \(apple)"))
    #expect(apple.map(\.run) == portable.map(\.run), rtNote("\(apple) vs \(portable)"))
    #expect(zip(apple, portable).allSatisfy { abs($0.minX - $1.minX) < 1e-3 && abs($0.maxX - $1.maxX) < 1e-3 },
            rtNote("\(apple) vs \(portable)"))
    #expect(zip(apple.dropLast(), apple.dropFirst()).allSatisfy { $0.maxX <= $1.minX + 1e-9 },
            rtNote("visual order, left to right: \(apple)"))
}

/// **1.14** (`RT-F` item 5). A warm styled frame shapes nothing: the second
/// frame's `measure` + `layOut` over the same `StyledText` leaves
/// `ShapingCache.misses` unmoved, and the portable system answers its styled
/// measurement from its entry (counted); two styled texts with one string and
/// different run splits are two entries. Mutation: key the styled entry by
/// the string only — the split arm reddens.
@MainActor
@Test func aWarmStyledFrameShapesNothing() throws {
    let urls = rtFaceFiles.map { rtFontsDirectory.appendingPathComponent($0) }
    for url in urls { CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil) }
    defer { for url in urls { CTFontManagerUnregisterFontsForURL(url as CFURL, .process, nil) } }
    let apple = CoreTextTextSystem()
    let portable = PortableTextSystem(resolver: try PortableFontResolver(defaultFont: [UInt8](Data(contentsOf: urls[0]))))
    for system in [apple, portable] as [any TextSystem] {
        let font = noto(system)
        let one = styled([("foo", TextRunStyle(font: font)), ("bar", TextRunStyle(font: font, kerning: 1))])
        let other = styled([("fo", TextRunStyle(font: font)), ("obar", TextRunStyle(font: font, kerning: 1))])
        func frame(_ texts: [StyledText]) {
            system.beginFrame()
            for text in texts {
                _ = system.measure(text, wrappingAt: 100, options: TextLayoutOptions())
                _ = system.layOut(text, wrappingAt: 100, options: TextLayoutOptions(), origin: (0, 0), scaleFactor: 2)
            }
            system.endFrame()
        }
        frame([one])
        if system === apple {
            let misses = apple.cache.misses
            frame([one])
            #expect(apple.cache.misses == misses, "CoreText: a warm frame shapes nothing")
            frame([one, other])
            #expect(apple.cache.misses == misses + 1, "CoreText: another split is another entry")
        } else {
            let misses = portable.styledMisses, hits = portable.styledHits
            frame([one])
            #expect(portable.styledMisses == misses, "portable: a warm frame measures nothing")
            #expect(portable.styledHits > hits, "portable: the warm frame was answered from the entry")
            frame([one, other])
            #expect(portable.styledMisses == misses + 1, "portable: another split is another entry")
        }
    }
}

/// **1.15** (`RT-F` item 1). Run lengths that do not sum to the string's
/// UTF-16 count trap. Mutation: delete the precondition.
@Test func aStyledTextWhoseLengthsDoNotSumTraps() async {
    await #expect(processExitsWith: .failure) {
        let font = FontKey(resolvedPostScriptName: "X", size: 13, variations: [],
                           matrix: FontKey.Matrix(a: 1, b: 0, c: 0, d: 1, tx: 0, ty: 0))
        _ = StyledText("abc", runs: [StyledTextRun(length: 2, style: TextRunStyle(font: font))])
    }
}
