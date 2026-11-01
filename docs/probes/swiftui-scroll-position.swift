// SwiftUI probe: pinned section headers/footers of LazyVStack/LazyHStack, `scrollPosition(id:anchor:)` with
// `scrollTargetLayout()`, an animated `scrollTo`, `@Bindable`, and `ScrollView([.horizontal, .vertical])`, for item
// R3-4 (docs/superpowers/2026-10-31-scroll-position-decisions.md, rulings SP-...).
//
// HOW TO RUN (ruling SA-O):
//
//   /usr/bin/swift docs/probes/swiftui-scroll-position.swift
//
// `/usr/bin/swift` is Apple's toolchain; a swift.org toolchain's JIT fails on SwiftUI symbols.
//
// METHOD. Each arm hosts the view in a 200x200 borderless NSWindow behind a ScrollView. A header or footer is an
// `NSViewRepresentable` marker whose NSView frame is read back in the NSScrollView's space after the clip view is
// scrolled with AppKit (`GeometryReader.onChange` never fires headless, the broken control of
// swiftui-lazy-containers.swift H0). A marker that is not attached to a window is printed `gone`. Every pinned arm has
// an UNPINNED CONTROL (same content, no `pinnedViews`) that must differ.
//
// RECORDED: see RESULT below.
import SwiftUI
import AppKit
import Observation

@Observable final class Model { var name = "a"; var count = 1 }

nonisolated(unsafe) var markers: [String: [NSView]] = [:]
nonisolated(unsafe) var built = Set<Int>()
nonisolated(unsafe) var positionLog: [String] = []

struct Mark: NSViewRepresentable {
    let name: String
    func makeNSView(context: Context) -> NSView {
        let v = NSView(); markers[name, default: []].append(v); return v
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
}
struct Row: View {
    let i: Int
    var body: some View {
        built.insert(i)
        return SwiftUI.Color(red: 0.5, green: 0.5, blue: 0.5).frame(height: 20)
    }
}
struct HCol: View {
    let i: Int
    var body: some View {
        built.insert(i)
        return SwiftUI.Color(red: 0.5, green: 0.5, blue: 0.5).frame(width: 20)
    }
}
func hdrColor(_ s: Int) -> SwiftUI.Color { [SwiftUI.Color(red: 1, green: 0, blue: 0), SwiftUI.Color(red: 1, green: 0.5, blue: 0), SwiftUI.Color(red: 1, green: 1, blue: 0)][s] }
func ftrColor(_ s: Int) -> SwiftUI.Color { [SwiftUI.Color(red: 0, green: 0, blue: 1), SwiftUI.Color(red: 0, green: 1, blue: 1), SwiftUI.Color(red: 1, green: 0, blue: 1)][s] }
@MainActor func spin(_ s: Double = 0.2) { RunLoop.main.run(until: Date().addingTimeInterval(s)) }
@MainActor func scrollViews(in view: NSView) -> [NSScrollView] {
    var found: [NSScrollView] = []
    if let s = view as? NSScrollView { found.append(s) }
    for sub in view.subviews { found += scrollViews(in: sub) }
    return found
}
@MainActor func host<V: View>(_ v: V) -> (NSWindow, NSHostingView<V>) {
    let h = NSHostingView(rootView: v)
    let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 200), styleMask: [.borderless], backing: .buffered, defer: false)
    win.isReleasedWhenClosed = false
    win.contentView = h
    win.orderFrontRegardless()
    spin(0.3)
    return (win, h)
}
@MainActor func scroll(_ h: NSView, x: CGFloat = 0, y: CGFloat = 0) {
    guard let s = scrollViews(in: h).first else { print("   (no NSScrollView)"); return }
    // Three moves (target, one point past, target) so pinned views, which lag a large jump, settle on the target.
    for (dx, dy) in [(0, 0), (1, 1), (0, 0)] as [(CGFloat, CGFloat)] {
        s.contentView.scroll(to: NSPoint(x: x + dx, y: y + dy))
        s.reflectScrolledClipView(s.contentView)
        spin(0.3)
    }
}
/// Paints the hosted view and returns, for the column / row through its middle, the spans of each named colour.
@MainActor func spans(_ h: NSView, horizontal: Bool = false) -> String {
    guard let rep = h.bitmapImageRepForCachingDisplay(in: h.bounds) else { return "no bitmap" }
    h.cacheDisplay(in: h.bounds, to: rep)
    func name(_ x: Int, _ y: Int) -> String {
        guard let c = rep.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { return "?" }
        let r = c.redComponent, g = c.greenComponent, b = c.blueComponent
        func near(_ a: CGFloat, _ b: CGFloat) -> Bool { abs(a - b) < 0.12 }
        if near(r, 1) && near(g, 0) && near(b, 0) { return "H0" }
        if near(r, 1) && near(g, 0.5) && near(b, 0) { return "H1" }
        if near(r, 1) && near(g, 1) && near(b, 0) { return "H2" }
        if near(r, 0) && near(g, 0) && near(b, 1) { return "F0" }
        if near(r, 0) && near(g, 1) && near(b, 1) { return "F1" }
        if near(r, 1) && near(g, 0) && near(b, 1) { return "F2" }
        if near(r, 0.5) && near(g, 0.5) && near(b, 0.5) { return "row" }
        return "bg"
    }
    let length = horizontal ? rep.pixelsWide : rep.pixelsHigh
    let scale = CGFloat(length) / (horizontal ? h.bounds.width : h.bounds.height)
    var out: [String] = []
    var start = 0
    var current = ""
    for i in 0...length {
        let n = i < length ? name(horizontal ? i : Int(CGFloat(rep.pixelsWide) / 2), horizontal ? Int(CGFloat(rep.pixelsHigh) / 2) : i) : "end"
        if n != current {
            if current != "" && current != "bg" && current != "row" { out.append("\(current) \(Int((CGFloat(start) / scale).rounded()))-\(Int((CGFloat(i) / scale).rounded()))") }
            current = n; start = i
        }
    }
    return out.isEmpty ? "none" : out.joined(separator: ", ")
}
/// Every attached instance of marker `name`: its leading edge in the scroll view's space (top-down y, or x).
@MainActor func edge(_ name: String, in h: NSView, horizontal: Bool = false) -> String {
    guard let s = scrollViews(in: h).first else { return "noscroll" }
    let live = (markers[name] ?? []).filter { $0.window != nil && $0.superview != nil }
    if live.isEmpty { return "gone" }
    return live.map { m -> String in
        let r = s.convert(m.bounds, from: m)
        if horizontal { return String(format: "%.0f", r.minX) }
        return String(format: "%.0f", s.isFlipped ? r.minY : s.bounds.height - r.maxY)
    }.joined(separator: "/")
}
func pruneMarkers() { for k in markers.keys { markers[k] = markers[k]!.filter { $0.window != nil } } }

@MainActor func probes() {
    func vstack(_ pinned: PinnedScrollableViews) -> some View {
        ScrollView {
            LazyVStack(spacing: 0, pinnedViews: pinned) {
                ForEach(0..<3, id: \.self) { s in
                    Section {
                        ForEach(0..<10, id: \.self) { Row(i: s * 10 + $0) }
                    } header: {
                        hdrColor(s % 3).frame(height: 30).overlay(Mark(name: "h\(s)"))
                    } footer: {
                        ftrColor(s % 3).frame(height: 30).overlay(Mark(name: "f\(s)"))
                    }
                }
            }
        }
    }
    print("=== V: LazyVStack in a 200x200 ScrollView; 3 sections of header 30 + 10 rows of 20 + footer 30 = 260 each (780)")
    print("    per offset: (leading edge of every attached marker, a/b when two instances; gone = none)")
    for (label, pinned) in [("V1 pinnedViews [.sectionHeaders, .sectionFooters]", PinnedScrollableViews([.sectionHeaders, .sectionFooters])),
                            ("V0 control, no pinnedViews", PinnedScrollableViews())] {
        print(label)
        markers = [:]
        let (w, h) = host(vstack(pinned))
        for offset in [0, 100, 230, 245, 250, 260, 300, 500, 580] as [CGFloat] {
            scroll(h, y: offset)
            pruneMarkers()
            let hs = (0..<3).map { edge("h\($0)", in: h) }.joined(separator: " ")
            let fs = (0..<3).map { edge("f\($0)", in: h) }.joined(separator: " ")
            print("   offset \(Int(offset)): headers \(hs) | footers \(fs)")
        }
        w.orderOut(nil); w.contentView = nil; spin(0.05)
    }

    print("=== W: windowing with pinned headers: 3 sections of 2000 rows, pinnedViews [.sectionHeaders], scrolled to 30000")
    do {
        built = []; markers = [:]
        let (w, h) = host(ScrollView {
            LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                ForEach(0..<3, id: \.self) { s in
                    Section { ForEach(0..<2000, id: \.self) { Row(i: s * 2000 + $0) } } header: { hdrColor(s % 3).frame(height: 30).overlay(Mark(name: "h\(s)")) }
                }
            }
        })
        scroll(h, y: 30000)
        print("W1 rows built \(built.count) of 6000; header 0 \(edge("h0", in: h)) header 1 \(edge("h1", in: h)) header 2 \(edge("h2", in: h))")
        w.orderOut(nil); w.contentView = nil; spin(0.05)
    }

    print("=== H: LazyHStack, horizontal ScrollView, 3 sections of header 30 + 10 columns of 20 + footer 30")
    for (label, pinned) in [("H1 pinnedViews [.sectionHeaders]", PinnedScrollableViews([.sectionHeaders])), ("H0 control", PinnedScrollableViews())] {
        print(label)
        markers = [:]
        let (w, h) = host(ScrollView(.horizontal) {
            LazyHStack(spacing: 0, pinnedViews: pinned) {
                ForEach(0..<3, id: \.self) { s in
                    Section { ForEach(0..<10, id: \.self) { HCol(i: s * 10 + $0) } } header: {
                        hdrColor(s % 3).frame(width: 30).overlay(Mark(name: "h\(s)"))
                    } footer: { ftrColor(s % 3).frame(width: 30).overlay(Mark(name: "f\(s)")) }
                }
            }
        })
        for offset in [0, 100, 300] as [CGFloat] {
            scroll(h, x: offset)
            pruneMarkers(); print("   offset \(Int(offset)): headers " + (0..<3).map { edge("h\($0)", in: h, horizontal: true) }.joined(separator: " "))
        }
        w.orderOut(nil); w.contentView = nil; spin(0.05)
    }

    print("=== O: where does a pinned header go at the end of its section? 3 sections of header 30 + 10 rows of 20 (230 each), headers only pinned")
    do {
        markers = [:]
        let (w, h) = host(ScrollView {
            LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                ForEach(0..<3, id: \.self) { s in
                    Section { ForEach(0..<10, id: \.self) { Row(i: s * 10 + $0) } } header: { hdrColor(s).frame(height: 30).overlay(Mark(name: "h\(s)")) }
                }
            }
        })
        for offset in [0, 100, 190, 200, 210, 220, 225, 229, 230, 231, 240] as [CGFloat] {
            scroll(h, y: offset); pruneMarkers()
            print("   offset \(Int(offset)): headers " + (0..<3).map { edge("h\($0)", in: h) }.joined(separator: " "))
        }
        w.orderOut(nil); w.contentView = nil; spin(0.05)
    }

    print("=== P: scrollPosition(id:anchor:) with scrollTargetLayout (LazyVStack of 100 rows of 20 in 200x200)")
    struct PosView: View {
        @State var id: Int? = nil
        let anchor: UnitPoint?
        let targets: Bool
        var body: some View {
            let base = ScrollView {
                if targets {
                    LazyVStack(spacing: 0) { ForEach(0..<100, id: \.self) { Row(i: $0) } }.scrollTargetLayout()
                } else {
                    LazyVStack(spacing: 0) { ForEach(0..<100, id: \.self) { Row(i: $0) } }
                }
            }
            let _ = positionLog.append("\(String(describing: id))")
            if let anchor { base.scrollPosition(id: $id, anchor: anchor) } else { base.scrollPosition(id: $id) }
        }
    }
    for (label, anchor, targets) in [("P1 no anchor", nil as UnitPoint?, true), ("P2 anchor .top", UnitPoint.top, true),
                                     ("P3 anchor .bottom", UnitPoint.bottom, true), ("P4 anchor .center", UnitPoint.center, true),
                                     ("P0 control, no scrollTargetLayout", nil as UnitPoint?, false)] {
        positionLog = []
        let (w, h) = host(PosView(anchor: anchor, targets: targets)); w.makeKeyAndOrderFront(nil); spin(0.3)
        let first = positionLog
        for y in [300, 310, 330] as [CGFloat] {
            positionLog = []
            scroll(h, y: y)
            spin(0.5)
            if let sv = scrollViews(in: h).first, let cg = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1, wheel1: -1, wheel2: 0, wheel3: 0), let ev = NSEvent(cgEvent: cg) {
                sv.scrollWheel(with: ev); spin(0.5)
            }
            print("\(label): at \(Int(y)) body ran with ids \(positionLog) (initial \(first))")
        }
        w.orderOut(nil); w.contentView = nil; spin(0.05)
    }
    print("=== X: writing the binding scrolls (P5)")
    do {
        struct Writer: View {
            @State var id: Int? = nil
            var body: some View {
                VStack(spacing: 0) {
                    SwiftUI.Button("go") { id = 50 }.frame(height: 20)
                    ScrollView { LazyVStack(spacing: 0) { ForEach(0..<100, id: \.self) { Row(i: $0) } }.scrollTargetLayout() }.scrollPosition(id: $id)
                }
            }
        }
        let (w, h) = host(Writer())
        func offsetNow() -> String { scrollViews(in: h).first.map { String(format: "%.0f", $0.contentView.bounds.origin.y) } ?? "none" }
        print("P5 before: clip y \(offsetNow())")
        // Click the button via accessibility is not available headless; drive the state through the responder chain.
        func press(_ v: NSView) -> Bool {
            if let b = v as? NSControl, b.isEnabled { b.performClick(nil); return true }
            for s in v.subviews { if press(s) { return true } }
            return false
        }
        let pressed = press(h)
        spin(0.4)
        print("P5 after write id = 50 (button pressed: \(pressed)): clip y \(offsetNow()) (row 50 top = 1000 if the binding scrolls to it)")
        w.orderOut(nil); w.contentView = nil; spin(0.05)
    }

    print("=== A: withAnimation { proxy.scrollTo(50, anchor: .top) }")
    do {
        struct Anim: View {
            let animated: Bool
            var body: some View {
                ScrollViewReader { proxy in
                    VStack(spacing: 0) {
                        SwiftUI.Button("go") {
                            if animated { withAnimation(.linear(duration: 1)) { proxy.scrollTo(50, anchor: .top) } } else { proxy.scrollTo(50, anchor: .top) }
                        }.frame(height: 20)
                        ScrollView { LazyVStack(spacing: 0) { ForEach(0..<100, id: \.self) { Row(i: $0).id($0) } } }
                    }
                }
            }
        }
        for animated in [true, false] {
            let (w, h) = host(Anim(animated: animated))
            func y() -> String { scrollViews(in: h).first.map { String(format: "%.0f", $0.contentView.bounds.origin.y) } ?? "none" }
            func press(_ v: NSView) -> Bool {
                if let b = v as? NSControl, b.isEnabled { b.performClick(nil); return true }
                for s in v.subviews { if press(s) { return true } }
                return false
            }
            let pressed = press(h)
            var samples: [String] = []
            for _ in 0..<6 { spin(0.2); samples.append(y()) }
            print("A\(animated ? "1 animated (linear 1s)" : "0 control, plain") pressed \(pressed): clip y samples every 0.2s \(samples)")
            w.orderOut(nil); w.contentView = nil; spin(0.05)
        }
    }

    print("=== B: @Bindable")
    do {
        struct Edit: View {
            @Bindable var model: Model
            var body: some View { TextField("n", text: $model.name) }
        }
        let m = Model()
        let b = Bindable(m).name
        b.wrappedValue = "b"
        print("B1 Bindable(m).name type \(type(of: b)) wrote through: \(m.name)")
        let c = Bindable(m).count
        c.wrappedValue += 1
        print("B2 count after += 1: \(m.count)")
        _ = Edit(model: m)
    }
    fflush(stdout)
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
MainActor.assumeIsolated { probes() }
print("DONE")
