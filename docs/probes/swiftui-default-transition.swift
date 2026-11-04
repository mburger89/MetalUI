// SwiftUI probe: the DEFAULT transition — what SwiftUI does to a view that an `if`, an `if`/`else`, a `ForEach`,
// an `.id` change or an `AnyView` swap inserts or removes when NO `.transition` is written. Round 4 item R4-3
// (divergence 98's evidence; 897/898/828 are recorded in record 204). Ruling prefix `XF-`, decisions
// docs/superpowers/2026-11-03-default-transition-decisions.md, plan record docs/record/204-default-crossfade-probe.md.
//
// HOW TO RUN (Apple's toolchain, COMPILED; the `/usr/bin/swift` JIT form does not link on macOS 27, SA-O):
//
//   xcrun swiftc docs/probes/swiftui-default-transition.swift -o /tmp/xfprobe
//   /tmp/xfprobe 2>&1 | grep -v 'Connection\]'
//   grep -v '^  ~' output   # the STABLE lines; the `~` lines are timing, see below
//
// HOW IT READS. The recorder is the one of swiftui-transactions-animation.swift (`Rec`: a `CustomAnimation` that
// records the TYPE of every animatable value SwiftUI hands it and its delta, then runs a ramp), with two changes
// the plan asked for: (1) an ANIMATOR COUNT, because that file's `seen` is a Set and printed one line for two
// animators of the same shape (plan finding 8): the first `animate` call of each animator is recorded through
// `context.state` (an `AnimationStateKey`), and a line's `xN` is the number of animators, not of frames; (2) every
// log is BUFFERED and printed after the arm (swiftui-lifecycle.swift's AV6c showed per-tick printing slows the
// animation clock). `A`/`B` ramp for 0.15 s, `L` for 1.2 s (the long ramp the bitmap arms sample), `S` for 0.6 s
// (the lifecycle arms, T1's duration).
//
// INSTRUMENTS AND WHAT THEY CANNOT SEPARATE.
//   - the recorder says which values reached an animation (type, delta, count). It does not say what is drawn,
//     z-order or blend, and a value reaching an animation does not prove the view faded on screen.
//   - `cacheDisplay` of the hosting view (XF1, XF10): swiftui-matched-geometry.swift's header says it draws the model
//     layer, so it shows GEOMETRY but possibly not an opacity Core Animation is fading. XF1's CONTROL is a plain
//     `.opacity(0 -> 1)` under the same long ramp: if the bitmap shows intermediate values for it the instrument sees
//     an animated opacity, and only then do the default-fade and z-order readings (XF10) mean anything.
//   - the CALayer read (XF2): the control is a static `.opacity(0.5)`; if no layer reads 0.5 the arm is dropped.
//   - `ImageRenderer` is NOT used (one snapshot, no animation clock; draws no glass).
//   - the lifecycle timing (XF7, XF8e) is a bucket: `early` (< 0.3 s after the change) or `late` (>= 0.5 s, i.e. after
//     the 0.6 s ramp); the raw milliseconds are `~` lines.
//
// STABLE VERSUS TIMING OUTPUT. Lines that start `  ~` are timing (wall-clock offsets of a sample, the animation clock
// at a sample, raw milliseconds); everything else is expected to be identical between two runs and was compared.
//
// CONTROLS (re-taken in this file through the new recorder, same session, beside the recorded lines of
// swiftui-transactions-animation.swift X0/W10/X15/C0 and swiftui-lifecycle.swift T1):
//   XF0  the recorder is reached and ticks; no transaction records nothing; one view is one animator; an if/else is two.
//
// RECORDED 2026-11-03 by R4-3 PR A, macOS 27.2 (26B123), Apple Swift 6.4.2, compiled with `xcrun swiftc`. Screen LOCKED
// (`CGSSessionScreenIsLocked = 1`, `displayAsleep main: 0`, `preflightScreenCaptureAccess: false`, one 1920x1080 screen); the
// desktop was shared. Run twice, exit 0, stderr empty after the `Connection]` filter: 423 lines each, the stable (non-`~`)
// lines identical (`diff` empty), the `~` lines differ by a few RGB units and 0.01 s. Run 1 is kept whole in
// docs/probes/swiftui-default-transition-run.txt. CONTROLS, same session: swiftui-transactions-animation.swift run twice, 227
// lines each, byte-identical and equal to its recorded 227 (C0 geometry [0, 0, 200, 0]; X0 insert +1 and remove -1; W10 -1 and
// +1; X15 +1; X15b nothing); swiftui-lifecycle.swift T1 `disappear x` only after the 1.0 s spin. XF0 re-takes C0, C1, X0, W10, X15
// and X15b through the new recorder and reads the same. READING (every item MEASURED unless it says so; the lines are in the
// run file):
//   XF0  recorder valid. One view under a changed opacity is ONE animator; an if/else swap is TWO (-1 and +1).
//   XF1  the bitmap SEES an animated opacity: control `.opacity(0 -> 1)` over a white `.background` reads a linear ramp
//        G 240, 225, 210, 194, 178 ... 91 (the colour-managed red is (255, 91, 86)); default and `.transition(.opacity)`
//        INSERTION read the same ramp, `.transition(.identity)` insertion is full red at the first sample; default and
//        `.transition(.opacity)` REMOVAL ramp back to white (m m m m m m m m m W W W), `.identity` removal is white at once.
//        **A white backdrop that is a SIBLING leaf hid the removal ghost entirely** (an earlier run read W at every sample): the
//        ghost sits below it (XF2z); the numbers above are with the backdrop as `.background`.
//   XF2  the layer tree exists: static `.opacity(0.5)` reads a CALayer of 50x30 with opacity 0.50; an animated one reads 0.33 at
//        0.4 s of a 1.2 s ramp; a default insertion reads 0.33 and a default or `.opacity` removal 0.67 (the leaver is a LAYER with
//        presentation opacity 0.67). Control valid.
//   XF3  `X0` in a VStack, HStack, a root Group and a bare ZStack child: opacity +1 / -1, one animator, plus the container's own
//        geometry shift of the sibling (VStack [0, +-30], HStack [+-50, 0]). Container independent.
//   XF4  `if f { A; B }`: **two** opacity animators (`x2`), insert and remove; in a VStack plus one sibling-shift geometry.
//   XF5  `if f { A.transition(.move(edge: .leading)); B }`: the annotated member animates its OWN move ([50, 0] / [-50, 0]) and
//        **the unannotated member still fades (one opacity animator, +1 / -1)**; with `.identity` on A only B fades (XF5b).
//   XF6  an unannotated ForEach insert or remove: ONE opacity animator (+1 / -1) for the one element; in a VStack the shifting
//        siblings add their geometry.
//   XF7  `.id(k)` 0 -> 1: **both** `-1` and `+1` opacity animators; under a 0.6 s ramp `appear x early`, `disappear x late` (the old
//        view's `onDisappear` waits for the animation). A changed id IS a cross-fade. Control: an unannotated `if` removal under the
//        same ramp reads `-1` and `disappear x late`.
//   XF8  **an `AnyView` swap records NOTHING (XF8a, XF8b, with and without `.transition(.opacity)` inside); `if f { AnyView(WA) }`
//        records +1 / -1 (XF8c); the same-type swap nothing (XF8d); XF8e/XF8f: `disappear A early`, `appear B early`** (disappear BEFORE
//        appear, no delay): a swap is instant, the fade does not reach it.
//   XF9  first appearance under a forced animation: nothing. `scrollTo(150)` under `withAnimation(A)` in a `LazyVStack` (origin 0 ->
//        2400) and in a `List` (0 -> 3610): nothing animated, no row fades. `List` data insertion: nothing reached the recorder
//        (an NSTableView row animation would not: UNMEASURED).
//   XF10 (leaves given `.opacity(0.99)` so each is a layer; the white backdrop a `.background`): a red 50x30 leaver overlapping a blue
//        30x10 sibling at (10, 5). Red BELOW blue (XF10a, XF10c): the overlap stays pure blue at every sample (ghost under blue).
//        **Red ABOVE blue (XF10b): the overlap ALSO reads pure blue at every sample, from the first, though the red covered it at
//        rest** (`before: (255, 92, 88)`). XF2zb reads the tree: `[background, GHOST red 0.66, blue, (green)]`: the ghost layer is the
//        FIRST sublayer above the background whatever its original position (also with a third, always-present leaf above red, and
//        in a VStack with red first). So the removal is neither in place (originally above its sibling it drops below it) nor on top: it
//        is at the BOTTOM of the sibling stack. Annotated (`.transition(.opacity)`) and unannotated read the same. Insertion (XF10d)
//        stays in place (overlap blue).
//   XF11 under the Reduce Motion swizzle (reader reads `appear true`) the default insert +1 and remove -1 are unchanged.
// NOT MEASURED: the look in a real window (no pixels of the window server, locked); per-primitive alpha through a card (205);
// the dip of an if/else swap; `List` row animation; a real backing scale (1.0).

import SwiftUI
import AppKit
import ObjectiveC

// ---------------------------------------------------------------- recorder
nonisolated(unsafe) var animators: [String] = []
nonisolated(unsafe) var maxTime = 0.0
nonisolated(unsafe) var events: [(String, Double)] = []
nonisolated(unsafe) var changeAt = Date()
nonisolated(unsafe) var currentHost: NSView?
nonisolated(unsafe) var proxyBox: ScrollViewProxy?
nonisolated(unsafe) var notes: [String] = []

struct SeenKey: AnimationStateKey { static var defaultValue: Bool { false } }

struct Rec: CustomAnimation {
    let tag: String
    var duration = 0.15
    func animate<V: VectorArithmetic>(value: V, time: TimeInterval, context: inout AnimationContext<V>) -> V? {
        maxTime = max(maxTime, time)
        if !context.state[SeenKey.self] {
            context.state[SeenKey.self] = true
            animators.append("\(tag) \(short(V.self)) \(fmt(value))")
        }
        if time > duration { return nil }
        return value.scaled(by: time / duration)
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
let L = Animation(Rec(tag: "L", duration: 1.2))
let S = Animation(Rec(tag: "S", duration: 0.6))

func ev(_ s: String) { events.append((s, Date().timeIntervalSince(changeAt))) }

// ---------------------------------------------------------------- model and harness
@MainActor final class M: ObservableObject {
    @Published var v = 0.0
    @Published var flag = false
    @Published var items = [1, 2]
    @Published var k = 0
}
struct Root<C: View>: View { @ObservedObject var m: M; let c: (M) -> C
    var body: some View { ZStack(alignment: .topLeading) { c(m) }.frame(width: 400, height: 200, alignment: .topLeading) } }

@MainActor func spin(_ s: Double) { RunLoop.main.run(until: Date().addingTimeInterval(s)) }

@MainActor func printAnimators(_ ls: [String]) {
    if ls.isEmpty { print("  (nothing animated)"); return }
    var counts: [String: Int] = [:]
    for l in ls { counts[l, default: 0] += 1 }
    for l in counts.keys.sorted() { print("  \(l) x\(counts[l]!)") }
}

/// Hosts `content`, runs `change` after a settle, spins `after` seconds, prints the animators that were reached.
@MainActor func arm<Content: View>(_ name: String, _ content: @escaping (M) -> Content,
                                    setup: (M) -> Void = { _ in },
                                    after: Double = 0.5,
                                    change: (M) -> Void) {
    let m = M()
    setup(m)
    let host = NSHostingView(rootView: Root(m: m, c: content))
    let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 200), styleMask: [.titled], backing: .buffered, defer: false)
    win.contentView = host
    currentHost = host
    win.orderFrontRegardless()
    spin(0.25)
    animators.removeAll(); events.removeAll(); maxTime = 0; notes.removeAll()
    changeAt = Date()
    change(m)
    spin(after)
    print("=== \(name)")
    printAnimators(animators)
    for n in notes { print("  \(n)") }
    win.orderOut(nil)
    win.contentView = nil
    currentHost = nil
    spin(0.05)
}

// ---------------------------------------------------------------- pixels
@MainActor func pixels(_ host: NSView, _ pts: [(Int, Int)]) -> [(Int, Int, Int)] {
    guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return pts.map { _ in (-1, -1, -1) } }
    host.cacheDisplay(in: host.bounds, to: rep)
    let sc = Double(rep.pixelsWide) / Double(host.bounds.width)
    return pts.map { p in
        guard let c = rep.colorAt(x: Int(Double(p.0) * sc + sc / 2), y: Int(Double(p.1) * sc + sc / 2))?.usingColorSpace(.deviceRGB) else { return (-1, -1, -1) }
        return (Int((c.redComponent * 255).rounded()), Int((c.greenComponent * 255).rounded()), Int((c.blueComponent * 255).rounded()))
    }
}
/// `cacheDisplay` reads the colour-managed values, so `Color.red` is (255,91,86) and `Color.blue` (0,165,255) here (the
/// `before:` lines show them). W = white (G >= 250), R = full red (G <= 95), m = between.
func redOverWhite(_ p: (Int, Int, Int)) -> String { p.1 < 0 ? "?" : p.1 >= 250 ? "W" : p.1 <= 95 ? "R" : "m" }
/// Bl = pure blue (0,165,255 +-8), W = white, Rd = full red, m = anything else (a blend).
func overBlue(_ p: (Int, Int, Int)) -> String {
    if p.2 < 0 { return "?" }
    if p.0 <= 8 && abs(p.1 - 165) <= 8 && p.2 >= 247 { return "Bl" }
    if p.0 >= 247 && p.1 >= 247 && p.2 >= 247 { return "W" }
    if p.0 >= 247 && abs(p.1 - 91) <= 8 && abs(p.2 - 86) <= 8 { return "Rd" }
    return "m"
}

/// Like `arm`, but samples bitmap pixels every 0.12 s for `n` samples after the change. Prints the recorder lines,
/// then `shape:` (the classification per sample; stable) and `~` lines (timing and raw RGB).
@MainActor func armPx<Content: View>(_ name: String, _ content: @escaping (M) -> Content,
                                      setup: (M) -> Void = { _ in },
                                      points: [(Int, Int)], classify: [(String, ((Int, Int, Int)) -> String)],
                                      n: Int = 12, change: (M) -> Void) {
    let m = M()
    setup(m)
    let host = NSHostingView(rootView: Root(m: m, c: content))
    let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 200), styleMask: [.titled], backing: .buffered, defer: false)
    win.contentView = host
    win.orderFrontRegardless()
    spin(0.3)
    animators.removeAll(); maxTime = 0
    let before = pixels(host, points)
    changeAt = Date()
    change(m)
    var shapes: [[String]] = Array(repeating: [], count: points.count)
    var timing: [String] = []
    for _ in 0..<n {
        spin(0.12)
        let px = pixels(host, points)
        for (i, p) in px.enumerated() { shapes[i].append(classify[i].1(p)) }
        timing.append(String(format: "t=%.2f anim=%.2f ", Date().timeIntervalSince(changeAt), maxTime) + px.map { "(\($0.0),\($0.1),\($0.2))" }.joined(separator: " "))
    }
    print("=== \(name)")
    printAnimators(animators)
    print("  before: " + before.map { "(\($0.0),\($0.1),\($0.2))" }.joined(separator: " "))
    for (i, c) in classify.enumerated() { print("  shape \(c.0): " + shapes[i].joined(separator: " ")) }
    for t in timing { print("  ~ \(t)") }
    win.orderOut(nil)
    win.contentView = nil
    spin(0.05)
}

/// A lifecycle arm: logs appear/disappear with the time since the change, spins `after`, prints the events in order
/// (stable) and `~` raw times, plus the early/late bucket of every disappear.
@MainActor func armEv<Content: View>(_ name: String, _ content: @escaping (M) -> Content,
                                      setup: (M) -> Void = { _ in },
                                      after: Double = 1.0,
                                      change: (M) -> Void) {
    let m = M()
    setup(m)
    let host = NSHostingView(rootView: Root(m: m, c: content))
    let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 200), styleMask: [.titled], backing: .buffered, defer: false)
    win.contentView = host
    win.orderFrontRegardless()
    spin(0.3)
    animators.removeAll(); events.removeAll(); maxTime = 0
    changeAt = Date()
    change(m)
    spin(after)
    print("=== \(name)")
    printAnimators(animators)
    for e in events {
        let bucket = e.1 < 0.3 ? "early" : e.1 >= 0.5 ? "late" : "mid"
        print("  \(e.0) \(bucket)")
    }
    for e in events { print("  ~ \(e.0) \(Int(e.1 * 1000)) ms") }
    win.orderOut(nil)
    win.contentView = nil
    spin(0.05)
}

// ---------------------------------------------------------------- views
struct Leaf: View {
    let name: String; let colour: Color
    var body: some View { colour.frame(width: 50, height: 30).onAppear { ev("appear \(name)") }.onDisappear { ev("disappear \(name)") } }
}
struct WA: View { var body: some View { Color.red.frame(width: 50, height: 30) } }
struct WB: View { var body: some View { Color.blue.frame(width: 50, height: 30) } }
struct LA: View { var body: some View { Color.red.frame(width: 50, height: 30).onAppear { ev("appear A") }.onDisappear { ev("disappear A") } } }
struct LB: View { var body: some View { Color.blue.frame(width: 50, height: 30).onAppear { ev("appear B") }.onDisappear { ev("disappear B") } } }
struct ProxyGrab<C: View>: View {
    @ViewBuilder let c: () -> C
    var body: some View { ScrollViewReader { p in c().onAppear { proxyBox = p } } }
}

// ---------------------------------------------------------------- reduce motion swizzle (as swiftui-transactions-animation.swift)
nonisolated(unsafe) var forceReduceMotion = false
nonisolated(unsafe) var rmReads: [String] = []
final class RMSwizzle: NSObject { @objc dynamic var fakeReduceMotion: Bool { forceReduceMotion } }
func installReduceMotionSwizzle() {
    let cls: AnyClass = NSWorkspace.self
    let orig = class_getInstanceMethod(cls, #selector(getter: NSWorkspace.accessibilityDisplayShouldReduceMotion))!
    let repl = class_getInstanceMethod(RMSwizzle.self, #selector(getter: RMSwizzle.fakeReduceMotion))!
    method_setImplementation(orig, method_getImplementation(repl))
}
struct RMReader: View {
    @Environment(\.accessibilityReduceMotion) var rm
    var body: some View { Color.clear.frame(width: 1, height: 1).onAppear { rmReads.append("appear \(rm)") } }
}

// ---------------------------------------------------------------- arms
/// `if flag { red }` over a blue 30x10 corner tile in a ZStack: the X0 shape of swiftui-transactions-animation.swift.
@MainActor func zif(_ name: String, _ anim: Animation? = A, insert: Bool, transition: AnyTransition? = nil) {
    arm("\(name) \(insert ? "insert" : "remove")", { m in
        ZStack(alignment: .topLeading) {
            Color.blue.frame(width: 30, height: 10)
            if m.flag {
                if let transition { Color.red.frame(width: 50, height: 30).transition(transition) } else { Color.red.frame(width: 50, height: 30) }
            }
        }
    }, setup: { m in m.flag = !insert }, change: { m in
        if let anim { withAnimation(anim) { m.flag = insert } } else { m.flag = insert }
    })
}

MainActor.assumeIsolated {
NSApplication.shared.setActivationPolicy(.accessory)

// ---- XF0 controls
arm("XF0 C0' control: withAnimation(A) { v } on .frame(width: 100 + v)", { m in Color.red.frame(width: 100 + m.v, height: 20) },
    change: { m in withAnimation(A) { m.v = 200 } })
arm("XF0 C1' control: the same change with no transaction", { m in Color.red.frame(width: 100 + m.v, height: 20) },
    change: { m in m.v = 200 })
zif("XF0 X0' default", insert: true)
zif("XF0 X0' default", insert: false)
zif("XF0 X0' default with NO transaction", nil, insert: true)
zif("XF0 X0' default with NO transaction", nil, insert: false)
arm("XF0 W10' .clipped() added where it was absent (structure change)", { m in Group { if m.v == 0 { Color.red.frame(width: 50, height: 20) } else { Color.red.frame(width: 50, height: 20).clipped() } } },
    change: { m in withAnimation(A) { m.v = 1 } })
arm("XF0 X15' nested: if flag { VStack { red.transition(.move(edge: .leading)) } } insert", { m in
    ZStack(alignment: .topLeading) { Color.blue.frame(width: 30, height: 10); if m.flag { VStack { Color.red.frame(width: 50, height: 30).transition(.move(edge: .leading)) } } }
}, change: { m in withAnimation(A) { m.flag = true } })
arm("XF0 X15b' nested, with .transition(.identity) on the inserted VStack", { m in
    ZStack(alignment: .topLeading) { Color.blue.frame(width: 30, height: 10); if m.flag { VStack { Color.red.frame(width: 50, height: 30).transition(.move(edge: .leading)) }.transition(.identity) } }
}, change: { m in withAnimation(A) { m.flag = true } })
arm("XF0 one view under a changed opacity: one animator", { m in Color.red.frame(width: 50, height: 20).opacity(1 - m.v) },
    change: { m in withAnimation(A) { m.v = 0.5 } })
arm("XF0 if/else swap of two views: animator count", { m in
    ZStack(alignment: .topLeading) { if m.flag { Color.red.frame(width: 50, height: 30) } else { Color.blue.frame(width: 50, height: 30) } }
}, change: { m in withAnimation(A) { m.flag = true } })

/// A white backdrop that is NOT a sibling leaf (a sibling backdrop is a layer of its own, and a removal ghost sits below it;
/// see XF2z). `.background` draws behind every child.
func onWhite<C: View>(@ViewBuilder _ c: () -> C) -> some View {
    ZStack(alignment: .topLeading) { c() }.frame(width: 400, height: 200, alignment: .topLeading).background(Color.white)
}
// ---- XF1 the bitmap. The CONTROL first: a plain animated opacity, 0 -> 1, over white, under the long ramp.
let ptRed = [(25, 15)]
let clsRed: [(String, ((Int, Int, Int)) -> String)] = [("red-over-white at (25,15)", redOverWhite)]
armPx("XF1 control: red.opacity(0 -> 1) under L (an animated opacity the bitmap MUST show if it can)", { m in
    onWhite { Color.red.frame(width: 50, height: 30).opacity(m.v) }
}, points: ptRed, classify: clsRed, change: { m in withAnimation(L) { m.v = 1 } })
armPx("XF1 control: static red.opacity(0.5) over white", { m in
    onWhite { Color.red.frame(width: 50, height: 30).opacity(0.5) }
}, points: ptRed, classify: clsRed, n: 1, change: { _ in })
armPx("XF1 default insertion under L (no .transition)", { m in
    onWhite { if m.flag { Color.red.frame(width: 50, height: 30) } }
}, points: ptRed, classify: clsRed, change: { m in withAnimation(L) { m.flag = true } })
armPx("XF1 .transition(.opacity) insertion under L", { m in
    onWhite { if m.flag { Color.red.frame(width: 50, height: 30).transition(.opacity) } }
}, points: ptRed, classify: clsRed, change: { m in withAnimation(L) { m.flag = true } })
armPx("XF1 .transition(.identity) insertion under L", { m in
    onWhite { if m.flag { Color.red.frame(width: 50, height: 30).transition(.identity) } }
}, points: ptRed, classify: clsRed, change: { m in withAnimation(L) { m.flag = true } })
armPx("XF1 default removal under L (no .transition)", { m in
    onWhite { if m.flag { Color.red.frame(width: 50, height: 30) } }
}, setup: { m in m.flag = true }, points: ptRed, classify: clsRed, change: { m in withAnimation(L) { m.flag = false } })
armPx("XF1 .transition(.opacity) removal under L", { m in
    onWhite { if m.flag { Color.red.frame(width: 50, height: 30).transition(.opacity) } }
}, setup: { m in m.flag = true }, points: ptRed, classify: clsRed, change: { m in withAnimation(L) { m.flag = false } })
armPx("XF1 .transition(.identity) removal under L", { m in
    onWhite { if m.flag { Color.red.frame(width: 50, height: 30).transition(.identity) } }
}, setup: { m in m.flag = true }, points: ptRed, classify: clsRed, change: { m in withAnimation(L) { m.flag = false } })

// ---- XF2 the layer tree: is there a CALayer to read?
@MainActor func layerLines(_ l: CALayer, _ depth: Int, _ out: inout [String], all: Bool) {
    let pres = l.presentation()?.opacity
    let presS = pres.map { String(format: "%.2f", $0) } ?? "nil"
    if all || l.opacity != 1 || (pres ?? 1) != 1 || depth == 0 {
        out.append("\(String(repeating: ">", count: depth)) \(type(of: l)) size=\(Int(l.bounds.width))x\(Int(l.bounds.height)) pos=(\(Int(l.position.x)),\(Int(l.position.y))) z=\(Int(l.zPosition)) opacity=\(String(format: "%.2f", l.opacity)) presentation=\(presS) sub=\(l.sublayers?.count ?? 0)")
    }
    for s in l.sublayers ?? [] { layerLines(s, depth + 1, &out, all: all) }
}
@MainActor func layerCount(_ l: CALayer) -> Int { 1 + (l.sublayers ?? []).map(layerCount).reduce(0, +) }
/// Reads `host.layer` recursively 0.4 s after `change`. `all` lists every layer in sublayer order (the z-order read);
/// otherwise only layers whose opacity or presentation opacity is not 1.
@MainActor func xf2(_ name: String, all: Bool = false, _ content: @escaping (M) -> some View, setup: (M) -> Void = { _ in }, change: ((M) -> Void)?) {
    let m = M(); setup(m)
    let host = NSHostingView(rootView: Root(m: m, c: content))
    let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 200), styleMask: [.titled], backing: .buffered, defer: false)
    win.contentView = host; win.orderFrontRegardless(); spin(0.3)
    animators.removeAll(); maxTime = 0
    if let change { change(m); spin(0.4) }
    var out: [String] = []
    print("=== \(name)")
    if let root = host.layer { layerLines(root, 0, &out, all: all); print("  layers: \(layerCount(root))") } else { print("  host.layer = nil") }
    for o in out { print("  \(o)") }
    print("  ~ anim clock \(String(format: "%.2f", maxTime))")
    win.orderOut(nil); win.contentView = nil; spin(0.05)
}
xf2("XF2 control: static red.opacity(0.5)", { m in Color.red.frame(width: 50, height: 30).opacity(0.5) }, change: nil)
xf2("XF2 control: red.opacity(0 -> 1) under L, read 0.4 s in", { m in Color.red.frame(width: 50, height: 30).opacity(m.v) },
    change: { m in withAnimation(L) { m.v = 1 } })
xf2("XF2 default insertion under L, read 0.4 s in", { m in ZStack { if m.flag { Color.red.frame(width: 50, height: 30) } } },
    change: { m in withAnimation(L) { m.flag = true } })
xf2("XF2 default removal under L, read 0.4 s in (the ghost: is there a layer at all?)", { m in ZStack { if m.flag { Color.red.frame(width: 50, height: 30) } } },
    setup: { m in m.flag = true }, change: { m in withAnimation(L) { m.flag = false } })
xf2("XF2 .transition(.opacity) removal under L, read 0.4 s in", { m in ZStack { if m.flag { Color.red.frame(width: 50, height: 30).transition(.opacity) } } },
    setup: { m in m.flag = true }, change: { m in withAnimation(L) { m.flag = false } })
// The z-order read: ALL layers, in sublayer order, for the XF10 trees. A leaf that needs no layer of its own is drawn
// into its parent's contents, so a sublayer is above it whatever the SwiftUI order: the arm with `.opacity(0.99)` on
// the blue sibling and on the white backdrop forces each into a layer of its own, which makes the order readable.
xf2("XF2z the tree at rest: ZStack { white; red; blue } with every leaf in its own layer (opacity 0.99)", all: true, { m in
    ZStack(alignment: .topLeading) { Color.white.frame(width: 400, height: 200).opacity(0.99); if m.flag { Color.red.frame(width: 50, height: 30).opacity(0.99) }; Color.blue.frame(width: 30, height: 10).opacity(0.99) }
}, setup: { m in m.flag = true }, change: nil)
xf2("XF2z unannotated removal, red BELOW blue (leaves in layers), 0.4 s in", all: true, { m in
    ZStack(alignment: .topLeading) { Color.white.frame(width: 400, height: 200).opacity(0.99); if m.flag { Color.red.frame(width: 50, height: 30).opacity(0.99) }; Color.blue.frame(width: 30, height: 10).opacity(0.99) }
}, setup: { m in m.flag = true }, change: { m in withAnimation(L) { m.flag = false } })
xf2("XF2z .transition(.opacity) removal, red BELOW blue (leaves in layers), 0.4 s in", all: true, { m in
    ZStack(alignment: .topLeading) { Color.white.frame(width: 400, height: 200).opacity(0.99); if m.flag { Color.red.frame(width: 50, height: 30).opacity(0.99).transition(.opacity) }; Color.blue.frame(width: 30, height: 10).opacity(0.99) }
}, setup: { m in m.flag = true }, change: { m in withAnimation(L) { m.flag = false } })
xf2("XF2z unannotated removal, red ABOVE blue (leaves in layers), 0.4 s in", all: true, { m in
    ZStack(alignment: .topLeading) { Color.white.frame(width: 400, height: 200).opacity(0.99); Color.blue.frame(width: 30, height: 10).opacity(0.99); if m.flag { Color.red.frame(width: 50, height: 30).opacity(0.99) } }
}, setup: { m in m.flag = true }, change: { m in withAnimation(L) { m.flag = false } })
xf2("XF2zb the same trees with the white backdrop as .background (not a sibling): unannotated removal, red BELOW blue, 0.4 s in", all: true, { m in
    onWhite { if m.flag { Color.red.frame(width: 50, height: 30).opacity(0.99) }; Color.blue.frame(width: 30, height: 10).opacity(0.99) }
}, setup: { m in m.flag = true }, change: { m in withAnimation(L) { m.flag = false } })
xf2("XF2zb unannotated removal, red ABOVE blue, 0.4 s in", all: true, { m in
    onWhite { Color.blue.frame(width: 30, height: 10).opacity(0.99); if m.flag { Color.red.frame(width: 50, height: 30).opacity(0.99) } }
}, setup: { m in m.flag = true }, change: { m in withAnimation(L) { m.flag = false } })
xf2("XF2zb .transition(.opacity) removal, red ABOVE blue, 0.4 s in", all: true, { m in
    onWhite { Color.blue.frame(width: 30, height: 10).opacity(0.99); if m.flag { Color.red.frame(width: 50, height: 30).transition(.opacity).opacity(0.99) } }
}, setup: { m in m.flag = true }, change: { m in withAnimation(L) { m.flag = false } })
xf2("XF2zb red ABOVE blue, the ZStack with a THIRD, always-present leaf above red, removal 0.4 s in", all: true, { m in
    onWhite { Color.blue.frame(width: 30, height: 10).opacity(0.99); if m.flag { Color.red.frame(width: 50, height: 30).opacity(0.99) }; Color.green.frame(width: 20, height: 5).opacity(0.99) }
}, setup: { m in m.flag = true }, change: { m in withAnimation(L) { m.flag = false } })
xf2("XF2z unannotated removal in a VStack, red FIRST (leaves in layers), 0.4 s in", all: true, { m in
    VStack(alignment: .leading, spacing: 0) { if m.flag { Color.red.frame(width: 50, height: 30).opacity(0.99) }; Color.blue.frame(width: 30, height: 10).opacity(0.99) }
}, setup: { m in m.flag = true }, change: { m in withAnimation(L) { m.flag = false } })

// ---- XF3 container independence
@MainActor func cont(_ name: String, _ f: @escaping (M) -> AnyView) {
    for insert in [true, false] {
        arm("\(name) \(insert ? "insert" : "remove")", { m in f(m) }, setup: { m in m.flag = !insert },
            change: { m in withAnimation(A) { m.flag = insert } })
    }
}
cont("XF3 VStack(spacing: 0) { if flag { red 50x30 }; blue 30x10 }") { m in AnyView(VStack(alignment: .leading, spacing: 0) { if m.flag { Color.red.frame(width: 50, height: 30) }; Color.blue.frame(width: 30, height: 10) }) }
cont("XF3 HStack(spacing: 0) { if flag { red 50x30 }; blue 30x10 }") { m in AnyView(HStack(alignment: .top, spacing: 0) { if m.flag { Color.red.frame(width: 50, height: 30) }; Color.blue.frame(width: 30, height: 10) }) }
cont("XF3 Group { if flag { red } } (root)") { m in AnyView(Group { if m.flag { Color.red.frame(width: 50, height: 30) } }) }
cont("XF3 bare if flag { red } as the root's only child") { m in AnyView(ZStack { if m.flag { Color.red.frame(width: 50, height: 30) } }) }

// ---- XF4 / XF5 a tuple under one if
cont("XF4 ZStack { if flag { red 50x30; blue 30x10 } }") { m in AnyView(ZStack(alignment: .topLeading) { if m.flag { Color.red.frame(width: 50, height: 30); Color.blue.frame(width: 30, height: 10) } }) }
cont("XF4b VStack(spacing: 0) { if flag { red 50x30; blue 30x10 }; green 20x10 }") { m in AnyView(VStack(alignment: .leading, spacing: 0) { if m.flag { Color.red.frame(width: 50, height: 30); Color.blue.frame(width: 30, height: 10) }; Color.green.frame(width: 20, height: 10) }) }
cont("XF5 ZStack { if flag { red.transition(.move(edge: .leading)); blue 30x10 } }") { m in AnyView(ZStack(alignment: .topLeading) { if m.flag { Color.red.frame(width: 50, height: 30).transition(.move(edge: .leading)); Color.blue.frame(width: 30, height: 10) } }) }
cont("XF5b ZStack { if flag { red.transition(.identity); blue 30x10 } }") { m in AnyView(ZStack(alignment: .topLeading) { if m.flag { Color.red.frame(width: 50, height: 30).transition(.identity); Color.blue.frame(width: 30, height: 10) } }) }

// ---- XF6 ForEach with no .transition
arm("XF6 ForEach insertion, no .transition: [1,2] -> [1,2,3] (ZStack of fixed rows, no geometry)", { m in
    ZStack(alignment: .topLeading) { ForEach(m.items, id: \.self) { i in Color.red.frame(width: 20 + CGFloat(i), height: 10) } }
}, change: { m in withAnimation(A) { m.items = [1, 2, 3] } })
arm("XF6 ForEach removal, no .transition: [1,2,3] -> [1,3]", { m in
    ZStack(alignment: .topLeading) { ForEach(m.items, id: \.self) { i in Color.red.frame(width: 20 + CGFloat(i), height: 10) } }
}, setup: { m in m.items = [1, 2, 3] }, change: { m in withAnimation(A) { m.items = [1, 3] } })
arm("XF6b ForEach in a VStack insertion: [1,2] -> [1,2,3]", { m in
    VStack(spacing: 0) { ForEach(m.items, id: \.self) { i in Color.red.frame(width: 20 + CGFloat(i), height: 10) } }
}, change: { m in withAnimation(A) { m.items = [1, 2, 3] } })
arm("XF6b ForEach in a VStack removal: [1,2,3] -> [1,3]", { m in
    VStack(spacing: 0) { ForEach(m.items, id: \.self) { i in Color.red.frame(width: 20 + CGFloat(i), height: 10) } }
}, setup: { m in m.items = [1, 2, 3] }, change: { m in withAnimation(A) { m.items = [1, 3] } })

// ---- XF7 a changed .id
arm("XF7 .id(k) change 0 -> 1 on a red view, recorder (A)", { m in Color.red.frame(width: 50, height: 30).id(m.k) },
    change: { m in withAnimation(A) { m.k = 1 } })
armEv("XF7 .id(k) 0 -> 1 under S (0.6 s), appear/disappear", { m in Leaf(name: "x", colour: .red).id(m.k) },
      change: { m in withAnimation(S) { m.k = 1 } })
armEv("XF7 control: if-removal under S, no .transition (the unannotated removal; T1u's twin)", { m in
    ZStack { if !m.flag { Leaf(name: "x", colour: .red) } }
}, change: { m in withAnimation(S) { m.flag = true } })

// ---- XF8 an AnyView swap
arm("XF8a AnyView(flag ? AnyView(WB) : AnyView(WA)) swap under A", { m in
    ZStack(alignment: .topLeading) { AnyView(m.flag ? AnyView(WB()) : AnyView(WA())) }
}, change: { m in withAnimation(A) { m.flag = true } })
arm("XF8b the same with .transition(.opacity) on each erased view", { m in
    ZStack(alignment: .topLeading) { AnyView(m.flag ? AnyView(WB().transition(.opacity)) : AnyView(WA().transition(.opacity))) }
}, change: { m in withAnimation(A) { m.flag = true } })
arm("XF8c control: if flag { AnyView(WA) } insert", { m in
    ZStack(alignment: .topLeading) { if m.flag { AnyView(WA()) } }
}, change: { m in withAnimation(A) { m.flag = true } })
arm("XF8c control: if flag { AnyView(WA) } remove", { m in
    ZStack(alignment: .topLeading) { if m.flag { AnyView(WA()) } }
}, setup: { m in m.flag = true }, change: { m in withAnimation(A) { m.flag = false } })
arm("XF8d control: AnyView(WA) swapped to another AnyView(WA) with a different tick (same type, no swap)", { m in
    ZStack(alignment: .topLeading) { AnyView(m.flag ? AnyView(WA()) : AnyView(WA())) }
}, change: { m in withAnimation(A) { m.flag = true } })
armEv("XF8e AnyView swap under S (0.6 s): appear/disappear timing (AV6a's twin, through the recorder)", { m in
    ZStack(alignment: .topLeading) { AnyView(m.flag ? AnyView(LB()) : AnyView(LA())) }
}, change: { m in withAnimation(S) { m.flag = true } })
armEv("XF8f AnyView swap under S with .transition(.opacity) inside (AV6b's twin)", { m in
    ZStack(alignment: .topLeading) { AnyView(m.flag ? AnyView(LB().transition(.opacity)) : AnyView(LA().transition(.opacity))) }
}, change: { m in withAnimation(S) { m.flag = true } })

// ---- XF9 no-animate cases
@MainActor func appearArm<Content: View>(_ name: String, _ content: @escaping (M) -> Content, setup: (M) -> Void) {
    let m = M(); setup(m)
    animators.removeAll(); maxTime = 0
    let host = NSHostingView(rootView: Root(m: m, c: content))
    let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 200), styleMask: [.titled], backing: .buffered, defer: false)
    win.contentView = host; win.orderFrontRegardless(); spin(0.5)
    print("=== \(name)"); printAnimators(animators)
    win.orderOut(nil); win.contentView = nil; spin(0.05)
}
appearArm("XF9a first appearance: if flag (true from the first render) { red } under .transaction { animation = A }", { m in
    ZStack(alignment: .topLeading) { Color.blue.frame(width: 30, height: 10); if m.flag { Color.red.frame(width: 50, height: 30) } }
        .transaction { $0.animation = A }
}, setup: { m in m.flag = true })
@MainActor func scrollOrigin() -> String {
    func find(_ v: NSView) -> NSScrollView? { if let s = v as? NSScrollView { return s }; for s in v.subviews { if let f = find(s) { return f } }; return nil }
    guard let h = currentHost, let s = find(h) else { return "no NSScrollView" }
    return String(format: "clip y=%.0f", s.contentView.bounds.origin.y)
}
for (nm, listy) in [("LazyVStack in a ScrollView", false), ("List", true)] {
    arm("XF9 \(nm): withAnimation(A) { proxy.scrollTo(150) }; rows enter the window", { _ in
        ProxyGrab {
            if listy { List(0..<200, id: \.self) { i in Text("row \(i)").id(i) }.frame(width: 200, height: 100) }
            else { ScrollView { LazyVStack { ForEach(0..<200, id: \.self) { i in Text("row \(i)").id(i) } } }.frame(width: 200, height: 100) }
        }
    }, after: 0.8, change: { _ in
        notes.append("before: \(scrollOrigin())")
        withAnimation(A) { proxyBox?.scrollTo(150, anchor: .top) }
        spin(0.3); notes.append("after 0.3 s: \(scrollOrigin()) (control: a moved origin means the scroll ran)")
    })
}
arm("XF9 List data insertion (not a scroll): items [1,2] -> [1,2,3] under A, informational", { m in
    List(m.items, id: \.self) { i in Text("row \(i)") }.frame(width: 200, height: 100)
}, change: { m in withAnimation(A) { m.items = [1, 2, 3] } })

// ---- XF10 z-order, sampled where a red 50x30 leaver overlaps a blue 30x10 sibling at (10,5); (40,20) is red-only
let ptZ = [(40, 20), (10, 5)]
let clsZ: [(String, ((Int, Int, Int)) -> String)] = [("red-over-white at (40,20)", redOverWhite), ("overlap at (10,5)", overBlue)]
armPx("XF10a unannotated removal, red BELOW the blue sibling in ZStack { if flag { red }; blue } .background(white)", { m in
    onWhite { if m.flag { Color.red.frame(width: 50, height: 30).opacity(0.99) }; Color.blue.frame(width: 30, height: 10).opacity(0.99) }
}, setup: { m in m.flag = true }, points: ptZ, classify: clsZ, change: { m in withAnimation(L) { m.flag = false } })
armPx("XF10b unannotated removal, red ABOVE the blue sibling in ZStack { blue; if flag { red } } .background(white)", { m in
    onWhite { Color.blue.frame(width: 30, height: 10).opacity(0.99); if m.flag { Color.red.frame(width: 50, height: 30).opacity(0.99) } }
}, setup: { m in m.flag = true }, points: ptZ, classify: clsZ, change: { m in withAnimation(L) { m.flag = false } })
armPx("XF10c .transition(.opacity) removal, red BELOW the blue sibling", { m in
    onWhite { if m.flag { Color.red.frame(width: 50, height: 30).transition(.opacity).opacity(0.99) }; Color.blue.frame(width: 30, height: 10).opacity(0.99) }
}, setup: { m in m.flag = true }, points: ptZ, classify: clsZ, change: { m in withAnimation(L) { m.flag = false } })
armPx("XF10d unannotated insertion, red BELOW the blue sibling", { m in
    onWhite { if m.flag { Color.red.frame(width: 50, height: 30).opacity(0.99) }; Color.blue.frame(width: 30, height: 10).opacity(0.99) }
}, points: ptZ, classify: clsZ, change: { m in withAnimation(L) { m.flag = true } })
armPx("XF10e control: red BELOW the blue sibling, red.opacity(1 -> 0) animated (no structure change)", { m in
    onWhite { Color.red.frame(width: 50, height: 30).opacity(0.99).opacity(1 - m.v); Color.blue.frame(width: 30, height: 10).opacity(0.99) }
}, points: ptZ, classify: clsZ, change: { m in withAnimation(L) { m.v = 1 } })

// ---- XF11 Reduce Motion (swizzled in-process, as swiftui-transactions-animation.swift R1/R2)
installReduceMotionSwizzle()
forceReduceMotion = true
NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: NSWorkspace.shared)
spin(0.1)
arm("XF11 control: a reader view under the swizzle", { _ in RMReader() }, change: { _ in })
print("  reads: \(rmReads)"); rmReads.removeAll()
for insert in [true, false] {
    arm("XF11 X0' default \(insert ? "insert" : "remove") with Reduce Motion reading true", { m in
        ZStack(alignment: .topLeading) { RMReader(); Color.blue.frame(width: 30, height: 10); if m.flag { Color.red.frame(width: 50, height: 30) } }
    }, setup: { m in m.flag = !insert }, change: { m in withAnimation(A) { m.flag = insert } })
    print("  reads: \(rmReads)"); rmReads.removeAll()
}
forceReduceMotion = false
NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: NSWorkspace.shared)
spin(0.1)
zif("XF11 control after undo: X0' default", insert: true)
}
