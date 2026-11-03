// SwiftUI probe: measuring a string (C23, user request 2026-10-02, item of the
// gpui-gap priority list; MetalCreator gap S5-c). SwiftUI's only public
// string measure is `GraphicsContext.ResolvedText.measure(in:)` inside a
// `Canvas`; `Text` itself has none. Evidence for rulings GT-C and GT-D in
// docs/superpowers/2026-10-12-surface-text-decisions.md.
//
// HOW TO RUN (compiled form, SA-O):
//
//   xcrun swiftc docs/probes/swiftui-surface-text.swift -o /tmp/st-probe && /tmp/st-probe
//
// THE INSTRUMENTS. `ImageRenderer` renders a `Canvas` synchronously on the
// main actor, so its closure runs and records what `context.resolve(_:)` and
// `ResolvedText.measure(in:)` answer. A0 is the positive control: the same
// `Text` laid out as a view (`ImageRenderer(content: Text…)` image size, which
// is the view's ideal size) must equal the Canvas measure with an unbounded
// proposal. Separating arms: B narrows the width (wraps: height grows), C
// proposes a short height (does the measure truncate?), D changes the font
// through the Canvas's environment (resolve reads the environment), E measures
// the empty string.
//
// RECORDED OUTPUT (macOS 27.0, 2026-10-12; run twice, byte-identical):
//
//   A0 view ideal size (51.0, 16.0)  canvas measure(1000x1000) (51.0, 16.0)  equal=true
//   B  measure(w:1000) (238.0, 16.0)  measure(w:60) (60.0, 80.0)
//   C  measure(w:60,h:5) (51.0, 16.0)
//   D  default env (51.0, 16.0)  .font(system 26) env (97.0, 30.0)
//   E  empty (0.0, 14.0)
//   E2 empty as a view (fixedSize) (0.0, 0.0)
//   G  ResolvedText firstBaseline(in:)/lastBaseline(in:) of the 13 pt text: (13.0, 13.0)
//   F  infinity proposal (51.0, 16.0)
//
// READING. A0 positive control: the Canvas measure equals the view's ideal
// size. B: a width proposal wraps (60 wide, five lines at 16). C: a short height
// proposal caps the lines to one (MetalUI's TE-H item 2 rule, the same). D:
// `resolve` reads the Canvas's environment font. E vs E2: the empty string
// measures (0, 14) in a Canvas and read (0, 0) as a view: **that E2 reading is WRONG, an instrument artifact**
// (R4-1 addendum below: the laid-out view is (0, 14) too, at every font). F: an infinite proposal is
// the unbounded measure. G: baselines are functions of a size, 13 for 13 pt.
//
// R4-1 PR A ADDENDUM (2026-11-03, macOS 27.2, same compiled form; the arms E3-E7 below the existing ones). **E2 WAS
// AN INSTRUMENT ARTIFACT**: `ImageRenderer` returns a nil image for a zero-WIDTH view, which `viewSize` reads as
// (0, 0). `NSHostingView.fittingSize` (the `fitting` helper) reads the same `Text("")` as (0, 14), equal to the
// Canvas measure `E`, so a laid-out empty `Text` is one line tall in SwiftUI and divergence 295's SwiftUI side was wrong.
//
//   E3  VStack(spacing:10){rect;Text("");rect}  (10.0, 54.0)   = 10+10+14+10+10: the empty Text takes its 14 AND both gaps
//   E3b VStack(spacing:10){rect;rect}           (10.0, 30.0)   (control)
//   E4  HStack(firstTextBaseline){Text("");Text("x")} (7.0, 16.0)  = Text("x") alone (7.0, 16.0)
//   E5  Text("").padding(4)                     (8.0, 22.0)    = 0+8 wide, 14+8 tall
//   E6  Text(" ")                               (4.0, 16.0)    (control: a blank is a full line, 16 not 14)
//   E7  Button("") (24.0, 22.0)  Toggle("") (21.0, 19.0)  Button("x") (31.0, 24.0)
//   E2c Text("") fittingSize (0.0, 14.0); Text("").fixedSize() (0.0, 14.0); .font(system 13) (0.0, 14.0);
//       ImageRenderer(Text("").fixedSize()) nsImage = nil (the artifact); ImageRenderer(Text("").padding(.horizontal,1).fixedSize()) (2.0, 14.0).
//
//   E8 (`Text("")` against `Text(" ")` by `fittingSize` height, system font): the empty height is a CONSTANT 14 whatever the font:
//       size 9: 14 vs 11 | 10: 14 vs 13 | 11: 14 vs 14 | 12: 14 vs 15 | 13: 14 vs 16 | 14: 14 vs 17 | 16: 14 vs 19 | 20: 14 vs 24
//       24: 14 vs 28 | 30: 14 vs 35 | 40: 14 vs 47; default font 14 vs 16; .body 14/16, .title 14/26, .caption 14/13.
//   So SwiftUI's empty `Text` is 14 tall at every size, equal to a line of the system font only near 11 pt; it is not a function of the
//   resolved font's metrics (divergence 295 keeps the full line of the resolved font).
import SwiftUI
import AppKit

@MainActor func canvasMeasure(_ text: Text, in proposal: CGSize, font: Font? = nil) -> CGSize {
    var result = CGSize.zero
    let canvas = Canvas { context, _ in
        result = context.resolve(text).measure(in: proposal)
    }
    .frame(width: 200, height: 100)
    let view: AnyView = font.map { AnyView(canvas.font($0)) } ?? AnyView(canvas)
    let renderer = ImageRenderer(content: view)
    renderer.scale = 1
    _ = renderer.nsImage
    return result
}

@MainActor func viewSize(_ text: Text) -> CGSize {
    let renderer = ImageRenderer(content: text.fixedSize())
    renderer.scale = 1
    return renderer.nsImage?.size ?? .zero
}

@MainActor func fitting<V: View>(_ v: V) -> CGSize {
    let host = NSHostingView(rootView: v)
    return host.fittingSize
}

@MainActor func main() {
    let t = Text("12.5 mm").font(.system(size: 13))
    let a0view = viewSize(t)
    let a0 = canvasMeasure(t, in: CGSize(width: 1000, height: 1000))
    print("A0 view ideal size \(a0view)  canvas measure(1000x1000) \(a0)  equal=\(a0view == a0)")
    let long = Text("12.5 mm and some more words to wrap").font(.system(size: 13))
    print("B  measure(w:1000) \(canvasMeasure(long, in: CGSize(width: 1000, height: 1000)))  measure(w:60) \(canvasMeasure(long, in: CGSize(width: 60, height: 1000)))")
    print("C  measure(w:60,h:5) \(canvasMeasure(long, in: CGSize(width: 60, height: 5)))")
    print("D  default env \(canvasMeasure(Text("12.5 mm"), in: CGSize(width: 1000, height: 1000)))  .font(system 26) env \(canvasMeasure(Text("12.5 mm"), in: CGSize(width: 1000, height: 1000), font: .system(size: 26)))")
    print("E  empty \(canvasMeasure(Text(""), in: CGSize(width: 1000, height: 1000)))")
    print("E2 empty as a view (fixedSize) \(viewSize(Text("")))")
    var base = (CGFloat(0), CGFloat(0))
    let r = ImageRenderer(content: Canvas { c, _ in let rt = c.resolve(t); let big = CGSize(width: 1000, height: 1000); base = (rt.firstBaseline(in: big), rt.lastBaseline(in: big)) }.frame(width: 50, height: 50))
    r.scale = 1; _ = r.nsImage
    print("G  ResolvedText firstBaseline(in:)/lastBaseline(in:) of the 13 pt text: \(base)")
    // R4-1 PR A arms (SR-A): what an empty Text does to its neighbours. Rows are 10x10 rects.
    let rect = Color.red.frame(width: 10, height: 10)
    print("E3 VStack(spacing:10){rect;Text(\"\");rect} \(fitting(VStack(spacing: 10) { rect; Text(""); rect })) (40 high = spacing survives twice; 30 = collapses)")
    print("E3b VStack(spacing:10){rect;rect} \(fitting(VStack(spacing: 10) { rect; rect }))")
    print("E4 HStack(firstTextBaseline){Text(\"\");Text(\"x\")} \(fitting(HStack(alignment: .firstTextBaseline, spacing: 0) { Text(""); Text("x") })) vs Text(\"x\") \(fitting(Text("x")))")
    print("E5 Text(\"\").padding(4) \(fitting(Text("").padding(4)))")
    print("E6 Text(\" \") \(fitting(Text(" "))) (control: one line)")
    print("E7 Button(\"\"){} \(fitting(Button("") {})) Toggle(\"\") \(fitting(Toggle("", isOn: .constant(false)))) Button(\"x\"){} \(fitting(Button("x") {}))")
    for size in [9, 10, 11, 12, 13, 14, 16, 20, 24, 30, 40] as [CGFloat] {
        let e = fitting(Text("").font(.system(size: size))).height, b = fitting(Text(" ").font(.system(size: size))).height
        let x = fitting(Text("x").font(.system(size: size))).height
        print("E8 system \(size)pt: Text(\"\") h=\(e)  Text(\" \") h=\(b)  Text(\"x\") h=\(x)  diff=\(b - e)")
    }
    print("E8 default font: Text(\"\") \(fitting(Text("")).height) Text(\" \") \(fitting(Text(" ")).height)")
    print("E8 .body \(fitting(Text("").font(.body)).height)/\(fitting(Text(" ").font(.body)).height) .title \(fitting(Text("").font(.title)).height)/\(fitting(Text(" ").font(.title)).height) .caption \(fitting(Text("").font(.caption)).height)/\(fitting(Text(" ").font(.caption)).height)")
    print("F  infinity proposal \(canvasMeasure(t, in: CGSize(width: CGFloat.infinity, height: CGFloat.infinity)))")
}
MainActor.assumeIsolated { main() }
