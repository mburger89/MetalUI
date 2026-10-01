// SwiftUI probe for plan task 15, the closeout (rulings CX-F, CX-I item 2).
//
// GROUP O — an optional `@State` with a non-nil initial value (divergence 85,
// ruling CX-F). Each arm is a view rendered once into an `NSHostingView`
// (layout + `cacheDisplay`, so `body` really runs), logging what `body` reads.
//   O0  positive control: `@State var n: Int = 2`, first body reads 2.
//   O1n control: `@State var x: Int? = nil`, first body reads nil.
//   O1  the claim: `@State var x: Int? = 2`, first body reads 2 (MetalUI read
//       nil before CX-F: `StateTable.peek` cast an absent entry to `Int?` as
//       `.some(nil)`).
//   O2  separating arm: O1's view after a write of `nil` (a closure installed
//       in `onAppear`, called after the first render, then re-rendered) reads
//       nil — a fix that treated a stored nil as absent would read 2.
//
// GROUP SW — `switch` transitions (CX-I item 2; added by lane 1). Task 13's
// recorder, copied from docs/probes/swiftui-transactions-animation.swift: every
// arm animates with `A = Animation(Rec(tag: "A"))`, a `CustomAnimation` that
// records the TYPE and DELTA (target − start) of each animatable value SwiftUI
// hands it. A `.move(edge: .leading)` transition's value is an OFFSET
// [dx, dy, 0, 0]: an insertion from the leading edge reads +width, a removal
// toward it −width (task 13's X2). Lines are de-duplicated and sorted.
//   SW0  positive control: an `if`/`else` whose two branches (50×30 red, 50×30
//        green) each carry `.transition(.move(edge: .leading))`; the flag
//        flips under withAnimation(A) — records the insertion's +50 and the
//        removal's −50.
//   SW1  the claim: a three-case `switch` (red, green, blue, each 50×30 with
//        the same transition), case 0 → 1 under withAnimation(A) — the same
//        two lines as SW0.
//   SW1n separating arm: SW1's change with no transaction — nothing animated.
//
// HOW TO RUN (the form that was run):
//   xcrun swiftc docs/probes/swiftui-closeout.swift -o /tmp/closeout && /tmp/closeout
//
// RECORDED 2026-09-30 (critic round of the closeout design), macOS 27.0.1
// (26A434), screen unlocked. Two runs, byte-identical:
//
//     O0 Int=2 first body: 2
//     O1n Int?=nil body: nil
//     O1 Int?=2 body: 2
//     O2 setter installed: true
//     O1 Int?=2 body: nil
//
// GROUP SW RECORDED 2026-09-30 23:58 PDT (lane 1), macOS 27.0.1 (26A434),
// screen unlocked (lock probe: no CGSSessionScreenIsLocked line,
// displayAsleep main: 0). The whole file was run twice, byte-identical; group
// O's lines re-read exactly as above, and group SW's are:
//
//     === SW0 if/else, each branch .transition(.move(edge: .leading)), c 0 -> 1 (if c == 0 / else) under withAnimation(A)
//       A P<P<F, F>, P<F, F>> [-50.000, 0.000, 0.000, 0.000]
//       A P<P<F, F>, P<F, F>> [50.000, 0.000, 0.000, 0.000]
//     === SW1 switch over three cases, each .transition(.move(edge: .leading)), case 0 -> 1 under withAnimation(A)
//       A P<P<F, F>, P<F, F>> [-50.000, 0.000, 0.000, 0.000]
//       A P<P<F, F>, P<F, F>> [50.000, 0.000, 0.000, 0.000]
//     === SW1n SW1 with no transaction
//       (nothing animated)
//
import SwiftUI
import AppKit

@MainActor final class Log { static var lines: [String] = [] ; static var setter: (() -> Void)? }

struct O0: View { @State var n: Int = 2
    var body: some View { let _ = Log.lines.append("O0 Int=2 first body: \(n)"); return Color.clear.frame(width: 10, height: 10) } }
struct O1: View { @State var x: Int? = 2
    var body: some View { let _ = Log.lines.append("O1 Int?=2 body: \(x.map(String.init) ?? "nil")"); return Color.clear.frame(width: 10, height: 10).onAppear { Log.setter = { x = nil } } } }
struct O1n: View { @State var x: Int? = nil
    var body: some View { let _ = Log.lines.append("O1n Int?=nil body: \(x.map(String.init) ?? "nil")"); return Color.clear.frame(width: 10, height: 10) } }

// ---- group SW: task 13's recorder, copied
nonisolated(unsafe) var swSeen: Set<String> = []
struct Rec: CustomAnimation {
    let tag: String
    func animate<V: VectorArithmetic>(value: V, time: TimeInterval, context: inout AnimationContext<V>) -> V? {
        swSeen.insert("\(tag) \(short(V.self)) \(fmt(value))")
        if time > 0.15 { return nil }
        return value.scaled(by: time / 0.15)
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
}
let A = Animation(Rec(tag: "A"))
@MainActor final class SWModel: ObservableObject { @Published var c = 0 }
struct IfElseSW: View { @ObservedObject var m: SWModel
    var body: some View { ZStack(alignment: .topLeading) {
        if m.c == 0 { Color.red.frame(width: 50, height: 30).transition(.move(edge: .leading)) }
        else { Color.green.frame(width: 50, height: 30).transition(.move(edge: .leading)) } }
        .frame(width: 400, height: 200, alignment: .topLeading) } }
struct SwitchSW: View { @ObservedObject var m: SWModel
    var body: some View { ZStack(alignment: .topLeading) {
        switch m.c {
        case 0: Color.red.frame(width: 50, height: 30).transition(.move(edge: .leading))
        case 1: Color.green.frame(width: 50, height: 30).transition(.move(edge: .leading))
        default: Color.blue.frame(width: 50, height: 30).transition(.move(edge: .leading))
        } }
        .frame(width: 400, height: 200, alignment: .topLeading) } }
@MainActor func swArm<C: View>(_ name: String, _ content: @escaping (SWModel) -> C, change: (SWModel) -> Void) {
    let m = SWModel()
    let host = NSHostingView(rootView: content(m))
    let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 200), styleMask: [.titled], backing: .buffered, defer: false)
    win.contentView = host; win.orderFrontRegardless()
    RunLoop.main.run(until: Date().addingTimeInterval(0.25))
    swSeen.removeAll()
    change(m)
    RunLoop.main.run(until: Date().addingTimeInterval(0.5))
    print("=== \(name)")
    if swSeen.isEmpty { print("  (nothing animated)") }
    for l in swSeen.sorted() { print("  \(l)") }
    win.orderOut(nil); win.contentView = nil
    RunLoop.main.run(until: Date().addingTimeInterval(0.05))
}

@MainActor func render<V: View>(_ v: V) -> NSHostingView<V> {
    let h = NSHostingView(rootView: v); h.frame = NSRect(x: 0, y: 0, width: 10, height: 10); h.layoutSubtreeIfNeeded()
    let rep = h.bitmapImageRepForCachingDisplay(in: h.bounds)!; h.cacheDisplay(in: h.bounds, to: rep); return h }

MainActor.assumeIsolated {
    _ = NSApplication.shared
    _ = render(O0()); _ = render(O1n())
    let h = render(O1())
    RunLoop.main.run(until: Date().addingTimeInterval(0.2))
    Log.lines.append("O2 setter installed: \(Log.setter != nil)")
    Log.setter?()
    RunLoop.main.run(until: Date().addingTimeInterval(0.2)); h.layoutSubtreeIfNeeded()
    let rep = h.bitmapImageRepForCachingDisplay(in: h.bounds)!; h.cacheDisplay(in: h.bounds, to: rep)
    var seen = Set<String>(); for l in Log.lines where seen.insert(l).inserted { print(l) }

    // GROUP SW
    NSApplication.shared.setActivationPolicy(.accessory)
    swArm("SW0 if/else, each branch .transition(.move(edge: .leading)), c 0 -> 1 (if c == 0 / else) under withAnimation(A)",
          { m in IfElseSW(m: m) }, change: { m in withAnimation(A) { m.c = 1 } })
    swArm("SW1 switch over three cases, each .transition(.move(edge: .leading)), case 0 -> 1 under withAnimation(A)",
          { m in SwitchSW(m: m) }, change: { m in withAnimation(A) { m.c = 1 } })
    swArm("SW1n SW1 with no transaction",
          { m in SwitchSW(m: m) }, change: { m in m.c = 1 })
}
