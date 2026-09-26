import Testing
import MetalUITestSupport

// Plan task 10, part 1, lane 2, guards G2.1–G2.3 (ruling `DD-D`). Each fixture
// compiles against a PLAIN `import MetalUI` — this file's own imports are
// irrelevant (shape 16). All three are whole-file Swift 6 (`typecheckFile`,
// ruling SA-P).
//
// **A guard skips silently when `.build/<triple>/debug/Modules` is absent**
// (CLAUDE.md, "Guards"); grep the log for `BINDING GUARD` to know it ran.

private let skipReason: Comment =
    "built module directory .build/<triple>/debug/Modules holding MetalUI not found — guard skipped"

/// **G2.1 — the `KeyBinding` alias is gone, so `Binding` names the value
/// binding** (`DD-D` item 6; whole-file Swift 6, `@MainActor`; inverts the retired
/// `theDeprecatedBindingSpellingStillCompilesAndPointsAtKeyBinding`). The old
/// keymap spelling `Binding("cmd-k", A())` fails to typecheck; the same entry
/// spelled `KeyBinding` succeeds in a `Keymap` (control).
///
/// **The negative fixture is the bare `Binding("cmd-k", A())`, not the spec's
/// `Keymap([Binding("cmd-k", A())])`**: a value `Binding` is never a
/// `KeyBinding`, so the Keymap-wrapped spelling stays an error under the named
/// mutation too and could not see it. The bare call is what the mutation
/// (below) makes compile.
///
/// Mutation that must redden it (M-G2.1): a public
/// `init(_: String, _: some Action) where Value == String` added to `Binding`.
@Test(.enabled(if: canTypecheck(module: "MetalUI"), skipReason))
func theKeyBindingAliasIsGoneSoBindingNamesTheValueBinding() throws {
    // Whole-file and `@MainActor`, so the old spelling can fail only for its
    // spelling: in a nonisolated function-body fixture, a main-actor
    // `Binding` initialiser is rejected for its ISOLATION, which read green
    // under the mutation below (measured: the first version of this guard).
    let old = try typecheckFile("""
        struct A: Action {}
        @MainActor func keymapEntry() {
            let b = Binding("cmd-k", A())
            _ = b
        }
        """, importing: "MetalUI")
    print("BINDING GUARD G2.1 old spelling: succeeded=\(old.succeeded)\n\(old.messages)")

    let control = try typecheckFile("""
        struct A: Action {}
        @MainActor func keymapEntry() {
            let k = Keymap([KeyBinding("cmd-k", A())])
            _ = k
        }
        """, importing: "MetalUI")
    print("BINDING GUARD G2.1 control: succeeded=\(control.succeeded)\n\(control.messages)")

    try #require(old.succeeded != control.succeeded,
                 "the two arms must disagree, or the guard measures nothing:\n\(old.output)\n\(control.output)")
    #expect(!old.succeeded, "the keymap's old `Binding` spelling must no longer compile:\n\(old.output)")
    #expect(!old.messages.contains("deprecated"),
            "rejected outright, not through a lingering deprecated alias:\n\(old.output)")
    #expect(!old.messages.contains("actor"),
            "rejected for its spelling, not for isolation:\n\(old.output)")
    #expect(control.succeeded, "`KeyBinding` is the keymap entry:\n\(control.output)")
}

/// **G2.2 — an external module can declare a `@Binding` and pass a state
/// projection** (`DD-D` item 1, `DD-E`). Whole-file Swift 6: `@Binding var
/// value: Int` in a `Component`, `Child(value: $n)` from `@State`,
/// `.constant`, `$model.name`, `Binding(get:set:)`, `TextField("p", text:
/// $s)`, `TextEditor(text: $s)`. The control passes the plain value `n` where
/// the binding goes.
///
/// Mutation that must redden it (M-G2.2): `State.projectedValue` renamed
/// (`projectedBinding`), so `$n` does not exist. The spec's mutation —
/// `projectedValue` made `internal` — does not compile: "internal property
/// 'projectedValue' cannot have more restrictive access than its enclosing
/// property wrapper type 'State'" (measured), so the compiler itself pins the
/// access level and the rename is the nearest mutant that builds.
@Test(.enabled(if: canTypecheck(module: "MetalUI"), skipReason))
func anExternalModuleCanDeclareABindingAndPassAStateProjection() throws {
    func source(_ childArgument: String) -> String {
        """
        public struct Child: Component {
            @Binding public var value: Int
            public init(value: Binding<Int>) { _value = value }
            public var content: some ElementGroup {
                Box().onClick { value += 1 }
            }
        }

        public struct Model: Sendable { public var name: String; public init() { name = "" } }

        public struct Owner: Component {
            @State var n = 0
            @State var s = ""
            @State var model = Model()
            public init() {}
            public var content: some ElementGroup {
                Child(value: \(childArgument))
                Child(value: .constant(3))
                Child(value: Binding(get: { n }, set: { n = $0 }))
                TextField("p", text: $s)
                TextField("p", text: $model.name)
                TextEditor(text: $s)
            }
        }
        """
    }
    let positive = try typecheckFile(source("$n"), importing: "MetalUI")
    print("BINDING GUARD G2.2 positive: succeeded=\(positive.succeeded)\n\(positive.messages)")
    let control = try typecheckFile(source("n"), importing: "MetalUI")
    print("BINDING GUARD G2.2 control: succeeded=\(control.succeeded)\n\(control.messages)")

    try #require(positive.succeeded != control.succeeded,
                 "the two arms must disagree, or the guard measures nothing:\n\(positive.output)\n\(control.output)")
    #expect(positive.succeeded, "the SwiftUI spellings must compile outside the module:\n\(positive.output)")
    #expect(!control.succeeded, "a plain value is not a binding:\n\(control.output)")
}

/// **G2.3 — a `Binding` is main-actor isolated** (`DD-D` item 4, divergence
/// 78's pin). Whole-file Swift 6: a `nonisolated` function reading
/// `b.wrappedValue` fails; the same function `@MainActor` succeeds (control).
///
/// Mutation that must redden it (M-G2.3): `@MainActor` removed from
/// `Binding`, its closures made plain `@Sendable` (the projection's closures
/// reaching `State` through `MainActor.assumeIsolated`).
@Test(.enabled(if: canTypecheck(module: "MetalUI"), skipReason))
func aBindingIsMainActorIsolated() throws {
    let nonisolatedRead = try typecheckFile("""
        public nonisolated func read(_ b: Binding<Int>) -> Int { b.wrappedValue }
        """, importing: "MetalUI")
    print("BINDING GUARD G2.3 nonisolated: succeeded=\(nonisolatedRead.succeeded)\n\(nonisolatedRead.messages)")
    let control = try typecheckFile("""
        @MainActor public func read(_ b: Binding<Int>) -> Int { b.wrappedValue }
        """, importing: "MetalUI")
    print("BINDING GUARD G2.3 control: succeeded=\(control.succeeded)\n\(control.messages)")

    try #require(nonisolatedRead.succeeded != control.succeeded,
                 "the two arms must disagree, or the guard measures nothing:\n\(nonisolatedRead.output)\n\(control.output)")
    #expect(!nonisolatedRead.succeeded,
            "a Binding cannot be read off the main actor (divergence 78):\n\(nonisolatedRead.output)")
    #expect(nonisolatedRead.messages.contains("main actor"),
            "rejected FOR its isolation:\n\(nonisolatedRead.output)")
}
