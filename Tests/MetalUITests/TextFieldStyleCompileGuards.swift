import Testing
import MetalUITestSupport

// Spec `docs/superpowers/specs/2026-10-07-port-gaps-medium-design.md` §4.1,
// test 1.10 (ruling `MD-B` in
// `docs/superpowers/2026-10-07-port-gaps-medium-decisions.md`): what an
// EXTERNAL module may write with `TextFieldStyle`.
//
// `typecheckFile` against a PLAIN `import MetalUI` (ruling SA-P): a
// `@testable` test cannot see an access level. **A guard skips silently when
// `.build/<triple>/debug/Modules` is absent** (CLAUDE.md, "Guards"); grep the
// log for `TEXT FIELD STYLE GUARD` to know it ran.

private let skipReason: Comment =
    "built module directory .build/<triple>/debug/Modules holding MetalUI not found — guard skipped"

private func show(_ label: String, _ result: TypecheckResult) {
    print("TEXT FIELD STYLE GUARD \(label): succeeded=\(result.succeeded)\n\(result.messages)")
}

/// **1.10** (`MD-B` items 1 and 2). The value spelling on the field keeps the
/// field a `TextField`, so `.background` and `.onSubmit` still chain after it;
/// the container spelling compiles on a `VStack`; `TextEditor` takes
/// `.textEditorStyle`. The separating arm: `TextFieldStyle` is closed — its
/// initialiser is not spellable outside MetalUI.
///
/// Red before: neither compiles (no `TextFieldStyle`). Mutation M1.10 (the
/// initialiser and its kind made public) makes the control compile.
@Test(.enabled(if: canTypecheck(module: "MetalUI"), skipReason))
func aTextFieldStyleIsWrittenOnTheFieldAndCannotBeMintedOutside() throws {
    let positive = try typecheckFile("""
        @MainActor public func fields() {
            let _: TextField = TextField("x", text: .constant("")).textFieldStyle(.plain)
            _ = TextField("x", text: .constant("")).textFieldStyle(.plain).background(.surface).onSubmit {}
            _ = VStack { TextField("x", text: .constant("")) }.textFieldStyle(.roundedBorder)
            _ = Column { TextField("x", text: .constant("")) }.textFieldStyle(.squareBorder)
            let _: TextEditor = TextEditor(text: .constant("")).textEditorStyle(.plain)
            _ = VStack { TextEditor(text: .constant("")) }.textEditorStyle(.automatic)
        }
        """, importing: "MetalUI")
    show("1.10 positive", positive)
    let control = try typecheckFile("""
        @MainActor public func minted() {
            _ = TextFieldStyle(kind: .plain)
        }
        """, importing: "MetalUI")
    show("1.10 control", control)
    try #require(positive.succeeded != control.succeeded,
                 "the two arms must disagree, or the guard measures nothing:\n\(positive.output)\n\(control.output)")
    #expect(positive.succeeded, "the field and container spellings compile:\n\(positive.output)")
    #expect(!control.succeeded, "TextFieldStyle is closed:\n\(control.output)")
}
