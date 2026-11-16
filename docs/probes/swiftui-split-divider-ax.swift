// SwiftUI probe: the accessibility elements of an `HSplitView` / `VSplitView` divider (ruling `HS-K`,
// docs/superpowers/2026-10-30-split-view-decisions.md; record docs/record/324-split-divider-ax.md).
//
// HOW TO RUN (ruling SA-O's two forms; about 3 seconds; opens one ordered-in window and exits itself; no computer use):
//
//   /usr/bin/swift docs/probes/swiftui-split-divider-ax.swift
//   xcrun swiftc docs/probes/swiftui-split-divider-ax.swift -o /tmp/split-ax-probe && /tmp/split-ax-probe
//
// THE INSTRUMENT. An `HSplitView` of three panes (frame minWidth 50 / 80 / 100, ideal 100 / 100 / 100) and a `VSplitView` of two,
// each in an `NSHostingView` in a 400 x 300 window. SwiftUI's split views are `NSSplitView`s on macOS; the probe finds them in the
// view hierarchy and reads the legacy NSAccessibility attribute API in-process (AXUIElement from the same process only sees the
// app-level elements, record 309): the split view's `AXChildren`, each element with role AXSplitter, every attribute it names, whether
// each is settable, its actions, and what an `AXValue` write, `AXIncrement` and `AXDecrement` do to the pane frames.
//
// RECORDED 2026-11-15 by the split-divider-ax lane, macOS 27.2.1 (26B131), Apple Swift 6.4.2, arm64; compiled form, stderr empty. THE READ,
// one value per fact (the raw lines are reproduced after it):
//
//   * SwiftUI's split views are `NSSplitView`s (`isVertical` true for HSplitView, `dividerStyle` 2 = thin, `dividerThickness` 1). The split's
//     `accessibilityChildren` interleave the panes and the dividers: pane, splitter, pane, splitter, pane (N panes give N - 1 splitters).
//     The split itself is `AXSplitGroup`; the panes are `AXGroup` hosting views.
//   * Each divider is an `NSSplitViewSplitter`, an `NSAccessibilityElement`: role `AXSplitter`, no subrole, role description "splitter".
//   * ORIENTATION (`accessibilityOrientation`): 1 (vertical) for the divider of an HSplitView (a vertical line), 2 (horizontal) for a VSplitView's.
//   * VALUE: a number, in points, equal to the SIZE OF THE PANE BEFORE the divider (133 and 132 for dividers 0 and 1 of three panes
//     133 | 132 | 133; 149 for the one divider of a VSplitView of 149 | 150), NOT the divider's position in the split and not a fraction.
//   * MIN VALUE: 0. MAX VALUE: the sum of the two neighbouring panes (265 = 133 + 132 for both dividers; 299 for 149 + 150), whatever the
//     panes' own frame minimums (50 / 80 / 100): the min and max do not carry the pane limits.
//   * SETTABLE: yes (`setAccessibilityValue:`). A write moves the divider by the same path as a drag: 150 moved panes 133 | 132 | 133 to
//     150 | 115 | 133 (the pair keeps its total, the others stay); 0 clamped to the pane's own minimum (50 | 215 | 133; for the VSplitView
//     60, the pane's minHeight); 1000 (above the maximum) and 0.5 left the panes unchanged (1000 is IGNORED, not clamped to the maximum;
//     0.5 reads as below the 50 minimum, so it is indistinguishable from "clamped to 50" here).
//   * ACTIONS: none. `NSSplitViewSplitter` has no `accessibilityActionNames`, and `accessibilityPerformIncrement` / `Decrement` (which it
//     inherits) forward to `accessibilityPerformAction:`, which is not implemented, so calling either RAISES "unrecognized selector" (the
//     first run of this probe died there). There is no AXIncrement / AXDecrement step: a client resizes by writing the value.
//   * LABEL, IDENTIFIER, HELP: all nil. `isAccessibilityEnabled` reads false (the NSAccessibilityElement default; it is not an
//     "disabled" signal: the value is settable). `.accessibilityIdentifier` and `.accessibilityLabel` on the split and on a pane do not
//     reach the splitters (probe arm I): SwiftUI has no way to name a divider.
//   * FRAME (screen): the divider's 1 point line: (233, 100, 1 x 300) for the first divider of a 400 wide HSplitView window at (100, 100).
//   * NOT MEASURABLE here: what VoiceOver's own keyboard resize (VO + shift + arrows on a splitter, or VO + the interaction commands)
//     sends. With no actions on the element the only thing VoiceOver can do is write the value; whether it steps by 1 point or by a
//     larger amount is VoiceOver's choice and needs a person at a keyboard (human check HS1 in docs/verification/human-checks.md).
//
// Raw output (arm H, the first divider; the rest follows the same shape):
//   splitter[0] role=AXSplitter subrole=nil roleDescription="splitter" label=nil identifier=nil help=nil value=133 min=0 max=265 orientation=1 enabled=false element=true frame(screen)=(233.0, 100.0, 1.0, 300.0) previousContents=1 nextContents=1
//   set value 150: value 133 -> 150, panes 133.0 | 132.0 | 133.0 -> 150.0 | 115.0 | 133.0
//   set value 0 (below the minimum): value 150 -> 50, panes 150.0 | 115.0 | 133.0 -> 50.0 | 215.0 | 133.0
//   set value 1000 (beyond the maximum): value 50 -> 50, panes 50.0 | 215.0 | 133.0 -> 50.0 | 215.0 | 133.0
//   set value 0.5 (a fraction?): value 50 -> 50, panes 50.0 | 215.0 | 133.0 -> 50.0 | 215.0 | 133.0
//   (arm V) splitter[0] ... value=149 min=0 max=299 orientation=2 ...; set value 0 -> 60, panes 60.0 | 239.0.
import AppKit
import SwiftUI

struct Pane: View {
    let name: String; let lo: CGFloat; let ideal: CGFloat
    var body: some View {
        Text(name).frame(minWidth: lo, idealWidth: ideal, maxWidth: .infinity, maxHeight: .infinity)
    }
}
struct VPane: View {
    let name: String
    var body: some View {
        Text(name).frame(minWidth: 50, maxWidth: .infinity, minHeight: 60, idealHeight: 100, maxHeight: .infinity)
    }
}
struct HFixture: View {
    var body: some View {
        HSplitView { Pane(name: "A", lo: 50, ideal: 100); Pane(name: "B", lo: 80, ideal: 100); Pane(name: "C", lo: 100, ideal: 100) }
    }
}
struct VFixture: View {
    var body: some View { VSplitView { VPane(name: "A"); VPane(name: "B") } }
}
struct IDFixture: View {
    var body: some View {
        HSplitView { Pane(name: "A", lo: 50, ideal: 100).accessibilityIdentifier("paneA"); Pane(name: "B", lo: 80, ideal: 100) }
            .accessibilityIdentifier("theSplit").accessibilityLabel("Split label")
    }
}

func attr(_ o: NSObject, _ a: String) -> Any? { o.accessibilityAttributeValue(NSAccessibility.Attribute(rawValue: a)) }
func show(_ v: Any?) -> String {
    guard let v else { return "-" }
    if let a = v as? NSArray { return "[" + a.map { show($0) }.joined(separator: ", ") + "]" }
    if let o = v as? NSObject, o.responds(to: Selector(("accessibilityAttributeValue:"))), !(v is NSNumber), !(v is NSString) {
        return "<\(type(of: o)) \(attr(o, "AXRole").map { "\($0)" } ?? "-")>"
    }
    return "\(v)"
}
func findSplit(_ v: NSView) -> NSSplitView? {
    if let s = v as? NSSplitView { return s }
    for c in v.subviews { if let s = findSplit(c) { return s } }
    return nil
}
func frames(_ s: NSSplitView) -> String {
    s.arrangedSubviews.map { v in
        let f = s.isVertical ? v.frame.width : v.frame.height
        return String(format: "%.1f", f)
    }.joined(separator: " | ")
}
@MainActor func pump(_ n: Int = 20) { for _ in 0..<n { RunLoop.current.run(until: Date().addingTimeInterval(0.02)) } }

@MainActor func window<V: View>(_ v: V, w: CGFloat = 400, h: CGFloat = 300) -> (NSWindow, NSHostingView<V>) {
    let win = NSWindow(contentRect: NSRect(x: 100, y: 100, width: w, height: h), styleMask: [.titled], backing: .buffered, defer: false)
    let host = NSHostingView(rootView: v)
    host.frame = NSRect(x: 0, y: 0, width: w, height: h)
    win.contentView = host
    win.orderBack(nil)
    pump(); host.layoutSubtreeIfNeeded(); pump()
    return (win, host)
}

@MainActor func dump(_ title: String, _ build: () -> (NSWindow, NSView)) {
    print("--- \(title)")
    let (win, host) = build()
    guard let split = findSplit(host) else { print("  no NSSplitView found"); return }
    print("  \(type(of: split)) isVertical=\(split.isVertical) dividerStyle=\(split.dividerStyle.rawValue) dividerThickness=\(split.dividerThickness) pane sizes: \(frames(split))")
    print("  split AX role=\(String(describing: split.accessibilityRole())) subrole=\(String(describing: split.accessibilitySubrole())) label=\(String(describing: split.accessibilityLabel())) identifier=\(String(describing: split.accessibilityIdentifier()))")
    let kids = ((attr(split, "AXChildren") as? NSArray) ?? []).compactMap { $0 as? NSObject }
    print("  AXChildren (\(kids.count)): " + kids.map { "\(type(of: $0)) role=\(String(describing: ($0 as? NSAccessibilityProtocol)?.accessibilityRole()))" }.joined(separator: ", "))
    // The splitters are `NSSplitViewSplitter`s: `NSAccessibilityElement` subclasses, read through the modern protocol.
    let splitters = kids.filter { String(describing: type(of: $0)) == "NSSplitViewSplitter" }
    print("  splitters: \(splitters.count)")
    func p(_ o: NSObject) -> NSAccessibilityProtocol { o as! NSAccessibilityProtocol }
    func describe(_ s: NSObject) -> String {
        let e = p(s)
        let frame = e.accessibilityFrame()
        let prev = (s.value(forKey: "accessibilityPreviousContents") as? [NSObject]) ?? []
        let next = (s.value(forKey: "accessibilityNextContents") as? [NSObject]) ?? []
        return "role=\(String(describing: e.accessibilityRole())) subrole=\(String(describing: e.accessibilitySubrole())) roleDescription=\(String(describing: e.accessibilityRoleDescription())) label=\(String(describing: e.accessibilityLabel())) identifier=\(String(describing: e.accessibilityIdentifier())) help=\(String(describing: e.accessibilityHelp())) value=\(String(describing: e.accessibilityValue())) min=\(String(describing: s.value(forKey: "accessibilityMinValue"))) max=\(String(describing: s.value(forKey: "accessibilityMaxValue"))) orientation=\(String(describing: s.value(forKey: "accessibilityOrientation"))) enabled=\(e.isAccessibilityEnabled()) element=\(e.isAccessibilityElement()) frame(screen)=\(frame) previousContents=\(prev.count) nextContents=\(next.count)"
    }
    for (i, s) in splitters.enumerated() {
        print("  splitter[\(i)] \(describe(s))")
        print("      responds: setAccessibilityValue:=\(s.responds(to: Selector(("setAccessibilityValue:")))) accessibilityPerformIncrement=\(s.responds(to: Selector(("accessibilityPerformIncrement")))) accessibilityPerformDecrement=\(s.responds(to: Selector(("accessibilityPerformDecrement")))) accessibilityActionNames=\(s.responds(to: Selector(("accessibilityActionNames"))))")
        // NSAccessibilityElement answers no legacy attribute or action API (accessibilityActionNames is not implemented), so the
        // actions are the modern accessibilityPerformIncrement / Decrement above and the value is settable through setAccessibilityValue:.
    }
    guard let first = splitters.first else { return }
    func step(_ label: String, _ act: () -> Void) {
        let before = frames(split), v0 = String(describing: p(first).accessibilityValue())
        act(); pump(); host.layoutSubtreeIfNeeded(); pump()
        print("  \(label): value \(v0) -> \(String(describing: p(first).accessibilityValue())), panes \(before) -> \(frames(split))")
    }
    // `accessibilityPerformIncrement` / `Decrement` are NOT called: an NSSplitViewSplitter inherits NSAccessibilityElement's, which forwards
    // to `accessibilityPerformAction:`, and that raises "unrecognized selector" (the first run of this probe died there). So the divider
    // has no increment, decrement or any other action.
    step("set value 150") { first.setValue(150 as NSNumber, forKey: "accessibilityValue") }
    step("set value 0 (below the minimum)") { first.setValue(0 as NSNumber, forKey: "accessibilityValue") }
    step("set value 1000 (beyond the maximum)") { first.setValue(1000 as NSNumber, forKey: "accessibilityValue") }
    step("set value 0.5 (a fraction?)") { first.setValue(0.5 as NSNumber, forKey: "accessibilityValue") }
    win.orderOut(nil)
}

@main @MainActor struct Main {
    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let arms = Set(CommandLine.arguments.dropFirst())
        func want(_ a: String) -> Bool { arms.isEmpty || arms.contains(a) }
        if want("H") { dump("H: HSplitView, three panes, 400 x 300") { let (w, h) = window(HFixture()); return (w, h) } }
        if want("V") { dump("V: VSplitView, two panes, 400 x 300") { let (w, h) = window(VFixture()); return (w, h) } }
        if want("I") { dump("I: HSplitView with .accessibilityIdentifier / .accessibilityLabel on the split and one pane") { let (w, h) = window(IDFixture()); return (w, h) } }
        print("not measurable here: what VoiceOver's own keyboard resize (VO + shift + arrows on a splitter) sends; it is one of the AXIncrement / AXDecrement / AXValue paths above, chosen by VoiceOver.")
        exit(0)
    }
}
