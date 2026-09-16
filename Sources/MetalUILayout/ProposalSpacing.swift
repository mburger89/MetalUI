/// SwiftUI's platform-default stack spacing and `Spacer` minimum on macOS.
///
/// `Spacer()`'s nil minimum is this constant, not the gap its neighbours would
/// get (probe `docs/probes/swiftui-stack-algorithms.swift` SP1, SP6, K1;
/// ruling CN-C in `docs/superpowers/2026-09-16-containers-decisions.md`).
/// Default stack spacing (S; ruling CN-H) is the same value, but no stack
/// reads this constant yet: `HStack`/`VStack` still hard-code `Pixels(8)`
/// until containers lane 3 wires them to it.
public enum ProposalSpacing {
    /// 8 points.
    public static let platformDefault: Double = 8
}
