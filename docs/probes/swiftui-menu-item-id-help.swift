// SwiftUI probe: `.accessibilityIdentifier` and `.help` on a Button inside
// `.contextMenu` — does SwiftUI carry them to the NSMenuItem? Evidence for
// ruling MN-AL in docs/superpowers/2026-10-02-menus-popovers-decisions.md
// (Alloy gap G24, record 253).
//
// HOW TO RUN (compiled form, SA-O):
//
//   xcrun swiftc docs/probes/swiftui-menu-item-id-help.swift -o /tmp/menu-id-help-probe
//   /tmp/menu-id-help-probe
//
// Headless: a synthesized right-mouse NSEvent is handed to `menu(for:)` on the
// hit view of an NSHostingView; nothing is posted at the HID tap.
//
// RECORDED OUTPUT (macOS 27.2, 2026-11-09, run on an unlocked-or-locked session
// alike; no window server traffic beyond the hosting view):
//
//   "Fork" enabled=true toolTip=Optional("Fork this branch") identifier=Optional("menuAction:") axIdentifier="" axHelp=nil
//   "Rename" enabled=false toolTip=Optional("Nothing to rename yet") identifier=nil axIdentifier="" axHelp=nil
//   "Plain" enabled=true toolTip=nil identifier=Optional("menuAction:") axIdentifier="" axHelp=nil
//
// READING. `.help` reaches `NSMenuItem.toolTip`, on a disabled item too.
// `.accessibilityIdentifier` does NOT reach the item: `accessibilityIdentifier()`
// is empty and `identifier` is SwiftUI's own "menuAction:" selector name (nil
// when disabled). MetalUI sets the identifier anyway (MN-AL): it is what Alloy
// asked for and nothing in SwiftUI contradicts it.
import AppKit
import SwiftUI

struct Host: View {
    var body: some View {
        Text("Target").frame(width: 200, height: 100)
            .contextMenu {
                Button("Fork") {}.accessibilityIdentifier("fork-1234").help("Fork this branch")
                Button("Rename") {}.accessibilityIdentifier("rename-1234").help("Nothing to rename yet").disabled(true)
                Button("Plain") {}
            }
    }
}

@MainActor func spin(_ s: Double) { RunLoop.current.run(until: Date(timeIntervalSinceNow: s)) }

let app = NSApplication.shared
app.setActivationPolicy(.regular)
MainActor.assumeIsolated {
    let w = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 300, height: 200),
                     styleMask: [.titled], backing: .buffered, defer: false)
    let h = NSHostingView(rootView: Host())
    w.contentView = h
    w.orderFrontRegardless(); w.makeKey(); h.layoutSubtreeIfNeeded(); spin(0.4)
    let pt = CGPoint(x: h.bounds.midX, y: h.bounds.midY)
    let e = NSEvent.mouseEvent(with: .rightMouseDown, location: pt, modifierFlags: [],
                               timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: w.windowNumber,
                               context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
    let hit = h.hitTest(h.convert(pt, from: nil)) ?? h
    guard let menu = hit.menu(for: e) else { print("no menu"); exit(1) }
    for item in menu.items {
        print("\"\(item.title)\" enabled=\(item.isEnabled) toolTip=\(String(describing: item.toolTip))"
              + " identifier=\(String(describing: item.identifier?.rawValue))"
              + " axIdentifier=\(item.accessibilityIdentifier().debugDescription)"
              + " axHelp=\(String(describing: item.accessibilityHelp()))")
    }
}
