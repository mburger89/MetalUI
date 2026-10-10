import Testing
import MetalUITestSupport

// App icon, lane 1, guard G1.1 (ruling `AI-B`; spec §5). Whole-file Swift 6
// (`typecheckFile`, ruling SA-P) against a PLAIN import — a `@testable` test
// cannot prove what an external module can write (practices shape 16).
//
// **A guard skips silently when `.build/<triple>/debug/Modules` is absent**
// (CLAUDE.md, "Guards"); grep the log for `AI-B member required` to know it ran.

private let platformSkipReason: Comment =
    "built module directory .build/<triple>/debug/Modules holding MetalUIPlatform not found — guard skipped"

/// A `Platform` conformer with every requirement except `setApplicationIcon`,
/// which the caller splices in (or not).
private func conformer(member: String) -> String {
    """
    import MetalUICore
    import MetalUIScene

    @MainActor
    final class Conformer: Platform {
        // The app-shell requirements (`AS-H`, `AS-J`).
        var onTerminateRequest: (() -> CloseRequestReply)?
        func replyToTerminateRequest(_ shouldTerminate: Bool) {}
        func terminate() {}
        var onOpenURLs: (([String]) -> Void)?
        func openWindow(title: String, size: Size<Pixels>) throws -> any PlatformWindow {
            throw PlatformError.windowCreationFailed
        }
        func run() {}
        func setMenuBar(_: PlatformMenuBar) {}
    \(member)
    }
    """
}

/// **G1.1** (`AI-B`). `Platform.setApplicationIcon(_:)` has **no default
/// implementation** (`AB-R`/`EV-AB`/`DN-C`'s reason): a conformer that forgets
/// it fails to compile, naming it. **Positive control**: the same conformer
/// with `AI-B`'s migration spelling, verbatim, compiles.
///
/// Mutation **MG1.1**: a protocol-extension default (the negative compiles).
@Test(.enabled(if: canTypecheck(module: "MetalUIPlatform"), platformSkipReason))
func aPlatformWithoutSetApplicationIconDoesNotCompile() throws {
    let without = try typecheckFile(conformer(member: ""), importing: "MetalUIPlatform")
    let with = try typecheckFile(conformer(member: """
            func setApplicationIcon(_: [ImageTexture]) {}
        """), importing: "MetalUIPlatform")

    print("""
        AI-B member required: without succeeded=\(without.succeeded) \
        messages=[\(without.messages)]; with succeeded=\(with.succeeded) \
        messages=[\(with.messages)]
        """)

    try #require(with.succeeded && !without.succeeded,
                 """
                 the control must compile and the negative must not, or this guard \
                 cannot fail:
                 with:
                 \(with.output)
                 without:
                 \(without.output)
                 """)
    #expect(without.messages.contains("setApplicationIcon"),
            "the negative must be refused FOR setApplicationIcon:\n\(without.output)")
}
