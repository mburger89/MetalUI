import Testing
import Foundation
import MetalUITestSupport

// Compile-time guards for plan task 15, the closeout — lane 1 (spec
// `docs/superpowers/specs/2026-09-30-closeout-design.md` §4; rulings `CX-D`
// and `CX-J` in `docs/superpowers/2026-09-30-closeout-decisions.md`; record
// §66 §4). What an external module can write is a compile-time property, so
// G1 uses `typecheckFile` against a PLAIN `import MetalUI` (`SA-P`; practices
// shape 16).
//
// **A guard skips silently when `.build/<triple>/debug/Modules` is absent**
// (the default build system, `--scratch-path`, `-c release`) — which is why
// G2 exists: with `METALUI_REQUIRE_GUARDS=1` that skip becomes a failure, and
// macOS CI sets it (`CX-J`).

private let skipReason: Comment =
    "built module directory .build/<triple>/debug/Modules holding MetalUI not found — guard skipped"

private func show(_ label: String, _ result: TypecheckResult) {
    print("CLOSEOUT GUARD \(label): succeeded=\(result.succeeded)\n\(result.messages)")
}

/// **G1 — a plain importer cannot pass `Box` a `Style`** (`CX-D`). Since stage
/// 10 every stored `Style` field is `package`, so `Box(style: Style())` could
/// only ever configure nothing; the `style:` initialisers are `package` now and
/// the public ones take `decoration:` alone. The control — `Box()`,
/// `Box(decoration:)` with and without content — compiles from the same import.
///
/// Red at `1b093b8` (the `style:` call compiled). Mutation **MG1**: re-publish
/// one `style:` initialiser → this guard.
@Test(.enabled(if: canTypecheck(module: "MetalUI"), skipReason))
func aPlainImportCannotPassBoxAStyle() throws {
    let control = try typecheckFile("""
        @MainActor func build() {
            _ = Box()
            _ = Box(decoration: Decoration())
            _ = Box(decoration: Decoration()) { Box() }
            _ = Box(decoration: Decoration(), content: EmptyGroup())
        }
        """, importing: "MetalUI")
    show("G1 control", control)
    try #require(control.succeeded, "Box() and Box(decoration:) must compile from a plain import:\n\(control.output)")

    for call in ["Box(style: Style())",
                 "Box(style: Style(), decoration: Decoration())",
                 "Box(style: Style()) { Box() }",
                 "Box(style: Style(), content: EmptyGroup())"] {
        let result = try typecheckFile("""
            @MainActor func build() {
                _ = \(call)
            }
            """, importing: "MetalUI")
        show("G1 \(call)", result)
        #expect(!result.succeeded, "\(call) must not compile from a plain import (CX-D):\n\(result.output)")
    }
}

/// **G2 — the guards ran where they are required** (`CX-J`). With
/// `METALUI_REQUIRE_GUARDS=1` in the environment, a missing
/// `.build/<triple>/debug/Modules` — the condition under which every other
/// guard returns true for free — fails here, naming where it looked. Without
/// the variable it asserts nothing (the env var is the gate, as the
/// `measure…` tests' are). It calls `canTypecheck`, so CLAUDE.md's guard count
/// includes it (`CX-P` item 4).
///
/// Red under the default build system with the variable set (no `debug/Modules`
/// there); green under `--build-system native`. Mutation **MG2**: ignore the
/// variable → green under default-with-env (the instrument proof).
@Test func theTypecheckGuardsRanWhereTheyAreRequired() {
    guard ProcessInfo.processInfo.environment["METALUI_REQUIRE_GUARDS"] == "1" else { return }
    #expect(canTypecheck(module: "MetalUI"),
            "METALUI_REQUIRE_GUARDS=1, but no .build/<triple>/debug/Modules holding MetalUI was found under \(URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent(".build").path): every typecheck guard skipped — build and test with --build-system native")
}
