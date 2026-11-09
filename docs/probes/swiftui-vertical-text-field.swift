// SwiftUI probe: `TextField(axis: .vertical)` with `lineLimit` ranges, internal scrolling, the wheel, the keys
// and the placeholder colour (Alloy G18; rulings `VT-` in docs/superpowers/2026-11-09-vertical-text-field-decisions.md).
//
// HOW TO RUN (compiled form, SA-O; one arm per argument, S E R W K F P, none runs all):
//
//   xcrun swiftc docs/probes/swiftui-vertical-text-field.swift -o /tmp/vtfield-probe && /tmp/vtfield-probe S E F R W K P
//
// ARMS.
// - S: a vertical `TextField` at width 200 through a custom `Layout` whose `sizeThatFits` is asked a list of proposals
//      (the `Ask` instrument of swiftui-field-chrome.swift): `lineLimit(1...8)` at 0/1/3/8/20 lines, no limit, plain style,
//      a wrapped paragraph, hugging, the floor, `reservesSpace`, `lineLimit(0)`, a trailing newline, a placeholder, font 20,
//      `.controlSize(.small)`, a container's `lineLimit`, the nil ideal, a horizontal field.
// - E: `TextEditor` with and without `lineLimit`.
// - F: the growing-editor recipe `TextEditor.frame(minHeight: 16, maxHeight: 128).fixedSize(horizontal: false, vertical: true)`.
// - R: a real `NSHostingView` window: the frame at 1/3/8/9/20 lines, the clip view inside the field, a scroll indicator, ⌘↓,
//      ⌘↑, a typed character past the cap, text replaced from code, an unfocused field.
// - W: the wheel on a focused field's scroll view (direct AppKit call; window routing is not measured).
// - K: Return, ⇧Return, keypad Enter, ⌥Return, ⌃Return and ⌘Return through `NSApp.sendEvent`, with and without `onSubmit`,
//      in a vertical field and in a `TextEditor`.
// - P: `NSColor.placeholderTextColor` in both appearances, and whether a red field `foregroundStyle` or a red `prompt:`
//      reaches the placeholder's pixels.
//
// POSITIVE CONTROL. S: a `Text("x")` answers its own line height; a single-line horizontal field answers 24 whatever it is
// given. SEPARATING ARM. S: `lineLimit(1...8)` at 20 lines (136) against no limit (328).
//
// RECORDED 2026-11-09 by the G18 implementation session, macOS 27.2, Apple Swift 6.4.2. Run twice, all arms: stdout
// byte-identical (md5 b3e9f1c21b1f74447fa7b7940d00575e), exit 0. A 24-line paragraph is 120 words at width 200.
//
// OUTPUT, verbatim:
//
//   === S vertical TextField sizeThatFits at width 200
//     1...8 0 lines: w200 200x24
//     1...8 1 lines: w200 200x24
//     1...8 3 lines: w200 200x56
//     1...8 8 lines: w200 200x136
//     1...8 20 lines: w200 200x136
//     no limit 20 lines: w200 200x328
//     plain 1 lines: w200 200x16
//     plain 3 lines: w200 200x48
//     plain 8 lines: w200 200x128
//     paragraph 60 words limit 1...8 | none: w200 200x136
//       (same, no limit): w200 200x200
//     paragraph 120 words limit 1...8 | none: w200 200x136
//       (same, no limit): w200 200x392
//     hug 20 lines 1...8 (1000, inf): h1000 200x136  hinf 200x136
//     no limit 20 lines (1000, inf): h1000 200x328  hinf 200x328
//     1...8 20 lines between floor and content: h100 200x100  h80 200x80  h70 200x70
//     floor 1...8 at 10, 0: h10 200x24  h0 200x24
//     floor 2...8: h10 200x40  h0 200x40
//     floor 3...: h10 200x56  h0 200x56
//     floor none: h10 200x10  h0 200x0
//     floor lineLimit(8): h10 200x10  h0 200x0
//     floor ...8: h10 200x10  h0 200x0
//     lineLimit(8) 20 lines: w200 200x136
//     reserves 3 @1 line: w200 200x56
//     reserves 3 @20 lines: w200 200x56
//     reserves 8 @1 line: w200 200x136
//     lineLimit(0): w200 200x24
//     trailing newline 1...8: w200 200x40
//     2-line placeholder, empty text: w200 200x40
//     font 20 @3 lines: w200 200x80
//     small @3 lines: w200 200x50
//     container lineLimit(1...2) @5: w200 200x40
//     nil ideal 'line 1': nil 43x24
//     nil ideal placeholder 'Message': nil 67x24
//     horizontal @3 lines + 1...8: w200 200x24
//   === E TextEditor ignores lineLimit
//     TextEditor 10 lines: w200 200x120
//     TextEditor 10 lines lineLimit(1...3): w200 200x120
//   === F growing-editor recipe at width 200
//     recipe 1 lines: w200 200x16
//     recipe 8 lines: w200 200x96
//     recipe 20 lines: w200 200x128
//   === R real window, vertical TextField 1...8
//     1 lines: field frame 200x24  clip frame (4,4,192,16) bounds.y=4 fieldEditor h=16 scrollers=0
//     3 lines: field frame 200x56  clip frame (4,4,192,48) bounds.y=4 fieldEditor h=48 scrollers=0
//     8 lines: field frame 200x136  clip frame (4,4,192,128) bounds.y=4 fieldEditor h=128 scrollers=0
//     9 lines: field frame 200x136  clip frame (4,4,192,128) bounds.y=4 fieldEditor h=144 scrollers=0
//     20 lines: field frame 200x136  clip frame (4,4,192,128) bounds.y=4 fieldEditor h=320 scrollers=0
//     replaced from code (20 lines): clip frame (4,4,192,128) bounds.y=4 fieldEditor h=320 scrollers=0
//     after cmd-down: clip frame (4,4,192,128) bounds.y=196 fieldEditor h=320 scrollers=0
//     after cmd-up: clip frame (4,4,192,128) bounds.y=4 fieldEditor h=320 scrollers=0
//     typed x at the end: clip frame (4,4,192,128) bounds.y=196 fieldEditor h=320 scrollers=0 tail=line 20x
//     typed y at the top: clip frame (4,4,192,128) bounds.y=4 fieldEditor h=320 scrollers=0
//     unfocused: no NSClipView
//   === W the wheel on a focused field (direct AppKit call)
//     before: clip frame (4,2,192,132) bounds.y=2 fieldEditor h=320 scrollers=0
//     after one wheel step (-40 px): clip frame (4,2,192,132) bounds.y=42 fieldEditor h=320 scrollers=0
//   === K keys: resulting text (U+ escapes) and onSubmit count
//     vertical+onSubmit option-Return: text="abU+000A" submits=0
//     vertical+onSubmit control-Return: text="abU+2028" submits=0
//     vertical+onSubmit command-Return: text="ab" submits=0
//     vertical+onSubmit Return: text="ab" submits=1
//     vertical+onSubmit shift-Return: text="ab" submits=1
//     vertical+onSubmit keypad Enter: text="ab" submits=1
//     vertical, no onSubmit option-Return: text="abU+000A" submits=0
//     vertical, no onSubmit control-Return: text="abU+2028" submits=0
//     vertical, no onSubmit command-Return: text="ab" submits=0
//     vertical, no onSubmit Return: text="ab" submits=0
//     vertical, no onSubmit shift-Return: text="ab" submits=0
//     vertical, no onSubmit keypad Enter: text="ab" submits=0
//     TextEditor option-Return: text="abU+000A" submits=0
//     TextEditor control-Return: text="abU+2028" submits=0
//     TextEditor command-Return: text="ab" submits=0
//     TextEditor Return: text="abU+000A" submits=0
//     TextEditor shift-Return: text="abU+000A" submits=0
//     TextEditor keypad Enter: text="abU+000A" submits=0
//   === P placeholder colour
//     light: placeholderTextColor rgba(0, 0, 0, 0.50)  secondaryLabelColor rgba(0, 0, 0, 0.50)
//     dark: placeholderTextColor rgba(1, 1, 1, 0.55)  secondaryLabelColor rgba(1, 1, 1, 0.55)
//     default: red pixels in the field = 0
//     field foregroundStyle(.red): red pixels in the field = 0
//     prompt Text red: red pixels in the field = 181
//
// READING. Height of a vertical field is 16 per line plus 8 of bordered chrome (16 per line plain), capped at the upper
// bound and floored at the LOWER bound only when there is one; between the floor and the content a proposal is answered
// exactly (not snapped to lines); a nil or infinite height proposal is answered with the content. reservesSpace is
// always the limit; lineLimit(0) acts as 1; a trailing newline and a placeholder's lines count. TextEditor ignores
// lineLimit. The editor recipe (F) grows and then caps at 128. In a window (R) the field is an AppKitTextField whose
// _NSKeyboardFocusClipView is 128 tall (4 pt inset) holding a 320-tall field editor, scrolled by bounds.y (4 at the top, 196 at the
// end), with no scroller; unfocused it is a label drawn from the top (no clip view). W: a wheel step moves a focused field
// by the step. K: Return, shift-Return and keypad Enter submit and insert nothing (SwiftUI also selects all), option-Return
// inserts U+000A, control-Return U+2028, command-Return nothing; a TextEditor inserts U+000A for the first three and
// the same as the field for the modifiers. P: the placeholder is secondaryLabelColor; a prompt: colour reaches it, the field's does not.

import AppKit
import SwiftUI

@MainActor func spin(_ s: Double = 0.3) { RunLoop.main.run(until: Date().addingTimeInterval(s)) }
func f(_ v: CGFloat) -> String {
    if v.isInfinite { return "inf" }
    let r = (v * 100).rounded() / 100
    return r == r.rounded() ? "\(Int(r))" : String(format: "%.2f", Double(r))
}
func f(_ s: CGSize) -> String { "\(f(s.width))x\(f(s.height))" }

final class KeyWindow: NSWindow { override var isKeyWindow: Bool { true }; override var canBecomeKey: Bool { true } }
var windows: [NSWindow] = []
@MainActor func host<V: View>(_ v: V, size: CGSize, dark: Bool = false) -> (NSHostingView<V>, KeyWindow) {
    let w = KeyWindow(contentRect: NSRect(x: 100, y: 100, width: size.width, height: size.height),
                      styleMask: [.titled], backing: .buffered, defer: false)
    w.isReleasedWhenClosed = false
    w.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
    let h = NSHostingView(rootView: v)
    h.sizingOptions = []
    w.contentView = h
    w.setContentSize(size)
    w.makeKeyAndOrderFront(nil)
    h.layoutSubtreeIfNeeded()
    spin(0.5)
    windows.append(w)
    return (h, w)
}

func lines(_ n: Int) -> String { (1...max(n, 1)).map { "line \($0)" }.joined(separator: "\n") }

// MARK: S, E, F — sizeThatFits readings

final class Sink { var out: [String] = [] }
struct Read: Layout {
    let asks: [(String, ProposedViewSize)]
    let sink: Sink
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let s = subviews.first else { return .zero }
        sink.out = asks.map { "\($0.0) \(f(s.sizeThatFits($0.1)))" }
        return s.sizeThatFits(proposal)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews.first?.place(at: bounds.origin, proposal: proposal)
    }
}

@MainActor func read<V: View>(_ name: String, _ v: V, _ asks: [(String, ProposedViewSize)]) {
    let sink = Sink()
    _ = host(Read(asks: asks, sink: sink) { v }, size: CGSize(width: 300, height: 400))
    print("  \(name): " + sink.out.joined(separator: "  "))
}
let w200 = ProposedViewSize(width: 200, height: nil)
func at(_ h: CGFloat) -> (String, ProposedViewSize) { ("h\(Int(h))", ProposedViewSize(width: 200, height: h)) }
let ideal: [(String, ProposedViewSize)] = [("w200", w200)]

@MainActor func vf(_ s: String, placeholder: String = "") -> TextField<Text> {
    TextField(placeholder, text: .constant(s), axis: .vertical)
}

@MainActor func armS() {
    print("=== S vertical TextField sizeThatFits at width 200")
    for n in [0, 1, 3, 8, 20] { read("1...8 \(n) lines", vf(n == 0 ? "" : lines(n)).lineLimit(1...8), ideal) }
    read("no limit 20 lines", vf(lines(20)), ideal)
    for n in [1, 3, 8] { read("plain \(n) lines", vf(lines(n)).textFieldStyle(.plain), ideal) }
    for words in [60, 120] {
        let p = Array(repeating: "word", count: words).joined(separator: " ")
        read("paragraph \(words) words limit 1...8 | none", vf(p).lineLimit(1...8), ideal)
        read("  (same, no limit)", vf(p), ideal)
    }
    read("hug 20 lines 1...8 (1000, inf)", vf(lines(20)).lineLimit(1...8),
         [("h1000", ProposedViewSize(width: 200, height: 1000)), ("hinf", ProposedViewSize(width: 200, height: .infinity))])
    read("no limit 20 lines (1000, inf)", vf(lines(20)),
         [("h1000", ProposedViewSize(width: 200, height: 1000)), ("hinf", ProposedViewSize(width: 200, height: .infinity))])
    read("1...8 20 lines between floor and content", vf(lines(20)).lineLimit(1...8), [at(100), at(80), at(70)])
    let small: [(String, ProposedViewSize)] = [at(10), at(0)]
    read("floor 1...8 at 10, 0", vf(lines(20)).lineLimit(1...8), small)
    read("floor 2...8", vf(lines(20)).lineLimit(2...8), small)
    read("floor 3...", vf(lines(20)).lineLimit(3...), small)
    read("floor none", vf(lines(20)), small)
    read("floor lineLimit(8)", vf(lines(20)).lineLimit(8), small)
    read("floor ...8", vf(lines(20)).lineLimit(...8), small)
    read("lineLimit(8) 20 lines", vf(lines(20)).lineLimit(8), ideal)
    read("reserves 3 @1 line", vf(lines(1)).lineLimit(3, reservesSpace: true), ideal)
    read("reserves 3 @20 lines", vf(lines(20)).lineLimit(3, reservesSpace: true), ideal)
    read("reserves 8 @1 line", vf(lines(1)).lineLimit(8, reservesSpace: true), ideal)
    read("lineLimit(0)", vf(lines(3)).lineLimit(0), ideal)
    read("trailing newline 1...8", vf("a\n").lineLimit(1...8), ideal)
    read("2-line placeholder, empty text", vf("", placeholder: "one\ntwo").lineLimit(1...8), ideal)
    read("font 20 @3 lines", vf(lines(3)).font(.system(size: 20)).lineLimit(1...8), ideal)
    read("small @3 lines", vf(lines(3)).controlSize(.small).lineLimit(1...8), ideal)
    read("container lineLimit(1...2) @5", VStack { vf(lines(5)) }.lineLimit(1...2), ideal)
    read("nil ideal 'line 1'", vf("line 1").lineLimit(1...8), [("nil", .unspecified)])
    read("nil ideal placeholder 'Message'", vf("", placeholder: "Message").lineLimit(1...8), [("nil", .unspecified)])
    read("horizontal @3 lines + 1...8", TextField("", text: .constant(lines(3))).lineLimit(1...8), ideal)
}

@MainActor func armE() {
    print("=== E TextEditor ignores lineLimit")
    read("TextEditor 10 lines", TextEditor(text: .constant(lines(10))), ideal)
    read("TextEditor 10 lines lineLimit(1...3)", TextEditor(text: .constant(lines(10))).lineLimit(1...3), ideal)
}

@MainActor func armF() {
    print("=== F growing-editor recipe at width 200")
    for n in [1, 8, 20] {
        read("recipe \(n) lines", TextEditor(text: .constant(lines(n)))
            .frame(minHeight: 16, maxHeight: 128).fixedSize(horizontal: false, vertical: true), ideal)
    }
}

// MARK: R, W, K — real windows

@MainActor @Observable final class Model { var text = ""; var submits = 0 }
func walk<T: NSView>(_ v: NSView, _ type: T.Type) -> [T] {
    var out: [T] = []
    if let t = v as? T { out.append(t) }
    for s in v.subviews { out += walk(s, type) }
    return out
}
@MainActor func key(_ c: String, _ code: UInt16, _ w: NSWindow, _ mods: NSEvent.ModifierFlags = [], ignoring: String? = nil) {
    for type in [NSEvent.EventType.keyDown, .keyUp] {
        let e = NSEvent.keyEvent(with: type, location: .zero, modifierFlags: mods,
                                 timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: w.windowNumber, context: nil,
                                 characters: c, charactersIgnoringModifiers: ignoring ?? c, isARepeat: false, keyCode: code)!
        NSApp.sendEvent(e); spin(0.12)
    }
}
func esc(_ s: String) -> String {
    s.unicodeScalars.map { $0.value < 32 || $0.value > 126 ? String(format: "U+%04X", $0.value) : String($0) }.joined()
}
var frameLog = CGSize.zero
struct Vertical: View {
    @Bindable var model: Model
    @FocusState var focused: Bool
    var body: some View {
        VStack(alignment: .leading) {
            TextField("", text: $model.text, axis: .vertical).lineLimit(1...8).focused($focused)
                .onSubmit { model.submits += 1 }
                .onGeometryChange(for: CGSize.self, of: { $0.size }) { frameLog = $0 }
            Spacer()
        }.padding(10).frame(width: 220, height: 360).onAppear { focused = true }
    }
}
func dump(_ v: NSView, _ depth: Int = 0) -> String {
    let d = String(repeating: " ", count: depth * 2)
    let own = "\(d)\(type(of: v)) frame=(\(f(v.frame.minX)),\(f(v.frame.minY)),\(f(v.frame.width)),\(f(v.frame.height))) bounds.y=\(f(v.bounds.minY))"
    return ([own] + v.subviews.map { dump($0, depth + 1) }).joined(separator: "\n")
}
func clipInfo(_ h: NSView) -> String {
    guard let c = walk(h, NSClipView.self).first else { return "no NSClipView" }
    let tv = walk(c, NSTextView.self).first
    return "clip frame (\(f(c.frame.minX)),\(f(c.frame.minY)),\(f(c.frame.width)),\(f(c.frame.height))) bounds.y=\(f(c.bounds.minY)) "
        + "fieldEditor h=\(f(tv?.frame.height ?? 0)) scrollers=\(walk(h, NSScroller.self).count)"
}

@MainActor func armR() {
    print("=== R real window, vertical TextField 1...8")
    let model = Model()
    let (h, w) = host(Vertical(model: model), size: CGSize(width: 220, height: 360))
    for n in [1, 3, 8, 9, 20] {
        model.text = lines(n); spin(0.4)
        print("  \(n) lines: field frame \(f(frameLog))  \(clipInfo(h))")
    }
    // Replaced from code: the caret goes to the end without scrolling.
    model.text = lines(20); spin(0.4)
    print("  replaced from code (20 lines): \(clipInfo(h))")
    let cmd: NSEvent.ModifierFlags = .command
    let down = String(UnicodeScalar(0xF701)!), up = String(UnicodeScalar(0xF700)!)
    key(down, 125, w, cmd); spin(0.3); print("  after cmd-down: \(clipInfo(h))")
    key(up, 126, w, cmd); spin(0.3); print("  after cmd-up: \(clipInfo(h))")
    key(down, 125, w, cmd); spin(0.3)
    key("x", 7, w); spin(0.3); print("  typed x at the end: \(clipInfo(h)) tail=\(esc(String(model.text.suffix(8))))")
    model.text = lines(20); spin(0.3)
    key(up, 126, w, cmd); spin(0.2); key("y", 16, w); spin(0.3)
    print("  typed y at the top: \(clipInfo(h))")
    w.makeFirstResponder(nil); spin(0.3)
    print("  unfocused: \(clipInfo(h))")
}

@MainActor func armW() {
    print("=== W the wheel on a focused field (direct AppKit call)")
    let model = Model(); model.text = lines(20)
    let (h, w) = host(Vertical(model: model), size: CGSize(width: 220, height: 360))
    spin(0.3)
    key(String(UnicodeScalar(0xF700)!), 126, w, .command); spin(0.3)
    print("  before: \(clipInfo(h))")
    guard let s = walk(h, NSTextView.self).first,
          let cg = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1, wheel1: -40, wheel2: 0, wheel3: 0),
          let ev = NSEvent(cgEvent: cg) else { print("  no field editor or event"); return }
    s.scrollWheel(with: ev); spin(0.3)
    print("  after one wheel step (-40 px): \(clipInfo(h))")
}

struct Editor: View {
    @Bindable var model: Model
    @FocusState var focused: Bool
    var body: some View {
        TextEditor(text: $model.text).focused($focused).frame(width: 200, height: 100).onAppear { focused = true }
    }
}
struct VerticalNoSubmit: View {
    @Bindable var model: Model
    @FocusState var focused: Bool
    var body: some View {
        TextField("", text: $model.text, axis: .vertical).lineLimit(1...8).focused($focused).frame(width: 200, height: 60)
            .onAppear { focused = true }
    }
}

@MainActor func armK() {
    print("=== K keys: resulting text (U+ escapes) and onSubmit count")
    let cr = "\r", enter = "\u{3}"
    let keys: [(String, String, UInt16, NSEvent.ModifierFlags)] = [
        ("option-Return", cr, 36, .option), ("control-Return", cr, 36, .control), ("command-Return", cr, 36, .command),
        ("Return", cr, 36, []), ("shift-Return", cr, 36, .shift), ("keypad Enter", enter, 76, []),
    ]
    func run(_ label: String, _ make: (Model) -> AnyView) {
        let model = Model()
        let (_, w) = host(make(model), size: CGSize(width: 260, height: 160))
        for (name, chars, code, mods) in keys {
            model.text = "ab"; model.submits = 0; spin(0.25)
            key(chars, code, w, mods, ignoring: chars); spin(0.2)
            print("  \(label) \(name): text=\"\(esc(model.text))\" submits=\(model.submits)")
        }
    }
    run("vertical+onSubmit") { AnyView(Vertical(model: $0)) }
    run("vertical, no onSubmit") { AnyView(VerticalNoSubmit(model: $0)) }
    run("TextEditor") { AnyView(Editor(model: $0)) }
}

// MARK: P — placeholder colour

struct Holder: View {
    let mode: Int
    var body: some View {
        Group {
            switch mode {
            case 1: TextField("Message", text: .constant(""), axis: .vertical).foregroundStyle(.red)
            case 2: TextField("", text: .constant(""), prompt: Text("Message").foregroundStyle(.red), axis: .vertical)
            default: TextField("Message", text: .constant(""), axis: .vertical)
            }
        }.textFieldStyle(.plain).frame(width: 200, height: 40).background(.white)
    }
}
@MainActor func redPixels(_ h: NSView) -> Int {
    guard let rep = h.bitmapImageRepForCachingDisplay(in: h.bounds) else { return -1 }
    h.cacheDisplay(in: h.bounds, to: rep)
    var n = 0
    for y in 0..<rep.pixelsHigh { for x in 0..<rep.pixelsWide {
        var px = [Int](repeating: 0, count: 4); rep.getPixel(&px, atX: x, y: y)
        if px[0] > 120 && px[1] < 100 && px[2] < 100 { n += 1 }
    } }
    return n
}
@MainActor func armP() {
    print("=== P placeholder colour")
    for (label, name) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
        NSAppearance(named: name)!.performAsCurrentDrawingAppearance {
            let c = NSColor.placeholderTextColor.usingColorSpace(.sRGB)!
            let l = NSColor.secondaryLabelColor.usingColorSpace(.sRGB)!
            print("  \(label): placeholderTextColor rgba(\(f(c.redComponent)), \(f(c.greenComponent)), \(f(c.blueComponent)), \(f(c.alphaComponent)))"
                  + "  secondaryLabelColor rgba(\(f(l.redComponent)), \(f(l.greenComponent)), \(f(l.blueComponent)), \(f(l.alphaComponent)))")
        }
    }
    for (label, mode) in [("default", 0), ("field foregroundStyle(.red)", 1), ("prompt Text red", 2)] {
        let (h, _) = host(Holder(mode: mode), size: CGSize(width: 200, height: 40))
        print("  \(label): red pixels in the field = \(redPixels(h))")
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.regular)
app.activate(ignoringOtherApps: true)
let args = Array(CommandLine.arguments.dropFirst())
let arms: [(String, @MainActor () -> Void)] = [("S", armS), ("E", armE), ("F", armF), ("R", armR), ("W", armW), ("K", armK), ("P", armP)]
MainActor.assumeIsolated {
    for (name, run) in arms where args.isEmpty || args.contains(name) { run() }
}
for w in windows { w.close() }
