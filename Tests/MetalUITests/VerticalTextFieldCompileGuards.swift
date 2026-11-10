import Testing
import MetalUITestSupport

// Alloy gap G18 (`VT-A`, `VT-C`, record 255): what an EXTERNAL module may write with a vertical `TextField`.
//
// `typecheckFile` against a PLAIN `import MetalUI` (ruling SA-P). **A guard skips silently when
// `.build/<triple>/debug/Modules` is absent** (CLAUDE.md, "Guards"); grep the log for `VERTICAL FIELD GUARD` to know it ran.

private let skipReason: Comment =
    "built module directory .build/<triple>/debug/Modules holding MetalUI not found — guard skipped"

private func show(_ label: String, _ result: TypecheckResult) {
    print("VERTICAL FIELD GUARD \(label): succeeded=\(result.succeeded)\n\(result.messages)")
}

/// **21** (`VT-A`, `VT-C`). The vertical initialisers compile, and `lineLimit` written on the field keeps it a `TextField`, so
/// `.onSubmit` chains before and after it (the container spelling would return an `EnvironmentScope` and stop the chain). The
/// separating arm assigns the container spelling to a `TextField`, which does not compile.
///
/// Mutation M21: the five `lineLimit` overloads on `TextField` deleted makes the positive arm fail.
@Test(.enabled(if: canTypecheck(module: "MetalUI"), skipReason))
func lineLimitOnAVerticalFieldKeepsItAFieldAndChainsWithOnSubmit() throws {
    let positive = try typecheckFile("""
        @MainActor public func fields() {
            let _: TextField = TextField("x", text: .constant(""), axis: .vertical).onSubmit {}.lineLimit(1...8)
            let _: TextField = TextField("x", text: .constant(""), axis: .vertical).lineLimit(1...8).onSubmit {}
            let _: TextField = TextField("x", text: .constant(""), axis: .vertical).lineLimit(3, reservesSpace: true)
            let _: TextField = TextField("x", text: .constant(""), axis: .vertical).lineLimit(5...)
            let _: TextField = TextField("x", text: .constant(""), axis: .vertical).lineLimit(...5)
            let _: TextField = TextField("x", text: .constant(""), axis: .vertical).lineLimit(nil)
            let _: TextField = TextField("x", text: "", axis: .vertical, onChange: { _ in })
            _ = VStack { TextField("x", text: .constant(""), axis: .vertical) }.lineLimit(1...3)
        }
        """, importing: "MetalUI")
    show("21 positive", positive)
    let control = try typecheckFile("""
        @MainActor public func container() {
            let _: TextField = VStack { TextField("x", text: .constant(""), axis: .vertical) }.lineLimit(1...3)
        }
        """, importing: "MetalUI")
    show("21 control", control)
    try #require(positive.succeeded != control.succeeded,
                 "the two arms must disagree, or the guard measures nothing:\n\(positive.output)\n\(control.output)")
    #expect(positive.succeeded, "the vertical field's spellings compile:\n\(positive.output)")
}

/// **22** (`VT-K`, Alloy gap G29). `selectedOffsets:` and `prompt:` combine, with and without `axis:`, from an external module.
/// The separating arm swaps the order (`prompt:` before `selectedOffsets:`), which does not compile.
///
/// Mutation M22: the two `selectedOffsets:prompt:` initialisers deleted makes the positive arm fail.
@Test(.enabled(if: canTypecheck(module: "MetalUI"), skipReason))
func selectedOffsetsAndPromptCombineFromAnExternalModule() throws {
    let positive = try typecheckFile("""
        @MainActor public func fields() {
            let t = Binding<String>.constant("")
            let o = Binding<Range<Int>?>.constant(nil)
            let _: TextField = TextField("x", text: t, selectedOffsets: o, prompt: Text("p").foregroundColor(.red), axis: .vertical)
            let _: TextField = TextField("x", text: t, selectedOffsets: o, prompt: Text("p"))
            let _: TextField = TextField("x", text: t, selectedOffsets: o, prompt: nil)
        }
        """, importing: "MetalUI")
    show("22 positive", positive)
    let control = try typecheckFile("""
        @MainActor public func swapped() {
            let t = Binding<String>.constant("")
            let o = Binding<Range<Int>?>.constant(nil)
            let _: TextField = TextField("x", text: t, prompt: Text("p"), selectedOffsets: o)
        }
        """, importing: "MetalUI")
    show("22 control", control)
    try #require(positive.succeeded != control.succeeded,
                 "the two arms must disagree, or the guard measures nothing:\n\(positive.output)\n\(control.output)")
    #expect(positive.succeeded, "the offsets-and-prompt spellings compile:\n\(positive.output)")
}
