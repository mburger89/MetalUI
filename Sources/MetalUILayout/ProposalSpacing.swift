/// SwiftUI's platform-default stack spacing and `Spacer` minimum on macOS.
///
/// `Spacer()`'s nil minimum is this constant, not the gap its neighbours would
/// get (probe `docs/probes/swiftui-stack-algorithms.swift` SP1, SP6, K1;
/// ruling CN-C in `docs/superpowers/2026-09-16-containers-decisions.md`).
/// It is also the default stack spacing between two views (S; ruling CN-H):
/// a linear stack registered with `spacing: nil` puts it between each adjacent
/// pair that has no zero-spacing edge (a spacer's, through its wrappers).
public enum ProposalSpacing {
    /// 8 points.
    public static let platformDefault: Double = 8
}
