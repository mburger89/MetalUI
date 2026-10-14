// Image orientation (ruling IB-E, record 113): SwiftUI's `Image.Orientation`
// with SwiftUI's own raw values (probe `docs/probes/swiftui-image-orientation.swift`),
// plus the sample permutation every orientation names. Portable: no Foundation.

extension Image {
    /// How a stored image is turned to be shown upright — SwiftUI's
    /// `Image.Orientation`: the eight EXIF transforms under
    /// `CGImagePropertyOrientation`'s names.
    ///
    /// **The raw values are SwiftUI's, not EXIF's** (`up` 0, `left` 1,
    /// `upMirrored` 2, `leftMirrored` 3, `downMirrored` 4, `rightMirrored` 5,
    /// `down` 6, `right` 7): never pass a `rawValue` where an EXIF number is
    /// wanted — use ``exifValue`` and ``init(exifValue:)``. A rotated
    /// orientation (``swapsAxes``) draws with its width and height exchanged.
    public enum Orientation: UInt8, CaseIterable, Hashable, Sendable {
        /// Stored as shown (EXIF 1).
        case up
        /// Rotated 90 degrees counter-clockwise to show upright (EXIF 8).
        case left
        /// Mirrored left to right (EXIF 2).
        case upMirrored
        /// Transposed: mirrored across the top-left to bottom-right diagonal (EXIF 5).
        case leftMirrored
        /// Mirrored top to bottom (EXIF 4).
        case downMirrored
        /// Mirrored across the top-right to bottom-left diagonal (EXIF 7).
        case rightMirrored
        /// Rotated 180 degrees (EXIF 3).
        case down
        /// Rotated 90 degrees clockwise to show upright (EXIF 6).
        case right

        /// The orientation for an EXIF orientation tag value `1…8`; any other
        /// value is `nil`. MetalUI-only.
        public init?(exifValue: Int) {
            switch exifValue {
            case 1: self = .up
            case 2: self = .upMirrored
            case 3: self = .down
            case 4: self = .downMirrored
            case 5: self = .leftMirrored
            case 6: self = .right
            case 7: self = .rightMirrored
            case 8: self = .left
            default: return nil
            }
        }

        /// The EXIF orientation tag value `1…8` of this orientation. MetalUI-only.
        public var exifValue: Int {
            switch self {
            case .up: 1
            case .upMirrored: 2
            case .down: 3
            case .downMirrored: 4
            case .leftMirrored: 5
            case .right: 6
            case .rightMirrored: 7
            case .left: 8
            }
        }

        /// Whether showing an image in this orientation exchanges its width
        /// and height (a 90-degree rotation or a diagonal mirror). MetalUI-only.
        public var swapsAxes: Bool {
            switch self {
            case .leftMirrored, .right, .rightMirrored, .left: true
            default: false
            }
        }
    }
}

/// Samples of `width × height` pixels (`bytesPerPixel` bytes each, row-major
/// from the top-left) turned by `orientation`; the result's size swaps for
/// ``Image/Orientation/swapsAxes``. A permutation only: no sample is changed,
/// so it commutes with premultiplication. Each output pixel `(x, y)` reads the
/// stored pixel the probe's 2x2 table names (record 113).
func permuteSamples(_ samples: [UInt8], width: Int, height: Int, bytesPerPixel: Int,
                    orientation: Image.Orientation) -> (width: Int, height: Int, samples: [UInt8]) {
    if orientation == .up { return (width, height, samples) }
    let outWidth = orientation.swapsAxes ? height : width
    let outHeight = orientation.swapsAxes ? width : height
    var out = [UInt8](repeating: 0, count: samples.count)
    for y in 0..<outHeight {
        for x in 0..<outWidth {
            let sx: Int, sy: Int
            switch orientation {
            case .up: (sx, sy) = (x, y)
            case .upMirrored: (sx, sy) = (width - 1 - x, y)
            case .down: (sx, sy) = (width - 1 - x, height - 1 - y)
            case .downMirrored: (sx, sy) = (x, height - 1 - y)
            case .leftMirrored: (sx, sy) = (y, x)
            case .right: (sx, sy) = (y, height - 1 - x)
            case .rightMirrored: (sx, sy) = (width - 1 - y, height - 1 - x)
            case .left: (sx, sy) = (width - 1 - y, x)
            }
            let from = (sy * width + sx) * bytesPerPixel
            let to = (y * outWidth + x) * bytesPerPixel
            for k in 0..<bytesPerPixel { out[to + k] = samples[from + k] }
        }
    }
    return (outWidth, outHeight, out)
}
