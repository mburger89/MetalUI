// SwiftUI probe: is a `ForEach` element's identity its id's Hashable value,
// or the id's description? (C20, ruling FI-A.) S6 of
// swiftui-scrollviewreader-scope.swift showed two elements are EVALUATED for
// AnyHashable(1)/AnyHashable("1"); this asks the stronger question the
// retirement of divergence 79 rests on: do they keep SEPARATE @State, and does
// each state follow its id through a reorder?
//
// ids are `Twin(u:)`: Hashable on `u`, but `description` is always "twin",
// so every pair prints alike and differs in value.
//
// ARMS (positive control + separating arms):
//   H1 Twin(1), Twin(2): two elements, two distinct @State tokens.
//   H2 H1 then reordered [Twin(2), Twin(1)]: each token follows its id.
//   H3 Twin(1), Twin(1) (equal values, F7's shape): ONE element evaluated.
//
// HOW TO RUN:  xcrun swiftc docs/probes/swiftui-foreach-hashable-identity.swift -o /tmp/fe-probe && /tmp/fe-probe
//
// RECORDED 2026-10-10 by the C20 designer session, macOS 27.0, Apple Swift 6.4
// (compiled form; tokens are random per run, the shape is the result; screen
// state not probed, the instrument needs no drawing):
//
//   H1 Twin(1), Twin(2) (descriptions equal, values differ): u1@0=03F2 u2@1=5881
//   H2 before reorder: u1@0=5BD0 u2@1=9E8A | after [2,1]: u1@1=5BD0 u2@0=9E8A
//   H3 Twin(1), Twin(1) (control, equal values): u1@0=5C88
//
// WHAT IT SHOWS: H1 two elements, two different @State tokens, though both ids
// print "twin". H2 (the separating arm: the body is re-run because the
// position changed) each token follows its id's VALUE through a reorder:
// u1 keeps 5BD0 and u2 keeps 9E8A. H3 the control: equal values are one
// element. SwiftUI's identity is Hashable equality, never the description.
import SwiftUI
import AppKit

struct Twin: Hashable, CustomStringConvertible {
    let u: Int
    var description: String { "twin" }
}

@MainActor var seen: [String] = []

struct Child: View {
    let label: String
    @State private var token = UUID().uuidString.prefix(4).description
    var body: some View {
        let _ = MainActor.assumeIsolated { seen.append("\(label)=\(token)") }
        return Color.red.frame(width: 10, height: 10)
    }
}

struct Model: View {
    let ids: [Twin]
    var body: some View {
        VStack { ForEach(Array(ids.enumerated()), id: \.element) { Child(label: "u\($0.element.u)@\($0.offset)") } }
    }
}

final class Box: ObservableObject { @Published var ids: [Twin]; init(ids: [Twin]) { self.ids = ids } }
struct Root: View {
    @ObservedObject var box: Box
    var body: some View { Model(ids: box.ids) }
}
extension Box { convenience init(_ ids: [Twin]) { self.init(ids: ids) } }

@MainActor func spin() { for _ in 0..<8 { RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.02)) } }

setvbuf(stdout, nil, _IOLBF, 0)
MainActor.assumeIsolated {
    NSApplication.shared.setActivationPolicy(.accessory)
    @MainActor func summary() -> String { Set(seen).sorted().joined(separator: " ") }
    @MainActor func host<V: View>(_ v: V) -> NSWindow {
        let h = NSHostingView(rootView: v)
        let w = NSWindow(contentRect: CGRect(x: 100, y: 100, width: 100, height: 100),
                         styleMask: [.borderless], backing: .buffered, defer: false)
        w.contentView = h; w.orderFrontRegardless(); h.layoutSubtreeIfNeeded(); spin(); return w
    }
    seen = []
    let w1 = host(Model(ids: [Twin(u: 1), Twin(u: 2)]))
    print("H1 Twin(1), Twin(2) (descriptions equal, values differ):", summary()); _ = w1
    seen = []
    let box = Box(ids: [Twin(u: 1), Twin(u: 2)])
    let w2 = host(Root(box: box))
    let before = summary()
    seen = []
    box.ids = [Twin(u: 2), Twin(u: 1)]; spin()
    print("H2 before reorder:", before, "| after [2,1]:", summary()); _ = w2
    seen = []
    let w3 = host(Model(ids: [Twin(u: 1), Twin(u: 1)]))
    print("H3 Twin(1), Twin(1) (control, equal values):", summary()); _ = w3
}
