import Testing
import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif
@testable import MetalUI

// Item S9 (rulings IH-A…IH-P; spec 2026-10-14-image-info-design §5). Bytes are generated
// (`ImageTestBytes.swift`); the real fixtures are `ImageFixtures`. Truncation and hostile fields are
// enumerations, not random. A test that counts work reads a `HeaderTrace`, never a clock.

private let fixtureDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    .appendingPathComponent("ImageFixtures")

private func fixtureNames() throws -> [String] {
    try FileManager.default.contentsOfDirectory(atPath: fixtureDirectory.path)
        .filter { $0.hasSuffix(".png") || $0.hasSuffix(".jpg") }.sorted()
}

private func fixtureData(_ name: String) throws -> Data {
    try Data(contentsOf: fixtureDirectory.appendingPathComponent(name))
}

private func info(_ bytes: [UInt8]) -> ImageInfo? { ImageInfo(data: Data(bytes)) }

/// A SOF segment of `marker` with `components` components and the given size.
private func sof(_ marker: UInt8 = 0xC0, width: Int, height: Int, precision: UInt8 = 8,
                 components: Int = 3) -> [UInt8] {
    var payload: [UInt8] = [precision] + be16(UInt16(height)) + be16(UInt16(width)) + [UInt8(components)]
    for index in 0..<components { payload += [UInt8(index + 1), 0x11, 0] }
    return jpegSegment(marker, payload)
}

private func eXIf(_ value: UInt16) -> [UInt8] { pngChunk("eXIf", orientationTIFF(value, bigEndian: true)) }

private func rgbaPNG(width: Int, height: Int, before: [[UInt8]] = [], between: [[UInt8]] = [],
                     after: [[UInt8]] = []) -> [UInt8] {
    makePNG(width: width, height: height, bitDepth: 8, colorType: 6,
            rows: [UInt8](repeating: 9, count: width * height * 4), before: before, between: between, after: after)
}

private func ihdr(_ width: UInt32, _ height: UInt32, depth: UInt8 = 8, colour: UInt8 = 2, length: Int? = nil,
                  badCRC: Bool = false) -> [UInt8] {
    var data = be32(width) + be32(height) + [depth, colour, 0, 0, 0]
    if let length { data = Array((data + [UInt8](repeating: 0, count: 64)).prefix(length)) }
    return [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A] + pngChunk("IHDR", data, badCRC: badCRC)
        + pngChunk("IEND", [])
}

/// **1** `aPNGReportsSizeDepthAndChannelsForEveryColourType`. Mutation: palette 3 → 1 channel.
@Test func aPNGReportsSizeDepthAndChannelsForEveryColourType() throws {
    let legal: [(colour: UInt8, depths: [UInt8], channels: Int)] = [
        (0, [1, 2, 4, 8, 16], 1), (2, [8, 16], 3), (3, [1, 2, 4, 8], 3), (4, [8, 16], 2), (6, [8, 16], 4),
    ]
    var checked = 0
    for entry in legal {
        for depth in entry.depths {
            let png = makePNG(width: 5, height: 3, bitDepth: depth, colorType: entry.colour,
                              rows: [UInt8](repeating: 0, count: 5 * 3 * 8))
            let read = try #require(info(png), "colour \(entry.colour) depth \(depth)")
            #expect(read.format == .png)
            #expect(read.width == 5 && read.height == 3)
            #expect(read.bitDepth == Int(depth), "colour \(entry.colour) depth \(depth)")
            #expect(read.channelCount == entry.channels, "colour \(entry.colour) depth \(depth)")
            #expect(read.orientation == .up)
            checked += 1
        }
    }
    try #require(checked == 15, "all fifteen legal pairs")
}

/// **2** `aJPEGReportsSizePrecisionAndComponents`. Mutation: the SOF set loses `0xC2`.
@Test func aJPEGReportsSizePrecisionAndComponents() throws {
    for (marker, components) in [(UInt8(0xC0), 1), (0xC0, 3), (0xC2, 3), (0xC2, 4)] {
        let jpeg = jpegWith([sof(marker, width: 7, height: 5, components: components)])
        let read = try #require(info(jpeg), "marker \(marker) components \(components)")
        #expect(read.format == .jpeg && read.width == 7 && read.height == 5)
        #expect(read.bitDepth == 8 && read.channelCount == components)
    }
    let twelve = try #require(info(jpegWith([sof(0xC1, width: 2, height: 2, precision: 12, components: 1)])))
    #expect(twelve.bitDepth == 12, "precision as stored")
    #expect(try #require(info(jpegWith([sof(width: 7, height: 5)]))).orientedSize == (7, 5))
}

/// **3** `everyDimensionBearingSOFMarkerIsRead`. Mutation: add `0xC4` to the set.
@Test func everyDimensionBearingSOFMarkerIsRead() throws {
    let frames: [UInt8] = [0xC0, 0xC1, 0xC2, 0xC3, 0xC5, 0xC6, 0xC7, 0xC9, 0xCA, 0xCB, 0xCD, 0xCE, 0xCF]
    for marker in frames {
        let read = try #require(info(jpegWith([sof(marker, width: 5, height: 3)])), "SOF \(marker)")
        #expect(read.width == 5 && read.height == 3, "SOF \(marker)")
    }
    // A DHT, JPG or DAC segment whose payload looks like a frame is never one.
    for marker: UInt8 in [0xC4, 0xC8, 0xCC] {
        let fake = sof(marker, width: 9, height: 9)
        #expect(info(jpegWith([fake])) == nil, "only a \(marker) lookalike")
        let read = try #require(info(jpegWith([fake, sof(0xC0, width: 5, height: 3)])), "before the frame \(marker)")
        #expect(read.width == 5 && read.height == 3, "a \(marker) before the SOF")
    }
}

/// **4** `theSizeEqualsTheDecodersForEveryFixture`. Mutation: IHDR width and height read swapped.
@Test func theSizeEqualsTheDecodersForEveryFixture() throws {
    var compared = 0
    var inputs: [(String, Data)] = try fixtureNames().map { ($0, try fixtureData($0)) }
    inputs.append(("generated rgba", Data(rgbaPNG(width: 9, height: 4))))
    inputs.append(("generated grey16", Data(makePNG(width: 3, height: 7, bitDepth: 16, colorType: 0,
                                                    rows: [UInt8](repeating: 1, count: 42)))))
    for (name, data) in inputs {
        guard let decoded = DecodedImage(data: data) else { continue }
        let read = try #require(ImageInfo(data: data), "\(name) decodes, so it has a header")
        #expect(read.width == decoded.width && read.height == decoded.height, "\(name)")
        #expect(read.orientation == decoded.orientation, "\(name)")
        #expect(read.orientedSize == decoded.orientedSize, "\(name)")
        compared += 1
    }
    try #require(compared >= 10, "the loop must compare real fixtures, compared \(compared)")
}

/// **5** `theOrientationMatchesTheS2WalksOnEveryFixture`. Mutation: drop the after-IDAT arm of the shared walk.
@Test func theOrientationMatchesTheS2WalksOnEveryFixture() throws {
    for value in 1...8 {
        let want = try #require(Image.Orientation(exifValue: value))
        let tiff = orientationTIFF(UInt16(value), bigEndian: value % 2 == 0)
        let jpeg = jpegWith([exifAPP1(tiff), sof(width: 4, height: 2)])
        #expect(info(jpeg)?.orientation == want, "jpeg \(value)")
        #expect(withBytes(jpeg) { exifOrientation(inJPEG: $0) } == want)
        let chunk = pngChunk("eXIf", tiff)
        let before = rgbaPNG(width: 2, height: 2, before: [chunk])
        let after = rgbaPNG(width: 2, height: 2, after: [chunk])
        let between = rgbaPNG(width: 2, height: 2, between: [chunk])
        #expect(info(before)?.orientation == want, "png before \(value)")
        #expect(info(after)?.orientation == want, "png after \(value)")
        #expect(info(between)?.orientation == .up, "png between IDATs is ignored \(value)")
        for png in [before, after, between] {
            #expect(info(png)?.orientation == (withBytes(png) { exifOrientation(inPNG: $0) } ?? .up))
        }
    }
    // An Exif block after the SOF still counts (it is before the SOS).
    let late = jpegWith([sof(width: 4, height: 2), exifAPP1(orientationTIFF(6, bigEndian: false))])
    #expect(info(late)?.orientation == .right)
}

/// **6** `everyTruncationOfAPNGIsNilOrAPrefixAnswer`. Mutation: the IHDR bound `<=` → `<`.
@Test func everyTruncationOfAPNGIsNilOrAPrefixAnswer() throws {
    let chunk = eXIf(6)
    let png = rgbaPNG(width: 5, height: 3, before: [chunk])
    try #require(info(png)?.width == 5)
    let ihdrEnd = 8 + 25
    let exifEnd = ihdrEnd + chunk.count
    for cut in 0...png.count {
        let read = info(Array(png[..<cut]))
        if cut < ihdrEnd {
            #expect(read == nil, "cut \(cut)")
        } else {
            #expect(read?.width == 5 && read?.height == 3, "cut \(cut)")
            #expect(read?.orientation == (cut >= exifEnd ? .right : .up), "cut \(cut)")
        }
    }
}

/// **7** `everyTruncationOfAJPEGIsNilOrAPrefixAnswer`. Mutation: the SOF length guard removed.
@Test func everyTruncationOfAJPEGIsNilOrAPrefixAnswer() throws {
    let app0 = jpegSegment(0xE0, Array("JFIF\0".utf8) + [1, 1, 0, 0, 1, 0, 1, 0, 0])
    let app1 = exifAPP1(orientationTIFF(6, bigEndian: true))
    let frame = sof(width: 5, height: 3)
    let jpeg = jpegWith([app0, app1, frame])
    try #require(info(jpeg)?.width == 5)
    let sofEnd = 2 + app0.count + app1.count + frame.count
    for cut in 0...jpeg.count {
        let read = info(Array(jpeg[..<cut]))
        if cut < sofEnd {
            #expect(read == nil, "cut \(cut)")
        } else {
            #expect(read?.width == 5 && read?.height == 3, "cut \(cut)")
            #expect(read?.orientation == .right, "cut \(cut)")
        }
    }
}

/// **8** `aHostileHeaderIsNilNotATrap`. Mutations: drop the IHDR CRC check; drop the `height >= 1` check.
@Test func aHostileHeaderIsNilNotATrap() throws {
    try #require(info(ihdr(5, 3))?.width == 5, "the PNG control must read")
    try #require(info(jpegWith([sof(width: 5, height: 3)]))?.width == 5, "the JPEG control must read")
    let pngRows: [(String, [UInt8])] = [
        ("IHDR length 12", ihdr(5, 3, length: 12)), ("IHDR length 14", ihdr(5, 3, length: 14)),
        ("bad CRC", ihdr(5, 3, badCRC: true)), ("width 0", ihdr(0, 3)), ("height 0", ihdr(5, 0)),
        ("width 2^31", ihdr(1 << 31, 3)), ("height 2^32-1", ihdr(5, UInt32.max)),
        ("depth 3", ihdr(5, 3, depth: 3)), ("palette 16-bit", ihdr(5, 3, depth: 16, colour: 3)),
        ("colour type 1", ihdr(5, 3, depth: 8, colour: 1)), ("RGB 4-bit", ihdr(5, 3, depth: 4, colour: 2)),
    ]
    for (name, bytes) in pngRows { #expect(info(bytes) == nil, "\(name)") }
    #expect(info(ihdr(1 << 31 - 1, 1 << 31 - 1))?.width == (1 << 31) - 1, "the largest legal side")
    let short = jpegSegment(0xC0, [8, 0, 3, 0, 5])
    let jpegRows: [(String, [UInt8])] = [
        ("SOF length 7", jpegWith([short])), ("height 0", jpegWith([sof(width: 5, height: 0)])),
        ("width 0", jpegWith([sof(width: 0, height: 3)])),
        ("0 components", jpegWith([jpegSegment(0xC0, [8, 0, 3, 0, 5, 0])])),
        ("5 components", jpegWith([sof(width: 5, height: 3, components: 5)])),
        ("components past the segment", jpegWith([jpegSegment(0xC0, [8, 0, 3, 0, 5, 3, 1, 0x11, 0])])),
        ("SOF only after the SOS", [0xFF, 0xD8] + jpegSegment(0xDA, [1, 1, 0, 0, 0x3F, 0]) + sof(width: 5, height: 3)),
        ("APP1 past EOF", [0xFF, 0xD8, 0xFF, 0xE1, 0xFF, 0xFF, 0x45, 0x78]),
    ]
    for (name, bytes) in jpegRows { #expect(info(bytes) == nil, "\(name)") }
    // Two SOF: the first wins. A fill run is skipped. A damaged APP1 past EOF after the frame still answers.
    #expect(info(jpegWith([sof(width: 5, height: 3), sof(0xC2, width: 9, height: 9)]))?.width == 5)
    #expect(info([0xFF, 0xD8] + [0xFF, 0xFF, 0xFF] + sof(width: 5, height: 3) + [0xFF, 0xDA])?.width == 5)
    #expect(info([0xFF, 0xD8] + sof(width: 5, height: 3) + [0xFF, 0xE1, 0xFF, 0xFF, 0x45])?.width == 5)
    // A first SOF that is damaged is nil even when a good one follows.
    #expect(info(jpegWith([sof(width: 5, height: 0), sof(width: 5, height: 3)])) == nil)
}

/// **9** `aFormatOtherThanPNGOrJPEGIsNil`. Mutation: a GIF arm that returns a made-up size.
@Test func aFormatOtherThanPNGOrJPEGIsNil() throws {
    let gif = Array("GIF89a".utf8) + le16(5) + le16(3) + [0, 0, 0]
    let tiff: [UInt8] = [0x49, 0x49, 0x2A, 0, 8, 0, 0, 0, 0, 0]
    let webp = Array("RIFF".utf8) + le32(20) + Array("WEBPVP8 ".utf8) + [UInt8](repeating: 0, count: 16)
    let bmp = Array("BM".utf8) + [UInt8](repeating: 0, count: 60)
    for (name, bytes) in [("gif", gif), ("tiff", tiff), ("webp", webp), ("bmp", bmp), ("empty", []),
                          ("one byte", [0xFF]), ("signature only", [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])] {
        #expect(info(bytes) == nil, "\(name)")
    }
    #expect(try fixtureData("rgb8.tiff").isEmpty == false)
    #expect(ImageInfo(data: try fixtureData("rgb8.tiff")) == nil, "the TIFF fixture")
}

/// **10** `aSizeAboveTheDecoderLimitStillReports`. Mutation: add `decodedSizeIsAccepted` to `ImageInfo`.
@Test func aSizeAboveTheDecoderLimitStillReports() throws {
    let png = ihdr(20000, 20000)
    let read = try #require(info(png))
    #expect(read.width == 20000 && read.height == 20000)
    #expect(DecodedImage(data: Data(png)) == nil)
    #expect(info(try [UInt8](fixtureData("wide-16385x1.png")))?.width == 16385)
}

/// A trace-friendly temporary file.
private func tempFile(_ bytes: some Sequence<UInt8>, name: String = UUID().uuidString) throws -> String {
    let path = NSTemporaryDirectory() + "imageinfo-\(name)"
    try Data(bytes).write(to: URL(fileURLWithPath: path))
    return path
}

/// **11** `theFileReaderEqualsTheDataReaderAndReadsNoPixels`. Mutation: the file reader reads
/// `prefix(65536)` only (the eXIf-after-IDAT fixture reddens).
@Test func theFileReaderEqualsTheDataReaderAndReadsNoPixels() throws {
    var inputs: [(String, [UInt8])] = try fixtureNames().map { ($0, [UInt8](try fixtureData($0))) }
    let rows = [UInt8](repeating: 7, count: 1024 * 1024 * 3)
    let big = makePNG(width: 1024, height: 1024, bitDepth: 8, colorType: 2, rows: rows, after: [eXIf(6)])
    inputs.append(("eXIf after 3 MB", big))
    inputs.append(("jpeg", jpegWith([exifAPP1(orientationTIFF(8, bigEndian: false)), sof(width: 6, height: 4)])))
    var read = 0
    for (name, bytes) in inputs {
        let path = try tempFile(bytes, name: name)
        defer { try? FileManager.default.removeItem(atPath: path) }
        let fromFile = ImageInfo(contentsOfFile: path)
        #expect(fromFile == ImageInfo(data: Data(bytes)), "\(name)")
        if fromFile != nil { read += 1 }
    }
    try #require(read >= 10, "the loop must read real files, read \(read)")
    #expect(ImageInfo(contentsOfFile: try tempFile(big, name: "big"))?.orientation == .right, "after the pixels")
    // Counted work: refills bounded by the file size over the window, none inside the IDAT payload.
    let path = try tempFile(big, name: "trace")
    defer { try? FileManager.default.removeItem(atPath: path) }
    let trace = HeaderTrace()
    let source = try #require(FileHeaderSource(path: path, trace: trace))
    #expect(source.size == big.count)
    #expect(readImageInfo(source)?.orientation == .right)
    let payload = (8 + 25 + 8)..<(big.count - eXIf(6).count - 12 - 4)
    #expect(trace.refills.count <= 2 + big.count / 65536 + trace.payloadReads, "refills \(trace.refills)")
    #expect(trace.refills.count >= 1)
    #expect(trace.refills.allSatisfy { !payload.contains($0) }, "a refill started inside the IDAT: \(trace.refills)")
    // IH-N: a directory, a FIFO and a file shortened after its size was recorded.
    #expect(ImageInfo(contentsOfFile: NSTemporaryDirectory()) == nil, "a directory")
    #expect(ImageInfo(contentsOfFile: NSTemporaryDirectory() + "no-such-\(UUID().uuidString)") == nil)
    #if canImport(Darwin) || canImport(Glibc)
    let fifo = NSTemporaryDirectory() + "imageinfo-fifo-\(UUID().uuidString)"
    try #require(mkfifo(fifo, 0o600) == 0)
    defer { unlink(fifo) }
    #expect(ImageInfo(contentsOfFile: fifo) == nil, "a FIFO (never opened)")
    #expect(DecodedImage(contentsOfFile: fifo, limits: DecodedImage.Limits(maxInputBytes: 1 << 30)) == nil)
    #endif
    let shrinking = try tempFile(big, name: "shrinking")
    defer { try? FileManager.default.removeItem(atPath: shrinking) }
    let recorded = try #require(FileHeaderSource(path: shrinking, trace: nil))
    try Data([1, 2, 3]).write(to: URL(fileURLWithPath: shrinking))
    #expect(readImageInfo(recorded) == nil, "a short read is damage, not a trap")
}

/// **12** `anEXIFPayloadOverOneMebibyteIsDamagedOnBothPaths`. Mutation: cap off by one; cap removed on the
/// file path only.
@Test func anEXIFPayloadOverOneMebibyteIsDamagedOnBothPaths() throws {
    let cap = 1 << 20
    func png(payload size: Int) -> [UInt8] {
        let tiff = orientationTIFF(6, bigEndian: true)
        return rgbaPNG(width: 2, height: 2, before: [pngChunk("eXIf", tiff + [UInt8](repeating: 0, count: size - tiff.count))])
    }
    for (size, want) in [(cap, Image.Orientation.right), (cap + 1, .up)] {
        let bytes = png(payload: size)
        #expect(info(bytes)?.orientation == want, "data \(size)")
        #expect(withBytes(bytes) { exifOrientation(inPNG: $0) } == (size == cap ? .right : nil), "wrapper \(size)")
        let path = try tempFile(bytes, name: "cap\(size)")
        defer { try? FileManager.default.removeItem(atPath: path) }
        #expect(ImageInfo(contentsOfFile: path)?.orientation == want, "file \(size)")
        #expect(ImageInfo(contentsOfFile: path)?.width == 2)
    }
}

private func decodable(_ width: Int, _ height: Int) -> Data {
    Data(rgbaPNG(width: width, height: height))
}

/// **13** `limitsRefuseBeforeStbSeesTheBytes`. Mutation: move the limit check after `decodeImage`.
@Test func limitsRefuseBeforeStbSeesTheBytes() throws {
    let wide = decodable(20, 1), tall = decodable(10, 40), small = decodable(4, 3)
    let refused: [(String, Data, DecodedImage.Limits)] = [
        ("side", wide, .init(maxSide: 19)), ("side on height", tall, .init(maxSide: 39)),
        ("pixels", tall, .init(maxPixels: 399)), ("input", small, .init(maxInputBytes: small.count - 1)),
    ]
    for (name, data, limits) in refused {
        let trace = HeaderTrace()
        #expect(DecodedImage.limitedDecode(data: data, format: .rgba, limits: limits, trace: trace) == nil, "\(name)")
        #expect(trace.decodeCalls == 0, "\(name) reached stb")
        #expect(DecodedImage(data: data, limits: limits) == nil, "\(name) public")
    }
    let trace = HeaderTrace()
    let limits = DecodedImage.Limits(maxInputBytes: small.count, maxSide: 4, maxPixels: 12)
    let inside = try #require(DecodedImage.limitedDecode(data: small, format: .rgba, limits: limits, trace: trace))
    #expect(trace.decodeCalls == 1)
    #expect(inside == DecodedImage(data: small), "byte-identical to the unlimited init")
    #expect(DecodedImage(data: small, format: .grey, limits: limits) == DecodedImage(data: small, format: .grey))
    // A header-unreadable image under a limit is nil and never reaches stb either.
    let garbage = HeaderTrace()
    #expect(DecodedImage.limitedDecode(data: Data([1, 2, 3]), format: .rgba, limits: .init(), trace: garbage) == nil)
    #expect(garbage.decodeCalls == 0)
}

/// **14** `eachLimitIsInclusiveAtItsBoundaryAndRefusedOneOver`. Mutation: `<=` → `<` in each check; drop
/// the overflow report.
@Test func eachLimitIsInclusiveAtItsBoundaryAndRefusedOneOver() throws {
    let data = decodable(6, 5)
    func decodes(_ limits: DecodedImage.Limits) -> Bool { DecodedImage(data: data, limits: limits) != nil }
    #expect(decodes(.init(maxSide: 6)) && !decodes(.init(maxSide: 5)))
    #expect(decodes(.init(maxPixels: 30)) && !decodes(.init(maxPixels: 29)))
    #expect(decodes(.init(maxInputBytes: data.count)) && !decodes(.init(maxInputBytes: data.count - 1)))
    #expect(decodes(.init()), "nil is unlimited")
    #expect(decodes(.init(maxInputBytes: nil, maxSide: nil, maxPixels: nil)))
    #expect(!decodes(.init(maxInputBytes: -1)), "a negative limit refuses everything")
    // Overflow: a product past Int.max is a refusal, never a wrap.
    #expect(exceedsPixelLimit(width: Int.max, height: 2, max: Int.max))
    #expect(!exceedsPixelLimit(width: 1 << 20, height: 1 << 20, max: Int.max))
    #expect(exceedsPixelLimit(width: 6, height: 5, max: 29) && !exceedsPixelLimit(width: 6, height: 5, max: 30))
    // The largest legal PNG sides, header only: refused by pixels, stb never called.
    let huge = Data(ihdr((1 << 31) - 1, (1 << 31) - 1))
    let trace = HeaderTrace()
    #expect(DecodedImage.limitedDecode(data: huge, format: .rgba, limits: .init(maxPixels: 1 << 60), trace: trace) == nil)
    #expect(trace.decodeCalls == 0)
}

/// **15** `aFileOverTheInputLimitIsRefusedWithoutReadingIt`. Mutation: check the limit after loading.
@Test func aFileOverTheInputLimitIsRefusedWithoutReadingIt() throws {
    let data = decodable(8, 8)
    let path = try tempFile(data, name: "limit")
    defer { try? FileManager.default.removeItem(atPath: path) }
    let refused = HeaderTrace()
    #expect(DecodedImage.limitedDecode(path: path, format: .rgba, limits: .init(maxInputBytes: data.count - 1),
                                       trace: refused) == nil)
    #expect(refused.refills.isEmpty && refused.payloadReads == 0 && refused.wholeFileLoads == 0
            && refused.decodeCalls == 0, "read something: \(refused.refills)")
    let allowed = HeaderTrace()
    let image = try #require(DecodedImage.limitedDecode(path: path, format: .rgba,
                                                        limits: .init(maxInputBytes: data.count), trace: allowed))
    #expect(allowed.wholeFileLoads == 1 && allowed.decodeCalls == 1)
    #expect(image == DecodedImage(data: data))
    #expect(DecodedImage(contentsOfFile: path, limits: .init(maxSide: 7)) == nil)
    #expect(DecodedImage(contentsOfFile: path, limits: .init(maxSide: 8)) == image)
    #expect(DecodedImage(contentsOfFile: path + "-missing", limits: .init()) == nil)
}

/// **16** `aDecodeWhoseSizeDisagreesWithTheHeaderIsNil`. Mutation: drop the equality check.
@Test func aDecodeWhoseSizeDisagreesWithTheHeaderIsNil() throws {
    let data = decodable(6, 5)
    let outcomes: [(Int, Int, Bool)] = [(6, 5, true), (5, 6, false), (6, 6, false), (7, 5, false)]
    for (width, height, accepted) in outcomes {
        let result = data.withUnsafeBytes { decodeImage($0, channels: 4, expecting: (width, height)) }
        #expect((result != nil) == accepted, "expecting \(width)x\(height)")
    }
    // 16-bit path too.
    let sixteen = Data(makePNG(width: 2, height: 2, bitDepth: 16, colorType: 6,
                               rows: [UInt8](repeating: 3, count: 32)))
    #expect(sixteen.withUnsafeBytes { decodeImage($0, channels: 4, expecting: (2, 2)) } != nil)
    #expect(sixteen.withUnsafeBytes { decodeImage($0, channels: 4, expecting: (3, 2)) } == nil)
    #expect(data.withUnsafeBytes { decodeImage($0, channels: 4) } != nil, "nil expectation skips the check")
    #expect(DecodedImage(data: data) != nil && DecodedImage(data: data, limits: .init()) != nil)
}

/// **17** `theUnlimitedInitStillDecodesEveryS2Fixture`: the unlimited init refuses exactly what the bare
/// decoder refuses. Mutation: make `ImageInfo` stricter than the decoder (require `Exif` before the SOF).
@Test func theUnlimitedInitStillDecodesEveryS2Fixture() throws {
    var decoded = 0
    for name in try fixtureNames() {
        let data = try fixtureData(name)
        let bare = data.withUnsafeBytes { decodeImage($0) }
        let init_ = DecodedImage(data: data)
        #expect((bare != nil) == (init_ != nil), "\(name)")
        if let bare, let init_ {
            #expect(bare.samples == init_.pixels && bare.width == init_.width, "\(name)")
            decoded += 1
        }
    }
    try #require(decoded >= 10, "decoded \(decoded)")
}

/// **18** `anImageInfoValueIsEqualHashableAndSendable`.
@Test func anImageInfoValueIsEqualHashableAndSendable() throws {
    func sendable<T: Sendable & Hashable>(_ value: T) -> T { value }
    let a = try #require(info(rgbaPNG(width: 4, height: 2, before: [eXIf(6)])))
    let b = try #require(info(rgbaPNG(width: 4, height: 2, before: [eXIf(6)])))
    let c = try #require(info(rgbaPNG(width: 4, height: 2)))
    #expect(sendable(a) == b && a != c && Set([a, b, c]).count == 2)
    #expect(a.orientedSize == (2, 4) && c.orientedSize == (4, 2), "a rotated tag swaps the axes")
    #expect(sendable(DecodedImage.Limits(maxSide: 1)) == DecodedImage.Limits(maxSide: 1))
    #expect(DecodedImage.Limits() == DecodedImage.Limits(maxInputBytes: nil, maxSide: nil, maxPixels: nil))
}
