// SwiftUI probe: window sizing — `.defaultSize(width:height:)` and
// `.windowResizability(_:)` on a SwiftUI `App` scene (user request 2026-10-02,
// platform services; not a plan task). Companion of
// swiftui-platform-services.swift. Evidence for rulings SV-… in
// docs/superpowers/2026-10-04-platform-services-decisions.md.
//
// HOW TO RUN (compiled form, SA-O; an `App` needs -parse-as-library). One
// build per arm, chosen by a -D flag:
//
//   for arm in W0 W1 W2 W3 W4 W5; do
//     xcrun swiftc -parse-as-library -D $arm docs/probes/swiftui-window-sizing.swift -o /tmp/ws-$arm
//     defaults delete ws-$arm 2>/dev/null; /tmp/ws-$arm -ApplePersistenceIgnoreState YES
//   done
//
// THE `defaults delete` IS LOAD-BEARING: a SwiftUI WindowGroup autosaves its
// frame ("NSWindow Frame SwiftUI.WindowGroup<main.Content>-1-AppWindow-1" in
// the binary's defaults domain), so a second run restores the 2000-wide frame
// the first run's last resize left and every "first" content size reads
// 2000 x 1290 — measured, then cleared.
//
// ARMS. Content: `Color.gray.frame(minWidth: 400, idealWidth: 500, maxWidth: 900,
// minHeight: 300, idealHeight: 350, maxHeight: 600)` unless the arm says otherwise.
// - W0 control: no scene modifier (the default resizability, `.automatic`).
// - W1 `.windowResizability(.contentMinSize)`.
// - W2 `.windowResizability(.contentSize)`.
// - W3 `.defaultSize(width: 1000, height: 700)` alone (default resizability).
// - W4 `.defaultSize(width: 200, height: 100)` + `.contentMinSize`: a default
//   below the content minimum.
// - W5 `.contentMinSize` over content whose minimum CHANGES at runtime
//   (`minWidth` 400 → 700 after the first report), read again.
// Each prints the first window's contentMinSize, contentMaxSize, content size,
// styleMask resizable bit, then (W5) the same after the change.
//
// RECORDED 2026-10-03 by the platform-services design session, macOS 27.0,
// Apple Swift 6.4, screen LOCKED (the app inactive). Each arm compiled and run
// twice from clean defaults: stdout byte-identical, exit 0. The content heights read 32 more than
// the content's minimum (332 for minHeight 300): a SwiftUI window's content
// view runs under the title bar (full-size content) and the minimum includes
// that inset.
//
// OUTPUT, verbatim:
//
//   === W0 control: no scene modifier
//     first: contentMinSize=(400.0, 332.0) contentMaxSize=(1.7976931348623157e+308, 1.7976931348623157e+308) content=(900.0, 450.0) resizable=true minSize=(400.0, 332.0) maxSize=(1.7976931348623157e+308, 1.7976931348623157e+308)
//     after setContentSize(100x100): contentMinSize=(400.0, 332.0) contentMaxSize=(1.7976931348623157e+308, 1.7976931348623157e+308) content=(400.0, 332.0) resizable=true minSize=(400.0, 332.0) maxSize=(1.7976931348623157e+308, 1.7976931348623157e+308)
//     after setContentSize(2000x2000): contentMinSize=(400.0, 332.0) contentMaxSize=(1.7976931348623157e+308, 1.7976931348623157e+308) content=(2000.0, 1290.0) resizable=true minSize=(400.0, 332.0) maxSize=(1.7976931348623157e+308, 1.7976931348623157e+308)
//   === W1 .windowResizability(.contentMinSize)
//     first: contentMinSize=(400.0, 332.0) contentMaxSize=(1.7976931348623157e+308, 1.7976931348623157e+308) content=(900.0, 450.0) resizable=true minSize=(400.0, 332.0) maxSize=(1.7976931348623157e+308, 1.7976931348623157e+308)
//     after setContentSize(100x100): contentMinSize=(400.0, 332.0) contentMaxSize=(1.7976931348623157e+308, 1.7976931348623157e+308) content=(400.0, 332.0) resizable=true minSize=(400.0, 332.0) maxSize=(1.7976931348623157e+308, 1.7976931348623157e+308)
//     after setContentSize(2000x2000): contentMinSize=(400.0, 332.0) contentMaxSize=(1.7976931348623157e+308, 1.7976931348623157e+308) content=(2000.0, 1290.0) resizable=true minSize=(400.0, 332.0) maxSize=(1.7976931348623157e+308, 1.7976931348623157e+308)
//   === W2 .windowResizability(.contentSize)
//     first: contentMinSize=(400.0, 332.0) contentMaxSize=(900.0, 632.0) content=(900.0, 450.0) resizable=true minSize=(400.0, 332.0) maxSize=(900.0, 632.0)
//     after setContentSize(100x100): contentMinSize=(400.0, 332.0) contentMaxSize=(900.0, 632.0) content=(400.0, 332.0) resizable=true minSize=(400.0, 332.0) maxSize=(900.0, 632.0)
//     after setContentSize(2000x2000): contentMinSize=(400.0, 332.0) contentMaxSize=(900.0, 632.0) content=(900.0, 632.0) resizable=true minSize=(400.0, 332.0) maxSize=(900.0, 632.0)
//   === W3 .defaultSize(width: 1000, height: 700)
//     first: contentMinSize=(400.0, 332.0) contentMaxSize=(1.7976931348623157e+308, 1.7976931348623157e+308) content=(1000.0, 700.0) resizable=true minSize=(400.0, 332.0) maxSize=(1.7976931348623157e+308, 1.7976931348623157e+308)
//     after setContentSize(100x100): contentMinSize=(400.0, 332.0) contentMaxSize=(1.7976931348623157e+308, 1.7976931348623157e+308) content=(400.0, 332.0) resizable=true minSize=(400.0, 332.0) maxSize=(1.7976931348623157e+308, 1.7976931348623157e+308)
//     after setContentSize(2000x2000): contentMinSize=(400.0, 332.0) contentMaxSize=(1.7976931348623157e+308, 1.7976931348623157e+308) content=(2000.0, 1290.0) resizable=true minSize=(400.0, 332.0) maxSize=(1.7976931348623157e+308, 1.7976931348623157e+308)
//   === W4 .defaultSize(width: 200, height: 100) + .contentMinSize
//     first: contentMinSize=(400.0, 332.0) contentMaxSize=(1.7976931348623157e+308, 1.7976931348623157e+308) content=(400.0, 332.0) resizable=true minSize=(400.0, 332.0) maxSize=(1.7976931348623157e+308, 1.7976931348623157e+308)
//     after setContentSize(100x100): contentMinSize=(400.0, 332.0) contentMaxSize=(1.7976931348623157e+308, 1.7976931348623157e+308) content=(400.0, 332.0) resizable=true minSize=(400.0, 332.0) maxSize=(1.7976931348623157e+308, 1.7976931348623157e+308)
//     after setContentSize(2000x2000): contentMinSize=(400.0, 332.0) contentMaxSize=(1.7976931348623157e+308, 1.7976931348623157e+308) content=(2000.0, 1290.0) resizable=true minSize=(400.0, 332.0) maxSize=(1.7976931348623157e+308, 1.7976931348623157e+308)
//   === W5 .contentMinSize, content minWidth 400 -> 700 at runtime
//     first: contentMinSize=(400.0, 332.0) contentMaxSize=(1.7976931348623157e+308, 1.7976931348623157e+308) content=(900.0, 450.0) resizable=true minSize=(400.0, 332.0) maxSize=(1.7976931348623157e+308, 1.7976931348623157e+308)
//     after minWidth 400 -> 700: contentMinSize=(700.0, 332.0) contentMaxSize=(1.7976931348623157e+308, 1.7976931348623157e+308) content=(900.0, 450.0) resizable=true minSize=(700.0, 332.0) maxSize=(1.7976931348623157e+308, 1.7976931348623157e+308)
//
// READING: W0 = W1 — on macOS the default resizability IS .contentMinSize:
// the window's contentMinSize is the content's minimum (400 x 300 + the 32-pt
// title-bar inset), its maximum unbounded. W2 .contentSize adds the content's
// maximum as contentMaxSize (900 x 600 + 32). AppKit enforces both on a
// programmatic resize (setContentSize clamps). W3: defaultSize is the initial
// content size. W4: a default below the content minimum opens AT the minimum.
// W5: the minimum follows the content when it changes at runtime. W0's first
// content (900 x 450) is SwiftUI's own pick for a window with no defaultSize.

import AppKit
import SwiftUI



final class Model: ObservableObject { @Published var minWidth: CGFloat = 400 }
let model = Model()

@MainActor func line(_ tag: String) {
    guard let w = NSApp.windows.first(where: { $0.isVisible && !($0 is NSPanel) }) else { print("  \(tag): no window"); return }
    let c = w.contentRect(forFrameRect: w.frame).size
    print("  \(tag): contentMinSize=\(w.contentMinSize) contentMaxSize=\(w.contentMaxSize) "
          + "content=\(c) resizable=\(w.styleMask.contains(.resizable)) minSize=\(w.minSize) maxSize=\(w.maxSize)")
}

struct Content: View {
    @ObservedObject var m: Model
    var body: some View {
        Color.gray
            .frame(minWidth: m.minWidth, idealWidth: 500, maxWidth: 900, minHeight: 300, idealHeight: 350, maxHeight: 600)
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    MainActor.assumeIsolated {
                        line("first")
                        #if W5
                        m.minWidth = 700
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                            MainActor.assumeIsolated { line("after minWidth 400 -> 700"); exit(0) }
                        }
                        #else
                        // Try to resize below and above the limits programmatically.
                        if let w = NSApp.windows.first(where: { $0.isVisible }) {
                            w.setContentSize(NSSize(width: 100, height: 100))
                            RunLoop.main.run(until: Date().addingTimeInterval(0.3))
                            line("after setContentSize(100x100)")
                            w.setContentSize(NSSize(width: 2000, height: 2000))
                            RunLoop.main.run(until: Date().addingTimeInterval(0.3))
                            line("after setContentSize(2000x2000)")
                        }
                        exit(0)
                        #endif
                    }
                }
            }
    }
}

@main
struct ProbeApp: App {
    init() {
        setvbuf(stdout, nil, _IOLBF, 0)
        #if W0
        print("=== W0 control: no scene modifier")
        #elseif W1
        print("=== W1 .windowResizability(.contentMinSize)")
        #elseif W2
        print("=== W2 .windowResizability(.contentSize)")
        #elseif W3
        print("=== W3 .defaultSize(width: 1000, height: 700)")
        #elseif W4
        print("=== W4 .defaultSize(width: 200, height: 100) + .contentMinSize")
        #elseif W5
        print("=== W5 .contentMinSize, content minWidth 400 -> 700 at runtime")
        #endif
    }
    var body: some Scene {
        #if W1 || W5
        WindowGroup("Probe") { Content(m: model) }.windowResizability(.contentMinSize)
        #elseif W2
        WindowGroup("Probe") { Content(m: model) }.windowResizability(.contentSize)
        #elseif W3
        WindowGroup("Probe") { Content(m: model) }.defaultSize(width: 1000, height: 700)
        #elseif W4
        WindowGroup("Probe") { Content(m: model) }.defaultSize(width: 200, height: 100).windowResizability(.contentMinSize)
        #else
        WindowGroup("Probe") { Content(m: model) }
        #endif
    }
}
