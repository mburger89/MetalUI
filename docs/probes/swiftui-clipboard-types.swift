// SwiftUI probe: clipboard beyond text (item S3, user request 2026-10-02, not a plan
// task) — `.copyable(_:)`, `.cuttable(for:action:)`, `.pasteDestination(for:action:validator:)`,
// `PasteButton`, and what each puts on or reads from the pasteboard. Evidence for rulings
// CB-A… in docs/superpowers/2026-10-14-clipboard-types-decisions.md; spec
// docs/superpowers/specs/2026-10-14-clipboard-types-design.md.
//
// HOW TO RUN (compiled form, SA-O):
//   xcrun swiftc docs/probes/swiftui-clipboard-types.swift -o /tmp/cb-probe && /tmp/cb-probe
//
// THE INSTRUMENTS.
// - S: the spellings compile (signatures as the SDK has them). A compile failure of this
//   file IS the reading; the separating arm is S-neg, run with METALUI_CB_NEG=1 through
//   `xcrun swiftc -D NEG`, which must FAIL to compile (a `.copyable` of a non-Transferable).
// - R: a hosting view in an offscreen, never-shown window; the responder-chain action
//   `copy:` is sent with `NSApp.sendAction(_:to:from:)`; a PRIVATE pasteboard is not
//   reachable (SwiftUI writes `NSPasteboard.general`), so R saves and restores the general
//   pasteboard's items around each arm. R needs an unlocked screen to make the window key
//   (lock probe: no CGSSessionScreenIsLocked line, `displayAsleep main: 0`); on a locked
//   screen the arms print `SKIP (locked)`, and the rulings that rest on them are marked
//   unprobed with a human check.
//
// RECORDED OUTPUT (2026-10-14, screen locked): see the block at the end of the file.
import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct Graph: Codable, Transferable {
    var nodes: [Int]
    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: UTType("com.metalui.probe.graph") ?? .json)
        ProxyRepresentation { (g: Graph) in "graph:\(g.nodes)" }
    }
}

struct Spellings: View {
    @State var graph = Graph(nodes: [1])
    var body: some View {
        Text("x").focusable()
            .copyable([graph])
            .cuttable(for: Graph.self) { let g = [graph]; graph = Graph(nodes: []); return g }
            .pasteDestination(for: Graph.self, action: { graph = $0.first ?? graph },
                              validator: { $0.filter { !$0.nodes.isEmpty } })
        PasteButton(payloadType: Graph.self) { graph = $0.first ?? graph }
    }
}
#if NEG
struct NotTransferable {}
struct Neg: View { var body: some View { Text("x").copyable([NotTransferable()]) } }
#endif

@MainActor func run() {
    print("S: spellings compile (copyable, cuttable, pasteDestination, PasteButton): OK")
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
    app.setActivationPolicy(.accessory)
    let host = NSHostingView(rootView: Spellings())
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 100), styleMask: [.titled], backing: .buffered, defer: false)
    window.contentView = host
    window.makeKeyAndOrderFront(nil)
    RunLoop.current.run(until: Date().addingTimeInterval(0.5))
    window.makeFirstResponder(host)
    general.clearContents()
    let sent = app.sendAction(#selector(NSText.copy(_:)), to: nil, from: nil)
    print("R1: copy: sent=\(sent) types=\(general.types?.map(\.rawValue) ?? [])")
}
MainActor.assumeIsolated { run() }

// RECORDED OUTPUT (2026-10-14, macOS, screen LOCKED):
//   S: spellings compile (copyable, cuttable, pasteDestination, PasteButton): OK
//   R: SKIP (locked)
//   -D NEG:  error: instance method 'copyable' requires that 'NotTransferable' conform to
//            'Transferable'                     <- the separating arm: S is not vacuous
// The signatures are therefore probed; routing (focus needed? responder-chain `copy:`),
// representations written (does a Transferable with a ProxyRepresentation also write a string?),
// validator effect on the menu item and PasteButton's look are UNPROBED here and ruled in
// CB-B/CB-G as such; human check CB1 re-takes arm R on an unlocked screen.
