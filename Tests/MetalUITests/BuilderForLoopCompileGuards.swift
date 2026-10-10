import Testing
import MetalUITestSupport

// Key and focus scoping, lane C — the `for` loop over an opaque helper in a
// result builder (MetalCreator gap M4-b (1); ruling `KF-M`; spec
// `docs/superpowers/specs/2026-10-08-key-focus-design.md` §5.3, guard C1;
// probe `docs/probes/swift-builder-for-opaque.sh`).
//
// **A toolchain limitation, pinned.** The result-builder transform declares
// the loop's accumulator with the body block's type, which reads back as a new
// opaque type nothing determines — decided before `buildArray` is consulted, so
// no library spelling of `buildArray` fixes it (`KF-M` item 2, probe A4). The
// failing arm is MetalCreator's spelling and **must fail** with the opaque-type
// diagnostic: a toolchain that fixes the transform reddens this guard, and the
// note in `docs/api-overview.md` and on both builders' `buildArray` can go.
// The separating arms are the remedies, and **must compile**.
//
// Whole-file, Swift 6, a plain `import MetalUI` (`typecheckFile`, `SA-P`): this
// is about what an app can write. **A guard skips silently when
// `.build/<triple>/debug/Modules` is absent** (CLAUDE.md, "Guards").

private let metalUISkipReason: Comment =
    "built module directory .build/<triple>/debug/Modules holding MetalUI not found — guard skipped"

/// The diagnostic the transform produces (probe arms A1, A12).
private let opaqueDiagnostic = "underlying type for opaque result type"

/// **C1** (`KF-M`). A `for` loop over a helper returning `some
/// ProposalElementGroup` in a `ZStack` does not compile, with the opaque-type
/// diagnostic; `ForEach(texts, id: \.self) { label($0) }`, a helper returning
/// a concrete type (`-> ProposalText`, a `struct Label: Element`) and the
/// inline chain each compile.
///
/// Mutations: change the failing fixture's helper to `-> ProposalText` (the
/// "must fail" arm compiles); spell the `ForEach` arm's type `ForEachh` (a
/// "must compile" arm fails).
@Test(.enabled(if: canTypecheck(module: "MetalUI"), metalUISkipReason))
func aForLoopOverAnOpaqueHelperIsAToolchainLimitation() throws {
    let failing = try typecheckFile("""
        @MainActor func label(_ text: String) -> some ProposalElementGroup {
            ProposalText(text).offset(x: Pixels(2))
        }
        @MainActor func labels(_ texts: [String]) -> some Element {
            ZStack { for text in texts { label(text) } }
        }
        """, importing: "MetalUI")
    print("C1 failing arm: succeeded=\(failing.succeeded) messages=[\(failing.messages)]")
    #expect(!failing.succeeded && failing.messages.contains(opaqueDiagnostic),
            """
            the for-over-an-opaque-helper spelling must fail with "\(opaqueDiagnostic)" — if it \
            compiles, the toolchain fixed the transform: retire KF-M's note. Output:
            \(failing.output)
            """)

    let remedies: [(String, String)] = [
        ("ForEach", """
            @MainActor func label(_ text: String) -> some ProposalElementGroup {
                ProposalText(text).offset(x: Pixels(2))
            }
            @MainActor func labels(_ texts: [String]) -> some Element {
                ZStack { ForEach(texts, id: \\.self) { label($0) } }
            }
            """),
        ("concrete helper", """
            @MainActor func label(_ text: String) -> ProposalText { ProposalText(text) }
            @MainActor func labels(_ texts: [String]) -> some Element {
                ZStack { for text in texts { label(text) } }
            }
            """),
        ("helper type", """
            struct Label: Component {
                let text: String
                var content: some ProposalElementGroup { ProposalText(text).offset(x: Pixels(2)) }
            }
            @MainActor func labels(_ texts: [String]) -> some Element {
                ZStack { for text in texts { Label(text: text) } }
            }
            """),
        ("inline chain", """
            @MainActor func labels(_ texts: [String]) -> some Element {
                ZStack { for text in texts { ProposalText(text).offset(x: Pixels(2)) } }
            }
            """),
    ]
    for (name, source) in remedies {
        let result = try typecheckFile(source, importing: "MetalUI")
        print("C1 \(name) arm: succeeded=\(result.succeeded) messages=[\(result.messages)]")
        #expect(result.succeeded, "the \(name) remedy must compile:\n\(result.output)")
    }
}
