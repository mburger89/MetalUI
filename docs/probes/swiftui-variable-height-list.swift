// SwiftUI probe: variable-height `List` rows (item 7 of the gpui-gap list,
// the variable-height-list design). Row heights from content, measured at the
// list's width; the row-height floor; laziness and the document height a
// lazy list reports for rows it has not realised; `scrollTo` onto an
// unrealised row of differing heights; and whether a row above the viewport
// that changes height (or a row inserted above it) moves the rows on screen.
//
// Evidence for rulings VL-A… in
// docs/superpowers/2026-10-08-variable-height-list-decisions.md.
//
// HOW TO RUN (ruling SA-O's two forms):
//
//   /usr/bin/swift docs/probes/swiftui-variable-height-list.swift
//   xcrun swiftc docs/probes/swiftui-variable-height-list.swift -o /tmp/vl-probe && /tmp/vl-probe
//
// THE INSTRUMENT. A macOS `List` is an `NSTableView` inside an
// `NSScrollView`. Row geometry is read from AppKit directly:
// `NSTableView.rect(ofRow:)` (document space) and the clip view's
// `bounds.origin.y` (the scroll offset). A row's ON-SCREEN position is
// `rect(ofRow:).minY - clip.bounds.origin.y`. Realisation is read from
// `.onAppear` per row. Every list is hosted in a borderless window ordered in
// (window-less, a `List` realises nothing — `swiftui-data-and-scrolling.swift`).
//
// POSITIVE CONTROLS / SEPARATING ARMS. V0 (uniform content) is the control
// V1 separates from. V2c (`.lineLimit(1)`) is the arm that separates "measured
// at the list's width" (V2) from "a fixed answer". V3b
// (`defaultMinListRowHeight` 4) separates V3's floor from the content. A6s (a
// non-lazy `VStack` in a `ScrollView`, the same height change) was meant as
// the control that the instrument sees a row on screen MOVE when nothing
// anchors it — but it reads only the clip (see CORRECTIONS below); A3 is the
// arm that reads a row moving on screen.
//
// RECORDED 2026-10-07 by the variable-height-list design session, macOS 27.0 (26A434),
// Apple Swift 6.4 (swiftlang-6.4.0.33.1), screen UNLOCKED (lock probe: no
// CGSSessionScreenIsLocked line, `displayAsleep main: 0`). Script form under
// /usr/bin/swift and compiled form under `xcrun swiftc` printed byte-identical
// stdout (23 lines), exit status 0 in both; stderr carries only AppKit's
// "reentrant operation in its NSTableView delegate" warnings:
//
//   --- V: row heights from content
//   V0 content 30,30,30,30 (control): row heights 38,38,38,38
//   V1 content 20,60,40,100: row heights 28,68,48,108
//   V2 wrapping Text, list width 200: row height 72
//   V2 wrapping Text, list width 400: row height 40
//   V2c the same Text .lineLimit(1) (separating), list width 200: row height 24
//   V2c the same Text .lineLimit(1) (separating), list width 400: row height 24
//   V3 content 4 tall: row heights 24,24
//   V3b content 4 tall, defaultMinListRowHeight 4 (separating): row heights 12,12
//   --- R: laziness and the unrealised extent (1000 rows, heights 20..100 repeating, viewport 300)
//   R1 rows appeared at rest: 13 of 1000; max id 12
//   R2 document height at rest: 25721 ; sum of content heights 60000 ; row heights 0..<5 28,48,68,88,108 ; rows 995..<1000 24,24,24,24,24
//   --- T: scrollTo onto an unrealised row of a variable-height List (1000 rows, viewport 300)
//   T-top scrollTo(500, anchor: .top): clip y 12946 ; row 500 minY 12946.2 height 28 ; on screen at 0.199336 ; rows appeared 19
//   T-bottom scrollTo(500, anchor: .bottom): clip y 13178 ; row 500 minY 13450.2 height 28 ; on screen at 272.199 ; rows appeared 18
//   --- A: anchoring — a change above the viewport (200 rows, viewport 300)
//   A1 List: row 50 grows 20 -> 220 (above the viewport, never realised): clip y 2922 -> 2922 ; row id 100 on screen 0 -> 0 ; document 5844 -> 5844 ; heights 50:24 -> 50:24
//   A2 List: row 98 grows +200 (realised overscan above row 100): clip y 2922 -> 2922 ; row id 100 on screen 0 -> 0 ; document 5844 -> 5844 ; heights 98:24 -> 98:24
//   A3 List: a 150-tall row inserted at index 0: clip y 2922 -> 3006 ; row id 100 on screen 0 -> 24 ; document 5844 -> 5952 ; heights 0:28 1:48 -> 0:24 1:28
//   A4 List: row 50 realised first (scrollTo 45), then grows 20 -> 220: clip y 3434 -> 3434 ; row id 100 on screen 0 -> 0 ; document 6356 -> 6356 ; heights 50:28 -> 50:28
//   A6s ScrollView { VStack }: row 50 grows 20 -> 220 (separating, non-lazy): clip y 6000 -> 6000 ; row id 100 on screen n/a -> n/a ; document n/a -> n/a ; heights n/a -> n/a
//   --- S: spelling
//   S1 List(_:rowContent:), List(_:selection: Binding<ID?>, rowContent:), List(_:selection: Binding<Set<ID>>, rowContent:) compile: 3
//
// WHAT IT SHOWS (controls first):
//   V0/V1 a row's height is its content's plus 8 (4pt insets top and bottom):
//         30 -> 38; 20,60,40,100 -> 28,68,48,108. Rows differ by content.
//   V2/V2c a row is measured at the LIST's width: a wrapping Text is 72 at 200
//         wide and 40 at 400; the same Text at .lineLimit(1) is 24 at both.
//   V3/V3b a row is floored at `defaultMinListRowHeight` (24 by default): a
//         4-tall content gives 24; with the floor set to 4 it gives 12 (4 + 8).
//   R1    the List is lazy: 13 of 1000 rows realised at rest.
//   R2    an UNREALISED row is estimated at 24 — the floor, not a running
//         mean: rows 995..<1000 read 24 each and the document is 25721 where
//         the content sums to 60000. SwiftUI's estimate is a constant.
//   T     scrollTo onto an unrealised row lands EXACTLY once it is measured:
//         .top puts row 500 at 0.2 on screen; .bottom puts its bottom at 300
//         (272.2 + 28). The offset (12946) is the realised-plus-24 prefix,
//         not the content's true prefix.
//   A1/A2/A4 a row's content changing height while it is OFF SCREEN changes
//         nothing — not its table height (24, or the 28 it was measured at in
//         A4), not the offset, not the rows on screen. SwiftUI trusts a cached
//         or estimated height until the row is realised again.
//   A3    a row INSERTED above the viewport is not anchored: the row on top
//         moves 24 on screen (the clip moved 84 while the content above grew
//         108).
//   A6s   (separating) a non-lazy ScrollView does not anchor either: the clip
//         stays at 6000 while 200 points grow above it, so what is on screen
//         moves. The instrument sees a non-anchoring scroller.
//   CORRECTIONS (critic, 2026-10-08, ruling VL-N; the output above re-taken
//   in both forms that day, byte-identical to it, 23 lines, exit 0, screen
//   unlocked). Two labels claim more than their readings show:
//   - A2's label says row 98 is "realised overscan". Its own reading (98:24)
//     refutes that: row 98's content is 80 tall (the 20..100 pattern), so a
//     measured row 98 would read 88. Row 98 was NOT realised; A2 is a second
//     instance of A1. NO arm measures a REALISED row above the viewport
//     changing height, so SwiftUI's answer there is unprobed.
//   - A6s prints `n/a` for the row on screen: it shows the clip unchanged
//     while content above grew, from which movement is inferred, not read.
//     The arm whose instrument READS a row moving on screen is A3 (0 -> 24);
//     A3 is the separating control for A1/A4's "nothing moved".
//   S1    the spelling: `List(_:rowContent:)` and both
//         `List(_:selection:rowContent:)` overloads (`Binding<ID?>`,
//         `Binding<Set<ID>>`) compile over `Identifiable` data.

import AppKit
import SwiftUI

@MainActor var windows: [NSWindow] = []
@MainActor var appeared: Set<Int> = []
@MainActor var proxies: [ScrollViewProxy] = []

@MainActor func spin(_ n: Int = 10) {
    for _ in 0..<n { RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.02)) }
}

@MainActor func host<V: View>(_ size: CGSize, _ view: V) -> NSHostingView<V> {
    let h = NSHostingView(rootView: view)
    let w = NSWindow(contentRect: CGRect(x: 100, y: 100, width: size.width, height: size.height),
                     styleMask: [.borderless], backing: .buffered, defer: false)
    w.contentView = h
    w.orderFrontRegardless()
    windows.append(w)
    h.layoutSubtreeIfNeeded()
    spin()
    h.layoutSubtreeIfNeeded()
    spin()
    return h
}

func find<T: NSView>(_ type: T.Type, in v: NSView) -> T? {
    if let t = v as? T { return t }
    for c in v.subviews { if let f = find(type, in: c) { return f } }
    return nil
}

@MainActor func table(_ h: NSView) -> NSTableView? { find(NSTableView.self, in: h) }
@MainActor func clipY(_ h: NSView) -> CGFloat {
    find(NSScrollView.self, in: h)?.contentView.bounds.origin.y ?? -1
}
@MainActor func heights(_ h: NSView, _ rows: Range<Int>) -> String {
    guard let t = table(h) else { return "no table" }
    return rows.map { $0 < t.numberOfRows ? String(format: "%g", Double(t.rect(ofRow: $0).height)) : "-" }
        .joined(separator: ",")
}
@MainActor func screenY(_ h: NSView, row: Int) -> String {
    guard let t = table(h), row < t.numberOfRows else { return "-" }
    return String(format: "%g", Double(t.rect(ofRow: row).minY - clipY(h)))
}

struct Row: Identifiable, Hashable { let id: Int; var height: CGFloat }

/// Heights 20, 40, 60, 80, 100 repeating — a pattern whose prefix sums are
/// exact, so an estimate-based answer is visible as a mismatch.
func patterned(_ n: Int) -> [Row] { (0..<n).map { Row(id: $0, height: CGFloat(20 + ($0 % 5) * 20)) } }

final class Model: ObservableObject {
    @Published var rows: [Row]
    init(_ rows: [Row]) { self.rows = rows }
}

struct ModelList: View {
    @ObservedObject var model: Model
    var body: some View {
        ScrollViewReader { proxy in
            List(model.rows) { row in
                Color.red.frame(height: row.height).id(row.id)
                    .onAppear { MainActor.assumeIsolated { _ = appeared.insert(row.id) } }
            }
            .onAppear { MainActor.assumeIsolated { proxies = [proxy] } }
        }
    }
}

struct ModelStack: View {
    @ObservedObject var model: Model
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(model.rows) { row in Color.red.frame(height: row.height).id(row.id) }
                }
            }
            .onAppear { MainActor.assumeIsolated { proxies = [proxy] } }
        }
    }
}

let longText = "The quick brown fox jumps over the lazy dog and keeps running far past the end of the line"

@MainActor func armV() {
    print("--- V: row heights from content")
    let v0 = host(CGSize(width: 300, height: 300), List(0..<4, id: \.self) { _ in Color.red.frame(height: 30) })
    print("V0 content 30,30,30,30 (control): row heights", heights(v0, 0..<4))
    let v1 = host(CGSize(width: 300, height: 300), List(Array(zip(0..., [20.0, 60, 40, 100])), id: \.0) { pair in
        Color.red.frame(height: pair.1)
    })
    print("V1 content 20,60,40,100: row heights", heights(v1, 0..<4))
    for width in [200.0, 400.0] {
        let v2 = host(CGSize(width: width, height: 300), List(0..<1, id: \.self) { _ in Text(longText) })
        print("V2 wrapping Text, list width \(Int(width)): row height", heights(v2, 0..<1))
    }
    for width in [200.0, 400.0] {
        let v2c = host(CGSize(width: width, height: 300),
                       List(0..<1, id: \.self) { _ in Text(longText).lineLimit(1) })
        print("V2c the same Text .lineLimit(1) (separating), list width \(Int(width)): row height",
              heights(v2c, 0..<1))
    }
    let v3 = host(CGSize(width: 300, height: 300), List(0..<2, id: \.self) { _ in Color.red.frame(height: 4) })
    print("V3 content 4 tall: row heights", heights(v3, 0..<2))
    let v3b = host(CGSize(width: 300, height: 300), List(0..<2, id: \.self) { _ in Color.red.frame(height: 4) }
        .environment(\.defaultMinListRowHeight, 4))
    print("V3b content 4 tall, defaultMinListRowHeight 4 (separating): row heights", heights(v3b, 0..<2))
}

@MainActor func armR() {
    print("--- R: laziness and the unrealised extent (1000 rows, heights 20..100 repeating, viewport 300)")
    appeared = []
    let model = Model(patterned(1000))
    let h = host(CGSize(width: 300, height: 300), ModelList(model: model))
    let exact = model.rows.reduce(0) { $0 + $1.height }
    let docH = table(h).map { Double($0.frame.height) } ?? -1
    print("R1 rows appeared at rest:", appeared.count, "of 1000; max id", appeared.max() ?? -1)
    print("R2 document height at rest:", String(format: "%g", docH),
          "; sum of content heights", String(format: "%g", Double(exact)),
          "; row heights 0..<5", heights(h, 0..<5), "; rows 995..<1000", heights(h, 995..<1000))
}

@MainActor func armT() {
    print("--- T: scrollTo onto an unrealised row of a variable-height List (1000 rows, viewport 300)")
    for (label, anchor) in [("top", UnitPoint.top), ("bottom", UnitPoint.bottom)] {
        appeared = []
        proxies = []
        let model = Model(patterned(1000))
        let h = host(CGSize(width: 300, height: 300), ModelList(model: model))
        proxies.first?.scrollTo(500, anchor: anchor)
        spin(); h.layoutSubtreeIfNeeded(); spin()
        let t = table(h)
        let rect = t.map { $0.rect(ofRow: 500) } ?? .zero
        print("T-\(label) scrollTo(500, anchor: .\(label)): clip y", String(format: "%g", Double(clipY(h))),
              "; row 500 minY", String(format: "%g", Double(rect.minY)),
              "height", String(format: "%g", Double(rect.height)),
              "; on screen at", screenY(h, row: 500),
              "; rows appeared", appeared.count)
    }
}

@MainActor func armA() {
    print("--- A: anchoring — a change above the viewport (200 rows, viewport 300)")
    func run(_ label: String, stack: Bool, visitFirst: Int? = nil, watch: [Int], _ change: (Model) -> Void) {
        proxies = []
        let model = Model(patterned(200))
        let h: NSView = stack ? host(CGSize(width: 300, height: 300), ModelStack(model: model))
                              : host(CGSize(width: 300, height: 300), ModelList(model: model))
        if let visitFirst {
            proxies.first?.scrollTo(visitFirst, anchor: .top)
            spin(); h.layoutSubtreeIfNeeded(); spin()
        }
        proxies.first?.scrollTo(100, anchor: .top)
        spin(); h.layoutSubtreeIfNeeded(); spin()
        func doc() -> String {
            stack ? "n/a" : String(format: "%g", Double(table(h)?.frame.height ?? -1))
        }
        func watched() -> String {
            stack ? "n/a" : watch.map { "\($0):" + heights(h, $0..<($0 + 1)) }.joined(separator: " ")
        }
        let beforeClip = clipY(h), before = stack ? "n/a" : screenY(h, row: 100)
        let beforeDoc = doc(), beforeWatched = watched()
        change(model)
        spin(); h.layoutSubtreeIfNeeded(); spin()
        let afterClip = clipY(h)
        let after = stack ? "n/a" : screenY(h, row: model.rows.firstIndex { $0.id == 100 } ?? 100)
        print(label, "clip y", String(format: "%g", Double(beforeClip)), "->", String(format: "%g", Double(afterClip)),
              "; row id 100 on screen", before, "->", after,
              "; document", beforeDoc, "->", doc(),
              "; heights", beforeWatched, "->", watched())
    }
    run("A1 List: row 50 grows 20 -> 220 (above the viewport, never realised):", stack: false, watch: [50]) {
        $0.rows[50].height = 220
    }
    run("A2 List: row 98 grows +200 (realised overscan above row 100):", stack: false, watch: [98]) {
        $0.rows[98].height += 200
    }
    run("A3 List: a 150-tall row inserted at index 0:", stack: false, watch: [0, 1]) {
        $0.rows.insert(Row(id: -1, height: 150), at: 0)
    }
    run("A4 List: row 50 realised first (scrollTo 45), then grows 20 -> 220:", stack: false, visitFirst: 45,
        watch: [50]) {
        $0.rows[50].height = 220
    }
    run("A6s ScrollView { VStack }: row 50 grows 20 -> 220 (separating, non-lazy):", stack: true, watch: []) {
        $0.rows[50].height = 220
    }
}

@MainActor func armS() {
    // The spelling: these compile only if SwiftUI labels the row closure
    // `rowContent:` and offers both selection overloads beside it.
    let single: Binding<Int?> = .constant(nil)
    let multi: Binding<Set<Int>> = .constant([])
    let views: [AnyView] = [
        AnyView(List(patterned(2), rowContent: { row in Text("\(row.id)") })),
        AnyView(List(patterned(2), selection: single, rowContent: { row in Text("\(row.id)") })),
        AnyView(List(patterned(2), selection: multi, rowContent: { row in Text("\(row.id)") })),
    ]
    print("--- S: spelling")
    print("S1 List(_:rowContent:), List(_:selection: Binding<ID?>, rowContent:), List(_:selection: Binding<Set<ID>>, rowContent:) compile:",
          views.count)
}

MainActor.assumeIsolated {
    _ = NSApplication.shared
    NSApp.setActivationPolicy(.accessory)
    armV()
    armR()
    armT()
    armA()
    armS()
}
