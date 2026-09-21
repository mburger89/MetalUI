// Helper for docs/probes/window-capture/capture.sh (2026-09-17); see its header.

import CoreGraphics
import ImageIO
import Foundation

let url = URL(fileURLWithPath: CommandLine.arguments[1]) as CFURL
let src = CGImageSourceCreateWithURL(url, nil)!
let img = CGImageSourceCreateImageAtIndex(src, 0, nil)!
let w = img.width, h = img.height
var buf = [UInt8](repeating: 0, count: w * h * 4)
let ctx = CGContext(data: &buf, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                    space: CGColorSpace(name: CGColorSpace.sRGB)!,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
var n = 0
for i in stride(from: 0, to: buf.count, by: 4) where buf[i] != 0 || buf[i + 1] != 0 || buf[i + 2] != 0 { n += 1 }
print("\(w)x\(h) nonBlack=\(n) of \(w * h)")
