import Testing
import MetalUITestSupport

// Platform services, lane 1, guards 1.G1–1.G4 (ruling `SV-B`; spec
// `docs/superpowers/specs/2026-10-04-platform-services-design.md` §6.1). Each of
// the four new `PlatformWindow` requirements has **no default implementation**
// (`AB-R`/`EV-AB`/`DN-C`/`MN-C`'s reason): a conformer that forgets one fails to
// compile, naming it. Every fixture is whole-file Swift 6 (`typecheckFile`,
// ruling SA-P) against a PLAIN import of `MetalUIPlatform`.
//
// **A guard skips silently when `.build/<triple>/debug/Modules` is absent**
// (CLAUDE.md, "Guards"); grep the log for `SV-B member required` to know these
// ran.

private let platformSkipReason: Comment =
    "built module directory .build/<triple>/debug/Modules holding MetalUIPlatform not found — guard skipped"

/// The four members, each spelled exactly as `SV-B` item 5's migration note
/// writes it — so the positive control proves the note compiles.
private let presentFileDialogMember = "func presentFileDialog(_: PlatformFileDialog) -> Bool { false }"
private let presentAlertMember = "func presentAlert(_: PlatformAlert) -> Bool { false }"
private let dismissPresentationMember = "func dismissPresentation(token: Int) {}"
private let setContentSizeLimitsMember =
    "func setContentSizeLimits(minimum: Size<Pixels>?, maximum: Size<Pixels>?) {}"
private let allMembers = [presentFileDialogMember, presentAlertMember, dismissPresentationMember,
                          setContentSizeLimitsMember]

/// A `PlatformWindow` conformer with every requirement `c2b8f48` had, plus the
/// new members in `members`.
private func conformer(members: [String]) -> String {
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
        func setPreferredColorScheme(_ colorScheme: ColorScheme?) {}
        func presentMenu(_: PlatformMenu, at: Point<Pixels>) -> Bool { false }
        func setToolbar(_: PlatformToolbar?) -> Bool { false }
    \(members.map { "    " + $0 }.joined(separator: "\n"))
    }
    """
}

/// Typechecks the conformer without `member` and with all four, and checks the
/// pair: the control compiles, the negative does not, and the refusal names
/// `name`.
private func checkRequired(_ member: String, named name: String) throws {
    let without = try typecheckFile(conformer(members: allMembers.filter { $0 != member }),
                                    importing: "MetalUIPlatform")
    let with = try typecheckFile(conformer(members: allMembers), importing: "MetalUIPlatform")
    print("""
        SV-B member required (\(name)): without succeeded=\(without.succeeded) \
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
    #expect(without.messages.contains(name), "the negative must be refused FOR \(name):\n\(without.output)")
}

/// **1.G1** (`SV-B` item 1). `presentFileDialog(_:)` has no default.
///
/// Mutation **M1.G1**: a protocol-extension default answering `false` (the
/// negative compiles).
@Test(.enabled(if: canTypecheck(module: "MetalUIPlatform"), platformSkipReason))
func aPlatformWindowWithoutPresentFileDialogDoesNotCompile() throws {
    try checkRequired(presentFileDialogMember, named: "presentFileDialog")
}

/// **1.G2** (`SV-B` item 1). `presentAlert(_:)` has no default.
///
/// Mutation **M1.G2**: a default answering `false`.
@Test(.enabled(if: canTypecheck(module: "MetalUIPlatform"), platformSkipReason))
func aPlatformWindowWithoutPresentAlertDoesNotCompile() throws {
    try checkRequired(presentAlertMember, named: "presentAlert")
}

/// **1.G3** (`SV-B` item 1). `dismissPresentation(token:)` has no default.
///
/// Mutation **M1.G3**: an empty default.
@Test(.enabled(if: canTypecheck(module: "MetalUIPlatform"), platformSkipReason))
func aPlatformWindowWithoutDismissPresentationDoesNotCompile() throws {
    try checkRequired(dismissPresentationMember, named: "dismissPresentation")
}

/// **1.G4** (`SV-B` item 1, `SV-M`). `setContentSizeLimits(minimum:maximum:)`
/// has no default.
///
/// Mutation **M1.G4**: an empty default.
@Test(.enabled(if: canTypecheck(module: "MetalUIPlatform"), platformSkipReason))
func aPlatformWindowWithoutSetContentSizeLimitsDoesNotCompile() throws {
    try checkRequired(setContentSizeLimitsMember, named: "setContentSizeLimits")
}
