// SwiftUI probe: a FOCUSED TextField / TextEditor whose bound text is replaced from outside
// (autocomplete "/com" -> "/compact ", an appended @path mention). Where does the caret land, so
// that the next typed key goes where? (ruling SL-P, record 241)
//
// HOW TO RUN (compiled form, one arm per process; harness of swiftui-text-selection.swift):
//
//   xcrun swiftc docs/probes/swiftui-text-external-replace.swift -o /tmp/ext-probe
//   for a in $(/tmp/ext-probe --list); do /tmp/ext-probe $a; done
//
// Each arm: window with the field focused from code on `initial`; collapse the selection and put the
// caret at offset `caret` (Right to collapse, then Left); write `new` through the binding from
// outside (a spin after); type X; print the resulting text, so "foX..." shows where the caret was.
//
// RECORDED: see RESULT below.

import SwiftUI
import AppKit

final class FirstMouseHost<V: View>: NSHostingView<V> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
final class KeyWindow: NSWindow {
    override var isKeyWindow: Bool { true }
    override var canBecomeKey: Bool { true }
}
enum Log {
    nonisolated(unsafe) static var lines: [String] = []
    nonisolated(unsafe) static var text = ""
    /// Hooks the probe's view installs so an arm can act "from code".
    nonisolated(unsafe) static var writeText: ((String) -> Void)?
    static func add(_ s: String) { lines.append(s) }
    static func take() -> String { defer { lines = [] }; return lines.isEmpty ? "-" : lines.joined(separator: ",") }
}
@MainActor func spin(_ s: Double = 0.15) { RunLoop.main.run(until: Date().addingTimeInterval(s)) }
@MainActor func makeWindow<V: View>(_ view: V) -> NSWindow {
    let w = KeyWindow(contentRect: CGRect(x: 200, y: 200, width: 200, height: 200),
                      styleMask: [.titled, .resizable], backing: .buffered, defer: false)
    w.isReleasedWhenClosed = false
    w.contentView = FirstMouseHost(rootView: view)
    w.makeKeyAndOrderFront(nil)
    spin(0.3)
    return w
}
@MainActor func mouse(_ w: NSWindow, _ t: NSEvent.EventType, _ p: CGPoint, clicks: Int = 1) {
    let e = NSEvent.mouseEvent(with: t, location: p, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                               windowNumber: w.windowNumber, context: nil, eventNumber: 0,
                               clickCount: clicks, pressure: t == .leftMouseUp ? 0 : 1)!
    w.sendEvent(e)
}
@MainActor func click(_ w: NSWindow, at p: CGPoint, clicks: Int = 1) {
    mouse(w, .leftMouseDown, p, clicks: clicks); spin(0.05); mouse(w, .leftMouseUp, p, clicks: clicks); spin()
}
@MainActor func keyEvent(_ w: NSWindow, _ type: NSEvent.EventType, _ chars: String,
                         modifiers: NSEvent.ModifierFlags = [], keyCode: UInt16) {
    let e = NSEvent.keyEvent(with: type, location: .zero, modifierFlags: modifiers,
                             timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: w.windowNumber,
                             context: nil, characters: chars, charactersIgnoringModifiers: chars,
                             isARepeat: false, keyCode: keyCode)!
    NSApp.sendEvent(e); spin()
}
@MainActor func key(_ w: NSWindow, _ chars: String, modifiers: NSEvent.ModifierFlags = [], keyCode: UInt16 = 0) {
    keyEvent(w, .keyDown, chars, modifiers: modifiers, keyCode: keyCode)
    keyEvent(w, .keyUp, chars, modifiers: modifiers, keyCode: keyCode)
}
let leftArrow = "\u{F702}", rightArrow = "\u{F703}"
let fieldPoint = CGPoint(x: 100, y: 185)

/// The binding's value as text over `text`: `ins@n`, `sel@a..b`, `multi[…]`, `nil`.
func describe(_ s: TextSelection?, in text: String) -> String {
    guard let s else { return "nil" }
    switch s.indices {
    case .selection(let r):
        guard r.lowerBound <= text.endIndex, r.upperBound <= text.endIndex else { return "OUT-OF-RANGE" }
        let a = text.distance(from: text.startIndex, to: r.lowerBound), b = text.distance(from: text.startIndex, to: r.upperBound)
        return s.isInsertion ? "ins@\(a)" : "sel@\(a)..\(b)"
    case .multiSelection(let set):
        return "multi\(set.ranges.map { text.distance(from: text.startIndex, to: $0.lowerBound) })"
    @unknown default: return "?"
    }
}

/// The same view with no binding at all (the control).

struct Plain: View {
    var initial: String
    var axisEditor = false
    @State var text = ""
    @FocusState var focused: Bool
    var body: some View {
        VStack {
            Group {
                if axisEditor { TextEditor(text: $text) } else { TextField("f", text: $text) }
            }.focused($focused).frame(height: 30)
            Spacer()
        }
        .onChange(of: text) { _, v in Log.text = v }
        .onAppear {
            text = initial; Log.text = initial; focused = true
            Log.writeText = { text = $0 }
        }
    }
}

/// The same with a selection binding attached (the binding is never rewritten by the replacement).
struct Bound: View {
    var initial: String
    var axisEditor = false
    @State var text = ""
    @State var selection: TextSelection?
    @FocusState var focused: Bool
    var body: some View {
        VStack {
            Group {
                if axisEditor { TextEditor(text: $text, selection: $selection) } else { TextField("f", text: $text, selection: $selection) }
            }.focused($focused).frame(height: 30)
            Spacer()
        }
        .onChange(of: text) { _, v in Log.text = v }
        .onAppear { text = initial; Log.text = initial; focused = true; Log.writeText = { text = $0 } }
    }
}
@MainActor func runBound(_ c: Case, editor: Bool) -> String {
    Log.text = ""
    let w = makeWindow(Bound(initial: c.initial, axisEditor: editor))
    key(w, rightArrow, keyCode: 124)
    for _ in 0..<(c.initial.count - c.caret) { key(w, leftArrow, keyCode: 123) }
    Log.writeText?(c.new); spin()
    key(w, "X")
    let out = Log.text
    w.orderOut(nil); w.contentView = nil
    return out
}

struct Case { var name: String; var initial: String; var caret: Int; var new: String }
let cases: [Case] = [
    Case(name: "extend-at-caret-end", initial: "/com", caret: 4, new: "/compact "),
    Case(name: "extend-at-caret-mid", initial: "ab cd", caret: 2, new: "abXY cd"),
    Case(name: "rewrite-earlier-same-length", initial: "foo bar", caret: 7, new: "FOO bar"),
    Case(name: "rewrite-earlier-mid-caret", initial: "foo bar", caret: 3, new: "goo bar"),
    Case(name: "insert-before-caret", initial: "foo bar", caret: 7, new: "AAfoo bar"),
    Case(name: "append-caret-mid", initial: "foo bar", caret: 3, new: "foo bar @path"),
    Case(name: "append-caret-end", initial: "foo bar", caret: 7, new: "foo bar @path"),
    Case(name: "shrink-caret-end", initial: "hello world", caret: 11, new: "hello"),
    Case(name: "shrink-caret-mid-beyond", initial: "hello world", caret: 8, new: "hel"),
    Case(name: "shrink-caret-mid-within", initial: "hello world", caret: 2, new: "hello"),
    Case(name: "identical", initial: "hello", caret: 2, new: "hello"),
    Case(name: "clear", initial: "hello", caret: 3, new: ""),
    Case(name: "unrelated-longer", initial: "abc", caret: 1, new: "completely different"),
]

typealias Arm = (name: String, run: @MainActor () -> Void)
@MainActor func runCase(_ c: Case, editor: Bool) -> String {
    Log.text = ""
    let w = makeWindow(Plain(initial: c.initial, axisEditor: editor))
    key(w, rightArrow, keyCode: 124)
    for _ in 0..<(c.initial.count - c.caret) { key(w, leftArrow, keyCode: 123) }
    Log.writeText?(c.new); spin()
    key(w, "X")
    let out = Log.text
    w.orderOut(nil); w.contentView = nil
    return out.replacingOccurrences(of: "\n", with: "\\n")
}
let boundCases = [cases[0], cases[1], cases[3], cases[5], cases[8]]
let arms: [Arm] = boundCases.flatMap { c in
    [("BF-" + c.name, { print("BF-\(c.name) TextField+selection binding '\(c.initial)'@\(c.caret) -> '\(c.new)', type X:", runBound(c, editor: false)) }),
     ("BE-" + c.name, { print("BE-\(c.name) TextEditor+selection binding '\(c.initial)'@\(c.caret) -> '\(c.new)', type X:", runBound(c, editor: true)) })]
} + cases.flatMap { c in
    [("F-" + c.name, { print("F-\(c.name) TextField '\(c.initial)'@\(c.caret) -> '\(c.new)', type X:", runCase(c, editor: false)) }),
     ("E-" + c.name, { print("E-\(c.name) TextEditor '\(c.initial)'@\(c.caret) -> '\(c.new)', type X:", runCase(c, editor: true)) })]
}

MainActor.assumeIsolated {
    let args = CommandLine.arguments.dropFirst()
    if args.first == "--list" { print(arms.map(\.name).joined(separator: " ")); exit(0) }
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    for a in arms where args.first == a.name || args.isEmpty { a.run() }
}
