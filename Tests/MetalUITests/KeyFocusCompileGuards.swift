import Testing
import MetalUITestSupport

// Compile-time guards for key and focus scoping, lane A (spec
// `docs/superpowers/specs/2026-10-08-key-focus-design.md` §5.1, guards G1, G2,
// G4; rulings `KF-B`, `KF-F`, `KF-W` item 2).
//
// **Every fixture uses `typecheckFile`** — whole-file, Swift 6, a PLAIN
// `import MetalUI`, as an external module writes it (`SA-P`): G4 is about what
// an external module cannot write, which a `@testable` test cannot see.
//
// **A guard skips silently when `.build/<triple>/debug/Modules` is absent**
// (CLAUDE.md, "Guards"). The proposal vocabulary's arm of G1 is lane C's
// (`KeyboardModifier`, `KF-W` item 1; its own guard C8).

private let metalUISkipReason: Comment =
    "built module directory .build/<triple>/debug/Modules holding MetalUI not found — guard skipped"

/// Requires `control` to compile and `negative` not to, printing both.
private func separate(_ label: String, control: TypecheckResult, negative: TypecheckResult) throws {
    print("""
        \(label): control succeeded=\(control.succeeded) messages=[\(control.messages)]; \
        negative succeeded=\(negative.succeeded) messages=[\(negative.messages)]
        """)
    try #require(control.succeeded && !negative.succeeded,
                 """
                 the control must compile and the negative must not, or this guard cannot fail:
                 control:
                 \(control.output)
                 negative:
                 \(negative.output)
                 """)
}

/// **G1** (`KF-B` item 1). SwiftUI's five `onKeyPress` spellings compile on a
/// `StyledElement` from an external module — a `Box`, a `TextField`, a `Text`
/// — each returning `Self` (a chain keeps its type); an action returning
/// `Bool` (`onKey`'s shape) does not.
///
/// Mutation: rename the `keys:` label to `keySet:` (the control fails).
@Test(.enabled(if: canTypecheck(module: "MetalUI"), metalUISkipReason))
func theOnKeyPressFamilyCompilesOnBothVocabularies() throws {
    let control = try typecheckFile("""
        import Foundation

        @MainActor func spellings(_ text: String) {
            let a: Box<EmptyGroup> = Box()
                .onKeyPress(.upArrow) { .handled }
                .onKeyPress(.tab, phases: .down) { press in .handled }
                .onKeyPress(keys: [.upArrow, .downArrow]) { press in .ignored }
                .onKeyPress(keys: ["a"], phases: .all) { press in .ignored }
                .onKeyPress(characters: .decimalDigits) { press in .ignored }
                .onKeyPress(characters: .letters, phases: [.down, .repeat]) { press in .handled }
                .onKeyPress(phases: .all) { press in .handled }
                .onKeyPress { press in .ignored }
            let b: TextField = TextField("Qty", text: text) { _ in }
                .onKeyPress(characters: CharacterSet.decimalDigits.inverted) { _ in .handled }
            let c: Text = Text("t").onKeyPress("x") { .handled }
            _ = (a, b, c)
        }
        """, importing: "MetalUI")
    let negative = try typecheckFile("""
        @MainActor func spellings() {
            _ = Box().onKeyPress(.upArrow) { true }
        }
        """, importing: "MetalUI")
    try separate("G1 onKeyPress family", control: control, negative: negative)
}

/// **G2** (`KF-F` item 2). `.focusable()` with no arguments still resolves (it
/// is `focusable(_:)`'s default), and `focusable(_:)` and
/// `focusable(_:interactions:)` compile with SwiftUI's arguments; an unknown
/// interaction does not.
///
/// Mutation: drop the `= true` default on `focusable(_:)` (the control's
/// `.focusable()` fails).
@Test(.enabled(if: canTypecheck(module: "MetalUI"), metalUISkipReason))
func focusableWithNoArgumentsStillResolvesAndInteractionsCompile() throws {
    let control = try typecheckFile("""
        @MainActor func spellings() {
            let a: Box<EmptyGroup> = Box().focusable()
            let b: Box<EmptyGroup> = Box().focusable(false)
            let c: Box<EmptyGroup> = Box().focusable(interactions: .edit)
            let d: Box<EmptyGroup> = Box().focusable(true, interactions: [.activate, .edit])
            let e: Box<EmptyGroup> = Box().focusable(interactions: .automatic)
            let f: Box<EmptyGroup> = Box().hoverKeyRegion().hoverKeyRegion(false)
            _ = (a, b, c, d, e, f)
        }
        """, importing: "MetalUI")
    let negative = try typecheckFile("""
        @MainActor func spellings() {
            _ = Box().focusable(interactions: .bogus)
        }
        """, importing: "MetalUI")
    try separate("G2 focusable", control: control, negative: negative)
    #expect(negative.messages.contains("bogus"), "refused for the unknown member:\n\(negative.output)")
}

/// **G4** (`KF-B` item 1, `KF-W` item 2). An external module cannot make a
/// `KeyPress` — its initializer is internal — while reading `key`,
/// `characters`, `modifiers` and `phase` inside an `onKeyPress` closure
/// compiles (the positive control).
///
/// Mutation: make `KeyPress.init` public (the negative compiles).
@Test(.enabled(if: canTypecheck(module: "MetalUI"), metalUISkipReason))
func keyPressHasNoPublicInitializer() throws {
    let control = try typecheckFile("""
        @MainActor func read() {
            _ = Box().onKeyPress { press in
                let key: KeyEquivalent = press.key
                let characters: String = press.characters
                let modifiers: EventModifiers = press.modifiers
                let phase: KeyPress.Phases = press.phase
                return key == .upArrow && characters.isEmpty && modifiers.isEmpty && phase == .down
                    ? .handled : .ignored
            }
        }
        """, importing: "MetalUI")
    let negative = try typecheckFile("""
        func make() -> KeyPress {
            KeyPress(phase: .down, key: "a", characters: "a", modifiers: [])
        }
        """, importing: "MetalUI")
    try separate("G4 KeyPress init", control: control, negative: negative)
    #expect(negative.messages.contains("initializer") || negative.messages.contains("inaccessible")
                || negative.messages.contains("internal"),
            "refused for access, not a typo:\n\(negative.output)")
}
