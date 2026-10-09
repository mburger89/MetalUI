import Testing
import MetalUITestSupport

// App shell, lane 1, guards 1.1 and 1.2 (rulings `AS-H`, `AS-J`; spec
// `docs/superpowers/specs/2026-10-08-app-shell-design.md` §4.1). The eleven
// seam requirements have **no default implementation** (`MD-J`/`CR-M`'s rule):
// a conformer that forgets one fails to compile, naming it.
//
// **Every fixture uses `typecheckFile`** — whole-file, Swift 6, a PLAIN
// `import MetalUIPlatform`, as an external module writes it (`SA-P`).
//
// **A guard skips silently when `.build/<triple>/debug/Modules` is absent**
// (CLAUDE.md, "Guards"); grep the log for `AS-H window members required` and
// `AS-H platform members required` to know they ran.

private let platformSkipReason: Comment =
    "built module directory .build/<triple>/debug/Modules holding MetalUIPlatform not found — guard skipped"

/// The seven `PlatformWindow` requirements (`AS-H` item 1, `AS-J` item 2),
/// each in the migration note's minimal honest spelling, keyed by the name a
/// refusal must mention.
private let windowMembers: [(name: String, spelling: String)] = [
    ("onCloseRequest", "var onCloseRequest: (() -> Bool)?"),
    ("close", "func close() { onClose?() }"),
    ("setDocumentEdited", "func setDocumentEdited(_ edited: Bool) {}"),
    ("setRepresentedFilePath", "func setRepresentedFilePath(_ path: String?) {}"),
    ("setTitleBarStyle", "func setTitleBarStyle(_ style: PlatformTitleBarStyle) -> Bool { false }"),
    ("titleBarInsets", "var titleBarInsets: Edges<Pixels> { Edges(top: Pixels(0), right: Pixels(0), bottom: Pixels(0), left: Pixels(0)) }"),
    ("performTitleBarPress", "func performTitleBarPress(clickCount: Int) -> Bool { false }"),
]

/// The four `Platform` requirements (`AS-H` item 2), in the migration note's
/// spelling.
private let platformMembers: [(name: String, spelling: String)] = [
    ("onTerminateRequest", "var onTerminateRequest: (() -> CloseRequestReply)?"),
    ("replyToTerminateRequest", "func replyToTerminateRequest(_ shouldTerminate: Bool) {}"),
    ("terminate", "func terminate() {}"),
    ("onOpenURLs", "var onOpenURLs: (([String]) -> Void)?"),
]

/// A `PlatformWindow` conformer with every requirement that existed before
/// this branch, plus `members`.
private func windowConformer(_ members: [String]) -> String {
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
        var controlActiveState: ControlActiveState { .key }
        var onControlActiveStateChange: ((ControlActiveState) -> Void)?
        var accessibilityReduceMotion: Bool { false }
        var onAccessibilityReduceMotionChange: ((Bool) -> Void)?
        var onClose: (() -> Void)?
        var onAccessibilityRequest: ((AccessibilityRequest) -> Bool)?
        func publishAccessibilityTree(_ tree: AccessibilityTree) {}
        func setTextInputArea(_ caret: Bounds<Pixels>?) {}
        func readClipboard() -> String? { nil }
        func writeClipboard(_ text: String) {}
        func startDisplayLink(_ tick: @escaping (Double) -> Void) {}
        func setDisplayLinkPaused(_ paused: Bool) {}
        func beginExternalDrag(_: [DragRepresentation], at: Point<Pixels>) -> Bool { false }
        func presentMenu(_ menu: PlatformMenu, at position: Point<Pixels>) -> Bool { false }
        func presentFileDialog(_: PlatformFileDialog) -> Bool { false }
        func presentAlert(_: PlatformAlert) -> Bool { false }
        func dismissPresentation(token: Int) {}
        func setToolbar(_: PlatformToolbar?) -> Bool { false }
        func setContentSizeLimits(minimum: Size<Pixels>?, maximum: Size<Pixels>?) {}
        func setPreferredColorScheme(_ colorScheme: ColorScheme?) {}
        func setPointerStyle(_ style: PlatformPointerStyle) {}
    \(members.map { "    " + $0 }.joined(separator: "\n"))
    }
    """
}

/// A `Platform` conformer with every requirement that existed before this
/// branch, plus `members`.
private func platformConformer(_ members: [String]) -> String {
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
        func setMenuBar(_: PlatformMenuBar) {}
    \(members.map { "    " + $0 }.joined(separator: "\n"))
    }
    """
}

/// **1.1** (`AS-H` item 1, `AS-J` item 2). Each of the seven new
/// `PlatformWindow` requirements has no default: a conformer with all seven —
/// the migration note's spelling, verbatim — compiles (the positive control),
/// and each of seven conformers missing exactly one fails, naming it.
///
/// Mutation: a protocol-extension default
/// `func setRepresentedFilePath(_: String?) {}` (that arm compiles).
@Test(.enabled(if: canTypecheck(module: "MetalUIPlatform"), platformSkipReason))
func aPlatformWindowWithoutEachAppShellRequirementDoesNotCompile() throws {
    let all = try typecheckFile(windowConformer(windowMembers.map(\.spelling)), importing: "MetalUIPlatform")
    print("AS-H window members required: all succeeded=\(all.succeeded) messages=[\(all.messages)]")
    try #require(all.succeeded, "the control must compile, or this guard cannot fail:\n\(all.output)")
    for (index, member) in windowMembers.enumerated() {
        var rest = windowMembers.map(\.spelling)
        rest.remove(at: index)
        let without = try typecheckFile(windowConformer(rest), importing: "MetalUIPlatform")
        print("AS-H window members required: without \(member.name) succeeded=\(without.succeeded)")
        #expect(!without.succeeded, "a conformer without \(member.name) must not compile:\n\(without.output)")
        #expect(without.messages.contains(member.name),
                "the refusal must name \(member.name):\n\(without.output)")
    }
}

/// **1.2** (`AS-H` item 2). Each of the four new `Platform` requirements has
/// no default: all four compile, each conformer missing one fails naming it.
///
/// Mutation: a protocol-extension default `func terminate() {}` (that arm
/// compiles).
@Test(.enabled(if: canTypecheck(module: "MetalUIPlatform"), platformSkipReason))
func aPlatformWithoutEachAppShellRequirementDoesNotCompile() throws {
    let all = try typecheckFile(platformConformer(platformMembers.map(\.spelling)), importing: "MetalUIPlatform")
    print("AS-H platform members required: all succeeded=\(all.succeeded) messages=[\(all.messages)]")
    try #require(all.succeeded, "the control must compile, or this guard cannot fail:\n\(all.output)")
    for (index, member) in platformMembers.enumerated() {
        var rest = platformMembers.map(\.spelling)
        rest.remove(at: index)
        let without = try typecheckFile(platformConformer(rest), importing: "MetalUIPlatform")
        print("AS-H platform members required: without \(member.name) succeeded=\(without.succeeded)")
        #expect(!without.succeeded, "a conformer without \(member.name) must not compile:\n\(without.output)")
        #expect(without.messages.contains(member.name),
                "the refusal must name \(member.name):\n\(without.output)")
    }
}
