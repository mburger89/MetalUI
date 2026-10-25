// SwiftUI probe: does SwiftUI tell a view whether a scroll came from a trackpad
// or a wheel (XP-G28, rulings TP-A, TP-K)? Typecheck-only: `ScrollPhase`,
// `ScrollPhaseChangeContext` and `ScrollGeometry` are the whole public
// surface a view can read about a scroll. A positive control compiles what
// exists; each separating arm compiles ONLY under -D ARM_<n> and must FAIL.
//
// HOW TO RUN:
//   xcrun swiftc -typecheck docs/probes/swiftui-scroll-precision.swift                 # control: exit 0
//   xcrun swiftc -typecheck -D ARM_1 docs/probes/swiftui-scroll-precision.swift         # must fail: no isPrecise on the context
//   xcrun swiftc -typecheck -D ARM_2 docs/probes/swiftui-scroll-precision.swift         # must fail: no per-view wheel hook
//
// RECORDED OUTPUT (macOS 27 SDK, 2026-10-24): control exit 0; ARM_1 `value of type
// 'ScrollPhaseChangeContext' has no member 'isPrecise'`; ARM_2 `value of type 'Text' has
// no member 'onScrollWheel'`. Conclusion: SwiftUI exposes phases of a ScrollView, never
// the device class, and has no per-view wheel hook: no SwiftUI claim backs isPrecise.
import SwiftUI

@available(macOS 15.0, *)
struct Control: View {
    @State private var log = ""
    var body: some View {
        ScrollView {
            Text("x")
        }
        .onScrollPhaseChange { old, new, context in
            // The phases SwiftUI names (idle, tracking, interacting, decelerating, animating)
            switch new {
            case .idle, .tracking, .interacting, .decelerating, .animating: break
            @unknown default: break
            }
            _ = context.geometry.contentOffset
        }
    }
}

#if ARM_1
@available(macOS 15.0, *)
func arm1(_ context: ScrollPhaseChangeContext) { _ = context.isPrecise }
#endif

#if ARM_2
struct Arm2: View {
    var body: some View {
        Text("x").onScrollWheel { _ in }
    }
}
#endif
