// SwiftUI probe: controls inside SwiftUI stacks (proposal-controls design,
// rulings PE-… in docs/superpowers/2026-10-06-proposal-controls-decisions.md).
//
// QUESTIONS.
// - FLEX: each control's answer to six proposals — zero (0x0), unspecified
//   (nil x nil, the ideal size), infinity, 200 x nil, nil x 200 and 50 x nil —
//   which says, per axis, whether it hugs (ideal = min = max), is greedy
//   (answers any finite offer) or compresses.
// - FORM: the frames of a representative form (VStack of HStacks holding
//   Text, TextField, Toggle, Button, Slider, Picker, Stepper, Divider and
//   Spacer) in a 400-wide window, read in one named coordinate space.
// - STATUS: the SMK configurator's status bar (HStack(spacing: 16) with a
//   nested HStack(spacing: 6), Texts, a Spacer, padding 16 horizontally and a
//   26-point flexible frame) in a 600-wide window.
// - MODS: modifiers a control needs in a stack — .padding, .frame(width:),
//   .disabled, .help, .keyboardShortcut, .buttonStyle(.plain),
//   .pickerStyle(.segmented), .controlSize(.small) — and what each does to
//   the control's frame in an HStack.
// - SPLIT: two greedy controls side by side (TextField + TextField,
//   TextField + Slider) and two hugging ones (Button + Button), the separating
//   arm between "greedy" and "hugs".
//
// INSTRUMENTS.
// - FLEX: a custom `Layout` (`Ask`) whose `sizeThatFits` calls
//   `subviews[0].sizeThatFits(_:)` with each proposal and records the answer
//   before answering its own proposal. Printed as WxH, rounded to 0.01.
// - FORM/STATUS/MODS/SPLIT: `.onGeometryChange(for: CGRect.self)` on each
//   control reading `frame(in: .named("root"))`, printed sorted by name.
//
// POSITIVE CONTROLS. FX0 `Color.red` must answer every proposal with the
// proposal itself (10x10 for unspecified — SwiftUI's default for nil), and
// FX1 `Color.red.frame(width: 30, height: 20)` 30x20 for every proposal; both
// read as expected, so the `Ask` instrument reports the child's answers.
// FX2 `Text("Go")` reads 17x16 unspecified (`BT2` of
// `swiftui-controls-and-selection.swift` read the same size another way).
// SEPARATING ARM. SP0/SP1 (greedy pairs split the width) vs SP2 (hugging
// pair keeps its ideal widths) — they separate, so the FLEX verdicts below
// are visible in a stack too.
//
// HOW TO RUN (ruling SA-O's compiled form; the script form fails to JIT on
// this machine, as recorded in swiftui-controls-and-selection.swift):
//
//   xcrun swiftc docs/probes/swiftui-controls-in-stacks.swift -o /tmp/pe-probe && /tmp/pe-probe
//
// RECORDED 2026-10-06 on macOS 27.0.1 (26A434), Apple Swift 6.4
// (swiftlang-6.4.0.33.1), screen unlocked (`appkit-screen-lock-state.swift`:
// no CGSSessionScreenIsLocked line, `displayAsleep main: 0`), compiled form.
// Run three times by the design session; the three outputs (95 lines) are
// byte-identical.
//
// READING (the authority for rulings PE-C, PE-D and PE-K):
// - Positive controls read as expected: FX0 answers every proposal itself
//   (10x10 for nil), FX1 30x20 everywhere, FX2 `Text("Go")` 17.50x16 (the
//   ceiled width, divergence 60).
// - FLEX, by class. HUGS on both axes (ideal = answer at inf = answer at a
//   finite offer): Button (41.50x24), `.plain` Button (the label, 17.50x16),
//   Toggle (53.50x16.42), Stepper (50x24), every Picker style (.menu
//   124.50x24, .segmented 159.50x24, .radioGroup 98x38.84), Menu (93x24) and
//   every modifier arm on a Button (FL15-FL20: padding adds, frame(width:)
//   fixes, disabled/help/keyboardShortcut change nothing, controlSize(.small)
//   shrinks to 35x20). GREEDY WIDTH (answers any finite width AND `inf` at
//   an infinite one; ideal at nil): TextField (ideal 47.50x24 placeholder,
//   43x24 "Hello"; inf -> infx24), Slider (ideal 30x16; inf -> infx16),
//   Divider in a VStack (ideal 10x1; inf -> infx1). GREEDY BOTH:
//   TextEditor (ideal 0x12; inf -> infxinf; h200 -> 0x200), List(selection:)
//   (ideal 0x0; inf -> infxinf). The infinite answer is load-bearing: a
//   stack orders its children by flexibility, measured at an infinite
//   proposal (CN-B), so a greedy control is served LAST — FM0's c2 slider
//   gets 321 = 368 - 39 - 8 beside its 39-wide label.
// - Below the ideal (zero, w50): Button compresses to 10x8 at zero, Toggle
//   wraps its label (43x32 at 50), a menu Picker and a Menu shrink to 50
//   (the Picker wrapping to 64 tall, the Menu staying one line), TextField
//   and Slider take the 50. Text wraps per the existing ProposalText rules
//   (FX3: 49.50x48 at 50).
// - FORM (FM0): VStack(alignment: .leading) rows stack with spacing 8 plus a
//   text-derived extra (48.15, 76.89, 101.04 — the CN-H note: MetalUI does
//   not adopt it); a Toggle/Spacer/Button row puts the Button at the trailing
//   edge (325 = 384 - 59); a TextField beside a label takes the rest
//   (324.50); the Divider spans 368; the Stepper hugs (50x24).
// - FM1's printed caption is wrong (kept so the output stays comparable):
//   Form1 is a two-row form with no Spacer; it reads that a VStack offered a
//   300-tall window hugs its content (63 tall).
// - STATUS (ST0): HStack(spacing: 16) of an HStack(spacing: 6) {dot, Text},
//   three Texts, a Spacer and a Text, padded 16 horizontally in a 26-tall
//   flexible frame: x = 16, 128, 218, 275.50, 411 (the trailing Text ends at
//   584 = 600 - 16); text 14 tall at size 11.
// - IN (instrument check): IN1 shows `.onGeometryChange` on a Spacer turns it
//   into an ordinary view (the row hugs at 33.50 and the Spacer is 0 wide),
//   so no FORM/STATUS arm tags a Spacer — the separating arm for the frame
//   reader.
// - SPLIT (the separating arm between greedy and hugging): two greedy
//   controls split 300 as 146 + 8 + 146 (SP0, SP1); two Buttons keep their
//   ideals 41.50 and 107.50 (SP2).
// - MODS: in an HStack beside a Text each modifier gives the FLEX answer
//   (MD0 57.50x40, MD1 120x24, MD2 17.50x16, MD3 159.50x24, MD4 41.50x24).
//
// OUTPUT (third run):
//
//   --- FLEX (child.sizeThatFits at each proposal)
//     FX0 control Color.red: zero 0x0  ideal 10x10  inf infxinf  w200 200x10  h200 10x200  w50 50x10
//     FX1 control Color.red.frame(30x20): zero 30x20  ideal 30x20  inf 30x20  w200 30x20  h200 30x20  w50 30x20
//     FX2 control Text("Go"): zero 0x0  ideal 17.50x16  inf 17.50x16  w200 17.50x16  h200 17.50x16  w50 17.50x16
//     FX3 Text("A much longer label"): zero 0x0  ideal 120.50x16  inf 120.50x16  w200 120.50x16  h200 120.50x16  w50 49.50x48
//     FL0 Button("Go"): zero 10x8  ideal 41.50x24  inf 41.50x24  w200 41.50x24  h200 41.50x24  w50 41.50x24
//     FL1 Button("Go").buttonStyle(.plain): zero 0x0  ideal 17.50x16  inf 17.50x16  w200 17.50x16  h200 17.50x16  w50 17.50x16
//     FL2 Toggle("Wi-Fi"): zero 21x16.42  ideal 53.50x16.42  inf 53.50x16.42  w200 53.50x16.42  h200 53.50x16.42  w50 43x32
//     FL3 TextField("Name") empty: zero 0x24  ideal 47.50x24  inf infx24  w200 200x24  h200 47.50x24  w50 50x24
//     FL4 TextField text Hello: zero 0x24  ideal 43x24  inf infx24  w200 200x24  h200 43x24  w50 50x24
//     FL5 TextEditor: zero 0x0  ideal 0x12  inf infxinf  w200 200x12  h200 0x200  w50 50x12
//     FL6 Slider: zero 20x16  ideal 30x16  inf infx16  w200 200x16  h200 30x16  w50 50x16
//     FL7 Stepper("Qty"): zero 28x24  ideal 50x24  inf 50x24  w200 50x24  h200 50x24  w50 50x24
//     FL8 Picker .menu: zero 41.50x24  ideal 124.50x24  inf 124.50x24  w200 124.50x24  h200 124.50x24  w50 50x64
//     FL9 Picker .segmented: zero 118.50x24  ideal 159.50x24  inf 159.50x24  w200 159.50x24  h200 159.50x24  w50 118.50x64
//     FL10 Picker .radioGroup: zero 29x38.84  ideal 98x38.84  inf 98x38.84  w200 98x38.84  h200 98x38.84  w50 50x150
//     FL11 Divider in VStack context: zero 0x1  ideal 10x1  inf infx1  w200 200x1  h200 10x1  w50 50x1
//     FL13 Menu("Actions"): zero 33.50x24  ideal 93x24  inf 93x24  w200 93x24  h200 93x24  w50 50x24
//     FL14 List(selection:) 3 rows: zero 0x0  ideal 0x0  inf infxinf  w200 200x0  h200 0x200  w50 50x0
//     FL15 Button("Go").padding(8): zero 26x24  ideal 57.50x40  inf 57.50x40  w200 57.50x40  h200 57.50x40  w50 50x40
//     FL16 Button("Go").frame(width: 120): zero 120x24  ideal 120x24  inf 120x24  w200 120x24  h200 120x24  w50 120x24
//     FL17 Button("Go").disabled(true): zero 10x8  ideal 41.50x24  inf 41.50x24  w200 41.50x24  h200 41.50x24  w50 41.50x24
//     FL18 Button("Go").help("tip"): zero 10x8  ideal 41.50x24  inf 41.50x24  w200 41.50x24  h200 41.50x24  w50 41.50x24
//     FL19 Button("Go").keyboardShortcut(.defaultAction): zero 10x8  ideal 41.50x24  inf 41.50x24  w200 41.50x24  h200 41.50x24  w50 41.50x24
//     FL20 Button("Go").controlSize(.small): zero 10x6  ideal 35x20  inf 35x20  w200 35x20  h200 35x20  w50 35x20
//     FL21 Toggle("Wi-Fi").frame(maxWidth: .infinity): zero 21x16.42  ideal 53.50x16.42  inf infx16.42  w200 200x16.42  h200 53.50x16.42  w50 50x32
//   --- FORM (frames in the root space, 400-wide window; the form at its ideal height)
//     FM0 form:
//       a0 row (16, 16, 368, 24)
//       a1 label (16, 20, 35.50, 16)
//       a2 textField (59.50, 16, 324.50, 24)
//       b0 row (16, 48.15, 368, 24)
//       b1 toggle (16, 51.94, 70, 16.42)
//       b3 button (325, 48.15, 59, 24)
//       c0 row (16, 76.89, 368, 16)
//       c1 label (16, 76.89, 39, 16)
//       c2 slider (63, 76.89, 321, 16)
//       d1 picker (16, 101.04, 124.50, 24)
//       e1 divider (16, 133.04, 368, 1)
//       f0 row (16, 142.04, 368, 24)
//       f1 stepper (16, 142.04, 50, 24)
//       z form (0, 0, 400, 182.04)
//   --- FORM1 (the same form offered a fixed 300-point height: a Spacer row takes the slack)
//     FM1 form, 300 tall:
//       b0 row (16, 16, 368, 24)
//       b1 toggle (16, 19.79, 70, 16.42)
//       b3 button (325, 16, 59, 24)
//       e1 divider (16, 46, 368, 1)
//       z form (0, 0, 400, 63)
//   --- STATUS (600-wide window)
//     ST0 status bar:
//       a1 group (16, 6, 96, 14)
//       a2 dot (16, 9.50, 7, 7)
//       a3 usb (29, 6, 83, 14)
//       b design (128, 6, 74, 14)
//       c layers (218, 6, 41.50, 14)
//       d fw (275.50, 6, 40.50, 14)
//       f dirty (411, 6, 173, 14)
//       z bar (0, 0, 600, 26)
//   --- IN (instrument check: a Spacer carrying the frame reader, 300-wide window)
//     IN0 HStack { Text; Spacer(); Text }:
//       0 row (0, 0, 300, 16)
//       1 a (0, 0, 9, 16)
//       3 b (291.50, 0, 8.50, 16)
//     IN1 HStack { Text; Spacer().onGeometryChange; Text }:
//       0 row (0, 0, 33.50, 40)
//       1 a (0, 12, 9, 16)
//       2 spacer (17, 0, 0, 40)
//       3 b (25, 12, 8.50, 16)
//   --- SPLIT (HStack in a 300-wide window)
//     SP0 TextField + TextField:
//       1 a (0, 0, 146, 24)
//       2 b (154, 0, 146, 24)
//     SP1 TextField + Slider:
//       1 field (0, 0, 146, 24)
//       2 slider (154, 4, 146, 16)
//     SP2 Button + Button:
//       1 go (0, 0, 41.50, 24)
//       2 longer (49.50, 0, 107.50, 24)
//   --- MODS (in an HStack with a Text, 300-wide window)
//     MD0 .padding(8):
//       1 text (0, 12, 7.50, 16)
//       2 button (15.50, 0, 57.50, 40)
//     MD1 .frame(width: 120):
//       1 text (0, 4, 7.50, 16)
//       2 button (15.50, 0, 120, 24)
//     MD2 .buttonStyle(.plain):
//       1 text (0, 0, 7.50, 16)
//       2 button (15.50, 0, 17.50, 16)
//     MD3 .pickerStyle(.segmented):
//       1 text (0, 4, 7.50, 16)
//       2 picker (15.50, 0, 159.50, 24)
//     MD4 .disabled(true).help("tip"):
//       1 text (0, 4, 7.50, 16)
//       2 button (15.50, 0, 41.50, 24)

import AppKit
import SwiftUI

@MainActor func spin(_ s: Double = 0.3) { RunLoop.main.run(until: Date().addingTimeInterval(s)) }
func f(_ v: CGFloat) -> String {
    if v.isInfinite { return "inf" }
    let r = (v * 100).rounded() / 100
    return r == r.rounded() ? "\(Int(r))" : String(format: "%.2f", Double(r))
}
func f(_ s: CGSize) -> String { "\(f(s.width))x\(f(s.height))" }
func f(_ r: CGRect) -> String { "(\(f(r.minX)), \(f(r.minY)), \(f(r.width)), \(f(r.height)))" }

var windows: [NSWindow] = []
@MainActor func host<V: View>(_ v: V, size: CGSize) -> NSHostingView<V> {
    let w = NSWindow(contentRect: NSRect(x: 100, y: 100, width: size.width, height: size.height),
                     styleMask: [.titled], backing: .buffered, defer: false)
    w.isReleasedWhenClosed = false
    let h = NSHostingView(rootView: v)
    h.sizingOptions = []
    w.contentView = h
    w.setContentSize(size)
    w.orderFrontRegardless()
    h.layoutSubtreeIfNeeded()
    spin(0.4)
    windows.append(w)
    return h
}

final class Log { var answers: [String] = []; var frames: [String: CGRect] = [:] }
let log = Log()

// MARK: - FLEX

struct Ask: Layout {
    let name: String
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let s = subviews.first else { return .zero }
        let asks: [(String, ProposedViewSize)] = [
            ("zero", .zero), ("ideal", .unspecified), ("inf", .infinity),
            ("w200", ProposedViewSize(width: 200, height: nil)),
            ("h200", ProposedViewSize(width: nil, height: 200)),
            ("w50", ProposedViewSize(width: 50, height: nil)),
        ]
        let parts = asks.map { "\($0.0) \(f(s.sizeThatFits($0.1)))" }
        let line = "\(name): " + parts.joined(separator: "  ")
        if !log.answers.contains(line) { log.answers.append(line) }
        return s.sizeThatFits(proposal)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews.first?.place(at: bounds.origin, proposal: proposal)
    }
}

struct FlexModel { var text = ""; var hello = "Hello"; var on = false; var value = 5.0; var pick = 0; var qty = 1; var sel: Int? = nil }

@MainActor func flex<V: View>(_ name: String, _ v: V) {
    _ = host(Ask(name: name) { v }, size: CGSize(width: 300, height: 200))
}

// MARK: - frames

struct Tag: ViewModifier {
    let name: String
    func body(content: Content) -> some View {
        content.onGeometryChange(for: CGRect.self) { $0.frame(in: .named("root")) } action: { r in
            log.frames[name] = r
        }
    }
}
extension View { func tag(as name: String) -> some View { modifier(Tag(name: name)) } }

@MainActor func frames<V: View>(_ label: String, _ v: V, size: CGSize) {
    log.frames = [:]
    _ = host(v.coordinateSpace(.named("root")).frame(width: size.width, height: size.height, alignment: .topLeading),
             size: size)
    print("  \(label):")
    for k in log.frames.keys.sorted() { print("    \(k) \(f(log.frames[k]!))") }
}

struct Form: View {
    @State var m = FlexModel()
    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                Text("Name").tag(as: "a1 label")
                TextField("Name", text: $m.text).tag(as: "a2 textField")
            }.tag(as: "a0 row")
            HStack {
                Toggle("Enabled", isOn: $m.on).tag(as: "b1 toggle")
                Spacer()
                Button("Apply") {}.tag(as: "b3 button")
            }.tag(as: "b0 row")
            HStack {
                Text("Speed").tag(as: "c1 label")
                Slider(value: $m.value, in: 0...10).tag(as: "c2 slider")
            }.tag(as: "c0 row")
            Picker("Mode", selection: $m.pick) {
                Text("Alpha").tag(0); Text("Beta").tag(1)
            }.pickerStyle(.menu).tag(as: "d1 picker")
            Divider().tag(as: "e1 divider")
            HStack {
                Stepper("Qty", value: $m.qty, in: 0...3).tag(as: "f1 stepper")
                Spacer()
            }.tag(as: "f0 row")
        }
        .padding()
        .frame(width: 400)
        .fixedSize(horizontal: false, vertical: true)
        .tag(as: "z form")
    }
}

struct Form1: View {
    @State var m = FlexModel()
    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                Toggle("Enabled", isOn: $m.on).tag(as: "b1 toggle")
                Spacer()
                Button("Apply") {}.tag(as: "b3 button")
            }.tag(as: "b0 row")
            Divider().tag(as: "e1 divider")
        }
        .padding()
        .frame(width: 400)
        .tag(as: "z form")
    }
}

struct StatusBar: View {
    var body: some View {
        HStack(spacing: 16) {
            HStack(spacing: 6) {
                Circle().frame(width: 7, height: 7).tag(as: "a2 dot")
                Text("USB Connected").tag(as: "a3 usb")
            }.tag(as: "a1 group")
            Text("Default · 5×14").tag(as: "b design")
            Text("4 layers").tag(as: "c layers")
            Text("fw 1.2.3").tag(as: "d fw")
            Spacer()
            Text("keymap.json — unsaved changes").tag(as: "f dirty")
        }
        .font(.system(size: 11))
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, minHeight: 26, maxHeight: 26)
        .tag(as: "z bar")
    }
}

@MainActor func run() {
    print("--- FLEX (child.sizeThatFits at each proposal)")
    flex("FX0 control Color.red", Color.red)
    flex("FX1 control Color.red.frame(30x20)", Color.red.frame(width: 30, height: 20))
    flex("FX2 control Text(\"Go\")", Text("Go"))
    flex("FX3 Text(\"A much longer label\")", Text("A much longer label"))
    flex("FL0 Button(\"Go\")", Button("Go") {})
    flex("FL1 Button(\"Go\").buttonStyle(.plain)", Button("Go") {}.buttonStyle(.plain))
    flex("FL2 Toggle(\"Wi-Fi\")", Toggle("Wi-Fi", isOn: .constant(false)))
    flex("FL3 TextField(\"Name\") empty", TextField("Name", text: .constant("")))
    flex("FL4 TextField text Hello", TextField("Name", text: .constant("Hello")))
    flex("FL5 TextEditor", TextEditor(text: .constant("Hello")))
    flex("FL6 Slider", Slider(value: .constant(5), in: 0...10))
    flex("FL7 Stepper(\"Qty\")", Stepper("Qty", value: .constant(1), in: 0...3))
    flex("FL8 Picker .menu", Picker("Mode", selection: .constant(0)) { Text("Alpha").tag(0); Text("Beta").tag(1) }.pickerStyle(.menu))
    flex("FL9 Picker .segmented", Picker("Mode", selection: .constant(0)) { Text("Alpha").tag(0); Text("Beta").tag(1) }.pickerStyle(.segmented))
    flex("FL10 Picker .radioGroup", Picker("Mode", selection: .constant(0)) { Text("Alpha").tag(0); Text("Beta").tag(1) }.pickerStyle(.radioGroup))
    flex("FL11 Divider in VStack context", VStack { Divider() })
    flex("FL12 Spacer", Spacer())
    flex("FL13 Menu(\"Actions\")", Menu("Actions") { Button("One") {} })
    flex("FL14 List(selection:) 3 rows", List(selection: .constant(Int?.none)) { ForEach(0..<3, id: \.self) { Text("Row \($0)") } })
    flex("FL15 Button(\"Go\").padding(8)", Button("Go") {}.padding(8))
    flex("FL16 Button(\"Go\").frame(width: 120)", Button("Go") {}.frame(width: 120))
    flex("FL17 Button(\"Go\").disabled(true)", Button("Go") {}.disabled(true))
    flex("FL18 Button(\"Go\").help(\"tip\")", Button("Go") {}.help("tip"))
    flex("FL19 Button(\"Go\").keyboardShortcut(.defaultAction)", Button("Go") {}.keyboardShortcut(.defaultAction))
    flex("FL20 Button(\"Go\").controlSize(.small)", Button("Go") {}.controlSize(.small))
    flex("FL21 Toggle(\"Wi-Fi\").frame(maxWidth: .infinity)", Toggle("Wi-Fi", isOn: .constant(false)).frame(maxWidth: .infinity))
    for line in log.answers { print("  " + line) }

    print("--- FORM (frames in the root space, 400-wide window; the form at its ideal height)")
    frames("FM0 form", Form(), size: CGSize(width: 400, height: 300))
    print("--- FORM1 (the same form offered a fixed 300-point height: a Spacer row takes the slack)")
    frames("FM1 form, 300 tall", Form1(), size: CGSize(width: 400, height: 300))

    print("--- STATUS (600-wide window)")
    frames("ST0 status bar", StatusBar(), size: CGSize(width: 600, height: 26))

    print("--- IN (instrument check: a Spacer carrying the frame reader, 300-wide window)")
    frames("IN0 HStack { Text; Spacer(); Text }", HStack {
        Text("A").tag(as: "1 a"); Spacer(); Text("B").tag(as: "3 b")
    }.tag(as: "0 row"), size: CGSize(width: 300, height: 40))
    frames("IN1 HStack { Text; Spacer().onGeometryChange; Text }", HStack {
        Text("A").tag(as: "1 a"); Spacer().tag(as: "2 spacer"); Text("B").tag(as: "3 b")
    }.tag(as: "0 row"), size: CGSize(width: 300, height: 40))

    print("--- SPLIT (HStack in a 300-wide window)")
    frames("SP0 TextField + TextField", HStack {
        TextField("A", text: .constant("")).tag(as: "1 a")
        TextField("B", text: .constant("")).tag(as: "2 b")
    }, size: CGSize(width: 300, height: 40))
    frames("SP1 TextField + Slider", HStack {
        TextField("A", text: .constant("")).tag(as: "1 field")
        Slider(value: .constant(5), in: 0...10).tag(as: "2 slider")
    }, size: CGSize(width: 300, height: 40))
    frames("SP2 Button + Button", HStack {
        Button("Go") {}.tag(as: "1 go")
        Button("A longer label") {}.tag(as: "2 longer")
    }, size: CGSize(width: 300, height: 40))

    print("--- MODS (in an HStack with a Text, 300-wide window)")
    frames("MD0 .padding(8)", HStack { Text("L").tag(as: "1 text"); Button("Go") {}.padding(8).tag(as: "2 button") },
           size: CGSize(width: 300, height: 60))
    frames("MD1 .frame(width: 120)", HStack { Text("L").tag(as: "1 text"); Button("Go") {}.frame(width: 120).tag(as: "2 button") },
           size: CGSize(width: 300, height: 60))
    frames("MD2 .buttonStyle(.plain)", HStack { Text("L").tag(as: "1 text"); Button("Go") {}.buttonStyle(.plain).tag(as: "2 button") },
           size: CGSize(width: 300, height: 60))
    frames("MD3 .pickerStyle(.segmented)", HStack {
        Text("L").tag(as: "1 text")
        Picker("Mode", selection: .constant(0)) { Text("Alpha").tag(0); Text("Beta").tag(1) }.pickerStyle(.segmented).tag(as: "2 picker")
    }, size: CGSize(width: 300, height: 60))
    frames("MD4 .disabled(true).help(\"tip\")", HStack { Text("L").tag(as: "1 text"); Button("Go") {}.disabled(true).help("tip").tag(as: "2 button") },
           size: CGSize(width: 300, height: 60))
}

MainActor.assumeIsolated {
    NSApplication.shared.setActivationPolicy(.accessory)
    run()
}
exit(0)
