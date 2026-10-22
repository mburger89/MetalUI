// SwiftUI probe: presentationBackground on a macOS popover and windowBackgroundDragBehavior (item BG, round 2
// item 7; rulings BG-A..BG-J in docs/superpowers/2026-10-22-presentation-extras-decisions.md; spec
// docs/superpowers/specs/2026-10-22-presentation-extras-design.md). Compile-time arms and the PointerStyle.shape
// census: swiftui-presentation-extras-typecheck.sh. Harness lines are swiftui-overlays-coords.swift's (B arms).
//
// HOW TO RUN (compiled form, SA-O):
//   xcrun swiftc docs/probes/swiftui-presentation-extras.swift -o /tmp/pe-probe
//   /tmp/pe-probe 2>/dev/null                      # the B arms
//   for d in none automatic enabled disabled hidden enabledHidden enabledLabel enabledButton; do
//     PROBE_D=$d /tmp/pe-probe 2>&1 | grep -E "^===|delta|Warning: Window move"; done     # the D arms, one process each
//
// THE INSTRUMENTS. B: a `.popover` on a gray anchor; the popover's window frame view read through cacheDisplay at
// four points of the 146x76 panel (content is 120x50, so left/right/top points lie in the 13 pt padding ring;
// "content centre" is under the Text). B0 is the control (no modifier); B2 is overlays-coords' B2 (the call reaches
// the panel); B4 puts the modifier on the DECLARER (separating arm: it must read as B0). The ring pixels of an
// unmodified popover vary with the window behind (glass), so a reading is compared with B0's in the same run.
// D: a real SwiftUI `App` (one process per arm: an App runs once) with a `WindowGroup` scene; the window's
// `isMovableByWindowBackground` and style flags are read, then a synthesized press-drag (left down at the content
// background, three drags, up) goes through `NSWindow.sendEvent`. A real window move shows as AppKit's stderr line
// "Warning: Window move completed without beginning" (the W arms' instrument, swiftui-window-drag.swift: SwiftUI never
// calls performDrag on a probe window, so the frame origin does not move). Positive control: the `enabled` arm;
// separating arms: `none`, `automatic`, `disabled`, `hidden` (title bar hidden, no behavior) read no line.
//
// RECORDED 2026-10-22 by the BG design session, macOS 27.0, Apple Swift 6.4 (swiftlang-6.4.0.33.1), screen LOCKED
// (lock probe: CGSSessionScreenIsLocked = 1, displayAsleep main: 1). B arms run twice, stdout byte-identical (65 lines);
// D arms run twice, the same lines.
//   B0 control: ring pixels left (0.14,0.09,0.55) right (0.52,0.97,0.62) top (0.30,0.56,0.18) (the desktop through glass),
//      content centre (0.86,0.86,0.86); NSPopoverFrame > NSGlassView > ContentHolderView, _NSCoreHostingView; PopoverHostingView.
//   B2 .presentationBackground(.red): left = right = top = (0.95,0.43,0.38), centre (0.99,0.90,0.90): one uniform fill over
//      the whole panel, ring included.
//   B3 presentationBackground { Color.green }: left = right = top = (0.50,0.86,0.52): the content spelling fills the panel too.
//   B4 modifier on the declarer: every pixel equal to B0: no effect outside the popover's content.
//   B5 LinearGradient red->blue leading->trailing: left (0.93,0.44,0.41) right (0.35,0.66,0.96) top (0.72,0.60,0.72): the
//      gradient spans the panel.
//   B6 .ultraThinMaterial: pixels differ slightly from B0 (left (0.17,0.13,0.42)), the view tree is B0's: no change of chrome.
//   B7 inner .red, outer .blue: left = right = top = red's (0.95,0.43,0.38): the INNERMOST (first reported) wins.
//   B8 alignment .leading, content HStack red 30 | blue 30: left ring red (0.95,0.43,0.38), right and top equal B0's: the
//      content is proposed the panel and placed by the alignment, not stretched (B3's Color fills because it is flexible).
//   B9 .red.opacity(0.5): translucent over the glass (left (0.59,0.25,0.47)).
//   D none/automatic/disabled/hidden: no "Warning: Window move completed without beginning" line;
//   D enabled, enabledHidden, enabledLabel (press on a Text), enabledButton (press on a Button's centre): the line is read.
//   In every arm isMovableByWindowBackground = false: SwiftUI does not use AppKit's flag.
// NOT SEPARATED (carried, human check BG4): enabledButton reads the line too, but the press may have landed on the button
// and begun a window move after a failed track; the probe cannot tell a button that fired from one that did not.
import AppKit
import Foundation
import SwiftUI

setvbuf(stdout, nil, _IOLBF, 0)
@MainActor func spin(_ s: Double = 0.3) { RunLoop.main.run(until: Date().addingTimeInterval(s)) }

final class Model: ObservableObject {
    @Published var shown = false
    @Published var anchor: CGRect = .zero
}
final class Frames: @unchecked Sendable { var lines: [String: CGRect] = [:] }
let frames = Frames()

var windows: [NSWindow] = []
@MainActor func host<V: View>(_ name: String, _ v: V, size: CGSize = CGSize(width: 300, height: 200),
                              origin: CGPoint = CGPoint(x: 400, y: 500)) -> NSHostingView<V> {
    let w = NSWindow(contentRect: NSRect(origin: origin, size: size),
                     styleMask: [.titled], backing: .buffered, defer: false)
    w.isReleasedWhenClosed = false
    let h = NSHostingView(rootView: v)
    w.contentView = h
    w.orderFrontRegardless(); h.layoutSubtreeIfNeeded(); spin(0.4)
    print("=== \(name)"); windows.append(w)
    return h
}
func r(_ x: CGFloat) -> String { x == x.rounded() ? "\(Int(x))" : String(format: "%.1f", x) }
func rect(_ f: CGRect) -> String { "(\(r(f.minX)),\(r(f.minY)),\(r(f.width))x\(r(f.height)))" }

// ---------------------------------------------------------------- A, B
@MainActor func popoverWindow() -> NSWindow? {
    NSApp.windows.first { "\(type(of: $0))".contains("Popover") && $0.isVisible }
}

@MainActor func closePopover(_ main: NSWindow, _ pw: NSWindow?) {
    pw?.orderOut(nil); main.orderOut(nil)
}

@MainActor func viewTree(_ v: NSView, _ d: Int = 0, maxDepth: Int = 6) {
    var s = String(repeating: "  ", count: d + 2) + "\(type(of: v))".components(separatedBy: "<").first!
    if let e = v as? NSVisualEffectView {
        s += " [effect state=\(e.state.rawValue) material=\(e.material.rawValue) blending=\(e.blendingMode.rawValue) alpha=\(r(e.alphaValue)) hidden=\(e.isHidden)]"
    }
    if v.isHidden { s += " hidden" }
    if v.alphaValue != 1 { s += " alpha=\(r(v.alphaValue))" }
    s += " \(rect(v.frame))"
    print(s)
    if d < maxDepth { for k in v.subviews { viewTree(k, d + 1, maxDepth: maxDepth) } }
}

@MainActor func pixel(_ pw: NSWindow, atTopLeft p: CGPoint) -> String {
    guard let frameView = pw.contentView?.superview ?? pw.contentView else { return "no view" }
    let b = frameView.bounds
    guard let rep = frameView.bitmapImageRepForCachingDisplay(in: b) else { return "no rep" }
    frameView.cacheDisplay(in: b, to: rep)
    let px = Int(p.x * CGFloat(rep.pixelsWide) / b.width), py = Int(p.y * CGFloat(rep.pixelsHigh) / b.height)
    guard let c = rep.colorAt(x: px, y: py)?.usingColorSpace(.sRGB) else { return "no colour" }
    return String(format: "rgba(%.2f,%.2f,%.2f,%.2f)", c.redComponent, c.greenComponent, c.blueComponent, c.alphaComponent)
}


// ---------------------------------------------------------------- B (popover backgrounds)
struct PopHost: View {
    @ObservedObject var m: Model
    let arm: String
    var body: some View {
        if arm == "B4" {
            // the modifier on the DECLARER, outside the popover's content (separating arm for B2/B3)
            Color.gray.frame(width: 100, height: 40)
                .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .global) }) { m.anchor = $0 }
                .popover(isPresented: $m.shown) { Text("Popover").frame(width: 120, height: 50) }
                .presentationBackground(.red)
                .frame(width: 300, height: 200)
        } else {
            Color.gray.frame(width: 100, height: 40)
                .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .global) }) { m.anchor = $0 }
                .popover(isPresented: $m.shown) { content }
                .frame(width: 300, height: 200)
        }
    }
    @ViewBuilder var content: some View {
        let t = Text("Popover").frame(width: 120, height: 50)
        switch arm {
        case "B0": t
        case "B2": t.presentationBackground(.red)
        case "B3": t.presentationBackground { Color.green }
        case "B5": t.presentationBackground(LinearGradient(colors: [.red, .blue], startPoint: .leading, endPoint: .trailing))
        case "B6": t.presentationBackground(.ultraThinMaterial)
        case "B7": t.presentationBackground(.red).presentationBackground(.blue)   // outer written after inner
        case "B8": t.presentationBackground(alignment: .leading) { HStack(spacing: 0) { Color.red.frame(width: 30); Color.blue.frame(width: 30) } }
        case "B9": t.presentationBackground(.red.opacity(0.5))
        default: t
        }
    }
}

@MainActor func showPopover(_ name: String, arm: String) -> (NSWindow, NSWindow?) {
    let m = Model()
    let h = host(name, PopHost(m: m, arm: arm))
    m.shown = true; spin(0.9)
    let main = h.window!
    guard let pw = popoverWindow() else { print("  popover window: none"); return (main, nil) }
    print("  popover window size \(r(pw.frame.width))x\(r(pw.frame.height))")
    return (main, pw)
}

enum DArm { static var name: String? { ProcessInfo.processInfo.environment["PROBE_D"] } }

// ---------------------------------------------------------------- D (window background drag), a real App scene
struct AppAutomatic: App { var body: some Scene { WindowGroup { Color.gray.frame(width: 300, height: 200) }.windowBackgroundDragBehavior(.automatic) } }
struct AppEnabled: App { var body: some Scene { WindowGroup { Color.gray.frame(width: 300, height: 200) }.windowBackgroundDragBehavior(.enabled) } }
struct AppDisabled: App { var body: some Scene { WindowGroup { Color.gray.frame(width: 300, height: 200) }.windowBackgroundDragBehavior(.disabled) } }
struct AppEnabledHidden: App { var body: some Scene { WindowGroup { Color.gray.frame(width: 300, height: 200) }.windowBackgroundDragBehavior(.enabled).windowStyle(.hiddenTitleBar) } }
struct AppHidden: App { var body: some Scene { WindowGroup { Color.gray.frame(width: 300, height: 200) }.windowStyle(.hiddenTitleBar) } }
struct Split: View { var body: some View { VStack(spacing: 0) { Text("label").frame(maxWidth: .infinity, maxHeight: .infinity).background(Color.gray); Button("button") {}.frame(maxWidth: .infinity, maxHeight: .infinity) }.frame(width: 300, height: 200) } }
struct AppEnabledLabel: App { var body: some Scene { WindowGroup { Split() }.windowBackgroundDragBehavior(.enabled) } }
struct AppNone: App { var body: some Scene { WindowGroup { Color.gray.frame(width: 300, height: 200) } } }

if let d = DArm.name {
    // Compiled-form SwiftUI App, one process per arm (an App can run once).
    struct Wrapper {
        @MainActor static func go(_ d: String) {
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                for w in NSApp.windows where w.isVisible && w.contentView != nil && !"\(type(of: w))".contains("Popover") {
                    print("  \(d): isMovableByWindowBackground=\(w.isMovableByWindowBackground) titled=\(w.styleMask.contains(.titled)) fullSizeContent=\(w.styleMask.contains(.fullSizeContentView)) titlebarAppearsTransparent=\(w.titlebarAppearsTransparent) titleVisibility=\(w.titleVisibility.rawValue) class=\(type(of: w))")
                }
                // A press-drag on the content background: a window move shows as a changed frame origin,
                // or as AppKit's own diagnostic on stderr (performDrag's nested loop needs live events).
                if let w = NSApp.windows.first(where: { $0.isVisible && $0.contentView != nil }) {
                    let before = w.frame.origin
                    func ev(_ t: NSEvent.EventType, _ p: CGPoint, _ n: Int) -> NSEvent {
                        NSEvent.mouseEvent(with: t, location: p, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                           windowNumber: w.windowNumber, context: nil, eventNumber: n, clickCount: 1, pressure: 1)!
                    }
                    FileHandle.standardError.write(Data("ARM-D \(d) press\n".utf8))
                    w.sendEvent(ev(.leftMouseDown, CGPoint(x: 150, y: d == "enabledButton" ? 50 : (d == "enabledLabel" ? 160 : 100)), 1))
                    for i in 1...3 { w.sendEvent(ev(.leftMouseDragged, CGPoint(x: 150 + 20 * CGFloat(i), y: 100 - 10 * CGFloat(i)), 1)); try? await Task.sleep(nanoseconds: 100_000_000) }
                    w.sendEvent(ev(.leftMouseUp, CGPoint(x: 210, y: 70), 1))
                    try? await Task.sleep(nanoseconds: 300_000_000)
                    print("  \(d): frame origin delta after background drag = (\(r(w.frame.origin.x - before.x)), \(r(w.frame.origin.y - before.y)))")
                }
                exit(0)
            }
        }
    }
    print("=== D \(d)")
    MainActor.assumeIsolated { Wrapper.go(d) }
    switch d {
    case "automatic": AppAutomatic.main()
    case "enabled": AppEnabled.main()
    case "disabled": AppDisabled.main()
    case "enabledHidden": AppEnabledHidden.main()
    case "hidden": AppHidden.main()
    case "enabledLabel", "enabledButton": AppEnabledLabel.main()
    default: AppNone.main()
    }
} else {
MainActor.assumeIsolated {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    print("--- B: popover presentationBackground")
    for (name, arm) in [("B0 control (none)", "B0"), ("B2 .presentationBackground(.red) (control from overlays-coords)", "B2"),
                        ("B3 .presentationBackground { Color.green } (content spelling)", "B3"),
                        ("B4 .presentationBackground(.red) on the DECLARER (separating)", "B4"),
                        ("B5 linear gradient leading->trailing", "B5"),
                        ("B6 .ultraThinMaterial", "B6"),
                        ("B7 inner .red, outer .blue (which wins)", "B7"),
                        ("B8 alignment .leading, content red|blue 30pt each", "B8"),
                        ("B9 .red.opacity(0.5)", "B9")] {
        let (main, pw) = showPopover(name, arm: arm)
        if let pw {
            for (label, p) in [("left ring", CGPoint(x: 6, y: pw.frame.height / 2)),
                               ("right ring", CGPoint(x: pw.frame.width - 6, y: pw.frame.height / 2)),
                               ("top ring", CGPoint(x: pw.frame.width / 2, y: 6)),
                               ("content centre", CGPoint(x: pw.frame.width / 2, y: pw.frame.height / 2))] {
                print("  pixel \(label): \(pixel(pw, atTopLeft: p))")
            }
            if name.hasPrefix("B6") || name.hasPrefix("B0") { if let fv = pw.contentView?.superview { viewTree(fv) } }
        }
        closePopover(main, pw); spin(0.3)
    }
    exit(0)
}
}
