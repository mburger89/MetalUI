// SwiftUI probe: a modifier written AFTER `.onGeometryChange(for:of:action:)`
// (ruling ES-J, docs/superpowers/2026-10-31-scope-decorations-decisions.md;
// record 180). ES-J ruled that a `.padding` or `.background` after the
// modifier is outside the measured size and an `.offset` after it moves the
// reported global frame (G4a, `swiftui-key-focus.swift`); only the offset half
// had a probe arm. This file is the separating arm for the other half.
//
// HOW TO RUN (SA-O's compiled form, as `swiftui-key-focus.swift`):
//
//   xcrun swiftc docs/probes/swiftui-geometry-decorations.swift -o /tmp/gd-probe && /tmp/gd-probe
//
// THE INSTRUMENT: a 200x200 titled window hosting the view in an
// `NSHostingView`; a 50x50 blue `Color` is the measured content, a trailing
// `Spacer`s keep it at the top-left. `onGeometryChange` reports `size` (or
// `frame(in: .global)`) as `W x H` / `minX`; the log is every reported value
// in order. The first line of each arm is the initial call.
//
// ARMS AND THEIR CONTROLS.
//   D0  nothing after the modifier (control): the content's own size.
//   D1  `.padding(8)` AFTER it. D1b `.padding(8)` BEFORE it (control: the
//       padded size is reported, so padding CAN change a report).
//   D2  `.background(Color.red)` AFTER it. D2b BEFORE (control).
//   D3  `.frame(width: 100, height: 100)` AFTER it. D3b BEFORE (control).
//   D4  `.padding(8).background(Color.red)` AFTER it (ES-J's pinned spelling).
//   D5  `.offset(x: 10)` AFTER it, `frame(in: .global).minX` (G4a again).
//       D5b `.offset(x: 10)` BEFORE it (control).
//   D6  `.padding(8)` AFTER it, `frame(in: .global).minX`: the padding moves
//       the measured content in from the window edge. D6b BEFORE (control:
//       the measured view is the padded one, so its own minX is 0).
//
// RECORDED 2026-10-31, macOS 27.0.1, Apple Swift 6.4, screen LOCKED (the
// window is hosted, laid out and reports all the same; compiled form, run
// once):
//
//   D0 nothing after (control): 50x50
//   D1 .padding(8) AFTER: 50x50
//   D1b .padding(8) BEFORE (control): 66x66
//   D2 .background(red) AFTER: 50x50
//   D2b .background(red) BEFORE (control): 50x50
//   D3 .frame(100x100) AFTER: 50x50
//   D3b .frame(100x100) BEFORE (control): 100x100
//   D4 .padding(8).background(red) AFTER: 50x50
//   D5 .offset(x: 10) AFTER, minX global: x:10
//   D5b .offset(x: 10) BEFORE (control), minX global: x:0
//   D6 .padding(8) AFTER, minX global: x:8
//   D6b .padding(8) BEFORE (control), minX global: x:0
//
// RESULT.
//   A `.padding`, `.background` or `.frame` written AFTER `.onGeometryChange`
//   does not change the size the action reports (D1, D2, D3, D4: all 50x50,
//   the plain D0), where the same `.padding`/`.frame` BEFORE it does (D1b 66,
//   D3b 100): the controls separate. A `.background` before it also leaves
//   the size alone (D2b), as background never sizes. An `.offset` after it
//   moves the reported global frame (D5: 10), before it does not (D5b: 0);
//   a `.padding(8)` after it moves it too (D6: 8), before it does not (D6b).
//   ES-J's assumption holds: a modifier after the measurement is outside it.
//   (The value is reported once, already offset, because the offset is static
//   here; G4a is the state-driven form: 0 then 10.)

import SwiftUI
import AppKit

final class KeyWindow: NSWindow {
    override var isKeyWindow: Bool { true }
    override var canBecomeKey: Bool { true }
}

nonisolated(unsafe) var lines: [String] = []
@MainActor func spin(_ s: Double = 0.2) { RunLoop.main.run(until: Date().addingTimeInterval(s)) }

@MainActor func arm<V: View>(_ label: String, _ view: V) {
    lines = []
    let w = KeyWindow(contentRect: CGRect(x: 200, y: 200, width: 200, height: 200),
                      styleMask: [.titled], backing: .buffered, defer: false)
    w.isReleasedWhenClosed = false
    w.contentView = NSHostingView(rootView: view)
    w.makeKeyAndOrderFront(nil)
    spin(0.4)
    print("  \(label): \(lines.isEmpty ? "-" : lines.joined(separator: ","))")
    w.orderOut(nil)
    w.contentView = nil
}

func size(_ v: CGSize) { lines.append("\(Int(v.width))x\(Int(v.height))") }
func minX(_ v: CGFloat) { lines.append("x:\(Int(v))") }

struct Top<C: View>: View {
    let content: C
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) { content; Spacer(minLength: 0) }
            Spacer(minLength: 0)
        }
    }
}

let tile = Color.blue.frame(width: 50, height: 50)

@MainActor func run() {
    print("--- D: a modifier after onGeometryChange")
    arm("D0 nothing after (control)", Top(content: tile.onGeometryChange(for: CGSize.self, of: { $0.size }, action: size)))
    arm("D1 .padding(8) AFTER", Top(content: tile.onGeometryChange(for: CGSize.self, of: { $0.size }, action: size).padding(8)))
    arm("D1b .padding(8) BEFORE (control)", Top(content: tile.padding(8).onGeometryChange(for: CGSize.self, of: { $0.size }, action: size)))
    arm("D2 .background(red) AFTER", Top(content: tile.onGeometryChange(for: CGSize.self, of: { $0.size }, action: size).background(Color.red)))
    arm("D2b .background(red) BEFORE (control)", Top(content: tile.background(Color.red).onGeometryChange(for: CGSize.self, of: { $0.size }, action: size)))
    arm("D3 .frame(100x100) AFTER", Top(content: tile.onGeometryChange(for: CGSize.self, of: { $0.size }, action: size).frame(width: 100, height: 100)))
    arm("D3b .frame(100x100) BEFORE (control)", Top(content: tile.frame(width: 100, height: 100).onGeometryChange(for: CGSize.self, of: { $0.size }, action: size)))
    arm("D4 .padding(8).background(red) AFTER", Top(content: tile.onGeometryChange(for: CGSize.self, of: { $0.size }, action: size).padding(8).background(Color.red)))
    arm("D5 .offset(x: 10) AFTER, minX global", Top(content: tile.onGeometryChange(for: CGFloat.self, of: { $0.frame(in: .global).minX }, action: minX).offset(x: 10)))
    arm("D5b .offset(x: 10) BEFORE (control), minX global", Top(content: tile.offset(x: 10).onGeometryChange(for: CGFloat.self, of: { $0.frame(in: .global).minX }, action: minX)))
    arm("D6 .padding(8) AFTER, minX global", Top(content: tile.onGeometryChange(for: CGFloat.self, of: { $0.frame(in: .global).minX }, action: minX).padding(8)))
    arm("D6b .padding(8) BEFORE (control), minX global", Top(content: tile.padding(8).onGeometryChange(for: CGFloat.self, of: { $0.frame(in: .global).minX }, action: minX)))
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
MainActor.assumeIsolated { run() }
