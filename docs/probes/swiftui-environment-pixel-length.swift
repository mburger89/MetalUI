// SwiftUI probe: where `pixelLength` comes from, what a whole-value
// `\.self` write does to it, and what a bare `EnvironmentValues()` holds (as
// opposed to a hosted window's defaults, which `swiftui-environment-scoping.swift`
// arm C read). Evidence for rulings EV-J (platform metrics), EV-U (the
// re-stamp is a DIVERGENCE for `pixelLength`) and EV-Y (`EnvironmentValues()`
// defaults) in docs/superpowers/2026-09-15-environment-decisions.md.
//
// Added in the environment track's THIRD design pass, from a critic's scratch
// probes `px-probe.swift` and `ev-default.swift`.
//
// HOW TO RUN. Either form; both were run on the final file and their filtered
// output is byte-identical to the recorded block below (and so is
// `/usr/bin/swiftc <file>` followed by the same filtered run):
//
//   /usr/bin/swift docs/probes/swiftui-environment-pixel-length.swift
//   swiftc docs/probes/swiftui-environment-pixel-length.swift -o /tmp/pxprobe
//   OS_ACTIVITY_DT_MODE=1 /tmp/pxprobe 2>&1 | grep -v 'Connection\]\|ntents\|WindowTab'
//
// CONTROLS. X0 (no write) must read the device (pixelLength 0.5 at 2x) for any
// later arm to mean anything; X1 must MOVE pixelLength, or `displayScale` is
// not its source; V1 (a bare value with `displayScale = 4`) must read 0.25, or
// the bare 1.0 is not derived either; V2 compares the bare locale against
// `Locale(identifier: "")` and against `Locale.current`, which must differ from
// each other on this machine for the comparison to discriminate.
//
// RECORDED 2026-09-15 (third design pass), macOS 26.6.2 (25G83), MacBook with a
// 2x display, system appearance dark, locale en_US. Run three ways, filtered
// output byte-identical: `/usr/bin/swift <file>` and `/usr/bin/swiftc` (Apple
// Swift 6.4, swiftlang-6.4.0.33.1), and `swiftc` from a swift.org 6.3.3
// toolchain (swiftly). Exit status 0 each time:
//
//   --- V: a bare EnvironmentValues(), no host
//     V0 EnvironmentValues(): pixelLength=1.0 displayScale=1.0 locale='' isEnabled=true dynamicTypeSize=large layoutDirection=leftToRight
//     V1 control, displayScale = 4 on a bare value: pixelLength=0.25
//     V2 bare locale == Locale(identifier: ""): true; == Locale.current: false; Locale.current='en_US'
//   --- X: hosted in an NSWindow, backingScaleFactor=2.0
//     X0 control, no write: pixelLength=0.5 displayScale=2.0 locale='en_US' isEnabled=true dynamicTypeSize=large layoutDirection=leftToRight
//     X1 .environment(\.displayScale, 3): pixelLength=0.3333333333333333 displayScale=3.0 locale='en_US' isEnabled=true dynamicTypeSize=large layoutDirection=leftToRight
//     X2 .environment(\.self, EnvironmentValues()): pixelLength=1.0 displayScale=1.0 locale='' isEnabled=true dynamicTypeSize=large layoutDirection=leftToRight
//     X3 .environment(\.self, EnvironmentValues()) then an outer .environment(\.locale, de_DE): pixelLength=1.0 displayScale=1.0 locale='' isEnabled=true dynamicTypeSize=large layoutDirection=leftToRight
//
// READING (what the rulings rely on):
// - X0 vs X1: `pixelLength` is DERIVED from `displayScale` and `displayScale`
//   is writable, so SwiftUI lets a scope change `pixelLength` (X1: 1/3 at a
//   written scale of 3 on a 2x display). It is not tied to the device.
// - X2: a whole-value `\.self` write resets `pixelLength` and `displayScale` to
//   1 on a 2x display, and the locale to ''. MetalUI's EV-U re-stamp keeps the
//   device's `pixelLength` instead: a DIVERGENCE (EV-U, as amended).
// - V0/V2: a bare `EnvironmentValues()` holds `pixelLength` 1, `displayScale` 1
//   and locale `Locale(identifier: "")` (V2 true), NOT `Locale.current` (V2
//   false, and `Locale.current` is en_US, so the comparison discriminates).
//   The hosted defaults (X0; scoping probe arm C) are a window's, stamped by
//   the host, not `EnvironmentValues()`'s. V1: the bare 1.0 is derived too.
// - X3: the inner `\.self` write replaces the outer locale write: nearest
//   writer wins, as scoping arm A2.
import SwiftUI
import AppKit

enum Seen {
    nonisolated(unsafe) static var lines: [String: String] = [:]
}

struct R: View {
    let label: String
    @Environment(\.pixelLength) var px
    @Environment(\.displayScale) var scale
    @Environment(\.locale) var locale
    @Environment(\.isEnabled) var isEnabled
    @Environment(\.dynamicTypeSize) var dts
    @Environment(\.layoutDirection) var dir
    var body: some View {
        Color.clear.onAppear {
            Seen.lines[label] = "pixelLength=\(px) displayScale=\(scale) locale='\(locale.identifier)' "
                + "isEnabled=\(isEnabled) dynamicTypeSize=\(dts) layoutDirection=\(dir)"
        }
    }
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)

    print("--- V: a bare EnvironmentValues(), no host")
    let e = EnvironmentValues()
    print("  V0 EnvironmentValues(): pixelLength=\(e.pixelLength) displayScale=\(e.displayScale) "
        + "locale='\(e.locale.identifier)' isEnabled=\(e.isEnabled) dynamicTypeSize=\(e.dynamicTypeSize) "
        + "layoutDirection=\(e.layoutDirection)")
    var four = EnvironmentValues()
    four.displayScale = 4
    print("  V1 control, displayScale = 4 on a bare value: pixelLength=\(four.pixelLength)")
    print("  V2 bare locale == Locale(identifier: \"\"): \(e.locale == Locale(identifier: "")); "
        + "== Locale.current: \(e.locale == Locale.current); Locale.current='\(Locale.current.identifier)'")

    let root = VStack {
        R(label: "X0 control, no write")
        R(label: "X1 .environment(\\.displayScale, 3)").environment(\.displayScale, 3)
        R(label: "X2 .environment(\\.self, EnvironmentValues())").environment(\.self, EnvironmentValues())
        R(label: "X3 .environment(\\.self, EnvironmentValues()) then an outer .environment(\\.locale, de_DE)")
            .environment(\.self, EnvironmentValues()).environment(\.locale, Locale(identifier: "de_DE"))
    }
    let w = NSWindow(contentRect: CGRect(x: 200, y: 200, width: 200, height: 200),
                     styleMask: [.titled], backing: .buffered, defer: false)
    w.isReleasedWhenClosed = false
    w.contentView = NSHostingView(rootView: root)
    w.makeKeyAndOrderFront(nil)
    RunLoop.main.run(until: Date().addingTimeInterval(0.5))
    print("--- X: hosted in an NSWindow, backingScaleFactor=\(w.backingScaleFactor)")
    for k in Seen.lines.keys.sorted() { print("  \(k): \(Seen.lines[k]!)") }
    w.orderOut(nil)
}
