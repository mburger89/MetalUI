import Foundation
import MetalUIScene

// Downscaled decode (ruling `PX-W`): `ImageBitmap(data:maxPixelSize:)` decodes as `init(data:)`
// does, then shrinks with an area-average resample, so the bitmap keeps only the small texture.

/// The size a `width × height` image is shrunk to for `maxPixelSize`, or `nil` when its longest
/// side already fits (never upscaled). The longest side becomes exactly `maxPixelSize`; the
/// other is `max(1, round(other × maxPixelSize / longest))`; a square gives a square (`PX-W`
/// item 2).
func downscaledSize(width: Int, height: Int, maxPixelSize: Int) -> (width: Int, height: Int)? {
    let longest = max(width, height)
    guard longest > maxPixelSize else { return nil }
    func scaled(_ side: Int) -> Int {
        side == longest ? maxPixelSize
            : max(1, Int((Double(side) * Double(maxPixelSize) / Double(longest)).rounded()))
    }
    return (scaled(width), scaled(height))
}

/// The texture for `bytes` decoded no larger than `maxPixelSize` on its longest side (`PX-W`).
///
/// PNG and JPEG go through ``decodeImage(_:channels:expecting:)`` (stb, so the bytes are the same on
/// every platform, `PX-C`) and are resampled from the straight samples, premultiplying as they
/// are read; other formats decode as ``decodeImageTexture(_:)`` does and are resampled from the
/// texture's premultiplied pixels. An image that already fits is exactly what
/// ``decodeImageTexture(_:)`` returns. The full-size buffer is local and gone on return;
/// the peak, though, includes it. Pure and stateless: callable from any thread.
func decodeImageTexture(_ bytes: UnsafeRawBufferPointer, maxPixelSize: Int) -> ImageTexture? {
    if isPNG(bytes) || isJPEG(bytes) {
        guard let image = decodeImage(bytes) else { return nil }
        guard let target = downscaledSize(width: image.width, height: image.height,
                                          maxPixelSize: maxPixelSize) else {
            return ImageTexture(width: image.width, height: image.height, straightRGBA: image.samples)
        }
        let pixels = image.samples.withUnsafeBufferPointer {
            areaAveraged($0, width: image.width, height: image.height, straight: true,
                         toWidth: target.width, height: target.height)
        }
        return ImageTexture(width: target.width, height: target.height, premultipliedRGBA: pixels)
    }
    #if canImport(ImageIO)
    guard let texture = decodeThroughImageIO(bytes) else { return nil }
    guard let target = downscaledSize(width: texture.width, height: texture.height,
                                      maxPixelSize: maxPixelSize) else { return texture }
    let pixels = texture.pixels.withUnsafeBufferPointer {
        areaAveraged($0, width: texture.width, height: texture.height, straight: false,
                     toWidth: target.width, height: target.height)
    }
    return ImageTexture(width: target.width, height: target.height, premultipliedRGBA: pixels)
    #else
    return nil
    #endif
}

/// RGBA8 `source` (`width × height`) shrunk to `toWidth × toHeight` by an area average: each
/// output texel is the mean of the source area it covers, source texels weighted by the
/// fraction of them inside it, on both axes. The mean is taken over **premultiplied** channels,
/// so a transparent texel's colour never leaks in. `straight` sources are premultiplied as they
/// are read, with `ImageTexture(width:height:straightRGBA:)`'s rule (`(c × a + 127) / 255`),
/// so no second full-size buffer exists. Result is premultiplied, rounded to nearest.
///
/// Memory is one source row of `Double`s plus the output; pure, no shared state.
func areaAveraged(_ source: UnsafeBufferPointer<UInt8>, width: Int, height: Int, straight: Bool,
                  toWidth outWidth: Int, height outHeight: Int) -> [UInt8] {
    let scaleX = Double(width) / Double(outWidth)
    let scaleY = Double(height) / Double(outHeight)
    let norm = 1 / (scaleX * scaleY)
    var out = [UInt8](repeating: 0, count: outWidth * outHeight * 4)
    var row = [Double](repeating: 0, count: width * 4)
    for oy in 0..<outHeight {
        for i in row.indices { row[i] = 0 }
        let y0 = Double(oy) * scaleY
        let y1 = min(Double(height), Double(oy + 1) * scaleY)
        var sy = Int(y0)
        while sy < height, Double(sy) < y1 {
            let wy = min(Double(sy + 1), y1) - max(Double(sy), y0)
            if wy > 0 {
                let base = sy * width * 4
                for x in 0..<width {
                    let p = base + x * 4
                    let a = UInt32(source[p + 3])
                    for c in 0..<3 {
                        let v = straight ? (UInt32(source[p + c]) * a + 127) / 255 : UInt32(source[p + c])
                        row[x * 4 + c] += Double(v) * wy
                    }
                    row[x * 4 + 3] += Double(a) * wy
                }
            }
            sy += 1
        }
        for ox in 0..<outWidth {
            let x0 = Double(ox) * scaleX
            let x1 = min(Double(width), Double(ox + 1) * scaleX)
            var sum = (0.0, 0.0, 0.0, 0.0)
            var sx = Int(x0)
            while sx < width, Double(sx) < x1 {
                let wx = min(Double(sx + 1), x1) - max(Double(sx), x0)
                if wx > 0 {
                    sum.0 += row[sx * 4] * wx
                    sum.1 += row[sx * 4 + 1] * wx
                    sum.2 += row[sx * 4 + 2] * wx
                    sum.3 += row[sx * 4 + 3] * wx
                }
                sx += 1
            }
            let o = (oy * outWidth + ox) * 4
            out[o] = UInt8(min(255, (sum.0 * norm + 0.5).rounded(.down)))
            out[o + 1] = UInt8(min(255, (sum.1 * norm + 0.5).rounded(.down)))
            out[o + 2] = UInt8(min(255, (sum.2 * norm + 0.5).rounded(.down)))
            out[o + 3] = UInt8(min(255, (sum.3 * norm + 0.5).rounded(.down)))
        }
    }
    return out
}
