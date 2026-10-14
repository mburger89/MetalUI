import Testing
import Foundation
@testable import MetalUI

// Lane 1 tests 7-11 (rulings IB-D, IB-H, IB-K; spec 2026-10-13-image-decode-api §5). Every block is
// built in the test (`ImageTestBytes.swift`). Truncation and hostile fields are enumerations, not
// random (IB-H).

private func jpegOrientation(_ bytes: [UInt8]) -> Image.Orientation? {
    withBytes(bytes) { exifOrientation(inJPEG: $0) }
}

private func pngOrientation(_ bytes: [UInt8]) -> Image.Orientation? {
    withBytes(bytes) { exifOrientation(inPNG: $0) }
}

/// **7** `exifOrientationOfAllEightValuesInBothByteOrders`.
/// Mutation: read the `MM` SHORT as its low byte (little-endian order for both).
@Test func exifOrientationOfAllEightValuesInBothByteOrders() throws {
    for bigEndian in [false, true] {
        for value in 1...8 {
            let jpeg = jpegWith([exifAPP1(orientationTIFF(UInt16(value), bigEndian: bigEndian))])
            #expect(jpegOrientation(jpeg) == Image.Orientation(exifValue: value),
                    "value \(value) bigEndian \(bigEndian)")
        }
    }
}

/// **8** `anExifBlockThatIsTruncatedAtEveryLengthIsUpAndNeverTraps`: the APP1 of test 7 cut at every
/// offset 0...count (the segment length field now lies), and again with the length field rewritten
/// to cover only what is left (the TIFF is cut inside a well-formed segment). Always `nil` or the
/// true value. Mutation: drop one `offset + n <= count` check.
@Test func anExifBlockThatIsTruncatedAtEveryLengthIsUpAndNeverTraps() throws {
    for bigEndian in [false, true] {
        let tiff = orientationTIFF(6, bigEndian: bigEndian)
        let whole = [0xFF, 0xD8] + exifAPP1(tiff)
        try #require(jpegOrientation(whole) == .right)
        for cut in 0...whole.count {
            let result = jpegOrientation(Array(whole[..<cut]))
            #expect(result == nil || result == .right, "cut \(cut)")
        }
        for keep in 0...tiff.count {
            let jpeg = [0xFF, 0xD8] + exifAPP1(Array(tiff[..<keep]))
            let result = jpegOrientation(jpeg)
            // IFD0 is complete at byte 8 + 2 + 12 = 22; the next-IFD pointer is never needed.
            #expect(result == (keep >= 22 ? .right : nil), "keep \(keep) read \(String(describing: result))")
        }
    }
    // The PNG route, the same enumeration.
    let tiff = orientationTIFF(6, bigEndian: true)
    let png = makePNG(width: 1, height: 1, bitDepth: 8, colorType: 0, rows: [7],
                      before: [pngChunk("eXIf", tiff)])
    try #require(pngOrientation(png) == .right)
    for cut in 0...png.count {
        let result = pngOrientation(Array(png[..<cut]))
        #expect(result == nil || result == .right, "png cut \(cut)")
    }
}

/// **9** `hostileExifFieldsAreIgnored`. Mutations: accept a type other than SHORT (the LONG rows);
/// drop the entry-count clamp (the 65535 row).
@Test func hostileExifFieldsAreIgnored() throws {
    let control = jpegOrientation(jpegWith([exifAPP1(orientationTIFF(6, bigEndian: false))]))
    try #require(control == .right, "the control must read")
    func read(_ tiff: [UInt8]) -> Image.Orientation? { jpegOrientation(jpegWith([exifAPP1(tiff)])) }
    let short6 = le16(6) + [0, 0]
    let rows: [(String, [UInt8])] = [
        ("IFD offset past the end", tiffBlock(bigEndian: false, entries: [(0x0112, 3, 1, short6)], ifdOffset: 0x100)),
        ("IFD offset 0xFFFFFFFF", tiffBlock(bigEndian: false, entries: [(0x0112, 3, 1, short6)], ifdOffset: 0xFFFF_FFFF)),
        ("IFD offset 0 (the header itself)", tiffBlock(bigEndian: false, entries: [(0x0112, 3, 1, short6)], ifdOffset: 0)),
        ("entry count 65535, two bytes left",
         Array(tiffBlock(bigEndian: false, entries: [(0x0112, 3, 1, short6)], entryCount: 65535)[..<12])),
        ("entry count 65535, entries cut mid-entry",
         Array(tiffBlock(bigEndian: false, entries: [(0x0112, 3, 1, short6)], entryCount: 65535)[..<19])),
        ("a next-IFD pointer to itself",
         tiffBlock(bigEndian: false, entries: [(0x0110, 3, 1, short6)], nextIFD: 8)),
        ("no entries", tiffBlock(bigEndian: false, entries: [])),
        ("type LONG, count 1", tiffBlock(bigEndian: false, entries: [(0x0112, 4, 1, le32(6))])),
        ("type BYTE, count 1", tiffBlock(bigEndian: false, entries: [(0x0112, 1, 1, [6, 0, 0, 0])])),
        ("type SHORT, count 2", tiffBlock(bigEndian: false, entries: [(0x0112, 3, 2, short6)])),
        ("type SHORT, count 0", tiffBlock(bigEndian: false, entries: [(0x0112, 3, 0, short6)])),
        ("value 0", orientationTIFF(0, bigEndian: false)),
        ("value 9", orientationTIFF(9, bigEndian: false)),
        ("value 0xFFFF", orientationTIFF(0xFFFF, bigEndian: false)),
        ("bad byte-order mark", [0x49, 0x4D, 0x2A, 0] + Array(orientationTIFF(6, bigEndian: false)[4...])),
        ("bad magic", [0x49, 0x49, 0x2B, 0] + Array(orientationTIFF(6, bigEndian: false)[4...])),
    ]
    for (name, tiff) in rows {
        #expect(read(tiff) == nil, "\(name)")
    }
}

/// **10** `theFirstExifSegmentWinsAndOnlyBeforeSOS`. Mutation: a raw byte search for `Exif`
/// (the thumbnail arm reads 3, not 6).
@Test func theFirstExifSegmentWinsAndOnlyBeforeSOS() throws {
    let six = exifAPP1(orientationTIFF(6, bigEndian: false))
    let three = exifAPP1(orientationTIFF(3, bigEndian: true))
    // Two APP1s: the first wins.
    #expect(jpegOrientation(jpegWith([six, three])) == .right)
    // After SOS: ignored.
    let afterScan = [0xFF, 0xD8] + jpegSegment(0xDA, [1, 1, 0, 0, 0x3F, 0]) + six + [0xFF, 0xD9]
    #expect(jpegOrientation(afterScan) == nil)
    // A non-Exif APP1 (XMP) is skipped.
    let xmp = jpegSegment(0xE1, Array("http://ns.adobe.com/xap/1.0/\0<x/>".utf8))
    #expect(jpegOrientation(jpegWith([xmp, six])) == .right)
    // Fill bytes and length-less markers before the APP1.
    #expect(jpegOrientation([0xFF, 0xD8] + [0xFF, 0xFF] + six) == .right)
    #expect(jpegOrientation([0xFF, 0xD8] + [0xFF, 0x01] + six) == .right)
    #expect(jpegOrientation([0xFF, 0xD8] + [0xFF, 0xD3] + six) == .right)
    // A segment of length 0 or 1 ends the walk.
    #expect(jpegOrientation([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x00] + six) == nil)
    #expect(jpegOrientation([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x01] + six) == nil)
    // A thumbnail holding its own SOI and Exif APP1 inside another segment: walked over by length.
    let thumbnail = jpegSegment(0xE1, Array("http://ns.adobe.com/xap/1.0/\0".utf8) + [0xFF, 0xD8] + three)
    #expect(jpegOrientation(jpegWith([thumbnail, six])) == .right, "the real Exif, not the embedded 3")
    #expect(jpegOrientation(jpegWith([thumbnail])) == nil, "an embedded Exif alone is not the image's")
    // Not a JPEG at all.
    #expect(jpegOrientation([0x00, 0x01, 0x02]) == nil)
    #expect(jpegOrientation([]) == nil)
}

/// **11** `aPngExifChunkIsRead`. Mutations: read an `eXIf` between IDATs; stop at the first IDAT
/// (reddens the after-arm). A bad CRC on the chunk makes the file `nil` through the structure
/// check, as for any chunk.
@Test func aPngExifChunkIsRead() throws {
    let six = pngChunk("eXIf", orientationTIFF(6, bigEndian: true))
    let before = makePNG(width: 2, height: 1, bitDepth: 8, colorType: 0, rows: [1, 2], before: [six])
    #expect(pngOrientation(before) == .right)
    let after = makePNG(width: 2, height: 1, bitDepth: 8, colorType: 0, rows: [1, 2], after: [six])
    #expect(pngOrientation(after) == .right, "PNG 1.5 allows eXIf after the last IDAT")
    let between = makePNG(width: 2, height: 1, bitDepth: 8, colorType: 0, rows: [1, 2], between: [six])
    #expect(pngOrientation(between) == nil, "between two IDATs is not a legal place")
    let none = makePNG(width: 2, height: 1, bitDepth: 8, colorType: 0, rows: [1, 2])
    #expect(pngOrientation(none) == nil)
    let bad = makePNG(width: 2, height: 1, bitDepth: 8, colorType: 0, rows: [1, 2],
                      before: [pngChunk("eXIf", orientationTIFF(6, bigEndian: true), badCRC: true)])
    #expect(DecodedImage(data: Data(bad)) == nil)
    #expect(DecodedImage(data: Data(before)) != nil, "the same file with a good CRC decodes")
    #expect(pngOrientation([]) == nil)
    #expect(pngOrientation([0x89, 0x50]) == nil)
}
