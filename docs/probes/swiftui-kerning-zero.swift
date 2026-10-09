// SwiftUI/CoreText probe: is `Text.kerning(0)` "no extra space" or "no pair
// kerning"? CoreText reads a `kCTKernAttributeName` of 0 as "no kerning at all"
// (the pair kerning of the font is switched off); SwiftUI's `kerning(0)` and
// `tracking(0)` draw exactly the plain text. Evidence for ruling RT-O item 6 in
// docs/superpowers/2026-10-08-rich-text-decisions.md (the critic pass).
//
// HOW TO RUN, from the repository root:
//
//   xcrun swiftc docs/probes/swiftui-kerning-zero.swift -o /tmp/kern-probe && /tmp/kern-probe
//
// INSTRUMENT: widths — SwiftUI's `ImageRenderer` size of a fixed-size `Text`
// (points, rounded by SwiftUI to its layout grid) and CoreText's
// `CTLineGetTypographicBounds` for the same attributed string.
// POSITIVE CONTROL / SEPARATING ARM: Helvetica 30 "AVAVAV" has strong pair
// kerning, so "kerning off" is 11 points wider than plain (K2's kern-0 arm).
//
// RECORDED 2026-10-08 by the rich-text critic pass, macOS 27.0, compiled twice
// (output byte-identical):
//
//     K1 SwiftUI AVAVAV: plain 109.0 kerning(0) 109.0 tracking(0) 109.0 kerning(4) 133.0 tracking(4) 133.0
//     K2 CoreText AVAVAV: no attribute 108.9990234375 kern 0 120.05859375 kern 4 132.9990234375 tracking 0 108.9990234375 tracking 4 132.9990234375
//
// Reading: SwiftUI's kerning(0) ≡ plain (no pair kerning lost); CoreText's
// kern 0 is 11.06 points wider (pair kerning off); a non-zero kern keeps pair
// kerning on both (plain + 6 × 4 = 133). So a run whose kerning is 0 must not
// carry kCTKernAttributeName at all.
import SwiftUI
import AppKit
import CoreText

@MainActor func width(_ view: some View) -> CGFloat {
    ImageRenderer(content: view.fixedSize()).nsImage!.size.width
}
func ctWidth(_ string: String, kern: Double?, tracking: Double? = nil) -> Double {
    var attributes: [NSAttributedString.Key: Any] = [.font: CTFontCreateWithName("Helvetica" as CFString, 30, nil)]
    if let kern { attributes[NSAttributedString.Key(kCTKernAttributeName as String)] = kern }
    if let tracking { attributes[NSAttributedString.Key(kCTTrackingAttributeName as String)] = tracking }
    let line = CTLineCreateWithAttributedString(NSAttributedString(string: string, attributes: attributes))
    return CTLineGetTypographicBounds(line, nil, nil, nil)
}
@MainActor func main() {
    let font = Font.custom("Helvetica", size: 30)
    let s = "AVAVAV"
    print("K1 SwiftUI \(s): plain \(width(Text(s).font(font))) kerning(0) \(width(Text(s).font(font).kerning(0))) tracking(0) \(width(Text(s).font(font).tracking(0))) kerning(4) \(width(Text(s).font(font).kerning(4))) tracking(4) \(width(Text(s).font(font).tracking(4)))")
    print("K2 CoreText \(s): no attribute \(ctWidth(s, kern: nil)) kern 0 \(ctWidth(s, kern: 0)) kern 4 \(ctWidth(s, kern: 4)) tracking 0 \(ctWidth(s, kern: nil, tracking: 0)) tracking 4 \(ctWidth(s, kern: nil, tracking: 4))")
}
MainActor.assumeIsolated { main() }
