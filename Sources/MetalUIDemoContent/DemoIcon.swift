import MetalUI

/// The demo's application icon (ruling `AI-G`): six square bitmaps, 16, 32,
/// 64, 128, 256 and 512 px, in that order — a `#2F6FEB` rounded square (corner
/// radius `0.22 s`) with a white disc of radius `0.28 s` at its centre.
/// Generated, so the demo needs no asset file; deterministic, so every pixel is
/// pinned (test `theDemoIconsPixelsAreTheSpecifiedShape`). Built outside every
/// element tree: the offscreen demo images and the one-megabyte-thread guard
/// never see it.
public func demoIcon() -> [ImageBitmap] {
    [16, 32, 64, 128, 256, 512].map(demoIconBitmap)
}

/// One size of ``demoIcon()``. Each pixel is classified by its **centre**
/// `(x + 0.5, y + 0.5)`, top-left origin — binary coverage, no anti-aliasing
/// (spec §3): outside the rounded square `[0, s]²` clear, inside the disc
/// white, else the accent.
private func demoIconBitmap(_ side: Int) -> ImageBitmap {
    let s = Double(side)
    let corner = 0.22 * s
    let disc = 0.28 * s
    var rgba = [UInt8](repeating: 0, count: side * side * 4)
    for y in 0..<side {
        for x in 0..<side {
            let px = Double(x) + 0.5
            let py = Double(y) + 0.5
            // Distance from the centre to the square's inner rectangle
            // [corner, s − corner]²: within `corner` of it is inside the
            // rounded square.
            let dx = max(corner - px, 0, px - (s - corner))
            let dy = max(corner - py, 0, py - (s - corner))
            guard dx * dx + dy * dy <= corner * corner else { continue }
            let cx = px - s / 2
            let cy = py - s / 2
            let colour: (UInt8, UInt8, UInt8) = cx * cx + cy * cy <= disc * disc
                ? (255, 255, 255) : (47, 111, 235)
            let i = (y * side + x) * 4
            rgba[i] = colour.0
            rgba[i + 1] = colour.1
            rgba[i + 2] = colour.2
            rgba[i + 3] = 255
        }
    }
    return ImageBitmap(width: side, height: side, rgba: rgba)
}
