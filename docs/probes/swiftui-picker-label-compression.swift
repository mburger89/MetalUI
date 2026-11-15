// SwiftUI probe: a menu `Picker`'s label under horizontal compression (Alloy composer row, BY-P).
//
// HOW TO RUN (offscreen, borderless, never ordered front):
//
//   xcrun swiftc -parse-as-library docs/probes/swiftui-picker-label-compression.swift -o /tmp/pk && /tmp/pk
//
// RECORDED OUTPUT (macOS 27, 2026-11-15; each cell is width x height @ x of the stack child, in points; "view tree" lines are the
// focus rings: x, y, w, h of each capsule):
//
//   Picker row (width: picker | Model | Effort | total right edge)
//   600 166.5x24.0@0.0 85.5x24.0@174.5 81.5x24.0@268.0 349.5
//   420 166.5x24.0@0.0 85.5x24.0@174.5 81.5x24.0@268.0 349.5
//   360 166.5x24.0@0.0 85.5x24.0@174.5 81.5x24.0@268.0 349.5
//   320 137.0x24.0@0.0 85.5x24.0@145.0 81.5x24.0@238.5 320.0
//   300 117.0x24.0@0.0 85.5x24.0@125.0 81.5x24.0@218.5 300.0
//   280 97.0x24.0@0.0 85.5x24.0@105.0 81.5x24.0@198.5 280.0
//   240 75.5x32.0@0.0 74.7x24.0@83.5 74.7x24.0@166.2 240.8
//   view tree at 280
//   NSHostingView<ModifiedContent<ModifiedContent<Row, _PreferenceActionModifier<Sizes>>, _FrameLayout>> (0.0, 0.0, 280.0, 120.0)
//     _FocusRingView (43.0, 0.0, 54.0, 24.0)
//     _FocusRingView (105.0, 0.0, 86.0, 24.0)
//     _FocusRingView (199.0, 0.0, 81.0, 24.0)
//   view tree at 240
//   NSHostingView<ModifiedContent<ModifiedContent<Row, _PreferenceActionModifier<Sizes>>, _FrameLayout>> (0.0, 0.0, 240.0, 120.0)
//     _FocusRingView (35.0, 4.0, 41.0, 24.0)
//     _FocusRingView (84.0, 4.0, 74.0, 24.0)
//     _FocusRingView (166.0, 4.0, 75.0, 24.0)
//   Plain text row (width: t1 | t2 | t3)
//   400 80.0x16.0@0.0 139.0x16.0@88.0 7.0x16.0@235.0
//   200 80.0x16.0@0.0 86.0x32.0@88.0 7.0x16.0@182.0
//   160 62.0x32.0@0.0 73.0x48.0@70.0 7.0x16.0@151.0
//   120 49.0x32.0@0.0 48.0x64.0@57.0 7.0x16.0@113.0
//   80 29.0x48.0@0.0 28.0x112.0@37.0 7.0x16.0@73.0
//
// READ: the picker (label + capsule) is 24 tall and keeps its label whole down to 280; the capsule shrinks first (54 wide at 280, 41 at
// 240). Only at 240 does the label wrap (32 tall). Plain Text breaks at the hyphen, then mid-word. Row width 600 down to 360 is the ideal.
import SwiftUI
import AppKit

struct Sizes: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) { value.merge(nextValue()) { $1 } }
}
extension View {
    func report(_ k: String) -> some View {
        background(GeometryReader { g in Color.clear.preference(key: Sizes.self, value: [k: g.frame(in: .named("row"))]) })
    }
}

struct Row: View {
    @State var mode = 3
    var body: some View {
        HStack(spacing: 8) {
            Picker("Mode", selection: $mode) {
                Text("Default").tag(0); Text("Accept edits").tag(1); Text("Plan").tag(2); Text("Auto").tag(3); Text("Don't ask").tag(4)
            }.buttonBorderShape(.capsule).report("picker")
            Menu("Model") { Button("x") {} }.buttonBorderShape(.capsule).report("model")
            Menu("Effort") { Button("x") {} }.buttonBorderShape(.capsule).report("effort")
        }
        .coordinateSpace(name: "row")
    }
}
struct Plain: View {
    var body: some View {
        HStack(spacing: 8) {
            Text("sourcekit-lsp").report("t1")
            Text("Sources/Forecast.swift").report("t2")
            Text("x").report("t3")
        }
        .coordinateSpace(name: "row")
    }
}

@MainActor func measure<V: View>(_ v: V, width: CGFloat, dump: Bool = false) -> [String: CGRect] {
    var got: [String: CGRect] = [:]
    let host = NSHostingView(rootView: v.onPreferenceChange(Sizes.self) { got = $0 }.frame(width: width, height: 120, alignment: .topLeading))
    let win = NSWindow(contentRect: NSRect(x: -5000, y: -5000, width: width, height: 120), styleMask: [.borderless], backing: .buffered, defer: false)
    win.contentView = host
    host.frame = NSRect(x: 0, y: 0, width: width, height: 120)
    host.layoutSubtreeIfNeeded()
    RunLoop.main.run(until: Date().addingTimeInterval(0.3))
    host.layoutSubtreeIfNeeded()
    if dump { dumpViews(host, 0) }
    return got
}
@MainActor func dumpViews(_ v: NSView, _ d: Int) {
    let extra = (v as? NSTextField).map { " \"\($0.stringValue)\"" } ?? (v as? NSPopUpButton).map { " popup \"\($0.titleOfSelectedItem ?? "")\"" } ?? ""
    print(String(repeating: "  ", count: d) + "\(type(of: v)) \(v.frame)\(extra)")
    for c in v.subviews { dumpViews(c, d + 1) }
}
func f(_ r: CGRect?) -> String { r.map { String(format: "%.1fx%.1f@%.1f", $0.width, $0.height, $0.minX) } ?? "-" }

@main struct Probe {
    @MainActor static func main() {
        _ = NSApplication.shared
        print("Picker row (width: picker | Model | Effort | total right edge)")
        for w in [600, 420, 360, 320, 300, 280, 240] as [CGFloat] {
            let s = measure(Row(), width: w)
            print(Int(w), f(s["picker"]), f(s["model"]), f(s["effort"]), String(format: "%.1f", s["effort"]?.maxX ?? 0))
        }
        for w in [280, 240] as [CGFloat] { print("view tree at \(Int(w))"); _ = measure(Row(), width: w, dump: true) }
        print("Plain text row (width: t1 | t2 | t3)")
        for w in [400, 200, 160, 120, 80] as [CGFloat] {
            let s = measure(Plain(), width: w)
            print(Int(w), f(s["t1"]), f(s["t2"]), f(s["t3"]))
        }
    }
}
