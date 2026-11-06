import Testing
import MetalUITestSupport

// `ViewThatFits` and `Axis` from outside the module (rulings `VF-A`, `VF-I`, record 217). Whole-file Swift 6
// (`typecheckFile`, ruling SA-P) against a PLAIN import, because a `@testable` test cannot prove what an external module
// can write: the three spellings SwiftUI's `ViewThatFits` takes, the SwiftUI `Axis.Set` literals, and that the kernel's
// registrar is not reachable.
//
// **A guard skips silently when `.build/<triple>/debug/Modules` is absent** (CLAUDE.md, "Guards"); grep the log for
// `VF-A spellings` to know it ran.

private let skipReason: Comment =
    "built module directory .build/<triple>/debug/Modules holding MetalUI not found — guard skipped"

/// `VF-A`/`VF-I`: `ViewThatFits(in: .horizontal) {}`, `ViewThatFits {}` and `ViewThatFits(in: [.horizontal, .vertical]) {}`
/// compile from a plain import, with `Text` content, an empty builder and `Axis`/`Axis.Set` as SwiftUI spells them.
/// Mutation: making `Axis.Set` an `internal` type, or dropping the `in:` default, reddens it.
@Test(.enabled(if: canTypecheck(module: "MetalUI"), skipReason))
func viewThatFitsIsSpelledAsSwiftUISpellsIt() throws {
    let source = """
    import MetalUICore
    import MetalUILayout
    @MainActor func use() {
        _ = ViewThatFits(in: .horizontal) { Text("a"); Text("b") }
        _ = ViewThatFits { Text("a"); Text("b") }
        _ = ViewThatFits(in: [.horizontal, .vertical]) { Text("a") }
        _ = ViewThatFits(in: .vertical) {}
        _ = ViewThatFits {}
        let axes: Axis.Set = [.horizontal, .vertical]
        let one: Axis = .horizontal
        _ = (axes.contains(.vertical), Axis.Set(one), Axis.allCases)
    }
    """
    let result = try typecheckFile(source, importing: "MetalUI")
    #expect(result.succeeded, "ViewThatFits and Axis as SwiftUI spells them must compile:\n\(result.output)")
    print("VF-A spellings: compiles=\(result.succeeded)")
}

/// `VF-B`: the kernel's registrar is `package`, not public API: a plain import reaches neither `newNativeFirstFitting` nor
/// `LayoutPass.requestNativeFirstFitting`. Mutation: either made `public` makes the negative compile.
@Test(.enabled(if: canTypecheck(module: "MetalUI"), skipReason))
func theFirstFittingRegistrarIsNotPublicAPI() throws {
    let tree = try typecheckFile("""
    import MetalUICore
    import MetalUILayout
    func use(_ tree: LayoutTree, _ children: [LayoutNodeID]) {
        _ = tree.newNativeFirstFitting(children: children, horizontal: true, vertical: false)
    }
    """, importing: "MetalUI")
    #expect(!tree.succeeded, "a plain import must not reach the kernel registrar:\n\(tree.output)")
    #expect(tree.messages.contains("package") && tree.messages.contains("newNativeFirstFitting"), "refused for its access level, not another reason:\n\(tree.output)")
    let pass = try typecheckFile("""
    import MetalUICore
    import MetalUILayout
    @MainActor func use(_ pass: inout LayoutPass, _ children: [ProposalNodeID]) {
        _ = pass.requestNativeFirstFitting(children: children, horizontal: true, vertical: false)
    }
    """, importing: "MetalUI")
    #expect(!pass.succeeded, "nor the pass's:\n\(pass.output)")
    #expect(pass.messages.contains("package") && pass.messages.contains("requestNativeFirstFitting"), "refused for its access level:\n\(pass.output)")
}
