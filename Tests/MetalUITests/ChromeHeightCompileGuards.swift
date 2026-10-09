import Testing
import MetalUITestSupport

// SMK port gaps, lane 1 — guard 2.21b (ruling `SG-F` item 1; spec
// `docs/superpowers/specs/2026-10-09-smk-gaps-design.md` §5). Whole-file
// Swift 6 (`typecheckFile`, ruling SA-P) against a PLAIN import — a
// `@testable` test cannot prove what an external module can spell.
//
// **A guard skips silently when `.build/<triple>/debug/Modules` is absent**
// (CLAUDE.md, "Guards"); grep the log for `SG-F drawnChromeHeight` to know it ran.

private let skipReason: Comment =
    "built module directory .build/<triple>/debug/Modules holding MetalUI not found — guard skipped"

/// **2.21b** (`SG-F` item 1). `Window.drawnChromeHeight` is readable from an
/// external module (the positive control) and cannot be assigned. Mutation
/// **MG2.21b**: make it settable (`public var … { get set }`) — the
/// assignment compiles and the guard reddens.
@Test(.enabled(if: canTypecheck(module: "MetalUI"), skipReason))
func drawnChromeHeightIsReadOnly() throws {
    let read = try typecheckFile("""
        @MainActor func chrome(_ window: Window) -> Pixels { window.drawnChromeHeight }
        """, importing: "MetalUI")
    print("SG-F drawnChromeHeight read: succeeded=\(read.succeeded) messages=[\(read.messages)]")
    #expect(read.succeeded, "a read must compile:\n\(read.output)")
    let write = try typecheckFile("""
        @MainActor func chrome(_ window: Window) { window.drawnChromeHeight = Pixels(0) }
        """, importing: "MetalUI")
    print("SG-F drawnChromeHeight write: succeeded=\(write.succeeded) messages=[\(write.messages)]")
    #expect(!write.succeeded, "an assignment must be refused")
    #expect(write.output.contains("drawnChromeHeight"), "refused for the property itself:\n\(write.output)")
}
