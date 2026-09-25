// SwiftUI probe: `displayScale`, `controlActiveState` and `controlSize` —
// what each reads, where it comes from, whether a scope can write it, what a
// write changes, and when a reader sees a change. Evidence for plan task 9's
// closing rulings (EV-AA onward) in
// docs/superpowers/2026-09-15-environment-decisions.md.
//
// HOW TO RUN (recorded below with the compiled form; the interpreted form was
// run too and its filtered output compared):
//
//   /usr/bin/swiftc docs/probes/swiftui-environment-control-state.swift -o /tmp/ctlprobe
//   OS_ACTIVITY_DT_MODE=1 /tmp/ctlprobe 2>&1 | grep -v 'Connection\]\|ntents\|WindowTab'
//   /usr/bin/swift docs/probes/swiftui-environment-control-state.swift 2>&1 | grep -v 'Connection\]\|ntents\|WindowTab'
//
// ARMS AND CONTROLS.
// - V: a bare `EnvironmentValues()` (no host) — the bare defaults; V1 what a
//   non-positive or non-finite `displayScale` write gives `pixelLength`.
// - S (displayScale):
//   S0 control: hosted in an NSWindow, `displayScale` must equal the window's
//      `backingScaleFactor`, or nothing below reads the device.
//   S1 source/update: an `ImageRenderer` at scale 1, then the SAME renderer
//      re-rendered at scale 3 — the host's rendering scale is what a reader
//      sees, and a change of it reaches the reader on the next render. The
//      two readings must differ (they are the separating pair).
//   S2 write: `.environment(\.displayScale, 1)` / `3` inside a 2x host — the
//      read value (must move from S0, or the key is not writable).
//   S3 rendering: an `ImageRenderer` at scale 2 drawing a black
//      `Rectangle().frame(width: pixelLength)` on white, (a) with no write
//      (control: 1 device pixel), (b) under `.environment(\.displayScale, 1)`,
//      (c) under `3`. Counts dark device-pixel columns: separates "a write
//      changes only the number (rendering stays at the host's scale)" from "a
//      write changes the scale the subtree is drawn at".
//   S4 layout rounding: `HStack(spacing: 0) { Color.frame(width: 10.3); probe }`
//      — the probe's minX in the stack's space at displayScale 1, 2 (control:
//      the host) and 3. Separates "layout rounds to the written scale's pixels"
//      from "layout does not round by displayScale".
// - C (controlActiveState):
//   C0 bare/hosted defaults and `NSApp.isActive`/`isKeyWindow` at each step, so
//      a reading is attributable to a window state and not assumed.
//   C1 window A made key in an ACTIVE app — control: must read `key`.
//   C2 window B made key: A must read `active` (app active, A not key).
//   C3 app deactivated (`NSApp.hide`): both windows must read `inactive`.
//   C4 `.environment(\.controlActiveState, .key)` on a second reader in A —
//      writable? (it must read `key` while A reads something else) and does
//      the write survive each state change?
//   C5 a non-activating `NSPanel` made key: can separate the window's key
//      status from the app's active status, if the panel becomes key.
//   Timing: every body evaluation of each reader is logged in order, so the
//      log shows whether the change arrives by re-evaluation and how many.
// - Z (controlSize):
//   Z0 bare/hosted default. Z1 `.controlSize(.small)` and a nested
//      `.controlSize(.large)` inside it (nearest writer). Z2 a `Text`'s
//      fitting size under each size — control: `.font(.system(size: 26))` must
//      move it; Z2e/Z2f an explicit `.font(.system(size: 13))` and `.font(.body)`
//      under `.mini` (does the size reach only the DEFAULT font?). Z3 a `TextField`'s and a `Button`'s fitting size under each
//      size (whether SwiftUI's built-in controls read it on macOS).
//
// RECORDED 2026-09-25 (task 9 design session), macOS 27.0 (26A428), MacBook
// Pro with one built-in 2x display, **screen locked** (the lock probe read
// `CGSSessionScreenIsLocked = 1`, `displayAsleep main: 1`). Apple Swift 6.4
// (swiftlang-6.4.0.33.1). Run compiled with `/usr/bin/swiftc` and interpreted
// with `/usr/bin/swift`; the two filtered outputs are byte-identical. Exit 0.
// `swiftui-environment-pixel-length.swift` was re-run in the same session and
// its V and X lines are byte-identical to its own header (macOS 26.6.2 then).
//
//   --- V: a bare EnvironmentValues(), no host
//     V0 displayScale=1.0 pixelLength=1.0 controlActiveState=key controlSize=regular
//     V1 displayScale = 0.0 on a bare value: displayScale=0.0 pixelLength=1.0
//     V1 displayScale = -1.0 on a bare value: displayScale=-1.0 pixelLength=-1.0
//     V1 displayScale = nan on a bare value: displayScale=nan pixelLength=nan
//     V1 displayScale = inf on a bare value: displayScale=inf pixelLength=0.0
//   --- S: displayScale
//     host backingScaleFactor=2.0
//     S0 control, no write: displayScale=2.0 pixelLength=0.5
//     S2a .environment(\.displayScale, 1): displayScale=1.0 pixelLength=1.0
//     S2b .environment(\.displayScale, 3): displayScale=3.0 pixelLength=0.3333333333333333
//     S1a ImageRenderer scale 1: displayScale=1.0 pixelLength=1.0
//     S1b same renderer, scale set to 3, re-rendered: displayScale=3.0 pixelLength=0.3333333333333333
//     S3a control, no write, renderer scale 2: image 24x20 dark columns at mid row: [8]
//     S3b .environment(\.displayScale, 1), renderer scale 2: image 24x20 dark columns at mid row: [8, 9]
//     S3c .environment(\.displayScale, 3), renderer scale 2: image 24x20 dark columns at mid row: [8]
//     S4a .environment(\.displayScale, 1): minX=10.650000000000006
//     S4b control, host scale (no write): minX=10.150000000000006
//     S4c .environment(\.displayScale, 3): minX=10.316666666666677
//   --- C: controlActiveState
//     C0 A ordered front, app not yet activated: NSApp.isActive=false A.isKey=false A=inactive A-written=key B=inactive
//     body A: inactive
//     body A-written: key
//     body B: inactive
//     C1 app activated, A made key: NSApp.isActive=false A.isKey=false A=inactive A-written=key B=inactive
//     C2 B made key: NSApp.isActive=false A.isKey=false B.isKey=false A=inactive A-written=key B=inactive
//     C2' A made key again: NSApp.isActive=false A.isKey=false B.isKey=false A=inactive A-written=key B=inactive
//     C3 app hidden: NSApp.isActive=false A.isKey=false B.isKey=false A=inactive A-written=key B=inactive
//     C3' app unhidden and activated, A made key: NSApp.isActive=false A.isKey=false B.isKey=false A=inactive A-written=key B=inactive
//     C5 non-activating panel made key: NSApp.isActive=false A.isKey=false A=inactive A-written=- B=-
//     body A: inactive
//   --- Z: controlSize
//     Z0 hosted default: regular
//     Z1a .controlSize(.small): small
//     Z1b .controlSize(.large) inside .controlSize(.small): large
//     Z1c .environment(\.controlSize, .mini): mini
//     Z2 Text("Hello, world") .controlSize(.mini): 53.0x11.0
//     Z2 Text("Hello, world") .controlSize(.small): 63.0x14.0
//     Z2 Text("Hello, world") .controlSize(.regular): 72.0x16.0
//     Z2 Text("Hello, world") .controlSize(.large): 72.0x16.0
//     Z2 Text("Hello, world") .controlSize(.extraLarge): 72.0x16.0
//     Z2 control, Text .font(.system(size: 26)): 130.0x30.0
//     Z2e Text .font(.system(size: 13)) .controlSize(.mini): 72.0x16.0
//     Z2f Text .font(.body) .controlSize(.mini): 72.0x16.0
//     Z3 TextField .controlSize(.mini): 120.0x19.0  Button: 30.0x13.0
//     Z3 TextField .controlSize(.small): 120.0x21.0  Button: 36.0x20.0
//     Z3 TextField .controlSize(.regular): 120.0x24.0  Button: 43.0x24.0
//     Z3 TextField .controlSize(.large): 120.0x24.0  Button: 47.0x28.0
//     Z3 TextField .controlSize(.extraLarge): 120.0x24.0  Button: 55.0x36.0
//
// READING (what the task 9 rulings rely on):
// - V0: a bare value holds displayScale 1, controlActiveState `key` and
//   controlSize `regular`. V1: `pixelLength` is `1 / displayScale` except that
//   a 0 scale gives 1 — a negative scale gives a negative length, NaN gives
//   NaN, infinity gives 0. SwiftUI rejects none of these writes.
// - S0: hosted, displayScale equals backingScaleFactor (2.0), pixelLength 0.5.
//   S1a/S1b: the host's RENDERING scale is the source — an ImageRenderer at
//   scale 1 hands its content 1, and the same renderer re-rendered at scale 3
//   re-evaluates the content with 3 (the change reaches the reader on the next
//   render). S2: a scope can write it, and pixelLength follows (1.0, 1/3).
// - S3: A WRITE CHANGES THE NUMBER, NOT THE SCALE DRAWING USES. At renderer
//   scale 2 a hairline `frame(width: pixelLength)` is 1 device pixel with no
//   write (control) and 2 device pixels under `displayScale = 1` (1 pt drawn
//   at 2x); under 3 it is 1 pixel (1/3 pt drawn at 2x, antialiased into one
//   column). So SwiftUI's rendering keeps the host's scale whatever a scope
//   writes — the "it would change only the number" that EV-J/EV-U gave as a
//   MetalUI-only hazard is SwiftUI's own behaviour.
// - S4: LAYOUT ROUNDS TO THE displayScale PIXEL GRID, AND FOLLOWS A WRITE. The
//   row sits at a fractional window x (52.35); the reader's absolute x, 62.65,
//   is rounded to 63 (scale 1), 62.5 (scale 2, the host) and 62.667 (scale 3),
//   which in the row's own space reads 10.65 / 10.15 / 10.3167.
// - C0: in an app that is NOT active (NSApp.isActive=false), every hosted
//   reader reads `inactive`, where a bare value holds `key` (V0) — the host
//   stamps it. C4: a scope can write it (`A-written` reads `key` beside `A`'s
//   `inactive`, and keeps it across every step).
// - C1–C3, C5 DID NOT RUN AS ARMS: with the screen locked the app never
//   became active and no window — not even a non-activating panel — became
//   key (every line prints `isActive=false`, `isKey=false`), so the positive
//   control (C1 must read `key`) never moved. SwiftUI's key/active mapping
//   and when a reader sees a key change are UNMEASURED here; re-run unlocked.
//   Only one body evaluation per reader was logged (the first), consistent
//   with nothing changing.
// - Z0/Z1: default `regular`; `.controlSize(_:)` and `.environment(\.controlSize,
//   _)` both write it; nearest writer wins (Z1b reads `large`).
// - Z2: CONTROL SIZE REACHES A TEXT'S DEFAULT FONT ON macOS: `Text("Hello,
//   world")` measures 53x11 (mini), 63x14 (small), 72x16 (regular, large,
//   extraLarge); control: a 26pt font measures 130x30. Z2e/Z2f: an explicit
//   `.font(.system(size: 13))` or `.font(.body)` under `.mini` stays 72x16 —
//   only the default font follows the control size.
// - Z3: built-in controls read it: a TextField's height is 19/21/24/24/24
//   and a Button's size 30x13 / 36x20 / 43x24 / 47x28 / 55x36 across
//   mini…extraLarge.
import SwiftUI
import AppKit

enum Log {
    nonisolated(unsafe) static var lines: [String] = []
    nonisolated(unsafe) static var last: [String: String] = [:]
}

struct ScaleReader: View {
    let label: String
    @Environment(\.displayScale) var scale
    @Environment(\.pixelLength) var px
    var body: some View {
        Log.last[label] = "displayScale=\(scale) pixelLength=\(px)"
        return Color.clear.frame(width: 1, height: 1)
    }
}

struct ActiveReader: View {
    let label: String
    @Environment(\.controlActiveState) var state
    var body: some View {
        Log.lines.append("  body \(label): \(state)")
        Log.last[label] = "\(state)"
        return Color.clear.frame(width: 20, height: 20)
    }
}

struct SizeReader: View {
    let label: String
    @Environment(\.controlSize) var size
    var body: some View {
        Log.last[label] = "\(size)"
        return Color.clear.frame(width: 1, height: 1)
    }
}

struct MinXReader: View {
    let label: String
    var body: some View {
        GeometryReader { g in
            Color.clear.onAppear {
                Log.last[label] = "minX=\(g.frame(in: .named("row")).minX)"
            }
        }.frame(width: 5, height: 5)
    }
}

struct Hairline: View {
    @Environment(\.pixelLength) var px
    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.white
            Rectangle().fill(Color.black).frame(width: px, height: 10).offset(x: 4, y: 0)
        }.frame(width: 12, height: 10)
    }
}

@MainActor
func darkColumns(_ view: some View, scale: CGFloat) -> String {
    let r = ImageRenderer(content: view)
    r.scale = scale
    guard let cg = r.cgImage else { return "no image" }
    let w = cg.width, h = cg.height
    var bytes = [UInt8](repeating: 0, count: w * h * 4)
    let ctx = CGContext(data: &bytes, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                        space: CGColorSpaceCreateDeviceRGB(),
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
    let row = h / 2
    var cols: [Int] = []
    for x in 0..<w where bytes[(row * w + x) * 4] < 128 { cols.append(x) }
    return "image \(w)x\(h) dark columns at mid row: \(cols)"
}

@MainActor
func fit(_ view: some View) -> String {
    let v = NSHostingView(rootView: view)
    let s = v.fittingSize
    return "\(s.width)x\(s.height)"
}

@MainActor
func spin(_ seconds: Double = 0.4) { RunLoop.main.run(until: Date().addingTimeInterval(seconds)) }

@MainActor
func row(_ label: String) -> some View {
    HStack(spacing: 0) { Color.red.frame(width: 10.3, height: 5); MinXReader(label: label) }
        .coordinateSpace(name: "row")
}

@MainActor
func state(_ tag: String, _ a: NSWindow, _ b: NSWindow?) {
    spin()
    let bKey = b.map { " B.isKey=\($0.isKeyWindow)" } ?? ""
    print("  \(tag): NSApp.isActive=\(NSApp.isActive) A.isKey=\(a.isKeyWindow)\(bKey) "
        + "A=\(Log.last["A"] ?? "-") A-written=\(Log.last["A-written"] ?? "-") B=\(Log.last["B"] ?? "-")")
    for l in Log.lines { print(l) }
    Log.lines = []
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    app.setActivationPolicy(.regular)

    print("--- V: a bare EnvironmentValues(), no host")
    let bare = EnvironmentValues()
    print("  V0 displayScale=\(bare.displayScale) pixelLength=\(bare.pixelLength) "
        + "controlActiveState=\(bare.controlActiveState) controlSize=\(bare.controlSize)")
    for v in [0.0, -1.0, Double.nan, Double.infinity] {
        var e = EnvironmentValues()
        e.displayScale = v
        print("  V1 displayScale = \(v) on a bare value: displayScale=\(e.displayScale) pixelLength=\(e.pixelLength)")
    }

    // ---- S
    print("--- S: displayScale")
    let sRoot = VStack {
        ScaleReader(label: "S0 control, no write")
        ScaleReader(label: "S2a .environment(\\.displayScale, 1)").environment(\.displayScale, 1)
        ScaleReader(label: "S2b .environment(\\.displayScale, 3)").environment(\.displayScale, 3)
    }
    let sw = NSWindow(contentRect: CGRect(x: 100, y: 100, width: 120, height: 80),
                      styleMask: [.titled], backing: .buffered, defer: false)
    sw.isReleasedWhenClosed = false
    sw.contentView = NSHostingView(rootView: sRoot)
    sw.orderFront(nil)
    spin()
    print("  host backingScaleFactor=\(sw.backingScaleFactor)")
    for k in Log.last.keys.sorted() where k.hasPrefix("S") { print("  \(k): \(Log.last[k]!)") }
    sw.orderOut(nil)

    Log.last = [:]
    let renderer = ImageRenderer(content: ScaleReader(label: "S1 ImageRenderer"))
    renderer.scale = 1
    _ = renderer.cgImage
    print("  S1a ImageRenderer scale 1: \(Log.last["S1 ImageRenderer"] ?? "not evaluated")")
    Log.last = [:]
    renderer.scale = 3
    _ = renderer.cgImage
    print("  S1b same renderer, scale set to 3, re-rendered: \(Log.last["S1 ImageRenderer"] ?? "not re-evaluated")")

    print("  S3a control, no write, renderer scale 2: \(darkColumns(Hairline(), scale: 2))")
    print("  S3b .environment(\\.displayScale, 1), renderer scale 2: \(darkColumns(Hairline().environment(\.displayScale, 1), scale: 2))")
    print("  S3c .environment(\\.displayScale, 3), renderer scale 2: \(darkColumns(Hairline().environment(\.displayScale, 3), scale: 2))")

    Log.last = [:]
    let rw = NSWindow(contentRect: CGRect(x: 100, y: 100, width: 120, height: 80),
                      styleMask: [.titled], backing: .buffered, defer: false)
    rw.isReleasedWhenClosed = false
    rw.contentView = NSHostingView(rootView: VStack {
        row("S4b control, host scale (no write)")
        row("S4a .environment(\\.displayScale, 1)").environment(\.displayScale, 1)
        row("S4c .environment(\\.displayScale, 3)").environment(\.displayScale, 3)
    })
    rw.orderFront(nil)
    spin()
    for k in Log.last.keys.sorted() where k.hasPrefix("S4") { print("  \(k): \(Log.last[k]!)") }
    rw.orderOut(nil)

    // ---- C
    print("--- C: controlActiveState")
    Log.lines = []; Log.last = [:]
    let aw = NSWindow(contentRect: CGRect(x: 100, y: 300, width: 120, height: 80),
                      styleMask: [.titled], backing: .buffered, defer: false)
    aw.isReleasedWhenClosed = false
    aw.contentView = NSHostingView(rootView: HStack {
        ActiveReader(label: "A")
        ActiveReader(label: "A-written").environment(\.controlActiveState, .key)
    })
    let bw = NSWindow(contentRect: CGRect(x: 300, y: 300, width: 120, height: 80),
                      styleMask: [.titled], backing: .buffered, defer: false)
    bw.isReleasedWhenClosed = false
    bw.contentView = NSHostingView(rootView: ActiveReader(label: "B"))

    aw.orderFront(nil)
    state("C0 A ordered front, app not yet activated", aw, nil)
    app.activate(ignoringOtherApps: true)
    aw.makeKeyAndOrderFront(nil)
    state("C1 app activated, A made key", aw, nil)
    bw.makeKeyAndOrderFront(nil)
    state("C2 B made key", aw, bw)
    aw.makeKeyAndOrderFront(nil)
    state("C2' A made key again", aw, bw)
    app.hide(nil)
    state("C3 app hidden", aw, bw)
    app.unhide(nil)
    app.activate(ignoringOtherApps: true)
    aw.makeKeyAndOrderFront(nil)
    state("C3' app unhidden and activated, A made key", aw, bw)
    aw.orderOut(nil); bw.orderOut(nil)

    // C5: a non-activating panel can become key while its app is not active,
    // which separates "reads the window's key status" from "reads the app's
    // active status" — if the panel does become key (printed).
    Log.lines = []; Log.last = [:]
    let panel = NSPanel(contentRect: CGRect(x: 500, y: 300, width: 120, height: 80),
                        styleMask: [.titled, .nonactivatingPanel], backing: .buffered, defer: false)
    panel.isReleasedWhenClosed = false
    panel.becomesKeyOnlyIfNeeded = false
    panel.contentView = NSHostingView(rootView: ActiveReader(label: "A"))
    panel.makeKeyAndOrderFront(nil)
    state("C5 non-activating panel made key", panel, nil)
    panel.orderOut(nil)

    // ---- Z
    print("--- Z: controlSize")
    Log.last = [:]
    _ = fit(VStack {
        SizeReader(label: "Z0 hosted default")
        SizeReader(label: "Z1a .controlSize(.small)").controlSize(.small)
        SizeReader(label: "Z1b .controlSize(.large) inside .controlSize(.small)").controlSize(.large).controlSize(.small)
        SizeReader(label: "Z1c .environment(\\.controlSize, .mini)").environment(\.controlSize, .mini)
    })
    for k in Log.last.keys.sorted() { print("  \(k): \(Log.last[k]!)") }
    let sizes: [(String, ControlSize)] = [("mini", .mini), ("small", .small), ("regular", .regular),
                                          ("large", .large), ("extraLarge", .extraLarge)]
    for (name, size) in sizes {
        print("  Z2 Text(\"Hello, world\") .controlSize(.\(name)): \(fit(Text("Hello, world").controlSize(size)))")
    }
    print("  Z2 control, Text .font(.system(size: 26)): \(fit(Text("Hello, world").font(.system(size: 26))))")
    print("  Z2e Text .font(.system(size: 13)) .controlSize(.mini): \(fit(Text("Hello, world").font(.system(size: 13)).controlSize(.mini)))")
    print("  Z2f Text .font(.body) .controlSize(.mini): \(fit(Text("Hello, world").font(.body).controlSize(.mini)))")
    for (name, size) in sizes {
        print("  Z3 TextField .controlSize(.\(name)): \(fit(TextField("Name", text: .constant("Hello")).frame(width: 120).controlSize(size)))"
            + "  Button: \(fit(Button("OK") {}.controlSize(size)))")
    }
}
