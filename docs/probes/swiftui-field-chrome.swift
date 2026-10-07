// SwiftUI probe: TextField/TextEditor field chrome and `.textFieldStyle`
// (port-gaps-medium design, rulings MD-… in
// docs/superpowers/2026-10-07-port-gaps-medium-decisions.md; MG-20).
//
// QUESTIONS.
// - SZ: each style's answer to six proposals (the `Ask` instrument of
//   swiftui-controls-in-stacks.swift) — no style, `.automatic`,
//   `.roundedBorder`, `.plain`, `.squareBorder` — for a placeholder-only field
//   and a field holding "Hello", beside the bare `Text` of the same strings,
//   so the chrome's insets are the difference.
// - CS: `.controlSize(.small/.large)` on the default field.
// - NS: the AppKit view SwiftUI hosts for each style: `isBezeled`,
//   `bezelStyle`, `isBordered`, `drawsBackground`, `focusRingType`, the
//   cell's text rect inside its bounds (the text inset), the font size.
// - PX: pixels of a 120-wide field, light and dark, enabled and disabled: the
//   colour runs along the field's middle row from its left edge, and down its
//   middle column from its top edge — border width and colour, fill colour.
// - ED: `TextEditor`'s sizes and its scroll view / text view (border type,
//   background, text container inset, line fragment padding).
// - ENV: whether `.textFieldStyle` on a container reaches a field inside it
//   and whether the innermost one wins (NS on a nested pair).
//
// INSTRUMENTS. `Ask` as in swiftui-controls-in-stacks.swift; an NSView walk
// for the first NSTextField / NSScrollView under the hosting view; a
// `cacheDisplay(in:to:)` bitmap of the hosting view, read at device pixels
// (scale printed) as runs "count×#RRGGBBAA".
//
// POSITIVE CONTROLS. AC0 `Color.red.frame(width: 30, height: 20)` answers
// 30x20 everywhere; PX0 a `Color(red: 1, green: 0, blue: 0)` 40x10 strip's
// middle row reads one run of red — the bitmap instrument reads colour.
// SEPARATING ARM. SZ `.plain` vs `.roundedBorder` (sizes) and NS
// `.plain` (isBezeled false) vs `.roundedBorder` (true) separate, so the
// default's class is visible.
//
// HOW TO RUN (compiled form, SA-O):
//
//   xcrun swiftc docs/probes/swiftui-field-chrome.swift -o /tmp/md-field && /tmp/md-field
//
// RECORDED and READING: the block at the end of this file.

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
@MainActor func host<V: View>(_ v: V, size: CGSize, dark: Bool = false) -> NSHostingView<V> {
    let w = NSWindow(contentRect: NSRect(x: 100, y: 100, width: size.width, height: size.height),
                     styleMask: [.titled], backing: .buffered, defer: false)
    w.isReleasedWhenClosed = false
    w.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
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

final class Log { var answers: [String] = [] }
let log = Log()

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
        let line = "\(name): " + asks.map { "\($0.0) \(f(s.sizeThatFits($0.1)))" }.joined(separator: "  ")
        if !log.answers.contains(line) { log.answers.append(line) }
        return s.sizeThatFits(proposal)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews.first?.place(at: bounds.origin, proposal: proposal)
    }
}

@MainActor func ask<V: View>(_ name: String, _ v: V) {
    _ = host(Ask(name: name) { v }, size: CGSize(width: 300, height: 200))
}

func walk<T: NSView>(_ v: NSView, _ type: T.Type) -> [T] {
    var out: [T] = []
    if let t = v as? T { out.append(t) }
    for s in v.subviews { out += walk(s, type) }
    return out
}

func hex(_ p: UnsafeMutablePointer<UInt8>?, _ rep: NSBitmapImageRep, _ x: Int, _ y: Int) -> String {
    var px = [Int](repeating: 0, count: 4)
    rep.getPixel(&px, atX: x, y: y)
    return String(format: "#%02X%02X%02X%02X", px[0], px[1], px[2], rep.samplesPerPixel > 3 ? px[3] : 255)
}

func runs(_ values: [String]) -> String {
    var out: [String] = []
    var last = "", n = 0
    for v in values {
        if v == last { n += 1 } else { if n > 0 { out.append("\(n)×\(last)") }; last = v; n = 1 }
    }
    if n > 0 { out.append("\(n)×\(last)") }
    return out.joined(separator: " ")
}

/// The hosting view's bitmap; then the runs along the middle row of `rect`
/// (points, view coordinates, top-left origin as SwiftUI places) from its left
/// edge to its centre, and down the middle column from its top to its centre.
@MainActor func pixels(_ label: String, _ h: NSView, field rect: CGRect) {
    guard let rep = h.bitmapImageRepForCachingDisplay(in: h.bounds) else { print("  \(label): no rep"); return }
    h.cacheDisplay(in: h.bounds, to: rep)
    let scale = CGFloat(rep.pixelsWide) / h.bounds.width
    // Pad one point outside the field on each side so the edge is visible.
    let x0 = Int(((rect.minX - 1) * scale).rounded()), xm = Int((rect.midX * scale).rounded())
    let y0 = Int(((rect.minY - 1) * scale).rounded()), ym = Int((rect.midY * scale).rounded())
    let row = (x0...xm).map { hex(nil, rep, $0, ym) }
    let col = (y0...ym).map { hex(nil, rep, xm, $0) }
    print("  \(label) scale=\(f(scale)) row: \(runs(row))")
    print("  \(label) scale=\(f(scale)) col: \(runs(col))")
    // The top-left corner, 14x14 device pixels from 2 pixels outside: each
    // cell the straight alpha in tenths (0-9, '#' for opaque) — the radius and
    // where the stroke sits relative to the frame.
    let cx = Int((rect.minX * scale).rounded()) - 2, cy = Int((rect.minY * scale).rounded()) - 2
    for y in cy..<(cy + 14) {
        var line = ""
        for x in cx..<(cx + 14) {
            var px = [Int](repeating: 0, count: 4)
            rep.getPixel(&px, atX: x, y: y)
            let a = rep.samplesPerPixel > 3 ? px[3] : 255
            line += a >= 250 ? "#" : String(a * 10 / 256)
        }
        print("  \(label) corner \(line)")
    }
}

func describe(_ t: NSTextField) -> String {
    let cellRect = t.cell?.drawingRect(forBounds: t.bounds) ?? .zero
    let titleRect = t.cell?.titleRect(forBounds: t.bounds) ?? .zero
    return "class=\(type(of: t)) bezeled=\(t.isBezeled) bezelStyle=\(t.bezelStyle.rawValue) bordered=\(t.isBordered) "
        + "drawsBackground=\(t.drawsBackground) focusRing=\(t.focusRingType.rawValue) "
        + "frame=\(f(t.frame)) drawingRect=\(f(cellRect)) titleRect=\(f(titleRect)) "
        + "font=\(t.font.map { f($0.pointSize) } ?? "nil") controlSize=\(t.controlSize.rawValue) "
        + "enabled=\(t.isEnabled) textColor=\(t.textColor.map { "\($0)" } ?? "nil")"
}

struct Field: View {
    @State var text: String
    let placeholder: String
    var body: some View { TextField(placeholder, text: $text) }
}

@MainActor func run() {
    NSApplication.shared.setActivationPolicy(.accessory)

    print("AC0 positive control")
    ask("AC0 Color 30x20", Color.red.frame(width: 30, height: 20))

    print("SZ sizes")
    ask("SZ0 Text(Name)", Text("Name"))
    ask("SZ0b Text(Hello)", Text("Hello"))
    ask("SZ1 none ph", Field(text: "", placeholder: "Name"))
    ask("SZ1b none Hello", Field(text: "Hello", placeholder: ""))
    ask("SZ2 automatic ph", Field(text: "", placeholder: "Name").textFieldStyle(.automatic))
    ask("SZ3 roundedBorder ph", Field(text: "", placeholder: "Name").textFieldStyle(.roundedBorder))
    ask("SZ3b roundedBorder Hello", Field(text: "Hello", placeholder: "").textFieldStyle(.roundedBorder))
    ask("SZ4 plain ph", Field(text: "", placeholder: "Name").textFieldStyle(.plain))
    ask("SZ4b plain Hello", Field(text: "Hello", placeholder: "").textFieldStyle(.plain))
    ask("SZ5 squareBorder ph", Field(text: "", placeholder: "Name").textFieldStyle(.squareBorder))
    ask("SZ5b squareBorder Hello", Field(text: "Hello", placeholder: "").textFieldStyle(.squareBorder))
    ask("SZ6 empty none", Field(text: "", placeholder: ""))
    ask("SZ6b empty plain", Field(text: "", placeholder: "").textFieldStyle(.plain))
    print("CS control sizes")
    ask("CS1 small", Field(text: "", placeholder: "Name").controlSize(.small))
    ask("CS2 large", Field(text: "", placeholder: "Name").controlSize(.large))
    ask("CS3 mini", Field(text: "", placeholder: "Name").controlSize(.mini))
    ask("ED1 TextEditor empty", TextEditor(text: .constant("")))
    ask("ED2 TextEditor Hello", TextEditor(text: .constant("Hello")))
    for line in log.answers { print("  " + line) }

    print("NS hosted AppKit views")
    let styles: [(String, AnyView)] = [
        ("none", AnyView(Field(text: "Hello", placeholder: "Name"))),
        ("automatic", AnyView(Field(text: "Hello", placeholder: "Name").textFieldStyle(.automatic))),
        ("roundedBorder", AnyView(Field(text: "Hello", placeholder: "Name").textFieldStyle(.roundedBorder))),
        ("plain", AnyView(Field(text: "Hello", placeholder: "Name").textFieldStyle(.plain))),
        ("squareBorder", AnyView(Field(text: "Hello", placeholder: "Name").textFieldStyle(.squareBorder))),
        ("disabled", AnyView(Field(text: "Hello", placeholder: "Name").disabled(true))),
        ("small", AnyView(Field(text: "Hello", placeholder: "Name").controlSize(.small))),
        ("ENV1 container plain", AnyView(VStack { Field(text: "Hello", placeholder: "Name") }.textFieldStyle(.plain))),
        ("ENV2 inner rounded in plain", AnyView(VStack { Field(text: "Hello", placeholder: "Name").textFieldStyle(.roundedBorder) }.textFieldStyle(.plain))),
        ("ENV3 inner plain in rounded", AnyView(VStack { Field(text: "Hello", placeholder: "Name").textFieldStyle(.plain) }.textFieldStyle(.roundedBorder))),
    ]
    for (name, view) in styles {
        let h = host(view.frame(width: 120).padding(10), size: CGSize(width: 140, height: 60))
        let fields = walk(h, NSTextField.self)
        print("  NS \(name): \(fields.count) field(s)" + (fields.first.map { " " + describe($0) } ?? ""))
    }

    print("PX pixels")
    let control = host(Color(red: 1, green: 0, blue: 0).frame(width: 40, height: 10).padding(10)
                           .frame(width: 140, height: 60, alignment: .topLeading),
                       size: CGSize(width: 140, height: 60))
    pixels("PX0 red strip", control, field: CGRect(x: 10, y: 10, width: 40, height: 10))
    for dark in [false, true] {
        for (name, view) in [
            ("default", AnyView(Field(text: "", placeholder: ""))),
            ("roundedBorder", AnyView(Field(text: "", placeholder: "").textFieldStyle(.roundedBorder))),
            ("squareBorder", AnyView(Field(text: "", placeholder: "").textFieldStyle(.squareBorder))),
            ("plain", AnyView(Field(text: "", placeholder: "").textFieldStyle(.plain))),
            ("disabled", AnyView(Field(text: "", placeholder: "").disabled(true))),
            ("TextEditor", AnyView(TextEditor(text: .constant("")).frame(height: 40))),
        ] {
            let h = host(view.frame(width: 120).padding(10).frame(width: 140, height: 70, alignment: .topLeading),
                         size: CGSize(width: 140, height: 70), dark: dark)
            let rect: CGRect
            if let t = walk(h, NSTextField.self).first {
                rect = t.convert(t.bounds, to: h)
            } else if let s = walk(h, NSScrollView.self).first {
                rect = s.convert(s.bounds, to: h)
            } else { rect = CGRect(x: 10, y: 10, width: 120, height: 22) }
            let flipped = h.isFlipped ? rect : CGRect(x: rect.minX, y: h.bounds.height - rect.maxY,
                                                      width: rect.width, height: rect.height)
            print("  PX \(dark ? "dark" : "light") \(name) rect=\(f(flipped))")
            pixels("PX \(dark ? "dark" : "light") \(name)", h, field: flipped)
        }
    }
    // Focus: make the field first responder and re-read (the ring may not be
    // drawn by cacheDisplay — recorded either way).
    let fh = host(Field(text: "", placeholder: "").frame(width: 120).padding(10)
                      .frame(width: 140, height: 70, alignment: .topLeading), size: CGSize(width: 140, height: 70))
    if let t = walk(fh, NSTextField.self).first {
        let ok = fh.window?.makeFirstResponder(t) ?? false
        spin(0.4)
        let r = t.convert(t.bounds, to: fh)
        let flipped = fh.isFlipped ? r : CGRect(x: r.minX, y: fh.bounds.height - r.maxY, width: r.width, height: r.height)
        print("  PX focus firstResponder=\(ok) rect=\(f(flipped))")
        pixels("PX light focused", fh, field: flipped.insetBy(dx: -3, dy: -3))
    }

    print("ED TextEditor views")
    let eh = host(TextEditor(text: .constant("Hello")).frame(width: 120, height: 60).padding(10),
                  size: CGSize(width: 140, height: 80))
    for s in walk(eh, NSScrollView.self) {
        print("  ED scroll class=\(type(of: s)) borderType=\(s.borderType.rawValue) drawsBackground=\(s.drawsBackground) "
              + "bg=\(s.backgroundColor) frame=\(f(s.frame)) focusRing=\(s.focusRingType.rawValue)")
    }
    for t in walk(eh, NSTextView.self) {
        print("  ED text class=\(type(of: t)) drawsBackground=\(t.drawsBackground) bg=\(t.backgroundColor) "
              + "inset=\(f(t.textContainerInset)) padding=\(f(t.textContainer?.lineFragmentPadding ?? -1)) "
              + "font=\(t.font.map { f($0.pointSize) } ?? "nil") focusRing=\(t.focusRingType.rawValue)")
    }
}


@MainActor func run2() {
    print("ED2 textEditorStyle(.plain)")
    let ph = host(TextEditor(text: .constant("Hello")).textEditorStyle(.plain).frame(width: 120, height: 60).padding(10),
                  size: CGSize(width: 140, height: 80))
    for s in walk(ph, NSScrollView.self) {
        print("  ED2 plain scroll drawsBackground=\(s.drawsBackground) borderType=\(s.borderType.rawValue)")
    }
    for t in walk(ph, NSTextView.self) {
        print("  ED2 plain text drawsBackground=\(t.drawsBackground) inset=\(f(t.textContainerInset)) "
              + "padding=\(f(t.textContainer?.lineFragmentPadding ?? -1))")
    }
    print("TX text drawn by the instrument? (enabled vs disabled field holding WWWW)")
    for disabled in [false, true] {
        let h = host(Field(text: "WWWW", placeholder: "").disabled(disabled).frame(width: 120).padding(10)
                         .frame(width: 140, height: 70, alignment: .topLeading), size: CGSize(width: 140, height: 70))
        guard let rep = h.bitmapImageRepForCachingDisplay(in: h.bounds) else { continue }
        h.cacheDisplay(in: h.bounds, to: rep)
        // Count distinct colours inside the field's text rect (10+6 … 10+40, 10+4 … 10+20).
        var seen = Set<String>()
        for y in stride(from: 28, to: 60, by: 1) { for x in stride(from: 32, to: 100, by: 1) { seen.insert(hex(nil, rep, x, y)) } }
        let darkest = seen.sorted().first ?? "-"
        print("  TX disabled=\(disabled) distinct=\(seen.count) smallest=\(darkest)")
    }
}

MainActor.assumeIsolated { run(); run2() }

// RECORDED 2026-10-06 on macOS 27.0.1 (26A434), Apple Swift 6.4
// (swiftlang-6.4.0.33.1), screen unlocked (appkit-screen-lock-state.swift: no
// CGSSessionScreenIsLocked line, displayAsleep main: 0), compiled form. Run three
// times by the design session; the three outputs (280 lines) are byte-identical.
//
// READING (the authority for MD-B…MD-F):
// - Controls: AC0 30x20 everywhere; PX0's red strip reads one red run from the
//   frame's edge (2 transparent pixels = the 1-point pad, then #EA3323) — the
//   bitmap instrument reads colour and position.
// - SZ: no style = .automatic = .roundedBorder = .squareBorder (ideal 47.50x24
//   for "Name", 43x24 for "Hello", 12x24 empty; inf -> infx24; any finite width
//   taken). .plain: 39.25x16, 34.95x16, 4x16. The bordered ideal is the Text's
//   width + 12 (SZ0 35.50, 31) and the height 16 + 8. Separating arm: plain vs
//   bordered differ in both axes.
// - CS: small 21 tall at an offered width (22 ideal), mini 19, large 24 (= regular
//   on macOS 27).
// - NS: none/automatic/squareBorder host a bezeled NSTextField (bezelStyle 0),
//   roundedBorder bezelStyle 1; all 120x24 with the cell's drawing rect
//   (4, 4, 112, 16) and focusRingType default (0); plain is unbezeled, no
//   background, focusRingType none (1), and 2 points wider than SwiftUI's frame
//   on each side (-2, 0, 124, 16); small: font 11, drawing rect inset 3.5
//   vertically. ENV1: a container's .plain reaches the field; ENV2/ENV3: the
//   innermost style wins.
// - PX: the three bordered styles draw byte-identical pixels, light and dark,
//   enabled and disabled (an empty field). Corner: the curve spans ~12 device
//   pixels at 2x (radius ~6 points), the fill starting at the frame's edge; a
//   faint 1-pixel edge lies outside the frame (light #00000026 premultiplied =
//   black 15 %, dark white 9 %); fill #F9F9F9F9 (white at 97.6 %) light,
//   #161616F9 (~#171717 at 97.6 %) dark. TextEditor: opaque, square, no edge,
//   #FFFFFF light / #1E1E1E dark. PX focus: cacheDisplay draws no focus ring
//   (the runs equal the unfocused field's) — the ring is NOT measured.
// - ED: TextEditor = NSScrollView (borderType 0, drawsBackground false) over an
//   NSTextView drawing textBackgroundColor, inset 0x0, line fragment padding 5,
//   font 12; sizes ideal 0x12, greedy both axes. ED2: .textEditorStyle(.plain)
//   draws no background.
// - TX: text is drawn by the instrument; darkest pixel enabled #212121,
//   disabled #B5B5B5 — disabled text dims to about a third; the chrome does not
//   change (PX disabled = PX default).
//
// OUTPUT:
// AC0 positive control
// SZ sizes
// CS control sizes
//   AC0 Color 30x20: zero 30x20  ideal 30x20  inf 30x20  w200 30x20  h200 30x20  w50 30x20
//   SZ0 Text(Name): zero 0x0  ideal 35.50x16  inf 35.50x16  w200 35.50x16  h200 35.50x16  w50 35.50x16
//   SZ0b Text(Hello): zero 0x0  ideal 31x16  inf 31x16  w200 31x16  h200 31x16  w50 31x16
//   SZ1 none ph: zero 0x24  ideal 47.50x24  inf infx24  w200 200x24  h200 47.50x24  w50 50x24
//   SZ1b none Hello: zero 0x24  ideal 43x24  inf infx24  w200 200x24  h200 43x24  w50 50x24
//   SZ2 automatic ph: zero 0x24  ideal 47.50x24  inf infx24  w200 200x24  h200 47.50x24  w50 50x24
//   SZ3 roundedBorder ph: zero 0x24  ideal 47.50x24  inf infx24  w200 200x24  h200 47.50x24  w50 50x24
//   SZ3b roundedBorder Hello: zero 0x24  ideal 43x24  inf infx24  w200 200x24  h200 43x24  w50 50x24
//   SZ4 plain ph: zero 0x16  ideal 39.25x16  inf infx16  w200 200x16  h200 39.25x16  w50 50x16
//   SZ4b plain Hello: zero 0x16  ideal 34.95x16  inf infx16  w200 200x16  h200 34.95x16  w50 50x16
//   SZ5 squareBorder ph: zero 0x24  ideal 47.50x24  inf infx24  w200 200x24  h200 47.50x24  w50 50x24
//   SZ5b squareBorder Hello: zero 0x24  ideal 43x24  inf infx24  w200 200x24  h200 43x24  w50 50x24
//   SZ6 empty none: zero 0x24  ideal 12x24  inf infx24  w200 200x24  h200 12x24  w50 50x24
//   SZ6b empty plain: zero 0x16  ideal 4x16  inf infx16  w200 200x16  h200 4x16  w50 50x16
//   CS1 small: zero 0x21  ideal 42.50x22  inf infx21  w200 200x21  h200 42.50x22  w50 50x21
//   CS2 large: zero 0x24  ideal 47.50x24  inf infx24  w200 200x24  h200 47.50x24  w50 50x24
//   CS3 mini: zero 0x19  ideal 37.50x19  inf infx19  w200 200x19  h200 37.50x19  w50 50x19
//   ED1 TextEditor empty: zero 0x0  ideal 0x12  inf infxinf  w200 200x12  h200 0x200  w50 50x12
//   ED2 TextEditor Hello: zero 0x0  ideal 0x12  inf infxinf  w200 200x12  h200 0x200  w50 50x12
// NS hosted AppKit views
//   NS none: 1 field(s) class=AppKitTextField bezeled=true bezelStyle=0 bordered=false drawsBackground=true focusRing=0 frame=(0, 0, 120, 24) drawingRect=(4, 4, 112, 16) titleRect=(4, 4, 112, 16) font=13 controlSize=0 enabled=true textColor=Catalog color: System controlTextColor
//   NS automatic: 1 field(s) class=AppKitTextField bezeled=true bezelStyle=0 bordered=false drawsBackground=true focusRing=0 frame=(0, 0, 120, 24) drawingRect=(4, 4, 112, 16) titleRect=(4, 4, 112, 16) font=13 controlSize=0 enabled=true textColor=Catalog color: System controlTextColor
//   NS roundedBorder: 1 field(s) class=AppKitTextField bezeled=true bezelStyle=1 bordered=false drawsBackground=false focusRing=0 frame=(0, 0, 120, 24) drawingRect=(4, 4, 112, 16) titleRect=(0, 4, 120, 16) font=13 controlSize=0 enabled=true textColor=Catalog color: System controlTextColor
//   NS plain: 1 field(s) class=AppKitTextField bezeled=false bezelStyle=0 bordered=false drawsBackground=false focusRing=1 frame=(-2, 0, 124, 16) drawingRect=(0, 0, 124, 16) titleRect=(0, 0, 124, 16) font=13 controlSize=0 enabled=true textColor=Catalog color: System controlTextColor
//   NS squareBorder: 1 field(s) class=AppKitTextField bezeled=true bezelStyle=0 bordered=false drawsBackground=true focusRing=0 frame=(0, 0, 120, 24) drawingRect=(4, 4, 112, 16) titleRect=(4, 4, 112, 16) font=13 controlSize=0 enabled=true textColor=Catalog color: System controlTextColor
//   NS disabled: 1 field(s) class=AppKitTextField bezeled=true bezelStyle=0 bordered=false drawsBackground=true focusRing=0 frame=(0, 0, 120, 24) drawingRect=(4, 4, 112, 16) titleRect=(4, 4, 112, 16) font=13 controlSize=0 enabled=false textColor=Catalog color: System controlTextColor
//   NS small: 1 field(s) class=AppKitTextField bezeled=true bezelStyle=0 bordered=false drawsBackground=true focusRing=0 frame=(0, 0, 120, 21) drawingRect=(4, 3.50, 112, 14) titleRect=(4, 3.50, 112, 14) font=11 controlSize=1 enabled=true textColor=Catalog color: System controlTextColor
//   NS ENV1 container plain: 1 field(s) class=AppKitTextField bezeled=false bezelStyle=0 bordered=false drawsBackground=false focusRing=1 frame=(-2, 0, 124, 16) drawingRect=(0, 0, 124, 16) titleRect=(0, 0, 124, 16) font=13 controlSize=0 enabled=true textColor=Catalog color: System controlTextColor
//   NS ENV2 inner rounded in plain: 1 field(s) class=AppKitTextField bezeled=true bezelStyle=1 bordered=false drawsBackground=false focusRing=0 frame=(0, 0, 120, 24) drawingRect=(4, 4, 112, 16) titleRect=(0, 4, 120, 16) font=13 controlSize=0 enabled=true textColor=Catalog color: System controlTextColor
//   NS ENV3 inner plain in rounded: 1 field(s) class=AppKitTextField bezeled=false bezelStyle=0 bordered=false drawsBackground=false focusRing=1 frame=(-2, 0, 124, 16) drawingRect=(0, 0, 124, 16) titleRect=(0, 0, 124, 16) font=13 controlSize=0 enabled=true textColor=Catalog color: System controlTextColor
// PX pixels
//   PX0 red strip scale=2 row: 2×#00000000 41×#EA3323FF
//   PX0 red strip scale=2 col: 2×#00000000 11×#EA3323FF
//   PX0 red strip corner 00000000000000
//   PX0 red strip corner 00000000000000
//   PX0 red strip corner 00############
//   PX0 red strip corner 00############
//   PX0 red strip corner 00############
//   PX0 red strip corner 00############
//   PX0 red strip corner 00############
//   PX0 red strip corner 00############
//   PX0 red strip corner 00############
//   PX0 red strip corner 00############
//   PX0 red strip corner 00############
//   PX0 red strip corner 00############
//   PX0 red strip corner 00############
//   PX0 red strip corner 00############
//   PX light default rect=(10, 10, 120, 24)
//   PX light default scale=2 row: 2×#00000026 121×#F9F9F9F9
//   PX light default scale=2 col: 2×#00000026 25×#F9F9F9F9
//   PX light default corner 00000000000011
//   PX light default corner 00000000111111
//   PX light default corner 00000011125789
//   PX light default corner 00000113799999
//   PX light default corner 00001159999999
//   PX light default corner 00011699999999
//   PX light default corner 00115999999999
//   PX light default corner 00139999999999
//   PX light default corner 01179999999999
//   PX light default corner 01299999999999
//   PX light default corner 01599999999999
//   PX light default corner 01799999999999
//   PX light default corner 11899999999999
//   PX light default corner 11999999999999
//   PX light roundedBorder rect=(10, 10, 120, 24)
//   PX light roundedBorder scale=2 row: 2×#00000026 121×#F9F9F9F9
//   PX light roundedBorder scale=2 col: 2×#00000026 25×#F9F9F9F9
//   PX light roundedBorder corner 00000000000011
//   PX light roundedBorder corner 00000000111111
//   PX light roundedBorder corner 00000011125789
//   PX light roundedBorder corner 00000113799999
//   PX light roundedBorder corner 00001159999999
//   PX light roundedBorder corner 00011699999999
//   PX light roundedBorder corner 00115999999999
//   PX light roundedBorder corner 00139999999999
//   PX light roundedBorder corner 01179999999999
//   PX light roundedBorder corner 01299999999999
//   PX light roundedBorder corner 01599999999999
//   PX light roundedBorder corner 01799999999999
//   PX light roundedBorder corner 11899999999999
//   PX light roundedBorder corner 11999999999999
//   PX light squareBorder rect=(10, 10, 120, 24)
//   PX light squareBorder scale=2 row: 2×#00000026 121×#F9F9F9F9
//   PX light squareBorder scale=2 col: 2×#00000026 25×#F9F9F9F9
//   PX light squareBorder corner 00000000000011
//   PX light squareBorder corner 00000000111111
//   PX light squareBorder corner 00000011125789
//   PX light squareBorder corner 00000113799999
//   PX light squareBorder corner 00001159999999
//   PX light squareBorder corner 00011699999999
//   PX light squareBorder corner 00115999999999
//   PX light squareBorder corner 00139999999999
//   PX light squareBorder corner 01179999999999
//   PX light squareBorder corner 01299999999999
//   PX light squareBorder corner 01599999999999
//   PX light squareBorder corner 01799999999999
//   PX light squareBorder corner 11899999999999
//   PX light squareBorder corner 11999999999999
//   PX light plain rect=(8, 10, 124, 16)
//   PX light plain scale=2 row: 127×#00000000
//   PX light plain scale=2 col: 19×#00000000
//   PX light plain corner 00000000000000
//   PX light plain corner 00000000000000
//   PX light plain corner 00000000000000
//   PX light plain corner 00000000000000
//   PX light plain corner 00000000000000
//   PX light plain corner 00000000000000
//   PX light plain corner 00000000000000
//   PX light plain corner 00000000000000
//   PX light plain corner 00000000000000
//   PX light plain corner 00000000000000
//   PX light plain corner 00000000000000
//   PX light plain corner 00000000000000
//   PX light plain corner 00000000000000
//   PX light plain corner 00000000000000
//   PX light disabled rect=(10, 10, 120, 24)
//   PX light disabled scale=2 row: 2×#00000026 121×#F9F9F9F9
//   PX light disabled scale=2 col: 2×#00000026 25×#F9F9F9F9
//   PX light disabled corner 00000000000011
//   PX light disabled corner 00000000111111
//   PX light disabled corner 00000011125789
//   PX light disabled corner 00000113799999
//   PX light disabled corner 00001159999999
//   PX light disabled corner 00011699999999
//   PX light disabled corner 00115999999999
//   PX light disabled corner 00139999999999
//   PX light disabled corner 01179999999999
//   PX light disabled corner 01299999999999
//   PX light disabled corner 01599999999999
//   PX light disabled corner 01799999999999
//   PX light disabled corner 11899999999999
//   PX light disabled corner 11999999999999
//   PX light TextEditor rect=(10, 10, 120, 40)
//   PX light TextEditor scale=2 row: 2×#00000000 121×#FFFFFFFF
//   PX light TextEditor scale=2 col: 2×#00000000 41×#FFFFFFFF
//   PX light TextEditor corner 00000000000000
//   PX light TextEditor corner 00000000000000
//   PX light TextEditor corner 00############
//   PX light TextEditor corner 00############
//   PX light TextEditor corner 00############
//   PX light TextEditor corner 00############
//   PX light TextEditor corner 00############
//   PX light TextEditor corner 00############
//   PX light TextEditor corner 00############
//   PX light TextEditor corner 00############
//   PX light TextEditor corner 00############
//   PX light TextEditor corner 00############
//   PX light TextEditor corner 00############
//   PX light TextEditor corner 00############
//   PX dark default rect=(10, 10, 120, 24)
//   PX dark default scale=2 row: 2×#17171717 121×#161616F9
//   PX dark default scale=2 col: 2×#17171717 25×#161616F9
//   PX dark default corner 00000000000000
//   PX dark default corner 00000000000000
//   PX dark default corner 00000000015789
//   PX dark default corner 00000002799999
//   PX dark default corner 00000059999999
//   PX dark default corner 00000699999999
//   PX dark default corner 00005999999999
//   PX dark default corner 00029999999999
//   PX dark default corner 00079999999999
//   PX dark default corner 00199999999999
//   PX dark default corner 00599999999999
//   PX dark default corner 00799999999999
//   PX dark default corner 00899999999999
//   PX dark default corner 00999999999999
//   PX dark roundedBorder rect=(10, 10, 120, 24)
//   PX dark roundedBorder scale=2 row: 2×#17171717 121×#161616F9
//   PX dark roundedBorder scale=2 col: 2×#17171717 25×#161616F9
//   PX dark roundedBorder corner 00000000000000
//   PX dark roundedBorder corner 00000000000000
//   PX dark roundedBorder corner 00000000015789
//   PX dark roundedBorder corner 00000002799999
//   PX dark roundedBorder corner 00000059999999
//   PX dark roundedBorder corner 00000699999999
//   PX dark roundedBorder corner 00005999999999
//   PX dark roundedBorder corner 00029999999999
//   PX dark roundedBorder corner 00079999999999
//   PX dark roundedBorder corner 00199999999999
//   PX dark roundedBorder corner 00599999999999
//   PX dark roundedBorder corner 00799999999999
//   PX dark roundedBorder corner 00899999999999
//   PX dark roundedBorder corner 00999999999999
//   PX dark squareBorder rect=(10, 10, 120, 24)
//   PX dark squareBorder scale=2 row: 2×#17171717 121×#161616F9
//   PX dark squareBorder scale=2 col: 2×#17171717 25×#161616F9
//   PX dark squareBorder corner 00000000000000
//   PX dark squareBorder corner 00000000000000
//   PX dark squareBorder corner 00000000015789
//   PX dark squareBorder corner 00000002799999
//   PX dark squareBorder corner 00000059999999
//   PX dark squareBorder corner 00000699999999
//   PX dark squareBorder corner 00005999999999
//   PX dark squareBorder corner 00029999999999
//   PX dark squareBorder corner 00079999999999
//   PX dark squareBorder corner 00199999999999
//   PX dark squareBorder corner 00599999999999
//   PX dark squareBorder corner 00799999999999
//   PX dark squareBorder corner 00899999999999
//   PX dark squareBorder corner 00999999999999
//   PX dark plain rect=(8, 10, 124, 16)
//   PX dark plain scale=2 row: 127×#00000000
//   PX dark plain scale=2 col: 19×#00000000
//   PX dark plain corner 00000000000000
//   PX dark plain corner 00000000000000
//   PX dark plain corner 00000000000000
//   PX dark plain corner 00000000000000
//   PX dark plain corner 00000000000000
//   PX dark plain corner 00000000000000
//   PX dark plain corner 00000000000000
//   PX dark plain corner 00000000000000
//   PX dark plain corner 00000000000000
//   PX dark plain corner 00000000000000
//   PX dark plain corner 00000000000000
//   PX dark plain corner 00000000000000
//   PX dark plain corner 00000000000000
//   PX dark plain corner 00000000000000
//   PX dark disabled rect=(10, 10, 120, 24)
//   PX dark disabled scale=2 row: 2×#17171717 121×#161616F9
//   PX dark disabled scale=2 col: 2×#17171717 25×#161616F9
//   PX dark disabled corner 00000000000000
//   PX dark disabled corner 00000000000000
//   PX dark disabled corner 00000000015789
//   PX dark disabled corner 00000002799999
//   PX dark disabled corner 00000059999999
//   PX dark disabled corner 00000699999999
//   PX dark disabled corner 00005999999999
//   PX dark disabled corner 00029999999999
//   PX dark disabled corner 00079999999999
//   PX dark disabled corner 00199999999999
//   PX dark disabled corner 00599999999999
//   PX dark disabled corner 00799999999999
//   PX dark disabled corner 00899999999999
//   PX dark disabled corner 00999999999999
//   PX dark TextEditor rect=(10, 10, 120, 40)
//   PX dark TextEditor scale=2 row: 2×#00000000 121×#1E1E1EFF
//   PX dark TextEditor scale=2 col: 2×#00000000 41×#1E1E1EFF
//   PX dark TextEditor corner 00000000000000
//   PX dark TextEditor corner 00000000000000
//   PX dark TextEditor corner 00############
//   PX dark TextEditor corner 00############
//   PX dark TextEditor corner 00############
//   PX dark TextEditor corner 00############
//   PX dark TextEditor corner 00############
//   PX dark TextEditor corner 00############
//   PX dark TextEditor corner 00############
//   PX dark TextEditor corner 00############
//   PX dark TextEditor corner 00############
//   PX dark TextEditor corner 00############
//   PX dark TextEditor corner 00############
//   PX dark TextEditor corner 00############
//   PX focus firstResponder=true rect=(10, 10, 120, 24)
//   PX light focused scale=2 row: 6×#00000000 2×#00000026 121×#F9F9F9F9
//   PX light focused scale=2 col: 6×#00000000 2×#00000026 25×#F9F9F9F9
//   PX light focused corner 00000000000000
//   PX light focused corner 00000000000000
//   PX light focused corner 00000000000000
//   PX light focused corner 00000000000000
//   PX light focused corner 00000000000000
//   PX light focused corner 00000000000000
//   PX light focused corner 00000000000000
//   PX light focused corner 00000000000000
//   PX light focused corner 00000000000011
//   PX light focused corner 00000000000113
//   PX light focused corner 00000000001159
//   PX light focused corner 00000000011699
//   PX light focused corner 00000000115999
//   PX light focused corner 00000000139999
// ED TextEditor views
//   ED scroll class=TextEditorScrollView borderType=0 drawsBackground=false bg=Catalog color: System controlBackgroundColor frame=(0, 0, 120, 60) focusRing=0
//   ED text class=PlatformTextView drawsBackground=true bg=Catalog color: System textBackgroundColor inset=0x0 padding=5 font=12 focusRing=0
// ED2 textEditorStyle(.plain)
//   ED2 plain scroll drawsBackground=false borderType=0
//   ED2 plain text drawsBackground=false inset=0x0 padding=5
// TX text drawn by the instrument? (enabled vs disabled field holding WWWW)
//   TX disabled=false distinct=95 smallest=#212121FF
//   TX disabled=true distinct=53 smallest=#B5B5B5FC
