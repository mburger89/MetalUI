import Foundation
import MetalUI
import MetalUIPlatform
import MetalUITesting
import Observation
import Testing

// Image content types (ruling prefix `SOC-`, record 234): `ContentType.image/.png/.tiff/.jpeg`,
// `Clipboard.readData(of:)`, `ImageData`, and the drop path. PLAIN imports; headless.

private let pngBytes = Data([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 1, 2, 3])
private let tiffBytes = Data([0x49, 0x49, 0x2a, 0x00, 9, 9])

/// The seam's spelling of a built-in type, as a platform lists it (identifier and conformance).
private func offered(_ type: ContentType) -> PasteboardType {
    PasteboardType(identifier: type.identifier, conformsTo: type.conformance.sorted())
}

/// A clipboard item offering `types` in order, each with the bytes the table gives.
@MainActor private func imageItem(_ types: [(ContentType, Data)]) -> ClipboardItem {
    ClipboardItem(payloads: types.map { type, bytes in
        ClipboardPayload(type: offered(type), bytes: .now([UInt8](bytes)))
    })
}

@MainActor private func emptyWindow() throws -> TestWindow {
    try TestWindow(size: sz(100, 100), textSystem: harnessTextSystem) { Color.clear.frame(width: Pixels(10), height: Pixels(10)) }
}

/// 1 - identifiers, conformance, extensions. Mutation: `.png` conforming to `.data` only.
@Test func theImageTypesHaveTheirUTIsAndConformToPublicImage() {
    #expect(ContentType.image.identifier == "public.image")
    #expect(ContentType.png.identifier == "public.png")
    #expect(ContentType.tiff.identifier == "public.tiff")
    #expect(ContentType.jpeg.identifier == "public.jpeg")
    for type in [ContentType.png, .tiff, .jpeg] {
        #expect(type.conforms(to: .image) && type.conforms(to: .data) && type.conforms(to: .item), "\(type)")
        #expect(!type.conforms(to: .text) && !type.conforms(to: .fileURL))
    }
    #expect(ContentType.image.conforms(to: .data) && !ContentType.image.conforms(to: .png))
    #expect(!ContentType.png.conforms(to: .tiff))
    #expect(ContentType.png.preferredFilenameExtension == "png")
    #expect(ContentType.jpeg.preferredFilenameExtension == "jpg")
    #expect(ContentType.tiff.preferredFilenameExtension == "tiff")
    #expect(ContentType.png.conformance.sorted() == ["public.data", "public.image", "public.item"])
}

/// 2 - a clipboard holding a PNG: `hasContent`, `readData(of:)` by exact type and by parent, a
/// `nil` for another format, and `Data` reading it (it read `nil` while `public.png` had no
/// conformance). Mutations: drop `.png` from `ContentType.builtIn`; make `readData` ignore the
/// type argument.
@MainActor @Test func aClipboardPNGReadsByExactTypeAndByParent() throws {
    let window = try emptyWindow()
    #expect(window.setClipboard(items: [imageItem([(.png, pngBytes)])]))
    let clipboard = window.window.clipboard
    #expect(clipboard.contentTypes == ["public.png"])
    #expect(clipboard.hasContent(of: .png) && clipboard.hasContent(of: .image) && clipboard.hasContent(of: .data))
    #expect(!clipboard.hasContent(of: .tiff) && !clipboard.hasContent(of: .jpeg) && !clipboard.hasContent(of: .text))
    #expect(clipboard.readData(of: .png) == pngBytes)
    #expect(clipboard.readData(of: .image) == pngBytes, "the parent takes whatever image is there")
    #expect(clipboard.readData(of: .tiff) == nil, "nothing converts between formats")
    #expect(clipboard.read(Data.self) == pngBytes, "a `Data` read takes it as bytes")
    #expect(clipboard.read(String.self) == nil)
}

/// 3 - both formats offered: a request for one gets that one; the parent gets the first listed.
/// Mutation: `readData` returning the first payload whatever the type.
@MainActor @Test func aRequestForTIFFGetsTIFFWhenPNGIsListedFirst() throws {
    let window = try emptyWindow()
    #expect(window.setClipboard(items: [imageItem([(.png, pngBytes), (.tiff, tiffBytes)])]))
    let clipboard = window.window.clipboard
    #expect(clipboard.readData(of: .tiff) == tiffBytes)
    #expect(clipboard.readData(of: .png) == pngBytes)
    #expect(clipboard.readData(of: .image) == pngBytes, "the first listed")
    #expect(clipboard.read(ImageData.self) == ImageData(data: pngBytes, contentType: .png), "ImageData prefers png")
    window.window.clipboard.write(ImageData(data: tiffBytes, contentType: .tiff))
    #expect(window.window.clipboard.read(ImageData.self)?.contentType == .tiff, "and learns which arrived")
}

/// 4 - empty bytes read as `nil`, and a clipboard with only text has no image.
@MainActor @Test func anEmptyOrAbsentImageReadsNil() throws {
    let window = try emptyWindow()
    window.setClipboard(text: "hi")
    #expect(window.window.clipboard.readData(of: .image) == nil)
    #expect(window.window.clipboard.read(ImageData.self) == nil)
    #expect(!window.window.clipboard.hasContent(of: .image))
}

/// 5 - writing `ImageData` offers its one type with its bytes, and a non-image type exports nothing.
@MainActor @Test func imageDataExportsItsOwnFormatOnly() throws {
    let window = try emptyWindow()
    let png = ImageData(data: pngBytes, contentType: .png)
    #expect(png.exportedContentTypes() == [.png])
    #expect(png.exported(as: .image) == pngBytes && png.exported(as: .data) == pngBytes)
    #expect(png.exported(as: .tiff) == nil)
    #expect(ImageData(data: pngBytes, contentType: .json).exportedContentTypes().isEmpty)
    #expect(window.window.clipboard.write(png))
    #expect(window.clipboardRepresentations.map(\.type.identifier) == ["public.png"])
    #expect(window.clipboardRepresentations.first?.bytes == [UInt8](pngBytes))
    #expect(ImageData(importing: pngBytes, contentType: .data) == nil, "told `data` it is not an image format")
    #expect(ImageData(importing: Data(), contentType: .png) == nil)
}

// MARK: drops

@Observable @MainActor private final class DropLog {
    var urls: [URL] = []
    var images: [ImageData] = []
    var datas: [Data] = []
}

@MainActor private func dropWindow(_ log: DropLog) throws -> TestWindow {
    try TestWindow(size: sz(200, 200), textSystem: harnessTextSystem) {
        VStack(spacing: 0) {
            Color.clear.frame(width: Pixels(200), height: Pixels(60))
                .dropDestination(for: URL.self) { urls, _ in log.urls += urls; return true }
            Color.clear.frame(width: Pixels(200), height: Pixels(60))
                .dropDestination(for: ImageData.self) { images, _ in log.images += images; return true }
            Color.clear.frame(width: Pixels(200), height: Pixels(60))
                .dropDestination(for: Data.self) { datas, _ in log.datas += datas; return true }
        }
    }
}

private func fileItem(_ path: String) -> DropItem {
    let type = offered(.fileURL)
    let bytes = [UInt8](URL(fileURLWithPath: path).absoluteString.utf8)
    return DropItem(types: [type]) { $0 == type.identifier ? bytes : nil }
}

private func rawItem(_ type: ContentType, _ data: Data) -> DropItem {
    let listed = offered(type)
    return DropItem(types: [listed]) { $0 == listed.identifier ? [UInt8](data) : nil }
}

/// 6 - a .png FILE dropped arrives as a `URL` with `isFileURL`, not as image data. Mutation:
/// let `ImageData` import `.fileURL`.
@MainActor @Test func aDroppedPNGFileArrivesAsAFileURL() throws {
    let log = DropLog()
    let window = try dropWindow(log)
    window.drop([fileItem("/tmp/a.png")], at: pt(100, 30))
    #expect(log.urls.count == 1 && log.urls[0].isFileURL && log.urls[0].lastPathComponent == "a.png")
    window.drop([fileItem("/tmp/a.png")], at: pt(100, 90))
    #expect(log.images.isEmpty, "an image destination does not take a file URL")
}

/// 7 - raw image data arrives as `ImageData` of the type offered, and as `Data` bytes. Mutation:
/// tell the destination `.image` instead of the exact type.
@MainActor @Test func rawImageDataArrivesWithItsFormat() throws {
    let log = DropLog()
    let window = try dropWindow(log)
    window.drop([rawItem(.png, pngBytes)], at: pt(100, 90))
    window.drop([rawItem(.tiff, tiffBytes)], at: pt(100, 90))
    #expect(log.images == [ImageData(data: pngBytes, contentType: .png), ImageData(data: tiffBytes, contentType: .tiff)])
    window.drop([rawItem(.png, pngBytes)], at: pt(100, 150))
    #expect(log.datas == [pngBytes], "a Data destination takes the bytes of a PNG")
    window.drop([rawItem(.png, pngBytes)], at: pt(100, 30))
    #expect(log.urls.count == 0, "and a URL destination refuses an image")
}
