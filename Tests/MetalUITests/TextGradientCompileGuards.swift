import Testing
import MetalUITestSupport

// R4-5 PR D (`TG-A`): `Text.foregroundColor` and `ProposalText.foregroundColor` are public *computed* properties over an internal
// storage, and stay writable from outside the module (whole-file Swift 6 against a PLAIN `import MetalUI`, `typecheckFile`, `SA-P`).
// The storage itself is not spellable. A guard skips silently when `.build/<triple>/debug/Modules` is absent; grep the log for
// `TEXT GRADIENT GUARD`.

private let skipReason: Comment =
    "built module directory .build/<triple>/debug/Modules holding MetalUI not found — guard skipped"

/// **G-TG1.** An external module reads and writes `foregroundColor` on both text types; the stored form cannot be named.
/// Mutation: `foregroundColor`'s setter `internal(set)` (the positive arm stops compiling).
@Test(.enabled(if: canTypecheck(module: "MetalUI"), skipReason))
func textForegroundColorStaysPubliclyReadableAndWritable() throws {
    let positive = try typecheckFile("""
        @MainActor func f() {
            var t = Text("a")
            t.foregroundColor = .red
            let _: Color? = t.foregroundColor
            t.foregroundColor = nil
            var p = ProposalText("b")
            p.foregroundColor = Color.blue
            let _: Color? = p.foregroundColor
        }
        """, importing: "MetalUI")
    let storage = try typecheckFile("""
        @MainActor func f() { var t = Text("a"); t.foregroundStorage = nil }
        """, importing: "MetalUI")
    print("TEXT GRADIENT GUARD G-TG1: positive=\(positive.succeeded) storage=\(storage.succeeded)")
    try #require(positive.succeeded && !storage.succeeded,
                 "the arms must disagree, or the guard measures nothing:\n\(positive.output)\n\(storage.output)")
    #expect(storage.messages.contains("foregroundStorage"), "\(storage.output)")
}
