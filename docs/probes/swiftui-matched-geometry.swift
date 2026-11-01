// SwiftUI probe: round 3 item R3-2 — `matchedGeometryEffect`, `contentTransition` and the `Transition`
// protocol. Evidence for rulings `MG-A`… in docs/superpowers/2026-10-31-matched-geometry-decisions.md and
// divergences 895–898.
//
// HOW TO RUN (Apple's toolchain, COMPILED — the `/usr/bin/swift` JIT form fails to link on macOS 27):
//
//   xcrun swiftc docs/probes/swiftui-matched-geometry.swift -o /tmp/mgprobe
//   /tmp/mgprobe 2>&1 | grep -v 'Connection\]'
//
// HOW IT READS — TWO INSTRUMENTS, both in-process with the screen LOCKED (the recorder and the bitmap are
// driven by SwiftUI itself, as in `swiftui-transactions-animation.swift`).
//
//  1. THE RECORDER (arms C0, MG*, CT*, TP*): every arm animates with `A`, an `Animation(Rec(tag:))` over a
//     `CustomAnimation` that records the TYPE of each animatable value SwiftUI hands it and its DELTA
//     (target − start). `P<P<F, F>, P<F, F>> [ox, oy, w, h]` is a view's GEOMETRY: its CENTRE and size,
//     interpolated per view after layout (the delta of a view whose centre moves by (325, 155) and whose size
//     grows by (50, 30) reads [325, 155, 50, 30]); `Double [d]` an opacity; `F [r]` a blur radius. The
//     `frame` lines are `onGeometryChange` reports of the LAID-OUT frame (a matched move is not a layout
//     change: they report one value).
//  2. THE BITMAP (arms S*, P*): `NSHostingView.cacheDisplay` into a bitmap at three moments after the change,
//     under `.linear(duration: 1)`, and the bounding box of the red (tile A, 50 × 30 pt) and blue (tile B,
//     100 × 60 pt) pixels, in DEVICE pixels at 2x. B lays out at x 600-799, y 280-399; A at x 0-99,
//     y 0-59. `cacheDisplay` draws the model layer, so it shows GEOMETRY truthfully but not an opacity that
//     Core Animation is fading: a "red none" at the end is the view having left, a red that never leaves
//     before 1 s is a view whose opacity is still running. The sample moments are wall-clock: the
//     mid-flight boxes vary by up to ~20 px between runs on a busy machine; every other line is stable.
//
// THE STAGE. A ZStack (400 × 200, top-leading) holds tile A (red 50 × 30) under `if !flag` and tile B (blue
// 100 × 60, pinned bottom-trailing by an outer `.frame(maxWidth/maxHeight: .infinity)`) under `if flag`, both
// `matchedGeometryEffect(id: "x", in: ns, ...)`; the change is `withAnimation(...) { flag.toggle() }`.
// `Swap` takes `properties`, `srcA`/`srcB` (`isSource`), `both` (both tiles present at once) and per-tile
// transitions.
//
// WHAT IT MEASURED (the numbers are in the recording below).
//
//   MG1/S1  A swap with the default transitions: the newcomer's geometry animates with delta
//           [325, 155, 50, 30] = B − A (centre and size), and both views cross-fade (Double ±1). The
//           reverse swap reads the negation (MG1r). With NO transaction nothing animates (MG1n).
//   MG1i…MG5i, S2, S4-S8  The OLD tile with `.transition(.identity)` (removed at once): the newcomer gets
//           NO geometry animation and is at its final frame on the first sample — whatever `properties` or
//           `isSource` (S5-S8). The handoff needs a leaver SwiftUI keeps on screen.
//   S3      The NEW tile with `.transition(.identity)`, the old default: the newcomer is drawn OPAQUE at A's
//           frame on the first sample and moves to B (x 0-112 → 600-799): "the newcomer animates from the
//           old frame" is exactly this arm.
//   S9      `properties: .position`: the newcomer starts with A's CENTRE and its OWN size (x 0-161 y 0-95
//           is B's 200 × 120 px box centred on A's centre, clipped at the window edge) and moves to B.
//   S10, P6, MG3  `properties: .size` alone: no visible motion (B at its final box at once; as a follower
//           B keeps its position AND its size). Unresolved: SwiftUI's `.size` is not read by this probe
//           further, and MetalUI implements the name (centre kept, size taken, `MG-C`).
//   S11     The newcomer `isSource: false`, the old a source: same as S1 — the newcomer still flies.
//   S12     The OLD tile `isSource: false`, the new a source: the newcomer is at B at once and the OLD tile
//           is the one that moves (to B's centre, keeping its own size). S13: neither a source: nothing
//           moves.
//   P1-P6   Two tiles with one id present at once: P1 both sources — A is drawn at B's frame (hidden under
//           B): the LAST source in tree order wins and the other follows; P2 B follows source A (B drawn at
//           A's frame, 50 × 30); P3 A follows source B; P4 neither a source: each at its own frame;
//           P5 B follows A with `.position`: B keeps its size, centred on A's centre; P6 `.size`: no
//           visible change.
//   MG12/MG13  A removal with no newcomer, an insertion with no old view: opacity only, no geometry.
//   CT0-CT4 `contentTransition` on a `Text` whose string changes (1234 → 9876): `.identity` records NO
//           opacity (the change is not cross-faded); `.opacity`, `.interpolate`, `.numericText()` and no
//           modifier all record an opacity [1] — and ALL FIVE record the same text-frame geometry
//           [-1.5, 0, 3, 0] (the width change of the new string): this probe sees `.interpolate` and
//           `.numericText()` as the same opacity cross-fade, their glyph morph is not visible to the
//           recorder.
//   TP1     A custom `Transition` (scale 0.5 and opacity 0 when not identity): insertion records opacity
//           [+1] and a SCALE [0.5, 0.5] (delta = identity − willAppear); removal [-1] and [-0.5, -0.5]; the
//           phases `body` is asked for are exactly willAppear, identity, didDisappear.
//   TP2     A custom offset transition (x −40 for willAppear, +40 for didDisappear, 0 identity): insertion
//           offset delta [40, 0], removal [40, 0].
//   TP3     `.blurReplace`: opacity ±1, a blur radius F [∓7] and a scale [±0.1, ±0.1] — a blur is not
//           something MetalUI's transition scope can draw (carried, `MG-H`).
//   TP4     `.modifier(active:identity:)` with a scale modifier: a scale record [0.5, 0.5].
//
// CONFORMANCES: the file typechecks `Transition`, `TransitionPhase`, `matchedGeometryEffect(id:in:properties:
// anchor:isSource:)` and `MatchedGeometryProperties` against the macOS 27 SDK.
//
// RECORDED 2026-10-31 by the R3-2 session, macOS 27.2 (Darwin 27.2.0), `xcrun swiftc` = Apple Swift 6.4,
// screen LOCKED. The file ran four times; every structural line was identical between runs and only the
// mid-flight bitmap boxes moved (by up to ~20 px). One run's output, verbatim:
//
//   === P1 both present, both sources
//     t~0.02 s: red none | blue x 600-799 y 280-399
//     t~0.37 s: red none | blue x 600-799 y 280-399
//     t~0.73 s: red none | blue x 600-799 y 280-399
//   === P2 both present, B isSource false
//     t~0.02 s: red none | blue x 0-99 y 0-59
//     t~0.37 s: red none | blue x 0-99 y 0-59
//     t~0.73 s: red none | blue x 0-99 y 0-59
//   === P3 both present, A isSource false
//     t~0.02 s: red none | blue x 600-799 y 280-399
//     t~0.37 s: red none | blue x 600-799 y 280-399
//     t~0.73 s: red none | blue x 600-799 y 280-399
//   === P4 both present, neither isSource
//     t~0.02 s: red x 0-99 y 0-59 | blue x 600-799 y 280-399
//     t~0.37 s: red x 0-99 y 0-59 | blue x 600-799 y 280-399
//     t~0.73 s: red x 0-99 y 0-59 | blue x 600-799 y 280-399
//   === P5 both present, B isSource false, .position
//     t~0.02 s: red none | blue x 0-149 y 0-89
//     t~0.37 s: red none | blue x 0-149 y 0-89
//     t~0.73 s: red none | blue x 0-149 y 0-89
//   === P6 both present, B isSource false, .size
//     t~0.02 s: red x 0-99 y 0-59 | blue x 600-799 y 280-399
//     t~0.37 s: red x 0-99 y 0-59 | blue x 600-799 y 280-399
//     t~0.73 s: red x 0-99 y 0-59 | blue x 600-799 y 280-399
//   === S1 swap default
//     t~0.02 s: red x 13-112 y 7-66 | blue x 0-112 y 0-66
//     t~0.37 s: red none | blue x 160-359 y 66-185
//     t~0.73 s: red none | blue x 406-605 y 186-305
//   === S2 swap, old .identity
//     t~0.02 s: red none | blue x 600-799 y 280-399
//     t~0.37 s: red none | blue x 600-799 y 280-399
//     t~0.73 s: red none | blue x 600-799 y 280-399
//   === S3 swap, new .identity
//     t~0.02 s: red none | blue x 0-113 y 0-66
//     t~0.37 s: red none | blue x 159-358 y 66-185
//     t~0.73 s: red none | blue x 405-604 y 185-304
//   === S4 swap both .identity
//     t~0.02 s: red none | blue x 600-799 y 280-399
//     t~0.37 s: red none | blue x 600-799 y 280-399
//     t~0.73 s: red none | blue x 600-799 y 280-399
//   === S5 .position, old .identity
//     t~0.02 s: red none | blue x 600-799 y 280-399
//     t~0.37 s: red none | blue x 600-799 y 280-399
//     t~0.73 s: red none | blue x 600-799 y 280-399
//   === S6 .size, old .identity
//     t~0.02 s: red none | blue x 600-799 y 280-399
//     t~0.37 s: red none | blue x 600-799 y 280-399
//     t~0.73 s: red none | blue x 600-799 y 280-399
//   === S7 newcomer isSource false, old .identity
//     t~0.02 s: red none | blue x 600-799 y 280-399
//     t~0.37 s: red none | blue x 600-799 y 280-399
//     t~0.73 s: red none | blue x 600-799 y 280-399
//   === S8 old isSource false, old .identity
//     t~0.02 s: red none | blue x 600-799 y 280-399
//     t~0.37 s: red none | blue x 600-799 y 280-399
//     t~0.73 s: red none | blue x 600-799 y 280-399
//   === S9 .position default transitions
//     t~0.02 s: red x 13-112 y 6-65 | blue x 0-162 y 0-95
//     t~0.37 s: red none | blue x 192-391 y 85-204
//     t~0.73 s: red none | blue x 421-620 y 195-314
//   === S10 .size default transitions
//     t~0.02 s: red x 0-99 y 0-59 | blue x 600-799 y 280-399
//     t~0.37 s: red x 0-99 y 0-59 | blue x 600-799 y 280-399
//     t~0.73 s: red x 0-99 y 0-59 | blue x 600-799 y 280-399
//   === S11 newcomer isSource false, default transitions
//     t~0.02 s: red x 14-113 y 7-66 | blue x 0-113 y 0-66
//     t~0.37 s: red none | blue x 160-359 y 66-185
//     t~0.73 s: red none | blue x 406-605 y 186-305
//   === S12 old isSource false, default transitions
//     t~0.02 s: red x 13-112 y 7-66 | blue x 599-799 y 280-399
//     t~0.37 s: red x 260-359 y 126-185 | blue x 600-799 y 279-399
//     t~0.73 s: red x 507-606 y 246-305 | blue x 600-799 y 279-399
//   === S13 neither isSource, default transitions
//     t~0.02 s: red x 0-99 y 0-59 | blue x 600-799 y 280-399
//     t~0.37 s: red x 0-99 y 0-59 | blue x 600-799 y 280-399
//     t~0.73 s: red x 0-99 y 0-59 | blue x 600-799 y 280-399

import SwiftUI
import AppKit
import ObjectiveC

// ---------------------------------------------------------------- recorder
nonisolated(unsafe) var seen: Set<String> = []
nonisolated(unsafe) var layoutWidths: Set<String> = []
nonisolated(unsafe) var tagsOnly = false
nonisolated(unsafe) var capturedBinding: Binding<Double>?
struct StateBindingView: View {
    let kind: Int
    @State var v = 0.0
    var body: some View {
        let b: Binding<Double> = kind == 1 ? $v.animation(A) : kind == 2 ? $v.transaction(Transaction(animation: A)) : $v
        DispatchQueue.main.async { capturedBinding = b }
        return Color.red.frame(width: 50, height: 20).opacity(1 - v)
    }
}

struct Rec: CustomAnimation {
    let tag: String
    func animate<V: VectorArithmetic>(value: V, time: TimeInterval, context: inout AnimationContext<V>) -> V? {
        seen.insert(tagsOnly ? tag : "\(tag) \(short(V.self)) \(fmt(value))")
        if time > 0.15 { return nil }
        return value.scaled(by: time / 0.15)
    }
}
func fmt<V>(_ v: V) -> String {
    let s = String(describing: v)
    let colour = s.contains("ResolvedHDR") ? "colour " : ""
    let re = try! NSRegularExpression(pattern: "-?[0-9]+\\.[0-9]+(e-?[0-9]+)?")
    let nums = re.matches(in: s, range: NSRange(s.startIndex..., in: s)).map { m -> String in
        let d = Double(String(s[Range(m.range, in: s)!]))!
        return String(format: "%.3f", abs(d) < 0.0005 ? 0 : d)
    }
    return colour + "[" + nums.joined(separator: ", ") + "]"
}
func short(_ t: Any.Type) -> String {
    let s = String(describing: t)
    if s.contains("KeyedAnimatableArray") { return "ShapeStyle" }
    return s.replacingOccurrences(of: "AnimatablePair", with: "P").replacingOccurrences(of: "CGFloat", with: "F")
}
let A = Animation(Rec(tag: "A"))
let B = Animation(Rec(tag: "B"))

// A custom Layout that records the width it is proposed and answers it.
struct WidthLog: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let w = proposal.width ?? 0
        layoutWidths.insert(String(format: "%.1f", w))
        return CGSize(width: w, height: 20)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {}
}

// ---------------------------------------------------------------- model
@MainActor final class M: ObservableObject {
    @Published var v = 0.0      // the animated value
    @Published var u = 0.0      // an unrelated value
    @Published var flag = false
    @Published var items = [1, 2]
    @Published var a = 0.0
    @Published var b = 0.0
}

// ---------------------------------------------------------------- reduce motion swizzle
nonisolated(unsafe) var forceReduceMotion = false
final class RMSwizzle: NSObject {
    @objc dynamic var fakeReduceMotion: Bool { forceReduceMotion }
}
func installReduceMotionSwizzle() {
    let cls: AnyClass = NSWorkspace.self
    let orig = class_getInstanceMethod(cls, #selector(getter: NSWorkspace.accessibilityDisplayShouldReduceMotion))!
    let repl = class_getInstanceMethod(RMSwizzle.self, #selector(getter: RMSwizzle.fakeReduceMotion))!
    method_setImplementation(orig, method_getImplementation(repl))
}

// ---------------------------------------------------------------- harness
nonisolated(unsafe) var rmReads: [String] = []
nonisolated(unsafe) var txReads: [String] = []
struct RMReader: View {
    @Environment(\.accessibilityReduceMotion) var rm
    var body: some View { Color.clear.frame(width: 1, height: 1).onAppear { rmReads.append("appear \(rm)") }.onChange(of: rm) { _, n in rmReads.append("change \(n)") } }
}

struct Root<C: View>: View { @ObservedObject var m: M; let c: (M) -> C
    var body: some View { ZStack(alignment: .topLeading) { c(m) }.frame(width: 400, height: 200, alignment: .topLeading) } }

@MainActor func spin(_ s: Double) { RunLoop.main.run(until: Date().addingTimeInterval(s)) }

@MainActor func arm<Content: View>(_ name: String, _ content: @escaping (M) -> Content,
                                    setup: (M) -> Void = { _ in },
                                    change: (M) -> Void) {
    let m = M()
    setup(m)
    let host = NSHostingView(rootView: Root(m: m, c: content))
    let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 200), styleMask: [.titled], backing: .buffered, defer: false)
    win.contentView = host
    win.orderFrontRegardless()
    spin(0.25)
    seen.removeAll(); layoutWidths.removeAll()
    change(m)
    spin(0.5)
    print("=== \(name)")
    if seen.isEmpty { print("  (nothing animated)") }
    for l in seen.sorted() { print("  \(l)") }
    win.orderOut(nil)
    win.contentView = nil
    spin(0.05)
}

@MainActor func tx(_ name: String, _ t: AnyTransition?, insert: Bool, animated: Bool = true) {
    arm("\(name) \(insert ? "insert" : "remove")", { m in
        ZStack(alignment: .topLeading) {
            Color.blue.frame(width: 30, height: 10)
            if m.flag {
                if let t { Color.red.frame(width: 50, height: 30).transition(t) } else { Color.red.frame(width: 50, height: 30) }
            }
        }
    }, setup: { m in m.flag = !insert }, change: { m in
        if animated { withAnimation(A) { m.flag = insert } } else { m.flag = insert }
    })
}
@MainActor func bbox(_ rep: NSBitmapImageRep) -> String {
    var r = (x0: 9999, y0: 9999, x1: -1, y1: -1), b = r
    for y in 0..<rep.pixelsHigh { for x in 0..<rep.pixelsWide {
        guard let c = rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { continue }
        let (rr, gg, bb) = (c.redComponent * 255, c.greenComponent * 255, c.blueComponent * 255)
        if rr > gg + 60 && rr > bb + 60 { r = (min(r.x0, x), min(r.y0, y), max(r.x1, x), max(r.y1, y)) }
        if bb > rr + 60 && bb > gg + 60 { b = (min(b.x0, x), min(b.y0, y), max(b.x1, x), max(b.y1, y)) }
    } }
    func s(_ v: (x0: Int, y0: Int, x1: Int, y1: Int)) -> String { v.x1 < 0 ? "none" : "x \(v.x0)-\(v.x1) y \(v.y0)-\(v.y1)" }
    return "red \(s(r)) | blue \(s(b))"
}
@MainActor func snap<Content: View>(_ name: String, _ content: @escaping (M) -> Content, setup: (M) -> Void, change: (M) -> Void) {
    let m = M(); setup(m)
    let host = NSHostingView(rootView: Root(m: m, c: content))
    let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 200), styleMask: [.borderless], backing: .buffered, defer: false)
    win.contentView = host; win.orderFrontRegardless(); spin(0.25)
    let t0 = Date()
    change(m)
    var reps: [(Double, NSBitmapImageRep)] = []
    for wait in [0.02, 0.35, 0.35] {
        spin(wait)
        let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
        host.cacheDisplay(in: host.bounds, to: rep)
        reps.append((Date().timeIntervalSince(t0), rep))
    }
    print("=== \(name)")
    for (i, (_, rep)) in reps.enumerated() { print("  \(["t~0.02", "t~0.37", "t~0.73"][i]) s: " + bbox(rep)) }
    win.orderOut(nil); win.contentView = nil; spin(0.05)
}
// ---------------------------------------------------------------- frames
nonisolated(unsafe) var frames: [String] = []
nonisolated(unsafe) var phases: Set<String> = []
func fmtR(_ r: CGRect) -> String { String(format: "[%.1f, %.1f, %.1f, %.1f]", r.minX, r.minY, r.width, r.height) }
extension View {
    func tag(_ t: String) -> some View {
        onGeometryChange(for: CGRect.self, of: { $0.frame(in: .global) }) { r in frames.append("\(t) \(fmtR(r))") }
    }
}
func printFrames() {
    var seenTags: [String: [String]] = [:]
    for f in frames { let t = String(f.prefix { $0 != " " }); seenTags[t, default: []].append(String(f.dropFirst(t.count + 1))) }
    for t in seenTags.keys.sorted() {
        let v = seenTags[t]!
        print("  frame \(t): first \(v.first!) last \(v.last!) (\(v.count) reports)")
    }
}

// ---------------------------------------------------------------- matched geometry arms
struct Swap: View {
    @Namespace var ns
    @ObservedObject var m: M
    var props: MatchedGeometryProperties = .frame
    var srcA = true, srcB = true
    var both = false
    var tA: AnyTransition? = nil
    var tB: AnyTransition? = nil
    var body: some View {
        ZStack(alignment: .topLeading) {
            if both || !m.flag {
                let a = Color.red.frame(width: 50, height: 30).matchedGeometryEffect(id: "x", in: ns, properties: props, isSource: srcA).tag("A")
                if let tA { a.transition(tA) } else { a }
            }
            if both || m.flag {
                let b = Color.blue.frame(width: 100, height: 60).matchedGeometryEffect(id: "x", in: ns, properties: props, isSource: srcB)
                    .tag("B").frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                if let tB { b.transition(tB) } else { b }
            }
        }
    }
}
@MainActor func mg(_ name: String, animated: Bool = true, setup: (M) -> Void = { _ in }, _ make: @escaping (M) -> Swap) {
    frames.removeAll()
    arm(name, { m in make(m) }, setup: { m in setup(m) }, change: { m in
        if animated { withAnimation(A) { m.flag.toggle() } } else { m.flag.toggle() }
    })
    printFrames()
}
// ---------------------------------------------------------------- transition protocol
struct Scaler: Transition {
    func body(content: Content, phase: TransitionPhase) -> some View {
        phases.insert("\(phase)")
        return content.scaleEffect(phase.isIdentity ? 1 : 0.5).opacity(phase.isIdentity ? 1 : 0)
    }
}
struct Mover: Transition {
    func body(content: Content, phase: TransitionPhase) -> some View {
        content.offset(x: phase == .willAppear ? -40 : phase == .didDisappear ? 40 : 0)
    }
}

@MainActor func sw(_ n: String, _ mk: @escaping (M) -> Swap) { snap(n, { mk($0) }, setup: { $0.flag = false }, change: { m in withAnimation(.linear(duration: 1.0)) { m.flag = true } }) }
@MainActor func st(_ n: String, _ mk: @escaping (M) -> Swap) { snap(n, { mk($0) }, setup: { $0.flag = false }, change: { _ in }) }
MainActor.assumeIsolated {
NSApplication.shared.setActivationPolicy(.accessory)
st("P1 both present, both sources") { Swap(m: $0, both: true) }
st("P2 both present, B isSource false") { Swap(m: $0, srcB: false, both: true) }
st("P3 both present, A isSource false") { Swap(m: $0, srcA: false, both: true) }
st("P4 both present, neither isSource") { Swap(m: $0, srcA: false, srcB: false, both: true) }
st("P5 both present, B isSource false, .position") { Swap(m: $0, props: .position, srcB: false, both: true) }
st("P6 both present, B isSource false, .size") { Swap(m: $0, props: .size, srcB: false, both: true) }
sw("S1 swap default") { Swap(m: $0) }
sw("S2 swap, old .identity") { Swap(m: $0, tA: .identity) }
sw("S3 swap, new .identity") { Swap(m: $0, tB: .identity) }
sw("S4 swap both .identity") { Swap(m: $0, tA: .identity, tB: .identity) }
sw("S5 .position, old .identity") { Swap(m: $0, props: .position, tA: .identity) }
sw("S6 .size, old .identity") { Swap(m: $0, props: .size, tA: .identity) }
sw("S7 newcomer isSource false, old .identity") { Swap(m: $0, srcB: false, tA: .identity) }
sw("S8 old isSource false, old .identity") { Swap(m: $0, srcA: false, tA: .identity) }
sw("S9 .position default transitions") { Swap(m: $0, props: .position) }
sw("S10 .size default transitions") { Swap(m: $0, props: .size) }
sw("S11 newcomer isSource false, default transitions") { Swap(m: $0, srcB: false) }
sw("S12 old isSource false, default transitions") { Swap(m: $0, srcA: false) }
sw("S13 neither isSource, default transitions") { Swap(m: $0, srcA: false, srcB: false) }
exit(0)
arm("C0 control: withAnimation(A) { v } on .frame(width: 100 + v)", { m in Color.red.frame(width: 100 + m.v, height: 20) },
    change: { m in withAnimation(A) { m.v = 200 } })

// MG: swap an old view for a newcomer with the same id. A = (0,0,50,30), B = (300,140,100,60).
mg("MG1 if/else swap, same id, .frame, withAnimation(A), no .transition", setup: { $0.flag = false }) { Swap(m: $0) }
mg("MG1r reverse (B -> A)", setup: { $0.flag = true }) { Swap(m: $0) }
mg("MG1n the same swap with NO transaction", animated: false, setup: { $0.flag = false }) { Swap(m: $0) }
mg("MG2 properties .position", setup: { $0.flag = false }) { Swap(m: $0, props: .position) }
mg("MG3 properties .size", setup: { $0.flag = false }) { Swap(m: $0, props: .size) }
mg("MG4 newcomer isSource: false", setup: { $0.flag = false }) { Swap(m: $0, srcB: false) }
mg("MG5 old view isSource: false", setup: { $0.flag = false }) { Swap(m: $0, srcA: false) }
mg("MG6 neither isSource", setup: { $0.flag = false }) { Swap(m: $0, srcA: false, srcB: false) }
for (n, p, sa, sb) in [("MG1i .frame", MatchedGeometryProperties.frame, true, true), ("MG2i .position", .position, true, true), ("MG3i .size", .size, true, true), ("MG4i newcomer isSource false", .frame, true, false), ("MG5i old isSource false", .frame, false, true)] {
    mg("\(n), old view .transition(.identity) (removed instantly)", setup: { $0.flag = false }) { Swap(m: $0, props: p, srcA: sa, srcB: sb, tA: .identity) }
}
mg("MG7 swap with .transition(.opacity) on both", setup: { $0.flag = false }) { Swap(m: $0, tA: .opacity, tB: .opacity) }
mg("MG8 swap with .transition(.identity) on both", setup: { $0.flag = false }) { Swap(m: $0, tA: .identity, tB: .identity) }
mg("MG9 both present at once (A, B sources), no change in presence", setup: { _ in }) { Swap(m: $0, both: true) }
mg("MG10 both present, B isSource: false (B placed where?)", setup: { _ in }) { Swap(m: $0, srcB: false, both: true) }
mg("MG11 both present, A isSource: false", setup: { _ in }) { Swap(m: $0, srcA: false, both: true) }
arm("MG12 removal only (no newcomer)", { m in
    MGOne(m: m) }, setup: { $0.flag = true }, change: { m in withAnimation(A) { m.flag = false } })
printFrames()
arm("MG13 insertion only (no old view)", { m in MGOne(m: m) }, setup: { $0.flag = false }, change: { m in withAnimation(A) { m.flag = true } })

// contentTransition on Text
@MainActor func ct(_ name: String, _ t: ContentTransition?) {
    arm(name, { m in
        let s = Text(m.v > 0 ? "9876" : "1234").font(.system(size: 20))
        return Group { if let t { s.contentTransition(t) } else { s } }.frame(width: 100, height: 30)
    }, change: { m in withAnimation(A) { m.v = 1 } })
}
ct("CT0 no contentTransition (Text 1234 -> 9876)", nil)
ct("CT1 .identity", .identity)
ct("CT2 .opacity", .opacity)
ct("CT3 .interpolate", .interpolate)
ct("CT4 .numericText()", .numericText())

// Transition protocol
phases.removeAll()
tx("TP1 custom Transition scale+opacity", AnyTransition(Scaler()), insert: true)
tx("TP1 custom Transition scale+opacity", AnyTransition(Scaler()), insert: false)
print("  phases seen: \(phases.sorted())")
tx("TP2 custom Transition offset", AnyTransition(Mover()), insert: true)
tx("TP2 custom Transition offset", AnyTransition(Mover()), insert: false)
tx("TP3 .blurReplace", AnyTransition(.blurReplace), insert: true)
tx("TP3 .blurReplace", AnyTransition(.blurReplace), insert: false)
tx("TP4 .modifier(active: scale 0.5, identity: scale 1)", AnyTransition.modifier(active: ScaleMod(s: 0.5), identity: ScaleMod(s: 1)), insert: true)
exit(0)
}
struct ScaleMod: ViewModifier { let s: Double; func body(content: Content) -> some View { content.scaleEffect(s) } }
struct MGOne: View {
    @Namespace var ns
    @ObservedObject var m: M
    var body: some View {
        ZStack(alignment: .topLeading) {
            if m.flag { Color.blue.frame(width: 100, height: 60).matchedGeometryEffect(id: "x", in: ns).tag("B") }
        }
    }
}
