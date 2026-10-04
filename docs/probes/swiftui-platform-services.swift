// SwiftUI probe: platform services (user request 2026-10-02, an item of the
// gpui-gap priority list; not a plan task) — `.fileImporter`, `.fileExporter`,
// `.alert`, `.confirmationDialog`, `.onHover`, `Divider` as a view, and
// `.pickerStyle(.menu)`. Evidence for rulings SV-… in
// docs/superpowers/2026-10-04-platform-services-decisions.md; spec
// docs/superpowers/specs/2026-10-04-platform-services-design.md. Window sizing
// (a Scene modifier) is the companion probe swiftui-window-sizing.swift.
//
// HOW TO RUN (compiled form, SA-O):
//
//   xcrun swiftc docs/probes/swiftui-platform-services.swift -o /tmp/services-probe
//   /tmp/services-probe
//
// Headless: every event is a synthesized NSEvent handed to a window or to
// NSApp.sendEvent; panels and alerts are found through NSApp.windows and
// `attachedSheet`, and driven through their own buttons (`performClick`) or
// `NSSavePanel.ok(_:)`/`cancel(_:)`. Nothing is posted at the HID tap.
//
// RECORDED 2026-10-03 by the platform-services design session, macOS 27.0,
// Apple Swift 6.4, screen LOCKED (CGSSessionScreenIsLocked = 1, displayAsleep
// main: 1), so the app never became active and had no key window. Compiled
// form, run twice: stdout byte-identical (163 lines), exit 0, stderr empty.
// (An earlier draft called `NSSavePanel.ok(_:)` to complete a save; it raised
// "-[NSSavePanel ok:] : not implemented" — the panel is out of process — so
// completing an export or an import headlessly is a broken instrument and the
// arms only present, cancel and dismiss.)
//
// POSITIVE CONTROLS AND SEPARATING ARMS. D0 (isPresented false: no panel)
// against D1. A0 (not shown: no sheet) against A1. V3/V4 (no stack) against V1
// and V2 (a stack on each axis); V5/V6 (nested stacks: the nearest decides).
// P0 (automatic) against P1 (.menu): the same pop-up button on macOS. H: every
// arm reads [] under BOTH instruments — no hover callback fired, including H1
// (a plain onHover with the pointer moved across it): a broken instrument
// (an inactive app's synthesized mouseMoved reaches no SwiftUI hover), not a
// SwiftUI answer. No ruling rests on an H line.

//
// OUTPUT, verbatim:
//
//   --- D: fileImporter
//   === D0 control: fileImporter, isPresented false
//     windows=NSWindow attachedSheet=nil modalWindow=nil
//   === D1 isPresented = true, [.json], allowsMultipleSelection true
//     windows=NSOpenPanel,NSWindow attachedSheet=NSOpenPanel modalWindow=nil
//     panel class=NSOpenPanel types=["public.json"] multiple=true dirs=false files=true name="Untitled" prompt=nil title=Optional("Open") message=Optional("") extHidden=false canCreateDirs=true sheetParent=NSWindow
//     panel isSheet=true isModal=false level=0
//     D2 panel.cancel -> log [] isPresented=false windows=NSWindow
//     D3 shown=true, then isPresented = false -> panel visible=false log [] windows=NSWindow
//   === D4 single-URL overload, [.json, .plainText]
//     attachedSheet=NSOpenPanel modalWindow=nil
//     panel class=NSOpenPanel types=["public.json", "public.plain-text"] multiple=false dirs=false files=true name="Untitled" prompt=nil title=Optional("Open") message=Optional("") extHidden=false canCreateDirs=true sheetParent=NSWindow
//     D4 cancel -> log [] isPresented=false
//     D5 re-presented: panel=true
//   --- X: fileExporter
//   === X1 fileExporter(item: Data, contentTypes: [.json], defaultFilename: "keymap")
//     windows=NSSavePanel,NSWindow,NSWindow,NSWindow attachedSheet=NSSavePanel modalWindow=nil
//     panel class=NSSavePanel types=["public.json"] name="keymap" prompt=Optional("Export") title=Optional("Export") message=Optional("") extHidden=true canCreateDirs=true sheetParent=NSWindow
//     X3 cancel -> log ["cancelled"] isPresented=false
//   === X4 fileExporter(item: String, contentTypes: [.json], defaultFilename: "notes")
//     attachedSheet=NSSavePanel modalWindow=nil
//     panel class=NSSavePanel types=["public.json"] name="notes" prompt=Optional("Export") title=Optional("Export") message=Optional("") extHidden=true canCreateDirs=true sheetParent=NSWindow
//     X4 cancel -> log ["cancelled"] isPresented=false
//   === X5 fileExporter(item: nil as Data?)
//     panel=NSSavePanel log [] isPresented=true
//   --- A: alert
//   === A1 Delete(destructive) + Cancel(cancel) + message
//     A0 control (not shown): attachedSheet=nil modalWindow=nil
//     attachedSheet=_NSAlertPanel modalWindow=nil windows=NSWindow,NSWindow,NSWindow,NSWindow,NSWindow,NSWindow,_NSAlertPanel
//     sheet class=_NSAlertPanel texts=["Delete keymap?", "This cannot be undone."]
//     buttons (left→right): "Cancel" key="\u{1B}" x=16 y=16 | "Delete" key="" x=134 y=16 destructive
//     A6 Escape -> log ["cancel"] isPresented=false sheet=false
//     A7 Return -> log [] isPresented=true sheet=true
//     A8 click Delete -> log ["delete"] isPresented=false sheet=false
//     A9 isPresented = false while shown -> sheet=false log []
//   === A2 three plain buttons A, B, C, no message
//     attachedSheet=_NSAlertPanel modalWindow=nil windows=NSWindow,NSWindow,NSWindow,NSWindow,NSWindow,NSWindow,NSWindow,_NSAlertPanel
//     sheet class=_NSAlertPanel texts=["Three"]
//     buttons (left→right): "A" key="\r" x=16 y=84 | "B" key="" x=16 y=50 | "C" key="" x=16 y=16
//     defaultButtonCell="Optional("A")"
//     Escape -> log [] isPresented=true sheet=true
//     Return -> log ["A"] isPresented=false sheet=false
//   === A3 no actions
//     attachedSheet=_NSAlertPanel modalWindow=nil windows=NSWindow,NSWindow,NSWindow,NSWindow,NSWindow,NSWindow,NSWindow,NSWindow,_NSAlertPanel
//     sheet class=_NSAlertPanel texts=["No actions"]
//     buttons (left→right): "OK" key="" x=16 y=16
//     defaultButtonCell="Optional("OK")"
//     Return -> log [] isPresented=true sheet=true
//     Escape -> log [] isPresented=true sheet=true
//   === A4 Cancel declared first, then Delete(destructive)
//     attachedSheet=_NSAlertPanel modalWindow=nil windows=NSWindow,NSWindow,NSWindow,NSWindow,NSWindow,NSWindow,NSWindow,NSWindow,NSWindow,_NSAlertPanel
//     sheet class=_NSAlertPanel texts=["Cancel first"]
//     buttons (left→right): "Cancel" key="\u{1B}" x=16 y=16 | "Delete" key="" x=134 y=16 destructive
//     click first -> log ["cancel"] isPresented=false
//   === A5 Save + Discard(destructive), no cancel
//     attachedSheet=_NSAlertPanel modalWindow=nil windows=NSWindow,NSWindow,NSWindow,NSWindow,NSWindow,NSWindow,NSWindow,NSWindow,NSWindow,NSWindow,_NSAlertPanel
//     sheet class=_NSAlertPanel texts=["Plain pair", "Unsaved changes."]
//     buttons (left→right): "Save" key="" x=16 y=84 | "Discard" key="" x=16 y=50 destructive | "Cancel" key="\u{1B}" x=16 y=16
//     defaultButtonCell="Optional("Save")"
//     Escape -> log [] isPresented=false sheet=false
//     Return -> log [] isPresented=true sheet=true
//   === C1 confirmationDialog Delete + Cancel, titleVisibility .visible
//     attachedSheet=_NSAlertPanel modalWindow=nil windows=NSWindow,NSWindow,NSWindow,NSWindow,NSWindow,NSWindow,NSWindow,NSWindow,NSWindow,NSWindow,NSWindow,_NSAlertPanel
//     sheet class=_NSAlertPanel texts=["Confirm?", "Dialog message."]
//     buttons (left→right): "Cancel" key="\u{1B}" x=16 y=16 | "Delete" key="" x=134 y=16 destructive
//     click first -> log ["cancel"] isPresented=false
//   --- H: onHover (mouseMoved through NSWindow.sendEvent; y measured from the window BOTTOM)
//     -- instrument I1: NSWindow.sendEvent
//   === H1 one 100x100 at top-left
//     out (250,180), (40,40), (150,120), out -> []
//     H11 in, then a mouseExited and a move outside the window's frame -> []
//     H11 hosting view trackingAreas=1 options=[643]
//   === H2 inner 80x80 over outer 200x150, both onHover
//     out (250,180), (40,40), (150,120), out -> []
//   === H3 painted cover (no onHover) over onHover
//     out (250,180), (40,40), (150,120), out -> []
//   === H4 cover .allowsHitTesting(false)
//     out (250,180), (40,40), (150,120), out -> []
//   === H5 hovered view removed
//     in, then removed -> []
//     then moved out -> []
//   === H6 .disabled(true)
//     out (250,180), (40,40), (150,120), out -> []
//   === H7 left then right, adjacent
//     out, left, right, out -> []
//   === H8 clear onHover cover over a Button
//     hover, then click the button beneath -> []
//   === H9 parent onHover around child onHover
//     out (250,180), (40,40), (150,120), out -> []
//   === H10 onContinuousHover, offset (50,30)
//     out, (60,40), (70,45), out -> []
//     -- instrument I2: NSHostingView.mouseMoved(with:)
//   === H1 one 100x100 at top-left
//     out (250,180), (40,40), (150,120), out -> []
//     H11 in, then a mouseExited and a move outside the window's frame -> []
//     H11 hosting view trackingAreas=1 options=[643]
//   === H2 inner 80x80 over outer 200x150, both onHover
//     out (250,180), (40,40), (150,120), out -> []
//   === H3 painted cover (no onHover) over onHover
//     out (250,180), (40,40), (150,120), out -> []
//   === H4 cover .allowsHitTesting(false)
//     out (250,180), (40,40), (150,120), out -> []
//   === H5 hovered view removed
//     in, then removed -> []
//     then moved out -> []
//   === H6 .disabled(true)
//     out (250,180), (40,40), (150,120), out -> []
//   === H7 left then right, adjacent
//     out, left, right, out -> []
//   === H8 clear onHover cover over a Button
//     hover, then click the button beneath -> []
//   === H9 parent onHover around child onHover
//     out (250,180), (40,40), (150,120), out -> []
//   === H10 onContinuousHover, offset (50,30)
//     out, (60,40), (70,45), out -> []
//   --- V: Divider as a view
//     V1 in VStack 120.0x1.0 fitting=(120.0, 46.0)
//     V2 in HStack 1.0x40.0 fitting=(32.5, 40.0)
//     V3 root 300.0x1.0 fitting=(10.0, 1.0)
//     V4 in ZStack 120.0x1.0 fitting=(120.0, 40.0)
//     V5 VStack inside HStack 80.0x1.0 fitting=(80.0, 25.5)
//     V6 HStack inside VStack 1.0x50.0 fitting=(32.5, 50.0)
//     V7 HStack, nothing else 1.0x200.0 fitting=(1.0, 10.0)
//     V8 framed width 60 in VStack 60.0x1.0 fitting=(120.0, 1.0)
//     V9 padded in VStack 120.0x21.0 fitting=(120.0, 21.0)
//     V10 in Group in HStack 10.0x1.0 fitting=(10.0, 30.0)
//     V11 Group inside HStack 1.0x30.0 fitting=(1.0, 30.0)
//     V12 light @1x Divider().frame(width: 8) in VStack(spacing:0) between 3pt clear: 8x7 centre column top→bottom: (0,0,0,0) (0,0,0,0) (0,0,0,0) (0,0,0,25) (0,0,0,0) (0,0,0,0) (0,0,0,0)
//     V12 light @2x Divider().frame(width: 8) in VStack(spacing:0) between 3pt clear: 16x14 centre column top→bottom: (0,0,0,0) (0,0,0,0) (0,0,0,0) (0,0,0,0) (0,0,0,0) (0,0,0,0) (0,0,0,25) (0,0,0,25) (0,0,0,0) (0,0,0,0) (0,0,0,0) (0,0,0,0) (0,0,0,0) (0,0,0,0)
//     V12 dark @1x Divider().frame(width: 8) in VStack(spacing:0) between 3pt clear: 8x7 centre column top→bottom: (0,0,0,0) (0,0,0,0) (0,0,0,0) (25,25,25,25) (0,0,0,0) (0,0,0,0) (0,0,0,0)
//     V12 dark @2x Divider().frame(width: 8) in VStack(spacing:0) between 3pt clear: 16x14 centre column top→bottom: (0,0,0,0) (0,0,0,0) (0,0,0,0) (0,0,0,0) (0,0,0,0) (0,0,0,0) (25,25,25,25) (25,25,25,25) (0,0,0,0) (0,0,0,0) (0,0,0,0) (0,0,0,0) (0,0,0,0) (0,0,0,0)
//     V13 NSColor.separatorColor light=sRGB IEC61966-2.1 colorspace 1 1 1 0.0980392
//     V14 AX children of VStack{Text; Divider; Text}: []
//   --- P: menu Picker (after NSApp AXEnhancedUserInterface = true, so SwiftUI publishes its tree)
//   === V15 (AX on) VStack{Text; Divider; Text}
//       AXGroup label=nil value=nil frame=100x33
//         AXStaticText label=nil value=a frame=7x16
//         AXStaticText label=nil value=b frame=8x16
//   === P0 control: automatic style, 5 items
//     fitting=(280.0, 24.0) popUps=0
//       AXGroup label=nil value=nil frame=280x24
//         AXStaticText label=nil value=Key frame=22x16
//         AXPopUpButton label=nil value=Item 3 frame=86x24
//   === P1 .menu, 5 items, frame width 280
//     fitting=(280.0, 24.0) popUps=0
//       AXGroup label=nil value=nil frame=280x24
//         AXStaticText label=nil value=Key frame=22x16
//         AXPopUpButton label=nil value=Item 3 frame=86x24
//     press -> true tracking=["menu items=5 on=3 highlighted=nil first=[\"Item 0\", \"Item 1\", \"Item 2\"] font=13.0"] pick=1
//     P5 binding 99 (no tag) -> value=nil
//   === P2 .menu .labelsHidden .fixedSize, 5 items
//     fitting=(86.0, 24.0) popUps=0
//       AXGroup label=nil value=nil frame=86x24
//         AXPopUpButton label=Key value=Item 3 frame=86x24
//     press -> true tracking=["menu items=5 on=3 highlighted=nil first=[\"Item 0\", \"Item 1\", \"Item 2\"] font=13.0"] pick=3
//   === P3 .menu .fixedSize, 300 items
//     fitting=(132.5, 24.0) popUps=0
//       AXGroup label=nil value=nil frame=133x24
//         AXStaticText label=nil value=Key frame=22x16
//         AXPopUpButton label=nil value=Item 3 frame=102x24
//     press -> true tracking=["menu items=300 on=3 highlighted=nil first=[\"Item 0\", \"Item 1\", \"Item 2\"] font=13.0"] pick=3
//   --- end
//   exit 0
//
// READING (what the rulings rest on):
// - D1/D4: `.fileImporter` presents an NSOpenPanel as a SHEET on the window
//   (attachedSheet, isSheet=true, not modal), its allowedContentTypes the
//   declared types, multiple selection as declared, files only.
// - D2/D4: Cancel calls NO onCompletion and writes isPresented = false.
// - D3: isPresented = false while shown dismisses the panel, no callback.
// - X1/X4: `.fileExporter(item:contentTypes:defaultFilename:)` presents an
//   NSSavePanel sheet: name = defaultFilename (extension hidden), types = the
//   declared contentTypes, prompt and title "Export". X3/X4: Cancel calls
//   onCancellation and writes isPresented = false. X5: a nil item still
//   presents the panel.
// - A1–A5, C1: `.alert` and `.confirmationDialog` present an NSAlert sheet
//   (_NSAlertPanel) with the title and message as its two texts. Buttons:
//   two lay out side by side, the cancel button on the left whatever the
//   declaration order (A1, A4); three or more stack vertically in declaration
//   order with the cancel button last (A5). A destructive button carries
//   hasDestructiveAction. Keys: the cancel button carries Escape (A1, A6:
//   Escape runs it and dismisses); the first plain (neither cancel nor
//   destructive) button is the default (A2 "A" key , Return runs it;
//   A3/A5 defaultButtonCell OK/Save — Return reached neither because the sheet
//   is not key on a locked screen, unmeasured); with only destructive + cancel
//   there is no default (A1: no defaultButtonCell, A7: Return does nothing).
//   No actions shows one "OK" (A3). A destructive button without a cancel
//   gets a synthesized "Cancel" carrying Escape (A5: Escape dismisses, no
//   action runs); plain buttons only get none (A2: Escape does nothing). Any
//   button writes isPresented = false and runs its action (A8); isPresented =
//   false while shown dismisses with no action (A9).
// - V: `Divider` is a 1-point line along the nearest enclosing stack's cross
//   axis — horizontal (full width, 1 tall) in a VStack (V1) and outside any
//   stack (V3, V4: a ZStack is no stack), vertical (1 wide, full height) in an
//   HStack (V2, V7: the HStack then fills the window's height). The nearest
//   stack decides (V5, V6); a padding (V9), a Group (V11) and a frame (V8) are
//   transparent to it. Unconstrained its length is 10 (V3 fitting 10x1, V7
//   1x10). 1 point is 2 device pixels at 2x (V12). Colour: black at alpha
//   25/255 (≈ 0.098) in light, white at the same alpha in dark (V12) —
//   NSColor.separatorColor's alpha (V13). Not in the accessibility tree (V15).
// - P: a `.menu` picker is the automatic one on macOS (P0 = P1): an
//   AXPopUpButton whose value is the selected option's title, labelled by a
//   sibling static text (the title) or, under labelsHidden, by its own label
//   (P2); 24 tall; as wide as its WIDEST option (86 for "Item 0…4", 102 for
//   "Item 0…299", P3), not stretched by a wider frame (P1). Pressing it opens
//   an NSMenu of every option (300 in P3), the selected one checked
//   (state on); choosing an item writes its tag (P1: pick=1). A selection
//   matching no tag shows no value (P5).

import AppKit
import SwiftUI
import UniformTypeIdentifiers

setvbuf(stdout, nil, _IOLBF, 0)
@MainActor func spin(_ s: Double = 0.3) { RunLoop.main.run(until: Date().addingTimeInterval(s)) }
func str(_ v: Any?) -> String { v.map { "\($0)" } ?? "nil" }
final class Log: @unchecked Sendable { var lines: [String] = [] }
let log = Log()

var windows: [NSWindow] = []
@MainActor func host<V: View>(_ name: String, _ v: V, size: CGSize = CGSize(width: 300, height: 200),
                              origin: CGPoint = CGPoint(x: 300, y: 400)) -> NSHostingView<V> {
    let w = NSWindow(contentRect: NSRect(origin: origin, size: size),
                     styleMask: [.titled, .resizable], backing: .buffered, defer: false)
    w.isReleasedWhenClosed = false
    let h = NSHostingView(rootView: v)
    w.contentView = h
    w.orderFrontRegardless(); w.makeKey(); h.layoutSubtreeIfNeeded(); spin(0.4)
    print("=== \(name)"); windows.append(w)
    return h
}
@MainActor func visibleWindows() -> String {
    NSApp.windows.filter(\.isVisible).map { "\(type(of: $0))" }.sorted().joined(separator: ",")
}
@MainActor func sheetLine(_ w: NSWindow) -> String {
    let sheet = w.attachedSheet.map { "\(type(of: $0))" } ?? "nil"
    let modal = NSApp.modalWindow.map { "\(type(of: $0))" } ?? "nil"
    return "attachedSheet=\(sheet) modalWindow=\(modal)"
}
@MainActor func allViews(_ v: NSView) -> [NSView] { [v] + v.subviews.flatMap(allViews) }
@MainActor func buttons(in w: NSWindow) -> [NSButton] {
    guard let root = w.contentView?.superview ?? w.contentView else { return [] }
    return allViews(root).compactMap { $0 as? NSButton }
        .filter { !$0.isHidden && !$0.title.isEmpty && $0.bezelStyle != .disclosure }
        .sorted { $0.convert($0.bounds, to: nil).minX < $1.convert($1.bounds, to: nil).minX }
}
@MainActor func buttonsLine(_ w: NSWindow) -> String {
    buttons(in: w).map { b in
        let f = b.convert(b.bounds, to: nil)
        var s = "\"\(b.title)\" key=\(b.keyEquivalent.debugDescription) x=\(Int(f.minX)) y=\(Int(f.minY))"
        if b.hasDestructiveAction { s += " destructive" }
        return s
    }.joined(separator: " | ")
}
@MainActor func textsLine(_ w: NSWindow) -> String {
    guard let root = w.contentView else { return "" }
    return allViews(root).compactMap { ($0 as? NSTextField)?.stringValue }.filter { !$0.isEmpty }
        .map { "\"\($0)\"" }.joined(separator: ", ")
}
@MainActor func key(_ w: NSWindow, _ chars: String, code: UInt16) -> NSEvent {
    NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                     windowNumber: w.windowNumber, context: nil, characters: chars, charactersIgnoringModifiers: chars,
                     isARepeat: false, keyCode: code)!
}
@MainActor func mouse(_ type: NSEvent.EventType, _ w: NSWindow, _ p: CGPoint) -> NSEvent {
    NSEvent.mouseEvent(with: type, location: p, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                       windowNumber: w.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 0)!
}

final class Model: ObservableObject {
    @Published var shown = false
    @Published var flag = false
    @Published var pick = 3
    @Published var hovered = true
}

// MARK: - D: fileImporter

struct ImporterHost: View {
    @ObservedObject var m: Model
    let multiple: Bool
    var body: some View {
        if multiple {
            Text("Importer").frame(width: 200, height: 100)
                .fileImporter(isPresented: $m.shown, allowedContentTypes: [.json], allowsMultipleSelection: true) { r in
                    log.lines.append("completion \(r.map { $0.map(\.lastPathComponent) })")
                }
        } else {
            Text("Importer").frame(width: 200, height: 100)
                .fileImporter(isPresented: $m.shown, allowedContentTypes: [.json, .plainText]) { r in
                    log.lines.append("completion1 \(r.map(\.lastPathComponent))")
                }
        }
    }
}

@MainActor func panel(_ cls: AnyClass) -> NSSavePanel? {
    NSApp.windows.first { $0.isVisible && $0.isKind(of: cls) } as? NSSavePanel
}
@MainActor func panelLine(_ p: NSSavePanel) -> String {
    var s = "class=\(type(of: p)) types=\(p.allowedContentTypes.map(\.identifier))"
    if let o = p as? NSOpenPanel {
        s += " multiple=\(o.allowsMultipleSelection) dirs=\(o.canChooseDirectories) files=\(o.canChooseFiles)"
    }
    s += " name=\(p.nameFieldStringValue.debugDescription) prompt=\(p.prompt.debugDescription)"
    s += " title=\(p.title.debugDescription) message=\(p.message.debugDescription)"
    s += " extHidden=\(p.isExtensionHidden) canCreateDirs=\(p.canCreateDirectories)"
    s += " sheetParent=\(p.sheetParent.map { "\(type(of: $0))" } ?? "nil")"
    return s
}

// MARK: - X: fileExporter

struct ExporterHost: View {
    @ObservedObject var m: Model
    let item: Data?
    let text: String?
    var body: some View {
        if let text {
            Text("Exporter").frame(width: 200, height: 100)
                .fileExporter(isPresented: $m.shown, item: text, contentTypes: [.json], defaultFilename: "notes") { r in
                    log.lines.append("completion \(r.map(\.lastPathComponent))")
                } onCancellation: { log.lines.append("cancelled") }
        } else {
            Text("Exporter").frame(width: 200, height: 100)
                .fileExporter(isPresented: $m.shown, item: item, contentTypes: [.json], defaultFilename: "keymap") { r in
                    log.lines.append("completion \(r.map(\.lastPathComponent))")
                } onCancellation: { log.lines.append("cancelled") }
        }
    }
}

// MARK: - A: alert

struct AlertHost: View {
    @ObservedObject var m: Model
    let arm: Int
    var body: some View {
        let base = Text("Alert").frame(width: 300, height: 200)
        switch arm {
        case 1:
            base.alert("Delete keymap?", isPresented: $m.shown) {
                Button("Delete", role: .destructive) { log.lines.append("delete") }
                Button("Cancel", role: .cancel) { log.lines.append("cancel") }
            } message: { Text("This cannot be undone.") }
        case 2:
            base.alert("Three", isPresented: $m.shown) {
                Button("A") { log.lines.append("A") }
                Button("B") { log.lines.append("B") }
                Button("C") { log.lines.append("C") }
            }
        case 3:
            base.alert("No actions", isPresented: $m.shown) {}
        case 4:
            base.alert("Cancel first", isPresented: $m.shown) {
                Button("Cancel", role: .cancel) { log.lines.append("cancel") }
                Button("Delete", role: .destructive) { log.lines.append("delete") }
            }
        case 5:
            base.alert("Plain pair", isPresented: $m.shown) {
                Button("Save") { log.lines.append("save") }
                Button("Discard", role: .destructive) { log.lines.append("discard") }
            } message: { Text("Unsaved changes.") }
        default:
            base.confirmationDialog("Confirm?", isPresented: $m.shown, titleVisibility: .visible) {
                Button("Delete", role: .destructive) { log.lines.append("delete") }
                Button("Cancel", role: .cancel) { log.lines.append("cancel") }
            } message: { Text("Dialog message.") }
        }
    }
}

// MARK: - H: onHover

struct HoverHost: View {
    @ObservedObject var m: Model
    let arm: Int
    var body: some View {
        switch arm {
        case 1:
            Color.gray.frame(width: 100, height: 100)
                .onHover { log.lines.append("H \($0)") }
                .frame(width: 300, height: 200, alignment: .topLeading)
        case 2:
            ZStack(alignment: .topLeading) {
                Color.gray.frame(width: 200, height: 150).onHover { log.lines.append("outer \($0)") }
                Color.blue.frame(width: 80, height: 80).onHover { log.lines.append("inner \($0)") }
            }.frame(width: 300, height: 200, alignment: .topLeading)
        case 3:
            ZStack(alignment: .topLeading) {
                Color.gray.frame(width: 200, height: 150).onHover { log.lines.append("under \($0)") }
                Color.blue.frame(width: 80, height: 80)
            }.frame(width: 300, height: 200, alignment: .topLeading)
        case 4:
            ZStack(alignment: .topLeading) {
                Color.gray.frame(width: 200, height: 150).onHover { log.lines.append("under \($0)") }
                Color.blue.frame(width: 80, height: 80).allowsHitTesting(false)
            }.frame(width: 300, height: 200, alignment: .topLeading)
        case 5:
            VStack {
                if m.hovered {
                    Color.gray.frame(width: 100, height: 100).onHover { log.lines.append("removable \($0)") }
                }
            }.frame(width: 300, height: 200, alignment: .topLeading)
        case 6:
            Color.gray.frame(width: 100, height: 100)
                .onHover { log.lines.append("disabled \($0)") }
                .disabled(true)
                .frame(width: 300, height: 200, alignment: .topLeading)
        case 7:
            HStack(spacing: 0) {
                Color.gray.frame(width: 100, height: 100).onHover { log.lines.append("left \($0)") }
                Color.blue.frame(width: 100, height: 100).onHover { log.lines.append("right \($0)") }
            }.frame(width: 300, height: 200, alignment: .topLeading)
        case 8:
            ZStack(alignment: .topLeading) {
                Button("Under") { log.lines.append("button") }.frame(width: 100, height: 40)
                Color.clear.frame(width: 120, height: 60).contentShape(Rectangle())
                    .onHover { log.lines.append("cover \($0)") }
            }.frame(width: 300, height: 200, alignment: .topLeading)
        case 9:
            VStack(alignment: .leading, spacing: 0) {
                Color.gray.frame(width: 100, height: 100).onHover { log.lines.append("child \($0)") }
            }
            .padding(20)
            .background(Color.yellow)
            .onHover { log.lines.append("parent \($0)") }
            .frame(width: 300, height: 200, alignment: .topLeading)
        default:
            Color.gray.frame(width: 100, height: 100)
                .onContinuousHover { phase in
                    switch phase {
                    case .active(let p): log.lines.append("active \(Int(p.x)),\(Int(p.y))")
                    case .ended: log.lines.append("ended")
                    }
                }
                .offset(x: 50, y: 30)
                .frame(width: 300, height: 200, alignment: .topLeading)
        }
    }
}

// MARK: - V: Divider

struct Measure: ViewModifier {
    let name: String
    func body(content: Content) -> some View {
        content.background(GeometryReader { g in
            Color.clear.onAppear { log.lines.append("\(name) \(g.size.width)x\(g.size.height)") }
        })
    }
}
extension View { func measure(_ n: String) -> some View { modifier(Measure(name: n)) } }

struct DividerHost: View {
    let arm: Int
    var body: some View {
        switch arm {
        case 1: VStack { Text("a"); Divider().measure("V1 in VStack"); Text("b") }.frame(width: 120)
        case 2: HStack { Text("a"); Divider().measure("V2 in HStack"); Text("b") }.frame(height: 40)
        case 3: Divider().measure("V3 root")
        case 4: ZStack { Divider().measure("V4 in ZStack") }.frame(width: 120, height: 40)
        case 5: HStack { VStack { Text("a"); Divider().measure("V5 VStack inside HStack") }.frame(width: 80) }
        case 6: VStack { HStack { Text("a"); Divider().measure("V6 HStack inside VStack"); Text("b") } }.frame(height: 50)
        case 7: HStack { Divider().measure("V7 HStack, nothing else") }
        case 8: VStack { Divider().frame(width: 60).measure("V8 framed width 60 in VStack") }.frame(width: 120)
        case 9: VStack { Divider().padding(10).measure("V9 padded in VStack") }.frame(width: 120)
        case 10: Group { Divider().measure("V10 in Group in HStack") }.frame(height: 30).fixedSize(horizontal: true, vertical: false)
        default: HStack { Group { Divider().measure("V11 Group inside HStack") } }.frame(height: 30)
        }
    }
}

@MainActor func pixel(_ view: some View, scheme: ColorScheme, scale: CGFloat) -> String {
    let r = ImageRenderer(content: view.environment(\.colorScheme, scheme))
    r.scale = scale
    guard let cg = r.cgImage else { return "no image" }
    let w = cg.width, h = cg.height
    var data = [UInt8](repeating: 0, count: w * h * 4)
    let ctx = CGContext(data: &data, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
    var rows: [String] = []
    for y in 0..<h {
        let i = (y * w + w / 2) * 4
        rows.append("(\(data[i]),\(data[i + 1]),\(data[i + 2]),\(data[i + 3]))")
    }
    return "\(w)x\(h) centre column top→bottom: " + rows.joined(separator: " ")
}

// MARK: - P: menu picker

struct PickerHost: View {
    @ObservedObject var m: Model
    let count: Int
    let style: Int
    var body: some View {
        let p = Picker("Key", selection: $m.pick) {
            ForEach(0..<count, id: \.self) { Text("Item \($0)").tag($0) }
        }
        switch style {
        case 0: p.frame(width: 280)
        case 1: p.pickerStyle(.menu).frame(width: 280)
        case 2: p.pickerStyle(.menu).labelsHidden().fixedSize()
        default: p.pickerStyle(.menu).fixedSize()
        }
    }
}
func axValue(_ o: NSObject, _ key: String) -> Any? {
    o.responds(to: Selector(key)) ? o.value(forKey: key) : nil
}
@MainActor func axKids(_ o: NSObject) -> [NSObject] {
    ((axValue(o, "accessibilityChildren") as? [Any]) ?? []).compactMap { $0 as? NSObject }
}
@MainActor func axFind(_ o: NSObject, where p: (NSObject) -> Bool) -> NSObject? {
    if p(o) { return o }
    for k in axKids(o) { if let f = axFind(k, where: p) { return f } }
    return nil
}
@MainActor func axDump(_ o: NSObject, _ d: Int = 0) {
    let f = (axValue(o, "accessibilityFrame") as? NSRect).map { "\(Int($0.width))x\(Int($0.height))" } ?? "?"
    print("    " + String(repeating: "  ", count: d) + "\(String(describing: axValue(o, "accessibilityRole") ?? "nil")) "
          + "label=\(String(describing: axValue(o, "accessibilityLabel") ?? "nil")) "
          + "value=\(String(describing: axValue(o, "accessibilityValue") ?? "nil")) frame=\(f)")
    if d < 4 { for k in axKids(o).prefix(4) { axDump(k, d + 1) } }
}
@MainActor func popUps(_ v: NSView) -> [NSPopUpButton] { allViews(v).compactMap { $0 as? NSPopUpButton } }

let app = NSApplication.shared
app.setActivationPolicy(.regular)
MainActor.assumeIsolated {
    // ------------------------------------------------------------ D
    print("--- D: fileImporter")
    do {
        let m = Model()
        let h = host("D0 control: fileImporter, isPresented false", ImporterHost(m: m, multiple: true))
        print("  windows=\(visibleWindows()) \(sheetLine(h.window!))")
        m.shown = true; spin(1.5)
        print("=== D1 isPresented = true, [.json], allowsMultipleSelection true")
        print("  windows=\(visibleWindows()) \(sheetLine(h.window!))")
        if let p = panel(NSOpenPanel.self) {
            print("  panel \(panelLine(p))")
            print("  panel isSheet=\(p.isSheet) isModal=\(p.isModalPanel) level=\(p.level.rawValue)")
            p.cancel(nil); spin(1.0)
            print("  D2 panel.cancel -> log \(log.lines) isPresented=\(m.shown) windows=\(visibleWindows())")
        } else {
            print("  no NSOpenPanel visible")
        }
        log.lines = []
        m.shown = true; spin(1.5)
        let shown = panel(NSOpenPanel.self) != nil
        m.shown = false; spin(1.0)
        print("  D3 shown=\(shown), then isPresented = false -> panel visible=\(panel(NSOpenPanel.self) != nil) log \(log.lines) windows=\(visibleWindows())")
        if let p = panel(NSOpenPanel.self) { p.cancel(nil); spin(0.5) }
        log.lines = []
    }
    do {
        let m = Model()
        let h = host("D4 single-URL overload, [.json, .plainText]", ImporterHost(m: m, multiple: false))
        m.shown = true; spin(1.5)
        print("  \(sheetLine(h.window!))")
        if let p = panel(NSOpenPanel.self) {
            print("  panel \(panelLine(p))")
            p.cancel(nil); spin(1.0)
            print("  D4 cancel -> log \(log.lines) isPresented=\(m.shown)")
        }
        log.lines = []
        // D5: two importers in one window? A second presentation while the
        // first is up.
        m.shown = true; spin(1.0)
        let first = panel(NSOpenPanel.self)
        print("  D5 re-presented: panel=\(first != nil)")
        first?.cancel(nil); spin(0.5)
        log.lines = []
    }

    // ------------------------------------------------------------ X
    print("--- X: fileExporter")
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("services-probe-\(getpid())")
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    do {
        let m = Model()
        let json = Data("{\"k\":1}".utf8)
        let h = host("X1 fileExporter(item: Data, contentTypes: [.json], defaultFilename: \"keymap\")",
                     ExporterHost(m: m, item: json, text: nil))
        m.shown = true; spin(1.5)
        print("  windows=\(visibleWindows()) \(sheetLine(h.window!))")
        if let p = panel(NSSavePanel.self) {
            print("  panel \(panelLine(p))")
            // X2: `NSSavePanel.ok(_:)` raises "not implemented" on this out-of-process panel
            // (recorded on the first run) — completing a save headlessly is a broken instrument.
            p.cancel(nil); spin(1.0)
            print("  X3 cancel -> log \(log.lines) isPresented=\(m.shown)")
        } else { print("  no NSSavePanel visible") }
        log.lines = []
    }
    do {
        let m = Model()
        let h = host("X4 fileExporter(item: String, contentTypes: [.json], defaultFilename: \"notes\")",
                     ExporterHost(m: m, item: nil, text: "plain text"))
        m.shown = true; spin(1.5)
        print("  \(sheetLine(h.window!))")
        if let p = panel(NSSavePanel.self) {
            print("  panel \(panelLine(p))")
            p.cancel(nil); spin(1.0)
            print("  X4 cancel -> log \(log.lines) isPresented=\(m.shown)")
        }
        log.lines = []
        // X5: item nil.
    }
    do {
        let m = Model()
        _ = host("X5 fileExporter(item: nil as Data?)", ExporterHost(m: m, item: nil, text: nil))
        m.shown = true; spin(1.5)
        let p = panel(NSSavePanel.self)
        print("  panel=\(p.map { "\(type(of: $0))" } ?? "nil") log \(log.lines) isPresented=\(m.shown)")
        p?.cancel(nil); spin(0.5)
        log.lines = []
    }
    try? FileManager.default.removeItem(at: dir)

    // ------------------------------------------------------------ A
    print("--- A: alert")
    for arm in [1, 2, 3, 4, 5, 6] {
        let m = Model()
        let name = ["", "A1 Delete(destructive) + Cancel(cancel) + message",
                    "A2 three plain buttons A, B, C, no message",
                    "A3 no actions", "A4 Cancel declared first, then Delete(destructive)",
                    "A5 Save + Discard(destructive), no cancel", "C1 confirmationDialog Delete + Cancel, titleVisibility .visible"][arm]
        let h = host(name, AlertHost(m: m, arm: arm))
        let w = h.window!
        if arm == 1 { print("  A0 control (not shown): \(sheetLine(w))") }
        m.shown = true; spin(1.0)
        print("  \(sheetLine(w)) windows=\(visibleWindows())")
        guard let sheet = w.attachedSheet ?? NSApp.modalWindow else { print("  no sheet"); continue }
        print("  sheet class=\(type(of: sheet)) texts=[\(textsLine(sheet))]")
        print("  buttons (left→right): \(buttonsLine(sheet))")
        if let def = sheet.defaultButtonCell { print("  defaultButtonCell=\"\(def.title)\"") }
        if arm == 1 {
            // A6: Escape; A7: Return; A8: a click.
            sheet.sendEvent(key(sheet, "\u{1b}", code: 53)); spin(0.6)
            print("  A6 Escape -> log \(log.lines) isPresented=\(m.shown) sheet=\(w.attachedSheet != nil)")
            log.lines = []
            if !m.shown { m.shown = true; spin(1.0) }
            if let s = w.attachedSheet {
                s.sendEvent(key(s, "\r", code: 36)); spin(0.6)
                print("  A7 Return -> log \(log.lines) isPresented=\(m.shown) sheet=\(w.attachedSheet != nil)")
            }
            log.lines = []
            if !m.shown { m.shown = true; spin(1.0) }
            if let s = w.attachedSheet, let b = buttons(in: s).first(where: { $0.title == "Delete" }) {
                b.performClick(nil); spin(0.6)
                print("  A8 click Delete -> log \(log.lines) isPresented=\(m.shown) sheet=\(w.attachedSheet != nil)")
            }
            log.lines = []
            m.shown = true; spin(1.0)
            m.shown = false; spin(1.0)
            print("  A9 isPresented = false while shown -> sheet=\(w.attachedSheet != nil) log \(log.lines)")
            log.lines = []
        } else if arm == 2 || arm == 5 {
            sheet.sendEvent(key(sheet, "\u{1b}", code: 53)); spin(0.6)
            print("  Escape -> log \(log.lines) isPresented=\(m.shown) sheet=\(w.attachedSheet != nil)")
            log.lines = []
            if !m.shown { m.shown = true; spin(1.0) }
            if let s = w.attachedSheet {
                s.sendEvent(key(s, "\r", code: 36)); spin(0.6)
                print("  Return -> log \(log.lines) isPresented=\(m.shown) sheet=\(w.attachedSheet != nil)")
            }
            log.lines = []
            if let s = w.attachedSheet { buttons(in: s).first?.performClick(nil); spin(0.6) }
        } else if arm == 3 {
            sheet.sendEvent(key(sheet, "\r", code: 36)); spin(0.6)
            print("  Return -> log \(log.lines) isPresented=\(m.shown) sheet=\(w.attachedSheet != nil)")
            if !m.shown { m.shown = true; spin(1.0) }
            if let s = w.attachedSheet {
                s.sendEvent(key(s, "\u{1b}", code: 53)); spin(0.6)
                print("  Escape -> log \(log.lines) isPresented=\(m.shown) sheet=\(w.attachedSheet != nil)")
            }
        } else {
            buttons(in: sheet).first?.performClick(nil); spin(0.6)
            print("  click first -> log \(log.lines) isPresented=\(m.shown)")
        }
        if let s = w.attachedSheet { w.endSheet(s); spin(0.3) }
        log.lines = []
    }

    // ------------------------------------------------------------ H
    print("--- H: onHover (mouseMoved through NSWindow.sendEvent; y measured from the window BOTTOM)")
    for (instrument, arm) in (1...10).map({ (1, $0) }) + (1...10).map({ (2, $0) }) {
        if arm == 1 { print("  -- instrument I\(instrument): " + (instrument == 1 ? "NSWindow.sendEvent" : "NSHostingView.mouseMoved(with:)")) }
        let m = Model()
        let names = ["", "H1 one 100x100 at top-left", "H2 inner 80x80 over outer 200x150, both onHover",
                     "H3 painted cover (no onHover) over onHover", "H4 cover .allowsHitTesting(false)",
                     "H5 hovered view removed", "H6 .disabled(true)", "H7 left then right, adjacent",
                     "H8 clear onHover cover over a Button", "H9 parent onHover around child onHover",
                     "H10 onContinuousHover, offset (50,30)"]
        let h = host(names[arm], HoverHost(m: m, arm: arm))
        let w = h.window!
        let H = h.bounds.height
        func at(_ x: CGFloat, _ yFromTop: CGFloat) -> CGPoint { CGPoint(x: x, y: H - yFromTop) }
        // Instrument I1 (first run): NSWindow.sendEvent(mouseMoved) — recorded
        // nothing in every arm, so I2 hands the same event to the hosting view's
        // own mouseMoved(with:) (the owner of its one tracking area, options 643 =
        // enteredAndExited | mouseMoved | activeAlways | inVisibleRect).
        w.acceptsMouseMovedEvents = true
        @MainActor func move(_ x: CGFloat, _ y: CGFloat) {
            let e = mouse(.mouseMoved, w, at(x, y))
            if instrument == 1 { w.sendEvent(e) } else { h.mouseMoved(with: e) }
            spin(0.15)
        }
        switch arm {
        case 7:
            move(250, 180); move(50, 50); move(150, 50); move(250, 180)
            print("  out, left, right, out -> \(log.lines)")
        case 5:
            move(250, 180); move(50, 50)
            m.hovered = false; spin(0.4)
            print("  in, then removed -> \(log.lines)")
            move(250, 180)
            print("  then moved out -> \(log.lines)")
        case 8:
            move(250, 180); move(30, 20)
            w.sendEvent(mouse(.leftMouseDown, w, at(30, 20))); spin(0.1)
            // (a press through the window, both instruments)
            w.sendEvent(mouse(.leftMouseUp, w, at(30, 20))); spin(0.3)
            print("  hover, then click the button beneath -> \(log.lines)")
        case 10:
            move(250, 180); move(60, 40); move(70, 45); move(250, 180)
            print("  out, (60,40), (70,45), out -> \(log.lines)")
        default:
            move(250, 180); move(40, 40); move(150, 120); move(250, 180)
            print("  out (250,180), (40,40), (150,120), out -> \(log.lines)")
        }
        // H11: the pointer leaves the window (mouseExited at the window).
        if arm == 1 {
            log.lines = []
            move(40, 40)
            let exit = NSEvent.enterExitEvent(with: .mouseExited, location: at(400, 400), modifierFlags: [],
                                              timestamp: ProcessInfo.processInfo.systemUptime,
                                              windowNumber: w.windowNumber, context: nil, eventNumber: 0,
                                              trackingNumber: 0, userData: nil)!
            if instrument == 1 { w.sendEvent(exit) } else { h.mouseExited(with: exit) }
            spin(0.2)
            w.sendEvent(mouse(.mouseMoved, w, at(400, -50))); spin(0.2)
            print("  H11 in, then a mouseExited and a move outside the window's frame -> \(log.lines)")
            print("  H11 hosting view trackingAreas=\(h.trackingAreas.count) options=\(h.trackingAreas.map { $0.options.rawValue })")
        }
        log.lines = []
    }

    // ------------------------------------------------------------ V
    print("--- V: Divider as a view")
    for arm in 1...11 {
        let h = NSHostingView(rootView: DividerHost(arm: arm))
        let w = NSWindow(contentRect: NSRect(x: 300, y: 400, width: 300, height: 200), styleMask: [.titled],
                         backing: .buffered, defer: false)
        w.isReleasedWhenClosed = false; windows.append(w)
        w.contentView = h; w.orderFrontRegardless(); h.layoutSubtreeIfNeeded(); spin(0.3)
        print("  \(log.lines.joined(separator: "; ")) fitting=\(h.fittingSize)")
        log.lines = []
    }
    for scheme in [ColorScheme.light, .dark] {
        for scale in [1.0, 2.0] {
            print("  V12 \(scheme) @\(Int(scale))x Divider().frame(width: 8) in VStack(spacing:0) between 3pt clear: "
                  + pixel(VStack(spacing: 0) { Color.clear.frame(width: 8, height: 3); Divider().frame(width: 8)
                                                Color.clear.frame(width: 8, height: 3) }, scheme: scheme, scale: scale))
        }
    }
    print("  V13 NSColor.separatorColor light=\(NSColor.separatorColor.usingColorSpace(.sRGB).map { "\($0)" } ?? "?")")
    do {
        let h = NSHostingView(rootView: VStack(spacing: 0) { Text("a"); Divider(); Text("b") }.frame(width: 100))
        h.layoutSubtreeIfNeeded()
        let ax = (h.accessibilityChildren() ?? []).compactMap { $0 as? NSObject }
        print("  V14 AX children of VStack{Text; Divider; Text}: \(ax.map { String(describing: $0.value(forKey: "accessibilityRole") ?? "nil") })")
    }

    // ------------------------------------------------------------ P
    print("--- P: menu Picker (after NSApp AXEnhancedUserInterface = true, so SwiftUI publishes its tree)")
    NSApp.accessibilitySetValue(true, forAttribute: NSAccessibility.Attribute(rawValue: "AXEnhancedUserInterface"))
    spin(0.5)
    do {
        let h = host("V15 (AX on) VStack{Text; Divider; Text}", VStack(spacing: 0) { Text("a"); Divider(); Text("b") }.frame(width: 100))
        axDump(h)
    }
    for (style, name) in [(0, "P0 control: automatic style, 5 items"), (1, "P1 .menu, 5 items, frame width 280"),
                          (2, "P2 .menu .labelsHidden .fixedSize, 5 items"), (3, "P3 .menu .fixedSize, 300 items")] {
        let m = Model()
        let count = style == 3 ? 300 : 5
        let h = host(name, PickerHost(m: m, count: count, style: style), size: CGSize(width: 320, height: 120))
        let pops = popUps(h)
        print("  fitting=\(h.fittingSize) popUps=\(pops.count)")
        axDump(h)
        if style != 0, let node = axFind(h, where: { (axValue($0, "accessibilityRole") as? String) == "AXPopUpButton" }) {
            var began: [String] = []
            let token = NotificationCenter.default.addObserver(forName: NSMenu.didBeginTrackingNotification, object: nil,
                                                               queue: nil) { n in
                MainActor.assumeIsolated {
                    guard let menu = n.object as? NSMenu else { return }
                    let on = menu.items.firstIndex { $0.state == .on }.map(String.init) ?? "none"
                    began.append("menu items=\(menu.items.count) on=\(on) highlighted=\(menu.highlightedItem?.title ?? "nil") "
                                 + "first=\(menu.items.prefix(3).map(\.title)) font=\(menu.font?.pointSize ?? 0)")
                    let choose = menu.items.firstIndex { $0.title == "Item 1" }
                    let t = Timer(timeInterval: 0.4, repeats: false) { _ in
                        MainActor.assumeIsolated {
                            if style == 1, let choose { menu.performActionForItem(at: choose) }
                            menu.cancelTracking()
                        }
                    }
                    RunLoop.main.add(t, forMode: .eventTracking)
                    RunLoop.main.add(t, forMode: .default)
                }
            }
            let pressed = (node as? NSAccessibilityElementProtocol).map { _ in true } ?? false
            _ = node.perform(Selector(("accessibilityPerformPress")))
            spin(1.2)
            NotificationCenter.default.removeObserver(token)
            print("  press -> \(pressed) tracking=\(began) pick=\(m.pick)")
            if style == 1 {
                m.pick = 99; spin(0.3)
                if let n2 = axFind(h, where: { (axValue($0, "accessibilityRole") as? String) == "AXPopUpButton" }) {
                    print("  P5 binding 99 (no tag) -> value=\(String(describing: axValue(n2, "accessibilityValue") ?? "nil"))")
                }
            }
        }
        for p in pops {
            let f = p.convert(p.bounds, to: nil)
            print("  \(type(of: p)) pullsDown=\(p.pullsDown) items=\(p.numberOfItems) selected=\(p.indexOfSelectedItem) "
                  + "title=\(p.titleOfSelectedItem.debugDescription) frame=\(Int(f.width))x\(Int(f.height)) "
                  + "preferredEdge=\(p.preferredEdge.rawValue) autoenables=\(p.autoenablesItems) "
                  + "role=\(p.accessibilityRole()?.rawValue ?? "nil") label=\(p.accessibilityLabel().debugDescription)")
            print("    first items: \(p.itemTitles.prefix(6)) states: \(p.itemArray.prefix(6).map { $0.state.rawValue })")
            if style == 1 {
                p.selectItem(at: 1)
                if let a = p.action { NSApp.sendAction(a, to: p.target, from: p) }
                spin(0.3)
                print("    P4 selectItem(at: 1) + action -> pick=\(m.pick) title=\(p.titleOfSelectedItem.debugDescription)")
                m.pick = 99; spin(0.3)
                print("    P5 binding set to 99 (no tag) -> selected=\(p.indexOfSelectedItem) title=\(p.titleOfSelectedItem.debugDescription) items=\(p.numberOfItems)")
            }
        }
    }
    print("--- end")
}
exit(0)
