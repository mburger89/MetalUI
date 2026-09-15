import Testing
import MetalUITestSupport

// Compile-time guards for plan task 9, the environment and control-state track
// (`docs/superpowers/specs/2026-09-15-environment-design.md`; rulings `EV-`).
//
// Each fixture compiles against a plain `import MetalUI`. This file's own
// imports are irrelevant (shape 16); the fixture's import is the one that
// counts.
//
// **A guard skips silently when `.build/<triple>/debug/Modules` is absent**
// (CLAUDE.md, "When CI lands"). Each guard here was mutated red once on a
// `--build-system native` build; the mutations are recorded under the ruling
// the guard cites and in `docs/record/11-environment.md`.

private let skipReason: Comment =
    "built module directory .build/<triple>/debug/Modules holding MetalUI not found — guard skipped"

/// **G5 — the keymap's old `Binding` spelling still compiles, and is
/// deprecated toward `KeyBinding`** (ruling EV-N, lane 1).
///
/// Two halves, and each is reddened by a different mutation:
///
/// - `succeeded`: deleting the typealias makes `Binding` unresolvable, so an
///   external caller who wrote the old spelling stops compiling instead of
///   getting a release to move.
/// - `messages` naming `KeyBinding`: dropping `@available(*, deprecated,
///   renamed:)` leaves the alias compiling silently, so nobody is told to move
///   before task 10 deletes the name. The assertion reads `messages`, never
///   `output`: the fixture's own source never spells `KeyBinding`, but a
///   diagnostic-free `output` must not be able to satisfy it by accident either.
///
/// **This guard is deleted by task 10** in the change that introduces a
/// SwiftUI-like `Binding<Value>`, since a module cannot declare both (EV-N).
///
/// The deprecation warning is printed by the child `swiftc`, whose output the
/// helper captures through a pipe, so it does not reach the suite log's
/// `warning:` count.
@Test(.enabled(if: canTypecheck(module: "MetalUI"), skipReason))
func theDeprecatedBindingSpellingStillCompilesAndPointsAtKeyBinding() throws {
    let result = try typecheck("""
        struct A: Action {}
        let k = Keymap([Binding("cmd-k", A())])
        _ = k
        """, importing: "MetalUI")
    #expect(result.succeeded,
            "the deprecated `Binding` spelling must still compile:\n\(result.output)")
    #expect(result.messages.contains("'Binding' is deprecated"),
            "`Binding` must carry a deprecation diagnostic:\n\(result.output)")
    #expect(result.messages.contains("KeyBinding"),
            "the deprecation must name its replacement, `KeyBinding`:\n\(result.output)")
}
