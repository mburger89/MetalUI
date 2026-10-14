// EXIF orientation from PNG and JPEG bytes (rulings IB-D, IB-K, record 113). Swift, Foundation-free,
// every read bounds-checked: a truncated or hostile block gives `nil`, never a trap or a read past
// the buffer. The JPEG walk is by segment lengths to the first SOS (never a byte search: a thumbnail
// holds its own markers, as `jpegScanIsTerminated`); the PNG walk is by chunk lengths.

/// The orientation the first `Exif` `APP1` segment before the first `SOS` of a JPEG names, or `nil`
/// (no segment, a damaged one, a value outside `1…8`). Does not check that the file decodes. A wrapper
/// over the one walk in `ImageHeader.swift` (`IH-H`).
func exifOrientation(inJPEG bytes: UnsafeRawBufferPointer) -> Image.Orientation? {
    jpegWalk(MemoryHeaderSource(bytes: bytes), wantFrame: false, stopAtExif: true).orientation
}

/// The orientation of a PNG's `eXIf` chunk: the first one before the first `IDAT`, else the first
/// after the last `IDAT` (PNG 1.5; one between two `IDAT`s is ignored), or `nil`. Chunk CRCs are
/// not checked here (`pngStructureIsIntact` does that before a decode); every length is. A wrapper
/// over the one walk in `ImageHeader.swift` (`IH-H`).
func exifOrientation(inPNG bytes: UnsafeRawBufferPointer) -> Image.Orientation? {
    pngOrientation(MemoryHeaderSource(bytes: bytes))
}

/// Orientation tag `0x0112` of IFD0 of a TIFF block (`II*\0` or `MM\0*`): type SHORT, count 1, value
/// `1…8`; anything else `nil`. Only IFD0 is read (the next-IFD pointer is never followed, so no
/// loop is possible); the entry count is clamped to the bytes left; every offset is range-checked
/// without arithmetic that can overflow.
func tiffOrientation(_ bytes: UnsafeRawBufferPointer) -> Image.Orientation? {
    guard bytes.count >= 8 else { return nil }
    let littleEndian: Bool
    if bytes[0] == 0x49, bytes[1] == 0x49 { littleEndian = true }
    else if bytes[0] == 0x4D, bytes[1] == 0x4D { littleEndian = false }
    else { return nil }
    func read16(_ offset: Int) -> Int? {
        guard offset >= 0, offset <= bytes.count - 2 else { return nil }
        let a = Int(bytes[offset]), b = Int(bytes[offset + 1])
        return littleEndian ? b << 8 | a : a << 8 | b
    }
    func read32(_ offset: Int) -> Int? {
        guard let low = read16(littleEndian ? offset : offset + 2),
              let high = read16(littleEndian ? offset + 2 : offset) else { return nil }
        return high << 16 | low
    }
    guard read16(2) == 42, let ifd = read32(4), let declared = read16(ifd) else { return nil }
    let first = ifd + 2                                   // ifd <= bytes.count - 2, so no overflow
    let entries = min(declared, (bytes.count - first) / 12)
    for index in 0..<entries {
        let entry = first + index * 12
        guard let tag = read16(entry) else { return nil }
        guard tag == 0x0112 else { continue }
        guard read16(entry + 2) == 3, read32(entry + 4) == 1, let value = read16(entry + 8) else { return nil }
        return Image.Orientation(exifValue: value)
    }
    return nil
}
