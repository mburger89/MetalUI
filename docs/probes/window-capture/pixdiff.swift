// Helper for docs/probes/window-capture/capture.sh (2026-09-17); see its header.

import CoreGraphics
import ImageIO
import Foundation
func load(_ p: String) -> (Int, Int, [UInt8]) {
    let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: p) as CFURL, nil)!
    let img = CGImageSourceCreateImageAtIndex(src, 0, nil)!
    let w = img.width, h = img.height
    var buf = [UInt8](repeating: 0, count: w * h * 4)
    let ctx = CGContext(data: &buf, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
    return (w, h, buf)
}
let a = load(CommandLine.arguments[1]), b = load(CommandLine.arguments[2])
guard a.0 == b.0 && a.1 == b.1 else { print("SIZE \(a.0)x\(a.1) vs \(b.0)x\(b.1)"); exit(0) }
var n = 0, minx = Int.max, miny = Int.max, maxx = -1, maxy = -1
for y in 0..<a.1 { for x in 0..<a.0 { let i = (y * a.0 + x) * 4
    if a.2[i] != b.2[i] || a.2[i+1] != b.2[i+1] || a.2[i+2] != b.2[i+2] || a.2[i+3] != b.2[i+3] { n += 1; minx = min(minx,x); miny = min(miny,y); maxx = max(maxx,x); maxy = max(maxy,y) } } }
print("\(a.0)x\(a.1) differing=\(n)" + (n > 0 ? " bbox=(\(minx),\(miny))-(\(maxx),\(maxy))" : ""))
