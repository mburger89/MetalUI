import Foundation

// Header-only image reads (rulings IH-E…IH-H, IH-M, IH-N, IH-P; record 117). One bounds-checked walk
// over a `HeaderSource`, shared by `ImageInfo`, the EXIF wrappers in `ImageEXIF.swift` and the file
// reader. Every read is range-checked without arithmetic that can overflow: a truncated or hostile
// header gives `nil`, never a trap and never a read past the source. No pixel is touched.

/// A readable run of bytes: `size` and a bounds-checked read. `nil` for any read that does not lie
/// wholly inside `0..<size` or that the underlying file cannot serve (damage, `IH-N` item 3).
protocol HeaderSource {
    var size: Int { get }
    func read(at offset: Int, count: Int) -> [UInt8]?
}

/// Work counters a test reads (benchmarks count work, never time). `nil` in production.
final class HeaderTrace {
    /// The offsets at which the file window was refilled.
    var refills: [Int] = []
    /// Reads larger than the window, served straight from the file.
    var payloadReads = 0
    /// Whole-file loads for a decode.
    var wholeFileLoads = 0
    /// Calls to the decoder.
    var decodeCalls = 0
}

/// A source over bytes already in memory.
struct MemoryHeaderSource: HeaderSource {
    let bytes: UnsafeRawBufferPointer
    var size: Int { bytes.count }

    func read(at offset: Int, count: Int) -> [UInt8]? {
        guard offset >= 0, count >= 0, offset <= bytes.count, count <= bytes.count - offset else { return nil }
        guard count > 0 else { return [] }
        return Array(UnsafeRawBufferPointer(rebasing: bytes[offset..<(offset + count)]))
    }
}

/// A source over a regular file, read through one 64 KiB window (`IH-M`): a read inside the window is
/// served from memory, one outside refills it at that offset, one larger than the window is read
/// straight (an EXIF payload, at most 1 MiB). The size is recorded once at open (`IH-N`); a file that
/// grows afterwards is read only to that size, one that shrinks answers `nil` at the short read.
final class FileHeaderSource: HeaderSource {
    static let windowSize = 64 * 1024

    let size: Int
    private let handle: FileHandle
    private let trace: HeaderTrace?
    private var window: [UInt8] = []
    private var windowStart = 0

    /// `nil` for a path that does not name a readable regular file (a directory, FIFO or device is
    /// never opened: a zero or lying size must not defeat an input limit, `IH-N` item 2).
    init?(path: String, trace: HeaderTrace?) {
        let resolved = URL(fileURLWithPath: path).resolvingSymlinksInPath().path
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: resolved),
              attributes[.type] as? FileAttributeType == .typeRegular,
              let handle = FileHandle(forReadingAtPath: resolved),
              let end = try? handle.seekToEnd(), end <= UInt64(Int.max) else { return nil }
        self.size = Int(end)
        self.handle = handle
        self.trace = trace
    }

    deinit { try? handle.close() }

    func read(at offset: Int, count: Int) -> [UInt8]? {
        guard offset >= 0, count >= 0, offset <= size, count <= size - offset else { return nil }
        guard count > 0 else { return [] }
        if count > Self.windowSize {
            trace?.payloadReads += 1
            return load(at: offset, count: count)
        }
        if offset >= windowStart, offset - windowStart + count <= window.count {
            let start = offset - windowStart
            return Array(window[start..<(start + count)])
        }
        trace?.refills.append(offset)
        guard let fresh = load(at: offset, count: min(Self.windowSize, size - offset)) else { return nil }
        window = fresh
        windowStart = offset
        return Array(window[0..<count])
    }

    /// Exactly `count` bytes at `offset`, or `nil` (a short read is damage).
    func load(at offset: Int, count: Int) -> [UInt8]? {
        guard (try? handle.seek(toOffset: UInt64(offset))) != nil,
              let data = try? handle.read(upToCount: count), data.count == count else { return nil }
        return [UInt8](data)
    }
}

let exifPayloadCap = 1 << 20

private let pngSignatureBytes: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]

private func tiffOrientation(of payload: [UInt8]) -> Image.Orientation? {
    payload.withUnsafeBytes { tiffOrientation($0) }
}

/// The orientation of a PNG's `eXIf` chunk: the first one before the first `IDAT`, else the first
/// after the last `IDAT` (PNG 1.5; one between two `IDAT`s is ignored), or `nil`. Chunk CRCs are not
/// checked here; every length is. A payload over 1 MiB is damaged (`IH-G`).
func pngOrientation(_ source: some HeaderSource) -> Image.Orientation? {
    let size = source.size
    guard size >= 8, source.read(at: 0, count: 8) == pngSignatureBytes else { return nil }
    func orientation(at start: Int, length: Int) -> Image.Orientation? {
        guard length <= exifPayloadCap, let payload = source.read(at: start, count: length) else { return nil }
        return tiffOrientation(of: payload)
    }
    var offset = 8
    var seenIDAT = false
    var afterIDAT: (start: Int, length: Int)?
    while size >= 12, offset <= size - 12 {
        guard let header = source.read(at: offset, count: 8) else { break }
        let length = Int(header[0]) << 24 | Int(header[1]) << 16 | Int(header[2]) << 8 | Int(header[3])
        guard length >= 0, length <= size - offset - 12 else { break }
        let type = (header[4], header[5], header[6], header[7])
        if type == (0x49, 0x44, 0x41, 0x54) {                                  // IDAT
            seenIDAT = true
            afterIDAT = nil                                                     // it was between IDATs
        } else if type == (0x65, 0x58, 0x49, 0x66) {                           // eXIf
            if !seenIDAT { return orientation(at: offset + 8, length: length) }
            if afterIDAT == nil { afterIDAT = (offset + 8, length) }
        } else if type == (0x49, 0x45, 0x4E, 0x44) {                           // IEND
            break
        }
        offset += 12 + length
    }
    return afterIDAT.flatMap { orientation(at: $0.start, length: $0.length) }
}

/// A JPEG frame header: the first SOF's precision, size and component count.
struct JPEGFrame {
    var precision: Int
    var width: Int
    var height: Int
    var components: Int
}

/// What the segment walk to the first `SOS` found.
struct JPEGWalk {
    var frame: JPEGFrame?
    var orientation: Image.Orientation?
    /// The first SOF was present but malformed (`IH-F`): the image has no usable header.
    var frameDamaged = false
}

/// Whether `marker` is a SOF that carries dimensions (`IH-F`): `C0–C3, C5–C7, C9–CB, CD–CF`, never `C4`
/// (DHT), `C8` (JPG) or `CC` (DAC).
func isDimensionBearingSOF(_ marker: UInt8) -> Bool {
    (0xC0...0xCF).contains(marker) && marker != 0xC4 && marker != 0xC8 && marker != 0xCC
}

/// The segment walk of `exifOrientation(inJPEG:)`, by segment lengths to the first `SOS` (never a byte
/// search: a thumbnail holds its own markers). `wantFrame` also reads the first SOF; `stopAtExif`
/// returns at the first `Exif` `APP1` (the orientation read's early exit). A segment that is damaged
/// ends the walk with what was found so far.
func jpegWalk(_ source: some HeaderSource, wantFrame: Bool, stopAtExif: Bool) -> JPEGWalk {
    var result = JPEGWalk()
    let size = source.size
    guard size >= 4, source.read(at: 0, count: 2) == [0xFF, 0xD8] else { return result }
    var offset = 2
    var sawExif = false
    while offset <= size - 2, let pair = source.read(at: offset, count: 2), pair[0] == 0xFF {
        let marker = pair[1]
        if marker == 0xFF { offset += 1; continue }                                    // fill byte
        if marker == 0x01 || (0xD0...0xD7).contains(marker) { offset += 2; continue }  // no length
        if marker == 0xD8 || marker == 0xD9 || marker == 0xDA { break }               // SOI, EOI, SOS
        guard offset <= size - 4, let lengthBytes = source.read(at: offset + 2, count: 2) else { break }
        let length = Int(lengthBytes[0]) << 8 | Int(lengthBytes[1])
        guard length >= 2, length <= size - offset - 2 else { break }
        if wantFrame, result.frame == nil, isDimensionBearingSOF(marker) {
            guard length >= 8, let fields = source.read(at: offset + 4, count: 6) else {
                result.frameDamaged = true
                return result
            }
            let height = Int(fields[1]) << 8 | Int(fields[2])
            let width = Int(fields[3]) << 8 | Int(fields[4])
            let components = Int(fields[5])
            guard width >= 1, height >= 1, (1...4).contains(components), length >= 8 + 3 * components else {
                result.frameDamaged = true
                return result
            }
            result.frame = JPEGFrame(precision: Int(fields[0]), width: width, height: height, components: components)
        }
        if marker == 0xE1, length >= 8, !sawExif, let tag = source.read(at: offset + 4, count: 6),
           tag == [0x45, 0x78, 0x69, 0x66, 0, 0] {
            sawExif = true
            if let tiff = source.read(at: offset + 10, count: length - 8) {
                result.orientation = tiffOrientation(of: tiff)
            }
            if stopAtExif { return result }
        }
        offset += 2 + length
    }
    return result
}

/// The header of a PNG or JPEG in `source`, or `nil` for any other format or a damaged header
/// (`IH-E`, `IH-F`). No size limit (`IH-D`).
func readImageInfo(_ source: some HeaderSource) -> ImageInfo? {
    guard let lead = source.read(at: 0, count: 3) else { return nil }
    if lead == [0xFF, 0xD8, 0xFF] {
        let walk = jpegWalk(source, wantFrame: true, stopAtExif: false)
        guard let frame = walk.frame else { return nil }
        return ImageInfo(format: .jpeg, width: frame.width, height: frame.height, orientation: walk.orientation ?? .up,
                         bitDepth: frame.precision, channelCount: frame.components)
    }
    // IHDR: signature, then length 13, "IHDR", 13 bytes, CRC (the first chunk, `IH-E`).
    guard let head = source.read(at: 0, count: 33), Array(head[0..<8]) == pngSignatureBytes,
          Array(head[8..<12]) == [0, 0, 0, 13], Array(head[12..<16]) == [0x49, 0x48, 0x44, 0x52] else { return nil }
    let stored = UInt32(head[29]) << 24 | UInt32(head[30]) << 16 | UInt32(head[31]) << 8 | UInt32(head[32])
    guard head.withUnsafeBytes({ crc32($0, from: 12, count: 17) }) == stored else { return nil }
    let width = Int(head[16]) << 24 | Int(head[17]) << 16 | Int(head[18]) << 8 | Int(head[19])
    let height = Int(head[20]) << 24 | Int(head[21]) << 16 | Int(head[22]) << 8 | Int(head[23])
    guard width >= 1, height >= 1, width <= Int(Int32.max), height <= Int(Int32.max) else { return nil }
    let depth = Int(head[24]), colour = head[25]
    let channels: Int
    let legalDepths: [Int]
    switch colour {
    case 0: channels = 1; legalDepths = [1, 2, 4, 8, 16]
    case 2: channels = 3; legalDepths = [8, 16]
    case 3: channels = 3; legalDepths = [1, 2, 4, 8]
    case 4: channels = 2; legalDepths = [8, 16]
    case 6: channels = 4; legalDepths = [8, 16]
    default: return nil
    }
    guard legalDepths.contains(depth) else { return nil }
    return ImageInfo(format: .png, width: width, height: height, orientation: pngOrientation(source) ?? .up,
                     bitDepth: depth, channelCount: channels)
}

/// Whether `width × height` is above `max` (an overflowing product always is, `IH-N` item 1).
func exceedsPixelLimit(width: Int, height: Int, max: Int) -> Bool {
    let (pixels, overflow) = width.multipliedReportingOverflow(by: height)
    return overflow || pixels > max
}
