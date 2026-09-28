import MetalUILayout

/// An `HStack`'s alignment of its children on the vertical (cross) axis:
/// SwiftUI's `VerticalAlignment` (ruling CN-I), its text baselines included
/// since plan task 11 (ruling TE-K).
///
/// Probe A1 (`docs/probes/swiftui-stack-algorithms.swift`): a 20×10 child
/// beside a 20×30 one sits at y 0, 10 and 20. There is no `leading` case, so
/// `HStack(alignment: .leading)` does not compile, as in SwiftUI
/// (`aHorizontalCaseIsNotAnHStackAlignmentNorAVerticalCaseAVStacks`).
///
/// **`.firstTextBaseline`/`.lastTextBaseline`** align each child's first (or
/// last) text baseline — its height when it has none — on one line (probe
/// `swiftui-text-semantics.swift` B2). An `HStack` honours them; a `GridRow`
/// traps on them (divergence 88: SwiftUI's grid-row answer, X11, overflows a
/// row in a way no measured rule reproduces). **Migration note** (`TE-S` item
/// 5): this is a public `enum` where SwiftUI's is a struct, so an exhaustive
/// `switch` over it outside the package needs the two new cases or a
/// `default:`.
public enum VerticalAlignment: Sendable, Hashable {
    case top, center, bottom, firstTextBaseline, lastTextBaseline

    /// The kernel's nine-case alignment with this vertical factor; a
    /// horizontal stack reads only that factor. A text baseline has no factor:
    /// it reads `.top`, which the kernel ignores whenever ``textBaseline`` is
    /// set.
    var proposalAlignment: ProposalAlignment {
        switch self {
        case .top, .firstTextBaseline, .lastTextBaseline: .top
        case .center: .center
        case .bottom: .bottom
        }
    }

    /// The kernel's text baseline for the two baseline cases, else `nil`.
    var textBaseline: ProposalTextBaseline? {
        switch self {
        case .firstTextBaseline: .first
        case .lastTextBaseline: .last
        case .top, .center, .bottom: nil
        }
    }

    /// The case with `alignment`'s vertical factor, for the deprecated
    /// spacing-first initializer, which accepted all nine and read only that.
    init(verticalFactorOf alignment: ProposalAlignment) {
        switch alignment.verticalFactor {
        case 0: self = .top
        case 1: self = .bottom
        default: self = .center
        }
    }
}

/// A `VStack`'s alignment of its children on the horizontal (cross) axis:
/// SwiftUI's `HorizontalAlignment` (ruling CN-I).
///
/// Probe A2: a 10×20 child above a 30×20 one sits at x 0, 10 and 20. There is
/// no `top` case, so `VStack(alignment: .top)` does not compile, as in SwiftUI.
public enum HorizontalAlignment: Sendable, Hashable {
    case leading, center, trailing

    /// The kernel's nine-case alignment with this horizontal factor; a
    /// vertical stack reads only that factor.
    var proposalAlignment: ProposalAlignment {
        switch self {
        case .leading: .leading
        case .center: .center
        case .trailing: .trailing
        }
    }

    /// The case with `alignment`'s horizontal factor, for the deprecated
    /// spacing-first initializer.
    init(horizontalFactorOf alignment: ProposalAlignment) {
        switch alignment.horizontalFactor {
        case 0: self = .leading
        case 1: self = .trailing
        default: self = .center
        }
    }
}
