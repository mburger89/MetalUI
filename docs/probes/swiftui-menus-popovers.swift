// SwiftUI probe: menus, popovers and tooltips (user request 2026-10-02, not a
// plan task) — `.contextMenu`, `Menu`, `Divider`, `.popover`, `.help`.
// Evidence for rulings MN-A… in
// docs/superpowers/2026-10-02-menus-popovers-decisions.md; spec
// docs/superpowers/specs/2026-10-02-menus-popovers-design.md. The menu bar
// (`.commands`) is the companion probe swiftui-commands.swift (it needs an
// `App` scene).
//
// HOW TO RUN (compiled form, SA-O):
//
//   xcrun swiftc docs/probes/swiftui-menus-popovers.swift -o /tmp/menus-probe
//   /tmp/menus-probe
//
// Headless: every event is a synthesized NSEvent handed to NSApp.sendEvent or
// to a view; nothing is posted at the HID tap, so a locked screen does not
// stop it (it was locked when this was recorded).
//
// THE INSTRUMENTS.
// - C: `NSView.menu(for:)` on the hit view under a synthesized right-mouse
//   event, and the NSMenu it returns dumped item by item (title, separator,
//   submenu, state, enabled, key equivalent); `performActionForItem(at:)`
//   runs an item. C5/C6 send a real right-mouse-down / control-left-mouse-down
//   through NSApp.sendEvent and record `NSMenu.didBeginTrackingNotification`
//   (the menu is then cancelled from a timer in the event-tracking mode).
// - P: a `.popover(isPresented:)` presented by flipping an ObservableObject;
//   NSApp.windows listed by class with frames relative to the anchor; Escape
//   and an outside mouse-down sent through NSApp.sendEvent.
// - H: `.help` read through the NSAccessibility walk of
//   swiftui-accessibility-part2.swift (KVC after AXEnhancedUserInterface),
//   plus `toolTip` on every NSView under the hosting view, and a tooltip
//   window looked for after a synthesized mouse-moved.
//
// POSITIVE CONTROLS AND SEPARATING ARMS. C0 (no contextMenu: menu nil) against
// C1. P0 (isPresented false: no popover window) against P1. H0 (no help: no
// help attribute) against H1. C5r (right-click) against C5l (plain left click,
// no menu). P4a (outside click on a Button: does it fire) against P4b (the
// same click with no popover shown: it fires).
//
// RECORDED 2026-10-02 by the menus/popovers design session, macOS 27.0,
// Apple Swift 6.4, screen LOCKED (CGSSessionScreenIsLocked = 1, displayAsleep
// main: 1), so the app never became active and had no key window. Compiled
// form, run twice: stdout byte-identical (131 lines), exit 0, stderr empty.
//
// CRITIC ROUND, 2026-10-02 (same machine, screen locked): the recorded
// program was first re-run unchanged — its stdout matched the 130 output lines
// below it byte for byte. Four arms were then APPENDED after C10 (nothing
// above them changed): C11n (show-menu on a node with no contextMenu — the
// separating arm C11 lacked: every node responds to the selector, so the
// dumps' `[showMenu]` is not an advertised action), C13c/C13 (a right press on
// a contextMenu view, then the same under `.allowsHitTesting(false)`) and C14
// (the menu view covered by an opaque sibling with no menu). Extended form run
// twice: stdout byte-identical (137 lines), exit 0, stderr empty. The P0/P3/
// P4a lines list three more windows than before (C13c, C13, C14 stay open);
// no other line moved. Rulings MN-U, MN-V, MN-W rest on these arms.
//
// WHAT THE LOCKED SCREEN COSTS (read before resting a ruling on an arm):
// - C5c/C5n: a synthesized control-left-click opens NO menu even on a plain
//   AppKit NSView with `menu` set (C5n), which right-click opens — AppKit's
//   control-click rule reads state a synthesized event does not carry. The
//   control-click arms are a broken instrument, not a SwiftUI answer.
// - P3/P3b/P4a/P4c: the popover window never became key (`key=false`,
//   `keyWindow=nil` even after makeKey), so Escape and an outside click
//   reached nothing that dismisses a transient NSPopover. Unmeasured, not
//   "SwiftUI keeps it open". `behavior=1` is NSPopover.Behavior.transient.
// - H7: no tooltip window appears for a synthesized mouse-moved in an
//   inactive app; the tooltip's delay and look are unmeasured.
// - C7b: a right-mouse-down on a `Button.contextMenu` began no menu tracking
//   and the right-mouse-UP pressed the button — read with C6 (a right click
//   presses a plain SwiftUI Button) and C6n (an NSButton ignores it).
//
// OUTPUT, verbatim:
//
//   --- C: contextMenu
//   === C0 control: Text without contextMenu
//     menu: nil
//   === C1 contextMenu { Copy, Delete(destructive), Divider, Menu More, Toggle, Picker, disabled, ⌘K, Label, Section, Text }
//     menu class=NSMenu items=14 autoenables=false
//     "Copy" action=menuAction:
//     "Delete" action=menuAction:
//     ----
//     "More" action=submenuAction: submenu:
//       "Sub A" action=menuAction:
//       "Sub B" action=menuAction:
//     "Flag" state=on action=menuAction:
//     "Pick" action=submenuAction: submenu:
//       "One" state=on action=menuAction:
//       "Two" action=menuAction:
//     "Off" disabled
//     "Short" key="k" mods=16 action=menuAction:
//     "Labelled" action=menuAction: image
//     ----
//     "Header"
//     "In section" action=menuAction:
//     ----
//     "Plain text item" disabled
//     C2 perform Copy -> log ["copy"]
//     C3 perform More>Sub B -> log ["copy", "subB"]
//     C4 perform Flag -> flag=false
//     C4b perform Pick>Two -> pick=2
//     C4c reopened: same object=false Flag state=off
//     C12 closed menu, window.performKeyEquivalent(⌘K) -> false log []
//     C12b NSApp.sendEvent(⌘K) -> log []
//     C5r right mouse down/up: menu tracking began ["14 items"]
//     C5c control-left mouse down/up: menu tracking began []
//     C5l control: plain left mouse down/up: menu tracking began []
//     C5n NSView.menu right mouse down/up: menu tracking began ["1 items"]
//     C5n NSView.menu control-left mouse down/up: menu tracking began []
//     C11 target actionNames=[]
//     C11 accessibilityPerformShowMenu -> true, menu tracking began ["14 items"]
//     C11c control (no contextMenu) actionNames=[]
//   === C6 Button(B) right-click
//     right click -> log ["B"]
//     C6b plain left click -> log ["B", "B"]
//     C6n NSButton right click -> 0 actions
//   === C6t Text.onTapGesture right-click
//     right click -> log ["tap"]
//   === C7 Button(B).contextMenu { X }
//     menu: ["X"]
//     C7b right mouse down -> menu [], log []
//     C7b' right mouse up (default mode) -> menu [], log ["B"]
//     C7c left click -> menu [], log ["B", "B"]
//   === C8 VStack { Text(inner).contextMenu{Inner} }.contextMenu{Outer}
//     at inner: ["Inner"]
//     at outer-only text: ["Outer"]
//   === C9 Text.contextMenu{X}.disabled(true)
//     menu: ["X enabled=false"]
//   === C10 Text.contextMenu {} (empty)
//     menu: nil
//     C11n control (no contextMenu) accessibilityPerformShowMenu -> false, menu tracking began []
//   === C13c Text.contextMenu{X} right press (control)
//     menu tracking began ["[\"X\"]"]
//   === C13 Text.contextMenu{X}.allowsHitTesting(false) right press
//     menu tracking began []
//   === C14 ZStack { Text.contextMenu{Beneath}; Color.blue cover } right press
//     menu tracking began []
//   === M1 Menu(Title) { A; Divider; B }
//   --- P: popover
//   === P1 popover arrowEdge .bottom
//     P0 control (not shown): windows NSWindow,NSWindow,NSWindow,NSWindow,NSWindow,NSWindow,NSWindow,NSWindow,NSWindow,NSWindow,NSWindow,NSWindow,NSWindow
//     popover window _NSPopoverWindow frame rel main=(57,-30,186x106) main=300x232 key=false level=0
//     NSPopover behavior=1 animates=true shown=true contentSize=(186.0, 106.0)
//     P2 popover window AX:
//     _NSPopoverWindow role=AXPopover sub=nil label= value=nil [showMenu] kids=1
//       PopoverHostingView role=AXGroup sub=AXHostingView label=nil value=nil [showMenu] kids=2
//         AccessibilityNode role=AXStaticText sub=nil label=nil value=Popover body [showMenu] kids=0
//         AccessibilityNode role=AXButton sub=nil label=Inside value=nil [showMenu] kids=0
//     P2b main window AX while shown:
//     NSWindow role=AXWindow sub=AXStandardWindow label= value=nil [showMenu] kids=2
//       NSHostingView role=AXGroup sub=AXHostingView label=nil value=nil [showMenu] kids=2
//         AccessibilityNode role=AXButton sub=nil label=Under value=nil [showMenu] kids=0
//         AccessibilityNode role=AXButton sub=nil label=Anchor value=nil [showMenu] kids=0
//       NSAccessibilityReparentingCellProxy role=nil sub=nil label=nil value=nil kids=0
//     P3 Escape -> shown=true windows NSWindow,NSWindow,NSWindow,NSWindow,NSWindow,NSWindow,NSWindow,NSWindow,NSWindow,NSWindow,NSWindow,NSWindow,NSWindow,_NSPopoverWindow
//     P3b popover window made key: key=false keyWindow=nil
//     P3b Escape -> shown=true windows NSWindow,NSWindow,NSWindow,NSWindow,NSWindow,NSWindow,NSWindow,NSWindow,NSWindow,NSWindow,NSWindow,NSWindow,NSWindow,_NSPopoverWindow
//   === P1 popover arrowEdge .top
//     P0 control (not shown): windows NSWindow,NSWindow,NSWindow,NSWindow,NSWindow,NSWindow,NSWindow,NSWindow,NSWindow,NSWindow,NSWindow,NSWindow,NSWindow
//     popover window _NSPopoverWindow frame rel main=(57,100,186x106) main=300x232 key=false level=0
//     NSPopover behavior=1 animates=true shown=true contentSize=(186.0, 106.0)
//     P4a outside click on Under while shown -> shown=true log ["under"] windows NSWindow,NSWindow,NSWindow,NSWindow,NSWindow,NSWindow,NSWindow,NSWindow,NSWindow,NSWindow,NSWindow,NSWindow,NSWindow,_NSPopoverWindow
//     P4b same click again -> shown=true log ["under", "under"]
//     P4c popover key, outside click on Under -> shown=true log ["under"]
//   === P1 popover arrowEdge .leading
//     P0 control (not shown): windows NSWindow,NSWindow,NSWindow,NSWindow,NSWindow,NSWindow,NSWindow,NSWindow,NSWindow,NSWindow,NSWindow,NSWindow,NSWindow
//     popover window _NSPopoverWindow frame rel main=(-69,35,186x106) main=300x232 key=false level=0
//     NSPopover behavior=1 animates=true shown=true contentSize=(186.0, 106.0)
//   === P1 popover arrowEdge .trailing
//     P0 control (not shown): windows NSWindow,NSWindow,NSWindow,NSWindow,NSWindow,NSWindow,NSWindow,NSWindow,NSWindow,NSWindow,NSWindow,NSWindow,NSWindow
//     popover window _NSPopoverWindow frame rel main=(184,35,186x106) main=300x232 key=false level=0
//     NSPopover behavior=1 animates=true shown=true contentSize=(186.0, 106.0)
//   === P5 arrowEdge .bottom, window at the screen's bottom
//     popover rel main=(57,100,186x106) screen.minY rel main=-5
//   === P7 popover with the default arrowEdge
//     popover rel main=(57,112,186x106)
//   === P6 popover(item:)
//     item set -> popover windows 1
//   --- H: help
//   === H0 control: Text(T)
//     NSHostingView role=AXGroup sub=AXHostingView label=nil value=nil [showMenu] kids=1
//       AccessibilityNode role=AXStaticText sub=nil label=nil value=T [showMenu] kids=0
//   === H1 Text(T).help(Tip)
//     NSHostingView role=AXGroup sub=AXHostingView label=nil value=nil [showMenu] kids=1
//       AccessibilityNode role=AXStaticText sub=nil label=nil value=T help=Tip [showMenu] kids=0
//   === H2 Button(B).help(Tip)
//     NSHostingView role=AXGroup sub=AXHostingView label=nil value=nil [showMenu] kids=1
//       AccessibilityNode role=AXButton sub=nil label=B value=nil help=Tip [showMenu] kids=0
//   === H3 Button(B).help(Tip).accessibilityHint(Hint)
//     NSHostingView role=AXGroup sub=AXHostingView label=nil value=nil [showMenu] kids=1
//       AccessibilityNode role=AXButton sub=nil label=B value=nil help=Hint [showMenu] kids=0
//   === H3b Button(B).accessibilityHint(Hint).help(Tip)
//     NSHostingView role=AXGroup sub=AXHostingView label=nil value=nil [showMenu] kids=1
//       AccessibilityNode role=AXButton sub=nil label=B value=nil help=Tip [showMenu] kids=0
//   === H4 VStack{Text A; Text B}.help(Tip)
//     NSHostingView role=AXGroup sub=AXHostingView label=nil value=nil [showMenu] kids=2
//       AccessibilityNode role=AXStaticText sub=nil label=nil value=A help=Tip [showMenu] kids=0
//       AccessibilityNode role=AXStaticText sub=nil label=nil value=B help=Tip [showMenu] kids=0
//   === H5 Text(T).help(Inner) inside VStack.help(Outer)
//     NSHostingView role=AXGroup sub=AXHostingView label=nil value=nil [showMenu] kids=2
//       AccessibilityNode role=AXStaticText sub=nil label=nil value=T help=Outer [showMenu] kids=0
//       AccessibilityNode role=AXStaticText sub=nil label=nil value=U help=Outer [showMenu] kids=0
//     H6 NSView.toolTip under H1's hosting view: []
//     H7 tooltip window after a synthesized mouseMoved: none
//     M1 Menu pull-down AX:
//     NSHostingView role=AXGroup sub=AXHostingView label=nil value=nil [showMenu] kids=1
//       AccessibilityNode role=AXMenuButton sub=nil label=nil value=nil [showMenu] kids=0
//     C1 AX (contextMenu target):
//     NSHostingView role=AXGroup sub=AXHostingView label=nil value=nil [showMenu] kids=1
//       AccessibilityNode role=AXStaticText sub=nil label=nil value=Target [showMenu] kids=0
//   --- end
//   exit 0

import AppKit
import SwiftUI

setvbuf(stdout, nil, _IOLBF, 0)
@MainActor func spin(_ s: Double = 0.3) { RunLoop.main.run(until: Date().addingTimeInterval(s)) }
func str(_ v: Any?) -> String { v.map { "\($0)" } ?? "nil" }
func kv(_ o: NSObject, _ key: String) -> Any? {
    let isKey = "is" + key.prefix(1).uppercased() + key.dropFirst()
    guard o.responds(to: Selector(key)) || o.responds(to: Selector(isKey)) else { return nil }
    return o.value(forKey: key)
}
@MainActor func kids(_ o: NSObject) -> [NSObject] { ((kv(o, "accessibilityChildren") as? [Any]) ?? []).compactMap { $0 as? NSObject } }
@MainActor func line(_ o: NSObject) -> String {
    var s = "\(type(of: o))".components(separatedBy: "<").first!
    s += " role=\(str(kv(o, "accessibilityRole"))) sub=\(str(kv(o, "accessibilitySubrole")))"
    s += " label=\(str(kv(o, "accessibilityLabel"))) value=\(str(kv(o, "accessibilityValue")))"
    if let help = kv(o, "accessibilityHelp") as? String, !help.isEmpty { s += " help=\(help)" }
    if let t = kv(o, "accessibilityTitle") as? String, !t.isEmpty { s += " title=\(t)" }
    if (kv(o, "accessibilityModal") as? Bool) == true { s += " modal" }
    let names = ((kv(o, "accessibilityCustomActions") as? [NSAccessibilityCustomAction]) ?? []).map(\.name)
    if !names.isEmpty { s += " custom=\(names)" }
    if o.responds(to: Selector(("accessibilityPerformShowMenu"))) { s += " [showMenu]" }
    s += " kids=\(kids(o).count)"
    return s
}
@MainActor func describe(_ o: NSObject, _ d: Int = 0, maxDepth: Int = 5, maxKids: Int = 6) {
    print("  " + String(repeating: "  ", count: d) + line(o))
    if d < maxDepth { for k in kids(o).prefix(maxKids) { describe(k, d + 1, maxDepth: maxDepth, maxKids: maxKids) } }
}
@MainActor func find(_ o: NSObject, where p: (NSObject) -> Bool) -> NSObject? {
    if p(o) { return o }
    for k in kids(o) { if let f = find(k, where: p) { return f } }
    return nil
}
final class Log: @unchecked Sendable { var lines: [String] = [] }
let log = Log()

var windows: [NSWindow] = []
@MainActor func host<V: View>(_ name: String, _ v: V, size: CGSize = CGSize(width: 300, height: 200),
                              origin: CGPoint = CGPoint(x: 300, y: 400)) -> NSHostingView<V> {
    let w = NSWindow(contentRect: NSRect(origin: origin, size: size),
                     styleMask: [.titled], backing: .buffered, defer: false)
    w.isReleasedWhenClosed = false
    let h = NSHostingView(rootView: v)
    w.contentView = h
    w.orderFrontRegardless(); w.makeKey(); h.layoutSubtreeIfNeeded(); spin(0.4)
    print("=== \(name)"); windows.append(w)
    return h
}
@MainActor func mouse(_ type: NSEvent.EventType, _ w: NSWindow, _ p: CGPoint, _ flags: NSEvent.ModifierFlags = []) -> NSEvent {
    NSEvent.mouseEvent(with: type, location: p, modifierFlags: flags, timestamp: ProcessInfo.processInfo.systemUptime,
                       windowNumber: w.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
}
@MainActor func key(_ w: NSWindow, _ chars: String, _ flags: NSEvent.ModifierFlags = [], code: UInt16 = 0) -> NSEvent {
    NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: ProcessInfo.processInfo.systemUptime,
                     windowNumber: w.windowNumber, context: nil, characters: chars, charactersIgnoringModifiers: chars,
                     isARepeat: false, keyCode: code)!
}
@MainActor func dumpMenu(_ m: NSMenu, _ d: Int = 1) {
    for item in m.items {
        var s = String(repeating: "  ", count: d)
        if item.isSeparatorItem { print(s + "----"); continue }
        s += "\"\(item.title)\""
        if !item.isEnabled { s += " disabled" }
        if item.state == .on { s += " state=on" } else if item.state == .mixed { s += " state=mixed" }
        if !item.keyEquivalent.isEmpty {
            s += " key=\(item.keyEquivalent.debugDescription) mods=\(item.keyEquivalentModifierMask.rawValue >> 16)"
        }
        if item.isHidden { s += " hidden" }
        if let a = item.action { s += " action=\(a)" }
        if item.image != nil { s += " image" }
        if item.attributedTitle != nil { s += " attributed" }
        if item.submenu != nil { s += " submenu:" }
        print(s)
        if let sub = item.submenu { dumpMenu(sub, d + 1) }
    }
}
@MainActor func contextMenu<V: View>(_ h: NSHostingView<V>, at p: CGPoint? = nil) -> NSMenu? {
    let w = h.window!
    let pt = p ?? CGPoint(x: h.bounds.midX, y: h.bounds.midY)
    let e = mouse(.rightMouseDown, w, pt)
    let hit = h.hitTest(h.convert(pt, from: nil)) ?? h
    return hit.menu(for: e)
}
@MainActor func windowsLine() -> String {
    NSApp.windows.filter(\.isVisible).map { "\(type(of: $0))" }.joined(separator: ",")
}

final class Model: ObservableObject {
    @Published var shown = false
    @Published var flag = true
    @Published var pick = 1
    @Published var item: Tag? = nil
}
struct Tag: Identifiable { let id: Int }

struct ContextHost: View {
    @ObservedObject var m: Model
    var body: some View {
        Text("Target").frame(width: 200, height: 100).background(Color.gray)
            .contextMenu {
                Button("Copy") { log.lines.append("copy") }
                Button("Delete", role: .destructive) { log.lines.append("delete") }
                Divider()
                Menu("More") {
                    Button("Sub A") { log.lines.append("subA") }
                    Button("Sub B") { log.lines.append("subB") }
                }
                Toggle("Flag", isOn: $m.flag)
                Picker("Pick", selection: $m.pick) { Text("One").tag(1); Text("Two").tag(2) }
                Button("Off") {}.disabled(true)
                Button("Short") { log.lines.append("short") }.keyboardShortcut("k")
                Button { } label: { Label("Labelled", systemImage: "star") }
                Section("Header") { Button("In section") {} }
                Text("Plain text item")
            }
    }
}

struct PopHost: View {
    @ObservedObject var m: Model
    let edge: Edge
    var body: some View {
        VStack {
            Button("Under") { log.lines.append("under") }
            Spacer()
            Button("Anchor") { m.shown = true }
                .popover(isPresented: $m.shown, arrowEdge: edge) {
                    VStack { Text("Popover body"); Button("Inside") { log.lines.append("inside") } }
                        .padding().frame(width: 160, height: 80)
                }
            Spacer()
        }.frame(width: 300, height: 200)
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.regular)
MainActor.assumeIsolated {
    // ------------------------------------------------------------ C
    print("--- C: contextMenu")
    let c0 = host("C0 control: Text without contextMenu", Text("Target").frame(width: 200, height: 100))
    print("  menu: \(str(contextMenu(c0)))")

    let m = Model()
    let c1 = host("C1 contextMenu { Copy, Delete(destructive), Divider, Menu More, Toggle, Picker, disabled, ⌘K, Label, Section, Text }", ContextHost(m: m))
    if let menu = contextMenu(c1) {
        print("  menu class=\(type(of: menu)) items=\(menu.items.count) autoenables=\(menu.autoenablesItems)")
        dumpMenu(menu)
        // C2: run an item; C3: a submenu item; C4: the toggle.
        if let i = menu.items.firstIndex(where: { $0.title == "Copy" }) {
            menu.performActionForItem(at: i); spin(0.1)
            print("  C2 perform Copy -> log \(log.lines)")
        }
        if let sub = menu.items.first(where: { $0.title == "More" })?.submenu,
           let i = sub.items.firstIndex(where: { $0.title == "Sub B" }) {
            sub.performActionForItem(at: i); spin(0.1)
            print("  C3 perform More>Sub B -> log \(log.lines)")
        }
        if let i = menu.items.firstIndex(where: { $0.title == "Flag" }) {
            menu.performActionForItem(at: i); spin(0.2)
            print("  C4 perform Flag -> flag=\(m.flag)")
        }
        if let pick = menu.items.first(where: { $0.title == "Pick" })?.submenu,
           let i = pick.items.firstIndex(where: { $0.title == "Two" }) {
            pick.performActionForItem(at: i); spin(0.2)
            print("  C4b perform Pick>Two -> pick=\(m.pick)")
        }
        // C4c: is the menu rebuilt per open (new state shown)?
        if let again = contextMenu(c1) {
            let flag = again.items.first(where: { $0.title == "Flag" })
            print("  C4c reopened: same object=\(again === menu) Flag state=\(flag.map { $0.state == .on ? "on" : "off" } ?? "nil")")
        }
    } else { print("  menu: nil") }

    // C12: a context-menu item's shortcut while the menu is closed.
    log.lines = []
    let k12 = key(c1.window!, "k", .command, code: 40)
    let w12 = c1.window!.performKeyEquivalent(with: k12); spin(0.2)
    print("  C12 closed menu, window.performKeyEquivalent(⌘K) -> \(w12) log \(log.lines)")
    NSApp.sendEvent(k12); spin(0.2)
    print("  C12b NSApp.sendEvent(⌘K) -> log \(log.lines)")

    // C5: real events through NSApp.sendEvent; which open the menu?
    var began: [String] = []
    let obs = NotificationCenter.default.addObserver(forName: NSMenu.didBeginTrackingNotification, object: nil, queue: nil) { n in
        let menu = n.object as? NSMenu
        began.append("\(menu.map { "\($0.items.count) items" } ?? "nil")")
        // End the modal tracking loop at once.
        RunLoop.main.perform(inModes: [.eventTracking, .common, .modalPanel]) { menu?.cancelTrackingWithoutAnimation() }
    }
    let w1 = c1.window!
    let mid = CGPoint(x: c1.bounds.midX, y: c1.bounds.midY)
    for (name, down, up, flags) in [("C5r right mouse down/up", NSEvent.EventType.rightMouseDown, NSEvent.EventType.rightMouseUp, NSEvent.ModifierFlags()),
                                    ("C5c control-left mouse down/up", .leftMouseDown, .leftMouseUp, .control),
                                    ("C5l control: plain left mouse down/up", .leftMouseDown, .leftMouseUp, [])] {
        began = []
        let t = Timer(timeInterval: 0.5, repeats: false) { _ in NSApp.sendEvent(mouse(up, w1, mid, flags)) }
        RunLoop.main.add(t, forMode: .eventTracking)
        NSApp.sendEvent(mouse(down, w1, mid, flags)); spin(0.3)
        t.invalidate()
        print("  \(name): menu tracking began \(began)")
    }
    // C5n: separating arm for C5c — a plain AppKit NSView with `menu` set,
    // control-left-clicked the same way. If this opens nothing either, the
    // synthesized control-click cannot see AppKit's control-click rule.
    final class MenuView: NSView {}
    let mv = MenuView(frame: NSRect(x: 0, y: 0, width: 200, height: 100))
    mv.menu = NSMenu(); mv.menu!.addItem(withTitle: "Native", action: nil, keyEquivalent: "")
    let mw = NSWindow(contentRect: NSRect(x: 300, y: 400, width: 200, height: 100), styleMask: [.titled], backing: .buffered, defer: false)
    mw.isReleasedWhenClosed = false; mw.contentView = mv; mw.orderFrontRegardless(); mw.makeKey(); spin(0.3); windows.append(mw)
    for (name, down, up, flags) in [("C5n NSView.menu right mouse down/up", NSEvent.EventType.rightMouseDown, NSEvent.EventType.rightMouseUp, NSEvent.ModifierFlags()),
                                    ("C5n NSView.menu control-left mouse down/up", .leftMouseDown, .leftMouseUp, .control)] {
        began = []
        let t = Timer(timeInterval: 0.5, repeats: false) { _ in NSApp.sendEvent(mouse(up, mw, CGPoint(x: 100, y: 50), flags)) }
        RunLoop.main.add(t, forMode: .eventTracking)
        NSApp.sendEvent(mouse(down, mw, CGPoint(x: 100, y: 50), flags)); spin(0.3)
        t.invalidate()
        print("  \(name): menu tracking began \(began)")
    }
    mw.orderOut(nil)

    // C11: VoiceOver's show-menu action on the contextMenu target.
    NSApp.accessibilitySetValue(true, forAttribute: NSAccessibility.Attribute(rawValue: "AXEnhancedUserInterface"))
    spin(0.3)
    began = []
    if let node = find(c1, where: { str(kv($0, "accessibilityRole")) == "AXStaticText" }) {
        let actions = (node.responds(to: Selector(("accessibilityActionNames"))) ? (node.value(forKey: "accessibilityActionNames") as? [Any]) : nil) ?? []
        print("  C11 target actionNames=\(actions)")
        typealias Fn = @convention(c) (AnyObject, Selector) -> Bool
        let ok = unsafeBitCast(node.method(for: Selector(("accessibilityPerformShowMenu"))), to: Fn.self)(node, Selector(("accessibilityPerformShowMenu")))
        spin(0.4)
        print("  C11 accessibilityPerformShowMenu -> \(ok), menu tracking began \(began)")
    }
    if let node = find(c0, where: { str(kv($0, "accessibilityRole")) == "AXStaticText" }) {
        let actions = (node.responds(to: Selector(("accessibilityActionNames"))) ? (node.value(forKey: "accessibilityActionNames") as? [Any]) : nil) ?? []
        print("  C11c control (no contextMenu) actionNames=\(actions)")
    }
    NotificationCenter.default.removeObserver(obs)

    // C6: a Button with no contextMenu — does a right click activate it?
    log.lines = []
    let c6 = host("C6 Button(B) right-click", Button("B") { log.lines.append("B") }.frame(width: 200, height: 100))
    let w6 = c6.window!; let p6 = CGPoint(x: c6.bounds.midX, y: c6.bounds.midY)
    NSApp.sendEvent(mouse(.rightMouseDown, w6, p6)); NSApp.sendEvent(mouse(.rightMouseUp, w6, p6)); spin(0.2)
    print("  right click -> log \(log.lines)")
    NSApp.sendEvent(mouse(.leftMouseDown, w6, p6)); NSApp.sendEvent(mouse(.leftMouseUp, w6, p6)); spin(0.2)
    print("  C6b plain left click -> log \(log.lines)")
    // C6n: the AppKit control — an NSButton right-clicked.
    final class Hits: NSObject { var n = 0; @objc func hit() { n += 1 } }
    let hits = Hits()
    let nb = NSButton(title: "N", target: hits, action: #selector(Hits.hit))
    nb.frame = NSRect(x: 0, y: 0, width: 200, height: 100)
    let nbw = NSWindow(contentRect: NSRect(x: 300, y: 400, width: 200, height: 100), styleMask: [.titled], backing: .buffered, defer: false)
    nbw.isReleasedWhenClosed = false; nbw.contentView = nb; nbw.orderFrontRegardless(); spin(0.3); windows.append(nbw)
    NSApp.sendEvent(mouse(.rightMouseDown, nbw, CGPoint(x: 100, y: 50))); NSApp.sendEvent(mouse(.rightMouseUp, nbw, CGPoint(x: 100, y: 50))); spin(0.2)
    print("  C6n NSButton right click -> \(hits.n) actions")
    nbw.orderOut(nil)
    // C6t: onTapGesture right-clicked.
    log.lines = []
    let c6t = host("C6t Text.onTapGesture right-click", Text("T").frame(width: 200, height: 100).contentShape(Rectangle()).onTapGesture { log.lines.append("tap") })
    NSApp.sendEvent(mouse(.rightMouseDown, c6t.window!, CGPoint(x: 100, y: 50))); NSApp.sendEvent(mouse(.rightMouseUp, c6t.window!, CGPoint(x: 100, y: 50))); spin(0.2)
    print("  right click -> log \(log.lines)")

    // C7: a contextMenu on a Button — the menu, and does a left click still press?
    log.lines = []
    let c7 = host("C7 Button(B).contextMenu { X }", Button("B") { log.lines.append("B") }.contextMenu { Button("X") { log.lines.append("X") } })
    print("  menu: \(contextMenu(c7).map { "\($0.items.map(\.title))" } ?? "nil")")
    do {
        var b7: [String] = []
        let o7 = NotificationCenter.default.addObserver(forName: NSMenu.didBeginTrackingNotification, object: nil, queue: nil) { n in
            let menu = n.object as? NSMenu; b7.append("\(menu?.items.count ?? -1) items")
            RunLoop.main.perform(inModes: [.eventTracking, .common]) { menu?.cancelTrackingWithoutAnimation() }
        }
        let w7 = c7.window!; let p7 = CGPoint(x: c7.bounds.midX, y: c7.bounds.midY)
        let t = Timer(timeInterval: 0.5, repeats: false) { _ in NSApp.sendEvent(mouse(.rightMouseUp, w7, p7)) }
        RunLoop.main.add(t, forMode: .eventTracking)
        NSApp.sendEvent(mouse(.rightMouseDown, w7, p7)); spin(0.3); t.invalidate()
        print("  C7b right mouse down -> menu \(b7), log \(log.lines)")
        NSApp.sendEvent(mouse(.rightMouseUp, w7, p7)); spin(0.3)
        print("  C7b' right mouse up (default mode) -> menu \(b7), log \(log.lines)")
        NSApp.sendEvent(mouse(.leftMouseDown, w7, p7)); NSApp.sendEvent(mouse(.leftMouseUp, w7, p7)); spin(0.2)
        print("  C7c left click -> menu \(b7), log \(log.lines)")
        NotificationCenter.default.removeObserver(o7)
    }

    // C8: nested contextMenus — which one wins at the inner view?
    let c8 = host("C8 VStack { Text(inner).contextMenu{Inner} }.contextMenu{Outer}",
                  VStack { Text("inner").frame(width: 100, height: 50).contextMenu { Button("Inner") {} } ; Text("outer-only").frame(width: 100, height: 50) }
                      .frame(width: 300, height: 200).contextMenu { Button("Outer") {} })
    let innerPt = CGPoint(x: c8.bounds.midX, y: c8.bounds.midY + 25)
    let outerPt = CGPoint(x: c8.bounds.midX, y: c8.bounds.midY - 25)
    print("  at inner: \(contextMenu(c8, at: innerPt).map { "\($0.items.map(\.title))" } ?? "nil")")
    print("  at outer-only text: \(contextMenu(c8, at: outerPt).map { "\($0.items.map(\.title))" } ?? "nil")")

    // C9: a disabled view with a contextMenu.
    let c9 = host("C9 Text.contextMenu{X}.disabled(true)", Text("T").frame(width: 200, height: 100).contextMenu { Button("X") {} }.disabled(true))
    print("  menu: \(contextMenu(c9).map { "\($0.items.map { "\($0.title) enabled=\($0.isEnabled)" })" } ?? "nil")")

    // C10: an empty contextMenu.
    let c10 = host("C10 Text.contextMenu {} (empty)", Text("T").frame(width: 200, height: 100).contextMenu { })
    print("  menu: \(contextMenu(c10).map { "\($0.items.count) items" } ?? "nil")")

    // Critic round (2026-10-02): C11n, C13c, C13, C14 — appended so every line
    // above is unchanged. Each right press is a real NSApp.sendEvent (C5r's
    // instrument, which opens a menu headless) and reads menu tracking.
    @MainActor func rightPressTracking(_ h: NSView, at p: CGPoint) -> [String] {
        var got: [String] = []
        let o = NotificationCenter.default.addObserver(forName: NSMenu.didBeginTrackingNotification, object: nil, queue: nil) { n in
            let menu = n.object as? NSMenu
            got.append("\(menu?.items.map(\.title) ?? [])")
            RunLoop.main.perform(inModes: [.eventTracking, .common, .modalPanel]) { menu?.cancelTrackingWithoutAnimation() }
        }
        let w = h.window!
        let t = Timer(timeInterval: 0.5, repeats: false) { _ in NSApp.sendEvent(mouse(.rightMouseUp, w, p)) }
        RunLoop.main.add(t, forMode: .eventTracking)
        NSApp.sendEvent(mouse(.rightMouseDown, w, p)); spin(0.3); t.invalidate()
        NSApp.sendEvent(mouse(.rightMouseUp, w, p)); spin(0.1)
        NotificationCenter.default.removeObserver(o)
        return got
    }
    // C11n: accessibilityPerformShowMenu on a node with NO contextMenu (C0's
    // text) — the separating arm for C11 (every node responds to the selector,
    // so `[showMenu]` in the dumps is not evidence of an advertised action).
    do {
        var bn: [String] = []
        let on = NotificationCenter.default.addObserver(forName: NSMenu.didBeginTrackingNotification, object: nil, queue: nil) { n in
            let menu = n.object as? NSMenu; bn.append("\(menu?.items.count ?? -1) items")
            RunLoop.main.perform(inModes: [.eventTracking, .common, .modalPanel]) { menu?.cancelTrackingWithoutAnimation() }
        }
        if let node = find(c0, where: { str(kv($0, "accessibilityRole")) == "AXStaticText" }) {
            typealias Fn = @convention(c) (AnyObject, Selector) -> Bool
            let ok = unsafeBitCast(node.method(for: Selector(("accessibilityPerformShowMenu"))), to: Fn.self)(node, Selector(("accessibilityPerformShowMenu")))
            spin(0.4)
            print("  C11n control (no contextMenu) accessibilityPerformShowMenu -> \(ok), menu tracking began \(bn)")
        } else { print("  C11n control node not found") }
        NotificationCenter.default.removeObserver(on)
    }
    // C13c (positive control) / C13: a contextMenu view, then the same with
    // .allowsHitTesting(false) — does a right press still open its menu?
    let c13c = host("C13c Text.contextMenu{X} right press (control)", Text("T").frame(width: 200, height: 100).background(Color.gray).contextMenu { Button("X") {} })
    print("  menu tracking began \(rightPressTracking(c13c, at: CGPoint(x: 100, y: 50)))")
    let c13 = host("C13 Text.contextMenu{X}.allowsHitTesting(false) right press", Text("T").frame(width: 200, height: 100).background(Color.gray).contextMenu { Button("X") {} }.allowsHitTesting(false))
    print("  menu tracking began \(rightPressTracking(c13, at: CGPoint(x: 100, y: 50)))")
    // C14: a contextMenu view covered by an opaque sibling with no menu
    // (ZStack, same window) — does the cover block the menu beneath?
    let c14 = host("C14 ZStack { Text.contextMenu{Beneath}; Color.blue cover } right press",
                   ZStack { Text("T").frame(width: 200, height: 100).background(Color.gray).contextMenu { Button("Beneath") {} }
                            Color.blue.frame(width: 200, height: 100) })
    print("  menu tracking began \(rightPressTracking(c14, at: CGPoint(x: 100, y: 50)))")

    // M: Menu("Title") { } as a pull-down button.
    let m1 = host("M1 Menu(Title) { A; Divider; B }", Menu("Title") { Button("A") { log.lines.append("mA") }; Divider(); Button("B") {} }.frame(width: 150))

    // ------------------------------------------------------------ P
    print("--- P: popover")
    for edge in [Edge.bottom, .top, .leading, .trailing] {
        let pm = Model()
        let ph = host("P1 popover arrowEdge .\(edge)", PopHost(m: pm, edge: edge), origin: CGPoint(x: 300, y: 500))
        print("  P0 control (not shown): windows \(windowsLine())")
        pm.shown = true; spin(0.8)
        let pw = NSApp.windows.first { "\(type(of: $0))".contains("Popover") && $0.isVisible }
        let mainFrame = ph.window!.frame
        if let pw {
            let anchor = ph.window!.convertToScreen(NSRect(x: 0, y: 0, width: 0, height: 0))
            _ = anchor
            let f = pw.frame
            print("  popover window \(type(of: pw)) frame rel main=(\(Int(f.minX - mainFrame.minX)),\(Int(f.minY - mainFrame.minY)),\(Int(f.width))x\(Int(f.height))) main=\(Int(mainFrame.width))x\(Int(mainFrame.height)) key=\(pw.isKeyWindow) level=\(pw.level.rawValue)")
            if let pop = pw.value(forKey: "_popover") as? NSPopover {
                print("  NSPopover behavior=\(pop.behavior.rawValue) animates=\(pop.animates) shown=\(pop.isShown) contentSize=\(pop.contentSize)")
            }
            if edge == .bottom {
                NSApp.accessibilitySetValue(true, forAttribute: NSAccessibility.Attribute(rawValue: "AXEnhancedUserInterface"))
                spin(0.3)
                print("  P2 popover window AX:")
                describe(pw, maxDepth: 6)
                print("  P2b main window AX while shown:")
                describe(ph.window!, maxDepth: 2)
            }
        } else { print("  popover window: none; windows \(windowsLine())") }
        // P3: Escape sent to the popover window (or key window).
        if edge == .bottom, let pw {
            NSApp.sendEvent(key(pw, "\u{1b}", code: 53)); spin(0.6)
            print("  P3 Escape -> shown=\(pm.shown) windows \(windowsLine())")
            pw.makeKey(); spin(0.2)
            print("  P3b popover window made key: key=\(pw.isKeyWindow) keyWindow=\(str(NSApp.keyWindow.map { type(of: $0) }))")
            NSApp.sendEvent(key(pw, "\u{1b}", code: 53)); spin(0.6)
            print("  P3b Escape -> shown=\(pm.shown) windows \(windowsLine())")
        }
        // P4: outside click on Under while shown.
        if edge == .top {
            log.lines = []
            let w = ph.window!
            // "Under" is at the top of the VStack: find it through AX frame? use top 20pt.
            let pt = CGPoint(x: 150, y: 200 - 12)
            NSApp.sendEvent(mouse(.leftMouseDown, w, pt)); NSApp.sendEvent(mouse(.leftMouseUp, w, pt)); spin(0.6)
            print("  P4a outside click on Under while shown -> shown=\(pm.shown) log \(log.lines) windows \(windowsLine())")
            NSApp.sendEvent(mouse(.leftMouseDown, w, pt)); NSApp.sendEvent(mouse(.leftMouseUp, w, pt)); spin(0.4)
            print("  P4b same click again -> shown=\(pm.shown) log \(log.lines)")
            if let pw = NSApp.windows.first(where: { "\(type(of: $0))".contains("Popover") && $0.isVisible }) {
                log.lines = []
                pw.makeKey(); spin(0.2)
                NSApp.sendEvent(mouse(.leftMouseDown, w, pt)); NSApp.sendEvent(mouse(.leftMouseUp, w, pt)); spin(0.6)
                print("  P4c popover key, outside click on Under -> shown=\(pm.shown) log \(log.lines)")
            }
        }
        pm.shown = false; spin(0.6)
        ph.window!.orderOut(nil)
    }
    // P5: anchor at the window's bottom edge, arrowEdge .bottom, window near the screen's bottom — does it flip?
    let screen = NSScreen.main!.visibleFrame
    let pm5 = Model()
    let ph5 = host("P5 arrowEdge .bottom, window at the screen's bottom", PopHost(m: pm5, edge: .bottom),
                   origin: CGPoint(x: 300, y: screen.minY + 5))
    pm5.shown = true; spin(0.8)
    if let pw = NSApp.windows.first(where: { "\(type(of: $0))".contains("Popover") && $0.isVisible }) {
        let f = pw.frame, mf = ph5.window!.frame
        print("  popover rel main=(\(Int(f.minX - mf.minX)),\(Int(f.minY - mf.minY)),\(Int(f.width))x\(Int(f.height))) screen.minY rel main=\(Int(screen.minY - mf.minY))")
    } else { print("  popover window: none") }
    pm5.shown = false; spin(0.5); ph5.window!.orderOut(nil)

    // P7: no arrowEdge argument (the default).
    struct DefaultEdgeHost: View {
        @ObservedObject var m: Model
        var body: some View {
            VStack { Spacer(); Button("Anchor") {}.popover(isPresented: $m.shown) { Text("Default edge").padding().frame(width: 160, height: 80) }; Spacer() }
                .frame(width: 300, height: 200)
        }
    }
    let pm7 = Model()
    let ph7 = host("P7 popover with the default arrowEdge", DefaultEdgeHost(m: pm7), origin: CGPoint(x: 300, y: 500))
    pm7.shown = true; spin(0.8)
    if let pw = NSApp.windows.first(where: { "\(type(of: $0))".contains("Popover") && $0.isVisible }) {
        let f = pw.frame, mf = ph7.window!.frame
        print("  popover rel main=(\(Int(f.minX - mf.minX)),\(Int(f.minY - mf.minY)),\(Int(f.width))x\(Int(f.height)))")
    } else { print("  popover window: none") }
    pm7.shown = false; spin(0.5); ph7.window!.orderOut(nil)

    // P6: item: variant.
    let pm6 = Model()
    struct ItemHost: View {
        @ObservedObject var m: Model
        var body: some View {
            Text("A").frame(width: 200, height: 100).popover(item: $m.item) { t in Text("item \(t.id)").padding() }
        }
    }
    let ph6 = host("P6 popover(item:)", ItemHost(m: pm6))
    pm6.item = Tag(id: 7); spin(0.8)
    print("  item set -> popover windows \(NSApp.windows.filter { "\(type(of: $0))".contains("Popover") && $0.isVisible }.count)")
    pm6.item = nil; spin(0.5); ph6.window!.orderOut(nil)

    // ------------------------------------------------------------ H
    print("--- H: help")
    NSApp.accessibilitySetValue(true, forAttribute: NSAccessibility.Attribute(rawValue: "AXEnhancedUserInterface"))
    spin(0.3)
    let h0 = host("H0 control: Text(T)", Text("T").frame(width: 200, height: 100)); describe(h0)
    let h1 = host("H1 Text(T).help(Tip)", Text("T").frame(width: 200, height: 100).help("Tip")); describe(h1)
    let h2 = host("H2 Button(B).help(Tip)", Button("B") {}.help("Tip")); describe(h2)
    let h3 = host("H3 Button(B).help(Tip).accessibilityHint(Hint)", Button("B") {}.help("Tip").accessibilityHint("Hint")); describe(h3)
    let h3b = host("H3b Button(B).accessibilityHint(Hint).help(Tip)", Button("B") {}.accessibilityHint("Hint").help("Tip")); describe(h3b)
    let h4 = host("H4 VStack{Text A; Text B}.help(Tip)", VStack { Text("A"); Text("B") }.help("Tip")); describe(h4)
    let h5 = host("H5 Text(T).help(Inner) inside VStack.help(Outer)", VStack { Text("T").help("Inner"); Text("U") }.help("Outer")); describe(h5)
    func tooltips(_ v: NSView, _ out: inout [String]) {
        if let t = v.toolTip { out.append("\(type(of: v)):\(t)") }
        for s in v.subviews { tooltips(s, &out) }
    }
    var tips: [String] = []; tooltips(h1, &tips)
    print("  H6 NSView.toolTip under H1's hosting view: \(tips)")
    // H7: a mouse-moved over H1, then sample for a tooltip window.
    let w = h1.window!
    NSApp.sendEvent(mouse(.mouseMoved, w, CGPoint(x: 100, y: 50)));
    var seen = "none"
    for i in 1...12 {
        spin(0.25)
        let names = NSApp.windows.filter(\.isVisible).map { "\(type(of: $0))" }.filter { $0.localizedCaseInsensitiveContains("tip") }
        if !names.isEmpty { seen = "\(names) at ~\(Double(i) * 0.25)s"; break }
    }
    print("  H7 tooltip window after a synthesized mouseMoved: \(seen)")
    print("  M1 Menu pull-down AX:")
    describe(m1, maxDepth: 4)
    print("  C1 AX (contextMenu target):")
    describe(c1, maxDepth: 3)
    print("--- end")
}
exit(0)
