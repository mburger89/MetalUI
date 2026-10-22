import Testing
import MetalUITestSupport

// Clipboard beyond text, guards 3.1 (rulings `CB-A`, `CB-E`, `CB-J`; spec §5). Every fixture is
// whole-file Swift 6 (`typecheckFile`, ruling SA-P) against a PLAIN import, as an external module
// writes it.
//
// **A guard skips silently when `.build/<triple>/debug/Modules` is absent** (CLAUDE.md,
// "Guards"); grep the log for `CB-E` / `CB-A` to know these ran.

private let metalUISkipReason: Comment =
    "built module directory .build/<triple>/debug/Modules holding MetalUI not found — guard skipped"
private let platformSkipReason: Comment =
    "built module directory .build/<triple>/debug/Modules holding MetalUIPlatform not found — guard skipped"

/// The eight clipboard requirements (`CB-E`'s four, `CP-E`'s four), one line each, so a negative drops exactly one.
private let clipboardMembers: [(name: String, line: String)] = [
    ("writeClipboard", "func writeClipboard(_ representations: [ClipboardRepresentation]) -> Bool { false }"),
    ("clipboardTypeIdentifiers", "func clipboardTypeIdentifiers() -> [String] { [] }"),
    ("readClipboard(identifier:)", "func readClipboard(identifier: String) -> [UInt8]? { nil }"),
    ("setClipboardCommands", "func setClipboardCommands(_ commands: ClipboardCommands) {}"),
    // `CP-E`: the four item requirements.
    ("writeClipboard(items:)", "func writeClipboard(items: [ClipboardItem]) -> Bool { false }"),
    ("clipboardItems", "func clipboardItems() -> [[String]] { [] }"),
    ("readClipboard(item:identifier:)", "func readClipboard(item: Int, identifier: String) -> [UInt8]? { nil }"),
    ("setClipboardChangeHandler", "func setClipboardChangeHandler(_ handler: (@MainActor () -> Void)?) {}"),
]

/// A `PlatformWindow` conformer with every requirement except the clipboard's four, which the
/// caller splices in.
private func conformer(clipboard members: String) -> String {
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
        func performWindowDrag() -> Bool { false }
        // Window chrome's four (`CW-`).
        func setWindowDragRegions(_ regions: [Bounds<Pixels>]) -> Bool { false }
        func performWindowAction(_ action: PlatformWindowAction) -> Bool { false }
        var hasNativeWindowControls: Bool { true }
        var isZoomed: Bool { false }
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
        var accessibilityReduceTransparency: Bool { false }
        var onAccessibilityReduceTransparencyChange: ((Bool) -> Void)?
        var onClose: (() -> Void)?
        var onAccessibilityRequest: ((AccessibilityRequest) -> Bool)?
        func publishAccessibilityTree(_ tree: AccessibilityTree) {}
        func setTextInputArea(_ caret: Bounds<Pixels>?) {}
        func readClipboard() -> String? { nil }
        func writeClipboard(_ text: String) {}
        func startDisplayLink(_ tick: @escaping (Double) -> Void) {}
        func setDisplayLinkPaused(_ paused: Bool) {}
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
    \(members)
    }
    """
}


/// **G3.1a** (`CB-E`). `PlatformWindow`'s four clipboard requirements have **no default**: a
/// conformer missing any one fails to compile, naming it. **Positive control**: the same
/// conformer with all four — `docs/migration.md`'s spelling — compiles.
///
/// Mutation **MG3.1a**: a protocol-extension default for one requirement (its negative compiles).
@Test(.enabled(if: canTypecheck(module: "MetalUIPlatform"), platformSkipReason))
func aPlatformWindowWithoutAClipboardRequirementDoesNotCompile() throws {
    let base = "func beginExternalDrag(_: [DragRepresentation], at: Point<Pixels>) -> Bool { false }\n"
    let all = clipboardMembers.map(\.line).joined(separator: "\n")
    let with = try typecheckFile(conformer(clipboard: base + all), importing: "MetalUIPlatform")
    try #require(with.succeeded, "the control must compile, or this guard cannot fail:\n\(with.output)")
    for dropped in clipboardMembers {
        let kept = clipboardMembers.filter { $0.name != dropped.name }.map(\.line).joined(separator: "\n")
        let without = try typecheckFile(conformer(clipboard: base + kept), importing: "MetalUIPlatform")
        print("CB-E member required: \(dropped.name) without succeeded=\(without.succeeded)")
        #expect(!without.succeeded, "a conformer without \(dropped.name) must not compile")
        #expect(without.messages.contains(dropped.name.components(separatedBy: "(").first ?? dropped.name),
                "refused FOR \(dropped.name):\n\(without.output)")
    }
}

/// **G3.1b** (`CB-A`, `CB-J`; probe `swiftui-clipboard-types.swift` arm S, with its separating arm S-neg:
/// the spellings compile, a non-`Transferable` does not). An external module writes the three modifiers on a `StyledElement`
/// and on proposal content, with SwiftUI's trailing-closure shapes and defaulted `validator:`, and
/// reads `Window.clipboard`. `Clipboard()` does **not** compile (no public initialiser), and neither
/// does `PasteButton` (`CB-N`: not built).
///
/// Mutation **MG3.1b**: a public `init()` on `Clipboard` (the negative compiles).
@Test(.enabled(if: canTypecheck(module: "MetalUI"), metalUISkipReason))
func theClipboardSpellingsCompileFromAPlainImportAndClipboardHasNoInitialiser() throws {
    let spellings = try typecheckFile("""
        import Foundation
        import MetalUICore

        struct Note: Transferable {
            static let noteType = ContentType("com.example.note", conformingTo: [.data])
            var text: String
            init(text: String) { self.text = text }
            func exportedContentTypes() -> [ContentType] { [Self.noteType, .utf8PlainText] }
            static func importedContentTypes() -> [ContentType] { [Self.noteType, .utf8PlainText] }
            func exported(as contentType: ContentType) -> Data? { Data(text.utf8) }
            init?(importing data: Data, contentType: ContentType) { text = String(decoding: data, as: UTF8.self) }
        }

        @MainActor func styled(_ note: Note) -> some ElementGroup {
            Box()
                .focusable()
                .copyable([note])
                .cuttable(for: Note.self) { [note] }
                .pasteDestination(for: Note.self) { notes in _ = notes }
        }

        @MainActor func validated() -> some ElementGroup {
            Box().pasteDestination(for: Note.self, action: { _ in }, validator: { $0.filter { !$0.text.isEmpty } })
        }

        @MainActor func proposal(_ note: Note) -> some ProposalElementGroup {
            Rectangle().copyable([note]).cuttable { [note] }.pasteDestination { (notes: [Note]) in _ = notes }
        }

        @MainActor func imperative(_ window: Window, _ note: Note) -> (Bool, Note?, [String], Bool) {
            (window.clipboard.write(note), window.clipboard.read(Note.self), window.clipboard.contentTypes,
             window.clipboard.hasContent(of: .utf8PlainText))
        }

        @MainActor func list(_ window: Window, _ notes: [Note]) -> Bool { window.clipboard.write(notes) }
        """, importing: "MetalUI")
    let initialiser = try typecheckFile("""
        @MainActor func make() -> Clipboard { Clipboard() }
        """, importing: "MetalUI")
    // `PasteButton` was the third negative here while it was not built (`CB-N`); it is built since `CP-B`
    // and its spellings are `PasteButtonCompileGuards.swift`'s (G1.1).

    print("""
        CB-A spellings: succeeded=\(spellings.succeeded) messages=[\(spellings.messages)]; \
        Clipboard() succeeded=\(initialiser.succeeded)
        """)

    try #require(spellings.succeeded && !initialiser.succeeded,
                 """
                 the spellings must compile and the negative must not, or this guard \
                 cannot fail:
                 spellings:
                 \(spellings.output)
                 Clipboard():
                 \(initialiser.output)
                 """)
    #expect(initialiser.messages.contains("Clipboard"), "refused FOR Clipboard:\n\(initialiser.output)")
}
