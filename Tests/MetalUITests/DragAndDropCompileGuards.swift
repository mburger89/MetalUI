import Testing
import MetalUITestSupport

// Drag and drop, lane 1, guards G1.1–G1.3 (rulings `DN-A`, `DN-C`, `DN-S`;
// spec §6.3). Every fixture is whole-file Swift 6 (`typecheckFile`, ruling
// SA-P) against a PLAIN import — a `@testable` test cannot prove what an
// external module can write (practices shape 16).
//
// **A guard skips silently when `.build/<triple>/debug/Modules` is absent**
// (CLAUDE.md, "Guards"); grep the log for `DN-A`/`DN-S`/`DN-C` to know these ran.

private let metalUISkipReason: Comment =
    "built module directory .build/<triple>/debug/Modules holding MetalUI not found — guard skipped"
private let platformSkipReason: Comment =
    "built module directory .build/<triple>/debug/Modules holding MetalUIPlatform not found — guard skipped"

/// **G1.1** (`DN-A`). The spellings of spec §2.2 — except
/// `draggable(_:preview:)`, lane 2's (G2.1) — compile under `import MetalUI`,
/// on a `StyledElement` and on a `ProposalElementGroup`, with SwiftUI's
/// trailing-closure shape. `.onDrop(of:isTargeted:perform:)` and `.onDrag { }`
/// do **not** (`DN-A` item 2: not offered).
///
/// Mutation **MG1.1**: an `onDrag` spelling added to `StyledElement` (the
/// negative compiles).
@Test(.enabled(if: canTypecheck(module: "MetalUI"), metalUISkipReason))
func theDragAndDropSpellingsCompileFromAPlainImport() throws {
    let spellings = try typecheckFile("""
        import Foundation
        import MetalUICore

        @MainActor func styled() -> some ElementGroup {
            Box()
                .draggable("s")
                .dropDestination(for: String.self) { items, location in
                    items.count > 0 && location.x.value >= 0
                } isTargeted: { _ in }
        }

        @MainActor func styledDefaults() -> some ElementGroup {
            Text("t").draggable(URL(string: "https://example.com")!).dropDestination(for: Data.self) { _, _ in true }
        }

        @MainActor func proposal() -> some ProposalElementGroup {
            Rectangle()
                .draggable(Data([1, 2]))
                .dropDestination(for: URL.self, action: { (urls: [URL], at: Point<Pixels>) -> Bool in
                    !urls.isEmpty
                }, isTargeted: { _ in })
        }

        @MainActor func types() -> (DraggableModifier<Rectangle>, DropDestinationModifier<Rectangle>) {
            (Rectangle().draggable("s"), Rectangle().dropDestination(for: String.self) { _, _ in true })
        }
        """, importing: "MetalUI")
    let older = try typecheckFile("""
        @MainActor func older() -> some ElementGroup {
            Box().onDrag { }.onDrop(of: [], isTargeted: nil) { _ in true }
        }
        """, importing: "MetalUI")

    print("""
        DN-A spellings: succeeded=\(spellings.succeeded) messages=[\(spellings.messages)]; \
        older succeeded=\(older.succeeded) messages=[\(older.messages)]
        """)

    try #require(spellings.succeeded && !older.succeeded,
                 """
                 the spellings must compile and the older surface must not, or this \
                 guard cannot fail:
                 spellings:
                 \(spellings.output)
                 older:
                 \(older.output)
                 """)
    #expect(older.messages.contains("onDrag"), "refused FOR onDrag:\n\(older.output)")
}

/// **G1.2** (`DN-S`). An outside type writing `Transferable`'s four members,
/// with its own `ContentType`, conforms and is accepted by `draggable` and
/// `dropDestination`. A type writing only SwiftUI's conformer spelling,
/// `static var transferRepresentation`, does **not** conform (`DN-S` item 4).
///
/// Mutation **MG1.2**: a protocol extension defaulting the four members (the
/// negative compiles).
@Test(.enabled(if: canTypecheck(module: "MetalUI"), metalUISkipReason))
func anOutsideTypeCanConformToTransferable() throws {
    let conforming = try typecheckFile("""
        import Foundation

        struct Note: Transferable {
            static let noteType = ContentType("com.example.note", conformingTo: [.utf8PlainText])
            var text: String
            init(text: String) { self.text = text }
            func exportedContentTypes() -> [ContentType] { [Self.noteType] }
            static func importedContentTypes() -> [ContentType] { [Self.noteType] }
            func exported(as contentType: ContentType) -> Data? {
                Self.noteType.conforms(to: contentType) ? Data(text.utf8) : nil
            }
            init?(importing data: Data, contentType: ContentType) {
                guard contentType == Self.noteType else { return nil }
                text = String(decoding: data, as: UTF8.self)
            }
        }

        @MainActor func probe() -> some ElementGroup {
            Box().draggable(Note(text: "n")).dropDestination(for: Note.self) { notes, _ in !notes.isEmpty }
        }
        """, importing: "MetalUI")
    let swiftUISpelling = try typecheckFile("""
        struct Note: Transferable {
            static var transferRepresentation: Int { 0 }
        }
        """, importing: "MetalUI")

    print("""
        DN-S conformance: conforming succeeded=\(conforming.succeeded) messages=[\(conforming.messages)]; \
        swiftUISpelling succeeded=\(swiftUISpelling.succeeded) messages=[\(swiftUISpelling.messages)]
        """)

    try #require(conforming.succeeded && !swiftUISpelling.succeeded,
                 """
                 the four-member conformer must compile and transferRepresentation \
                 alone must not, or this guard cannot fail:
                 conforming:
                 \(conforming.output)
                 swiftUISpelling:
                 \(swiftUISpelling.output)
                 """)
    #expect(swiftUISpelling.messages.contains("Transferable"),
            "refused FOR the conformance:\n\(swiftUISpelling.output)")
}

/// A `PlatformWindow` conformer with every requirement except
/// `beginExternalDrag`, which the caller splices in (or not).
private func conformer(member: String) -> String {
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
        func presentMenu(_ menu: PlatformMenu, at position: Point<Pixels>) -> Bool { false }
        // Colour scheme (`CR-M`), defaultless too, so every arm here carries
        // it; `ColorSchemeCompileGuards` pins it.
        func setPreferredColorScheme(_ colorScheme: ColorScheme?) {}
    \(member)
    }
    """
}

/// **G1.3** (`DN-C` item 2). `PlatformWindow.beginExternalDrag` has **no
/// default implementation** (`EV-AB`'s reason): a conformer that forgets it
/// fails to compile, naming it. **Positive control**: the same conformer with
/// the member — `DN-C` item 3's migration spelling, verbatim — compiles.
///
/// Mutation **MG1.3**: a protocol-extension default answering `false` (the
/// negative compiles).
@Test(.enabled(if: canTypecheck(module: "MetalUIPlatform"), platformSkipReason))
func aPlatformWindowWithoutBeginExternalDragDoesNotCompile() throws {
    let without = try typecheckFile(conformer(member: ""), importing: "MetalUIPlatform")
    let with = try typecheckFile(conformer(member: """
            func beginExternalDrag(_: [DragRepresentation], at: Point<Pixels>) -> Bool { false }
        """), importing: "MetalUIPlatform")

    print("""
        DN-C member required: without succeeded=\(without.succeeded) \
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
    #expect(without.messages.contains("beginExternalDrag"),
            "the negative must be refused FOR beginExternalDrag:\n\(without.output)")
}
