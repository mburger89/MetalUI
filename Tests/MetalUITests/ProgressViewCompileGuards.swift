import Testing
import MetalUITestSupport

// C10 lane 2, the `ProgressView` guard (rulings `LK-E` item 1, `LK-P` item 2;
// spec `2026-10-08-controls-looks-design.md` §1). Whole-file Swift 6
// (`typecheckFile`, ruling SA-P) against a PLAIN import. No `PlatformWindow`
// conformer is declared here (`LK-T` item 1). Grep the log for `LK-E
// spellings` to know it ran.

private let skipReason: Comment =
    "built module directory .build/<triple>/debug/Modules holding MetalUI not found — guard skipped"

/// `LK-E` item 1, `LK-P` item 2. MetalCreator's `M5-j` spellings typecheck
/// from an external module — `ProgressView()`, `ProgressView(value: x, total:
/// 1)`, `ProgressView("Label", value: x)`, `ProgressView("Label")`, the label
/// views, `.controlSize(.small)`, `.progressViewStyle` on the view and on a
/// container, an `Int`-free `Float` value — and a progress view takes
/// `.padding` and `.background` like any control (it is one `StyledElement`);
/// a `.progressViewStyle` given a string does not (the negative control).
///
/// Mutations: delete `init(value:total:label:currentValueLabel:)` (the positive
/// fails); drop the `StyledElement` conformance (`.padding(4)` after the view's
/// own `.progressViewStyle` fails).
@Test(.enabled(if: canTypecheck(module: "MetalUI"), skipReason))
func progressViewSpellingsTypecheckFromAnExternalModule() throws {
    let positive = try typecheckFile("""
        @MainActor func tree(_ x: Double, _ f: Float, _ busy: Bool) -> some Element {
            Column {
                ProgressView()
                ProgressView().controlSize(.small)
                ProgressView(value: x, total: 1)
                ProgressView(value: f)
                ProgressView(value: busy ? nil : x)
                ProgressView("Exporting", value: x)
                ProgressView("Loading")
                ProgressView(value: x, total: 10) { Text("Export") } currentValueLabel: { Text("\\(Int(x))") }
                ProgressView(value: x).progressViewStyle(.circular).padding(Pixels(4)).background(.surface)
                Column { ProgressView(); ProgressView(value: x) }.progressViewStyle(.linear)
                HStack { ProgressView(value: x).progressViewStyle(.linear) }
            }
        }
        """, importing: "MetalUI")
    let negative = try typecheckFile("""
        @MainActor func tree() -> some Element {
            Column { ProgressView().progressViewStyle("linear") }
        }
        """, importing: "MetalUI")
    print("""
        LK-E spellings: positive succeeded=\(positive.succeeded); negative succeeded=\(negative.succeeded) \
        messages=[\(negative.messages)]
        """)
    try #require(positive.succeeded && !negative.succeeded,
                 """
                 SwiftUI's spellings must compile and a string style must not, or this guard cannot fail:
                 positive:
                 \(positive.output)
                 negative:
                 \(negative.output)
                 """)
}
