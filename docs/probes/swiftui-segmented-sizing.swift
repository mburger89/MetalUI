// SwiftUI probe: the SEGMENTED `Picker`'s size, its segment widths, and where a labelled one puts its
// title. The rule behind R4-3a (Tasks.md; human check SR1 Finding A; ruling `SR-G` in
// docs/superpowers/2026-11-03-silent-results-decisions.md; record 210): MetalUI's options row answered
// `n x widest` whatever it was offered, so a labelled picker in a 420 window starved its title to 8 wide.
//
// HOW TO RUN (ruling SA-O):
//
//   xcrun swiftc -O docs/probes/swiftui-segmented-sizing.swift -o /tmp/segsizing && /tmp/segsizing
//
// Apple's toolchain (`xcrun swiftc`, or `/usr/bin/swift` as the other probes use); a swift.org toolchain's
// JIT fails on SwiftUI symbols. The first compile takes about a minute.
//
// NO ARM READS PIXELS. Every figure comes from layout (`NSHostingView` + `layoutSubtreeIfNeeded`, a custom
// `Layout` asking the subview, `onGeometryChange` frames) or from the `NSSegmentedControl` the picker hosts
// (its frame, `intrinsicContentSize`, `segmentDistribution` and the accessibility frames of its segments), so
// the probe runs in a LOCKED session. Segment edges from the accessibility frames read 1 to 2 points over
// the layout figure (`ax=[122,121,122]` for a 363 control): the AX figure is a bound, not an edge.
//
// WHAT IT SHOWS (the rules, all [MEASURED] below):
// - SG1: ideal = n x (widest + 24) = 363 for "Vanilla", "Chocolate", "Strawberry mint"; floor = sum of the
//   natural widths (text + 24) = 271. Offered more than the ideal it answers the ideal, between the floor
//   and the ideal it takes the offer, below the floor it answers the floor and overflows. A labelled one
//   answers 279 at zero (the floor and the 8 gap, the title 0 wide) and 408 at nil.
// - SG2: the control's `segmentDistribution` reads raw value 2 (`.fillEqually` by AppKit's enum order,
//   not checked against the header here). Each segment gets an equal share, never less than its natural width:
//   335 -> 108, 108, 121; 300 -> 91, 90, 121; 280 -> 75, 86, 121; 271 and below -> 66, 86, 121 (AX bounds).
// - SG3: a labelled picker is its own rule, not a stack's. The control is offered W - 8 - titleIdeal; if
//   what is left for the title is short of its ideal the title is offered that remainder and the control
//   is offered W - 8 - titleAnswer. W 380: title 37x16, control 335; W 300: title 20x32, control 272;
//   W 280: title 1x96, control 271; W <= 260: the picker answers 279x96, the title 0x96.
// - SG4: SG4a an HStack around a hidden-title Alpha/Beta picker at 200 lands it on its FLOOR (111), not its
//   ideal (118): the stack's flexibility order puts the narrow-flex picker first; SG4c the labelled
//   Alpha/Beta at 200 keeps its ideal (control 118); SG4h a long title wraps (83x48) and the control takes
//   289; five segments (SG4d, SG4e) share the same rule.
// - SQ: a `Text` beside a rigid sibling takes what remains, wrapping by word then by character, down to
//   one letter a line ("Flavor" 6x96 beside a 366 rigid; 6x16 with the height capped to 24). There is no
//   priority boost: one letter per line is SwiftUI's own behaviour under a true squeeze, so `Text` is not at
//   fault in R4-3a. TW: the line counts of "Vanilla", "Chocolate", "Strawberry mint", "Flavor" at 16 widths.
// - PM: the pop-up's frame is title + about 48 (144.50 for "Strawberry mint", 56.50 for "A"), MetalUI's
//   132 / 132 (divergence 131; the pop-up is not changed by R4-3a).
//
// RECORDED 2026-11-04 by R4-3a on macOS 27.2, Apple Swift 6.4.2 (`xcrun swiftc`), screen LOCKED
// (`CGSSessionScreenIsLocked = 1`, `docs/probes/appkit-screen-lock-state.swift`). Exit 0. Run twice; the two
// outputs are byte-identical (`cmp` empty, 188 lines) and are kept in
// docs/probes/swiftui-segmented-sizing-run.txt. Every reading the plan quoted from an earlier run was read
// again; SG3e at 280 (added to this copy, the plan had it from SG1a's 280x96 and a subtraction) reads
// label 1x96 and a 271 control.
//
import AppKit
import SwiftUI

@MainActor func spin(_ s: Double = 0.3) { RunLoop.main.run(until: Date().addingTimeInterval(s)) }
func f(_ v: CGFloat) -> String {
    if v.isInfinite { return "inf" }
    let r = (v * 100).rounded() / 100
    return r == r.rounded() ? "\(Int(r))" : String(format: "%.2f", Double(r))
}
func f(_ s: CGSize) -> String { "\(f(s.width))x\(f(s.height))" }
func f(_ r: CGRect) -> String { "(\(f(r.minX)), \(f(r.minY)), \(f(r.width)), \(f(r.height)))" }
var windows: [NSWindow] = []
@MainActor func host<V: View>(_ v: V, size: CGSize) -> NSHostingView<V> {
    let w = NSWindow(contentRect: NSRect(x: 100, y: 100, width: size.width, height: size.height), styleMask: [.titled], backing: .buffered, defer: false)
    w.isReleasedWhenClosed = false
    let h = NSHostingView(rootView: v)
    h.sizingOptions = []
    w.contentView = h
    w.setContentSize(size)
    w.orderFrontRegardless()
    h.layoutSubtreeIfNeeded()
    spin(0.4)
    windows.append(w)
    return h
}
final class Log { var answers: [String] = []; var frames: [String: CGRect] = [:] }
nonisolated(unsafe) let log = Log()
struct Ask: Layout {
    let name: String
    let widths: [CGFloat]
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let s = subviews.first else { return .zero }
        var parts = ["zero \(f(s.sizeThatFits(.zero)))", "nil \(f(s.sizeThatFits(.unspecified)))", "inf \(f(s.sizeThatFits(.infinity)))"]
        for w in widths { parts.append("w\(f(w)) \(f(s.sizeThatFits(ProposedViewSize(width: w, height: nil))))") }
        let line = "\(name): " + parts.joined(separator: "  ")
        if !log.answers.contains(line) { log.answers.append(line) }
        return s.sizeThatFits(proposal)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews.first?.place(at: bounds.origin, proposal: proposal)
    }
}
struct Tag: ViewModifier {
    let name: String
    func body(content: Content) -> some View {
        content.onGeometryChange(for: CGRect.self) { $0.frame(in: .named("root")) } action: { r in log.frames[name] = r }
    }
}
extension View { func tag(as name: String) -> some View { modifier(Tag(name: name)) } }

@MainActor func allViews(_ v: NSView) -> [NSView] { [v] + v.subviews.flatMap(allViews) }
@MainActor func segs(_ root: NSView) -> String {
    var out: [String] = []
    for v in allViews(root) {
        if let s = v as? NSSegmentedControl {
            let w = (0..<s.segmentCount).map { f(s.width(forSegment: $0)) }.joined(separator: ",")
            let kids = (s.accessibilityChildren() ?? []).compactMap { $0 as? NSAccessibilityElement ?? nil }
            func walk(_ o: Any) -> [String] {
                guard let n = o as? NSObject else { return [] }
                let kids = (n.value(forKey: "accessibilityChildren") as? [Any]) ?? []
                if kids.isEmpty { return [f(((n.value(forKey: "accessibilityFrame") as? NSValue)?.rectValue ?? .zero).width)] }
                return kids.flatMap(walk)
            }
            let ax = walk(s).joined(separator: ",")
            _ = kids
            out.append("ctl frame=\(f(s.frame)) intrinsic=\(f(s.intrinsicContentSize)) dist=\(s.segmentDistribution.rawValue) widthForSegment=[\(w)] ax=[\(ax)]")
        }
    }
    return out.joined(separator: " | ")
}
@MainActor func frames<V: View>(_ label: String, _ v: V, size: CGSize, seg: Bool = true) {
    log.frames = [:]
    let h = host(v.coordinateSpace(.named("root")).frame(width: size.width, height: size.height, alignment: .topLeading), size: size)
    print("  \(label):")
    for k in log.frames.keys.sorted() { print("    \(k) \(f(log.frames[k]!))") }
    if seg { print("    \(segs(h))") }
}
let three = ["Vanilla", "Chocolate", "Strawberry mint"]
@ViewBuilder func opts(_ t: [String]) -> some View { ForEach(t.indices, id: \.self) { Text(t[$0]).tag($0) } }
@MainActor func pick(_ t: [String]) -> some View {
    Picker(selection: .constant(1)) { opts(t) } label: { Text("Flavor").tag(as: "label") }
}
@MainActor func run() {
    let ws: [CGFloat] = [1000, 500, 420, 412, 400, 380, 350, 335, 320, 300, 280, 260, 240, 220, 200, 180, 160, 140, 120, 100, 80, 60, 50, 40, 20, 6]
    print("--- TW: Text widths")
    for t in three + ["Flavor", "Strawberry mint Strawberry mint"] {
        _ = host(Ask(name: "TW \(t)", widths: [200, 100, 60, 50, 40, 38, 37, 36, 30, 20, 12, 8, 6, 4, 2, 1]) { Text(t) }, size: CGSize(width: 300, height: 200))
    }
    print("--- SG1 sizes")
    _ = host(Ask(name: "SG1a labelled 3", widths: ws) { Picker("Flavor", selection: .constant(1)) { opts(three) }.pickerStyle(.segmented) }, size: CGSize(width: 300, height: 200))
    _ = host(Ask(name: "SG1b hidden 3", widths: ws) { Picker("Flavor", selection: .constant(1)) { opts(three) }.pickerStyle(.segmented).labelsHidden() }, size: CGSize(width: 300, height: 200))
    _ = host(Ask(name: "SG1c empty title 3", widths: ws) { Picker("", selection: .constant(1)) { opts(three) }.pickerStyle(.segmented) }, size: CGSize(width: 300, height: 200))
    _ = host(Ask(name: "SG1d hidden Alpha/Beta", widths: ws) { Picker("M", selection: .constant(0)) { opts(["Alpha", "Beta"]) }.pickerStyle(.segmented).labelsHidden() }, size: CGSize(width: 300, height: 200))
    _ = host(Ask(name: "SG1e hidden A/long", widths: ws) { Picker("M", selection: .constant(0)) { opts(["A", "A much longer label"]) }.pickerStyle(.segmented).labelsHidden() }, size: CGSize(width: 300, height: 200))
    _ = host(Ask(name: "SG1f labelled menu 3", widths: ws) { Picker("Flavor", selection: .constant(1)) { opts(three) }.pickerStyle(.menu) }, size: CGSize(width: 300, height: 200))
    _ = host(Ask(name: "SG1g hidden menu 3", widths: ws) { Picker("Flavor", selection: .constant(1)) { opts(three) }.pickerStyle(.menu).labelsHidden() }, size: CGSize(width: 300, height: 200))
    for l in log.answers { print("  \(l)") }
    print("--- SG2 hidden picker in frame(width:) and placed; the segment widths")
    for w: CGFloat in [500, 380, 335, 300, 280, 260, 240, 200, 160, 100] {
        frames("SG2 w\(f(w)) 3", Picker("F", selection: .constant(1)) { opts(three) }.pickerStyle(.segmented).labelsHidden().tag(as: "picker").frame(width: w), size: CGSize(width: 540, height: 60))
    }
    for w: CGFloat in [300, 200, 160, 120] {
        frames("SG2 w\(f(w)) A/long", Picker("F", selection: .constant(1)) { opts(["A", "A much longer label"]) }.pickerStyle(.segmented).labelsHidden().tag(as: "picker").frame(width: w), size: CGSize(width: 540, height: 60))
    }
    print("--- SG3 the human-check scenes, label frame from a Picker label: view")
    frames("SG3a VStack.padding(20) 420", VStack(alignment: .leading, spacing: 14) {
        pick(three).pickerStyle(.segmented).tag(as: "picker")
    }.padding(20), size: CGSize(width: 420, height: 420))
    frames("SG3b frame(width:380)", pick(three).pickerStyle(.segmented).tag(as: "picker").frame(width: 380), size: CGSize(width: 420, height: 420))
    frames("SG3c HStack{Text;Picker(\"\")} 380", HStack { Text("Flavor").tag(as: "text"); Picker("", selection: .constant(1)) { opts(three) }.pickerStyle(.segmented).tag(as: "picker") }.frame(width: 380), size: CGSize(width: 420, height: 420))
    frames("SG3d HStack{Text;Picker.hidden} 380", HStack { Text("Flavor").tag(as: "text"); Picker("", selection: .constant(1)) { opts(three) }.pickerStyle(.segmented).labelsHidden().tag(as: "picker") }.frame(width: 380), size: CGSize(width: 420, height: 420))
    for w: CGFloat in [300, 280, 260, 240, 200, 150, 100] {
        frames("SG3e labelled frame(width:\(f(w)))", pick(three).pickerStyle(.segmented).tag(as: "picker").frame(width: w), size: CGSize(width: 420, height: 420))
    }
    print("--- SG4 stack around a flexible picker with a small flex")
    frames("SG4a HStack{Text Mode;Picker.hidden Alpha/Beta} 200", HStack { Text("Mode").tag(as: "text"); Picker("", selection: .constant(0)) { opts(["Alpha", "Beta"]) }.pickerStyle(.segmented).labelsHidden().tag(as: "picker") }.frame(width: 200), size: CGSize(width: 420, height: 100))
    frames("SG4b HStack{Text Mode;Picker.hidden A/long} 300", HStack { Text("Mode").tag(as: "text"); Picker("", selection: .constant(0)) { opts(["A", "A much longer label"]) }.pickerStyle(.segmented).labelsHidden().tag(as: "picker") }.frame(width: 300), size: CGSize(width: 420, height: 100))
    frames("SG4c labelled Alpha/Beta 200", Picker(selection: .constant(0)) { opts(["Alpha", "Beta"]) } label: { Text("Mode").tag(as: "label") }.pickerStyle(.segmented).tag(as: "picker").frame(width: 200), size: CGSize(width: 420, height: 100))
    frames("SG4d five segments 300", Picker("", selection: .constant(0)) { opts(["A", "Bb", "Ccc", "Dddddddd", "Eeeeeeeeeeeeeeeeeeee"]) }.pickerStyle(.segmented).labelsHidden().tag(as: "picker").frame(width: 300), size: CGSize(width: 420, height: 100))
    frames("SG4e five segments ideal", Picker("", selection: .constant(0)) { opts(["A", "Bb", "Ccc", "Dddddddd", "Eeeeeeeeeeeeeeeeeeee"]) }.pickerStyle(.segmented).labelsHidden().tag(as: "picker"), size: CGSize(width: 800, height: 100))
    frames("SG4f controlSize small", Picker("", selection: .constant(0)) { opts(three) }.pickerStyle(.segmented).labelsHidden().controlSize(.small).tag(as: "picker").frame(width: 300), size: CGSize(width: 420, height: 100))
    frames("SG4g with disabled", Picker("", selection: .constant(0)) { opts(three) }.pickerStyle(.segmented).labelsHidden().disabled(true).tag(as: "picker").frame(width: 300), size: CGSize(width: 420, height: 100))
    frames("SG4h long title 380", Picker(selection: .constant(1)) { opts(three) } label: { Text("A rather long title for one picker").tag(as: "label") }.pickerStyle(.segmented).tag(as: "picker").frame(width: 380), size: CGSize(width: 420, height: 100))
    print("--- SQ Text squeezed by a rigid sibling, window 380x200")
    for w: CGFloat in [300, 330, 335, 336, 340, 350, 366, 372, 374, 379, 400] {
        frames("SQ1 HStack{Text Flavor; Color w\(f(w))} 380", HStack { Text("Flavor").tag(as: "text"); Color.red.frame(width: w, height: 24).tag(as: "rigid") }.frame(width: 380), size: CGSize(width: 380, height: 200), seg: false)
    }
    frames("SQ2 two words, tight", HStack { Text("Strawberry mint").tag(as: "text"); Color.red.frame(width: 300, height: 24).tag(as: "rigid") }.frame(width: 380), size: CGSize(width: 380, height: 200), seg: false)
    frames("SQ3 two words, tighter", HStack { Text("Strawberry mint").tag(as: "text"); Color.red.frame(width: 340, height: 24).tag(as: "rigid") }.frame(width: 380), size: CGSize(width: 380, height: 200), seg: false)
    frames("SQ4 height capped 24", HStack { Text("Flavor").tag(as: "text"); Color.red.frame(width: 366, height: 24).tag(as: "rigid") }.frame(width: 380, height: 24), size: CGSize(width: 380, height: 200), seg: false)
    print("--- PM pop-up frames")
    frames("PM1 labelled menu", pick(three).pickerStyle(.menu).tag(as: "picker").frame(width: 380, alignment: .leading), size: CGSize(width: 420, height: 100), seg: false)
    frames("PM2 hidden menu", Picker("F", selection: .constant(1)) { opts(three) }.pickerStyle(.menu).labelsHidden().tag(as: "picker").frame(width: 380, alignment: .leading), size: CGSize(width: 420, height: 100), seg: false)
    frames("PM3 hidden menu selection 2", Picker("F", selection: .constant(2)) { opts(three) }.pickerStyle(.menu).labelsHidden().tag(as: "picker").frame(width: 380, alignment: .leading), size: CGSize(width: 420, height: 100), seg: false)
    frames("PM4 hidden short", Picker("F", selection: .constant(0)) { opts(["A", "B"]) }.pickerStyle(.menu).labelsHidden().tag(as: "picker").frame(width: 380, alignment: .leading), size: CGSize(width: 420, height: 100), seg: false)
    frames("PM5 hidden Alpha Beta", Picker("F", selection: .constant(0)) { opts(["Alpha", "Beta"]) }.pickerStyle(.menu).labelsHidden().tag(as: "picker").frame(width: 380, alignment: .leading), size: CGSize(width: 420, height: 100), seg: false)
    frames("PM6 hidden long", Picker("F", selection: .constant(0)) { opts(["A much longer label"]) }.pickerStyle(.menu).labelsHidden().tag(as: "picker").frame(width: 380, alignment: .leading), size: CGSize(width: 420, height: 100), seg: false)
}
MainActor.assumeIsolated {
    NSApplication.shared.setActivationPolicy(.accessory)
    run()
}
exit(0)
