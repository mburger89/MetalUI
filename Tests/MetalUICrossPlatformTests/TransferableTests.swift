import Testing
import Foundation
import MetalUI

// Drag and drop, lane 1, tests 1.1–1.4 (rulings `DN-B`, `DN-S`; spec
// `docs/superpowers/specs/2026-10-01-drag-and-drop-design.md` §6.1). Portable:
// `Transferable` and its `Data`/`URL` conformances are on the surface Linux and
// Windows build, so these run there too. Every answer is an arm of
// `docs/probes/swiftui-drag-and-drop.swift` group `T`, named per assertion.

/// **1.1** (`T1`, `T5`, `T5b`, `T6c`, `T7`). A `String` exports and imports
/// `utf8PlainText` only, as UTF-8; it exports to a supertype it conforms to
/// (`T5b`) where a web URL does not export as plain text (`T6c`).
/// Mutations **M1a** (String's exported types gain `.plainText`) and **M1a′**
/// (`exported(as:)` requires an exact match — reddens the `T5b` arm).
@Test func aStringExportsAndImportsUTF8PlainTextOnly() {
    #expect("héllo".exportedContentTypes() == [.utf8PlainText], "T1: one exported type")
    #expect(String.importedContentTypes() == [.utf8PlainText], "T1: one imported type")
    #expect("héllo".exported(as: .utf8PlainText) == Data("héllo".utf8), "T5: UTF-8")
    #expect("héllo".exported(as: .utf8PlainText)?.count == 6, "T5: é is two UTF-8 bytes")
    #expect("héllo".exported(as: .plainText)?.count == 6, "T5b: exports to a supertype it conforms to")
    #expect("héllo".exported(as: .url) == nil, "not to a type it does not conform to")
    let web = URL(string: "https://example.com")!
    #expect(web.exported(as: .plainText) == nil, "T6c: a URL does not export as plain text")
    #expect(String(importing: Data("héllo".utf8), contentType: .utf8PlainText) == "héllo", "T7")
}

/// **1.2** (`T4`, `T6`, `T6b`). A web URL exports `[url]`, a file URL
/// `[url, fileURL]`; the bytes are the absolute string in UTF-8.
/// Mutation **M1b** (a file URL exports `[url]` only).
@Test func aWebURLExportsURLAndAFileURLExportsBoth() {
    let web = URL(string: "https://example.com/a?b=c")!
    let file = URL(fileURLWithPath: "/tmp/a b.txt")
    #expect(web.exportedContentTypes() == [.url], "T4: a web URL")
    #expect(file.exportedContentTypes() == [.url, .fileURL], "T4: a file URL")
    #expect(web.exported(as: .url) == Data("https://example.com/a?b=c".utf8), "T6")
    #expect(file.exported(as: .fileURL) == Data(file.absoluteString.utf8), "T6b")
    #expect(file.absoluteString == "file:///tmp/a%20b.txt", "the absolute string is percent-encoded")
    #expect(URL.importedContentTypes() == [.url, .fileURL], "T2")
}

/// **1.3** (`T7b`, `T7c`, `T7d`, `T7e`). Each built-in imports only its own
/// types — told a type it does not import, its init is `nil` — and conformance
/// is transitive. Mutations **M1c** (`.url`'s parents gain `.plainText`) and
/// **M1c′** (`Data.init` accepts any type conforming to `.data` — reddens the
/// `T7e` arm).
@Test func eachBuiltInImportsOnlyItsOwnTypesAndConformanceIsTransitive() {
    let png = ContentType("public.png", conformingTo: [.data])
    #expect(String(importing: Data("https://example.com".utf8), contentType: .url) == nil, "T7b")
    #expect(URL(importing: Data("https://example.com".utf8), contentType: .utf8PlainText) == nil, "T7c")
    #expect(URL(importing: Data("https://example.com".utf8), contentType: .plainText) == nil, "T7c")
    #expect(URL(importing: Data("https://example.com".utf8), contentType: .url)
                == URL(string: "https://example.com"), "T7d")
    #expect(Data(importing: Data([1, 2]), contentType: png) == nil, "T7e: Data refuses being told png")
    #expect(Data(importing: Data([1, 2]), contentType: .data) == Data([1, 2]), "told data, it takes the bytes")
    #expect(ContentType.fileURL.conforms(to: .url))
    #expect(ContentType.fileURL.conforms(to: .data), "transitively")
    #expect(ContentType.utf8PlainText.conforms(to: .data), "through plainText and text")
    #expect(ContentType.utf8PlainText.conforms(to: .item))
    #expect(!ContentType.url.conforms(to: .plainText), "a URL is not plain text")
    #expect(!ContentType.item.conforms(to: .data), "item is the root")
    #expect(ContentType.data.conforms(to: .data), "a type conforms to itself")
}

/// **1.4** (`DN-B` item 2). A custom type conforms through its declared
/// parents, transitively, and to nothing else.
/// Mutation **M1d** (conformance not transitive — parents only).
@Test func aCustomContentTypeConformsThroughItsDeclaredParents() {
    let note = ContentType("com.example.note", conformingTo: [.utf8PlainText])
    #expect(note.conforms(to: .utf8PlainText))
    #expect(note.conforms(to: .text), "transitively")
    #expect(note.conforms(to: .data), "transitively")
    #expect(note.conforms(to: .item), "transitively")
    #expect(!note.conforms(to: .url))
    #expect(!note.conformance.contains(note.identifier), "never contains itself")
    let bare = ContentType("com.example.bare")
    #expect(bare.conforms(to: .data) && bare.conforms(to: .item), "the default parent is data")
}
