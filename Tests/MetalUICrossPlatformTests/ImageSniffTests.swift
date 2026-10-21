import Testing
import Foundation
@testable import MetalUI

// Item XP-G12 (rulings IS-A…IS-J; spec 2026-10-20-image-sniff-design §5). Bytes are generated
// (`ImageTestBytes.swift`); a test that counts work reads a spy source or a `HeaderTrace`, never a clock.

private func ascii(_ text: String) -> [UInt8] { Array(text.utf8) }

/// The shortest bytes that match each signature (`IS-D`), one entry per spelling.
private func minimalPrefixes(for format: ImageFileFormat) -> [(name: String, bytes: [UInt8])] {
    switch format {
    case .png: return [("png", [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])]
    case .jpeg: return [("jpeg", [0xFF, 0xD8, 0xFF])]
    case .gif: return [("gif87a", ascii("GIF87a")), ("gif89a", ascii("GIF89a"))]
    case .tiff: return [("tiff-le", [0x49, 0x49, 0x2A, 0x00]), ("tiff-be", [0x4D, 0x4D, 0x00, 0x2A])]
    case .bmp: return [("bmp", ascii("BM") + [UInt8](repeating: 0, count: 12) + le32(40))]
    case .webp: return [("webp", ascii("RIFF") + [1, 2, 3, 4] + ascii("WEBP"))]
    case .heif:
        return ["heic", "heix", "hevc", "hevx", "heim", "heis", "mif1", "msf1"].map {
            ("heif-\($0)", [0, 0, 0, 0x18] + ascii("ftyp") + ascii($0))
        }
    case .avif:
        return ["avif", "avis"].map { ("avif-\($0)", [0, 0, 0, 0x18] + ascii("ftyp") + ascii($0)) }
    case .unknown: return []
    }
}

private func sniff(_ bytes: [UInt8]) -> ImageFileFormat { ImageInfo.sniffedFormat(of: Data(bytes)) }

private let knownFormats = ImageFileFormat.allCases.filter { $0 != .unknown }

/// **1** Mutation: delete or alter each signature arm in turn.
@Test func everyFormatsMinimalSignatureSniffsItsCase() throws {
    var checked = 0
    for format in knownFormats {
        let prefixes = minimalPrefixes(for: format)
        try #require(!prefixes.isEmpty, "\(format) has no minimal prefix")
        for (name, bytes) in prefixes {
            #expect(sniff(bytes) == format, "\(name)")
            #expect(sniff(bytes + [UInt8](repeating: 0xAB, count: 40)) == format, "\(name) with trailing bytes")
            checked += 1
        }
    }
    try #require(checked == 1 + 1 + 2 + 2 + 1 + 1 + 8 + 2)
}

/// **2** Mutation: weaken a length guard by one (PNG, WebP arms).
@Test func everyTruncatedByOnePrefixSniffsUnknown() throws {
    for format in knownFormats {
        for (name, bytes) in minimalPrefixes(for: format) {
            for length in 0..<bytes.count {
                #expect(sniff(Array(bytes.prefix(length))) == .unknown, "\(name) prefix of \(length)")
            }
        }
    }
}

/// **3** Mutation: drop the DIB-size check, the `WEBP` tag check, widen the brand set to `isom`.
@Test func emptyAndGarbageSniffUnknown() {
    let cases: [(String, [UInt8])] = [
        ("empty", []), ("one byte", [0x42]), ("text", ascii("hello world, this is text")),
        ("BM text", ascii("BM is the start of this text, too")),
        ("BM bad DIB", ascii("BM") + [UInt8](repeating: 0, count: 12) + le32(41)),
        ("RIFF WAVE", ascii("RIFF") + [1, 2, 3, 4] + ascii("WAVE")),
        ("BigTIFF LE", [0x49, 0x49, 0x2B, 0x00, 8, 0]), ("BigTIFF BE", [0x4D, 0x4D, 0x00, 0x2B, 0, 8]),
        ("ftyp isom", [0, 0, 0, 0x18] + ascii("ftyp") + ascii("isom")),
        ("ftyp mp42", [0, 0, 0, 0x18] + ascii("ftyp") + ascii("mp42")),
        ("zeros", [UInt8](repeating: 0, count: 1024)),
    ]
    for (name, bytes) in cases { #expect(sniff(bytes) == .unknown, "\(name)") }
}

/// **4** Mutation: make `sniffImageFormat` call `readImageInfo` and return `.unknown` on nil.
@Test func aDamagedPNGSniffsPNGWhileImageInfoIsNil() throws {
    let png = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A] as [UInt8]
        + pngChunk("IHDR", be32(4) + be32(4) + [8, 2, 0, 0, 0], badCRC: true) + pngChunk("IEND", [])
    #expect(ImageInfo(data: Data(png)) == nil)
    #expect(sniff(png) == .png)
    let noSOF = jpegWith([])
    #expect(ImageInfo(data: Data(noSOF)) == nil)
    #expect(sniff(noSOF) == .jpeg)
    for format in [ImageFileFormat.gif, .webp, .tiff, .bmp, .heif, .avif] {
        for (name, bytes) in minimalPrefixes(for: format) {
            #expect(ImageInfo(data: Data(bytes)) == nil, "\(name)")
            #expect(sniff(bytes) == format, "\(name)")
        }
    }
}

/// A source over zeros that records every read; `nilReads` makes every read fail.
private final class SpySource: HeaderSource {
    let size: Int
    let nilReads: Bool
    var reads: [(offset: Int, count: Int)] = []
    init(size: Int, nilReads: Bool = false) { self.size = size; self.nilReads = nilReads }
    func read(at offset: Int, count: Int) -> [UInt8]? {
        reads.append((offset, count))
        guard !nilReads, offset >= 0, count >= 0, offset <= size, count <= size - offset else { return nil }
        return [UInt8](repeating: 0, count: count)
    }
}

/// **5** Mutation: read 64 bytes, or read twice.
@Test func sniffReadsOnlyThePrefix() {
    for size in [0, 1, 5, 17, 18, 19, 1 << 20] {
        let spy = SpySource(size: size)
        #expect(sniffImageFormat(spy) == .unknown)
        #expect(spy.reads.count <= 1, "size \(size)")
        for read in spy.reads { #expect(read.offset == 0 && read.count == min(size, 18), "size \(size)") }
    }
    let failing = SpySource(size: 100, nilReads: true)
    #expect(sniffImageFormat(failing) == .unknown)
}

private func temporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("image-sniff-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

/// **6** Mutation: `Data(contentsOf:)` (trace pin); read through `FileHandle` directly (directory case).
@Test func theFileFormAgreesWithTheDataFormAndRefusesWhatIsNotARegularFile() throws {
    let directory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    for format in knownFormats {
        for (name, bytes) in minimalPrefixes(for: format) {
            let path = directory.appendingPathComponent(name).path
            try Data(bytes + [UInt8](repeating: 7, count: 100)).write(to: URL(fileURLWithPath: path))
            #expect(ImageInfo.sniffedFormat(ofFile: path) == format, "\(name)")
            #expect(ImageInfo.sniffedFormat(ofFile: path) == ImageInfo.sniffedFormat(of: try Data(contentsOf: URL(fileURLWithPath: path))))
            let trace = HeaderTrace()
            let source = try #require(FileHeaderSource(path: path, trace: trace))
            #expect(sniffImageFormat(source) == format)
            #expect(trace.refills == [0] && trace.payloadReads == 0 && trace.wholeFileLoads == 0, "\(name)")
        }
    }
    let empty = directory.appendingPathComponent("empty").path
    try Data().write(to: URL(fileURLWithPath: empty))
    #expect(ImageInfo.sniffedFormat(ofFile: empty) == .unknown)
    #expect(ImageInfo.sniffedFormat(ofFile: directory.path) == .unknown)
    #expect(ImageInfo.sniffedFormat(ofFile: directory.appendingPathComponent("missing").path) == .unknown)
    #if !os(Windows)
    let target = directory.appendingPathComponent("gif89a").path
    let link = directory.appendingPathComponent("link").path
    try FileManager.default.createSymbolicLink(atPath: link, withDestinationPath: target)
    #expect(ImageInfo.sniffedFormat(ofFile: link) == .gif)
    let dirLink = directory.appendingPathComponent("dirlink").path
    try FileManager.default.createSymbolicLink(atPath: dirLink, withDestinationPath: directory.path)
    #expect(ImageInfo.sniffedFormat(ofFile: dirLink) == .unknown)
    #endif
}

/// The independent oracle: which signature, if any, `bytes` carries (spelled differently from the sniff).
private func oracle(_ b: [UInt8]) -> ImageFileFormat {
    func starts(_ p: [UInt8]) -> Bool { b.count >= p.count && Array(b[0..<p.count]) == p }
    if starts([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]) { return .png }
    if starts([0xFF, 0xD8, 0xFF]) { return .jpeg }
    if starts(ascii("GIF87a")) || starts(ascii("GIF89a")) { return .gif }
    if starts([0x49, 0x49, 0x2A, 0x00]) || starts([0x4D, 0x4D, 0x00, 0x2A]) { return .tiff }
    if b.count >= 18, starts(ascii("BM")),
       [12, 40, 52, 56, 64, 108, 124].contains(Int(b[14]) | Int(b[15]) << 8 | Int(b[16]) << 16 | Int(b[17]) << 24) { return .bmp }
    if b.count >= 12, starts(ascii("RIFF")), Array(b[8..<12]) == ascii("WEBP") { return .webp }
    if b.count >= 12, Array(b[4..<8]) == ascii("ftyp") {
        let brand = String(decoding: b[8..<12], as: UTF8.self)
        if ["heic", "heix", "hevc", "hevx", "heim", "heis", "mif1", "msf1"].contains(brand) { return .heif }
        if ["avif", "avis"].contains(brand) { return .avif }
    }
    return .unknown
}

/// **7** Mutation: an unchecked index at 12.
@Test func sniffNeverTrapsOnAnySingleByteMutationOfAValidSignature() {
    for format in knownFormats {
        for (name, bytes) in minimalPrefixes(for: format) {
            for index in bytes.indices {
                for value in [UInt8(0x00), 0xFF] {
                    var mutated = bytes
                    mutated[index] = value
                    #expect(sniff(mutated) == oracle(mutated), "\(name) byte \(index) = \(value)")
                    #expect(sniff(Array(mutated.prefix(index))) == oracle(Array(mutated.prefix(index))))
                }
            }
        }
    }
}

/// **8** Mutation: swap the PNG and JPEG arms.
@Test func sniffAndImageInfoAgreeOnPNGAndJPEGFixtures() throws {
    let directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("ImageFixtures")
    let names = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        .filter { $0.hasSuffix(".png") || $0.hasSuffix(".jpg") }
    try #require(!names.isEmpty)
    for name in names {
        let data = try Data(contentsOf: directory.appendingPathComponent(name))
        let read = try #require(ImageInfo(data: data), name)
        #expect(ImageInfo.sniffedFormat(of: data) == (read.format == .png ? .png : .jpeg), name)
    }
    let generated: [[UInt8]] = [
        makePNG(width: 2, height: 2, bitDepth: 8, colorType: 6, rows: [UInt8](repeating: 1, count: 16)),
        jpegWith([jpegSegment(0xC0, [8, 0, 5, 0, 7, 1, 1, 0x11, 0])]),
    ]
    for bytes in generated {
        let read = try #require(ImageInfo(data: Data(bytes)))
        #expect(sniff(bytes) == (read.format == .png ? .png : .jpeg))
    }
}

/// **9** A tenth case needs a test arm.
@Test func iterationCoversNineCases() throws {
    try #require(ImageFileFormat.allCases.count == 9)
    #expect(Set(ImageFileFormat.allCases).count == 9)
}
