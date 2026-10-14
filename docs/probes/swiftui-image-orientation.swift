// SwiftUI probe: `Image.Orientation` and what `Image(decorative:scale:orientation:)`
// does with it, for MetalUI's image decode API (item S2, rulings IB-…).
//
// HOW TO RUN (compiled form, SA-O):
//   xcrun swiftc docs/probes/swiftui-image-orientation.swift -o /tmp/orientation-probe
//   /tmp/orientation-probe
//
// Arms. O0 (positive control): a 2x1 CGImage (left px red, right px blue) drawn
// `.up` through ImageRenderer at scale 1: the render reads red at x=0, blue at
// x=1, size 2x1 -- the instrument sees pixels. O1..O8: the eight orientations
// (rawValue order); each prints rendered size and the colour at each rendered
// pixel (R/B). A 2x1 image separates rotation (size 1x2) from mirroring (R/B
// swapped), and `.down` (R/B swapped, size 2x1) from `.upMirrored`
// (R/B swapped too -- told apart by the 2x2 arm O9: red/blue/green/white).
// O10: JPEG EXIF handling. A JPEG tagged orientation 6 decoded by
// CGImageSource: CGImage dimensions (EXIF ignored by CGImageSourceCreateImageAtIndex)
// against the thumbnail-with-transform route.
//
// RECORDED 2026-10-13 by the image-decode-api design session, macOS 27.0.1, Apple
// Swift 6.4, compiled form, run twice identical. Output (2x2 stored R B / G W,
// rendered row-major top-left; the render is colour-managed so colours are
// classified by dominant channel):
//   2x1 up rawValue=0: 2x1 RB          2x2 up: RBGW
//   2x1 upMirrored rawValue=2: BR      2x2 upMirrored: BRWG     (EXIF 2)
//   2x1 down rawValue=6: BR            2x2 down: WGBR           (EXIF 3)
//   2x1 downMirrored rawValue=4: RB    2x2 downMirrored: GWRB   (EXIF 4)
//   2x1 leftMirrored rawValue=3: 1x2 RB  2x2 leftMirrored: RGBW (EXIF 5)
//   2x1 right rawValue=7: 1x2 RB       2x2 right: GRWB          (EXIF 6)
//   2x1 rightMirrored rawValue=5: 1x2 BR 2x2 rightMirrored: WBGR (EXIF 7)
//   2x1 left rawValue=1: 1x2 BR        2x2 left: BWRG           (EXIF 8)
//   allCases count: 8
// So Image.Orientation is EXIF's eight transforms under CGImagePropertyOrientation's
// case names, with its OWN raw values (up 0, left 1, upMirrored 2, leftMirrored 3,
// downMirrored 4, rightMirrored 5, down 6, right 7), not EXIF's 1...8.
//   O10 exif orientation property: 6
//   O10 CGImageSource image: 4x2        (CGImage route: EXIF ignored)
//   O10 NSImage size: (2.0, 4.0)        (NSImage route: EXIF applied)
//   O10 Image(nsImage:) rendered: 2x4

import SwiftUI
import ImageIO
import AppKit

func cg(_ w: Int, _ h: Int, _ px: [UInt32]) -> CGImage {
    var data = px
    let ctx = CGContext(data: &data, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue)!
    return ctx.makeImage()!
}
let R = UInt32(bigEndian: 0xFF0000FF), B = UInt32(bigEndian: 0x0000FFFF), G = UInt32(bigEndian: 0x00FF00FF), W = UInt32(bigEndian: 0xFFFFFFFF)

@MainActor func render(_ image: CGImage, _ o: Image.Orientation) -> String {
    let r = ImageRenderer(content: Image(decorative: image, scale: 1, orientation: o))
    r.scale = 1
    guard let out = r.cgImage else { return "nil" }
    var d = [UInt8](repeating: 0, count: out.width * out.height * 4)
    let c = CGContext(data: &d, width: out.width, height: out.height, bitsPerComponent: 8,
        bytesPerRow: out.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue)!
    c.draw(out, in: CGRect(x: 0, y: 0, width: out.width, height: out.height))
    var s = "\(out.width)x\(out.height) "
    for i in 0..<(out.width * out.height) {
        let (r, g, b) = (d[i*4], d[i*4+1], d[i*4+2])
        s += r > 150 && g > 150 && b > 150 ? "W" : r >= g && r >= b ? "R" : b >= g ? "B" : "G"  // dominant channel: the render is colour-managed
    }
    return s
}

let all: [(String, Image.Orientation)] = [("up", .up), ("upMirrored", .upMirrored), ("down", .down),
    ("downMirrored", .downMirrored), ("leftMirrored", .leftMirrored), ("right", .right),
    ("rightMirrored", .rightMirrored), ("left", .left)]
MainActor.assumeIsolated {
    let two = cg(2, 1, [R, B])
    let four = cg(2, 2, [R, B, G, W])   // row-major from top-left: R B / G W
    for (n, o) in all { print("2x1 \(n) rawValue=\(o.rawValue): \(render(two, o))") }
    for (n, o) in all { print("2x2 \(n): \(render(four, o))") }
    print("allCases count: \(Image.Orientation.allCases.count)")
}

// O10: a 4x2 JPEG written with EXIF orientation 6 (ImageIO destination property).
// What does the stock decode route give: CGImageSource's CGImage size, NSImage
// size, and Image(nsImage:) rendered through ImageRenderer.
MainActor.assumeIsolated {
    let img = cg(4, 2, [UInt32](repeating: R, count: 8))
    let data = NSMutableData()
    let dest = CGImageDestinationCreateWithData(data, "public.jpeg" as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, img, [kCGImagePropertyOrientation: 6] as CFDictionary)
    CGImageDestinationFinalize(dest)
    let src = CGImageSourceCreateWithData(data, nil)!
    let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any]
    let decoded = CGImageSourceCreateImageAtIndex(src, 0, nil)!
    print("O10 exif orientation property: \(props?[kCGImagePropertyOrientation] ?? "nil")")
    print("O10 CGImageSource image: \(decoded.width)x\(decoded.height)")
    let ns = NSImage(data: data as Data)!
    print("O10 NSImage size: \(ns.size)")
    let r = ImageRenderer(content: Image(nsImage: ns)); r.scale = 1
    print("O10 Image(nsImage:) rendered: \(r.cgImage?.width ?? -1)x\(r.cgImage?.height ?? -1)")
}
