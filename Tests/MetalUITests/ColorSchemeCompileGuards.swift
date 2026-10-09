import Testing
import MetalUITestSupport

// Compile-time guards for colour and colour scheme, lane 2 (spec
// `docs/superpowers/specs/2026-10-03-colour-design.md` §6.2, guards 2.18 and
// 2.19; rulings `CR-J` item 1, `CR-M`).
//
// **Every fixture uses `typecheckFile`** — whole-file, Swift 6, a PLAIN
// import, as an external module writes it (`SA-P`).
//
// **A guard skips silently when `.build/<triple>/debug/Modules` is absent**
// (CLAUDE.md, "Guards").

private let platformSkipReason: Comment =
    "built module directory .build/<triple>/debug/Modules holding MetalUIPlatform not found — guard skipped"
private let metalUISkipReason: Comment =
    "built module directory .build/<triple>/debug/Modules holding MetalUI not found — guard skipped"

/// A `PlatformWindow` conformer with every requirement except
/// `setPreferredColorScheme(_:)`, which the caller splices in (or not).
private func conformer(member: String) -> String {
    """
    import MetalUICore
    import MetalUIScene

    @MainActor
    final class Conformer: PlatformWindow {
        // The app-shell requirements (`AS-H`, `AS-J`).
        var onCloseRequest: (() -> Bool)?
        func close() { onClose?() }
        func setDocumentEdited(_ edited: Bool) {}
        func setRepresentedFilePath(_ path: String?) {}
        func setTitleBarStyle(_ style: PlatformTitleBarStyle) -> Bool { false }
        var titleBarInsets: Edges<Pixels> { Edges(all: Pixels(0)) }
        func performTitleBarPress(clickCount: Int) -> Bool { false }
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
        // Platform services (`SV-B`), defaultless too, so every arm here carries
        // them; `PlatformServicesCompileGuards` pins them.
        func presentFileDialog(_: PlatformFileDialog) -> Bool { false }
        func presentAlert(_: PlatformAlert) -> Bool { false }
        func dismissPresentation(token: Int) {}
        func setToolbar(_: PlatformToolbar?) -> Bool { false }
        func setContentSizeLimits(minimum: Size<Pixels>?, maximum: Size<Pixels>?) {}
        func setPointerStyle(_ style: PlatformPointerStyle) {}
    \(member)
    }
    """
}

/// **2.18** (`CR-M`). `PlatformWindow.setPreferredColorScheme(_:)` has **no
/// default implementation** (`EV-AB`'s reason): a conformer that forgets it
/// fails to compile, naming it. **Positive control**: the same conformer with
/// the member — the migration note's spelling, verbatim — compiles.
///
/// Mutation: a protocol-extension default (the negative compiles).
@Test(.enabled(if: canTypecheck(module: "MetalUIPlatform"), platformSkipReason))
func aPlatformWindowWithoutSetPreferredColorSchemeDoesNotCompile() throws {
    let without = try typecheckFile(conformer(member: ""), importing: "MetalUIPlatform")
    let with = try typecheckFile(conformer(member: """
            func setPreferredColorScheme(_ colorScheme: ColorScheme?) {}
        """), importing: "MetalUIPlatform")
    print("""
        CR-M member required: without succeeded=\(without.succeeded) \
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
    #expect(without.messages.contains("setPreferredColorScheme"),
            "the negative must be refused FOR setPreferredColorScheme:\n\(without.output)")
}

/// **2.19** (`CR-J` item 1). The `Appearance` spelling still compiles, as a
/// plain alias of `ColorScheme`, beside `Theme.forAppearance(_:)` and the new
/// public surface an app writes: the window's scheme, preference and
/// variants, the app's, and the modifier. **Positive control** for the
/// fixture: a deliberately wrong line (`let _: Int = ColorScheme.dark`) is
/// refused.
///
/// Mutation: delete the typealias.
@Test(.enabled(if: canTypecheck(module: "MetalUI"), metalUISkipReason))
func theAppearanceSpellingStillCompiles() throws {
    let source = """
        @MainActor func use(window: Window, app: App) {
            let a: Appearance = ColorScheme.dark
            let s: ColorScheme = a
            _ = Theme.forAppearance(.dark)
            _ = Theme.forAppearance(s)
            let current: ColorScheme = window.colorScheme
            window.preferredColorScheme = current
            window.lightTheme = .light
            window.darkTheme = .dark
            app.preferredColorScheme = nil
            app.lightTheme = window.lightTheme
            app.darkTheme = window.darkTheme
            _ = Box().preferredColorScheme(.dark)
            _ = Rectangle().preferredColorScheme(nil)
        }
        """
    let result = try typecheckFile(source, importing: "MetalUI")
    let negative = try typecheckFile("func f() { let _: Int = ColorScheme.dark }", importing: "MetalUI")
    print("CR-J Appearance alias: succeeded=\(result.succeeded) messages=[\(result.messages)]")
    try #require(!negative.succeeded && negative.messages.contains("Int"),
                 "the fixture must be able to fail, for the type:\n\(negative.output)")
    #expect(result.succeeded, "\(result.output)")
}
