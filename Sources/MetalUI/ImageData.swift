import Foundation

// Encoded image bytes that remember their format (ruling `SOC-H`). `Data` imports as
// `public.data` and is always told so (`T7e`), so a destination or a clipboard read of
// `Data` cannot learn that the bytes are a PNG; `ImageData` imports the three image formats
// by name and is told which one arrived.

/// Encoded image bytes and their format: PNG, TIFF or JPEG. MetalUI-only (class `M`).
///
/// As a drop destination (`dropDestination(for: ImageData.self)`) or a clipboard read
/// (`Clipboard.read(ImageData.self)`) it imports `[.png, .tiff, .jpeg]` in that order, takes
/// the first offered type that is one of them, and carries that type in ``contentType``. A
/// **file** dropped from the Finder or a file manager is a `URL` (`.fileURL`), not image data:
/// a destination wanting the file imports `URL`. Raw image data arrives where the source
/// offers it: AppKit drags and pastes (and the clipboard of Linux and Windows apps that
/// offer `image/png`); SDL's drag-and-drop delivers files and text only, so there is no
/// raw image drop there. The bytes are not decoded or checked against the type.
public struct ImageData: Transferable, Sendable, Equatable {
    /// The encoded bytes, as the source supplied them.
    public var data: Data
    /// The format: ``ContentType/png``, ``ContentType/tiff`` or ``ContentType/jpeg``.
    public var contentType: ContentType

    /// `data` told to be `contentType`. A type that is not PNG, TIFF or JPEG exports and
    /// imports nothing.
    public init(data: Data, contentType: ContentType) {
        self.data = data
        self.contentType = contentType
    }

    /// `[contentType]`, or none when it is not one of the three formats.
    public func exportedContentTypes() -> [ContentType] {
        Self.formats.contains(contentType) ? [contentType] : []
    }

    /// `[png, tiff, jpeg]`.
    public static func importedContentTypes() -> [ContentType] { formats }

    /// The bytes as ``contentType`` or a type it conforms to (`.image`, `.data`, `.item`).
    public func exported(as type: ContentType) -> Data? {
        exportedContentTypes().contains { $0.conforms(to: type) } ? data : nil
    }

    /// The bytes told one of the three formats; `nil` told anything else, or with no bytes.
    public init?(importing data: Data, contentType: ContentType) {
        guard Self.formats.contains(contentType), !data.isEmpty else { return nil }
        self.init(data: data, contentType: contentType)
    }

    private static let formats: [ContentType] = [.png, .tiff, .jpeg]
}
