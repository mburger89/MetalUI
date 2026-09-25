// SwiftUI probe: data and scrolling (plan task 10, part 1). `ForEach` identity
// over identified data (Identifiable, `id:` key path, ranges) including a loop
// that shrinks at its tail; `Binding` semantics (`$state`, `.constant`, derived
// key-path bindings, `init(get:set:)`, the optional initialisers, live reads);
// a `List` and a `LazyVStack` inside a `ScrollView` beside a header; wheel
// scrolling under `.disabled`; `ScrollViewReader.scrollTo(_:anchor:)`,
// `scrollPosition(id:)`; and scroll indicator visibility.
//
// Evidence for rulings DD-A… in
// docs/superpowers/2026-09-25-data-and-scrolling-decisions.md.
//
// HOW TO RUN (ruling SA-O's two forms):
//
//   /usr/bin/swift docs/probes/swiftui-data-and-scrolling.swift
//   xcrun swiftc docs/probes/swiftui-data-and-scrolling.swift -o /tmp/dd-probe && /tmp/dd-probe
//
// THE STATE INSTRUMENT (as in `swiftui-composition-identity.swift`). `P` owns
// a `@StateObject Token`; `StateObject`'s autoclosure runs once per view
// identity, so a new serial means new state for that identity and the same
// serial across an update means the state was kept. Each arm hosts generation
// 0, then swaps `rootView` to generation 1 (and 2) and lays out again, and
// prints, per name, the serials seen in each generation (`g0 / g1 / g2`).
//
// THE BINDING INSTRUMENT (arms B*). A parent owns `@State`; a child or
// grandchild writes through a `Binding` from `.onAppear` (or a stashed closure
// called directly afterwards); the parent's body logs what it reads. Arms B4/B5
// build bindings over a plain box with `init(get:set:)` outside any view.
//
// THE SCROLL INSTRUMENT (arms L*, T*, P*). Offsets are read with
// `.onScrollGeometryChange(for:)` (`contentOffset`), which also moves under a
// programmatic `NSClipView` scroll (arm L2's scroll, measured: the geometry
// read 100 after `contentView.scroll(to: (0, 100))`). Row realisation is read
// from `.onAppear`/`.onDisappear` per row. `scrollTo` is called on the proxy a
// `ScrollViewReader` stashes, outside any SwiftUI dispatch, then the run loop
// is spun. Rows are 30 tall in a 100-tall viewport unless the arm says so.
//
// POSITIVE CONTROLS. F0 (same data, input changes) must read "kept"; F11 (the
// id changes at a fixed position) must read "NEW". B2 (`.constant`) is the
// control that the binding instrument can see a write NOT land. L3 (a
// non-lazy `VStack`) is the control that `.onAppear` sees laziness in L2. T0
// (no call) reads 0, T8 (an unknown id) is the no-op control. I0 (no
// overflow) is the indicator control. W's direct wheel arm has NO working
// positive control on this machine (see "W" below) and is recorded as such.
//
// RECORDED 2026-09-25 by the plan task 10 part 1 design session, macOS 27.0
// (26A428), Apple Swift 6.4 (swiftlang-6.4.0.33.1), screen LOCKED (the lock
// probe read `CGSSessionScreenIsLocked = 1`, `displayAsleep main: 1`). Script
// form under /usr/bin/swift and compiled form under `xcrun swiftc` printed
// byte-identical stdout (58 lines), exit status 0, stderr empty in both:
//
//   --- F: ForEach identity
//   F0 Identifiable, same data, input changes: a 1 / 1, b 2 / 2
//   F1 Identifiable reorder [a,b] -> [b,a]: a 3 / 3, b 4 / 4
//   F2 Identifiable tail shrink [a,b], [a], [a,b]: a 5 / 5 / 5, b 6 / none / 7
//   F3 range 0..<2, 0..<1, 0..<2: 0 8 / 8 / 8, 1 9 / none / 10
//   F4 id: \.self, insert at front [b] -> [a,b]: a none / 12, b 11 / 11
//   F5 indices as ids, insert at front [b] -> [a,b] (P named by position): pos0 13 / 13, pos1 none / 14
//   F6 remove middle [a,b,c] -> [a,c]: a 15 / 15, b 16 / none, c 17 / 17
//   F7 two elements with the SAME id [x,x]: x0 18 / 18, x1 none / none
//   F8 two views per item, tail shrink [a,b], [a], [a,b]: a1 19 / 19 / 19, a2 20 / 20 / 20, b1 21 / none / 23, b2 22 / none / 24
//   F9 ForEach shrink in an HStack, trailing sibling: a 25 / 25, b 26 / none, t 27 / 27
//   F10 item a moves from the first ForEach to the second: a 28 / 30, k 29 / 29
//   F11 the id changes at a fixed position [a] -> [b] (P named 'p'): p 31 / 32
//   F12 List rows, Identifiable tail shrink [a,b], [a], [a,b]: a 33 / 33 / 33, b 34 / none / 34
//   --- B: Binding
//   B1 $n through a child and a grandchild (@Binding's projection), grandchild sets 5: n=0, n=5
//   B2 .constant(3), set 5 then read: after set=3
//   B3 $model.name (derived by key path), child sets "b": a/1, b/1
//   B4 init(get:set:): read 1, set 4, read 4; gets 3 sets 1, store 4
//   B5 init?(Binding<Value?>): nil -> nil, 3 -> non-nil, write 9 through it -> base 9; init(Binding<V>) as Value?: write nil -> base 2, write 6 -> base 6
//   B6 a $n stashed at appear, read later: at appear 0, after the state is set to 7 elsewhere 7, after writing 11 through it 11
//   --- L: List / LazyVStack beside a header in a ScrollView (viewport 400x112, rows 28)
//   L0 List alone (control: a List scrolls itself): rows appeared 0...4 (5)
//   L1 ScrollView { header 300; List }: List height 0, rows appeared none
//   L2 ScrollView { header 300; LazyVStack { ForEach } }: at 0 rows appeared none; scrolled to 300 rows visible 0...3 (4)
//   L3 ScrollView { header 300; VStack { ForEach } } (control): at 0 rows appeared 0...39 (40); scrolled to 300 rows visible 0...39 (40)
//   --- W: wheel under .disabled
//   W0 enabled ScrollView (positive control): offset after 5 wheel events: 0; hit chain: PlatformGroupContainer < DocumentView < HostingClipView < HostingScrollView < PlatformContainer
//   W1 ScrollView.disabled(true): offset after 5 wheel events: 0; hit chain: PlatformGroupContainer < DocumentView < HostingClipView < HostingScrollView < PlatformContainer
//   W2 disabled content inside an enabled ScrollView: offset after 5 wheel events: 0; hit chain: PlatformGroupContainer < DocumentView < HostingClipView < HostingScrollView < PlatformContainer
//   --- T: scrollTo(_:anchor:) (rows 30, viewport 100, 20 rows unless noted)
//   T0 no call (control): start 0
//   T1 scrollTo(10, anchor: .top): start 0 -> 300
//   T2 scrollTo(10, anchor: .center): start 0 -> 265
//   T3 scrollTo(10, anchor: .bottom): start 0 -> 230
//   T4 scrollTo(10) (nil anchor), target below: start 0 -> 230
//   T5 scrollTo(1) (nil anchor), target already visible: start 0 -> 0
//   T6 .top to 10, then scrollTo(2) (nil anchor), target above: start 0 -> 300 -> 60
//   T7 scrollTo(19, anchor: .top) (past the end): start 0 -> 500
//   T8 scrollTo(99, anchor: .top) (unknown id, control): start 0 -> 0
//   T9 scrollTo(10, anchor: UnitPoint(x: 0, y: 0.25)): start 0 -> 282.5
//   T10 LazyVStack of 200, scrollTo(150, anchor: .top) (unrealised): start 0 -> 4500
//   T11 horizontal, scrollTo(10, anchor: .leading): start 0 -> 300
//   T12 ForEach with two views per item (30 + 10), scrollTo(10, anchor: .top): start 0 -> 400
//   T12b the same, scrollTo(10, anchor: .bottom) (first view 330, whole item 340): start 0 -> 330
//   T13 an .id("x") on a plain view at y 250, scrollTo("x", anchor: .top): start 0 -> 250
//   T14 nested scrollers, scrollTo(inner row 10, anchor: .top): outer 0 inner 300
//   T15 List of 200, scrollTo(150, anchor: .top): offset 0 -> 3610
//   --- P: scrollPosition(id:)
//   P1 position set to 10 at appear: offset 230; reports: position=10
//   P2 scrolled to 95 by the platform: offset 95; reports: none
//   --- I: scroll indicator visibility (NSScrollView state, 20 rows of 30 in 100)
//   I0 no overflow, .automatic (control): hasVerticalScroller true autohides true style overlay scrollerHidden true alpha 1.00
//   I1 .automatic: hasVerticalScroller true autohides true style overlay scrollerHidden false alpha 1.00
//   I2 .visible: hasVerticalScroller true autohides true style overlay scrollerHidden false alpha 1.00
//   I3 .hidden: hasVerticalScroller false autohides true style overlay scrollerHidden n/a alpha n/a
//   I4 .never: hasVerticalScroller false autohides true style overlay scrollerHidden n/a alpha n/a
//   I5 ScrollView(showsIndicators: false) (the older spelling): hasVerticalScroller false autohides true style overlay scrollerHidden n/a alpha n/a
//
// K2 (a typecheck, not an arm — it cannot live in this file, which must
// compile): SwiftUI has no `for` loop in a view builder. Recorded the same
// day with `xcrun swiftc -typecheck` over
// `struct V: View { var body: some View { VStack { for i in 0..<3 { Text("\(i)") } } } }`:
//   error: closure containing control flow statement cannot be used with
//   result builder 'ViewBuilder'
// so MetalUI's `for` (ruling ID-B) has no SwiftUI spelling; `ForEach` over a
// range (F3) is its nearest one.
//
// WHAT IT SHOWS, arm by arm (controls first):
//   F0/F11 the instrument sees retention (F0) and re-creation (F11).
//   F1/F6 state follows the id through a reorder and a middle removal.
//   F2/F3/F8 an element a ForEach stops producing gets NEW state when it comes
//         back — Identifiable data, a range, and an item of two views alike
//         (V10 of `swiftui-composition-identity.swift`, re-run with ids).
//   F4/F5 `id: \.self` keeps b's state when a is inserted before it; ids that
//         are INDICES keep the state with the position (pos0 keeps 13).
//   F7    two elements with the same id: only the first element's content is
//         ever evaluated (x1 none in both generations).
//   F9    a ForEach is one slot: the trailing sibling keeps its state.
//   F10   an id is scoped to its ForEach: a moved to another ForEach is NEW.
//   F12   a `List` row removed from the data and re-added KEEPS its state
//         (b 34 / none / 34) — unlike a ForEach element (F2).
//   B1    `$n` passed down two levels (`@Binding`'s own projection) writes the
//         parent's state. B2 (control): `.constant` ignores the write.
//   B3    `$model.name` writes one field and leaves the other.
//   B4    `init(get:set:)`: the setter runs once per write (and the getter
//         also runs during the write: gets 3 for two reads and one write).
//   B5    `init?(Binding<Value?>)` is nil over nil and writes through over a
//         value; `init(Binding<V>)` as `V?` IGNORES a nil write (base stays 2).
//   B6    a `$n` binding kept after its body ran reads the CURRENT state (7)
//         and writes it (11): live, not a snapshot.
//   L0    a `List` alone scrolls itself and realises the visible rows.
//   L1    a `List` inside a `ScrollView` beside a header is 0 tall and
//         realises nothing: blank in SwiftUI too (K6: greedy, 0 at nil).
//   L2/L3 the ordinary SwiftUI shape, `ScrollView { header; LazyVStack {
//         ForEach } }`, realises nothing at offset 0 (every row is below a
//         300-tall header in a 112-tall viewport) and exactly rows 0...3 once
//         scrolled to 300 — the rows on screen. L3 (a plain `VStack`, 40 of
//         40 at once) is the control that `.onAppear` sees laziness.
//   W0-W2 NOT MEASURED. The wheel events move nothing even in the enabled
//         control W0 (the screen is locked, and five delivery strategies —
//         window `sendEvent`, a continuous-phase variant, a direct
//         `scrollWheel(with:)` on the `HostingScrollView`, the hit view, and
//         `NSApp.sendEvent` — all read 0 while a programmatic `NSClipView`
//         scroll moved the same instrument to 100). The only reading is
//         indirect: `.disabled(true)` leaves the AppKit hit chain reaching
//         `HostingScrollView` unchanged (W1 = W0).
//   T0/T8 no call and an unknown id leave the offset at 0.
//   T1-T3/T9 an anchor lands the target at `minY - anchor.y × (viewport -
//         height)`: .top 300, .center 265, .bottom 230, y 0.25 282.5.
//   T4-T6 a nil anchor scrolls the least distance: a target below lands at
//         the bottom (230), a visible one does not move (0), one above lands
//         at the top (60).
//   T7    the offset is clamped to the content (500 = 600 - 100).
//   T10/T15 an unrealised row of a LazyVStack (4500) and of a List (3610; a
//         List's rows are not 30 tall) is reachable.
//   T11   horizontal: .leading lands x at 300.
//   T12/T12b an item of two views is targeted at its FIRST view: .bottom
//         reads 330 (the first view's 30), not 340 (the item's 40).
//   T13   any view carrying `.id` is a target, not only a ForEach element.
//   T14   nested scrollers: only the NEAREST scroller moves (outer 0).
//   P1/P2 `scrollPosition(id:)` set to 10 scrolls the least distance (230,
//         like a nil anchor); a platform scroll to 95 reports no position.
//   I0-I5 on overlay scrollers, `.visible` leaves the `NSScrollView` exactly
//         as `.automatic` does (a hidden overlay scroller at rest), and
//         `.hidden`, `.never` and `showsIndicators: false` each remove the
//         scroller (`hasVerticalScroller false`). Whether `.visible` differs
//         under the "always show scroll bars" system setting is NOT measured.

import AppKit
import SwiftUI

@MainActor var nextSerial = 0
@MainActor var serials: [String: [Int]] = [:]
@MainActor var reads: [String] = []
@MainActor var visible: Set<Int> = []
@MainActor var offsets: [String: CGFloat] = [:]
@MainActor var proxies: [ScrollViewProxy] = []
@MainActor var stashedBinding: Binding<Int>? = nil
@MainActor var stashedSetter: (() -> Void)? = nil

@MainActor final class Token: ObservableObject {
    let serial: Int
    init() { nextSerial += 1; serial = nextSerial }
}

struct P: View {
    let name: String
    let generation: Int
    init(_ name: String, _ generation: Int) { self.name = name; self.generation = generation }
    @StateObject private var token = Token()
    var body: some View {
        let _ = MainActor.assumeIsolated {
            if serials[name]?.contains(token.serial) != true {
                serials[name, default: []].append(token.serial)
            }
        }
        let _ = generation
        return Color.red.frame(width: 10, height: 10)
    }
}

struct Item: Identifiable, Hashable { let id: String }

func show(_ xs: [Int]?) -> String {
    guard let xs, !xs.isEmpty else { return "none" }
    return xs.map(String.init).joined(separator: "+")
}

@MainActor func spin(_ n: Int = 8) {
    for _ in 0..<n { RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.02)) }
}

/// Hosts each generation in turn and prints, per name, the serials seen in
/// each generation (`g0 / g1 / …`).
@MainActor func arm<V: View>(_ label: String, names: [String], generations: Int = 2,
                             _ make: @escaping (Int) -> V) {
    serials = [:]
    let host = NSHostingView(rootView: AnyView(make(0)))
    let w = NSWindow(contentRect: CGRect(x: 100, y: 100, width: 400, height: 400),
                     styleMask: [.borderless], backing: .buffered, defer: false)
    w.contentView = host
    w.orderFrontRegardless()
    windows.append(w)
    host.layoutSubtreeIfNeeded()
    var perGen: [[String: [Int]]] = [serials]
    for g in 1..<generations {
        serials = [:]
        host.rootView = AnyView(make(g))
        host.layoutSubtreeIfNeeded()
        perGen.append(serials)
    }
    let rendered = names.map { n in "\(n) " + perGen.map { show($0[n]) }.joined(separator: " / ") }
    print(label, rendered.joined(separator: ", "))
}

/// Hosts `make()` in a window-less hosting view of `size`, spins so
/// `.onAppear` runs, and returns the host.
@MainActor var windows: [NSWindow] = []

@MainActor func host<V: View>(_ size: CGSize, _ view: V) -> NSHostingView<V> {
    let h = NSHostingView(rootView: view)
    // In a borderless window, ordered in: without one, `List` realises no row
    // and `scrollTo`/`scrollPosition` move nothing (measured while writing
    // this probe — every T arm read 0 and L0 "none" window-less).
    let w = NSWindow(contentRect: CGRect(x: 100, y: 100, width: size.width, height: size.height),
                     styleMask: [.borderless], backing: .buffered, defer: false)
    w.contentView = h
    w.orderFrontRegardless()
    windows.append(w)
    h.layoutSubtreeIfNeeded()
    spin()
    h.layoutSubtreeIfNeeded()
    return h
}

func findScrollViews(_ v: NSView) -> [NSScrollView] {
    var found: [NSScrollView] = []
    if let s = v as? NSScrollView { found.append(s) }
    for c in v.subviews { found += findScrollViews(c) }
    return found
}

// MARK: - F: ForEach identity

func items(_ ids: [String]) -> [Item] { ids.map(Item.init(id:)) }

@MainActor func armF() {
    print("--- F: ForEach identity")
    arm("F0 Identifiable, same data, input changes:", names: ["a", "b"]) { g in
        VStack { ForEach(items(["a", "b"])) { P($0.id, g) } }
    }
    arm("F1 Identifiable reorder [a,b] -> [b,a]:", names: ["a", "b"]) { g in
        VStack { ForEach(items(g == 0 ? ["a", "b"] : ["b", "a"])) { P($0.id, g) } }
    }
    arm("F2 Identifiable tail shrink [a,b], [a], [a,b]:", names: ["a", "b"], generations: 3) { g in
        VStack { ForEach(items(g == 1 ? ["a"] : ["a", "b"])) { P($0.id, g) } }
    }
    arm("F3 range 0..<2, 0..<1, 0..<2:", names: ["0", "1"], generations: 3) { g in
        VStack { ForEach(0..<(g == 1 ? 1 : 2), id: \.self) { P("\($0)", g) } }
    }
    arm("F4 id: \\.self, insert at front [b] -> [a,b]:", names: ["a", "b"]) { g in
        VStack { ForEach(g == 0 ? ["b"] : ["a", "b"], id: \.self) { P($0, g) } }
    }
    arm("F5 indices as ids, insert at front [b] -> [a,b] (P named by position):",
        names: ["pos0", "pos1"]) { g in
        let data = g == 0 ? ["b"] : ["a", "b"]
        return VStack { ForEach(data.indices, id: \.self) { i in P("pos\(i)", g) } }
    }
    arm("F6 remove middle [a,b,c] -> [a,c]:", names: ["a", "b", "c"]) { g in
        VStack { ForEach(items(g == 0 ? ["a", "b", "c"] : ["a", "c"])) { P($0.id, g) } }
    }
    arm("F7 two elements with the SAME id [x,x]:", names: ["x0", "x1"]) { g in
        VStack { ForEach(Array(zip([0, 1], ["x", "x"])), id: \.1) { pair in P("x\(pair.0)", g) } }
    }
    arm("F8 two views per item, tail shrink [a,b], [a], [a,b]:", names: ["a1", "a2", "b1", "b2"],
        generations: 3) { g in
        VStack { ForEach(items(g == 1 ? ["a"] : ["a", "b"])) { P($0.id + "1", g); P($0.id + "2", g) } }
    }
    arm("F9 ForEach shrink in an HStack, trailing sibling:", names: ["a", "b", "t"]) { g in
        HStack { ForEach(items(g == 0 ? ["a", "b"] : ["a"])) { P($0.id, g) }; P("t", g) }
    }
    arm("F10 item a moves from the first ForEach to the second:", names: ["a", "k"]) { g in
        VStack {
            ForEach(items(g == 0 ? ["a"] : [])) { P($0.id, g) }
            ForEach(items(g == 0 ? ["k"] : ["k", "a"])) { P($0.id, g) }
        }
    }
    arm("F11 the id changes at a fixed position [a] -> [b] (P named 'p'):", names: ["p"]) { g in
        VStack { ForEach(items(g == 0 ? ["a"] : ["b"])) { _ in P("p", g) } }
    }
    arm("F12 List rows, Identifiable tail shrink [a,b], [a], [a,b]:", names: ["a", "b"],
        generations: 3) { g in
        List(items(g == 1 ? ["a"] : ["a", "b"])) { P($0.id, g) }.frame(width: 200, height: 200)
    }
}

// MARK: - B: Binding

struct GrandChild: View {
    @Binding var value: Int
    var body: some View { Color.clear.frame(width: 1, height: 1).onAppear { value = 5 } }
}
struct Child: View {
    @Binding var value: Int
    var body: some View { GrandChild(value: $value) }
}
struct ParentB1: View {
    @State private var n = 0
    var body: some View {
        let _ = MainActor.assumeIsolated { reads.append("n=\(n)") }
        Child(value: $n)
    }
}
struct ConstantChild: View {
    @Binding var value: Int
    var body: some View {
        Color.clear.frame(width: 1, height: 1).onAppear {
            value = 5
            MainActor.assumeIsolated { reads.append("after set=\(value)") }
        }
    }
}
struct Model { var name = "a"; var count = 1 }
struct NameChild: View {
    @Binding var name: String
    var body: some View { Color.clear.frame(width: 1, height: 1).onAppear { name = "b" } }
}
struct ParentB3: View {
    @State private var model = Model()
    var body: some View {
        let _ = MainActor.assumeIsolated { reads.append("\(model.name)/\(model.count)") }
        NameChild(name: $model.name)
    }
}
struct ParentB6: View {
    @State private var n = 0
    var body: some View {
        Color.clear.frame(width: 1, height: 1).onAppear {
            let binding = $n
            MainActor.assumeIsolated {
                stashedBinding = binding
                stashedSetter = { n = 7 }
            }
        }
    }
}

@MainActor func armB() {
    print("--- B: Binding")
    reads = []
    _ = host(CGSize(width: 50, height: 50), ParentB1())
    print("B1 $n through a child and a grandchild (@Binding's projection), grandchild sets 5:",
          reads.joined(separator: ", "))
    reads = []
    _ = host(CGSize(width: 50, height: 50), ConstantChild(value: .constant(3)))
    print("B2 .constant(3), set 5 then read:", reads.joined(separator: ", "))
    reads = []
    _ = host(CGSize(width: 50, height: 50), ParentB3())
    print("B3 $model.name (derived by key path), child sets \"b\":", reads.joined(separator: ", "))

    var store = 1
    var gets = 0, sets = 0
    let custom = Binding<Int>(get: { gets += 1; return store }, set: { sets += 1; store = $0 })
    let before = custom.wrappedValue
    custom.wrappedValue = 4
    let after = custom.wrappedValue
    print("B4 init(get:set:): read \(before), set 4, read \(after); gets \(gets) sets \(sets), store \(store)")

    // Each base is built AFTER its box holds the value it is read with: a
    // binding built over a box that then changes traps in `init?` (measured
    // while writing this arm: `optional = 3` after the base was built, then
    // `Binding<Int>(base)`, exit 133) — `Binding` stores a `_value` snapshot
    // beside its getter. Not an arm: the design builds no snapshot.
    var noneBox: Int? = nil
    let unwrappedNil = Binding<Int>(Binding<Int?>(get: { noneBox }, set: { noneBox = $0 }))
    var someBox: Int? = 3
    let unwrapped = Binding<Int>(Binding<Int?>(get: { someBox }, set: { someBox = $0 }))
    unwrapped?.wrappedValue = 9
    var plain = 2
    let lifted = Binding<Int?>(Binding<Int>(get: { plain }, set: { plain = $0 }))
    lifted.wrappedValue = nil
    let liftedAfterNil = plain
    lifted.wrappedValue = 6
    print("B5 init?(Binding<Value?>): nil -> \(unwrappedNil == nil ? "nil" : "non-nil"),",
          "3 -> \(unwrapped == nil ? "nil" : "non-nil"), write 9 through it -> base \(someBox.map(String.init) ?? "nil");",
          "init(Binding<V>) as Value?: write nil -> base \(liftedAfterNil), write 6 -> base \(plain)")

    stashedBinding = nil
    stashedSetter = nil
    let h = host(CGSize(width: 50, height: 50), ParentB6())
    let first = stashedBinding?.wrappedValue
    stashedSetter?()
    spin()
    h.layoutSubtreeIfNeeded()
    let live = stashedBinding?.wrappedValue
    stashedBinding?.wrappedValue = 11
    spin()
    let written = stashedBinding?.wrappedValue
    print("B6 a $n stashed at appear, read later: at appear \(first.map(String.init) ?? "nil"),",
          "after the state is set to 7 elsewhere \(live.map(String.init) ?? "nil"),",
          "after writing 11 through it \(written.map(String.init) ?? "nil")")
}

// MARK: - L: List and LazyVStack beside a header inside a ScrollView

struct Row: View {
    let i: Int
    var body: some View {
        Color.blue.frame(height: 28)
            .onAppear { MainActor.assumeIsolated { _ = visible.insert(i) } }
            .onDisappear { MainActor.assumeIsolated { _ = visible.remove(i) } }
    }
}

func range(_ s: Set<Int>) -> String {
    guard let lo = s.min(), let hi = s.max() else { return "none" }
    return "\(lo)...\(hi) (\(s.count))"
}

@MainActor func armL() {
    print("--- L: List / LazyVStack beside a header in a ScrollView (viewport 400x112, rows 28)")
    visible = []
    _ = host(CGSize(width: 400, height: 112), List(0..<40, id: \.self) { Row(i: $0) })
    print("L0 List alone (control: a List scrolls itself): rows appeared", range(visible))

    visible = []
    var listHeight: CGFloat = -1
    _ = host(CGSize(width: 400, height: 112), ScrollView {
        VStack(spacing: 0) {
            Color.gray.frame(height: 300)
            List(0..<40, id: \.self) { Row(i: $0) }
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { listHeight = $0 }
        }
    })
    print("L1 ScrollView { header 300; List }: List height \(Int(listHeight)), rows appeared", range(visible))

    for lazy in [true, false] {
        visible = []
        let content = VStack(spacing: 0) {
            Color.gray.frame(height: 300)
            if lazy {
                LazyVStack(spacing: 0) { ForEach(0..<40, id: \.self) { Row(i: $0) } }
            } else {
                VStack(spacing: 0) { ForEach(0..<40, id: \.self) { Row(i: $0) } }
            }
        }
        let h = host(CGSize(width: 400, height: 112), ScrollView { content })
        let before = range(visible)
        let sv = findScrollViews(h).first
        sv?.contentView.scroll(to: CGPoint(x: 0, y: 300))
        if let sv { sv.reflectScrolledClipView(sv.contentView) }
        spin()
        h.layoutSubtreeIfNeeded()
        spin()
        let label = lazy ? "L2 ScrollView { header 300; LazyVStack { ForEach } }"
                         : "L3 ScrollView { header 300; VStack { ForEach } } (control)"
        print(label + ": at 0 rows appeared \(before); scrolled to 300 rows visible \(range(visible))")
    }
}

// MARK: - W: wheel scrolling under .disabled

func chain(_ v: NSView?) -> String {
    var names: [String] = []
    var c = v
    while let x = c, !(x is NSHostingView<AnyView>) {
        let n = String(describing: type(of: x))
        if n.hasPrefix("NSHostingView") { break }
        names.append(n)
        c = x.superview
    }
    return names.joined(separator: " < ")
}

struct Tall: View {
    let name: String
    var body: some View {
        ScrollView {
            VStack(spacing: 0) { ForEach(0..<20, id: \.self) { _ in Color.red.frame(width: 100, height: 30) } }
        }
        .onScrollGeometryChange(for: CGFloat.self) { $0.contentOffset.y } action: { _, n in
            MainActor.assumeIsolated { offsets[name] = n }
        }
    }
}

@MainActor func wheel(_ label: String, _ view: some View, name: String) {
    offsets = [:]
    let w = NSWindow(contentRect: CGRect(x: 200, y: 200, width: 120, height: 100),
                     styleMask: [.borderless], backing: .buffered, defer: false)
    let h = NSHostingView(rootView: view)
    w.contentView = h
    w.orderFrontRegardless()
    h.layoutSubtreeIfNeeded()
    spin()
    let screenH = NSScreen.screens.first?.frame.height ?? 0
    for _ in 0..<5 {
        let cg = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1,
                         wheel1: -20, wheel2: 0, wheel3: 0)!
        cg.location = CGPoint(x: 260, y: screenH - 250)
        cg.setIntegerValueField(.scrollWheelEventPointDeltaAxis1, value: -20)
        cg.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1, value: -20)
        w.sendEvent(NSEvent(cgEvent: cg)!)
        spin(2)
    }
    let hit = chain(h.hitTest(CGPoint(x: 60, y: 50)))
    print(label, "offset after 5 wheel events: \(Int(offsets[name] ?? -1)); hit chain: \(hit)")
    w.orderOut(nil)
}

@MainActor func armW() {
    print("--- W: wheel under .disabled")
    wheel("W0 enabled ScrollView (positive control):", Tall(name: "e"), name: "e")
    wheel("W1 ScrollView.disabled(true):", Tall(name: "d").disabled(true), name: "d")
    wheel("W2 disabled content inside an enabled ScrollView:", ScrollView {
        VStack(spacing: 0) { ForEach(0..<20, id: \.self) { _ in Color.red.frame(width: 100, height: 30) } }
            .disabled(true)
    }.onScrollGeometryChange(for: CGFloat.self) { $0.contentOffset.y } action: { _, n in
        MainActor.assumeIsolated { offsets["c"] = n }
    }, name: "c")
}

// MARK: - T: ScrollViewReader.scrollTo(_:anchor:)

struct Reader<Content: View>: View {
    let name: String
    let axis: Axis.Set
    @ViewBuilder let content: () -> Content
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(axis) { content() }
                .onScrollGeometryChange(for: CGPoint.self) { $0.contentOffset } action: { _, p in
                    MainActor.assumeIsolated { offsets[name] = axis == .horizontal ? p.x : p.y }
                }
                .onAppear { MainActor.assumeIsolated { proxies = [proxy] } }
        }
    }
}

func rows(_ n: Int) -> some View {
    VStack(spacing: 0) { ForEach(0..<n, id: \.self) { i in Color.red.frame(width: 100, height: 30).id(i) } }
}

/// Hosts a 100x100 (unless given) scroller over `content`, runs each call in
/// turn, and prints the offset after each.
@MainActor func scrollArm<V: View>(_ label: String, size: CGSize = CGSize(width: 100, height: 100),
                                   _ view: V, _ calls: [(ScrollViewProxy) -> Void], key: String = "s") {
    offsets = [:]
    proxies = []
    let h = host(size, view)
    var readings: [String] = ["start \(Int(offsets[key] ?? 0))"]
    for call in calls {
        guard let proxy = proxies.first else { readings.append("no proxy"); break }
        call(proxy)
        spin()
        h.layoutSubtreeIfNeeded()
        spin()
        readings.append(String(format: "%g", Double(offsets[key] ?? 0)))
    }
    print(label, readings.joined(separator: " -> "))
}

@MainActor func armT() {
    print("--- T: scrollTo(_:anchor:) (rows 30, viewport 100, 20 rows unless noted)")
    let v = Reader(name: "s", axis: .vertical) { rows(20) }
    scrollArm("T0 no call (control):", v, [])
    scrollArm("T1 scrollTo(10, anchor: .top):", v, [{ $0.scrollTo(10, anchor: .top) }])
    scrollArm("T2 scrollTo(10, anchor: .center):", v, [{ $0.scrollTo(10, anchor: .center) }])
    scrollArm("T3 scrollTo(10, anchor: .bottom):", v, [{ $0.scrollTo(10, anchor: .bottom) }])
    scrollArm("T4 scrollTo(10) (nil anchor), target below:", v, [{ $0.scrollTo(10) }])
    scrollArm("T5 scrollTo(1) (nil anchor), target already visible:", v, [{ $0.scrollTo(1) }])
    scrollArm("T6 .top to 10, then scrollTo(2) (nil anchor), target above:", v,
              [{ $0.scrollTo(10, anchor: .top) }, { $0.scrollTo(2) }])
    scrollArm("T7 scrollTo(19, anchor: .top) (past the end):", v, [{ $0.scrollTo(19, anchor: .top) }])
    scrollArm("T8 scrollTo(99, anchor: .top) (unknown id, control):", v, [{ $0.scrollTo(99, anchor: .top) }])
    scrollArm("T9 scrollTo(10, anchor: UnitPoint(x: 0, y: 0.25)):", v,
              [{ $0.scrollTo(10, anchor: UnitPoint(x: 0, y: 0.25)) }])
    scrollArm("T10 LazyVStack of 200, scrollTo(150, anchor: .top) (unrealised):",
              Reader(name: "s", axis: .vertical) {
                  LazyVStack(spacing: 0) {
                      ForEach(0..<200, id: \.self) { i in Color.red.frame(width: 100, height: 30).id(i) }
                  }
              }, [{ $0.scrollTo(150, anchor: .top) }])
    scrollArm("T11 horizontal, scrollTo(10, anchor: .leading):",
              Reader(name: "s", axis: .horizontal) {
                  HStack(spacing: 0) {
                      ForEach(0..<20, id: \.self) { i in Color.red.frame(width: 30, height: 100).id(i) }
                  }
              }, [{ $0.scrollTo(10, anchor: .leading) }])
    scrollArm("T12 ForEach with two views per item (30 + 10), scrollTo(10, anchor: .top):",
              Reader(name: "s", axis: .vertical) {
                  VStack(spacing: 0) {
                      ForEach(0..<20, id: \.self) { _ in
                          Color.red.frame(width: 100, height: 30)
                          Color.blue.frame(width: 100, height: 10)
                      }
                  }
              }, [{ $0.scrollTo(10, anchor: .top) }])
    scrollArm("T12b the same, scrollTo(10, anchor: .bottom) (first view 330, whole item 340):",
              Reader(name: "s", axis: .vertical) {
                  VStack(spacing: 0) {
                      ForEach(0..<20, id: \.self) { _ in
                          Color.red.frame(width: 100, height: 30)
                          Color.blue.frame(width: 100, height: 10)
                      }
                  }
              }, [{ $0.scrollTo(10, anchor: .bottom) }])
    scrollArm("T13 an .id(\"x\") on a plain view at y 250, scrollTo(\"x\", anchor: .top):",
              Reader(name: "s", axis: .vertical) {
                  VStack(spacing: 0) {
                      Color.gray.frame(width: 100, height: 250)
                      Color.red.frame(width: 100, height: 30).id("x")
                      Color.gray.frame(width: 100, height: 400)
                  }
              }, [{ $0.scrollTo("x", anchor: .top) }])
    // Nested: an outer vertical scroller (100 tall) over a 200 header and an
    // inner scroller (100 tall) whose row 10 is the target. Both offsets.
    offsets = [:]
    proxies = []
    let nested = ScrollViewReader { proxy in
        ScrollView {
            VStack(spacing: 0) {
                Color.gray.frame(width: 100, height: 200)
                ScrollView { rows(20) }
                    .frame(height: 100)
                    .onScrollGeometryChange(for: CGFloat.self) { $0.contentOffset.y } action: { _, n in
                        MainActor.assumeIsolated { offsets["inner"] = n }
                    }
                Color.gray.frame(width: 100, height: 400)
            }
        }
        .onScrollGeometryChange(for: CGFloat.self) { $0.contentOffset.y } action: { _, n in
            MainActor.assumeIsolated { offsets["outer"] = n }
        }
        .onAppear { MainActor.assumeIsolated { proxies = [proxy] } }
    }
    let nh = host(CGSize(width: 100, height: 100), nested)
    proxies.first?.scrollTo(10, anchor: .top)
    spin(); nh.layoutSubtreeIfNeeded(); spin()
    print("T14 nested scrollers, scrollTo(inner row 10, anchor: .top): outer",
          Int(offsets["outer"] ?? 0), "inner", Int(offsets["inner"] ?? 0))
    // A List is its own scroller: scrollTo an unrealised row.
    offsets = [:]
    proxies = []
    let list = ScrollViewReader { proxy in
        List(0..<200, id: \.self) { i in Text("row \(i)").id(i) }
            .onScrollGeometryChange(for: CGFloat.self) { $0.contentOffset.y } action: { _, n in
                MainActor.assumeIsolated { offsets["list"] = n }
            }
            .onAppear { MainActor.assumeIsolated { proxies = [proxy] } }
    }
    let lh = host(CGSize(width: 200, height: 100), list)
    let listStart = offsets["list"] ?? 0
    proxies.first?.scrollTo(150, anchor: .top)
    spin(); lh.layoutSubtreeIfNeeded(); spin()
    print("T15 List of 200, scrollTo(150, anchor: .top): offset", Int(listStart), "->",
          Int(offsets["list"] ?? 0))
}

// MARK: - P: scrollPosition(id:)

struct Positioned: View {
    @State var position: Int? = nil
    let request: Int?
    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(0..<20, id: \.self) { i in Color.red.frame(width: 100, height: 30) }
            }
            .scrollTargetLayout()
        }
        .scrollPosition(id: $position)
        .onScrollGeometryChange(for: CGFloat.self) { $0.contentOffset.y } action: { _, n in
            MainActor.assumeIsolated { offsets["p"] = n }
        }
        .onAppear { if let request { position = request } }
        .onChange(of: position) { _, new in
            MainActor.assumeIsolated { reads.append("position=\(new.map(String.init) ?? "nil")") }
        }
    }
}

@MainActor func armP() {
    print("--- P: scrollPosition(id:)")
    offsets = [:]
    reads = []
    _ = host(CGSize(width: 100, height: 100), Positioned(request: 10))
    print("P1 position set to 10 at appear: offset \(Int(offsets["p"] ?? 0)); reports:",
          reads.isEmpty ? "none" : reads.joined(separator: ", "))
    offsets = [:]
    reads = []
    let h = host(CGSize(width: 100, height: 100), Positioned(request: nil))
    let sv = findScrollViews(h).first
    sv?.contentView.scroll(to: CGPoint(x: 0, y: 95))
    if let sv { sv.reflectScrolledClipView(sv.contentView) }
    spin(); h.layoutSubtreeIfNeeded(); spin()
    print("P2 scrolled to 95 by the platform: offset \(Int(offsets["p"] ?? 0)); reports:",
          reads.isEmpty ? "none" : reads.joined(separator: ", "))
}

// MARK: - I: scroll indicators

@MainActor func armI() {
    print("--- I: scroll indicator visibility (NSScrollView state, 20 rows of 30 in 100)")
    func describe(_ label: String, _ view: some View) {
        let h = host(CGSize(width: 100, height: 100), view)
        guard let sv = findScrollViews(h).first else { print(label, "no NSScrollView"); return }
        let scroller = sv.verticalScroller
        print(label, "hasVerticalScroller \(sv.hasVerticalScroller)",
              "autohides \(sv.autohidesScrollers)",
              "style \(sv.scrollerStyle == .overlay ? "overlay" : "legacy")",
              "scrollerHidden \(scroller?.isHidden.description ?? "n/a")",
              "alpha \(scroller.map { String(format: "%.2f", $0.alphaValue) } ?? "n/a")")
    }
    describe("I0 no overflow, .automatic (control):",
             ScrollView { Color.red.frame(width: 100, height: 50) })
    describe("I1 .automatic:", ScrollView { rows(20) }.scrollIndicators(.automatic))
    describe("I2 .visible:", ScrollView { rows(20) }.scrollIndicators(.visible))
    describe("I3 .hidden:", ScrollView { rows(20) }.scrollIndicators(.hidden))
    describe("I4 .never:", ScrollView { rows(20) }.scrollIndicators(.never))
    describe("I5 ScrollView(showsIndicators: false) (the older spelling):",
             ScrollView(.vertical, showsIndicators: false) { rows(20) })
}

// MARK: - K: API shapes that must compile (no output of their own)

/// The spellings the design rules against. Compiling this file is the
/// evidence: `TextField(_:text:)` and `TextEditor(text:)` take a
/// `Binding<String>`, `ForEach` takes a range, a key path and Identifiable
/// data, and `ScrollViewReader`/`scrollTo(_:anchor:)` exist.
struct Shapes: View {
    @State private var text = ""
    @State private var body2 = ""
    var body: some View {
        VStack {
            TextField("Name", text: $text)
            TextEditor(text: $body2)
            ForEach(0..<3) { Text("\($0)") }
            ForEach(["a"], id: \.self) { Text($0) }
            ForEach(items(["a"])) { Text($0.id) }
            ScrollViewReader { proxy in Button("top") { proxy.scrollTo(0, anchor: .top) } }
        }
    }
}

setvbuf(stdout, nil, _IOLBF, 0)
MainActor.assumeIsolated {
    NSApplication.shared.setActivationPolicy(.accessory)
    _ = Shapes()
    armF()
    armB()
    armL()
    armW()
    armT()
    armP()
    armI()
}
