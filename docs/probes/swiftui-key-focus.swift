// SwiftUI probe: key and focus scoping (rulings KF-* in
// docs/superpowers/2026-10-08-key-focus-decisions.md; spec
// docs/superpowers/specs/2026-10-08-key-focus-design.md).
//
// HOW TO RUN (SA-O's compiled form, as `swiftui-interaction.swift`):
//
//   xcrun swiftc docs/probes/swiftui-key-focus.swift -o /tmp/kf-probe && /tmp/kf-probe
//
// THE INSTRUMENT is `swiftui-interaction.swift`'s: a `FirstMouseHost` in a
// window, `NSEvent`s through `NSWindow.sendEvent` with a run-loop spin
// between events, keys through `NSApp.sendEvent`. The window is a `KeyWindow`
// (`swiftui-input-apis.swift`'s: it answers `isKeyWindow` true) so a
// `TextField`'s field editor takes typed characters. Window coordinates have
// their origin at the BOTTOM left; the window is 200x200.
//
// ARMS AND THEIR CONTROLS.
//   K  — `onKeyPress`. K0 (a focused `.focusable()` view's handler hears `x`)
//        is the control every K arm reads against; K1/K1h separate "needs
//        focus" from "hears every key"; K2/K3 bubbling; K4 a focused
//        TextField against its field editor (K4t, typing with no handler, is
//        the control that the field takes characters at all); K5 phases; K6–
//        K9 the key/character/modifier filters.
//   FC — Does a click focus? FC1 repeats interaction F3 (the control); FC2–
//        FC6 the `interactions:` variants and `.focusEffectDisabled()`.
//   RS — Does a press elsewhere resign a focused TextField? RS0 (the field
//        reports focused=true from onAppear) is the control.
//   G  — `onGeometryChange(for:of:action:)`: the initial call and its order
//        against `onAppear`, a window resize, an unrelated state change.
//   T  — `TimelineView`: `.animation`, `.animation(paused:)`,
//        `.animation(minimumInterval:)`, `.periodic(from:by:)`. Each arm counts
//        content evaluations over a fixed spin; T2 (paused) is the separating
//        arm for "evaluates every frame".
//
// RECORDED 2026-10-08 by the key-focus (C9) designer, macOS 27.0.1 (26A434),
// Apple Swift 6.4 (swiftlang-6.4.0.33.1), screen UNLOCKED (lock probe: no
// CGSSessionScreenIsLocked line, `displayAsleep main: 0`). Compiled form, run
// twice on the final revision (runs 10, 11): stdout byte-identical (69 lines), exit 0,
// stderr empty both times.
//
// INSTRUMENT HISTORY (discarded runs, not answers). Run 1 left each arm's
// window alive behind `orderOut`: the TimelineView arms read 60 evaluations for
// a PAUSED schedule with non-monotonic dates (T1's timeline still running),
// and RS1/RS2 read `focused=false` after a click — neither survived once each
// arm's hosting view is released (`contentView = nil`) and each timeline
// records under its own tag; runs 2–5 agree on every RS line. Run 1's K1
// (a never-focused view hears a key) was macOS's default focus, not "keys
// without focus": K1 logs `focused=true` and K1s/K1t separate it. Runs 2–3
// added K1s–K1w, K2s–K2u; runs 4–5 K2v–K2x (byte-identical). Runs 6–7 added
// K12 and differed from each other only in T1's pre-show count and largest
// gap (display jitter), and printed K4g's Return as a raw carriage return;
// T1 now reports bounds (>= 45 evaluations, median gap) and Return is named.
// Runs 8–9 (byte-identical) preceded G6/G7; runs 10–11 add them and every
// earlier line is unchanged.
//
// macOS Version 27.0.1 (Build 26A434)
// --- K: onKeyPress
//   K0 focused .focusable() view, key x (control): focused=true,k:x[down]
//   K1 same view, never focused, key x: focused=true,k:x[down]
//   K1h never focused, pointer moved over it first, key x: focused=true,k:x[down]
//   K1c never focused, CLICKED first, key x: focused=true,k:x[down]
//   K1s two focusables, A focused, B (handler) not: key x: a=true,a:x[down]
//   K1t two focusables, neither focused by the probe: key x: a=true,a:x[down]
//   K1u two focusables, A focused, pointer moved over B: key x: a=true,a:x[down]
//   K1v focused A; hovered non-focusable region with onKeyPress (right): key x: focused:x[down]
//   K1w two focusables, neither focused, B CLICKED: key x: a=true,a=false,b=true,b:x[down]
//   K2s focused inner .ignored, parent .ignored, sibling and root: key x: focused=true,root:x[down]
//   K2t focused inner .ignored; ancestor .ignored: key x: outer:x[down],inner:x[down]
//   K2u focused inner .ignored; ancestor onKeyPress(keys: [q]): key x, then q: inner:x[down],outer-q:q[down]
//   K2v three levels (root, mid, inner focused), all .ignored: key x: root:x[down],mid:x[down],inner:x[down]
//   K2w one view: .focusable().onKeyPress(A).onKeyPress(B), both .ignored: key x: B:x[down],A:x[down]
//   K2x focused TextField with onKeyPress (field) .ignored inside ancestor .ignored: key z: anc:z[down],field:z[down]
//   K2 focused child returns .handled; ancestor VStack also has onKeyPress: focused=true,outer:x[down]
//   K3 focused child returns .ignored; ancestor VStack .handled: focused=true,outer:x[down]
//   K4t focused TextField "abc", no handler, type z (control): text=z
//   K4a focused TextField onKeyPress (all) .handled, type z: f:z[down]
//   K4b focused TextField onKeyPress (all) .ignored, type z: f:z[down],text=z
//   K4c focused TextField onKeyPress(.upArrow) .handled, up then type z: up,text=z
//   K4d focused TextField onKeyPress(.upArrow) .ignored, up then type z: up,text=zabc
//   K4e focused TextField, ANCESTOR onKeyPress .handled, up then z: anc:up[down],anc:z[down]
//   K4f focused TextField, ANCESTOR onKeyPress .ignored, up then z: anc:up[down],anc:z[down],text=zabc
//   K4g focused TextField onKeyPress (all) .handled, Return: f:return[down]
//   K4h focused TextField onKeyPress (all) .handled, cmd-a: f:a[down+cmd]
//   K5a default phases: down, repeat, up: x[down],x[repeat]
//   K5b phases: .all: down, repeat, up: x[down],x[repeat],x[up]
//   K5c phases: .up: down, repeat, up: x[up]
//   K6 onKeyPress(keys: [.upArrow, "a"]): b, a, up: a[down],up[down]
//   K7 onKeyPress(characters: .decimalDigits): x, 5: 5[down]
//   K8 onKeyPress("a"): a, cmd-a, shift-A: a-fired,a-fired
//   K9 onKeyPress(.upArrow) (no phases arg): down, repeat, up: up,up
//   K12 onKeyPress written BEFORE (inside) .focusable(): key x: -
//   K10 focused view + Button .keyboardShortcut("k", []) elsewhere; view .handled, key k: view:k[down]
//   K11 same, view .ignored, key k: view:k[down],button
// --- FC: does a click focus a focusable view?
//   FC1 .focusable(), click (control, interaction F3): focused=true
//   FC2 .focusable(interactions: .activate), click: -
//   FC3 .focusable(interactions: .edit), click: focused=true
//   FC4 .focusable().focusEffectDisabled(), click: focused=true
//   FC5 .focusable(false), click: -
//   FC6 .focusable() + onTapGesture, click: focused=true,tap
//   FC7 .focusable(interactions: .activate) + onTapGesture, click: tap
// --- RS: press elsewhere while a TextField is focused
//   RS0 field focused in onAppear, no click (control): focused=true,|start
//   RS1 click plain Color (no gesture): focused=true,|start
//   RS2 click Color.onTapGesture: focused=true,|start,tap
//   RS3 click a Button: focused=true,|start,button
//   RS4 click a .focusable() view: below=true,below=false,focused=true,|start,below=true,focused=false
//   RS5 click a DragGesture view (zero-distance): focused=true,|start,drag
// --- G: onGeometryChange(for:of:action:)
//   G1 initial call (old,new form) and order against onAppear: g:200x180->200x180,appear,|shown
//   G1b single-value form, initial: g1:200x200,|shown
//   G2 resize the window to 300x250, spin: g:200x180->200x180,appear,|shown,g:200x180->300x230,|resized
//   G3 unrelated state change (Text below changes, size of blue unchanged): g:200x180->200x180,appear,|shown,|changed
//   G4a frame(in: .global).minX; .offset(x: 10) written AFTER it: x:0,|shown,x:10,|changed
//   G4b frame(in: .global).minX; nothing moves it (control for G4a): x:0,|shown,|idle
//   G6 on a Group of two views (50 and 30 tall): h:88,|shown
//   G7 view removed by an if, then re-inserted: w:40,|shown,|removed,w:40,|back
//   G5 resize in 5 steps 200->300 wide: g:200x180->200x180,appear,|shown,g:200x180->220x180,g:220x180->240x180,g:240x180->260x180,g:260x180->280x180,g:280x180->300x180,|resized
// --- T: TimelineView
//   T1 .animation: evaluations in 0.5s after show >= 45: true, median delta 0.008, monotonic=true
//   T2 .animation(paused: true): evaluations in 0.5s after show: 0 (before: 1)
//   T3 .animation(minimumInterval: 0.1): evaluations in 0.5s after show: 5 (before: 4), min delta 0.100, max delta 0.100, monotonic=true
//   T4 .periodic(from: now, by: 0.1): evaluations in 0.55s after show: 5 (before: 4), min delta 0.100, max delta 0.100, monotonic=true, first dates - start: [0.00 0.10 0.20 0.30 0.40 0.50 0.60 0.70]
//   T5 cadence of .animation (first evaluation): cadence=live
//
// RESULT.
//   K  `onKeyPress` NEEDS FOCUS: a key reaches only handlers on the focused
//      view and its ancestors (K1s, K2s's sibling never hears). Hovering does
//      not route a key (K1u: the pointer over unfocused B, A hears; K1v: a
//      hovered non-focusable region with `onKeyPress` hears nothing). A
//      window's first focusable view is focused by default on macOS (K1,
//      K1t: `focused=true` with no probe write). A click on a focusable view
//      focuses it (K1w).
//      ORDER IS OUTERMOST FIRST: an ancestor's handler runs BEFORE the
//      focused view's (K2t: outer, inner; K2v: root, mid, inner); a handler
//      returning `.handled` stops the walk, so a handling ancestor shadows the
//      child (K2, K3, K2s); on one view the LATER modifier runs first (K2w:
//      B, A); an ancestor filtering to another key lets the child hear it
//      (K2u). A handler written INSIDE `.focusable()` never hears (K12): the
//      focused view is the `.focusable()` layer, and only it and what wraps it
//      are on the path. Every `onKeyPress` — the field's own and its ancestors' — runs
//      BEFORE a focused TextField's editor: `.handled` swallows a typed
//      character (K4a), ↑ (K4c: the select-all survives, so `z` replaces it)
//      and Return (K4g: no submit); `.ignored` lets the field act (K4b, K4d:
//      ↑ moved the caret to the start, so `z` inserted before "abc").
//      Phases default to down + repeat (K5a, K9); `.all` adds up; `.up` alone
//      hears only the release (K5c). `onKeyPress(_ key:)`/`keys:` ignore the
//      modifiers (K8: `a` and cmd-a fire) but compare the character, so
//      shift-A (characters "A") does not match "a"; `characters:` filters by
//      CharacterSet (K7). A handled key does not reach a Button's
//      `keyboardShortcut`; an ignored one does (K10, K11).
//   FC A click focuses `.focusable()` (FC1, F3 again), `.focusable(
//      interactions: .edit)` (FC3) and `.focusable().focusEffectDisabled()`
//      (FC4: the effect is only the look); NOT `.focusable(interactions:
//      .activate)` (FC2, FC7) or `.focusable(false)` (FC5). A tap gesture on a
//      click-focusable view both focuses and taps (FC6).
//   RS A press on non-focusable content does NOT resign a focused TextField:
//      a plain colour (RS1), a tap target (RS2), a Button (RS3) and a drag
//      target (RS5) all leave `focused=true`; only a click on another
//      click-focusable view moves focus (RS4).
//   G  `onGeometryChange` calls its action ONCE with the initial value, BEFORE
//      `onAppear` (G1; the two-argument form passes old == new), then once per
//      changed value: per resize step (G5, five steps five calls), never for an
//      unchanged value (G3). `frame(in: .global)` includes an `.offset`
//      written after the modifier (G4a: 0 → 10; G4b the idle control). On a
//      `Group` of two views it is called ONCE, with the union (G6: 50 + 8 + 30
//      = 88). A view removed and re-inserted gets the initial call again (G7).
//   T  `TimelineView(.animation)` re-evaluates its content every display frame
//      (T1: 60 in 0.5 s, 8 ms apart, cadence `live`, T5); `paused: true`
//      evaluates once and never again (T2); `minimumInterval: 0.1` and
//      `.periodic(from:by: 0.1)` evaluate every 0.1 s, and a periodic date is
//      the schedule's entry, not the clock (T4: dates − start 0.00, 0.10, …).

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
    static func add(_ s: String) { lines.append(s) }
    static func take() -> String {
        defer { lines = [] }
        return lines.isEmpty ? "-" : lines.joined(separator: ",")
    }
}

@MainActor func spin(_ s: Double = 0.15) { RunLoop.main.run(until: Date().addingTimeInterval(s)) }

@MainActor func makeWindow<V: View>(_ view: V, size: CGFloat = 200) -> NSWindow {
    let w = KeyWindow(contentRect: CGRect(x: 200, y: 200, width: size, height: size),
                      styleMask: [.titled, .resizable], backing: .buffered, defer: false)
    w.isReleasedWhenClosed = false
    w.contentView = FirstMouseHost(rootView: view)
    w.makeKeyAndOrderFront(nil)
    spin(0.3)
    return w
}

@MainActor func mouse(_ w: NSWindow, _ t: NSEvent.EventType, _ p: CGPoint) {
    let e = NSEvent.mouseEvent(with: t, location: p, modifierFlags: [],
                               timestamp: ProcessInfo.processInfo.systemUptime,
                               windowNumber: w.windowNumber, context: nil, eventNumber: 0,
                               clickCount: 1, pressure: t == .leftMouseUp ? 0 : 1)!
    w.sendEvent(e)
}

@MainActor func click(_ w: NSWindow, at p: CGPoint) {
    mouse(w, .leftMouseDown, p); spin(0.05); mouse(w, .leftMouseUp, p); spin()
}

@MainActor func keyEvent(_ w: NSWindow, _ type: NSEvent.EventType, _ chars: String,
                         modifiers: NSEvent.ModifierFlags = [], keyCode: UInt16, repeat isRepeat: Bool = false) {
    let e = NSEvent.keyEvent(with: type, location: .zero, modifierFlags: modifiers,
                             timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: w.windowNumber,
                             context: nil, characters: chars, charactersIgnoringModifiers: chars,
                             isARepeat: isRepeat, keyCode: keyCode)!
    NSApp.sendEvent(e)
    spin()
}

@MainActor func key(_ w: NSWindow, _ chars: String, modifiers: NSEvent.ModifierFlags = [], keyCode: UInt16 = 0) {
    keyEvent(w, .keyDown, chars, modifiers: modifiers, keyCode: keyCode)
    keyEvent(w, .keyUp, chars, modifiers: modifiers, keyCode: keyCode)
}

let up = "\u{F700}"
let centre = CGPoint(x: 100, y: 100)
let topPoint = CGPoint(x: 100, y: 185)     // a 200x30 field pinned to the top
let bottomPoint = CGPoint(x: 100, y: 40)

@MainActor func arm<V: View>(_ label: String, _ view: V, _ act: (NSWindow) -> Void) {
    _ = Log.take()
    let w = makeWindow(view)
    act(w)
    print("  \(label): \(Log.take())")
    w.orderOut(nil)
    w.contentView = nil   // stop the hosting view (a TimelineView kept evaluating after orderOut, run 1)
}

// MARK: - K: onKeyPress

func describe(_ p: KeyPress) -> String {
    let c = p.characters == up ? "up" : p.characters == "\r" ? "return" : p.characters
    var mods: [String] = []
    if p.modifiers.contains(.command) { mods.append("cmd") }
    if p.modifiers.contains(.shift) { mods.append("shift") }
    let phase: String
    switch p.phase {
    case .down: phase = "down"
    case .repeat: phase = "repeat"
    case .up: phase = "up"
    default: phase = "?"
    }
    return "\(c)[\(phase)\(mods.isEmpty ? "" : "+" + mods.joined(separator: "+"))]"
}

struct FocusedKeys: View {
    var focusOnAppear = true
    var result: KeyPress.Result = .handled
    @FocusState var focused: Bool
    var body: some View {
        Color.blue.focusable().focused($focused)
            .onKeyPress { p in Log.add("k:" + describe(p)); return result }
            .onAppear { if focusOnAppear { focused = true } }
            .onChange(of: focused) { _, v in Log.add("focused=\(v)") }
    }
}

struct Bubbling: View {
    var inner: KeyPress.Result
    @FocusState var focused: Bool
    var body: some View {
        VStack {
            Color.blue.focusable().focused($focused)
                .onKeyPress { p in Log.add("inner:" + describe(p)); return inner }
        }
        .onKeyPress { p in Log.add("outer:" + describe(p)); return .handled }
        .onAppear { focused = true }
        .onChange(of: focused) { _, v in Log.add("focused=\(v)") }
    }
}

/// Two focusable views; `a` (left) focused in onAppear; `b` (right) has the
/// handler. Separates "needs focus" from "the window's only focusable view
/// hears keys" (run 1: K1 heard a key with nothing focused by the probe).
struct TwoFocusables: View {
    var focusA = true
    @FocusState var a: Bool
    @FocusState var b: Bool
    var body: some View {
        HStack(spacing: 0) {
            Color.gray.focusable().focused($a)
                .onKeyPress { p in Log.add("a:" + describe(p)); return .ignored }
            Color.blue.focusable().focused($b)
                .onKeyPress { p in Log.add("b:" + describe(p)); return .handled }
        }
        .onAppear { if focusA { a = true } }
        .onChange(of: a) { _, v in Log.add("a=\(v)") }
        .onChange(of: b) { _, v in Log.add("b=\(v)") }
    }
}

/// A focused focusable child, and a NON-focusable sibling region with its own
/// onKeyPress under the pointer: does a hovered region hear keys?
struct HoverRegion: View {
    @FocusState var a: Bool
    var body: some View {
        HStack(spacing: 0) {
            Color.gray.focusable().focused($a)
                .onKeyPress { p in Log.add("focused:" + describe(p)); return .ignored }
            Color.blue.onKeyPress { p in Log.add("hovered:" + describe(p)); return .handled }
                .onHover { Log.add("hover=\($0)") }
        }
        .onAppear { a = true }
    }
}

/// Bubbling with the focused child on one side and a non-ancestor handler on
/// the other: only ancestors should hear.
struct BubblingSibling: View {
    @FocusState var focused: Bool
    var body: some View {
        HStack(spacing: 0) {
            VStack {
                Color.blue.focusable().focused($focused)
                    .onKeyPress { p in Log.add("inner:" + describe(p)); return .ignored }
            }
            .onKeyPress { p in Log.add("parent:" + describe(p)); return .ignored }
            Color.gray.onKeyPress { p in Log.add("sibling:" + describe(p)); return .handled }
        }
        .onKeyPress { p in Log.add("root:" + describe(p)); return .handled }
        .onAppear { focused = true }
        .onChange(of: focused) { _, v in Log.add("focused=\(v)") }
    }
}

/// Run 2: with an ancestor `onKeyPress`, the focused child's own handler did
/// not run (K2, K3, K2s). These separate "outermost first" from "the inner
/// handler is shadowed": the ancestor returns `.ignored` (K2t), or filters to
/// another key (K2u), or the child sits two levels down (K2v).
struct OuterIgnores: View {
    var outerKeys: Bool
    @FocusState var focused: Bool
    var body: some View {
        let inner = VStack {
            Color.blue.focusable().focused($focused)
                .onKeyPress { p in Log.add("inner:" + describe(p)); return .ignored }
        }
        Group {
            if outerKeys {
                inner.onKeyPress(keys: ["q"]) { p in Log.add("outer-q:" + describe(p)); return .handled }
            } else {
                inner.onKeyPress { p in Log.add("outer:" + describe(p)); return .ignored }
            }
        }
        .onAppear { focused = true }
    }
}

struct FieldKeys: View {
    var handler: Bool
    var result: KeyPress.Result = .handled
    var onAncestor = false
    var onlyUp = false
    @State var text = "abc"
    @FocusState var focused: Bool
    var body: some View {
        VStack(spacing: 0) {
            field.frame(height: 30)
            Color.gray
        }
        .onKeyPress { p in
            guard onAncestor else { return .ignored }
            Log.add("anc:" + describe(p)); return result
        }
        .onAppear { focused = true }
        .onChange(of: text) { _, v in Log.add("text=\(v)") }
    }
    @ViewBuilder var field: some View {
        let f = TextField("f", text: $text).focused($focused).onSubmit { Log.add("submit") }
        if handler && !onAncestor {
            if onlyUp {
                f.onKeyPress(.upArrow) { Log.add("up"); return result }
            } else {
                f.onKeyPress { p in Log.add("f:" + describe(p)); return result }
            }
        } else {
            f
        }
    }
}

struct Phases: View {
    var phases: KeyPress.Phases?
    @FocusState var focused: Bool
    var body: some View {
        Group {
            if let phases {
                Color.blue.focusable().focused($focused)
                    .onKeyPress(phases: phases) { p in Log.add(describe(p)); return .handled }
            } else {
                Color.blue.focusable().focused($focused)
                    .onKeyPress { p in Log.add(describe(p)); return .handled }
            }
        }
        .onAppear { focused = true }
    }
}

struct Filtered<Inner: View>: View {
    @FocusState var focused: Bool
    let make: (FocusState<Bool>.Binding) -> Inner
    var body: some View { make($focused).onAppear { focused = true } }
}

@MainActor func armK() {
    print("--- K: onKeyPress")
    arm("K0 focused .focusable() view, key x (control)", FocusedKeys()) { key($0, "x", keyCode: 7) }
    arm("K1 same view, never focused, key x", FocusedKeys(focusOnAppear: false)) { key($0, "x", keyCode: 7) }
    arm("K1h never focused, pointer moved over it first, key x", FocusedKeys(focusOnAppear: false)) { w in
        mouse(w, .mouseMoved, centre); spin(); key(w, "x", keyCode: 7)
    }
    arm("K1c never focused, CLICKED first, key x", FocusedKeys(focusOnAppear: false)) { w in
        click(w, at: centre); key(w, "x", keyCode: 7)
    }
    arm("K1s two focusables, A focused, B (handler) not: key x", TwoFocusables()) { key($0, "x", keyCode: 7) }
    arm("K1t two focusables, neither focused by the probe: key x", TwoFocusables(focusA: false)) {
        key($0, "x", keyCode: 7)
    }
    arm("K1u two focusables, A focused, pointer moved over B: key x", TwoFocusables()) { w in
        mouse(w, .mouseMoved, CGPoint(x: 150, y: 100)); spin(); key(w, "x", keyCode: 7)
    }
    arm("K1v focused A; hovered non-focusable region with onKeyPress (right): key x", HoverRegion()) { w in
        mouse(w, .mouseMoved, CGPoint(x: 150, y: 100)); spin(); key(w, "x", keyCode: 7)
    }
    arm("K1w two focusables, neither focused, B CLICKED: key x", TwoFocusables(focusA: false)) { w in
        click(w, at: CGPoint(x: 150, y: 100)); key(w, "x", keyCode: 7)
    }
    arm("K2s focused inner .ignored, parent .ignored, sibling and root: key x", BubblingSibling()) {
        key($0, "x", keyCode: 7)
    }
    arm("K2t focused inner .ignored; ancestor .ignored: key x", OuterIgnores(outerKeys: false)) {
        key($0, "x", keyCode: 7)
    }
    arm("K2u focused inner .ignored; ancestor onKeyPress(keys: [q]): key x, then q", OuterIgnores(outerKeys: true)) { w in
        key(w, "x", keyCode: 7); key(w, "q", keyCode: 12)
    }
    arm("K2v three levels (root, mid, inner focused), all .ignored: key x", Filtered { f in
        VStack {
            VStack {
                Color.blue.focusable().focused(f)
                    .onKeyPress { p in Log.add("inner:" + describe(p)); return .ignored }
            }
            .onKeyPress { p in Log.add("mid:" + describe(p)); return .ignored }
        }
        .onKeyPress { p in Log.add("root:" + describe(p)); return .ignored }
    }) { key($0, "x", keyCode: 7) }
    arm("K2w one view: .focusable().onKeyPress(A).onKeyPress(B), both .ignored: key x", Filtered { f in
        Color.blue.focusable().focused(f)
            .onKeyPress { p in Log.add("A:" + describe(p)); return .ignored }
            .onKeyPress { p in Log.add("B:" + describe(p)); return .ignored }
    }) { key($0, "x", keyCode: 7) }
    arm("K2x focused TextField with onKeyPress (field) .ignored inside ancestor .ignored: key z", Filtered { f in
        VStack {
            TextField("f", text: .constant("abc")).focused(f)
                .onKeyPress { p in Log.add("field:" + describe(p)); return .ignored }
        }
        .onKeyPress { p in Log.add("anc:" + describe(p)); return .ignored }
    }) { key($0, "z", keyCode: 6) }
    arm("K2 focused child returns .handled; ancestor VStack also has onKeyPress", Bubbling(inner: .handled)) {
        key($0, "x", keyCode: 7)
    }
    arm("K3 focused child returns .ignored; ancestor VStack .handled", Bubbling(inner: .ignored)) {
        key($0, "x", keyCode: 7)
    }
    arm("K4t focused TextField \"abc\", no handler, type z (control)", FieldKeys(handler: false)) {
        key($0, "z", keyCode: 6)
    }
    arm("K4a focused TextField onKeyPress (all) .handled, type z", FieldKeys(handler: true)) {
        key($0, "z", keyCode: 6)
    }
    arm("K4b focused TextField onKeyPress (all) .ignored, type z", FieldKeys(handler: true, result: .ignored)) {
        key($0, "z", keyCode: 6)
    }
    arm("K4c focused TextField onKeyPress(.upArrow) .handled, up then type z",
        FieldKeys(handler: true, onlyUp: true)) { w in
        key(w, up, keyCode: 126); key(w, "z", keyCode: 6)
    }
    arm("K4d focused TextField onKeyPress(.upArrow) .ignored, up then type z",
        FieldKeys(handler: true, result: .ignored, onlyUp: true)) { w in
        key(w, up, keyCode: 126); key(w, "z", keyCode: 6)
    }
    arm("K4e focused TextField, ANCESTOR onKeyPress .handled, up then z",
        FieldKeys(handler: true, onAncestor: true)) { w in
        key(w, up, keyCode: 126); key(w, "z", keyCode: 6)
    }
    arm("K4f focused TextField, ANCESTOR onKeyPress .ignored, up then z",
        FieldKeys(handler: true, result: .ignored, onAncestor: true)) { w in
        key(w, up, keyCode: 126); key(w, "z", keyCode: 6)
    }
    arm("K4g focused TextField onKeyPress (all) .handled, Return", FieldKeys(handler: true)) {
        key($0, "\r", keyCode: 36)
    }
    arm("K4h focused TextField onKeyPress (all) .handled, cmd-a", FieldKeys(handler: true)) {
        key($0, "a", modifiers: .command, keyCode: 0)
    }
    arm("K5a default phases: down, repeat, up", Phases(phases: nil)) { w in
        keyEvent(w, .keyDown, "x", keyCode: 7); keyEvent(w, .keyDown, "x", keyCode: 7, repeat: true)
        keyEvent(w, .keyUp, "x", keyCode: 7)
    }
    arm("K5b phases: .all: down, repeat, up", Phases(phases: .all)) { w in
        keyEvent(w, .keyDown, "x", keyCode: 7); keyEvent(w, .keyDown, "x", keyCode: 7, repeat: true)
        keyEvent(w, .keyUp, "x", keyCode: 7)
    }
    arm("K5c phases: .up: down, repeat, up", Phases(phases: .up)) { w in
        keyEvent(w, .keyDown, "x", keyCode: 7); keyEvent(w, .keyDown, "x", keyCode: 7, repeat: true)
        keyEvent(w, .keyUp, "x", keyCode: 7)
    }
    arm("K6 onKeyPress(keys: [.upArrow, \"a\"]): b, a, up", Filtered { f in
        Color.blue.focusable().focused(f)
            .onKeyPress(keys: [.upArrow, "a"]) { p in Log.add(describe(p)); return .handled }
    }) { w in key(w, "b", keyCode: 11); key(w, "a", keyCode: 0); key(w, up, keyCode: 126) }
    arm("K7 onKeyPress(characters: .decimalDigits): x, 5", Filtered { f in
        Color.blue.focusable().focused(f)
            .onKeyPress(characters: .decimalDigits) { p in Log.add(describe(p)); return .handled }
    }) { w in key(w, "x", keyCode: 7); key(w, "5", keyCode: 23) }
    arm("K8 onKeyPress(\"a\"): a, cmd-a, shift-A", Filtered { f in
        Color.blue.focusable().focused(f)
            .onKeyPress("a") { Log.add("a-fired"); return .handled }
    }) { w in
        key(w, "a", keyCode: 0); key(w, "a", modifiers: .command, keyCode: 0)
        key(w, "A", modifiers: .shift, keyCode: 0)
    }
    arm("K9 onKeyPress(.upArrow) (no phases arg): down, repeat, up", Filtered { f in
        Color.blue.focusable().focused(f)
            .onKeyPress(.upArrow) { Log.add("up"); return .handled }
    }) { w in
        keyEvent(w, .keyDown, up, keyCode: 126); keyEvent(w, .keyDown, up, keyCode: 126, repeat: true)
        keyEvent(w, .keyUp, up, keyCode: 126)
    }
    arm("K12 onKeyPress written BEFORE (inside) .focusable(): key x", Filtered { f in
        Color.blue.onKeyPress { p in Log.add("inside:" + describe(p)); return .handled }
            .focusable().focused(f)
    }) { key($0, "x", keyCode: 7) }
    arm("K10 focused view + Button .keyboardShortcut(\"k\", []) elsewhere; view .handled, key k", Filtered { f in
        VStack {
            Color.blue.focusable().focused(f)
                .onKeyPress { p in Log.add("view:" + describe(p)); return .handled }
            Button("K") { Log.add("button") }.keyboardShortcut("k", modifiers: [])
        }
    }) { key($0, "k", keyCode: 40) }
    arm("K11 same, view .ignored, key k", Filtered { f in
        VStack {
            Color.blue.focusable().focused(f)
                .onKeyPress { p in Log.add("view:" + describe(p)); return .ignored }
            Button("K") { Log.add("button") }.keyboardShortcut("k", modifiers: [])
        }
    }) { key($0, "k", keyCode: 40) }
}

// MARK: - FC: does a click focus?

struct ClickFocus<V: View>: View {
    @FocusState var focused: Bool
    let make: (FocusState<Bool>.Binding) -> V
    var body: some View {
        make($focused).onChange(of: focused) { _, v in Log.add("focused=\(v)") }
    }
}

@MainActor func armFC() {
    print("--- FC: does a click focus a focusable view?")
    arm("FC1 .focusable(), click (control, interaction F3)", ClickFocus { f in
        Color.blue.focusable().focused(f) }) { click($0, at: centre) }
    arm("FC2 .focusable(interactions: .activate), click", ClickFocus { f in
        Color.blue.focusable(interactions: .activate).focused(f) }) { click($0, at: centre) }
    arm("FC3 .focusable(interactions: .edit), click", ClickFocus { f in
        Color.blue.focusable(interactions: .edit).focused(f) }) { click($0, at: centre) }
    arm("FC4 .focusable().focusEffectDisabled(), click", ClickFocus { f in
        Color.blue.focusable().focusEffectDisabled().focused(f) }) { click($0, at: centre) }
    arm("FC5 .focusable(false), click", ClickFocus { f in
        Color.blue.focusable(false).focused(f) }) { click($0, at: centre) }
    arm("FC6 .focusable() + onTapGesture, click", ClickFocus { f in
        Color.blue.focusable().focused(f).onTapGesture { Log.add("tap") } }) { click($0, at: centre) }
    arm("FC7 .focusable(interactions: .activate) + onTapGesture, click", ClickFocus { f in
        Color.blue.focusable(interactions: .activate).focused(f).onTapGesture { Log.add("tap") } }) {
        click($0, at: centre)
    }
}

// MARK: - RS: does a press elsewhere resign a focused TextField?

struct Resign<Below: View>: View {
    @State var text = "abc"
    @FocusState var focused: Bool
    let below: Below
    var body: some View {
        VStack(spacing: 0) {
            TextField("f", text: $text).focused($focused).frame(height: 30)
            below
        }
        .onAppear { focused = true }
        .onChange(of: focused) { _, v in Log.add("focused=\(v)") }
    }
}

struct FocusableBelow: View {
    @FocusState var f: Bool
    var body: some View {
        Color.blue.focusable().focused($f).onChange(of: f) { _, v in Log.add("below=\(v)") }
    }
}

@MainActor func armRS() {
    print("--- RS: press elsewhere while a TextField is focused")
    arm("RS0 field focused in onAppear, no click (control)", Resign(below: Color.gray)) { _ in Log.add("|start") }
    arm("RS1 click plain Color (no gesture)", Resign(below: Color.gray)) { w in
        Log.add("|start"); click(w, at: bottomPoint); key(w, "z", keyCode: 6)
    }
    arm("RS2 click Color.onTapGesture", Resign(below: Color.gray.onTapGesture { Log.add("tap") })) { w in
        Log.add("|start"); click(w, at: bottomPoint)
    }
    arm("RS3 click a Button", Resign(below: Button("B") { Log.add("button") }.frame(maxHeight: .infinity))) { w in
        Log.add("|start"); click(w, at: CGPoint(x: 100, y: 85))
    }
    arm("RS4 click a .focusable() view", Resign(below: FocusableBelow())) { w in
        Log.add("|start"); click(w, at: bottomPoint)
    }
    arm("RS5 click a DragGesture view (zero-distance)", Resign(below: Color.gray
        .gesture(DragGesture(minimumDistance: 0).onEnded { _ in Log.add("drag") }))) { w in
        Log.add("|start"); click(w, at: bottomPoint)
    }
}

// MARK: - G: onGeometryChange

final class Holder: ObservableObject { @Published var n = 0 }

struct Geo: View {
    @ObservedObject var holder: Holder
    var body: some View {
        VStack(spacing: 0) {
            Color.blue
                .onGeometryChange(for: CGSize.self, of: { $0.size }) { old, new in
                    Log.add("g:\(Int(old.width))x\(Int(old.height))->\(Int(new.width))x\(Int(new.height))")
                }
                .onAppear { Log.add("appear") }
            Text("n=\(holder.n)").frame(height: 20)
        }
    }
}

struct GeoOne: View {
    var body: some View {
        Color.blue
            .onGeometryChange(for: CGSize.self, of: { $0.size }) { new in Log.add("g1:\(Int(new.width))x\(Int(new.height))") }
    }
}

struct GeoOrigin: View {
    @ObservedObject var holder: Holder
    var offsetOnly: Bool
    var body: some View {
        HStack(spacing: 0) {
            Color.blue.frame(width: 50, height: 50)
                .onGeometryChange(for: CGFloat.self, of: { $0.frame(in: .global).minX }) { new in
                    Log.add("x:\(Int(new))")
                }
                .offset(x: offsetOnly ? CGFloat(holder.n * 10) : 0)
            Spacer().frame(width: offsetOnly ? 0 : CGFloat(holder.n * 10))
            Spacer()
        }
    }
}

struct GeoGroup: View {
    var body: some View {
        VStack(spacing: 0) {
            Group {
                Color.blue.frame(height: 50)
                Color.red.frame(height: 30)
            }
            .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { new in Log.add("h:\(Int(new))") }
            Spacer()
        }
    }
}

struct GeoToggle: View {
    @ObservedObject var holder: Holder
    var body: some View {
        VStack {
            if holder.n % 2 == 0 {
                Color.blue.frame(width: 40, height: 40)
                    .onGeometryChange(for: CGFloat.self, of: { $0.size.width }) { new in Log.add("w:\(Int(new))") }
            }
            Spacer()
        }
    }
}

@MainActor func armG() {
    print("--- G: onGeometryChange(for:of:action:)")
    let h = Holder()
    arm("G1 initial call (old,new form) and order against onAppear", Geo(holder: h)) { _ in Log.add("|shown") }
    arm("G1b single-value form, initial", GeoOne()) { _ in Log.add("|shown") }
    let h2 = Holder()
    arm("G2 resize the window to 300x250, spin", Geo(holder: h2)) { w in
        Log.add("|shown"); w.setContentSize(CGSize(width: 300, height: 250)); spin(0.3); Log.add("|resized")
    }
    let h3 = Holder()
    arm("G3 unrelated state change (Text below changes, size of blue unchanged)", Geo(holder: h3)) { _ in
        Log.add("|shown"); h3.n = 1; spin(0.3); Log.add("|changed")
    }
    let h4 = Holder()
    arm("G4a frame(in: .global).minX; .offset(x: 10) written AFTER it", GeoOrigin(holder: h4, offsetOnly: true)) { _ in
        Log.add("|shown"); h4.n = 1; spin(0.3); Log.add("|changed")
    }
    let h6 = Holder()
    arm("G4b frame(in: .global).minX; nothing moves it (control for G4a)", GeoOrigin(holder: h6, offsetOnly: false)) { _ in
        Log.add("|shown"); spin(0.3); Log.add("|idle")
    }
    arm("G6 on a Group of two views (50 and 30 tall)", GeoGroup()) { _ in Log.add("|shown") }
    let h7 = Holder()
    arm("G7 view removed by an if, then re-inserted", GeoToggle(holder: h7)) { _ in
        Log.add("|shown"); h7.n = 1; spin(0.3); Log.add("|removed"); h7.n = 2; spin(0.3); Log.add("|back")
    }
    let h5 = Holder()
    arm("G5 resize in 5 steps 200->300 wide", Geo(holder: h5)) { w in
        Log.add("|shown")
        for i in 1...5 { w.setContentSize(CGSize(width: 200 + 20 * i, height: 200)); spin(0.05) }
        spin(0.2); Log.add("|resized")
    }
}

// MARK: - T: TimelineView

final class Counter {
    nonisolated(unsafe) static var tag = 0
    nonisolated(unsafe) static var dates: [Date] = []
}

/// Each arm's view carries its tag and records only while it is current, so a
/// window from an earlier arm cannot add to a later count (run 1's T2 read 60
/// with a non-monotonic date sequence: T1's timeline was still evaluating).
struct Timeline<S: TimelineSchedule>: View {
    let schedule: S
    let tag: Int
    var body: some View {
        TimelineView(schedule) { ctx in
            let _ = (tag == Counter.tag ? Counter.dates.append(ctx.date) : ())
            Color.blue
        }
    }
}

struct Cadence: View {
    var body: some View {
        TimelineView(.animation) { ctx in
            let _ = Log.lines.isEmpty ? Log.add("cadence=\(ctx.cadence)") : ()
            Color.blue
        }
    }
}

@MainActor func tarm<S: TimelineSchedule>(_ label: String, _ schedule: S, seconds: Double = 0.5,
                                           start: Date? = nil, live: Bool = false) {
    Counter.tag += 1
    Counter.dates = []
    let w = makeWindow(Timeline(schedule: schedule, tag: Counter.tag))
    let n0 = Counter.dates.count
    spin(seconds)
    let ds = Counter.dates
    let n = ds.count - n0
    // Run 6/7: T1's count before the show (36/37) and its largest gap (8/17 ms)
    // jitter with the display; a live schedule reports its bounds instead.
    var line: String
    if live {
        let deltas = zip(ds.dropFirst(), ds).map { $0.timeIntervalSince($1) }.sorted()
        let median = deltas.isEmpty ? 0 : deltas[deltas.count / 2]
        line = "evaluations in \(seconds)s after show >= 45: \(n >= 45), median delta \(String(format: "%.3f", median))"
        line += ", monotonic=\(deltas.allSatisfy { $0 >= 0 })"
    } else {
        line = "evaluations in \(seconds)s after show: \(n) (before: \(n0))"
    }
    if !live, ds.count >= 2 {
        let deltas = zip(ds.dropFirst(), ds).map { $0.timeIntervalSince($1) }
        line += String(format: ", min delta %.3f, max delta %.3f", deltas.min()!, deltas.max()!)
        line += ", monotonic=\(deltas.allSatisfy { $0 >= 0 })"
    }
    if let start {
        let offs = ds.prefix(8).map { String(format: "%.2f", $0.timeIntervalSince(start)) }
        line += ", first dates - start: [\(offs.joined(separator: " "))]"
    }
    print("  \(label): \(line)")
    w.orderOut(nil)
    w.contentView = nil
}

@MainActor func armT() {
    print("--- T: TimelineView")
    tarm("T1 .animation", .animation, live: true)
    tarm("T2 .animation(paused: true)", .animation(minimumInterval: nil, paused: true))
    tarm("T3 .animation(minimumInterval: 0.1)", .animation(minimumInterval: 0.1, paused: false))
    let start = Date()
    tarm("T4 .periodic(from: now, by: 0.1)", .periodic(from: start, by: 0.1), seconds: 0.55, start: start)
    arm("T5 cadence of .animation (first evaluation)", Cadence()) { _ in }
}

// MARK: - run

@MainActor func run() {
    print("macOS \(ProcessInfo.processInfo.operatingSystemVersionString)")
    armK(); armFC(); armRS(); armG(); armT()
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    app.activate(ignoringOtherApps: true)
    run()
}
exit(0)
