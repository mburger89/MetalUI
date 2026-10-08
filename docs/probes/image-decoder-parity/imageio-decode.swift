import Foundation
import CoreGraphics
import ImageIO
let url = URL(fileURLWithPath: CommandLine.arguments[1]) as CFURL
guard let source = CGImageSourceCreateWithURL(url, nil), let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
      let space = CGColorSpace(name: CGColorSpace.sRGB) else { print("nil"); exit(0) }
let w = image.width, h = image.height
var px = [UInt8](repeating: 0, count: w*h*4)
px.withUnsafeMutableBytes { b in
  let ctx = CGContext(data: b.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w*4, space: space,
     bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue)!
  ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h)) }
print(w, h); print(px.map(String.init).joined(separator: " ") + " ")
