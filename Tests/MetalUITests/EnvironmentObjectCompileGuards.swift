import Testing
import MetalUITestSupport

// Spec `docs/superpowers/specs/2026-10-07-port-gaps-medium-design.md` §4.2,
// test 2.12 (ruling `MD-H` item 1 in
// `docs/superpowers/2026-10-07-port-gaps-medium-decisions.md`): what an
// EXTERNAL module may write with `@Environment(Type.self)` and
// `.environment(_ object:)`.
//
// `typecheckFile` against a PLAIN `import MetalUI` (ruling SA-P). **A guard
// skips silently when `.build/<triple>/debug/Modules` is absent** (CLAUDE.md,
// "Guards"); grep the log for `ENVIRONMENT OBJECT GUARD` to know it ran.

private let skipReason: Comment =
    "built module directory .build/<triple>/debug/Modules holding MetalUI not found — guard skipped"

private func show(_ label: String, _ result: TypecheckResult) {
    print("ENVIRONMENT OBJECT GUARD \(label): succeeded=\(result.succeeded)\n\(result.messages)")
}

/// **2.12** (`MD-H` item 1; SwiftUI's `Environment.init(_:)` pair is
/// constrained to `AnyObject & Observable`). An `@Observable` class is read
/// with `@Environment(M.self)` — non-optional and optional — and provided with
/// `.environment(M())` or `.environment(nil as M?)`. The separating arms: a
/// class that is not `Observable`, and a struct, are each refused.
///
/// Red before: the positive does not compile (no such initialiser). Mutation
/// M2.12 (the `Observable` constraint dropped from both initialisers and the
/// modifier) makes the class control compile.
@Test(.enabled(if: canTypecheck(module: "MetalUI"), skipReason))
func onlyAnObservableClassIsAnEnvironmentObject() throws {
    let positive = try typecheckFile("""
        import Observation
        @Observable public final class M { public var count = 0; public init() {} }
        public struct Reader: Component {
            @Environment(M.self) var m
            @Environment(M.self) var o: M?
            public var content: some ElementGroup { Text("\\(m.count) \\(o?.count ?? 0)") }
        }
        @MainActor public func provide() {
            _ = Row { Reader() }.environment(M())
            _ = Row { Reader() }.environment(nil as M?)
            _ = VStack { Reader() }.environment(M())
        }
        """, importing: "MetalUI")
    show("2.12 positive", positive)
    let notObservable = try typecheckFile("""
        public final class N { public init() {} }
        public struct Reader: Component {
            @Environment(N.self) var n
            public var content: some ElementGroup { Text("x") }
        }
        @MainActor public func provide() { _ = Row { Reader() }.environment(N()) }
        """, importing: "MetalUI")
    show("2.12 class control", notObservable)
    let aStruct = try typecheckFile("""
        public struct S { public init() {} }
        public struct Reader: Component {
            @Environment(S.self) var s
            public var content: some ElementGroup { Text("x") }
        }
        """, importing: "MetalUI")
    show("2.12 struct control", aStruct)
    try #require(positive.succeeded != notObservable.succeeded,
                 "the arms must disagree, or the guard measures nothing:\n\(positive.output)\n\(notObservable.output)")
    #expect(positive.succeeded, "an @Observable class is an environment object:\n\(positive.output)")
    #expect(!notObservable.succeeded, "a class that is not Observable is refused:\n\(notObservable.output)")
    #expect(!aStruct.succeeded, "a struct is refused:\n\(aStruct.output)")
}
