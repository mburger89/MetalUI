import Testing
import MetalUITestSupport

// Compile-time guards for plan task 9's control state, lane 3 (the seam):
// `docs/superpowers/specs/2026-09-25-environment-control-state-design.md` §6,
// T3.4 and T3.5, ruling `EV-AB`.
//
// **Every fixture uses `typecheckFile`** — whole-file, Swift 6, a PLAIN
// import, as an external module writes it (`SA-P`); a `@testable` test cannot
// prove an access level (practices shape 16).
//
// **A guard skips silently when `.build/<triple>/debug/Modules` is absent**
// (CLAUDE.md, "Guards").

private let platformSkipReason: Comment =
    "built module directory .build/<triple>/debug/Modules holding MetalUIPlatform not found — guard skipped"
private let metalUISkipReason: Comment =
    "built module directory .build/<triple>/debug/Modules holding MetalUI not found — guard skipped"

/// A `PlatformWindow` conformer with every requirement except the
/// control-active-state pair, which the caller splices in (or not).
private func conformer(pair: String) -> String {
    """
    import MetalUICore
    import MetalUIScene

    @MainActor
    final class Conformer: PlatformWindow {
        var contentSize: Size<Pixels> { Size(width: Pixels(1), height: Pixels(1)) }
        var scaleFactor: Float { 1 }
        var renderer: any WindowRenderer { fatalError("never drawn") }
        var title: String = ""
        var appearance: Appearance { .light }
        var onInput: ((InputEvent) -> Bool)?
        var onResize: ((Size<Pixels>, Float) -> Void)?
        var onAppearanceChange: ((Appearance) -> Void)?
        var onClose: (() -> Void)?
        var onAccessibilityRequest: ((AccessibilityRequest) -> Bool)?
        func publishAccessibilityTree(_ tree: AccessibilityTree) {}
        func setTextInputArea(_ caret: Bounds<Pixels>?) {}
        func readClipboard() -> String? { nil }
        func writeClipboard(_ text: String) {}
        func startDisplayLink(_ tick: @escaping (Double) -> Void) {}
        func setDisplayLinkPaused(_ paused: Bool) {}
    \(pair)
    }
    """
}

/// **T3.4.** `PlatformWindow`'s `controlActiveState` and
/// `onControlActiveStateChange` have **no default implementation** (`EV-AB`,
/// `AB-R`'s reason): a conformer that forgets them fails to compile, naming
/// both, rather than compiling into a window whose controls never learn it
/// lost key. **Positive control**: the same conformer with the pair compiles,
/// so the negative is refused for the pair and nothing else.
///
/// Imports `MetalUIPlatform` itself — the module a backend (`Backends/SDL`)
/// imports — which `typecheckFile` can see under `#filePath`'s layout.
///
/// Mutation: **MG7** a protocol-extension default for the pair (the negative
/// compiles).
@Test(.enabled(if: canTypecheck(module: "MetalUIPlatform"), platformSkipReason))
func aPlatformWindowWithoutTheControlActiveStatePairDoesNotCompile() throws {
    let without = try typecheckFile(conformer(pair: ""), importing: "MetalUIPlatform")
    let with = try typecheckFile(conformer(pair: """
            var controlActiveState: ControlActiveState { .key }
            var onControlActiveStateChange: ((ControlActiveState) -> Void)?
        """), importing: "MetalUIPlatform")

    print("""
        EV-AB pair required: without succeeded=\(without.succeeded) \
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
    #expect(without.messages.contains("controlActiveState"),
            "the negative must be refused FOR controlActiveState:\n\(without.output)")
    #expect(without.messages.contains("onControlActiveStateChange"),
            "the negative must be refused FOR onControlActiveStateChange:\n\(without.output)")
}

/// **T3.5.** `Window.controlActiveState` is `public private(set)`: an
/// external module reads it (the control) and cannot assign it — the platform
/// window is its only writer, through `onControlActiveStateChange`.
///
/// Mutation: **MG8** the setter made `public` (the negative compiles).
@Test(.enabled(if: canTypecheck(module: "MetalUI"), metalUISkipReason))
func theWindowsControlActiveStateIsReadableButNotSettableOutsideTheModule() throws {
    let read = try typecheckFile("""
        @MainActor func probe(_ w: Window) -> ControlActiveState { w.controlActiveState }
        """, importing: "MetalUI")
    let write = try typecheckFile("""
        @MainActor func probe(_ w: Window) { w.controlActiveState = .inactive }
        """, importing: "MetalUI")

    print("""
        EV-AB window state: read succeeded=\(read.succeeded) \
        messages=[\(read.messages)]; write succeeded=\(write.succeeded) \
        messages=[\(write.messages)]
        """)

    try #require(read.succeeded && !write.succeeded,
                 """
                 the read must compile and the write must not, or this guard \
                 cannot fail:
                 read:
                 \(read.output)
                 write:
                 \(write.output)
                 """)
    #expect(write.messages.contains("controlActiveState") && write.messages.contains("inaccessible"),
            "the write must be refused FOR the setter's access:\n\(write.output)")
}
