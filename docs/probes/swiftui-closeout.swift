// SwiftUI probe for plan task 15, the closeout (rulings CX-F, CX-I item 2).
//
// GROUP O — an optional `@State` with a non-nil initial value (divergence 85,
// ruling CX-F). Each arm is a view rendered once into an `NSHostingView`
// (layout + `cacheDisplay`, so `body` really runs), logging what `body` reads.
//   O0  positive control: `@State var n: Int = 2`, first body reads 2.
//   O1n control: `@State var x: Int? = nil`, first body reads nil.
//   O1  the claim: `@State var x: Int? = 2`, first body reads 2 (MetalUI read
//       nil before CX-F: `StateTable.peek` cast an absent entry to `Int?` as
//       `.some(nil)`).
//   O2  separating arm: O1's view after a write of `nil` (a closure installed
//       in `onAppear`, called after the first render, then re-rendered) reads
//       nil — a fix that treated a stored nil as absent would read 2.
//
// GROUP SW — `switch` transitions (CX-I item 2): TO BE ADDED BY LANE 1 (arms
// SW0, SW1, SW1n per spec §3), copying task 13's offset recorder from
// docs/probes/swiftui-transactions-animation.swift, with its own run output
// below.
//
// HOW TO RUN (the form that was run):
//   xcrun swiftc docs/probes/swiftui-closeout.swift -o /tmp/closeout && /tmp/closeout
//
// RECORDED 2026-09-30 (critic round of the closeout design), macOS 27.0.1
// (26A434), screen unlocked. Two runs, byte-identical:
//
//     O0 Int=2 first body: 2
//     O1n Int?=nil body: nil
//     O1 Int?=2 body: 2
//     O2 setter installed: true
//     O1 Int?=2 body: nil
//
import SwiftUI
import AppKit

@MainActor final class Log { static var lines: [String] = [] ; static var setter: (() -> Void)? }

struct O0: View { @State var n: Int = 2
    var body: some View { let _ = Log.lines.append("O0 Int=2 first body: \(n)"); return Color.clear.frame(width: 10, height: 10) } }
struct O1: View { @State var x: Int? = 2
    var body: some View { let _ = Log.lines.append("O1 Int?=2 body: \(x.map(String.init) ?? "nil")"); return Color.clear.frame(width: 10, height: 10).onAppear { Log.setter = { x = nil } } } }
struct O1n: View { @State var x: Int? = nil
    var body: some View { let _ = Log.lines.append("O1n Int?=nil body: \(x.map(String.init) ?? "nil")"); return Color.clear.frame(width: 10, height: 10) } }

@MainActor func render<V: View>(_ v: V) -> NSHostingView<V> {
    let h = NSHostingView(rootView: v); h.frame = NSRect(x: 0, y: 0, width: 10, height: 10); h.layoutSubtreeIfNeeded()
    let rep = h.bitmapImageRepForCachingDisplay(in: h.bounds)!; h.cacheDisplay(in: h.bounds, to: rep); return h }

MainActor.assumeIsolated {
    _ = NSApplication.shared
    _ = render(O0()); _ = render(O1n())
    let h = render(O1())
    RunLoop.main.run(until: Date().addingTimeInterval(0.2))
    Log.lines.append("O2 setter installed: \(Log.setter != nil)")
    Log.setter?()
    RunLoop.main.run(until: Date().addingTimeInterval(0.2)); h.layoutSubtreeIfNeeded()
    let rep = h.bitmapImageRepForCachingDisplay(in: h.bounds)!; h.cacheDisplay(in: h.bounds, to: rep)
    var seen = Set<String>(); for l in Log.lines where seen.insert(l).inserted { print(l) }
}
