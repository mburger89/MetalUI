// SwiftUI probe: an input method's marked text in a TextField/TextEditor (rulings IM-* in
// docs/superpowers/2026-10-12-ime-driver-decisions.md; spec
// docs/superpowers/specs/2026-10-12-ime-driver-design.md). Instrument: swiftui-text-selection.swift's
// (a KeyWindow, a run-loop spin between steps); marked text is driven by calling the focused field
// editor's NSTextInputClient methods directly (setMarkedText / insertText / unmarkText /
// inputContext.discardMarkedText), which is what an input method does through the input context.
//
// HOW TO RUN (one arm per process):
//   xcrun swiftc docs/probes/swiftui-ime-composition.swift -o /tmp/ime-probe
//   for a in $(/tmp/ime-probe --list); do /tmp/ime-probe $a; done
//
// ARMS. C0 control: the focused field, nothing marked (text/binding/AX at rest). The separating arm of
// every "while marked" reading is the same arm read at C0. A: setMarkedText "ni" at the end of
// "hello"; reads the text binding, the selection binding, the field editor's string, hasMarkedText,
// and the accessibility value of the field. B: update the marked text. U: unmarkText (the commit
// AppKit sends). I: insertText replacing the marked text. D: discardMarkedText (cancel). W: a
// selection written from code while marked. Z: undo (NSUndoManager) after a commit.
//

// RECORDED 2026-10-12 by the ime-driver (C28) designer, macOS 27.0.1, Apple Swift 6.4, screen
// UNLOCKED, compiled form, one arm per process. The machine was loaded by other builds: in the
// confirming second pass arms C0 and A exceeded the 25 s watchdog (HANG, killed) and Z hangs on
// every run in the Z arm's undo step (a probe defect, not a finding); every other arm printed
// the same line both times. Lines trimmed to the readings (setup=[...] omitted: it is the C0 line's).
//
//   C0 at rest: text=hello binding=sel@0..5 editor='hello' hasMarked=false editorSel={0, 5}
//   A  marked 'ni' (TextField, focused from code => all selected): after=[sel->ins@2] text=hello binding=ins@2 editor='ni' hasMarked=true markedRange={0, 2} editorAX='ni'
//   Ae TextEditor, caret at end, marked 'ni': after=[-] text=hello binding=ins@5 editor='helloni' markedRange={5, 2} editorAX='helloni'
//   B  'ni' updated to 'ni hao': after=[sel->ins@2,sel->OUT-OF-RANGE] text=hello binding=OUT-OF-RANGE editor='ni hao'
//   U  marked 'ni' then unmarkText: after=[sel->ins@2,sel->ins@0,sel->ins@2,text->ni] text=ni binding=ins@2 hasMarked=false
//   I  marked 'ni' then insertText 你: after=[sel->ins@2,sel->ins@1,text->你] text=你 binding=ins@1
//   D  marked 'ni' then inputContext.discardMarkedText(): hasMarked STILL true, editor 'ni' (the instrument cannot cancel this way)
//   D2 marked 'ni' then setMarkedText '' (SDL's clear): after=[sel->ins@2,sel->ins@0] text=hello(unwritten) binding=ins@0 editor='' hasMarked=false
//   W  marked 'ni', selection written 0..<1 from code: after=[sel->ins@2,sel->sel@0..1] binding=sel@0..1 editor='ni' editorSel={0, 1} hasMarked=true
//   WU as W then unmarkText: after=[...,sel->ins@0,sel->ins@2,text->ni] text=ni binding=ins@2
//   Zs type X, write ins@0, type Y, NSUndoManager.undo(): canUndo=true, text=YX binding=ins@0 (editor 'X': the instrument's editor and
//      the model disagree after a code write, so no undo claim is made, as in swiftui-text-selection.swift R4/R5)
//
// RESULT (read by rulings IM-E, IM-G, IM-H).
//  1. THE TEXT BINDING IS NOT WRITTEN WHILE MARKED (A, Ae, B, W: text=hello throughout); it is written
//     once, at the commit (U, I). Marked text is the field editor's, not the model's.
//  2. THE FIELD EDITOR'S ACCESSIBILITY VALUE INCLUDES THE MARKED TEXT (editorAX 'ni', 'helloni') while
//     the text binding does not. The SwiftUI element's own AX value is not reachable by this
//     instrument (the hosting view's tree is empty without an AX client: ax=[]); no claim about it.
//  3. THE SELECTION BINDING IS WRITTEN DURING COMPOSITION, IN THE EDITOR'S COORDINATES: ins@2 for
//     'ni' (an offset into the marked text, not into 'hello'), then OUT-OF-RANGE for 'ni hao' (B).
//     A TextEditor, whose marked text sits at the caret, wrote nothing (Ae).
//  4. A SELECTION WRITTEN FROM CODE WHILE MARKED IS APPLIED AT ONCE (W: editorSel={0, 1}, binding
//     sel@0..1) and the marked text stays; the commit then overwrites it (WU: ins@2). End state after
//     the commit equals a held-back write's.
//  5. THE COMMIT: unmarkText and insertText both write the text once and the selection after it (U, I).
//  6. CANCEL is not observable through discardMarkedText on a field editor (D); the SDL form (D2)
//     leaves the model untouched (the text binding was never written) - no claim about what the
//     editor shows afterwards.

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
    nonisolated(unsafe) static var sel: TextSelection?
    /// Hooks the probe's view installs so an arm can act "from code".
    nonisolated(unsafe) static var writeSelection: ((TextSelection?) -> Void)?
    nonisolated(unsafe) static var writeText: ((String) -> Void)?
    nonisolated(unsafe) static var setFocus: ((Bool) -> Void)?
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

/// A field with a selection binding. `setup` runs in onAppear (after focus).
struct Probe: View {
    var initial: String
    var axisEditor = false
    var focusOnAppear = true
    var startSelection: ((String) -> TextSelection?)? = nil
    var onAppearWrite: ((String) -> TextSelection?)? = nil
    @State var text = ""
    @State var selection: TextSelection?
    @FocusState var focused: Bool
    var body: some View {
        VStack {
            Group {
                if axisEditor {
                    TextEditor(text: $text, selection: $selection)
                } else {
                    TextField("f", text: $text, selection: $selection)
                }
            }
            .focused($focused).frame(height: 30)
            Spacer()
        }
        .onChange(of: selection) { _, v in Log.sel = v; Log.add("sel->" + describe(v, in: text)) }
        .onChange(of: text) { _, v in Log.text = v; Log.add("text->\(v)") }
        .onChange(of: focused) { _, v in Log.add("focus=\(v)") }
        .onAppear {
            Log.writeSelection = { selection = $0 }; Log.writeText = { text = $0 }; Log.setFocus = { focused = $0 }
            text = initial; Log.text = initial
            selection = startSelection?(initial)
            if focusOnAppear { focused = true }
            if let w = onAppearWrite { selection = w(initial) }
        }
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
        .onAppear { text = initial; Log.text = initial; focused = true }
    }
}
func at(_ s: String, _ n: Int) -> String.Index { s.index(s.startIndex, offsetBy: n) }

typealias Arm = (name: String, run: @MainActor () -> Void)
@MainActor func run<V: View>(_ view: V, _ act: (NSWindow) -> Void) -> String {
    _ = Log.take(); Log.sel = nil
    let w = makeWindow(view)
    _ = Log.take()   // drop the setup lines; arms print what the ACT did
    act(w)
    let out = "text=\(Log.text) binding=\(describe(Log.sel, in: Log.text)) events=\(Log.take())"
    w.orderOut(nil); w.contentView = nil
    return out
}
@MainActor func runKeepSetup<V: View>(_ view: V, _ act: (NSWindow) -> Void) -> String {
    _ = Log.take(); Log.sel = nil
    let w = makeWindow(view)
    let setup = Log.take()
    act(w)
    let out = "setup=[\(setup)] text=\(Log.text) binding=\(describe(Log.sel, in: Log.text)) after=[\(Log.take())]"
    w.orderOut(nil); w.contentView = nil
    return out
}


/// The focused field editor as an input client.
@MainActor func client(_ w: NSWindow) -> NSTextInputClient? { w.firstResponder as? NSTextInputClient }
@MainActor func fieldEditor(_ w: NSWindow) -> NSTextView? { w.firstResponder as? NSTextView }
@MainActor func mark(_ w: NSWindow, _ s: String, sel: NSRange? = nil) {
    client(w)?.setMarkedText(s, selectedRange: sel ?? NSRange(location: (s as NSString).length, length: 0),
                             replacementRange: NSRange(location: NSNotFound, length: 0))
    spin()
}
/// Every AX element's role and value below `root`, depth-first (the hosting view's tree).
@MainActor func axValues(_ root: Any?, depth: Int = 0) -> [String] {
    guard depth < 8, let e = root as? NSAccessibilityProtocol else { return [] }
    var out: [String] = []
    let role = e.accessibilityRole()?.rawValue ?? "-"
    if role == "AXTextField" || role == "AXTextArea" { out.append("\(role)=\(String(describing: e.accessibilityValue()))") }
    for c in (e.accessibilityChildren() ?? []) { out += axValues(c, depth: depth + 1) }
    return out
}
@MainActor func state(_ w: NSWindow) -> String {
    let fe = fieldEditor(w)
    return "text=\(Log.text) binding=\(describe(Log.sel, in: Log.text)) editor='\(fe?.string ?? "?")' hasMarked=\(client(w)?.hasMarkedText() ?? false) markedRange=\(client(w).map { NSStringFromRange($0.markedRange()) } ?? "?") editorSel=\(fe.map { NSStringFromRange($0.selectedRange()) } ?? "?") ax=\(axValues(w.contentView)) editorAX=\(String(describing: fe?.accessibilityValue()))"
}
@MainActor func go(_ name: String, _ view: some View, _ act: (NSWindow) -> Void) {
    _ = Log.take(); Log.sel = nil
    let w = makeWindow(view)
    let setup = Log.take()
    act(w)
    print(name, "setup=[\(setup)]", "after=[\(Log.take())]", state(w))
    w.orderOut(nil); w.contentView = nil
}
let end5 = { (s: String) in TextSelection(insertionPoint: s.index(s.endIndex, offsetBy: 0)) }
let arms: [Arm] = [
    ("C0", { go("C0 at rest, caret at end:", Probe(initial: "hello", startSelection: end5, onAppearWrite: end5)) { _ in } }),
    ("A", { go("A marked 'ni' at end:", Probe(initial: "hello", startSelection: end5, onAppearWrite: end5)) { w in mark(w, "ni") } }),
    ("Ae", { go("Ae TextEditor marked 'ni' at end:", Probe(initial: "hello", axisEditor: true, startSelection: end5)) { w in mark(w, "ni") } }),
    ("A0", { go("A0 marked 'ni' over a select-all field (focus from code):", Probe(initial: "hello")) { w in mark(w, "ni") } }),
    ("B", { go("B marked 'ni' then updated to 'ni hao':", Probe(initial: "hello", startSelection: end5, onAppearWrite: end5)) { w in mark(w, "ni"); mark(w, "ni hao") } }),
    ("U", { go("U marked 'ni' then unmarkText (commit):", Probe(initial: "hello", startSelection: end5, onAppearWrite: end5)) { w in mark(w, "ni"); client(w)?.unmarkText(); spin() } }),
    ("I", { go("I marked 'ni' then insertText '你':", Probe(initial: "hello", startSelection: end5, onAppearWrite: end5)) { w in mark(w, "ni"); client(w)?.insertText("你", replacementRange: NSRange(location: NSNotFound, length: 0)); spin() } }),
    ("D", { go("D marked 'ni' then discardMarkedText (cancel):", Probe(initial: "hello", startSelection: end5, onAppearWrite: end5)) { w in mark(w, "ni"); fieldEditor(w)?.inputContext?.discardMarkedText(); spin() } }),
    ("D2", { go("D2 marked 'ni' then setMarkedText '' (the SDL clear):", Probe(initial: "hello", startSelection: end5, onAppearWrite: end5)) { w in mark(w, "ni"); mark(w, "") } }),
    ("W", { go("W marked 'ni', selection written 0..<1 from code, spin:", Probe(initial: "hello", startSelection: end5, onAppearWrite: end5)) { w in mark(w, "ni"); Log.writeSelection?(TextSelection(range: at("hello", 0)..<at("hello", 1))); spin() } }),
    ("WU", { go("WU as W then unmarkText:", Probe(initial: "hello", startSelection: end5, onAppearWrite: end5)) { w in mark(w, "ni"); Log.writeSelection?(TextSelection(range: at("hello", 0)..<at("hello", 1))); spin(); client(w)?.unmarkText(); spin() } }),
    ("Z", { go("Z type X, commit 'ni', then NSUndoManager.undo():", Probe(initial: "hello", startSelection: end5, onAppearWrite: end5)) { w in key(w, "X"); mark(w, "ni"); client(w)?.unmarkText(); spin(); print("   Z canUndo:", w.firstResponder?.undoManager?.canUndo ?? false); w.firstResponder?.undoManager?.undo(); spin() } }),
    ("Zs", { go("Zs type X, selection written ins@0, type Y, undo():", Probe(initial: "hello", startSelection: end5, onAppearWrite: end5)) { w in key(w, "X"); Log.writeSelection?(TextSelection(insertionPoint: at("helloX", 0))); spin(); key(w, "Y"); print("   Zs canUndo:", w.firstResponder?.undoManager?.canUndo ?? false); w.firstResponder?.undoManager?.undo(); spin() } }),
]

MainActor.assumeIsolated {
    let args = CommandLine.arguments.dropFirst()
    if args.first == "--list" { print(arms.map(\.name).joined(separator: " ")); exit(0) }
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    for a in arms where args.first == a.name || args.isEmpty { a.run() }
}
