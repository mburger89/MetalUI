// How far does a layer's colour tag move a colour? (round 4 item R4-1 PR C, ruling `LS-A`)
//
// A gamma sRGB number written to a `bgra8Unorm` drawable is read by the
// compositor in whatever space the `CAMetalLayer` is tagged with. Until record
// 200 MetalUI tagged Display P3, so `#38BDF8` was displayed as the P3 colour
// with those numbers: more saturated than the sRGB colour SwiftUI draws from
// the same hex. This probe sizes the shift by converting the P3 reading to
// sRGB with CoreGraphics. It is arithmetic, not a window: the end-to-end arm is
// `appkit-layer-colourspace.swift`.
//
// Run: xcrun swiftc -O docs/probes/coregraphics-layer-colourspace.swift -o /tmp/cgls && /tmp/cgls
//
// Recorded output (macOS 27.2, 2026-11-03):
//   #38BDF8 read as P3 -> sRGB (extended): -0.2851 0.7539 0.9956   (8-bit: -73 192 254, clipped 0 192 254)
//   #FF0000 read as P3 -> sRGB (extended): 1.0931 -0.2268 -0.1501   (8-bit: 279 -58 -38, clipped 255 0 0)
//   #808080 read as P3 -> sRGB (extended): 0.5020 0.5020 0.5020   (8-bit: 128 128 128, clipped 128 128 128)
//   #1D4ED8 read as P3 -> sRGB (extended): -0.0272 0.3112 0.8797   (8-bit: -7 79 224, clipped 0 79 224)
// So on a P3 panel the old tag drew `#38BDF8` as the sRGB colour (-73, 192, 254)
// (red below the sRGB gamut, shown as the display's own most saturated blue-cyan),
// where SwiftUI draws (56, 189, 248); a neutral grey moved by 0 to 1 level.
// `#38BDF8` is the window probe's colour because its red channel separates the
// two tags even where the display is only sRGB; pure red would not.
import CoreGraphics
import Foundation

let p3 = CGColorSpace(name: CGColorSpace.displayP3)!
let srgb = CGColorSpace(name: CGColorSpace.extendedSRGB)!
for hex in [0x38BDF8, 0xFF0000, 0x808080, 0x1D4ED8] {
    let c = [CGFloat((hex >> 16) & 255) / 255, CGFloat((hex >> 8) & 255) / 255, CGFloat(hex & 255) / 255]
    let src = CGColor(colorSpace: p3, components: c + [1])!
    let out = src.converted(to: srgb, intent: .absoluteColorimetric, options: nil)!.components!
    let b = out.prefix(3).map { Int(($0 * 255).rounded()) }
    let clip = b.map { max(0, min(255, $0)) }
    print(String(format: "#%06X read as P3 -> sRGB (extended): %.4f %.4f %.4f   (8-bit: %d %d %d, clipped %d %d %d)",
                 hex, out[0], out[1], out[2], b[0], b[1], b[2], clip[0], clip[1], clip[2]))
}
