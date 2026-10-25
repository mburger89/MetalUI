import Testing
import MetalUITestSupport

// Clipboard items, guard G2.1 (rulings `CP-C`, `CP-E`). Whole-file Swift 6 (`typecheckFile`, `SA-P`) against a PLAIN import.
// **A guard skips silently when `.build/<triple>/debug/Modules` is absent**; grep the log for `CP-C` to know this ran. The
// seam's missing-requirement negatives are `ClipboardCompileGuards.swift`'s G3.1a.

private let metalUISkipReason: Comment =
    "built module directory .build/<triple>/debug/Modules holding MetalUI not found — guard skipped"

/// **G2.1** (`CP-C`, `CP-E`). From a plain import: `ClipboardItem`/`ClipboardPayload` with both `ClipboardBytes` spellings
/// (`.now`, `.later`), several-item `copyable`/`cuttable`, and `Window.clipboard.readAll`/`itemCount`/`write([…])` compile.
/// **Negatives**, each its own file: `ClipboardItemPack` (a `package` type) and a `Clipboard()` initialiser are not reachable
/// from outside the package.
///
/// Mutation **MG2.1**: make `ClipboardItemPack` `public` (its negative compiles) or drop `Clipboard.readAll` (the spellings fail).
@Test(.enabled(if: canTypecheck(module: "MetalUI"), metalUISkipReason))
func theClipboardItemSpellingsCompileFromAPlainImportAndThePackIsUnreachable() throws {
    let spellings = try typecheckFile("""
        import Foundation
        import MetalUICore
        import MetalUIPlatform

        struct Note: Transferable {
            static let noteType = ContentType("com.example.note", conformingTo: [.data])
            var text: String
            init(text: String) { self.text = text }
            func exportedContentTypes() -> [ContentType] { [Self.noteType] }
            static func importedContentTypes() -> [ContentType] { [Self.noteType] }
            func exported(as contentType: ContentType) -> Data? { Data(text.utf8) }
            init?(importing data: Data, contentType: ContentType) { text = String(decoding: data, as: UTF8.self) }
        }

        func item() -> ClipboardItem {
            ClipboardItem(payloads: [
                ClipboardPayload(type: PasteboardType(identifier: "com.example.note"), bytes: .now([1, 2])),
                ClipboardPayload(type: PasteboardType(identifier: "public.utf8-plain-text"), bytes: .later { [3] }),
            ])
        }

        @MainActor func source() -> some ElementGroup {
            Box().focusable()
                .copyable([Note(text: "a"), Note(text: "b")])
                .cuttable(for: Note.self) { [Note(text: "c")] }
                .pasteDestination(for: Note.self) { (notes: [Note]) in _ = notes.count }
        }

        @MainActor func fromCode(_ window: Window) -> (Int, [Note], Bool) {
            let wrote = window.clipboard.write([Note(text: "a"), Note(text: "b")])
            return (window.clipboard.itemCount, window.clipboard.readAll(Note.self), wrote)
        }
        """, importing: "MetalUI")
    let pack = try typecheckFile("""
        import MetalUIPlatform
        func leak() -> [UInt8]? { ClipboardItemPack.encode([]) }
        """, importing: "MetalUI")
    let initialiser = try typecheckFile("""
        @MainActor func make(_ window: Window) -> Clipboard { Clipboard(platform: window.platformWindow) }
        """, importing: "MetalUI")

    print("""
        CP-C spellings: succeeded=\(spellings.succeeded) messages=[\(spellings.messages)]; \
        pack succeeded=\(pack.succeeded); initialiser succeeded=\(initialiser.succeeded)
        """)

    try #require(spellings.succeeded && !pack.succeeded && !initialiser.succeeded,
                 """
                 the spellings must compile and both negatives must not, or this guard cannot fail:
                 spellings:
                 \(spellings.output)
                 pack:
                 \(pack.output)
                 initialiser:
                 \(initialiser.output)
                 """)
    #expect(pack.messages.contains("ClipboardItemPack"), "refused FOR the pack:\n\(pack.output)")
    #expect(initialiser.messages.contains("Clipboard") || initialiser.messages.contains("platform"),
            "refused FOR the initialiser:\n\(initialiser.output)")
}
