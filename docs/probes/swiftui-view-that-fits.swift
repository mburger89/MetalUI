// SwiftUI probe: `ViewThatFits` (rulings `VF-` in docs/superpowers/2026-11-06-view-that-fits-decisions.md,
// record 217). Which candidate it chooses and from what, what it proposes to the candidates and the chosen
// one, what it answers its parent, what it does to its first child's spacing edge, and what an unchosen
// candidate does (state, lifecycle, shortcuts, accessibility, alerts, focus).
//
// HOW TO RUN (SA-O's compiled form; no JIT shim; no computer use, the screen may be locked):
//
//   xcrun swiftc -swift-version 6 docs/probes/swiftui-view-that-fits.swift -o /tmp/vtf-probe
//   /tmp/vtf-probe > /tmp/vtf-1.txt; /tmp/vtf-probe > /tmp/vtf-2.txt; cmp /tmp/vtf-1.txt /tmp/vtf-2.txt
//
// INSTRUMENT. Measurement arms host a `Measure` layout (it asks its one subview a proposal and places it at the
// same proposal) in an `NSHostingView`; a candidate is an `Ask` layout (a leaf that logs the proposal it is
// asked and answers a closure of it), so which candidates were measured, in what order and with what proposal
// is the log. **A `Layout` with no subviews never gets `placeSubviews`, so a choice is read from the one
// candidate that was asked the whole proposal.** `NSHostingView` lays out several times per arm and the log is
// de-duplicated (first occurrence kept): **a call count is not a reading, only presence and order are**.
// Behaviour arms use a key `NSWindow` and `performKeyEquivalent`. **`NSApplication.shared` is initialised first
// (without it `NSApp` is nil and the first behaviour arm crashes).** Every key event uses keyCode 0 whatever
// its character: the chosen key firing in the same window is the separating control. `accessibilityLabel` of a
// `Text` is empty (value-based), so the AX arms read buttons. `navigationTitle` and toolbar items cannot be
// measured with a bare hosting view (no scene).
//
// ARM IDS. The plan's arms were run as `swift -` scripts that were not kept; this file rebuilds them from the
// plan's tables with the same ids (`H1`, `V1`, `H2`, `B1`, `W1`, `W2`, `Z1`, `P1`..`P3`, `S1`, `E2`/`E3`, `F1`..`F4`,
// `I1`..`I6`, `PR1`/`PR2`, `N1`, `SP0`..`SP2`, `S0`, `K1`, `K4`, `R1`..`R3`, `T1`..`T4`, `WR`, `AX`, `X0`..`X3`,
// `FO`). Where a setup was not recoverable from a table (the candidates of `I3`, `PR1`/`PR2`, `P1`/`P2`) it is
// stated at the arm.
//
// NOT MEASURED / NOT RECOVERABLE. `I3`'s and `P1`/`P2`'s exact candidates and `PR1`/`PR2`'s were not in the
// plan's tables; the setups here are stated at the arms. **`PR1`/`PR2`/`PR0` here do not separate (all three
// read the same), so "a `.layoutPriority(1)` on the VTF works, on its only child it is not passed through" is
// the plan's reading, NOT re-taken by this file.** Also unmeasured: that SwiftUI's `ViewThatFits {}` answers
// zero, that a switch is not animated, an unchosen candidate's `navigationTitle` / toolbar items, a `Spacer` as
// a candidate, a custom parent placing the VTF in larger bounds (the plan's "inferred" list).
//
// RECORDED 2026-11-06, macOS 27.2, Apple Swift 6.4.2, Mac session LOCKED (no computer use, no pixels read; the
// `NSWindow`s order front regardless and `performKeyEquivalent` is called on them). Compiled form, run three
// times: stdout byte-identical (146 lines, shasum ddfed0677f04efe5df2933cb230e5bf71cad23ad), exit 0, stderr empty.
//
// DIFFERENCES FROM THE PLAN'S TABLES (the implementation follows this file):
// - **S0 / S0b: the plan read "`@StateObject` made for A and B, not C". Here it is made for EVERY candidate**, including
//   C (and D) when A is the chosen one in a 1000 pt window, so SwiftUI creates the state of the candidates after the
//   chosen one too. Divergence 220 (a later candidate's `@State` seeds on the first frame) is therefore
//   narrower than the plan said: SwiftUI also seeds it early here. Not understood: the instrument differs from the
//   plan's (a pre-sized `NSHostingView` as an `NSWindow` content view; `sizingOptions = []` read the same).
// - `T`: the plan's "switches at W=105" is read with a 0.5 pt sweep as: `Mirror` is wide from W=106 (More at
//   105.5), `Mirror \u{2713}` from W=121. At W=106 the label change `Mirror` -> `Mirror \u{2713}` switches to More
//   (the plan's reading holds); the second number is this setup's, not the plan's.
// - `I5`: offered W-8 in the plan; here `HStack(spacing: 0) { VTF; Spacer() }` offers 192 = W-8 (the first
//   version of the arm with spacing 8 offered 184 = W-16: the Spacer's 8 minimum plus the 8 spacing).
// - `I2` uses `B1`'s candidates (the plan's arm did too). `P1`/`P2` read the VTF's placed rect (`Bounds`; the
//   second `rect` is the final pass, the hosting view is 400 wide so a 200 frame sits at x=100 and a 10 frame at
//   x=195): P1 60x20 at x=170 = centred in the frame (offset 70), P2 30x20 at x=185 = 10 pt left of the frame
//   (the plan's x = -10). Both as the plan says.
// - Everything else in the plan's tables (H1, V1, H2, B1, W1, W2, Z1, P3, S1, E2, E3, F1..F4, I1, I3, I4, I6,
//   N1, SP0..SP2, AX, K1, K4, R1..R3, WR, X0..X3, FO) read as the plan says.
//
// OUTPUT, verbatim:
//
//   --- H: .horizontal {a100, b60, c30} (20 tall), height 50
//     H1 W=101 chosen=a answer=answer 100x20 asks=a(nil,50) a(101,50)
//     H1 W=100 chosen=a answer=answer 100x20 asks=a(nil,50) a(100,50)
//     H1 W=99.5 chosen=b answer=answer 60x20 asks=a(nil,50) a(99.5,50) b(nil,50) b(99.5,50)
//     H1 W=60.5 chosen=b answer=answer 60x20 asks=a(nil,50) a(60.5,50) b(nil,50) b(60.5,50)
//     H1 W=60 chosen=b answer=answer 60x20 asks=a(nil,50) a(60,50) b(nil,50) b(60,50)
//     H1 W=59.99 chosen=c answer=answer 30x20 asks=a(nil,50) a(59.99,50) b(nil,50) b(59.99,50) c(nil,50) c(59.99,50)
//     H1 W=30 chosen=c answer=answer 30x20 asks=a(nil,50) a(30,50) b(nil,50) b(30,50) c(nil,50) c(30,50)
//     H1 W=29 chosen=c answer=answer 30x20 asks=a(nil,50) a(29,50) b(nil,50) b(29,50) c(nil,50) c(29,50)
//   --- V: .vertical {a h100, b h60, c h30} (20 wide), width 50
//     V1 H=100 chosen=a answer=answer 20x100 asks=a(50,nil) a(50,100)
//     V1 H=99.5 chosen=b answer=answer 20x60 asks=a(50,nil) a(50,99.5) b(50,nil) b(50,99.5)
//     V1 H=30 chosen=c answer=answer 20x30 asks=a(50,nil) a(50,30) b(50,nil) b(50,30) c(50,nil) c(50,30)
//   --- H2: .horizontal, a child 200 tall, height 10
//     H2 chosen=a answer=answer 100x200 asks=a(nil,10) a(150,10)
//   --- B: both axes {a 100x40, b 60x10, c 30x30}
//     B1 120x50 chosen=a answer=answer 100x40 asks=a(nil,nil) a(120,50)
//     B1 120x15 chosen=b answer=answer 60x10 asks=a(nil,nil) a(120,15) b(nil,nil) b(120,15)
//     B1 50x50 chosen=c answer=answer 30x30 asks=a(nil,nil) a(50,50) b(nil,nil) b(50,50) c(nil,nil) c(50,50)
//     B1 20x10 chosen=c answer=answer 30x30 asks=a(nil,nil) a(20,10) b(nil,nil) b(20,10) c(nil,nil) c(20,10)
//   --- W: the fit test is the ideal alone (W=100)
//     W1 ideal 50 answer 150: chosen=x asks=x(nil,50) x(100,50)
//     W2 ideal 150 answer 50: chosen=y asks=x(nil,50) x(100,50) y(nil,50) y(100,50)
//     Z1 ideal 0 at W=0: chosen=z answer=answer 0x20
//   --- P: frames and padding around the chosen candidate (Bounds logs the VTF's placed rect)
//     P1 chosen 60 (a is 300) in a 200 frame: rect 0,0,60,20 rect 170,40,60,20
//     P2 fallback 30 (a is 100) in a 10 frame: rect 0,0,30,20 rect 185,40,30,20
//     P3 .padding(8) in a candidate, W=100 (a is 116 wide with it): asks=a(nil,34) a(84,34) b(nil,50) b(100,50) answer=answer 60x20
//   --- E2/E3/S1: ForEach, Group, ScrollView
//     E2 ForEach {100,60,30} at W=70: chosen=f60 answer=answer 60x20
//     E3 Group {100,60} + 30 at W=70: chosen=g60 answer=answer 60x20
//     S1 inside ScrollView(.horizontal) at W=70: asks=s1(nil,50) s1(nil,20) answer=answer 70x20
//   --- F: flexible candidates. Ideal alone at (nil,50), then the choice against a fallback (10x20) at W=40/70/200
//     F1 HStack(spacing:0){50; Spacer()}: ideal answer 58x20; W=40 answer 10x20 | W=70 answer 70x20 | W=200 answer 200x20
//     F1m Spacer(minLength:0): ideal answer 50x20; W=40 answer 10x20 | W=70 answer 70x20 | W=200 answer 200x20
//     F2 Color.frame(maxWidth:.infinity): ideal answer 10x50; W=40 answer 40x50 | W=70 answer 70x50 | W=200 answer 200x50
//     F2b {50; Color.clear.frame(maxWidth:inf,maxHeight:inf).contentShape} (the app's WindowDragHandle shape): ideal answer 60x50; W=40 answer 10x20 | W=70 answer 70x50 | W=200 answer 200x50
//     F3 Text("Hello wide world"): ideal answer 100x16; W=40 answer 10x20 | W=70 answer 10x20 | W=200 answer 100x16
//     F4 frame(minWidth:80, maxWidth:.infinity): ideal answer 80x20; W=40 answer 10x20 | W=70 answer 10x20 | W=200 answer 200x20
//   --- I: what the VTF reports to its parent
//     I1 .horizontal {100,60,30 x20}: (nil,nil)=100x20, (0,0)=30x20, (inf,inf)=100x20, (50,nil)=30x20, (nil,10)=100x20, (80,50)=60x20
//     I2 both axes {100x40, 60x10, 30x30} (nil,10): 60x10
//     I3 .vertical {20x100, 40x80, 70x60}: (0,0)=70x60, (50,nil)=20x100
//     I4 HStack(spacing:0){VTF; 50} at W=200: answer 150x20 asks=a(nil,50) a(150,50)
//     I4 HStack(spacing:0){VTF; 50} at W=120: answer 110x20 asks=a(nil,50) a(70,50) b(nil,50) b(70,50)
//     I4 HStack(spacing:0){VTF; 50} at W=70: answer 80x20 asks=a(nil,50) a(20,50) b(nil,50) b(20,50) c(nil,50) c(20,50)
//     I5 HStack(spacing:0){VTF; Spacer()} at W=200: asks=a(nil,50) a(192,50)
//     I6 .fixedSize(): asks=a(nil,nil) answer=answer 100x20
//   --- PR: layout priority (setup chosen here: HStack(spacing:0){VTF{a: greedy, ideal 150; b: greedy, ideal 90}; g: greedy, ideal 10}, W=200)
//     PR1 .layoutPriority(1) on the VTF: asks=g(0,50) a(nil,50) a(200,50) answer=answer 200x20
//     PR2 .layoutPriority(1) on its candidate: asks=g(0,50) a(nil,50) a(200,50) answer=answer 200x20
//     PR0 control, none: asks=g(0,50) a(nil,50) a(200,50) answer=answer 200x20
//   --- N1: nested {{150, 90}, 40}
//     N1 W=160: chosen=i150 answer=answer 150x20
//     N1 W=100: chosen=o40 answer=answer 40x20
//     N1 W=60: chosen=o40 answer=answer 40x20
//   --- SP: the spacing edge in a VStack under a Text
//     SP0 control Text then Text: y=16
//     SP0b control Text then Color: y=24
//     SP1 {Text; Color} (the Text is the first, chosen): y=16
//     SP1' {Text; Color} with a width that picks the Color: y=16
//     SP2 {Color(unchosen); Text(chosen)}: y=24
//   --- BEHAVIOUR (key window, performKeyEquivalent)
//   --- S0/K1/AX/R: three candidates A(400,a) B(150,b) C(10,c) in a 300 window
//       made storage A#1
//       made storage B#2
//       made storage C#3
//       appear B obj#2 n=0
//     S0 above: @StateObject made for which candidates; appear for which
//     AX0 buttons in the AX tree: ["B"]
//       key a handled=false
//       fire B n=1
//       key b handled=true
//       key c handled=false
//       fire B n=2
//       key b handled=true
//       fire B n=3
//       key b handled=true
//     R1 shrink to 50 (content size)
//       disappear B
//       appear C obj#3 n=0
//     AX1 buttons: ["C"]
//     R2 back to 300
//       disappear C
//       appear B obj#2 n=3
//       fire B n=4
//       key b handled=true
//     R3 widen to 500
//       disappear B
//       appear A obj#1 n=0
//   --- S0b: which candidates' storage is made when the first candidate is chosen (A400 B150 C10 D5 in a 1000 window) and when B is (300 window)
//       made storage A#1
//       made storage B#2
//       made storage C#3
//       made storage D#4
//       appear A obj#1 n=0
//     S0b 1000 done
//       made storage A#1
//       made storage B#2
//       made storage C#3
//       made storage D#4
//       appear B obj#2 n=0
//     S0b 300 done
//   --- K4: three candidates sharing key g (widths 400, 150, 10) in a 300 window
//       made storage G1#5
//       made storage G2#6
//       made storage G3#7
//       appear G2 obj#6 n=0
//       fire G2 n=1
//       key g handled=true
//   --- T: label change and resize ({HStack{label; Text("Other tool")}; Text("More")}, default HStack spacing): the smallest W (0.5 steps) whose answer is the wide one
//     T Mirror: first wide W = 106 (answer 106x16)
//     T Mirror ✓: first wide W = 121 (answer 121x16)
//   --- WR: window resize 600 -> 300 -> 600 switches both ways
//       made storage A#8
//       made storage B#9
//       made storage C#10
//       appear A obj#8 n=0
//     WR0 600: ["A"]
//       disappear A
//       appear B obj#9 n=0
//     WR1 300: ["B"]
//       disappear B
//       appear A obj#8 n=0
//     WR2 600: ["A"]
//   --- X: lifecycle in an unchosen candidate (wide 400 unchosen in a 300 window, mid 150 chosen)
//       geometry mid 150
//       task mid
//       appear mid
//       onChange mid 1
//     X0 sheet=false
//       geometry mid 400
//       geometry wide 400
//       task wide
//       appear wide
//       onChange wide 1
//     X2 after widening to 600 (wide chosen) sheet=true
//   --- X3: control, the same alert outside a VTF
//     X3 sheet=true
//   --- FO: a focused TextField in the wide candidate
//       focus wide=true
//     FO0 wide, responder=_SystemTextFieldFieldEditor
//       focus wide=false
//     FO1 narrow, responder=NSWindow (is window: true)
//     FO2 wide again, responder=NSWindow
//   --- end

import AppKit
import SwiftUI

nonisolated(unsafe) var asks: [String] = []
nonisolated(unsafe) var events: [String] = []
func fmtN(_ v: CGFloat?) -> String {
    guard let v else { return "nil" }
    if v == .infinity { return "inf" }
    return v == v.rounded() ? "\(Int(v))" : "\(v)"
}
func fmt(_ p: ProposedViewSize) -> String { "(\(fmtN(p.width)),\(fmtN(p.height)))" }
func fmt(_ s: CGSize) -> String { "\(fmtN(s.width))x\(fmtN(s.height))" }
func log(_ s: String) { print(s); fflush(stdout) }
func dedupe(_ xs: [String]) -> [String] {
    var seen = Set<String>(), out: [String] = []
    for x in xs where seen.insert(x).inserted { out.append(x) }
    return out
}
@MainActor func spin(_ s: Double = 0.15) { RunLoop.main.run(until: Date().addingTimeInterval(s)) }

/// A candidate leaf: logs every proposal and answers a closure of it.
struct Ask: Layout {
    let name: String
    let answer: (ProposedViewSize) -> CGSize
    init(_ name: String, _ w: CGFloat, _ h: CGFloat) { self.name = name; self.answer = { _ in CGSize(width: w, height: h) } }
    init(_ name: String, answer: @escaping (ProposedViewSize) -> CGSize) { self.name = name; self.answer = answer }
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        asks.append("\(name)\(fmt(proposal))")
        return answer(proposal)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {}
}

/// Asks its one subview a proposal, answers what it answered, places it at that proposal.
struct Measure: Layout {
    let proposal: ProposedViewSize
    let label: String
    func sizeThatFits(proposal _: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let s = subviews[0].sizeThatFits(proposal)
        events.append("answer \(fmt(s))")
        return s
    }
    func placeSubviews(in bounds: CGRect, proposal _: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews[0].place(at: bounds.origin, proposal: proposal)
    }
}

@MainActor func host<V: View>(_ v: V) -> NSHostingView<V> {
    let h = NSHostingView(rootView: v)
    h.frame = CGRect(x: 0, y: 0, width: 600, height: 400)
    h.layoutSubtreeIfNeeded()
    return h
}

/// Runs a measuring arm: returns the de-duplicated ask log and the VTF's answer.
@MainActor func run<V: View>(_ p: ProposedViewSize, @ViewBuilder _ v: () -> V) -> (asks: [String], answer: String) {
    asks = []; events = []
    _ = host(Measure(proposal: p, label: "") { v() })
    return (dedupe(asks), dedupe(events).last ?? "no-answer")
}

func ph(_ w: CGFloat?, _ h: CGFloat?) -> ProposedViewSize { ProposedViewSize(width: w, height: h) }
func cands() -> [(String, CGFloat, CGFloat)] { [("a", 100, 20), ("b", 60, 20), ("c", 30, 20)] }

/// The chosen candidate: the last-named one asked the whole proposal `(w,h)` while a later ask exists for none.
func chosen(_ r: [String], _ p: ProposedViewSize, names: [String]) -> String {
    let want = fmt(p)
    return names.last(where: { r.contains("\($0)\(want)") }) ?? "?"
}

@MainActor func selection() {
    log("--- H: .horizontal {a100, b60, c30} (20 tall), height 50")
    for w: CGFloat in [101, 100, 99.5, 60.5, 60, 59.99, 30, 29] {
        let r = run(ph(w, 50)) {
            ViewThatFits(in: .horizontal) {
                Ask("a", 100, 20) { EmptyView() }
                Ask("b", 60, 20) { EmptyView() }
                Ask("c", 30, 20) { EmptyView() }
            }
        }
        log("  H1 W=\(fmtN(w)) chosen=\(chosen(r.asks, ph(w, 50), names: ["a", "b", "c"])) answer=\(r.answer) asks=\(r.asks.joined(separator: " "))")
    }
    log("--- V: .vertical {a h100, b h60, c h30} (20 wide), width 50")
    for h: CGFloat in [100, 99.5, 30] {
        let r = run(ph(50, h)) {
            ViewThatFits(in: .vertical) {
                Ask("a", 20, 100) { EmptyView() }
                Ask("b", 20, 60) { EmptyView() }
                Ask("c", 20, 30) { EmptyView() }
            }
        }
        log("  V1 H=\(fmtN(h)) chosen=\(chosen(r.asks, ph(50, h), names: ["a", "b", "c"])) answer=\(r.answer) asks=\(r.asks.joined(separator: " "))")
    }
    log("--- H2: .horizontal, a child 200 tall, height 10")
    do {
        let r = run(ph(150, 10)) {
            ViewThatFits(in: .horizontal) { Ask("a", 100, 200) { EmptyView() }; Ask("b", 60, 20) { EmptyView() } }
        }
        log("  H2 chosen=\(chosen(r.asks, ph(150, 10), names: ["a", "b"])) answer=\(r.answer) asks=\(r.asks.joined(separator: " "))")
    }
    log("--- B: both axes {a 100x40, b 60x10, c 30x30}")
    for (w, h): (CGFloat, CGFloat) in [(120, 50), (120, 15), (50, 50), (20, 10)] {
        let r = run(ph(w, h)) {
            ViewThatFits {
                Ask("a", 100, 40) { EmptyView() }
                Ask("b", 60, 10) { EmptyView() }
                Ask("c", 30, 30) { EmptyView() }
            }
        }
        log("  B1 \(fmtN(w))x\(fmtN(h)) chosen=\(chosen(r.asks, ph(w, h), names: ["a", "b", "c"])) answer=\(r.answer) asks=\(r.asks.joined(separator: " "))")
    }
    log("--- W: the fit test is the ideal alone (W=100)")
    do {
        let r = run(ph(100, 50)) {
            ViewThatFits(in: .horizontal) {
                Ask("x", answer: { p in p.width == nil ? CGSize(width: 50, height: 20) : CGSize(width: 150, height: 20) }) { EmptyView() }
                Ask("y", 20, 20) { EmptyView() }
            }
        }
        log("  W1 ideal 50 answer 150: chosen=\(chosen(r.asks, ph(100, 50), names: ["x", "y"])) asks=\(r.asks.joined(separator: " "))")
    }
    do {
        let r = run(ph(100, 50)) {
            ViewThatFits(in: .horizontal) {
                Ask("x", answer: { p in p.width == nil ? CGSize(width: 150, height: 20) : CGSize(width: 50, height: 20) }) { EmptyView() }
                Ask("y", 20, 20) { EmptyView() }
            }
        }
        log("  W2 ideal 150 answer 50: chosen=\(chosen(r.asks, ph(100, 50), names: ["x", "y"])) asks=\(r.asks.joined(separator: " "))")
    }
    do {
        let r = run(ph(0, 50)) {
            ViewThatFits(in: .horizontal) { Ask("z", 0, 20) { EmptyView() }; Ask("y", 20, 20) { EmptyView() } }
        }
        log("  Z1 ideal 0 at W=0: chosen=\(chosen(r.asks, ph(0, 50), names: ["z", "y"])) answer=\(r.answer)")
    }
    log("--- P: frames and padding around the chosen candidate (Bounds logs the VTF's placed rect)")
    do {
        func bounds<V: View>(_ w: CGFloat, _ v: () -> V) -> String {
            asks = []
            let h = NSHostingView(rootView: v().frame(width: w, height: 50))
            h.frame = CGRect(x: 0, y: 0, width: 400, height: 100)
            h.layoutSubtreeIfNeeded()
            return dedupe(asks).filter { $0.hasPrefix("rect") }.joined(separator: " ")
        }
        log("  P1 chosen 60 (a is 300) in a 200 frame: \(bounds(200) { Bounds { ViewThatFits(in: .horizontal) { Ask("a", 300, 20) { EmptyView() }; Ask("b", 60, 20) { EmptyView() } } } })")
        log("  P2 fallback 30 (a is 100) in a 10 frame: \(bounds(10) { Bounds { ViewThatFits(in: .horizontal) { Ask("a", 100, 20) { EmptyView() }; Ask("b", 30, 20) { EmptyView() } } } })")
        let r4 = run(ph(100, 50)) {
            ViewThatFits(in: .horizontal) {
                Ask("a", 100, 20) { EmptyView() }.padding(8)
                Ask("b", 60, 20) { EmptyView() }
            }
        }
        log("  P3 .padding(8) in a candidate, W=100 (a is 116 wide with it): asks=\(r4.asks.joined(separator: " ")) answer=\(r4.answer)")
    }
    log("--- E2/E3/S1: ForEach, Group, ScrollView")
    do {
        let r = run(ph(70, 50)) {
            ViewThatFits(in: .horizontal) {
                ForEach([100, 60, 30], id: \.self) { w in Ask("f\(w)", CGFloat(w), 20) { EmptyView() } }
            }
        }
        log("  E2 ForEach {100,60,30} at W=70: chosen=\(chosen(r.asks, ph(70, 50), names: ["f100", "f60", "f30"])) answer=\(r.answer)")
        let r2 = run(ph(70, 50)) {
            ViewThatFits(in: .horizontal) {
                Group { Ask("g100", 100, 20) { EmptyView() }; Ask("g60", 60, 20) { EmptyView() } }
                Ask("g30", 30, 20) { EmptyView() }
            }
        }
        log("  E3 Group {100,60} + 30 at W=70: chosen=\(chosen(r2.asks, ph(70, 50), names: ["g100", "g60", "g30"])) answer=\(r2.answer)")
        let r3 = run(ph(70, 50)) {
            ScrollView(.horizontal) {
                ViewThatFits(in: .horizontal) { Ask("s1", 100, 20) { EmptyView() }; Ask("s2", 60, 20) { EmptyView() } }
            }
        }
        log("  S1 inside ScrollView(.horizontal) at W=70: asks=\(r3.asks.joined(separator: " ")) answer=\(r3.answer)")
    }
}

@MainActor func flexible() {
    log("--- F: flexible candidates. Ideal alone at (nil,50), then the choice against a fallback (10x20) at W=40/70/200")
    func fb() -> some View { Ask("fb", 10, 20) { EmptyView() } }
    func ideal<V: View>(_ v: V) -> String { let r = run(ph(nil, 50)) { v }; return r.answer == "no-answer" ? "no-answer(asks \(r.asks.joined(separator: " ")))" : r.answer }
    func trial<V: View>(_ v: @autoclosure () -> V) -> String {
        var parts: [String] = []
        for w: CGFloat in [40, 70, 200] {
            let r = run(ph(w, 50)) { ViewThatFits(in: .horizontal) { v(); fb() } }
            parts.append("W=\(fmtN(w)) \(r.answer)")
        }
        return parts.joined(separator: " | ")
    }
    let f1 = HStack(spacing: 0) { SwiftUI.Color.clear.frame(width: 50, height: 20); Spacer() }
    log("  F1 HStack(spacing:0){50; Spacer()}: ideal \(ideal(f1)); \(trial(HStack(spacing: 0) { SwiftUI.Color.clear.frame(width: 50, height: 20); Spacer() }))")
    log("  F1m Spacer(minLength:0): ideal \(ideal(HStack(spacing: 0) { SwiftUI.Color.clear.frame(width: 50, height: 20); Spacer(minLength: 0) })); \(trial(HStack(spacing: 0) { SwiftUI.Color.clear.frame(width: 50, height: 20); Spacer(minLength: 0) }))")
    log("  F2 Color.frame(maxWidth:.infinity): ideal \(ideal(SwiftUI.Color.red.frame(maxWidth: .infinity))); \(trial(SwiftUI.Color.red.frame(maxWidth: .infinity)))")
    func handle() -> some View {
        HStack(spacing: 0) {
            SwiftUI.Color.clear.frame(width: 50, height: 20)
            SwiftUI.Color.clear.frame(maxWidth: .infinity, maxHeight: .infinity).contentShape(Rectangle())
        }
    }
    log("  F2b {50; Color.clear.frame(maxWidth:inf,maxHeight:inf).contentShape} (the app's WindowDragHandle shape): ideal \(ideal(handle())); \(trial(handle()))")
    log("  F3 Text(\"Hello wide world\"): ideal \(ideal(Text("Hello wide world"))); \(trial(Text("Hello wide world")))")
    log("  F4 frame(minWidth:80, maxWidth:.infinity): ideal \(ideal(SwiftUI.Color.clear.frame(width: 10, height: 20).frame(minWidth: 80, maxWidth: .infinity))); \(trial(SwiftUI.Color.clear.frame(width: 10, height: 20).frame(minWidth: 80, maxWidth: .infinity)))")
}

@MainActor func reports() {
    func set3(_ axes: Axis.Set, vertical: Bool = false) -> some View {
        ViewThatFits(in: axes) {
            Ask("a", vertical ? 20 : 100, vertical ? 100 : 20) { EmptyView() }
            Ask("b", vertical ? 40 : 60, vertical ? 80 : 20) { EmptyView() }
            Ask("c", vertical ? 70 : 30, vertical ? 60 : 20) { EmptyView() }
        }
    }
    log("--- I: what the VTF reports to its parent")
    let props: [(String, ProposedViewSize)] = [("(nil,nil)", ph(nil, nil)), ("(0,0)", ph(0, 0)), ("(inf,inf)", ph(.infinity, .infinity)),
                                               ("(50,nil)", ph(50, nil)), ("(nil,10)", ph(nil, 10)), ("(80,50)", ph(80, 50))]
    log("  I1 .horizontal {100,60,30 x20}: " + props.map { "\($0.0)=\(run($0.1) { set3(.horizontal) }.answer.dropFirst(7))" }.joined(separator: ", "))
    func b3() -> some View {
        ViewThatFits {
            Ask("a", 100, 40) { EmptyView() }
            Ask("b", 60, 10) { EmptyView() }
            Ask("c", 30, 30) { EmptyView() }
        }
    }
    log("  I2 both axes {100x40, 60x10, 30x30} (nil,10): \(run(ph(nil, 10)) { b3() }.answer.dropFirst(7))")
    log("  I3 .vertical {20x100, 40x80, 70x60}: (0,0)=\(run(ph(0, 0)) { set3(.vertical, vertical: true) }.answer.dropFirst(7)), (50,nil)=\(run(ph(50, nil)) { set3(.vertical, vertical: true) }.answer.dropFirst(7))")
    for w: CGFloat in [200, 120, 70] {
        let r = run(ph(w, 50)) {
            HStack(spacing: 0) {
                ViewThatFits(in: .horizontal) { Ask("a", 100, 20) { EmptyView() }; Ask("b", 60, 20) { EmptyView() }; Ask("c", 30, 20) { EmptyView() } }
                Ask("o", 50, 20) { EmptyView() }
            }
        }
        log("  I4 HStack(spacing:0){VTF; 50} at W=\(fmtN(w)): \(r.answer) asks=\(r.asks.filter { !$0.hasPrefix("o") }.joined(separator: " "))")
    }
    do {
        let r = run(ph(200, 50)) {
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    ViewThatFits(in: .horizontal) { Ask("a", 100, 20) { EmptyView() }; Ask("b", 60, 20) { EmptyView() } }
                    Spacer()
                }
            }
        }
        log("  I5 HStack(spacing:0){VTF; Spacer()} at W=200: asks=\(r.asks.joined(separator: " "))")
    }
    let fx = run(ph(200, 50)) { ViewThatFits(in: .horizontal) { Ask("a", 100, 20) { EmptyView() }; Ask("b", 60, 20) { EmptyView() } }.fixedSize() }
    log("  I6 .fixedSize(): asks=\(fx.asks.joined(separator: " ")) answer=\(fx.answer)")
    log("--- PR: layout priority (setup chosen here: HStack(spacing:0){VTF{a: greedy, ideal 150; b: greedy, ideal 90}; g: greedy, ideal 10}, W=200)")
    func prRow(_ onVTF: Bool, _ onChild: Bool) -> String {
        let r = run(ph(200, 50)) {
            HStack(spacing: 0) {
                ViewThatFits(in: .horizontal) {
                    Ask("a", answer: { p in CGSize(width: p.width ?? 150, height: 20) }) { EmptyView() }.layoutPriority(onChild ? 1 : 0)
                    Ask("b", answer: { p in CGSize(width: p.width ?? 90, height: 20) }) { EmptyView() }
                }
                .layoutPriority(onVTF ? 1 : 0)
                Ask("g", answer: { p in CGSize(width: p.width ?? 10, height: 20) }) { EmptyView() }
            }
        }
        return "asks=\(r.asks.joined(separator: " ")) answer=\(r.answer)"
    }
    log("  PR1 .layoutPriority(1) on the VTF: \(prRow(true, false))")
    log("  PR2 .layoutPriority(1) on its candidate: \(prRow(false, true))")
    log("  PR0 control, none: \(prRow(false, false))")
    log("--- N1: nested {{150, 90}, 40}")
    for w: CGFloat in [160, 100, 60] {
        let r = run(ph(w, 50)) {
            ViewThatFits(in: .horizontal) {
                ViewThatFits(in: .horizontal) { Ask("i150", 150, 20) { EmptyView() }; Ask("i90", 90, 20) { EmptyView() } }
                Ask("o40", 40, 20) { EmptyView() }
            }
        }
        log("  N1 W=\(fmtN(w)): chosen=\(chosen(r.asks, ph(w, 50), names: ["i150", "i90", "o40"])) answer=\(r.answer)")
    }
}

@MainActor func spacing() {
    log("--- SP: the spacing edge in a VStack under a Text")
    func y<V: View>(_ name: String, _ build: () -> V) {
        asks = []
        let h = NSHostingView(rootView: VStack(spacing: nil) { Text("T"); build() }.frame(width: 100, height: 200, alignment: .top))
        h.frame = CGRect(x: 0, y: 0, width: 100, height: 200)
        h.layoutSubtreeIfNeeded()
        log("  \(name): \(dedupe(asks).last(where: { $0.hasPrefix("y=") }) ?? "no-y")")
    }
    y("SP0 control Text then Text") { Probe2() }
    y("SP0b control Text then Color") { ColorProbe() }
    y("SP1 {Text; Color} (the Text is the first, chosen)") { ViewThatFits(in: .horizontal) { Probe2(); ColorProbe() } }
    y("SP1' {Text; Color} with a width that picks the Color") { ViewThatFits(in: .horizontal) { WidePT(); ColorProbe() } }
    y("SP2 {Color(unchosen); Text(chosen)}") { ViewThatFits(in: .horizontal) { WideColor(); Probe2() } }
}
/// Logs the rect its subview is placed in (`rect x,y,w,h`), at the proposal it was given.
struct Bounds: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize { subviews[0].sizeThatFits(proposal) }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let s = subviews[0].sizeThatFits(proposal)
        asks.append("rect \(Int(bounds.minX)),\(Int(bounds.minY)),\(fmtN(s.width)),\(fmtN(s.height))")
        subviews[0].place(at: bounds.origin, proposal: proposal)
    }
}
struct Marker: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize { subviews[0].sizeThatFits(proposal) }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        asks.append("y=\(Int(bounds.minY))")
        subviews[0].place(at: bounds.origin, proposal: proposal)
    }
}
struct Probe2: View { var body: some View { Marker { Text("U") } } }
struct ColorProbe: View { var body: some View { Marker { SwiftUI.Color.red.frame(width: 20, height: 10) } } }
struct WidePT: View { var body: some View { Marker { Text("U").frame(width: 500) } } }
struct WideColor: View { var body: some View { Marker { SwiftUI.Color.red.frame(width: 500, height: 10) } } }

// MARK: behaviour

final class Obj: ObservableObject {
    nonisolated(unsafe) static var next = 0
    let id: Int; let tag: String
    init(_ tag: String) { Obj.next += 1; id = Obj.next; self.tag = tag; log("    made storage \(tag)#\(id)") }
}
struct Cand: View {
    let tag: String; let width: CGFloat; let key: Character
    @StateObject var obj: Obj
    @State var n = 0
    init(_ tag: String, _ width: CGFloat, key: Character) { self.tag = tag; self.width = width; self.key = key; _obj = StateObject(wrappedValue: Obj(tag)) }
    var body: some View {
        Button(tag) { n += 1; log("    fire \(tag) n=\(n)") }
            .keyboardShortcut(KeyEquivalent(key), modifiers: [])
            .frame(width: width, height: 20)
            .onAppear { log("    appear \(tag) obj#\(obj.id) n=\(n)") }
            .onDisappear { log("    disappear \(tag)") }
    }
}

@MainActor final class Box { var w: CGFloat = 300 }
@MainActor func keyWindow<V: View>(_ v: V, size: CGSize = CGSize(width: 300, height: 100)) -> NSWindow {
    let win = NSWindow(contentRect: CGRect(origin: .zero, size: size), styleMask: [.titled], backing: .buffered, defer: false)
    let hv = NSHostingView(rootView: v)
    hv.frame = CGRect(origin: .zero, size: size)
    if ProcessInfo.processInfo.environment["VTF_NOSIZING"] != nil { hv.sizingOptions = [] }
    win.contentView = hv
    win.orderFrontRegardless(); win.makeKey()
    spin(0.3)
    return win
}
@MainActor func press(_ win: NSWindow, _ c: String) {
    let ev = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: win.windowNumber,
                              context: nil, characters: c, charactersIgnoringModifiers: c, isARepeat: false, keyCode: 0)!
    let handled = win.performKeyEquivalent(with: ev)
    log("    key \(c) handled=\(handled)")
    spin(0.1)
}
@MainActor func axString(_ o: NSObject, _ sel: String) -> String? {
    guard o.responds(to: Selector(sel)) else { return nil }
    return o.perform(Selector(sel))?.takeUnretainedValue() as? String
}
@MainActor func buttons(_ win: NSWindow) -> [String] {
    var out: [String] = []
    func walk(_ o: NSObject) {
        if axString(o, "accessibilityRole") == NSAccessibility.Role.button.rawValue {
            out.append(axString(o, "accessibilityTitle") ?? axString(o, "accessibilityLabel") ?? "?")
        }
        let kids = o.perform(Selector("accessibilityChildren"))?.takeUnretainedValue() as? [Any] ?? []
        for c in kids { if let c = c as? NSObject { walk(c) } }
    }
    if let v = win.contentView { walk(v) }
    return out
}

struct Narrow3: View {
    @Binding var w: CGFloat
    var body: some View {
        ViewThatFits(in: .horizontal) {
            Cand("A", 400, key: "a")
            Cand("B", 150, key: "b")
            Cand("C", 10, key: "c")
        }
        .frame(width: w, height: 40)
    }
}

@MainActor func behaviour() {
    log("--- S0/K1/AX/R: three candidates A(400,a) B(150,b) C(10,c) in a 300 window")
    Obj.next = 0
    let hostW = HostBox()
    let win = keyWindow(HostRoot(box: hostW))
    log("  S0 above: @StateObject made for which candidates; appear for which")
    log("  AX0 buttons in the AX tree: \(buttons(win))")
    for c in ["a", "b", "c", "b", "b"] { press(win, c) }
    log("  R1 shrink to 50 (content size)")
    win.setContentSize(CGSize(width: 50, height: 100)); spin(0.3)
    log("  AX1 buttons: \(buttons(win))")
    log("  R2 back to 300")
    win.setContentSize(CGSize(width: 300, height: 100)); spin(0.3)
    press(win, "b")
    log("  R3 widen to 500")
    win.setContentSize(CGSize(width: 500, height: 100)); spin(0.3)
    win.orderOut(nil)

    log("--- S0b: which candidates' storage is made when the first candidate is chosen (A400 B150 C10 D5 in a 1000 window) and when B is (300 window)")
    for (w, label) in [(CGFloat(1000), "1000"), (CGFloat(300), "300")] {
        Obj.next = 0
        let ws = keyWindow(ViewThatFits(in: .horizontal) { Cand("A", 400, key: "a"); Cand("B", 150, key: "b"); Cand("C", 10, key: "c"); Cand("D", 5, key: "d") }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading), size: CGSize(width: w, height: 100))
        log("  S0b \(label) done")
        ws.orderOut(nil)
    }
    log("--- K4: three candidates sharing key g (widths 400, 150, 10) in a 300 window")
    let w4 = keyWindow(ViewThatFits(in: .horizontal) { Cand("G1", 400, key: "g"); Cand("G2", 150, key: "g"); Cand("G3", 10, key: "g") })
    press(w4, "g")
    w4.orderOut(nil)
}
@MainActor final class HostBox { }
struct HostRoot: View {
    let box: HostBox
    var body: some View {
        ViewThatFits(in: .horizontal) {
            Cand("A", 400, key: "a")
            Cand("B", 150, key: "b")
            Cand("C", 10, key: "c")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

struct Lab: View {
    let label: String
    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack { Text(label); Text("Other tool") }
            Text("More")
        }
    }
}
struct TextCand: View {
    let tag: String; let width: CGFloat; let presents: Bool
    @State var v = 0
    @State var shown = false
    var body: some View {
        Text(tag).frame(width: width, height: 20)
            .onChange(of: v) { _, new in log("    onChange \(tag) \(new)") }
            .task { log("    task \(tag)") }
            .onGeometryChange(for: CGFloat.self, of: { $0.size.width }) { w in log("    geometry \(tag) \(Int(w))") }
            .alert("Alert \(tag)", isPresented: $shown) { Button("OK") {} }
            .onAppear { log("    appear \(tag)"); v = 1; if presents { shown = true } }
    }
}
struct FocusCand: View {
    @FocusState var f: Bool
    @State var t = ""
    let wide: Bool
    var body: some View {
        if wide {
            TextField("t", text: $t).focused($f).frame(width: 200).onAppear { f = true }
                .onChange(of: f) { _, n in log("    focus wide=\(n)") }
        } else {
            Text("narrow").frame(width: 50)
        }
    }
}
struct FocusRoot: View {
    var body: some View {
        ViewThatFits(in: .horizontal) { FocusCand(wide: true); FocusCand(wide: false) }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
struct XRoot: View {
    var body: some View {
        ViewThatFits(in: .horizontal) { TextCand(tag: "wide", width: 400, presents: true); TextCand(tag: "mid", width: 150, presents: false) }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

@MainActor func behaviour2() {
    log("--- T: label change and resize ({HStack{label; Text(\"Other tool\")}; Text(\"More\")}, default HStack spacing): the smallest W (0.5 steps) whose answer is the wide one")
    for lab in ["Mirror", "Mirror \u{2713}"] {
        var first = "never"
        var w: CGFloat = 60
        while w <= 160 {
            let r = run(ph(w, 30)) { Lab(label: lab) }
            let width = Double(r.answer.dropFirst(7).split(separator: "x").first ?? "0") ?? 0
            if width > 60 { first = "\(fmtN(w)) (answer \(r.answer.dropFirst(7)))"; break }
            w += 0.5
        }
        log("  T \(lab): first wide W = \(first)")
    }
    log("--- WR: window resize 600 -> 300 -> 600 switches both ways")
    let win = keyWindow(HostRoot(box: HostBox()), size: CGSize(width: 600, height: 100))
    log("  WR0 600: \(buttons(win))")
    win.setContentSize(CGSize(width: 300, height: 100)); spin(0.3)
    log("  WR1 300: \(buttons(win))")
    win.setContentSize(CGSize(width: 600, height: 100)); spin(0.3)
    log("  WR2 600: \(buttons(win))")
    win.orderOut(nil)
    log("--- X: lifecycle in an unchosen candidate (wide 400 unchosen in a 300 window, mid 150 chosen)")
    let wx = keyWindow(XRoot())
    log("  X0 sheet=\(wx.attachedSheet != nil)")
    wx.setContentSize(CGSize(width: 600, height: 100)); spin(0.4)
    log("  X2 after widening to 600 (wide chosen) sheet=\(wx.attachedSheet != nil)")
    wx.orderOut(nil)
    log("--- X3: control, the same alert outside a VTF")
    struct Ctl: View { @State var s = false; var body: some View { Text("c").alert("Alert", isPresented: $s) { Button("OK") {} }.onAppear { s = true } } }
    let wc = keyWindow(Ctl())
    log("  X3 sheet=\(wc.attachedSheet != nil)")
    wc.orderOut(nil)
    log("--- FO: a focused TextField in the wide candidate")
    let wf = keyWindow(FocusRoot(), size: CGSize(width: 300, height: 100))
    func fr(_ w: NSWindow) -> String { w.firstResponder.map { String(describing: type(of: $0)) } ?? "nil" }
    log("  FO0 wide, responder=\(fr(wf))")
    wf.setContentSize(CGSize(width: 100, height: 100)); spin(0.4)
    log("  FO1 narrow, responder=\(fr(wf)) (is window: \(wf.firstResponder === wf))")
    wf.setContentSize(CGSize(width: 300, height: 100)); spin(0.4)
    log("  FO2 wide again, responder=\(fr(wf))")
    wf.orderOut(nil)
}

let app = NSApplication.shared
app.setActivationPolicy(.regular)
NSApp.accessibilitySetValue(true as NSNumber, forAttribute: NSAccessibility.Attribute(rawValue: "AXEnhancedUserInterface"))
NSApp.accessibilitySetValue(true as NSNumber, forAttribute: NSAccessibility.Attribute(rawValue: "AXManualAccessibility"))
MainActor.assumeIsolated {
    selection()
    flexible()
    reports()
    spacing()
    log("--- BEHAVIOUR (key window, performKeyEquivalent)")
    behaviour()
    behaviour2()
    log("--- end")
}
