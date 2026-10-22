import Testing
import MetalUITestSupport

// `PasteButton`, guard G1.1 (rulings `CP-B`; probe `swiftui-clipboard-extras.swift` arms `-DNEG2`, `-DNEG3`). Whole-file
// Swift 6 (`typecheckFile`, `SA-P`) against a PLAIN import. **A guard skips silently when
// `.build/<triple>/debug/Modules` is absent**; grep the log for `CP-B` to know this ran. The seam's negatives (a conformer
// without `setClipboardChangeHandler`, and the other three item requirements) are `ClipboardCompileGuards.swift`'s G3.1a.

private let metalUISkipReason: Comment =
    "built module directory .build/<triple>/debug/Modules holding MetalUI not found — guard skipped"

/// **G1.1** (`CP-B`). Both SwiftUI initialisers compile from a plain import (a `Transferable` payload; the content-type
/// form), and so do `.disabled` and `.buttonStyle` after them. **Negatives**, each rebuilt as its own file so one cannot hide
/// another: a trailing **label** closure (SwiftUI's `PasteButton` takes none, `-DNEG2`) and a payload that is not
/// `Transferable` (`-DNEG3`) do not compile, and each refusal names `PasteButton` or the payload.
///
/// Mutation **MG1.1**: add `init(label:)`-style trailing label support, or drop the `T: Transferable` bound (the negatives compile).
@Test(.enabled(if: canTypecheck(module: "MetalUI"), metalUISkipReason))
func thePasteButtonSpellingsCompileFromAPlainImportAndASwiftUIMisspellingDoesNot() throws {
    let spellings = try typecheckFile("""
        import Foundation
        import MetalUICore

        struct Note: Transferable {
            static let noteType = ContentType("com.example.note", conformingTo: [.data])
            var text: String
            init(text: String) { self.text = text }
            func exportedContentTypes() -> [ContentType] { [Self.noteType] }
            static func importedContentTypes() -> [ContentType] { [Self.noteType] }
            func exported(as contentType: ContentType) -> Data? { Data(text.utf8) }
            init?(importing data: Data, contentType: ContentType) { text = String(decoding: data, as: UTF8.self) }
        }

        @MainActor func payload() -> some ElementGroup {
            PasteButton(payloadType: Note.self) { notes in _ = notes }
        }

        @MainActor func types() -> some ElementGroup {
            PasteButton(supportedContentTypes: [.plainText, .json]) { (items: [DropItem]) in _ = items.count }
        }

        @MainActor func styled() -> some ElementGroup {
            PasteButton(payloadType: String.self) { _ in }.buttonStyle(.plain).disabled(true)
        }

        @MainActor func inAStack() -> some ElementGroup {
            VStack { PasteButton(payloadType: String.self) { _ in } }
        }
        """, importing: "MetalUI")
    let label = try typecheckFile("""
        @MainActor func labelled() -> some ElementGroup {
            PasteButton(payloadType: String.self, onPaste: { _ in }) { Text("Paste here") }
        }
        """, importing: "MetalUI")
    let notTransferable = try typecheckFile("""
        struct Plain {}
        @MainActor func bad() -> some ElementGroup { PasteButton(payloadType: Plain.self) { _ in } }
        """, importing: "MetalUI")

    print("""
        CP-B spellings: succeeded=\(spellings.succeeded) messages=[\(spellings.messages)]; \
        label succeeded=\(label.succeeded); non-Transferable succeeded=\(notTransferable.succeeded)
        """)

    try #require(spellings.succeeded && !label.succeeded && !notTransferable.succeeded,
                 """
                 the spellings must compile and both negatives must not, or this guard cannot fail:
                 spellings:
                 \(spellings.output)
                 label:
                 \(label.output)
                 non-Transferable:
                 \(notTransferable.output)
                 """)
    #expect(label.messages.contains("PasteButton") || label.messages.contains("label")
                || label.messages.contains("trailing"), "refused FOR the label:\n\(label.output)")
    #expect(notTransferable.messages.contains("Transferable") || notTransferable.messages.contains("Plain"),
            "refused FOR the payload:\n\(notTransferable.output)")
}
