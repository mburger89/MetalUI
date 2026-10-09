import Testing
import MetalUITestSupport

// Plan task 13, lane 1, guards 1.14 and 1.15 (ruling `AN-AD`). Every fixture
// is whole-file Swift 6 (`typecheckFile`, ruling SA-P) against a PLAIN import —
// a `@testable` test cannot prove an access level (practices shape 16).
//
// **A guard skips silently when `.build/<triple>/debug/Modules` is absent**
// (CLAUDE.md, "Guards"); grep the log for `AN-AD` to know these ran.

private let metalUISkipReason: Comment =
    "built module directory .build/<triple>/debug/Modules holding MetalUI not found — guard skipped"
private let platformSkipReason: Comment =
    "built module directory .build/<triple>/debug/Modules holding MetalUIPlatform not found — guard skipped"

/// **1.14.** `EnvironmentValues.accessibilityReduceMotion` is
/// `public internal(set)` — SwiftUI's key path is get-only (the probe
/// header's typecheck) — so an external module reads it (the control) and a
/// scope cannot write it: `.environment(\.accessibilityReduceMotion, true)`
/// does not compile, because the key path is not writable outside the module.
///
/// Mutation **MG1.14**: the setter made `public` (the negative compiles).
@Test(.enabled(if: canTypecheck(module: "MetalUI"), metalUISkipReason))
func aScopeCannotWriteReduceMotion() throws {
    let read = try typecheckFile("""
        @MainActor func probe(_ values: EnvironmentValues) -> Bool { values.accessibilityReduceMotion }
        """, importing: "MetalUI")
    let write = try typecheckFile("""
        @MainActor func probe() -> some ElementGroup {
            Box().environment(\\.accessibilityReduceMotion, true)
        }
        """, importing: "MetalUI")

    print("""
        AN-AD reduce motion: read succeeded=\(read.succeeded) messages=[\(read.messages)]; \
        write succeeded=\(write.succeeded) messages=[\(write.messages)]
        """)

    try #require(read.succeeded && !write.succeeded,
                 """
                 the read must compile and the scope write must not, or this guard \
                 cannot fail:
                 read:
                 \(read.output)
                 write:
                 \(write.output)
                 """)
    #expect(write.messages.contains("WritableKeyPath") || write.messages.contains("get-only")
                || write.messages.contains("accessibilityReduceMotion"),
            "the write must be refused FOR the key path's writability:\n\(write.output)")
}

/// A `PlatformWindow` conformer with every requirement except the Reduce
/// Motion pair, which the caller splices in (or not).
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
        var controlActiveState: ControlActiveState { .key }
        var onControlActiveStateChange: ((ControlActiveState) -> Void)?
        var onClose: (() -> Void)?
        var onAccessibilityRequest: ((AccessibilityRequest) -> Bool)?
        func publishAccessibilityTree(_ tree: AccessibilityTree) {}
        func setTextInputArea(_ caret: Bounds<Pixels>?) {}
        func readClipboard() -> String? { nil }
        func writeClipboard(_ text: String) {}
        func startDisplayLink(_ tick: @escaping (Double) -> Void) {}
        func setDisplayLinkPaused(_ paused: Bool) {}
        // Drag and drop's hand-off (`DN-C` item 2), defaultless too, so every
        // arm here carries it; `DragAndDropCompileGuards` pins it.
        func beginExternalDrag(_ representations: [DragRepresentation], at position: Point<Pixels>) -> Bool { false }
        func presentMenu(_ menu: PlatformMenu, at position: Point<Pixels>) -> Bool { false }
        // Platform services (`SV-B`), defaultless too, so every arm here carries
        // them; `PlatformServicesCompileGuards` pins them.
        func presentFileDialog(_: PlatformFileDialog) -> Bool { false }
        func presentAlert(_: PlatformAlert) -> Bool { false }
        func dismissPresentation(token: Int) {}
        func setToolbar(_: PlatformToolbar?) -> Bool { false }
        func setContentSizeLimits(minimum: Size<Pixels>?, maximum: Size<Pixels>?) {}
        func setPointerStyle(_ style: PlatformPointerStyle) {}
        // Colour scheme (`CR-M`), defaultless too, so every arm here carries
        // it; `ColorSchemeCompileGuards` pins it.
        func setPreferredColorScheme(_ colorScheme: ColorScheme?) {}
    \(pair)
    }
    """
}

/// **1.15.** `PlatformWindow`'s `accessibilityReduceMotion` and
/// `onAccessibilityReduceMotionChange` have **no default implementation**
/// (`AN-AD`, `EV-AB`'s reason): a conformer that forgets them fails to
/// compile, naming both. **Positive control**: the same conformer with the
/// pair — `AN-AH` item 7's migration spelling, verbatim — compiles.
///
/// Mutation **MG1.15**: a protocol-extension default for the pair (the
/// negative compiles).
@Test(.enabled(if: canTypecheck(module: "MetalUIPlatform"), platformSkipReason))
func aPlatformWindowWithoutTheReduceMotionPairDoesNotCompile() throws {
    let without = try typecheckFile(conformer(pair: ""), importing: "MetalUIPlatform")
    let with = try typecheckFile(conformer(pair: """
            var accessibilityReduceMotion: Bool { false }
            var onAccessibilityReduceMotionChange: ((Bool) -> Void)?
        """), importing: "MetalUIPlatform")

    print("""
        AN-AD pair required: without succeeded=\(without.succeeded) \
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
    #expect(without.messages.contains("accessibilityReduceMotion"),
            "the negative must be refused FOR accessibilityReduceMotion:\n\(without.output)")
    #expect(without.messages.contains("onAccessibilityReduceMotionChange"),
            "the negative must be refused FOR onAccessibilityReduceMotionChange:\n\(without.output)")
}
