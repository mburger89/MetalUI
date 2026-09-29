import Testing
import MetalUITestSupport

// Compile-time guards for plan task 11 part 1, lane 3 (spec rows G3.1, G3.2;
// rulings TE-B, TE-D, TE-H, TE-I, TE-J). Whole-file, Swift 6, a PLAIN
// `import MetalUI`, as an app writes it (`SA-P`; practices shape 16).
//
// **A guard skips silently when `.build/<triple>/debug/Modules` is absent**
// (CLAUDE.md, "Guards").

private let skipReason: Comment =
    "built module directory .build/<triple>/debug/Modules holding MetalUI not found — guard skipped"

/// **G3.1.** Every spec §3 spelling compiles from a plain import: `Font`'s
/// statics and methods; on a `Text`, its own `font`/`fontWeight`/`italic`/
/// `foregroundStyle` and the environment writes; on a `ProposalText` inside an
/// `HStack`; on a container; the four `lineLimit` spellings plus
/// `reservesSpace`; `truncationMode`; `multilineTextAlignment`; the public
/// environment keys; `font(_:)` on `TextField` and `TextEditor`.
/// **Positive control**: `lineLimit(_: Range<Int>)` (a half-open range, which
/// SwiftUI does not take) fails.
///
/// Mutation **MG3a**: `lineLimit(_: ClosedRange<Int>)` made `internal`.
@MainActor
@Test(.enabled(if: canTypecheck(module: "MetalUI"), skipReason))
func theTextModifiersAreSwiftUIsSpellings() throws {
    let uses = """
        @MainActor
        func use() {
            let fonts: [Font] = [.largeTitle, .title, .title2, .title3, .headline, .subheadline, .body,
                                 .callout, .footnote, .caption, .caption2,
                                 .system(size: 13), .system(size: 13, weight: .semibold, design: .rounded),
                                 .system(.body, design: .serif, weight: .light),
                                 .custom("Menlo", size: 12), .custom("Menlo", fixedSize: 12),
                                 .custom("Menlo", size: 12, relativeTo: .caption),
                                 Font.body.weight(.heavy).italic(), Font.title.bold()]
            _ = fonts
            let weights: [Font.Weight] = [.ultraLight, .thin, .light, .regular, .medium, .semibold, .bold,
                                          .heavy, .black]
            _ = weights
            _ = Font.TextStyle.allCases
            let designs: [Font.Design] = [.default, .serif, .rounded, .monospaced]
            _ = designs
            _ = Text("a").font(.title).fontWeight(.bold).italic().foregroundStyle(.accent)
            _ = Text("a").font(nil).fontWeight(nil).italic(false).foregroundColor(.accent)
            _ = Text("a").font(family: "Menlo", size: 12).lineLimit(2).truncationMode(.middle)
            _ = Text("a").lineLimit(2, reservesSpace: true).multilineTextAlignment(.center)
            _ = HStack(alignment: .firstTextBaseline) {
                ProposalText("a").font(.body).fontWeight(.semibold).italic().foregroundStyle(.accent)
                ProposalText("b").lineLimit(1).truncationMode(.head)
            }
            _ = Column { Text("a") }
                .font(.title).fontWeight(.bold).italic().foregroundStyle(.accent).foregroundColor(.accent)
                .lineLimit(nil).lineLimit(1...3).lineLimit(2...).lineLimit(...4).lineLimit(3, reservesSpace: false)
                .truncationMode(.tail).multilineTextAlignment(.trailing)
            _ = TextField("n", text: "") { _ in }.font(.caption)
            _ = TextEditor(text: "") { _ in }.font(nil)
            var values = EnvironmentValues()
            values.font = .body
            values.lineLimit = 2
            values.truncationMode = .head
            values.multilineTextAlignment = .center
            let modes: [Text.TruncationMode] = [.head, .tail, .middle]
            let alignments: [TextAlignment] = [.leading, .center, .trailing]
            _ = (values, modes, alignments)
        }
        """
    let control = """
        @MainActor
        func use() {
            _ = Column { Text("a") }.lineLimit(1..<3)
        }
        """
    let positive = try typecheckFile(uses, importing: "MetalUI")
    let negative = try typecheckFile(control, importing: "MetalUI")
    print("""
        TE-B text modifiers: positive succeeded=\(positive.succeeded) messages=[\(positive.messages)]; \
        control succeeded=\(negative.succeeded) messages=[\(negative.messages)]
        """)
    try #require(!negative.succeeded, "the control must fail, or this guard cannot: \(negative.messages)")
    #expect(positive.succeeded, "every text spelling must compile from a plain import: \(positive.messages)")
}

/// **G3.2.** `Text("a").bold()` is not offered (ruling TE-B item 4: SwiftUI's
/// draws semibold, heavy or nothing by font, X1/X1b/F2e — no rule fits);
/// **positive control**: `Text("a").font(.body.bold())` compiles.
///
/// Mutation **MG3b**: add `Text.bold()`.
@MainActor
@Test(.enabled(if: canTypecheck(module: "MetalUI"), skipReason))
func textBoldIsNotOffered() throws {
    let bold = """
        @MainActor
        func use() {
            _ = Text("a").bold()
        }
        """
    let control = """
        @MainActor
        func use() {
            _ = Text("a").font(.body.bold())
            _ = Text("a").fontWeight(.bold)
        }
        """
    let negative = try typecheckFile(bold, importing: "MetalUI")
    let positive = try typecheckFile(control, importing: "MetalUI")
    print("""
        TE-B bold: bold succeeded=\(negative.succeeded) messages=[\(negative.messages)]; \
        control succeeded=\(positive.succeeded) messages=[\(positive.messages)]
        """)
    try #require(positive.succeeded, "the control must compile, or this guard cannot: \(positive.messages)")
    #expect(!negative.succeeded, "Text.bold() must not be offered")
    #expect(negative.messages.contains("bold"), "it fails for the missing method: \(negative.messages)")
}
