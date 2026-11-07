// SwiftUI probe: `Image(systemName:)` — sizes, baselines, tint, variants, missing names, accessibility,
// pixel placement, and whether AppKit can hand out vector outlines. Evidence for rulings SYM-A…SYM-H in
// docs/superpowers/2026-11-07-symbol-images-decisions.md (record 230).
//
// HOW TO RUN, from the repository root:
//
//   DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swiftc docs/probes/swiftui-symbol-images.swift -o /tmp/sym-probe
//   /tmp/sym-probe 2>/dev/null
//
// INSTRUMENT: `ImageRenderer` at scale 2 on white, drawn into an sRGB RGBA context; `px` counts pixels whose
// channel difference sums above 3, `max` is the largest single-channel difference. Sizes come from
// `NSHostingView.fittingSize`, baselines from a custom `Layout` reading `dimensions[.firstTextBaseline]`.
// POSITIVE CONTROL: S0 (`star` against itself 0 px; against `star.fill` many).
//
// RECORDED 2026-11-07 by the G3 PR 0 session, macOS 27.2 (26B123), Apple Swift 6.4.2, compiled with
// `xcrun swiftc` (no warnings that matter), run twice with stderr discarded, exit 0, stdout byte-identical
// (`cmp` clean, 85 lines). No window was ordered front (S8 reads an `NSHostingView` inside a never-shown
// `NSWindow` after `AXEnhancedUserInterface`); nothing here needs an unlocked session. Verbatim:
//
//     S0 star vs star: 0 px; star vs star.fill: 215 px
//     S1 names present on macOS Version 27.2 (Build 26B123): star=yes magnifyingglass=yes doc=yes doc.text=yes pencil=yes square.and.pencil=yes doc.badge.plus=yes terminal=yes apple.terminal=yes brain=yes brain.head.profile=yes sparkles=yes globe=yes person=yes person.crop.circle=yes exclamationmark.triangle=yes xmark=yes xmark.circle=yes play=yes play.fill=yes stop=yes stop.fill=yes stop.circle=yes checkmark=yes chevron.right=yes chevron.down=yes doc.on.doc=yes arrow.uturn.backward=yes arrow.up.right.square=yes rectangle.split.2x1=yes cpu=yes cpu.fill=yes desktopcomputer=yes robot=NO robot.fill=NO brain.filled.head.profile=yes gearshape.2=yes wand.and.stars=yes bolt.horizontal=yes ant=yes
//     S1 max |SwiftUI fittingSize - NSImage(config).size| per name (names over 0.01 only): square.and.pencil=1 doc.badge.plus=9; overall max 9; names checked 38
//     S1 refined model H1' (width = NSImage.alignmentRect.width, height = NSImage.size.height): names over 0.01: none; overall max 0
//     S1 doc.badge.plus@13 medium regular: SwiftUI 15x18; NSImage.size 17x18; alignmentRect (2.0, 5.0, 15.0, 9.0)
//     S1 square.and.pencil@13 medium regular: SwiftUI 16x16; NSImage.size 16x16; alignmentRect (0.0, 2.0, 16.0, 9.0)
//     S1 literals: star@13 medium regular = 17x16; star@13 large regular = 23x20; star@13 small bold = 14x14; star@26 medium regular = 33x32; magnifyingglass@13 medium bold = 15x15; arrow.up.right.square@13 medium bold = 17x15; doc.text@13 large regular = 18x20; xmark.circle@48 medium regular = 56x56; brain@13 medium regular = 19x17
//     S1 star regular medium @9: 12x12
//     S1 star regular medium @13: 17x16
//     S1 star regular medium @26: 33x32
//     S1 star regular medium @48: 62x59
//     S2 baselines: firstTextBaseline / lastTextBaseline from the top, size; H2 = size.height - alignmentRect.minY (NSImage.alignmentRect, origin bottom-left); H3 = side/2 + capHeight/2
//     S2 star@13 medium regular: first 13 last 13 size 17x16 | H2 13 (alignmentRect (0.0, 3.0, 17.0, 9.0)) | H3 12.58 cap 9.16
//     S2 star@26 medium regular: first 27 last 27 size 33x32 | H2 27 (alignmentRect (0.0, 5.0, 33.0, 18.0)) | H3 25.16 cap 18.32
//     S2 star@48 medium regular: first 49 last 49 size 62x59 | H2 49 (alignmentRect (0.0, 10.0, 62.0, 34.0)) | H3 46.41 cap 33.82
//     S2 magnifyingglass@13 medium regular: first 12 last 12 size 15x15 | H2 12 (alignmentRect (0.0, 3.0, 15.0, 9.0)) | H3 12.08 cap 9.16
//     S2 doc@13 medium regular: first 13 last 13 size 15x16 | H2 13 (alignmentRect (0.0, 3.0, 15.0, 9.0)) | H3 12.58 cap 9.16
//     S2 doc.text@13 large regular: first 15 last 15 size 18x20 | H2 15 (alignmentRect (0.0, 5.0, 18.0, 9.0)) | H3 14.58 cap 9.16
//     S2 xmark@13 small bold: first 10 last 10 size 11x11 | H2 10 (alignmentRect (0.0, 1.0, 11.0, 9.0)) | H3 10.08 cap 9.16
//     S2 chevron.right@17 medium regular: first 15 last 15 size 13x17 | H2 15 (alignmentRect (0.0, 2.0, 13.0, 12.0)) | H3 14.49 cap 11.98
//     S2 globe@26 medium regular: first 24 last 24 size 30x30 | H2 24 (alignmentRect (0.0, 6.0, 30.0, 18.0)) | H3 24.16 cap 18.32
//     S2 star@13 small regular: first 12 last 12 size 14x13 | H2 12 (alignmentRect (0.0, 1.0, 14.0, 9.0)) | H3 11.08 cap 9.16
//     S2 star@13 large regular: first 16 last 16 size 23x20 | H2 16 (alignmentRect (0.0, 4.0, 23.0, 9.0)) | H3 14.58 cap 9.16
//     S2 HStack(.firstTextBaseline) star|Hxg @13: stack size 41x16 first 13; text alone size 24x16 first 13; star alone height 16
//     S3 font routes (star): no font = 17x16; .body = 17x16; .system(size: 13) = 17x16; .title = 29x27; .fontWeight(.bold) = 17x17; .bold() = 17x17; .font(.body).fontWeight(.bold) = 17x17; default imageScale medium vs .medium px = 17x16
//     S3 default imageScale == .medium: 0 px; vs .small: 1374 px
//     S3 .bold() == .fontWeight(.bold): 0 px; bold vs regular: 306 px
//     S3 Text .body size for reference: 10x16
//     S4 square.fill .foregroundStyle(red) centre pixel: (255, 0, 0) (expect 255,0,0 if exact)
//     S4 default (no foregroundStyle) centre pixel: (39, 39, 39); labelColor over white (light): (39, 39, 39); is the render's appearance light? NSAppearanceNameDarkAqua
//     S4 .tint(.red) vs default: 0 px
//     S4 .foregroundColor(red) vs .foregroundStyle(red): 0 px
//     S4 hierarchical black square.on.square: top grey buckets (255=white): 0..:1137 128..:814 216..:86 88..:82
//     S4 hierarchical black doc.on.doc: top grey buckets (255=white): 0..:1509 128..:921 192..:76 184..:69
//     S4 hierarchical black speaker.wave.2: top grey buckets (255=white): 0..:905 128..:470 176..:74 56..:59
//     S4 hierarchical black wifi: top grey buckets (255=white): 0..:1839 8..:26 224..:23 240..:22
//     S4 hierarchical black cloud.sun: top grey buckets (255=white): 0..:1020 128..:686 160..:81 16..:53
//     S4 hierarchical black person.2: top grey buckets (255=white): 0..:1196 128..:814 168..:77 192..:59
//     S4 multicolor ignores foreground (sun.max.fill red vs none): 0 px; multicolor vs monochrome: 2229 px
//     S4 monochrome explicit == default: 0 px
//     S5 star + .fill vs star.fill: 0 px (vs star alone 215 px)
//     S5 xmark + .circle.fill vs xmark.circle.fill: 0 px (vs xmark 537 px)
//     S5 xmark + .fill.circle vs xmark.circle.fill: 0 px
//     S5 chevron.right.fill exists? false; chevron.right + .fill vs chevron.right: 0 px (falls back to base if 0)
//     S5 environment symbolVariants form: star via .environment(\.symbolVariants, .fill) vs star.fill: 0 px
//     S5 an explicit .fill name under .symbolVariant(.none): 0 px (0 = the name is kept; .none removes nothing)
//     S5 star.fill under .symbolVariant(.slash): matches star.slash.fill? true 153 px; star.slash? true 269 px
//     S5 star.fill + .slash vs star.fill: 0 px; star + .slash vs star.slash: 0 px; star + .fill.slash vs star.slash.fill: 0 px
//     S5 xmark.circle + .fill vs xmark.circle.fill: 0 px (an explicit shape in the name plus a fill variant)
//     S5 order (bell): circle.fill->bell.circle.fill; fill.circle->bell.circle.fill; slash.fill->bell.slash.fill; fill.slash->bell.slash.fill; circle.slash->bell.slash.circle; slash.circle->bell.slash.circle; circle.slash.fill->bell.slash.circle.fill; fill.slash.circle->bell.slash.circle.fill; square.fill->bell.square.fill; rectangle.fill->base.fill
//     S5 order (plus): circle.fill->plus.circle.fill; fill.circle->plus.circle.fill; slash.fill->base; fill.slash->base; circle.slash->other; slash.circle->other; circle.slash.fill->other; fill.slash.circle->other; square.fill->plus.square.fill; rectangle.fill->plus.rectangle.fill
//     S5 order (mic): circle.fill->mic.circle.fill; fill.circle->mic.circle.fill; slash.fill->mic.slash.fill; fill.slash->mic.slash.fill; circle.slash->mic.slash.circle; slash.circle->mic.slash.circle; circle.slash.fill->mic.slash.circle.fill; fill.slash.circle->mic.slash.circle.fill; square.fill->mic.square.fill; rectangle.fill->base.fill
//     S6 missing name: size 0x0 (font 26: 0x0); render empty: true; baselines first 0 last 0 size 0x0; .frame(30,30): 30x30; resizable framed: 30x30
//     S6 stderr text (0 chars): (none)
//     S6 an empty-string name: size 0x0
//     S7 star ink bbox in a 40x40 frame: resizable [0,0..39.5,38.5]; resizable+scaledToFit [0,0.5..39.5,38]; scaledToFill+clipped [0,0..40,38.5]; font 40 (not resizable) [0,0..40,40]
//     S7 resizable star ideal (nil proposal) size: 15x14; in a 40x20 frame: 40x20; ink in 40x20: [0,0..39.5,19.5]
//     S7 resizable star under a 100x100 proposal as an overlay-free child: ideal ratio fit: 100x100
//     S8 control: Text("hello") tree [AXGroup:nil >AXStaticText:nil]; Image(decorative: nil) n/a
//     S8 star: [AXGroup:nil >AXImage:'Favorite']; NSImage.accessibilityDescription (nil in) = 'favorite'; ("X" in) = 'X'
//     S8 star hidden: [AXGroup:nil]; accessibilityLabel("Custom"): [AXGroup:nil >AXImage:'Custom']; inside Button(action:){Image}: [AXGroup:nil >AXButton:'Favorite']
//     S8 magnifyingglass: [AXGroup:nil >AXImage:'Search']; NSImage.accessibilityDescription (nil in) = 'Search'; ("X" in) = 'X'
//     S8 magnifyingglass hidden: [AXGroup:nil]; accessibilityLabel("Custom"): [AXGroup:nil >AXImage:'Custom']; inside Button(action:){Image}: [AXGroup:nil >AXButton:'Search']
//     S8 doc: [AXGroup:nil >AXImage:'Document']; NSImage.accessibilityDescription (nil in) = 'Document page'; ("X" in) = 'X'
//     S8 doc hidden: [AXGroup:nil]; accessibilityLabel("Custom"): [AXGroup:nil >AXImage:'Custom']; inside Button(action:){Image}: [AXGroup:nil >AXButton:'Document']
//     S9 star@13: origin 0: 315 px of 4800 (6.56%), max 217; origin 0.25: 377 px of 4800 (7.85%), max 145; origin 0.5: 315 px of 4800 (6.56%), max 217; separating (route@4 vs SwiftUI@4.5): 313 px, max 238; SwiftUI@4.25 vs SwiftUI@4: 348 px (0 = SwiftUI snaps the quarter point)
//     S9 magnifyingglass@13: origin 0: 264 px of 4800 (5.5%), max 255; origin 0.25: 325 px of 4800 (6.77%), max 255; origin 0.5: 264 px of 4800 (5.5%), max 255; separating (route@4 vs SwiftUI@4.5): 284 px, max 255; SwiftUI@4.25 vs SwiftUI@4: 231 px (0 = SwiftUI snaps the quarter point)
//     S9 doc.text@26: origin 0: 411 px of 4800 (8.56%), max 255; origin 0.25: 764 px of 4800 (15.92%), max 199; origin 0.5: 408 px of 4800 (8.5%), max 255; separating (route@4 vs SwiftUI@4.5): 617 px, max 255; SwiftUI@4.25 vs SwiftUI@4: 663 px (0 = SwiftUI snaps the quarter point)
//     S9b star@13: at the same origin 315 px (max 217) of 12000 (2.63%); best offset (dx 0, dy -0.5) 214 px (max 65) = 1.78%
//     S9b magnifyingglass@13: at the same origin 264 px (max 255) of 12000 (2.2%); best offset (dx 0.5, dy -0.5) 192 px (max 239) = 1.6%
//     S9b doc.text@26: at the same origin 512 px (max 255) of 12000 (4.27%); best offset (dx 0, dy -0.5) 489 px (max 255) = 4.08%
//     S9b xmark@17: at the same origin 220 px (max 219) of 12000 (1.83%); best offset (dx 0, dy -0.5) 218 px (max 255) = 1.82%
//     S9b chevron.right@13: at the same origin 145 px (max 255) of 12000 (1.21%); best offset (dx 0, dy -1) 76 px (max 26) = 0.63%
//     S9b globe@26: at the same origin 1251 px (max 255) of 12000 (10.43%); best offset (dx 0.5, dy 0.5) 1009 px (max 254) = 8.41%
//     S9b doc.badge.plus@13: at the same origin 581 px (max 255) of 12000 (4.84%); best offset (dx -1, dy 0) 517 px (max 255) = 4.31%
//     S10 symbol star@13 into a PDF context (Form XObjects descended): Do:Form=2 Do:Image=1 f=1; coordinates seen 0
//     S10 symbol magnifyingglass@13 into a PDF context (Form XObjects descended): Do:Form=2 Do:Image=1 f=1; coordinates seen 0
//     S10 symbol doc.text@13 into a PDF context (Form XObjects descended): Do:Form=2 Do:Image=1 f=1; coordinates seen 0
//     S10 separating (bitmap NSImage): Do:Form=1 Do:Image=1 (expect Do:Image, no m/l/c)
//     S10 separating (a CGContext path fill): f=1 l=2 m=1 (expect m/l/f, no Do)
//     S10 star outlines 13 vs 26 pt: coordinate counts 0 vs 0 (not comparable)
//     S11 Label("Read", systemImage: "doc") size 54x17; image alone 15x16; text alone 31x16; horizontal gap = 8
//     S11 baselines: label first 13 last 13.08; image first 13; text first 13 last 13
//     S11 HStack(.firstTextBaseline, spacing 4) equivalent size 50x16
//     S11 label ink bbox: [3.5,3..53.5,17]
//
// READINGS (what each arm decides; the stop conditions are the plan's):
//   S0  separating: star vs star 0 px, star vs star.fill 215 px.
//   S1  H1 REFUTED as written for 2 of 38 names (stop condition: more than 0.5 pt on more than one symbol):
//       `doc.badge.plus` (up to 9 pt wide) and `square.and.pencil` (up to 1 pt). The refinement H1' holds for
//       all 38 names x 6 sizes x 3 scales x 2 weights (max difference 0): SwiftUI's size is
//       (`NSImage.alignmentRect.width`, `NSImage.size.height`). For every other name the alignment rect starts
//       at x = 0 and spans the image, which is why H1 looked true. A symbol whose alignment rect is narrower
//       than its image (badges) is laid out at the narrower width.
//   S2  H2 HOLDS in all 14 rows: first = last = `size.height - alignmentRect.minY` (H3, the cap-centre model, is off by up to 2.8 pt).
//       A symbol's last baseline equals its first. In `HStack(.firstTextBaseline)` it sits on the text's baseline.
//   S3  no font = `.body` = `.system(size: 13)` (13 pt); default `imageScale` is `.medium` (0 px); `.bold()` = `.fontWeight(.bold)` (0 px).
//   S4  `.foregroundStyle(red)` centre is exactly (255, 0, 0); the default is `labelColor` (39, 39, 39 over white, light);
//       `.tint` changes nothing (0 px); hierarchical secondary layers are at coverage 0.5 (grey bucket 128 beside 0);
//       multicolor ignores the foreground (0 px) and differs from monochrome. The `ImageRenderer` appearance reads light.
//   S5  `star` + `.fill` = `star.fill` (0 px); `.circle.fill` and `.fill.circle` both give `xmark.circle.fill`; a variant with no such
//       name falls back to the base (or to the base's `.fill` when only the fill exists); chained order of the
//       *name* is slash, then circle/square/rectangle, then fill (`bell.slash.circle.fill`); an explicit name is kept.
//   S6  a missing name is a 0 x 0 leaf with an empty render and NO stderr diagnostic.
//   S7  resizable fills the proposal; `scaledToFit` of the 15 x 14 ideal box fills 40 x 40.
//   S8  an `.image` node labelled with a SwiftUI-own title-cased name ('Favorite', 'Search', 'Document') that is NOT
//       `NSImage.accessibilityDescription` ('favorite', 'Search', 'Document page'); `accessibilityLabel("Custom")`
//       overrides, `accessibilityHidden(true)` records nothing, inside a `Button` the button takes the same label.
//   S9  STOP CONDITION TRIGGERED: the AppKit raster route (NSImage with the symbol configuration drawn into a
//       2x bitmap, coverage = alpha) differs from `ImageRenderer` by 5.5% to 8.6% of a 40 x 30 pt canvas at an
//       integer origin (264 to 411 px, max channel 217 to 255), 1.2% to 10% of a 60 x 50 canvas in S9b. The
//       shapes agree; the placement does not: the route sits about one device pixel lower, and no constant
//       offset in +-1 pt closes the gap (best 0.6% to 8.4%, still hundreds of px). SwiftUI itself does NOT snap
//       the quarter point (S9, last column: 231 to 663 px). So the symbol is not drawn from the integer-size NSImage.
//   S10 AppKit symbol images are NOT vector in a PDF context: `Do:Form` x2, `Do:Image` x1, one `f`, zero m/l/c
//       (the bitmap control gives the same Form/Image pair; the CGContext path control gives m/l/f). There is no
//       outline to extract this way; the vector route is carried.
//   S11 `Label("Read", systemImage: "doc")` is 54 x 17: the icon gap is 8 (not an HStack(spacing: 4)); first baseline 13.
import SwiftUI
import AppKit
import CoreGraphics

// MARK: instrument

struct Raster {
    var w: Int, h: Int
    var data: [UInt8]   // RGBA, 8 bit, sRGB, row 0 at the top
    func rgb(_ x: Int, _ y: Int) -> (Int, Int, Int) {
        let i = (y * w + x) * 4
        return (Int(data[i]), Int(data[i + 1]), Int(data[i + 2]))
    }
}

@MainActor func raster(_ view: some View, _ w: Int, _ h: Int) -> Raster {
    let r = ImageRenderer(content: view.frame(width: CGFloat(w), height: CGFloat(h), alignment: .topLeading)
        .background(Color.white))
    r.scale = 2
    return rasterize(r.cgImage!)
}

func rasterize(_ cg: CGImage) -> Raster {
    let w = cg.width, h = cg.height
    var data = [UInt8](repeating: 255, count: w * h * 4)
    let cs = CGColorSpace(name: CGColorSpace.sRGB)!
    data.withUnsafeMutableBytes { p in
        let ctx = CGContext(data: p.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                            space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
    }
    return Raster(w: w, h: h, data: data)
}

func diff(_ a: Raster, _ b: Raster) -> (px: Int, max: Int, total: Int) {
    var n = 0, m = 0
    for y in 0..<min(a.h, b.h) {
        for x in 0..<min(a.w, b.w) {
            let p = a.rgb(x, y), q = b.rgb(x, y)
            let d = [abs(p.0 - q.0), abs(p.1 - q.1), abs(p.2 - q.2)]
            if d.reduce(0, +) > 3 { n += 1 }
            m = max(m, d.max()!)
        }
    }
    return (n, m, min(a.w, b.w) * min(a.h, b.h))
}

@MainActor func px(_ a: some View, _ b: some View, _ w: Int = 60, _ h: Int = 40) -> Int {
    diff(raster(a, w, h), raster(b, w, h)).px
}

/// Ink bounding box in points (scale 2): (minX, minY, maxX, maxY) of non-white pixels, nil when empty.
func ink(_ r: Raster) -> (Double, Double, Double, Double)? {
    var x0 = Int.max, y0 = Int.max, x1 = -1, y1 = -1
    for y in 0..<r.h { for x in 0..<r.w {
        let p = r.rgb(x, y)
        if p.0 < 250 || p.1 < 250 || p.2 < 250 { x0 = min(x0, x); y0 = min(y0, y); x1 = max(x1, x); y1 = max(y1, y) }
    } }
    return x1 < 0 ? nil : (Double(x0) / 2, Double(y0) / 2, Double(x1 + 1) / 2, Double(y1 + 1) / 2)
}

@MainActor func fit(_ view: some View) -> CGSize { NSHostingView(rootView: view).fittingSize }

func g(_ v: Double) -> String {
    let r = (v * 100).rounded() / 100
    return r == r.rounded() ? String(Int(r)) : String(r)
}
func g(_ s: CGSize) -> String { "\(g(Double(s.width)))x\(g(Double(s.height)))" }

final class Box: @unchecked Sendable { var first = Double.nan, last = Double.nan, size = CGSize.zero }
struct BaselineProbe: Layout {
    let box: Box
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let d = subviews[0].dimensions(in: .unspecified)
        box.first = Double(d[.firstTextBaseline]); box.last = Double(d[.lastTextBaseline])
        box.size = CGSize(width: d.width, height: d.height)
        return box.size
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews[0].place(at: bounds.origin, proposal: .unspecified)
    }
}
@MainActor func baselines(_ view: some View) -> (first: Double, last: Double, size: CGSize) {
    let b = Box()
    _ = NSHostingView(rootView: BaselineProbe(box: b) { view }).fittingSize
    return (b.first, b.last, b.size)
}

func exists(_ n: String) -> Bool { NSImage(systemSymbolName: n, accessibilityDescription: nil) != nil }
func nsConfig(size: Double, weight: NSFont.Weight, scale: NSImage.SymbolScale) -> NSImage.SymbolConfiguration {
    NSImage.SymbolConfiguration(pointSize: size, weight: weight, scale: scale)
}
func nsImage(_ n: String, _ size: Double, _ weight: NSFont.Weight, _ scale: NSImage.SymbolScale) -> NSImage? {
    NSImage(systemSymbolName: n, accessibilityDescription: nil)?.withSymbolConfiguration(nsConfig(size: size, weight: weight, scale: scale))
}

let alloy = ["star", "magnifyingglass", "doc", "doc.text", "pencil", "square.and.pencil", "doc.badge.plus", "terminal",
             "apple.terminal", "brain", "brain.head.profile", "sparkles", "globe", "person", "person.crop.circle",
             "exclamationmark.triangle", "xmark", "xmark.circle", "play", "play.fill", "stop", "stop.fill", "stop.circle",
             "checkmark", "chevron.right", "chevron.down", "doc.on.doc", "arrow.uturn.backward", "arrow.up.right.square",
             "rectangle.split.2x1"]
let robotCandidates = ["cpu", "cpu.fill", "desktopcomputer", "robot", "robot.fill", "brain.filled.head.profile",
                       "gearshape.2", "wand.and.stars", "bolt.horizontal", "ant"]

let sizes: [Double] = [9, 11, 13, 17, 26, 48]
let scalePairs: [(String, Image.Scale, NSImage.SymbolScale)] = [("small", .small, .small), ("medium", .medium, .medium), ("large", .large, .large)]
let weightPairs: [(String, Font.Weight, NSFont.Weight)] = [("regular", .regular, .regular), ("bold", .bold, .bold)]

// MARK: arms

@MainActor func s0() {
    print("S0 star vs star: \(px(Image(systemName: "star"), Image(systemName: "star"))) px; star vs star.fill: \(px(Image(systemName: "star"), Image(systemName: "star.fill"))) px")
}

@MainActor func s1() {
    print("S1 names present on macOS \(ProcessInfo.processInfo.operatingSystemVersionString): "
          + (alloy + robotCandidates).map { "\($0)=\(exists($0) ? "yes" : "NO")" }.joined(separator: " "))
    var worst: [(String, Double)] = [], worstAlign: [(String, Double)] = []
    var samples: [String] = []
    for name in alloy + robotCandidates where exists(name) {
        var maxDiff = 0.0, maxDiffAlign = 0.0
        for size in sizes { for (_, sScale, nScale) in scalePairs { for (_, sw, nw) in weightPairs {
            let sw1 = fit(Image(systemName: name).font(.system(size: CGFloat(size), weight: sw)).imageScale(sScale))
            guard let ns = nsImage(name, size, nw, nScale) else { continue }
            maxDiff = max(maxDiff, abs(Double(sw1.width) - Double(ns.size.width)), abs(Double(sw1.height) - Double(ns.size.height)))
            maxDiffAlign = max(maxDiffAlign, abs(Double(sw1.width) - Double(ns.alignmentRect.width)), abs(Double(sw1.height) - Double(ns.size.height)))
        } } }
        worst.append((name, maxDiff))
        worstAlign.append((name, maxDiffAlign))
    }
    print("S1 max |SwiftUI fittingSize - NSImage(config).size| per name (names over 0.01 only): "
          + (worst.filter { $0.1 > 0.01 }.map { "\($0.0)=\(g($0.1))" }.joined(separator: " ").nonEmpty ?? "none")
          + "; overall max \(g(worst.map(\.1).max() ?? 0)); names checked \(worst.count)")
    print("S1 refined model H1' (width = NSImage.alignmentRect.width, height = NSImage.size.height): names over 0.01: "
          + (worstAlign.filter { $0.1 > 0.01 }.map { "\($0.0)=\(g($0.1))" }.joined(separator: " ").nonEmpty ?? "none")
          + "; overall max \(g(worstAlign.map(\.1).max() ?? 0))")
    for name in ["doc.badge.plus", "square.and.pencil"] {
        let ns = nsImage(name, 13, .regular, .medium)!
        let sw1 = fit(Image(systemName: name).font(.system(size: 13)))
        print("S1 \(name)@13 medium regular: SwiftUI \(g(sw1)); NSImage.size \(g(ns.size)); alignmentRect \(ns.alignmentRect)")
    }
    for (name, size, scale, weight) in [("star", 13.0, 1, 0), ("star", 13, 2, 0), ("star", 13, 0, 1), ("star", 26, 1, 0), ("magnifyingglass", 13, 1, 1),
                                         ("arrow.up.right.square", 13, 1, 1), ("doc.text", 13, 2, 0), ("xmark.circle", 48, 1, 0), ("brain", 13, 1, 0)] as [(String, Double, Int, Int)] {
        let s = scalePairs[scale], w = weightPairs[weight]
        let sz = fit(Image(systemName: name).font(.system(size: CGFloat(size), weight: w.1)).imageScale(s.1))
        samples.append("\(name)@\(g(size)) \(s.0) \(w.0) = \(g(sz))")
    }
    print("S1 literals: " + samples.joined(separator: "; "))
    for (name, size) in [("star", 9.0), ("star", 13), ("star", 26), ("star", 48)] {
        print("S1 star regular medium @\(g(size)): " + g(fit(Image(systemName: name).font(.system(size: CGFloat(size))))))
    }
}

@MainActor func s2() {
    print("S2 baselines: firstTextBaseline / lastTextBaseline from the top, size; H2 = size.height - alignmentRect.minY (NSImage.alignmentRect, origin bottom-left); H3 = side/2 + capHeight/2")
    for (name, size, scaleIdx, wIdx) in [("star", 13.0, 1, 0), ("star", 26, 1, 0), ("star", 48, 1, 0), ("magnifyingglass", 13, 1, 0), ("doc", 13, 1, 0),
                                          ("doc.text", 13, 2, 0), ("xmark", 13, 0, 1), ("chevron.right", 17, 1, 0), ("globe", 26, 1, 0), ("star", 13, 0, 0), ("star", 13, 2, 0)] as [(String, Double, Int, Int)] {
        let s = scalePairs[scaleIdx], w = weightPairs[wIdx]
        let b = baselines(Image(systemName: name).font(.system(size: CGFloat(size), weight: w.1)).imageScale(s.1))
        let ns = nsImage(name, size, w.2, s.2)!
        let h2 = Double(ns.size.height - ns.alignmentRect.minY)
        let cap = Double(NSFont.systemFont(ofSize: size).capHeight)
        let side = Double(ns.size.height)
        let h3 = side / 2 + cap / 2
        print("S2 \(name)@\(g(size)) \(s.0) \(w.0): first \(g(b.first)) last \(g(b.last)) size \(g(b.size)) | H2 \(g(h2)) (alignmentRect \(ns.alignmentRect)) | H3 \(g(h3)) cap \(g(cap))")
    }
    // beside text: where does the symbol's baseline land in an HStack(.firstTextBaseline)?
    let stack = HStack(alignment: .firstTextBaseline, spacing: 0) { Image(systemName: "star").font(.system(size: 13)); Text("Hxg").font(.system(size: 13)) }
    let b = baselines(stack)
    let textB = baselines(Text("Hxg").font(.system(size: 13)))
    print("S2 HStack(.firstTextBaseline) star|Hxg @13: stack size \(g(b.size)) first \(g(b.first)); text alone size \(g(textB.size)) first \(g(textB.first)); star alone height \(g(fit(Image(systemName: "star").font(.system(size: 13))).height))")
}

@MainActor func s3() {
    let routes: [(String, AnyView)] = [
        ("no font", AnyView(Image(systemName: "star"))),
        (".body", AnyView(Image(systemName: "star").font(.body))),
        (".system(size: 13)", AnyView(Image(systemName: "star").font(.system(size: 13)))),
        (".title", AnyView(Image(systemName: "star").font(.title))),
        (".fontWeight(.bold)", AnyView(Image(systemName: "star").fontWeight(.bold))),
        (".bold()", AnyView(Image(systemName: "star").bold())),
        (".font(.body).fontWeight(.bold)", AnyView(Image(systemName: "star").font(.body).fontWeight(.bold))),
        ("default imageScale medium vs .medium px", AnyView(Image(systemName: "star").imageScale(.medium))),
    ]
    print("S3 font routes (star): " + routes.map { "\($0.0) = \(g(fit($0.1)))" }.joined(separator: "; "))
    print("S3 default imageScale == .medium: \(px(Image(systemName: "star").font(.system(size: 26)), Image(systemName: "star").font(.system(size: 26)).imageScale(.medium))) px; vs .small: \(px(Image(systemName: "star").font(.system(size: 26)), Image(systemName: "star").font(.system(size: 26)).imageScale(.small))) px")
    print("S3 .bold() == .fontWeight(.bold): \(px(Image(systemName: "star").bold(), Image(systemName: "star").fontWeight(.bold))) px; bold vs regular: \(px(Image(systemName: "star").bold(), Image(systemName: "star"))) px")
    print("S3 Text .body size for reference: \(g(fit(Text("H"))))")
}

@MainActor func s4() {
    let red = Color(red: 1, green: 0, blue: 0)
    let sq = raster(Image(systemName: "square.fill").font(.system(size: 40)).foregroundStyle(red), 60, 60)
    print("S4 square.fill .foregroundStyle(red) centre pixel: \(sq.rgb(sq.w / 2 - 20, sq.h / 2 - 20)) (expect 255,0,0 if exact)")
    let def = raster(Image(systemName: "square.fill").font(.system(size: 40)), 60, 60)
    var lightLabel = (0, 0, 0)
    NSAppearance(named: .aqua)!.performAsCurrentDrawingAppearance {
        let c = NSColor.labelColor.usingColorSpace(.sRGB)!
        let a = Double(c.alphaComponent)
        lightLabel = (Int((255 * (1 - a) + 255 * Double(c.redComponent) * a).rounded()), Int((255 * (1 - a) + 255 * Double(c.greenComponent) * a).rounded()), Int((255 * (1 - a) + 255 * Double(c.blueComponent) * a).rounded()))
    }
    print("S4 default (no foregroundStyle) centre pixel: \(def.rgb(def.w / 2 - 20, def.h / 2 - 20)); labelColor over white (light): \(lightLabel); is the render's appearance light? \(NSApp?.effectiveAppearance.name.rawValue ?? "nil NSApp")")
    print("S4 .tint(.red) vs default: \(px(Image(systemName: "square.fill").font(.system(size: 40)).tint(.red), Image(systemName: "square.fill").font(.system(size: 40)), 60, 60)) px")
    print("S4 .foregroundColor(red) vs .foregroundStyle(red): \(px(Image(systemName: "square.fill").font(.system(size: 40)).foregroundColor(red), Image(systemName: "square.fill").font(.system(size: 40)).foregroundStyle(red), 60, 60)) px")
    for name in ["square.on.square", "doc.on.doc", "speaker.wave.2", "wifi", "cloud.sun", "person.2"] where exists(name) {
        let r = raster(Image(systemName: name).font(.system(size: 40)).symbolRenderingMode(.hierarchical).foregroundStyle(Color.black), 60, 60)
        var hist: [Int: Int] = [:]
        for y in 0..<r.h { for x in 0..<r.w { let p = r.rgb(x, y).0; if p < 250 { hist[p / 8 * 8, default: 0] += 1 } } }
        let top = hist.sorted { $0.value > $1.value }.prefix(4).map { "\($0.key)..:\($0.value)" }.joined(separator: " ")
        print("S4 hierarchical black \(name): top grey buckets (255=white): \(top)")
    }
    print("S4 multicolor ignores foreground (sun.max.fill red vs none): \(px(Image(systemName: "sun.max.fill").font(.system(size: 40)).symbolRenderingMode(.multicolor).foregroundStyle(red), Image(systemName: "sun.max.fill").font(.system(size: 40)).symbolRenderingMode(.multicolor), 60, 60)) px; multicolor vs monochrome: \(px(Image(systemName: "sun.max.fill").font(.system(size: 40)).symbolRenderingMode(.multicolor), Image(systemName: "sun.max.fill").font(.system(size: 40)), 60, 60)) px")
    print("S4 monochrome explicit == default: \(px(Image(systemName: "star").symbolRenderingMode(.monochrome), Image(systemName: "star"))) px")
}

@MainActor func s5() {
    print("S5 star + .fill vs star.fill: \(px(Image(systemName: "star").symbolVariant(.fill), Image(systemName: "star.fill"))) px (vs star alone \(px(Image(systemName: "star").symbolVariant(.fill), Image(systemName: "star"))) px)")
    print("S5 xmark + .circle.fill vs xmark.circle.fill: \(px(Image(systemName: "xmark").symbolVariant(.circle.fill), Image(systemName: "xmark.circle.fill"))) px (vs xmark \(px(Image(systemName: "xmark").symbolVariant(.circle.fill), Image(systemName: "xmark"))) px)")
    print("S5 xmark + .fill.circle vs xmark.circle.fill: \(px(Image(systemName: "xmark").symbolVariant(.fill.circle), Image(systemName: "xmark.circle.fill"))) px")
    print("S5 chevron.right.fill exists? \(exists("chevron.right.fill")); chevron.right + .fill vs chevron.right: \(px(Image(systemName: "chevron.right").symbolVariant(.fill), Image(systemName: "chevron.right"))) px (falls back to base if 0)")
    print("S5 environment symbolVariants form: star via .environment(\\.symbolVariants, .fill) vs star.fill: \(px(Image(systemName: "star").environment(\.symbolVariants, .fill), Image(systemName: "star.fill"))) px")
    print("S5 an explicit .fill name under .symbolVariant(.none): \(px(Image(systemName: "star.fill").symbolVariant(.none), Image(systemName: "star.fill"))) px (0 = the name is kept; .none removes nothing)")
    print("S5 star.fill under .symbolVariant(.slash): matches star.slash.fill? \(exists("star.slash.fill")) \(px(Image(systemName: "star.fill").symbolVariant(.slash), Image(systemName: "star.slash.fill"))) px; star.slash? \(exists("star.slash")) \(px(Image(systemName: "star.fill").symbolVariant(.slash), Image(systemName: "star.slash"))) px")
    print("S5 star.fill + .slash vs star.fill: \(px(Image(systemName: "star.fill").symbolVariant(.slash), Image(systemName: "star.fill"))) px; star + .slash vs star.slash: \(px(Image(systemName: "star").symbolVariant(.slash), Image(systemName: "star.slash"))) px; star + .fill.slash vs star.slash.fill: \(px(Image(systemName: "star").symbolVariant(.fill.slash), Image(systemName: "star.slash.fill"))) px")
    print("S5 xmark.circle + .fill vs xmark.circle.fill: \(px(Image(systemName: "xmark.circle").symbolVariant(.fill), Image(systemName: "xmark.circle.fill"))) px (an explicit shape in the name plus a fill variant)")
    let chains: [(String, SymbolVariants)] = [("circle.fill", .circle.fill), ("fill.circle", .fill.circle), ("slash.fill", .slash.fill), ("fill.slash", .fill.slash),
                                              ("circle.slash", .circle.slash), ("slash.circle", .slash.circle), ("circle.slash.fill", .circle.slash.fill), ("fill.slash.circle", .fill.slash.circle),
                                              ("square.fill", .square.fill), ("rectangle.fill", .rectangle.fill)]
    for base in ["bell", "plus", "mic"] {
        var report: [String] = []
        for (label, v) in chains {
            let words = label.split(separator: ".").map(String.init)
            let perms = permutations(words).map { base + "." + $0.joined(separator: ".") }.filter(exists)
            let hits = perms.filter { px(Image(systemName: base).symbolVariant(v), Image(systemName: $0)) == 0 }
            let fallback = hits.isEmpty ? (px(Image(systemName: base).symbolVariant(v), Image(systemName: base)) == 0 ? "base" : (exists(base + ".fill") && px(Image(systemName: base).symbolVariant(v), Image(systemName: base + ".fill")) == 0 ? "base.fill" : "other")) : hits.joined(separator: "|")
            report.append("\(label)->\(fallback)")
        }
        print("S5 order (\(base)): " + report.joined(separator: "; "))
    }
}

func permutations(_ a: [String]) -> [[String]] {
    if a.count <= 1 { return [a] }
    var out: [[String]] = []
    for i in a.indices { var rest = a; let x = rest.remove(at: i); for p in permutations(rest) { out.append([x] + p) } }
    return out
}

@MainActor func s6() {
    let path = NSTemporaryDirectory() + "sym-probe-stderr.txt"
    let saved = dup(2)
    let fd = open(path, O_WRONLY | O_CREAT | O_TRUNC, 0o644)
    dup2(fd, 2)
    let size = fit(Image(systemName: "this.symbol.does.not.exist"))
    let sizeWithFont = fit(Image(systemName: "this.symbol.does.not.exist").font(.system(size: 26)))
    let r = raster(Image(systemName: "this.symbol.does.not.exist"), 60, 40)
    let bl = baselines(Image(systemName: "this.symbol.does.not.exist").font(.system(size: 13)))
    let empty = ink(r) == nil
    let frameSized = fit(Image(systemName: "this.symbol.does.not.exist").frame(width: 30, height: 30))
    let resizable = fit(Image(systemName: "this.symbol.does.not.exist").resizable().frame(width: 30, height: 30))
    fflush(stderr)
    dup2(saved, 2); close(saved); close(fd)
    let text = (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
    try? FileManager.default.removeItem(atPath: path)
    print("S6 missing name: size \(g(size)) (font 26: \(g(sizeWithFont))); render empty: \(empty); baselines first \(g(bl.first)) last \(g(bl.last)) size \(g(bl.size)); .frame(30,30): \(g(frameSized)); resizable framed: \(g(resizable))")
    print("S6 stderr text (\(text.count) chars): \(text.isEmpty ? "(none)" : text.replacingOccurrences(of: "\n", with: " | "))")
    print("S6 an empty-string name: size \(g(fit(Image(systemName: ""))))")
}

@MainActor func s7() {
    let box = 40
    let rz = raster(Image(systemName: "star").resizable().frame(width: 40, height: 40), box, box)
    let fitR = raster(Image(systemName: "star").resizable().scaledToFit().frame(width: 40, height: 40), box, box)
    let fillR = raster(Image(systemName: "star").resizable().scaledToFill().frame(width: 40, height: 40).clipped(), box, box)
    let plain = raster(Image(systemName: "star").font(.system(size: 40)).frame(width: 40, height: 40), box, box)
    func f(_ b: (Double, Double, Double, Double)?) -> String { b.map { "[\(g($0.0)),\(g($0.1))..\(g($0.2)),\(g($0.3))]" } ?? "empty" }
    print("S7 star ink bbox in a 40x40 frame: resizable \(f(ink(rz))); resizable+scaledToFit \(f(ink(fitR))); scaledToFill+clipped \(f(ink(fillR))); font 40 (not resizable) \(f(ink(plain)))")
    print("S7 resizable star ideal (nil proposal) size: \(g(fit(Image(systemName: "star").resizable()))); in a 40x20 frame: \(g(fit(Image(systemName: "star").resizable().frame(width: 40, height: 20)))); ink in 40x20: \(f(ink(raster(Image(systemName: "star").resizable().frame(width: 40, height: 20), 40, 40))))")
    print("S7 resizable star under a 100x100 proposal as an overlay-free child: ideal ratio fit: \(g(fit(Image(systemName: "star").resizable().scaledToFit().frame(width: 100, height: 100))))")
}

func kv(_ o: NSObject, _ key: String) -> Any? {
    guard o.responds(to: Selector(key)) else { return nil }
    return o.value(forKey: key)
}
@MainActor func axTree(_ o: Any, _ depth: Int, _ out: inout [String]) {
    guard depth < 7, let obj = o as? NSObject else { return }
    let role = (kv(obj, "accessibilityRole") as? String) ?? "-"
    let label = (kv(obj, "accessibilityLabel") as? String).map { "'\($0)'" } ?? "nil"
    let kids = (kv(obj, "accessibilityChildren") as? [Any]) ?? []
    out.append(String(repeating: ">", count: depth) + "\(role):\(label)")
    for k in kids { axTree(k, depth + 1, &out) }
}

@MainActor func s8() {
    _ = NSApplication.shared
    NSApp.accessibilitySetValue(true, forAttribute: NSAccessibility.Attribute(rawValue: "AXEnhancedUserInterface"))
    func tree<V: View>(_ v: V) -> String {
        let hv = NSHostingView(rootView: v.frame(width: 40, height: 40))
        let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 100, height: 100), styleMask: [.titled], backing: .buffered, defer: true)
        win.isReleasedWhenClosed = false
        win.contentView = hv   // never ordered front: no window is shown
        hv.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        var lines: [String] = []
        axTree(hv, 0, &lines)
        return lines.joined(separator: " ")
    }
    print("S8 control: Text(\"hello\") tree [\(tree(Text("hello")))]; Image(decorative: nil) n/a")
    for name in ["star", "magnifyingglass", "doc"] {
        let desc = NSImage(systemSymbolName: name, accessibilityDescription: nil)?.accessibilityDescription
        let described = NSImage(systemSymbolName: name, accessibilityDescription: "X")?.accessibilityDescription
        print("S8 \(name): [\(tree(Image(systemName: name)))]; NSImage.accessibilityDescription (nil in) = \(desc.map { "'\($0)'" } ?? "nil"); (\"X\" in) = \(described.map { "'\($0)'" } ?? "nil")")
        print("S8 \(name) hidden: [\(tree(Image(systemName: name).accessibilityHidden(true)))]; accessibilityLabel(\"Custom\"): [\(tree(Image(systemName: name).accessibilityLabel("Custom")))]; inside Button(action:){Image}: [\(tree(Button(action: {}) { Image(systemName: name) }))]")
    }
}

/// Coverage route: NSImage into a transparent RGBA bitmap at scale 2, then composite black coverage over white.
@MainActor func routeRaster(_ name: String, size: Double, weight: NSFont.Weight, scale: NSImage.SymbolScale, originX: Double, originY: Double, w: Int, h: Int) -> Raster {
    let s = 2, W = w * s, H = h * s
    var data = [UInt8](repeating: 0, count: W * H * 4)
    let cs = CGColorSpace(name: CGColorSpace.sRGB)!
    let img = nsImage(name, size, weight, scale)!
    data.withUnsafeMutableBytes { p in
        let ctx = CGContext(data: p.baseAddress, width: W, height: H, bitsPerComponent: 8, bytesPerRow: W * 4, space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.scaleBy(x: CGFloat(s), y: CGFloat(s))
        let gc = NSGraphicsContext(cgContext: ctx, flipped: false)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = gc
        let rect = NSRect(x: originX, y: Double(h) - originY - Double(img.size.height), width: Double(img.size.width), height: Double(img.size.height))
        img.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()
    }
    var out = [UInt8](repeating: 255, count: W * H * 4)
    for i in 0..<(W * H) {
        let a = Int(data[i * 4 + 3])
        let v = UInt8(255 - a)   // black ink over white
        out[i * 4] = v; out[i * 4 + 1] = v; out[i * 4 + 2] = v; out[i * 4 + 3] = 255
    }
    return Raster(w: W, h: H, data: out)
}

@MainActor func s9() {
    let w = 40, h = 30
    for (name, size) in [("star", 13.0), ("magnifyingglass", 13.0), ("doc.text", 26.0)] {
        var parts: [String] = []
        for o in [0.0, 0.25, 0.5] {
            let sw = raster(Image(systemName: name).font(.system(size: CGFloat(size))).foregroundStyle(Color.black).offset(x: 4 + o, y: 4 + o), w, h)
            let mine = routeRaster(name, size: size, weight: .regular, scale: .medium, originX: 4 + o, originY: 4 + o, w: w, h: h)
            let d = diff(mine, sw)
            parts.append("origin \(g(o)): \(d.px) px of \(d.total) (\(g(Double(d.px) * 100 / Double(d.total)))%), max \(d.max)")
        }
        // separating: route at origin 0 against SwiftUI at 0.5 (a half point = one device pixel shift)
        let sw5 = raster(Image(systemName: name).font(.system(size: CGFloat(size))).foregroundStyle(Color.black).offset(x: 4.5, y: 4.5), w, h)
        let mine0 = routeRaster(name, size: size, weight: .regular, scale: .medium, originX: 4, originY: 4, w: w, h: h)
        let sep = diff(mine0, sw5)
        let sw025 = raster(Image(systemName: name).font(.system(size: CGFloat(size))).foregroundStyle(Color.black).offset(x: 4.25, y: 4.25), w, h)
        let sw0 = raster(Image(systemName: name).font(.system(size: CGFloat(size))).foregroundStyle(Color.black).offset(x: 4, y: 4), w, h)
        print("S9 \(name)@\(g(size)): " + parts.joined(separator: "; ") + "; separating (route@4 vs SwiftUI@4.5): \(sep.px) px, max \(sep.max); SwiftUI@4.25 vs SwiftUI@4: \(diff(sw025, sw0).px) px (0 = SwiftUI snaps the quarter point)")
    }
}

@MainActor func s9b() {
    // Does a constant offset reconcile the AppKit raster with SwiftUI's? Search +-1 pt in quarter points around origin 4.
    let w = 60, h = 50
    for (name, size) in [("star", 13.0), ("magnifyingglass", 13.0), ("doc.text", 26.0), ("xmark", 17.0), ("chevron.right", 13.0), ("globe", 26.0), ("doc.badge.plus", 13.0)] {
        let sw = raster(Image(systemName: name).font(.system(size: CGFloat(size))).foregroundStyle(Color.black).offset(x: 4, y: 4), w, h)
        var best: (Double, Double, Int, Int)? = nil
        var at0 = (0, 0)
        for dx in stride(from: -1.0, through: 1.0, by: 0.25) { for dy in stride(from: -1.0, through: 1.0, by: 0.25) {
            let d = diff(routeRaster(name, size: size, weight: .regular, scale: .medium, originX: 4 + dx, originY: 4 + dy, w: w, h: h), sw)
            if dx == 0 && dy == 0 { at0 = (d.px, d.max) }
            if best == nil || d.px < best!.2 { best = (dx, dy, d.px, d.max) }
        } }
        let b = best!
        print("S9b \(name)@\(g(size)): at the same origin \(at0.0) px (max \(at0.1)) of \(w * h * 4) (\(g(Double(at0.0) * 100 / Double(w * h * 4)))%); best offset (dx \(g(b.0)), dy \(g(b.1))) \(b.2) px (max \(b.3)) = \(g(Double(b.2) * 100 / Double(w * h * 4)))%")
    }
}

// PDF operator scan (S10)
nonisolated(unsafe) var pdfOps: [String: Int] = [:]
nonisolated(unsafe) var pdfCoords: [Double] = []
func pop(_ s: OpaquePointer, _ n: Int) -> [Double] {
    var v: [Double] = []
    for _ in 0..<n { var x: CGPDFReal = 0; if CGPDFScannerPopNumber(s, &x) { v.append(Double(x)) } }
    return v.reversed()
}
let opM: CGPDFOperatorCallback = { s, _ in pdfOps["m", default: 0] += 1; pdfCoords += pop(s, 2) }
let opL: CGPDFOperatorCallback = { s, _ in pdfOps["l", default: 0] += 1; pdfCoords += pop(s, 2) }
let opC: CGPDFOperatorCallback = { s, _ in pdfOps["c", default: 0] += 1; pdfCoords += pop(s, 6) }
let opF: CGPDFOperatorCallback = { _, _ in pdfOps["f", default: 0] += 1 }
let opFs: CGPDFOperatorCallback = { _, _ in pdfOps["f*", default: 0] += 1 }
nonisolated(unsafe) var pdfStreams: [CGPDFContentStreamRef] = []
nonisolated(unsafe) var pdfTable: CGPDFOperatorTableRef?
let opDo: CGPDFOperatorCallback = { s, _ in
    var name: UnsafePointer<CChar>?
    guard CGPDFScannerPopName(s, &name), let name, let cs = pdfStreams.last else { pdfOps["Do", default: 0] += 1; return }
    var obj: CGPDFObjectRef?
    guard CGPDFContentStreamGetResource(cs, "XObject", name) != nil else { pdfOps["Do", default: 0] += 1; return }
    obj = CGPDFContentStreamGetResource(cs, "XObject", name)
    var stream: CGPDFStreamRef?
    guard let obj, CGPDFObjectGetValue(obj, .stream, &stream), let st = stream, let sd = CGPDFStreamGetDictionary(st) else { pdfOps["Do", default: 0] += 1; return }
    var sub: UnsafePointer<CChar>?
    let kind = CGPDFDictionaryGetName(sd, "Subtype", &sub) && sub != nil ? String(cString: sub!) : "?"
    pdfOps["Do:\(kind)", default: 0] += 1
    if kind == "Form" {
        var res: CGPDFDictionaryRef?
        _ = CGPDFDictionaryGetDictionary(sd, "Resources", &res)
        let inner = CGPDFContentStreamCreateWithStream(st, res ?? sd, cs)
        pdfStreams.append(inner)
        let sc = CGPDFScannerCreate(inner, pdfTable, nil)
        CGPDFScannerScan(sc)
        CGPDFScannerRelease(sc); CGPDFContentStreamRelease(inner)
        pdfStreams.removeLast()
    }
}
let opSh: CGPDFOperatorCallback = { _, _ in pdfOps["sh", default: 0] += 1 }
let opBI: CGPDFOperatorCallback = { _, _ in pdfOps["BI", default: 0] += 1 }
let opS: CGPDFOperatorCallback = { _, _ in pdfOps["S", default: 0] += 1 }

/// The /Subtype names of the first page's XObjects ("Image" or "Form").
func xobjectSubtypes(_ data: Data) -> [String] {
    guard let prov = CGDataProvider(data: data as CFData), let doc = CGPDFDocument(prov), let page = doc.page(at: 1), let d = page.dictionary else { return ["no page"] }
    var res: CGPDFDictionaryRef?
    guard CGPDFDictionaryGetDictionary(d, "Resources", &res), let r = res else { return ["no resources"] }
    var xo: CGPDFDictionaryRef?
    guard CGPDFDictionaryGetDictionary(r, "XObject", &xo), let x = xo else { return ["no XObject entry"] }
    nonisolated(unsafe) var names: [String] = []
    CGPDFDictionaryApplyBlock(x, { key, obj, _ in
        var stream: CGPDFStreamRef?
        if CGPDFObjectGetValue(obj, .stream, &stream), let st = stream, let sd = CGPDFStreamGetDictionary(st) {
            var sub: UnsafePointer<CChar>?
            if CGPDFDictionaryGetName(sd, "Subtype", &sub), let sub { names.append(String(cString: sub)) } else { names.append("?") }
        } else { names.append("not a stream") }
        return true
    }, nil)
    return names.isEmpty ? ["none"] : names
}

func scanPDF(_ data: Data) -> (ops: [String: Int], coords: [Double]) {
    pdfOps = [:]; pdfCoords = []
    guard let prov = CGDataProvider(data: data as CFData), let doc = CGPDFDocument(prov), let page = doc.page(at: 1) else { return ([:], []) }
    let table = CGPDFOperatorTableCreate()!
    for (n, cb) in [("m", opM), ("l", opL), ("c", opC), ("f", opF), ("f*", opFs), ("Do", opDo), ("sh", opSh), ("BI", opBI), ("S", opS)] {
        CGPDFOperatorTableSetCallback(table, n, cb)
    }
    let cs = CGPDFContentStreamCreateWithPage(page)
    pdfTable = table; pdfStreams = [cs]
    let scanner = CGPDFScannerCreate(cs, table, nil)
    CGPDFScannerScan(scanner)
    CGPDFScannerRelease(scanner); CGPDFContentStreamRelease(cs)
    return (pdfOps, pdfCoords)
}

@MainActor func pdf(drawing: (CGContext) -> Void) -> Data {
    let data = NSMutableData()
    var box = CGRect(x: 0, y: 0, width: 200, height: 200)
    let ctx = CGContext(consumer: CGDataConsumer(data: data)!, mediaBox: &box, nil)!
    ctx.beginPDFPage(nil)
    drawing(ctx)
    ctx.endPDFPage(); ctx.closePDF()
    return data as Data
}

@MainActor func s10() {
    func symbolPDF(_ name: String, _ size: Double) -> Data {
        pdf { ctx in
            let img = nsImage(name, size, .regular, .medium)!
            let gc = NSGraphicsContext(cgContext: ctx, flipped: false)
            NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = gc
            img.draw(in: NSRect(x: 20, y: 20, width: img.size.width, height: img.size.height))
            NSGraphicsContext.restoreGraphicsState()
        }
    }
    func fmt(_ o: [String: Int]) -> String { o.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: " ").nonEmpty ?? "(no operators)" }
    for name in ["star", "magnifyingglass", "doc.text"] {
        let r = scanPDF(symbolPDF(name, 13))
        print("S10 symbol \(name)@13 into a PDF context (Form XObjects descended): \(fmt(r.ops)); coordinates seen \(r.coords.count)")
    }
    // separating arm: a bitmap-backed NSImage
    let bitmapImage = NSImage(size: NSSize(width: 20, height: 20), flipped: false) { rect in
        NSColor.black.setFill(); NSBezierPath(ovalIn: rect).fill(); return true
    }
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 40, pixelsHigh: 40, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    let bm = NSImage(size: NSSize(width: 20, height: 20)); bm.addRepresentation(rep)
    let bpdf = pdf { ctx in
        let gc = NSGraphicsContext(cgContext: ctx, flipped: false)
        NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = gc
        bm.draw(in: NSRect(x: 20, y: 20, width: 20, height: 20))
        NSGraphicsContext.restoreGraphicsState()
    }
    print("S10 separating (bitmap NSImage): \(fmt(scanPDF(bpdf).ops)) (expect Do:Image, no m/l/c)")
    let vecPDF = pdf { ctx in ctx.move(to: CGPoint(x: 20, y: 20)); ctx.addLine(to: CGPoint(x: 60, y: 60)); ctx.addLine(to: CGPoint(x: 20, y: 60)); ctx.fillPath() }
    print("S10 separating (a CGContext path fill): \(fmt(scanPDF(vecPDF).ops)) (expect m/l/f, no Do)")
    _ = bitmapImage
    // scale agreement of outlines: normalise each coordinate list by its own x/y extent
    let a = scanPDF(symbolPDF("star", 13)).coords, b = scanPDF(symbolPDF("star", 26)).coords
    func norm(_ c: [Double]) -> [Double] {
        let xs = stride(from: 0, to: c.count, by: 2).map { c[$0] }, ys = stride(from: 1, to: c.count, by: 2).map { c[$0] }
        let (x0, x1, y0, y1) = (xs.min()!, xs.max()!, ys.min()!, ys.max()!)
        return c.enumerated().map { $0.offset % 2 == 0 ? ($0.element - x0) / (x1 - x0) : ($0.element - y0) / (y1 - y0) }
    }
    if a.count == b.count, !a.isEmpty {
        let na = norm(a), nb = norm(b)
        print("S10 star outlines at 13 and 26 pt, same coordinate count (\(a.count)): max |difference| of bbox-normalised coordinates: \(g((0..<na.count).map { abs(na[$0] - nb[$0]) }.max()!))")
    } else {
        print("S10 star outlines 13 vs 26 pt: coordinate counts \(a.count) vs \(b.count) (not comparable)")
    }
}

@MainActor func s11() {
    let label = Label("Read", systemImage: "doc")
    let sizeL = fit(label), imgS = fit(Image(systemName: "doc")), txtS = fit(Text("Read"))
    let bL = baselines(label), bI = baselines(Image(systemName: "doc")), bT = baselines(Text("Read"))
    print("S11 Label(\"Read\", systemImage: \"doc\") size \(g(sizeL)); image alone \(g(imgS)); text alone \(g(txtS)); horizontal gap = \(g(Double(sizeL.width - imgS.width - txtS.width)))")
    print("S11 baselines: label first \(g(bL.first)) last \(g(bL.last)); image first \(g(bI.first)); text first \(g(bT.first)) last \(g(bT.last))")
    let hs = HStack(alignment: .firstTextBaseline, spacing: 4) { Image(systemName: "doc"); Text("Read") }
    print("S11 HStack(.firstTextBaseline, spacing 4) equivalent size \(g(fit(hs)))")
    let r = raster(label.padding(2), 80, 30)
    print("S11 label ink bbox: \(ink(r).map { "[\(g($0.0)),\(g($0.1))..\(g($0.2)),\(g($0.3))]" } ?? "empty")")
}

extension String { var nonEmpty: String? { isEmpty ? nil : self } }

@MainActor func main() {
    _ = NSApplication.shared
    s0(); s1(); s2(); s3(); s4(); s5(); s6(); s7(); s8(); s9(); s9b(); s10(); s11()
}
MainActor.assumeIsolated { main() }
