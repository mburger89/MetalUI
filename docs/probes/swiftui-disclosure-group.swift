// SwiftUI probe: a standalone `DisclosureGroup` in a `VStack` (design docs/superpowers/specs/2026-11-15-outline-disclosure-design.md,
// section 7; the companion of docs/probes/swiftui-outline.swift, which covers the same view inside a `List`).
//
// Evidence for rulings OG-A and OG-J in docs/superpowers/2026-11-15-outline-disclosure-decisions.md (the eager-context look and
// the title forms).
//
// HOW TO RUN (ruling SA-O's two forms; an argument restricts the run to D1, D3 or A3; about 15 seconds, run it in the foreground):
//
//   /usr/bin/swift docs/probes/swiftui-disclosure-group.swift
//   xcrun swiftc docs/probes/swiftui-disclosure-group.swift -o /tmp/dg-probe && /tmp/dg-probe
//
// THE INSTRUMENT. The group sits in a `VStack(alignment: .leading, spacing: 0)` between two `Text`s ("above" and "below"), inside a
// 300 wide ordered-in window with 20 pt of padding (so the stack is 260 wide). Every view reports its frame with
// `onGeometryChange(for: CGRect.self) { $0.frame(in: .named("stack")) }` (the stack's space); the chevron and label ink boxes are
// read from a 2x `cacheDisplay` snapshot (alpha above 0.35) and are in WINDOW space (the stack starts at 20, 20). Animation is the
// series of "below" frames the geometry callback reports through the animation (to 0.5 pt).
//
// ARMS. D1 geometry (label row, chevron, content indent and spacing, nesting); D2 the title forms (`String`, `LocalizedStringKey`,
// `Text`-title literal, and a `Label` label closure), each collapsed and expanded through `isExpanded: $binding`; D3 the animation
// of a bare binding write, of `withAnimation`, and of a click; D4 the initial state of an uncontrolled group and of `.constant(true)`;
// A3 the accessibility tree.
//
// POSITIVE CONTROLS / SEPARATING ARMS. D3a (a bare write: one geometry report, the "below" text jumps 40 -> 72) is the control that
// D3b (the same write under `withAnimation(.easeInOut(duration: 0.5))`: 33 distinct positions over 503 ms) is animated at all.
// D1's four title forms against each other separate "the title form changes the geometry" (it does not) from the `Label` form (its
// label ink starts 1.5 pt later because of the icon).
//
// RECORDED 2026-11-15 by the outline-probes lane, macOS 27.2.1 (26B131), Apple Swift 6.4.2 (swift-6.4.2-RELEASE), arm64, screen
// UNLOCKED (lock probe: no CGSSessionScreenIsLocked key, kCGSSessionOnConsoleKey 1, IOConsoleLocked No). Script form and compiled
// form printed the same lines up to the millisecond figures. stderr carried nothing. Output (compiled form):
//
//   --- D1 / D2: geometry of a standalone DisclosureGroup (VStack in a 300 wide window, 20 pt padding; frames in the stack's space, ink boxes in window space)
//     title collapsed (isExpanded: bound): group=(0,16 260x24) above=(0,0 37x16) below=(0,40 36x16) content1=- content2=-
//         chevron ink (the first 11 pt of the label line) (22,44 5x8) colour #C0C0C0 a=0.94; label ink (32.5,43 25.5x10) colour #000000 a=0.83
//     title expanded (isExpanded: bound): group=(0,16 260x56) above=(0,0 37x16) below=(0,72 36x16) content1=(92.5,40 75x16) content2=(93,56 74x16)
//         chevron ink (the first 11 pt of the label line) (20,47 8x5) colour #BFBFBF a=0.93; label ink (32.5,43 25.5x10) colour #000000 a=0.83
//         content leading edge minus label ink leading edge: 80; content1.minY - group.minY = 24; content2.minY - content1.maxY = 0
//     key collapsed (isExpanded: bound): group=(0,16 260x24) above=(0,0 37x16) below=(0,40 36x16) content1=- content2=-
//         chevron ink (the first 11 pt of the label line) (22,44 5x8) colour #C0C0C0 a=0.94; label ink (32.5,43 25.5x10) colour #000000 a=0.83
//     key expanded (isExpanded: bound): group=(0,16 260x56) above=(0,0 37x16) below=(0,72 36x16) content1=(92.5,40 75x16) content2=(93,56 74x16)
//         chevron ink (the first 11 pt of the label line) (20,47 8x5) colour #BFBFBF a=0.93; label ink (32.5,43 25.5x10) colour #000000 a=0.83
//         content leading edge minus label ink leading edge: 80; content1.minY - group.minY = 24; content2.minY - content1.maxY = 0
//     string collapsed (isExpanded: bound): group=(0,16 260x24) above=(0,0 37x16) below=(0,40 36x16) content1=- content2=-
//         chevron ink (the first 11 pt of the label line) (22,44 5x8) colour #C0C0C0 a=0.94; label ink (32.5,43 25.5x10) colour #000000 a=0.83
//     string expanded (isExpanded: bound): group=(0,16 260x56) above=(0,0 37x16) below=(0,72 36x16) content1=(92.5,40 75x16) content2=(93,56 74x16)
//         chevron ink (the first 11 pt of the label line) (20,47 8x5) colour #BFBFBF a=0.93; label ink (32.5,43 25.5x10) colour #000000 a=0.83
//         content leading edge minus label ink leading edge: 80; content1.minY - group.minY = 24; content2.minY - content1.maxY = 0
//     label collapsed (isExpanded: bound): group=(0,16 260x24) above=(0,0 37x16) below=(0,40 36x16) content1=- content2=-
//         chevron ink (the first 11 pt of the label line) (22,44 5x8) colour #C0C0C0 a=0.94; label ink (34,42 51x12) colour #000000 a=0.85
//     label expanded (isExpanded: bound): group=(0,16 260x56) above=(0,0 37x16) below=(0,72 36x16) content1=(92.5,40 75x16) content2=(93,56 74x16)
//         chevron ink (the first 11 pt of the label line) (20,47 8x5) colour #BFBFBF a=0.93; label ink (34,42 51x12) colour #000000 a=0.85
//         content leading edge minus label ink leading edge: 78.5; content1.minY - group.minY = 24; content2.minY - content1.maxY = 0
//     nested (both constant true): group=(0,16 260x64) inner=(0,40 260x40) leaf=(116.5,64 27x16) below=(0,80 36x16); indentation outer->inner = 0, inner->leaf = 116.5
//     light chevron ink box (expanded): (20,46 8x6) colour #BFBFBF a=0.93
//     dark chevron ink box (expanded): (20,46 8x6) colour #FFFFFF a=0.93
//     light chevron ink box (collapsed): (22,44 5.5x9) colour #C0C0C0 a=0.94
//   --- D3 / D4: initial state, and the animation of a click, of a bare binding write, and of withAnimation
//     D4a uncontrolled DisclosureGroup, no isExpanded: content1 frame = - (nil = not built / collapsed), group = (0,16 260x24) below = (0,40 36x16)
//     D4b isExpanded: .constant(true): content1 = (92.5,40 75x16) below = (0,72 36x16)
//     D3a bare binding write (box.open = true): below.y 40 -> 72; distinct y (to 0.5 pt): 1 72  first at 3 ms, last at 3 ms
//     D3b withAnimation(.easeInOut(duration: 0.5)) { box.open = true }: below.y 40 -> 72; distinct y (to 0.5 pt): 33 56 56.5 57 57.5 58 58.5 59 59.5 60 60.5 61 61.5 ...  first at 4 ms, last at 507 ms
//     D3c click on the label line (NSEvent through NSApp), bound: below.y 40 -> 40; distinct y (to 0.5 pt): 0   first at -, last at -
//   --- P-A3: AX tree of a standalone DisclosureGroup, read in-process through the legacy NSAccessibility attribute API
//     (an AXUIElement client of this process, from a child process, answered only with application-role elements in this environment, so only the in-process view is measured)
//     --- AXEnhancedUserInterface/AXManualAccessibility set: false
//     collapsed (isExpanded: bound):
//       NSHostingView<Fixture> Role=AXUnknown RoleDescription=group Help=- actions=[]
//     expanded:
//       NSHostingView<Fixture> Role=AXUnknown RoleDescription=group Help=- actions=[]
//       NSHostingView<Fixture> Role=AXUnknown RoleDescription=group Help=- actions=[]
//     elements with AXPress: 0
//     --- AXEnhancedUserInterface/AXManualAccessibility set: true
//     collapsed (isExpanded: bound):
//       NSHostingView<Fixture> Role=AXUnknown RoleDescription=group Help=- actions=[]
//     expanded:
//       NSHostingView<Fixture> Role=AXUnknown RoleDescription=group Help=- actions=[]
//       NSHostingView<Fixture> Role=AXUnknown RoleDescription=group Help=- actions=[]
//     elements with AXPress: 0
//
// READ:
//   D1 A collapsed group is 260 x 24 (the label row, 24 tall); expanded, it is 24 + the content (two 16 pt Texts, 0 spacing between
//     them, the first directly under the label row at +24): 260 x 56. The chevron is at the LEADING edge, left of the label: collapsed
//     it points right (ink 5 x 8 at x 22, 2 pt in), expanded it points down (ink 8 x 5 at x 20); light chevron #C0C0C0 / #BFBFBF at
//     alpha 0.93, against label ink #000000 at alpha 0.83, so a lighter grey than the label; dark #FFFFFF (the sampled ink, not
//     checked against the drawn colour). The label ink starts 12.5 pt from the group's leading edge (32.5 in window space),
//     34 for a `Label` with an icon. There is NO indentation: the content of a bare DisclosureGroup is a centre-aligned stack in
//     the group's width (a 75 wide Text at x 92.5 = (260 - 75) / 2, a 27 wide Leaf at 116.5 = (260 - 27) / 2), and a nested group
//     starts at x 0 like its parent (outer to inner indentation 0). The inside-a-List indent is the outline's, not the view's.
//   D2 The `String`, `LocalizedStringKey` and literal title forms print identical frames and ink; the `Label` form differs only by
//     the icon's 1.5 pt.
//   D3 A bare binding write snaps (below 40 -> 72 in one report). Under `withAnimation(.easeInOut(duration: 0.5))` the group
//     animates, honouring the duration: 33 distinct positions (to 0.5 pt) from 56 to 72 over 503 ms (the first report is already
//     16 pt along, as the content's first line appears at once). This is SwiftUI's own animation, unlike the List's row slide, whose
//     ~245 ms AppKit curve ignores `withAnimation` (swiftui-outline.swift, P-N). D3c, the default click animation, is NOT MEASURED: a
//     synthetic mouse event (through the NSApp queue, or `NSHostingView.mouseDown` and `mouseUp` directly) does not reach SwiftUI's
//     gesture, so the click does nothing (below stays 40) and no animation could be sampled.
//   D4 An uncontrolled DisclosureGroup is COLLAPSED initially (no content frame; 260 x 24); `isExpanded: .constant(true)` is expanded
//     at once (260 x 56).
//   P-A3 NOT MEASURED. The in-process tree of the hosting view is one AXUnknown "group" element with no children, collapsed or
//     expanded, with or without AXEnhancedUserInterface / AXManualAccessibility set (SwiftUI builds its elements for a live AX
//     client); no element has AXPress, AXExpanded or AXDisclosing. An AXUIElement client of this process, run from a child process of
//     the same binary, answered only with application-role elements (the window and its children all read AXApplication), so the tree
//     could not be read in this environment. Nothing about a standalone DisclosureGroup's role, value, label or press is known from
//     this lane; the outline's own elements are in swiftui-outline.swift, P-A.
import SwiftUI
import AppKit


final class Cell<T>: @unchecked Sendable { var v: T?; init(_ v: T? = nil) { self.v = v } }

@MainActor var turn = 0
@MainActor var t0 = Date()
@MainActor var logLines: [String] = []
@MainActor func log(_ s: String) { logLines.append(String(format: "  [turn %d +%3dms] ", turn, Int(Date().timeIntervalSince(t0) * 1000)) + s) }
@MainActor func flushLog() { for l in logLines { print(l) }; logLines = [] }

@MainActor var frames: [String: CGRect] = [:]
@MainActor var series: [(Int, CGRect)] = []
@MainActor var seriesKey = ""

struct Rep: ViewModifier {
    let key: String
    func body(content: Content) -> some View {
        content.onGeometryChange(for: CGRect.self, of: { $0.frame(in: .named("stack")) }) { r in
            frames[key] = r
            if key == seriesKey { series.append((Int(Date().timeIntervalSince(t0) * 1000), r)) }
        }
    }
}
extension View { func rep(_ k: String) -> some View { modifier(Rep(key: k)) } }

@MainActor final class Box: ObservableObject { @Published var open = false }

struct Fixture: View {
    let kind: String
    let bound: Bool
    @ObservedObject var box: Box
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("above").rep("above")
            Group {
                switch kind {
                case "title":
                    if bound { DisclosureGroup("Title", isExpanded: $box.open) { cont } } else { DisclosureGroup("Title") { cont } }
                case "key":
                    if bound { DisclosureGroup(LocalizedStringKey("Title"), isExpanded: $box.open) { cont } } else { DisclosureGroup(LocalizedStringKey("Title")) { cont } }
                case "string":
                    if bound { DisclosureGroup(String("Title"), isExpanded: $box.open) { cont } } else { DisclosureGroup(String("Title")) { cont } }
                case "label":
                    if bound { DisclosureGroup(isExpanded: $box.open) { cont } label: { Label("Title", systemImage: "folder") } }
                    else { DisclosureGroup { cont } label: { Label("Title", systemImage: "folder") } }
                case "constantTrue":
                    DisclosureGroup("Title", isExpanded: .constant(true)) { cont }
                case "nested":
                    DisclosureGroup("Outer", isExpanded: .constant(true)) {
                        DisclosureGroup("Inner", isExpanded: .constant(true)) { Text("Leaf").rep("c1") }.rep("inner")
                    }
                default: EmptyView()
                }
            }.rep("group")
            Text("below").rep("below")
        }
        .coordinateSpace(name: "stack")
        .padding(20)
        .frame(width: 300, alignment: .topLeading)
    }
    @ViewBuilder var cont: some View { Text("Content one").rep("c1"); Text("Content two").rep("c2") }
}

final class KeyWin: NSWindow {
    override var canBecomeKey: Bool { true }
    override var isKeyWindow: Bool { true }
}
@MainActor var openWindows: [NSWindow] = []
@MainActor func closeAll() { for w in openWindows { w.orderOut(nil); w.close() }; openWindows = [] }
@MainActor func spin(_ n: Int = 8, _ dt: Double = 0.02) { for _ in 0..<n { RunLoop.main.run(until: Date(timeIntervalSinceNow: dt)) } }
func find<T: NSView>(_ type: T.Type, in v: NSView) -> T? {
    if let t = v as? T { return t }
    for c in v.subviews { if let f = find(type, in: c) { return f } }
    return nil
}

@MainActor func make(_ kind: String, bound: Bool = false, open: Bool = false, dark: Bool = false) -> (KeyWin, NSHostingView<Fixture>, Box) {
    frames = [:]
    let box = Box(); box.open = open
    let h = NSHostingView(rootView: Fixture(kind: kind, bound: bound, box: box))
    let w = KeyWin(contentRect: CGRect(x: 100, y: 100, width: 300, height: 300), styleMask: [.borderless], backing: .buffered, defer: false)
    w.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
    w.contentView = h
    w.makeKeyAndOrderFront(nil)
    openWindows.append(w)
    spin(); h.layoutSubtreeIfNeeded(); spin()
    return (w, h, box)
}

func f(_ x: CGFloat) -> String { String(format: "%g", Double((x * 100).rounded() / 100)) }
func fr(_ r: CGRect?) -> String { guard let r = r else { return "-" }; return "(\(f(r.minX)),\(f(r.minY)) \(f(r.width))x\(f(r.height)))" }

@MainActor func snapshot(_ v: NSView) -> NSBitmapImageRep {
    let r = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(v.bounds.width * 2), pixelsHigh: Int(v.bounds.height * 2), bitsPerSample: 8,
                             samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    r.size = v.bounds.size
    v.cacheDisplay(in: v.bounds, to: r)
    return r
}

/// Bounding box (points, view coordinates) of the pixels with alpha above `tol` inside `r`, and the colour of the most opaque one
/// (the snapshot has a transparent background, so ink is alpha).
@MainActor func inkBox(_ rep: NSBitmapImageRep, _ r: CGRect, tol: CGFloat = 0.35) -> (CGRect, String) {
    var minX = Int.max, maxX = -1, minY = Int.max, maxY = -1
    var best: NSColor? = nil; var ba: CGFloat = 0
    for y in Int(r.minY * 2)..<Int(r.maxY * 2) { for x in Int(r.minX * 2)..<Int(r.maxX * 2) {
        guard let c = rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { continue }
        if c.alphaComponent > tol { minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y) }
        if c.alphaComponent > ba { ba = c.alphaComponent; best = c }
    } }
    func hx(_ c: NSColor?) -> String { guard let c = c else { return "-" }; return String(format: "#%02X%02X%02X a=%.2f", Int(c.redComponent * 255 + 0.5), Int(c.greenComponent * 255 + 0.5), Int(c.blueComponent * 255 + 0.5), Double(c.alphaComponent)) }
    if maxX < 0 { return (.zero, "-") }
    return (CGRect(x: CGFloat(minX) / 2, y: CGFloat(minY) / 2, width: CGFloat(maxX - minX + 1) / 2, height: CGFloat(maxY - minY + 1) / 2), hx(best))
}

// MARK: arms

@MainActor func armD1() {
    print("--- D1 / D2: geometry of a standalone DisclosureGroup (VStack in a 300 wide window, 20 pt padding; frames in the stack's space, ink boxes in window space)")
    for kind in ["title", "key", "string", "label"] {
        for open in [false, true] {
            let (_, h, _) = make(kind, bound: true, open: open)
            let rep = snapshot(h)
            let g = frames["group"]
            print("  \(kind) \(open ? "expanded" : "collapsed") (isExpanded: bound): group=\(fr(g)) above=\(fr(frames["above"])) below=\(fr(frames["below"])) content1=\(fr(frames["c1"])) content2=\(fr(frames["c2"]))")
            if let g = g {
                let (cb, col) = inkBox(rep, CGRect(x: 20 + g.minX, y: 20 + g.minY, width: 11, height: 24))
                let lab = inkBox(rep, CGRect(x: 20 + g.minX + 11, y: 20 + g.minY, width: 200, height: 24))
                print("      chevron ink (the first 11 pt of the label line) \(fr(cb)) colour \(col); label ink \(fr(lab.0)) colour \(lab.1)")
                if open, let c1 = frames["c1"] { print("      content leading edge minus label ink leading edge: \(f(c1.minX + 20 - lab.0.minX)); content1.minY - group.minY = \(f(c1.minY - g.minY)); content2.minY - content1.maxY = \(f((frames["c2"]?.minY ?? 0) - c1.maxY))") }
            }
            closeAll()
        }
    }
    let (_, hn, _) = make("nested")
    print("  nested (both constant true): group=\(fr(frames["group"])) inner=\(fr(frames["inner"])) leaf=\(fr(frames["c1"])) below=\(fr(frames["below"])); indentation outer->inner = \(f((frames["inner"]?.minX ?? 0) - (frames["group"]?.minX ?? 0))), inner->leaf = \(f((frames["c1"]?.minX ?? 0) - (frames["inner"]?.minX ?? 0)))")
    _ = hn; closeAll()
    for dark in [false, true] {
        let (_, h, _) = make("constantTrue", dark: dark)
        let rep = snapshot(h)
        if let g = frames["group"] { let (cb, col) = inkBox(rep, CGRect(x: 20 + g.minX, y: 20 + g.minY, width: 11, height: 24), tol: 0.1); print("  \(dark ? "dark" : "light") chevron ink box (expanded): \(fr(cb)) colour \(col)") }
        closeAll()
    }
    let (_, hc, bc) = make("title", bound: true, open: false)
    let repc = snapshot(hc)
    if let g = frames["group"] { let (cb, col) = inkBox(repc, CGRect(x: 20 + g.minX, y: 20 + g.minY, width: 11, height: 24), tol: 0.1); print("  light chevron ink box (collapsed): \(fr(cb)) colour \(col)") }
    _ = bc; closeAll()
}

@MainActor func armD3() {
    print("--- D3 / D4: initial state, and the animation of a click, of a bare binding write, and of withAnimation")
    // D4
    let (_, h4, _) = make("title")
    print("  D4a uncontrolled DisclosureGroup, no isExpanded: content1 frame = \(fr(frames["c1"])) (nil = not built / collapsed), group = \(fr(frames["group"])) below = \(fr(frames["below"]))")
    _ = h4; closeAll()
    let (_, h4b, _) = make("constantTrue")
    print("  D4b isExpanded: .constant(true): content1 = \(fr(frames["c1"])) below = \(fr(frames["below"]))")
    _ = h4b; closeAll()

    func run(_ title: String, kind: String, bound: Bool, _ act: (KeyWin, NSHostingView<Fixture>, Box) -> Void) {
        let (w, h, b) = make(kind, bound: bound)
        series = []; seriesKey = "below"
        t0 = Date()
        let before = frames["below"]
        act(w, h, b)
        spin(90, 0.01)
        let after = frames["below"]
        let ys = series.map { ($0.1.minY * 2).rounded() / 2 }
        var u: [CGFloat] = []; for y in ys where u.last != y { u.append(y) }
        let tFirst = series.first?.0, tLast = series.last?.0
        print("  \(title): below.y \(before.map { f($0.minY) } ?? "-") -> \(after.map { f($0.minY) } ?? "-"); distinct y (to 0.5 pt): \(u.count) \(u.prefix(12).map { f($0) }.joined(separator: " "))\(u.count > 12 ? " ..." : "")  first at \(tFirst.map { "\($0) ms" } ?? "-"), last at \(tLast.map { "\($0) ms" } ?? "-")")
        closeAll()
    }
    run("D3a bare binding write (box.open = true)", kind: "title", bound: true) { _, _, b in b.open = true }
    run("D3b withAnimation(.easeInOut(duration: 0.5)) { box.open = true }", kind: "title", bound: true) { _, _, b in withAnimation(.easeInOut(duration: 0.5)) { b.open = true } }
    // click on the chevron/label: through the event queue, then through AX press
    run("D3c click on the label line (NSEvent through NSApp), bound", kind: "title", bound: true) { w, h, _ in
        guard let g = frames["group"] else { return }
        let p = CGPoint(x: 20 + g.minX + 8, y: 20 + g.minY + 8)
        let wp = CGPoint(x: p.x, y: h.bounds.height - p.y)
        func ev(_ t: NSEvent.EventType) -> NSEvent { NSEvent.mouseEvent(with: t, location: wp, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: w.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: t == .leftMouseUp ? 0 : 1)! }
        NSApp.postEvent(ev(.leftMouseDown), atStart: false); NSApp.postEvent(ev(.leftMouseUp), atStart: false)
        while let e = NSApp.nextEvent(matching: .any, until: Date(timeIntervalSinceNow: 0.02), inMode: .default, dequeue: true) { NSApp.sendEvent(e) }
        if frames["below"]?.minY == 40 {   // the queue path did nothing: hand the event to the hosting view itself
            h.mouseDown(with: ev(.leftMouseDown)); h.mouseUp(with: ev(.leftMouseUp))
            spin(2)
        }
    }
}

func axv(_ o: NSObject, _ a: String) -> String {
    guard let x = o.accessibilityAttributeValue(NSAccessibility.Attribute(rawValue: a)) else { return "-" }
    if let arr = x as? NSArray { return "[\(arr.count)]" }
    return "\(x)"
}
func axKids(_ o: NSObject) -> [NSObject] { ((o.accessibilityAttributeValue(.children) as? NSArray) ?? []).compactMap { $0 as? NSObject } }
@MainActor func walk(_ o: NSObject, _ d: Int) {
    let names = (o.accessibilityAttributeNames() ?? []).map { $0.rawValue }
    let interesting = ["AXRole", "AXSubrole", "AXRoleDescription", "AXTitle", "AXLabel", "AXValue", "AXDescription", "AXExpanded", "AXDisclosing", "AXDisclosureLevel", "AXHelp"].filter { names.contains($0) }
    let attrs = interesting.map { "\($0.dropFirst(2))=\(axv(o, $0))" }.joined(separator: " ")
    let acts = o.accessibilityActionNames().map { $0.rawValue }
    print(String(repeating: "  ", count: d + 2) + "\(type(of: o)) \(attrs) actions=\(acts)")
    for k in axKids(o) { walk(k, d + 1) }
}

@MainActor func walk(_ o: NSObject, _ d: Int, _ found: inout [NSObject]) {
    let names = (o.accessibilityAttributeNames() ?? []).map { $0.rawValue }
    let want = ["AXRole", "AXSubrole", "AXRoleDescription", "AXTitle", "AXLabel", "AXDescription", "AXValue", "AXExpanded", "AXDisclosing", "AXDisclosureLevel", "AXHelp"].filter { names.contains($0) }
    let attrs = want.map { "\($0.dropFirst(2))=\(axv(o, $0))" }.joined(separator: " ")
    let acts = o.accessibilityActionNames().map { $0.rawValue }
    print(String(repeating: "  ", count: d + 2) + "\(type(of: o)) \(attrs) actions=\(acts)")
    if o.accessibilityActionNames().contains(.press) { found.append(o) }
    for k in axKids(o) { walk(k, d + 1, &found) }
}

@MainActor func armA3() {
    print("--- P-A3: AX tree of a standalone DisclosureGroup, read in-process through the legacy NSAccessibility attribute API")
    print("  (an AXUIElement client of this process, from a child process, answered only with application-role elements in this environment, so only the in-process view is measured)")
    for enh in [false, true] {
        if enh {
            NSApp.accessibilitySetValue(true as NSNumber, forAttribute: NSAccessibility.Attribute(rawValue: "AXEnhancedUserInterface"))
            NSApp.accessibilitySetValue(true as NSNumber, forAttribute: NSAccessibility.Attribute(rawValue: "AXManualAccessibility"))
            spin(5)
        }
        print("  --- AXEnhancedUserInterface/AXManualAccessibility set: \(enh)")
        let (_, h, box) = make("title", bound: true)
        spin(10)
        var found: [NSObject] = []
        print("  collapsed (isExpanded: bound):"); walk(h, 0, &found)
        box.open = true; spin(10)
        found = []
        print("  expanded:"); walk(h, 0, &found)
        box.open = false; spin(10)
        found = []
        walk(h, 0, &found)
        print("  elements with AXPress: \(found.count)")
        if let p = found.first {
            p.accessibilityPerformAction(.press); spin(15)
            print("  AXPress on the first: box.open = \(box.open), group = \(fr(frames["group"]))")
        }
        closeAll()
    }
}

@MainActor func resetOpenLog() { t0 = Date() }

struct Probe {
    @MainActor static func main() {
        setvbuf(stdout, nil, _IOLBF, 0)
        // no App Nap: with offscreen windows a background run is throttled to a crawl otherwise
        let activity = ProcessInfo.processInfo.beginActivity(options: [.userInitiated, .latencyCritical], reason: "probe")
        _ = activity
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        app.activate()
        let want = Set(CommandLine.arguments.dropFirst())
        func on(_ k: String) -> Bool { want.isEmpty || want.contains(k) }
        if on("D1") { armD1() }
        if on("D3") { armD3() }
        if on("A3") { armA3() }
        flushLog()
        exit(0)
    }
}

MainActor.assumeIsolated { Probe.main() }
