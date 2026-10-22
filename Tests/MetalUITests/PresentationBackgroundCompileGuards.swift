import Testing
import MetalUITestSupport

// Presentation extras, lane 1, guards BG1.1-BG1.2 (rulings `BG-D`, `CR-D`; spec test 14). Whole-file Swift 6
// (`typecheckFile`, ruling SA-P) against a PLAIN import. **A guard skips silently when
// `.build/<triple>/debug/Modules` is absent** (CLAUDE.md, "Guards"); grep the log for
// `BG token twin` and `BG presentationBackground spellings` to know each ran.

private let skipReason: Comment =
    "built module directory .build/<triple>/debug/Modules holding MetalUI not found — guard skipped"

/// **Guard BG1.1** (`CR-D`, guards 1.24/1.25's rule). The colour-token twin keeps `.presentationBackground(.surface)`
/// unambiguous beside the `Color` overload (`Color.surface` also exists). **Separating arm**: the same call over a
/// non-element type does not compile. Mutation: delete the `@_disfavoredOverload` token twin (the call is ambiguous).
@Test(.enabled(if: canTypecheck(module: "MetalUI"), skipReason))
func thePresentationBackgroundColourTokenTwinIsUnambiguous() throws {
    let spelled = try typecheckFile("""
        @MainActor func view(shown: Binding<Bool>) -> some ElementGroup {
            Box().popover(isPresented: shown) {
                Box().presentationBackground(.surface)
            }
        }
        """, importing: "MetalUI")
    let separating = try typecheckFile("""
        struct NotAnElement {}
        func view() { _ = NotAnElement().presentationBackground(.surface) }
        """, importing: "MetalUI")
    print("BG token twin: succeeded=\(spelled.succeeded) messages=[\(spelled.messages)]; separating succeeded=\(separating.succeeded)")
    try #require(spelled.succeeded && !separating.succeeded,
                 "the token spelling compiles, a non-element does not:\n\(spelled.output)\n\(separating.output)")
}

/// **Guard BG1.2** (`BG-D`). The spellings are offered on an element group and on proposal content: a `Color`, a
/// `Material`, both gradients, the content spelling with and without `alignment:`. **Separating arm**: a `ShapeStyle`
/// generic is not offered (an arbitrary `ShapeStyle` value does not compile). Mutation: delete the radial overload.
@Test(.enabled(if: canTypecheck(module: "MetalUI"), skipReason))
func presentationBackgroundIsOfferedOnAnElementGroupAndAProposalGroup() throws {
    let spelled = try typecheckFile("""
        @MainActor func legacy(shown: Binding<Bool>) -> some ElementGroup {
            Box().popover(isPresented: shown) {
                Box().presentationBackground(Color.red)
                    .presentationBackground(Material.regularMaterial)
                    .presentationBackground(LinearGradient(colors: [.red, .blue], startPoint: .top, endPoint: .bottom))
                    .presentationBackground(RadialGradient(colors: [.red, .blue], center: .center,
                                                           startRadius: Pixels(0), endRadius: Pixels(10)))
                    .presentationBackground { Color.red }
                    .presentationBackground(alignment: .topLeading) { Color.red.frame(width: Pixels(10)) }
            }
        }

        @MainActor func proposal(shown: Binding<Bool>) -> some Element {
            HStack {
                Rectangle().popover(isPresented: shown) {
                    VStack { Rectangle() }.presentationBackground(.blue)
                }
            }
        }
        """, importing: "MetalUI")
    let separating = try typecheckFile("""
        @MainActor func view<S: Sendable>(_ style: S) -> some ElementGroup { Box().presentationBackground(style) }
        """, importing: "MetalUI")
    print("BG presentationBackground spellings: succeeded=\(spelled.succeeded) messages=[\(spelled.messages)]; separating succeeded=\(separating.succeeded)")
    try #require(spelled.succeeded && !separating.succeeded,
                 "the spellings compile and a generic style does not:\n\(spelled.output)\n\(separating.output)")
}
