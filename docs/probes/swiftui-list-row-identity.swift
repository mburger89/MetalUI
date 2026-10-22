// SwiftUI probe: does a `List` row keep its identity by the id's Hashable VALUE
// (not its description)? (LH-A, retires divergence 255.) The List twin of
// swiftui-foreach-hashable-identity.swift, same Twin ids (description always
// "twin", Hashable on u). Selection and scrollTo are by value in the type
// system (`Binding<Set<ID>>`, `ScrollViewProxy.scrollTo(_:)` take the Hashable),
// so the arms below are identity/state; selection and scrollTo are asked at the
// source level by the pins, with the description-equal rows kept apart.
//
// ARMS:
//   L1 List(enumerated, id: \.element) Twin(1), Twin(2): two rows, two distinct @State tokens.
//   L2 L1 then reordered [Twin(2), Twin(1)]: each token follows its id (separating arm).
//   L3 Twin(1), Twin(1) (control, equal values): rows evaluated.
//
// HOW TO RUN:  xcrun swiftc docs/probes/swiftui-list-row-identity.swift -o /tmp/lr-probe && /tmp/lr-probe
//
// RECORDED 2026-10-22 by the LH designer session, macOS 27.0, Apple Swift 6.4
// (compiled form; tokens are random per run, the shape is the result; two runs
// agree in shape). The first draft labelled rows "u<n>" only: after the reorder
// the row bodies were not re-run, so nothing printed (a non-separating arm);
// the label carries the position, as the ForEach probe's does.
//
//   L1 Twin(1), Twin(2) (descriptions equal, values differ): u1@0=A452 u2@1=B8DF
//   L2 before reorder: u1@0=6FD4 u2@1=E8E2 | after [2,1]: u1@1=6FD4 u2@0=E8E2
//   L3 Twin(1), Twin(1) (control, equal values): u1@0=803E
//
// WHAT IT SHOWS: a SwiftUI List row is identified by its id's Hashable value:
// L1 two rows with two different @State tokens though both ids print "twin";
// L2 (separating arm, the body is re-run because the position changed) each
// token follows its id's value through a reorder; L3 the control, equal values
// are one row. This is the ForEach answer (FI-A); MetalUI's List follows it.
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
        List(Array(ids.enumerated()), id: \.element) { Child(label: "u\($0.element.u)@\($0.offset)") }
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
    print("L1 Twin(1), Twin(2) (descriptions equal, values differ):", summary()); _ = w1
    seen = []
    let box = Box(ids: [Twin(u: 1), Twin(u: 2)])
    let w2 = host(Root(box: box))
    let before = summary()
    seen = []
    box.ids = [Twin(u: 2), Twin(u: 1)]; spin()
    print("L2 before reorder:", before, "| after [2,1]:", summary()); _ = w2
    seen = []
    let w3 = host(Model(ids: [Twin(u: 1), Twin(u: 1)]))
    print("L3 Twin(1), Twin(1) (control, equal values):", summary()); _ = w3
}
