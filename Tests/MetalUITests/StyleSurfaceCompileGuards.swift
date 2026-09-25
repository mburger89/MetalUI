import Testing
import MetalUITestSupport

// Compile-time guards for stage 10 of plan task 7 (spec
// `docs/superpowers/specs/2026-09-24-engine-stage-10-design.md` §6 lane 2,
// guards G1–G3; rulings LR-FM, LR-FN, LR-FP item 5): `Style`'s surviving
// fields are `package`, its deleted CSS spellings are gone, and the layout
// kernel declares no `Style` at all.
//
// **A plain `import` fixture through `typecheckFile`** (ruling SA-P; taxonomy
// shape 16): a `@testable` test cannot prove a narrowing or an absence from an
// external module's view.
//
// **The guards skip silently when `.build/<triple>/debug/Modules` is absent**
// (CLAUDE.md, CI section); `theLegacyEngineSymbolsAreAbsentFromTheTestProcess`
// (`MetalUICrossPlatformTests`) is the half of the closing check that cannot
// skip. Each guard was run red once (record §52 §5).

private let skipReason: Comment =
    "built module directory .build/<triple>/debug/Modules holding MetalUI not found — guard skipped"

/// **G1.** Outside the package a `Style` field cannot be written: every
/// surviving stored field is `package` (`LR-FM` item 2), so an element's layout
/// is spelled only through its modifiers. The control writes the same field
/// through `.flexGrow(_:)`.
///
/// Mutation that must redden it (**M2b**): `Style.flexGrow` made `public`.
@Test(.enabled(if: canTypecheck(module: "MetalUI"), skipReason))
func aPlainImportCannotWriteAStyleField() throws {
    let write = try typecheckFile("""
        public func write() {
            var s = Style()
            s.flexGrow = 1
            _ = s
        }
        """, importing: "MetalUI")
    let control = try typecheckFile("""
        @MainActor public func control() {
            _ = Box().flexGrow(1)
        }
        """, importing: "MetalUI")
    print("STYLE-SURFACE GUARD G1 write: succeeded=\(write.succeeded)\n\(write.messages)")
    print("STYLE-SURFACE GUARD G1 control: succeeded=\(control.succeeded)\n\(control.messages)")
    try #require(write.succeeded != control.succeeded,
                 "the write and the control must disagree, or the instrument cannot fail:\n\(write.output)\n\(control.output)")
    #expect(control.succeeded, "the control must compile:\n\(control.output)")
    #expect(!write.succeeded, "an external module must not write a Style field:\n\(write.output)")
    #expect(write.messages.contains("'flexGrow' is inaccessible due to 'package' protection level"),
            "rejected, but not by access:\n\(write.output)")
}

/// **G2.** Every spelling stage 10 deleted fails to compile, each with its own
/// message (`LR-FN` items 1–4): the two removed modifiers, `Position.relative`,
/// the three removed enums and `Style.border`. The control spells the kept
/// neighbours of each — `.position(.absolute)`, `.inset`, `.alignItems`,
/// `.flexBasis` — on one chain.
///
/// Mutation that must redden it (**M2a**): `FlexWrap`, `Style.flexWrap` and
/// `StyledElement.flexWrap(_:)` re-added — the first fixture compiles.
@Test(.enabled(if: canTypecheck(module: "MetalUI"), skipReason))
func theDeletedStyleSpellingsDoNotCompile() throws {
    let fixtures: [(body: String, message: String)] = [
        ("_ = Box().flexWrap(.wrap)", "has no member 'flexWrap'"),
        ("_ = Box().alignContent(.center)", "has no member 'alignContent'"),
        ("_ = Box().position(.relative)", "type 'Position' has no member 'relative'"),
        ("let _: FlexWrap? = nil", "cannot find type 'FlexWrap' in scope"),
        ("let _: AlignContent? = nil", "cannot find type 'AlignContent' in scope"),
        ("let _: Overflow? = nil", "cannot find type 'Overflow' in scope"),
        ("_ = Style().border", "value of type 'Style' has no member 'border'"),
    ]
    try #require(fixtures.count == 7)
    let control = try typecheckFile("""
        @MainActor public func control() {
            _ = Box().position(.absolute).inset(Pixels(0)).alignItems(.center).flexBasis(Pixels(0))
        }
        """, importing: "MetalUI")
    print("STYLE-SURFACE GUARD G2 control: succeeded=\(control.succeeded)\n\(control.messages)")
    try #require(control.succeeded, "the control must compile, or no fixture's failure means anything:\n\(control.output)")
    for fixture in fixtures {
        let result = try typecheckFile("""
            @MainActor public func fixture() {
                \(fixture.body)
            }
            """, importing: "MetalUI")
        print("STYLE-SURFACE GUARD G2 `\(fixture.body)`: succeeded=\(result.succeeded)\n\(result.messages)")
        #expect(!result.succeeded, "`\(fixture.body)` must not compile:\n\(result.output)")
        #expect(result.messages.contains(fixture.message),
                "`\(fixture.body)` rejected, but not because the spelling is gone:\n\(result.output)")
    }
}

/// **G3.** The layout kernel declares no CSS vocabulary: `Style` lives in
/// `MetalUI` (`LR-FM` item 3), so `MetalUILayout.Style` does not exist. The
/// control spells the same value under `import MetalUI`.
///
/// Mutation that must redden it (**M2c**): `Style.swift` moved back to
/// `MetalUILayout`.
@Test(.enabled(if: canTypecheck(module: "MetalUI"), skipReason))
func theLayoutKernelDeclaresNoStyle() throws {
    let kernel = try typecheckFile("""
        public func kernel() {
            let _ = MetalUILayout.Style()
        }
        """, importing: "MetalUILayout")
    let control = try typecheckFile("""
        public func control() {
            let _ = Style()
        }
        """, importing: "MetalUI")
    print("STYLE-SURFACE GUARD G3 kernel: succeeded=\(kernel.succeeded)\n\(kernel.messages)")
    print("STYLE-SURFACE GUARD G3 control: succeeded=\(control.succeeded)\n\(control.messages)")
    try #require(kernel.succeeded != control.succeeded,
                 "the kernel spelling and the control must disagree, or the instrument cannot fail:\n\(kernel.output)\n\(control.output)")
    #expect(control.succeeded, "the control must compile:\n\(control.output)")
    #expect(!kernel.succeeded, "MetalUILayout must not declare Style:\n\(kernel.output)")
    #expect(kernel.messages.contains("module 'MetalUILayout' has no member named 'Style'"),
            "rejected, but not because the type is gone:\n\(kernel.output)")
}
