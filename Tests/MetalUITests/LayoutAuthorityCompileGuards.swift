import Testing
import MetalUITestSupport

// Compile-time guard for plan task 7's layout authority
// (`docs/superpowers/specs/2026-09-17-engine-replacement-design.md` §6 lane 1,
// guard G1; ruling LR-B: the authority is internal until stage 6b).
//
// **A plain `import MetalUI` fixture through `typecheckFile`** (ruling SA-P;
// taxonomy shape 16): a `@testable` test file sees `internal` and cannot show
// that an external module cannot choose the authority.
//
// **The guard skips silently when `.build/<triple>/debug/Modules` is absent**
// (CLAUDE.md, CI section). It was run red once, with `LayoutAuthority` and
// `Window.layoutAuthority` made `public` (record §18, lane 1).

private let skipReason: Comment =
    "built module directory .build/<triple>/debug/Modules holding MetalUI not found — guard skipped"

/// **G1.** Outside `MetalUI`, `window.layoutAuthority = …` does not compile.
/// The positive control writes `theme` on the same `Window`, so the negative's
/// failure is about the authority's access level and not about the fixture.
///
/// Mutation that must redden it: `LayoutAuthority` and `Window.layoutAuthority`
/// made `public`.
@Test(.enabled(if: canTypecheck(module: "MetalUI"), skipReason))
func aPlainImportCannotChooseTheLayoutAuthority() throws {
    let choose = try typecheckFile("""
        @MainActor public func choose(_ window: Window) {
            window.layoutAuthority = .proposal
        }
        """, importing: "MetalUI")
    let control = try typecheckFile("""
        @MainActor public func control(_ window: Window) {
            window.theme = .dark
        }
        """, importing: "MetalUI")
    print("LAYOUT-AUTHORITY GUARD G1 choose: succeeded=\(choose.succeeded)\n\(choose.messages)")
    print("LAYOUT-AUTHORITY GUARD G1 control: succeeded=\(control.succeeded)\n\(control.messages)")
    try #require(choose.succeeded != control.succeeded,
                 "the choice and the control must disagree, or the instrument cannot fail:\n\(choose.output)\n\(control.output)")
    #expect(control.succeeded, "the control must compile:\n\(control.output)")
    #expect(!choose.succeeded, "an external module must not choose the layout authority:\n\(choose.output)")
    #expect(choose.messages.contains("'layoutAuthority' is inaccessible due to 'internal' protection level"),
            "rejected, but not because the property is internal:\n\(choose.output)")
}
