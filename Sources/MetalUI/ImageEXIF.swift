// EXIF orientation from PNG and JPEG bytes (rulings IB-D, IB-K, record 113). Swift, Foundation-free,
// every read bounds-checked: a truncated or hostile block gives `nil`, never a trap or a read past
// the buffer. The JPEG walk is by segment lengths to the first SOS (never a byte search: a thumbnail
// holds its own markers, as `jpegScanIsTerminated`); the PNG walk is by chunk lengths.

/// The orientation the first `Exif` `APP1` segment before the first `SOS` of a JPEG names, or `nil`
/// (no segment, a damaged one, a value outside `1…8`). Does not check that the file decodes.
func exifOrientation(inJPEG bytes: UnsafeRawBufferPointer) -> Image.Orientation? {
    guard bytes.count >= 4, bytes[0] == 0xFF, bytes[1] == 0xD8 else { return nil }
    var offset = 2
    while true {
        guard offset <= bytes.count - 2, bytes[offset] == 0xFF else { return nil }
        let marker = bytes[offset + 1]
        if marker == 0xFF { offset += 1; continue }                                    // fill byte
        if marker == 0x01 || (0xD0...0xD7).contains(marker) { offset += 2; continue }  // no length
        if marker == 0xD8 || marker == 0xD9 || marker == 0xDA { return nil }          // SOI, EOI, SOS
        guard offset <= bytes.count - 4 else { return nil }
        let length = Int(bytes[offset + 2]) << 8 | Int(bytes[offset + 3])
        guard length >= 2, length <= bytes.count - offset - 2 else { return nil }
        if marker == 0xE1, length >= 8 {
            let payload = offset + 4
            let isExif = bytes[payload] == 0x45 && bytes[payload + 1] == 0x78 && bytes[payload + 2] == 0x69
                && bytes[payload + 3] == 0x66 && bytes[payload + 4] == 0 && bytes[payload + 5] == 0
            if isExif {
                return tiffOrientation(UnsafeRawBufferPointer(rebasing: bytes[(payload + 6)..<(offset + 2 + length)]))
            }
        }
        offset += 2 + length
    }
}

/// The orientation of a PNG's `eXIf` chunk: the first one before the first `IDAT`, else the first
/// after the last `IDAT` (PNG 1.5; one between two `IDAT`s is ignored), or `nil`. Chunk CRCs are
/// not checked here (`pngStructureIsIntact` does that before a decode); every length is.
func exifOrientation(inPNG bytes: UnsafeRawBufferPointer) -> Image.Orientation? {
    let signature: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
    guard bytes.count >= 8, zip(bytes.prefix(8), signature).allSatisfy({ $0 == $1 }) else { return nil }
    var offset = 8
    var seenIDAT = false
    var afterIDAT: Range<Int>?
    while bytes.count >= 12, offset <= bytes.count - 12 {
        let length = Int(bytes[offset]) << 24 | Int(bytes[offset + 1]) << 16
            | Int(bytes[offset + 2]) << 8 | Int(bytes[offset + 3])
        guard length <= bytes.count - offset - 12 else { break }
        let type = (bytes[offset + 4], bytes[offset + 5], bytes[offset + 6], bytes[offset + 7])
        let data = (offset + 8)..<(offset + 8 + length)
        if type == (0x49, 0x44, 0x41, 0x54) {                                 // IDAT
            seenIDAT = true
            afterIDAT = nil                                                    // it was between IDATs
        } else if type == (0x65, 0x58, 0x49, 0x66) {                          // eXIf
            if !seenIDAT { return tiffOrientation(UnsafeRawBufferPointer(rebasing: bytes[data])) }
            if afterIDAT == nil { afterIDAT = data }
        } else if type == (0x49, 0x45, 0x4E, 0x44) {                          // IEND
            break
        }
        offset += 12 + length
    }
    return afterIDAT.flatMap { tiffOrientation(UnsafeRawBufferPointer(rebasing: bytes[$0])) }
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
