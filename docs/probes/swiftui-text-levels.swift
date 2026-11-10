// SwiftUI probe: the label colour levels (Alloy gap G21, ruling `CR-AD`, record 259).
//
// WHAT IT READS. `.secondary`, `.tertiary` and `.quaternary` as SwiftUI on macOS resolve them
// are `NSColor.secondaryLabelColor`, `tertiaryLabelColor` and `quaternaryLabelColor` (and
// `labelColor` for `.primary`). Each is read under `NSAppearance.aqua` and `.darkAqua` with
// `performAsCurrentDrawingAppearance`, converted to sRGB, and printed as RGB and alpha. Then the
// ratio of each level's alpha to the primary's, which is MetalUI's factor (divergence 116,
// `HierarchicalShapeStyle.Level.factor`). `placeholderTextColor` is printed as a control.
// Nothing is drawn and no window opens.
//
// HOW TO RUN (compiled form, SA-O):
//
//   xcrun swiftc docs/probes/swiftui-text-levels.swift -o /tmp/text-levels-probe
//   /tmp/text-levels-probe
//
// RECORDED OUTPUT (macOS 27.2, Swift 6.4.2, 2026-11-09):
//
//   LIGHT primary    rgb 0.0000 0.0000 0.0000 alpha 0.8471  ratio 1.0000
//   LIGHT secondary  rgb 0.0000 0.0000 0.0000 alpha 0.4980  ratio 0.5880
//   LIGHT tertiary   rgb 0.0000 0.0000 0.0000 alpha 0.2588  ratio 0.3056
//   LIGHT quaternary rgb 0.0000 0.0000 0.0000 alpha 0.0980  ratio 0.1157
//   LIGHT placeholder rgb 0.0000 0.0000 0.0000 alpha 0.4980 ratio 0.5880
//   DARK  primary    rgb 1.0000 1.0000 1.0000 alpha 0.8471  ratio 1.0000
//   DARK  secondary  rgb 1.0000 1.0000 1.0000 alpha 0.5490  ratio 0.6481
//   DARK  tertiary   rgb 1.0000 1.0000 1.0000 alpha 0.2471  ratio 0.2917
//   DARK  quaternary rgb 1.0000 1.0000 1.0000 alpha 0.0980  ratio 0.1157
//   DARK  placeholder rgb 1.0000 1.0000 1.0000 alpha 0.5490 ratio 0.6481
//
// VERDICT. MetalUI's factors (0.588/0.648, 0.306/0.292, 0.116) are these ratios, to the digit
// shown. They are a *ratio over an opaque theme text colour*, not SwiftUI's absolute alpha: the
// theme's `textPrimary` is opaque (SwiftUI's label is already 0.8471), so MetalUI's secondary is
// at alpha 0.588/0.648 where SwiftUI's is 0.498/0.549. The same visual weight relative to the
// primary, a higher absolute alpha, and so more contrast than SwiftUI. Nothing to align; a
// palette that wants a different level sets `Theme.textSecondary`/`textTertiary` (`CR-AD`).
import AppKit

func read(_ name: String, _ color: NSColor, _ appearance: NSAppearance, primary: inout CGFloat?) {
    appearance.performAsCurrentDrawingAppearance {
        guard let c = color.usingColorSpace(.sRGB) else { print("\(name) no sRGB"); return }
        if primary == nil { primary = c.alphaComponent }
        let ratio = c.alphaComponent / (primary ?? 1)
        print(String(format: "%@ rgb %.4f %.4f %.4f alpha %.4f  ratio %.4f", name,
                     c.redComponent, c.greenComponent, c.blueComponent, c.alphaComponent, ratio))
    }
}

for (label, appearance) in [("LIGHT", NSAppearance(named: .aqua)!), ("DARK ", NSAppearance(named: .darkAqua)!)] {
    var primary: CGFloat?
    read("\(label) primary   ", .labelColor, appearance, primary: &primary)
    read("\(label) secondary ", .secondaryLabelColor, appearance, primary: &primary)
    read("\(label) tertiary  ", .tertiaryLabelColor, appearance, primary: &primary)
    read("\(label) quaternary", .quaternaryLabelColor, appearance, primary: &primary)
    read("\(label) placeholder", .placeholderTextColor, appearance, primary: &primary)
}
