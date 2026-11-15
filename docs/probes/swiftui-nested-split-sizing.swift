// SwiftUI probe: how HSplitView/VSplitView size themselves, and how a split view nested as a pane of another is sized (SA-O; MetalUI `HS-J`).
//
// HOW TO RUN (offscreen, borderless, never ordered front; exits by itself):
//
//   xcrun swiftc -parse-as-library docs/probes/swiftui-nested-split-sizing.swift -o /tmp/ns && /tmp/ns
//
// RECORDED OUTPUT (macOS 27.2.1, 2026-11-15; (a) is name: width x height @ (x, y) in a 600 x 400 window, (b) is the width x height the
// split view answers `sizeThatFits` for each proposal, "inf" infinity, from a custom `Layout` that asks its one child):
//
//   (a) bare nested split view as a pane, window 600x400
//   H{V{red,green}, blue}
//     H: 600.0x400.0@(0.0,0.0)
//     V: 300.0x400.0@(0.0,0.0)
//     blue: 299.0x400.0@(301.0,0.0)
//     green: 300.0x200.0@(0.0,200.0)
//     red: 300.0x199.0@(0.0,0.0)
//   H{V{..}, V{..}}
//     H: 600.0x400.0@(0.0,0.0)
//     V1: 300.0x400.0@(0.0,0.0)
//     V2: 299.0x400.0@(301.0,0.0)
//     blue: 299.0x199.0@(301.0,0.0)
//     green: 300.0x200.0@(0.0,200.0)
//     red: 300.0x199.0@(0.0,0.0)
//     yellow: 299.0x200.0@(301.0,200.0)
//   V{H{red,green}, blue}
//     H: 600.0x199.0@(0.0,0.0)
//     V: 600.0x400.0@(0.0,0.0)
//     blue: 600.0x200.0@(0.0,200.0)
//     green: 299.0x199.0@(301.0,0.0)
//     red: 300.0x199.0@(0.0,0.0)
//   (b) sizeThatFits answers of the split view (w x h) per proposal
//   HSplitView fixed 50x50 x2:  zero=0x0  unspecified=0x0  infinity=infxinf  300x200=300x200  w300 h-nil=300x0  w-nil h200=0x200  w-inf h200=infx200  w0 h200=0x200
//   VSplitView fixed 50x50 x2:  zero=0x0  unspecified=0x0  infinity=infxinf  300x200=300x200  w300 h-nil=300x0  w-nil h200=0x200  w-inf h200=infx200  w0 h200=0x200
//   HSplitView flexible Color x2:  zero=0x0  unspecified=0x0  infinity=infxinf  300x200=300x200  w300 h-nil=300x0  w-nil h200=0x200  w-inf h200=infx200  w0 h200=0x200
//   VSplitView flexible Color x2:  zero=0x0  unspecified=0x0  infinity=infxinf  300x200=300x200  w300 h-nil=300x0  w-nil h200=0x200  w-inf h200=infx200  w0 h200=0x200
//   HSplitView min40/ideal100/max200 x2:  zero=0x0  unspecified=0x0  infinity=infxinf  300x200=300x200  w300 h-nil=300x0  w-nil h200=0x200  w-inf h200=infx200  w0 h200=0x200
//   VSplitView min40/ideal100/max200 x2:  zero=0x0  unspecified=0x0  infinity=infxinf  300x200=300x200  w300 h-nil=300x0  w-nil h200=0x200  w-inf h200=infx200  w0 h200=0x200
//
// READ: (a) a bare nested split view is a flexible pane: V takes 300 of 600 beside a plain pane (one 1-point divider each way), and
// the two Vs of `H{V, V}` take 300 and 299. (b) A split view answers the proposal it is offered whatever its children (fixed 50 x 50,
// flexible, or min/ideal/max frames give identical rows): zero -> 0, infinity -> infinity, finite -> itself, and nil -> 0 (ideal 0).
// MetalUI follows all but the nil row (it keeps the sum of the panes' ideals; see `HS-J`).
//
import SwiftUI
import AppKit

struct Sizes: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) { value.merge(nextValue()) { $1 } }
}
extension View {
    func report(_ k: String) -> some View {
        background(GeometryReader { g in Color.clear.preference(key: Sizes.self, value: [k: g.frame(in: .named("root"))]) })
    }
}

@MainActor func measure<V: View>(_ v: V, size: CGSize) -> [String: CGRect] {
    var got: [String: CGRect] = [:]
    let host = NSHostingView(rootView: v.coordinateSpace(name: "root").onPreferenceChange(Sizes.self) { got = $0 }
        .frame(width: size.width, height: size.height, alignment: .topLeading))
    let win = NSWindow(contentRect: NSRect(x: -5000, y: -5000, width: size.width, height: size.height), styleMask: [.borderless], backing: .buffered, defer: false)
    win.contentView = host
    host.frame = NSRect(origin: .zero, size: size)
    host.layoutSubtreeIfNeeded()
    RunLoop.main.run(until: Date().addingTimeInterval(0.2))
    host.layoutSubtreeIfNeeded()
    win.contentView = nil
    return got
}

func fmt(_ r: CGRect?) -> String { r.map { String(format: "%.1fx%.1f@(%.1f,%.1f)", $0.width, $0.height, $0.minX, $0.minY) } ?? "-" }

// (a) a bare split view as a pane of another
struct BareNestH: View {   // HSplitView { VSplitView { red; green }; blue }
    var body: some View {
        HSplitView {
            VSplitView { Color.red.report("red"); Color.green.report("green") }.report("V")
            Color.blue.report("blue")
        }.report("H")
    }
}
struct BareNestHTwo: View {   // HSplitView { VSplitView {..}; VSplitView {..} }
    var body: some View {
        HSplitView {
            VSplitView { Color.red.report("red"); Color.green.report("green") }.report("V1")
            VSplitView { Color.blue.report("blue"); Color.yellow.report("yellow") }.report("V2")
        }.report("H")
    }
}
struct BareNestV: View {   // VSplitView { HSplitView { red; green }; blue }
    var body: some View {
        VSplitView {
            HSplitView { Color.red.report("red"); Color.green.report("green") }.report("H")
            Color.blue.report("blue")
        }.report("V")
    }
}

// (b) what a split view answers to sizeThatFits
final class Log: @unchecked Sendable { var lines: [String] = [] }
struct Spy: Layout {
    let log: Log
    let label: String
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let proposals: [(String, ProposedViewSize)] = [
            ("zero", .zero), ("unspecified", .unspecified), ("infinity", .infinity), ("300x200", ProposedViewSize(width: 300, height: 200)),
            ("w300 h-nil", ProposedViewSize(width: 300, height: nil)), ("w-nil h200", ProposedViewSize(width: nil, height: 200)),
            ("w-inf h200", ProposedViewSize(width: .infinity, height: 200)), ("w0 h200", ProposedViewSize(width: 0, height: 200)),
        ]
        var cells: [String] = []
        for (name, p) in proposals { let s = subviews[0].sizeThatFits(p); cells.append("\(name)=" + dim(s.width) + "x" + dim(s.height)) }
        let key = label
        if !log.lines.contains(where: { $0.hasPrefix(key) }) { log.lines.append(key + "  " + cells.joined(separator: "  ")) }
        return subviews[0].sizeThatFits(proposal)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews[0].place(at: bounds.origin, proposal: ProposedViewSize(bounds.size))
    }
}
struct Spied<C: View>: View {
    let log: Log; let label: String; @ViewBuilder var content: C
    var body: some View { Spy(log: log, label: label) { content } }
}

@main struct Probe {
    @MainActor static func main() {
        setvbuf(stdout, nil, _IOLBF, 0)
        _ = NSApplication.shared
        print("(a) bare nested split view as a pane, window 600x400")
        for (name, v) in [("H{V{red,green}, blue}", AnyView(BareNestH())), ("H{V{..}, V{..}}", AnyView(BareNestHTwo())), ("V{H{red,green}, blue}", AnyView(BareNestV()))] {
            let g = measure(v, size: CGSize(width: 600, height: 400))
            print(name); for k in g.keys.sorted() { print("  \(k): \(fmt(g[k]))") }
        }
        print("(b) sizeThatFits answers of the split view (w x h) per proposal")
        let log = Log()
        let fixedH = Spied(log: log, label: "HSplitView fixed 50x50 x2:") { HSplitView { Color.red.frame(width: 50, height: 50); Color.green.frame(width: 50, height: 50) } }
        let fixedV = Spied(log: log, label: "VSplitView fixed 50x50 x2:") { VSplitView { Color.red.frame(width: 50, height: 50); Color.green.frame(width: 50, height: 50) } }
        let flexH = Spied(log: log, label: "HSplitView flexible Color x2:") { HSplitView { Color.red; Color.green } }
        let flexV = Spied(log: log, label: "VSplitView flexible Color x2:") { VSplitView { Color.red; Color.green } }
        let limH = Spied(log: log, label: "HSplitView min40/ideal100/max200 x2:") {
            HSplitView { Color.red.frame(minWidth: 40, idealWidth: 100, maxWidth: 200); Color.green.frame(minWidth: 40, idealWidth: 100, maxWidth: 200) } }
        let limV = Spied(log: log, label: "VSplitView min40/ideal100/max200 x2:") {
            VSplitView { Color.red.frame(minHeight: 40, idealHeight: 100, maxHeight: 200); Color.green.frame(minHeight: 40, idealHeight: 100, maxHeight: 200) } }
        _ = measure(fixedH, size: CGSize(width: 600, height: 400)); _ = measure(fixedV, size: CGSize(width: 600, height: 400))
        _ = measure(flexH, size: CGSize(width: 600, height: 400)); _ = measure(flexV, size: CGSize(width: 600, height: 400))
        _ = measure(limH, size: CGSize(width: 600, height: 400)); _ = measure(limV, size: CGSize(width: 600, height: 400))
        for l in log.lines { print(l) }
        exit(0)
    }
}

func dim(_ v: CGFloat) -> String { v.isInfinite ? "inf" : String(format: "%g", v) }
