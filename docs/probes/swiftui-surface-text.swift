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
// measures (0, 14) in a Canvas but (0, 0) as a view, so the Canvas measure is
// NOT always the layout answer (divergence 295). F: an infinite proposal is
// the unbounded measure. G: baselines are functions of a size, 13 for 13 pt.
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
    print("F  infinity proposal \(canvasMeasure(t, in: CGSize(width: CGFloat.infinity, height: CGFloat.infinity)))")
}
MainActor.assumeIsolated { main() }
