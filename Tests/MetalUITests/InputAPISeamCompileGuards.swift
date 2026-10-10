import Testing
import MetalUITestSupport

// Compile-time guards for the input APIs' platform seam, lane 1 (spec
// `docs/superpowers/specs/2026-10-08-input-apis-design.md` §4.1, guards 1.1 and
// 1.2; rulings `CI-E` item 5, `CI-J`).
//
// **Every fixture uses `typecheckFile`** — whole-file, Swift 6, a PLAIN
// `import MetalUIPlatform`, as an external module writes it (`SA-P`).
//
// **A guard skips silently when `.build/<triple>/debug/Modules` is absent**
// (CLAUDE.md, "Guards").

private let platformSkipReason: Comment =
    "built module directory .build/<triple>/debug/Modules holding MetalUIPlatform not found — guard skipped"

/// Every `InputEvent` case that existed before this branch, as one `case` list.
private let oldCases = """
    .mouseDown, .mouseUp, .mouseMoved, .mouseDragged, .scrollWheel, .keyDown, .keyUp,
             .modifiersChanged, .textInput, .textComposition, .drop, .rightMouseDown, .rightMouseUp,
             .menuAction, .pointerExited, .fileDialogResult, .alertResult, .toolbarAction
    """

/// A `switch` over `InputEvent` naming every old case, plus `extra` (or not).
private func exhaustiveSwitch(extra: String) -> String {
    """
    func name(_ event: InputEvent) -> String {
        switch event {
        case \(oldCases): return "old"
        \(extra)
        }
    }
    """
}

/// **1.1** (`CI-E` items 1 and 5, `CI-J` item 1). `InputEvent` has the six new
/// cases — `.rightMouseDragged`, `.otherMouseDown`, `.otherMouseDragged`,
/// `.otherMouseUp`, `.magnify`, `.rotate` — so an exhaustive `switch` outside
/// the package that names only the old ones **does not compile** (the
/// migration note's premise), and one that adds the six does (the positive
/// control).
///
/// Mutation: delete `case otherMouseDragged` from `InputEvent` (the "with" arm
/// fails).
@Test(.enabled(if: canTypecheck(module: "MetalUIPlatform"), platformSkipReason))
func anExhaustiveInputEventSwitchWithoutTheInputAPICasesDoesNotCompile() throws {
    let without = try typecheckFile(exhaustiveSwitch(extra: ""), importing: "MetalUIPlatform")
    let with = try typecheckFile(exhaustiveSwitch(extra: """
            case .rightMouseDragged, .otherMouseDown, .otherMouseDragged, .otherMouseUp,
                 .magnify, .rotate: return "new"
        """), importing: "MetalUIPlatform")
    print("""
        CI-E six cases: without succeeded=\(without.succeeded) messages=[\(without.messages)]; \
        with succeeded=\(with.succeeded) messages=[\(with.messages)]
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
    #expect(without.messages.contains("exhaustive"),
            "the negative must be refused for exhaustiveness:\n\(without.output)")
}

/// A `PlatformWindow` conformer with every requirement except
/// `setPointerStyle(_:)`, which the caller splices in (or not).
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
        func presentFileDialog(_: PlatformFileDialog) -> Bool { false }
        func presentAlert(_: PlatformAlert) -> Bool { false }
        func dismissPresentation(token: Int) {}
        func setToolbar(_: PlatformToolbar?) -> Bool { false }
        func setContentSizeLimits(minimum: Size<Pixels>?, maximum: Size<Pixels>?) {}
        func setPreferredColorScheme(_ colorScheme: ColorScheme?) {}
    \(member)
    }
    """
}

/// **1.2** (`CI-J` item 2, `CR-M`'s shape). `PlatformWindow.setPointerStyle(_:)`
/// has **no default implementation** (`EV-AB`'s reason): a conformer that
/// forgets it fails to compile, naming it. **Positive control**: the same
/// conformer with the member — the migration note's spelling, verbatim —
/// compiles.
///
/// Mutation: a protocol-extension default `func setPointerStyle(_:) {}` (the
/// negative compiles).
@Test(.enabled(if: canTypecheck(module: "MetalUIPlatform"), platformSkipReason))
func aPlatformWindowWithoutSetPointerStyleDoesNotCompile() throws {
    let without = try typecheckFile(conformer(member: ""), importing: "MetalUIPlatform")
    let with = try typecheckFile(conformer(member: """
            func setPointerStyle(_ style: PlatformPointerStyle) {}
        """), importing: "MetalUIPlatform")
    print("""
        CI-J member required: without succeeded=\(without.succeeded) \
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
    #expect(without.messages.contains("setPointerStyle"),
            "the negative must be refused FOR setPointerStyle:\n\(without.output)")
}
