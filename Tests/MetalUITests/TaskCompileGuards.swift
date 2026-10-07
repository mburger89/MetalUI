import Testing
import MetalUITestSupport

// `.task`, guards 3.G1–3.G3 (rulings `PX-F` items 1–2, divergence 120; spec
// `docs/superpowers/specs/2026-10-07-portable-app-design.md` §4.3). Whole-file
// Swift 6 (`typecheckFile`, ruling SA-P) against a PLAIN import — a
// `@testable` test cannot prove what an external module can spell.
//
// **A guard skips silently when `.build/<triple>/debug/Modules` is absent**
// (CLAUDE.md, "Guards"); grep the log for `PX-F spellings`, `PX-F decoration
// order` and `PX-F equatable id` to know each ran.

private let skipReason: Comment =
    "built module directory .build/<triple>/debug/Modules holding MetalUI not found — guard skipped"

/// **3.G1** (`PX-F` item 1, `X2`). Every `.task` spelling typechecks from an
/// external module — `.task {}`, `name:`, `priority:`, `task(id:)` with each,
/// on a legacy `Text` and a `ProposalText`, with `.frame` and `.id` written
/// after — and the closure written in an element is main-actor isolated: it
/// calls a `@MainActor` model method synchronously and captures a
/// non-`Sendable` value.
///
/// Mutation **MG3.1**: remove `@_inheritActorContext` from both overloads
/// (the synchronous `model.start()` calls fail).
@Test(.enabled(if: canTypecheck(module: "MetalUI"), skipReason))
func theTaskSpellingsTypecheckFromAnExternalModule() throws {
    let result = try typecheckFile("""
        @MainActor final class Model {
            var n = 0
            func start() { n += 1 }
        }
        struct Token { var x = 0 }
        @MainActor func tree(_ model: Model, _ k: Int) -> some Element {
            let token = Token()
            return Column {
                Text("a")
                    .task { model.start(); let y = token.x; await Task.yield(); model.n += y }
                    .task(name: "named") { model.start() }
                    .task(priority: .low) { model.start() }
                    .task(name: "both", priority: .background) { await Task.yield() }
                    .task(id: k) { model.start(); _ = token.x }
                    .task(id: k, name: "id", priority: .high) { model.start() }
                    .frame(width: Pixels(10))
                    .id("text")
                HStack {
                    ProposalText("c")
                        .task { model.start() }
                        .task(id: "s") { model.start() }
                        .frame(width: Pixels(10))
                }
            }
        }
        """, importing: "MetalUI")
    print("PX-F spellings: succeeded=\(result.succeeded) messages=[\(result.messages)]")
    #expect(result.succeeded, "every task spelling must compile:\n\(result.output)")
}

/// **3.G2** (`PX-F` item 2, divergence 120). A legacy `Self`-returning
/// decoration written after a `.task` does not compile —
/// `Text("a").task {}.onClick {}`; written first it does (the positive
/// control).
///
/// Mutation **MG3.2**: a temporary `onClick` forwarding extension on
/// `LifecycleScope` (the negative compiles).
@Test(.enabled(if: canTypecheck(module: "MetalUI"), skipReason))
func aLegacyDecorationAfterATaskModifierDoesNotCompile() throws {
    let positive = try typecheckFile("""
        @MainActor func tree() -> some Element {
            Column { Text("a").onClick {}.task {} }
        }
        """, importing: "MetalUI")
    let negative = try typecheckFile("""
        @MainActor func tree() -> some Element {
            Column { Text("a").task {}.onClick {} }
        }
        """, importing: "MetalUI")
    print("""
        PX-F decoration order: positive succeeded=\(positive.succeeded); negative \
        succeeded=\(negative.succeeded) messages=[\(negative.messages)]
        """)
    try #require(positive.succeeded && !negative.succeeded,
                 """
                 a decoration before the task must compile and one after it must not, \
                 or this guard cannot fail:
                 positive:
                 \(positive.output)
                 negative:
                 \(negative.output)
                 """)
    #expect(negative.messages.contains("onClick"),
            "the negative must be refused for onClick:\n\(negative.output)")
}

/// **3.G3** (`PX-F` item 5). A non-`Equatable` `task(id:)` value does not
/// compile; the positive control — the same call on an `Equatable` value —
/// does.
///
/// Mutation **MG3.3**: drop the `Equatable` constraint (the negative
/// compiles).
@Test(.enabled(if: canTypecheck(module: "MetalUI"), skipReason))
func aTaskIDMustBeEquatable() throws {
    let positive = try typecheckFile("""
        struct Token: Equatable { var n: Int }
        @MainActor func tree(_ t: Token) -> some Element {
            Column { Text("a").task(id: t) {} }
        }
        """, importing: "MetalUI")
    let negative = try typecheckFile("""
        struct Token { var n: Int }
        @MainActor func tree(_ t: Token) -> some Element {
            Column { Text("a").task(id: t) {} }
        }
        """, importing: "MetalUI")
    print("""
        PX-F equatable id: positive succeeded=\(positive.succeeded); negative succeeded=\(negative.succeeded) \
        messages=[\(negative.messages)]
        """)
    try #require(positive.succeeded && !negative.succeeded,
                 """
                 the Equatable id must compile and the non-Equatable one must not, or \
                 this guard cannot fail:
                 positive:
                 \(positive.output)
                 negative:
                 \(negative.output)
                 """)
    #expect(negative.messages.contains("Equatable"),
            "the negative must be refused for Equatable:\n\(negative.output)")
}
