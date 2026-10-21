import Foundation

// Header-only image format sniff (rulings IS-A…IS-J, record 130). One read of at most 18 bytes at
// offset 0 through the one header source (`IH-H`); no pixel work, no stb, never a trap.

/// The picture format a byte prefix starts like — MetalUI's header-only format sniff (rulings
/// `IS-A`…`IS-J`). MetalUI-only: SwiftUI has no analogue.
///
/// **A sniff names a prefix, never a promise** (`IS-C`). Compare it with ``ImageInfo/init(data:)``:
/// ``png`` or ``jpeg`` with a `nil` `ImageInfo` is a *damaged* picture; any other case with a `nil`
/// `ImageInfo` is a picture of an *unsupported* type (the header walk reads PNG and JPEG only);
/// ``unknown`` is *not a picture* (or a type with no case here). A distinct type from
/// ``ImageInfo/Format`` so that value can never be a format no `ImageInfo` can hold (`IS-A`).
///
/// More cases may be added: switch with a `default`.
public enum ImageFileFormat: Sendable, Hashable, CaseIterable {
    /// PNG (the 8-byte signature).
    case png
    /// JPEG (`FF D8 FF`).
    case jpeg
    /// GIF, `GIF87a` or `GIF89a`.
    case gif
    /// TIFF, either byte order (BigTIFF is ``unknown``).
    case tiff
    /// Windows BMP: `BM` and a plausible DIB header size (OS/2 variants are ``unknown``).
    case bmp
    /// WebP: `RIFF`, a size and `WEBP`.
    case webp
    /// HEIF or HEIC: an `ftyp` box whose major brand is `heic`, `heix`, `hevc`, `hevx`, `heim`, `heis`,
    /// `mif1` or `msf1` (compatible brands are not read, so an `mif1` AVIF is reported here).
    case heif
    /// AVIF: an `ftyp` box whose major brand is `avif` or `avis` (`IS-E`).
    case avif
    /// Not a recognised picture prefix: garbage, empty, too short, or a format with no case.
    case unknown
}

extension ImageInfo {
    /// The format `data` starts like, from at most its first 18 bytes; ``ImageFileFormat/unknown``
    /// when no whole signature matches (a prefix one byte short of one included). Never traps.
    /// A result of ``ImageFileFormat/png`` or ``ImageFileFormat/jpeg`` does not mean
    /// ``ImageInfo/init(data:)`` succeeds (`IS-C`).
    public static func sniffedFormat(of data: Data) -> ImageFileFormat {
        data.withUnsafeBytes { sniffImageFormat(MemoryHeaderSource(bytes: $0)) }
    }

    /// The format the regular file at `path` starts like; ``ImageFileFormat/unknown`` for a missing
    /// path, a directory, FIFO or device, or an unreadable file (`IS-F`). Equals ``sniffedFormat(of:)``
    /// of the whole file; reads only the first bytes through the 64 KiB window.
    public static func sniffedFormat(ofFile path: String) -> ImageFileFormat {
        guard let source = FileHeaderSource(path: path, trace: nil) else { return .unknown }
        return sniffImageFormat(source)
    }
}

private func ascii(_ text: StaticString) -> [UInt8] { text.withUTF8Buffer { Array($0) } }

private let sniffPNG: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
private let sniffGIF87a = ascii("GIF87a")
private let sniffGIF89a = ascii("GIF89a")
private let sniffTIFFLE: [UInt8] = [0x49, 0x49, 0x2A, 0x00]
private let sniffTIFFBE: [UInt8] = [0x4D, 0x4D, 0x00, 0x2A]
private let sniffRIFF = ascii("RIFF")
private let sniffWEBP = ascii("WEBP")
private let sniffFTYP = ascii("ftyp")
private let sniffHEIFBrands: [[UInt8]] = [
    ascii("heic"), ascii("heix"), ascii("hevc"), ascii("hevx"), ascii("heim"), ascii("heis"), ascii("mif1"), ascii("msf1"),
]
private let sniffAVIFBrands: [[UInt8]] = [ascii("avif"), ascii("avis")]
private let sniffDIBSizes: Set<Int> = [12, 40, 52, 56, 64, 108, 124]

/// Names the format of `source`'s first bytes (`IS-D`, `IS-F`): one read of `min(size, 18)` bytes at
/// offset 0; a `nil` read is `.unknown`.
func sniffImageFormat(_ source: some HeaderSource) -> ImageFileFormat {
    guard let b = source.read(at: 0, count: min(source.size, 18)) else { return .unknown }
    func starts(_ prefix: [UInt8]) -> Bool { b.count >= prefix.count && Array(b[0..<prefix.count]) == prefix }
    if starts(sniffPNG) { return .png }
    if starts([0xFF, 0xD8, 0xFF]) { return .jpeg }
    if starts(sniffGIF87a) || starts(sniffGIF89a) { return .gif }
    if starts(sniffTIFFLE) || starts(sniffTIFFBE) { return .tiff }
    if b.count >= 18, b[0] == 0x42, b[1] == 0x4D,
       sniffDIBSizes.contains(Int(b[14]) | Int(b[15]) << 8 | Int(b[16]) << 16 | Int(b[17]) << 24) { return .bmp }
    if b.count >= 12, starts(sniffRIFF), Array(b[8..<12]) == sniffWEBP { return .webp }
    if b.count >= 12, Array(b[4..<8]) == sniffFTYP {
        let brand = Array(b[8..<12])
        if sniffHEIFBrands.contains(brand) { return .heif }
        if sniffAVIFBrands.contains(brand) { return .avif }
    }
    return .unknown
}
