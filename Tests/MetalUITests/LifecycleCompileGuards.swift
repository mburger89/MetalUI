import Testing
import MetalUITestSupport

// Lifecycle modifiers, guards 9.1–9.3 (rulings `LC-B`, `LC-G`; spec
// `docs/superpowers/specs/2026-10-03-lifecycle-design.md` §5.2). Whole-file
// Swift 6 (`typecheckFile`, ruling SA-P) against a PLAIN import — a
// `@testable` test cannot prove what an external module can spell.
//
// **A guard skips silently when `.build/<triple>/debug/Modules` is absent**
// (CLAUDE.md, "Guards"); grep the log for `LC-B spellings`, `LC-G equatable`
// and `LC-B decoration order` to know each ran.

private let skipReason: Comment =
    "built module directory .build/<triple>/debug/Modules holding MetalUI not found — guard skipped"

/// **9.1** (`LC-B` items 1–2). Every lifecycle spelling typechecks from an
/// external module: `.onAppear { model.start() }` calling a `@MainActor`
/// model, `.onAppear()`, `.onDisappear(perform: f)`, both `onChange` closure
/// forms and `{ _, _ in }`, `initial: true`, on a legacy `Text` and a
/// `ProposalText`, with `.frame` and `.id` written after.
///
/// Mutation **MG9.1**: delete the zero-parameter `onChange` overload (the
/// `{ }` lines fail).
@Test(.enabled(if: canTypecheck(module: "MetalUI"), skipReason))
func theLifecycleSpellingsTypecheckFromAnExternalModule() throws {
    let result = try typecheckFile("""
        @MainActor final class Monitor {
            var running = false
            func start() { running = true }
            func stop() { running = false }
        }
        @MainActor func tree(_ model: Monitor, _ x: Int, _ f: @escaping () -> Void) -> some Element {
            Column {
                Text("a")
                    .onAppear { model.start() }
                    .onDisappear(perform: f)
                    .onChange(of: x) { old, new in print(old, new) }
                    .onChange(of: x) { model.stop() }
                    .onChange(of: x) { _, _ in }
                    .onChange(of: x, initial: true) { old, new in _ = old + new }
                    .frame(width: Pixels(10))
                    .id("text")
                Text("b").onAppear().onDisappear()
                HStack {
                    ProposalText("c")
                        .onAppear { model.start() }
                        .onChange(of: x, initial: true) { model.stop() }
                        .frame(width: Pixels(10))
                }
            }
        }
        """, importing: "MetalUI")
    print("LC-B spellings: succeeded=\(result.succeeded) messages=[\(result.messages)]")
    #expect(result.succeeded, "every lifecycle spelling must compile:\n\(result.output)")
}

/// **9.2** (`LC-G` item 5). A non-`Equatable` `onChange` value does not
/// compile; the positive control — the same call on an `Equatable` value —
/// does.
///
/// Mutation **MG9.2**: drop the `Equatable` constraint (the negative compiles).
@Test(.enabled(if: canTypecheck(module: "MetalUI"), skipReason))
func aNonEquatableOnChangeValueDoesNotCompile() throws {
    let positive = try typecheckFile("""
        struct Token: Equatable { var n: Int }
        @MainActor func tree(_ t: Token) -> some Element {
            Column { Text("a").onChange(of: t) { _, _ in } }
        }
        """, importing: "MetalUI")
    let negative = try typecheckFile("""
        struct Token { var n: Int }
        @MainActor func tree(_ t: Token) -> some Element {
            Column { Text("a").onChange(of: t) { _, _ in } }
        }
        """, importing: "MetalUI")
    print("""
        LC-G equatable: positive succeeded=\(positive.succeeded); negative succeeded=\(negative.succeeded) \
        messages=[\(negative.messages)]
        """)
    try #require(positive.succeeded && !negative.succeeded,
                 """
                 the Equatable value must compile and the non-Equatable one must not, or \
                 this guard cannot fail:
                 positive:
                 \(positive.output)
                 negative:
                 \(negative.output)
                 """)
    #expect(negative.messages.contains("Equatable"),
            "the negative must be refused for Equatable:\n\(negative.output)")
}

/// **9.3** (`LC-B` item 4, divergence 120). A legacy `Self`-returning
/// decoration written after a lifecycle modifier does not compile —
/// `Text("a").onAppear {}.onClick {}`; written first it does (the positive
/// control).
///
/// Mutation **MG9.3**: move `.onClick` before `.onAppear` in the negative
/// fixture (it compiles).
@Test(.enabled(if: canTypecheck(module: "MetalUI"), skipReason))
func aLegacyDecorationAfterALifecycleModifierDoesNotCompile() throws {
    let positive = try typecheckFile("""
        @MainActor func tree() -> some Element {
            Column { Text("a").onClick {}.onAppear {} }
        }
        """, importing: "MetalUI")
    let negative = try typecheckFile("""
        @MainActor func tree() -> some Element {
            Column { Text("a").onAppear {}.onClick {} }
        }
        """, importing: "MetalUI")
    print("""
        LC-B decoration order: positive succeeded=\(positive.succeeded); negative \
        succeeded=\(negative.succeeded) messages=[\(negative.messages)]
        """)
    try #require(positive.succeeded && !negative.succeeded,
                 """
                 a decoration before the modifier must compile and one after it must not, \
                 or this guard cannot fail:
                 positive:
                 \(positive.output)
                 negative:
                 \(negative.output)
                 """)
    #expect(negative.messages.contains("onClick"),
            "the negative must be refused for onClick:\n\(negative.output)")
}
