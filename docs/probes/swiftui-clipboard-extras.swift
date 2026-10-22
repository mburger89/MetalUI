// SwiftUI probe: clipboard extras (round 2 item 6; record 142; rulings CP-A... in
// docs/superpowers/2026-10-22-clipboard-extras-decisions.md; spec
// docs/superpowers/specs/2026-10-22-clipboard-extras-design.md).
// Settles what CB-N (record 115) deferred: PasteButton, an environment clipboard,
// multi-item copy and paste (divergence 456), and lazy export.
//
// HOW TO RUN (compiled form, SA-O; R needs an unlocked screen, lock probe:
// `xcrun swiftc -O docs/probes/appkit-screen-lock-state.swift -o /tmp/ls && /tmp/ls`):
//   xcrun swiftc docs/probes/swiftui-clipboard-extras.swift -o /tmp/cx && /tmp/cx
//   xcrun swiftc -DNEG1 ... must FAIL (no EnvironmentValues.clipboard on macOS)
//   xcrun swiftc -DNEG2 ... must FAIL (PasteButton takes no label)
//   xcrun swiftc -DNEG3 ... must FAIL (PasteButton(payloadType:) needs a Transferable)
//
// INSTRUMENTS. S: spellings compile (the SDK's own signatures: three PasteButton
// initialisers, array forms of copyable/cuttable/pasteDestination). NEG1..3 are the
// separating arms: each non-existence claim is a compile failure of the same file with
// one line added, so S is not vacuous. R: an NSHostingView in an offscreen window whose
// first responder is the host; `copy:`/`paste:` are sent with NSApp.sendAction, and the
// GENERAL pasteboard is saved and restored (SwiftUI cannot be pointed at a private one).
// R1 multi-item copy writes N pasteboard items; R2 a paste of N items reaches the action
// as N values; R3 PasteButton's AppKit control, its enablement against an empty and a
// matching and a non-matching pasteboard, its accessibility role and label. R4 lazy export
// is read from the SDK headers, not run (see the end).
import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct Tag: Codable, Transferable, Equatable {
    var n: Int
    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: UTType("com.metalui.probe.tag") ?? .json)
    }
}

final class Box: @unchecked Sendable { var received: [Tag] = []; var pasted = 0 }

struct Spellings: View {
    let box: Box
    var body: some View {
        VStack {
            Text("x").focusable()
                .copyable([Tag(n: 1), Tag(n: 2)])
                .cuttable(for: Tag.self) { [Tag(n: 3), Tag(n: 4)] }
                .pasteDestination(for: Tag.self, action: { box.received = $0; box.pasted += 1 })
            PasteButton(payloadType: Tag.self) { box.received = $0; box.pasted += 1 }
            PasteButton(supportedContentTypes: [.plainText]) { _ in }
        }
    }
}
#if NEG1
func neg1() -> Any { EnvironmentValues().clipboard }
#endif
#if NEG2
struct Neg2: View { var body: some View { PasteButton(payloadType: Tag.self, onPaste: { _ in }) { Text("Paste") } } }
#endif
#if NEG3
struct NotT {}
struct Neg3: View { var body: some View { PasteButton(payloadType: NotT.self, onPaste: { _ in }) } }
#endif

func walk(_ v: NSView, _ depth: Int = 0, _ out: inout [String]) {
    let extra: String
    if let c = v as? NSControl { extra = " enabled=\(c.isEnabled) title=\(c.stringValue.debugDescription) size=\(v.frame.size)" } else { extra = "" }
    out.append(String(repeating: " ", count: depth) + "\(type(of: v))\(extra) axRole=\(v.accessibilityRole()?.rawValue ?? "-") axLabel=\(v.accessibilityLabel() ?? "-")")
    for s in v.subviews { walk(s, depth + 1, &out) }
}

@MainActor func run() {
    print("S: spellings compile (3 PasteButton inits, array forms): OK")
    let locked = (CGSessionCopyCurrentDictionary() as? [String: Any])?["CGSSessionScreenIsLocked"] != nil
    if locked { print("R: SKIP (locked)"); return }
    let general = NSPasteboard.general
    let saved = general.pasteboardItems?.map { item in
        item.types.compactMap { t in item.data(forType: t).map { (t, $0) } } } ?? []
    defer {
        general.clearContents()
        for item in saved { let n = NSPasteboardItem(); for (t, d) in item { n.setData(d, forType: t) }; general.writeObjects([n]) }
    }
    let app = NSApplication.shared
    app.setActivationPolicy(.regular)
    app.finishLaunching()
    let box = Box()
    let host = NSHostingView(rootView: Spellings(box: box))
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 200), styleMask: [.titled], backing: .buffered, defer: false)
    window.contentView = host
    app.activate(ignoringOtherApps: true)
    window.makeKeyAndOrderFront(nil)
    RunLoop.current.run(until: Date().addingTimeInterval(1.0))
    func spin() { RunLoop.current.run(until: Date().addingTimeInterval(0.4)) }

    // R1: multi-item copy. Focus the focusable Text by sending a key view loop step.
    func findProxy(_ v: NSView) -> NSView? { if "\(type(of: v))".contains("KeyViewProxy") { return v }; for s in v.subviews { if let f = findProxy(s) { return f } }; return nil }
    if let proxy = findProxy(host) { print("   proxy acceptsFirstResponder=\(proxy.acceptsFirstResponder) made=\(window.makeFirstResponder(proxy))") }
    spin()
    print("   isKey=\(window.isKeyWindow) responds copy:=\(window.firstResponder?.responds(to: #selector(NSText.copy(_:))) ?? false) paste:=\(window.firstResponder?.responds(to: #selector(NSText.paste(_:))) ?? false) validate=\(String(describing: (window.firstResponder as? NSUserInterfaceValidations)?.validateUserInterfaceItem(NSMenuItem(title: "c", action: #selector(NSText.copy(_:)), keyEquivalent: ""))))")
    print("   firstResponder=\(String(describing: window.firstResponder.map { "\(type(of: $0))" }))")
    general.clearContents()
    let sent = app.sendAction(#selector(NSText.copy(_:)), to: nil, from: nil)
    let items = general.pasteboardItems ?? []
    print("R1: copy: sent=\(sent) items=\(items.count) types=\(items.map { $0.types.map(\.rawValue) })")
    for (i, item) in items.enumerated() {
        for t in item.types { if let d = item.data(forType: t) { print("   item\(i) \(t.rawValue) \(d.count) bytes \(String(decoding: d.prefix(40), as: UTF8.self))") } }
    }

    // R2: multi-item paste: two Tag items on the pasteboard, then paste:.
    general.clearContents()
    let tagType = NSPasteboard.PasteboardType("com.metalui.probe.tag")
    func tagItem(_ n: Int) -> NSPasteboardItem { let i = NSPasteboardItem(); i.setData(Data("{\"n\":\(n)}".utf8), forType: tagType); return i }
    general.writeObjects([tagItem(7), tagItem(8)])
    box.pasted = 0
    let sentPaste = app.sendAction(#selector(NSText.paste(_:)), to: nil, from: nil)
    spin()
    print("R2: paste: sent=\(sentPaste) action ran \(box.pasted)x, received=\(box.received.map(\.n))")

    // R3: PasteButton control and its enablement.
    for (label, setup) in [("empty", { general.clearContents() }),
                           ("matching", { general.clearContents(); general.writeObjects([tagItem(7)]) }),
                           ("nonmatching", { general.clearContents(); general.setString("hello", forType: .string) })] as [(String, () -> Void)] {
        setup(); spin(); host.layoutSubtreeIfNeeded()
        var lines: [String] = []; walk(host, 0, &lines)
        func ax(_ e: Any, _ d: Int) { guard d < 6 else { return }
            if let el = e as? NSAccessibilityElementProtocol & NSObjectProtocol { let o = el as AnyObject
                let role = o.accessibilityRole?()?.rawValue ?? "-"; let label = o.accessibilityLabel?() ?? "-"
                lines.append(String(repeating: " ", count: d) + "AX \(role) label=\(label) enabled=\(o.isAccessibilityEnabled?() ?? true)")
                for c in (o.accessibilityChildren?() ?? []) { ax(c, d + 1) } } }
        ax(host, 0)
        print("R3[\(label)]:"); lines.forEach { print("   " + $0) }
    }
}
MainActor.assumeIsolated { run() }
// R4 (SDK headers, not run): `lazy export` — CoreTransferable's `DataRepresentation(exportedContentType:exporting:)`
// closure is async and is evaluated by the system when a consumer asks (NSItemProvider/NSPasteboardItemDataProvider
// under the hood); `copyable` hands the pasteboard the Transferable and SwiftUI decides when to call the closure.

// RECORDED OUTPUT (2026-10-21, macOS, screen UNLOCKED by the lock probe, `swift`-built command-line
// process with .regular policy, activate(ignoringOtherApps:) and makeKeyAndOrderFront):
//   S: spellings compile (3 PasteButton inits, array forms): OK
//   -DNEG1: error: value of type 'EnvironmentValues' has no member 'clipboard'      <- no env clipboard on macOS
//   -DNEG2: error: extra trailing closure passed in call                            <- PasteButton has no label
//   -DNEG3: error: initializer 'init(payloadType:onPaste:)' requires that 'NotT' conform to 'Transferable'
//   R1/R2: copy:/paste: sent=false, items=0 — the hosting window never became key (isKey=false)
//          from a command-line process in this session, so no responder-chain action reached the
//          hosting view. R3: PasteButton and the focusable Text host NO NSControl (KeyViewProxy and
//          _FocusRingView only; AX tree not exposed: AXGroup enabled=false for every pasteboard state).
// Therefore PROBED: the three PasteButton initialisers (SDK header: payloadType:onPaste: macOS 13,
// supportedContentTypes:payloadAction: macOS 11, a validator form deprecated on macOS), the array
// signatures of copyable/cuttable/pasteDestination, and that there is NO EnvironmentValues clipboard
// and NO label on macOS. UNPROBED (human check CP1 on a machine where the window becomes key):
// how many pasteboard items an array copy writes, what a multi-item paste delivers, PasteButton's
// enablement against the pasteboard and its look. Rulings resting on those say unprobed.
