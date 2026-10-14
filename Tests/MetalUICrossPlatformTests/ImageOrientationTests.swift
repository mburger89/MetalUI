import Testing
@testable import MetalUI

// Lane 1 test 14 (rulings IB-E; probe docs/probes/swiftui-image-orientation.swift).

/// **14** `orientationRawValuesAreSwiftUIsAndExifValuesRoundTrip` (probe arm O1: the eight
/// orientations and their raw values, recorded in the probe's header).
/// Mutation: set `up = 1` (shifts every raw value).
@Test func orientationRawValuesAreSwiftUIsAndExifValuesRoundTrip() throws {
    let probed: [(Image.Orientation, UInt8, Int)] = [
        (.up, 0, 1), (.left, 1, 8), (.upMirrored, 2, 2), (.leftMirrored, 3, 5),
        (.downMirrored, 4, 4), (.rightMirrored, 5, 7), (.down, 6, 3), (.right, 7, 6),
    ]
    try #require(probed.count == Image.Orientation.allCases.count)
    for (orientation, raw, exif) in probed {
        #expect(orientation.rawValue == raw)
        #expect(orientation.exifValue == exif)
        #expect(Image.Orientation(exifValue: exif) == orientation)
    }
    #expect(Image.Orientation(exifValue: 0) == nil)
    #expect(Image.Orientation(exifValue: 9) == nil)
    #expect(Image.Orientation(exifValue: -1) == nil)
    #expect(Set(Image.Orientation.allCases.filter(\.swapsAxes)) == [.leftMirrored, .right, .rightMirrored, .left])
}
