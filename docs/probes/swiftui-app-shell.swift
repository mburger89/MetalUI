// SwiftUI probe: the app shell — window title (`.navigationTitle`), the
// represented document (`.navigationDocument`), `.windowStyle(.hiddenTitleBar)`,
// `.windowDismissBehavior`, termination with a presentation up
// (`.presentationPreventsAppTermination`), and `.onOpenURL` delivery (item C8,
// user request 2026-10-02; MetalCreator gaps M6-a…M6-d). Evidence for rulings
// AS-… in docs/superpowers/2026-10-08-app-shell-decisions.md.
//
// HOW TO RUN (compiled form, SA-O; an `App` needs -parse-as-library). One
// build per arm, chosen by a -D flag; defaults cleared first (a WindowGroup
// autosaves its frame, see swiftui-window-sizing.swift):
//
//   for arm in N0 N1 N2 N5 N3 N4 H0 H1 D0 D1 T0 T1 T2 T3 O0 O1 O2 O3 O4 O5; do
//     xcrun swiftc -parse-as-library -D $arm docs/probes/swiftui-app-shell.swift -o /tmp/as-$arm
//     defaults delete as-$arm 2>/dev/null; /tmp/as-$arm -ApplePersistenceIgnoreState YES
//   done
//
// INSTRUMENTS. Every reading is of the real `NSWindow` SwiftUI made
// (`NSApp.windows`, panels excluded) one second after the content appeared.
// Termination is read by calling SwiftUI's own application delegate
// (`NSApp.delegate?.applicationShouldTerminate(NSApp)`) — the call AppKit makes
// for ⌘Q — without terminating; URL opens by calling the delegate's
// `application(_:open:)`, the call AppKit makes for a Finder open, `open -a`,
// a Dock drop or a URL scheme.
//
// POSITIVE CONTROLS AND SEPARATING ARMS. N0 (no modifier) is the control for
// N1-N4's title and represented URL; H0 against N0's style mask and geometry;
// D1 (no modifier) is the control for D0's close; T0 (nothing presented) the
// control for T1-T3; O0 (one handler) the control for O1-O3, and O2 (no
// handler) separates "a handler ran" from "the delegate ignored the call".
//
// RECORDED 2026-10-09 by the app-shell design session, macOS 27.0.1, Apple
// Swift 6.4, screen LOCKED (CGSSessionScreenIsLocked = 1, displayAsleep main:
// 1; the app never became active: `key=nil main=nil`). Every arm compiled and
// run twice from cleared defaults, exit 0 each, stderr empty. The two runs are
// byte-identical EXCEPT the order of the handler lines in O1 and O5, which
// differs between runs; O1 and O5 were then run four more times each: O1 read
// outer-then-inner all four times, O5 right-then-left all four. Over the six
// runs O1 read inner-first once (run 1, below) and O5 left-first once (run 2):
// SwiftUI runs every handler once and its order is NOT stable.
//
// RE-RUN 2026-10-09 by the app-shell critic session, screen UNLOCKED (no
// CGSSessionScreenIsLocked line, displayAsleep main: 0): arms N5 and H0
// rebuilt and run once each from cleared defaults; every line byte-identical
// to run 1 below, exit 0.
//
// OUTPUT, run 1 verbatim (run 2 differs only in O1's and O5's order):
//
//   === N0 control: WindowGroup("Probe"), no modifier
//     window #1 appeared
//     first: title="Probe" subtitle="" representedURL=nil edited=false fullSize=true titled=true closable=true transparentBar=false titleVisibility=visible closeButton=hidden:false enabled:true frame=(900.0, 450.0) contentView=(900.0, 450.0) contentLayoutRect=(0.0, 0.0, 900.0, 418.0)
//     content geometry: safeArea.top=32.0 origin(global)=(0.0, 32.0) size=(900.0, 418.0)
//     exit=0
//   === N1 .navigationTitle("Doc A"), then "Doc B"
//     window #1 appeared
//     first: title="Doc A" subtitle="" representedURL=nil edited=false fullSize=true titled=true closable=true transparentBar=false titleVisibility=visible closeButton=hidden:false enabled:true frame=(900.0, 450.0) contentView=(900.0, 450.0) contentLayoutRect=(0.0, 0.0, 900.0, 418.0)
//     content geometry: safeArea.top=32.0 origin(global)=(0.0, 32.0) size=(900.0, 418.0)
//     after title -> Doc B: title="Doc B" subtitle="" representedURL=nil edited=false fullSize=true titled=true closable=true transparentBar=false titleVisibility=visible closeButton=hidden:false enabled:true frame=(900.0, 450.0) contentView=(900.0, 450.0) contentLayoutRect=(0.0, 0.0, 900.0, 418.0)
//     exit=0
//   === N2 nested .navigationTitle: "Inner" inside "Outer"
//     window #1 appeared
//     first: title="Inner" subtitle="" representedURL=nil edited=false fullSize=true titled=true closable=true transparentBar=false titleVisibility=visible closeButton=hidden:false enabled:true frame=(900.0, 450.0) contentView=(900.0, 450.0) contentLayoutRect=(0.0, 0.0, 900.0, 418.0)
//     content geometry: safeArea.top=32.0 origin(global)=(0.0, 32.0) size=(900.0, 418.0)
//     exit=0
//   === N5 sibling .navigationTitle: "Left" then "Right" in one HStack
//     window #1 appeared
//     first: title="Left" subtitle="" representedURL=nil edited=false fullSize=true titled=true closable=true transparentBar=false titleVisibility=visible closeButton=hidden:false enabled:true frame=(900.0, 450.0) contentView=(900.0, 450.0) contentLayoutRect=(0.0, 0.0, 900.0, 418.0)
//     content geometry: safeArea.top=32.0 origin(global)=(0.0, 32.0) size=(446.0, 418.0)
//     exit=0
//   === N3 .navigationDocument(file URL)
//     window #1 appeared
//     first: title="Probe" subtitle="" representedURL=/tmp/probe-doc.mcgraph edited=false fullSize=true titled=true closable=true transparentBar=false titleVisibility=visible closeButton=hidden:false enabled:true frame=(900.0, 450.0) contentView=(900.0, 450.0) contentLayoutRect=(0.0, 0.0, 900.0, 418.0)
//     content geometry: safeArea.top=32.0 origin(global)=(0.0, 32.0) size=(900.0, 418.0)
//     exit=0
//   === N4 .navigationDocument(file URL) + .navigationTitle("Custom")
//     window #1 appeared
//     first: title="Custom" subtitle="" representedURL=/tmp/probe-doc.mcgraph edited=false fullSize=true titled=true closable=true transparentBar=false titleVisibility=visible closeButton=hidden:false enabled:true frame=(900.0, 450.0) contentView=(900.0, 450.0) contentLayoutRect=(0.0, 0.0, 900.0, 418.0)
//     content geometry: safeArea.top=32.0 origin(global)=(0.0, 32.0) size=(900.0, 418.0)
//     exit=0
//   === H0 .windowStyle(.hiddenTitleBar)
//     window #1 appeared
//     first: title="Probe" subtitle="" representedURL=nil edited=false fullSize=true titled=true closable=true transparentBar=true titleVisibility=hidden closeButton=hidden:false enabled:true frame=(900.0, 450.0) contentView=(900.0, 450.0) contentLayoutRect=(0.0, 0.0, 900.0, 418.0)
//     content geometry: safeArea.top=32.0 origin(global)=(0.0, 32.0) size=(900.0, 418.0)
//     exit=0
//   === H1 .windowStyle(.hiddenTitleBar), content .ignoresSafeArea()
//     window #1 appeared
//     first: title="Probe" subtitle="" representedURL=nil edited=false fullSize=true titled=true closable=true transparentBar=true titleVisibility=hidden closeButton=hidden:false enabled:true frame=(900.0, 450.0) contentView=(900.0, 450.0) contentLayoutRect=(0.0, 0.0, 900.0, 418.0)
//     content geometry: safeArea.top=0.0 origin(global)=(0.0, 0.0) size=(900.0, 450.0)
//     exit=0
//   === D0 .windowDismissBehavior(.disabled)
//     window #1 appeared
//     first: title="Probe" subtitle="" representedURL=nil edited=false fullSize=true titled=true closable=false transparentBar=false titleVisibility=visible closeButton=hidden:false enabled:false frame=(900.0, 450.0) contentView=(900.0, 450.0) contentLayoutRect=(0.0, 0.0, 900.0, 418.0)
//     content geometry: safeArea.top=32.0 origin(global)=(0.0, 32.0) size=(900.0, 418.0)
//     delegate=AppKitWindowController windowShouldClose -> true
//     after performClose: visible windows=1
//     exit=0
//   === D1 control: no dismiss modifier
//     window #1 appeared
//     first: title="Probe" subtitle="" representedURL=nil edited=false fullSize=true titled=true closable=true transparentBar=false titleVisibility=visible closeButton=hidden:false enabled:true frame=(900.0, 450.0) contentView=(900.0, 450.0) contentLayoutRect=(0.0, 0.0, 900.0, 418.0)
//     content geometry: safeArea.top=32.0 origin(global)=(0.0, 32.0) size=(900.0, 418.0)
//     delegate=AppKitWindowController windowShouldClose -> true
//     after performClose: visible windows=0
//     exit=0
//   === T0 control: nothing presented
//     window #1 appeared
//     first: title="Probe" subtitle="" representedURL=nil edited=false fullSize=true titled=true closable=true transparentBar=false titleVisibility=visible closeButton=hidden:false enabled:true frame=(900.0, 450.0) contentView=(900.0, 450.0) contentLayoutRect=(0.0, 0.0, 900.0, 418.0)
//     content geometry: safeArea.top=32.0 origin(global)=(0.0, 32.0) size=(900.0, 418.0)
//     nothing presented: applicationShouldTerminate -> terminateNow; sheet=false sheet.preventsApplicationTerminationWhenModal=n/a
//     exit=0
//   === T1 .alert presented, no prevents modifier
//     window #1 appeared
//     first: title="Probe" subtitle="" representedURL=nil edited=false fullSize=true titled=true closable=true transparentBar=false titleVisibility=visible closeButton=hidden:false enabled:true frame=(900.0, 450.0) contentView=(900.0, 450.0) contentLayoutRect=(0.0, 0.0, 900.0, 418.0)
//     content geometry: safeArea.top=32.0 origin(global)=(0.0, 32.0) size=(900.0, 418.0)
//     alert presented: applicationShouldTerminate -> terminateNow; sheet=true sheet.preventsApplicationTerminationWhenModal=false
//     exit=0
//   === T2 .alert presented + .presentationPreventsAppTermination(true)
//     window #1 appeared
//     first: title="Probe" subtitle="" representedURL=nil edited=false fullSize=true titled=true closable=true transparentBar=false titleVisibility=visible closeButton=hidden:false enabled:true frame=(900.0, 450.0) contentView=(900.0, 450.0) contentLayoutRect=(0.0, 0.0, 900.0, 418.0)
//     content geometry: safeArea.top=32.0 origin(global)=(0.0, 32.0) size=(900.0, 418.0)
//     alert presented: applicationShouldTerminate -> terminateNow; sheet=true sheet.preventsApplicationTerminationWhenModal=false
//     exit=0
//   === T3 .alert presented + .presentationPreventsAppTermination(false)
//     window #1 appeared
//     first: title="Probe" subtitle="" representedURL=nil edited=false fullSize=true titled=true closable=true transparentBar=false titleVisibility=visible closeButton=hidden:false enabled:true frame=(900.0, 450.0) contentView=(900.0, 450.0) contentLayoutRect=(0.0, 0.0, 900.0, 418.0)
//     content geometry: safeArea.top=32.0 origin(global)=(0.0, 32.0) size=(900.0, 418.0)
//     alert presented: applicationShouldTerminate -> terminateNow; sheet=true sheet.preventsApplicationTerminationWhenModal=false
//     exit=0
//   === O0 one .onOpenURL
//     window #1 appeared
//     first: title="Probe" subtitle="" representedURL=nil edited=false fullSize=true titled=true closable=true transparentBar=false titleVisibility=visible closeButton=hidden:false enabled:true frame=(900.0, 450.0) contentView=(900.0, 450.0) contentLayoutRect=(0.0, 0.0, 900.0, 418.0)
//     content geometry: safeArea.top=32.0 origin(global)=(0.0, 32.0) size=(900.0, 418.0)
//     delegate=AppDelegate respondsToOpenURLs=true
//     window #2 appeared
//     after open probe-open.mcgraph: handlers ran=["#2:probe-open.mcgraph"] windows 1 -> 2
//     exit=0
//   === O1 nested .onOpenURL (inner, outer) in one window
//     window #1 appeared
//     first: title="Probe" subtitle="" representedURL=nil edited=false fullSize=true titled=true closable=true transparentBar=false titleVisibility=visible closeButton=hidden:false enabled:true frame=(900.0, 450.0) contentView=(900.0, 450.0) contentLayoutRect=(0.0, 0.0, 900.0, 418.0)
//     content geometry: safeArea.top=32.0 origin(global)=(0.0, 32.0) size=(900.0, 418.0)
//     delegate=AppDelegate respondsToOpenURLs=true
//     window #2 appeared
//     after open probe-open.mcgraph: handlers ran=["#2 inner:probe-open.mcgraph", "#2 outer:probe-open.mcgraph"] windows 1 -> 2
//     exit=0
//   === O2 no .onOpenURL anywhere
//     window #1 appeared
//     first: title="Probe" subtitle="" representedURL=nil edited=false fullSize=true titled=true closable=true transparentBar=false titleVisibility=visible closeButton=hidden:false enabled:true frame=(900.0, 450.0) contentView=(900.0, 450.0) contentLayoutRect=(0.0, 0.0, 900.0, 418.0)
//     content geometry: safeArea.top=32.0 origin(global)=(0.0, 32.0) size=(900.0, 418.0)
//     delegate=AppDelegate respondsToOpenURLs=true
//     window #2 appeared
//     window #3 appeared
//     after open probe-open.mcgraph: handlers ran=[] windows 1 -> 2
//     exit=0
//   === O3 two opens: the second with two windows of one group up, each with .onOpenURL
//     window #1 appeared
//     first: title="Probe" subtitle="" representedURL=nil edited=false fullSize=true titled=true closable=true transparentBar=false titleVisibility=visible closeButton=hidden:false enabled:true frame=(900.0, 450.0) contentView=(900.0, 450.0) contentLayoutRect=(0.0, 0.0, 900.0, 418.0)
//     content geometry: safeArea.top=32.0 origin(global)=(0.0, 32.0) size=(900.0, 418.0)
//     window #2 appeared
//     after first open: handlers ran=["#2:probe-open.mcgraph"] windows=2 key=nil main=nil
//     window #3 appeared
//     after second open: handlers ran=["#3:probe-open-2.mcgraph"] windows=3
//     exit=0
//   === O4 .onOpenURL + .handlesExternalEvents(preferring: ["*"], allowing: ["*"])
//     window #1 appeared
//     first: title="Probe" subtitle="" representedURL=nil edited=false fullSize=true titled=true closable=true transparentBar=false titleVisibility=visible closeButton=hidden:false enabled:true frame=(900.0, 450.0) contentView=(900.0, 450.0) contentLayoutRect=(0.0, 0.0, 900.0, 418.0)
//     content geometry: safeArea.top=32.0 origin(global)=(0.0, 32.0) size=(900.0, 418.0)
//     delegate=AppDelegate respondsToOpenURLs=true
//     after open probe-open.mcgraph: handlers ran=["#1:probe-open.mcgraph"] windows 1 -> 1
//     exit=0
//   === O5 sibling .onOpenURL (left, right) in one HStack + .handlesExternalEvents("*")
//     window #1 appeared
//     first: title="Probe" subtitle="" representedURL=nil edited=false fullSize=true titled=true closable=true transparentBar=false titleVisibility=visible closeButton=hidden:false enabled:true frame=(900.0, 450.0) contentView=(900.0, 450.0) contentLayoutRect=(0.0, 0.0, 900.0, 418.0)
//     content geometry: safeArea.top=32.0 origin(global)=(0.0, 32.0) size=(446.0, 418.0)
//     delegate=AppDelegate respondsToOpenURLs=true
//     after open probe-open.mcgraph: handlers ran=["#1 right:probe-open.mcgraph", "#1 left:probe-open.mcgraph"] windows 1 -> 1
//     exit=0
//
// READING.
// - N0-N5: `.navigationTitle` IS the window's title on macOS, no navigation
//   container needed (N1), and follows a change (N1 "Doc B"). Nested: the
//   INNER title wins (N2). Siblings: the FIRST wins (N5). `.navigationDocument`
//   sets `representedURL` and leaves the title alone (N3); with a title, both
//   (N4). `isDocumentEdited` stays false throughout: SwiftUI has no view-level
//   edited marker (only DocumentGroup sets it).
// - Every SwiftUI window is already `.fullSizeContentView` (N0) with the
//   content in a 32-pt top safe area. H0 `.hiddenTitleBar` adds
//   `titlebarAppearsTransparent` and `titleVisibility = .hidden`, keeps the
//   traffic lights (close button visible, enabled), and the content STAYS
//   below the bar (safeArea.top 32, origin y 32); only `.ignoresSafeArea()`
//   puts it under the bar (H1: origin y 0, height 450).
// - D0: `.windowDismissBehavior(.disabled)` clears `.closable` and disables
//   the close button; `performClose` then closes nothing — a static switch,
//   not a veto (the delegate's `windowShouldClose` still answers true). D1 is
//   its control.
// - T0-T3: SwiftUI's delegate answers `terminateNow` with an alert sheet up,
//   with or without `.presentationPreventsAppTermination(true)` — this
//   instrument (the delegate call, app inactive) does not separate the
//   modifier; the sheet's `preventsApplicationTerminationWhenModal` reads
//   false in all three. NOT a measurement of what ⌘Q does with that modifier.
// - O0-O5: an external open makes a WindowGroup open a NEW window and run
//   that window's handlers (O0, O1, O3 — the second open made a third
//   window, #3); with no handler a window still opens (O2). With
//   `.handlesExternalEvents(preferring: ["*"], allowing: ["*"])` the existing
//   window takes it and no window opens (O4, O5). Every handler in the
//   receiving window runs once (O1, O5); their order varies between runs.

import AppKit
import SwiftUI

@MainActor func mainWindows() -> [NSWindow] {
    NSApp.windows.filter { !($0 is NSPanel) && $0.isVisible }
}

@MainActor func describe(_ tag: String) {
    guard let w = mainWindows().first else { print("  \(tag): no window"); return }
    let m = w.styleMask
    let close = w.standardWindowButton(.closeButton)
    print("  \(tag): title=\"\(w.title)\" subtitle=\"\(w.subtitle)\" representedURL=\(w.representedURL?.path ?? "nil") "
          + "edited=\(w.isDocumentEdited) fullSize=\(m.contains(.fullSizeContentView)) titled=\(m.contains(.titled)) "
          + "closable=\(m.contains(.closable)) transparentBar=\(w.titlebarAppearsTransparent) "
          + "titleVisibility=\(w.titleVisibility == .hidden ? "hidden" : "visible") "
          + "closeButton=\(close.map { "hidden:\($0.isHidden) enabled:\($0.isEnabled)" } ?? "nil") "
          + "frame=\(w.frame.size) contentView=\(w.contentView?.frame.size ?? .zero) "
          + "contentLayoutRect=\(w.contentLayoutRect)")
}

final class Model: ObservableObject {
    @Published var title = "Doc A"
    @Published var showAlert = false
    @Published var opened: [String] = []
    @Published var geometry = ""
}
let model = Model()

/// Reports the content's safe-area insets and global origin.
struct GeometryProbe: View {
    var body: some View {
        GeometryReader { proxy in
            Color.gray.onAppear {
                model.geometry = "safeArea.top=\(proxy.safeAreaInsets.top) origin(global)=\(proxy.frame(in: .global).origin) "
                    + "size=\(proxy.size)"
            }
        }
    }
}

@MainActor func after(_ seconds: Double, _ body: @escaping @MainActor () -> Void) {
    DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { MainActor.assumeIsolated { body() } }
}

@MainActor func openURL(_ path: String) {
    let delegate = NSApp.delegate
    let url = URL(fileURLWithPath: path)
    let responds = (delegate as AnyObject?)?.responds(to: #selector(NSApplicationDelegate.application(_:open:))) ?? false
    print("  delegate=\(delegate.map { String(describing: type(of: $0)) } ?? "nil") respondsToOpenURLs=\(responds)")
    let before = mainWindows().count
    delegate?.application?(NSApp, open: [url])
    after(1.0) {
        print("  after open \(url.lastPathComponent): handlers ran=\(model.opened) windows \(before) -> \(mainWindows().count)")
        exit(0)
    }
}

@MainActor func openURLThenAgain(_ first: String, _ second: String) {
    NSApp.delegate?.application?(NSApp, open: [URL(fileURLWithPath: first)])
    after(1.0) {
        print("  after first open: handlers ran=\(model.opened) windows=\(mainWindows().count) "
              + "key=\(NSApp.keyWindow.map { _ in "some" } ?? "nil") main=\(NSApp.mainWindow.map { _ in "some" } ?? "nil")")
        model.opened = []
        NSApp.delegate?.application?(NSApp, open: [URL(fileURLWithPath: second)])
        after(1.0) {
            print("  after second open: handlers ran=\(model.opened) windows=\(mainWindows().count)")
            exit(0)
        }
    }
}

@MainActor func shouldTerminate(_ tag: String) {
    let reply = NSApp.delegate?.applicationShouldTerminate?(NSApp)
    let text: String
    switch reply {
    case .terminateNow?: text = "terminateNow"
    case .terminateCancel?: text = "terminateCancel"
    case .terminateLater?: text = "terminateLater"
    case nil: text = "nil (delegate does not implement it)"
    @unknown default: text = "unknown"
    }
    let sheet = mainWindows().first?.attachedSheet
    print("  \(tag): applicationShouldTerminate -> \(text); sheet=\(sheet != nil) "
          + "sheet.preventsApplicationTerminationWhenModal=\(sheet.map { String($0.preventsApplicationTerminationWhenModal) } ?? "n/a")")
}

/// Each window's content gets the next serial at its first appearance, so a
/// handler's log entry names the window it ran in (#1 the first window).
@MainActor var nextSerial = 0
@MainActor var ranOnce = false

struct Content: View {
    @ObservedObject var m: Model
    @State private var serial = 0
    var body: some View {
        root
            .onAppear {
                nextSerial += 1
                serial = nextSerial
                print("  window #\(serial) appeared")
                // Only the first window runs the arm: a window SwiftUI opens
                // for an external event must not re-run it.
                guard !ranOnce else { return }
                ranOnce = true
                after(1.0) { run() }
            }
    }

    @ViewBuilder var root: some View {
        #if N1
        GeometryProbe().navigationTitle(m.title)
        #elseif N2
        VStack { GeometryProbe().navigationTitle("Inner") }.navigationTitle("Outer")
        #elseif N5
        HStack { GeometryProbe().navigationTitle("Left"); GeometryProbe().navigationTitle("Right") }
        #elseif N3
        GeometryProbe().navigationDocument(URL(fileURLWithPath: "/tmp/probe-doc.mcgraph"))
        #elseif N4
        GeometryProbe().navigationDocument(URL(fileURLWithPath: "/tmp/probe-doc.mcgraph")).navigationTitle("Custom")
        #elseif H1
        GeometryProbe().ignoresSafeArea()
        #elseif D0
        GeometryProbe().windowDismissBehavior(.disabled)
        #elseif T1
        GeometryProbe().alert("Save?", isPresented: $m.showAlert) { Button("Cancel", role: .cancel) {} }
        #elseif T2
        GeometryProbe().alert("Save?", isPresented: $m.showAlert) { Button("Cancel", role: .cancel) {} }
            .presentationPreventsAppTermination(true)
        #elseif T3
        GeometryProbe().alert("Save?", isPresented: $m.showAlert) { Button("Cancel", role: .cancel) {} }
            .presentationPreventsAppTermination(false)
        #elseif O5
        HStack {
            GeometryProbe().onOpenURL { url in model.opened.append("#\(serial) left:\(url.lastPathComponent)") }
            GeometryProbe().onOpenURL { url in model.opened.append("#\(serial) right:\(url.lastPathComponent)") }
        }
        .handlesExternalEvents(preferring: ["*"], allowing: ["*"])
        #elseif O4
        GeometryProbe().onOpenURL { url in model.opened.append("#\(serial):\(url.lastPathComponent)") }
            .handlesExternalEvents(preferring: ["*"], allowing: ["*"])
        #elseif O0 || O3
        GeometryProbe().onOpenURL { url in model.opened.append("#\(serial):\(url.lastPathComponent)") }
        #elseif O1
        VStack { GeometryProbe().onOpenURL { url in model.opened.append("#\(serial) inner:\(url.lastPathComponent)") } }
            .onOpenURL { url in model.opened.append("#\(serial) outer:\(url.lastPathComponent)") }
        #else
        GeometryProbe()
        #endif
    }

    func run() {
        describe("first")
        print("  content geometry: \(model.geometry)")
        #if N1
        m.title = "Doc B"
        after(0.5) { describe("after title -> Doc B"); exit(0) }
        #elseif D0 || D1
        let w = mainWindows().first!
        let should = w.delegate?.windowShouldClose?(w)
        print("  delegate=\(w.delegate.map { String(describing: type(of: $0)) } ?? "nil") windowShouldClose -> \(should.map(String.init) ?? "nil (not implemented)")")
        w.performClose(nil)
        after(0.5) { print("  after performClose: visible windows=\(mainWindows().count)"); exit(0) }
        #elseif T0
        shouldTerminate("nothing presented"); exit(0)
        #elseif T1 || T2 || T3
        m.showAlert = true
        after(0.7) { shouldTerminate("alert presented"); exit(0) }
        #elseif O0 || O1 || O2 || O4 || O5
        openURL("/tmp/probe-open.mcgraph")
        #elseif O3
        // A second window of the same group, then one open: which handler runs?
        // The second window comes from one open (as O0 shows), then a second
        // open with two windows up.
        openURLThenAgain("/tmp/probe-open.mcgraph", "/tmp/probe-open-2.mcgraph")
        #else
        exit(0)
        #endif
    }
}

@main
struct ProbeApp: App {
    init() {
        setvbuf(stdout, nil, _IOLBF, 0)
        let arms: [String: String] = [:]
        _ = arms
        #if N0
        print("=== N0 control: WindowGroup(\"Probe\"), no modifier")
        #elseif N1
        print("=== N1 .navigationTitle(\"Doc A\"), then \"Doc B\"")
        #elseif N2
        print("=== N2 nested .navigationTitle: \"Inner\" inside \"Outer\"")
        #elseif N5
        print("=== N5 sibling .navigationTitle: \"Left\" then \"Right\" in one HStack")
        #elseif N3
        print("=== N3 .navigationDocument(file URL)")
        #elseif N4
        print("=== N4 .navigationDocument(file URL) + .navigationTitle(\"Custom\")")
        #elseif H0
        print("=== H0 .windowStyle(.hiddenTitleBar)")
        #elseif H1
        print("=== H1 .windowStyle(.hiddenTitleBar), content .ignoresSafeArea()")
        #elseif D0
        print("=== D0 .windowDismissBehavior(.disabled)")
        #elseif D1
        print("=== D1 control: no dismiss modifier")
        #elseif T0
        print("=== T0 control: nothing presented")
        #elseif T1
        print("=== T1 .alert presented, no prevents modifier")
        #elseif T2
        print("=== T2 .alert presented + .presentationPreventsAppTermination(true)")
        #elseif T3
        print("=== T3 .alert presented + .presentationPreventsAppTermination(false)")
        #elseif O0
        print("=== O0 one .onOpenURL")
        #elseif O1
        print("=== O1 nested .onOpenURL (inner, outer) in one window")
        #elseif O2
        print("=== O2 no .onOpenURL anywhere")
        #elseif O3
        print("=== O3 two opens: the second with two windows of one group up, each with .onOpenURL")
        #elseif O5
        print("=== O5 sibling .onOpenURL (left, right) in one HStack + .handlesExternalEvents(\"*\")")
        #elseif O4
        print("=== O4 .onOpenURL + .handlesExternalEvents(preferring: [\"*\"], allowing: [\"*\"])")
        #endif
    }
    var body: some Scene {
        #if H0 || H1
        WindowGroup("Probe") { Content(m: model) }.windowStyle(.hiddenTitleBar)
        #else
        WindowGroup("Probe") { Content(m: model) }
        #endif
    }
}
