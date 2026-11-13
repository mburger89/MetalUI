// SwiftUI probe: contentMargins(_:_:for:) and ContentMarginPlacement (.automatic, .scrollContent,
// .scrollIndicators) on a vertical ScrollView, for Alloy gap G43 (glass bars floating over scrolled content;
// decisions CMG-A.. in docs/superpowers/2026-11-13-content-margins-decisions.md).
//
// HOW TO RUN (ruling SA-O):
//
//   /usr/bin/swift docs/probes/swiftui-content-margins.swift
//   xcrun swiftc -O docs/probes/swiftui-content-margins.swift -o /tmp/cmg && /tmp/cmg
//
// `/usr/bin/swift` is Apple's toolchain; a swift.org toolchain's JIT fails on SwiftUI symbols.
//
// **NOT RUN.** This file was written by the G43 session, which may open no window; it has not been compiled or
// executed, and NO recorded output exists. The MetalUI tests (`ContentMarginsTests.swift`) are built from the
// documentation's statements, not from these readings. Run it on a Mac, paste the stdout under WHOLE STDOUT and
// settle the five uncertainties named in the decisions doc (`.automatic` and the indicators, per-edge override,
// the thumb's length with an inset, the right-to-left indicator, a top-margin change while scrolled away).
//
// METHOD (as swiftui-default-scroll-anchor.swift). A 200x200 borderless NSWindow hosts the view; the first
// NSScrollView under the hosting view is the instrument: `clip.bounds.origin.y` is the offset (0 = top),
// `documentView.frame.height` the content extent, `scrollView.contentInsets` / `automaticallyAdjustsContentInsets`
// the AppKit inset the margin becomes, and `verticalScroller` frame the indicator track. Rows are 20 points;
// every arm has a CONTROL without the modifier.
//
// EXPECTED READINGS (the arm ids the tests cite; 30 rows = 600 in 200, margins 40 above and 60 below):
//   M1 `.contentMargins(.top, 40, for: .scrollContent)` + `.contentMargins(.bottom, 60, for: .scrollContent)`:
//      first row's top at offset 0 is 40; at the maximum offset (500) the last row ends at 140 = 200 - 60.
//      Control: 0 and 180.
//   M2 the content draws under the margin region: scrolled by 30, row 0 (top 10) is on screen, not clipped.
//   M3 `.contentMargins(.vertical, 30, for: .scrollIndicators)`: the first row stays at 0 and the content's
//      extent is the control's (600); the indicator's track starts at 30 and ends at 170.
//   M4 `.contentMargins(.vertical, 40)` (`.automatic`): UNCERTAIN, expected both the content and the indicator.
//   M5 a margin adds to the content's own padding: `.padding(10)` on the content under a 40 margin puts the first
//      row at 50.
//   M6 per-edge override: `.contentMargins(.top, 10, for: .scrollContent)` inside `.contentMargins(.vertical, 40,
//      ...)`: UNCERTAIN whether the bottom stays 40 (per edge) or resets (whole placement).
//   M7 `ScrollViewReader.scrollTo(10, anchor: .top)` puts row 10 at 40; `.bottom` at 120 (its top).
//   M8 `.defaultScrollAnchor(.bottom)`: the last row's top is 120; growing the bottom margin to 100 moves it to 80
//      in the same layout pass (no lag); a scroller scrolled away keeps its offset.
//   M9 `List` takes the same margins as a ScrollView.
//
// WHOLE STDOUT: (none recorded; not run)

import SwiftUI
import AppKit

@MainActor final class Model: ObservableObject {
    @Published var bottom: CGFloat = 60
    @Published var count = 30
}

@MainActor func scroller(from root: NSView) -> NSScrollView? {
    if let s = root as? NSScrollView { return s }
    for sub in root.subviews { if let s = scroller(from: sub) { return s } }
    return nil
}

@MainActor func host<V: View>(_ view: V) -> (NSWindow, NSScrollView?) {
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 200), styleMask: .borderless,
                          backing: .buffered, defer: false)
    let hosting = NSHostingView(rootView: view.frame(width: 200, height: 200))
    window.contentView = hosting
    window.orderFrontRegardless()
    for _ in 0..<5 { RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05)); hosting.layoutSubtreeIfNeeded() }
    return (window, scroller(from: hosting))
}

@MainActor func report(_ id: String, _ what: String, _ s: NSScrollView?) {
    guard let s, let doc = s.documentView else { print("\(id) \(what): no scroll view"); return }
    print("\(id) \(what): offset \(s.contentView.bounds.origin.y) content \(doc.frame.height) viewport \(s.contentView.bounds.height) insets top \(s.contentInsets.top) bottom \(s.contentInsets.bottom)")
}

struct Rows: View {
    var count = 30
    var body: some View {
        VStack(spacing: 0) { ForEach(0..<count, id: \.self) { Text("row \($0)").frame(height: 20) } }
    }
}

@MainActor func main() {
    print("=== M: content margins (30 rows x 20 = 600 in 200)")
    let (w0, s0) = host(ScrollView { Rows() })
    report("M0", "control", s0)
    let (w1, s1) = host(ScrollView { Rows() }
        .contentMargins(.top, 40, for: .scrollContent).contentMargins(.bottom, 60, for: .scrollContent))
    report("M1", "top 40 bottom 60, scrollContent", s1)
    let (w3, s3) = host(ScrollView { Rows() }.contentMargins(.vertical, 30, for: .scrollIndicators))
    report("M3", "indicators 30", s3)
    let (w4, s4) = host(ScrollView { Rows() }.contentMargins(.vertical, 40))
    report("M4", "automatic 40", s4)
    let (w5, s5) = host(ScrollView { Rows().padding(10) }.contentMargins(.top, 40, for: .scrollContent))
    report("M5", "padding 10 + top 40", s5)
    let (w6, s6) = host(ScrollView { Rows() }
        .contentMargins(.top, 10, for: .scrollContent).contentMargins(.vertical, 40, for: .scrollContent))
    report("M6", "inner top 10 under outer vertical 40", s6)
    let (w9, s9) = host(List(0..<30, id: \.self) { Text("row \($0)") }
        .contentMargins(.vertical, 40, for: .scrollContent))
    report("M9", "List", s9)
    _ = (w0, w1, w3, w4, w5, w6, w9)
    print("DONE")
}

MainActor.assumeIsolated { main() }
