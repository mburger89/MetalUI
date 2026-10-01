import Foundation
import MetalUIPlatform

// Drag and drop's payload protocol (rulings `DN-B`, `DN-S`). MetalUI's own,
// because CoreTransferable exists only on Apple platforms and its
// representations are asynchronous, where MetalUI's drop path delivers items
// inside one input event on every platform. Evidence:
// `docs/probes/swiftui-drag-and-drop.swift`, group `T`.

/// A uniform type identifier and the identifiers it conforms to — UTType's
/// conformance reduced to what drag and drop matches on (ruling `DN-B` item 2).
///
/// Conformance is **transitive**: a type conforms to its declared parents and
/// to everything they conform to. Every built-in conforms to ``item``, and
/// every one but ``item`` to ``data``; a custom type does too unless declared
/// otherwise, since ``init(_:conformingTo:)`` defaults its parents to
/// `[.data]`.
public struct ContentType: Hashable, Sendable, CustomStringConvertible {
    /// The identifier, e.g. `public.utf8-plain-text`.
    public let identifier: String
    /// Every identifier this type conforms to, transitively; never contains
    /// ``identifier``.
    public let conformance: Set<String>

    /// A type named `identifier` conforming to `parents` and, transitively,
    /// to everything they conform to.
    public init(_ identifier: String, conformingTo parents: [ContentType] = [.data]) {
        self.identifier = identifier
        var all = Set<String>()
        for parent in parents {
            all.insert(parent.identifier)
            all.formUnion(parent.conformance)
        }
        all.remove(identifier)
        self.conformance = all
    }

    private init(root identifier: String) {
        self.identifier = identifier
        self.conformance = []
    }

    /// Whether this type is `other` or conforms to it.
    public func conforms(to other: ContentType) -> Bool {
        identifier == other.identifier || conformance.contains(other.identifier)
    }

    /// The identifier.
    public var description: String { identifier }

    /// `public.item`: the root; conforms to nothing.
    public static let item = ContentType(root: "public.item")
    /// `public.data`: bytes. Conforms to ``item``.
    public static let data = ContentType("public.data", conformingTo: [.item])
    /// `public.text`. Conforms to ``data``.
    public static let text = ContentType("public.text", conformingTo: [.data])
    /// `public.plain-text`. Conforms to ``text``.
    public static let plainText = ContentType("public.plain-text", conformingTo: [.text])
    /// `public.utf8-plain-text`, what a `String` drags as. Conforms to ``plainText``.
    public static let utf8PlainText = ContentType("public.utf8-plain-text", conformingTo: [.plainText])
    /// `public.url`. Conforms to ``data``.
    public static let url = ContentType("public.url", conformingTo: [.data])
    /// `public.file-url`. Conforms to ``url``.
    public static let fileURL = ContentType("public.file-url", conformingTo: [.url])

    /// The seam's spelling of this type (ruling `DN-B` item 4), its
    /// conformance in a stable order.
    var pasteboardType: PasteboardType {
        PasteboardType(identifier: identifier, conformsTo: conformance.sorted())
    }
}

/// A value that can be dragged and dropped — MetalUI's own `Transferable`
/// (rulings `DN-B`, `DN-S`).
///
/// The call sites read as CoreTransferable's (`String.importedContentTypes()`,
/// `url.exportedContentTypes()`, `x.exported(as:)`,
/// `T(importing:contentType:)`), but every member is **synchronous,
/// non-throwing and optional-returning**: a drop is delivered inside one input
/// event. There is no `visibility:` parameter and no static
/// `exportedContentTypes()`, and SwiftUI's conformer spelling
/// (`static var transferRepresentation`) is **not offered** — a conformer
/// writes the four members (`DN-S` item 4). **Migration**: a file importing
/// both MetalUI and CoreTransferable spells `MetalUI.Transferable`; a ported
/// custom type rewrites its conformance; `String`, `URL` and `Data` need
/// nothing.
public protocol Transferable {
    /// The types this value exports as, most preferred first. An instance
    /// member: a web URL and a file URL export differently (probe `T4`).
    func exportedContentTypes() -> [ContentType]
    /// The types this type imports from, most preferred first.
    static func importedContentTypes() -> [ContentType]
    /// This value's bytes as `contentType`, or `nil` unless one of
    /// ``exportedContentTypes()`` conforms to it (`T5b`, `T6c`).
    func exported(as contentType: ContentType) -> Data?
    /// A value from `data`, which the drop path read for `contentType` — always
    /// one of ``importedContentTypes()``, never the type the item was offered
    /// as (ruling `DN-S` item 2). `nil` when the bytes do not decode.
    init?(importing data: Data, contentType: ContentType)
}

extension String: Transferable {
    /// `[utf8PlainText]` (probe `T1`).
    public func exportedContentTypes() -> [ContentType] { [.utf8PlainText] }
    /// `[utf8PlainText]` (probe `T1`); not `url` (`T7b`).
    public static func importedContentTypes() -> [ContentType] { [.utf8PlainText] }
    /// UTF-8, as `utf8PlainText` or any type it conforms to (`T5`, `T5b`).
    public func exported(as contentType: ContentType) -> Data? {
        guard exportedContentTypes().contains(where: { $0.conforms(to: contentType) }) else { return nil }
        return Data(utf8)
    }
    /// UTF-8 told `utf8PlainText` (`T7`); nothing else (`T7b`).
    public init?(importing data: Data, contentType: ContentType) {
        guard contentType == .utf8PlainText else { return nil }
        self.init(decoding: data, as: UTF8.self)
    }
}

extension URL: Transferable {
    /// A file URL `[url, fileURL]`, any other `[url]` (probe `T4`).
    public func exportedContentTypes() -> [ContentType] { isFileURL ? [.url, .fileURL] : [.url] }
    /// `[url, fileURL]` (probe `T2`); not plain text (`T7c`).
    public static func importedContentTypes() -> [ContentType] { [.url, .fileURL] }
    /// The absolute string in UTF-8 (`T6`, `T6b`); never plain text (`T6c`).
    public func exported(as contentType: ContentType) -> Data? {
        guard exportedContentTypes().contains(where: { $0.conforms(to: contentType) }) else { return nil }
        return Data(absoluteString.utf8)
    }
    /// An absolute string told `url` or `fileURL` (`T7d`).
    public init?(importing data: Data, contentType: ContentType) {
        guard contentType == .url || contentType == .fileURL else { return nil }
        self.init(string: String(decoding: data, as: UTF8.self))
    }
}

extension Data: Transferable {
    /// `[data]` (probe `T3`).
    public func exportedContentTypes() -> [ContentType] { [.data] }
    /// `[data]` (probe `T3`).
    public static func importedContentTypes() -> [ContentType] { [.data] }
    /// The bytes themselves, as `data` or `item`.
    public func exported(as contentType: ContentType) -> Data? {
        ContentType.data.conforms(to: contentType) ? self : nil
    }
    /// The bytes, told `data` only (`T7e`: CoreTransferable's `Data` refuses
    /// being told its bytes are `public.png`). A `Data` destination still
    /// takes any drop: the drop path matches by conformance and hands it
    /// `data` (`P16b`, `DN-S` item 2).
    public init?(importing data: Data, contentType: ContentType) {
        guard contentType == .data else { return nil }
        self = data
    }
}

extension Transferable {
    /// This value exported as every one of its types, for a drag session
    /// (ruling `DN-H`): one representation per exported type that exports.
    func dragRepresentations() -> [DragRepresentation] {
        exportedContentTypes().compactMap { type in
            exported(as: type).map { DragRepresentation(type: type.pasteboardType, bytes: [UInt8]($0)) }
        }
    }
}
