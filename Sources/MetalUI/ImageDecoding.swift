internal import CStbImage
#if canImport(ImageIO)
import Foundation
import CoreGraphics
import ImageIO
#endif
import MetalUIScene

// Portable image decoding (rulings PX-B, PX-C, PX-D, PX-O): PNG and JPEG
// through the vendored stb_image 2.30 on every platform, macOS included, so a
// file's bytes are the same on every platform; other formats through ImageIO
// on Apple only. Every check that decides `nil` runs in Swift before stb sees
// the bytes — stb_image is not hardened against malicious input (`PX-B`).

/// The decoded texture for a file's bytes, or `nil`: PNG and JPEG through
/// ``decodeImage(_:)`` (straight samples, premultiplied once by
/// `ImageTexture(width:height:straightRGBA:)`, `TE-AR`); anything else
/// through ImageIO where it exists (colour-managed, premultiplied by its own
/// draw — `359444e`'s decode, `PX-C` item 5), `nil` elsewhere.
func decodeImageTexture(_ bytes: UnsafeRawBufferPointer) -> ImageTexture? {
    if isPNG(bytes) || isJPEG(bytes) {
        guard let image = decodeImage(bytes) else { return nil }
        return ImageTexture(width: image.width, height: image.height, straightRGBA: image.straightRGBA)
    }
    #if canImport(ImageIO)
    return decodeThroughImageIO(bytes)
    #else
    return nil
    #endif
}

/// PNG or JPEG bytes → straight-alpha sRGB RGBA8, row-major from the top-left,
/// or `nil` (`PX-D`: never a trap). Steps, in order (spec §1.1):
///
/// 0. More than `Int32.max` bytes → `nil`: stb's lengths are `int`, and an
///    unchecked `Int32(count)` would trap (`PX-O` item 5).
/// 1. The signature: PNG → 2, JPEG → 3, anything else → `nil`.
/// 2. ``pngStructureIsIntact(_:)``; then a 16-bit file decodes at 16 bits and
///    each sample rounds `(v × 255 + 32767) / 65535` (stb's own 8-bit path
///    truncates, `v >> 8`, and differs from ImageIO by up to 2; `PX-C` item 2).
/// 3. ``jpegScanIsTerminated(_:)``; then the 8-bit path.
/// 4. ``decodedSizeIsAccepted(width:height:)``; `stbi_image_free` on every path.
///
/// Colour profiles are ignored: every sample is taken as sRGB (`PX-C` item 4,
/// divergence 138).
func decodeImage(_ bytes: UnsafeRawBufferPointer) -> (width: Int, height: Int, straightRGBA: [UInt8])? {
    guard bytes.count <= Int(Int32.max), let base = bytes.baseAddress else { return nil }
    let sixteenBit: Bool
    if isPNG(bytes) {
        guard pngStructureIsIntact(bytes) else { return nil }
        sixteenBit = stbi_is_16_bit_from_memory(base.assumingMemoryBound(to: UInt8.self), Int32(bytes.count)) == 1
    } else if isJPEG(bytes) {
        guard jpegScanIsTerminated(bytes) else { return nil }
        sixteenBit = false
    } else {
        return nil
    }
    let input = base.assumingMemoryBound(to: UInt8.self)
    var width: Int32 = 0, height: Int32 = 0, channels: Int32 = 0
    if sixteenBit {
        guard let samples = stbi_load_16_from_memory(input, Int32(bytes.count), &width, &height, &channels, 4)
        else { return nil }
        defer { stbi_image_free(samples) }
        guard decodedSizeIsAccepted(width: Int(width), height: Int(height)) else { return nil }
        let count = Int(width) * Int(height) * 4
        let rgba = [UInt8](unsafeUninitializedCapacity: count) { buffer, initialized in
            for i in 0..<count {
                buffer[i] = UInt8((UInt32(samples[i]) * 255 + 32767) / 65535)
            }
            initialized = count
        }
        return (Int(width), Int(height), rgba)
    }
    guard let samples = stbi_load_from_memory(input, Int32(bytes.count), &width, &height, &channels, 4)
    else { return nil }
    defer { stbi_image_free(samples) }
    guard decodedSizeIsAccepted(width: Int(width), height: Int(height)) else { return nil }
    let count = Int(width) * Int(height) * 4
    return (Int(width), Int(height), Array(UnsafeBufferPointer(start: samples, count: count)))
}

/// Whether a decoded size is one MetalUI accepts: each side in `1…16384` (the
/// largest texture side both renderers guarantee; `STBI_MAX_DIMENSIONS`, the
/// independent guard inside stb, is the same number — `PX-O` item 3) and a
/// byte count that does not overflow `Int`.
func decodedSizeIsAccepted(width: Int, height: Int) -> Bool {
    guard (1...16384).contains(width), (1...16384).contains(height) else { return false }
    let (pixels, overflow) = width.multipliedReportingOverflow(by: height)
    return !overflow && !pixels.multipliedReportingOverflow(by: 4).overflow
}

private let pngSignature: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]

private func isPNG(_ bytes: UnsafeRawBufferPointer) -> Bool {
    bytes.count >= 8 && zip(bytes, pngSignature).allSatisfy { $0 == $1 }
}

private func isJPEG(_ bytes: UnsafeRawBufferPointer) -> Bool {
    bytes.count >= 3 && bytes[0] == 0xFF && bytes[1] == 0xD8 && bytes[2] == 0xFF
}

private func bigEndian32(_ bytes: UnsafeRawBufferPointer, at offset: Int) -> UInt32 {
    UInt32(bytes[offset]) << 24 | UInt32(bytes[offset + 1]) << 16
        | UInt32(bytes[offset + 2]) << 8 | UInt32(bytes[offset + 3])
}

/// CRC-32 (ISO 3309, PNG's), table computed once.
private let crcTable: [UInt32] = (0..<256).map { n -> UInt32 in
    var c = UInt32(n)
    for _ in 0..<8 { c = c & 1 == 1 ? 0xEDB8_8320 ^ (c >> 1) : c >> 1 }
    return c
}

private func crc32(_ bytes: UnsafeRawBufferPointer, from start: Int, count: Int) -> UInt32 {
    var c: UInt32 = 0xFFFF_FFFF
    for i in start..<(start + count) {
        c = crcTable[Int((c ^ UInt32(bytes[i])) & 0xFF)] ^ (c >> 8)
    }
    return c ^ 0xFFFF_FFFF
}

/// The PNG pre-check (`PX-D` item 1, `PX-O` item 1): the signature, then a
/// chunk walk in which every chunk's length fits the buffer and its CRC-32
/// (of type and data) equals the stored one, ending at an `IEND`. Bytes after
/// `IEND` are ignored. libpng — so ImageIO — tolerates a bad CRC on an
/// ancillary chunk; MetalUI refuses any.
func pngStructureIsIntact(_ bytes: UnsafeRawBufferPointer) -> Bool {
    guard isPNG(bytes) else { return false }
    var offset = 8
    while offset + 8 <= bytes.count {
        let length = Int(bigEndian32(bytes, at: offset))
        // The chunk-length bound: length, type, data and CRC inside the buffer.
        guard length <= Int(Int32.max), offset + 12 + length <= bytes.count else { return false }
        let stored = bigEndian32(bytes, at: offset + 8 + length)
        guard crc32(bytes, from: offset + 4, count: 4 + length) == stored else { return false }
        if bytes[offset + 4] == 0x49, bytes[offset + 5] == 0x45, bytes[offset + 6] == 0x4E,
           bytes[offset + 7] == 0x44 {
            return true  // IEND
        }
        offset += 12 + length
    }
    return false  // the walk ran out with no IEND
}

/// The JPEG pre-check (`PX-D` item 2, `PX-O` item 2): from `SOI`, walk the
/// marker segments by their 16-bit lengths to the first `SOS` — never a raw
/// byte search, since an `APP1` thumbnail holds its own `FF DA … FF D9` — then
/// require an `EOI` (`FF D9`) after that `SOS`'s header. Entropy-coded data
/// cannot hold `FF D9` (a data `FF` is stuffed `FF 00`), so the first one
/// found ends the image; bytes after it are allowed. A JPEG has no checksum:
/// a flipped bit inside its scan may decode to wrong pixels, as in every
/// decoder.
func jpegScanIsTerminated(_ bytes: UnsafeRawBufferPointer) -> Bool {
    guard bytes.count >= 4, bytes[0] == 0xFF, bytes[1] == 0xD8 else { return false }
    var offset = 2
    while true {
        guard offset + 2 <= bytes.count, bytes[offset] == 0xFF else { return false }
        let marker = bytes[offset + 1]
        if marker == 0xFF { offset += 1; continue }                         // fill byte
        if marker == 0x01 || (0xD0...0xD7).contains(marker) { offset += 2; continue }  // no length
        if marker == 0xD8 || marker == 0xD9 { return false }               // SOI/EOI before SOS
        guard offset + 4 <= bytes.count else { return false }
        let length = Int(bytes[offset + 2]) << 8 | Int(bytes[offset + 3])
        guard length >= 2, offset + 2 + length <= bytes.count else { return false }
        offset += 2 + length
        if marker == 0xDA { break }                                         // SOS
    }
    while offset + 1 < bytes.count {
        if bytes[offset] == 0xFF && bytes[offset + 1] == 0xD9 { return true }
        offset += 1
    }
    return false
}

#if canImport(ImageIO)
/// `ImageBitmap(contentsOfFile:)`'s decode at `359444e`, for formats the
/// portable decoder does not read (TIFF, GIF, HEIC, …; `PX-C` item 5): the
/// first frame drawn into a premultiplied sRGB RGBA8 context, so its colours
/// are converted to sRGB and its rows read top-down. Apple only.
private func decodeThroughImageIO(_ bytes: UnsafeRawBufferPointer) -> ImageTexture? {
    guard !bytes.isEmpty,
          let source = CGImageSourceCreateWithData(Data(bytes) as CFData, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
          image.width > 0, image.height > 0,
          let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
    let width = image.width
    let height = image.height
    var pixels = [UInt8](repeating: 0, count: width * height * 4)
    let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
        guard let context = CGContext(data: buffer.baseAddress, width: width, height: height,
                                      bitsPerComponent: 8, bytesPerRow: width * 4, space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                                          | CGBitmapInfo.byteOrder32Big.rawValue)
        else { return false }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return true
    }
    guard drawn else { return nil }
    return ImageTexture(width: width, height: height, premultipliedRGBA: pixels)
}
#endif
