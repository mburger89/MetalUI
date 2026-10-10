import Testing
import MetalUITestSupport

// Key and focus scoping, lane C — the proposal `KeyboardModifier`'s one-layer
// rule (ruling `KF-H` item 2; spec
// `docs/superpowers/specs/2026-10-08-key-focus-design.md` §5.3, guard C8, was
// G3 before `KF-W`).
//
// Whole-file, Swift 6, a plain `import MetalUI` (`typecheckFile`, `SA-P`).
// **A guard skips silently when `.build/<triple>/debug/Modules` is absent**
// (CLAUDE.md, "Guards").

private let metalUISkipReason: Comment =
    "built module directory .build/<triple>/debug/Modules holding MetalUI not found — guard skipped"

/// **C8** (`KF-H` item 2, `KF-Z` item 1). A chain of keyboard modifiers on a
/// `MetalView`, written with no contextual type as an app writes it, is one
/// `KeyboardModifier<MetalView>` — every keyboard modifier on a
/// `KeyboardModifier` returns `Self`, and overload resolution prefers it — so
/// the inferred value converts to that type, and not to the nested
/// `KeyboardModifier<KeyboardModifier<MetalView>>` a wrapper-per-modifier
/// spelling would produce. (Annotating the chain itself with the nested type
/// compiles: the contextual type selects the generic `ProposalElementGroup`
/// overload for the last call — `KF-Z` item 1 — so the type is inferred first.)
///
/// Mutation: make `KeyboardModifier.keyContext(_:_:)` return
/// `KeyboardModifier<Self>` (the control fails).
@Test(.enabled(if: canTypecheck(module: "MetalUI"), metalUISkipReason))
func keyboardModifiersMergeIntoOneLayer() throws {
    func chain(_ type: String) -> String {
        """
        import Foundation

        @MainActor func viewport(_ flag: FocusState<Bool>.Binding) {
            let inferred = MetalView { _ in }
                .focusable(interactions: .edit)
                .keyContext("V")
                .onKeyPress("f") { .handled }
                .onKeyPress(.tab, phases: .down) { _ in .handled }
                .onKeyPress(keys: [.upArrow]) { _ in .ignored }
                .onKeyPress(characters: .decimalDigits) { _ in .ignored }
                .onKeyPress { _ in .ignored }
                .focused(flag)
                .focusable()
                .hoverKeyRegion()
            let x: \(type) = inferred
            _ = x
        }
        """
    }
    let control = try typecheckFile(chain("KeyboardModifier<MetalView>"), importing: "MetalUI")
    let negative = try typecheckFile(chain("KeyboardModifier<KeyboardModifier<MetalView>>"),
                                     importing: "MetalUI")
    print("""
        C8 one layer: control succeeded=\(control.succeeded) messages=[\(control.messages)]; \
        negative succeeded=\(negative.succeeded) messages=[\(negative.messages)]
        """)
    try #require(control.succeeded && !negative.succeeded,
                 """
                 the one-layer type must compile and the nested one must not:
                 control:
                 \(control.output)
                 negative:
                 \(negative.output)
                 """)
}
