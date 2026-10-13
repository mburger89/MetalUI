import Testing
import MetalUITestSupport

// C14 lane 2, guards 2.11 (`IV-B`): `EquatableComponent` has no initialiser outside
// the module, and `.equatable()` is offered only to `Equatable` components. A fixture
// is a whole Swift 6 file with plain imports. **A guard skips silently when
// `.build/<triple>/debug/Modules` is absent**; grep the log for `IV-B`.

private let skipReason: Comment =
    "built module directory .build/<triple>/debug/Modules holding MetalUI not found — guard skipped"

private let uiBuilt = canTypecheck(module: "MetalUI")

/// **2.11a** — the separating control compiles (`.equatable()` on an `Equatable`
/// component, the result named by its public type); the initialiser does not.
/// Mutation: `EquatableComponent.init(component:)` made `public` → red.
@Test(.enabled(if: uiBuilt, skipReason))
func aPlainImportCannotConstructAnEquatableComponent() throws {
    let control = try typecheckFile("""
        import MetalUI
        @MainActor struct Leaf: Component, @MainActor Equatable {
            var content: some ElementGroup { EmptyGroup() }
        }
        @MainActor func make() -> EquatableComponent<Leaf> { Leaf().equatable() }
        """, importing: "MetalUI")
    try #require(control.succeeded, "the control must compile:\n\(control.output)")

    let direct = try typecheckFile("""
        import MetalUI
        @MainActor struct Leaf: Component, @MainActor Equatable {
            var content: some ElementGroup { EmptyGroup() }
        }
        @MainActor func make() -> EquatableComponent<Leaf> { EquatableComponent(component: Leaf()) }
        """, importing: "MetalUI")
    #expect(!direct.succeeded, "the initialiser must be unreachable:\n\(direct.output)")
}

/// **2.11b** — `.equatable()` on a component that is not `Equatable` does not
/// compile. Mutation: the `where Self: Equatable` clause removed → red (and the
/// control then also needs `Equatable`, so the mutation is the clause).
@Test(.enabled(if: uiBuilt, skipReason))
func equatableIsOfferedOnlyToEquatableComponents() throws {
    let result = try typecheckFile("""
        import MetalUI
        @MainActor struct Plain: Component {
            var content: some ElementGroup { EmptyGroup() }
        }
        @MainActor func make() { _ = Plain().equatable() }
        """, importing: "MetalUI")
    #expect(!result.succeeded, "a non-Equatable component must not offer equatable():\n\(result.output)")
}
