import AppKit
import SwiftUI
// Draws the file through SwiftUI (Image(nsImage:) rendered by ImageRenderer at
// scale 1) and prints its pixels as premultiplied sRGB RGBA8, in the format
// of the other two decoders.
MainActor.assumeIsolated {
    let path = CommandLine.arguments[1]
    guard let ns = NSImage(contentsOfFile: path), let rep = ns.representations.first else { print("nil"); exit(0) }
    let w = rep.pixelsWide, h = rep.pixelsHigh
    let renderer = ImageRenderer(content: Image(nsImage: ns).resizable().frame(width: CGFloat(w), height: CGFloat(h)))
    renderer.scale = 1
    guard let cg = renderer.cgImage else { print("nil"); exit(0) }
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    var px = [UInt8](repeating: 0, count: w * h * 4)
    px.withUnsafeMutableBytes { b in
        let ctx = CGContext(data: b.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: space,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue)!
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
    }
    print(w, h); print(px.map(String.init).joined(separator: " ") + " ")
    exit(0)
}
