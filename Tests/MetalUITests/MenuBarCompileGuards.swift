import Testing
import MetalUITestSupport

// SMK port gaps, lane 2, guard 2.21a (ruling `SG-A` item 1; spec
// `docs/superpowers/specs/2026-10-09-smk-gaps-design.md` §5). Whole-file
// Swift 6 (`typecheckFile`, ruling SA-P) against a PLAIN import — a
// `@testable` test cannot prove what an external module can write.
//
// **A guard skips silently when `.build/<triple>/debug/Modules` is absent**
// (CLAUDE.md, "Guards"); grep the log for `SG-A setMenuBar answers` to know it
// ran.

private let platformSkipReason: Comment =
    "built module directory .build/<triple>/debug/Modules holding MetalUIPlatform not found — guard skipped"

/// A `Platform` conformer with every requirement but `setMenuBar`, spliced in.
private func conformer(member: String) -> String {
    """
    import MetalUICore
    import MetalUIScene

    @MainActor
    final class Conformer: Platform {
        func openWindow(title: String, size: Size<Pixels>) throws -> any PlatformWindow {
            throw PlatformError.windowCreationFailed
        }
        func run() {}
        func setApplicationIcon(_: [ImageTexture]) {}
    \(member)
    }
    """
}

/// **2.21a** (`SG-A` item 1). `Platform.setMenuBar(_:)` answers whether the
/// platform shows the bar: a conformer keeping the old `Void` spelling no
/// longer conforms, naming `setMenuBar`. **Positive control**: the migration
/// spelling, `-> Bool { false }`, verbatim, compiles.
///
/// Mutation (run once, red): a protocol-extension default
/// `func setMenuBar(_:) -> Bool { true }` — the `Void` spelling then compiles
/// (it becomes an unrelated overload).
@Test(.enabled(if: canTypecheck(module: "MetalUIPlatform"), platformSkipReason))
func aPlatformWhoseSetMenuBarReturnsNothingDoesNotConform() throws {
    let void = try typecheckFile(conformer(member: """
            func setMenuBar(_: PlatformMenuBar) {}
        """), importing: "MetalUIPlatform")
    let answering = try typecheckFile(conformer(member: """
            func setMenuBar(_: PlatformMenuBar) -> Bool { false }
        """), importing: "MetalUIPlatform")
    print("""
        SG-A setMenuBar answers: void succeeded=\(void.succeeded) messages=[\(void.messages)]; \
        answering succeeded=\(answering.succeeded) messages=[\(answering.messages)]
        """)
    try #require(answering.succeeded && !void.succeeded,
                 """
                 the control must compile and the Void spelling must not, or this guard \
                 cannot fail:
                 answering:
                 \(answering.output)
                 void:
                 \(void.output)
                 """)
    #expect(void.messages.contains("setMenuBar"),
            "the Void spelling must be refused FOR setMenuBar:\n\(void.output)")
}
