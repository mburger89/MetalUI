// SwiftUI probe: `Animatable` — custom shapes, `trim`, a wrapper composing a trim, a pair retargeted mid-flight, a
// `View & Animatable`, an `Animatable & Equatable` view with `.equatable()`, keyframes over a custom `Animatable`
// struct, and the language-mode isolation of the conformance. Round 4 item R4-3 (divergences 169 and 947; the PR D
// design of docs/record/204-default-crossfade-probe.md). Ruling prefix `VA-`,
// docs/superpowers/2026-11-03-default-transition-decisions.md for the record (the `VA-` document is PR D's).
//
// HOW TO RUN (Apple's toolchain, COMPILED; the `/usr/bin/swift` JIT form does not link on macOS 27, SA-O):
//
//   xcrun swiftc docs/probes/swiftui-animatable.swift -o /tmp/vaprobe
//   /tmp/vaprobe 2>&1 | grep -v 'Connection\]'
//   grep -v '^  ~' output   # the STABLE lines; the `~` lines are timing (frame counts, sampled values)
//
// INSTRUMENTS. `Rec` is swiftui-transactions-animation.swift's recorder, with an ANIMATOR COUNT (the first `animate` call of
// each animator is recorded through `context.state`; `xN` is the number of animators, not of frames) and every log
// BUFFERED (printing per tick slows the animation clock, swiftui-lifecycle.swift AV6c). `A4`/`B4` ramp over 0.4 s,
// `A6`/`B6` over 0.6 s. The `path(in:)` / `body` / layout logs are a buffered `[String: [Double]]` keyed by arm; an arm
// prints a SUMMARY (was the value interpolated: more than two distinct values, between the endpoints) and the raw
// distinct count on a `~` line, because a frame count is a timing fact.
//
// SWIFT LANGUAGE MODE. Everything here compiles and runs in Swift 5 mode (the `xcrun swiftc` default). The VT group
// type-checks one-line snippets in BOTH modes with `swiftc -typecheck -swift-version 5|6`, positive control and
// separating arm each, because SwiftUI's `View` is `@MainActor` while `Animatable` is not.
//
// NOT MEASURED. How an animated shape looks (no pixels are read); a spring's feel; `Layout`/`TextRenderer` `Animatable`.
//
// RECORDED 2026-11-03 by R4-3 PR A, macOS 27.2 (26B123), Apple Swift 6.4.2, compiled with `xcrun swiftc`. Screen LOCKED
// (`CGSSessionScreenIsLocked = 1`, `displayAsleep main: 0`, `preflightScreenCaptureAccess: false`); the desktop was shared. Run
// twice, exit 0, stderr empty after the `Connection]` filter: the stable (non-`~`) lines identical (`diff` empty). Run 1 is kept
// whole in docs/probes/swiftui-animatable-run.txt. `path`/`body` call counts are in the tens of thousands per arm (the headless
// animation clock is not frame-limited), so they are `~` lines and mean nothing as frame counts. READING (MEASURED):
//   VT   SwiftUI's OWN spelling `struct V: View, Animatable { var animatableData }` compiles in Swift 5 mode and is an ERROR in
//        Swift 6 mode ("conformance of 'V' to protocol 'Animatable' crosses into main actor-isolated code"; the same for a
//        `ViewModifier`); `nonisolated var animatableData` compiles in both, and so do `@Animatable` and a `Shape` (nonisolated). The
//        SDK interface: `public protocol Animatable` carries no isolation, `nonisolated public protocol Shape`, `@MainActor protocol
//        View`, `@MainActor protocol ViewModifier`, `@MainActor protocol Transition`. `Float` is NOT `Animatable` (a `Float`
//        `LinearKeyframe` is an error, VT11/VT16; `Float` is a `VectorArithmetic`, VT13); `Double`, `CGFloat`, `CGPoint`, `CGSize`,
//        `Angle`, `UnitPoint`, `EdgeInsets` and `CGRect` are; `Int` and `Color` are not. `VectorArithmetic.scaled(by:)` is public (VT12).
//   VA1  a custom Shape with `animatableData` (Double): the animator is `Double [1]` and `path(in:)` runs at interpolated values
//        (more than two distinct values, range [0, 1]); no transaction: one call at the final value (VA1c).
//   VA2  a Shape without `animatableData`: nothing animated, one call at the final value (it snaps).
//   VA3  `Circle().trim(from: 0, to: v).stroke(...)`: type `P<P<Empty, P<F, F>>, P<F, P<F, F>>>` (the trim's data is
//        `AnimatablePair<S.AnimatableData, AnimatablePair<CGFloat, CGFloat>>`, here S = Circle so `Empty`), **and its fractions are
//        scaled by 128: an end fraction 0 -> 1 reads delta 128.000, a start fraction 0 -> 0.5 reads 64.000** (VA3a2: `P<Double, P<F,
//        F>> [1, 64, 128]` for base u 0 -> 1, start 0 -> 0.5, end 0 -> 1). A wrapper that declares nothing snaps (VA3b); one that
//        forwards a Double animates (VA3c); one that forwards the trim's own `animatableData` animates both the trim and the base
//        (VA3d: `P<Double, P<F, F>> [1, 0, 128]`); trim of a trim nests (VA3e: `P<P<Double, P<F, F>>, P<F, F>> [1, 0, 128, 0, 128]`),
//        both layers animate.
//   VA4  a pair retargeted on ONE component mid-flight: **the retarget is a new animator over the WHOLE pair** (`A P<Double, Double>`
//        then `B P<Double, Double>`, one each, no `Double`): B's delta is `[-0.50, +0.50]`, i.e. BOTH components re-based to current
//        (b, unchanged in the write, gets its remaining distance to the same target). After it `a` falls monotonically to 0 and
//        `b` never restarts (min b not below b-at-retarget - 0.05).
//   VA5  a `View & Animatable`: the animator is `Double [200]`, `body` runs with interpolated x (range [0.1, 200]) and its child
//        layout is proposed interpolated widths ([100.1, 300]); the control P1' (a plain `.frame(width:)` around a layout) is
//        proposed the final 300 only and animates a geometry value.
//   VA6  with the ramp recorder the retarget is continuous (last x before 49.9, first after 49.9) and the new ramp runs from the
//        current value (B delta -49.9); with `.spring(duration: 0.6, bounce: 0)` the position is continuous (81.8 / 81.8). The 30 ms
//        mean slopes are `~` lines (timing). **VA6c: `a`'s slope across a retarget of the OTHER component under a spring is 3.58/s
//        before and 3.17/s after (a window mean, timing): `a` keeps its velocity; a projection onto the new delta direction would have
//        reduced it, so the recollection "the perpendicular component is dropped" is not seen (the window is 30 ms and
//        the spring's internals are unread).**
//   VA7  `Animatable & Equatable` with `.equatable()` runs its body in flight with interpolated values exactly as the plain
//        `Animatable` control; settled, an unrelated parent change runs no body for either.
//   VA8  `keyframeAnimator` with `KeyframeTrack(\.pos)` over a custom `Animatable` struct (not a `VectorArithmetic`) compiles and
//        interpolates both components (a 0 -> 100 -> 0, b 0 -> 50 -> 0), recorder lines absent (keyframes do not go through `Rec`).
// NOT MEASURED: how a shape looks; the spring's internals.
//
// VA6d (added by R4-3 PR D, 2026-11-04): the per-tick arm for "does a retarget keep its velocity?" (docs/superpowers/2026-11-04-animatable-decisions.md
// `VA-F`). It typechecks (`xcrun swiftc -typecheck`) and was NOT RUN: `appkit-screen-lock-state.swift` read `CGSSessionScreenIsLocked = 1` that
// day. Its result is unmeasured; divergence 216 says so. Run it on an unlocked Mac, twice, and record the `~` fit line here.

import SwiftUI
import AppKit

// ---------------------------------------------------------------- recorder and buffers
nonisolated(unsafe) var animators: [String] = []
nonisolated(unsafe) var vlog: [String: [Double]] = [:]
nonisolated(unsafe) var vtimes: [String: [Double]] = [:]
nonisolated(unsafe) var t0 = Date()
nonisolated(unsafe) var retargetMark = 0
nonisolated(unsafe) var notes: [String] = []
let vlock = NSLock()
func vadd(_ k: String, _ v: Double) {
    vlock.lock(); vlog[k, default: []].append(v); vtimes[k, default: []].append(Date().timeIntervalSince(t0)); vlock.unlock()
}

struct SeenKey: AnimationStateKey { static var defaultValue: Bool { false } }
struct Rec: CustomAnimation {
    let tag: String
    var duration = 0.4
    func animate<V: VectorArithmetic>(value: V, time: TimeInterval, context: inout AnimationContext<V>) -> V? {
        if !context.state[SeenKey.self] {
            context.state[SeenKey.self] = true
            vlock.lock(); animators.append("\(tag) \(short(V.self)) \(fmt(value))"); vlock.unlock()
        }
        if time > duration { return nil }
        return value.scaled(by: time / duration)
    }
}
func fmt<V>(_ v: V) -> String {
    let s = String(describing: v)
    let re = try! NSRegularExpression(pattern: "-?[0-9]+\\.[0-9]+(e-?[0-9]+)?")
    let nums = re.matches(in: s, range: NSRange(s.startIndex..., in: s)).map { m -> String in
        let d = Double(String(s[Range(m.range, in: s)!]))!
        return String(format: "%.3f", abs(d) < 0.0005 ? 0 : d)
    }
    return "[" + nums.joined(separator: ", ") + "]"
}
func short(_ t: Any.Type) -> String {
    String(describing: t).replacingOccurrences(of: "AnimatablePair", with: "P").replacingOccurrences(of: "CGFloat", with: "F")
        .replacingOccurrences(of: "EmptyAnimatableData", with: "Empty")
}
let A4 = Animation(Rec(tag: "A", duration: 0.4))
let B4 = Animation(Rec(tag: "B", duration: 0.4))
let A6 = Animation(Rec(tag: "A", duration: 0.6))
let B6 = Animation(Rec(tag: "B", duration: 0.6))

@MainActor final class M: ObservableObject {
    @Published var v = 0.0
    @Published var u = 0.0
    @Published var w = 0.0
    @Published var a = 0.0
    @Published var b = 0.0
    @Published var flag = false
    @Published var tick = 0
    @Published var k = 0
}
struct Root<C: View>: View { @ObservedObject var m: M; let c: (M) -> C
    var body: some View { ZStack(alignment: .topLeading) { c(m) }.frame(width: 400, height: 200, alignment: .topLeading) } }
@MainActor func spin(_ s: Double) { RunLoop.main.run(until: Date().addingTimeInterval(s)) }

/// Prints the animators: the stable lines drop the delta (`tag Type xN`), the `~` lines keep it when `deltaIsTiming`.
@MainActor func printAnimators(deltaIsTiming: Bool) {
    if animators.isEmpty { print("  (nothing animated)"); return }
    var counts: [String: Int] = [:]
    for l in animators { counts[l, default: 0] += 1 }
    if !deltaIsTiming { for l in counts.keys.sorted() { print("  \(l) x\(counts[l]!)") }; return }
    var types: [String: Int] = [:]
    for l in animators { types[l.split(separator: "[").first.map(String.init) ?? l, default: 0] += 1 }
    for l in types.keys.sorted() { print("  \(l)x\(types[l]!)") }
    for l in counts.keys.sorted() { print("  ~ \(l) x\(counts[l]!)") }
}
/// Summary of a buffered series: was it interpolated (some value strictly between the first and last distinct values).
func summary(_ k: String, from idx: Int = 0) -> String {
    let all = Array((vlog[k] ?? []).dropFirst(idx))
    let r = all.map { ($0 * 1000).rounded() / 1000 }
    let distinct = Set(r).sorted()
    guard let lo = distinct.first, let hi = distinct.last else { return "\(k): no calls" }
    let interior = distinct.contains { $0 > lo && $0 < hi }
    // the end points of the first sample after the change are timing; the stable line rounds them to one decimal
    func one(_ x: Double) -> String { String(format: "%.1f", (x * 10).rounded() / 10 + 0.0) }
    return "\(k): interpolated=\(distinct.count > 2 && interior ? "yes" : "no") range=[\(one(lo)), \(one(hi))] last=\(one(r.last!))"
}
func rawCount(_ k: String, from idx: Int = 0) -> String {
    let all = Array((vlog[k] ?? []).dropFirst(idx))
    return "~ \(k): calls=\(all.count) distinct=\(Set(all.map { ($0 * 1000).rounded() / 1000 }).count) exact range=[\(all.min() ?? 0), \(all.max() ?? 0)]"
}

/// Mean slope of a buffered series over the window (lo, hi] of its timestamps (end points of the window, so per-call jitter cancels).
func slope(_ k: String, _ lo: Double, _ hi: Double) -> Double? {
    let xs = vlog[k] ?? [], ts = vtimes[k] ?? []
    let idx = ts.indices.filter { ts[$0] > lo && ts[$0] <= hi }
    guard let f = idx.first, let l = idx.last, ts[l] > ts[f] else { return nil }
    return (xs[l] - xs[f]) / (ts[l] - ts[f])
}

@MainActor func arm<Content: View>(_ name: String, _ content: @escaping (M) -> Content,
                                    setup: (M) -> Void = { _ in },
                                    keys: [String] = [], deltaIsTiming: Bool = false, after: Double = 0.7,
                                    change: (M) -> Void) {
    let m = M()
    setup(m)
    let host = NSHostingView(rootView: Root(m: m, c: content))
    let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 200), styleMask: [.titled], backing: .buffered, defer: false)
    win.contentView = host
    win.orderFrontRegardless()
    spin(0.3)
    animators.removeAll(); vlog.removeAll(); vtimes.removeAll(); notes.removeAll()
    t0 = Date()
    change(m)
    spin(after)
    print("=== \(name)")
    printAnimators(deltaIsTiming: deltaIsTiming)
    for k in keys { print("  \(summary(k))"); print("  \(rawCount(k))") }
    for n in notes { print("  \(n)") }
    win.orderOut(nil)
    win.contentView = nil
    spin(0.05)
}

// ---------------------------------------------------------------- shapes and views
struct Bar: Shape {                       // VA1
    var t: Double
    var animatableData: Double { get { t } set { t = newValue } }
    func path(in r: CGRect) -> Path { vadd("bar", t); return Path(CGRect(x: 0, y: 0, width: r.width * t, height: r.height)) }
}
struct BarNoData: Shape {                 // VA2: no animatableData
    var t: Double
    func path(in r: CGRect) -> Path { vadd("nodata", t); return Path(CGRect(x: 0, y: 0, width: r.width * t, height: r.height)) }
}
struct PS: Shape {                        // the base of the trims: its own data u, logged
    var u: Double
    var animatableData: Double { get { u } set { u = newValue } }
    func path(in r: CGRect) -> Path { vadd("ps", u); return Path(CGRect(x: 0, y: 0, width: r.width * max(u, 0.01), height: r.height)) }
}
struct TrimWrapNoData: Shape {            // VA3b: wraps a trim, declares nothing
    var to: Double
    func path(in r: CGRect) -> Path { vadd("tw0", to); return PS(u: 1).trim(from: 0, to: to).path(in: r) }
}
struct TrimWrapDouble: Shape {            // VA3c: wraps a trim, forwards one Double
    var to: Double
    var animatableData: Double { get { to } set { to = newValue } }
    func path(in r: CGRect) -> Path { vadd("tw1", to); return PS(u: 1).trim(from: 0, to: to).path(in: r) }
}
struct TrimHolder: Shape {                // VA3d: holds the trim and forwards ITS animatableData
    var s: _TrimmedShape<PS>
    var animatableData: _TrimmedShape<PS>.AnimatableData { get { s.animatableData } set { s.animatableData = newValue } }
    func path(in r: CGRect) -> Path { s.path(in: r) }
}
struct PairShape: Shape {                 // VA4 / VA6c
    var a: Double; var b: Double
    var animatableData: AnimatablePair<Double, Double> { get { AnimatablePair(a, b) } set { a = newValue.first; b = newValue.second } }
    func path(in r: CGRect) -> Path { vadd("pa", a); vadd("pb", b); return Path(CGRect(x: 0, y: 0, width: r.width * max(a, 0.01), height: r.height * max(b, 0.01))) }
}
struct WidthLog: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let w = proposal.width ?? 0
        vadd("w", Double(w))
        return CGSize(width: w, height: 20)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {}
}
struct AVw: View, Animatable {            // VA5: a View & Animatable
    var x: Double
    var animatableData: Double { get { x } set { x = newValue } }
    var body: some View { vadd("avbody", x); return WidthLog { Color.red }.frame(width: 100 + x, height: 20) }
}
struct EV: View, Animatable, Equatable {  // VA7
    var x: Double
    var animatableData: Double { get { x } set { x = newValue } }
    var body: some View { vadd("evbody", x); return Color.red.frame(width: 100 + x, height: 20) }
}
struct EVplain: View, Animatable {        // VA7 control: the same without Equatable
    var x: Double
    var animatableData: Double { get { x } set { x = newValue } }
    var body: some View { vadd("evplain", x); return Color.red.frame(width: 100 + x, height: 20) }
}
struct Pos: Animatable, Equatable {       // VA8: a custom Animatable that is not itself a VectorArithmetic
    var a: Double; var b: Double
    var animatableData: AnimatablePair<Double, Double> { get { AnimatablePair(a, b) } set { a = newValue.first; b = newValue.second } }
}
struct KFVal { var pos = Pos(a: 0, b: 0) }

// ---------------------------------------------------------------- typecheck group
func compiles(_ body: String, mode: Int) -> String {
    let dir = NSTemporaryDirectory() + "va-\(UInt32.random(in: 0...UInt32.max))"
    try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
    let src = dir + "/s.swift"
    try? ("import SwiftUI\n" + body + "\n").write(toFile: src, atomically: true, encoding: .utf8)
    let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
    p.arguments = ["swiftc", "-typecheck", "-swift-version", "\(mode)", src]
    let pipe = Pipe(); p.standardError = pipe; p.standardOutput = pipe
    try? p.run(); p.waitUntilExit()
    let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    if p.terminationStatus == 0 { return "compiles" }
    let line = out.split(separator: "\n").first { $0.contains("error:") }.map { String($0.split(separator: ":", maxSplits: 4).last ?? "") } ?? "?"
    return "ERROR" + line
}
func vt(_ name: String, _ body: String) {
    print("  \(name): swift5 \(compiles(body, mode: 5)) | swift6 \(compiles(body, mode: 6))")
}

// ---------------------------------------------------------------- arms
MainActor.assumeIsolated {
NSApplication.shared.setActivationPolicy(.accessory)

print("=== VT language-mode isolation of Animatable (SwiftUI's View is @MainActor, Animatable and Shape are not)")
vt("VT1 positive: struct S: Shape { var animatableData } (nonisolated protocol)",
   "struct S: Shape { var t: Double; var animatableData: Double { get { t } set { t = newValue } }; func path(in r: CGRect) -> Path { Path() } }")
vt("VT2 struct V: View, Animatable { var animatableData: Double } (SwiftUI's own spelling)",
   "struct V: View, Animatable { var x: Double; var animatableData: Double { get { x } set { x = newValue } }; var body: some View { Color.red.frame(width: x) } }")
vt("VT3 the same with `nonisolated var animatableData`",
   "struct V: View, Animatable { var x: Double; nonisolated var animatableData: Double { get { x } set { x = newValue } }; var body: some View { Color.red.frame(width: x) } }")
vt("VT4 struct M: ViewModifier, Animatable { var animatableData: Double }",
   "struct M: ViewModifier, Animatable { var x: Double; var animatableData: Double { get { x } set { x = newValue } }; func body(content: Content) -> some View { content.offset(x: x) } }")
vt("VT5 the same with `nonisolated var animatableData`",
   "struct M: ViewModifier, Animatable { var x: Double; nonisolated var animatableData: Double { get { x } set { x = newValue } }; func body(content: Content) -> some View { content.offset(x: x) } }")
vt("VT6 @Animatable macro on a View", "@Animatable struct V: View { var x: Double; var body: some View { Color.red.frame(width: x) } }")
vt("VT7 @Animatable macro on a Shape", "@Animatable struct S: Shape { var t: Double; func path(in r: CGRect) -> Path { Path() } }")
vt("VT8 struct E: Animatable {} (no animatableData: EmptyAnimatableData default)", "struct E: Animatable {}")
vt("VT9 a Shape with no animatableData", "struct S: Shape { func path(in r: CGRect) -> Path { Path() } }")
vt("VT10 positive: Double is Animatable", "func f<T: Animatable>(_ t: T) {}\nfunc g() { f(Double(1)) }")
for (ty, e) in [("Float", "Float(1)"), ("CGFloat", "CGFloat(1)"), ("CGPoint", "CGPoint.zero"), ("CGSize", "CGSize.zero"), ("Angle", "Angle.zero"),
                ("UnitPoint", "UnitPoint.center"), ("EdgeInsets", "EdgeInsets()"), ("CGRect", "CGRect.zero"), ("Int", "Int(1)"), ("Color", "Color.red")] {
    vt("VT11 \(ty): Animatable?", "func f<T: Animatable>(_ t: T) {}\nfunc g() { f(\(e)) }")
}
vt("VT12 VectorArithmetic.scaled(by:) is public: Double(1).scaled(by: 2)", "func g() -> Double { Double(1).scaled(by: 2) }")
vt("VT13 Float: VectorArithmetic", "func f<T: VectorArithmetic>(_ t: T) {}\nfunc g() { f(Float(1)) }")
vt("VT14 positive: LinearKeyframe over a custom Animatable struct", "struct P: Animatable { var a: Double; var animatableData: Double { get { a } set { a = newValue } } }\nfunc g() { _ = LinearKeyframe(P(a: 1), duration: 1) }")
vt("VT15 separating: LinearKeyframe over a plain struct that is not Animatable", "struct P { var a: Double }\nfunc g() { _ = LinearKeyframe(P(a: 1), duration: 1) }")
vt("VT16 positive: LinearKeyframe over Float", "func g() { _ = LinearKeyframe(Float(1), duration: 1) }")

// ---- VA1 a custom shape with animatableData
arm("VA1 custom Shape with animatableData: Bar(t: 0 -> 1) under A4", { m in Bar(t: m.v).fill(Color.red).frame(width: 100, height: 20) },
    keys: ["bar"], change: { m in withAnimation(A4) { m.v = 1 } })
arm("VA1c control: the same change with no transaction (path called at the final value only)", { m in Bar(t: m.v).fill(Color.red).frame(width: 100, height: 20) },
    keys: ["bar"], change: { m in m.v = 1 })
// ---- VA2 no animatableData
arm("VA2 a Shape with NO animatableData (BarNoData t: 0 -> 1) under A4: snaps?", { m in BarNoData(t: m.v).fill(Color.red).frame(width: 100, height: 20) },
    keys: ["nodata"], change: { m in withAnimation(A4) { m.v = 1 } })
// ---- VA3 trim and wrappers
arm("VA3a Circle().trim(from: 0, to: v).stroke under A4: the animated type", { m in Circle().trim(from: 0, to: m.v).stroke(Color.red, lineWidth: 2).frame(width: 60, height: 60) },
    change: { m in withAnimation(A4) { m.v = 1 } })
arm("VA3a2 PS(u).trim(from: u2, to: v) under A4, all three moving: the pair's type and the base's u", { m in PS(u: m.u).trim(from: m.w, to: m.v).fill(Color.red).frame(width: 100, height: 20) },
    keys: ["ps"], change: { m in withAnimation(A4) { m.u = 1; m.v = 1; m.w = 0.5 } })
arm("VA3b a wrapper around a trim that declares nothing (TrimWrapNoData to: 0 -> 1): snaps?", { m in TrimWrapNoData(to: m.v).fill(Color.red).frame(width: 100, height: 20) },
    keys: ["tw0"], change: { m in withAnimation(A4) { m.v = 1 } })
arm("VA3c a wrapper that forwards one Double (TrimWrapDouble to: 0 -> 1): animates?", { m in TrimWrapDouble(to: m.v).fill(Color.red).frame(width: 100, height: 20) },
    keys: ["tw1"], change: { m in withAnimation(A4) { m.v = 1 } })
arm("VA3d a wrapper that forwards the trim's own animatableData (TrimHolder): the type and the base's u", { m in
    TrimHolder(s: _TrimmedShape(shape: PS(u: m.u), startFraction: 0, endFraction: m.v)).fill(Color.red).frame(width: 100, height: 20) },
    keys: ["ps"], change: { m in withAnimation(A4) { m.u = 1; m.v = 1 } })
arm("VA3e trim of a trim: PS(u).trim(from: 0, to: v).trim(from: 0, to: w) under A4: the nested type and the base's u", { m in
    PS(u: m.u).trim(from: 0, to: m.v).trim(from: 0, to: m.w).fill(Color.red).frame(width: 100, height: 20) },
    keys: ["ps"], change: { m in withAnimation(A4) { m.u = 1; m.v = 1; m.w = 1 } })
// ---- VA4 a pair retargeted on one component mid-flight
arm("VA4 AnimatablePair retarget: A6 { a = 1, b = 1 }, 0.3 s later B6 { a = 0 } (b unchanged): whole pair or one component?", { m in
    PairShape(a: m.a, b: m.b).fill(Color.red).frame(width: 100, height: 20) },
    keys: ["pa", "pb"], deltaIsTiming: true, after: 1.0, change: { m in
        withAnimation(A6) { m.a = 1; m.b = 1 }
        spin(0.3)
        vlock.lock(); let mark = vlog["pa"]?.count ?? 0; vlock.unlock()
        withAnimation(B6) { m.a = 0 }
        spin(0.05)
        vlock.lock(); let bAt = (vlog["pb"] ?? []).last ?? -1; let aAt = (vlog["pa"] ?? [])[max(0, mark - 1)]; vlock.unlock()
        notes.append("~ at the retarget: a=\(String(format: "%.3f", aAt)) b=\(String(format: "%.3f", bAt)) (path calls before: \(mark))")
        retargetMark = mark
    })
do {
    let pa = Array((vlog["pa"] ?? []).dropFirst(retargetMark)), pb = Array((vlog["pb"] ?? []).dropFirst(retargetMark))
    let bMin = pb.min() ?? -1, bAt = (vlog["pb"] ?? [])[max(0, retargetMark - 1)]
    print("  after the retarget: b restarts (min b below b-at-retarget - 0.05) = \(bMin < bAt - 0.05 ? "yes" : "no"); a ends at \(String(format: "%.2f", pa.last ?? -1)), b ends at \(String(format: "%.2f", pb.last ?? -1)); a decreases monotonically = \(zip(pa, pa.dropFirst()).allSatisfy { $0 >= $1 - 0.001 } ? "yes" : "no")")
}
// ---- VA5 a View & Animatable
arm("VA5 View & Animatable: AVw(x: 0 -> 200) under A4: body values and the widths its child layout is proposed", { m in AVw(x: m.v) },
    keys: ["avbody", "w"], change: { m in withAnimation(A4) { m.v = 200 } })
arm("VA5 control P1': .frame(width: 100 + v) around a WidthLog layout (no Animatable): the widths proposed", { m in WidthLog { Color.red }.frame(width: 100 + m.v, height: 20) },
    keys: ["w"], change: { m in withAnimation(A4) { m.v = 200 } })
// ---- VA6 retarget continuity (views; the body logs x with its time)
@MainActor func va6(_ name: String, _ anim: Animation, _ retarget: Animation) {
    arm(name, { m in AVw(x: m.v) }, keys: [], deltaIsTiming: true, after: 1.2, change: { m in
        withAnimation(anim) { m.v = 100 }
        spin(0.3)
        vlock.lock(); let n = vlog["avbody"]?.count ?? 0; vlock.unlock()
        let tR = Date().timeIntervalSince(t0)
        withAnimation(retarget) { m.v = 0 }
        spin(0.9)
        let xs = vlog["avbody"] ?? []
        guard n >= 2, xs.count > n + 1 else { notes.append("VA6 not enough body calls (\(xs.count))"); return }
        let before = xs[n - 1], after = xs[n]
        notes.append("continuous across the retarget (|first x after - last x before| < 8): \(abs(after - before) < 8 ? "yes" : "no")")
        let vb = slope("avbody", tR - 0.03, tR).map { String(format: "%.0f", $0) } ?? "?", va = slope("avbody", tR, tR + 0.03).map { String(format: "%.0f", $0) } ?? "?"
        notes.append("~ last x before \(String(format: "%.1f", before)), first x after \(String(format: "%.1f", after)); mean slope over the 30 ms before the retarget \(vb)/s, over the 30 ms after \(va)/s")
    })
}
va6("VA6 retarget continuity with the ramp recorder: A6 { x = 100 }, 0.3 s later B6 { x = 0 }", A6, B6)
va6("VA6b retarget continuity with .spring(duration: 0.6, bounce: 0): x = 100, 0.3 s later x = 0 (velocity read)", .spring(duration: 0.6, bounce: 0), .spring(duration: 0.6, bounce: 0))
arm("VA6c pair retarget under a spring: a moves 0 -> 1, 0.15 s later b moves 0 -> 1 (a's slope across the retarget)", { m in
    PairShape(a: m.a, b: m.b).fill(Color.red).frame(width: 100, height: 20) },
    keys: [], deltaIsTiming: true, after: 1.2, change: { m in
        withAnimation(.spring(duration: 0.6, bounce: 0)) { m.a = 1 }
        spin(0.15)
        let tR = Date().timeIntervalSince(t0)
        withAnimation(.spring(duration: 0.6, bounce: 0)) { m.b = 1 }
        spin(1.0)
        let vb = slope("pa", tR - 0.03, tR), va = slope("pa", tR, tR + 0.03)
        guard let vb, let va else { notes.append("VA6c not enough path calls"); return }
        notes.append("~ a slope over the 30 ms before the retarget \(String(format: "%.2f", vb))/s, over the 30 ms after \(String(format: "%.2f", va))/s (a's own target did not change)")
    })
// VA6d (R4-3 PR D): the stronger arm for "does a retarget keep its velocity?". The same-component retarget of VA6b under
// `.spring(duration: 0.6, bounce: 0)` (a critically damped spring, omega = 2 pi / 0.6), but with PER-TICK `x(t)` for 100 ms after
// the retarget fitted against both models: KEPT, `x(tau) = (x0 + (v0 + omega x0) tau) e^(-omega tau)` with `v0` the slope over the
// 30 ms before the retarget, and REST, the same with `v0 = 0`. The line prints each model's RMS residual over the ticks; the
// model with the smaller RMS is the reading. Every number is timing, so the whole result is `~`.
arm("VA6d per-tick fit of x(t) after a same-component retarget under a spring: velocity kept or restarted at rest?", { m in AVw(x: m.v) },
    keys: [], deltaIsTiming: true, after: 1.2, change: { m in
        let spring = Animation.spring(duration: 0.6, bounce: 0)
        withAnimation(spring) { m.v = 100 }
        spin(0.3)
        let tR = Date().timeIntervalSince(t0)
        withAnimation(spring) { m.v = 0 }
        spin(0.5)
        let xs = vlog["avbody"] ?? [], ts = vtimes["avbody"] ?? []
        let pre = ts.indices.filter { ts[$0] <= tR }, post = ts.indices.filter { ts[$0] > tR && ts[$0] <= tR + 0.1 }
        guard let x0 = pre.last.map({ xs[$0] }), let v0 = slope("avbody", tR - 0.03, tR), post.count >= 3 else {
            notes.append("VA6d not enough ticks (pre \(pre.count), post \(post.count))"); return
        }
        let omega = 2 * Double.pi / 0.6
        func rms(_ v: Double) -> Double {
            let e = post.map { i -> Double in
                let tau = ts[i] - tR
                return ((x0 + (v + omega * x0) * tau) * exp(-omega * tau) - xs[i])
            }
            return (e.map { $0 * $0 }.reduce(0, +) / Double(e.count)).squareRoot()
        }
        let kept = rms(v0), rest = rms(0)
        notes.append("~ ticks \(post.count) over 100 ms; x0 \(String(format: "%.1f", x0)), v0 \(String(format: "%.0f", v0))/s; RMS residual KEPT \(String(format: "%.2f", kept)), REST \(String(format: "%.2f", rest)) => \(kept < rest ? "velocity kept" : "restarts at rest")")
    })
// ---- VA7 Animatable & Equatable with .equatable()
arm("VA7 EV (Animatable & Equatable) with .equatable() under A4: does the body run in flight?", { m in EV(x: m.v).equatable() },
    keys: ["evbody"], change: { m in withAnimation(A4) { m.v = 200 } })
arm("VA7 control: EVplain (Animatable, no Equatable, no .equatable()) under A4", { m in EVplain(x: m.v) },
    keys: ["evplain"], change: { m in withAnimation(A4) { m.v = 200 } })
arm("VA7s settled: EV(x: 5).equatable() re-evaluated by an unrelated parent change (tick): body calls", { m in let _ = m.tick; return EV(x: 5).equatable() },
    keys: ["evbody"], change: { m in m.tick += 1 })
arm("VA7s control: EVplain(x: 5) with no .equatable(), the same parent change", { m in let _ = m.tick; return EVplain(x: 5) },
    keys: ["evplain"], change: { m in m.tick += 1 })
// ---- VA8 keyframes over a custom Animatable struct
struct KFView: View {
    @ObservedObject var m: M
    var body: some View {
        Color.red.frame(width: 50, height: 20)
            .keyframeAnimator(initialValue: KFVal(), trigger: m.k) { content, val in
                vadd("kfa", val.pos.a); vadd("kfb", val.pos.b); return content.offset(x: val.pos.a)
            } keyframes: { _ in
                KeyframeTrack(\.pos) {
                    LinearKeyframe(Pos(a: 100, b: 50), duration: 0.4)
                    LinearKeyframe(Pos(a: 0, b: 0), duration: 0.2)
                }
            }
    }
}
arm("VA8 keyframeAnimator with KeyframeTrack(\\.pos) over a custom Animatable struct (Pos: a 0 -> 100 -> 0, b 0 -> 50 -> 0)", { m in KFView(m: m) },
    keys: ["kfa", "kfb"], deltaIsTiming: true, after: 1.0, change: { m in m.k += 1 })
}

