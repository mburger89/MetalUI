// SwiftUI probe: dialog and alert extras (round-3 item R3-6) -
// `.fileDialogConfirmationLabel(_:)` / `.fileDialogMessage(_:)` on an
// importer and an exporter, `confirmationDialog`'s `titleVisibility`, an alert
// whose `Button` label is not a plain `Text`, and a `TextField`/`SecureField`
// inside alert actions. Evidence for rulings SV-AO... in
// docs/superpowers/2026-10-04-platform-services-decisions.md.
//
// HOW TO RUN (compiled form, SA-O):
//
//   xcrun swiftc docs/probes/swiftui-dialog-extras.swift -o /tmp/dialog-extras-probe
//   /tmp/dialog-extras-probe
//
// Same instrument as swiftui-platform-services.swift (panels and sheets found
// through NSApp.windows / attachedSheet, driven through cancel/performClick).
//
// OUTPUT: see the RECORDED block below.

// RECORDED 2026-10-31 by the R3-6 session, macOS 27.0, Apple Swift 6.4, screen
// LOCKED (the app never became active). Compiled form, run twice: stdout
// byte-identical (109 lines), exit 0.
//
// READING.
// - F: `fileDialogConfirmationLabel`/`fileDialogMessage` written AFTER (outside)
//   `.fileImporter`/`.fileExporter` reach the panel as `NSSavePanel.prompt` and
//   `.message` (F1, F3, F4; the exporter's own "Export" prompt gives way to the
//   label, its title stays "Export"); written on the content INSIDE the
//   presenter they reach nothing (F2: prompt nil, message ""). The control
//   (F0) has prompt nil and message "". The String spellings read as Text's (F4).
// - C: `titleVisibility` has no effect on macOS: the sheet shows the title for
//   .automatic, .visible and .hidden, with a message (C1-C3) or without (C4-C7);
//   an empty message shows nothing (C8). A confirmation dialog differs from an
//   alert in its buttons: with any action and no cancel role a "Cancel" is
//   appended (C10, C12, L7) - plain buttons get it too, where an alert's get
//   none (A2) - and then nothing is the default (C10, C12: key ""); with a
//   declared cancel the first plain button is the default (C11, key "\r").
//   No actions: one "OK" (C9).
// - L: a button's title is the FIRST Text in its label, depth first (L1 Label,
//   L2 HStack of Image and Text, L4 VStack, L5 styled Text, L6 Label{icon:},
//   L11 a nested stack after an Image). A button whose label holds no Text is
//   LEFT OUT (L3, L8, L9, L10); when none is left the alert shows "OK" and a
//   click runs nothing (L3, L10). A left-out cancel button is not a cancel
//   button (L9: "B" takes Return).
// - T: a TextField (and a SecureField, T2) in alert actions - and in a
//   confirmation dialog (T3) - is shown as an accessory view of the sheet, one
//   field per declaration, in order, with its placeholder; typing writes the
//   binding live (T1: binding "abc" before OK) and the button's action reads
//   it. Carried: MetalUI's SDL alert is drawn by the window and has no text
//   input (`SV-AO` item 5).
//
// OUTPUT, verbatim:
//
//   --- F: file dialog label and message
//   === F0 control
//     panel class=NSOpenPanel types=["public.json"] multiple=false dirs=false files=true name="Untitled" prompt=nil title=Optional("Open") message=Optional("") extHidden=false canCreateDirs=true sheetParent=NSWindow
//   === F1 importer, modifiers outside
//     panel class=NSOpenPanel types=["public.json"] multiple=false dirs=false files=true name="Untitled" prompt=Optional("Pick it") title=Optional("Open") message=Optional("Choose the keymap") extHidden=false canCreateDirs=true sheetParent=NSWindow
//   === F2 importer, modifiers inside
//     panel class=NSOpenPanel types=["public.json"] multiple=false dirs=false files=true name="Untitled" prompt=nil title=Optional("Open") message=Optional("") extHidden=false canCreateDirs=true sheetParent=NSWindow
//   === F3 exporter, modifiers outside
//     panel class=NSSavePanel types=["public.json"] name="k" prompt=Optional("Keep") title=Optional("Export") message=Optional("Where to keep it") extHidden=true canCreateDirs=true sheetParent=NSWindow
//   === F4 importer [.folder], String overloads
//     panel class=NSOpenPanel types=["public.folder"] multiple=false dirs=true files=false name="Untitled" prompt=Optional("Use folder") title=Optional("Open") message=Optional("Pick a folder") extHidden=false canCreateDirs=true sheetParent=NSWindow
//   --- C: confirmationDialog titleVisibility
//   === C1
//     texts=["Title1", "Message1"] buttons: "Cancel" key="\u{1B}" x=16 y=16 | "Go" key="" x=134 y=16
//   === C2
//     texts=["Title2", "Message2"] buttons: "Cancel" key="\u{1B}" x=16 y=16 | "Go" key="" x=134 y=16
//   === C3
//     texts=["Title3", "Message3"] buttons: "Cancel" key="\u{1B}" x=16 y=16 | "Go" key="" x=134 y=16
//   === C4
//     texts=["Title4"] buttons: "Cancel" key="\u{1B}" x=16 y=16 | "Go" key="" x=134 y=16
//   === C5
//     texts=["Title5"] buttons: "Cancel" key="\u{1B}" x=16 y=16 | "Go" key="" x=134 y=16
//   === C6
//     texts=["Title6"] buttons: "Cancel" key="\u{1B}" x=16 y=16 | "Go" key="" x=134 y=16
//   === C7
//     texts=["Title7"] buttons: "Cancel" key="\u{1B}" x=16 y=16 | "Go" key="" x=134 y=16
//   === C8
//     texts=["Title8"] buttons: "Cancel" key="\u{1B}" x=16 y=16 | "Go" key="" x=134 y=16
//   === C9
//     texts=["Title9"] buttons: "OK" key="" x=16 y=16
//     Escape -> log [] isPresented=true
//     Return -> log [] isPresented=true
//   === C10
//     texts=["Title10"] buttons: "A" key="" x=16 y=84 | "B" key="" x=16 y=50 | "Cancel" key="\u{1B}" x=16 y=16
//     Escape -> log [] isPresented=false
//     Return -> log [] isPresented=true
//   === C11
//     texts=["Title11"] buttons: "Stop" key="\u{1B}" x=16 y=16 | "A" key="\r" x=134 y=16
//     Escape -> log ["A", "stop"] isPresented=false
//     Return -> log ["A"] isPresented=false
//   === C12
//     texts=["Title12"] buttons: "Cancel" key="\u{1B}" x=16 y=16 | "Delete" key="" x=134 y=16 destructive
//     Escape -> log [] isPresented=false
//     Return -> log [] isPresented=true
//   --- L: non-Text button labels
//   === L1
//     texts=["L1"] buttons: "Never mind" key="\u{1B}" x=16 y=16 | "Trash" key="\r" x=134 y=16
//     all NSButtons titles/images: ["\"Never mind\" img=false", "\"Trash\" img=false"]
//     click first -> log []
//   === L2
//     texts=["L2"] buttons: "Star it" key="\r" x=16 y=16
//     all NSButtons titles/images: ["\"Star it\" img=false"]
//     click first -> log ["hs"]
//   === L3
//     texts=["L3"] buttons: "OK" key="" x=16 y=16
//     all NSButtons titles/images: ["\"OK\" img=false"]
//     click first -> log []
//   === L4
//     texts=["L4"] buttons: "First" key="\r" x=16 y=16
//     all NSButtons titles/images: ["\"First\" img=false"]
//     click first -> log ["two"]
//   === L5
//     texts=["L5"] buttons: "Bold" key="\r" x=16 y=16
//     all NSButtons titles/images: ["\"Bold\" img=false"]
//     click first -> log ["styled"]
//   === L6
//     texts=["L6"] buttons: "Custom" key="\r" x=16 y=16
//     all NSButtons titles/images: ["\"Custom\" img=false"]
//     click first -> log ["lab2"]
//   === L7
//     texts=["L7"] buttons: "Cancel" key="\u{1B}" x=16 y=16 | "Trash" key="" x=134 y=16
//     all NSButtons titles/images: ["\"Cancel\" img=false", "\"Trash\" img=false"]
//     click first -> log []
//   === L8
//     texts=["L8"] buttons: "C" key="" x=16 y=16 | "A" key="\r" x=134 y=16
//     all NSButtons titles/images: ["\"C\" img=false", "\"A\" img=false"]
//     click first -> log ["C"]
//   === L9
//     texts=["L9"] buttons: "B" key="\r" x=16 y=16
//     all NSButtons titles/images: ["\"B\" img=false"]
//     click first -> log ["B"]
//   === L10
//     texts=["L10"] buttons: "OK" key="" x=16 y=16
//     all NSButtons titles/images: ["\"OK\" img=false"]
//     click first -> log []
//   === L11
//     texts=["L11"] buttons: "Deep" key="\r" x=16 y=16
//     all NSButtons titles/images: ["\"Deep\" img=false"]
//     click first -> log ["nested"]
//   --- T: text fields in alert actions
//   === T1
//     texts=["F1"] buttons: "Cancel" key="\u{1B}" x=16 y=16 | "OK" key="\r" x=134 y=16
//     fields: AppKitTextField value="" placeholder=Optional("Name")
//     accessoryView: 0 secure fields
//     typed: field="abc" binding="abc"
//     click OK -> log ["ok text=abc"] text="abc"
//   === T2
//     texts=["F2", "Enter both"] buttons: "OK" key="\r" x=16 y=16
//     fields: AppKitTextField value="" placeholder=Optional("Name") | AppKitSecureTextField value="" placeholder=Optional("Password")
//     accessoryView: 1 secure fields
//     typed: field="abc" binding="abc"
//     click OK -> log [] text="abc"
//   === T3
//     texts=["F3"] buttons: "Cancel" key="\u{1B}" x=16 y=16 | "OK" key="" x=134 y=16
//     fields: AppKitTextField value="" placeholder=Optional("Name")
//     accessoryView: 0 secure fields
//     typed: field="abc" binding="abc"
//     click OK -> log [] text="abc"
//   --- end


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
    @Published var text = ""
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

struct FileHost: View {
    @ObservedObject var m: Model
    let arm: Int
    var body: some View {
        let base = Text("File").frame(width: 200, height: 100)
        switch arm {
        case 1: // label and message OUTSIDE the importer
            base.fileImporter(isPresented: $m.shown, allowedContentTypes: [.json]) { _ in }
                .fileDialogConfirmationLabel(Text("Pick it")).fileDialogMessage(Text("Choose the keymap"))
        case 2: // INSIDE (on the content)
            base.fileDialogConfirmationLabel(Text("Pick it")).fileDialogMessage(Text("Choose the keymap"))
                .fileImporter(isPresented: $m.shown, allowedContentTypes: [.json]) { _ in }
        case 3: // exporter, outside
            base.fileExporter(isPresented: $m.shown, item: Data("{}".utf8), contentTypes: [.json], defaultFilename: "k") { _ in }
                .fileDialogConfirmationLabel(Text("Keep")).fileDialogMessage(Text("Where to keep it"))
        case 4: // String overloads, importer folders
            base.fileImporter(isPresented: $m.shown, allowedContentTypes: [.folder]) { _ in }
                .fileDialogConfirmationLabel("Use folder").fileDialogMessage("Pick a folder")
        default: // control, neither
            base.fileImporter(isPresented: $m.shown, allowedContentTypes: [.json]) { _ in }
        }
    }
}

struct DialogHost: View {
    @ObservedObject var m: Model
    let arm: Int
    var body: some View {
        let base = Text("Dialog").frame(width: 300, height: 200)
        switch arm {
        case 1: base.confirmationDialog("Title1", isPresented: $m.shown, titleVisibility: .automatic) {
                    Button("Go") {}
                } message: { Text("Message1") }
        case 2: base.confirmationDialog("Title2", isPresented: $m.shown, titleVisibility: .visible) {
                    Button("Go") {}
                } message: { Text("Message2") }
        case 3: base.confirmationDialog("Title3", isPresented: $m.shown, titleVisibility: .hidden) {
                    Button("Go") {}
                } message: { Text("Message3") }
        case 4: base.confirmationDialog("Title4", isPresented: $m.shown, titleVisibility: .automatic) {
                    Button("Go") {}
                }
        case 5: base.confirmationDialog("Title5", isPresented: $m.shown, titleVisibility: .visible) {
                    Button("Go") {}
                }
        case 6: base.confirmationDialog("Title6", isPresented: $m.shown, titleVisibility: .hidden) {
                    Button("Go") {}
                }
        case 7: base.confirmationDialog("Title7", isPresented: $m.shown) { // no titleVisibility argument
                    Button("Go") {}
                }
        case 8: base.confirmationDialog("Title8", isPresented: $m.shown, titleVisibility: .hidden) {
                    Button("Go") {}
                } message: { Text("") }
        case 9: base.confirmationDialog("Title9", isPresented: $m.shown) {}
        case 10: base.confirmationDialog("Title10", isPresented: $m.shown) {
                    Button("A") { log.lines.append("A") }
                    Button("B") { log.lines.append("B") }
                }
        case 11: base.confirmationDialog("Title11", isPresented: $m.shown) {
                    Button("A") { log.lines.append("A") }
                    Button("Stop", role: .cancel) { log.lines.append("stop") }
                }
        case 12: base.confirmationDialog("Title12", isPresented: $m.shown) {
                    Button("Delete", role: .destructive) { log.lines.append("delete") }
                }
        default: base
        }
    }
}

struct LabelHost: View {
    @ObservedObject var m: Model
    let arm: Int
    var body: some View {
        let base = Text("Label").frame(width: 300, height: 200)
        switch arm {
        case 1: base.alert("L1", isPresented: $m.shown) {
                    Button(action: { log.lines.append("trash") }) { Label("Trash", systemImage: "trash") }
                    Button(role: .cancel, action: {}) { Text("Never mind") }
                }
        case 2: base.alert("L2", isPresented: $m.shown) {
                    Button(action: { log.lines.append("hs") }) { HStack { Image(systemName: "star"); Text("Star it") } }
                }
        case 3: base.alert("L3", isPresented: $m.shown) {
                    Button(action: { log.lines.append("img") }) { Image(systemName: "star") }
                }
        case 4: base.alert("L4", isPresented: $m.shown) {
                    Button(action: { log.lines.append("two") }) { VStack { Text("First"); Text("Second") } }
                }
        case 5: base.alert("L5", isPresented: $m.shown) {
                    Button(action: { log.lines.append("styled") }) { Text("Bold").bold() }
                }
        case 6: base.alert("L6", isPresented: $m.shown) {
                    Button(action: { log.lines.append("lab2") }) { Label { Text("Custom") } icon: { Image(systemName: "star") } }
                }
        case 7: base.confirmationDialog("L7", isPresented: $m.shown, titleVisibility: .visible) {
                    Button(action: { log.lines.append("trash") }) { Label("Trash", systemImage: "trash") }
                }
        case 8: base.alert("L8", isPresented: $m.shown) {
                    Button("A") { log.lines.append("A") }
                    Button(action: { log.lines.append("img") }) { Image(systemName: "star") }
                    Button("C") { log.lines.append("C") }
                }
        case 9: base.alert("L9", isPresented: $m.shown) {
                    Button(role: .cancel, action: { log.lines.append("imgcancel") }) { Image(systemName: "star") }
                    Button("B") { log.lines.append("B") }
                }
        case 10: base.alert("L10", isPresented: $m.shown) {
                    Button(action: { log.lines.append("empty") }) { EmptyView() }
                }
        case 11: base.alert("L11", isPresented: $m.shown) {
                    Button(action: { log.lines.append("nested") }) { VStack { Image(systemName: "star"); HStack { Text("Deep"); Text("Second") } } }
                }
        default: base
        }
    }
}

struct FieldHost: View {
    @ObservedObject var m: Model
    let arm: Int
    var body: some View {
        let base = Text("Field").frame(width: 300, height: 200)
        switch arm {
        case 1: base.alert("F1", isPresented: $m.shown) {
                    TextField("Name", text: $m.text)
                    Button("OK") { log.lines.append("ok text=\(m.text)") }
                    Button("Cancel", role: .cancel) {}
                }
        case 2: base.alert("F2", isPresented: $m.shown) {
                    TextField("Name", text: $m.text)
                    SecureField("Password", text: $m.text)
                    Button("OK") {}
                } message: { Text("Enter both") }
        default: base.confirmationDialog("F3", isPresented: $m.shown) {
                    TextField("Name", text: $m.text)
                    Button("OK") {}
                }
        }
    }
}

@MainActor func fieldsLine(_ w: NSWindow) -> String {
    guard let root = w.contentView?.superview ?? w.contentView else { return "" }
    return allViews(root).compactMap { v -> String? in
        guard let t = v as? NSTextField, t.isEditable else { return nil }
        return "\(type(of: t)) value=\(t.stringValue.debugDescription) placeholder=\(t.placeholderString.debugDescription)"
    }.joined(separator: " | ")
}

let app = NSApplication.shared
app.setActivationPolicy(.regular)
MainActor.assumeIsolated {
    print("--- F: file dialog label and message")
    for arm in 0...4 {
        let m = Model()
        let name = ["F0 control", "F1 importer, modifiers outside", "F2 importer, modifiers inside",
                    "F3 exporter, modifiers outside", "F4 importer [.folder], String overloads"][arm]
        let h = host(name, FileHost(m: m, arm: arm))
        m.shown = true; spin(1.5)
        if let p = panel(NSSavePanel.self) {
            print("  panel \(panelLine(p))")
            p.cancel(nil); spin(1.0)
        } else { print("  no panel") }
    }
    print("--- C: confirmationDialog titleVisibility")
    for arm in 1...12 {
        let m = Model()
        let h = host("C\(arm)", DialogHost(m: m, arm: arm))
        m.shown = true; spin(1.0)
        guard let sheet = h.window!.attachedSheet else { print("  no sheet"); continue }
        print("  texts=[\(textsLine(sheet))] buttons: \(buttonsLine(sheet))")
        if arm >= 9 {
            sheet.sendEvent(key(sheet, "\u{1b}", code: 53)); spin(0.6)
            print("  Escape -> log \(log.lines) isPresented=\(m.shown)")
            log.lines = []
            if !m.shown { m.shown = true; spin(1.0) }
            if let s2 = h.window!.attachedSheet {
                s2.sendEvent(key(s2, "\r", code: 36)); spin(0.6)
                print("  Return -> log \(log.lines) isPresented=\(m.shown)")
                log.lines = []
            }
        }
        if let b = buttons(in: h.window!.attachedSheet ?? sheet).first { b.performClick(nil); spin(0.5) }
    }
    print("--- L: non-Text button labels")
    for arm in 1...11 {
        let m = Model()
        let h = host("L\(arm)", LabelHost(m: m, arm: arm))
        m.shown = true; spin(1.0)
        guard let sheet = h.window!.attachedSheet else { print("  no sheet"); continue }
        print("  texts=[\(textsLine(sheet))] buttons: \(buttonsLine(sheet))")
        let all = buttons(in: sheet)
        print("  all NSButtons titles/images: \(all.map { "\($0.title.debugDescription) img=\($0.image != nil)" })")
        if let b = all.first { b.performClick(nil); spin(0.5); print("  click first -> log \(log.lines)"); log.lines = [] }
    }
    print("--- T: text fields in alert actions")
    for arm in 1...3 {
        let m = Model()
        let h = host("T\(arm)", FieldHost(m: m, arm: arm))
        m.shown = true; spin(1.0)
        guard let sheet = h.window!.attachedSheet else { print("  no sheet"); continue }
        print("  texts=[\(textsLine(sheet))] buttons: \(buttonsLine(sheet))")
        print("  fields: \(fieldsLine(sheet))")
        print("  accessoryView: \((sheet.contentView?.superview).map { allViews($0).filter { $0 is NSSecureTextField }.count } ?? -1) secure fields")
        if let f = allViews(sheet.contentView!.superview!).compactMap({ $0 as? NSTextField }).first(where: { $0.isEditable }) {
            sheet.makeFirstResponder(f); f.currentEditor()?.insertText("abc"); spin(0.3)
            print("  typed: field=\(f.stringValue.debugDescription) binding=\(m.text.debugDescription)")
        }
        if let b = buttons(in: sheet).first(where: { $0.title == "OK" }) { b.performClick(nil); spin(0.5); print("  click OK -> log \(log.lines) text=\(m.text.debugDescription)"); log.lines = [] }
    }
    print("--- end")
}
exit(0)
