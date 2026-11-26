// SwiftUI probe: `.fileDialogDefaultDirectory(_:)` on an importer and an
// exporter (ruling SV-AQ, record 432). What `NSSavePanel.directoryURL` reads
// when the panel is up, for a directory above the presenter, inside it, `nil`,
// a directory that does not exist and a URL that is not a file URL.
//
// HOW TO RUN (compiled form, SA-O):
//
//   xcrun swiftc docs/probes/swiftui-file-dialog-directory.swift -o /tmp/file-dialog-directory-probe
//   for arm in 0 1 2 3 4 5 6 7; do /tmp/file-dialog-directory-probe $arm; done
//
// One arm per process: an open panel remembers the last directory it showed
// in the same process, which would colour the arms after the first.//
// OUTPUT: see the RECORDED block below (the first run's reading is in the
// record's "SwiftUI side").

// RECORDED 2026-11-26 by the SV-AQ session, macOS 27.0, Apple Swift 6.4, run
// once per arm, then once more as a whole: the same lines.
//
// READING. The panel remembers the last directory it showed in (per
// executable, across runs: the first whole run left /private/var/.../T, the
// control then read that), so "no effect" shows as the remembered directory in
// its resolved /private/var form, and an effect as the URL exactly as given.
// - D1, D3, D7: written AFTER (outside) the importer or exporter, the panel's
//   `directoryURL` is the given URL as written (/var/..., not /private/var/...).
// - D2: written on the content INSIDE the presenter it reaches nothing (the
//   remembered directory), as `fileDialogMessage` does (SV-AO, F2).
// - D4: nil leaves the panel's own choice. D5: a directory that does not exist
//   also leaves it (the panel fell back; nothing thrown). D6: an https URL
//   gives `directoryURL == nil`.
// - D7: the nearest writer wins (the nearer `project`, not `missing`).
//
// OUTPUT, verbatim (arms joined):
//
//   === D0 control
//     class=NSOpenPanel directoryURL=/private/var/folders/67/mp31lvkj38b4dbjrq20qyjlw0000gn/T
//   === D1 importer, outside
//     class=NSOpenPanel directoryURL=/var/folders/67/mp31lvkj38b4dbjrq20qyjlw0000gn/T
//   === D2 importer, inside
//     class=NSOpenPanel directoryURL=/private/var/folders/67/mp31lvkj38b4dbjrq20qyjlw0000gn/T
//   === D3 exporter, outside
//     class=NSSavePanel directoryURL=/var/folders/67/mp31lvkj38b4dbjrq20qyjlw0000gn/T
//   === D4 nil
//     class=NSOpenPanel directoryURL=/private/var/folders/67/mp31lvkj38b4dbjrq20qyjlw0000gn/T
//   === D5 nonexistent directory
//     class=NSOpenPanel directoryURL=/private/var/folders/67/mp31lvkj38b4dbjrq20qyjlw0000gn/T
//   === D6 https URL
//     class=NSOpenPanel directoryURL=nil
//   === D7 two writers
//     class=NSOpenPanel directoryURL=/var/folders/67/mp31lvkj38b4dbjrq20qyjlw0000gn/T

import AppKit
import SwiftUI
import UniformTypeIdentifiers

setvbuf(stdout, nil, _IOLBF, 0)
@MainActor func spin(_ s: Double = 0.3) { RunLoop.main.run(until: Date().addingTimeInterval(s)) }

var windows: [NSWindow] = []
@MainActor func host<V: View>(_ name: String, _ v: V) -> NSHostingView<V> {
    let w = NSWindow(contentRect: NSRect(origin: CGPoint(x: 300, y: 400), size: CGSize(width: 300, height: 200)),
                     styleMask: [.titled, .resizable], backing: .buffered, defer: false)
    w.isReleasedWhenClosed = false
    let h = NSHostingView(rootView: v)
    w.contentView = h
    w.orderFrontRegardless(); w.makeKey(); h.layoutSubtreeIfNeeded(); spin(0.4)
    print("=== \(name)"); windows.append(w)
    return h
}

final class Model: ObservableObject { @Published var shown = false }

@MainActor func panel() -> NSSavePanel? {
    NSApp.windows.first { $0.isVisible && $0.isKind(of: NSSavePanel.self) } as? NSSavePanel
}

let project = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
let missing = URL(fileURLWithPath: "/no/such/directory-\(ProcessInfo.processInfo.processIdentifier)", isDirectory: true)
let web = URL(string: "https://example.com/a")!

struct Host: View {
    @ObservedObject var m: Model
    let arm: Int
    var body: some View {
        let base = Text("File").frame(width: 200, height: 100)
        switch arm {
        case 1: // outside the importer
            base.fileImporter(isPresented: $m.shown, allowedContentTypes: [.json]) { _ in }
                .fileDialogDefaultDirectory(project)
        case 2: // inside (on the content)
            base.fileDialogDefaultDirectory(project)
                .fileImporter(isPresented: $m.shown, allowedContentTypes: [.json]) { _ in }
        case 3: // exporter, outside
            base.fileExporter(isPresented: $m.shown, item: Data("{}".utf8), contentTypes: [.json], defaultFilename: "k") { _ in }
                .fileDialogDefaultDirectory(project)
        case 4: // nil
            base.fileImporter(isPresented: $m.shown, allowedContentTypes: [.json]) { _ in }
                .fileDialogDefaultDirectory(nil)
        case 5: // a directory that does not exist
            base.fileImporter(isPresented: $m.shown, allowedContentTypes: [.json]) { _ in }
                .fileDialogDefaultDirectory(missing)
        case 6: // not a file URL
            base.fileImporter(isPresented: $m.shown, allowedContentTypes: [.json]) { _ in }
                .fileDialogDefaultDirectory(web)
        case 7: // nearest writer wins
            base.fileImporter(isPresented: $m.shown, allowedContentTypes: [.json]) { _ in }
                .fileDialogDefaultDirectory(project).fileDialogDefaultDirectory(missing)
        default: // control
            base.fileImporter(isPresented: $m.shown, allowedContentTypes: [.json]) { _ in }
        }
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.regular)
MainActor.assumeIsolated {
    let names = ["D0 control", "D1 importer, outside", "D2 importer, inside", "D3 exporter, outside", "D4 nil",
                 "D5 nonexistent directory", "D6 https URL", "D7 two writers"]
    print("project = \(project.path)")
    let arms = CommandLine.arguments.dropFirst().compactMap { Int($0) }
    for arm in arms {
        let m = Model()
        _ = host(names[arm], Host(m: m, arm: arm))
        m.shown = true; spin(1.5)
        if let p = panel() {
            print("  class=\(type(of: p)) directoryURL=\(p.directoryURL.map { "\($0.path)" } ?? "nil")")
            p.cancel(nil); spin(1.0)
        } else { print("  no panel") }
    }
    print("--- end")
}
exit(0)
