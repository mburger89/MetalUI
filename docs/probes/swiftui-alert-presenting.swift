// SwiftUI probe: `.alert(_:isPresented:presenting:actions:message:)` and the
// Return key on an alert whose default button carries no key equivalent.
// Evidence for rulings SV-X and SV-Y in
// docs/superpowers/2026-10-04-platform-services-decisions.md (the critic pass
// over the platform-services design; the companion of
// swiftui-platform-services.swift, whose A arms it extends).
//
// HOW TO RUN (compiled form, SA-O):
//
//   xcrun swiftc docs/probes/swiftui-alert-presenting.swift -o /tmp/alert-presenting
//   /tmp/alert-presenting
//
// Headless, as swiftui-platform-services.swift: synthesized key events go to
// the sheet through two instruments (I1 `sendEvent`, I2
// `performKeyEquivalent`), buttons are driven by `performClick`.
//
// POSITIVE CONTROLS AND SEPARATING ARMS. R0 (data non-nil) against R1 (data
// nil, isPresented true). K0 (A2's shape: the first plain button carries
// "\r") is the positive control for the Return instrument against K1 (A5's
// shape) and K2 (A3's shape): if K0 runs under an instrument and K1/K2 do not,
// the instrument delivers Return and the difference is the alert's. K3 (a
// plain button + a cancel button, two side by side) is the shape A1-A5 left
// unmeasured.
//
// RECORDED 2026-10-03 by the platform-services critic pass, macOS 27.0, Apple
// Swift 6.4, screen LOCKED (CGSSessionScreenIsLocked = 1, displayAsleep main:
// 1; the app never became active, no key window). Compiled form, run twice:
// output byte-identical (38 lines including the exit line), stderr empty.
//
// OUTPUT, verbatim:
//
//   --- R: alert presenting:
//   === R0 control: data "k1", isPresented true
//     sheet=_NSAlertPanel texts=["Delete?", "Item k1."] buttons: "Cancel" key="\u{1B}" | "Delete k1" key=""
//     click Delete -> log ["delete k1"] isPresented=false sheet=false
//   === R1 fresh: data nil, isPresented true
//     R1 data nil, isPresented true -> sheet=true isPresented=true log []
//     R1 sheet texts=["Delete?"] buttons: "OK" key=""
//     R2 then data "k2" -> sheet=true texts=["Delete?"] buttons: "OK" key=""
//     R3 then data nil while shown -> sheet=true isPresented=true log []
//     R3 sheet texts=["Delete?"] buttons: "OK" key=""
//     R4 click first -> log [] isPresented=false sheet=false
//   --- K: Return on the alert (I1 sendEvent, I2 performKeyEquivalent)
//   === K0 I1
//     buttons: "A" key="\r" | "B" key="" | "C" key="" default=A key=false
//     Return -> log ["A"] isPresented=false sheet=false
//   === K0 I2
//     buttons: "A" key="\r" | "B" key="" | "C" key="" default=A key=false
//     Return -> log ["A"] isPresented=false sheet=false
//   === K1 I1
//     buttons: "Save" key="" | "Discard" key="" | "Cancel" key="\u{1B}" default=Save key=false
//     Return -> log [] isPresented=true sheet=true
//   === K1 I2
//     buttons: "Save" key="" | "Discard" key="" | "Cancel" key="\u{1B}" default=Save key=false
//     Return -> log [] isPresented=true sheet=true
//   === K2 I1
//     buttons: "OK" key="" default=OK key=false
//     Return -> log [] isPresented=true sheet=true
//   === K2 I2
//     buttons: "OK" key="" default=OK key=false
//     Return -> log [] isPresented=true sheet=true
//   === K3 I1
//     buttons: "Cancel" key="\u{1B}" | "Save" key="\r" default=Save key=false
//     Return -> log ["save"] isPresented=false sheet=false
//   === K3 I2
//     buttons: "Cancel" key="\u{1B}" | "Save" key="\r" default=Save key=false
//     Return -> log ["save"] isPresented=false sheet=false
//   --- end
//   exit 0
//
// READING:
// - R0/R1 separate: `presenting: nil` with isPresented true STILL presents
//   (fresh window, no history) — the title only, no message, and one "OK"
//   (A3's shape: the actions and message closures are not run). Clicking OK
//   writes isPresented = false and runs nothing (R4). Data arriving while the
//   alert is up does not re-evaluate it (R2: still "OK"), nor does data going
//   nil (R3). So "shown only while data is non-nil" is refuted on macOS 27.
// - K0 vs K1/K2/K3: both instruments deliver Return with the sheet not key
//   (K0 runs "A" under I1 and I2; K3 runs "Save"), so the instrument is not
//   what stops K1/K2. SwiftUI gives the first plain (role-less) button the
//   "\r" key equivalent when the declared actions hold NO destructive button
//   (A2/K0 three plain; K3 plain + cancel), and NO button Return when one is
//   destructive (A1, A5/K1: Save key "" although defaultButtonCell is Save) or
//   when the only button is the synthesized "OK" (A3/K2). Measured with no key
//   window; whether an ACTIVE app's key sheet routes Return to
//   defaultButtonCell anyway (K1, K2) is human check U4.

import AppKit
import SwiftUI

setvbuf(stdout, nil, _IOLBF, 0)
@MainActor func spin(_ s: Double = 0.3) { RunLoop.main.run(until: Date().addingTimeInterval(s)) }
final class Log: @unchecked Sendable { var lines: [String] = [] }
let log = Log()
final class Model: ObservableObject {
    @Published var shown = false
    @Published var data: String? = nil
}
var windows: [NSWindow] = []
@MainActor func host<V: View>(_ name: String, _ v: V) -> NSWindow {
    let w = NSWindow(contentRect: NSRect(x: 300, y: 400, width: 300, height: 200),
                     styleMask: [.titled, .resizable], backing: .buffered, defer: false)
    w.isReleasedWhenClosed = false
    let h = NSHostingView(rootView: v)
    w.contentView = h
    w.orderFrontRegardless(); w.makeKey(); h.layoutSubtreeIfNeeded(); spin(0.4)
    print("=== \(name)"); windows.append(w)
    return w
}
@MainActor func allViews(_ v: NSView) -> [NSView] { [v] + v.subviews.flatMap(allViews) }
@MainActor func buttons(in w: NSWindow) -> [NSButton] {
    guard let root = w.contentView?.superview ?? w.contentView else { return [] }
    return allViews(root).compactMap { $0 as? NSButton }
        .filter { !$0.isHidden && !$0.title.isEmpty && $0.bezelStyle != .disclosure }
        .sorted { $0.convert($0.bounds, to: nil).minX < $1.convert($1.bounds, to: nil).minX }
}
@MainActor func texts(_ w: NSWindow) -> String {
    guard let root = w.contentView else { return "" }
    return allViews(root).compactMap { ($0 as? NSTextField)?.stringValue }.filter { !$0.isEmpty }
        .map { "\"\($0)\"" }.joined(separator: ", ")
}
@MainActor func buttonsLine(_ w: NSWindow) -> String {
    buttons(in: w).map { "\"\($0.title)\" key=\($0.keyEquivalent.debugDescription)" }.joined(separator: " | ")
}
@MainActor func returnKey(_ w: NSWindow) -> NSEvent {
    NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                     windowNumber: w.windowNumber, context: nil, characters: "\r",
                     charactersIgnoringModifiers: "\r", isARepeat: false, keyCode: 36)!
}

struct PresentingHost: View {
    @ObservedObject var m: Model
    var body: some View {
        Text("Host").frame(width: 300, height: 200)
            .alert("Delete?", isPresented: $m.shown, presenting: m.data) { d in
                Button("Delete \(d)", role: .destructive) { log.lines.append("delete \(d)") }
                Button("Cancel", role: .cancel) { log.lines.append("cancel") }
            } message: { d in Text("Item \(d).") }
    }
}
struct KeyHost: View {
    @ObservedObject var m: Model
    let arm: Int
    var body: some View {
        let base = Text("Keys").frame(width: 300, height: 200)
        switch arm {
        case 0:
            base.alert("K0", isPresented: $m.shown) {
                Button("A") { log.lines.append("A") }
                Button("B") { log.lines.append("B") }
                Button("C") { log.lines.append("C") }
            }
        case 1:
            base.alert("K1", isPresented: $m.shown) {
                Button("Save") { log.lines.append("save") }
                Button("Discard", role: .destructive) { log.lines.append("discard") }
            }
        case 2:
            base.alert("K2", isPresented: $m.shown) {}
        default:
            base.alert("K3", isPresented: $m.shown) {
                Button("Save") { log.lines.append("save") }
                Button("Cancel", role: .cancel) { log.lines.append("cancel") }
            }
        }
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.regular)
MainActor.assumeIsolated {
    print("--- R: alert presenting:")
    do {
        let m = Model()
        let w = host("R0 control: data \"k1\", isPresented true", PresentingHost(m: m))
        m.data = "k1"; m.shown = true; spin(1.0)
        if let s = w.attachedSheet {
            print("  sheet=\(type(of: s)) texts=[\(texts(s))] buttons: \(buttonsLine(s))")
            buttons(in: s).first(where: { $0.title.hasPrefix("Delete") })?.performClick(nil); spin(0.6)
            print("  click Delete -> log \(log.lines) isPresented=\(m.shown) sheet=\(w.attachedSheet != nil)")
        } else { print("  no sheet isPresented=\(m.shown)") }
        log.lines = []
        w.orderOut(nil)
    }
    do {
        // R1: a fresh window, data nil, isPresented true.
        let m = Model()
        let w = host("R1 fresh: data nil, isPresented true", PresentingHost(m: m))
        m.data = nil; m.shown = true; spin(1.0)
        print("  R1 data nil, isPresented true -> sheet=\(w.attachedSheet != nil) isPresented=\(m.shown) log \(log.lines)")
        if let s = w.attachedSheet { print("  R1 sheet texts=[\(texts(s))] buttons: \(buttonsLine(s))") }
        // R2: data arrives while isPresented is already true.
        m.data = "k2"; spin(1.0)
        print("  R2 then data \"k2\" -> sheet=\(w.attachedSheet != nil) texts=[\(w.attachedSheet.map(texts) ?? "")] buttons: \(w.attachedSheet.map(buttonsLine) ?? "")")
        // R3: data set nil while shown.
        m.data = nil; spin(1.0)
        print("  R3 then data nil while shown -> sheet=\(w.attachedSheet != nil) isPresented=\(m.shown) log \(log.lines)")
        if let s = w.attachedSheet {
            print("  R3 sheet texts=[\(texts(s))] buttons: \(buttonsLine(s))")
            buttons(in: s).first?.performClick(nil); spin(0.6)
            print("  R4 click first -> log \(log.lines) isPresented=\(m.shown) sheet=\(w.attachedSheet != nil)")
        }
        m.shown = false; spin(0.5)
        log.lines = []
    }
    print("--- K: Return on the alert (I1 sendEvent, I2 performKeyEquivalent)")
    for arm in [0, 1, 2, 3] {
        for inst in [1, 2] {
            let m = Model()
            let w = host("K\(arm) I\(inst)", KeyHost(m: m, arm: arm))
            m.shown = true; spin(1.0)
            guard let s = w.attachedSheet else { print("  no sheet"); continue }
            print("  buttons: \(buttonsLine(s)) default=\(s.defaultButtonCell?.title ?? "nil") key=\(s.isKeyWindow)")
            if inst == 1 { s.sendEvent(returnKey(s)) } else { _ = s.performKeyEquivalent(with: returnKey(s)) }
            spin(0.6)
            print("  Return -> log \(log.lines) isPresented=\(m.shown) sheet=\(w.attachedSheet != nil)")
            if let s2 = w.attachedSheet { buttons(in: s2).first?.performClick(nil); spin(0.6) }
            log.lines = []
            w.orderOut(nil)
        }
    }
    print("--- end")
}
exit(0)
