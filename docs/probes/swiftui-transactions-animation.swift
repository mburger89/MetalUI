// SwiftUI probe: plan task 13 — transactions and animation. Which modifier
// wrappers animate and as WHAT value, `.animation(_:value:)`, `Transaction`,
// `withTransaction`, `.transaction(_:)`, `Binding.animation`/`.transaction`,
// the transition surface on insertion and removal inside `if` and `ForEach`,
// and what Reduce Motion changes. Evidence for rulings `AN-X`… in
// docs/superpowers/2026-09-03-animation-decisions.md and spec
// docs/superpowers/specs/2026-09-30-transactions-animation-design.md.
//
// HOW TO RUN (Apple's toolchain, COMPILED — the `/usr/bin/swift` JIT form
// fails to link on macOS 27 with `Symbols not found:
// ___isPlatformVersionAtLeast`, as the accessibility part-2 probe found):
//
//   xcrun swiftc docs/probes/swiftui-transactions-animation.swift -o /tmp/txprobe
//   /tmp/txprobe 2>&1 | grep -v 'Connection\]'
//
// HOW IT READS — THE RECORDER. Every arm animates with `A` or `B`, an
// `Animation(Rec(tag:))` over a `CustomAnimation` whose `animate(value:time:
// context:)` records the TYPE of each animatable value SwiftUI hands it and
// that value's DELTA (target − start), then runs a 0.15 s linear ramp. So an
// arm's lines say exactly which attributes SwiftUI animated for that change,
// under which animation, by how much — and "(nothing animated)" says no
// attribute reached any animation. SwiftUI drives `CustomAnimation`s itself,
// frame by frame, in-process: every arm here ran with the screen LOCKED and
// the display ASLEEP, and ticked (control C0). Lines are de-duplicated and
// sorted, so a line's count is not a frame count. Reading the types:
//   P<P<F, F>, P<F, F>> [ox, oy, w, h]  a VIEW'S GEOMETRY — its placed origin
//                                       and size; SwiftUI interpolates this
//                                       per view, after layout
//   Double [d]                          an opacity (a render effect)
//   ShapeStyle colour [...]             a fill/stroke colour (a ShapeStyle pack)
//   P<F, F> [r, r]                      a RoundedRectangle's corner size
//   P<F, P<F, P<F, F>>> [...]           `.border`'s stroke (inset, width, …)
// A transition's own value is the geometry-shaped pair too: `.move`/`.slide`/
// `.offset`/`.push` animate an OFFSET [dx, dy, 0, 0], `.scale` a SCALE
// [sx, sy, 0, 0]; the delta is target − start, so an insertion from the
// leading edge reads +width and a removal toward it −width.
//
// POSITIVE CONTROLS.
//   C0   `.frame(width:)` under withAnimation(A) records a geometry line —
//        the recorder is reached and ticks with the screen locked.
//   C1   the same change with no transaction records nothing.
//   C2   withAnimation(A) around a write that changes nothing records nothing.
//   X1n  a `.transition(.opacity)` insertion/removal with no transaction
//        records nothing.
//   T11c a write through a plain `@State` binding records nothing.
//   R0/R8, R10  the Reduce Motion reader reads false before the swizzle and
//        after it is undone, and a `.move`/`.scale` insertion records its
//        offset/scale there — the separating arms for R5*.
//
// REDUCE MOTION, IN-PROCESS. `EnvironmentValues.accessibilityReduceMotion` is
// get-only in SwiftUI (`.environment(\.accessibilityReduceMotion, true)`
// fails to typecheck: "cannot convert value of type 'KeyPath<EnvironmentValues,
// Bool>' to expected argument type 'WritableKeyPath<EnvironmentValues,
// Bool>'" — checked separately with `xcrun swiftc -typecheck`, so it is not
// in this file). The system setting is NOT touched: the probe swizzles
// `NSWorkspace.accessibilityDisplayShouldReduceMotion`'s getter in this
// process only. R1 shows SwiftUI does not re-read it on its own (a fresh host
// still reads false); R2 shows it re-reads it on
// `NSWorkspace.accessibilityDisplayOptionsDidChangeNotification` (reads
// true). Every R3+ arm runs with the reader reading true.
//
// RECORDED 2026-09-30 by the plan-task-13 design session, macOS 27.0
// (26A428), `xcrun swiftc` = Apple Swift 6.4 (swiftlang-6.4.0.33.1). Screen
// LOCKED (CGSSessionScreenIsLocked = 1, displayAsleep main: 1). The final
// revision ran twice, exit 0, stdout byte-identical (223 lines), and once
// more compiled from this path, identical again; stderr empty
// after the `Connection]` filter. One run's output, verbatim:
//
//   === C0 control: withAnimation(A) { v } on .frame(width: 100 + v)
//     A P<P<F, F>, P<F, F>> [0.000, 0.000, 200.000, 0.000]
//   === C1 control: the same change with no transaction
//     (nothing animated)
//   === C2 control: withAnimation(A) around a write that changes nothing
//     (nothing animated)
//   === W1 .frame(width:) 100 -> 300 (fixed 20 high, top-leading)
//     A P<P<F, F>, P<F, F>> [0.000, 0.000, 200.000, 0.000]
//   === W2 .padding 10 -> 30 around a 50x20 colour
//     A P<P<F, F>, P<F, F>> [0.000, 0.000, 40.000, 40.000]
//     A P<P<F, F>, P<F, F>> [20.000, 20.000, 0.000, 0.000]
//   === W3 .opacity 1 -> 0.2
//     A Double [-0.800]
//   === W4 .background(red -> blue) on a fixed frame
//     A ShapeStyle colour [-22.421, 4.491, 47.533, 0.000, 1.000, 0.000]
//   === W5 .border(black, width: 1 -> 5)
//     A P<F, P<F, P<F, F>>> [2.000, 4.000, 0.000, 0.000]
//   === W5c .border(red -> blue, width: 2)
//     A ShapeStyle colour [-22.421, 4.491, 47.533, 0.000, 1.000, 0.000]
//   === W6 .clipShape(RoundedRectangle(cornerRadius: 2 -> 12))
//     A P<F, F> [10.000, 10.000]
//   === W7 .frame(maxWidth: 100 -> 300) over a greedy colour
//     A P<P<F, F>, P<F, F>> [0.000, 0.000, 200.000, 0.000]
//   === W8 .overlay(alignment: .leading) { blue.frame(width: 10 -> 40) } on a 50x20
//     A P<P<F, F>, P<F, F>> [0.000, 0.000, 30.000, 0.000]
//   === W9 Rectangle().fill(red -> blue)
//     A ShapeStyle colour [-22.421, 4.491, 47.533, 0.000, 1.000, 0.000]
//   === W10 .clipped() added where it was absent (structure change)
//     A Double [-1.000]
//     A Double [1.000]
//   === W11 HStack(spacing: 0 -> 20) { 20x20; 20x20 }
//     A P<P<F, F>, P<F, F>> [20.000, 0.000, 0.000, 0.000]
//   === P1 a custom Layout inside .frame(width: 100 -> 300): the widths it was proposed
//     A P<P<F, F>, P<F, F>> [0.000, 0.000, 200.000, 0.000]
//     proposed widths seen by the child layout during the animation: ["300.0"]
//   === P2 a Text inside .frame(width: 60 -> 200) that wraps at 60
//     A Double [1.000]
//     A P<P<F, F>, P<F, F>> [0.000, 0.000, 67.000, -32.000]
//   === T1 .animation(A, value: v); v changes, no withAnimation
//     A Double [-0.500]
//   === T2 .animation(A, value: v); only u changes (u drives the opacity)
//     (nothing animated)
//   === T3 scope: HStack { X.opacity(1-v/2).animation(A, value: v); Y.opacity(1-v*0.8) }
//     A Double [-0.500]
//   === T3b order: X.animation(A, value: v).opacity(1 - v/2) -- the modifier written AFTER .animation
//     (nothing animated)
//   === T4 withAnimation(A) { v } with .animation(B, value: v) on the subtree
//     B Double [-0.500]
//   === T4n withAnimation(A) { v } with .animation(nil, value: v) on the subtree
//     (nothing animated)
//   === T5 withTransaction(Transaction(animation: A)) { v }
//     A Double [-0.500]
//   === T5n withTransaction(Transaction(animation: nil)) { v }
//     (nothing animated)
//   === T6 withAnimation(A) { v }; X has .transaction { $0.animation = nil }, Y none (X 1->0.5, Y 1->0.2)
//     A Double [-0.800]
//   === T7 withAnimation(A) { v } with .transaction { $0.animation = B }
//     B Double [-0.500]
//   === T7c no transaction at all, with .transaction { $0.animation = B }
//     B Double [-0.500]
//   === T8 withTransaction(disablesAnimations, animation A) { v } with .animation(B, value: v) below
//     A Double [-0.500]
//   === T8b withTransaction(disablesAnimations, animation nil) { v } with .animation(B, value: v) below
//     (nothing animated)
//   === T8c withTransaction(disablesAnimations, animation A) { v }, no .animation below
//     A Double [-0.500]
//   === T9 nesting: withAnimation(A) { withAnimation(B) { a = 0.5 }; b = 0.2 }  (X reads a, Y reads b)
//     A Double [-0.200]
//     B Double [-0.500]
//   === T10 two calls in one interval: withAnimation(A) { a = 0.5 }; withAnimation(B) { b = 0.2 }
//     A Double [-0.500]
//     B Double [-0.200]
//   === T11 Binding.animation(A): a write through $v.animation(A)
//     (nothing animated)
//   === T12 Binding.transaction(Transaction(animation: A))
//     (nothing animated)
//   === T13 retarget mid-flight: withAnimation(A) { v = 200 }, then 0.05 s later withAnimation(B) { v = 0 } (tags only)
//     A
//     B
//   === T11s @State: a write through $v.animation(A)
//     A Double [-0.500]
//   === T11c @State control: a write through plain $v
//     (nothing animated)
//   === T12s @State: a write through $v.transaction(Transaction(animation: A))
//     A Double [-0.500]
//   === X00 VStack: removing the first of two (50x30 .opacity, then 30x10): the sibling's shift
//     A Double [-1.000]
//     A P<P<F, F>, P<F, F>> [0.000, -30.000, 0.000, 0.000]
//   === X0 no .transition (the default) insert
//     A Double [1.000]
//   === X0 no .transition (the default) remove
//     A Double [-1.000]
//   === X1 .opacity insert
//     A Double [1.000]
//   === X1 .opacity remove
//     A Double [-1.000]
//   === X1n .opacity with NO transaction insert
//     (nothing animated)
//   === X1n .opacity with NO transaction remove
//     (nothing animated)
//   === X2 .move(edge: .leading) insert
//     A P<P<F, F>, P<F, F>> [50.000, 0.000, 0.000, 0.000]
//   === X2 .move(edge: .leading) remove
//     A P<P<F, F>, P<F, F>> [-50.000, 0.000, 0.000, 0.000]
//   === X3 .move(edge: .trailing) insert
//     A P<P<F, F>, P<F, F>> [-50.000, 0.000, 0.000, 0.000]
//   === X3t .move(edge: .top) insert
//     A P<P<F, F>, P<F, F>> [0.000, 30.000, 0.000, 0.000]
//   === X3t .move(edge: .top) remove
//     A P<P<F, F>, P<F, F>> [0.000, -30.000, 0.000, 0.000]
//   === X3b .move(edge: .bottom) remove
//     A P<P<F, F>, P<F, F>> [0.000, 30.000, 0.000, 0.000]
//   === X4 .scale insert
//     A P<P<F, F>, P<F, F>> [1.000, 1.000, 0.000, 0.000]
//   === X4 .scale remove
//     A P<P<F, F>, P<F, F>> [-1.000, -1.000, 0.000, 0.000]
//   === X4a .scale(scale: 0.5, anchor: .topLeading) insert
//     A P<P<F, F>, P<F, F>> [0.500, 0.500, 0.000, 0.000]
//   === X5 .slide insert
//     A P<P<F, F>, P<F, F>> [50.000, 0.000, 0.000, 0.000]
//   === X5 .slide remove
//     A P<P<F, F>, P<F, F>> [50.000, 0.000, 0.000, 0.000]
//   === X6 .asymmetric(insertion: .opacity, removal: .move(edge: .trailing)) insert
//     A Double [1.000]
//   === X6 .asymmetric(insertion: .opacity, removal: .move(edge: .trailing)) remove
//     A P<P<F, F>, P<F, F>> [50.000, 0.000, 0.000, 0.000]
//   === X7 .identity insert
//     (nothing animated)
//   === X7 .identity remove
//     (nothing animated)
//   === X8 .opacity.combined(with: .move(edge: .bottom)) insert
//     A Double [1.000]
//     A P<P<F, F>, P<F, F>> [0.000, -30.000, 0.000, 0.000]
//   === X9 .offset(x: 30, y: 5) insert
//     A P<P<F, F>, P<F, F>> [-30.000, -5.000, 0.000, 0.000]
//   === X10 .push(from: .leading) insert
//     A Double [1.000]
//     A P<P<F, F>, P<F, F>> [50.000, 0.000, 0.000, 0.000]
//   === X10 .push(from: .leading) remove
//     A Double [-1.000]
//     A P<P<F, F>, P<F, F>> [50.000, 0.000, 0.000, 0.000]
//   === X15 nested: if flag { VStack { red.transition(.move(edge: .leading)) } } insert (the transition is not on the inserted view)
//     A Double [1.000]
//   === X15b nested, with .transition(.identity) on the inserted VStack
//     (nothing animated)
//   === X16 .transition(.move) on a view that is always present; an unrelated opacity changes
//     A Double [-0.500]
//   === X11 ForEach insertion: items [1,2] -> [1,2,3], each .transition(.opacity)
//     A Double [1.000]
//     A P<P<F, F>, P<F, F>> [0.500, 0.000, 0.000, 0.000]
//   === X12 ForEach removal: items [1,2,3] -> [1,3], each .transition(.opacity)
//     A Double [-1.000]
//     A P<P<F, F>, P<F, F>> [0.000, -10.000, 0.000, 0.000]
//   === X13 .animation(A, value: flag) on the container, flag inserts an .opacity view
//     A Double [1.000]
//     A P<P<F, F>, P<F, F>> [10.000, 20.000, 0.000, 0.000]
//   === X14 .transition(.opacity) on an if's content under .transaction { $0.animation = nil } (inside the if)
//     A Double [1.000]
//     A P<P<F, F>, P<F, F>> [10.000, 20.000, 0.000, 0.000]
//   === R0 the system's setting and SwiftUI's reading, unmodified
//     NSWorkspace.accessibilityDisplayShouldReduceMotion = false
//   === R0 a reader view's @Environment(\.accessibilityReduceMotion)
//     (nothing animated)
//     reads: ["appear false"]
//   === R1 NSWorkspace getter swizzled in-process to answer true
//     NSWorkspace.accessibilityDisplayShouldReduceMotion = true
//   === R1 a reader view's @Environment(\.accessibilityReduceMotion), fresh host after the swizzle
//     (nothing animated)
//     reads: ["appear false"]
//   === R2 reader after posting accessibilityDisplayOptionsDidChangeNotification (swizzle true)
//     (nothing animated)
//     reads: ["appear true"]
//   === R3 withAnimation(A) { v } on .frame(width:), Reduce Motion reading true
//     A P<P<F, F>, P<F, F>> [0.000, 0.000, 200.000, 0.000]
//     reads: ["appear true"]
//   === R4 withAnimation(A) { v } on .opacity, Reduce Motion reading true
//     A Double [-0.500]
//     reads: ["appear true"]
//   === R5 .transition(.move(edge: .leading)) insertion, Reduce Motion reading true
//     A Double [1.000]
//     reads: ["appear true"]
//   === R5r .move(edge: .leading) remove, Reduce Motion reading true
//     A Double [-1.000]
//     reads: ["appear true"]
//   === R5s .scale insert, Reduce Motion reading true
//     A Double [1.000]
//     reads: ["appear true"]
//   === R5l .slide insert, Reduce Motion reading true
//     A Double [1.000]
//     reads: ["appear true"]
//   === R5o .offset(x: 30, y: 5) insert, Reduce Motion reading true
//     A Double [1.000]
//     reads: ["appear true"]
//   === R5p .push(from: .leading) insert, Reduce Motion reading true
//     A Double [1.000]
//     reads: ["appear true"]
//   === R5a .asymmetric(insertion: .move(edge: .top), removal: .scale) insert, Reduce Motion reading true
//     A Double [1.000]
//     reads: ["appear true"]
//   === R5c .opacity.combined(with: .move(edge: .bottom)) insert, Reduce Motion reading true
//     A Double [1.000]
//     reads: ["appear true"]
//   === R5i .identity insert, Reduce Motion reading true
//     (nothing animated)
//     reads: ["appear true"]
//   === R6 .animation(A, value: v), Reduce Motion reading true
//     A Double [-0.500]
//     reads: ["appear true"]
//   === R7 withAnimation(.default) { v } on .opacity, Reduce Motion true: a reader of the transaction's animation
//     (nothing animated)
//     reads: ["appear true"] transaction: ["animation DefaultAnimation()"]
//   === R8 reader after the swizzle answers false again and the notification is re-posted
//     (nothing animated)
//     reads: ["appear false"]
//   === R10 control: .move(edge: .leading) insert, Reduce Motion reading false
//     A P<P<F, F>, P<F, F>> [50.000, 0.000, 0.000, 0.000]
//     reads: ["appear false"]
//   === R10 control: .scale insert, Reduce Motion reading false
//     A P<P<F, F>, P<F, F>> [1.000, 1.000, 0.000, 0.000]
//     reads: ["appear false"]
//   === R9 control: withAnimation(.default) { v } on .opacity, Reduce Motion false: the transaction's animation
//     (nothing animated)
//     reads: ["appear false"] transaction: ["animation DefaultAnimation()"]

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

// ---------------------------------------------------------------- arms
MainActor.assumeIsolated {
NSApplication.shared.setActivationPolicy(.accessory)

// Controls
arm("C0 control: withAnimation(A) { v } on .frame(width: 100 + v)", { m in Color.red.frame(width: 100 + m.v, height: 20) },
    change: { m in withAnimation(A) { m.v = 200 } })
arm("C1 control: the same change with no transaction", { m in Color.red.frame(width: 100 + m.v, height: 20) },
    change: { m in m.v = 200 })
arm("C2 control: withAnimation(A) around a write that changes nothing", { m in Color.red.frame(width: 100 + m.v, height: 20) },
    change: { m in withAnimation(A) { m.v = 0 } })

// W: which wrapper animates, and as what value
arm("W1 .frame(width:) 100 -> 300 (fixed 20 high, top-leading)", { m in Color.red.frame(width: 100 + m.v, height: 20) },
    change: { m in withAnimation(A) { m.v = 200 } })
arm("W2 .padding 10 -> 30 around a 50x20 colour", { m in Color.red.frame(width: 50, height: 20).padding(10 + m.v).background(Color.blue) },
    change: { m in withAnimation(A) { m.v = 20 } })
arm("W3 .opacity 1 -> 0.2", { m in Color.red.frame(width: 50, height: 20).opacity(1 - m.v) },
    change: { m in withAnimation(A) { m.v = 0.8 } })
arm("W4 .background(red -> blue) on a fixed frame", { m in Color.clear.frame(width: 50, height: 20).background(m.v == 0 ? Color.red : Color.blue) },
    change: { m in withAnimation(A) { m.v = 1 } })
arm("W5 .border(black, width: 1 -> 5)", { m in Color.clear.frame(width: 50, height: 20).border(Color.black, width: 1 + m.v) },
    change: { m in withAnimation(A) { m.v = 4 } })
arm("W5c .border(red -> blue, width: 2)", { m in Color.clear.frame(width: 50, height: 20).border(m.v == 0 ? Color.red : Color.blue, width: 2) },
    change: { m in withAnimation(A) { m.v = 1 } })
arm("W6 .clipShape(RoundedRectangle(cornerRadius: 2 -> 12))", { m in Color.red.frame(width: 50, height: 20).clipShape(RoundedRectangle(cornerRadius: 2 + m.v)) },
    change: { m in withAnimation(A) { m.v = 10 } })
arm("W7 .frame(maxWidth: 100 -> 300) over a greedy colour", { m in Color.red.frame(maxWidth: 100 + m.v, maxHeight: 20) },
    change: { m in withAnimation(A) { m.v = 200 } })
arm("W8 .overlay(alignment: .leading) { blue.frame(width: 10 -> 40) } on a 50x20", { m in Color.red.frame(width: 50, height: 20).overlay(alignment: .leading) { Color.blue.frame(width: 10 + m.v) } },
    change: { m in withAnimation(A) { m.v = 30 } })
arm("W9 Rectangle().fill(red -> blue)", { m in Rectangle().fill(m.v == 0 ? Color.red : Color.blue).frame(width: 50, height: 20) },
    change: { m in withAnimation(A) { m.v = 1 } })
arm("W10 .clipped() added where it was absent (structure change)", { m in Group { if m.v == 0 { Color.red.frame(width: 50, height: 20) } else { Color.red.frame(width: 50, height: 20).clipped() } } },
    change: { m in withAnimation(A) { m.v = 1 } })
arm("W11 HStack(spacing: 0 -> 20) { 20x20; 20x20 }", { m in HStack(spacing: m.v) { Color.red.frame(width: 20, height: 20); Color.blue.frame(width: 20, height: 20) } },
    change: { m in withAnimation(A) { m.v = 20 } })

// P: is layout re-run at interpolated inputs, or once at the final ones?
arm("P1 a custom Layout inside .frame(width: 100 -> 300): the widths it was proposed", { m in WidthLog { Color.red }.frame(width: 100 + m.v, height: 20) },
    change: { m in withAnimation(A) { m.v = 200 } })
print("  proposed widths seen by the child layout during the animation: \(layoutWidths.sorted())")
arm("P2 a Text inside .frame(width: 60 -> 200) that wraps at 60", { m in Text("wrapping words here").frame(width: 60 + m.v, alignment: .leading) },
    change: { m in withAnimation(A) { m.v = 140 } })

// T: transactions
arm("T1 .animation(A, value: v); v changes, no withAnimation", { m in Color.red.frame(width: 50, height: 20).opacity(1 - m.v).animation(A, value: m.v) },
    change: { m in m.v = 0.5 })
arm("T2 .animation(A, value: v); only u changes (u drives the opacity)", { m in Color.red.frame(width: 50, height: 20).opacity(1 - m.u).animation(A, value: m.v) },
    change: { m in m.u = 0.5 })
arm("T3 scope: HStack { X.opacity(1-v/2).animation(A, value: v); Y.opacity(1-v*0.8) }", { m in HStack { Color.red.frame(width: 20, height: 20).opacity(1 - m.v / 2).animation(A, value: m.v); Color.blue.frame(width: 20, height: 20).opacity(1 - m.v * 0.8) } },
    change: { m in m.v = 1 })
arm("T3b order: X.animation(A, value: v).opacity(1 - v/2) -- the modifier written AFTER .animation", { m in Color.red.frame(width: 20, height: 20).animation(A, value: m.v).opacity(1 - m.v / 2) },
    change: { m in m.v = 1 })
arm("T4 withAnimation(A) { v } with .animation(B, value: v) on the subtree", { m in Color.red.frame(width: 50, height: 20).opacity(1 - m.v).animation(B, value: m.v) },
    change: { m in withAnimation(A) { m.v = 0.5 } })
arm("T4n withAnimation(A) { v } with .animation(nil, value: v) on the subtree", { m in Color.red.frame(width: 50, height: 20).opacity(1 - m.v).animation(nil, value: m.v) },
    change: { m in withAnimation(A) { m.v = 0.5 } })
arm("T5 withTransaction(Transaction(animation: A)) { v }", { m in Color.red.frame(width: 50, height: 20).opacity(1 - m.v) },
    change: { m in withTransaction(Transaction(animation: A)) { m.v = 0.5 } })
arm("T5n withTransaction(Transaction(animation: nil)) { v }", { m in Color.red.frame(width: 50, height: 20).opacity(1 - m.v) },
    change: { m in withTransaction(Transaction(animation: nil)) { m.v = 0.5 } })
arm("T6 withAnimation(A) { v }; X has .transaction { $0.animation = nil }, Y none (X 1->0.5, Y 1->0.2)", { m in HStack { Color.red.frame(width: 20, height: 20).opacity(1 - m.v / 2).transaction { $0.animation = nil }; Color.blue.frame(width: 20, height: 20).opacity(1 - m.v * 0.8) } },
    change: { m in withAnimation(A) { m.v = 1 } })
arm("T7 withAnimation(A) { v } with .transaction { $0.animation = B }", { m in Color.red.frame(width: 50, height: 20).opacity(1 - m.v).transaction { $0.animation = B } },
    change: { m in withAnimation(A) { m.v = 0.5 } })
arm("T7c no transaction at all, with .transaction { $0.animation = B }", { m in Color.red.frame(width: 50, height: 20).opacity(1 - m.v).transaction { $0.animation = B } },
    change: { m in m.v = 0.5 })
arm("T8 withTransaction(disablesAnimations, animation A) { v } with .animation(B, value: v) below", { m in Color.red.frame(width: 50, height: 20).opacity(1 - m.v).animation(B, value: m.v) },
    change: { m in var t = Transaction(animation: A); t.disablesAnimations = true; withTransaction(t) { m.v = 0.5 } })
arm("T8b withTransaction(disablesAnimations, animation nil) { v } with .animation(B, value: v) below", { m in Color.red.frame(width: 50, height: 20).opacity(1 - m.v).animation(B, value: m.v) },
    change: { m in var t = Transaction(); t.disablesAnimations = true; withTransaction(t) { m.v = 0.5 } })
arm("T8c withTransaction(disablesAnimations, animation A) { v }, no .animation below", { m in Color.red.frame(width: 50, height: 20).opacity(1 - m.v) },
    change: { m in var t = Transaction(animation: A); t.disablesAnimations = true; withTransaction(t) { m.v = 0.5 } })
arm("T9 nesting: withAnimation(A) { withAnimation(B) { a = 0.5 }; b = 0.2 }  (X reads a, Y reads b)", { m in HStack { Color.red.frame(width: 20, height: 20).opacity(1 - m.a); Color.blue.frame(width: 20, height: 20).opacity(1 - m.b) } },
    change: { m in withAnimation(A) { withAnimation(B) { m.a = 0.5 }; m.b = 0.2 } })
arm("T10 two calls in one interval: withAnimation(A) { a = 0.5 }; withAnimation(B) { b = 0.2 }", { m in HStack { Color.red.frame(width: 20, height: 20).opacity(1 - m.a); Color.blue.frame(width: 20, height: 20).opacity(1 - m.b) } },
    change: { m in withAnimation(A) { m.a = 0.5 }; withAnimation(B) { m.b = 0.2 } })
arm("T11 Binding.animation(A): a write through $v.animation(A)", { m in Color.red.frame(width: 50, height: 20).opacity(1 - m.v) },
    change: { m in let bnd = Binding(get: { m.v }, set: { m.v = $0 }).animation(A); bnd.wrappedValue = 0.5 })
arm("T12 Binding.transaction(Transaction(animation: A))", { m in Color.red.frame(width: 50, height: 20).opacity(1 - m.v) },
    change: { m in let bnd = Binding(get: { m.v }, set: { m.v = $0 }).transaction(Transaction(animation: A)); bnd.wrappedValue = 0.5 })
tagsOnly = true
arm("T13 retarget mid-flight: withAnimation(A) { v = 200 }, then 0.05 s later withAnimation(B) { v = 0 } (tags only)", { m in Color.red.frame(width: 100 + m.v, height: 20) },
    change: { m in withAnimation(A) { m.v = 200 }; spin(0.05); withAnimation(B) { m.v = 0 } })
tagsOnly = false
// @State-backed bindings, written through a binding captured from body
arm("T11s @State: a write through $v.animation(A)", { _ in StateBindingView(kind: 1) }, change: { _ in capturedBinding!.wrappedValue = 0.5 })
arm("T11c @State control: a write through plain $v", { _ in StateBindingView(kind: 0) }, change: { _ in capturedBinding!.wrappedValue = 0.5 })
arm("T12s @State: a write through $v.transaction(Transaction(animation: A))", { _ in StateBindingView(kind: 2) }, change: { _ in capturedBinding!.wrappedValue = 0.5 })

// X: transitions (insertion = flag false -> true, removal = true -> false)
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
arm("X00 VStack: removing the first of two (50x30 .opacity, then 30x10): the sibling's shift", { m in
    VStack(alignment: .leading, spacing: 0) { if m.flag { Color.red.frame(width: 50, height: 30).transition(.opacity) }; Color.blue.frame(width: 30, height: 10) }
}, setup: { m in m.flag = true }, change: { m in withAnimation(A) { m.flag = false } })
tx("X0 no .transition (the default)", nil, insert: true)
tx("X0 no .transition (the default)", nil, insert: false)
tx("X1 .opacity", .opacity, insert: true)
tx("X1 .opacity", .opacity, insert: false)
tx("X1n .opacity with NO transaction", .opacity, insert: true, animated: false)
tx("X1n .opacity with NO transaction", .opacity, insert: false, animated: false)
tx("X2 .move(edge: .leading)", .move(edge: .leading), insert: true)
tx("X2 .move(edge: .leading)", .move(edge: .leading), insert: false)
tx("X3 .move(edge: .trailing)", .move(edge: .trailing), insert: true)
tx("X3t .move(edge: .top)", .move(edge: .top), insert: true)
tx("X3t .move(edge: .top)", .move(edge: .top), insert: false)
tx("X3b .move(edge: .bottom)", .move(edge: .bottom), insert: false)
tx("X4 .scale", .scale, insert: true)
tx("X4 .scale", .scale, insert: false)
tx("X4a .scale(scale: 0.5, anchor: .topLeading)", .scale(scale: 0.5, anchor: .topLeading), insert: true)
tx("X5 .slide", .slide, insert: true)
tx("X5 .slide", .slide, insert: false)
tx("X6 .asymmetric(insertion: .opacity, removal: .move(edge: .trailing))", .asymmetric(insertion: .opacity, removal: .move(edge: .trailing)), insert: true)
tx("X6 .asymmetric(insertion: .opacity, removal: .move(edge: .trailing))", .asymmetric(insertion: .opacity, removal: .move(edge: .trailing)), insert: false)
tx("X7 .identity", .identity, insert: true)
tx("X7 .identity", .identity, insert: false)
tx("X8 .opacity.combined(with: .move(edge: .bottom))", .opacity.combined(with: .move(edge: .bottom)), insert: true)
tx("X9 .offset(x: 30, y: 5)", .offset(x: 30, y: 5), insert: true)
tx("X10 .push(from: .leading)", .push(from: .leading), insert: true)
tx("X10 .push(from: .leading)", .push(from: .leading), insert: false)
arm("X15 nested: if flag { VStack { red.transition(.move(edge: .leading)) } } insert (the transition is not on the inserted view)", { m in
    ZStack(alignment: .topLeading) { Color.blue.frame(width: 30, height: 10); if m.flag { VStack { Color.red.frame(width: 50, height: 30).transition(.move(edge: .leading)) } } }
}, change: { m in withAnimation(A) { m.flag = true } })
arm("X15b nested, with .transition(.identity) on the inserted VStack", { m in
    ZStack(alignment: .topLeading) { Color.blue.frame(width: 30, height: 10); if m.flag { VStack { Color.red.frame(width: 50, height: 30).transition(.move(edge: .leading)) }.transition(.identity) } }
}, change: { m in withAnimation(A) { m.flag = true } })
arm("X16 .transition(.move) on a view that is always present; an unrelated opacity changes", { m in
    Color.red.frame(width: 50, height: 30).opacity(1 - m.v).transition(.move(edge: .leading))
}, change: { m in withAnimation(A) { m.v = 0.5 } })

arm("X11 ForEach insertion: items [1,2] -> [1,2,3], each .transition(.opacity)", { m in
    VStack(spacing: 0) { ForEach(m.items, id: \.self) { i in Color.red.frame(width: 20 + CGFloat(i), height: 10).transition(.opacity) } }
}, change: { m in withAnimation(A) { m.items = [1, 2, 3] } })
arm("X12 ForEach removal: items [1,2,3] -> [1,3], each .transition(.opacity)", { m in
    VStack(spacing: 0) { ForEach(m.items, id: \.self) { i in Color.red.frame(width: 20 + CGFloat(i), height: 10).transition(.opacity) } }
}, setup: { m in m.items = [1, 2, 3] }, change: { m in withAnimation(A) { m.items = [1, 3] } })
arm("X13 .animation(A, value: flag) on the container, flag inserts an .opacity view", { m in
    VStack(spacing: 0) { if m.flag { Color.red.frame(width: 50, height: 20).transition(.opacity) }; Color.blue.frame(width: 30, height: 10) }.animation(A, value: m.flag)
}, change: { m in m.flag = true })
arm("X14 .transition(.opacity) on an if's content under .transaction { $0.animation = nil } (inside the if)", { m in
    VStack(spacing: 0) { if m.flag { Color.red.frame(width: 50, height: 20).transition(.opacity).transaction { $0.animation = nil } }; Color.blue.frame(width: 30, height: 10) }
}, change: { m in withAnimation(A) { m.flag = true } })

// R: Reduce Motion
print("=== R0 the system's setting and SwiftUI's reading, unmodified")
print("  NSWorkspace.accessibilityDisplayShouldReduceMotion = \(NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)")
arm("R0 a reader view's @Environment(\\.accessibilityReduceMotion)", { _ in RMReader() }, change: { _ in })
print("  reads: \(rmReads)"); rmReads.removeAll()
installReduceMotionSwizzle()
forceReduceMotion = true
print("=== R1 NSWorkspace getter swizzled in-process to answer true")
print("  NSWorkspace.accessibilityDisplayShouldReduceMotion = \(NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)")
arm("R1 a reader view's @Environment(\\.accessibilityReduceMotion), fresh host after the swizzle", { _ in RMReader() }, change: { _ in })
print("  reads: \(rmReads)"); rmReads.removeAll()
NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: NSWorkspace.shared)
spin(0.1)
arm("R2 reader after posting accessibilityDisplayOptionsDidChangeNotification (swizzle true)", { _ in RMReader() }, change: { _ in })
print("  reads: \(rmReads)"); rmReads.removeAll()
arm("R3 withAnimation(A) { v } on .frame(width:), Reduce Motion reading true", { m in HStack { RMReader(); Color.red.frame(width: 100 + m.v, height: 20) } },
    change: { m in withAnimation(A) { m.v = 200 } })
print("  reads: \(rmReads)"); rmReads.removeAll()
arm("R4 withAnimation(A) { v } on .opacity, Reduce Motion reading true", { m in HStack { RMReader(); Color.red.frame(width: 50, height: 20).opacity(1 - m.v) } },
    change: { m in withAnimation(A) { m.v = 0.5 } })
print("  reads: \(rmReads)"); rmReads.removeAll()
arm("R5 .transition(.move(edge: .leading)) insertion, Reduce Motion reading true", { m in
    ZStack(alignment: .topLeading) { RMReader(); if m.flag { Color.red.frame(width: 50, height: 30).transition(.move(edge: .leading)) } }
}, change: { m in withAnimation(A) { m.flag = true } })
print("  reads: \(rmReads)"); rmReads.removeAll()
@MainActor func rmtx(_ name: String, _ t: AnyTransition, insert: Bool) {
    arm("\(name) \(insert ? "insert" : "remove"), Reduce Motion reading \(forceReduceMotion)", { m in
        ZStack(alignment: .topLeading) { RMReader(); if m.flag { Color.red.frame(width: 50, height: 30).transition(t) } }
    }, setup: { m in m.flag = !insert }, change: { m in withAnimation(A) { m.flag = insert } })
    print("  reads: \(rmReads)"); rmReads.removeAll()
}
rmtx("R5r .move(edge: .leading)", .move(edge: .leading), insert: false)
rmtx("R5s .scale", .scale, insert: true)
rmtx("R5l .slide", .slide, insert: true)
rmtx("R5o .offset(x: 30, y: 5)", .offset(x: 30, y: 5), insert: true)
rmtx("R5p .push(from: .leading)", .push(from: .leading), insert: true)
rmtx("R5a .asymmetric(insertion: .move(edge: .top), removal: .scale)", .asymmetric(insertion: .move(edge: .top), removal: .scale), insert: true)
rmtx("R5c .opacity.combined(with: .move(edge: .bottom))", .opacity.combined(with: .move(edge: .bottom)), insert: true)
rmtx("R5i .identity", .identity, insert: true)
arm("R6 .animation(A, value: v), Reduce Motion reading true", { m in HStack { RMReader(); Color.red.frame(width: 50, height: 20).opacity(1 - m.v).animation(A, value: m.v) } },
    change: { m in m.v = 0.5 })
print("  reads: \(rmReads)"); rmReads.removeAll()
arm("R7 withAnimation(.default) { v } on .opacity, Reduce Motion true: a reader of the transaction's animation", { m in HStack { RMReader(); Color.red.frame(width: 50, height: 20).opacity(1 - m.v).transaction { t in txReads.append("animation \(t.animation.map { String(describing: $0) } ?? "nil")") } } },
    change: { m in withAnimation(.default) { m.v = 0.5 } })
print("  reads: \(rmReads) transaction: \(Array(Set(txReads)).sorted())"); rmReads.removeAll(); txReads.removeAll()
forceReduceMotion = false
NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: NSWorkspace.shared)
spin(0.1)
arm("R8 reader after the swizzle answers false again and the notification is re-posted", { _ in RMReader() }, change: { _ in })
print("  reads: \(rmReads)"); rmReads.removeAll()
rmtx("R10 control: .move(edge: .leading)", .move(edge: .leading), insert: true)
rmtx("R10 control: .scale", .scale, insert: true)
arm("R9 control: withAnimation(.default) { v } on .opacity, Reduce Motion false: the transaction's animation", { m in HStack { RMReader(); Color.red.frame(width: 50, height: 20).opacity(1 - m.v).transaction { t in txReads.append("animation \(t.animation.map { String(describing: $0) } ?? "nil")") } } },
    change: { m in withAnimation(.default) { m.v = 0.5 } })
print("  reads: \(rmReads) transaction: \(Array(Set(txReads)).sorted())"); rmReads.removeAll(); txReads.removeAll()
}
