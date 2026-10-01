import Foundation
import MetalUIPlatform

// RED-FIRST STUB (lane 1): the surface with no behaviour; replaced by the
// implementation in the green commit.

public struct ContentType: Hashable, Sendable, CustomStringConvertible {
    public let identifier: String
    public let conformance: Set<String>
    public init(_ identifier: String, conformingTo parents: [ContentType] = [.data]) {
        self.identifier = identifier
        self.conformance = []
    }
    private init(root identifier: String) { self.identifier = identifier; self.conformance = [] }
    public func conforms(to other: ContentType) -> Bool { false }
    public var description: String { identifier }
    public static let item = ContentType(root: "public.item")
    public static let data = ContentType(root: "public.data")
    public static let text = ContentType(root: "public.text")
    public static let plainText = ContentType(root: "public.plain-text")
    public static let utf8PlainText = ContentType(root: "public.utf8-plain-text")
    public static let url = ContentType(root: "public.url")
    public static let fileURL = ContentType(root: "public.file-url")
    var pasteboardType: PasteboardType { PasteboardType(identifier: identifier) }
}

public protocol Transferable {
    func exportedContentTypes() -> [ContentType]
    static func importedContentTypes() -> [ContentType]
    func exported(as contentType: ContentType) -> Data?
    init?(importing data: Data, contentType: ContentType)
}

extension String: Transferable {
    public func exportedContentTypes() -> [ContentType] { [] }
    public static func importedContentTypes() -> [ContentType] { [] }
    public func exported(as contentType: ContentType) -> Data? { nil }
    public init?(importing data: Data, contentType: ContentType) { return nil }
}
extension URL: Transferable {
    public func exportedContentTypes() -> [ContentType] { [] }
    public static func importedContentTypes() -> [ContentType] { [] }
    public func exported(as contentType: ContentType) -> Data? { nil }
    public init?(importing data: Data, contentType: ContentType) { return nil }
}
extension Data: Transferable {
    public func exportedContentTypes() -> [ContentType] { [] }
    public static func importedContentTypes() -> [ContentType] { [] }
    public func exported(as contentType: ContentType) -> Data? { nil }
    public init?(importing data: Data, contentType: ContentType) { return nil }
}

extension Transferable {
    func dragRepresentations() -> [DragRepresentation] { [] }
}
