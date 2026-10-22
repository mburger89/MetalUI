import Testing
import MetalUITestSupport

// Presentation extras, lane 2, guards (rulings `BG-G`, `BG-K`; spec
// `docs/superpowers/specs/2026-10-22-presentation-extras-design.md` tests 26 and 36). Whole-file Swift 6 fixtures with
// a PLAIN import, as an external module writes them (`SA-P`). **A guard skips silently when
// `.build/<triple>/debug/Modules` is absent** (CLAUDE.md, "Guards"); grep the log for `BG-G values`,
// `BG-G settable` and `BG-K spelling` to know they ran.

private let metalUISkipReason: Comment =
    "built module directory .build/<triple>/debug/Modules holding MetalUI not found — guard skipped"

/// **BG-1** (`BG-G`). `WindowInteractionBehavior` offers exactly SwiftUI's three values: the three compile
/// and are `Hashable`; a fourth spelling and the internal initialiser do not.
///
/// Mutation: make `kind` or the memberwise initialiser reachable (the second arm compiles), or delete
/// `.disabled` (the control fails).
@Test(.enabled(if: canTypecheck(module: "MetalUI"), metalUISkipReason))
func windowInteractionBehaviorOffersExactlyThreeValues() throws {
    let control = try typecheckFile("""
        import MetalUI

        func all() -> Set<WindowInteractionBehavior> {
            [.automatic, .enabled, .disabled]
        }
        """, importing: "MetalUI")
    print("BG-G values: control succeeded=\(control.succeeded) messages=[\(control.messages)]")
    try #require(control.succeeded, "the control must compile, or this guard cannot fail:\n\(control.output)")
    let fourth = try typecheckFile("""
        import MetalUI

        func some() -> WindowInteractionBehavior { .sometimes }
        """, importing: "MetalUI")
    print("BG-G values: fourth succeeded=\(fourth.succeeded)")
    #expect(!fourth.succeeded, "a fourth value must not exist:\n\(fourth.output)")
    let make = try typecheckFile("""
        import MetalUI

        func make() -> WindowInteractionBehavior { WindowInteractionBehavior(kind: .enabled) }
        """, importing: "MetalUI")
    print("BG-G values: make succeeded=\(make.succeeded)")
    #expect(!make.succeeded, "the initialiser must stay internal:\n\(make.output)")
}

/// **BG-2** (`BG-G`). `Window.backgroundDragBehavior` is read and written from outside the module.
///
/// Mutation: make the setter `internal` (the fixture fails to compile).
@Test(.enabled(if: canTypecheck(module: "MetalUI"), metalUISkipReason))
@MainActor func theBackgroundDragBehaviorIsSettableFromOutsideTheModule() throws {
    let settable = try typecheckFile("""
        import MetalUI

        @MainActor func drive(_ window: Window) -> Bool {
            window.backgroundDragBehavior = .enabled
            return window.backgroundDragBehavior == .enabled
        }
        """, importing: "MetalUI")
    print("BG-G settable: succeeded=\(settable.succeeded) messages=[\(settable.messages)]")
    #expect(settable.succeeded, "the property must be public get/set:\n\(settable.output)")
}

/// **BG-3** (`BG-K`). The shape cursor typechecks with the visionOS call (`shape(_:eoFill:size:)`) and with
/// the extras; a call omitting `size:` does not compile (SwiftUI's `size` has no default).
///
/// Mutation: give `size` a default (the second arm compiles), or drop `eoFill` (the control fails).
@Test(.enabled(if: canTypecheck(module: "MetalUI"), metalUISkipReason))
@MainActor func theShapeCursorSpellingTypechecksWithTheVisionOSCall() throws {
    let control = try typecheckFile("""
        import MetalUI
        import MetalUICore

        @MainActor func styles() -> [PointerStyle] {
            let size = Size(width: Pixels(20), height: Pixels(20))
            return [
                .shape(Circle(), size: size),
                .shape(Circle(), eoFill: true, size: size),
                .shape(Circle(), eoFill: false, size: size, hotSpot: .topLeading, fill: .red, outline: .white),
            ]
        }
        """, importing: "MetalUI")
    print("BG-K spelling: control succeeded=\(control.succeeded) messages=[\(control.messages)]")
    try #require(control.succeeded, "the control must compile, or this guard cannot fail:\n\(control.output)")
    let withoutSize = try typecheckFile("""
        import MetalUI

        @MainActor func style() -> PointerStyle { .shape(Circle()) }
        """, importing: "MetalUI")
    print("BG-K spelling: without size succeeded=\(withoutSize.succeeded)")
    #expect(!withoutSize.succeeded, "size has no default:\n\(withoutSize.output)")
}
