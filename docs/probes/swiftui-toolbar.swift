// SwiftUI probe: `.toolbar { ToolbarItem(placement:) { … } }` on macOS — what
// SwiftUI puts in the window (port-gaps-medium design, rulings MD-… in
// docs/superpowers/2026-10-07-port-gaps-medium-decisions.md; MG-3).
//
// QUESTIONS.
// - TB: with a toolbar on the root view of an `NSHostingController` whose
//   `sceneBridgingOptions` include `.toolbars`: does the NSWindow get an
//   NSToolbar; its style, display mode, item identifiers, labels, and what
//   view each item holds (an AppKit control, or SwiftUI hosting its own view).
// - PL: where each placement lands (identifier order; the principal and
//   navigation items).
// - GEO: the titlebar+toolbar height (frame height − contentLayoutRect
//   height) with and without a toolbar; where the root view's content starts.
// - SR: `.searchable(text:)` — the item it adds.
// - UP: an item whose state changes (a Toggle's binding written from outside)
//   — is the toolbar rebuilt or updated in place (item identity kept).
//
// INSTRUMENTS. A real NSWindow (needs an unlocked screen —
// appkit-screen-lock-state.swift), a 1.0 s run-loop spin, then a dump of
// `window.toolbar` and each item's view subtree (class names, depth ≤ 4).
//
// POSITIVE CONTROL. TB0: the same window without `.toolbar` has no toolbar
// (or an empty one) and the 28-point titlebar. SEPARATING ARM: TB0 vs TB1.
//
// HOW TO RUN (compiled form, SA-O):
//
//   xcrun swiftc docs/probes/swiftui-toolbar.swift -o /tmp/md-toolbar && /tmp/md-toolbar
//
// RECORDED and READING: the block at the end of this file.

import AppKit
import SwiftUI

@MainActor func spin(_ s: Double = 1.0) { RunLoop.main.run(until: Date().addingTimeInterval(s)) }
func f(_ v: CGFloat) -> String {
    let r = (v * 100).rounded() / 100
    return r == r.rounded() ? "\(Int(r))" : String(format: "%.2f", Double(r))
}
func f(_ r: CGRect) -> String { "(\(f(r.minX)), \(f(r.minY)), \(f(r.width)), \(f(r.height)))" }

func tree(_ v: NSView, depth: Int = 0) -> [String] {
    guard depth <= 4 else { return [] }
    var out = [String(repeating: "  ", count: depth) + "\(type(of: v)) \(f(v.frame))"]
    for s in v.subviews { out += tree(s, depth: depth + 1) }
    return out
}

@Observable final class Model { var on = false; var pick = 0; var search = ""; var query = "" }
let model = Model()

struct Root: View {
    @Bindable var m: Model
    let withToolbar: Bool
    let searchable: Bool
    var body: some View {
        let base = Color.gray.opacity(0.2)
            .overlay(GeometryReader { g in
                Color.clear.onAppear { print("  GEO root frame in window: \(f(g.frame(in: .global))) safeTop=\(f(g.safeAreaInsets.top))") }
            })
            .frame(width: 600, height: 300)
        if withToolbar {
            let t = base.toolbar {
                ToolbarItem(placement: .navigation) { Button("Nav") {} }
                ToolbarItem(placement: .principal) {
                    Picker("Mode", selection: $m.pick) { Text("A").tag(0); Text("B").tag(1) }.pickerStyle(.segmented)
                }
                ToolbarItem(placement: .primaryAction) { Button { } label: { Image(systemName: "square.and.arrow.down") } }
                ToolbarItem(placement: .automatic) { Toggle("Advanced", isOn: $m.on) }
                ToolbarItem(placement: .automatic) { TextField("Filter", text: $m.query).frame(width: 120) }
                ToolbarItem(placement: .status) { Text("Status") }
            }
            if searchable { AnyView(t.searchable(text: $m.search)) } else { AnyView(t) }
        } else {
            AnyView(base)
        }
    }
}

var windows: [NSWindow] = []
@MainActor func open(_ label: String, toolbar: Bool, searchable: Bool = false) -> NSWindow {
    let c = NSHostingController(rootView: Root(m: model, withToolbar: toolbar, searchable: searchable))
    c.sceneBridgingOptions = [.toolbars, .title]
    let w = NSWindow(contentViewController: c)
    w.isReleasedWhenClosed = false
    w.title = label
    w.setFrameOrigin(NSPoint(x: 100, y: 100))
    w.makeKeyAndOrderFront(nil)
    spin()
    windows.append(w)
    print("\(label):")
    print("  window frame=\(f(w.frame)) contentLayoutRect=\(f(w.contentLayoutRect)) titlebar+toolbar=\(f(w.frame.height - w.contentLayoutRect.height))")
    print("  styleMask fullSizeContentView=\(w.styleMask.contains(.fullSizeContentView)) titlebarAppearsTransparent=\(w.titlebarAppearsTransparent) toolbarStyle=\(w.toolbarStyle.rawValue) titleVisibility=\(w.titleVisibility.rawValue)")
    if let t = w.toolbar {
        print("  toolbar class=\(type(of: t)) id=\(t.identifier) displayMode=\(t.displayMode.rawValue) items=\(t.items.count) visible=\(t.isVisible) allowsUserCustomization=\(t.allowsUserCustomization) centered=\(t.centeredItemIdentifiers.map(\.rawValue))")
        for item in t.items {
            print("  item id=\(item.itemIdentifier.rawValue) class=\(type(of: item)) label=\"\(item.label)\" bordered=\(item.isBordered) navigational=\(item.isNavigational) visibilityPriority=\(item.visibilityPriority.rawValue)")
            if let v = item.view { for line in tree(v) { print("      " + line) } }
        }
    } else {
        print("  toolbar nil")
    }
    return w
}

@MainActor func run() {
    NSApplication.shared.setActivationPolicy(.regular)
    NSApplication.shared.activate()
    _ = open("TB0 no toolbar", toolbar: false)
    let w1 = open("TB1 toolbar", toolbar: true)
    let before = w1.toolbar?.items.map { ObjectIdentifier($0) } ?? []
    let beforeToolbar = w1.toolbar.map { ObjectIdentifier($0) }
    model.on.toggle(); model.pick = 1
    spin(0.5)
    let after = w1.toolbar?.items.map { ObjectIdentifier($0) } ?? []
    print("UP after state change: same toolbar=\(beforeToolbar == w1.toolbar.map { ObjectIdentifier($0) }) same items=\(before == after) count=\(after.count)")
    _ = open("SR searchable", toolbar: true, searchable: true)
}

MainActor.assumeIsolated { run() }

// RECORDED 2026-10-06 on macOS 27.0.1 (26A434), Apple Swift 6.4
// (swiftlang-6.4.0.33.1), screen unlocked (appkit-screen-lock-state.swift: no
// CGSSessionScreenIsLocked line, displayAsleep main: 0), compiled form. Run three
// times by the design session; the three outputs (68 lines) are identical once the per-run item UUIDs are replaced by <uuid> (as below).
//
// READING (the authority for MD-I…MD-K):
// - TB0 (positive control): no toolbar; titlebar 32 points (frame 332 for a
//   300-tall content). TB1: an NSToolbar exists; the frame grows to 352
//   (titlebar + toolbar 52) while contentLayoutRect stays 600x300 — the window
//   grows, the content keeps its size; fullSizeContentView false; toolbarStyle
//   0 (.automatic); displayMode 2 (.iconOnly); allowsUserCustomization false.
// - Items: one AppKitToolbarItem per ToolbarItem, each holding a
//   ToolbarItemHostingView (SwiftUI's own view; the segmented picker and the
//   text field are AppKit controls inside it). Order in `items`: principal
//   ("Mode") and status, both in centeredItemIdentifiers; a flexible space;
//   the navigation item (isNavigational true); the primaryAction image button
//   (36x36); the Toggle (73.50x36); the TextField (120x24). Item heights 36.
// - UP: after the Toggle's and the Picker's bindings change, the same NSToolbar
//   and the same item objects (updated in place).
// - SR: .searchable adds a second flexible space and
//   com.apple.SwiftUI.search (AppKitSearchToolbarItem, label "Search") last.
// - GEO: the root view's frame in the window is the same 600x300 with and
//   without the toolbar (safe-area top 0).
//
// OUTPUT:
//   GEO root frame in window: (-300, -150, 600, 300) safeTop=0
// TB0 no toolbar:
//   window frame=(100, 100, 600, 332) contentLayoutRect=(0, 0, 600, 300) titlebar+toolbar=32
//   styleMask fullSizeContentView=false titlebarAppearsTransparent=false toolbarStyle=0 titleVisibility=0
//   toolbar nil
//   GEO root frame in window: (-300, -150, 600, 300) safeTop=0
// TB1 toolbar:
//   window frame=(100, -168, 600, 352) contentLayoutRect=(0, 0, 600, 300) titlebar+toolbar=52
//   styleMask fullSizeContentView=false titlebarAppearsTransparent=false toolbarStyle=0 titleVisibility=0
//   toolbar class=NSToolbar id= displayMode=2 items=7 visible=true allowsUserCustomization=false centered=["<uuid>", "<uuid>"]
//   item id=<uuid> class=AppKitToolbarItem label="Mode" bordered=true navigational=false visibilityPriority=0
//       ToolbarItemHostingView<_ViewList_View> (4, 8, 70, 36)
//         AppKitPlatformViewHost<PlatformViewRepresentableAdaptor<SystemSegmentedControl>> (0, 0, 70, 36)
//           SwiftUISegmentedControl (0, 0, 70, 36)
//             _NSCoreHostingView<AppKitSegmentedControl> (0, 0, 70, 36)
//   item id=<uuid> class=AppKitToolbarItem label="" bordered=true navigational=false visibilityPriority=0
//       ToolbarItemHostingView<_ViewList_View> (4, 18, 39, 16)
//   item id=NSToolbarFlexibleSpaceItem class=NSToolbarFlexibleSpaceItem label="" bordered=false navigational=false visibilityPriority=0
//   item id=<uuid> class=AppKitToolbarItem label="" bordered=true navigational=true visibilityPriority=0
//       ToolbarItemHostingView<_ViewList_View> (4, 8, 36, 36)
//         _FocusRingView (0, 0, 36, 36)
//         KeyViewProxy (0, 0, 36, 36)
//   item id=<uuid> class=AppKitToolbarItem label="" bordered=true navigational=false visibilityPriority=0
//       ToolbarItemHostingView<_ViewList_View> (0, 8, 36, 36)
//         _FocusRingView (0, 0, 36, 36)
//         KeyViewProxy (0, 0, 36, 36)
//   item id=<uuid> class=AppKitToolbarItem label="" bordered=true navigational=false visibilityPriority=0
//       ToolbarItemHostingView<_ViewList_View> (4.50, 8, 73.50, 36)
//         _FocusRingView (0, 0, 73.50, 36)
//         KeyViewProxy (0, 0, 73.50, 36)
//   item id=<uuid> class=AppKitToolbarItem label="" bordered=true navigational=false visibilityPriority=0
//       ToolbarItemHostingView<_ViewList_View> (0, 0, 0, 0)
//         AppKitPlatformViewHost<PlatformViewRepresentableAdaptor<PlatformTextFieldAdaptor>> (-60, -12, 120, 24)
//           AppKitTextField (0, 0, 120, 24)
//             _NSCoreHostingView<AppKitTextField> (0, 0, 120, 24)
// UP after state change: same toolbar=true same items=true count=7
//   GEO root frame in window: (-300, -150, 600, 300) safeTop=0
// SR searchable:
//   window frame=(100, -168, 600, 352) contentLayoutRect=(0, 0, 600, 300) titlebar+toolbar=52
//   styleMask fullSizeContentView=false titlebarAppearsTransparent=false toolbarStyle=0 titleVisibility=0
//   toolbar class=NSToolbar id= displayMode=2 items=9 visible=true allowsUserCustomization=false centered=["<uuid>", "<uuid>"]
//   item id=<uuid> class=AppKitToolbarItem label="Mode" bordered=true navigational=false visibilityPriority=0
//       ToolbarItemHostingView<_ViewList_View> (4, 8, 70, 36)
//         AppKitPlatformViewHost<PlatformViewRepresentableAdaptor<SystemSegmentedControl>> (0, 0, 70, 36)
//           SwiftUISegmentedControl (0, 0, 70, 36)
//             _NSCoreHostingView<AppKitSegmentedControl> (0, 0, 70, 36)
//   item id=<uuid> class=AppKitToolbarItem label="" bordered=true navigational=false visibilityPriority=0
//       ToolbarItemHostingView<_ViewList_View> (4, 18, 39, 16)
//   item id=NSToolbarFlexibleSpaceItem class=NSToolbarFlexibleSpaceItem label="" bordered=false navigational=false visibilityPriority=0
//   item id=<uuid> class=AppKitToolbarItem label="" bordered=true navigational=true visibilityPriority=0
//       ToolbarItemHostingView<_ViewList_View> (4, 8, 36, 36)
//         _FocusRingView (0, 0, 36, 36)
//         KeyViewProxy (0, 0, 36, 36)
//   item id=<uuid> class=AppKitToolbarItem label="" bordered=true navigational=false visibilityPriority=0
//       ToolbarItemHostingView<_ViewList_View> (0, 8, 36, 36)
//         _FocusRingView (0, 0, 36, 36)
//         KeyViewProxy (0, 0, 36, 36)
//   item id=<uuid> class=AppKitToolbarItem label="" bordered=true navigational=false visibilityPriority=0
//       ToolbarItemHostingView<_ViewList_View> (4.50, 8, 73.50, 36)
//         _FocusRingView (0, 0, 73.50, 36)
//         KeyViewProxy (0, 0, 73.50, 36)
//   item id=<uuid> class=AppKitToolbarItem label="" bordered=true navigational=false visibilityPriority=0
//       ToolbarItemHostingView<_ViewList_View> (0, 0, 0, 0)
//         AppKitPlatformViewHost<PlatformViewRepresentableAdaptor<PlatformTextFieldAdaptor>> (-60, -12, 120, 24)
//           AppKitTextField (0, 0, 120, 24)
//             _NSCoreHostingView<AppKitTextField> (0, 0, 120, 24)
//   item id=NSToolbarFlexibleSpaceItem class=NSToolbarFlexibleSpaceItem label="" bordered=false navigational=false visibilityPriority=0
//   item id=com.apple.SwiftUI.search class=AppKitSearchToolbarItem label="Search" bordered=true navigational=false visibilityPriority=0
