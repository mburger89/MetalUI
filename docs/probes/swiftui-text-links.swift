// SwiftUI probe: clickable text links (round 4 item R4-4 PR D, divergence 150, rulings `LI-` in
// docs/superpowers/2026-11-04-text-links-decisions.md). What a `Text` link run does under a click: which
// events open it, how it ranks against the gestures around it, what `\.openURL` sees, and what the
// accessibility tree publishes for it.
//
// HOW TO RUN (SA-O's compiled form; no JIT shim; no computer use, the screen may be locked):
//
//   xcrun swiftc -swift-version 6 docs/probes/swiftui-text-links.swift -o /tmp/li-probe
//   /tmp/li-probe > /tmp/li-1.txt; /tmp/li-probe > /tmp/li-2.txt; cmp /tmp/li-1.txt /tmp/li-2.txt
//
// INSTRUMENT. `swiftui-focus-click.swift`'s: a `FirstMouseHost` (an `NSHostingView`) in a `KeyWindow`, laid out
// and shown before the first event, `NSEvent`s through `NSWindow.sendEvent` with a run-loop spin between them.
// The window is 200 x 200, the origin at the BOTTOM left. Every arm logs its own action (`open <url>`, `tap`),
// so a reading proves the control was hit (that probe's trap T2: a small root view is not centred, so each
// subject is expanded with a top-leading frame). **The link's point is read from the accessibility tree**
// (the `AXLink` child's frame, screen to window), not guessed; an arm that cannot find one logs `no-link`.
// Accessibility is switched on for the process with `AXEnhancedUserInterface` / `AXManualAccessibility` on the
// application (without it the hosting view publishes no children). Every `OpenURLAction` here is custom and
// returns `.handled`: **no arm ever returns `.systemAction`, so no browser opens** (the system path is
// therefore not measured, nor is what `.discarded` does after the handler ran).
//
// ARM IDS. The plan's arms were never committed; its ids are kept for the same questions and the arm bodies
// are rebuilt from the plan's table (`LK0`..`LK23`, `O0`..`O9`). Where the plan gave an id only in a list, the
// body here is the closest reading of its sentence, stated at the arm.
//
// NOT MEASURED. The cursor over a link (a synthetic `mouseMoved` does not change `NSCursor.current`);
// `.systemAction` / `.discarded` falling back to the system; the pressed look; VoiceOver; Full Keyboard Access
// Tab into a link; a real browser (human group `LI`).
//
// RECORDED 2026-11-04, macOS 27.2, Apple Swift 6.4.2 (swiftlang-6.4.2.1.9), screen LOCKED
// (CGSSessionScreenIsLocked = 1; the events go into the probe's own window through `NSWindow.sendEvent`).
// Compiled form, run three times: stdout byte-identical (44 lines, shasum b9e0ebd4a13e4e86f1bc72fcd5890bbc74fc1d91), exit 0,
// stderr empty. `LI_PROBE_PRESS=1` additionally calls the link element's `accessibilityPerformPress` and TERMINATES the
// process (see the reading); the recorded run does not set it.
//
//   --- LK: which events open a run
//     LK0 Text(AttributedString markdown link), click on the run: open https://x.org
//     LK1 same, click OFF the run (left of it): -
//     LK3 two links, click the second: open https://b.org
//     LK16 AttributedString with .link set in code: open https://code.org
//     LK_lit Text("[x](url)") literal, LocalizedStringKey markdown: open https://lit.org
//     LK4 press on the run, release OFF the run: -
//     LK5 press OFF the run, release ON the run: -
//     LK6 right press on the run: -
//     LK7 .disabled(true): open https://x.org
//     LK8 .allowsHitTesting(false): -
//     LK19 double click on the run (count 1 then 2): open https://x.org,open https://x.org
//     O9 one drag event 25 pt inside a wide run, release inside it: open https://x.org
//     O9b the same drag as five 5 pt events: open https://x.org
//     O9d CONTROL: the same synthetic drag reaches a DragGesture (so the drag events are delivered): drag0,drag5,drag10,drag15,drag20,drag25,end
//     O9c a 3 pt drag (one event): open https://x.org
//   --- LK12: a run wrapped over two lines (the text 60 pt wide)
//     LK12 map: one click per 4 pt along each line of the text ('X' opened, '.' did not); rows top to bottom: axLinks=1 frame=(0.0, 166.0, 59.0, 34.0),row0=.....XXXXXXXXXX.,row1=XXXX............
//   --- action: which OpenURLAction runs, and with what
//     LK15 inner action beats outer: inner https://x.org
//     LK14 handler returns .discarded: the handler ran (system fallback not observable here): ran https://x.org
//     LK14b nested: inner .discarded, does the OUTER action also run?: inner
//     LK21 custom scheme probe://x reaches the action: open probe://x
//     LK20 a scheme-less destination (example.com): open example.com
//   --- LK23: a click on a link and a focused field (a real @FocusState)
//     LK23 field focused on appear, click the link: focused=true,|start,open https://x.org
//     LK23b control: the same window, click the second focusable (focus must move): focused=true,|start,focused=false,other=true
//   --- O: ranking against the gestures around it
//     O0a Text.onTapGesture, click the run: open https://x.org
//     O0b Text.onTapGesture, click off the run: tap
//     O1a Button { Text(link) }, click the run: open https://x.org
//     O1b same, click off the run: tap
//     O2a ancestor onTapGesture, click the run: open https://x.org
//     O2b same, click off the run: tap
//     O3 link in a disabled Button: open https://x.org
//     O5 an overlay tap ABOVE the text: tap
//     O6 simultaneousGesture(TapGesture) on the Text, click the run: tap,open https://x.org
//     O6b highPriorityGesture(TapGesture) on the Text, click the run: tap
//     LK13 .textSelection(.enabled), click the run (NSHostingView: read as measured, see header): -
//     LK17 Link("docs", destination:) view (carried; not built by this PR): open https://x.org
//   --- AX: what the tree publishes
//     AX1 tree of `two [aa] and [bb]`: AXStaticText label=nil value=two aa and bb w=91.0,>AXLink label=aa value=nil w=15.0,>AXLink label=bb value=nil w=17.0
//     AX2 the link element: selectors it answers, AXURL, actions: accessibilityURL=true,accessibilityActionNames=false,accessibilityAttributeNames=true,accessibilityPerformPress=true,accessibilityPerformAction:=false,accessibilityHelp=true,accessibilityIdentifier=true,accessibilityLinkedUIElements=true,accessibilityParent=true,accessibilityTitle=true,accessibilitySubrole=true,accessibilityCustomActions=true,accessibilityURL value=nil,attributeNames=[__C.NSAccessibilityAttributeName(_rawValue: AXRole), __C.NSAccessibilityAttributeName(_rawValue: AXRoleDescription), __C.NSAccessibilityAttributeName(_rawValue: AXParent), __C.NSAccessibilityAttributeName(_rawValue: AXWindow), __C.NSAccessibilityAttributeName(_rawValue: AXTopLevelUIElement)],AXURL (old API)=nil,customActions=nil,parentRole=AXStaticText
//     AX3 press path: accessibilityPerformPress on the link element: responds-performPress=true
//
// READING (against the plan's table; the arm bodies were rebuilt, so each difference is a difference of reading).
//   Opens on mouse-up, on the run only: LK0, LK16 (code-set `.link`), `Text("[x](url)")` literal, LK3 (the second of
//   two), LK17 (`Link` view; carried, not built here). A click off the run does not (LK1). Not: press on and release
//   off (LK4), press off and release on (LK5), a right press (LK6), `.allowsHitTesting(false)` (LK8).
//   A WRAPPED run opens only over its own pieces: line 1 from the run's start to the line's end, line 2 up to the
//   run's end, and not over "ee" after it (LK12 map). The AX tree has ONE link element for it (frame (0, 166, 59, 34),
//   the union of both pieces, so it also covers the "aa " before the run on line 1).
//   `.disabled(true)` STILL OPENS (LK7, and a disabled `Button`'s label, O3). A double click opens twice (LK19).
//   Gestures: the link beats a tap on the `Text` (O0a), on an ancestor (O2a) and a `Button` label (O1a); off the run
//   those fire (O0b, O1b, O2b). An overlay tap ABOVE the text wins and the link does not open (O5);
//   `simultaneousGesture` fires both, the tap first (O6); `highPriorityGesture` fires the tap only (O6b).
//   Action: the nearest `\.openURL` runs (LK15); `.discarded` ran the handler (LK14) and an OUTER action did not run
//   after it (LK14b). A custom scheme (LK21) and a scheme-less destination (LK20) both reach the action as written.
//   A click on a link does not move a focused field (LK23), with the control reading that a click on a second
//   focusable does (LK23b).
//   DIFFERS FROM THE PLAN: O9. The plan read "a 25 pt drag inside the run does not open"; here a drag inside the run
//   OPENS, as a 3 pt drag does (O9, O9b as five events, O9c), and the control reads that the same synthetic drag
//   reaches a `DragGesture` (O9d), so the drag events are delivered and the plan's reading is not reproduced.
//   MetalUI opens on a drag inside the run too, so there is NO drag residue for row 218.
//   AX: the `Text` stays `AXStaticText` with its whole string as the value and no label; each link is an `AXLink`
//   child with a label (`aa`, `bb`) and its own frame (AX1). The link element publishes five attributes (role, role
//   description, parent, window, top-level element), NO `AXURL` (AX2: `accessibilityURL` answers nil, the old-API
//   `AXURL` nil), no actions (`accessibilityActionNames` is not implemented) and no custom actions. Its press path is
//   not reachable in-process: `accessibilityPerformPress` is answered by AppKit's default and raises
//   NSInvalidArgumentException (`accessibilityPerformAction:` unrecognised) under `LI_PROBE_PRESS=1`. What VoiceOver does
//   with a link is NOT measured (human group LI). The bridge therefore needs no `AXURL` field.
//   UNRESOLVED, as in the plan: `.textSelection(.enabled)` did not open in the instrument (LK13); the cursor over a
//   link (a synthetic `mouseMoved` does not change `NSCursor.current`); what `.systemAction` and `.discarded` do
//   AFTER the handler ran (the probe never opens a browser).

import SwiftUI
import AppKit

final class FirstMouseHost<V: View>: NSHostingView<V> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

final class KeyWindow: NSWindow {
    override var isKeyWindow: Bool { true }
    override var canBecomeKey: Bool { true }
}

enum Log {
    nonisolated(unsafe) static var lines: [String] = []
    static func add(_ s: String) { lines.append(s) }
    static func take() -> String {
        defer { lines = [] }
        return lines.isEmpty ? "-" : lines.joined(separator: ",")
    }
}

@MainActor func spin(_ s: Double = 0.15) { RunLoop.main.run(until: Date().addingTimeInterval(s)) }

/// The action every arm installs: logs the URL and swallows it (never `.systemAction`).
let logging = OpenURLAction { url in Log.add("open \(url.absoluteString)"); return .handled }

@MainActor func makeWindow<V: View>(_ view: V, size: CGFloat = 200) -> NSWindow {
    let w = KeyWindow(contentRect: CGRect(x: 200, y: 200, width: size, height: size),
                      styleMask: [.titled], backing: .buffered, defer: false)
    w.isReleasedWhenClosed = false
    let host = FirstMouseHost(rootView: view.environment(\.openURL, logging))
    w.contentView = host
    host.layoutSubtreeIfNeeded()
    w.makeKeyAndOrderFront(nil)
    spin(0.3)
    return w
}

@MainActor func mouse(_ w: NSWindow, _ t: NSEvent.EventType, _ p: CGPoint, count: Int = 1) {
    let pressure: Float = (t == .leftMouseUp || t == .rightMouseUp) ? 0 : 1
    let e = NSEvent.mouseEvent(with: t, location: p, modifierFlags: [],
                               timestamp: ProcessInfo.processInfo.systemUptime,
                               windowNumber: w.windowNumber, context: nil, eventNumber: 0,
                               clickCount: count, pressure: pressure)!
    w.sendEvent(e)
}

@MainActor func click(_ w: NSWindow, at p: CGPoint) {
    mouse(w, .leftMouseDown, p); spin(0.05); mouse(w, .leftMouseUp, p); spin()
}

@MainActor func doubleClick(_ w: NSWindow, at p: CGPoint) {
    mouse(w, .leftMouseDown, p, count: 1); spin(0.02); mouse(w, .leftMouseUp, p, count: 1); spin(0.02)
    mouse(w, .leftMouseDown, p, count: 2); spin(0.02); mouse(w, .leftMouseUp, p, count: 2); spin()
}

@MainActor func rightClick(_ w: NSWindow, at p: CGPoint) {
    mouse(w, .rightMouseDown, p); spin(0.05); mouse(w, .rightMouseUp, p); spin()
}

@MainActor func press(_ w: NSWindow, _ down: CGPoint, release up: CGPoint) {
    mouse(w, .leftMouseDown, down); spin(0.05)
    if down != up { mouse(w, .leftMouseDragged, up); spin(0.05) }
    mouse(w, .leftMouseUp, up); spin()
}

// MARK: - Accessibility reading (the new-style protocol methods, through the runtime)

@MainActor func kv(_ o: NSObject, _ k: String) -> String {
    guard o.responds(to: Selector(k)) else { return "(no \(k))" }
    return String(describing: o.value(forKey: k) ?? "nil")
}

@MainActor func axChildren(_ o: NSObject) -> [NSObject] {
    guard o.responds(to: Selector("accessibilityChildren")) else { return [] }
    return ((o.value(forKey: "accessibilityChildren") as? [Any]) ?? []).compactMap { $0 as? NSObject }
}

@MainActor func axLinks(_ w: NSWindow) -> [NSObject] {
    @MainActor func walk(_ o: NSObject) -> [NSObject] {
        var found: [NSObject] = []
        if kv(o, "accessibilityRole") == "AXLink" { found.append(o) }
        for c in axChildren(o) { found += walk(c) }
        return found
    }
    return walk(w.contentView!)
}

@MainActor func axFrame(_ o: NSObject) -> CGRect {
    (o.value(forKey: "accessibilityFrame") as? NSValue)?.rectValue ?? .zero
}

/// Window-coordinate rect of an accessibility frame (screen coordinates in).
@MainActor func windowRect(_ w: NSWindow, _ screen: CGRect) -> CGRect { w.convertFromScreen(screen) }

/// The centre of the `index`th `AXLink`, in window coordinates, or `nil`.
@MainActor func linkPoint(_ w: NSWindow, _ index: Int = 0, dx: CGFloat = 0, dy: CGFloat = 0) -> CGPoint? {
    let links = axLinks(w)
    guard index < links.count else { return nil }
    let r = windowRect(w, axFrame(links[index]))
    return CGPoint(x: r.midX + dx, y: r.midY + dy)
}

/// A point on the text's line but OFF every link: left of the first link's frame.
@MainActor func offPoint(_ w: NSWindow) -> CGPoint? {
    guard let first = axLinks(w).first else { return nil }
    let r = windowRect(w, axFrame(first))
    return CGPoint(x: Swift.max(r.minX - 12, 1), y: r.midY)
}

@MainActor func arm<V: View>(_ label: String, _ view: V, size: CGFloat = 200, _ act: @MainActor (NSWindow) -> Void) {
    _ = Log.take()
    let w = makeWindow(view, size: size)
    act(w)
    print("  \(label): \(Log.take())")
    w.orderOut(nil)
    w.contentView = nil
}

/// Clicks the link at `index` (`no-link` when the tree has none) and then, if given, `then`.
@MainActor func clickLink(_ w: NSWindow, _ index: Int = 0) {
    guard let p = linkPoint(w, index) else { Log.add("no-link"); return }
    click(w, at: p)
}

func md(_ s: String) -> AttributedString { try! AttributedString(markdown: s) }

/// A top-leading text of 14 pt so the geometry is the same in every arm.
struct Subject<V: View>: View {
    let content: V
    var body: some View {
        content.font(.system(size: 14)).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

// MARK: - Arms

@MainActor func armOpen() {
    print("--- LK: which events open a run")
    let text = Subject(content: Text(md("see [docs](https://x.org) now")))
    arm("LK0 Text(AttributedString markdown link), click on the run", text) { clickLink($0) }
    arm("LK1 same, click OFF the run (left of it)", text) { w in
        guard let p = offPoint(w) else { Log.add("no-link"); return }
        click(w, at: p)
    }
    arm("LK3 two links, click the second", Subject(content: Text(md("[a](https://a.org) and [b](https://b.org)")))) {
        clickLink($0, 1)
    }
    arm("LK16 AttributedString with .link set in code", Subject(content: Text({
        var s = AttributedString("go there")
        s.link = URL(string: "https://code.org")
        return s }()))) { clickLink($0) }
    arm("LK_lit Text(\"[x](url)\") literal, LocalizedStringKey markdown", Subject(content: Text("see [docs](https://lit.org) now"))) {
        clickLink($0)
    }
    arm("LK4 press on the run, release OFF the run", text) { w in
        guard let on = linkPoint(w), let off = offPoint(w) else { Log.add("no-link"); return }
        press(w, on, release: off)
    }
    arm("LK5 press OFF the run, release ON the run", text) { w in
        guard let on = linkPoint(w), let off = offPoint(w) else { Log.add("no-link"); return }
        press(w, off, release: on)
    }
    arm("LK6 right press on the run", text) { w in
        guard let p = linkPoint(w) else { Log.add("no-link"); return }
        rightClick(w, at: p)
    }
    arm("LK7 .disabled(true)", Subject(content: Text(md("see [docs](https://x.org) now"))).disabled(true)) { clickLink($0) }
    arm("LK8 .allowsHitTesting(false)", Subject(content: Text(md("see [docs](https://x.org) now"))).allowsHitTesting(false)) {
        clickLink($0)
    }
    arm("LK19 double click on the run (count 1 then 2)", text) { w in
        guard let p = linkPoint(w) else { Log.add("no-link"); return }
        doubleClick(w, at: p)
    }
    let wide = Subject(content: Text(md("[a very long link run indeed](https://x.org)")))
    arm("O9 one drag event 25 pt inside a wide run, release inside it", wide) { w in
        guard let p = linkPoint(w, 0, dx: -60) else { Log.add("no-link"); return }
        press(w, p, release: CGPoint(x: p.x + 25, y: p.y))
    }
    arm("O9b the same drag as five 5 pt events", wide) { w in
        guard let p = linkPoint(w, 0, dx: -60) else { Log.add("no-link"); return }
        mouse(w, .leftMouseDown, p); spin(0.05)
        for i in 1...5 { mouse(w, .leftMouseDragged, CGPoint(x: p.x + 5 * CGFloat(i), y: p.y)); spin(0.03) }
        mouse(w, .leftMouseUp, CGPoint(x: p.x + 25, y: p.y)); spin()
    }
    arm("O9d CONTROL: the same synthetic drag reaches a DragGesture (so the drag events are delivered)",
        Subject(content: Color.blue.frame(width: 150, height: 20).gesture(DragGesture(minimumDistance: 0)
            .onChanged { v in Log.add("drag\(Int(v.translation.width))") }.onEnded { _ in Log.add("end") }))) { w in
        let p = CGPoint(x: 40, y: 190)
        mouse(w, .leftMouseDown, p); spin(0.05)
        for i in 1...5 { mouse(w, .leftMouseDragged, CGPoint(x: p.x + 5 * CGFloat(i), y: p.y)); spin(0.03) }
        mouse(w, .leftMouseUp, CGPoint(x: p.x + 25, y: p.y)); spin()
    }
    arm("O9c a 3 pt drag (one event)", wide) { w in
        guard let p = linkPoint(w, 0, dx: -60) else { Log.add("no-link"); return }
        press(w, p, release: CGPoint(x: p.x + 3, y: p.y))
    }
}

@MainActor func armWrap() {
    print("--- LK12: a run wrapped over two lines (the text 60 pt wide)")
    let wrapped = Subject(content: Text(md("aa [bb cc dd](https://w.org) ee")).frame(width: 60, alignment: .leading))
    arm("LK12 map: one click per 4 pt along each line of the text ('X' opened, '.' did not); rows top to bottom", wrapped) { w in
        guard let r = axLinks(w).first.map({ windowRect(w, axFrame($0)) }) else { Log.add("no-link"); return }
        var rows = ["axLinks=\(axLinks(w).count) frame=\(r)"]
        let lineHeight = r.height / 2
        for row in 0..<2 {
            let y = r.maxY - lineHeight * (CGFloat(row) + 0.5)
            var map = ""
            var x: CGFloat = 1
            while x < 64 {
                click(w, at: CGPoint(x: x, y: y))
                map += Log.take() == "-" ? "." : "X"
                x += 4
            }
            rows.append("row\(row)=\(map)")
        }
        rows.forEach { Log.add($0) }
    }
}

@MainActor func armAction() {
    print("--- action: which OpenURLAction runs, and with what")
    let one = Subject(content: Text(md("see [docs](https://x.org) now")))
    arm("LK15 inner action beats outer", one.environment(\.openURL, OpenURLAction { u in Log.add("inner \(u.absoluteString)"); return .handled })) {
        clickLink($0)
    }
    arm("LK14 handler returns .discarded: the handler ran (system fallback not observable here)",
        one.environment(\.openURL, OpenURLAction { u in Log.add("ran \(u.absoluteString)"); return .discarded })) {
        clickLink($0)
    }
    arm("LK14b nested: inner .discarded, does the OUTER action also run?",
        one.environment(\.openURL, OpenURLAction { u in Log.add("inner"); return .discarded })
            .environment(\.openURL, OpenURLAction { u in Log.add("outer"); return .handled })) { clickLink($0) }
    arm("LK21 custom scheme probe://x reaches the action", Subject(content: Text(md("[c](probe://x)")))) { clickLink($0) }
    arm("LK20 a scheme-less destination (example.com)", Subject(content: Text(md("[c](example.com)")))) { clickLink($0) }
}

struct FocusedField: View {
    @State var text = "abc"
    @FocusState var focused: Bool
    @FocusState var other: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(md("see [docs](https://x.org) now")).font(.system(size: 14))
            TextField("f", text: $text).focused($focused).frame(height: 30)
            Color.blue.focusable().focused($other).frame(height: 40)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear { focused = true }
        .onChange(of: focused) { _, v in Log.add("focused=\(v)") }
        .onChange(of: other) { _, v in Log.add("other=\(v)") }
    }
}

@MainActor func armFocus() {
    print("--- LK23: a click on a link and a focused field (a real @FocusState)")
    arm("LK23 field focused on appear, click the link", FocusedField()) { w in
        Log.add("|start"); clickLink(w)
    }
    arm("LK23b control: the same window, click the second focusable (focus must move)", FocusedField()) { w in
        Log.add("|start"); click(w, at: CGPoint(x: 100, y: 130))
    }
}

@MainActor func armGestures() {
    print("--- O: ranking against the gestures around it")
    func linked() -> Text { Text(md("see [docs](https://x.org) now")) }
    arm("O0a Text.onTapGesture, click the run", Subject(content: linked().onTapGesture { Log.add("tap") })) { clickLink($0) }
    arm("O0b Text.onTapGesture, click off the run", Subject(content: linked().onTapGesture { Log.add("tap") })) { w in
        guard let p = offPoint(w) else { Log.add("no-link"); return }
        click(w, at: p)
    }
    arm("O1a Button { Text(link) }, click the run", Subject(content: Button(action: { Log.add("tap") }) { linked() }.buttonStyle(.plain))) {
        clickLink($0)
    }
    arm("O1b same, click off the run", Subject(content: Button(action: { Log.add("tap") }) { linked() }.buttonStyle(.plain))) { w in
        guard let p = offPoint(w) else { Log.add("no-link"); return }
        click(w, at: p)
    }
    arm("O2a ancestor onTapGesture, click the run", Subject(content: VStack(alignment: .leading) { linked() }.contentShape(Rectangle())
        .onTapGesture { Log.add("tap") })) { clickLink($0) }
    arm("O2b same, click off the run", Subject(content: VStack(alignment: .leading) { linked() }.contentShape(Rectangle())
        .onTapGesture { Log.add("tap") })) { w in
        guard let p = offPoint(w) else { Log.add("no-link"); return }
        click(w, at: p)
    }
    arm("O3 link in a disabled Button", Subject(content: Button(action: { Log.add("tap") }) { linked() }.buttonStyle(.plain).disabled(true))) {
        clickLink($0)
    }
    arm("O5 an overlay tap ABOVE the text", Subject(content: linked().overlay(Color.clear.contentShape(Rectangle())
        .onTapGesture { Log.add("tap") }))) { clickLink($0) }
    arm("O6 simultaneousGesture(TapGesture) on the Text, click the run", Subject(content: linked()
        .simultaneousGesture(TapGesture().onEnded { Log.add("tap") }))) { clickLink($0) }
    arm("O6b highPriorityGesture(TapGesture) on the Text, click the run", Subject(content: linked()
        .highPriorityGesture(TapGesture().onEnded { Log.add("tap") }))) { clickLink($0) }
    arm("LK13 .textSelection(.enabled), click the run (NSHostingView: read as measured, see header)",
        Subject(content: linked().textSelection(.enabled))) { clickLink($0) }
    arm("LK17 Link(\"docs\", destination:) view (carried; not built by this PR)", Subject(content: Link("docs", destination: URL(string: "https://x.org")!))) { w in
        click(w, at: CGPoint(x: 15, y: 191))
    }
}

@MainActor func armAX() {
    print("--- AX: what the tree publishes")
    arm("AX1 tree of `two [aa] and [bb]`", Subject(content: Text(md("two [aa](https://x.org) and [bb](probe://b)")))) { w in
        @MainActor func dump(_ o: NSObject, _ depth: Int) {
            let r = windowRect(w, axFrame(o))
            Log.add("\(String(repeating: ">", count: depth))\(kv(o, "accessibilityRole")) label=\(kv(o, "accessibilityLabel")) value=\(kv(o, "accessibilityValue")) w=\(r.width.rounded())")
            for c in axChildren(o) { dump(c, depth + 1) }
        }
        for c in axChildren(w.contentView!) { dump(c, 0) }
    }
    arm("AX2 the link element: selectors it answers, AXURL, actions", Subject(content: Text(md("two [aa](https://x.org) and [bb](probe://b)")))) { w in
        guard let l = axLinks(w).first else { Log.add("no-link"); return }
        for sel in ["accessibilityURL", "accessibilityActionNames", "accessibilityAttributeNames", "accessibilityPerformPress",
                    "accessibilityPerformAction:", "accessibilityHelp", "accessibilityIdentifier", "accessibilityLinkedUIElements",
                    "accessibilityParent", "accessibilityTitle", "accessibilitySubrole", "accessibilityCustomActions"] {
            Log.add("\(sel)=\(l.responds(to: Selector(sel)))")
        }
        Log.add("accessibilityURL value=\(kv(l, "accessibilityURL"))")
        Log.add("attributeNames=\(l.accessibilityAttributeNames())")
        Log.add("AXURL (old API)=\(String(describing: l.accessibilityAttributeValue(NSAccessibility.Attribute(rawValue: "AXURL"))))")
        Log.add("customActions=\(kv(l, "accessibilityCustomActions"))")
        Log.add("parentRole=\(kv(l.value(forKey: "accessibilityParent") as! NSObject, "accessibilityRole"))")
    }
    arm("AX3 press path: accessibilityPerformPress on the link element", Subject(content: Text(md("two [aa](https://x.org) and [bb](probe://b)")))) { w in
        guard let l = axLinks(w).first else { Log.add("no-link"); return }
        Log.add("responds-performPress=\(l.responds(to: Selector("accessibilityPerformPress")))")
        // Calling it raises NSInvalidArgumentException (the element inherits AppKit's default, which forwards to
        // `accessibilityPerformAction:`, which the SwiftUI link element does not implement) and terminates the
        // process, so it runs only under LI_PROBE_PRESS=1; the default run stops at the respondsTo reading.
        if ProcessInfo.processInfo.environment["LI_PROBE_PRESS"] == "1" {
            _ = l.perform(Selector("accessibilityPerformPress"))
            spin()
        }
    }
}

setbuf(stdout, nil)
let app = NSApplication.shared
app.setActivationPolicy(.regular)
NSApp.accessibilitySetValue(true as NSNumber, forAttribute: NSAccessibility.Attribute(rawValue: "AXEnhancedUserInterface"))
NSApp.accessibilitySetValue(true as NSNumber, forAttribute: NSAccessibility.Attribute(rawValue: "AXManualAccessibility"))
armOpen(); armWrap(); armAction(); armFocus(); armGestures(); armAX()
