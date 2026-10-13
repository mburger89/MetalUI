// SwiftUI probe: TextField/TextEditor selection binding (rulings SL-* in
// docs/superpowers/2026-10-12-text-selection-decisions.md; spec
// docs/superpowers/specs/2026-10-12-text-selection-design.md).
//
// HOW TO RUN (compiled form, `swiftui-key-focus.swift`'s instrument: a
// KeyWindow, NSEvents through NSWindow/NSApp.sendEvent, a run-loop spin
// between events). One arm per process so a trap in one cannot hide the
// others:
//
//   xcrun swiftc docs/probes/swiftui-text-selection.swift -o /tmp/sel-probe
//   for a in $(/tmp/sel-probe --list); do /tmp/sel-probe $a; done
//
// ARMS. C0 control: a focused-from-code field, NO binding (what the caret
// does). Every other arm reads against C0 (text) and C1 (the binding's
// shape at rest). The separating arm of "a write is applied" is the same arm
// with the write left out.
//
// The window is 200x200 (origin bottom-left), the field pinned to the top.

// RECORDED 2026-10-12 by the text-selection (C25) designer, macOS 27.0.1, Apple Swift 6.4,
// screen LOCKED (the instrument sends NSEvents to its own window and ran fine locked), compiled
// form, every arm its own process, run twice, stdout byte-identical (49 lines), exit 0.
// (Arm names above the line they print; a multi-line value is a TextEditor's "ab\ncd".)
//
//   C0 no binding, focused from code, 'hello', type X: text=X binding=nil events=-
//   C0e TextEditor, no binding, focused from code, 'hello', type X: text=helloX binding=nil events=-
//   C1 binding nil, focused from code, nothing typed: setup=[text->hello,sel->sel@0..5,focus=true] text=hello binding=sel@0..5 after=[-]
//   C1e TextEditor binding nil, focused from code, nothing typed: setup=[text->hello,sel->ins@5,focus=true] text=hello binding=ins@5 after=[-]
//   C2 binding nil, focused from code, type X: text=X binding=ins@1 events=sel->ins@1,text->X
//   C3 unfocused, binding nil, nothing: setup=[text->hello] text=hello binding=nil after=[-]
//   P1 preset insertion@5 (end), focus in onAppear, type X: text=X binding=ins@1 events=sel->ins@1,text->X
//   P1s same, nothing typed (what the binding reads): setup=[sel->ins@5,text->hello,sel->sel@0..5,focus=true] text=hello binding=sel@0..5 after=[-]
//   P2 preset sel 1..<3, type X: text=X binding=ins@1 events=sel->ins@1,text->X
//   P3 preset sel 0..<5 (all), type X: text=X binding=ins@1 events=sel->ins@1,text->X
//   P4 preset insertion@0, type X: text=X binding=ins@1 events=sel->ins@1,text->X
//   P5 preset set AFTER focus in onAppear (same turn) insertion@2, type X: text=X binding=ins@1 events=sel->ins@1,text->X
//   P5s same, nothing typed: setup=[sel->ins@2,text->hello,sel->sel@0..5,focus=true] text=hello binding=sel@0..5 after=[-]
//   P6 UNFOCUSED field with preset sel 1..<3; then focus by click, type X: text=helloX binding=ins@6 events=sel->sel@0..5,sel->ins@0,focus=true,sel->ins@5,sel->ins@6,text->helloX
//   P6s unfocused preset 1..<3, no click, binding reads: setup=[sel->sel@1..3,text->hello] text=hello binding=sel@1..3 after=[-]
//   P7 TextEditor preset insertion@5, type X: text=helloX binding=ins@6 events=sel->ins@6,text->helloX
//   P8 TextEditor preset sel 1..<3, type X: text=hXlo binding=ins@2 events=sel->ins@2,text->hXlo
//   P9 multi-line TextEditor 'ab\ncd' preset insertion@5 (end), type X: text=ab
//   cdX binding=ins@6 events=sel->ins@6,text->ab
//   cdX
//   R1 preset insertion@5, then Left x2, binding: setup=[sel->ins@5,text->hello,sel->sel@0..5,focus=true] text=hello binding=ins@0 after=[sel->ins@0]
//   R2 preset insertion@5, cmd-a, binding: setup=[sel->ins@5,text->hello,sel->sel@0..5,focus=true] text=hello binding=sel@0..5 after=[-]
//   R3 preset insertion@5, type X then Y, binding: setup=[sel->ins@5,text->hello,sel->sel@0..5,focus=true] text=XY binding=ins@2 after=[sel->ins@1,text->X,sel->ins@2,text->XY]
//   R4 preset insertion@5, type X, cmd-z, binding: setup=[sel->ins@5,text->hello,sel->sel@0..5,focus=true] text=X binding=ins@1 after=[sel->ins@1,text->X]
//   R5 preset sel 1..<3 type X, cmd-z, binding: setup=[sel->sel@1..3,text->hello,sel->sel@0..5,focus=true] text=X binding=ins@1 after=[sel->ins@1,text->X]
//   R6 preset insertion@5, click at the field's left end, binding: setup=[sel->ins@5,text->hello,sel->sel@0..5,focus=true] text=hello binding=ins@0 after=[sel->ins@0]
//   R7 preset insertion@5, double click on 'hello', binding: setup=[sel->ins@5,text->hello,sel->sel@0..5,focus=true] text=hello binding=sel@0..5 after=[sel->sel@0..5]
//   R8 preset sel 1..<3, shift-Right, binding: setup=[sel->sel@1..3,text->hello,sel->sel@0..5,focus=true] text=hello binding=sel@0..5 after=[sel->sel@0..5]
//   R9 preset insertion@2, delete backward, binding: setup=[sel->ins@2,text->hello,sel->sel@0..5,focus=true] text= binding=ins@0 after=[sel->ins@0,text->]
//   S1 preset indices from a LONGER string ('hello world' @11) on 'hello':  setup=[sel->OUT-OF-RANGE,text->hello,sel->sel@0..5,focus=true] text=X binding=ins@1 after=[sel->ins@1,text->X]
//   S2 preset indices from an unrelated string ('hello' @3 of a copy): setup=[sel->ins@3,text->hello,sel->sel@0..5,focus=true] text=X binding=ins@1 after=[sel->ins@1,text->X]
//   S3 preset .multiSelection two ranges (0..<1, 3..<4), type X: setup=[sel->multi[0, 3],text->hello,sel->sel@0..5,focus=true] text=X binding=ins@1 after=[sel->ins@1,text->X]
//      W1 after write+spin: ins@2 sel->ins@2
//   W1 settled focused TextField, write insertion@2, binding then type X: setup=[text->hello,sel->sel@0..5,focus=true] text=heXllo binding=ins@3 after=[sel->ins@3,text->heXllo]
//   W2 settled focused TextField, write sel 1..<4, type X: setup=[text->hello,sel->sel@0..5,focus=true] text=hXo binding=ins@2 after=[sel->sel@1..4,sel->ins@2,text->hXo]
//   W3 settled focused TextField, write sel 1..<4, NO spin before reading (same turn read): setup=[text->hello,sel->sel@0..5,focus=true] text=X binding=ins@1 after=[sel->OUT-OF-RANGE,sel->ins@1,text->X]
//   W4 settled focused TextField, write nil, type X: setup=[sel->ins@5,text->hello,sel->sel@0..5,focus=true] text=X binding=ins@1 after=[sel->nil,sel->ins@1,text->X]
//   W5 TextEditor settled, write insertion@2, type X: setup=[text->hello,sel->ins@5,focus=true] text=heXllo binding=ins@3 after=[sel->ins@2,sel->ins@2,sel->ins@3,text->heXllo]
//      W6 after text write: OUT-OF-RANGE sel->ins@5,text->hi
//   W6 settled focused TextField ins@5 (typed), text replaced from code 'hi', binding then type X: setup=[text->hello,sel->sel@0..5,focus=true] text=hiX binding=ins@3 after=[sel->ins@3,text->hiX]
//   W7 settled, write ALL (0..<5), cmd-c not probed; type X: setup=[text->hello,sel->sel@0..5,focus=true] text=X binding=ins@1 after=[sel->ins@5,sel->sel@0..5,sel->ins@1,text->X]
//   W8 settled, write stale indices from 'hello world'@11, then type X: setup=[text->hello,sel->sel@0..5,focus=true] text=helloX binding=ins@6 after=[sel->OUT-OF-RANGE,sel->ins@6,text->helloX]
//   W9 settled, write a multiSelection (0..<1, 3..<4), then type X: setup=[text->hello,sel->sel@0..5,focus=true] text=Xello binding=ins@1 after=[sel->multi[0, 3],sel->ins@1,text->Xello]
//      F1 after focus+spin: sel@0..5 sel->sel@1..3,sel->sel@0..5,focus=true
//   F1 unfocused; write sel 0..<5 then (same turn) focus from code; type X: setup=[text->hello] text=X binding=ins@1 after=[sel->ins@1,text->X]
//   F2 unfocused; focus from code, spin, THEN write sel 1..<3; type X: setup=[text->hello] text=hXlo binding=ins@2 after=[sel->sel@0..5,focus=true,sel->sel@1..3,sel->ins@2,text->hXlo]
//   F3 TextEditor unfocused; write ins@2 then focus same turn; type X: setup=[text->hello,sel->ins@5] text=heXllo binding=ins@3 after=[sel->ins@2,sel->ins@2,focus=true,sel->ins@3,text->heXllo]
//   F4 TextField unfocused; write ins@2 then focus same turn; type X: setup=[text->hello] text=X binding=ins@1 after=[sel->ins@2,sel->sel@0..5,focus=true,sel->ins@1,text->X]
//   F5 TextField focused then unfocused (focus=false), binding reads: setup=[text->hello,sel->sel@0..5,focus=true] text=hello binding=ins@0 after=[sel->sel@1..3,sel->ins@0,focus=false]
//
// RESULT (read by rulings SL-A..SL-H).
//  1. FOCUS FROM CODE. A TextField focused from code SELECTS ALL (C0: type X gives "X"; C1: the
//     binding reads sel@0..5); a TextEditor's caret goes to the END (C0e: "helloX"; C1e: ins@5).
//     A preset binding does not survive that for a TextField: a value written before or in the
//     same turn as the focus loses to the select-all (P1, P2, P4, P5, F1, F4: "X"), a TextEditor
//     keeps it (P7, P8, F3). A write one turn AFTER the focus wins on both (F2, W1, W2, W5).
//  2. A WRITE IS APPLIED ON THE NEXT RUN-LOOP TURN: a key in the same turn as the write still
//     sees the old selection (W3: "X" with the write 1..<4 unseen; W1/W2 with a spin: heXllo,
//     hXo).
//  3. WHAT THE BINDING READS: after typing ins@(after the insertion) (R3, C2); Left x2: R1 reads
//     ins@0 (the field was select-all at focus, so Left collapses to the start); cmd-a sel@0..n (R2); a click ins@n (R6); a double click sel@word (R7);
//     shift-arrow extends (R8); delete ins@n (R9). An unfocused field keeps its preset (P6s).
//     Resigning focus writes ins@0 (F5).
//  4. nil: writing nil does not move the field's own selection (W4).
//  5. STALE / OUT OF RANGE: no trap. Indices from a longer string clamp to the end (S1, W8:
//     "helloX"); a text replaced from code leaves the binding stale and typing clamps (W6: "hiX");
//     the binding is never rewritten until the user acts.
//  6. .multiSelection: the field takes the FIRST range (S3, W9: "Xello"), binding reads ins@1.
//  7. UNDO: cmd-z synthesized through NSApp.sendEvent did not undo (R4, R5: text stays "X") -
//     the instrument cannot see undo; the undo claim is MetalUI's own (TI-G), not SwiftUI's.

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

let arms: [Arm] = [
    // --- C: controls
    ("C0", { print("C0 no binding, focused from code, 'hello', type X:", run(Plain(initial: "hello")) { w in key(w, "X") }) }),
    ("C0e", { print("C0e TextEditor, no binding, focused from code, 'hello', type X:", run(Plain(initial: "hello", axisEditor: true)) { w in key(w, "X") }) }),
    ("C1", { print("C1 binding nil, focused from code, nothing typed:", runKeepSetup(Probe(initial: "hello")) { _ in }) }),
    ("C1e", { print("C1e TextEditor binding nil, focused from code, nothing typed:", runKeepSetup(Probe(initial: "hello", axisEditor: true)) { _ in }) }),
    ("C2", { print("C2 binding nil, focused from code, type X:", run(Probe(initial: "hello")) { w in key(w, "X") }) }),
    ("C3", { print("C3 unfocused, binding nil, nothing:", runKeepSetup(Probe(initial: "hello", focusOnAppear: false)) { _ in }) }),
    // --- P: a preset binding at focus
    ("P1", { print("P1 preset insertion@5 (end), focus in onAppear, type X:", run(Probe(initial: "hello", startSelection: { TextSelection(insertionPoint: at($0, 5)) })) { w in key(w, "X") }) }),
    ("P1s", { print("P1s same, nothing typed (what the binding reads):", runKeepSetup(Probe(initial: "hello", startSelection: { TextSelection(insertionPoint: at($0, 5)) })) { _ in }) }),
    ("P2", { print("P2 preset sel 1..<3, type X:", run(Probe(initial: "hello", startSelection: { TextSelection(range: at($0, 1)..<at($0, 3)) })) { w in key(w, "X") }) }),
    ("P3", { print("P3 preset sel 0..<5 (all), type X:", run(Probe(initial: "hello", startSelection: { TextSelection(range: at($0, 0)..<at($0, 5)) })) { w in key(w, "X") }) }),
    ("P4", { print("P4 preset insertion@0, type X:", run(Probe(initial: "hello", startSelection: { TextSelection(insertionPoint: at($0, 0)) })) { w in key(w, "X") }) }),
    ("P5", { print("P5 preset set AFTER focus in onAppear (same turn) insertion@2, type X:", run(Probe(initial: "hello", onAppearWrite: { TextSelection(insertionPoint: at($0, 2)) })) { w in key(w, "X") }) }),
    ("P5s", { print("P5s same, nothing typed:", runKeepSetup(Probe(initial: "hello", onAppearWrite: { TextSelection(insertionPoint: at($0, 2)) })) { _ in }) }),
    ("P6", { print("P6 UNFOCUSED field with preset sel 1..<3; then focus by click, type X:", run(Probe(initial: "hello", focusOnAppear: false, startSelection: { TextSelection(range: at($0, 1)..<at($0, 3)) })) { w in click(w, at: fieldPoint); key(w, "X") }) }),
    ("P6s", { print("P6s unfocused preset 1..<3, no click, binding reads:", runKeepSetup(Probe(initial: "hello", focusOnAppear: false, startSelection: { TextSelection(range: at($0, 1)..<at($0, 3)) })) { _ in }) }),
    ("P7", { print("P7 TextEditor preset insertion@5, type X:", run(Probe(initial: "hello", axisEditor: true, startSelection: { TextSelection(insertionPoint: at($0, 5)) })) { w in key(w, "X") }) }),
    ("P8", { print("P8 TextEditor preset sel 1..<3, type X:", run(Probe(initial: "hello", axisEditor: true, startSelection: { TextSelection(range: at($0, 1)..<at($0, 3)) })) { w in key(w, "X") }) }),
    ("P9", { print("P9 multi-line TextEditor 'ab\\ncd' preset insertion@5 (end), type X:", run(Probe(initial: "ab\ncd", axisEditor: true, startSelection: { TextSelection(insertionPoint: at($0, 5)) })) { w in key(w, "X") }) }),
    // --- R: what the binding reads after user actions
    ("R1", { print("R1 preset insertion@5, then Left x2, binding:", runKeepSetup(Probe(initial: "hello", startSelection: { TextSelection(insertionPoint: at($0, 5)) })) { w in key(w, leftArrow, keyCode: 123); key(w, leftArrow, keyCode: 123) }) }),
    ("R2", { print("R2 preset insertion@5, cmd-a, binding:", runKeepSetup(Probe(initial: "hello", startSelection: { TextSelection(insertionPoint: at($0, 5)) })) { w in key(w, "a", modifiers: .command, keyCode: 0) }) }),
    ("R3", { print("R3 preset insertion@5, type X then Y, binding:", runKeepSetup(Probe(initial: "hello", startSelection: { TextSelection(insertionPoint: at($0, 5)) })) { w in key(w, "X"); key(w, "Y") }) }),
    ("R4", { print("R4 preset insertion@5, type X, cmd-z, binding:", runKeepSetup(Probe(initial: "hello", startSelection: { TextSelection(insertionPoint: at($0, 5)) })) { w in key(w, "X"); key(w, "z", modifiers: .command, keyCode: 6) }) }),
    ("R5", { print("R5 preset sel 1..<3 type X, cmd-z, binding:", runKeepSetup(Probe(initial: "hello", startSelection: { TextSelection(range: at($0, 1)..<at($0, 3)) })) { w in key(w, "X"); key(w, "z", modifiers: .command, keyCode: 6) }) }),
    ("R6", { print("R6 preset insertion@5, click at the field's left end, binding:", runKeepSetup(Probe(initial: "hello", startSelection: { TextSelection(insertionPoint: at($0, 5)) })) { w in click(w, at: CGPoint(x: 8, y: 185)) }) }),
    ("R7", { print("R7 preset insertion@5, double click on 'hello', binding:", runKeepSetup(Probe(initial: "hello", startSelection: { TextSelection(insertionPoint: at($0, 5)) })) { w in click(w, at: CGPoint(x: 14, y: 185), clicks: 2) }) }),
    ("R8", { print("R8 preset sel 1..<3, shift-Right, binding:", runKeepSetup(Probe(initial: "hello", startSelection: { TextSelection(range: at($0, 1)..<at($0, 3)) })) { w in key(w, rightArrow, modifiers: .shift, keyCode: 124) }) }),
    ("R9", { print("R9 preset insertion@2, delete backward, binding:", runKeepSetup(Probe(initial: "hello", startSelection: { TextSelection(insertionPoint: at($0, 2)) })) { w in key(w, "\u{7f}", keyCode: 51) }) }),
    // --- S: stale or out-of-range
    ("S1", { print("S1 preset indices from a LONGER string ('hello world' @11) on 'hello': ", runKeepSetup(Probe(initial: "hello", startSelection: { _ in let l = "hello world"; return TextSelection(insertionPoint: at(l, 11)) })) { w in key(w, "X") }) }),
    ("S2", { print("S2 preset indices from an unrelated string ('hello' @3 of a copy):", runKeepSetup(Probe(initial: "hello", startSelection: { _ in let l = String("hello"); return TextSelection(insertionPoint: at(l, 3)) })) { w in key(w, "X") }) }),
    ("S3", { print("S3 preset .multiSelection two ranges (0..<1, 3..<4), type X:", runKeepSetup(Probe(initial: "hello", startSelection: { s in var set = RangeSet<String.Index>(); set.insert(contentsOf: at(s, 0)..<at(s, 1)); set.insert(contentsOf: at(s, 3)..<at(s, 4)); return TextSelection(ranges: set) })) { w in key(w, "X") }) }),
    // --- W: writes from code once the field has settled (a spin after focus)
    ("W1", { print("W1 settled focused TextField, write insertion@2, binding then type X:", runKeepSetup(Probe(initial: "hello")) { w in Log.writeSelection?(TextSelection(insertionPoint: at("hello", 2))); spin(); print("   W1 after write+spin:", describe(Log.sel, in: Log.text), Log.take()); key(w, "X") }) }),
    ("W2", { print("W2 settled focused TextField, write sel 1..<4, type X:", runKeepSetup(Probe(initial: "hello")) { w in Log.writeSelection?(TextSelection(range: at("hello", 1)..<at("hello", 4))); spin(); key(w, "X") }) }),
    ("W3", { print("W3 settled focused TextField, write sel 1..<4, NO spin before reading (same turn read):", runKeepSetup(Probe(initial: "hello")) { w in Log.writeSelection?(TextSelection(range: at("hello", 1)..<at("hello", 4))); key(w, "X") }) }),
    ("W4", { print("W4 settled focused TextField, write nil, type X:", runKeepSetup(Probe(initial: "hello", startSelection: { TextSelection(insertionPoint: at($0, 5)) })) { w in Log.writeSelection?(nil); spin(); key(w, "X") }) }),
    ("W5", { print("W5 TextEditor settled, write insertion@2, type X:", runKeepSetup(Probe(initial: "hello", axisEditor: true)) { w in Log.writeSelection?(TextSelection(insertionPoint: at("hello", 2))); spin(); key(w, "X") }) }),
    ("W6", { print("W6 settled focused TextField ins@5 (typed), text replaced from code 'hi', binding then type X:", runKeepSetup(Probe(initial: "hello")) { w in Log.writeSelection?(TextSelection(insertionPoint: at("hello", 5))); spin(); Log.writeText?("hi"); spin(); print("   W6 after text write:", describe(Log.sel, in: Log.text), Log.take()); key(w, "X") }) }),
    ("W7", { print("W7 settled, write ALL (0..<5), cmd-c not probed; type X:", runKeepSetup(Probe(initial: "hello")) { w in Log.writeSelection?(TextSelection(insertionPoint: at("hello", 5))); spin(); Log.writeSelection?(TextSelection(range: at("hello", 0)..<at("hello", 5))); spin(); key(w, "X") }) }),
    ("W8", { print("W8 settled, write stale indices from 'hello world'@11, then type X:", runKeepSetup(Probe(initial: "hello")) { w in Log.writeSelection?(TextSelection(insertionPoint: at("hello world", 11))); spin(); key(w, "X") }) }),
    ("W9", { print("W9 settled, write a multiSelection (0..<1, 3..<4), then type X:", runKeepSetup(Probe(initial: "hello")) { w in var set = RangeSet<String.Index>(); set.insert(contentsOf: at("hello", 0)..<at("hello", 1)); set.insert(contentsOf: at("hello", 3)..<at("hello", 4)); Log.writeSelection?(TextSelection(ranges: set)); spin(); key(w, "X") }) }),
    // --- F: rename recipe — set the selection while UNFOCUSED, then focus from code
    ("F1", { print("F1 unfocused; write sel 0..<5 then (same turn) focus from code; type X:", runKeepSetup(Probe(initial: "hello", focusOnAppear: false)) { w in Log.writeSelection?(TextSelection(range: at("hello", 1)..<at("hello", 3))); Log.setFocus?(true); spin(); print("   F1 after focus+spin:", describe(Log.sel, in: Log.text), Log.take()); key(w, "X") }) }),
    ("F2", { print("F2 unfocused; focus from code, spin, THEN write sel 1..<3; type X:", runKeepSetup(Probe(initial: "hello", focusOnAppear: false)) { w in Log.setFocus?(true); spin(); Log.writeSelection?(TextSelection(range: at("hello", 1)..<at("hello", 3))); spin(); key(w, "X") }) }),
    ("F3", { print("F3 TextEditor unfocused; write ins@2 then focus same turn; type X:", runKeepSetup(Probe(initial: "hello", axisEditor: true, focusOnAppear: false)) { w in Log.writeSelection?(TextSelection(insertionPoint: at("hello", 2))); Log.setFocus?(true); spin(); key(w, "X") }) }),
    ("F4", { print("F4 TextField unfocused; write ins@2 then focus same turn; type X:", runKeepSetup(Probe(initial: "hello", focusOnAppear: false)) { w in Log.writeSelection?(TextSelection(insertionPoint: at("hello", 2))); Log.setFocus?(true); spin(); key(w, "X") }) }),
    ("F5", { print("F5 TextField focused then unfocused (focus=false), binding reads:", runKeepSetup(Probe(initial: "hello")) { w in Log.writeSelection?(TextSelection(range: at("hello", 1)..<at("hello", 3))); spin(); Log.setFocus?(false); spin() }) }),
]

MainActor.assumeIsolated {
    let args = CommandLine.arguments.dropFirst()
    if args.first == "--list" { print(arms.map(\.name).joined(separator: " ")); exit(0) }
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    for a in arms where args.first == a.name || args.isEmpty { a.run() }
}
