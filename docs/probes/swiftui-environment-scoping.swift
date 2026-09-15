// SwiftUI probe: how environment values scope, compose and persist, which
// defaults a hosted view sees, and what two of them (dynamic type, layout
// direction) do to layout on macOS. Evidence for rulings EV-A (scoping), EV-B
// (identity- and layout-transparent writers), EV-D (isEnabled composition),
// EV-G (theme stays paint-only; overlay analogy for Deferred), EV-H (defaults),
// EV-I (dynamic type), EV-K (layout direction) in
// docs/superpowers/2026-09-15-environment-decisions.md.
//
// HOW TO RUN. Either form; both were run on the final file and their filtered
// output is byte-identical (`diff` empty):
//
//   /usr/bin/swift docs/probes/swiftui-environment-scoping.swift
//   swiftc docs/probes/swiftui-environment-scoping.swift -o /tmp/envprobe
//   OS_ACTIVITY_DT_MODE=1 /tmp/envprobe 2>&1 | grep -v 'Connection\]\|ntents\|WindowTab'
//
// The filter removes nine XPC/intents log lines an unbundled process prints at
// launch; nothing else is removed. Exit status 0.
//
// Every arm carries its own positive control, named "(control)" or "control:"
// in the label: A0 (no writer reads the default), B0, C2 (every default reader
// moves when written), D2 (an `.id` change DOES reset state, so D1's retention
// is observable), E3 (a writer on a VStack reads 1, so E1's 2 is not the
// counter failing), G3 (a real font change moves the size), H0 (LTR order).
//
// RECORDED 2026-09-14, macOS 26.6.2 (25G83), Apple Swift 6.4
// (swiftlang-6.4.0.33.1), MacBook with a 2x display, system appearance dark,
// locale en_US:
//
//   --- A: nearest-ancestor precedence and modifier order
//     A0 no writer (control): probe=0 isEnabled=true
//     A1 .environment(1): probe=1 isEnabled=true
//     A2 .environment(2).environment(1): inner written first: probe=2 isEnabled=true
//     A3 inside outer(1): probe=1 isEnabled=true
//     A4 inside outer(1), own inner(2): probe=2 isEnabled=true
//     A5 sibling after A4, inside outer(1): probe=1 isEnabled=true
//     A6 after the outer scope closes: probe=0 isEnabled=true
//     A7 transformEnvironment +10 inside +100: probe=110 isEnabled=true
//     A8 .environment(5) inside transformEnvironment +100: probe=5 isEnabled=true
//   --- B: isEnabled under .disabled and .environment(\.isEnabled)
//     B0 no modifier (control): probe=0 isEnabled=true
//     B1 .disabled(true): probe=0 isEnabled=false
//     B2 .disabled(false): probe=0 isEnabled=true
//     B3 .disabled(false) inside .disabled(true): probe=0 isEnabled=false
//     B4 .disabled(true) inside .disabled(false): probe=0 isEnabled=false
//     B5 .environment(isEnabled,true) inside .disabled(true): probe=0 isEnabled=true
//     B6 .disabled(false) inside .environment(isEnabled,false): probe=0 isEnabled=false
//     B7 .disabled(true) inside .environment(isEnabled,true): probe=0 isEnabled=false
//     B8 grandchild of a disabled VStack: probe=0 isEnabled=false
//   --- C: default values (hosted in an NSWindow)
//     defaults: layoutDirection=leftToRight locale=en_US (Locale.current=en_US) dynamicTypeSize=large displayScale=2.0 pixelLength=0.5 colorScheme=dark controlActiveState=inactive controlSize=regular isEnabled=true
//     window backingScaleFactor=2.0 NSApp.userInterfaceLayoutDirection=0 (0 = LTR)
//     C2 with locale de_DE, RTL, .dynamicTypeSize(.accessibility3) (control that the readers can move):
//     defaults: layoutDirection=rightToLeft locale=de_DE (Locale.current=en_US) dynamicTypeSize=accessibility3 displayScale=2.0 pixelLength=0.5 colorScheme=dark controlActiveState=inactive controlSize=regular isEnabled=true
//   --- D: @State across an environment value change (control: .id change)
//     frame 1:
//     D1 value changes, no id: n=5 probe=1
//     D2 control: .id changes: n=5 probe=1
//     after probe = 2:
//     D1 value changes, no id: n=6 probe=2
//     D2 control: .id changes: n=6 probe=2
//     after identity = 1 and probe = 3 together:
//     D1 value changes, no id: n=7 probe=3
//     D2 control: .id changes: n=5 probe=3
//     onAppear counts: [(key: "D1 value changes, no id", value: 1), (key: "D2 control: .id changes", value: 2)]
//   --- E: subview count through an environment writer
//     E0 Group{A;B} (baseline): subviews.count=2
//     E1 Group{A;B}.environment: subviews.count=2
//     E2 Group{A;B}.disabled(true): subviews.count=2
//     E3 control: VStack{A;B}.environment: subviews.count=1
//   --- F: an overlay's content inherits the scope it is declared in
//     F1 overlay, then .environment(3) outside it: probe=3 isEnabled=true
//     F2 .environment(3) on the base, overlay added after: probe=0 isEnabled=true
//   --- G: does .dynamicTypeSize change a .body Text's size on macOS? (control: .font(size: 26))
//     G0 default fittingSize: (120.0, 16.0)
//     G1 .dynamicTypeSize(.xSmall) fittingSize: (120.0, 16.0)
//     G2 .dynamicTypeSize(.accessibility5) fittingSize: (120.0, 16.0)
//     G3 control .font(.system(size: 26)) fittingSize: (219.0, 30.0)
//   --- H: HStack placement under .environment(\.layoutDirection, .rightToLeft) (control: LTR)
//     H0 LTR first(10): minX=0.0
//     H0 LTR second(20): minX=10.0
//     H1 RTL first(10): minX=90.0
//     H1 RTL second(20): minX=70.0
//
// READING (what the rulings rely on):
// - A: the nearest writer wins (A2, A4); a scope ends with its subtree (A5, A6);
//   a transform composes with the INHERITED value (A7 = 110) and a plain write
//   below a transform replaces it (A8 = 5). This is a value flowing down one
//   path, not a cascade with selectors or specificity.
// - B: `.disabled(d)` composes as `isEnabled = inherited && !d` — an inner
//   `.disabled(false)` cannot re-enable (B3, B6) — while a plain
//   `.environment(\.isEnabled, true)` write CAN (B5). Disablement reaches
//   grandchildren (B8).
// - C: defaults in an NSWindow: leftToRight, Locale.current, dynamicTypeSize
//   .large, displayScale 2.0 = backingScaleFactor, pixelLength 0.5, isEnabled
//   true. This machine is LTR, so C cannot tell a constant LTR default from one
//   derived from `NSApp.userInterfaceLayoutDirection`.
// - D: a changed environment VALUE keeps the @State below the writer (D1: 5 → 6
//   → 7, onAppear once); the control's `.id` change resets it (D2: 7 would be
//   retained, reads 5, onAppear twice).
// - E: a writer adds no layout container (E1, E2 read 2 like the bare Group).
// - F: overlay content sees the scope the overlay modifier sits in (F1) and not
//   a writer applied to the base before the overlay was attached (F2).
// - G: on macOS `.dynamicTypeSize` does not change a `.body` Text's size at
//   either extreme; the control shows the measurement can move.
// - H: under `.rightToLeft` an HStack mirrors: its first child sits at the
//   trailing edge (minX 90 of a 100pt frame), the second to its left (70).
import SwiftUI
import AppKit

// MARK: - A custom key and a recorder

struct ProbeKey: EnvironmentKey { static let defaultValue: Int = 0 }
extension EnvironmentValues {
    var probe: Int {
        get { self[ProbeKey.self] }
        set { self[ProbeKey.self] = newValue }
    }
}

enum Log {
    nonisolated(unsafe) static var values: [String: String] = [:]
    nonisolated(unsafe) static var appearCount: [String: Int] = [:]
}

struct Reader: View {
    let label: String
    @Environment(\.probe) var probe
    @Environment(\.isEnabled) var isEnabled
    var body: some View {
        Log.values[label] = "probe=\(probe) isEnabled=\(isEnabled)"
        return Color.clear.frame(width: 10, height: 10)
    }
}

struct Defaults: View {
    @Environment(\.layoutDirection) var layoutDirection
    @Environment(\.locale) var locale
    @Environment(\.dynamicTypeSize) var dynamicTypeSize
    @Environment(\.displayScale) var displayScale
    @Environment(\.pixelLength) var pixelLength
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.controlActiveState) var controlActiveState
    @Environment(\.controlSize) var controlSize
    @Environment(\.isEnabled) var isEnabled
    var body: some View {
        Log.values["defaults"] = """
            layoutDirection=\(layoutDirection) locale=\(locale.identifier) \
            (Locale.current=\(Locale.current.identifier)) dynamicTypeSize=\(dynamicTypeSize) \
            displayScale=\(displayScale) pixelLength=\(pixelLength) colorScheme=\(colorScheme) \
            controlActiveState=\(controlActiveState) controlSize=\(controlSize) isEnabled=\(isEnabled)
            """
        return Color.clear.frame(width: 10, height: 10)
    }
}

@MainActor func host<V: View>(_ view: V, size: CGSize = CGSize(width: 200, height: 200),
                              inWindow: Bool = false) -> NSHostingView<V> {
    let h = NSHostingView(rootView: view)
    h.frame = CGRect(origin: .zero, size: size)
    if inWindow {
        let w = NSWindow(contentRect: CGRect(origin: .zero, size: size),
                         styleMask: [.titled], backing: .buffered, defer: false)
        w.contentView = h
    }
    h.layoutSubtreeIfNeeded()
    return h
}

func printLog(_ keys: [String]) {
    for k in keys { print("  \(k): \(Log.values[k] ?? "<body never ran>")") }
}

// MARK: - A: precedence and order

@MainActor func armA() {
    print("--- A: nearest-ancestor precedence and modifier order")
    Log.values = [:]
    let v = VStack {
        Reader(label: "A0 no writer (control)")
        Reader(label: "A1 .environment(1)").environment(\.probe, 1)
        Reader(label: "A2 .environment(2).environment(1): inner written first")
            .environment(\.probe, 2).environment(\.probe, 1)
        VStack {
            Reader(label: "A3 inside outer(1)")
            Reader(label: "A4 inside outer(1), own inner(2)").environment(\.probe, 2)
            Reader(label: "A5 sibling after A4, inside outer(1)")
        }.environment(\.probe, 1)
        Reader(label: "A6 after the outer scope closes")
        Reader(label: "A7 transformEnvironment +10 inside +100")
            .transformEnvironment(\.probe) { $0 += 10 }
            .transformEnvironment(\.probe) { $0 += 100 }
        Reader(label: "A8 .environment(5) inside transformEnvironment +100")
            .environment(\.probe, 5)
            .transformEnvironment(\.probe) { $0 += 100 }
    }
    _ = host(v, size: CGSize(width: 200, height: 400))
    printLog(Log.values.keys.sorted())
}

// MARK: - B: isEnabled and .disabled

@MainActor func armB() {
    print("--- B: isEnabled under .disabled and .environment(\\.isEnabled)")
    Log.values = [:]
    let v = VStack {
        Reader(label: "B0 no modifier (control)")
        Reader(label: "B1 .disabled(true)").disabled(true)
        Reader(label: "B2 .disabled(false)").disabled(false)
        Reader(label: "B3 .disabled(false) inside .disabled(true)")
            .disabled(false).disabled(true)
        Reader(label: "B4 .disabled(true) inside .disabled(false)")
            .disabled(true).disabled(false)
        Reader(label: "B5 .environment(isEnabled,true) inside .disabled(true)")
            .environment(\.isEnabled, true).disabled(true)
        Reader(label: "B6 .disabled(false) inside .environment(isEnabled,false)")
            .disabled(false).environment(\.isEnabled, false)
        Reader(label: "B7 .disabled(true) inside .environment(isEnabled,true)")
            .disabled(true).environment(\.isEnabled, true)
        VStack {
            Reader(label: "B8 grandchild of a disabled VStack")
        }.disabled(true)
    }
    _ = host(v, size: CGSize(width: 200, height: 400))
    printLog(Log.values.keys.sorted())
}

// MARK: - C: defaults inside a window

@MainActor func armC() {
    print("--- C: default values (hosted in an NSWindow)")
    Log.values = [:]
    let hv = host(Defaults(), inWindow: true)
    printLog(["defaults"])
    print("  window backingScaleFactor=\(hv.window?.backingScaleFactor ?? -1) " +
          "NSApp.userInterfaceLayoutDirection=\(NSApplication.shared.userInterfaceLayoutDirection.rawValue) (0 = LTR)")
    Log.values = [:]
    _ = host(Defaults().environment(\.locale, Locale(identifier: "de_DE"))
                       .environment(\.layoutDirection, .rightToLeft)
                       .dynamicTypeSize(.accessibility3), inWindow: true)
    print("  C2 with locale de_DE, RTL, .dynamicTypeSize(.accessibility3) (control that the readers can move):")
    printLog(["defaults"])
}

// MARK: - D: @State survives an environment value change; .id() is the control

@MainActor final class Model: ObservableObject {
    @Published var probe = 1
    @Published var identity = 0
}

struct Counter: View {
    let label: String
    @State var n = 0
    @Environment(\.probe) var probe
    var body: some View {
        Log.values[label] = "n=\(n) probe=\(probe)"
        return Color.clear.frame(width: 10, height: 10)
            .onAppear {
                Log.appearCount[label, default: 0] += 1
                n += 5
            }
            // +1 per value change, so a retained box reads 6 after one change
            // and a reset one reads 5 again (onAppear's +5 on a fresh box).
            .onChange(of: probe) { _, _ in n += 1 }
    }
}

struct DRoot: View {
    @ObservedObject var model: Model
    var body: some View {
        VStack {
            Counter(label: "D1 value changes, no id").environment(\.probe, model.probe)
            Counter(label: "D2 control: .id changes").environment(\.probe, model.probe)
                .id(model.identity)
        }
    }
}

@MainActor func spin() { RunLoop.main.run(until: Date().addingTimeInterval(0.2)) }

@MainActor func armD() {
    print("--- D: @State across an environment value change (control: .id change)")
    Log.values = [:]; Log.appearCount = [:]
    let model = Model()
    let h = host(DRoot(model: model), inWindow: true)
    spin(); h.layoutSubtreeIfNeeded()
    print("  frame 1:"); printLog(["D1 value changes, no id", "D2 control: .id changes"])
    model.probe = 2
    spin(); h.layoutSubtreeIfNeeded()
    print("  after probe = 2:"); printLog(["D1 value changes, no id", "D2 control: .id changes"])
    model.identity = 1
    model.probe = 3
    spin(); h.layoutSubtreeIfNeeded()
    print("  after identity = 1 and probe = 3 together:"); printLog(["D1 value changes, no id", "D2 control: .id changes"])
    print("  onAppear counts: \(Log.appearCount.sorted { $0.key < $1.key })")
}

// MARK: - E: an environment writer is layout-transparent

struct CountLayout: Layout {
    let label: String
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        Log.values[label] = "subviews.count=\(subviews.count)"
        return CGSize(width: 100, height: 100)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for s in subviews { s.place(at: bounds.origin, proposal: .unspecified) }
    }
}

@MainActor func armE() {
    print("--- E: subview count through an environment writer")
    Log.values = [:]
    _ = host(CountLayout(label: "E0 Group{A;B} (baseline)") {
        Group { Color.red; Color.blue }
    })
    _ = host(CountLayout(label: "E1 Group{A;B}.environment") {
        Group { Color.red; Color.blue }.environment(\.probe, 1)
    })
    _ = host(CountLayout(label: "E2 Group{A;B}.disabled(true)") {
        Group { Color.red; Color.blue }.disabled(true)
    })
    _ = host(CountLayout(label: "E3 control: VStack{A;B}.environment") {
        VStack { Color.red; Color.blue }.environment(\.probe, 1)
    })
    printLog(Log.values.keys.sorted())
}

// MARK: - F: overlay content and modifier order

@MainActor func armF() {
    print("--- F: an overlay's content inherits the scope it is declared in")
    Log.values = [:]
    let v = VStack {
        Color.clear.frame(width: 10, height: 10)
            .overlay { Reader(label: "F1 overlay, then .environment(3) outside it") }
            .environment(\.probe, 3)
        Color.clear.frame(width: 10, height: 10)
            .environment(\.probe, 3)
            .overlay { Reader(label: "F2 .environment(3) on the base, overlay added after") }
    }
    _ = host(v)
    printLog(Log.values.keys.sorted())
}

// MARK: - G: dynamic type on macOS

struct SizeReport: View {
    let label: String
    var body: some View {
        Text("Hello, dynamic type").font(.body)
            .background(GeometryReader { g in
                Color.clear.onAppear { Log.values[label] = "size=\(g.size)" }
                    .onChange(of: g.size) { _, s in Log.values[label] = "size=\(s)" }
            })
    }
}

@MainActor func armG() {
    print("--- G: does .dynamicTypeSize change a .body Text's size on macOS? (control: .font(size: 26))")
    Log.values = [:]
    for (label, view) in [
        ("G0 default", AnyView(SizeReport(label: "G0 default"))),
        ("G1 .dynamicTypeSize(.xSmall)", AnyView(SizeReport(label: "G1 .dynamicTypeSize(.xSmall)").dynamicTypeSize(.xSmall))),
        ("G2 .dynamicTypeSize(.accessibility5)", AnyView(SizeReport(label: "G2 .dynamicTypeSize(.accessibility5)").dynamicTypeSize(.accessibility5))),
    ] {
        let h = NSHostingView(rootView: view)
        Log.values[label + " fittingSize"] = "\(h.fittingSize)"
    }
    let control = NSHostingView(rootView: Text("Hello, dynamic type").font(.system(size: 26)))
    Log.values["G3 control .font(.system(size: 26)) fittingSize"] = "\(control.fittingSize)"
    printLog(Log.values.keys.filter { $0.contains("fittingSize") }.sorted())
}

// MARK: - H: RTL placement in an HStack

struct Where: View {
    let label: String
    let width: CGFloat
    var body: some View {
        Color.clear.frame(width: width, height: 10)
            .background(GeometryReader { g in
                Color.clear.onAppear { Log.values[label] = "minX=\(g.frame(in: .named("root")).minX)" }
            })
    }
}

@MainActor func armH() {
    print("--- H: HStack placement under .environment(\\.layoutDirection, .rightToLeft) (control: LTR)")
    Log.values = [:]
    let ltr = HStack(spacing: 0) { Where(label: "H0 LTR first(10)", width: 10); Where(label: "H0 LTR second(20)", width: 20) }
        .frame(width: 100, alignment: .leading).coordinateSpace(name: "root")
    let rtl = HStack(spacing: 0) { Where(label: "H1 RTL first(10)", width: 10); Where(label: "H1 RTL second(20)", width: 20) }
        .frame(width: 100, alignment: .leading)
        .environment(\.layoutDirection, .rightToLeft).coordinateSpace(name: "root")
    let h0 = host(ltr, size: CGSize(width: 100, height: 20), inWindow: true)
    let h1 = host(rtl, size: CGSize(width: 100, height: 20), inWindow: true)
    spin(); h0.layoutSubtreeIfNeeded(); h1.layoutSubtreeIfNeeded()
    printLog(Log.values.keys.sorted())
}

MainActor.assumeIsolated {
    _ = NSApplication.shared
    armA(); armB(); armC(); armD(); armE(); armF(); armG(); armH()
}
