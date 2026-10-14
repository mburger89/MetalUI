import Foundation

/// What an image's header says, read without decoding a pixel — MetalUI's header-only image read
/// (rulings `IH-A`…`IH-P`, record 117). MetalUI-only: SwiftUI has no header-only image API (ImageIO's
/// `CGImageSourceCopyPropertiesAtIndex` is the analogue, not a claim).
///
/// PNG and JPEG only, as ``DecodedImage`` (`IH-B`): every other format, a missing or unreadable file
/// and every damaged header is `nil`, never a trap. The size is the **stored** size, before
/// ``orientation``; ``orientedSize`` turns it. Nothing here limits the size (`IH-D`): a 40000 × 40000
/// PNG reports 40000 × 40000 although ``DecodedImage`` refuses it above 16384 a side, so a non-nil
/// `ImageInfo` does not mean decodable. To bound a decode use ``DecodedImage/Limits``, which runs
/// this read before any pixel is allocated.
///
/// The width and height of a decodable image equal ``DecodedImage``'s (the decoder refuses a stb
/// size that disagrees with this header, `IH-I`), and ``orientation`` is the one the decode reports.
public struct ImageInfo: Sendable, Hashable {
    /// The file format.
    public enum Format: Sendable, Hashable {
        /// PNG.
        case png
        /// JPEG, baseline or progressive.
        case jpeg
    }

    /// The file format.
    public let format: Format
    /// The stored width in pixels, before ``orientation``; at least 1.
    public let width: Int
    /// The stored height in pixels, before ``orientation``; at least 1.
    public let height: Int
    /// The EXIF orientation of a JPEG `APP1` or a PNG `eXIf` chunk; `.up` when there is none or it is
    /// damaged (as ``DecodedImage/orientation``).
    public let orientation: Image.Orientation
    /// Bits per sample as the header stores them: a PNG's IHDR bit depth (1, 2, 4, 8, 16), a JPEG's
    /// frame precision.
    public let bitDepth: Int
    /// Stored channels: a PNG's grey 1, grey with alpha 2, RGB 3, palette 3, RGBA 4; a JPEG's
    /// component count (1 to 4).
    public let channelCount: Int

    /// The size once ``orientation`` is applied: width and height swap for a rotated one.
    public var orientedSize: (width: Int, height: Int) {
        orientation.swapsAxes ? (height, width) : (width, height)
    }

    init(format: Format, width: Int, height: Int, orientation: Image.Orientation, bitDepth: Int, channelCount: Int) {
        self.format = format
        self.width = width
        self.height = height
        self.orientation = orientation
        self.bitDepth = bitDepth
        self.channelCount = channelCount
    }

    /// The header of PNG or JPEG bytes, or `nil` for any other format or a damaged header. Reads
    /// only the structure (IHDR or the segments up to the first scan, plus the EXIF payload).
    public init?(data: Data) {
        let read: ImageInfo? = data.withUnsafeBytes { readImageInfo(MemoryHeaderSource(bytes: $0)) }
        guard let read else { return nil }
        self = read
    }

    /// The header of the PNG or JPEG file at `path`, or `nil` when the file is missing, is not a regular
    /// file (a directory, FIFO or device is never opened), is not PNG or JPEG or has a damaged header.
    /// It seeks over the pixel data and reads through one 64 KiB window (`IH-G`, `IH-M`); the answer
    /// equals ``init(data:)`` of the whole file, including a PNG whose `eXIf` follows the pixels. An
    /// EXIF payload over 1 MiB is damaged (`.up`) here and in ``init(data:)``.
    public init?(contentsOfFile path: String) {
        guard let source = FileHeaderSource(path: path, trace: nil), let read = readImageInfo(source) else { return nil }
        self = read
    }
}

extension DecodedImage {
    /// Bounds checked from the header **before** any pixel is decoded (`IH-J`): an image over a limit
    /// is `nil` and never reaches the decoder, so an oversize image costs no pixel memory. A `nil`
    /// limit is no limit of that kind; every bound is inclusive.
    public struct Limits: Sendable, Hashable {
        /// The most bytes of input (the data's size, or the file's size read before the file is).
        public var maxInputBytes: Int?
        /// The most pixels on either stored side.
        public var maxSide: Int?
        /// The most pixels in all (`width × height`; an overflowing product is over any limit).
        public var maxPixels: Int?

        /// Limits; every omitted one is unlimited.
        public init(maxInputBytes: Int? = nil, maxSide: Int? = nil, maxPixels: Int? = nil) {
            self.maxInputBytes = maxInputBytes
            self.maxSide = maxSide
            self.maxPixels = maxPixels
        }
    }

    /// Decodes PNG or JPEG bytes as ``init(data:format:)`` does, or `nil` when the input, the stored
    /// size or the pixel count is over `limits` (checked in that order from the header, before the
    /// decoder allocates anything), or when the header cannot be read. An image inside the limits
    /// decodes byte-identically to the unlimited initialiser.
    public init?(data: Data, format: Format = .rgba, limits: Limits) {
        guard let decoded = DecodedImage.limitedDecode(data: data, format: format, limits: limits, trace: nil) else { return nil }
        self = decoded
    }

    /// Decodes the PNG or JPEG file at `path` as ``init(data:format:limits:)`` does. The file's size is
    /// checked against `maxInputBytes` before any of it is read; a path that is not a regular file is
    /// `nil`.
    public init?(contentsOfFile path: String, format: Format = .rgba, limits: Limits) {
        guard let decoded = DecodedImage.limitedDecode(path: path, format: format, limits: limits, trace: nil) else { return nil }
        self = decoded
    }

    /// The one decode: limits, then the decoder with the header's size as its expectation (`IH-I`).
    static func limitedDecode(data: Data, format: Format, limits: Limits, trace: HeaderTrace?) -> DecodedImage? {
        data.withUnsafeBytes { bytes in
            if let maxInput = limits.maxInputBytes, bytes.count > maxInput { return nil }
            guard let info = readImageInfo(MemoryHeaderSource(bytes: bytes)), limits.accepts(info) else { return nil }
            return decode(bytes, info: info, format: format, trace: trace)
        }
    }

    /// The file route: size and header through the file source, then one bounded load for the decode.
    static func limitedDecode(path: String, format: Format, limits: Limits, trace: HeaderTrace?) -> DecodedImage? {
        guard let source = FileHeaderSource(path: path, trace: trace) else { return nil }
        if let maxInput = limits.maxInputBytes, source.size > maxInput { return nil }
        guard let info = readImageInfo(source), limits.accepts(info), source.size <= Int(Int32.max),
              let bytes = source.load(at: 0, count: source.size) else { return nil }
        trace?.wholeFileLoads += 1
        return bytes.withUnsafeBytes { decode($0, info: info, format: format, trace: trace) }
    }

    private static func decode(_ bytes: UnsafeRawBufferPointer, info: ImageInfo, format: Format,
                               trace: HeaderTrace?) -> DecodedImage? {
        trace?.decodeCalls += 1
        guard let image = decodeImage(bytes, channels: format == .rgba ? 4 : 1,
                                      expecting: (info.width, info.height)) else { return nil }
        return DecodedImage(format: format, width: image.width, height: image.height, pixels: image.samples,
                            orientation: info.orientation)
    }
}

extension DecodedImage.Limits {
    /// Whether the header's stored size is inside the side and pixel limits.
    func accepts(_ info: ImageInfo) -> Bool {
        if let maxSide, info.width > maxSide || info.height > maxSide { return false }
        if let maxPixels, exceedsPixelLimit(width: info.width, height: info.height, max: maxPixels) { return false }
        return true
    }
}
