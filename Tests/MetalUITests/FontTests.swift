import CoreText
import Foundation
import Testing
import MetalUIPortableText
@testable import MetalUI
@testable import MetalUIText

// Plan task 11 part 1, lane 3 (spec rows 3.1–3.5, 3.9, 3.14, 3.15, 3.22;
// rulings TE-B, TE-E, TE-F, TE-G). Every literal is derived from the frame's
// own text system — its `resolveFont`, `fontMetrics` and `measure` — never
// typed from SwiftUI's numbers where MetalUI's line height differs
// (divergence 86). A row that reads a SwiftUI number says so.

let tePara = "The quick brown fox jumps over the lazy dog and keeps on running far away."

let teNotoURL = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    .deletingLastPathComponent().appendingPathComponent("Fonts/NotoSans-Regular.ttf")

/// A CoreText text system over its own cache — the default a `Frame` makes,
/// so its keys and answers are the frame's.
@MainActor
func teSystem() -> CoreTextTextSystem { CoreTextTextSystem() }

/// The portable system on Noto Sans, the seam tests' pairing.
@MainActor
func tePortableSystem() throws -> PortableTextSystem {
    PortableTextSystem(resolver: try PortableFontResolver(defaultFont: [UInt8](Data(contentsOf: teNotoURL))))
}

/// `content`'s first element's bounds, in a `controlRoot` 400 × `height`
/// (its first child at x = 0), through a reporting frame.
@MainActor
func teBounds<C: ElementGroup>(height: Float = 200, _ path: [Int] = [0, 0],
                               @ElementBuilder _ content: () -> C) throws -> Bounds<Pixels> {
    let frame = try controlRender(controlRoot(height: height) { content() }, height: height)
    return try controlBounds(frame, controlID(path))
}

/// The rounded size a one-line-or-wrapped `string` in `font` answers at
/// x = 0 when proposed `width` (nil: unwrapped).
@MainActor
func teExpectedSize(_ string: String, _ descriptor: FontDescriptor, width: Double? = nil,
                    options: TextLayoutOptions = TextLayoutOptions()) -> (width: Float, height: Float) {
    let system = teSystem()
    let key = system.resolveFont(descriptor)
    let m = system.measure(string, font: key, wrappingAt: width, options: options)
    let w = width.map { min($0, m.widestLine) } ?? m.widestLine
    return (Float(w.rounded()), Float(m.totalHeight.rounded()))
}

@MainActor
func teSize(_ b: Bounds<Pixels>) -> (width: Float, height: Float) {
    (b.size.width.value, b.size.height.value)
}

// MARK: - 3.1

/// **3.1.** Every text style is F1's macOS face: the eleven styles' seam
/// descriptors resolve to the system face at F1's (size, weight) — `.headline`
/// 13 bold, `.caption2` 10 medium, the rest regular — and a `Text` drawn in
/// each measures as that face does. `.system(_:)` spells the same fonts.
///
/// Red before: `Font` absent (does not compile at `35eb357`); on the skeleton
/// the rendered arm reads a styled `Text` at its size but not its weight.
/// Mutation **M3a**: title2 17 → 18.
@MainActor
@Test func aTextStyleResolvesToMacOSsFace() throws {
    let table: [(Font, Font.TextStyle, Double, Font.Weight?)] = [
        (.largeTitle, .largeTitle, 26, nil), (.title, .title, 22, nil), (.title2, .title2, 17, nil),
        (.title3, .title3, 15, nil), (.headline, .headline, 13, .bold), (.subheadline, .subheadline, 11, nil),
        (.body, .body, 13, nil), (.callout, .callout, 12, nil), (.footnote, .footnote, 10, nil),
        (.caption, .caption, 10, nil), (.caption2, .caption2, 10, .medium),
    ]
    try #require(table.count == Font.TextStyle.allCases.count)
    let system = teSystem()
    for (font, style, size, weight) in table {
        let expected = FontDescriptor(size: size, weight: weight?.value)
        #expect(system.resolveFont(font.descriptor()) == system.resolveFont(expected), "\(style)")
        #expect(system.resolveFont(Font.system(style).descriptor()) == system.resolveFont(expected), "\(style)")
        let drawn = teSize(try teBounds { Text("Hello, world").font(font) })
        let want = teExpectedSize("Hello, world", expected)
        #expect(drawn == want, "\(style): drew \(drawn), \(size) pt \(weight.map { "\($0.value)" } ?? "regular") is \(want)")
    }
    // The weight is real: the headline is wider than the body.
    try #require(teExpectedSize("Hello, world", FontDescriptor(size: 13, weight: 0.4)).width
                 != teExpectedSize("Hello, world", FontDescriptor(size: 13)).width)
}

// MARK: - 3.2, 3.3

/// **3.2.** A container's `.font(_:)` reaches a `Text` below it (F6a); a
/// `Text`'s own font wins (F6b); the nearest writer wins (F6e: `.font(.title)`
/// inside `.font(.caption)` reads the title).
///
/// Mutation **M3b**: the environment's font read before the text's own.
@MainActor
@Test func theEnvironmentFontReachesATextAndTheTextsOwnWins() throws {
    let title = teExpectedSize("Hg ag", FontDescriptor(size: 22))
    let caption = teExpectedSize("Hg ag", FontDescriptor(size: 10))
    let body = teExpectedSize("Hg ag", FontDescriptor(size: 13))
    try #require(Set([title.width, caption.width, body.width]).count == 3)
    #expect(teSize(try teBounds([0, 0, 0]) { Column { Text("Hg ag") }.font(.title) }) == title, "F6a")
    #expect(teSize(try teBounds([0, 0, 0]) { Column { Text("Hg ag").font(.caption) }.font(.title) }) == caption,
            "F6b")
    #expect(teSize(try teBounds([0, 0, 0, 0]) {
        Column { Column { Text("Hg ag") }.font(.title) }.font(.caption)
    }) == title, "F6e")
    #expect(teSize(try teBounds { Text("Hg ag") }) == body, "no writer: the default font")
}

/// **3.3.** `Text.font(nil)` is the default font, not the inherited one
/// (F6c) — and the default font follows `controlSize` (TE-F).
///
/// Mutation **M3c**: `nil` means inherit.
@MainActor
@Test func aTextsNilFontIsTheDefaultNotTheInheritedOne() throws {
    let body = teExpectedSize("Hg ag", FontDescriptor(size: 13))
    let small = teExpectedSize("Hg ag", FontDescriptor(size: 11))
    let title = teExpectedSize("Hg ag", FontDescriptor(size: 22))
    try #require(body != title && small != body)
    #expect(teSize(try teBounds([0, 0, 0]) { Column { Text("Hg ag").font(nil) }.font(.title) }) == body, "F6c")
    #expect(teSize(try teBounds([0, 0, 0]) { Column { Text("Hg ag") }.font(.title) }) == title, "control")
    #expect(teSize(try teBounds([0, 0, 0]) {
        Column { Text("Hg ag").font(nil) }.font(.title).controlSize(.small)
    }) == small, "the default font at .small")
}

// MARK: - 3.4

/// **3.4.** `fontWeight` and `italic` apply over whichever font the text
/// resolves: a container's weight over the text's own `.body` (F6d, which
/// SwiftUI draws as `.system(size: 13, weight: .bold)`, F6d'); the text's own
/// weight over its own font (F2f) and over the default; `Font.bold()` is
/// `weight(.bold)` (X1c); italic from the container or the text over a
/// family with an italic face (F4).
///
/// Mutation **M3d**: the environment's weight dropped under an own font.
@MainActor
@Test func fontWeightAndItalicApplyOverWhicheverFontTheTextResolves() throws {
    let s = "Hello, world"
    let bold = teExpectedSize(s, FontDescriptor(size: 13, weight: 0.4))
    let semibold = teExpectedSize(s, FontDescriptor(size: 13, weight: 0.3))
    let regular = teExpectedSize(s, FontDescriptor(size: 13))
    try #require(bold != regular && semibold != regular)
    #expect(teSize(try teBounds([0, 0, 0]) { Column { Text(s).font(.body) }.fontWeight(.bold) }) == bold, "F6d")
    #expect(teSize(try teBounds { Text(s).font(.system(size: 13)).fontWeight(.semibold) }) == semibold, "F2f")
    #expect(teSize(try teBounds { Text(s).fontWeight(.bold) }) == bold, "over the default font")
    #expect(teSize(try teBounds { Text(s).font(.body.bold()) }) == bold, "X1c")
    #expect(teSize(try teBounds([0, 0, 0]) {
        Column { Text(s).fontWeight(nil) }.fontWeight(.bold)
    }) == bold, "a nil own weight inherits the container's")

    // Italic: Helvetica Neue's italic face is as wide as its upright one, so
    // these arms compare sprites against the italic face drawn explicitly.
    let italic = FontDescriptor(family: "Helvetica Neue", size: 13, italic: true)
    let upright = FontDescriptor(family: "Helvetica Neue", size: 13)
    let system = teSystem()
    try #require(system.resolveFont(italic) != system.resolveFont(upright), "Helvetica Neue has an italic face")
    func drawn<C: ElementGroup>(@ElementBuilder _ content: () -> C) throws -> [[Float]] {
        teSprites(try controlRender(controlRoot { content() }))
    }
    let slanted = try drawn { Text(s).font(.custom("HelveticaNeue-Italic", size: 13)) }
    try #require(slanted != (try drawn { Text(s).font(.custom("Helvetica Neue", size: 13)) }))
    #expect(try drawn { Column { Text(s).font(.custom("Helvetica Neue", size: 13)) }.italic() } == slanted,
            "the container's italic over the text's own font")
    #expect(try drawn { Text(s).font(.custom("Helvetica Neue", size: 13)).italic() } == slanted,
            "the text's own italic")
    #expect(try drawn { Text(s).font(.custom("Helvetica Neue", size: 13).italic()) } == slanted, "Font.italic()")
}

// MARK: - 3.5

/// **3.5.** The legacy spelling is an explicit font (TE-B item 5):
/// `font(size: 22)` inside `.font(.title)` stays 22 — and, separating, inside
/// `.font(.caption)` too; `fontSize`/`fontFamily` read back 13/`nil`
/// unconfigured and an explicit font's otherwise, and a write sets an explicit
/// font.
///
/// Mutation **M3e**: `font(family:size:)` stores "inherit".
@MainActor
@Test func theLegacyFontSpellingIsAnExplicitFont() throws {
    let s22 = teExpectedSize("Hg ag", FontDescriptor(size: 22))
    let menlo = teExpectedSize("Hg ag", FontDescriptor(family: "Menlo", size: 12))
    #expect(teSize(try teBounds([0, 0, 0]) { Column { Text("Hg ag").font(size: 22) }.font(.title) }) == s22)
    #expect(teSize(try teBounds([0, 0, 0]) { Column { Text("Hg ag").font(size: 22) }.font(.caption) }) == s22,
            "the explicit size wins over the environment")
    #expect(teSize(try teBounds([0, 0, 0]) {
        Column { Text("Hg ag").font(family: "Menlo", size: 12) }.font(.caption)
    }) == menlo)

    let plain = Text("x")
    #expect(plain.fontSize == 13)
    #expect(plain.fontFamily == nil)
    #expect(Text("x").font(family: "Menlo", size: 12).fontFamily == "Menlo")
    #expect(Text("x").font(family: "Menlo", size: 12).fontSize == 12)
    #expect(Text("x").font(.title).fontSize == 22)
    var written = Text("Hg ag")
    written.fontSize = 22
    #expect(teSize(try teBounds([0, 0, 0]) { Column { written }.font(.caption) }) == s22, "a write is explicit")
    #expect(ProposalText("x").fontSize == 13)
    #expect(TextField("n", text: "") { _ in }.fontSize == 13)
    #expect(TextEditor(text: "") { _ in }.fontFamily == nil)
}

// MARK: - 3.9

/// **3.9.** No font responds to `dynamicTypeSize` — SwiftUI's macOS answer
/// (F7, ruling TE-E): `.body`, `.title`, the default font,
/// `.custom(_:size:relativeTo:)` and `.system(size:)` measure the same at
/// four sizes. **Positive control**: a 26 pt font measures differently.
///
/// Green by design (SwiftUI's answer, pinned). Mutation **M3i**: text styles
/// scaled by the size.
@MainActor
@Test func noFontRespondsToDynamicTypeSize() throws {
    let fonts: [(String, Font?)] = [("body", .body), ("title", .title), ("default", nil),
                                    ("relativeTo", .custom("Helvetica Neue", size: 17, relativeTo: .body)),
                                    ("system13", .system(size: 13))]
    try #require(teSize(try teBounds { Text("Hello, world").font(size: 26) })
                 != teSize(try teBounds { Text("Hello, world") }), "positive control")
    for (name, font) in fonts {
        func sized(_ size: DynamicTypeSize) throws -> (width: Float, height: Float) {
            teSize(try teBounds([0, 0, 0]) {
                Column { font.map { Text("Hello, world").font($0) } ?? Text("Hello, world") }.dynamicTypeSize(size)
            })
        }
        let large = try sized(.large)
        for size in [DynamicTypeSize.xSmall, .xxxLarge, .accessibility5] {
            #expect(try sized(size) == large, "\(name) at \(size)")
        }
    }
}

// MARK: - 3.14, 3.15 (metrics divergences)

/// A root `Text`'s measured (unrounded) width and stored width, in a 200-wide
/// frame where the root is centred at its answer (`CN-J`).
@MainActor
private func rootTextWidths(_ text: Text) -> (measured: Double, stored: Double) {
    var text = text
    let frame = Frame(contentSize: Size(width: Pixels(200), height: Pixels(100)), scaleFactor: 2)
    let rootID = GlobalElementID.child(of: nil, at: 0, name: nil)
    var pass = LayoutPass(frame: frame)
    let (root, _) = text.requestLayout(rootID, pass: &pass)
    frame.computeRootLayout(root: root)
    return (frame.tree.measuredWidth(root), frame.tree.layout(root).width)
}

/// **3.14. PINNED WRONG ON PURPOSE — divergence 60** (ruling TE-G item 1).
/// SwiftUI ceils a text's width to the `displayScale` pixel grid (M1: "Hello,
/// world" 72 at 13, 63 at 11 at scale 1; 62.5 at 11 at scale 2). MetalUI
/// answers the seam's unrounded widest line — read through `measuredWidth` —
/// and rounds only the stored rect's edges (divergence 77). At 13 both round
/// to 72, so the 11 pt arm separates at the rect (`TE-S` item 3): stored 62
/// where a `ceil` would give 63.
///
/// Mutation **M3m**: `ceil` in the measurement (both halves redden).
@MainActor
@Test func aTextAnswersItsUnroundedWidestLineWhereSwiftUICeilsToThePixelGrid() throws {
    let system = teSystem()
    for size in [13.0, 11.0] {
        let seam = system.measure("Hello, world", font: system.resolveFont(family: nil, size: size),
                                  wrappingAt: nil).widestLine
        try #require(seam != seam.rounded(.up), "the seam width is fractional at \(size)")
        let (measured, stored) = rootTextWidths(Text("Hello, world").font(size: size))
        #expect(measured == seam, "\(size) pt: measured \(measured), the seam's \(seam)")
        func edges(_ w: Double) -> Double { ((200 + w) / 2).rounded() - ((200 - w) / 2).rounded() }
        #expect(stored == edges(seam), "\(size) pt: stored \(stored)")
        if size == 11 {
            try #require(edges(seam) != edges(seam.rounded(.up)), "the 11 pt arm separates a ceil")
            #expect(stored == 62, "divergence 60: SwiftUI's 63 at scale 1")
        }
    }
}

/// **3.15. PINNED — divergence 86** (ruling TE-G item 3). MetalUI's line
/// advance is `ceil(ascent + descent + leading)` on both text systems: one
/// line of Noto Sans 17 is **24** tall, where SwiftUI's is 23 (X13; CoreText's
/// sum is 23.154).
///
/// Mutation **M3n**: `lineHeight` rounded to nearest on both systems.
@MainActor
@Test func aNotoSansLineIsTwentyFourPointsWhereSwiftUIsIsTwentyThree() throws {
    CTFontManagerRegisterFontsForURL(teNotoURL as CFURL, .process, nil)
    defer { CTFontManagerUnregisterFontsForURL(teNotoURL as CFURL, .process, nil) }
    let systems: [(String, any TextSystem)] = [("CoreText", CoreTextTextSystem()), ("portable", try tePortableSystem())]
    for (name, system) in systems {
        let metrics = system.fontMetrics(system.resolveFont(family: "Noto Sans", size: 17))
        try #require(abs(metrics.ascent + metrics.descent + metrics.leading - 23.154) < 0.01, "\(name)")
        let frame = Frame(contentSize: Size(width: Pixels(400), height: Pixels(200)), scaleFactor: 1,
                          textSystem: system, reportsUnlowerableFields: true, recordsElementBounds: true)
        var root = controlRoot { Text("Hg").font(family: "Noto Sans", size: 17) }
        frame.render(&root)
        let b = try controlBounds(frame, controlID([0, 0]))
        #expect(b.size.height.value == 24, "\(name): one line is \(b.size.height.value) tall")
    }
}

// MARK: - 3.22

/// Every glyph sprite of `frame`.
@MainActor
func teSprites(_ frame: Frame) -> [[Float]] {
    frame.finalizedScene().glyphs.map {
        [$0.bounds.origin.x, $0.bounds.origin.y, $0.bounds.size.width, $0.bounds.size.height]
    }
}

/// **3.22.** A container's `.font(_:)` reaches a `TextField` and a
/// `TextEditor` (TE-F item 2): the field's height is the 20 pt line, and both
/// draw exactly what the same element with an explicit 20 pt font draws. Under
/// the default environment each draws its old 13 pt self.
///
/// Mutation **M3t**: the fields keep `fontSize` 13.
@MainActor
@Test func aTextFieldAndATextEditorTakeTheEnvironmentFont() throws {
    let system = teSystem()
    let line20 = Float(system.fontMetrics(system.resolveFont(family: nil, size: 20)).lineHeight)
    let line13 = Float(system.fontMetrics(system.resolveFont(family: nil, size: 13)).lineHeight)
    try #require(line20 != line13)
    let field = TextField("Name", text: "Hello") { _ in }
    #expect(try teBounds([0, 0, 0]) { Column { field }.font(.system(size: 20)) }.size.height.value == line20)
    #expect(try teBounds { field }.size.height.value == line13, "the default environment: 13 pt")

    func editorSprites<C: ElementGroup>(@ElementBuilder _ content: () -> C) throws -> [[Float]] {
        teSprites(try controlRender(controlRoot { content() }))
    }
    let scoped = try editorSprites {
        Column { TextEditor(text: "Hello editor") { _ in }.frame(width: Pixels(200), height: Pixels(80)) }
            .font(.system(size: 20))
    }
    let explicit = try editorSprites {
        Column { TextEditor(text: "Hello editor") { _ in }.font(size: 20).frame(width: Pixels(200), height: Pixels(80)) }
    }
    let plain = try editorSprites {
        Column { TextEditor(text: "Hello editor") { _ in }.frame(width: Pixels(200), height: Pixels(80)) }
    }
    try #require(!plain.isEmpty && explicit != plain)
    #expect(scoped == explicit, "the editor draws the environment's 20 pt font")
}
