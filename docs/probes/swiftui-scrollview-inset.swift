// SwiftUI probe (SP-N, CMG-G): what `.accessibilityIdentifier` on a `ScrollView` does (the scroll area's own identifier, or pushed
// down onto the content's leaves), and what a NEGATIVE `.contentMargins(_, _, for: .scrollIndicators)` does to the
// scroller. Evidence for `SP-M`..`SP-O` in docs/superpowers/2026-10-31-scroll-position-decisions.md and
// `CMG-G` in 2026-11-13-content-margins-decisions.md (Alloy's transcript `ScrollView`, record 438).
//
// HOW TO RUN (Apple's toolchain; needs a window server, not a locked screen):
//
//   /usr/bin/swift docs/probes/swiftui-scrollview-inset.swift 2>&1 \
//     | grep -v 'Connection\]\|ntents\|warning:\|deprecated\|^ *[0-9]* |\|^ *|\|note:\|WARNING: Application performed a reentrant'
//
// RECORDED OUTPUT (macOS, 2026-11-27, 1x display; the NSHostingView line and zero contentInsets dropped, frames in the
// scroll view's own space). READINGS:
//   I1..I3  `.accessibilityIdentifier(transcript)` on a `ScrollView` is the `HostingScrollView`'s (`AXScrollArea`) own
//           identifier; its children keep theirs (I2: a, b) and a child with none gets none (I3: `c`, no id). It is NOT
//           pushed down onto the leaves, unlike a `VStack`'s (`swiftui-accessibility-identifier-nesting.swift` X1, X3).
//   N0..N9  a `.scrollIndicators` margin moves the scroller (`NSScroller.frame`) by its TRAILING margin across a vertical
//           scroller (N5: x 25 -> 18, N7: -4 -> x 29) and its BOTTOM margin across a horizontal one (N8: y -1 -> -8),
//           inward when positive and OUTWARD when negative (a negative margin is accepted, not clamped: N2, N7); the
//           leading margin does nothing to a vertical scroller (N6); along the axis the margin shrinks (positive) or
//           lengthens (negative: N3, y -20, height 240) the track. The knob keeps its 6-point slot, 3 points inside the
//           scroller's edge, in every arm.
//
//   I0 control: ScrollView { rows } (no identifier)
//     HostingScrollView role=AXScrollArea value=nil kids=2
//       AccessibilityNode role=AXStaticText value=a kids=0
//       AccessibilityNode role=AXStaticText value=b kids=0
//   I1 ScrollView { Text a; Text b }.accessibilityIdentifier(transcript)
//     HostingScrollView role=AXScrollArea value=nil id=transcript kids=2
//       AccessibilityNode role=AXStaticText value=a kids=0
//       AccessibilityNode role=AXStaticText value=b kids=0
//   I2 ScrollView { Text a(id a); Text b(id b) }.accessibilityIdentifier(transcript)
//     HostingScrollView role=AXScrollArea value=nil id=transcript kids=2
//       AccessibilityNode role=AXStaticText value=a id=a kids=0
//       AccessibilityNode role=AXStaticText value=b id=b kids=0
//   I3 ScrollView { Text a(id a); Text c (no id) }.accessibilityIdentifier(transcript)
//     HostingScrollView role=AXScrollArea value=nil id=transcript kids=2
//       AccessibilityNode role=AXStaticText value=a id=a kids=0
//       AccessibilityNode role=AXStaticText value=c kids=0
//   N0 control 30 rows
//     scrollView (0.0, 0.0, 42.0, 200.0) scrollerInsets=(t0.0 l0.0 b0.0 r0.0) contentSize=(42.0, 200.0)
//     scroller (25.0, 0.0, 17.0, 200.0) knobSlot=(8.0, 3.0, 6.0, 194.0) knob=(8.0, 3.0, 6.0, 64.0) style=1
//   N1 .contentMargins(.horizontal, 7, for: .scrollIndicators)
//     scrollView (0.0, 0.0, 42.0, 200.0) scrollerInsets=(t0.0 l7.0 b0.0 r7.0) contentSize=(42.0, 200.0)
//     scroller (18.0, 0.0, 17.0, 200.0) knobSlot=(8.0, 3.0, 6.0, 194.0) knob=(8.0, 3.0, 6.0, 64.0) style=1
//   N2 .contentMargins(.horizontal, -7, for: .scrollIndicators)
//     scrollView (0.0, 0.0, 42.0, 200.0) scrollerInsets=(t0.0 l-7.0 b0.0 r-7.0) contentSize=(42.0, 200.0)
//     scroller (32.0, 0.0, 17.0, 200.0) knobSlot=(8.0, 3.0, 6.0, 194.0) knob=(8.0, 3.0, 6.0, 64.0) style=1
//   N3 .contentMargins(.vertical, -20, for: .scrollIndicators)
//     scrollView (0.0, 0.0, 42.0, 200.0) scrollerInsets=(t-20.0 l0.0 b-20.0 r0.0) contentSize=(42.0, 200.0)
//     scroller (25.0, -20.0, 17.0, 240.0) knobSlot=(8.0, 3.0, 6.0, 234.0) knob=(8.0, 3.0, 6.0, 78.0) style=1
//   N4 .contentMargins(.vertical, 20, for: .scrollIndicators)
//     scrollView (0.0, 0.0, 42.0, 200.0) scrollerInsets=(t20.0 l0.0 b20.0 r0.0) contentSize=(42.0, 200.0)
//     scroller (25.0, 20.0, 17.0, 160.0) knobSlot=(8.0, 3.0, 6.0, 154.0) knob=(8.0, 3.0, 6.0, 51.0) style=1
//   N5 .contentMargins(.trailing, 7, for: .scrollIndicators)
//     scrollView (0.0, 0.0, 42.0, 200.0) scrollerInsets=(t0.0 l0.0 b0.0 r7.0) contentSize=(42.0, 200.0)
//     scroller (18.0, 0.0, 17.0, 200.0) knobSlot=(8.0, 3.0, 6.0, 194.0) knob=(8.0, 3.0, 6.0, 64.0) style=1
//   N6 .contentMargins(.leading, 7, for: .scrollIndicators)
//     scrollView (0.0, 0.0, 42.0, 200.0) scrollerInsets=(t0.0 l7.0 b0.0 r0.0) contentSize=(42.0, 200.0)
//     scroller (25.0, 0.0, 17.0, 200.0) knobSlot=(8.0, 3.0, 6.0, 194.0) knob=(8.0, 3.0, 6.0, 64.0) style=1
//   N7 .contentMargins(.trailing, -4, for: .scrollIndicators)
//     scrollView (0.0, 0.0, 42.0, 200.0) scrollerInsets=(t0.0 l0.0 b0.0 r-4.0) contentSize=(42.0, 200.0)
//     scroller (29.0, 0.0, 17.0, 200.0) knobSlot=(8.0, 3.0, 6.0, 194.0) knob=(8.0, 3.0, 6.0, 64.0) style=1
//   N8 horizontal ScrollView, .contentMargins(.bottom, 7, for: .scrollIndicators)
//     scrollView (0.0, 0.0, 200.0, 16.0) scrollerInsets=(t0.0 l0.0 b7.0 r0.0) contentSize=(200.0, 16.0)
//     scroller (0.0, -8.0, 200.0, 17.0) knobSlot=(3.0, 8.0, 194.0, 6.0) knob=(3.0, 8.0, 32.0, 6.0) style=1
//   N9 horizontal ScrollView control
//     scrollView (0.0, 0.0, 200.0, 16.0) scrollerInsets=(t0.0 l0.0 b0.0 r0.0) contentSize=(200.0, 16.0)
//     scroller (0.0, -1.0, 200.0, 17.0) knobSlot=(3.0, 8.0, 194.0, 6.0) knob=(3.0, 8.0, 32.0, 6.0) style=1
//   P1 ScrollView { rows }.padding(.horizontal, 7)
//     scrollView (0.0, 0.0, 42.0, 200.0) scrollerInsets=(t0.0 l0.0 b0.0 r0.0) contentSize=(42.0, 200.0)
//     scroller (25.0, 0.0, 17.0, 200.0) knobSlot=(8.0, 3.0, 6.0, 194.0) knob=(8.0, 3.0, 6.0, 64.0) style=1
//

import AppKit
import SwiftUI

setvbuf(stdout, nil, _IOLBF, 0)
@MainActor func spin(_ s: Double = 0.3) { RunLoop.main.run(until: Date().addingTimeInterval(s)) }
func str(_ v: Any?) -> String { v.map { "\($0)" } ?? "nil" }
/// KVC, guarded: AppKit's own row/cell mock elements are not KVC-compliant for
/// the accessibility keys, and an undefined key raises.
func kv(_ o: NSObject, _ key: String) -> Any? {
    let isKey = "is" + key.prefix(1).uppercased() + key.dropFirst()
    guard o.responds(to: Selector(key)) || o.responds(to: Selector(isKey)) else { return nil }
    return o.value(forKey: key)
}
@MainActor func kids(_ o: NSObject) -> [NSObject] { ((kv(o, "accessibilityChildren") as? [Any]) ?? []).compactMap { $0 as? NSObject } }
@MainActor func customActions(_ o: NSObject) -> [NSAccessibilityCustomAction] {
    (kv(o, "accessibilityCustomActions") as? [NSAccessibilityCustomAction]) ?? []
}
@MainActor func line(_ o: NSObject) -> String {
    var s = "\(type(of: o))".components(separatedBy: "<").first!
    s += " role=\(str(kv(o, "accessibilityRole"))) sub=\(str(kv(o, "accessibilitySubrole")))"
    s += " label=\(str(kv(o, "accessibilityLabel"))) value=\(str(kv(o, "accessibilityValue")))"
    if let help = kv(o, "accessibilityHelp") as? String, !help.isEmpty { s += " help=\(help)" }
    if let ident = kv(o, "accessibilityIdentifier") as? String, !ident.isEmpty { s += " id=\(ident)" }
    if (kv(o, "accessibilitySelected") as? Bool) == true { s += " selected" }
    if (kv(o, "accessibilityEnabled") as? Bool) == false { s += " disabled" }
    let names = customActions(o).map(\.name)
    if !names.isEmpty { s += " custom=\(names)" }
    if str(kv(o, "accessibilityRole")) == "AXOutline" { s += " rows=\((kv(o, "accessibilityRows") as? [Any])?.count ?? -1)" }
    s += " kids=\(kids(o).count)"
    return s
}
@MainActor func describe(_ o: NSObject, _ d: Int = 0, maxDepth: Int = 4, maxKids: Int = 5) {
    print(String(repeating: "  ", count: d) + line(o))
    if d < maxDepth { for k in kids(o).prefix(maxKids) { describe(k, d + 1, maxDepth: maxDepth, maxKids: maxKids) } }
}
@MainActor func perform(_ e: NSObject, _ sel: String) -> Bool {
    typealias Fn = @convention(c) (AnyObject, Selector) -> Bool
    return unsafeBitCast(e.method(for: Selector(sel)), to: Fn.self)(e, Selector(sel))
}
/// Depth-first, first node with this role.
@MainActor func find(_ o: NSObject, role: String) -> NSObject? {
    if str(kv(o, "accessibilityRole")) == role { return o }
    for k in kids(o) { if let f = find(k, role: role) { return f } }
    return nil
}
final class Counter: @unchecked Sendable { var n = 0; var log: [String] = [] }
var windows: [NSWindow] = []
@MainActor func host<V: View>(_ name: String, _ v: V, size: CGSize = CGSize(width: 300, height: 300)) -> NSHostingView<V> {
    let w = NSWindow(contentRect: NSRect(x: 100, y: 100, width: size.width, height: size.height),
                     styleMask: [.titled], backing: .buffered, defer: false)
    w.isReleasedWhenClosed = false
    let h = NSHostingView(rootView: v)
    w.contentView = h
    w.orderFrontRegardless(); w.makeKey(); h.layoutSubtreeIfNeeded(); spin(0.5)
    print("=== \(name)"); windows.append(w)
    return h
}
@MainActor func show<V: View>(_ name: String, _ v: V, size: CGSize = CGSize(width: 300, height: 300)) {
    describe(host(name, v, size: size), maxDepth: 5, maxKids: 6)
}
@MainActor func scrollers(_ o: NSObject, _ d: Int = 0) {
    if let s = o as? NSScroller {
        print("  NSScroller frame=\(s.frame) knobProportion=\(s.knobProportion) knobSlot=\(s.rect(for: .knobSlot)) knob=\(s.rect(for: .knob)) style=\(s.scrollerStyle.rawValue)")
    }
    if let v = o as? NSView { for k in v.subviews { scrollers(k, d + 1) } }
}
@MainActor func showScroller<V: View>(_ name: String, _ v: V, size: CGSize = CGSize(width: 300, height: 200)) {
    let h = host(name, v, size: size)
    if let sv = firstScrollView(h) {
        print("  NSScrollView frame=\(sv.frame) contentInsets=\(sv.contentInsets) scrollerInsets=\(sv.scrollerInsets) contentSize=\(sv.contentSize)")
    }
    scrollers(h)
}
@MainActor func firstScrollView(_ v: NSView) -> NSScrollView? {
    if let s = v as? NSScrollView { return s }
    for k in v.subviews { if let f = firstScrollView(k) { return f } }
    return nil
}
NSApplication.shared.setActivationPolicy(.accessory)
NSApp.setValue(true, forKey: "accessibilityEnhancedUserInterface")
func rows(_ n: Int = 30) -> some View {
    VStack(spacing: 0) { ForEach(0..<n, id: \.self) { Text("row \($0)").frame(height: 20) } }
}
func rowsWithIDs(_ n: Int = 30) -> some View {
    VStack(spacing: 0) { ForEach(0..<n, id: \.self) { Text("row \($0)").frame(height: 20).accessibilityIdentifier(n > 1 && $0 % 2 == 0 ? "block-\($0)" : "x") } }
}
@MainActor func run() {
    // Gap 2: where an identifier written on a ScrollView lands.
    show("I0 control: ScrollView { rows } (no identifier)", ScrollView { VStack { Text("a"); Text("b") } }, size: CGSize(width: 300, height: 200))
    show("I1 ScrollView { Text a; Text b }.accessibilityIdentifier(transcript)",
         ScrollView { VStack { Text("a"); Text("b") } }.accessibilityIdentifier("transcript"), size: CGSize(width: 300, height: 200))
    show("I2 ScrollView { Text a(id a); Text b(id b) }.accessibilityIdentifier(transcript)",
         ScrollView { VStack { Text("a").accessibilityIdentifier("a"); Text("b").accessibilityIdentifier("b") } }.accessibilityIdentifier("transcript"),
         size: CGSize(width: 300, height: 200))
    show("I3 ScrollView { Text a(id a); Text c (no id) }.accessibilityIdentifier(transcript)",
         ScrollView { VStack { Text("a").accessibilityIdentifier("a"); Text("c") } }.accessibilityIdentifier("transcript"),
         size: CGSize(width: 300, height: 200))
    // Gap 3: a negative indicator margin.
    showScroller("N0 control 30 rows", ScrollView { rows() })
    showScroller("N1 .contentMargins(.horizontal, 7, for: .scrollIndicators)", ScrollView { rows() }.contentMargins(.horizontal, 7, for: .scrollIndicators))
    showScroller("N2 .contentMargins(.horizontal, -7, for: .scrollIndicators)", ScrollView { rows() }.contentMargins(.horizontal, -7, for: .scrollIndicators))
    showScroller("N3 .contentMargins(.vertical, -20, for: .scrollIndicators)", ScrollView { rows() }.contentMargins(.vertical, -20, for: .scrollIndicators))
    showScroller("N4 .contentMargins(.vertical, 20, for: .scrollIndicators)", ScrollView { rows() }.contentMargins(.vertical, 20, for: .scrollIndicators))
    showScroller("N5 .contentMargins(.trailing, 7, for: .scrollIndicators)", ScrollView { rows() }.contentMargins(.trailing, 7, for: .scrollIndicators))
    showScroller("N6 .contentMargins(.leading, 7, for: .scrollIndicators)", ScrollView { rows() }.contentMargins(.leading, 7, for: .scrollIndicators))
    showScroller("N7 .contentMargins(.trailing, -4, for: .scrollIndicators)", ScrollView { rows() }.contentMargins(.trailing, -4, for: .scrollIndicators))
    showScroller("N8 horizontal ScrollView, .contentMargins(.bottom, 7, for: .scrollIndicators)",
                 ScrollView(.horizontal) { HStack(spacing: 0) { ForEach(0..<30, id: \.self) { Text("c \($0)").frame(width: 40) } } }
                    .contentMargins(.bottom, 7, for: .scrollIndicators), size: CGSize(width: 200, height: 42))
    showScroller("N9 horizontal ScrollView control",
                 ScrollView(.horizontal) { HStack(spacing: 0) { ForEach(0..<30, id: \.self) { Text("c \($0)").frame(width: 40) } } }, size: CGSize(width: 200, height: 42))
    // Gap 1: a padding on the ScrollView insets its viewport inside the parent.
    showScroller("P1 ScrollView { rows }.padding(.horizontal, 7)", ScrollView { rows() }.padding(.horizontal, 7))
    spin(0.2)
}
MainActor.assumeIsolated { run() }
